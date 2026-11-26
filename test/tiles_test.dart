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

  test('okey: en iyi bölünüş', () {
    // 1-2-3 sarı + 7 üç renk + yalnız 11 kırmızı
    final (cov, out) = okeyCoverPlan([t(0, 1), t(0, 2), t(0, 3), t(0, 7), t(1, 7), t(2, 7), t(3, 11)]);
    expect(cov, 6);
    expect(out, [t(3, 11)]);
    expect(okeyCoverPlan([t(1, 4), -1, t(1, 6)]).$1, 3);
  });

  test('mahjong: shanten', () {
    List<int> cnt(List<int> ks) {
      final c = List.filled(34, 0);
      for (final k in ks) {
        c[k]++;
      }
      return c;
    }

    // Tamam: -1; bir eksik: 0.
    expect(mjShanten(cnt([0, 1, 2, 9, 10, 11, 18, 18, 18, 27, 27, 27, 33, 33]), 4), -1);
    expect(mjShanten(cnt([0, 1, 2, 9, 10, 11, 18, 18, 18, 27, 27, 27, 33]), 4), 0);
    expect(mjShanten(cnt([0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 28, 29, 30]), 4) >= 5, isTrue);
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

  test('eşli domino: çift dokuzlu takım, ortaklar, çekme yok', () {
    expect(dominoA(dominoTile9(3, 9)), 3);
    expect(dominoB(dominoTile9(9, 3)), 9);
    expect(dominoA(dominoFlipped(dominoTile9(3, 9))), 3);
    expect(dominoIsFlipped(dominoFlipped(dominoTile9(8, 9))), isTrue);
    expect(dominoIsFlipped(dominoTile(6, 6)), isFalse);
    for (final nine in [false, true]) {
      final r = PartnerDominoRules(nine: nine);
      expect(r.partnerships, isTrue);
      final deck = r.deck();
      expect(deck.length, nine ? 55 : 28);
      expect(deck.toSet().length, deck.length);
      deck.shuffle();
      final s = r.deal(deck, 0);
      expect(s.hands.every((h) => h.length == (nine ? 10 : 7)), isTrue);
      var guard = 0;
      while (!s.over && guard++ < 400) {
        final l = r.legalActions(s);
        expect(l.any((a) => a.kind == 1), isFalse);
        r.apply(s, l.first);
        final line = s.piles[1];
        for (var i = 0; i + 1 < line.length; i++) {
          final a = line[i], b = line[i + 1];
          final ar = dominoIsFlipped(a) ? dominoA(a) : dominoB(a);
          final bl = dominoIsFlipped(b) ? dominoB(b) : dominoA(b);
          expect(ar, bl);
        }
      }
      expect(s.over, isTrue);
      final w = [for (var p = 0; p < 4; p++) p].firstWhere((p) => s.scores[p] > 0, orElse: () => -1);
      if (w >= 0) {
        expect(s.scores[(w + 2) % 4], s.scores[w]);
        expect(r.utility(s, (w + 2) % 4), greaterThan(0));
      }
    }
  });

  final games = <String, TableGameRules>{
    'okey': TableGameRules(gameId: 'okey', rulesFor: (_) => const OkeyRules(), aiScale: 0.1, quickValidate: true),
    'okey-esli': TableGameRules(gameId: 'okey-esli', rulesFor: (_) => const OkeyRules(partners: true), aiScale: 0.1, quickValidate: true),
    'okey-katlamali': TableGameRules(gameId: 'okey-katlamali', rulesFor: (_) => const OkeyRules(doubling: true), aiScale: 0.1, quickValidate: true),
    'okey-iki': TableGameRules(gameId: 'okey-iki', rulesFor: (_) => const OkeyRules(players: 2), aiScale: 0.1, quickValidate: true),
    '101': TableGameRules(gameId: '101', rulesFor: (_) => const Okey101Rules(), aiScale: 0.1, quickValidate: true),
    'domino': TableGameRules(gameId: 'domino', rulesFor: (d) => DominoRules(d <= 4 ? 2 : 4), quickValidate: true),
    'esli-domino': TableGameRules(gameId: 'esli-domino', rulesFor: (d) => PartnerDominoRules(nine: d >= 7), quickValidate: true),
    'mahjong': TableGameRules(gameId: 'mahjong', rulesFor: (_) => const MahjongRules(), aiScale: 0.1, quickValidate: true),
    'riichi': TableGameRules(gameId: 'riichi', rulesFor: (_) => const MahjongRules(MahjongStyle.riichi), aiScale: 0.1, quickValidate: true),
    'hk': TableGameRules(gameId: 'hk', rulesFor: (_) => const MahjongRules(MahjongStyle.hongKong), aiScale: 0.1, quickValidate: true),
    'sanma': TableGameRules(gameId: 'sanma', rulesFor: (_) => const MahjongRules(MahjongStyle.sanma), aiScale: 0.1, quickValidate: true),
  };

  games.forEach((name, rules) {
    test('$name: bölümler üretilir ve oyun biter', () {
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
      for (final lv in [1, 9999]) {
        final sw = Stopwatch()..start();
        final gl = rules.build(planner.spec(lv));
        expect(gl.validation.ok, isTrue, reason: '$name $lv');
        final end = TableGameRules.simulate(gl.puzzle, quick: true);
        expect(end.over, isTrue, reason: '$name $lv');
        final back = TableState.fromJson(end.serialize());
        expect(back.serialize(), end.serialize());
        // ignore: avoid_print
        print('$name $lv d=${gl.spec.difficulty} attempts=${gl.attempts} ${sw.elapsedMilliseconds}ms scores=${gl.puzzle.rules.finalScores(end)}');
      }
    }, timeout: const Timeout(Duration(minutes: 8)));
  });

  test('101 okey: yapay zekâ elini açar ve el bitirebilir', () {
    final rules = games['101']!;
    final planner = LevelPlanner(gameId: '101', optionalMechanics: const []);
    var opened = 0, out = 0, n = 0;
    for (final lv in [1, 7, 33, 120, 555, 1234, 4321, 9000, 20000, 41000]) {
      final gl = rules.build(planner.spec(lv));
      for (final seed in [1, 2, 3]) {
        final end = TableGameRules.simulate(gl.puzzle, quick: true, seed: seed);
        final rr = gl.puzzle.rules as Okey101Rules;
        n++;
        for (var p = 0; p < end.seats; p++) {
          if (rr.opened(end, p)) opened++;
        }
        if (end.hands.any((h) => h.isEmpty)) out++;
      }
    }
    // ignore: avoid_print
    print('101: $n el, açan oyuncu $opened, bitirilen el $out');
    expect(opened, greaterThan(n));
    // Deste yalnızca 20 taş: ellerin bir kısmı deste bitince sona erer.
    expect(out * 8, greaterThanOrEqualTo(n));
  }, timeout: const Timeout(Duration(minutes: 8)));
}
