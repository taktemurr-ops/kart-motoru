import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'table_engine.dart';
import 'table_view.dart' show cardsLabel;

const _rankTr = ['', 'As', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'Vale', 'Kız', 'Papaz'];
const _rankEn = ['', 'Ace', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'Jack', 'Queen', 'King'];
String rankName(int r, String lang) => Strings.tx(lang, _rankTr[r], _rankEn[r]);

void _sortByRank(List<KCard> h, int Function(KCard) key) => h.sort((a, b) => key(a).compareTo(key(b)));

int _nextActive(TableState s, int from, bool Function(int) active) {
  for (var k = 1; k <= s.seats; k++) {
    final p = (from + k) % s.seats;
    if (active(p)) return p;
  }
  return from;
}

// ======================================================================
/// Başkan: aynı değerde 1–4 kart at; sonraki ya aynı sayıda daha büyük atar
/// ya da pas der. Herkes pas derse son atan yeni tura başlar. İlk biten başkan.
/// Güç sırası: 3 en küçük, 2 en büyük.
class PresidentRules extends TableRules {
  const PresidentRules();

  @override
  int get seats => 4;

  static int power(KCard c) => switch (rankOf(c)) { 2 => 15, 1 => 14, final r => r };

  // 0: masadaki son atılan takım; 1: atılanlar
  // vars: 0 takım boyu, 1 son atan, 2 bitiş sırası sayacı, 3 pas sayısı
  // scores: bitiş sırasına göre puan
  @override
  List<PileView> get pileViews => const [
        PileView('Masa', 'Table', spread: true),
        PileView('Atılan', 'Played', faceUp: false),
      ];
  @override
  Set<int> get hiddenPiles => const {};

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final hands = [for (var p = 0; p < 4; p++) <KCard>[]];
    for (var i = 0; i < shuffled.length; i++) {
      hands[i % 4].add(shuffled[i]);
    }
    for (final h in hands) {
      _sortByRank(h, power);
    }
    final start = hands.indexWhere((h) => h.contains(makeCard(3, kClubs)));
    final s = TableState(seats: 4, hands: hands, piles: [[], []], turn: start);
    s.vars[1] = -1;
    for (var p = 0; p < 4; p++) {
      s.scores[p] = -1; // henüz bitmedi
    }
    return s;
  }

  bool _out(TableState s, int p) => s.hands[p].isEmpty;

  @override
  List<TAction> legalActions(TableState s) {
    final h = s.hands[s.turn];
    final byRank = <int, List<KCard>>{};
    for (final c in h) {
      byRank.putIfAbsent(power(c), () => []).add(c);
    }
    final out = <TAction>[];
    final size = s.vars[0];
    final top = s.piles[0].isEmpty ? 0 : power(s.piles[0].first);
    byRank.forEach((pw, cards) {
      for (var n = 1; n <= cards.length; n++) {
        if (size == 0 || (n == size && pw > top)) out.add(TAction(0, cards.sublist(0, n)));
      }
    });
    if (size != 0) out.add(const TAction(1));
    return out;
  }

  @override
  bool isCardPlay(TAction a) => a.kind == 0 && a.cards.length == 1;

  @override
  String actionLabel(TAction a, String lang) => a.kind == 1 ? Strings.tx(lang, 'Pas', 'Pass') : cardsLabel(a.cards);

  @override
  void apply(TableState s, TAction a) {
    final seat = s.turn;
    s.lastSeat = seat;
    s.last = a;
    if (a.kind == 0) {
      for (final c in a.cards) {
        s.hands[seat].remove(c);
      }
      s.piles[1].addAll(s.piles[0]);
      s.piles[0]
        ..clear()
        ..addAll(a.cards);
      s.vars[0] = a.cards.length;
      s.vars[1] = seat;
      s.vars[3] = 0;
      if (_out(s, seat)) {
        s.scores[seat] = 3 - s.vars[2];
        s.vars[2]++;
        if (s.vars[2] >= 3) {
          for (var p = 0; p < 4; p++) {
            if (s.scores[p] < 0) s.scores[p] = 0;
          }
          s.over = true;
          return;
        }
      }
    } else {
      s.vars[3]++;
    }
    final active = [for (var p = 0; p < 4; p++) !_out(s, p)];
    final activeCount = active.where((x) => x).length;
    // Herkes pas dediyse masa temizlenir, son atan (bittiyse sonraki) başlar.
    final passNeeded = s.vars[1] >= 0 && !_out(s, s.vars[1]) ? activeCount - 1 : activeCount;
    if (s.vars[3] >= passNeeded && s.vars[0] != 0) {
      s.piles[1].addAll(s.piles[0]);
      s.piles[0].clear();
      s.vars[0] = 0;
      s.vars[3] = 0;
      final lead = s.vars[1];
      s.turn = !_out(s, lead) ? lead : _nextActive(s, lead, (p) => active[p]);
      return;
    }
    s.turn = _nextActive(s, seat, (p) => active[p]);
  }

  @override
  TAction quick(TableState s, SeededRandom r) {
    final l = legalActions(s);
    final plays = l.where((a) => a.kind == 0).toList();
    if (plays.isEmpty) return l.first;
    plays.sort((a, b) => (power(a.cards.first) * 4 - a.cards.length).compareTo(power(b.cards.first) * 4 - b.cards.length));
    if (s.vars[0] != 0 && r.chance(0.15)) return l.last;
    return plays.first;
  }

  @override
  String status(TableState s, String lang) {
    final names = [Strings.tx(lang, 'Başkan', 'President'), Strings.tx(lang, 'Yardımcı', 'Vice'), Strings.tx(lang, 'Halk', 'Citizen')];
    final done = <String>[];
    for (var p = 0; p < 4; p++) {
      if (s.scores[p] >= 1) done.add('${p == 0 ? Strings.tx(lang, 'Sen', 'You') : '#$p'}: ${names[3 - s.scores[p]]}');
    }
    return done.join(' · ');
  }

  @override
  List<int> finalScores(TableState s) => [for (final x in s.scores) x < 0 ? 0 : x];
}

