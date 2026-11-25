import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  final games = <String, TrickGameRules>{
    'tarneeb': TrickGameRules(gameId: 'oyun-tarneeb', rulesFor: (_) => const TarneebRules()),
    'hokm': TrickGameRules(gameId: 'oyun-hokm', rulesFor: (_) => const HokmRules()),
    'baloot': TrickGameRules(gameId: 'oyun-baloot', rulesFor: (_) => const BalootRules()),
    '29': TrickGameRules(gameId: 'oyun-yirmi-dokuz', rulesFor: (_) => const TwentyNineRules()),
  };

  games.forEach((name, rules) {
    test('$name: bölümler üretilir, el sonuna kadar oynanır, hedef tutar', () {
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
      for (final lv in [1, 250, 9999, 49999, 99999]) {
        final gl = rules.build(planner.spec(lv));
        expect(gl.validation.ok, isTrue, reason: '$name $lv');
        final end = TrickGameRules.simulate(gl.puzzle);
        expect(end.phase, TrickPhase.over, reason: '$name $lv');
        expect(gl.puzzle.goal.check(gl.puzzle.rules, end), isTrue, reason: '$name $lv');
        final back = TrickState.fromJson(end.toJson());
        expect(back.serialize(), end.serialize());
      }
    });
  });

  test('tarneeb: ihale 7-13, herkes pas derse dağıtan 7 alır', () {
    const r = TarneebRules();
    final s = r.deal(r.deck(), 0);
    expect(r.legalBids(s, s.turn), [0, 7, 8, 9, 10, 11, 12, 13]);
    for (var i = 0; i < 4; i++) {
      r.applyBid(s, s.turn, 0);
      r.biddingOver(s);
    }
    expect(s.declarer, 0);
    expect(s.contract, 7);
    expect(r.legalBids(s, s.turn), [100, 101, 102, 103]);
    r.applyBid(s, s.turn, 101);
    expect(r.biddingOver(s), isTrue);
    r.finishBidding(s);
    expect(s.trump, kHearts);
    expect(s.turn, 0);
  });

  test('hokm: hakem 5 kartla kozu seçer, sonra 13 kart', () {
    const r = HokmRules();
    final s = r.deal(r.deck(), 3);
    expect(s.hands.every((h) => h.length == 5), isTrue);
    expect(s.kitty.length, 32);
    expect(s.turn, s.declarer);
    r.applyBid(s, s.turn, 100 + kSpades);
    expect(r.biddingOver(s), isTrue);
    r.finishBidding(s);
    expect(s.hands.every((h) => h.length == 13), isTrue);
    expect(s.leader, s.declarer);
  });

  test('baloot: Sun hokmu geçer, kazanan açık kartı alır', () {
    const r = BalootRules();
    final s = r.deal(r.deck(), 0);
    final up = s.kitty.first;
    expect(s.hands.every((h) => h.length == 5), isTrue);
    r.applyBid(s, s.turn, BalootRules.hokmBase + suitOf(up));
    expect(r.biddingOver(s), isFalse);
    expect(r.legalBids(s, s.turn), [0, BalootRules.sunBid]);
    final sunSeat = s.turn;
    r.applyBid(s, s.turn, BalootRules.sunBid);
    expect(r.biddingOver(s), isTrue);
    r.finishBidding(s);
    expect(s.hands[sunSeat].contains(up), isTrue);
    expect(s.hands.every((h) => h.length == 8), isTrue);
    expect(s.trump, -1);
  });

  test('29: koz kapalı kalır, rengi olmayan açtırır', () {
    const r = TwentyNineRules();
    final s = r.deal(r.deck(), 0);
    expect(s.hands.every((h) => h.length == 4), isTrue);
    r.applyBid(s, s.turn, 16);
    r.biddingOver(s);
    for (var i = 0; i < 3; i++) {
      r.applyBid(s, s.turn, 0);
      r.biddingOver(s);
    }
    r.applyBid(s, s.turn, 100 + kHearts);
    expect(r.biddingOver(s), isTrue);
    r.finishBidding(s);
    expect(s.trump, -1);
    expect(r.hiddenSuit(s), kHearts);
    expect(s.hands.every((h) => h.length == 8), isTrue);
    // Puan toplamı 28.
    expect(r.deck().fold<int>(0, (a, c) => a + r.cardPoints(c)), 28);
  });

  test('trix: sözleşmeler ve dizme', () {
    final trix = TrixGameRules(gameId: 'oyun-trix');
    final planner = LevelPlanner(gameId: 'oyun-trix', optionalMechanics: const []);
    final seen = <int>{};
    for (var lv = 1; lv <= 60 && seen.length < 5; lv++) {
      final spec = planner.spec(lv * 131);
      final gl = trix.build(spec);
      expect(gl.validation.ok, isTrue);
      final p = gl.puzzle;
      if (p is TableLevel) {
        seen.add(4);
        final end = TableGameRules.simulate(p);
        expect(end.over, isTrue);
        expect(end.scores.toList()..sort(), [50, 100, 150, 200]);
      } else {
        final l = p as TrickLevel;
        seen.add((l.rules as TrixRules).contract);
        final end = TrickGameRules.simulate(l);
        expect(end.phase, TrickPhase.over);
        expect(l.goal.check(l.rules, end), isTrue);
      }
    }
    expect(seen.length, 5);
    const lay = TrixLayoutRules();
    final s = lay.deal(buildDeck(), 0);
    expect(lay.playable(s, makeCard(11, kSpades)), isTrue);
    expect(lay.playable(s, makeCard(12, kSpades)), isFalse);
    s.piles[kSpades].add(makeCard(11, kSpades));
    expect(lay.playable(s, makeCard(12, kSpades)), isTrue);
    expect(lay.playable(s, makeCard(10, kSpades)), isTrue);
    expect(lay.playable(s, makeCard(9, kSpades)), isFalse);
  });
}
