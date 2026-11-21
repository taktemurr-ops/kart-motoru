import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  final games = <String, TableGameRules>{
    'pisti': TableGameRules(gameId: 'pisti', rulesFor: (_) => const PistiRules()),
    'scopa': TableGameRules(gameId: 'scopa', rulesFor: (_) => const ScopaRules()),
    'cassino': TableGameRules(gameId: 'cassino', rulesFor: (_) => const CassinoRules()),
    'renk': TableGameRules(gameId: 'renk', rulesFor: (_) => const ColorMatchRules()),
    'savas': TableGameRules(gameId: 'savas', rulesFor: (_) => const WarRules()),
    'baskan': TableGameRules(gameId: 'baskan', rulesFor: (_) => const PresidentRules()),
    'papaz': TableGameRules(gameId: 'papaz', rulesFor: (_) => const OldMaidRules()),
    'balik': TableGameRules(gameId: 'balik', rulesFor: (_) => const GoFishRules()),
    'blof': TableGameRules(gameId: 'blof', rulesFor: (_) => const CheatRules()),
    '31': TableGameRules(gameId: '31', rulesFor: (_) => const ThirtyOneRules()),
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
}