// ======================================================================
/// Papaz Kaçtı: bir papaz çıkarılmış desteyle oynanır; eşler atılır. Sıra sende
/// yanındaki oyuncudan kapalı bir kart çekersin. Sonda tek papazla kalan kaybeder.
class OldMaidRules extends TableRules {
  const OldMaidRules();

  @override
  int get seats => 3;

  static final _maid = makeCard(13, kSpades);

  @override
  List<KCard> deck() => buildDeck()..remove(makeCard(13, kClubs));

  @override
  List<PileView> get pileViews => const [PileView('Atılan eşler', 'Pairs out', spread: true)];
  @override
  Set<int> get hiddenPiles => const {};

  void _discardPairs(TableState s, int p) {
    final h = s.hands[p];
    final byRank = <int, List<KCard>>{};
    for (final c in h) {
      byRank.putIfAbsent(rankOf(c), () => []).add(c);
    }
    byRank.forEach((r, cards) {
      for (var i = 0; i + 1 < cards.length; i += 2) {
        h.remove(cards[i]);
        h.remove(cards[i + 1]);
        s.piles[0].addAll([cards[i], cards[i + 1]]);
        s.captured[p].addAll([cards[i], cards[i + 1]]);
      }
    });
  }

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final hands = [for (var p = 0; p < 3; p++) <KCard>[]];
    for (var i = 0; i < shuffled.length; i++) {
      hands[i % 3].add(shuffled[i]);
    }
    final s = TableState(seats: 3, hands: hands, piles: [[]], turn: (dealer + 1) % 3);
    for (var p = 0; p < 3; p++) {
      _discardPairs(s, p);
      _sortByRank(s.hands[p], rankOf);
    }
    s.vars[0] = 0; // bitiren sayısı
    for (var p = 0; p < 3; p++) {
      s.scores[p] = -1;
    }
    _settle(s);
    return s;
  }

  int _source(TableState s, int seat) => _nextActive(s, seat, (p) => s.hands[p].isNotEmpty && p != seat);

  @override
  List<TAction> legalActions(TableState s) {
    final src = _source(s, s.turn);
    return [for (var i = 0; i < s.hands[src].length; i++) TAction(1, const [], i)];
  }

  @override
  String actionLabel(TAction a, String lang) => '🂠 ${a.target + 1}';

  void _settle(TableState s) {
    for (var p = 0; p < 3; p++) {
      if (s.hands[p].isEmpty && s.scores[p] < 0) {
        s.scores[p] = 2 - s.vars[0];
        s.vars[0]++;
      }
    }
    final left = [for (var p = 0; p < 3; p++) if (s.hands[p].isNotEmpty) p];
    if (left.length <= 1) {
      for (final p in left) {
        s.scores[p] = 0;
      }
      s.over = true;
    }
  }

  @override
  void apply(TableState s, TAction a) {
    final seat = s.turn;
    final src = _source(s, seat);
    final c = s.hands[src].removeAt(a.target.clamp(0, s.hands[src].length - 1));
    s.hands[seat].add(c);
    _discardPairs(s, seat);
    _sortByRank(s.hands[seat], rankOf);
    // Kartların yeri karışsın (papaz nerede bilinmesin).
    final hs = s.hands[src];
    if (hs.length > 1) {
      s.vars[5] = (s.vars[5] + 5) % 97;
      final k = s.vars[5] % hs.length;
      final rot = [...hs.sublist(k), ...hs.sublist(0, k)];
      hs
        ..clear()
        ..addAll(rot);
    }
    s.lastSeat = seat;
    s.last = a;
    _settle(s);
    if (!s.over) s.turn = _nextActive(s, seat, (p) => s.hands[p].isNotEmpty);
  }

  @override
  List<int> finalScores(TableState s) => [for (var p = 0; p < 3; p++) s.hands[p].contains(_maid) ? -5 : (s.scores[p] < 0 ? 0 : s.scores[p])];

  @override
  String status(TableState s, String lang) => Strings.pick(_oddKing, lang);
}

