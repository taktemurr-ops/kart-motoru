import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  test('kart hafıza: bölümler üretilir, çözülür, kayıt geri yüklenir', () {
    final rules = MemoryRules(gameId: 'kart-hafiza');
    final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
    for (final lv in [1, 50, 999, 12345, 77777, 99999]) {
      final g = rules.build(planner.spec(lv));
      expect(g.validation.ok, isTrue, reason: 'bölüm $lv');
      final l = g.puzzle;
      expect(l.cards.length, l.cols * l.rows);
      final game = MemoryGame(l);
      final h = game.hint()!;
      game.pick(h.$1);
      expect(game.pick(h.$2), isTrue);
      final back = MemoryGame.restore(l, game.serialize());
      expect(back.matched, game.matched);
      expect(back.moves, 1);
    }
    for (var d = 1; d <= 10; d++) {
      final g = rules.build(planner.spec(500).copyWith(difficulty: d));
      expect(g.validation.ok, isTrue, reason: 'zorluk $d');
    }
  });
}
