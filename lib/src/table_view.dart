import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'card_painter.dart';
import 'match_view.dart';
import 'studio_chrome.dart';
import 'tile_painter.dart';
import 'cards.dart';
import 'table_ai.dart';
import 'table_engine.dart';
import 'table_rules.dart';

/// Sıra tabanlı masa oyunlarının ortak ekranı: rakip koltukları, ortadaki
/// yığınlar, oyuncunun eli ve kartsız hamle düğmeleri.
///
/// "Maç" modunda (ve isteğe bağlı olarak çok oyunculu masada) hedef puana
/// kadar çok elli maç oynanır ([MatchView]).
class TableView extends StatelessWidget {
  final PlayContext ctx;
  const TableView({super.key, required this.ctx});

  @override
  Widget build(BuildContext context) => MatchView.wants(ctx) ? MatchView(ctx: ctx) : TableHandView(ctx: ctx);
}

/// Masa oyunlarının tek el ekranı.
class TableHandView extends StatefulWidget {
  final PlayContext ctx;

  /// Maçta: el bitince sonuç ekranı yerine çağrılır (puanları maç sayar).
  final void Function(TableState end)? onHandOver;
  const TableHandView({super.key, required this.ctx, this.onHandOver});

  @override
  State<TableHandView> createState() => _TableViewState();
}

class _TableViewState extends State<TableHandView> {
  late TableLevel level;
  late TableState s;
  late List<TableAI> ais;
  final List<String> _undo = [];
  int _seconds = 0, _hints = 0, _undos = 0;
  Timer? _timer;
  bool _ended = false, _busy = false;
  TAction? _hint;
  final Set<KCard> _selected = {};

  PlayContext get ctx => widget.ctx;
  TableRules get rules => level.rules;

  // ---- Koltuklar ---------------------------------------------------------------
  StreamSubscription<(int, String)>? _sub;
  final List<(int, String)> _inbox = [];

  /// Bu koltuğun hamlesi ağdan gelmiş ve sırasını bekliyor mu.
  bool _queued(int seat) => _inbox.any((e) => e.$1 == seat);
  Completer<void>? _wake;

  /// Sırayla oynamada el, telefon elden ele geçene kadar kapalı tutulur.
  bool _cover = false;
  int _shown = 0;

  bool get _multi => ctx.seats.isNotEmpty;
  MatchLink? get _match => ctx.match;
  bool _isLocal(int seat) => _multi ? ctx.role(seat) == SeatRole.local : seat == 0;
  bool _isAi(int seat) => _multi ? (ctx.role(seat) == SeatRole.ai || (_match?.dropped.contains(seat) ?? false)) : seat != 0;

  /// Eli ekranda gösterilen koltuk.
  int get me {
    final m = _match;
    if (m != null) return m.mySeat;
    if (ctx.passAndPlay) return _shown;
    return 0;
  }

  Future<int?> _remote(int seat) async {
    while (mounted && !_ended) {
      final i = _inbox.indexWhere((e) => e.$1 == seat);
      if (i >= 0) return int.tryParse(_inbox.removeAt(i).$2);
      if (_isAi(seat)) return null;
      _wake = Completer<void>();
      await Future.any([_wake!.future, Future<void>.delayed(const Duration(seconds: 2))]);
    }
    return null;
  }

  /// Sıra başka bir yerel oyuncuya geçtiyse eli kapat.
  void _maybeCover() {
    if (!ctx.passAndPlay || s.over) return;
    if (_isLocal(s.turn) && s.turn != _shown) {
      _shown = s.turn;
      _cover = true;
    }
  }

