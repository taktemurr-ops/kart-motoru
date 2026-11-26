import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

void main() {
  group('Çinçon', () {
    test('İspanyol destesi: 40 kart, seri sırası 7 → 10', () {
      final d = const ChinchonRules().deck();
      expect(d.length, 40);
      expect(d.toSet().length, 40);
      expect(ChinchonRules.ord(makeCard(11, kHearts)), 8);
      expect(ChinchonRules.isRun([makeCard(6, kHearts), makeCard(7, kHearts), makeCard(11, kHearts)]), isTrue);
      expect(ChinchonRules.isRun([makeCard(7, kHearts), makeCard(11, kHearts), makeCard(13, kHearts)]), isFalse);
      expect(ChinchonRules.value(makeCard(12, kClubs)), 10);
    });
    test('kapatma: ölü kartlar 3 ya da altı; Çinçon yedi kartlık seri', () {
      final h = [
        makeCard(1, kSpades), makeCard(2, kSpades), makeCard(3, kSpades), //
        makeCard(5, kHearts), makeCard(5, kClubs), makeCard(5, kDiamonds), makeCard(2, kHearts),
      ];
      expect(ChinchonRules.deadwood(h), 2);
      const r = ChinchonRules();
      expect(r.canClose(h), isTrue);
      final run = [for (final k in [1, 2, 3, 4, 5, 6, 7]) makeCard(k, kClubs)];
      expect(ChinchonRules.chinchon(run), isTrue);
      expect(ChinchonRules.deadwood(run), 0);
    });
    for (final n in [2, 4]) {
      test('$n kişi: el biter, en az ceza kazanır', () {
        final r = ChinchonRules(n);
        final rnd = SeededRandom(n * 3);
        final deck = r.deck();
        shuffleCards(deck, rnd);
        final s = r.deal(deck, 0);
        var guard = 0;
        while (!s.over && guard++ < 3000) {
          final l = r.legalActions(s);
          final a = r.quick(s, rnd);
          expect(l.contains(a), isTrue);
          r.apply(s, a);
        }
        expect(s.over, isTrue);
        expect(r.matchPoints(s).length, n);
        expect(TableState.fromJson(s.serialize()).serialize(), s.serialize());
      });
    }
  });

  group('Burako', () {
    test('perler: ayak, merdiven, tek joker', () {
      expect(BurakoRules.validMeld([makeCard(5, 0), makeCard(5, 1, 1), makeCard(5, 3)]), isTrue);
      expect(BurakoRules.validMeld([makeCard(5, 0), makeCard(6, 0), makeCard(7, 0)]), isTrue);
      expect(BurakoRules.validMeld([makeCard(5, 0), makeCard(2, 1), makeCard(7, 0)]), isTrue);
      expect(BurakoRules.validMeld([makeCard(5, 0), makeCard(2, 1), makeCard(2, 2), makeCard(8, 0)]), isFalse);
      expect(BurakoRules.validMeld([makeCard(12, 0), makeCard(13, 0), makeCard(1, 0)]), isTrue);
      expect(BurakoRules.validMeld([makeCard(5, 0), makeCard(6, 1), makeCard(7, 0)]), isFalse);
      final h = [makeCard(4, 2), makeCard(5, 2), makeCard(6, 2), makeCard(9, 1), makeCard(9, 3), makeCard(2, 0)];
      final ms = BurakoRules.newMelds(h);
      expect(ms.any((m) => m.length == 3 && m.contains(makeCard(4, 2))), isTrue);
      expect(ms.any((m) => m.contains(makeCard(9, 1)) && m.contains(makeCard(2, 0))), isTrue);
      expect(BurakoRules.meldPoints([for (var k = 3; k <= 9; k++) makeCard(k, 1)]), 5 * 5 + 2 * 10 + 200);
    });
    test('el biter, puanlar tutarlı', () {
      const r = BurakoRules();
      for (final seed in [1, 2, 3]) {
        final rnd = SeededRandom(seed);
        final deck = r.deck();
        shuffleCards(deck, rnd);
        final s = r.deal(deck, 0);
        expect(s.piles[BurakoRules.deadIx(0)].length, 11);
        var guard = 0;
        while (!s.over && guard++ < 6000) {
          final l = r.legalActions(s);
          final a = r.quick(s, rnd);
          expect(l.contains(a), isTrue);
          r.apply(s, a);
          for (var p = 0; p < 2; p++) {
            for (final m in r.meldsOf(s, p)) {
              expect(BurakoRules.validMeld(m), isTrue);
            }
          }
        }
        expect(s.over, isTrue);
        expect(TableState.fromJson(s.serialize()).serialize(), s.serialize());
      }
    });
  });

  group('Doppelkopf', () {
    test('deste, kozlar ve takımlar', () {
      const r = DoppelkopfRules();
      final d = r.deck();
      expect(d.length, 48);
      expect(d.fold<int>(0, (a, c) => a + r.cardPoints(c)), 240);
      expect(d.where(DoppelkopfRules.trumpCard).length, 26);
      expect(r.strength(makeCard(10, kHearts)) > r.strength(makeCard(12, kClubs)), isTrue);
      expect(r.strength(makeCard(11, kDiamonds)) > r.strength(makeCard(1, kDiamonds)), isTrue);
      final s = r.deal(d, 0);
      expect(s.hands.every((h) => h.length == 12), isTrue);
      final re = [for (var p = 0; p < 4; p++) if (r.re(s, p)) p];
      expect(re.length == 2 || s.declarer >= 0, isTrue);
    });
  });

  final tables = <String, TableGameRules>{
    'cincon': TableGameRules(gameId: 'cincon', rulesFor: (d) => ChinchonRules(d <= 4 ? 2 : (d <= 7 ? 3 : 4))),
    'burako': TableGameRules(gameId: 'burako', rulesFor: (_) => const BurakoRules(), aiScale: 0.1, quickValidate: true),
  };
  tables.forEach((name, rules) {
    test('$name: bölümler üretilir', () {
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
      for (final lv in [1, 250, 9999]) {
        final gl = rules.build(planner.spec(lv));
        expect(gl.validation.ok, isTrue, reason: '$name $lv');
        final end = TableGameRules.simulate(gl.puzzle, quick: true);
        expect(end.over, isTrue);
      }
    }, timeout: const Timeout(Duration(minutes: 8)));
  });

  test('doppelkopf: bölümler üretilir, el oynanır', () {
    final rules = TrickGameRules(gameId: 'doppelkopf', rulesFor: (_) => const DoppelkopfRules());
    final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
    for (final lv in [1, 250, 9999]) {
      final gl = rules.build(planner.spec(lv));
      expect(gl.validation.ok, isTrue);
      final end = TrickGameRules.simulate(gl.puzzle);
      expect(end.phase, TrickPhase.over);
      final sc = gl.puzzle.rules.handScores(end);
      expect(sc.fold<int>(0, (a, b) => a + b) == 0 || end.declarer >= 0, isTrue);
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
