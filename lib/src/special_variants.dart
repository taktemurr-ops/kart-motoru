import 'dart:math' as math;

import 'package:studio_core/core/rng.dart';

import 'cards.dart';
import 'solitaire_engine.dart';

/// Tek kartlık konumlardan oluşan, üstü kapalı kartların açılmayı beklediği
/// türler (Piramit, Üç Tepe) için ortak yardımcılar.
abstract class _CoveredVariant extends SolitaireVariant {
  _CoveredVariant();

  /// Konum sayısı ve her konumun üstünü örten konumlar.
  int get spots;
  List<List<int>> get coveredBy;
  List<Offset2> get spotPos;

  int get stockIx => spots;
  int get wasteIx => spots + 1;
  int get foundIx => spots + 2;

  bool exposed(SolState s, int p) => p < spots && s.piles[p].isNotEmpty && coveredBy[p].every((q) => s.piles[q].isEmpty);

  @override
  void afterMove(SolState s) {
    for (var p = 0; p < spots; p++) {
      if (s.down[p] > 0 && exposed(s, p)) s.down[p] = 0;
    }
  }

  @override
  bool isWon(SolState s) {
    for (var p = 0; p < spots; p++) {
      if (s.piles[p].isNotEmpty) return false;
    }
    return true;
  }

  @override
  int progress(SolState s) {
    var n = 0;
    for (var p = 0; p < spots; p++) {
      if (s.piles[p].isEmpty) n++;
    }
    return n;
  }

  @override
  int get totalCards => spots;

  @override
  int priority(SolState s, SolMove m) {
    if (m.isStock) return 9;
    if (m.from < spots) return 1;
    return 4;
  }
}

class Offset2 {
  final double x, y;
  const Offset2(this.x, this.y);
}

/// Piramit: toplamı 13 eden iki açık kartı çıkar; Papaz tek başına çıkar.
class PyramidVariant extends _CoveredVariant {
  final int redealsAllowed;
  PyramidVariant({this.redealsAllowed = 2});

  @override
  int get spots => 28;

  @override
  late final List<List<int>> coveredBy = () {
    final out = <List<int>>[];
    for (var r = 0; r < 7; r++) {
      for (var k = 0; k <= r; k++) {
        if (r == 6) {
          out.add(const []);
        } else {
          final next = (r + 1) * (r + 2) ~/ 2;
          out.add([next + k, next + k + 1]);
        }
      }
    }
    return out;
  }();

  @override
  late final List<Offset2> spotPos = [
    for (var r = 0; r < 7; r++)
      for (var k = 0; k <= r; k++) Offset2((6 - r) * 0.56 + k * 1.12, r * 0.52),
  ];

  @override
  late final List<PileSpec> layout = [
    for (final p in spotPos) PileSpec(PileKind.free, p.x, p.y),
    const PileSpec(PileKind.stock, 0, 6 * 0.52 + 1.7),
    const PileSpec(PileKind.waste, 1.12, 6 * 0.52 + 1.7),
    PileSpec(PileKind.foundation, 6 * 1.12, 6 * 0.52 + 1.7, label: 'K'),
  ];

  @override
  double get boardWidth => 6 * 1.12 + 1;
  @override
  double get boardHeight => 6 * 0.52 + 1.7 + 1.4;

  @override
  SolState deal(List<KCard> shuffled) {
    final piles = <List<KCard>>[for (var i = 0; i < 28; i++) [shuffled[i]]];
    piles.add(shuffled.sublist(28));
    piles.add([]);
    piles.add([]);
    return SolState(piles, [...List.filled(28, 0), 24, 0, 0]);
  }

  bool _open(SolState s, int p) => p == wasteIx ? s.piles[p].isNotEmpty : exposed(s, p);

  @override
  bool canPick(SolState s, int pile, int index) =>
      _open(s, pile) && index == s.piles[pile].length - 1;

  @override
  bool canDrop(SolState s, int from, int index, int to) {
    if (!_open(s, from)) return false;
    final c = s.piles[from].last;
    if (to == foundIx) return rankOf(c) == 13;
    if (to == stockIx || to == from || !_open(s, to)) return false;
    return rankOf(c) + rankOf(s.piles[to].last) == 13;
  }

