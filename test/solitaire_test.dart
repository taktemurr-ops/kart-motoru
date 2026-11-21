import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

SolitaireRules rulesFor(String id, SolitaireVariant Function(int) v,
        {SolState Function(SolitaireVariant, SeededRandom)? deal, bool Function(SolLevel)? check, int cap = 25000}) =>
    SolitaireRules(
      gameId: id,
      variantFor: v,
      dealOverride: deal,
      customCheck: check,
      nodeCap: cap,
    );

void playOut(SolitaireRules rules, int lv) {
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
  final sw = Stopwatch()..start();
  final gl = rules.build(planner.spec(lv));
  final ms = sw.elapsedMilliseconds;
  expect(gl.validation.ok, isTrue, reason: '${rules.gameId} $lv');
  expect(gl.spec.difficulty, planner.spec(lv).difficulty, reason: '${rules.gameId} $lv kolaylaştırıldı');
  final l = gl.puzzle;
  final g = SolGame(l.variant, l.start);
  if (rules.customCheck == null) {
    final sol = solveSolitaire(l.variant, l.start, nodeCap: rules.nodeCap).moves!;
    for (final m in sol) {
      expect(g.play(m), isTrue, reason: '${rules.gameId} $lv $m');
    }
  } else {
    while (!g.won) {
      final m = g.v.legalMoves(g.s);
      expect(m, isNotEmpty);
      g.play(m.first);
    }
  }
  expect(g.won, isTrue, reason: '${rules.gameId} $lv');
  // ignore: avoid_print
  print('${rules.gameId} level $lv d=${gl.spec.difficulty} attempts=${gl.attempts} ${ms}ms');
}

void main() {
  final all = <SolitaireRules>[
    rulesFor('klondike', klondike),
    rulesFor('freecell', freeCell),
    rulesFor('spider', spider, cap: 40000),
    rulesFor('yukon', yukon),
    rulesFor('scorpion', scorpion),
    rulesFor('forty', fortyThieves),
    rulesFor('canfield', canfield),
    rulesFor('pyramid', (d) => PyramidVariant(redealsAllowed: d >= 9 ? 1 : 2)),
    rulesFor('tripeaks', (d) => TriPeaksVariant(wrap: d < 8)),
    rulesFor('golf', (d) => GolfVariant(wrap: d < 7), cap: 60000),
    rulesFor('accordion', (d) => AccordionVariant(target: (12 - d).clamp(3, 11))),
    rulesFor('clock', (d) => ClockVariant(), deal: (v, r) => clockDeal(v, r), check: (l) => (l.variant as ClockVariant).wins(l.start)),
  ];

  for (final r in all) {
    test('${r.gameId}: bölümler çözülür', () {
      for (final lv in [1, 150, 2400, 7777, 31313, 49999, 64000, 99999]) {
        playOut(r, lv);
      }
    });
  }

  test('geri al ve kayıt', () {
    final r = rulesFor('klondike', klondike);
    final planner = LevelPlanner(gameId: r.gameId, optionalMechanics: const []);
    final l = r.build(planner.spec(10)).puzzle;
    final g = SolGame(l.variant, l.start);
    final before = g.serialize();
    final m = g.v.legalMoves(g.s).first;
    expect(g.play(m), isTrue);
    final restored = SolGame.restore(l.variant, l.start, g.serialize());
    expect(restored.s.key(), g.s.key());
    g.undo();
    expect(SolGame.restore(l.variant, l.start, before).s.key(), g.s.key());
  });

  testWidgets('kart çizimi hatasız', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Wrap(children: [
        for (final c in [0, 10, 11, 12, 13, 26, 39, 51])
          SizedBox(
            width: 60,
            height: 84,
            child: CustomPaint(
                painter: _P(c, c.isEven),
                size: const Size(60, 84)),
          ),
      ]),
    ));
    expect(t.takeException(), isNull);
  });
}

class _P extends CustomPainter {
  final int c;
  final bool up;
  _P(this.c, this.up);
  @override
  void paint(Canvas canvas, Size size) =>
      paintCard(canvas, Offset.zero & size, c, faceUp: up, style: const CardStyle());
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
