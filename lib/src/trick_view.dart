import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'card_painter.dart';
import 'table_theme.dart';
import 'cards.dart';
import 'match_view.dart';
import 'studio_chrome.dart';
import 'table_seats.dart';
import 'trick_ai.dart';
import 'trick_engine.dart';
import 'trick_rules.dart';

/// Rakipli kart oyunlarının ekranı: bölüm modunda tek el ([TrickHandView]);
/// "Maç" modunda (ve isteğe bağlı olarak çok oyunculu masada) hedef puana
/// kadar çok elli maç ([MatchView]).
class TrickView extends StatelessWidget {
  final PlayContext ctx;
  const TrickView({super.key, required this.ctx});

  @override
  Widget build(BuildContext context) => MatchView.wants(ctx) ? MatchView(ctx: ctx) : TrickHandView(ctx: ctx);
}

/// Rakipli kart oyunlarının ortak masası: dört (ya da daha az) koltuk, ortada
/// el, altta oyuncunun eli; ihale düğmeleri; ipucu ve geri al.
class TrickHandView extends StatefulWidget {
  final PlayContext ctx;

  /// Maçta: el bitince sonuç ekranı yerine çağrılır (puanları maç sayar).
  final void Function(TrickState end)? onHandOver;
  const TrickHandView({super.key, required this.ctx, this.onHandOver});

  @override
  State<TrickHandView> createState() => _TrickViewState();
}

class _TrickViewState extends State<TrickHandView> {
  late TrickLevel level;
  late TrickState s;
  late List<TrickAI> ais;
  final List<String> _undo = [];
  int _seconds = 0, _hints = 0, _undos = 0;
  Timer? _timer;
  bool _ended = false, _busy = false;
  KCard? _hintCard;
  int? _hintBid;
  List<KCard> _shownTrick = const [];
  int _shownLeader = 0, _shownWinner = -1;

  /// El bitince kartlar kazanana doğru toplanıyor.
  bool _collecting = false;

  /// Son tamamlanan el (gözden geçirme için).
  List<KCard> _lastTrick = const [];
  int _lastLeader = 0, _lastWin = -1;
  bool _showLast = false;

  /// El sonu özeti gösteriliyor: "Devam" ile sonuç ekranına geçilir.
  RoundResult? _pending;

  PlayContext get ctx => widget.ctx;
  TrickRules get rules => level.rules;

  // ---- Koltuklar ---------------------------------------------------------------
  StreamSubscription<(int, String)>? _sub;
  final List<(int, String)> _inbox = [];

  /// Bu koltuğun hamlesi ağdan gelmiş ve sırasını bekliyor mu.
  bool _queued(int seat) => _inbox.any((e) => e.$1 == seat);
  Completer<void>? _wake;
  bool _cover = false;
  int _shown = 0;

  bool get _multi => ctx.seats.isNotEmpty;
  MatchLink? get _match => ctx.match;
  bool _isLocal(int seat) => _multi ? ctx.role(seat) == SeatRole.local : seat == 0;
  bool _isAi(int seat) =>
      (_multi ? (ctx.role(seat) == SeatRole.ai || (_match?.dropped.contains(seat) ?? false)) : seat != 0) ||
      (_pilot && seat == me);

  /// Oyun testi: bu koltuğu da yapay zekâ oynar.
  bool get _pilot => KartAutoPilot.on.value && _match == null;

  void _onPilot() {
    if (_pilot && mounted) _advance();
  }

  int get me {
    final m = _match;
    if (m != null) return m.mySeat;
    if (ctx.passAndPlay) return _shown;
    return 0;
  }

  bool get _myTurn => _isLocal(s.turn) && s.turn == me && !_cover;

  Future<String?> _remote(int seat) async {
    while (mounted && !_ended) {
      final i = _inbox.indexWhere((e) => e.$1 == seat);
      if (i >= 0) return _inbox.removeAt(i).$2;
      if (_isAi(seat)) return null;
      _wake = Completer<void>();
      await Future.any([_wake!.future, Future<void>.delayed(const Duration(seconds: 2))]);
    }
    return null;
  }

