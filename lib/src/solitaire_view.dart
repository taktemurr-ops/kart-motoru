import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/strings.dart';

import 'card_painter.dart';
import 'cards.dart';
import 'solitaire_engine.dart';
import 'solitaire_rules.dart';

/// Ekrandaki bir kart.
class _Placed {
  final KCard card;
  final int pile, index;
  final Rect rect;
  final bool up;
  const _Placed(this.card, this.pile, this.index, this.rect, this.up);
}

/// Bütün solitaire oyunlarının ortak oyun ekranı: sürükle-bırak, dokun-gönder,
/// ipucu, geri al, otomatik bitirme.
class SolitaireView extends StatefulWidget {
  final PlayContext ctx;
  const SolitaireView({super.key, required this.ctx});

  @override
  State<SolitaireView> createState() => _SolitaireViewState();
}

class _SolitaireViewState extends State<SolitaireView> {
  late SolLevel level;
  late SolGame game;
  int _seconds = 0, _hints = 0, _undos = 0;
  Timer? _timer;
  bool _ended = false;
  SolMove? _hint;

  // Sürükleme
  int _dragPile = -1, _dragIndex = -1;
  Offset _dragDelta = Offset.zero;
  Offset? _dragStart;

  // Son yerleşim (dokunma testi için)
  List<_Placed> _placed = const [];
  List<Rect> _slots = const [];
  double _cw = 40;

  PlayContext get ctx => widget.ctx;
  SolitaireVariant get v => level.variant;

