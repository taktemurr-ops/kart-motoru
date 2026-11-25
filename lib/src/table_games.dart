import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'table_engine.dart';
import 'table_view.dart' show cardsLabel;

const _suitSym = ['♠', '♥', '♦', '♣'];

void _deal(List<KCard> deck, List<List<KCard>> hands, int each) {
  for (var r = 0; r < each; r++) {
    for (final h in hands) {
      if (deck.isNotEmpty) h.add(deck.removeLast());
    }
  }
}

void _sortHand(List<KCard> h) => h.sort((a, b) => (suitOf(a) * 20 + (rankOf(a) == 1 ? 14 : rankOf(a)))
    .compareTo(suitOf(b) * 20 + (rankOf(b) == 1 ? 14 : rankOf(b))));

// ======================================================================
// Toplama oyunları: Pişti, Scopa, Cassino
// ======================================================================

/// Pişti: masadaki üst kartla aynı değerde kart ya da Vale atan masayı alır.
/// Tek kartı alan "pişti" yapar (10 puan, Valeyle Vale 20).
class PistiRules extends TableRules {
  const PistiRules();

  /// Pişti maçı 151 puana.
  @override
  MatchFormat get matchFormat => const MatchFormat(target: 151);

  // yığınlar: 0 deste, 1 masa
  @override
  List<PileView> get pileViews => const [
        PileView('Deste', 'Stock', faceUp: false),
        PileView('Masa', 'Table'),
      ];

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final deck = List.of(shuffled);
    final table = <KCard>[for (var i = 0; i < 4; i++) deck.removeLast()];
    final hands = [<KCard>[], <KCard>[]];
    _deal(deck, hands, 4);
    for (final h in hands) {
      _sortHand(h);
    }
    final s = TableState(seats: 2, hands: hands, piles: [deck, table], turn: (dealer + 1) % 2);
    s.vars[0] = -1; // son alan
    return s;
  }

  @override
  List<TAction> legalActions(TableState s) => [for (final c in s.hands[s.turn]) TAction(0, [c])];

  @override
  void apply(TableState s, TAction a) {
    final seat = s.turn, c = a.cards.first;
    final table = s.piles[1];
    s.hands[seat].remove(c);
    final top = table.isEmpty ? null : table.last;
    final takes = top != null && (rankOf(top) == rankOf(c) || rankOf(c) == 11);
    if (takes) {
      if (table.length == 1) {
        s.scores[seat] += rankOf(c) == 11 && rankOf(top) == 11 ? 20 : 10;
        s.vars[1 + seat]++;
      }
      s.captured[seat]
        ..addAll(table)
        ..add(c);
      table.clear();
      s.vars[0] = seat;
    } else {
      table.add(c);
    }
    s.lastSeat = seat;
    s.last = a;
    s.turn = (seat + 1) % 2;
    if (s.hands.every((h) => h.isEmpty)) {
      if (s.piles[0].isNotEmpty) {
        _deal(s.piles[0], s.hands, 4);
        for (final h in s.hands) {
          _sortHand(h);
        }
      } else {
        if (s.vars[0] >= 0) s.captured[s.vars[0]].addAll(table);
        table.clear();
        s.over = true;
      }
    }
  }

  int cardPoints(KCard c) {
    if (c == makeCard(2, kClubs)) return 2;
    if (c == makeCard(10, kDiamonds)) return 3;
    if (rankOf(c) == 1 || rankOf(c) == 11) return 1;
    return 0;
  }

  @override
  List<int> finalScores(TableState s) {
    final out = [for (var p = 0; p < 2; p++) s.scores[p] + s.captured[p].fold<int>(0, (a, c) => a + cardPoints(c))];
    final n0 = s.captured[0].length, n1 = s.captured[1].length;
    if (n0 > n1) out[0] += 3;
    if (n1 > n0) out[1] += 3;
    return out;
  }

  @override
  TAction quick(TableState s, SeededRandom r) {
    final h = s.hands[s.turn];
    final t = s.piles[1];
    if (t.isNotEmpty) {
      for (final c in h) {
        if (rankOf(c) == rankOf(t.last)) return TAction(0, [c]);
      }
      if (t.length >= 3) {
        for (final c in h) {
          if (rankOf(c) == 11) return TAction(0, [c]);
        }
      }
    }
    final non = h.where((c) => rankOf(c) != 11).toList();
    final pick = non.isNotEmpty ? non : h;
    return TAction(0, [pick[r.nextInt(pick.length)]]);
  }

  @override
  String status(TableState s, String lang) =>
      '${Strings.tx(lang, 'Pişti', 'Pisti')}: ${s.vars[1]} · ${s.vars[2]}';
}