  @override
  void initState() {
    super.initState();
    level = (ctx.generated as GeneratedLevel<TableLevel>).puzzle;
    final snap = ctx.resume['snap'];
    s = snap is String ? TableState.fromJson(snap) : level.start.copy();
    _seconds = (ctx.resume['secs'] as num?)?.toInt() ?? 0;
    _hints = (ctx.resume['hints'] as num?)?.toInt() ?? 0;
    final r = SeededRandom(mixSeed([level.seed, 77, _seconds]));
    ais = [for (var p = 0; p < s.seats; p++) TableAI(rules, level.aiSamples, r)];
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

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _persist() => ctx.saveResume({'snap': s.serialize(), 'secs': _seconds, 'hints': _hints});

  Duration get _pace => ctx.reducedMotion ? const Duration(milliseconds: 150) : const Duration(milliseconds: 650);

  Future<void> _advance() async {
    if (_busy) return;
    _busy = true;
    while (mounted && !_ended && !s.over && (!_isLocal(s.turn) || _queued(s.turn))) {
      final seat = s.turn;
      final mt = _match;
      TAction act;
      if (mt != null && (_queued(seat) || !_isAi(seat) || !mt.isHost)) {
        final i = await _remote(seat);
        if (!mounted || _ended) return;
        final legal = rules.legalActions(s);
        if (i == null || i < 0 || i >= legal.length) continue;
        act = legal[i];
      } else {
        await Future<void>.delayed(_pace);
        if (!mounted) return;
        act = ais[seat].choose(s);
        if (mt != null) unawaited(mt.send('${rules.legalActions(s).indexOf(act)}', asSeat: seat));
      }
      final before = s.captured.fold<int>(0, (a, c) => a + c.length);
      rules.apply(s, act);
      final after = s.captured.fold<int>(0, (a, c) => a + c.length);
      ctx.sfx(after > before ? Sfx.coin : Sfx.place);
      setState(() {});
    }
    _busy = false;
    _persist();
    if (s.over) {
      _end();
    } else {
      setState(_maybeCover);
    }
  }

  void _human(TAction a) {
    if (_ended || _busy || !_isLocal(s.turn) || s.over || _cover) return;
    final legal = rules.legalActions(s);
    if (!legal.contains(a)) {
      ctx.sfx(Sfx.error);
      return;
    }
    unawaited(_match?.send('${legal.indexOf(a)}'));
    _undo.add(s.serialize());
    final who = s.turn;
    final before = s.captured[who].length;
    rules.apply(s, a);
    ctx.sfx(s.captured[who].length > before ? Sfx.coin : Sfx.place);
    setState(() {
      _hint = null;
      _selected.clear();
      _maybeCover();
    });
    _persist();
    if (s.over) {
      _end();
    } else {
      _advance();
    }
  }

  void _tapCard(KCard c) {
    if (_ended || _busy || !_isLocal(s.turn) || _cover) return;
    final legal = rules.legalActions(s);
    final plays = legal.where((a) => a.cards.length == 1 && a.cards.first == c).toList();
    final multi = legal.any((a) => a.cards.length > 1 && a.cards.contains(c));
    if (plays.length == 1 && !multi) {
      _human(plays.first);
      return;
    }
    setState(() => _selected.contains(c) ? _selected.remove(c) : _selected.add(c));
  }

  void _doUndo() {
    if (_undo.isEmpty || _busy || _ended || _match != null || ctx.passAndPlay) return;
    setState(() {
      s = TableState.fromJson(_undo.removeLast());
      _undos++;
      _hint = null;
      _selected.clear();
    });
    _persist();
  }

  Future<void> _useHint() async {
    if (_ended || _busy || !_isLocal(s.turn) || _cover || !await ctx.requestHint()) return;
    _hints++;
    final adv = TableAI(rules, 20, SeededRandom(mixSeed([level.seed, _seconds, 5])));
    setState(() => _hint = adv.choose(s));
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
      final sc = rules.finalScores(s);
      var w = 0;
      for (var i = 1; i < sc.length; i++) {
        if (sc[i] > sc[w]) w = i;
      }
      final tie = [for (var i = 0; i < sc.length; i++) if (sc[i] == sc[w]) i].length > 1;
      final team = rules.partnerships ? {w, (w + 2) % s.seats} : {w};
      final iWon = !tie && (_match != null ? team.contains(_match!.mySeat) : true);
      ctx.sfx(iWon ? Sfx.win : Sfx.lose);
      unawaited(_match?.finish(tie ? -1 : w, iWon: iWon));
      ctx.finish(RoundResult(
        won: iWon,
        score: iWon ? 300 : 30,
        seconds: _seconds,
        headline: tie ? ctx.t('draw_title') : (_match != null ? null : ctx.t('player_wins', {'n': w + 1})),
        gameStats: {'games_won': iWon ? 1 : 0},
      ));
      return;
    }
    final won = level.goal.check(rules, s);
    ctx.sfx(won ? Sfx.win : Sfx.lose);
    ctx.finish(RoundResult(
      won: won,
      score: math.max(0, (rules.utility(s, 0) * 5).round() + s.captured[0].length * 5 + (won ? 300 : 0)),
      stars: TableGameRules.stars(won: won, hints: _hints, undos: _undos),
      seconds: _seconds,
      moves: _undo.length,
      hintsUsed: _hints,
      undosUsed: _undos,
      gameStats: {'cards_won': s.captured[0].length, 'games_won': won ? 1 : 0},
    ));
  }