  void _maybeCover() {
    if (!ctx.passAndPlay || s.phase == TrickPhase.over) return;
    if (_isLocal(s.turn) && s.turn != _shown) {
      _shown = s.turn;
      _cover = true;
    }
  }

  @override
  void initState() {
    super.initState();
    level = (ctx.generated as GeneratedLevel<TrickLevel>).puzzle;
    final snap = ctx.resume['snap'];
    s = snap is String ? TrickState.fromJson(_decode(snap)) : level.start.copy();
    _seconds = (ctx.resume['secs'] as num?)?.toInt() ?? 0;
    _hints = (ctx.resume['hints'] as num?)?.toInt() ?? 0;
    final r = SeededRandom(mixSeed([level.seed, 99, _seconds]));
    ais = [
      for (var p = 0; p < s.seats; p++)
        TrickAI(rules, rules.partnerships && p == 2 ? 16 : level.aiSamples, r),
    ];
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_ended && mounted) setState(() => _seconds++);
    });
    final m = _match;
    if (m != null) {
      // Maça geri dönüş: o ana kadarki hamleler beklemeden yeniden oynanır.
      _inbox.addAll(m.history);
      _sub = m.moves.listen((e) {
        _inbox.add(e);
        final w = _wake;
        _wake = null;
        w?.complete();
        // Koltuğumuz bir süre bota kaldıysa onun hamlesi sıradaki yerel hamledir.
        if (mounted && !_ended && e.$1 == s.turn && _isLocal(s.turn)) _advance();
      });
    }
    if (ctx.passAndPlay) {
      _shown = _isLocal(s.turn) ? s.turn : 0;
      _cover = true;
    }
    KartAutoPilot.on.addListener(_onPilot);
    WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
  }

  static Map<String, dynamic> _decode(String s) => jsonDecode(s) as Map<String, dynamic>;

  @override
  void dispose() {
    KartAutoPilot.on.removeListener(_onPilot);
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _persist() => ctx.saveResume({'snap': s.serialize(), 'secs': _seconds, 'hints': _hints});

  Duration get _pace => ctx.reducedMotion ? const Duration(milliseconds: 150) : const Duration(milliseconds: 520);

  /// Yapay zekâ koltuklarını sırası gelince oynat.
  Future<void> _advance() async {
    if (_busy) return;
    _busy = true;
    while (mounted && !_ended && s.phase != TrickPhase.over && (!_isLocal(s.turn) || _queued(s.turn) || (_pilot && s.turn == me))) {
      final seat = s.turn;
      final mt = _match;
      if (mt != null && (_queued(seat) || !_isAi(seat) || !mt.isHost)) {
        final mv = await _remote(seat);
        if (!mounted || _ended) return;
        if (mv == null) continue;
        if (!await _applyRemote(seat, mv)) continue;
        continue;
      }
      await Future<void>.delayed(_pace);
      if (!mounted) return;
      if (s.phase == TrickPhase.bidding) {
        final b = ais[seat].bid(s, seat);
        if (mt != null) unawaited(mt.send('b:$b', asSeat: seat));
        rules.applyBid(s, seat, b);
        if (rules.biddingOver(s)) rules.finishBidding(s);
        setState(() {});
      } else {
        final act = ais[seat].action(s, seat);
        if (act != null) {
          if (mt != null) unawaited(mt.send('a:$act', asSeat: seat));
          rules.applyPlayAction(s, seat, act);
          setState(() {});
          continue;
        }
        final c = ais[seat].play(s, seat);
        if (mt != null) unawaited(mt.send('c:${rules.legalPlays(s, seat).indexOf(c)}', asSeat: seat));
        await _playCard(seat, c);
      }
    }
    _busy = false;
    _persist();
    if (s.phase == TrickPhase.over) {
      _end();
    } else {
      setState(_maybeCover);
      _autoLast();
    }
  }

  /// Son kart zorunlu hamledir: piyasadaki masalar gibi kendiliğinden oynanır.
  void _autoLast() {
    if (s.phase != TrickPhase.play || !_myTurn || s.hands[s.turn].length != 1) return;
    if (rules.playActions(s, s.turn).isNotEmpty) return;
    final seat = s.turn;
    Future<void>.delayed(_pace, () {
      if (!mounted || _ended || _busy || !_myTurn || s.turn != seat || s.hands[seat].length != 1) return;
      _humanPlay(s.hands[seat].first);
    });
  }

  /// Ağdan gelen hamle: "b:<ihale>" ya da "c:<geçerli kart sırası>".
  Future<bool> _applyRemote(int seat, String mv) async {
    final v = int.tryParse(mv.substring(2));
    if (v == null) return false;
    if (mv.startsWith('b:') && s.phase == TrickPhase.bidding) {
      if (!rules.legalBids(s, seat).contains(v)) return false;
      rules.applyBid(s, seat, v);
      if (rules.biddingOver(s)) rules.finishBidding(s);
      setState(() {});
      return true;
    }
    if (mv.startsWith('a:') && s.phase == TrickPhase.play) {
      if (!rules.playActions(s, seat).contains(v)) return false;
      rules.applyPlayAction(s, seat, v);
      setState(() {});
      return true;
    }
    if (mv.startsWith('c:') && s.phase == TrickPhase.play) {
      final legal = rules.legalPlays(s, seat);
      if (v < 0 || v >= legal.length) return false;
      await _playCard(seat, legal[v]);
      return true;
    }
    return false;
  }

  Future<void> _playCard(int seat, KCard c) async {
    final before = List<KCard>.of(s.trick);
    final leader = s.leader;
    rules.play(s, seat, c);
    ctx.sfx(Sfx.place);
    if (before.length == s.seats - 1) {
      // El tamamlandı: kartları kısa süre göster, kazananı işaretle.
      setState(() {
        _shownTrick = [...before, c];
        _shownLeader = leader;
        _shownWinner = s.lastWinner;
        _lastTrick = _shownTrick;
        _lastLeader = leader;
        _lastWin = s.lastWinner;
        _showLast = false;
      });
      if (_inbox.isEmpty) await Future<void>.delayed(_pace * 1.4);
      if (!mounted) return;
      ctx.sfx(s.lastWinner == me || (rules.partnerships && s.lastWinner == (me + 2) % s.seats) ? Sfx.coin : Sfx.tap);
      if (_inbox.isEmpty && !ctx.reducedMotion) {
        // Kartlar el alanın önüne doğru toplanır.
        setState(() => _collecting = true);
        await Future<void>.delayed(const Duration(milliseconds: 320));
        if (!mounted) return;
      }
      setState(() {
        _shownTrick = const [];
        _collecting = false;
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _humanPlay(KCard c) async {
    if (_ended || _busy || !_myTurn || s.phase != TrickPhase.play) return;
    final seat = s.turn;
    final legal = rules.legalPlays(s, seat);
    if (!legal.contains(c)) {
      ctx.sfx(Sfx.error);
      return;
    }
    unawaited(_match?.send('c:${legal.indexOf(c)}'));
    _undo.add(s.serialize());
    _hintCard = null;
    _busy = true;
    await _playCard(seat, c);
    _busy = false;
    _persist();
    setState(_maybeCover);
    _advance();
  }


  /// Kartsız hamle (ör. 29'da "koz açtır").
  void _humanAction(int a) {
    if (_ended || _busy || !_myTurn || s.phase != TrickPhase.play) return;
    final seat = s.turn;
    if (!rules.playActions(s, seat).contains(a)) return;
    unawaited(_match?.send('a:$a'));
    _undo.add(s.serialize());
    rules.applyPlayAction(s, seat, a);
    ctx.sfx(Sfx.tap);
    setState(() {});
    _persist();
  }

  void _humanBid(int bid) {
    if (_ended || _busy || !_myTurn || s.phase != TrickPhase.bidding) return;
    final seat = s.turn;
    unawaited(_match?.send('b:$bid'));
    _undo.add(s.serialize());
    rules.applyBid(s, seat, bid);
    if (rules.biddingOver(s)) rules.finishBidding(s);
    setState(() {
      _hintBid = null;
      _maybeCover();
    });
    _persist();
    _advance();
  }

  void _doUndo() {
    if (_undo.isEmpty || _busy || _ended || _match != null || ctx.passAndPlay) return;
    setState(() {
      s = TrickState.fromJson(_decode(_undo.removeLast()));
      _undos++;
      _hintCard = null;
      _shownTrick = const [];
    });
    _persist();
  }

  Future<void> _hint() async {
    if (_ended || _busy || !_myTurn || !await ctx.requestHint()) return;
    _hints++;
    final adv = TrickAI(rules, 30, SeededRandom(mixSeed([level.seed, _seconds, 3])));
    setState(() {
      if (s.phase == TrickPhase.bidding) {
        _hintBid = adv.bid(s, s.turn);
      } else {
        _hintCard = adv.play(s, s.turn);
      }
    });
    _persist();
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    final over = widget.onHandOver;
    if (over != null) {
      over(s);
      return;
    }
    if (_multi) {
      final u = [for (var i = 0; i < s.seats; i++) rules.utility(s, i)];
      var w = 0;
      for (var i = 1; i < u.length; i++) {
        if (u[i] > u[w]) w = i;
      }
      final team = rules.partnerships ? {w, (w + 2) % s.seats} : {w};
      final tie = [for (var i = 0; i < u.length; i++) if (u[i] == u[w] && !team.contains(i)) i].isNotEmpty;
      final iWon = !tie && (_match != null ? team.contains(_match!.mySeat) : true);
      ctx.sfx(iWon ? Sfx.win : Sfx.lose);
      unawaited(_match?.finish(tie ? -1 : w, iWon: iWon));
      _summary(RoundResult(
        won: iWon,
        score: iWon ? 300 : 30,
        seconds: _seconds,
        headline: tie ? ctx.t('draw_title') : (_match != null ? null : ctx.t('player_wins', {'n': w + 1})),
        gameStats: {'hands_won': iWon ? 1 : 0},
      ));
      return;
    }
    final won = level.goal.check(rules, s);
    ctx.sfx(won ? Sfx.win : Sfx.lose);
    final mine = s.tricks[0] + (rules.partnerships ? s.tricks[2] : 0);
    _summary(RoundResult(
      won: won,
      score: math.max(0, (rules.utility(s, 0) * 10).round() + mine * 20 + (won ? 300 : 0)),
      stars: TrickGameRules.stars(won: won, hints: _hints, undos: _undos),
      seconds: _seconds,
      moves: s.played.length,
      hintsUsed: _hints,
      undosUsed: _undos,
      gameStats: {'tricks_taken': s.tricks[0], 'hands_won': won ? 1 : 0},
    ));
  }

  /// El sonu tablosu: kim kaç el aldı, ihaleler ve puanlar; "Devam" ile
  /// sonuç ekranı.
  void _summary(RoundResult r) {
    if (!mounted) {
      ctx.finish(r);
      return;
    }
    setState(() {
      _pending = r;
      _showLast = false;
    });
  }

  // ---- görünüm ----

  CardStyle get _style => kartCardStyle(context, ctx);

  /// Koltuğun ekrandaki yeri: 0 alt, sonra saat yönünde.
  Alignment _seatAlign(int seat) => tableSeatAlign(seat, me, s.seats);

  String _seatName(int seat) => tableSeatName(ctx, seat, me, s.seats);

  bool _isPartner(int seat) => rules.partnerships && seat != me && seat == s.partnerOf(me);

  List<Widget> _pills(int seat) {
    final bid = s.bids[seat];
    final lang = ctx.lang;
    final decl = s.declarer == seat && s.phase != TrickPhase.bidding;
    return [
      SeatPill('${s.tricks[seat]}', icon: Icons.layers_rounded),
      if (bid != null && (s.phase == TrickPhase.bidding || decl || !rules.hasBidding || s.declarer < 0))
        SeatPill(rules.bidLabel(bid, lang),
            icon: decl ? Icons.gavel_rounded : Icons.record_voice_over_rounded,
            color: decl ? const Color(0xFFF2D38A) : null,
            textColor: decl ? const Color(0xFF3A2A08) : null)
      else if (decl)
        SeatPill(Strings.tx(lang, 'İhale', 'Bid'), icon: Icons.gavel_rounded, color: const Color(0xFFF2D38A), textColor: const Color(0xFF3A2A08)),
    ];
  }

  Widget _opponent(int seat, {required bool side}) {
    final active = s.turn == seat && s.phase != TrickPhase.over && _pending == null;
    return TableSeat(
      name: _seatName(seat),
      seat: (seat - me + s.seats) % s.seats,
      style: _style,
      lang: ctx.lang,
      active: active,
      cards: s.hands[seat].length,
      pills: _pills(seat),
      partner: _isPartner(seat),
      dealer: s.dealer == seat,
      side: side,
      compact: side,
      // Açık el (Null Ouvert): kartlar herkese görünür.
      extra: rules.openHand(s, seat)
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 1, runSpacing: 2, children: [for (final c in s.hands[seat]) _card(c, 18)]),
              ),
            )
          : null,
    );
  }

  Widget _mySeat() {
    final active = s.turn == me && s.phase != TrickPhase.over && _pending == null;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      SeatAvatar(name: _seatName(me), seat: 0, active: active, size: 30),
      const SizedBox(width: 4),
      SeatNameTag(text: active && s.phase == TrickPhase.play ? Strings.tx(ctx.lang, 'Sıra sende', 'Your turn') : _seatName(me), active: active, maxWidth: 180),
      const SizedBox(width: 4),
      ..._pills(me).map((p) => Padding(padding: const EdgeInsets.only(left: 3), child: p)),
      if (s.dealer == me) Padding(padding: const EdgeInsets.only(left: 4), child: DealerCoin(lang: ctx.lang)),
    ]);
  }

  Widget _card(KCard c, double w, {bool up = true, bool dim = false, bool hl = false}) => SizedBox(
        width: w,
        height: w * 1.4,
        child: CustomPaint(painter: _CardP(c, up, _style, dim, hl)),
      );

  /// Ortadaki el: her kart oynayanın tarafına doğru, hafif dönük; kart
  /// oynayanın yerinden kayarak gelir, el bitince kazanana doğru toplanır.
  Widget _trickArea(double tw, List<KCard> cards, int leader, int winner, {bool review = false}) {
    final boxW = tw * 3.5, boxH = tw * 1.4 * 2.55;
    final wa = winner >= 0 ? _seatAlign(winner) : Alignment.center;
    final fast = ctx.reducedMotion;
    Widget area = SizedBox(
      width: boxW,
      height: boxH,
      child: Stack(clipBehavior: Clip.none, children: [
        for (var i = 0; i < cards.length; i++)
          () {
            final seat = (leader + i) % s.seats;
            final a = _seatAlign(seat);
            final win = winner == seat && (review || _shownTrick.isNotEmpty);
            final card = Transform.rotate(
              angle: a.x * 0.14 + (a.y < 0 ? 0.05 : -0.03) * (i.isEven ? 1 : -1),
              child: AnimatedScale(
                scale: win ? 1.1 : 1,
                duration: const Duration(milliseconds: 200),
                child: _card(cards[i], tw, hl: win),
              ),
            );
            return Align(
              alignment: Alignment(a.x * 0.74, a.y * 0.8),
              child: review
                  ? card
                  : TweenAnimationBuilder<double>(
                      key: ValueKey('t${s.played.length ~/ s.seats}_${cards[i]}'),
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(milliseconds: fast ? 1 : 280),
                      curve: Curves.easeOutCubic,
                      builder: (_, t, child) => Transform.translate(
                        offset: Offset(a.x * boxW * 0.9, a.y * boxH * 0.9) * (1 - t),
                        child: child,
                      ),
                      child: card,
                    ),
            );
          }(),
      ]),
    );
    if (review) return area;
    final dur = Duration(milliseconds: _collecting && !fast ? 300 : 0);
    return AnimatedSlide(
      offset: _collecting ? Offset(wa.x * 0.9, wa.y * 0.9) : Offset.zero,
      duration: dur,
      curve: Curves.easeInCubic,
      child: AnimatedOpacity(
        opacity: _collecting ? 0 : 1,
        duration: dur,
        child: AnimatedScale(scale: _collecting ? 0.55 : 1, duration: dur, child: area),
      ),
    );
  }

  Widget _lastTrickPanel(double tw) => GestureDetector(
        onTap: () => setState(() => _showLast = false),
        child: StudioBoardPanel(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              '${Strings.tx(ctx.lang, 'Son el', 'Last trick')} · ${_seatName(_lastWin)}',
              style: const TextStyle(color: kStudioText, fontWeight: FontWeight.w900, fontSize: 14),
            ),
            const SizedBox(height: 4),
            _trickArea(tw * 0.9, _lastTrick, _lastLeader, _lastWin, review: true),
          ]),
        ),
      );

  Widget _summaryPanel() {
    final r = _pending!;
    final sc = rules.handScores(s);
    final lang = ctx.lang;
    const head = TextStyle(color: kStudioTextDim, fontSize: 12, fontWeight: FontWeight.w700);
    const cell = TextStyle(color: kStudioText, fontSize: 15, fontWeight: FontWeight.w800);
    Widget c(String t, TextStyle st, {TextAlign a = TextAlign.center}) =>
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: Text(t, style: st, textAlign: a));
    final order = [for (var k = 0; k < s.seats; k++) (me + k) % s.seats];
    return StudioBoardPanel(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(r.won ? Icons.emoji_events_rounded : Icons.sentiment_dissatisfied_rounded,
                color: r.won ? const Color(0xFFFFD45A) : kStudioTextDim, size: 40),
            Text(
              r.headline ?? (r.won ? Strings.tx(lang, 'Eli kazandın!', 'You won the hand!') : Strings.tx(lang, 'Bu eli kaybettin', 'You lost this hand')),
              textAlign: TextAlign.center,
              style: const TextStyle(color: kStudioText, fontSize: 20, fontWeight: FontWeight.w900),
            ),
            if (rules.status(s, lang).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(rules.status(s, lang), style: const TextStyle(color: kStudioTextDim, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 10),
            Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const {0: FlexColumnWidth(2.2)},
              children: [
                TableRow(children: [
                  c(Strings.tx(lang, 'Oyuncu', 'Player'), head, a: TextAlign.start),
                  if (rules.hasBidding) c(Strings.tx(lang, 'İhale', 'Bid'), head),
                  c(Strings.tx(lang, 'El', 'Tricks'), head),
                  c(Strings.tx(lang, 'Puan', 'Score'), head),
                ]),
                for (final p in order)
                  TableRow(
                    decoration: BoxDecoration(
                      color: p == me ? Colors.white.withValues(alpha: 0.08) : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    children: [
                      Row(children: [
                        Padding(
                          padding: const EdgeInsets.all(3),
                          child: SeatAvatar(name: _seatName(p), seat: (p - me + s.seats) % s.seats, size: 24),
                        ),
                        Flexible(
                          child: Text(
                            _isPartner(p) ? '${_seatName(p)} · ${Strings.tx(lang, 'Eş', 'Partner')}' : _seatName(p),
                            overflow: TextOverflow.ellipsis,
                            style: cell.copyWith(fontSize: 14),
                          ),
                        ),
                      ]),
                      if (rules.hasBidding)
                        c(s.bids[p] == null ? '–' : (s.declarer == p ? '★ ' : '') + rules.bidLabel(s.bids[p]!, lang), cell),
                      c('${s.tricks[p]}', cell),
                      c('${sc[p]}', cell.copyWith(color: sc[p] < 0 ? const Color(0xFFFF8A80) : kStudioText)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            StudioButton.hot(
              label: Strings.tx(lang, 'Devam', 'Continue'),
              onPressed: () {
                final res = _pending;
                if (res == null) return;
                setState(() => _pending = null);
                ctx.finish(res);
              },
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FeltTable(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final status = rules.status(s, ctx.lang);
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth, h = cons.maxHeight;
      final wide = w > h * 1.15;
      final ts = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
      final handLen = math.max(1, s.hands[me].length);
      final cw = math.min(wide ? 84.0 : 76.0, math.min(w / (handLen * 0.56 + 0.7), h * (wide ? 0.19 : 0.15) / ts));
      final tw = math.min(wide ? 74.0 : 66.0, math.min(w * 0.16, h * (wide ? 0.13 : 0.1)));
      final legal = _myTurn && s.phase == TrickPhase.play && _pending == null ? rules.legalPlays(s, s.turn).toSet() : <KCard>{};
      final trickCards = _shownTrick.isNotEmpty ? _shownTrick : s.trick;
      final trickLeader = _shownTrick.isNotEmpty ? _shownLeader : s.leader;
      final board = Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
          child: Row(children: [
            Expanded(
              child: Text(level.goal.text(rules, s, ctx.lang),
                  style: const TextStyle(color: kStudioText, fontWeight: FontWeight.w800, fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
            if (s.trump >= 0 && s.trump < 4)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: TrumpBadge(suit: s.trump, label: Strings.tx(ctx.lang, 'Koz', 'Trump')),
              ),
            const SizedBox(width: 8),
            StudioTag(
              icon: Icons.timer_outlined,
              text: '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}',
            ),
          ]),
        ),
        if (status.isNotEmpty)
          Text(status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kStudioTextDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
        Expanded(
          child: Stack(children: [
            for (var k = 1; k < s.seats; k++)
              () {
                final seat = (me + k) % s.seats;
                final a = _seatAlign(seat);
                final side = a.x.abs() > 0.6 && a.y.abs() < 0.6;
                return Align(
                  alignment: a,
                  child: Padding(padding: const EdgeInsets.all(4), child: _opponent(seat, side: side)),
                );
              }(),
            Center(
              child: Padding(
                padding: EdgeInsets.only(top: s.seats == 3 ? 0 : 30),
                child: _trickArea(tw, trickCards, trickLeader, _shownWinner),
              ),
            ),
            if (_showLast && _lastTrick.isNotEmpty) Center(child: _lastTrickPanel(tw)),
            if (s.phase == TrickPhase.bidding && _myTurn && !_busy)
              Align(
                alignment: const Alignment(0, 0.75),
                child: StudioBoardPanel(
                  margin: const EdgeInsets.all(10),
                  padding: const EdgeInsets.all(12),
                  // Çok sayıda teklif kısa ekrana sığmazsa panel kaydırılır.
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(rules.bidPrompt(s, ctx.lang),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: kStudioText, fontSize: 17, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
                        for (final b in rules.legalBids(s, s.turn))
                          () {
                            final lab = rules.bidLabel(b, ctx.lang);
                            final suit = const ['♠', '♥', '♦', '♣'].indexOf(lab);
                            if (suit >= 0) {
                              // Koz seçimi: büyük renk düğmesi.
                              return Semantics(
                                button: true,
                                label: '${Strings.tx(ctx.lang, 'Koz', 'Trump')} $lab',
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => _humanBid(b),
                                  child: Container(
                                    width: 60,
                                    height: 72,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: CardStyle.paper,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                          color: _hintBid == b ? const Color(0xFFFFC53D) : const Color(0xFFD9D1C0),
                                          width: _hintBid == b ? 3 : 1.5),
                                    ),
                                    child: CustomPaint(painter: SuitIconPainter(suit)),
                                  ),
                                ),
                              );
                            }
                            return StudioChoice(hinted: _hintBid == b, onPressed: () => _humanBid(b), label: lab);
                          }(),
                      ]),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
        if (s.phase == TrickPhase.play && _myTurn && !_busy && rules.playActions(s, s.turn).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
              for (final a in rules.playActions(s, s.turn))
                StudioButton(
                  expand: false,
                  height: 48,
                  fontSize: 15,
                  icon: Icons.visibility,
                  onPressed: () => _humanAction(a),
                  label: rules.playActionLabel(a, ctx.lang),
                ),
            ]),
          ),
        Padding(padding: const EdgeInsets.only(bottom: 2), child: _mySeat()),
        // Oyuncunun eli: hafif yay biçiminde yelpaze; oynanabilenler yukarıda,
        // oynanamayanlar soluk.
        if (_cover)
          StudioCover(
            height: cw * 1.4 + 18,
            text: ctx.t('pass_device', {'p': ctx.seatName(_shown)}),
            sub: ctx.t('tap_when_ready'),
            onTap: () => setState(() => _cover = false),
          )
        else
          SizedBox(
            height: cw * 1.4 + 18,
            child: LayoutBuilder(builder: (context, c2) {
              final n = s.hands[me].length;
              final step = n <= 1 ? 0.0 : math.min(cw * 0.9, (c2.maxWidth - cw - 12) / (n - 1));
              final total = cw + step * math.max(0, n - 1);
              final left0 = (c2.maxWidth - total) / 2;
              final spread = math.min(0.2, n * 0.016);
              return Stack(clipBehavior: Clip.none, children: [
                for (var i = 0; i < n; i++)
                  () {
                    final c = s.hands[me][i];
                    final ok = legal.contains(c);
                    final t = n <= 1 ? 0.0 : (i - (n - 1) / 2) / ((n - 1) / 2);
                    final dim = s.phase == TrickPhase.play && _myTurn && !ok;
                    return AnimatedPositioned(
                      key: ValueKey(c),
                      duration: const Duration(milliseconds: 180),
                      left: left0 + step * i,
                      top: (ok ? 0.0 : 14.0) + t * t * cw * 0.1,
                      child: Transform.rotate(
                        angle: t * spread,
                        alignment: Alignment.bottomCenter,
                        child: Semantics(
                          button: ok,
                          label: '${rankLabel(rankOf(c))} ${const ['♠', '♥', '♦', '♣'][suitOf(c)]}',
                          child: GestureDetector(
                            onTap: () => _humanPlay(c),
                            child: _card(c, cw, dim: dim, hl: _hintCard == c),
                          ),
                        ),
                      ),
                    );
                  }(),
              ]);
            }),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            StudioRoundAction(
                onPressed: _ended || _busy || !_myTurn ? null : _hint,
                icon: Icons.lightbulb,
                tooltip: ctx.t('hint')),
            StudioRoundAction(
                onPressed: _lastTrick.isEmpty ? null : () => setState(() => _showLast = !_showLast),
                icon: Icons.history_rounded,
                tooltip: Strings.tx(ctx.lang, 'Son el', 'Last trick')),
            StudioRoundAction(
                onPressed: _undo.isNotEmpty && !_busy && !_ended ? _doUndo : null,
                icon: Icons.undo,
                tooltip: ctx.t('undo')),
          ]),
        ),
      ]);
      return Stack(children: [
        board,
        if (_pending != null)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.45),
              child: Center(child: _summaryPanel()),
            ),
          ),
      ]);
    });
  }
}

class _CardP extends CustomPainter {
  final KCard c;
  final bool up, dim, hl;
  final CardStyle style;
  _CardP(this.c, this.up, this.style, this.dim, this.hl);
  @override
  void paint(Canvas canvas, Size size) =>
      paintCard(canvas, Offset.zero & size, c, faceUp: up, style: style, dim: dim, highlight: hl);
  @override
  bool shouldRepaint(covariant _CardP o) => o.c != c || o.up != up || o.dim != dim || o.hl != hl || o.style != style;
}
