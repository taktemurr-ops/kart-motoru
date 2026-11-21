import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'kart_texts.dart';
import 'table_engine.dart';
import 'table_games2.dart' show rankName;

// ======================================================================
// Per (meld) yardımcıları

/// Kart değeri: As 1, resimli 10, diğerleri sayısı.
int rummyValue(KCard c) => rankOf(c) > 10 ? 10 : rankOf(c);

bool isSetMeld(List<KCard> m) {
  if (m.length < 3 || m.length > 4) return false;
  final r = rankOf(m.first);
  final suits = <int>{};
  for (final c in m) {
    if (rankOf(c) != r || !suits.add(suitOf(c))) return false;
  }
  return true;
}

bool isRunMeld(List<KCard> m, {int minLen = 3}) {
  if (m.length < minLen) return false;
  final su = suitOf(m.first);
  if (m.any((c) => suitOf(c) != su)) return false;
  final ranks = [for (final c in m) rankOf(c)]..sort();
  bool consecutive(List<int> rs) {
    for (var i = 1; i < rs.length; i++) {
      if (rs[i] != rs[i - 1] + 1) return false;
    }
    return true;
  }

  if (consecutive(ranks)) return true;
  // As yüksek: Q-K-A
  if (ranks.first == 1) {
    final hi = [...ranks.skip(1), 14];
    return consecutive(hi);
  }
  return false;
}

bool isMeld(List<KCard> m, {int runMin = 3}) => isSetMeld(m) || isRunMeld(m, minLen: runMin);

/// Bir eldeki bütün geçerli perler (set ya da seri).
List<List<KCard>> enumerateMelds(List<KCard> hand, {int runMin = 3, bool sets = true, bool runs = true}) {
  final out = <List<KCard>>[];
  if (sets) {
    final byRank = <int, List<KCard>>{};
    for (final c in hand) {
      byRank.putIfAbsent(rankOf(c), () => []).add(c);
    }
    for (final g in byRank.values) {
      // Aynı desenden yalnızca birer kart
      final bySuit = <int, KCard>{};
      for (final c in g) {
        bySuit.putIfAbsent(suitOf(c), () => c);
      }
      final u = bySuit.values.toList();
      if (u.length >= 3) {
        if (u.length == 4) out.add(List.of(u));
        for (var skip = 0; skip < u.length && u.length == 4; skip++) {
          out.add([for (var i = 0; i < 4; i++) if (i != skip) u[i]]);
        }
        if (u.length == 3) out.add(List.of(u));
      }
    }
  }
  if (runs) {
    for (var su = 0; su < 4; su++) {
      final byRank = <int, KCard>{};
      for (final c in hand) {
        if (suitOf(c) == su) byRank.putIfAbsent(rankOf(c), () => c);
      }
      if (byRank.length < runMin) continue;
      // 1..14 (As iki uçta da)
      KCard? at(int r) => byRank[r == 14 ? 1 : r];
      var start = 1;
      while (start <= 14) {
        if (at(start) == null) {
          start++;
          continue;
        }
        var end = start;
        while (end + 1 <= 14 && at(end + 1) != null) {
          end++;
        }
        for (var a = start; a <= end; a++) {
          for (var b = a + runMin - 1; b <= end; b++) {
            if (b - a + 1 > 13) continue;
            out.add([for (var r = a; r <= b; r++) at(r)!]);
          }
        }
        start = end + 1;
      }
    }
  }
  return out;
}

/// Birbirine değmeyen perlerin en değerli seçimi (kalan kartlar "ölü").
/// Dönüş: (perler, perlerdeki toplam değer).
(List<List<KCard>>, int) bestMeldSet(List<KCard> hand, {int runMin = 3, int Function(KCard)? value}) {
  final v = value ?? rummyValue;
  final melds = enumerateMelds(hand, runMin: runMin);
  var best = <List<KCard>>[];
  var bestV = 0;
  final cur = <List<KCard>>[];
  final used = <KCard>{};
  var steps = 0;
  void go(int i, int val) {
    if (++steps > 20000) return;
    if (val > bestV) {
      bestV = val;
      best = List.of(cur);
    }
    for (var k = i; k < melds.length; k++) {
      final m = melds[k];
      if (m.any(used.contains)) continue;
      used.addAll(m);
      cur.add(m);
      go(k + 1, val + m.fold<int>(0, (a, c) => a + v(c)));
      cur.removeLast();
      used.removeAll(m);
    }
  }

  go(0, 0);
  return (best, bestV);
}