  @override
  void move(SolState s, int from, int index, int to) {
    final c = s.piles[from].removeLast();
    s.piles[foundIx].add(c);
    if (to != foundIx) s.piles[foundIx].add(s.piles[to].removeLast());
    afterMove(s);
  }

  @override
  bool canStock(SolState s) => s.piles[stockIx].isNotEmpty || (s.piles[wasteIx].isNotEmpty && s.passes < redealsAllowed);

  @override
  void stock(SolState s) {
    final st = s.piles[stockIx], w = s.piles[wasteIx];
    if (st.isNotEmpty) {
      w.add(st.removeLast());
    } else {
      st.addAll(w.reversed);
      w.clear();
      s.passes++;
    }
    s.down[stockIx] = st.length;
  }

  @override
  List<int> tapTargets(SolState s, int from, int index) {
    final c = s.piles[from].last;
    if (rankOf(c) == 13) return [foundIx];
    return super.tapTargets(s, from, index)..remove(foundIx);
  }
}

/// Üç Tepe: açık kartı atık kartından bir büyük ya da bir küçükse at.
class TriPeaksVariant extends _CoveredVariant {
  final bool wrap;
  TriPeaksVariant({this.wrap = true});

  @override
  int get spots => 28;

  // Satırlar: 3 tepe, 6, 9, 10.
  static const _rowStart = [0, 3, 9, 18];

  @override
  late final List<List<int>> coveredBy = () {
    final out = List.generate(28, (_) => <int>[]);
    for (var p = 0; p < 3; p++) {
      out[_rowStart[0] + p] = [_rowStart[1] + 2 * p, _rowStart[1] + 2 * p + 1];
    }
    for (var i = 0; i < 6; i++) {
      final p = i ~/ 2, q = i % 2;
      out[_rowStart[1] + i] = [_rowStart[2] + p * 3 + q, _rowStart[2] + p * 3 + q + 1];
    }
    for (var i = 0; i < 9; i++) {
      out[_rowStart[2] + i] = [_rowStart[3] + i, _rowStart[3] + i + 1];
    }
    return out;
  }();

  @override
  late final List<Offset2> spotPos = [
    for (var p = 0; p < 3; p++) Offset2(1.53 + p * 3.06, 0),
    for (var i = 0; i < 6; i++) Offset2(1.02 + (i ~/ 2) * 3.06 + (i % 2) * 1.02, 0.55),
    for (var i = 0; i < 9; i++) Offset2(0.51 + i * 1.02, 1.1),
    for (var i = 0; i < 10; i++) Offset2(i * 1.02, 1.65),
  ];

  @override
  late final List<PileSpec> layout = [
    for (final p in spotPos) PileSpec(PileKind.free, p.x, p.y),
    const PileSpec(PileKind.stock, 3.0, 3.4),
    const PileSpec(PileKind.waste, 5.0, 3.4),
    const PileSpec(PileKind.free, 99, 99), // atık zaten temel görevi görür
  ];

  @override
  double get boardWidth => 9 * 1.02 + 1;
  @override
  double get boardHeight => 3.4 + 1.4;

  @override
  SolState deal(List<KCard> shuffled) {
    final piles = <List<KCard>>[for (var i = 0; i < 28; i++) [shuffled[i]]];
    piles.add(shuffled.sublist(29));
    piles.add([shuffled[28]]);
    piles.add([]);
    return SolState(piles, [...List.filled(18, 1), ...List.filled(10, 0), 23, 0, 0]);
  }

  bool _adjacent(KCard a, KCard b) {
    final d = (rankOf(a) - rankOf(b)).abs();
    return d == 1 || (wrap && d == 12);
  }

  @override
  bool canPick(SolState s, int pile, int index) => exposed(s, pile) && s.down[pile] == 0;

  @override
  bool canDrop(SolState s, int from, int index, int to) =>
      to == wasteIx && exposed(s, from) && s.piles[to].isNotEmpty && _adjacent(s.piles[from].last, s.piles[to].last);

  @override
  bool canStock(SolState s) => s.piles[stockIx].isNotEmpty;

  @override
  void stock(SolState s) {
    s.piles[wasteIx].add(s.piles[stockIx].removeLast());
    s.down[stockIx] = s.piles[stockIx].length;
  }
}