/// Toplamayla alma (Scopa ve Cassino): aynı değerde kart varsa onu, yoksa
/// toplamı kartın değerine eşit olan kartları al; alamıyorsan kartı masaya bırak.
abstract class _SumCaptureRules extends TableRules {
  const _SumCaptureRules();

  int get handCards;
  int get tableCards;
  int value(KCard c);
  bool get mustCaptureSameRank => true;

  @override
  List<PileView> get pileViews => const [
        PileView('Deste', 'Stock', faceUp: false),
        PileView('Masa', 'Table', spread: true),
      ];

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final deck = List.of(shuffled);
    final table = <KCard>[for (var i = 0; i < tableCards; i++) deck.removeLast()];
    final hands = [<KCard>[], <KCard>[]];
    _deal(deck, hands, handCards);
    for (final h in hands) {
      _sortHand(h);
    }
    final s = TableState(seats: 2, hands: hands, piles: [deck, table], turn: (dealer + 1) % 2);
    s.vars[0] = -1;
    return s;
  }

  List<List<KCard>> captures(List<KCard> table, KCard c) {
    final same = table.where((t) => rankOf(t) == rankOf(c)).toList();
    if (same.isNotEmpty && mustCaptureSameRank) return [for (final t in same) [t]];
    final out = <List<KCard>>[];
    final v = value(c);
    final n = table.length;
    for (var mask = 1; mask < (1 << n) && out.length < 12; mask++) {
      var sum = 0;
      final pick = <KCard>[];
      for (var i = 0; i < n; i++) {
        if (mask & (1 << i) != 0) {
          sum += value(table[i]);
          pick.add(table[i]);
        }
      }
      if (sum == v && pick.length >= (mustCaptureSameRank ? 2 : 1)) out.add(pick);
    }
    if (!mustCaptureSameRank) {
      for (final t in same) {
        if (!out.any((o) => o.length == 1 && o.first == t)) out.add([t]);
      }
    }
    return out;
  }

  @override
  List<TAction> legalActions(TableState s) {
    final out = <TAction>[];
    for (final c in s.hands[s.turn]) {
      final caps = captures(s.piles[1], c);
      if (caps.isEmpty) {
        out.add(TAction(0, [c]));
      } else {
        for (final cap in caps) {
          out.add(TAction(1, [c, ...cap]));
        }
      }
    }
    return out;
  }

  @override
  bool isCardPlay(TAction a) => a.kind == 0;

  @override
  String actionLabel(TAction a, String lang) =>
      '${cardsLabel([a.cards.first])} → ${cardsLabel(a.cards.sublist(1))}';

  @override
  void apply(TableState s, TAction a) {
    final seat = s.turn, c = a.cards.first;
    final table = s.piles[1];
    s.hands[seat].remove(c);
    if (a.kind == 1) {
      for (final t in a.cards.skip(1)) {
        table.remove(t);
      }
      s.captured[seat].addAll(a.cards);
      s.vars[0] = seat;
      final lastPlay = s.piles[0].isEmpty && s.hands.every((h) => h.isEmpty);
      if (table.isEmpty && !lastPlay) {
        s.scores[seat]++; // süpürme
        s.vars[1 + seat]++;
      }
    } else {
      table.add(c);
    }
    s.lastSeat = seat;
    s.last = a;
    s.turn = (seat + 1) % 2;
    if (s.hands.every((h) => h.isEmpty)) {
      if (s.piles[0].isNotEmpty) {
        _deal(s.piles[0], s.hands, handCards);
        for (final h in s.hands) {
          _sortHand(h);
        }
      } else {
        if (s.vars[0] >= 0) s.captured[s.vars[0]].addAll(table);
        table.clear();
        s.over = true;
      }
    }
  }

  @override
  TAction quick(TableState s, SeededRandom r) {
    final l = legalActions(s);
    final caps = l.where((a) => a.kind == 1).toList();
    if (caps.isNotEmpty) {
      caps.sort((a, b) => b.cards.length.compareTo(a.cards.length));
      return caps.first;
    }
    return l[r.nextInt(l.length)];
  }

  @override
  String status(TableState s, String lang) =>
      '${Strings.tx(lang, 'Süpürme', 'Sweeps')}: ${s.vars[1]} · ${s.vars[2]}';
}

