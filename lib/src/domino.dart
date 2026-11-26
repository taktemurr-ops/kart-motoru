import 'package:studio_core/core/rng.dart';

import 'cards.dart';
import 'kart_texts.dart';
import 'table_engine.dart';
import 'tile_painter.dart';

/// Çekmeli domino (çift altılı, 28 taş). İki kişide yedişer, üç-dört kişide
/// beşer taş. Sırası gelen taşını açık uçlardan birine, sayısı tutacak şekilde
/// ekler; ekleyemezse yığından çeker, yığın bitmişse pas geçer. Elini ilk
/// bitiren, rakiplerin elindeki noktaların toplamını kazanır. Oyun kilitlenirse
/// (herkes art arda pas) en az noktası olan kazanır.
///
/// piles: 0 yığın (kapalı), 1 sıra (soldan sağa; ters duranlar +100).
/// vars: 0 sol uç, 1 sağ uç, 2 art arda pas.
class DominoRules extends TableRules {
  final int players;

  /// Maçta önceki eli kazanan: yeni eli istediği taşla açar (-1: en büyük çift).
  final int opener;
  const DominoRules([this.players = 2, this.opener = -1]);

  /// Maç: iki kişide 100, üç-dört kişide 150 puana ilk ulaşan kazanır.
  int get matchTarget => players == 2 ? 100 : 150;

  @override
  MatchFormat get matchFormat => MatchFormat(target: matchTarget);

  @override
  TableRules rulesForMatch(int deal, List<List<int>> history) => DominoRules(players, lastRowWinner(history));

  @override
  int get seats => players;
  @override
  int get tileStyle => kTileDomino;
  @override
  double get tileAspect => 1.9;
  @override
  List<KCard> deck() => [for (var a = 0; a <= 6; a++) for (var b = a; b <= 6; b++) dominoTile(a, b)];

  static const _labelsLine = [
    'Sıra', 'Line', 'Reihe', 'Fila', 'Ligne', 'الصف', 'ردیف', 'שורה', 'قطار', 'Ряд', 'Ряд', 'Rząd', 'Řada', 'Șir', 'Sor', 'Σειρά', 'Fila', 'Fila', 'Rij', 'Rad', 'Række', 'Rekke', 'Rivi', '列', '줄', '牌列', 'पंक्ति', 'সারি', 'Barisan', 'Barisan', 'แถว', 'Hàng', 'Hanay',
  ];
  static const _labelsYard = [
    'Yığın', 'Boneyard', 'Vorrat', 'Pozo', 'Pioche', 'المخزون', 'انبار', 'מאגר', 'ذخیرہ', 'Базар', 'Базар', 'Pula', 'Zásoba', 'Rezervă', 'Készlet', 'Αποθέματα', 'Riserva', 'Monte', 'Pot', 'Hög', 'Bunke', 'Haug', 'Varasto', '山', '더미', '牌堆', 'भंडार', 'ভাণ্ডার', 'Tumpukan', 'Longgokan', 'กองกลาง', 'Nọc', 'Tumpok',
  ];

  @override
  List<PileView> get pileViews => const [
        PileView('Yığın', 'Boneyard', faceUp: false, labels: _labelsYard),
        PileView('Sıra', 'Line', spread: true, maxShown: 28, labels: _labelsLine),
      ];