/// Kart, eldeki kartlarla bir per oluşturuyor ya da bir perin parçası olabiliyor mu?
bool helps(List<KCard> hand, KCard c, int runMin) {
  final sameRank = hand.where((x) => rankOf(x) == rankOf(c) && suitOf(x) != suitOf(c)).length;
  if (sameRank >= 2) return true;
  final near = hand.where((x) => suitOf(x) == suitOf(c) && (rankOf(x) - rankOf(c)).abs() <= 2 && rankOf(x) != rankOf(c)).length;
  return near >= 2 && enumerateMelds([...hand, c], runMin: runMin, sets: false).any((m) => m.contains(c));
}

List<KCard> _loose(List<KCard> hand) {
  final inMeld = {for (final m in enumerateMelds(hand)) ...m};
  return hand.where((c) => !inMeld.contains(c)).toList();
}

/// Hızlı atış: hiçbir perde yer almayan, komşusu az, değeri yüksek kart.
KCard cheapDiscard(List<KCard> hand, SeededRandom r, int Function(KCard) value, int runMin) {
  final inMeld = {for (final m in enumerateMelds(hand, runMin: runMin)) ...m};
  var best = hand.first;
  var bv = -1 << 20;
  for (final c in hand) {
    if (inMeld.contains(c)) continue;
    final pairs = hand.where((x) => x != c && rankOf(x) == rankOf(c)).length;
    final adj = hand.where((x) => suitOf(x) == suitOf(c) && (rankOf(x) - rankOf(c)).abs() == 1).length;
    final v = value(c) * 2 - pairs * 9 - adj * 7 + r.nextInt(3);
    if (v > bv) {
      bv = v;
      best = c;
    }
  }
  if (bv == -1 << 20) {
    best = hand.reduce((a, b) => value(a) >= value(b) ? a : b);
  }
  return best;
}

int deadwood(List<KCard> hand, {int Function(KCard)? value}) {
  final v = value ?? rummyValue;
  final total = hand.fold<int>(0, (a, c) => a + v(c));
  return total - bestMeldSet(hand, value: v).$2;
}

const kMeldsLabel = [
  'Perler', 'Melds', 'Meldungen', 'Combinaciones', 'Combinaisons', 'التشكيلات', 'دست‌ها', 'צירופים', 'ملاپ', 'Комбинации',
  'Комбінації', 'Układy', 'Kombinace', 'Combinații', 'Kombinációk', 'Συνδυασμοί', 'Combinazioni', 'Combinações', 'Combinaties',
  'Kombinationer', 'Kombinationer', 'Kombinasjoner', 'Yhdistelmät', '役', '조합', '组合', 'संयोजन', 'সংযোগ', 'Kombinasi',
  'Kombinasi', 'ชุดไพ่', 'Bộ bài', 'Mga meld',
];

// ======================================================================
// Remi ailesi

/// Remi (Rummy) ailesi: desteden ya da atıktan bir kart çek, per aç ya da
/// masadaki perlere işle, sonra bir kart at. Elini ilk bitiren kazanır; diğer
/// oyuncuların elindeki kartların değeri ona yazılır.
///
/// [openMin]: ilk açılışta perlerin toplam değeri en az bu kadar olmalı
/// (Konken 51). [contract]: Aşamalı Remi'de ilk açılışın içermesi gereken
/// perler (true: seri, false: set); seriler en az 4 kart.
class RummyRules extends TableRules {
  final int players;
  final int handSize;
  final int decks;
  final int openMin;
  final List<bool>? contract;
  const RummyRules({this.players = 3, this.handSize = 7, this.decks = 1, this.openMin = 0, this.contract});

  @override
  int get seats => players;
  @override
  List<KCard> deck() => buildDeck(decks: decks);

  // piles: 0 deste (kapalı), 1 atık, 2 masadaki perler (gösterim), 3+ perler
  // vars: 0 aşama (0 çek, 1 oyna), 1 açmış oyuncular (bit), 2 karıştırma sayısı
  @override
  List<PileView> get pileViews => const [
        PileView('Deste', 'Stock', faceUp: false),
        PileView('Atık', 'Discard'),
        PileView('Perler', 'Melds', spread: true, maxShown: 40, labels: kMeldsLabel),
      ];

  int get runMin => contract != null ? 4 : 3;

