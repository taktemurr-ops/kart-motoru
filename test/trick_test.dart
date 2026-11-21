import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  final games = <String, TrickGameRules>{
    'hearts': TrickGameRules(gameId: 'hearts', rulesFor: (_) => const HeartsRules()),
    'spades': TrickGameRules(gameId: 'spades', rulesFor: (_) => const SpadesRules()),
    'batak': TrickGameRules(gameId: 'batak', rulesFor: (_) => const BatakRules()),
    'batak-esli': TrickGameRules(gameId: 'batak-esli', rulesFor: (_) => const BatakRules(pairs: true)),
    'batak-koz-maca': TrickGameRules(gameId: 'batak-koz-maca', rulesFor: (_) => const BatakRules(spadesTrump: true)),
    'whist': TrickGameRules(gameId: 'whist', rulesFor: (_) => const WhistRules()),
    'ohhell': TrickGameRules(
        gameId: 'ohhell', rulesFor: (d) => OhHellRules(cards: 4 + d ~/ 2), goalFor: (_) => OhHellRules.exact),
    'briscola': TrickGameRules(gameId: 'briscola', rulesFor: (_) => const BriscolaRules()),
    'sueca': TrickGameRules(gameId: 'sueca', rulesFor: (_) => const SuecaRules()),
    'king': TrickGameRules(gameId: 'king', rulesFor: (_) => const KingRules()),
  };

  games.forEach((name, rules) {
    test('$name: bölümler üretilir, el sonuna kadar oynanır, hedef tutar', () {
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
      for (final lv in [1, 250, 9999, 49999]) {
        final sw = Stopwatch()..start();
        final gl = rules.build(planner.spec(lv));
        expect(gl.validation.ok, isTrue, reason: '$name $lv');
        final end = TrickGameRules.simulate(gl.puzzle);
        expect(end.phase, TrickPhase.over, reason: '$name $lv');
        final total = gl.puzzle.rules.deck().length;
        final used = end.played.length + end.kitty.length;
        expect(used, total, reason: '$name $lv kart sayısı');
        // ignore: avoid_print
        print('$name $lv d=${gl.spec.difficulty} attempts=${gl.attempts} ${sw.elapsedMilliseconds}ms tricks=${end.tricks}');
      }
    });
  });

  test('kayıt ve geri yükleme', () {
    final r = games['spades']!;
    final planner = LevelPlanner(gameId: r.gameId, optionalMechanics: const []);
    final l = r.build(planner.spec(12)).puzzle;
    final s = l.start.copy();
    final back = TrickState.fromJson(jsonDecode(s.serialize()) as Map<String, dynamic>);
    expect(back.serialize(), s.serialize());
  });
}