// ======================================================================
/// Balık Tut: elindeki bir değeri bir oyuncudan iste. Varsa hepsini alır ve
/// tekrar oynarsın; yoksa desteden çekersin. Dörtlüleri tamamlayan puan alır.
class GoFishRules extends TableRules {
  final int players;
  const GoFishRules({this.players = 3});

  @override
  int get seats => players;

  @override
  List<PileView> get pileViews => const [
        PileView('Deniz', 'Pond', faceUp: false),
        PileView('Dörtlüler', 'Books', spread: true),
      ];

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final deck = List.of(shuffled);
    final hands = [for (var p = 0; p < seats; p++) <KCard>[]];
    for (var r = 0; r < (seats == 2 ? 7 : 5); r++) {
      for (final h in hands) {
        h.add(deck.removeLast());
      }
    }
    final s = TableState(seats: seats, hands: hands, piles: [deck, []], turn: (dealer + 1) % seats);
    for (var p = 0; p < seats; p++) {
      _books(s, p);
      _sortByRank(s.hands[p], rankOf);
    }
    return s;
  }

  void _books(TableState s, int p) {
    final h = s.hands[p];
    for (var r = 1; r <= 13; r++) {
      final cs = h.where((c) => rankOf(c) == r).toList();
      if (cs.length == 4) {
        for (final c in cs) {
          h.remove(c);
        }
        s.piles[1].addAll(cs);
        s.captured[p].addAll(cs);
        s.scores[p]++;
      }
    }
  }

  @override
  List<TAction> legalActions(TableState s) {
    final h = s.hands[s.turn];
    if (h.isEmpty) return const [TAction(2)];
    final ranks = {for (final c in h) rankOf(c)}.toList()..sort();
    final out = [
      for (var p = 0; p < seats; p++)
        if (p != s.turn && s.hands[p].isNotEmpty)
          for (final r in ranks) TAction(0, const [], p * 100 + r),
    ];
    // Sorulacak kimse kalmadıysa yalnızca çekilebilir.
    return out.isEmpty ? const [TAction(2)] : out;
  }

  @override
  String actionLabel(TAction a, String lang) {
    if (a.kind == 2) return Strings.tx(lang, 'Çek', 'Draw');
    final p = a.target ~/ 100, r = a.target % 100;
    final who = seats == 2 ? '' : '${['', Strings.tx(lang, 'Sol', 'Left'), Strings.tx(lang, 'Karşı', 'Across'), Strings.tx(lang, 'Sağ', 'Right')][p]}: ';
    return '$who${rankName(r, lang)}?';
  }

  void _checkOver(TableState s) {
    final holders = s.hands.where((h) => h.isNotEmpty).length;
    if (s.piles[1].length >= 52 || (s.piles[0].isEmpty && holders <= 1)) s.over = true;
  }

  @override
  void apply(TableState s, TAction a) {
    final seat = s.turn;
    s.lastSeat = seat;
    s.last = a;
    if (a.kind == 2) {
      if (s.piles[0].isNotEmpty) s.hands[seat].add(s.piles[0].removeLast());
      _books(s, seat);
      _checkOver(s);
      s.turn = (seat + 1) % seats;
      return;
    }
    final p = a.target ~/ 100, r = a.target % 100;
    final got = s.hands[p].where((c) => rankOf(c) == r).toList();
    var again = false;
    if (got.isNotEmpty) {
      for (final c in got) {
        s.hands[p].remove(c);
      }
      s.hands[seat].addAll(got);
      again = true;
    } else if (s.piles[0].isNotEmpty) {
      final c = s.piles[0].removeLast();
      s.hands[seat].add(c);
      again = rankOf(c) == r;
    }
    _books(s, seat);
    _sortByRank(s.hands[seat], rankOf);
    _checkOver(s);
    if (!again || s.hands[seat].isEmpty) s.turn = (seat + 1) % seats;
  }

  @override
  TAction quick(TableState s, SeededRandom r) {
    final l = legalActions(s);
    return l[r.nextInt(l.length)];
  }

  @override
  String status(TableState s, String lang) => '${Strings.tx(lang, 'Dörtlü', 'Books')}: ${s.scores.join(' · ')}';
}