  int value(KCard c) => rummyValue(c);

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final deck = List.of(shuffled);
    final hands = [for (var p = 0; p < seats; p++) <KCard>[]];
    for (var r = 0; r < handSize; r++) {
      for (final h in hands) {
        h.add(deck.removeLast());
      }
    }
    for (final h in hands) {
      _sort(h);
    }
    final s = TableState(seats: seats, hands: hands, piles: [deck, [deck.removeLast()], []], turn: (dealer + 1) % seats);
    return s;
  }

  void _sort(List<KCard> h) => h.sort((a, b) => (suitOf(a) * 20 + rankOf(a)).compareTo(suitOf(b) * 20 + rankOf(b)));

  bool opened(TableState s, int p) => (s.vars[1] >> p) & 1 == 1;

  List<List<KCard>> melds(TableState s) => s.piles.length > 3 ? s.piles.sublist(3) : const [];

  /// Açılış hamlesinin kartları (yoksa null).
  List<KCard>? openingCards(TableState s, int p) {
    final h = s.hands[p];
    final con = contract;
    if (con != null) {
      final ms = enumerateMelds(h, runMin: runMin);
      final pick = <List<KCard>>[];
      final used = <KCard>{};
      var steps = 0;
      bool go(int slot) {
        if (slot == con.length) return true;
        if (++steps > 5000) return false;
        for (final m in ms) {
          if (isRunMeld(m, minLen: runMin) != con[slot] || (!con[slot] && !isSetMeld(m))) continue;
          if (m.any(used.contains)) continue;
          used.addAll(m);
          pick.add(m);
          if (go(slot + 1)) return true;
          pick.removeLast();
          used.removeAll(m);
        }
        return false;
      }

      if (!go(0)) return null;
      return [for (final m in pick) ...m];
    }
    final (ms, v) = bestMeldSet(h, runMin: runMin, value: value);
    if (ms.isEmpty || v < openMin) return null;
    return [for (final m in ms) ...m];
  }

  /// Açılış kartlarını perlere ayır (sıra korunur).
  List<List<KCard>> _split(List<KCard> cards) {
    final out = <List<KCard>>[];
    var rest = List.of(cards);
    while (rest.isNotEmpty) {
      var found = false;
      for (var n = rest.length; n >= 3 && !found; n--) {
        final m = rest.sublist(0, n);
        if (isMeld(m, runMin: runMin)) {
          out.add(m);
          rest = rest.sublist(n);
          found = true;
        }
      }
      if (!found) {
        out.add(rest);
        break;
      }
    }
    return out;
  }

  @override
  List<TAction> legalActions(TableState s) {
    final p = s.turn;
    final h = s.hands[p];
    if (s.vars[0] == 0) {
      return [
        const TAction(1, [], 0),
        if (s.piles[1].isNotEmpty) const TAction(1, [], 1),
      ];
    }
    final out = <TAction>[];
    if (!opened(s, p)) {
      final o = openingCards(s, p);
      if (o != null) out.add(TAction(5, o));
    } else {
      for (final m in enumerateMelds(h, runMin: runMin)) {
        out.add(TAction(2, m));
      }
      final ms = melds(s);
      for (final c in h) {
        for (var i = 0; i < ms.length; i++) {
          if (isMeld([...ms[i], c], runMin: runMin)) out.add(TAction(3, [c], i));
        }
      }
    }
    for (final c in h) {
      out.add(TAction(0, [c]));
    }
    return out;
  }

  void _layMeld(TableState s, List<KCard> m) {
    final sorted = List.of(m)..sort((a, b) => rankOf(a).compareTo(rankOf(b)));
    s.piles.add(sorted);
    _refreshDisplay(s);
  }

  void _refreshDisplay(TableState s) {
    s.piles[2]
      ..clear()
      ..addAll([for (final m in melds(s)) ...m]);
  }

  @override
  void apply(TableState s, TAction a) {
    final p = s.turn;
    final h = s.hands[p];
    s.lastSeat = p;
    s.last = a;
    switch (a.kind) {
      case 1:
        if (a.target == 1 && s.piles[1].isNotEmpty) {
          h.add(s.piles[1].removeLast());
        } else {
          if (s.piles[0].isEmpty) _reshuffle(s);
          if (s.piles[0].isNotEmpty) h.add(s.piles[0].removeLast());
        }
        _sort(h);
        s.vars[0] = 1;
        return;
      case 5:
        for (final c in a.cards) {
          h.remove(c);
        }
        for (final m in _split(a.cards)) {
          _layMeld(s, m);
        }
        s.vars[1] |= 1 << p;
      case 2:
        for (final c in a.cards) {
          h.remove(c);
        }
        _layMeld(s, a.cards);
      case 3:
        h.remove(a.cards.first);
        final m = s.piles[3 + a.target]..add(a.cards.first);
        m.sort((x, y) => rankOf(x).compareTo(rankOf(y)));
        _refreshDisplay(s);
      case 0:
        h.remove(a.cards.first);
        s.piles[1].add(a.cards.first);
        s.vars[0] = 0;
        s.turn = (p + 1) % seats;
    }
    if (h.isEmpty) _finish(s, p);
  }

  void _reshuffle(TableState s) {
    if (s.vars[2] >= 2 || s.piles[1].length < 2) {
      _finish(s, -1);
      return;
    }
    s.vars[2]++;
    final top = s.piles[1].removeLast();
    s.piles[0].addAll(s.piles[1].reversed);
    s.piles[1]
      ..clear()
      ..add(top);
  }

  void _finish(TableState s, int winner) {
    s.over = true;
    final left = [for (final h in s.hands) h.fold<int>(0, (a, c) => a + value(c))];
    for (var p = 0; p < seats; p++) {
      s.scores[p] = p == winner ? left.fold<int>(0, (a, b) => a + b) : -left[p];
    }
  }

  @override
  String actionLabel(TAction a, String lang) => switch (a.kind) {
        1 => a.target == 0 ? kt(lang, 'drawStock') : Strings.tx(lang, 'Atıktan al', 'Take discard'),
        5 => '${kt(lang, 'meld')} ✓',
        2 => a.cards.map((c) => rankName(rankOf(c), lang)).join(' '),
        3 => '${rankName(rankOf(a.cards.first), lang)} → ${a.target + 1}',
        _ => '${Strings.tx(lang, 'Atık', 'Discard')}: ${cardsName(a.cards, lang)}',
      };

  String cardsName(List<KCard> cs, String lang) => cs.map((c) => rankName(rankOf(c), lang)).join(' ');

  @override
  bool isCardPlay(TAction a) => a.kind == 0;

  @override
  TAction quick(TableState s, SeededRandom r) {
    final p = s.turn;
    final h = s.hands[p];
    if (s.vars[0] == 0) {
      if (s.piles[1].isNotEmpty && helps(h, s.piles[1].last, runMin)) return const TAction(1, [], 1);
      return const TAction(1, [], 0);
    }
    final l = legalActions(s);
    final open = l.where((a) => a.kind == 5).toList();
    if (open.isNotEmpty) return open.first;
    final meld = l.where((a) => a.kind == 2).toList()..sort((a, b) => b.cards.length.compareTo(a.cards.length));
    if (meld.isNotEmpty) return meld.first;
    final lay = l.where((a) => a.kind == 3).toList();
    if (lay.isNotEmpty) return lay[r.nextInt(lay.length)];
    return TAction(0, [cheapDiscard(h, r, value, runMin)]);
  }

  @override
  String status(TableState s, String lang) {
    final con = contract;
    final need = con != null
        ? con.map((run) => run ? '4+' : '3').join(' + ')
        : (openMin > 0 ? '$openMin+' : '');
    final left = [for (final h in s.hands) h.length];
    return '${need.isEmpty ? '' : '${kt(lang, 'need')}: $need  ·  '}🂠 ${left.join(' · ')}';
  }
}