  @override
  void initState() {
    super.initState();
    level = (ctx.generated as GeneratedLevel<SolLevel>).puzzle;
    final snap = ctx.resume['snap'];
    game = snap is String ? SolGame.restore(v, level.start, snap) : SolGame(v, level.start);
    _seconds = (ctx.resume['secs'] as num?)?.toInt() ?? 0;
    _hints = (ctx.resume['hints'] as num?)?.toInt() ?? 0;
    _undos = (ctx.resume['undos'] as num?)?.toInt() ?? 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_ended && mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _persist() => ctx.saveResume({'snap': game.serialize(), 'secs': _seconds, 'hints': _hints, 'undos': _undos});

  CardStyle get _style => CardStyle(
        backA: ctx.pieceColors.isNotEmpty ? ctx.pieceColors[0] : const Color(0xFF1F5E8C),
        backB: ctx.pieceColors.length > 1 ? ctx.pieceColors[1] : const Color(0xFF2BB3B1),
        colorBlind: ctx.colorBlind,
      );

  // ---- yerleşim ----

  void _layoutFor(Size size) {
    final l = v.layout;
    // Kart genişliği: genişliğe sığsın; yükseklikte fan için pay kalsın.
    _cw = math.min(size.width / v.boardWidth, size.height / (v.boardHeight + 2.2));
    final cw = _cw, ch = cw * 1.4;
    final ox = (size.width - v.boardWidth * cw) / 2;
    final s = game.s;
    final placed = <_Placed>[];
    final slots = <Rect>[];
    for (var p = 0; p < l.length; p++) {
      final spec = l[p];
      final base = Rect.fromLTWH(ox + spec.x * cw, spec.y * cw, cw, ch);
      slots.add(base);
      final cards = s.piles[p];
      if (cards.isEmpty) continue;
      switch (spec.fan) {
        case Fan.none:
          // Yalnızca üstteki iki kart (animasyon için) yeter; hepsini aynı yere koy.
          for (var i = 0; i < cards.length; i++) {
            placed.add(_Placed(cards[i], p, i, base, s.faceUp(p, i) && spec.kind != PileKind.stock));
          }
        case Fan.right:
          final step = cw * 0.3;
          for (var i = 0; i < cards.length; i++) {
            placed.add(_Placed(cards[i], p, i, base.shift(Offset(step * i, 0)), s.faceUp(p, i)));
          }
        case Fan.rightLast3:
          final first = math.max(0, cards.length - 3);
          for (var i = 0; i < cards.length; i++) {
            final k = math.max(0, i - first);
            placed.add(_Placed(cards[i], p, i, base.shift(Offset(cw * 0.32 * k, 0)), true));
          }
        case Fan.down:
          final avail = size.height - base.top - ch - 4;
          final downN = math.min(s.down[p], cards.length);
          final upN = cards.length - downN;
          var dStep = ch * 0.12, uStep = ch * 0.27;
          final need = downN * dStep + math.max(0, upN - 1) * uStep;
          if (need > avail && need > 0) {
            final k = avail / need;
            dStep *= k;
            uStep *= k;
          }
          var y = base.top;
          for (var i = 0; i < cards.length; i++) {
            placed.add(_Placed(cards[i], p, i, Rect.fromLTWH(base.left, y, cw, ch), s.faceUp(p, i)));
            y += i < downN ? dStep : uStep;
          }
      }
    }
    _placed = placed;
    _slots = slots;
  }

  // ---- etkileşim ----

  _Placed? _hit(Offset pos) {
    for (var i = _placed.length - 1; i >= 0; i--) {
      if (_placed[i].rect.contains(pos)) return _placed[i];
    }
    return null;
  }

  int _slotAt(Offset pos) {
    for (var p = 0; p < _slots.length; p++) {
      if (_slots[p].contains(pos)) return p;
    }
    return -1;
  }

  void _after(bool moved, {bool toFoundation = false}) {
    if (!moved) {
      ctx.sfx(Sfx.error);
      return;
    }
    ctx.sfx(toFoundation ? Sfx.clear : Sfx.place);
    setState(() => _hint = null);
    _persist();
    if (game.won) {
      ctx.sfx(Sfx.win);
      _end();
    } else if (game.stuck) {
      _end();
    }
  }

  bool _isFoundation(int p) => v.layout[p].kind == PileKind.foundation;

  void _tap(Offset pos) {
    if (_ended) return;
    final slot = _slotAt(pos);
    final hit = _hit(pos);
    final stockPile = v.layout.indexWhere((s) => s.kind == PileKind.stock);
    if ((hit != null && hit.pile == stockPile) || (hit == null && slot == stockPile && stockPile >= 0)) {
      _after(game.play(const SolMove.stock()));
      return;
    }
    if (hit == null) return;
    if (!v.canPick(game.s, hit.pile, hit.index)) {
      // Bazı türlerde (Golf, Piramit) dokunulan kart tek başına hedefsizdir.
      ctx.sfx(Sfx.error);
      return;
    }
    final targets = v.tapTargets(game.s, hit.pile, hit.index);
    if (targets.isEmpty) {
      ctx.sfx(Sfx.error);
      return;
    }
    final to = targets.first;
    _after(game.play(SolMove(hit.pile, hit.index, to)), toFoundation: _isFoundation(to));
  }

  void _panStart(DragStartDetails d) {
    if (_ended) return;
    final hit = _hit(d.localPosition);
    if (hit == null || !v.canPick(game.s, hit.pile, hit.index)) return;
    setState(() {
      _dragPile = hit.pile;
      _dragIndex = hit.index;
      _dragStart = d.localPosition;
      _dragDelta = Offset.zero;
    });
  }

  void _panUpdate(DragUpdateDetails d) {
    if (_dragPile < 0) return;
    setState(() => _dragDelta = d.localPosition - _dragStart!);
  }

  void _panEnd(DragEndDetails d) {
    if (_dragPile < 0) return;
    final from = _dragPile, index = _dragIndex;
    final head = _placed.firstWhere((p) => p.pile == from && p.index == index);
    final r = head.rect.shift(_dragDelta);
    var best = -1;
    var bestArea = 0.0;
    for (var p = 0; p < _slots.length; p++) {
      if (p == from || !v.canDrop(game.s, from, index, p)) continue;
      // Hedef bölge: yuva + yığındaki son kart.
      var zone = _slots[p];
      for (final c in _placed) {
        if (c.pile == p) zone = zone.expandToInclude(c.rect);
      }
      final inter = zone.intersect(r);
      if (inter.width <= 0 || inter.height <= 0) continue;
      final area = inter.width * inter.height;
      if (area > bestArea) {
        bestArea = area;
        best = p;
      }
    }
    setState(() {
      _dragPile = -1;
      _dragIndex = -1;
      _dragDelta = Offset.zero;
    });
    if (best >= 0) {
      _after(game.play(SolMove(from, index, best)), toFoundation: _isFoundation(best));
    } else if (_dragDelta.distance > 8) {
      ctx.sfx(Sfx.error);
    }
  }

  Future<void> _useHint() async {
    if (_ended || !await ctx.requestHint()) return;
    final h = game.hint();
    _hints++;
    setState(() => _hint = h);
    _persist();
  }

  Future<void> _autoFinish() async {
    while (mounted && !_ended && v.canAutoFinish(game.s)) {
      SolMove? next;
      for (final m in v.legalMoves(game.s)) {
        if (!m.isStock && _isFoundation(m.to)) {
          next = m;
          break;
        }
      }
      if (next == null) break;
      game.play(next);
      ctx.sfx(Sfx.place);
      setState(() {});
      await Future<void>.delayed(const Duration(milliseconds: 70));
    }
    _persist();
    if (game.won) {
      ctx.sfx(Sfx.win);
      _end();
    }
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    if (!game.won) ctx.sfx(Sfx.lose);
    final prog = v.progress(game.s);
    ctx.finish(RoundResult(
      won: game.won,
      score: prog * 10 + (game.won ? 500 + math.max(0, 600 - _seconds) : 0),
      stars: SolitaireRules.stars(won: game.won, hints: _hints, undos: _undos),
      seconds: _seconds,
      moves: game.moves,
      hintsUsed: _hints,
      undosUsed: _undos,
      gameStats: {'cards_home': prog, 'clean_wins': game.won && _hints == 0 ? 1 : 0},
    ));
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          Expanded(
            child: Text(
                Strings.tx(ctx.lang, 'Yerine giden: {0} / {1}', 'Cards home: {0} / {1}', [v.progress(game.s), v.totalCards]),
                style: Theme.of(context).textTheme.titleSmall),
          ),
          const Icon(Icons.swap_horiz, size: 18),
          Text(' ${game.moves}  '),
          const Icon(Icons.timer_outlined, size: 18),
          Text(' ${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}'),
        ]),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, cons) {
          final size = Size(cons.maxWidth - 8, cons.maxHeight);
          _layoutFor(size);
          final hintFrom = _hint;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _tap(d.localPosition),
              onPanStart: _panStart,
              onPanUpdate: _panUpdate,
              onPanEnd: _panEnd,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(child: CustomPaint(painter: _SlotPainter(this))),
                for (final c in _placed)
                  () {
                    final dragging = _dragPile == c.pile && c.index >= _dragIndex && _dragIndex >= 0;
                    final r = dragging ? c.rect.shift(_dragDelta) : c.rect;
                    final hl = hintFrom != null &&
                        ((!hintFrom.isStock && hintFrom.from == c.pile && c.index == hintFrom.index) ||
                            (hintFrom.isStock && v.layout[c.pile].kind == PileKind.stock && c.index == game.s.piles[c.pile].length - 1));
                    return AnimatedPositioned(
                      key: ValueKey(c.card),
                      duration: dragging || ctx.reducedMotion ? Duration.zero : const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      left: r.left,
                      top: r.top,
                      width: r.width,
                      height: r.height,
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _CardPainter(c.card, c.up, style, hl),
                        ),
                      ),
                    );
                  }(),
              ]),
            ),
          );
        }),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          IconButton.filledTonal(onPressed: _ended ? null : _useHint, icon: const Icon(Icons.lightbulb), tooltip: ctx.t('hint')),
          IconButton.filledTonal(
              onPressed: game.canUndo && !_ended
                  ? () {
                      setState(() {
                        game.undo();
                        _undos++;
                        _hint = null;
                      });
                      _persist();
                    }
                  : null,
              icon: const Icon(Icons.undo),
              tooltip: ctx.t('undo')),
          if (v.canAutoFinish(game.s))
            FilledButton.icon(
              onPressed: _ended ? null : _autoFinish,
              icon: const Icon(Icons.done_all),
              label: Text(Strings.tx(ctx.lang, 'Bitir', 'Finish')),
            ),
        ]),
      ),
    ]);
  }
}

class _SlotPainter extends CustomPainter {
  final _SolitaireViewState v;
  _SlotPainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final l = v.v.layout;
    final h = v._hint;
    for (var p = 0; p < v._slots.length; p++) {
      final spec = l[p];
      if (spec.kind == PileKind.free) continue;
      final r = v._slots[p];
      paintSlot(canvas, r,
          label: spec.kind == PileKind.stock ? '↻' : spec.label, suit: spec.suitHint);
      if (h != null && !h.isStock && h.to == p) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(r.inflate(3), Radius.circular(r.width * 0.12)),
            Paint()
              ..color = const Color(0xFFFFC53D)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _CardPainter extends CustomPainter {
  final KCard card;
  final bool up;
  final CardStyle style;
  final bool highlight;
  _CardPainter(this.card, this.up, this.style, this.highlight);

  @override
  void paint(Canvas canvas, Size size) =>
      paintCard(canvas, Offset.zero & size, card, faceUp: up, style: style, highlight: highlight);

  @override
  bool shouldRepaint(covariant _CardPainter o) => o.card != card || o.up != up || o.highlight != highlight || o.style != style;
}