// ======================================================================
/// Blöf: sıradaki değeri söyleyerek 1–4 kartı kapalı at (yalan söyleyebilirsin).
/// Sonraki oyuncu "Blöf!" diyebilir: yalan varsa yalancı, yoksa itiraz eden
/// yığını alır. Elini ilk bitiren kazanır.
class CheatRules extends TableRules {
  const CheatRules();

  @override
  int get seats => 3;

  // 0: ortadaki kapalı yığın. vars: 0 sıradaki değer, 1 son atılan sayı,
  // 2 son atan (-1 yok), 3 son atış yalan mıydı (gizli bilgi; sadece kural için)
  @override
  List<PileView> get pileViews => const [PileView('Ortadaki yığın', 'Pile', faceUp: false)];
  @override
  Set<int> get hiddenPiles => const {0};

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final hands = [for (var p = 0; p < 3; p++) <KCard>[]];
    for (var i = 0; i < shuffled.length; i++) {
      hands[i % 3].add(shuffled[i]);
    }
    for (final h in hands) {
      _sortByRank(h, rankOf);
    }
    final s = TableState(seats: 3, hands: hands, piles: [[]], turn: (dealer + 1) % 3);
    s.vars[0] = 1;
    s.vars[2] = -1;
    return s;
  }

  @override
  List<TAction> legalActions(TableState s) {
    final h = s.hands[s.turn];
    final out = <TAction>[];
    if (s.vars[2] >= 0) out.add(const TAction(2)); // blöf de
    final want = s.vars[0];
    final truth = h.where((c) => rankOf(c) == want).toList();
    for (var n = 1; n <= truth.length; n++) {
      out.add(TAction(0, truth.sublist(0, n)));
    }
    // Yalanlar: tek kart ya da aynı değerden iki kart.
    final byRank = <int, List<KCard>>{};
    for (final c in h) {
      if (rankOf(c) != want) byRank.putIfAbsent(rankOf(c), () => []).add(c);
    }
    byRank.forEach((r, cs) {
      out.add(TAction(0, [cs.first]));
      if (cs.length >= 2) out.add(TAction(0, cs.sublist(0, 2)));
    });
    return out;
  }

  @override
  bool isCardPlay(TAction a) => a.kind == 0 && a.cards.length == 1;

  @override
  String actionLabel(TAction a, String lang) => a.kind == 2 ? Strings.tx(lang, 'Blöf!', 'Cheat!') : cardsLabel(a.cards);

  @override
  void apply(TableState s, TAction a) {
    final seat = s.turn;
    s.lastSeat = seat;
    s.last = a;
    if (a.kind == 2) {
      final liar = s.vars[3] == 1;
      final taker = liar ? s.vars[2] : seat;
      s.hands[taker].addAll(s.piles[0]);
      _sortByRank(s.hands[taker], rankOf);
      s.piles[0].clear();
      s.vars[2] = -1;
      if (!liar) s.scores[seat]--;
      // Önceki atan elini bitirdiyse ve haklıysa kazandı.
      for (var p = 0; p < 3; p++) {
        if (s.hands[p].isEmpty) {
          s.over = true;
          s.vars[4] = p;
          return;
        }
      }
      return; // itiraz eden oynamaya devam eder
    }
    // Önceki atan elini bitirdiyse ve kimse itiraz etmediyse kazanır.
    if (s.vars[2] >= 0 && s.hands[s.vars[2]].isEmpty) {
      s.over = true;
      s.vars[4] = s.vars[2];
      return;
    }
    for (final c in a.cards) {
      s.hands[seat].remove(c);
    }
    s.piles[0].addAll(a.cards);
    s.vars[3] = a.cards.every((c) => rankOf(c) == s.vars[0]) ? 0 : 1;
    s.vars[1] = a.cards.length;
    s.vars[2] = seat;
    s.vars[0] = s.vars[0] % 13 + 1;
    s.turn = (seat + 1) % 3;
  }

  @override
  List<int> finalScores(TableState s) => [for (var p = 0; p < 3; p++) p == s.vars[4] ? 100 : -s.hands[p].length];

  /// Yapay zekâ son atışın yalan olup olmadığını bilemez: yeniden dağıtılan
  /// yığının üstündeki kartlara bakarak tahmin eder.
  @override
  void afterDeterminize(TableState w) {
    if (w.vars[2] < 0) return;
    final n = w.vars[1].clamp(0, w.piles[0].length);
    final claimed = w.vars[0] == 1 ? 13 : w.vars[0] - 1;
    final top = w.piles[0].sublist(w.piles[0].length - n);
    w.vars[3] = top.every((c) => rankOf(c) == claimed) ? 0 : 1;
  }

  @override
  TAction quick(TableState s, SeededRandom r) {
    final l = legalActions(s);
    if (s.vars[2] >= 0 && (s.vars[1] >= 3 || r.chance(0.15))) return const TAction(2);
    final truthful = l.where((a) => a.kind == 0 && a.cards.every((c) => rankOf(c) == s.vars[0])).toList();
    if (truthful.isNotEmpty) return truthful.last;
    final plays = l.where((a) => a.kind == 0).toList();
    return plays[r.nextInt(plays.length)];
  }

  @override
  String status(TableState s, String lang) {
    final last = s.vars[2] >= 0 ? ' · ${s.vars[1]}× ${rankName(s.vars[0] == 1 ? 13 : s.vars[0] - 1, lang)}' : '';
    return '${Strings.tx(lang, 'Sıradaki', 'Next')}: ${rankName(s.vars[0], lang)}$last';
  }
}