/// Scopa: 40 kart; As 1 … Papaz 10. Kartlar, karolar, karo yedi ve yediler birer puan.
class ScopaRules extends _SumCaptureRules {
  const ScopaRules();

  @override
  MatchFormat get matchFormat => const MatchFormat(target: 11);

  @override
  List<KCard> deck() => buildDeck(ranks: const [1, 2, 3, 4, 5, 6, 7, 11, 12, 13]);
  @override
  int get handCards => 3;
  @override
  int get tableCards => 4;
  @override
  int value(KCard c) => switch (rankOf(c)) { 11 => 8, 12 => 9, 13 => 10, final r => r };

  @override
  List<int> finalScores(TableState s) {
    final out = List.of(s.scores);
    void most(int Function(List<KCard>) f) {
      final a = f(s.captured[0]), b = f(s.captured[1]);
      if (a > b) out[0]++;
      if (b > a) out[1]++;
    }

    most((l) => l.length);
    most((l) => l.where((c) => suitOf(c) == kDiamonds).length);
    most((l) => l.where((c) => rankOf(c) == 7).length);
    final sb = makeCard(7, kDiamonds);
    for (var p = 0; p < 2; p++) {
      if (s.captured[p].contains(sb)) out[p]++;
    }
    return out;
  }
}

/// Cassino: 52 kart; As 1, resimliler yalnızca aynısıyla alınır. En çok kart 3,
/// en çok maça 1, karo 10 iki, maça 2 bir, her As bir puan.
class CassinoRules extends _SumCaptureRules {
  const CassinoRules();

  @override
  MatchFormat get matchFormat => const MatchFormat(target: 21);

  @override
  int get handCards => 4;
  @override
  int get tableCards => 4;
  @override
  bool get mustCaptureSameRank => false;
  @override
  int value(KCard c) => rankOf(c) > 10 ? 100 + rankOf(c) : rankOf(c);

  @override
  List<int> finalScores(TableState s) {
    final out = List.of(s.scores);
    final a = s.captured[0], b = s.captured[1];
    if (a.length > b.length) out[0] += 3;
    if (b.length > a.length) out[1] += 3;
    final sa = a.where((c) => suitOf(c) == kSpades).length, sb = b.where((c) => suitOf(c) == kSpades).length;
    if (sa > sb) out[0]++;
    if (sb > sa) out[1]++;
    for (var p = 0; p < 2; p++) {
      final l = s.captured[p];
      if (l.contains(makeCard(10, kDiamonds))) out[p] += 2;
      if (l.contains(makeCard(2, kSpades))) out[p] += 1;
      out[p] += l.where((c) => rankOf(c) == 1).length;
    }
    return out;
  }
}

// ======================================================================
// Atma oyunları
// ======================================================================

/// Renk Eşle: üstteki kartla aynı renk ya da aynı değerde kart at; sekizler
/// joker (renk seçersin). Elinde kart kalmayan ilk oyuncu kazanır.
class ColorMatchRules extends TableRules {
  final int players;
  const ColorMatchRules({this.players = 3});

  /// Elde kalan kartların cezası birikir; 100'e varan olunca en az ceza kazanır.
  @override
  MatchFormat get matchFormat => const MatchFormat(target: 100, lowWins: true);