/// Golf: yedi sütun; sütunların üstündeki kartı atık kartından bir büyük ya
/// da bir küçükse at. Papazın üstüne kart gelmez (sarma yok).
class GolfVariant extends SolitaireVariant {
  final bool wrap;
  GolfVariant({this.wrap = false});

  static const _cols = 7;
  int get stockIx => _cols;
  int get wasteIx => _cols + 1;

  @override
  late final List<PileSpec> layout = [
    for (var i = 0; i < _cols; i++) PileSpec(PileKind.tableau, i * 1.12, 0, fan: Fan.down),
    const PileSpec(PileKind.stock, 1.12, 4.0),
    const PileSpec(PileKind.waste, 3.36, 4.0, label: '±1'),
  ];

  @override
  double get boardWidth => 6 * 1.12 + 1;
  @override
  double get boardHeight => 4.0 + 1.4;

  @override
  SolState deal(List<KCard> shuffled) {
    final piles = <List<KCard>>[for (var i = 0; i < _cols; i++) shuffled.sublist(i * 5, i * 5 + 5)];
    piles.add(shuffled.sublist(36));
    piles.add([shuffled[35]]);
    return SolState(piles, [...List.filled(_cols, 0), 16, 0]);
  }

  bool _adjacent(KCard a, KCard b) {
    final d = (rankOf(a) - rankOf(b)).abs();
    if (!wrap && rankOf(b) == 13) return false;
    return d == 1 || (wrap && d == 12);
  }

  @override
  bool canPick(SolState s, int pile, int index) => pile < _cols && index == s.piles[pile].length - 1;

  @override
  bool canDrop(SolState s, int from, int index, int to) =>
      from < _cols &&
      to == wasteIx &&
      s.piles[from].isNotEmpty &&
      s.piles[to].isNotEmpty &&
      _adjacent(s.piles[from].last, s.piles[to].last);

  @override
  void afterMove(SolState s) {}

  @override
  bool canStock(SolState s) => s.piles[stockIx].isNotEmpty;

  @override
  void stock(SolState s) {
    s.piles[wasteIx].add(s.piles[stockIx].removeLast());
    s.down[stockIx] = s.piles[stockIx].length;
  }

  @override
  bool isWon(SolState s) {
    for (var i = 0; i < _cols; i++) {
      if (s.piles[i].isNotEmpty) return false;
    }
    return true;
  }

  @override
  int progress(SolState s) => 35 - [for (var i = 0; i < _cols; i++) s.piles[i].length].fold<int>(0, (a, b) => a + b);

  @override
  int get totalCards => 35;

  @override
  int priority(SolState s, SolMove m) => m.isStock ? 9 : 1;
}

/// Akordeon: bir yığını hemen solundaki ya da üç solundaki yığının üstüne,
/// üst kartları aynı renk ya da aynı değerse koy. Hedef: yığın sayısını
/// bölümün istediği sayıya indir.
class AccordionVariant extends SolitaireVariant {
  final int target;
  AccordionVariant({required this.target});

  static const _cols = 13;

  @override
  late final List<PileSpec> layout = [
    for (var i = 0; i < 52; i++) PileSpec(PileKind.free, (i % _cols) * 1.06, (i ~/ _cols) * 1.55),
  ];

  @override
  double get boardWidth => (_cols - 1) * 1.06 + 1;
  @override
  double get boardHeight => 3 * 1.55 + 1.4;

  @override
  SolState deal(List<KCard> shuffled) =>
      SolState([for (final c in shuffled) [c]], List.filled(52, 0));

  int _left(SolState s, int p, int steps) {
    var q = p;
    for (var k = 0; k < steps; k++) {
      q--;
      while (q >= 0 && s.piles[q].isEmpty) {
        q--;
      }
      if (q < 0) return -1;
    }
    return q;
  }

  @override
  bool canPick(SolState s, int pile, int index) => s.piles[pile].isNotEmpty && index == s.piles[pile].length - 1;

