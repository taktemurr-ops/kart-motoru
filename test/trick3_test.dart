import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  final games = <String, TrickGameRules>{
    'euchre': TrickGameRules(gameId: 'euchre', rulesFor: (_) => const EuchreRules()),
    'belote': TrickGameRules(gameId: 'belote', rulesFor: (_) => const BeloteRules()),
    'klaverjas': TrickGameRules(gameId: 'klaverjas', rulesFor: (_) => const BeloteRules(alwaysTrump: true)),
    'jass': TrickGameRules(gameId: 'jass', rulesFor: (_) => const BeloteRules(jass: true)),
    'pinochle': TrickGameRules(gameId: 'pinochle', rulesFor: (_) => const PinochleRules()),
    'skat': TrickGameRules(gameId: 'skat', rulesFor: (_) => const SkatRules()),
    'sheepshead': TrickGameRules(gameId: 'sheepshead', rulesFor: (_) => const SheepsheadRules()),
    'bridge': TrickGameRules(gameId: 'bridge', rulesFor: (_) => const ContractBridgeRules()),
    'bezik': TrickGameRules(gameId: 'bezik', rulesFor: (_) => const BezikRules()),
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
        expect(end.hands.every((h) => h.isEmpty), isTrue);
        final back = TrickState.fromJson(end.toJson());
        expect(back.serialize(), end.serialize());
        // ignore: avoid_print
        print('$name $lv d=${gl.spec.difficulty} attempts=${gl.attempts} ${sw.elapsedMilliseconds}ms '
            'tricks=${end.tricks} scores=${gl.puzzle.rules.handScores(end)} c=${end.contract} t=${end.trump}');
      }
    });
  });

  test('pinochle deklarasyon puanları', () {
    final h = [
      makeCard(1, kHearts), makeCard(10, kHearts), makeCard(13, kHearts), makeCard(12, kHearts), makeCard(11, kHearts), //
      makeCard(12, kSpades), makeCard(11, kDiamonds), makeCard(9, kHearts),
    ];
    // seri 15 + pinochle 4 + dix 1 (koz evliliği seride sayıldı)
    expect(PinochleRules.meld(h, kHearts), 20);
  });

  test('euchre bower', () {
    const r = EuchreRules();
    final s = r.deal(r.deck(), 0)..trump = kHearts;
    expect(r.effSuit(s, makeCard(11, kDiamonds)), kHearts);
    expect(r.beats(s, makeCard(11, kHearts), makeCard(11, kDiamonds), kHearts), isTrue);
    expect(r.beats(s, makeCard(11, kDiamonds), makeCard(1, kHearts), kHearts), isTrue);
  });
}
