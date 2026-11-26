import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'kart_texts.dart';
import 'rummy.dart' show kMeldsLabel;
import 'table_engine.dart';
import 'table_games2.dart' show rankName;

/// Çinçon (Chinchón): İspanyol destesiyle (40 kart: 1–7, 10 uşak, 11 atlı,
/// 12 kral) remi. 2–4 kişi, yedişer kart. Sırası gelen desteden ya da atığın
/// üstünden bir kart çeker, sonra bir kart atar. Per: aynı sayıdan 3–4 kart
/// ya da aynı renkten art arda en az 3 kart (7'den sonra 10 gelir).
/// Perlere girmeyen kartların toplamı 3 ya da altındaysa atarken "Kapat"
/// denir; el biter, herkes perlere girmeyen kartlarının değerini ceza yazar
/// (resimliler 10). Bütün kartları perde kapatan −10 yazar; yedi kartlık aynı
/// renk seri "Çinçon"dur ve maçı hemen kazandırır. Maç: 100 cezaya ulaşan
/// olunca en az cezalı kazanır.
///
/// piles: 0 deste (kapalı), 1 atık, 2 kapatanın perleri.
/// vars: 0 çekildi mi, 1 kapatan + 1, 2 Çinçon, 3.. ceza.
class ChinchonRules extends TableRules {
  final int players;
  const ChinchonRules([this.players = 2]);

  @override
  int get seats => players;

  @override
  bool get spanishDeck => true;

  @override
  MatchFormat get matchFormat => const MatchFormat(target: 100, lowWins: true);

  @override
  List<KCard> deck() => buildDeck(ranks: const [1, 2, 3, 4, 5, 6, 7, 11, 12, 13]);

  @override
  List<PileView> get pileViews => const [
        PileView('Deste', 'Stock', faceUp: false),
        PileView('Atık', 'Discard'),
        PileView('Perler', 'Melds', spread: true, maxShown: 8, labels: kMeldsLabel),
      ];

  static const handSize = 7, closeMax = 3;

  /// Seri sırası: 1..7, uşak 8, atlı 9, kral 10.
  static int ord(KCard c) => rankOf(c) <= 7 ? rankOf(c) : rankOf(c) - 3;
  static int value(KCard c) => rankOf(c) <= 7 ? rankOf(c) : 10;

  static bool isSet(List<KCard> m) => m.length >= 3 && m.length <= 4 && m.every((c) => rankOf(c) == rankOf(m.first));

  static bool isRun(List<KCard> m) {
    if (m.length < 3 || m.any((c) => suitOf(c) != suitOf(m.first))) return false;
    final o = [for (final c in m) ord(c)]..sort();
    for (var i = 1; i < o.length; i++) {
      if (o[i] != o[i - 1] + 1) return false;
    }
    return true;
  }

  static List<List<KCard>> melds(List<KCard> hand) {
    final out = <List<KCard>>[];
    final byRank = <int, List<KCard>>{};
    for (final c in hand) {
      byRank.putIfAbsent(rankOf(c), () => []).add(c);
    }
    for (final g in byRank.values) {
      if (g.length == 4) {
        out.add(List.of(g));
        for (var skip = 0; skip < 4; skip++) {
          out.add([for (var i = 0; i < 4; i++) if (i != skip) g[i]]);
        }
      } else if (g.length == 3) {
        out.add(List.of(g));
      }
    }
    for (var su = 0; su < 4; su++) {
      final byOrd = <int, KCard>{for (final c in hand) if (suitOf(c) == su) ord(c): c};
      for (var a = 1; a <= 10; a++) {
        for (var b = a + 2; b <= 10; b++) {
          if (![for (var o = a; o <= b; o++) byOrd.containsKey(o)].every((x) => x)) break;
          out.add([for (var o = a; o <= b; o++) byOrd[o]!]);
        }
      }
    }
    return out;
  }

  /// En çok değeri perlere koyan seçim: (perler, ölü kartlar).
  static (List<List<KCard>>, List<KCard>) arrange(List<KCard> hand) {
    final ms = melds(hand);
    var best = <List<KCard>>[];
    var bestV = -1;
    final cur = <List<KCard>>[];
    final used = <KCard>{};
    void go(int i, int v) {
      if (v > bestV) {
        bestV = v;
        best = List.of(cur);
      }
      for (var k = i; k < ms.length; k++) {
        final m = ms[k];
        if (m.any(used.contains)) continue;
        used.addAll(m);
        cur.add(m);
        go(k + 1, v + m.fold<int>(0, (a, c) => a + value(c)) * 4 + m.length);
        cur.removeLast();
        used.removeAll(m);
      }
    }

    go(0, 0);
    final inMeld = {for (final m in best) ...m};
    return (best, [for (final c in hand) if (!inMeld.contains(c)) c]);
  }

  static int deadwood(List<KCard> hand) => arrange(hand).$2.fold<int>(0, (a, c) => a + value(c));