  @override
  List<int> matchPoints(TableState s) => [for (final h in s.hands) penalty(h)];

  @override
  int get seats => players;

  // 0 deste, 1 atık; vars[0] geçerli renk, vars[1] bu turda çekildi mi
  @override
  List<PileView> get pileViews => const [
        PileView('Deste', 'Stock', faceUp: false),
        PileView('Atık', 'Discard'),
      ];

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final deck = List.of(shuffled);
    final hands = [for (var p = 0; p < seats; p++) <KCard>[]];
    _deal(deck, hands, seats == 2 ? 7 : 5);
    for (final h in hands) {
      _sortHand(h);
    }
    var first = deck.removeLast();
    while (rankOf(first) == 8) {
      deck.insert(0, first);
      first = deck.removeLast();
    }
    final s = TableState(seats: seats, hands: hands, piles: [deck, [first]], turn: (dealer + 1) % seats);
    s.vars[0] = suitOf(first);
    return s;
  }

  bool _ok(TableState s, KCard c) => rankOf(c) == 8 || suitOf(c) == s.vars[0] || rankOf(c) == rankOf(s.piles[1].last);

  @override
  List<TAction> legalActions(TableState s) {
    final out = <TAction>[];
    for (final c in s.hands[s.turn]) {
      if (!_ok(s, c)) continue;
      if (rankOf(c) == 8) {
        for (var t = 0; t < 4; t++) {
          out.add(TAction(2, [c], t));
        }
      } else {
        out.add(TAction(0, [c]));
      }
    }
    if (s.vars[1] == 0 && s.piles[0].isNotEmpty) {
      out.add(const TAction(1)); // çek
    } else if (out.isEmpty || s.vars[1] == 1) {
      out.add(const TAction(3)); // pas
    }
    return out;
  }

  @override
  String actionLabel(TAction a, String lang) => switch (a.kind) {
        1 => Strings.tx(lang, 'Kart çek', 'Draw'),
        3 => Strings.tx(lang, 'Pas', 'Pass'),
        2 => '8 → ${_suitSym[a.target]}',
        _ => cardsLabel(a.cards),
      };

  @override
  void apply(TableState s, TAction a) {
    final seat = s.turn;
    s.lastSeat = seat;
    s.last = a;
    if (a.kind == 1) {
      s.hands[seat].add(s.piles[0].removeLast());
      _sortHand(s.hands[seat]);
      s.vars[1] = 1;
      return;
    }
    if (a.kind == 0 || a.kind == 2) {
      final c = a.cards.first;
      s.hands[seat].remove(c);
      s.piles[1].add(c);
      s.vars[0] = a.kind == 2 ? a.target : suitOf(c);
      if (s.hands[seat].isEmpty) {
        s.over = true;
        s.vars[2] = seat;
        return;
      }
    }
    s.vars[1] = 0;
    s.turn = (seat + 1) % seats;
    // Deste bitti ve kimse oynayamıyorsa: en az kart kalan kazanır.
    if (s.piles[0].isEmpty) {
      s.vars[3]++;
      if (s.vars[3] > seats * 2) {
        s.over = true;
        s.vars[2] = -1;
      }
    }
    if (a.kind != 3) s.vars[3] = 0;
  }

  int penalty(List<KCard> h) => h.fold(0, (a, c) => a + (rankOf(c) == 8 ? 50 : (rankOf(c) > 10 ? 10 : rankOf(c))));

  @override
  List<int> finalScores(TableState s) => [for (final h in s.hands) -penalty(h)];

  @override
  TAction quick(TableState s, SeededRandom r) {
    final l = legalActions(s);
    final plays = l.where((a) => a.kind == 0).toList();
    if (plays.isNotEmpty) return plays[r.nextInt(plays.length)];
    final eights = l.where((a) => a.kind == 2).toList();
    if (eights.isNotEmpty) {
      final h = s.hands[s.turn];
      final best = [0, 1, 2, 3]..sort((x, y) => h.where((c) => suitOf(c) == y).length.compareTo(h.where((c) => suitOf(c) == x).length));
      return eights.firstWhere((a) => a.target == best.first, orElse: () => eights.first);
    }
    return l.first;
  }

  @override
  String status(TableState s, String lang) => '${Strings.tx(lang, 'Renk', 'Suit')}: ${_suitSym[s.vars[0]]}';
}