  CardStyle get _style => CardStyle(
        backA: ctx.pieceColors.isNotEmpty ? ctx.pieceColors[0] : const Color(0xFF1F5E8C),
        backB: ctx.pieceColors.length > 1 ? ctx.pieceColors[1] : const Color(0xFF2BB3B1),
        colorBlind: ctx.colorBlind,
        spanish: rules.spanishDeck,
      );

  Widget _card(KCard c, double w, {bool up = true, bool dim = false, bool hl = false}) => SizedBox(
        width: w,
        height: w * rules.tileAspect,
        child: CustomPaint(painter: _CardP(c, up, _style, dim, hl, rules.tileStyle)),
      );

  String _seatName(int seat) {
    if (_multi && (ctx.passAndPlay || ctx.role(seat) != SeatRole.ai)) {
      return seat == me && _match != null ? Strings.tx(ctx.lang, 'Sen', 'You') : ctx.seatName(seat);
    }
    seat = (seat - me + s.seats) % s.seats;
    if (seat == 0) return Strings.tx(ctx.lang, 'Sen', 'You');
    if (s.seats == 2) return Strings.tx(ctx.lang, 'Karşı', 'Across');
    if (rules.partnerships && seat == 2) return Strings.tx(ctx.lang, 'Eşin', 'Partner');
    return ['', Strings.tx(ctx.lang, 'Sol', 'Left'), Strings.tx(ctx.lang, 'Karşı', 'Across'), Strings.tx(ctx.lang, 'Sağ', 'Right')][seat % 4];
  }

  Widget _badge(int seat) {
    final active = s.turn == seat && !s.over;
    return StudioSeatBadge(
      title: _seatName(seat),
      active: active,
      detail: '${seat != me ? '🂠${s.hands[seat].length}  ' : ''}'
          '${Strings.tx(ctx.lang, 'Puan', 'Points')}: ${rules.finalScores(s)[seat]}',
    );
  }

  Widget _pile(int i, double cw) {
    final pv = rules.pileViews[i];
    final p = s.piles[i];
    final label = pv.labels != null ? Strings.pick(pv.labels!, ctx.lang) : Strings.tx(ctx.lang, pv.trLabel, pv.enLabel);
    Widget body;
    if (p.isEmpty) {
      body = SizedBox(
        width: cw,
        height: cw * rules.tileAspect,
        child: CustomPaint(painter: _SlotP()),
      );
    } else if (pv.spread) {
      final show = p.length > pv.maxShown ? p.sublist(p.length - pv.maxShown) : p;
      final small = pv.maxShown > 12 ? cw * 0.55 : cw * 0.8;
      body = Wrap(spacing: pv.maxShown > 12 ? 2 : 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
        for (final c in show) _card(c, small, up: pv.faceUp),
      ]);
    } else {
      body = Stack(clipBehavior: Clip.none, children: [
        if (p.length > 1) Transform.translate(offset: const Offset(3, 3), child: _card(p[p.length - 2], cw, up: pv.faceUp)),
        _card(p.last, cw, up: pv.faceUp),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      body,
      const SizedBox(height: 2),
      Text('$label · ${p.length}', style: const TextStyle(color: kStudioTextDim, fontSize: 11.5, fontWeight: FontWeight.w700)),
    ]);
  }

