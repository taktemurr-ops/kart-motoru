import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';

import 'cards.dart';
import 'lesson_texts.dart';
import 'lessons.dart';
import 'studio_chrome.dart';
import 'tile_painter.dart';

/// Oyunun ana ekranındaki "Öğretici" mod kartı.
ExtraMode lessonMode(LessonCourse course) => ExtraMode(
      id: 'ogretici',
      title: kLessonTexts['mode']!,
      subtitle: kLessonTexts['mode_d']!,
      icon: Icons.school_rounded,
      color: const Color(0xFF2E9E78),
      builder: (context, lang) => LessonView(course: course, lang: lang),
    );

/// Adım adım ders ekranı.
class LessonView extends StatefulWidget {
  final LessonCourse course;
  final String lang;
  const LessonView({super.key, required this.course, required this.lang});

  @override
  State<LessonView> createState() => _LessonViewState();
}

class _LessonViewState extends State<LessonView> {
  late final List<LessonStep> steps = buildCourse(widget.course);
  int index = 0;
  final Set<int> _solved = {};
  bool _done = false;

  String t(String key, [Map<String, Object> p = const {}]) => lessonText(key, widget.lang, p);

  LessonStep get step => steps[index];
  bool get _canNext => step.task == null || step.task is PracticeTask || _solved.contains(index);

  void _go(int d) => setState(() {
        if (index + d >= steps.length) {
          _done = true;
        } else {
          index = (index + d).clamp(0, steps.length - 1);
        }
      });

