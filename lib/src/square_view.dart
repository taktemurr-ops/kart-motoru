import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/strings.dart';

import 'card_painter.dart';
import 'table_theme.dart';
import 'cards.dart';
import 'square.dart';
import 'studio_chrome.dart';

/// Kart Karesi ekranı: üstte ızgara ve çizgi toplamları, altta eldeki kartlar.
class SquareView extends StatefulWidget {
  final PlayContext ctx;
  const SquareView({super.key, required this.ctx});

  @override
  State<SquareView> createState() => _SquareViewState();
}

class _SquareViewState extends State<SquareView> {
  late SquareLevel level;
  late SquareGame game;
  bool _ended = false;
  int _seconds = 0, _hints = 0;
  int? _selCard; // seçili kart (elden ya da ızgaradan)
  (int, int)? _flash;
  Timer? _timer;

  PlayContext get ctx => widget.ctx;

  @override
  void initState() {
    super.initState();
    level = (ctx.generated as GeneratedLevel<SquareLevel>).puzzle;
    final snap = ctx.resume['snap'];
    game = snap is String ? SquareGame.restore(level, snap) : SquareGame(level);
    _seconds = (ctx.resume['secs'] as num?)?.toInt() ?? 0;
    _hints = (ctx.resume['hints'] as num?)?.toInt() ?? 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_ended && mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _persist() => ctx.saveResume({'snap': game.serialize(), 'secs': _seconds, 'hints': _hints});

  CardStyle get _style => kartCardStyle(context, ctx);

  void _after() {
    ctx.sfx(Sfx.place);
    _persist();
    if (game.won) _end();
  }

  void _tapCell(int cell) {
    if (_ended) return;
    final sel = _selCard;
    if (sel != null) {
      setState(() {
        game.put(sel, cell);
        _selCard = null;
        _flash = null;
      });
      _after();
      return;
    }
    if (game.grid[cell] >= 0) {
      ctx.sfx(Sfx.tap);
      setState(() => _selCard = game.grid[cell]);
    }
  }

  void _tapTrayCard(int card) {
    if (_ended) return;
    ctx.sfx(Sfx.tap);
    setState(() => _selCard = _selCard == card ? null : card);
  }

  /// Seçili ızgara kartını ele geri al.
  void _tapTray() {
    final sel = _selCard;
    if (_ended || sel == null) return;
    final cell = game.grid.indexOf(sel);
    if (cell < 0) return;
    setState(() {
      game.lift(cell);
      _selCard = null;
    });
    _persist();
  }

  Future<void> _useHint() async {
    if (_ended || !await ctx.requestHint()) return;
    final h = game.hint();
    if (h == null) return;
    _hints++;
    setState(() {
      game.put(h.$1, h.$2);
      _selCard = null;
      _flash = h;
    });
    _after();
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    ctx.sfx(Sfx.win);
    final all = game.goodLines == level.lineCount;
    final stars = _hints == 0 ? (all ? 3 : 2) : 1;
    ctx.finish(RoundResult(
      won: true,
      score: math.max(10, game.goodLines * 60 - _hints * 40 + (all ? 120 : 0)),
      stars: stars,
      seconds: _seconds,
      moves: game.moves,
      hintsUsed: _hints,
      undosUsed: 0,
      gameStats: {'lines_made': game.goodLines, 'perfect_squares': all ? 1 : 0},
    ));
  }

  Widget _sumChip(List<int> cells, double size) {
    final full = game.lineSum(cells);
    final s = game.partialSum(cells);
    final good = full == level.target;
    final over = s > level.target;
    final look = StudioLook.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: good ? StudioLook.good : (over ? StudioLook.bad : Colors.black.withValues(alpha: 0.38)),
        shape: BoxShape.circle,
        border: Border.all(color: good || over ? Colors.white70 : look.accent.withValues(alpha: 0.6), width: 1.2),
      ),
      child: Text('$s',
          style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: size * 0.42,
              color: good ? const Color(0xFF0B2A12) : (over ? Colors.white : kStudioText))),
    );
  }

  Widget _card(KCard c, double w, {bool hl = false, bool dim = false}) =>
      SizedBox(width: w, height: w * 1.4, child: CustomPaint(painter: _CardP(c, _style, hl, dim)));

  @override
  Widget build(BuildContext context) => FeltTable(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final n = level.n;
    final lines = game.lines;
    final goal = Strings.pick(_tGoal, ctx.lang).replaceAll('{t}', '${level.target}');
    return LayoutBuilder(builder: (context, cons) {
      final tray = game.tray;
      final trayRows = tray.isEmpty ? 0 : 2;
      // Üst bilgi hapı, masa çerçevesi ve yuvarlak düğmeler için pay.
      final availH = cons.maxHeight - 136;
      final gridH = availH * (trayRows == 0 ? 0.92 : 0.66);
      final chip = 30.0;
      var cw = math.min((cons.maxWidth - 24 - chip - 8 * n) / n, (gridH - chip - 8 * n) / n / 1.4);
      cw = math.max(20, cw);
      final ch = cw * 1.4;
      final perRow = math.max(1, (tray.length / 2).ceil());
      var tw = math.min(cw * 0.9, (cons.maxWidth - 16) / perRow - 6);
      tw = math.max(18, math.min(tw, (availH - gridH) / 2 / 1.4 - 6));
      Widget cell(int i) {
        final k = game.grid[i];
        final sel = k >= 0 && k == _selCard;
        return GestureDetector(
          onTap: () => _tapCell(i),
          child: Container(
            margin: const EdgeInsets.all(4),
            width: cw,
            height: ch,
            child: k < 0
                ? CustomPaint(painter: _SlotP())
                : _card(level.cards[k], cw, hl: sel || (_flash != null && _flash!.$2 == i)),
          ),
        );
      }

      return Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Expanded(
              child: Text('$goal · ${Strings.pick(_tLines, ctx.lang)}: ${game.goodLines} / ${level.required}',
                  style: const TextStyle(color: kStudioText, fontWeight: FontWeight.w800, fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            StudioTag(icon: Icons.timer_outlined, text: '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}'),
          ]),
        ),
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (var r = 0; r < n; r++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var c = 0; c < n; c++) cell(r * n + c),
                  const SizedBox(width: 4),
                  _sumChip(lines[r], chip),
                ]),
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (var c = 0; c < n; c++)
                  SizedBox(width: cw + 8, child: Center(child: _sumChip(lines[n + c], chip))),
                const SizedBox(width: 4),
                level.diagonals
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        _sumChip(lines[2 * n], chip * 0.8),
                        const SizedBox(width: 2),
                        _sumChip(lines[2 * n + 1], chip * 0.8),
                      ])
                    : SizedBox(width: chip),
              ]),
            ]),
          ),
        ),
        GestureDetector(
          onTap: _tapTray,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              border: Border.symmetric(horizontal: BorderSide(color: StudioLook.of(context).accent.withValues(alpha: 0.35))),
            ),
            constraints: BoxConstraints(minHeight: tw * 1.4 + 12),
            child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
              for (final k in tray)
                GestureDetector(onTap: () => _tapTrayCard(k), child: _card(level.cards[k], tw, hl: _selCard == k)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            StudioRoundAction(onPressed: _ended ? null : _useHint, icon: Icons.lightbulb, tooltip: ctx.t('hint')),
            StudioTag(icon: Icons.swap_horiz, text: '${Strings.pick(_tMoves, ctx.lang)}: ${game.moves}'),
          ]),
        ),
      ]);
    });
  }
}

