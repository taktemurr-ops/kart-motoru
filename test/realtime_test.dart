import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  for (final kind in RtKind.values) {
    test('${kind.name}: hızlı oyuncu kazanabiliyor, oyun biter', () {
      final rules = RealtimeRules(gameId: 'rt-${kind.name}', kind: kind);
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
      for (final lv in [1, 300, 9999, 49999]) {
        final sw = Stopwatch()..start();
        final gl = rules.build(planner.spec(lv));
        expect(gl.validation.ok, isTrue, reason: '${kind.name} $lv');
        final g = RtGame.create(gl.puzzle);
        var guard = 0;
        while (!g.over && guard++ < 40000) {
          g.botAct();
          g.advance(20);
        }
        expect(g.over, isTrue);
        // ignore: avoid_print
        print('${kind.name} $lv d=${gl.spec.difficulty} attempts=${gl.attempts} ${sw.elapsedMilliseconds}ms '
            't=${g.time} you=${g.playerScore} ai=${g.aiScore} won=${g.playerWon}');
      }
    });
  }
}
