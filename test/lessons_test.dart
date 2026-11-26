import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';

void main() {
  test('ders yazıları 33 dilde ve dolu', () {
    for (final e in kLessonTexts.entries) {
      expect(e.value.length, 33, reason: e.key);
      for (final s in e.value) {
        expect(s.trim(), isNotEmpty, reason: e.key);
      }
    }
    for (final c in LessonCourse.values) {
      for (final s in buildCourse(c)) {
        expect(kLessonTexts.containsKey(s.title), isTrue, reason: s.title);
        expect(kLessonTexts.containsKey(s.body), isTrue, reason: s.body);
        final t = s.task;
        if (t is PickTilesTask) expect(kLessonTexts.containsKey(t.prompt), isTrue, reason: t.prompt);
        if (t is ChoiceTask) expect(kLessonTexts.containsKey(t.prompt), isTrue, reason: t.prompt);
        if (t is PickGroupsTask) expect(kLessonTexts.containsKey(t.prompt), isTrue, reason: t.prompt);
      }
    }
  });

  test('görevlerin örnek çözümleri motor kurallarıyla doğru', () {
    for (final c in LessonCourse.values) {
      for (final s in buildCourse(c)) {
        final t = s.task;
        if (t is PickTilesTask) {
          final picked = [for (final i in t.solution) t.tiles[i]];
          expect(t.check(picked), isTrue, reason: '${c.name} ${s.title}');
          // Yanlış seçimler kabul edilmez.
          expect(t.check([t.tiles.firstWhere((x) => !picked.contains(x))]), isFalse, reason: '${c.name} ${s.title}');
        }
        if (t is PickGroupsTask) {
          expect(t.check(t.solution.toSet()), isTrue);
          expect(t.check({0, 1, 2, 3, 4}), isFalse, reason: 'geçersiz per seçilince olmaz');
          expect(t.check({2}), isFalse, reason: '101\'e ulaşmaz');
        }
      }
    }
  });

  test('yaku sorusu: el yalnız 2-8, ejder yok, yedi çift değil, tek renk değil', () {
    final kinds = [for (final t in kYakuHand) mjKind(t)];
    expect(kinds.every((k) => !mjTerminalOrHonor(k)), isTrue);
    expect(mjWinning(kYakuHand), isTrue);
    expect(mjSevenPairs(mjCounts(kYakuHand)), isFalse);
    expect({for (final k in kinds) k ~/ 9}.length, greaterThan(1));
    // Motorun Riichi puanlaması da bu eli tanyao (+tsumo) sayar.
    expect(mjHandValue(MahjongStyle.riichi, kYakuHand), greaterThanOrEqualTo(2));
  });

  test('puan soruları oyunun kendi puanlamasıyla', () {
    expect(mjHandValue(MahjongStyle.riichi, kHanHand), 5); // tek renk 3 + ejder 1 + tsumo 1
    expect(mjHandValue(MahjongStyle.hongKong, kFanHand), 8); // tsumo, kapalı, hepsi üçlü 3, doğu x2, çiçeksiz
    expect(mjHandValue(MahjongStyle.classic, kFanHand), 7);
    expect(mjWinning([...kWaitHand, mjTile(mjKindOf('3p'), 1)]), isTrue);
    expect(mjWinning([...kWaitHand, mjTile(mjKindOf('9m'), 1)]), isFalse);
    for (final c in LessonCourse.values) {
      for (final s in buildCourse(c)) {
        final t = s.task;
        if (t is ChoiceTask) {
          expect(t.correct, inInclusiveRange(0, t.options.length - 1));
          expect(t.options[t.correct]('tr'), isNotEmpty);
        }
      }
    }
  });

  test('101: bölüşüm değeri', () {
    int v(List<KCard> t) => okeyBestPartition([for (final x in t) okeyMeaning(x, 999)]);
    expect(v([okeyTile(3, 10), okeyTile(3, 11), okeyTile(3, 12)]), 33);
    expect(v([okeyTile(2, 13), okeyTile(0, 13), okeyTile(1, 13), okeyTile(3, 10), okeyTile(3, 11), okeyTile(3, 12)]), 72);
    expect(v([okeyTile(3, 12), okeyTile(3, 13), okeyTile(3, 1)]), 26); // 12-13-1
    expect(v([okeyTile(3, 13), okeyTile(3, 1), okeyTile(3, 2)]), -1);
    expect(v([okeyTile(3, 5), okeyTile(1, 6), okeyTile(2, 7)]), -1);
    // Jokerle: siyah 9, okey, siyah 11.
    final kind = okeyKindFrom(okeyTile(3, 2));
    expect(okeyBestPartition([for (final x in [okeyTile(2, 9), okeyTile(3, 3), okeyTile(2, 11)]) okeyMeaning(x, kind)]), 30);
  });

  group('koçlu alıştırma elleri', () {
    for (final seed in [11, 21, 31, 41, 51, 7, 99]) {
      test('okey: koçu izleyen eli bitirir ($seed)', () {
        final p = OkeyPractice(seed);
        expect(p.hand.length, 15);
        expect(p.canFinish, isFalse);
        var turns = 0;
        while (!p.won && !p.outOfTiles && turns++ < 30) {
          final t = p.coach();
          expect(p.isGoodDiscard(t), isTrue);
          p.discard(t);
        }
        expect(p.won, isTrue, reason: 'tohum $seed');
      });
      test('mahjong: koçu izleyen eli tamamlar ($seed)', () {
        final p = MahjongPractice(seed);
        expect(p.hand.length, 14);
        var turns = 0;
        while (!p.canWin && !p.outOfTiles && turns++ < 30) {
          final t = p.coach();
          expect(p.isGoodDiscard(t), isTrue);
          p.discard(t);
        }
        expect(p.canWin, isTrue, reason: 'tohum $seed');
      });
      test('101 açılış: örnek çözüm en az 101 ($seed)', () {
        final p = Open101Practice(seed);
        expect(p.hand.length, 22);
        final picked = [for (final g in p.plan) ...g];
        expect(p.value(picked), greaterThanOrEqualTo(101));
        expect(p.value(p.hand.take(2).toList()), -1);
      });
    }
  });

  for (final course in LessonCourse.values) {
    testWidgets('ders ekranı baştan sona ilerler (${course.name})', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: LessonView(course: course, lang: course.index.isEven ? 'tr' : 'ar'))));
      await tester.pump();
      final steps = buildCourse(course);
      for (var i = 0; i < steps.length; i++) {
        expect(tester.takeException(), isNull);
        final t = steps[i].task;
        if (t is PickTilesTask) {
          // İpucu çözümü gösterir; çözüm taşlarını seç.
          await tester.ensureVisible(find.byKey(const ValueKey('task-hint')));
          await tester.tap(find.byKey(const ValueKey('task-hint')));
          await tester.pump();
          final strip = find.byType(TileStrip).last;
          for (final k in t.solution) {
            final f = find.descendant(of: strip, matching: find.byKey(ValueKey('tile-$k')));
            await tester.ensureVisible(f);
            await tester.tap(f);
            await tester.pump();
          }
          if (!t.single) {
            await tester.ensureVisible(find.byKey(const ValueKey('task-check')));
            await tester.tap(find.byKey(const ValueKey('task-check')));
            await tester.pump();
          }
        } else if (t is PickGroupsTask) {
          for (final g in t.solution) {
            await tester.ensureVisible(find.byKey(ValueKey('group-$g')));
            await tester.tap(find.byKey(ValueKey('group-$g')));
            await tester.pump();
          }
          await tester.ensureVisible(find.byKey(const ValueKey('task-check')));
          await tester.tap(find.byKey(const ValueKey('task-check')));
          await tester.pump();
        } else if (t is ChoiceTask) {
          await tester.ensureVisible(find.byKey(ValueKey('choice-${t.correct}')));
          await tester.tap(find.byKey(ValueKey('choice-${t.correct}')));
          await tester.pump();
        } else if (t is PracticeTask) {
          // Koçun ipucunu bir kez kullan, sonra at.
          if (t.kind != PracticeKind.open101) {
            await tester.ensureVisible(find.byKey(const ValueKey('practice-hint')));
            await tester.tap(find.byKey(const ValueKey('practice-hint')));
            await tester.pump();
            await tester.ensureVisible(find.byKey(const ValueKey('practice-discard')));
            await tester.tap(find.byKey(const ValueKey('practice-discard')));
            await tester.pump();
          }
        }
        expect(tester.takeException(), isNull);
        final next = find.byKey(const ValueKey('lesson-next'));
        await tester.tap(next);
        await tester.pump();
      }
      expect(find.byKey(const ValueKey('lesson-restart')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('mod kartı 33 dilde', () {
    final m = lessonMode(LessonCourse.okey);
    expect(m.id, 'ogretici');
    expect(m.title.length, 33);
    expect(m.subtitle.length, 33);
  });
}
