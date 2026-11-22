import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  test('Kart Yolu: bölümler çözülebilir, ipucu bitirir', () {
    final rules = TrailRules(gameId: 'oyun-kart-yolu');
    final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
    for (final lv in [1, 2, 40, 900, 5000, 33333, 77777, 99999]) {
      final sw = Stopwatch()..start();
      final gl = rules.build(planner.spec(lv));
      expect(gl.validation.ok, isTrue, reason: 'bölüm $lv');
      final l = gl.puzzle;
      expect(l.cards.toSet().length, l.size);
      final g = TrailGame(l);
      while (!g.won) {
        final h = g.hint();
        expect(h, isNotNull, reason: 'bölüm $lv');
        expect(g.tap(h!), isTrue);
      }
      // ignore: avoid_print
      print('yol $lv d=${gl.spec.difficulty} ${l.cols}x${l.rows} ${l.link} ${sw.elapsedMilliseconds}ms');
    }
  });

  test('Kart Yolu: kayıt geri yüklenir', () {
    final rules = TrailRules(gameId: 'oyun-kart-yolu');
    final gl = rules.build(LevelPlanner(gameId: rules.gameId, optionalMechanics: const []).spec(321));
    final g = TrailGame(gl.puzzle)..tap(gl.puzzle.solution[0])..tap(gl.puzzle.solution[1]);
    final b = TrailGame.restore(gl.puzzle, g.serialize());
    expect(b.path, g.path);
  });

  test('Kart Karesi: bölümler çözülebilir, ipucu bitirir', () {
    final rules = SquareRules(gameId: 'oyun-kart-karesi');
    final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
    for (final lv in [1, 2, 40, 900, 5000, 33333, 77777, 99999]) {
      final sw = Stopwatch()..start();
      final gl = rules.build(planner.spec(lv));
      expect(gl.validation.ok, isTrue, reason: 'bölüm $lv');
      final l = gl.puzzle;
      expect(l.cards.toSet().length, l.n * l.n);
      final g = SquareGame(l);
      var guard = 0;
      while (!g.won && guard++ < 100) {
        final h = g.hint();
        expect(h, isNotNull, reason: 'bölüm $lv');
        g.put(h!.$1, h.$2);
      }
      expect(g.won, isTrue, reason: 'bölüm $lv');
      final b = SquareGame.restore(l, g.serialize());
      expect(b.grid, g.grid);
      // ignore: avoid_print
      print('kare $lv d=${gl.spec.difficulty} n=${l.n} need=${l.required}/${l.lineCount} ${sw.elapsedMilliseconds}ms');
    }
  });
}