// ======================================================================
/// 31: elinde üç kart. Desteden ya da atıktan bir kart al, bir kart at.
/// Aynı renkteki kartların toplamı (As 11, resimli 10) 31'e yaklaşsın.
/// "Kapat" dersen herkes son bir kez oynar; en yüksek el kazanır.
class ThirtyOneRules extends TableRules {
  const ThirtyOneRules();

  @override
  int get seats => 3;

  // 0 deste, 1 atık. vars: 0 aşama (0 çek, 1 at), 1 kapatan (-1), 2 kapanıştan sonra kalan tur
  @override
  List<PileView> get pileViews => const [
        PileView('Deste', 'Stock', faceUp: false),
        PileView('Atık', 'Discard'),
      ];

  static int cardValue(KCard c) => rankOf(c) == 1 ? 11 : (rankOf(c) > 10 ? 10 : rankOf(c));

  static int handValue(List<KCard> h) {
    var best = 0;
    for (var s = 0; s < 4; s++) {
      final v = h.where((c) => suitOf(c) == s).fold(0, (a, c) => a + cardValue(c));
      if (v > best) best = v;
    }
    return best;
  }

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final deck = List.of(shuffled);
    final hands = [for (var p = 0; p < 3; p++) <KCard>[]];
    for (var r = 0; r < 3; r++) {
      for (final h in hands) {
        h.add(deck.removeLast());
      }
    }
    final s = TableState(seats: 3, hands: hands, piles: [deck, [deck.removeLast()]], turn: (dealer + 1) % 3);
    s.vars[1] = -1;
    s.vars[3] = 40; // en çok tur
    return s;
  }

  @override
  List<TAction> legalActions(TableState s) {
    if (s.vars[0] == 1) return [for (final c in s.hands[s.turn]) TAction(0, [c])];
    return [
      if (s.piles[0].isNotEmpty) const TAction(1),
      if (s.piles[1].isNotEmpty) const TAction(2),
      if (s.vars[1] < 0) const TAction(3),
    ];
  }

  @override
  String actionLabel(TAction a, String lang) => switch (a.kind) {
        1 => Strings.tx(lang, 'Desteden çek', 'Draw stock'),
        2 => Strings.tx(lang, 'Atığı al', 'Take discard'),
        3 => Strings.tx(lang, 'Kapat', 'Knock'),
        _ => cardsLabel(a.cards),
      };

  void _endTurn(TableState s, int seat) {
    s.turn = (seat + 1) % 3;
    s.vars[3]--;
    if (s.vars[1] >= 0) {
      s.vars[2]--;
      if (s.vars[2] <= 0) s.over = true;
    }
    if (s.vars[3] <= 0 || (s.piles[0].isEmpty && s.vars[0] == 0 && s.piles[1].isEmpty)) s.over = true;
  }

  @override
  void apply(TableState s, TAction a) {
    final seat = s.turn;
    s.lastSeat = seat;
    s.last = a;
    switch (a.kind) {
      case 1:
        s.hands[seat].add(s.piles[0].removeLast());
        s.vars[0] = 1;
      case 2:
        s.hands[seat].add(s.piles[1].removeLast());
        s.vars[0] = 1;
      case 3:
        s.vars[1] = seat;
        s.vars[2] = 2;
        _endTurn(s, seat);
      default:
        s.hands[seat].remove(a.cards.first);
        s.piles[1].add(a.cards.first);
        s.vars[0] = 0;
        if (handValue(s.hands[seat]) == 31) {
          s.over = true;
          return;
        }
        _endTurn(s, seat);
    }
  }

  @override
  List<int> finalScores(TableState s) => [for (final h in s.hands) handValue(h)];

  @override
  TAction quick(TableState s, SeededRandom r) {
    final h = s.hands[s.turn];
    if (s.vars[0] == 1) {
      var best = h.first, bestV = -1;
      for (final c in h) {
        final v = handValue([for (final x in h) if (x != c) x]);
        if (v > bestV) {
          bestV = v;
          best = c;
        }
      }
      return TAction(0, [best]);
    }
    if (s.vars[1] < 0 && handValue(h) >= 27) return const TAction(3);
    if (s.piles[1].isNotEmpty) {
      final top = s.piles[1].last;
      final with3 = [...h, top];
      var bestV = 0;
      for (final c in with3) {
        final v = handValue([for (final x in with3) if (x != c) x]);
        if (v > bestV) bestV = v;
      }
      if (bestV > handValue(h) + 2) return const TAction(2);
    }
    return s.piles[0].isNotEmpty ? const TAction(1) : const TAction(2);
  }

  @override
  String status(TableState s, String lang) =>
      '${Strings.tx(lang, 'Elin', 'Your hand')}: ${handValue(s.hands[0])}${s.vars[1] >= 0 ? ' · ${Strings.tx(lang, 'Kapatıldı', 'Knocked')}' : ''}';
}

