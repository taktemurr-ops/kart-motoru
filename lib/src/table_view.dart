import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'card_painter.dart';
import 'tile_painter.dart';
import 'cards.dart';
import 'table_ai.dart';
import 'table_engine.dart';
import 'table_rules.dart';

/// Sıra tabanlı masa oyunlarının ortak ekranı: rakip koltukları, ortadaki
/// yığınlar, oyuncunun eli ve kartsız hamle düğmeleri.
class TableView extends StatefulWidget {
  final PlayContext ctx;
  const TableView({super.key, required this.ctx});

  @override
  State<TableView> createState() => _TableViewState();
}

class _TableViewState extends State<TableView> {
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _persist() => ctx.saveResume({'snap': s.serialize(), 'secs': _seconds, 'hints': _hints});

  Duration get _pace => ctx.reducedMotion ? const Duration(milliseconds: 150) : const Duration(milliseconds: 650);

  Future<void> _advance() async {
    if (_busy) return;
    _busy = true;
    while (mounted && !_ended && !s.over && s.turn != 0) {
      await Future<void>.delayed(_pace);
      if (!mounted) return;
      final before = s.captured.fold<int>(0, (a, c) => a + c.length);
      rules.apply(s, ais[s.turn].choose(s));
      final after = s.captured.fold<int>(0, (a, c) => a + c.length);
      ctx.sfx(after > before ? Sfx.coin : Sfx.place);
      setState(() {});
    }
    _busy = false;
    _persist();
    if (s.over) _end();
  }

  void _human(TAction a) {
    if (_ended || _busy || s.turn != 0 || s.over) return;
    if (!rules.legalActions(s).contains(a)) {
      ctx.sfx(Sfx.error);
      return;
    }
    _undo.add(s.serialize());
    final before = s.captured[0].length;
    rules.apply(s, a);
    ctx.sfx(s.captured[0].length > before ? Sfx.coin : Sfx.place);
    setState(() {
      _hint = null;
      _selected.clear();
    });
    _persist();
    if (s.over) {
      _end();
    } else {
      _advance();
    }
  }

  void _tapCard(KCard c) {
    if (_ended || _busy || s.turn != 0) return;
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
    if (_undo.isEmpty || _busy || _ended) return;
    setState(() {
      s = TableState.fromJson(_undo.removeLast());
      _undos++;
      _hint = null;
      _selected.clear();
    });
    _persist();
  }

  Future<void> _useHint() async {
    if (_ended || _busy || s.turn != 0 || !await ctx.requestHint()) return;
    _hints++;
    final adv = TableAI(rules, 20, SeededRandom(mixSeed([level.seed, _seconds, 5])));
    setState(() => _hint = adv.choose(s));
    _persist();
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
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
      );

  Widget _card(KCard c, double w, {bool up = true, bool dim = false, bool hl = false}) => SizedBox(
        width: w,
        height: w * rules.tileAspect,
        child: CustomPaint(painter: _CardP(c, up, _style, dim, hl, rules.tileStyle)),
      );

  String _seatName(int seat) {
    if (seat == 0) return Strings.tx(ctx.lang, 'Sen', 'You');
    if (s.seats == 2) return Strings.tx(ctx.lang, 'Karşı', 'Across');
    if (rules.partnerships && seat == 2) return Strings.tx(ctx.lang, 'Eşin', 'Partner');
    return ['', Strings.tx(ctx.lang, 'Sol', 'Left'), Strings.tx(ctx.lang, 'Karşı', 'Across'), Strings.tx(ctx.lang, 'Sağ', 'Right')][seat % 4];
  }

  Widget _badge(int seat) {
    final cs = Theme.of(context).colorScheme;
    final active = s.turn == seat && !s.over;
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
        Text(
            '${seat != 0 ? '🂠${s.hands[seat].length}  ' : ''}'
            '${Strings.tx(ctx.lang, 'Puan', 'Points')}: ${rules.finalScores(s)[seat]}',
            style: const TextStyle(fontSize: 12)),
      ]),
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
      Text('$label · ${p.length}', style: Theme.of(context).textTheme.labelSmall),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final legal = s.turn == 0 && !s.over && !_busy ? rules.legalActions(s) : const <TAction>[];
    final playable = {for (final a in legal) if (a.cards.length == 1) a.cards.first};
    final buttons = legal
        .where((a) => !rules.isCardPlay(a) || (_selected.length == 1 && a.cards.length == 1 && _selected.contains(a.cards.first)))
        .where((a) =>
        a.cards.isEmpty || _selected.isEmpty || a.cards.toSet().containsAll(_selected)).take(16).toList();
    final status = rules.status(s, ctx.lang);
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth, h = cons.maxHeight;
      final n = math.max(1, s.hands[0].length);
      final cw = math.min(72.0, math.min(w / (n * 0.62 + 0.6), h * 0.15));
      final pw = math.min(64.0, w * 0.14);
      return Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            Expanded(
                child: Text(level.goal.text(rules, s, ctx.lang),
                    style: Theme.of(context).textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.timer_outlined, size: 18),
            Text(' ${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}'),
          ]),
        ),
        if (status.isNotEmpty) Text(status, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
            for (var p = 1; p < s.seats; p++) _badge(p),
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
            height: 46,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
              for (final a in buttons)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: FilledButton.tonal(
                    style: _hint == a ? FilledButton.styleFrom(backgroundColor: const Color(0xFFFFC53D)) : null,
                    onPressed: () => _human(a),
                    child: Text(rules.actionLabel(a, ctx.lang)),
                  ),
                ),
            ]),
          ),
        _badge(0),
        const SizedBox(height: 4),
        SizedBox(
          height: cw * rules.tileAspect + 18,
          child: LayoutBuilder(builder: (context, c2) {
            final cards = s.hands[0];
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
                      child: _card(c, cw, dim: s.turn == 0 && legal.isNotEmpty && !ok, hl: hl || sel),
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
                onPressed: _ended || _busy || s.turn != 0 ? null : _useHint,
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