  @override
  bool canDrop(SolState s, int from, int index, int to) {
    if (s.piles[from].isEmpty || s.piles[to].isEmpty) return false;
    if (to != _left(s, from, 1) && to != _left(s, from, 3)) return false;
    final a = s.piles[from].last, b = s.piles[to].last;
    return suitOf(a) == suitOf(b) || rankOf(a) == rankOf(b);
  }

  @override
  void move(SolState s, int from, int index, int to) {
    s.piles[to].addAll(s.piles[from]);
    s.piles[from].clear();
  }

  @override
  void afterMove(SolState s) {}

  int piles(SolState s) => s.piles.where((p) => p.isNotEmpty).length;

  @override
  bool isWon(SolState s) => piles(s) <= target;

  @override
  int progress(SolState s) => 52 - piles(s);

  @override
  int get totalCards => 52 - target;

  @override
  int priority(SolState s, SolMove m) => s.piles[m.from].length > 1 ? 1 : 2;
}

/// Saat: kapalı kartı aç, değerinin saat konumuna koy; oradan yenisini al.
/// Dört papaz bitmeden bütün kartları açarsan kazanırsın. Karar yoktur;
/// bölümler yalnızca kazanılan dağıtımlardan seçilir.
class ClockVariant extends SolitaireVariant {
  ClockVariant();

  static const hand = 13;

  @override
  late final List<PileSpec> layout = [
    for (var i = 0; i < 13; i++)
      () {
        if (i == 12) return const PileSpec(PileKind.tableau, 2.6, 1.9);
        // Saat yönünde: 1 (As) saat 1 konumunda.
        final ang = (i + 1) * math.pi / 6 - math.pi / 2;
        return PileSpec(PileKind.tableau, 2.6 + 2.5 * _cos(ang), 1.9 + 2.3 * _sin(ang),
            label: rankLabel(i + 1));
      }(),
    const PileSpec(PileKind.free, 2.6, 1.9 + 0.5),
  ];

  static double _cos(double a) => math.cos(a);
  static double _sin(double a) => math.sin(a);

  @override
  double get boardWidth => 6.2;
  @override
  double get boardHeight => 6.2;

  @override
  SolState deal(List<KCard> shuffled) {
    final piles = <List<KCard>>[for (var i = 0; i < 13; i++) shuffled.sublist(i * 4, i * 4 + 4)];
    final down = List<int>.filled(14, 4);
    // İlk kart: papaz yığınının üstü.
    piles.add([piles[12].removeLast()]);
    down[12] = 3;
    down[hand] = 0;
    return SolState(piles, down);
  }

  @override
  bool canPick(SolState s, int pile, int index) => pile == hand && s.piles[hand].isNotEmpty;

  @override
  bool canDrop(SolState s, int from, int index, int to) =>
      from == hand && s.piles[hand].isNotEmpty && to == rankOf(s.piles[hand].last) - 1;

  @override
  void move(SolState s, int from, int index, int to) {
    final c = s.piles[hand].removeLast();
    s.piles[to].add(c);
    // Sıradaki kart bu yığının kapalı kartlarından.
    if (s.down[to] > 0) {
      final i = s.down[to] - 1;
      final next = s.piles[to].removeAt(i);
      s.down[to] = i;
      s.piles[hand].add(next);
    }
  }

  @override
  void afterMove(SolState s) {}

  @override
  bool isWon(SolState s) => s.piles[hand].isEmpty && s.down.every((d) => d == 0);

  @override
  int progress(SolState s) => 52 - s.down.fold<int>(0, (a, b) => a + b) - s.piles[hand].length;

  @override
  int get totalCards => 52;

  /// Dağıtım kazanılır mı? (Karar olmadığı için düz benzetim.)
  bool wins(SolState start) {
    final s = start.copy();
    while (s.piles[hand].isNotEmpty) {
      move(s, hand, 0, rankOf(s.piles[hand].last) - 1);
    }
    return isWon(s);
  }
}

/// Saat için yalnızca kazanılan dağıtımları kurar.
SolState clockDeal(SolitaireVariant v, SeededRandom r) {
  final c = v as ClockVariant;
  SolState? last;
  for (var i = 0; i < 2000; i++) {
    final deck = c.makeDeck();
    shuffleCards(deck, r);
    final s = c.deal(deck);
    if (c.wins(s)) return s;
    last = s;
  }
  return last!;
}