  /// Okey/remi taşları için iki katlı ahşap ıstaka: taşlar tek sıraya
  /// sıkışmaz, rakamlar büyük ve okunur kalır.
  Widget _rack(TableState s, int me, double w, double h, List<TAction> legal, Set<KCard> playable) {
    final cards = s.hands[me];
    final k = cards.length;
    final perRow = (k + 1) ~/ 2;
    final tw = math.min(60.0, math.min((w - 24) / (perRow * 1.04), h * 0.085));
    final th = tw * rules.tileAspect;
    final rowH = th + 10;
    Widget row(int from, int to) => SizedBox(
          height: rowH,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = from; i < to; i++)
              () {
                final c = cards[i];
                final ok = playable.contains(c) || legal.any((a) => a.cards.contains(c));
                final sel = _selected.contains(c);
                final hl = _hint != null && _hint!.cards.contains(c);
                return Padding(
                  padding: EdgeInsets.only(left: tw * 0.02, right: tw * 0.02, bottom: sel ? 8 : 0, top: sel ? 0 : 8),
                  child: GestureDetector(
                    onTap: () => _tapCard(c),
                    child: _card(c, tw, dim: s.turn == me && legal.isNotEmpty && !ok, hl: hl || sel),
                  ),
                );
              }(),
          ]),
        );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFC08A5A), Color(0xFF8A5A36)]),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        row(0, perRow),
        Container(height: 3, color: const Color(0xFF5C3A20)),
        row(perRow, k),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => FeltTable(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final legal = _isLocal(s.turn) && s.turn == me && !s.over && !_busy && !_cover ? rules.legalActions(s) : const <TAction>[];
    final playable = {for (final a in legal) if (a.cards.length == 1) a.cards.first};
    final buttons = legal
        .where((a) => !rules.isCardPlay(a) || (_selected.length == 1 && a.cards.length == 1 && _selected.contains(a.cards.first)))
        .where((a) =>
        a.cards.isEmpty || _selected.isEmpty || a.cards.toSet().containsAll(_selected)).take(16).toList();
    final status = rules.status(s, ctx.lang);
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth, h = cons.maxHeight;
      final n = math.max(1, s.hands[me].length);
      // Büyük yazıda üst/alt yazı satırları uzar: taşlar biraz küçülür ki
      // kısa ekranda (320x568) alt sıra kesilmesin.
      final ts = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
      final cw = math.min(72.0, math.min(w / (n * 0.62 + 0.6), h * 0.15 / ts));
      final pw = math.min(64.0, w * 0.14);
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            Expanded(
                child: Text(level.goal.text(rules, s, ctx.lang),
                    style: const TextStyle(color: kStudioText, fontWeight: FontWeight.w800, fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            StudioTag(
              icon: Icons.timer_outlined,
              text: '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}',
            ),
          ]),
        ),
        if (status.isNotEmpty)
          Text(status,
              style: const TextStyle(color: kStudioTextDim, fontSize: 12.5, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
            for (var k = 1; k < s.seats; k++) _badge((me + k) % s.seats),
          ]),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Wrap(spacing: 14, runSpacing: 10, alignment: WrapAlignment.center, children: [
                for (var i = 0; i < rules.pileViews.length && i < s.piles.length; i++) _pile(i, pw),
              ]),
            ),
          ),
        ),
        if (buttons.isNotEmpty)
          SizedBox(
            height: 52,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), children: [
              for (final a in buttons)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Center(
                    child: StudioChoice(
                      hinted: _hint == a,
                      onPressed: () => _human(a),
                      label: rules.actionLabel(a, ctx.lang),
                    ),
                  ),
                ),
            ]),
          ),
        _badge(me),
        const SizedBox(height: 4),
        if (_cover)
          _CoverCard(
            text: ctx.t('pass_device', {'p': ctx.seatName(_shown)}),
            sub: ctx.t('tap_when_ready'),
            height: cw * rules.tileAspect + 18,
            onTap: () => setState(() => _cover = false),
          )
        else if (rules.tileStyle != kTileCard && s.hands[me].length > 11)
          _rack(s, me, w, h, legal, playable)
        else
        SizedBox(
          height: cw * rules.tileAspect + 18,
          child: LayoutBuilder(builder: (context, c2) {
            final cards = s.hands[me];
            final k = cards.length;
            final step = k <= 1 ? 0.0 : math.min(cw * 0.95, (c2.maxWidth - cw - 8) / (k - 1));
            final left0 = (c2.maxWidth - (cw + step * math.max(0, k - 1))) / 2;
            return Stack(children: [
              for (var i = 0; i < k; i++)
                () {
                  final c = cards[i];
                  final ok = playable.contains(c) || legal.any((a) => a.cards.contains(c));
                  final sel = _selected.contains(c);
                  final hl = _hint != null && _hint!.cards.contains(c);
                  return AnimatedPositioned(
                    key: ValueKey(c),
                    duration: const Duration(milliseconds: 180),
                    left: left0 + step * i,
                    top: sel ? 0 : (ok ? 6 : 16),
                    child: GestureDetector(
                      onTap: () => _tapCard(c),
                      child: _card(c, cw, dim: s.turn == me && legal.isNotEmpty && !ok, hl: hl || sel),
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
                onPressed: _ended || _busy || !_isLocal(s.turn) || _cover ? null : _useHint,
                icon: Icons.lightbulb,
                tooltip: ctx.t('hint')),
            StudioRoundAction(
                onPressed: _undo.isNotEmpty && !_busy && !_ended ? _doUndo : null,
                icon: Icons.undo,
                tooltip: ctx.t('undo')),
          ]),
        ),
      ]);
    });
  }
}