// ======================================================================
// Gin Remi

/// Gin Remi: iki kişi, onar kart. Desteden ya da atıktan çek, bir kart at.
/// Perlere girmeyen kartların toplamı 10 ya da altındaysa "Kapat" ile eli
/// bitirebilirsin; hiç ölü kart yoksa Gin (+25). Rakip ölü kartlarını
/// senin perlerine işler; ölü kartı senden azsa ya da eşitse o kazanır (+25).
class GinRummyRules extends TableRules {
  const GinRummyRules();

  @override
  int get seats => 2;

  @override
  List<PileView> get pileViews => const [
        PileView('Deste', 'Stock', faceUp: false),
        PileView('Atık', 'Discard'),
        PileView('Perler', 'Melds', spread: true, maxShown: 24, labels: kMeldsLabel),
      ];

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final deck = List.of(shuffled);
    final hands = [<KCard>[], <KCard>[]];
    for (var r = 0; r < 10; r++) {
      hands[0].add(deck.removeLast());
      hands[1].add(deck.removeLast());
    }
    for (final h in hands) {
      _sort(h);
    }
    return TableState(seats: 2, hands: hands, piles: [deck, [deck.removeLast()], []], turn: (dealer + 1) % 2);
  }

  void _sort(List<KCard> h) => h.sort((a, b) => (suitOf(a) * 20 + rankOf(a)).compareTo(suitOf(b) * 20 + rankOf(b)));

  @override
  List<TAction> legalActions(TableState s) {
    final h = s.hands[s.turn];
    if (s.vars[0] == 0) return [const TAction(1, [], 0), if (s.piles[1].isNotEmpty) const TAction(1, [], 1)];
    return [
      for (final c in h) TAction(0, [c]),
      for (final c in h)
        if (_loose([...h]..remove(c)).fold<int>(0, (a, x) => a + rummyValue(x)) <= 40 && deadwood([...h]..remove(c)) <= 10)
          TAction(4, [c]),
    ];
  }

  @override
  void apply(TableState s, TAction a) {
    final p = s.turn;
    final h = s.hands[p];
    s.lastSeat = p;
    s.last = a;
    if (a.kind == 1) {
      h.add(a.target == 1 ? s.piles[1].removeLast() : s.piles[0].removeLast());
      _sort(h);
      s.vars[0] = 1;
      return;
    }
    h.remove(a.cards.first);
    s.piles[1].add(a.cards.first);
    if (a.kind == 4) {
      _knock(s, p);
      return;
    }
    s.vars[0] = 0;
    s.turn = 1 - p;
    if (s.piles[0].length <= 2) {
      s.over = true; // berabere
    }
  }

  void _knock(TableState s, int p) {
    s.over = true;
    final (ms, _) = bestMeldSet(s.hands[p]);
    for (final m in ms) {
      s.piles.add(List.of(m));
    }
    s.piles[2]
      ..clear()
      ..addAll([for (final m in ms) ...m]);
    final kd = deadwood(s.hands[p]);
    // Rakip: önce kendi perleri, sonra ölü kartlarını işler
    final o = 1 - p;
    final oh = List.of(s.hands[o]);
    final (oms, _) = bestMeldSet(oh);
    final inMeld = {for (final m in oms) ...m};
    var dead = oh.where((c) => !inMeld.contains(c)).toList();
    if (kd > 0) {
      var changed = true;
      while (changed) {
        changed = false;
        for (final c in List.of(dead)) {
          for (final m in s.piles.sublist(3)) {
            if (isMeld([...m, c])) {
              m.add(c);
              dead.remove(c);
              changed = true;
              break;
            }
          }
        }
      }
    }
    final od = dead.fold<int>(0, (a, c) => a + rummyValue(c));
    s.vars[3 + p] = kd;
    s.vars[3 + o] = od;
    if (kd == 0) {
      s.scores[p] = od + 25;
    } else if (kd < od) {
      s.scores[p] = od - kd;
    } else {
      s.scores[o] = kd - od + 25;
    }
  }

  @override
  String actionLabel(TAction a, String lang) => switch (a.kind) {
        1 => a.target == 0 ? kt(lang, 'drawStock') : Strings.tx(lang, 'Atıktan al', 'Take discard'),
        4 => '${kt(lang, 'knock')}: ${rankName(rankOf(a.cards.first), lang)}',
        _ => '${Strings.tx(lang, 'Atık', 'Discard')}: ${rankName(rankOf(a.cards.first), lang)}',
      };

  @override
  bool isCardPlay(TAction a) => a.kind == 0;

  @override
  TAction quick(TableState s, SeededRandom r) {
    final h = s.hands[s.turn];
    if (s.vars[0] == 0) {
      if (s.piles[1].isNotEmpty && helps(h, s.piles[1].last, 3)) return const TAction(1, [], 1);
      return const TAction(1, [], 0);
    }
    final c = cheapDiscard(h, r, rummyValue, 3);
    final rest = [...h]..remove(c);
    final looseValue = _loose(rest).fold<int>(0, (a, x) => a + rummyValue(x));
    if (looseValue <= 16 && deadwood(rest) <= 10 && r.chance(0.9)) return TAction(4, [c]);
    return TAction(0, [c]);
  }

  @override
  String status(TableState s, String lang) {
    if (s.over && s.piles.length > 3) {
      return '${Strings.tx(lang, 'Sen', 'You')}: ${s.vars[3]}  ·  ${kt(lang, 'rival')}: ${s.vars[4]}';
    }
    return '${Strings.tx(lang, 'Deste', 'Stock')}: ${s.piles[0].length}';
  }
}