/// Savaş (taktikli): herkesin destesinden üç kart elde durur; sırayla birini
/// açarsınız, büyük kart ikisini alır. Eşitlikte üçer kart daha ortaya konur.
class WarRules extends TableRules {
  const WarRules();

  // 0,1: oyuncuların desteleri (gizli), 2: ortadaki kartlar
  @override
  List<PileView> get pileViews => const [
        PileView('Senin desten', 'Your deck', faceUp: false),
        PileView('Rakibin destesi', 'Rival deck', faceUp: false),
        PileView('Ortada', 'Center', spread: true),
      ];

  @override
  Set<int> get hiddenPiles => const {0, 1};

  static int power(KCard c) => rankOf(c) == 1 ? 14 : rankOf(c);

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final a = shuffled.sublist(0, 26), b = shuffled.sublist(26);
    final hands = [<KCard>[], <KCard>[]];
    for (var i = 0; i < 3; i++) {
      hands[0].add(a.removeLast());
      hands[1].add(b.removeLast());
    }
    final s = TableState(seats: 2, hands: hands, piles: [a, b, []], turn: dealer % 2);
    s.vars[0] = 30; // kalan tur
    s.vars[1] = s.turn; // turu açan
    return s;
  }

  @override
  List<TAction> legalActions(TableState s) => [for (final c in s.hands[s.turn]) TAction(0, [c])];

  void _refill(TableState s, int p) {
    while (s.hands[p].length < 3 && s.piles[p].isNotEmpty) {
      s.hands[p].add(s.piles[p].removeLast());
    }
  }

  @override
  void apply(TableState s, TAction a) {
    final seat = s.turn, c = a.cards.first;
    s.hands[seat].remove(c);
    s.piles[2].add(c);
    s.lastSeat = seat;
    s.last = a;
    if (s.vars[2] == 0) {
      s.vars[2] = 1;
      s.vars[3] = c;
      s.turn = 1 - seat;
      return;
    }
    // İki kart açıldı.
    final lead = s.vars[3], leader = 1 - seat;
    s.vars[2] = 0;
    final pl = power(lead), pc = power(c);
    if (pl != pc) {
      final w = pl > pc ? leader : seat;
      s.captured[w].addAll(s.piles[2]);
      s.scores[w] += s.piles[2].length;
      s.piles[2].clear();
    } else {
      // Savaş: ikişer kart kapalı ortaya.
      for (final p in [0, 1]) {
        for (var k = 0; k < 2 && (s.piles[p].isNotEmpty || s.hands[p].isNotEmpty); k++) {
          s.piles[2].add(s.piles[p].isNotEmpty ? s.piles[p].removeLast() : s.hands[p].removeLast());
        }
      }
    }
    _refill(s, 0);
    _refill(s, 1);
    s.vars[0]--;
    s.vars[1] = 1 - s.vars[1];
    s.turn = s.vars[1];
    if (s.vars[0] <= 0 || s.hands.any((h) => h.isEmpty)) s.over = true;
  }

  @override
  TAction quick(TableState s, SeededRandom r) {
    final h = s.hands[s.turn];
    if (s.vars[2] == 1) {
      final lead = power(s.vars[3]);
      final win = h.where((c) => power(c) > lead).toList()..sort((a, b) => power(a).compareTo(power(b)));
      if (win.isNotEmpty) return TAction(0, [win.first]);
      final low = List.of(h)..sort((a, b) => power(a).compareTo(power(b)));
      return TAction(0, [low.first]);
    }
    return TAction(0, [h[r.nextInt(h.length)]]);
  }

  @override
  String status(TableState s, String lang) => '${Strings.tx(lang, 'Kalan tur', 'Rounds left')}: ${s.vars[0]}';
}
