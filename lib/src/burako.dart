import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'kart_texts.dart';
import 'rummy.dart' show kMeldsLabel;
import 'table_engine.dart';
import 'table_games2.dart' show rankName;

/// Burako (Burraco ailesi): iki deste, ikiler joker. Kanastadan farkı: perler
/// aynı sayıdan (ayak) ya da aynı renkten sıralı (merdiven) olabilir, her
/// perde en çok bir joker bulunur; atık destesinin tamamı koşulsuz alınır ve
/// herkesin bir "ölü"sü (kapalı 11 kart) vardır.
/// İkişer kişi, 11'er kart. Desteden bir kart çek ya da bütün atığı al; per
/// aç ya da perlerine işle; bir kart at. Elin bitince ölünü alıp oynamaya
/// devam edersin. Bitmek için ölünü almış ve en az bir burako (7+ kartlık
/// per) yapmış olmalısın. Burako jokersiz 200, jokerli 100; bitiren 100 alır.
/// Kart değerleri: İki 20, As 15, 8–Papaz 10, 3–7 5. Elde kalan kartlar
/// eksi, alınmamış ölü −100 yazar. Bu sürümde ayrı joker kartı yoktur.
///
/// piles: 0 deste, 1 atık, 2 benim perlerim (görünüm), 3 rakibin perleri
/// (görünüm), 4.. oyuncu başına [maxMelds] per, sonra iki ölü.
/// vars: 0 çekildi mi, 1 ölüsünü alanlar (bit), 2 deste yenilendi, 3 bitiren + 1.
class BurakoRules extends TableRules {
  const BurakoRules();

  @override
  int get seats => 2;

  @override
  MatchFormat get matchFormat => const MatchFormat(target: 2000);

  @override
  bool get heuristicAI => true;

  @override
  List<KCard> deck() => buildDeck(decks: 2);

  static const maxMelds = 15, handSize = 11, _base = 4;
  static int meldIx(int p, int k) => _base + p * maxMelds + k;
  static int deadIx(int p) => _base + 2 * maxMelds + p;

  static const _rivalMelds = [
    'Rakibin perleri', 'Rival\'s melds', 'Meldungen des Gegners', 'Combinaciones del rival', 'Combinaisons adverses', 'تشكيلات الخصم',
    'دست‌های حریف', 'צירופי היריב', 'مخالف کے ملاپ', 'Комбинации соперника', 'Комбінації суперника', 'Układy rywala', 'Kombinace soupeře',
    'Combinațiile adversarului', 'Az ellenfél kombinációi', 'Συνδυασμοί αντιπάλου', 'Combinazioni avversarie', 'Combinações do rival',
    'Combinaties van tegenstander', 'Motståndarens kombinationer', 'Modstanderens kombinationer', 'Motstanderens kombinasjoner',
    'Vastustajan yhdistelmät', '相手の役', '상대의 조합', '对手的组合', 'प्रतिद्वंद्वी के संयोजन', 'প্রতিপক্ষের সংযোগ', 'Kombinasi lawan',
    'Kombinasi lawan', 'ชุดไพ่ของคู่แข่ง', 'Bộ bài đối thủ', 'Mga meld ng kalaban',
  ];

  @override
  List<PileView> get pileViews => const [
        PileView('Deste', 'Stock', faceUp: false),
        PileView('Atık', 'Discard', spread: true, maxShown: 8),
        PileView('Perler', 'Melds', spread: true, maxShown: 60, labels: kMeldsLabel),
        PileView('Rakip', 'Rival', spread: true, maxShown: 60, labels: _rivalMelds),
      ];

  @override
  Set<int> get hiddenPiles => {0, deadIx(0), deadIx(1)};

  static bool isWild(KCard c) => rankOf(c) == 2;

  static int value(KCard c) {
    final r = rankOf(c);
    if (r == 2) return 20;
    if (r == 1) return 15;
    return r >= 8 ? 10 : 5;
  }