  /// Yedi kartlık aynı renk seri.
  static bool chinchon(List<KCard> hand) => hand.length == 7 && isRun(hand);

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
    return TableState(seats: seats, hands: hands, piles: [deck, [deck.removeLast()], []], turn: (dealer + 1) % seats, vars: List.filled(8, 0));
  }

  void _sort(List<KCard> h) => h.sort((a, b) => (suitOf(a) * 20 + ord(a)).compareTo(suitOf(b) * 20 + ord(b)));

  bool canClose(List<KCard> rest) => deadwood(rest) <= closeMax;

  @override
  List<TAction> legalActions(TableState s) {
    if (s.over) return const [];
    final h = s.hands[s.turn];
    if (s.vars[0] == 0) {
      return [if (s.piles[0].isNotEmpty) const TAction(1, [], 0), if (s.piles[1].isNotEmpty) const TAction(1, [], 1)];
    }
    final seen = <KCard>{};
    return [
      for (final c in h) TAction(0, [c]),
      for (final c in h)
        if (seen.add(c) && canClose([...h]..remove(c))) TAction(4, [c]),
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
      _close(s, p);
      return;
    }
    s.vars[0] = 0;
    s.turn = (p + 1) % seats;
    if (s.piles[0].isEmpty) {
      // Deste bitti: atık (üstteki hariç) ters çevrilip yeni deste olur;
      // ikinci kez bitince el kapanmadan sayılır.
      if (s.vars[7] >= 1 || s.piles[1].length < 3) {
        _close(s, -1);
        return;
      }
      s.vars[7]++;
      final top = s.piles[1].removeLast();
      s.piles[0].addAll(s.piles[1].reversed);
      s.piles[1]
        ..clear()
        ..add(top);
    }
  }

  void _close(TableState s, int closer) {
    s.over = true;
    s.vars[1] = closer + 1;
    if (closer >= 0) {
      final (ms, _) = arrange(s.hands[closer]);
      s.piles[2]
        ..clear()
        ..addAll([for (final m in ms) ...m]);
      if (chinchon(s.hands[closer])) s.vars[2] = 1;
    }
    for (var p = 0; p < seats; p++) {
      final dw = deadwood(s.hands[p]);
      s.vars[3 + p] = p == closer && dw == 0 ? -10 : dw;
      s.scores[p] = -s.vars[3 + p];
    }
    if (s.vars[2] == 1) {
      for (var p = 0; p < seats; p++) {
        s.scores[p] = p == closer ? 100 : -100;
      }
    }
  }

  /// Maç: el cezaları; Çinçon yapan dışındakiler doğrudan 100'e ulaşır.
  @override
  List<int> matchPoints(TableState s) {
    final closer = s.vars[1] - 1;
    if (s.vars[2] == 1) return [for (var p = 0; p < seats; p++) p == closer ? -10 : 100];
    return [for (var p = 0; p < seats; p++) s.vars[3 + p]];
  }

  @override
  String actionLabel(TAction a, String lang) => switch (a.kind) {
        1 => a.target == 0 ? kt(lang, 'drawStock') : Strings.tx(lang, 'Atıktan al', 'Take discard'),
        4 => '${kt(lang, 'knock')}: ${rankName(rankOf(a.cards.first), lang)}',
        _ => '${Strings.tx(lang, 'Atık', 'Discard')}: ${rankName(rankOf(a.cards.first), lang)}',
      };

  @override
  bool isCardPlay(TAction a) => a.kind == 0;

  /// Atık kartı bir perin parçası olur ya da iki kartlık bir başlangıcı
  /// tamamlar mı?
  static bool helps(List<KCard> hand, KCard c) {
    if (hand.where((x) => rankOf(x) == rankOf(c)).length >= 2) return true;
    final near = hand.where((x) => suitOf(x) == suitOf(c) && (ord(x) - ord(c)).abs() <= 2 && x != c).length;
    return near >= 2 && melds([...hand, c]).any((m) => m.contains(c));
  }

  static KCard cheapest(List<KCard> hand, SeededRandom r) {
    final (_, dead) = arrange(hand);
    final pool = dead.isNotEmpty ? dead : hand;
    var best = pool.first;
    var bv = -1 << 20;
    for (final c in pool) {
      final pairs = hand.where((x) => x != c && rankOf(x) == rankOf(c)).length;
      final adj = hand.where((x) => suitOf(x) == suitOf(c) && (ord(x) - ord(c)).abs() == 1).length;
      final v = value(c) * 2 - pairs * 7 - adj * 6 + r.nextInt(3);
      if (v > bv) {
        bv = v;
        best = c;
      }
    }
    return best;
  }

  @override
  TAction quick(TableState s, SeededRandom r) {
    final h = s.hands[s.turn];
    if (s.vars[0] == 0) {
      if (s.piles[1].isNotEmpty && (helps(h, s.piles[1].last) || s.piles[0].isEmpty)) return const TAction(1, [], 1);
      return s.piles[0].isNotEmpty ? const TAction(1, [], 0) : const TAction(1, [], 1);
    }
    // Çinçon ya da sıfır ölü kartla kapatma fırsatı.
    for (final c in h) {
      final rest = [...h]..remove(c);
      if (chinchon(rest) || deadwood(rest) == 0) return TAction(4, [c]);
    }
    final c = cheapest(h, r);
    final rest = [...h]..remove(c);
    if (canClose(rest) && r.chance(0.92)) return TAction(4, [c]);
    return TAction(0, [c]);
  }

  @override
  String status(TableState s, String lang) {
    if (s.over) {
      return [for (var p = 0; p < seats; p++) '${p + 1}: ${s.vars[3 + p]}'].join('  ·  ');
    }
    return '${Strings.tx(lang, 'Deste', 'Stock')}: ${s.piles[0].length}';
  }
}