const _oddKing = [
  'Tek papaz sende kalmasın!', 'Don\'t get stuck with the odd king!', 'Bleib nicht auf dem letzten König sitzen!', '¡Que no te quede el rey suelto!',
  'Ne restez pas avec le roi seul !', 'لا يبقَ معك الملك الوحيد!', 'شاه تنها دستت نماند!', 'שהמלך הבודד לא יישאר אצלך!',
  'اکیلا بادشاہ آپ کے پاس نہ رہے!', 'Не останьтесь с лишним королём!', 'Не залиштеся з зайвим королем!', 'Nie zostań z samotnym królem!',
  'Nezůstaň s osamělým králem!', 'Nu rămâne cu regele singur!', 'Ne nálad maradjon a magányos király!', 'Μη μείνεις με τον μόνο βασιλιά!',
  'Non restare con il re solo!', 'Não fique com o rei sozinho!', 'Blijf niet zitten met de eenzame koning!', 'Bli inte kvar med den ensamma kungen!',
  'Bliv ikke siddende med den ensomme konge!', 'Ikke bli sittende med den ensomme kongen!', 'Älä jää yksinäisen kuninkaan kanssa!', '最後のキングを残さないで！',
  '외톨이 킹을 떠안지 마세요!', '别让落单的K留在你手里！', 'अकेला बादशाह आपके पास न रहे!', 'একা রাজা যেন আপনার কাছে না থাকে!',
  'Jangan tersisa dengan raja sendirian!', 'Jangan tinggal dengan raja bersendirian!', 'อย่าให้คิงเดี่ยวค้างมือ!', 'Đừng để kẹt vua lẻ!',
  'Huwag maiwan sa nag-iisang hari!',
];