  /// Geçerli per: en az 3 kart, en az 2 doğal, en çok 1 joker; doğallar ya
  /// aynı sayı ya da aynı renkten sıralı (boşluk jokerle dolar, As iki uçta).
  static bool validMeld(List<KCard> m) {
    if (m.length < 3) return false;
    final nat = m.where((c) => !isWild(c)).toList();
    final w = m.length - nat.length;
    if (w > 1 || nat.length < 2) return false;
    if (nat.every((c) => rankOf(c) == rankOf(nat.first))) return true;
    if (nat.any((c) => suitOf(c) != suitOf(nat.first))) return false;
    for (final aceHigh in [false, true]) {
      final rs = [for (final c in nat) rankOf(c) == 1 && aceHigh ? 14 : rankOf(c)]..sort();
      var dup = false;
      for (var i = 1; i < rs.length; i++) {
        if (rs[i] == rs[i - 1]) dup = true;
      }
      if (dup) continue;
      final span = rs.last - rs.first + 1;
      final gaps = span - rs.length;
      if (gaps > w) continue;
      if (span + (w - gaps) > 14) continue;
      return true;
    }
    return false;
  }

  static bool isRun(List<KCard> m) {
    final nat = m.where((c) => !isWild(c)).toList();
    return nat.length >= 2 && !nat.every((c) => rankOf(c) == rankOf(nat.first));
  }

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final deck = List.of(shuffled);
    final hands = [<KCard>[], <KCard>[]];
    final dead = [<KCard>[], <KCard>[]];
    for (var r = 0; r < handSize; r++) {
      for (var p = 0; p < 2; p++) {
        hands[p].add(deck.removeLast());
        dead[p].add(deck.removeLast());
      }
    }
    for (final h in hands) {
      _sort(h);
    }
    final piles = <List<KCard>>[
      deck,
      [deck.removeLast()],
      [],
      [],
      for (var i = 0; i < 2 * maxMelds; i++) <KCard>[],
      dead[0],
      dead[1],
    ];
    return TableState(seats: 2, hands: hands, piles: piles, turn: (dealer + 1) % 2);
  }

  static void _sort(List<KCard> h) =>
      h.sort((a, b) => ((isWild(a) ? 5 : suitOf(a)) * 20 + rankOf(a)).compareTo((isWild(b) ? 5 : suitOf(b)) * 20 + rankOf(b)));

  bool deadTaken(TableState s, int p) => (s.vars[1] >> p) & 1 == 1;

  List<List<KCard>> meldsOf(TableState s, int p) => [for (var k = 0; k < maxMelds; k++) if (s.piles[meldIx(p, k)].isNotEmpty) s.piles[meldIx(p, k)]];

  int burakos(TableState s, int p) => meldsOf(s, p).where((m) => m.length >= 7).length;

  bool canGoOut(TableState s, int p) => deadTaken(s, p) && burakos(s, p) >= 1;

  /// Eldeki kartlarla açılabilecek yeni perler.
  static List<List<KCard>> newMelds(List<KCard> h) {
    final out = <List<KCard>>[];
    final wilds = h.where(isWild).toList();
    final byRank = <int, List<KCard>>{};
    for (final c in h) {
      if (!isWild(c)) byRank.putIfAbsent(rankOf(c), () => []).add(c);
    }
    for (final g in byRank.values) {
      if (g.length >= 3) out.add(List.of(g));
      if (g.length == 2 && wilds.isNotEmpty) out.add([...g, wilds.first]);
    }
    for (var su = 0; su < 4; su++) {
      final by = <int, KCard>{};
      for (final c in h) {
        if (!isWild(c) && suitOf(c) == su) {
          by.putIfAbsent(rankOf(c), () => c);
          if (rankOf(c) == 1) by.putIfAbsent(14, () => c);
        }
      }
      // Ardışık bölümler.
      final segs = <List<KCard>>[];
      var cur = <KCard>[];
      for (var r = 1; r <= 14; r++) {
        final c = by[r];
        if (c != null && !cur.contains(c)) {
          cur.add(c);
        } else {
          if (cur.isNotEmpty) segs.add(cur);
          cur = <KCard>[];
          if (c != null) cur.add(c);
        }
      }
      if (cur.isNotEmpty) segs.add(cur);
      for (var i = 0; i < segs.length; i++) {
        final sg = segs[i];
        if (sg.length >= 3) out.add(List.of(sg));
        if (sg.length == 2 && wilds.isNotEmpty) out.add([...sg, wilds.first]);
        // Tek boşluk jokerle: iki bölüm birleşir.
        if (i + 1 < segs.length && wilds.isNotEmpty) {
          final joined = [...sg, wilds.first, ...segs[i + 1]];
          if (validMeld(joined)) out.add(joined);
        }
      }
    }
    final seen = <String>{};
    return [
      for (final m in out)
        if (validMeld(m) && seen.add((List.of(m)..sort()).join(','))) m
    ];
  }

  @override
  List<TAction> legalActions(TableState s) {
    if (s.over) return const [];
    final p = s.turn;
    final h = s.hands[p];
    if (s.vars[0] == 0) {
      return [const TAction(1, [], 0), if (s.piles[1].isNotEmpty) const TAction(1, [], 1)];
    }
    final out = <TAction>[];
    final melds = meldsOf(s, p);
    bool leaves(int used, {bool makesBurako = false}) =>
        h.length - used >= 2 || !deadTaken(s, p) || canGoOut(s, p) || (makesBurako && deadTaken(s, p));
    if (melds.length < maxMelds) {
      for (final m in newMelds(h)) {
        if (leaves(m.length, makesBurako: m.length >= 7)) out.add(TAction(2, m));
      }
    }
    final seen = <KCard>{};
    for (final c in h) {
      if (!seen.add(c)) continue;
      for (var k = 0; k < maxMelds; k++) {
        final m = s.piles[meldIx(p, k)];
        if (m.isEmpty) continue;
        if (validMeld([...m, c]) && leaves(1, makesBurako: m.length + 1 >= 7)) out.add(TAction(3, [c], k));
      }
    }
    final dseen = <KCard>{};
    for (final c in h) {
      if (!dseen.add(c)) continue;
      if (h.length > 1 || !deadTaken(s, p) || canGoOut(s, p)) out.add(TAction(0, [c]));
    }
    if (out.isEmpty && h.isNotEmpty) out.add(TAction(0, [h.first]));
    return out;
  }

  void _refresh(TableState s) {
    for (var p = 0; p < 2; p++) {
      s.piles[2 + p]
        ..clear()
        ..addAll([for (final m in meldsOf(s, p)) ...m]);
    }
  }

  @override
  void apply(TableState s, TAction a) {
    final p = s.turn;
    final h = s.hands[p];
    s.lastSeat = p;
    s.last = a;
    switch (a.kind) {
      case 1:
        if (a.target == 1) {
          h.addAll(s.piles[1]);
          s.piles[1].clear();
        } else {
          if (s.piles[0].isEmpty) _restock(s);
          if (s.over) return;
          h.add(s.piles[0].removeLast());
        }
        _sort(h);
        s.vars[0] = 1;
        return;
      case 2:
        for (final c in a.cards) {
          h.remove(c);
        }
        for (var k = 0; k < maxMelds; k++) {
          if (s.piles[meldIx(p, k)].isEmpty) {
            s.piles[meldIx(p, k)].addAll(a.cards);
            break;
          }
        }
        _refresh(s);
      case 3:
        h.remove(a.cards.first);
        s.piles[meldIx(p, a.target)].add(a.cards.first);
        _sortMeld(s.piles[meldIx(p, a.target)]);
        _refresh(s);
      default:
        h.remove(a.cards.first);
        s.piles[1].add(a.cards.first);
        s.vars[0] = 0;
        s.turn = 1 - p;
    }
    if (h.isEmpty) {
      if (!deadTaken(s, p)) {
        h.addAll(s.piles[deadIx(p)]);
        s.piles[deadIx(p)].clear();
        s.vars[1] |= 1 << p;
        _sort(h);
      } else {
        _finish(s, canGoOut(s, p) ? p : -1);
      }
    }
  }

  static void _sortMeld(List<KCard> m) {
    if (!isRun(m)) return;
    m.sort((a, b) => (isWild(a) ? 50 : rankOf(a)).compareTo(isWild(b) ? 50 : rankOf(b)));
  }

  void _restock(TableState s) {
    if (s.vars[2] >= 1 || s.piles[1].length < 4) {
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

  static int meldPoints(List<KCard> m) {
    final base = m.fold<int>(0, (a, c) => a + value(c));
    if (m.length >= 7) return base + (m.any(isWild) ? 100 : 200);
    return base;
  }

  List<int> points(TableState s) => [
        for (var p = 0; p < 2; p++)
          meldsOf(s, p).fold<int>(0, (a, m) => a + meldPoints(m)) -
              s.hands[p].fold<int>(0, (a, c) => a + value(c)) -
              (deadTaken(s, p) ? 0 : 100) +
              (s.over && s.vars[3] == p + 1 ? 100 : 0),
      ];

  void _finish(TableState s, int winner) {
    s.over = true;
    s.vars[3] = winner + 1;
    final pt = points(s);
    s.scores[0] = pt[0];
    s.scores[1] = pt[1];
  }

  @override
  List<int> finalScores(TableState s) => s.over ? s.scores : points(s);

  @override
  String actionLabel(TAction a, String lang) => switch (a.kind) {
        1 => a.target == 0 ? kt(lang, 'drawStock') : Strings.tx(lang, 'Atığı al', 'Take the pile'),
        2 => '${kt(lang, 'meld')}: ${a.cards.map((c) => rankName(rankOf(c), lang)).join(' ')}',
        3 => '${rankName(rankOf(a.cards.first), lang)} → ${a.target + 1}',
        _ => '${Strings.tx(lang, 'Atık', 'Discard')}: ${rankName(rankOf(a.cards.first), lang)}',
      };

  @override
  bool isCardPlay(TAction a) => a.kind == 0;

  static bool _helps(List<KCard> h, KCard c) {
    if (isWild(c)) return true;
    if (h.where((x) => !isWild(x) && rankOf(x) == rankOf(c)).length >= 2) return true;
    return h.where((x) => !isWild(x) && suitOf(x) == suitOf(c) && (rankOf(x) - rankOf(c)).abs() <= 2 && rankOf(x) != rankOf(c)).length >= 2;
  }

  @override
  TAction quick(TableState s, SeededRandom r) {
    final l = legalActions(s);
    if (l.length == 1) return l.first;
    final p = s.turn;
    final h = s.hands[p];
    if (s.vars[0] == 0) {
      final pile = s.piles[1];
      final take = pile.isNotEmpty && (_helps(h, pile.last) && (pile.length >= 2 || r.chance(0.6)) || pile.length >= 6);
      return take && l.length > 1 ? l[1] : l.first;
    }
    // İşle (jokeri en son), sonra en uzun yeni per.
    final adds = l.where((a) => a.kind == 3).toList()..sort((a, b) => (isWild(a.cards.first) ? 1 : 0).compareTo(isWild(b.cards.first) ? 1 : 0));
    if (adds.isNotEmpty && !isWild(adds.first.cards.first)) return adds.first;
    final news = l.where((a) => a.kind == 2).toList()..sort((a, b) => b.cards.length.compareTo(a.cards.length));
    if (news.isNotEmpty) return news.first;
    // Jokeri yalnızca burakoya yaklaşan pere işle.
    for (final a in adds) {
      if (s.piles[meldIx(p, a.target)].length >= 5) return a;
    }
    final disc = l.where((a) => a.kind == 0).toList();
    if (disc.isEmpty) return l.first;
    int keep(KCard c) {
      if (isWild(c)) return 1000;
      final same = h.where((x) => x != c && rankOf(x) == rankOf(c)).length;
      final adj = h.where((x) => x != c && suitOf(x) == suitOf(c) && (rankOf(x) - rankOf(c)).abs() <= 2).length;
      return same * 12 + adj * 9 - value(c) + r.nextInt(3);
    }

    disc.sort((a, b) => keep(a.cards.first).compareTo(keep(b.cards.first)));
    return disc.first;
  }

  @override
  String status(TableState s, String lang) {
    final pt = points(s);
    return '${Strings.tx(lang, 'Puan', 'Points')}: ${pt[0]} · ${pt[1]}  ·  ${Strings.tx(lang, 'Deste', 'Stock')}: ${s.piles[0].length}'
        '  ·  ${Strings.tx(lang, 'Ölü', 'Pot')}: ${deadTaken(s, 0) ? '✓' : '11'}';
  }
}
