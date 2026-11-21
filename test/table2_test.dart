import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  final games = <String, TableGameRules>{
    'gin': TableGameRules(gameId: 'gin', rulesFor: (_) => const GinRummyRules()),
    'remi': TableGameRules(gameId: 'remi', rulesFor: (_) => const RummyRules()),
    'konken': TableGameRules(gameId: 'konken', rulesFor: (_) => const RummyRules(players: 3, handSize: 13, decks: 2, openMin: 51)),
    'asamali': TableGameRules(
        gameId: 'asamali', rulesFor: (d) => RummyRules(players: 3, handSize: 10, contract: d <= 3 ? const [false, false] : (d <= 6 ? const [false, true] : const [true, true]))),
    'kanasta': TableGameRules(gameId: 'kanasta', rulesFor: (_) => const CanastaRules()),
    'elayak': TableGameRules(gameId: 'elayak', rulesFor: (_) => const CanastaRules(handAndFoot: true)),
    'cribbage': TableGameRules(gameId: 'cribbage', rulesFor: (_) => const CribbageRules()),
    'durak': TableGameRules(gameId: 'durak', rulesFor: (_) => const DurakRules()),
  };

  games.forEach((name, rules) {
    test('$name: bölümler üretilir ve oyun biter', () {
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
      for (final lv in [1, 250, 9999, 49999]) {
        final sw = Stopwatch()..start();
        final gl = rules.build(planner.spec(lv));
        expect(gl.validation.ok, isTrue, reason: '$name $lv');
        final end = TableGameRules.simulate(gl.puzzle);
        expect(end.over, isTrue, reason: '$name $lv');
        final back = TableState.fromJson(end.serialize());
        expect(back.serialize(), end.serialize());
        // ignore: avoid_print
        print('$name $lv d=${gl.spec.difficulty} attempts=${gl.attempts} ${sw.elapsedMilliseconds}ms scores=${gl.puzzle.rules.finalScores(end)}');
      }
    });
  });

  test('per ve ölü kart hesapları', () {
    final h = [
      makeCard(3, kHearts), makeCard(4, kHearts), makeCard(5, kHearts), //
      makeCard(9, kSpades), makeCard(9, kClubs), makeCard(9, kDiamonds),
      makeCard(13, kClubs), makeCard(1, kSpades),
    ];
    expect(deadwood(h), 11);
    expect(isRunMeld([makeCard(12, 0), makeCard(13, 0), makeCard(1, 0)]), isTrue);
    expect(isSetMeld([makeCard(5, 0), makeCard(5, 1), makeCard(5, 1)]), isFalse);
  });

  test('cribbage el puanı', () {
    // 5-5-5-J + 5 (J aynı renk): 29
    final hand = [makeCard(5, kHearts), makeCard(5, kSpades), makeCard(5, kDiamonds), makeCard(11, kClubs)];
    expect(cribHandScore(hand, makeCard(5, kClubs)), 29);
  });
}