  @override
  Widget build(BuildContext context) => StudioChrome(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final look = StudioLook.of(context);
    if (_done) {
      return Center(
        child: StudioBoardPanel(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.emoji_events_rounded, color: StudioLook.gold, size: 56),
            const SizedBox(height: 8),
            Text(t('done_t'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(t('done_b'), textAlign: TextAlign.center, style: const TextStyle(color: kStudioTextDim)),
            const SizedBox(height: 16),
            StudioButton(
              key: const ValueKey('lesson-restart'),
              icon: Icons.replay_rounded,
              label: t('restart'),
              onPressed: () => setState(() {
                _done = false;
                index = 0;
                _solved.clear();
              }),
            ),
          ]),
        ),
      );
    }
    final s = step;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (index + 1) / steps.length,
                minHeight: 8,
                backgroundColor: Colors.black.withValues(alpha: 0.3),
                color: look.accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          StudioTag(text: '${index + 1}/${steps.length}'),
        ]),
      ),
      Expanded(
        child: ListView(
          key: ValueKey('lesson-step-$index'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            Text(t(s.title), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(t(s.body), style: const TextStyle(fontSize: 15, height: 1.35, color: kStudioText)),
            if (s.tiles.isNotEmpty) ...[
              const SizedBox(height: 14),
              TileStrip(tiles: s.tiles, style: s.style, marked: s.marked),
            ],
            if (s.task != null) ...[
              const SizedBox(height: 16),
              _taskView(s),
            ],
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Row(children: [
          Expanded(
            child: StudioButton(
              key: const ValueKey('lesson-back'),
              icon: Icons.arrow_back_rounded,
              label: t('back'),
              tone: StudioButtonTone.gold,
              onPressed: index > 0 ? () => _go(-1) : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StudioButton(
              key: const ValueKey('lesson-next'),
              icon: Icons.arrow_forward_rounded,
              label: t('next'),
              onPressed: _canNext ? () => _go(1) : null,
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _taskView(LessonStep s) {
    void solved() => setState(() => _solved.add(index));
    final task = s.task!;
    final key = ValueKey('task-$index');
    return switch (task) {
      PickTilesTask() => _PickTilesView(key: key, task: task, style: s.style, t: t, onSolved: solved),
      PickGroupsTask() => _PickGroupsView(key: key, task: task, t: t, onSolved: solved),
      ChoiceTask() => _ChoiceView(key: key, task: task, lang: widget.lang, t: t, onSolved: solved),
      PracticeTask() => _PracticeView(key: key, task: task, t: t, onSolved: solved),
    };
  }
}

// ---- Taş çizimi ---------------------------------------------------------------

class _TileP extends CustomPainter {
  final KCard tile;
  final int style;
  final bool highlight, dim;
  _TileP(this.tile, this.style, this.highlight, this.dim);
  @override
  void paint(Canvas canvas, Size size) =>
      paintTile(canvas, Offset.zero & size, tile, style, faceUp: true, highlight: highlight, dim: dim);
  @override
  bool shouldRepaint(covariant _TileP o) => o.tile != tile || o.highlight != highlight || o.dim != dim;
}

/// Bir sıra taş; dokunulabilir.
class TileStrip extends StatelessWidget {
  final List<KCard> tiles;
  final int style;
  final Set<int> selected;
  final Set<int> marked;
  final Set<int> hinted;
  final void Function(int index)? onTap;
  const TileStrip({super.key, required this.tiles, required this.style, this.selected = const {}, this.marked = const {}, this.hinted = const {}, this.onTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final perRow = tiles.length.clamp(1, style == kTileMahjong ? 9 : 8);
      final w = ((c.maxWidth - (perRow - 1) * 6) / perRow).clamp(26.0, 54.0);
      final h = w * (style == kTileMahjong ? 1.36 : 1.38);
      return Wrap(spacing: 6, runSpacing: 10, children: [
        for (var i = 0; i < tiles.length; i++)
          Semantics(
            button: onTap != null,
            selected: selected.contains(i),
            label: 'tile ${i + 1}',
            child: GestureDetector(
              key: ValueKey('tile-$i'),
              onTap: onTap == null ? null : () => onTap!(i),
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 150),
                offset: Offset(0, selected.contains(i) ? -0.15 : 0),
                child: SizedBox(
                  width: w,
                  height: h,
                  child: CustomPaint(painter: _TileP(tiles[i], style, selected.contains(i) || marked.contains(i) || hinted.contains(i), false)),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}

class _Feedback extends StatelessWidget {
  final String? text;
  final bool good;
  const _Feedback(this.text, this.good);
  @override
  Widget build(BuildContext context) => text == null
      ? const SizedBox(height: 8)
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(good ? Icons.check_circle_rounded : Icons.info_rounded, color: good ? const Color(0xFF8BE28B) : const Color(0xFFFFC46B)),
            const SizedBox(width: 8),
            Expanded(child: Text(text!, style: TextStyle(fontWeight: FontWeight.w700, color: good ? const Color(0xFF8BE28B) : const Color(0xFFFFD9A0)))),
          ]),
        );
}

// ---- Taş seçme -------------------------------------------------------------------

class _PickTilesView extends StatefulWidget {
  final PickTilesTask task;
  final int style;
  final String Function(String, [Map<String, Object>]) t;
  final VoidCallback onSolved;
  const _PickTilesView({super.key, required this.task, required this.style, required this.t, required this.onSolved});
  @override
  State<_PickTilesView> createState() => _PickTilesViewState();
}

class _PickTilesViewState extends State<_PickTilesView> {
  final Set<int> sel = {};
  Set<int> hinted = {};
  String? msg;
  bool good = false, solved = false;

  void _check() {
    final picked = [for (final i in (sel.toList()..sort())) widget.task.tiles[i]];
    final ok = widget.task.check(picked);
    setState(() {
      good = ok;
      msg = widget.t(ok ? 'correct' : 'wrong');
      if (ok) solved = true;
    });
    if (ok) widget.onSolved();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return StudioPanel(
      margin: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.t(task.prompt), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 10),
        TileStrip(
          tiles: task.tiles,
          style: widget.style,
          selected: sel,
          hinted: hinted,
          onTap: solved
              ? null
              : (i) {
                  setState(() {
                    if (task.single) {
                      sel
                        ..clear()
                        ..add(i);
                    } else if (!sel.remove(i)) {
                      sel.add(i);
                    }
                    msg = null;
                  });
                  if (task.single) _check();
                },
        ),
        _Feedback(msg, good),
        if (!solved)
          Wrap(spacing: 10, runSpacing: 8, children: [
            if (!task.single) StudioChoice(key: const ValueKey('task-check'), icon: Icons.check_rounded, label: widget.t('check'), onPressed: sel.isEmpty ? null : _check),
            StudioChoice(
              key: const ValueKey('task-hint'),
              icon: Icons.lightbulb_rounded,
              label: widget.t('hint'),
              onPressed: () => setState(() => hinted = task.solution.toSet()),
            ),
          ]),
      ]),
    );
  }
}

// ---- Grup seçme (101 açılışı) -------------------------------------------------

class _PickGroupsView extends StatefulWidget {
  final PickGroupsTask task;
  final String Function(String, [Map<String, Object>]) t;
  final VoidCallback onSolved;
  const _PickGroupsView({super.key, required this.task, required this.t, required this.onSolved});
  @override
  State<_PickGroupsView> createState() => _PickGroupsViewState();
}

class _PickGroupsViewState extends State<_PickGroupsView> {
  final Set<int> sel = {};
  bool hint = false, good = false, solved = false;
  String? msg;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final look = StudioLook.of(context);
    final total = sel.fold<int>(0, (a, g) => a + (task.value(g) < 0 ? 0 : task.value(g)));
    return StudioPanel(
      margin: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.t(task.prompt), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 10),
        for (var g = 0; g < task.groups.length; g++)
          GestureDetector(
            key: ValueKey('group-$g'),
            onTap: solved
                ? null
                : () => setState(() {
                      if (!sel.remove(g)) sel.add(g);
                      msg = null;
                    }),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: sel.contains(g) ? look.accent.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.2),
                border: Border.all(
                    color: sel.contains(g) || (hint && task.solution.contains(g)) ? look.accent : Colors.white24, width: sel.contains(g) ? 2 : 1),
              ),
              child: Row(children: [
                Expanded(child: TileStrip(tiles: task.groups[g], style: kTileOkey)),
                const SizedBox(width: 8),
                Text(task.value(g) < 0 ? '✗' : '${task.value(g)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ]),
            ),
          ),
        StudioTag(icon: Icons.functions_rounded, text: widget.t('value', {'n': total})),
        _Feedback(msg, good),
        if (!solved)
          Wrap(spacing: 10, runSpacing: 8, children: [
            StudioChoice(
              key: const ValueKey('task-check'),
              icon: Icons.check_rounded,
              label: widget.t('check'),
              onPressed: sel.isEmpty
                  ? null
                  : () {
                      final ok = task.check(sel);
                      setState(() {
                        good = ok;
                        solved = ok;
                        msg = ok ? widget.t('correct') : widget.t(sel.any((g) => task.value(g) < 0) ? 'invalid_group' : 'need_101');
                      });
                      if (ok) widget.onSolved();
                    },
            ),
            StudioChoice(key: const ValueKey('task-hint'), icon: Icons.lightbulb_rounded, label: widget.t('hint'), onPressed: () => setState(() => hint = true)),
          ]),
      ]),
    );
  }
}

// ---- Çoktan seçmeli ------------------------------------------------------------

class _ChoiceView extends StatefulWidget {
  final ChoiceTask task;
  final String lang;
  final String Function(String, [Map<String, Object>]) t;
  final VoidCallback onSolved;
  const _ChoiceView({super.key, required this.task, required this.lang, required this.t, required this.onSolved});
  @override
  State<_ChoiceView> createState() => _ChoiceViewState();
}

class _ChoiceViewState extends State<_ChoiceView> {
  int? picked;
  final Set<int> wrong = {};

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final solved = picked == task.correct;
    return StudioPanel(
      margin: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.t(task.prompt), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < task.options.length; i++)
            StudioChoice(
              key: ValueKey('choice-$i'),
              label: task.options[i](widget.lang),
              selected: picked == i && solved,
              icon: wrong.contains(i) ? Icons.close_rounded : (picked == i && solved ? Icons.check_rounded : null),
              onPressed: solved || wrong.contains(i)
                  ? null
                  : () {
                      setState(() {
                        picked = i;
                        if (i != task.correct) wrong.add(i);
                      });
                      if (i == task.correct) widget.onSolved();
                    },
            ),
        ]),
        _Feedback(picked == null ? null : widget.t(solved ? 'correct' : 'wrong'), solved),
      ]),
    );
  }
}

