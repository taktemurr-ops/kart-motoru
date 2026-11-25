import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

/// Mahjong yapay zekâsı: hızlı shanten, pinfu, furiten, yaku planlı alma,
/// riichi ilanı, savunma ve benzetimle kazanma oranları.
void main() {
  KCard t(int kind, [int copy = 0]) => 2000 + kind * 4 + copy;
  List<KCard> tiles(List<int> kinds) {
    final used = <int, int>{};
    return [
      for (final k in kinds) t(k, used[k] = (used[k] ?? -1) + 1),
    ];
  }

  TableState table(MahjongRules r, List<int> hand, {int turn = 1}) {
    final s = r.deal(r.deck(), 0);
    s.hands[turn]
      ..clear()
      ..addAll(tiles(hand));
    s.turn = turn;
    return s;
  }

  test('hızlı shanten eski shanten ile aynı', () {
    final r = SeededRandom(5);
    for (var i = 0; i < 3000; i++) {
      final c = List.filled(34, 0);
      final n = [13, 14, 10, 11, 7][i % 5];
      final need = {13: 4, 14: 4, 10: 3, 11: 3, 7: 2}[n]!;
      var k = 0;
      while (k < n) {
        final x = i.isEven ? r.nextInt(9) : r.nextInt(34);
        if (c[x] < 4) {
          c[x]++;
          k++;
        }
      }
      expect(mjShantenFast(c, need, sevenPairs: need == 4), mjShanten(List.of(c), need, sevenPairs: need == 4));
    }
    final pungs = List.filled(34, 0)
      ..[0] = 3
      ..[5] = 2
      ..[27] = 2
      ..[31] = 2
      ..[12] = 1
      ..[20] = 3;
    expect(mjShantenPungs(pungs, 4), 1);
  });

  test('pinfu: iki yönlü bekleyişte bir han, kanchan bekleyişte yok', () {
    const r = MahjongRules(MahjongStyle.riichi);
    final s = table(r, []);
    final c = List.filled(34, 0);
    for (final k in [0, 1, 2, 3, 4, 5, 10, 11, 12, 23, 24, 25, 8, 8]) {
      c[k]++;
    }
    expect(r.pinfu(c, 12, s, 1), isTrue);
    expect(r.pinfu(c, 11, s, 1), isFalse);
    // Çift ejderse pinfu olmaz.
    c[8] = 0;
    c[31] = 2;
    expect(r.pinfu(c, 12, s, 1), isFalse);
  });

  test('furiten: bekleyişi kendi attıklarındaysa ron yok', () {
    const r = MahjongRules(MahjongStyle.riichi);
    // Riichi'de 2-3-4p 5-6-7p 2-3-4s 6-7-8m + tek kırmızı ejder bekleyişi.
    TableState make({required bool furiten}) {
      final s = table(r, [1, 2, 3, 4, 5, 6, 10, 11, 12, 23, 24, 25, 33]);
      s.vars[4] = 1 << 1;
      if (furiten) s.piles[r.riverBase + 1].add(t(33, 3));
      s.turn = 0;
      s.vars[0] = 1;
      s.hands[0]
        ..clear()
        ..add(t(33, 2));
      return s;
    }

    final ok = make(furiten: false);
    expect(r.waits(ok, 1), [33]);
    expect(r.furiten(ok, 1), isFalse);
    r.apply(ok, TAction(0, [t(33, 2)]));
    expect((ok.vars[0], ok.turn), (2, 1));
    final f = make(furiten: true);
    expect(r.furiten(f, 1), isTrue);
    r.apply(f, TAction(0, [t(33, 2)]));
    expect(f.vars[0] == 2 && f.turn == 1, isFalse);
  });

  test('Riichi: yakusuz açık el için almaz, yakuhai üçlüsünü alır', () {
    const r = MahjongRules(MahjongStyle.riichi);
    // Uçlar ve karışık renkler: tanyao/honitsu/toitoi yok.
    final s = table(r, [0, 1, 8, 9, 10, 17, 18, 26, 26, 27, 31, 31, 13]);
    s.piles[1].add(t(2, 3));
    s.vars[1] = 0;
    final chi = TAction(5, [t(0), t(1)], 0);
    expect(MahjongBrain(r, s, 1, 2).wantsCall(chi, t(2, 3)), isFalse);
    s.piles[1]
      ..removeLast()
      ..add(t(31, 3));
    final pon = TAction(3, [t(31), t(31, 1)]);
    expect(MahjongBrain(r, s, 1, 2).wantsCall(pon, t(31, 3)), isTrue);
  });

  test('kapalı ve hazır elde riichi ilan eder', () {
    const r = MahjongRules(MahjongStyle.riichi);
    final s = table(r, [1, 2, 3, 4, 5, 6, 10, 11, 12, 23, 24, 25, 22, 33]);
    s.vars[0] = 1;
    final a = r.quick(s, SeededRandom(1));
    expect(a.kind, 6);
    expect(mjKind(a.cards.first), 33);
  });

  test('riichi diyen rakibe karşı uzak elde güvenli taş (genbutsu) atar', () {
    const r = MahjongRules(MahjongStyle.riichi);
    final s = table(r, [0, 4, 8, 10, 14, 17, 19, 22, 26, 28, 30, 13, 6, 2]);
    s.vars[0] = 1;
    s.vars[4] = 1 << 2; // oyuncu 2 riichi
    s.piles[r.riverBase + 2].add(t(22, 3));
    final b = MahjongBrain(r, s, 1, 2);
    expect(b.danger(22), 0);
    expect(b.danger(4), greaterThan(5));
    expect(b.bestDiscard(SeededRandom(3)).$1, 22);
  });

  test('zorluk → ustalık; Mahjong kararları doğrudan sezgisel', () {
    expect(MahjongRules.skillFor(1), 0);
    expect(MahjongRules.skillFor(5), 1);
    expect(MahjongRules.skillFor(9), 2);
    expect((const MahjongRules(MahjongStyle.riichi).forDifficulty(2) as MahjongRules).skill, 0);
    expect(const MahjongRules().heuristicAI, isTrue);
    final g = TableGameRules(gameId: 'mj', rulesFor: (_) => const MahjongRules(MahjongStyle.riichi), aiScale: 0.1, quickValidate: true);
    final spec = LevelPlanner(gameId: 'mj', optionalMechanics: const []).spec(1).copyWith(difficulty: 2);
    expect((g.generate(spec).rules as MahjongRules).skill, 0);
    expect((g.generate(spec.copyWith(difficulty: 10)).rules as MahjongRules).skill, 2);
  });

  for (final style in MahjongStyle.values) {
    test('benzetim: ${style.name} — herkes el kazanır, berabere azınlıkta', () {
      final rules = MahjongRules(style);
      final wins = List.filled(rules.seats, 0);
      var draws = 0;
      const n = 120;
      for (var g = 0; g < n; g++) {
        final r = SeededRandom(mixSeed([g, 99]));
        final deck = rules.deck();
        shuffleCards(deck, r);
        final s = rules.deal(deck, g % rules.seats);
        var guard = 0;
        while (!s.over && guard++ < 3000) {
          rules.apply(s, rules.quick(s, r));
        }
        expect(s.over, isTrue);
        final w = s.vars[5] - 1;
        if (w < 0) {
          draws++;
        } else {
          wins[w]++;
        }
      }
      expect(draws, lessThan(n * 0.3), reason: '$wins draws=$draws');
      for (final w in wins) {
        expect(w, greaterThan(n * 0.1), reason: '$wins draws=$draws');
      }
    });
  }
}
