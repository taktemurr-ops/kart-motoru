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
import 'cards.dart';
import 'trick_ai.dart';
import 'trick_engine.dart';
import 'trick_rules.dart';

/// Rakipli kart oyunlarının ortak masası: dört (ya da daha az) koltuk, ortada
/// el, altta oyuncunun eli; ihale düğmeleri; ipucu ve geri al.
class TrickView extends StatefulWidget {
  final PlayContext ctx;
  const TrickView({super.key, required this.ctx});

  @override
  State<TrickView> createState() => _TrickViewState();
}

class _TrickViewState extends State<TrickView> {
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
  bool _isAi(int seat) => _multi ? (ctx.role(seat) == SeatRole.ai || (_match?.dropped.contains(seat) ?? false)) : seat != 0;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
  }

  static Map<String, dynamic> _decode(String s) => jsonDecode(s) as Map<String, dynamic>;

  @override
  void dispose() {
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
    while (mounted && !_ended && s.phase != TrickPhase.over && (!_isLocal(s.turn) || _queued(s.turn))) {
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
    }
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
      });
      if (_inbox.isEmpty) await Future<void>.delayed(_pace * 1.6);
      if (!mounted) return;
      ctx.sfx(s.lastWinner == me || (rules.partnerships && s.lastWinner == (me + 2) % s.seats) ? Sfx.coin : Sfx.tap);
      setState(() => _shownTrick = const []);
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
      ctx.finish(RoundResult(
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
    ctx.finish(RoundResult(
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

  // ---- görünüm ----

  CardStyle get _style => CardStyle(
        backA: ctx.pieceColors.isNotEmpty ? ctx.pieceColors[0] : const Color(0xFF1F5E8C),
        backB: ctx.pieceColors.length > 1 ? ctx.pieceColors[1] : const Color(0xFF2BB3B1),
        colorBlind: ctx.colorBlind,
      );

  /// Koltuğun ekrandaki yeri: 0 alt, sonra saat yönünde.
  Alignment _seatAlign(int seat) {
    final n = s.seats;
    seat = (seat - me + n) % n;
    if (n == 2) return seat == 0 ? Alignment.bottomCenter : Alignment.topCenter;
    if (n == 3) return const [Alignment.bottomCenter, Alignment.centerLeft, Alignment.centerRight][seat];
    return const [Alignment.bottomCenter, Alignment.centerLeft, Alignment.topCenter, Alignment.centerRight][seat % 4];
  }

  String _seatName(int seat) {
    if (_multi && (ctx.passAndPlay || ctx.role(seat) != SeatRole.ai)) {
      return seat == me && _match != null ? Strings.tx(ctx.lang, 'Sen', 'You') : ctx.seatName(seat);
    }
    if (seat == me) return Strings.tx(ctx.lang, 'Sen', 'You');
    if (rules.partnerships && seat == (me + 2) % s.seats) return Strings.tx(ctx.lang, 'Eşin', 'Partner');
    final a = _seatAlign(seat);
    if (a == Alignment.centerLeft) return Strings.tx(ctx.lang, 'Sol', 'Left');
    if (a == Alignment.centerRight) return Strings.tx(ctx.lang, 'Sağ', 'Right');
    return Strings.tx(ctx.lang, 'Karşı', 'Across');
  }

  Widget _seatBadge(int seat) {
    final bid = s.bids[seat];
    final active = s.turn == seat && s.phase != TrickPhase.over;
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? cs.primaryContainer : cs.surfaceContainerHigh.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: active ? cs.primary : Colors.transparent, width: 2),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_seatName(seat), style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('${Strings.tx(ctx.lang, 'El', 'Tricks')}: ${s.tricks[seat]}'
            '${bid != null ? '  ·  ${rules.bidLabel(bid, ctx.lang)}' : ''}'
            '${seat != me ? '  ·  🂠${s.hands[seat].length}' : ''}',
            style: const TextStyle(fontSize: 12)),
      ]),
    );
  }

  Widget _card(KCard c, double w, {bool up = true, bool dim = false, bool hl = false}) => SizedBox(
        width: w,
        height: w * 1.4,
        child: CustomPaint(painter: _CardP(c, up, _style, dim, hl)),
      );

  @override
  Widget build(BuildContext context) => FeltTable(child: _build(context));

  Widget _build(BuildContext context) {
    final trumpTxt = s.trump >= 0 && s.trump < 4 ? ['♠', '♥', '♦', '♣'][s.trump] : null;
    final status = rules.status(s, ctx.lang);
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth, h = cons.maxHeight;
      final handLen = math.max(1, s.hands[me].length);
      final cw = math.min(76.0, math.min(w / (handLen * 0.62 + 0.6), h * 0.16));
      final tw = math.min(70.0, w * 0.15);
      final legal = _myTurn && s.phase == TrickPhase.play ? rules.legalPlays(s, s.turn).toSet() : <KCard>{};
      final trickCards = _shownTrick.isNotEmpty ? _shownTrick : s.trick;
      final trickLeader = _shownTrick.isNotEmpty ? _shownLeader : s.leader;
      // Koyu masa zemininde üst bilgiler açık renkle yazılır (okunurluk).
      final bg = ctx.background;
      final dark = bg.isNotEmpty && bg.map((c) => c.computeLuminance()).reduce((a, b) => a + b) / bg.length < 0.3;
      final fg = dark ? const Color(0xFFF5EFE6) : null;
      final fgDim = dark ? const Color(0xCCF5EFE6) : null;
      return Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            Expanded(
              child: Text(level.goal.text(rules, s, ctx.lang),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: fg), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            if (trumpTxt != null)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: Text('${Strings.tx(ctx.lang, 'Koz', 'Trump')} $trumpTxt',
                    style: TextStyle(color: _style.suitColor(s.trump), fontWeight: FontWeight.w800)),
              ),
            const SizedBox(width: 8),
            Icon(Icons.timer_outlined, size: 18, color: fg),
            Text(' ${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}', style: TextStyle(color: fg)),
          ]),
        ),
        if (status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(status, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fgDim)),
          ),
        Expanded(
          child: Stack(children: [
            for (var k = 1; k < s.seats; k++)
              Align(alignment: _seatAlign((me + k) % s.seats), child: Padding(padding: const EdgeInsets.all(6), child: _seatBadge((me + k) % s.seats))),
            // Ortadaki el
            Center(
              child: SizedBox(
                width: tw * 3.4,
                height: tw * 1.4 * 2.6,
                child: Stack(children: [
                  for (var i = 0; i < trickCards.length; i++)
                    () {
                      final seat = (trickLeader + i) % s.seats;
                      final a = _seatAlign(seat);
                      return Align(
                        alignment: Alignment(a.x * 0.7, a.y * 0.75),
                        child: AnimatedScale(
                          scale: _shownWinner == seat && _shownTrick.isNotEmpty ? 1.08 : 1,
                          duration: const Duration(milliseconds: 200),
                          child: _card(trickCards[i], tw, hl: _shownWinner == seat && _shownTrick.isNotEmpty),
                        ),
                      );
                    }(),
                ]),
              ),
            ),
            if (s.phase == TrickPhase.bidding && _myTurn && !_busy)
              Align(
                alignment: const Alignment(0, 0.55),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(Strings.tx(ctx.lang, 'İhalen?', 'Your bid?'), style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
                        for (final b in rules.legalBids(s, s.turn))
                          FilledButton.tonal(
                            style: _hintBid == b
                                ? FilledButton.styleFrom(backgroundColor: const Color(0xFFFFC53D))
                                : null,
                            onPressed: () => _humanBid(b),
                            child: Text(rules.bidLabel(b, ctx.lang)),
                          ),
                      ]),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
        _seatBadge(me),
        const SizedBox(height: 4),
        // Oyuncunun eli
        if (_cover)
          GestureDetector(
            onTap: () => setState(() => _cover = false),
            child: Container(
              height: cw * 1.4 + 18,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
              alignment: Alignment.center,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.swap_horiz),
                Text(ctx.t('pass_device', {'p': ctx.seatName(_shown)}),
                    textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(ctx.t('tap_when_ready')),
              ]),
            ),
          )
        else
        SizedBox(
          height: cw * 1.4 + 18,
          child: LayoutBuilder(builder: (context, c2) {
            final n = s.hands[me].length;
            final step = n <= 1 ? 0.0 : math.min(cw * 0.95, (c2.maxWidth - cw - 8) / (n - 1));
            final total = cw + step * math.max(0, n - 1);
            final left0 = (c2.maxWidth - total) / 2;
            return Stack(children: [
              for (var i = 0; i < n; i++)
                () {
                  final c = s.hands[me][i];
                  final ok = legal.contains(c);
                  return AnimatedPositioned(
                    key: ValueKey(c),
                    duration: const Duration(milliseconds: 180),
                    left: left0 + step * i,
                    top: ok ? 0 : 14,
                    child: GestureDetector(
                      onTap: () => _humanPlay(c),
                      child: _card(c, cw, dim: s.phase == TrickPhase.play && _myTurn && !ok, hl: _hintCard == c),
                    ),
                  );
                }(),
            ]);
          }),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            IconButton.filledTonal(
                onPressed: _ended || _busy || !_myTurn ? null : _hint,
                icon: const Icon(Icons.lightbulb),
                tooltip: ctx.t('hint')),
            IconButton.filledTonal(
                onPressed: _undo.isNotEmpty && !_busy && !_ended ? _doUndo : null,
                icon: const Icon(Icons.undo),
                tooltip: ctx.t('undo')),
          ]),
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