class _CardP extends CustomPainter {
  final KCard c;
  final CardStyle style;
  final bool hl, dim;
  _CardP(this.c, this.style, this.hl, this.dim);
  @override
  void paint(Canvas canvas, Size size) => paintCard(canvas, Offset.zero & size, c, faceUp: true, style: style, highlight: hl, dim: dim);
  @override
  bool shouldRepaint(covariant _CardP o) => o.c != c || o.hl != hl || o.dim != dim || o.style != style;
}

class _SlotP extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => paintSlot(canvas, Offset.zero & size);
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// tr en de es fr ar fa he ur ru uk pl cs ro hu el it pt nl sv da nb fi ja ko zh hi bn id ms th vi fil
const _tGoal = ['Çizgi toplamı {t}', 'Line total {t}', 'Liniensumme {t}', 'Suma de línea {t}', 'Total de ligne {t}', 'مجموع الخط {t}', 'جمع خط {t}', 'סכום שורה {t}', 'لائن کا مجموعہ {t}', 'Сумма линии {t}', 'Сума лінії {t}', 'Suma linii {t}', 'Součet řady {t}', 'Totalul liniei {t}', 'Vonalösszeg {t}', 'Άθροισμα γραμμής {t}', 'Totale linea {t}', 'Total da linha {t}', 'Lijntotaal {t}', 'Radsumma {t}', 'Liniesum {t}', 'Linjesum {t}', 'Rivin summa {t}', 'ライン合計 {t}', '줄 합계 {t}', '每行合计 {t}', 'पंक्ति योग {t}', 'সারির যোগফল {t}', 'Jumlah baris {t}', 'Jumlah barisan {t}', 'ผลรวมแถว {t}', 'Tổng hàng {t}', 'Kabuuan ng linya {t}'];
const _tLines = ['Çizgi', 'Lines', 'Linien', 'Líneas', 'Lignes', 'الخطوط', 'خط‌ها', 'שורות', 'لائنیں', 'Линии', 'Лінії', 'Linie', 'Řady', 'Linii', 'Vonalak', 'Γραμμές', 'Linee', 'Linhas', 'Lijnen', 'Rader', 'Linjer', 'Linjer', 'Rivit', 'ライン', '줄', '行', 'पंक्तियाँ', 'সারি', 'Baris', 'Barisan', 'แถว', 'Hàng', 'Linya'];
const _tMoves = ['Hamle', 'Moves', 'Züge', 'Jugadas', 'Coups', 'الحركات', 'حرکت', 'מהלכים', 'چالیں', 'Ходы', 'Ходи', 'Ruchy', 'Tahy', 'Mutări', 'Lépés', 'Κινήσεις', 'Mosse', 'Jogadas', 'Zetten', 'Drag', 'Træk', 'Trekk', 'Siirrot', '手数', '이동', '步数', 'चालें', 'চাল', 'Langkah', 'Langkah', 'ตา', 'Lượt', 'Galaw'];