  int get handSize => players == 2 ? 7 : 5;

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final deck = List.of(shuffled);
    final hands = [for (var p = 0; p < seats; p++) <KCard>[]];
    for (var k = 0; k < handSize; k++) {
      for (final h in hands) {
        h.add(deck.removeLast());
      }
    }
    for (final h in hands) {
      h.sort();
    }
    // En büyük çifti olan başlar; yoksa dağıtanın solundaki.
    var starter = (dealer + 1) % seats;
    var bestDouble = -1;
    for (var p = 0; p < seats; p++) {
      for (final t in hands[p]) {
        if (dominoA(t) == dominoB(t) && dominoA(t) > bestDouble) {
          bestDouble = dominoA(t);
          starter = p;
        }
      }
    }
    if (opener >= 0 && opener < seats) starter = opener;
    final s = TableState(seats: seats, hands: hands, piles: [deck, []], turn: starter);
    s.vars[0] = s.vars[1] = -1;
    return s;
  }

  int pips(List<KCard> h) => h.fold<int>(0, (a, t) => a + dominoA(t) + dominoB(t));

  @override
  List<TAction> legalActions(TableState s) {
    if (s.over) return const [];
    final h = s.hands[s.turn];
    final out = <TAction>[];
    final l = s.vars[0], r = s.vars[1];
    for (final t in h) {
      final a = dominoA(t), b = dominoB(t);
      if (s.piles[1].isEmpty) {
        out.add(TAction(0, [t], 1));
        continue;
      }
      if (a == l || b == l) out.add(TAction(0, [t], 0));
      if ((a == r || b == r) && !(l == r && (a == l || b == l))) out.add(TAction(0, [t], 1));
    }
    if (out.isEmpty) out.add(s.piles[0].isNotEmpty ? const TAction(1) : const TAction(2));
    return out;
  }

  @override
  void apply(TableState s, TAction a) {
    final p = s.turn;
    final h = s.hands[p];
    s.lastSeat = p;
    s.last = a;
    switch (a.kind) {
      case 1:
        h.add(s.piles[0].removeLast());
        h.sort();
        s.vars[2] = 0;
        return; // aynı oyuncu yeniden dener
      case 2:
        s.vars[2]++;
        if (s.vars[2] >= seats) {
          _end(s, -1);
          return;
        }
        s.turn = (p + 1) % seats;
        return;
    }
    final t = a.cards.first;
    h.remove(t);
    final ta = dominoA(t), tb = dominoB(t);
    final line = s.piles[1];
    if (line.isEmpty) {
      line.add(t);
      s.vars[0] = ta;
      s.vars[1] = tb;
    } else if (a.target == 0) {
      // Sola: taşın sağ yarısı sol uca değmeli.
      final keepB = tb == s.vars[0];
      line.insert(0, keepB ? t : dominoFlipped(t));
      s.vars[0] = keepB ? ta : tb;
    } else {
      final keepA = ta == s.vars[1];
      line.add(keepA ? t : dominoFlipped(t));
      s.vars[1] = keepA ? tb : ta;
    }
    s.vars[2] = 0;
    if (h.isEmpty) {
      _end(s, p);
      return;
    }
    s.turn = (p + 1) % seats;
  }

  void _end(TableState s, int winner) {
    s.over = true;
    var w = winner;
    if (w < 0) {
      // Kilitlendi: en az noktası olan.
      var best = 1 << 30;
      for (var p = 0; p < seats; p++) {
        final v = pips(s.hands[p]);
        if (v < best) {
          best = v;
          w = p;
        }
      }
    }
    var total = 0;
    for (var p = 0; p < seats; p++) {
      if (p != w) total += pips(s.hands[p]);
    }
    s.scores[w] = total;
  }

  @override
  String actionLabel(TAction a, String lang) => switch (a.kind) {
        1 => kt(lang, 'drawStock'),
        2 => kt(lang, 'pass'),
        _ => a.target == 0 ? '◀' : '▶',
      };

  @override
  bool isCardPlay(TAction a) => a.kind == 0;

  @override
  TAction quick(TableState s, SeededRandom r) {
    final l = legalActions(s);
    if (l.length == 1) return l.first;
    var best = l.first;
    var bv = -1 << 20;
    final h = s.hands[s.turn];
    for (final a in l) {
      final t = a.cards.first;
      final x = dominoA(t), y = dominoB(t);
      // Büyük ve çift taşları önce ver; elde kalan sayılarla uç bırak.
      final open = a.target == 0 ? (y == s.vars[0] ? x : y) : (x == s.vars[1] ? y : x);
      final keep = h.where((u) => u != t && (dominoA(u) == open || dominoB(u) == open)).length;
      final v = (x + y) * 2 + (x == y ? 6 : 0) + keep * 3 + r.nextInt(3);
      if (v > bv) {
        bv = v;
        best = a;
      }
    }
    return best;
  }

  @override
  String status(TableState s, String lang) =>
      s.piles[1].isEmpty ? '' : '◀ ${s.vars[0]}   ·   ${s.vars[1]} ▶';
}

/// Eşli domino (Karayipler ve Latin Amerika usulü): dört kişi, karşılıklı
/// oturanlar ortak (0+2, 1+3). Çift altılıda bütün taşlar dağıtılır (yedişer);
/// çift dokuzluda onar taş dağıtılır, kalanlar kapalı kalır. Yığından çekilmez:
/// ekleyemeyen pas geçer. Elini ilk bitiren taraf, rakip ikilinin elinde kalan
/// noktaları kazanır; kilitlenirse en az noktalı oyuncunun tarafı kazanır.
/// Maç 200 puana.
class PartnerDominoRules extends DominoRules {
  /// Çift dokuzlu takım (55 taş).
  final bool nine;
  const PartnerDominoRules({this.nine = false, int opener = -1}) : super(4, opener);

  @override
  bool get partnerships => true;

  @override
  MatchFormat get matchFormat => const MatchFormat(target: 200);

  @override
  TableRules rulesForMatch(int deal, List<List<int>> history) => PartnerDominoRules(nine: nine, opener: lastRowWinner(history));

  @override
  List<KCard> deck() => nine ? [for (var a = 0; a <= 9; a++) for (var b = a; b <= 9; b++) dominoTile9(a, b)] : super.deck();

  @override
  int get handSize => nine ? 10 : 7;

  @override
  List<TAction> legalActions(TableState s) {
    final l = super.legalActions(s);
    // Yığından çekilmez: ekleyemeyen pas geçer.
    if (l.length == 1 && l.first.kind == 1) return const [TAction(2)];
    return l;
  }

  @override
  void _end(TableState s, int winner) {
    s.over = true;
    var w = winner;
    if (w < 0) {
      var best = 1 << 30;
      for (var p = 0; p < seats; p++) {
        final v = pips(s.hands[p]);
        if (v < best) {
          best = v;
          w = p;
        }
      }
    }
    var total = 0;
    for (var p = 0; p < seats; p++) {
      if (p % 2 != w % 2) total += pips(s.hands[p]);
    }
    s.scores[w] = total;
    s.scores[(w + 2) % 4] = total;
  }
}