/// Sırayla oynamada eli kapatan kart: "Telefonu Oyuncu 2'ye ver".
class _CoverCard extends StatelessWidget {
  final String text, sub;
  final double height;
  final VoidCallback onTap;
  const _CoverCard({required this.text, required this.sub, required this.height, required this.onTap});

  @override
  Widget build(BuildContext context) => StudioCover(text: text, sub: sub, height: height, onTap: onTap);
}

class _CardP extends CustomPainter {
  final KCard c;
  final bool up, dim, hl;
  final CardStyle style;
  final int tile;
  _CardP(this.c, this.up, this.style, this.dim, this.hl, this.tile);
  @override
  void paint(Canvas canvas, Size size) {
    if (tile == kTileCard) {
      paintCard(canvas, Offset.zero & size, c, faceUp: up, style: style, dim: dim, highlight: hl);
    } else {
      paintTile(canvas, Offset.zero & size, c, tile,
          faceUp: up, backA: style.backA, backB: style.backB, dim: dim, highlight: hl, colorBlind: style.colorBlind);
    }
  }

  @override
  bool shouldRepaint(covariant _CardP o) => o.c != c || o.up != up || o.dim != dim || o.hl != hl || o.style != style || o.tile != tile;
}

class _SlotP extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => paintSlot(canvas, Offset.zero & size);
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Kartları kısa yazıya çevir (düğme etiketleri için).
String cardsLabel(List<KCard> cards) =>
    cards.map((c) => '${rankLabel(rankOf(c))}${const ['♠', '♥', '♦', '♣'][suitOf(c)]}').join(' ');