// ---- Koçlu alıştırma eli -----------------------------------------------------------

class _PracticeView extends StatefulWidget {
  final PracticeTask task;
  final String Function(String, [Map<String, Object>]) t;
  final VoidCallback onSolved;
  const _PracticeView({super.key, required this.task, required this.t, required this.onSolved});
  @override
  State<_PracticeView> createState() => _PracticeViewState();
}

class _PracticeViewState extends State<_PracticeView> {
  OkeyPractice? okey;
  MahjongPractice? mj;
  Open101Practice? open;
  int round = 0;
  int? sel;
  Set<int> hinted = {};
  String? msg;
  bool good = false, finished = false;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    final seed = widget.task.seed + round * 101;
    okey = widget.task.kind == PracticeKind.okey ? OkeyPractice(seed) : null;
    mj = widget.task.kind == PracticeKind.mahjong ? MahjongPractice(seed) : null;
    open = widget.task.kind == PracticeKind.open101 ? Open101Practice(seed) : null;
    sel = null;
    hinted = {};
    msg = null;
    finished = false;
    openSel.clear();
  }

  final Set<int> openSel = {};

  List<KCard> get hand => okey?.hand ?? mj?.hand ?? open!.hand;
  int get style => mj != null ? kTileMahjong : kTileOkey;
  int get stockLeft => okey?.stock.length ?? mj?.stock.length ?? 0;
  bool get outOfTiles => okey?.outOfTiles ?? mj?.outOfTiles ?? false;

  void _win() {
    setState(() {
      finished = true;
      good = true;
      msg = widget.t('won_hand');
    });
    widget.onSolved();
  }

  void _discard() {
    final i = sel;
    if (i == null || finished) return;
    final tile = hand[i];
    if (okey != null) {
      final p = okey!;
      final wasGood = p.isGoodDiscard(tile);
      if (p.discard(tile)) {
        _win();
        return;
      }
      setState(() {
        sel = null;
        hinted = {};
        good = wasGood;
        msg = widget.t(wasGood ? (p.canFinish ? 'can_finish' : 'good_discard') : 'bad_discard');
      });
    } else {
      final p = mj!;
      final wasGood = p.isGoodDiscard(tile);
      p.discard(tile);
      setState(() {
        sel = null;
        hinted = {};
        good = wasGood;
        msg = widget.t(wasGood ? (p.canWin ? 'can_finish' : 'good_discard') : 'bad_discard');
      });
    }
    if (outOfTiles) setState(() => msg = widget.t('out_of_tiles'));
  }

  void _hint() {
    if (open != null) {
      // Seçilmemiş ilk örnek grubu göster.
      final p = open!;
      for (final g in p.plan) {
        final idx = {for (final t in g) p.hand.indexOf(t)};
        if (!idx.every(openSel.contains)) {
          setState(() => hinted = idx);
          return;
        }
      }
      return;
    }
    final tile = okey?.coach() ?? mj!.coach();
    setState(() {
      hinted = {hand.indexOf(tile)};
      sel = hand.indexOf(tile);
    });
  }

  @override
  Widget build(BuildContext context) {
    final indicator = okey?.indicator;
    final last = okey?.lastDrawn ?? mj?.lastDrawn;
    final o = open;
    return StudioPanel(
      margin: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (indicator != null || o != null)
          Row(children: [
            Text('${widget.t('indicator')}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(
              width: 34,
              height: 47,
              child: CustomPaint(painter: _TileP(indicator ?? _indicatorFor(o!.okeyKind), kTileOkey, true, false)),
            ),
            const SizedBox(width: 10),
            if (o == null) StudioTag(icon: Icons.layers_rounded, text: widget.t('draws_left', {'n': stockLeft})),
          ])
        else
          StudioTag(icon: Icons.layers_rounded, text: widget.t('draws_left', {'n': stockLeft})),
        const SizedBox(height: 10),
        TileStrip(
          tiles: hand,
          style: style,
          selected: o != null ? openSel : {if (sel != null) sel!},
          hinted: {...hinted, if (last != null && hand.contains(last)) hand.indexOf(last)},
          onTap: finished || outOfTiles
              ? null
              : (i) => setState(() {
                    if (o != null) {
                      if (!openSel.remove(i)) openSel.add(i);
                    } else {
                      sel = sel == i ? null : i;
                    }
                    msg = null;
                  }),
        ),
        if (o != null) ...[
          const SizedBox(height: 8),
          StudioTag(
              icon: Icons.functions_rounded,
              text: widget.t('value', {'n': () {
                final v = o.value([for (final i in openSel) o.hand[i]]);
                return v < 0 ? '–' : '$v';
              }()})),
        ],
        _Feedback(msg, good),
        Wrap(spacing: 10, runSpacing: 8, children: [
          if (!finished && !outOfTiles && o == null)
            StudioChoice(
              key: const ValueKey('practice-discard'),
              icon: (okey?.canFinish ?? false) && sel != null && okey!.finishesWith(hand[sel!]) ? Icons.flag_rounded : Icons.south_rounded,
              label: widget.t((okey?.canFinish ?? false) && sel != null && okey!.finishesWith(hand[sel!]) ? 'finish' : 'discard'),
              onPressed: sel == null ? null : _discard,
            ),
          if (!finished && (mj?.canWin ?? false))
            StudioChoice(key: const ValueKey('practice-win'), icon: Icons.flag_rounded, label: widget.t('finish'), onPressed: _win),
          if (!finished && o != null)
            StudioChoice(
              key: const ValueKey('practice-open'),
              icon: Icons.flag_rounded,
              label: widget.t('open'),
              onPressed: openSel.isEmpty
                  ? null
                  : () {
                      final v = o.value([for (final i in openSel) o.hand[i]]);
                      if (v >= 101) {
                        _win();
                      } else {
                        setState(() {
                          good = false;
                          msg = widget.t(v < 0 ? 'invalid_group' : 'need_101');
                        });
                      }
                    },
            ),
          if (!finished && !outOfTiles)
            StudioChoice(key: const ValueKey('practice-hint'), icon: Icons.lightbulb_rounded, label: widget.t('hint'), onPressed: _hint),
          if (finished || outOfTiles)
            StudioChoice(
              key: const ValueKey('practice-again'),
              icon: Icons.replay_rounded,
              label: widget.t('restart'),
              onPressed: () => setState(() {
                round++;
                _reset();
              }),
            ),
        ]),
      ]),
    );
  }

  /// Okey türünü gösteren gösterge taşı (okey bir küçüğü).
  static KCard _indicatorFor(int kind) {
    final c = kind ~/ 13, n = kind % 13; // n: okeyin sayısı - 1
    return c * 13 + (n + 12) % 13;
  }
}
