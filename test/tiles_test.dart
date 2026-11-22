import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  // Anlam: renk * 13 + (sayı - 1); -1 joker.
  int t(int color, int n) => color * 13 + n - 1;

  test('okey: perlere bölünme', () {
    // 1-2-3 sarı, 7 dört renk, 11-12-13-1 mavi, 5-5-5 (üç renk)
    expect(okeyAllGrouped([t(0, 1), t(0, 2), t(0, 3), t(0, 7), t(1, 7), t(2, 7), t(3, 7), t(1, 11), t(1, 12), t(1, 13), t(1, 1), t(0, 5), t(1, 5), t(2, 5)]), isTrue);
    // Jokerle boşluk doldurma: 4-?-6 kırmızı
    expect(okeyAllGrouped([t(3, 4), -1, t(3, 6)]), isTrue);
    // 13-1-2 olmaz
    expect(okeyAllGrouped([t(0, 13), t(0, 1), t(0, 2)]), isFalse);
    // Aynı renkten iki 7 set olmaz
    expect(okeyAllGrouped([t(0, 7), t(0, 7), t(1, 7)]), isFalse);
    expect(okeyPairCount([t(0, 1), t(0, 1), t(1, 3), -1, t(2, 9), t(2, 9)]), 3);
    expect(okeyGroupValue([t(0, 10), t(0, 11), -1]), 10 + 11 + 12);
    expect(okeyGroupValue([t(1, 9), t(2, 9), t(3, 9)]), 27);
    expect(okeyGroupValue([t(1, 12), t(1, 13), t(1, 1)]), 12 + 13 + 1);
    expect(okeyGroupValue([t(1, 12), t(2, 13), t(1, 1)]), -1);
  });

  test('mahjong: tamam el', () {
    final c = List.filled(34, 0);
    for (final k in [0, 1, 2, 9, 10, 11, 18, 18, 18, 27, 27, 27, 33, 33]) {
      c[k]++;
    }
    expect(mjComplete(List.of(c), 4), isTrue);
    c[33]--;
    c[32]++;
    expect(mjComplete(List.of(c), 4), isFalse);
    final seven = List.filled(34, 0);
    for (final k in [0, 3, 7, 12, 20, 28, 31]) {
      seven[k] = 2;
    }
    expect(mjSevenPairs(seven), isTrue);
  });

  test('domino: sıra uçları tutarlı', () {
    const r = DominoRules(2);
    final deck = r.deck()..shuffle();
    final s = r.deal(deck, 0);
    var guard = 0;
    while (!s.over && guard++ < 200) {
      final l = r.legalActions(s);
      r.apply(s, l.first);
      final line = s.piles[1];
      for (var i = 0; i + 1 < line.length; i++) {
        final a = line[i], b = line[i + 1];
        final ar = a >= 1100 ? dominoA(a) : dominoB(a);
        final bl = b >= 1100 ? dominoB(b) : dominoA(b);
        expect(ar, bl);
      }
    }
    expect(s.over, isTrue);
  });

  final games = <String, TableGameRules>{
    'okey': TableGameRules(gameId: 'okey', rulesFor: (_) => const OkeyRules(), aiScale: 0.25),
    'okey-esli': TableGameRules(gameId: 'okey-esli', rulesFor: (_) => const OkeyRules(partners: true), aiScale: 0.25),
    'okey-katlamali': TableGameRules(gameId: 'okey-katlamali', rulesFor: (_) => const OkeyRules(doubling: true), aiScale: 0.25),
    'okey-iki': TableGameRules(gameId: 'okey-iki', rulesFor: (_) => const OkeyRules(players: 2), aiScale: 0.25),
    '101': TableGameRules(gameId: '101', rulesFor: (_) => const Okey101Rules(), aiScale: 0.2),
    'domino': TableGameRules(gameId: 'domino', rulesFor: (d) => DominoRules(d <= 4 ? 2 : 4)),
    'mahjong': TableGameRules(gameId: 'mahjong', rulesFor: (_) => const MahjongRules(), aiScale: 0.2),
    'riichi': TableGameRules(gameId: 'riichi', rulesFor: (_) => const MahjongRules(MahjongStyle.riichi), aiScale: 0.2),
    'hk': TableGameRules(gameId: 'hk', rulesFor: (_) => const MahjongRules(MahjongStyle.hongKong), aiScale: 0.2),
    'sanma': TableGameRules(gameId: 'sanma', rulesFor: (_) => const MahjongRules(MahjongStyle.sanma), aiScale: 0.2),
  };

  games.forEach((name, rules) {
    test('$name: bölümler üretilir ve oyun biter', () {
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
      for (final lv in [1, 9999]) {
        final sw = Stopwatch()..start();
        final gl = rules.build(planner.spec(lv));
        expect(gl.validation.ok, isTrue, reason: '$name $lv');
        final end = TableGameRules.simulate(gl.puzzle, seat0Samples: 2);
        expect(end.over, isTrue, reason: '$name $lv');
        final back = TableState.fromJson(end.serialize());
        expect(back.serialize(), end.serialize());
        // ignore: avoid_print
        print('$name $lv d=${gl.spec.difficulty} attempts=${gl.attempts} ${sw.elapsedMilliseconds}ms scores=${gl.puzzle.rules.finalScores(end)}');
      }
    }, timeout: const Timeout(Duration(minutes: 8)));
  });
}
