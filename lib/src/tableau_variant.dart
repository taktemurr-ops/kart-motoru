import 'cards.dart';
import 'solitaire_engine.dart';

/// Sütunlara dizme kuralı.
enum Build { altColor, sameSuit, anySuit, sameColor, none }

/// Sütundan kaç kart alınabilir.
enum Pick { single, ordered, anyFaceUp, supermove }

/// Boş sütuna ne konur.
enum Empty { any, king, none }

/// Kart birimleri: genişlik 1, yükseklik 1.4, aralık 0.1.
const kCardH = 1.4, kGapX = 1.12, kRowY = 1.4 + 0.28;

/// Klondike, FreeCell, Spider, Yukon, Scorpion, Forty Thieves, Canfield ve
/// solitaire paketindeki türevlerin tamamını kapsayan ayarlanabilir kurallar.
class TableauVariant extends SolitaireVariant {
  final int decks;
  final List<int> suits;
  final List<int> dealDown, dealUp;
  final Build build;
  final Build seqBuild;
  final Pick pick;
  final Empty empty;
  final int cells;
  final int reserve;
  final int draw;
  final int redeals; // -1 sınırsız
  final bool stockToTableau;
  final int stockDealPiles;
  final bool foundations; // false: Spider tarzı, tam seriler kendiliğinden çıkar
  final bool baseFromFirst; // Canfield: temel değeri ilk açılan karttan
  final bool wrap;
  final bool autoFillFromReserve;
  final bool noEmptyForDeal;

  TableauVariant({
    this.decks = 1,
    this.suits = const [0, 1, 2, 3],
    required this.dealDown,
    required this.dealUp,
    this.build = Build.altColor,
    Build? seqBuild,
    this.pick = Pick.ordered,
    this.empty = Empty.king,
    this.cells = 0,
    this.reserve = 0,
    this.draw = 1,
    this.redeals = -1,
    this.stockToTableau = false,
    this.stockDealPiles = 0,
    this.foundations = true,
    this.baseFromFirst = false,
    this.wrap = false,
    this.autoFillFromReserve = false,
    this.noEmptyForDeal = false,
  }) : seqBuild = seqBuild ?? build;

  int get tabCount => dealDown.length;
  int get foundationCount => 4 * decks;

  int get _dealt => [for (var i = 0; i < tabCount; i++) dealDown[i] + dealUp[i]].fold<int>(0, (a, b) => a + b) + reserve;
  late final bool hasStock = makeDeck().length - _dealt - (baseFromFirst ? 1 : 0) > 0;
  bool get hasWaste => hasStock && !stockToTableau;

  // Yığın indeksleri
  late final int stockIx = hasStock ? 0 : -1;
  late final int wasteIx = hasWaste ? 1 : -1;
  late final int cellStart = (hasStock ? 1 : 0) + (hasWaste ? 1 : 0);
  late final int foundStart = cellStart + cells;
  late final int reserveIx = reserve > 0 ? foundStart + foundationCount : -1;
  late final int tabStart = foundStart + foundationCount + (reserve > 0 ? 1 : 0);

  @override
  List<KCard> makeDeck() => buildDeck(decks: decks, suits: suits);

  @override
  late final List<PileSpec> layout = _layout();

  late final double _width = _computeWidth();

  double _computeWidth() {
    final top = (hasStock ? 1 : 0) + (hasWaste ? (draw > 1 ? 2 : 1) : 0) + cells + foundationCount + 0.0;
    final bottom = tabCount + (reserve > 0 ? 1 : 0) + 0.0;
    return (top > bottom ? top : bottom) * kGapX - (kGapX - 1);
  }

  @override
  double get boardWidth => _width;
  @override
  double get boardHeight => kRowY + kCardH;

  List<PileSpec> _layout() {
    final out = <PileSpec>[];
    var x = 0.0;
    if (hasStock) {
      out.add(const PileSpec(PileKind.stock, 0, 0));
      x += kGapX;
    }
    if (hasWaste) {
      out.add(PileSpec(PileKind.waste, x, 0, fan: draw > 1 ? Fan.rightLast3 : Fan.none));
      x += kGapX * (draw > 1 ? 2 : 1);
    }
    for (var i = 0; i < cells; i++) {
      out.add(PileSpec(PileKind.cell, x, 0));
      x += kGapX;
    }
    // Temeller sağa yaslı.
    final fx = _width - foundationCount * kGapX + (kGapX - 1);
    for (var i = 0; i < foundationCount; i++) {
      out.add(PileSpec(PileKind.foundation, (fx > x ? fx : x) + i * kGapX, 0,
          label: foundations ? (baseFromFirst ? null : 'A') : 'K', suitHint: null));
    }
    var tx = 0.0;
    if (reserve > 0) {
      out.add(const PileSpec(PileKind.reserve, 0, kRowY, fan: Fan.down));
      tx = kGapX;
    }
    for (var i = 0; i < tabCount; i++) {
      out.add(PileSpec(PileKind.tableau, tx + i * kGapX, kRowY, fan: Fan.down));
    }
    return out;
  }

  @override
  SolState deal(List<KCard> shuffled) {
    final n = layout.length;
    final piles = List.generate(n, (_) => <KCard>[]);
    final down = List<int>.filled(n, 0);
    var k = 0;
    if (reserve > 0) {
      piles[reserveIx].addAll(shuffled.sublist(k, k + reserve));
      down[reserveIx] = reserve - 1;
      k += reserve;
    }
    var base = 1;
    if (baseFromFirst) {
      piles[foundStart].add(shuffled[k]);
      base = rankOf(shuffled[k]);
      k++;
    }
    for (var i = 0; i < tabCount; i++) {
      final c = dealDown[i] + dealUp[i];
      piles[tabStart + i].addAll(shuffled.sublist(k, k + c));
      down[tabStart + i] = dealDown[i];
      k += c;
    }
    if (hasStock) {
      piles[stockIx].addAll(shuffled.sublist(k));
      down[stockIx] = piles[stockIx].length;
    }
    return SolState(piles, down, counter: base);
  }

  int baseRank(SolState s) => baseFromFirst ? s.counter : 1;

  PileKind kindOf(int p) => layout[p].kind;

  bool _follows(KCard lower, KCard upper, Build b) {
    // upper, lower'ın üstüne konur: upper bir küçük.
    final lr = rankOf(lower), ur = rankOf(upper);
    final ok = ur == lr - 1 || (wrap && lr == 1 && ur == 13);
    if (!ok) return false;
    return switch (b) {
      Build.altColor => isRed(lower) != isRed(upper),
      Build.sameSuit => suitOf(lower) == suitOf(upper),
      Build.sameColor => isRed(lower) == isRed(upper),
      Build.anySuit => true,
      Build.none => false,
    };
  }

  bool _isSequence(List<KCard> p, int from) {
    for (var i = from; i + 1 < p.length; i++) {
      if (!_follows(p[i], p[i + 1], seqBuild)) return false;
    }
    return true;
  }

  int _emptyTableaus(SolState s, {int except = -1}) {
    var n = 0;
    for (var i = 0; i < tabCount; i++) {
      final p = tabStart + i;
      if (p != except && s.piles[p].isEmpty) n++;
    }
    return n;
  }

  int _freeCells(SolState s) {
    var n = 0;
    for (var i = 0; i < cells; i++) {
      if (s.piles[cellStart + i].isEmpty) n++;
    }
    return n;
  }

  @override
  bool canPick(SolState s, int pile, int index) {
    final p = s.piles[pile];
    if (index < 0 || index >= p.length) return false;
    switch (kindOf(pile)) {
      case PileKind.waste:
      case PileKind.cell:
        return index == p.length - 1;
      case PileKind.reserve:
        return index == p.length - 1 && s.faceUp(pile, index);
      case PileKind.tableau:
        if (!s.faceUp(pile, index)) return false;
        return switch (pick) {
          Pick.single => index == p.length - 1,
          Pick.anyFaceUp => true,
          Pick.ordered || Pick.supermove => _isSequence(p, index),
        };
      default:
        return false;
    }
  }

  bool _toFoundation(SolState s, KCard c, int to) {
    final f = s.piles[to];
    if (f.isEmpty) return rankOf(c) == baseRank(s);
    final t = f.last;
    if (suitOf(t) != suitOf(c)) return false;
    final want = rankOf(t) == 13 ? (wrap ? 1 : 0) : rankOf(t) + 1;
    return rankOf(c) == want && f.length < 13;
  }

  @override
  bool canDrop(SolState s, int from, int index, int to) {
    if (from == to) return false;
    final src = s.piles[from];
    final count = src.length - index;
    if (count <= 0) return false;
    final first = src[index];
    switch (kindOf(to)) {
      case PileKind.foundation:
        return foundations && count == 1 && _toFoundation(s, first, to);
      case PileKind.cell:
        return count == 1 && s.piles[to].isEmpty;
      case PileKind.tableau:
        final dst = s.piles[to];
        if (pick == Pick.supermove && count > 1) {
          final cap = (_freeCells(s) + 1) * (1 << _emptyTableaus(s, except: to));
          if (count > cap) return false;
        }
        if (dst.isEmpty) {
          return switch (empty) {
            Empty.any => true,
            Empty.king => rankOf(first) == (wrap ? (baseRank(s) == 1 ? 13 : baseRank(s) - 1) : 13),
            Empty.none => false,
          };
        }
        return _follows(dst.last, first, build);
      default:
        return false;
    }
  }

  @override
  void afterMove(SolState s) {
    if (!foundations) _collectRuns(s);
    if (autoFillFromReserve && reserve > 0) {
      for (var i = 0; i < tabCount; i++) {
        final p = tabStart + i;
        if (s.piles[p].isEmpty && s.piles[reserveIx].isNotEmpty) {
          s.piles[p].add(s.piles[reserveIx].removeLast());
        }
      }
      if (s.down[reserveIx] >= s.piles[reserveIx].length) {
        s.down[reserveIx] = s.piles[reserveIx].isEmpty ? 0 : s.piles[reserveIx].length - 1;
      }
    }
    super.afterMove(s);
  }

  /// Spider: üstte açık K…A aynı renk seri varsa çıkar.
  void _collectRuns(SolState s) {
    for (var i = 0; i < tabCount; i++) {
      final p = tabStart + i;
      final pile = s.piles[p];
      if (pile.length < 13) continue;
      final st = pile.length - 13;
      if (st < s.down[p]) continue;
      if (rankOf(pile[st]) != 13) continue;
      var ok = true;
      for (var k = st; k + 1 < pile.length; k++) {
        if (!(rankOf(pile[k + 1]) == rankOf(pile[k]) - 1 && suitOf(pile[k + 1]) == suitOf(pile[k]))) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      final run = pile.sublist(st);
      pile.removeRange(st, pile.length);
      for (var f = 0; f < foundationCount; f++) {
        if (s.piles[foundStart + f].isEmpty) {
          s.piles[foundStart + f].addAll(run);
          break;
        }
      }
      s.counter++;
    }
  }

  @override
  bool canStock(SolState s) {
    if (!hasStock) return false;
    final st = s.piles[stockIx];
    if (stockToTableau) {
      if (st.isEmpty) return false;
      if (noEmptyForDeal && _emptyTableaus(s) > 0) return false;
      return true;
    }
    if (st.isNotEmpty) return true;
    return s.piles[wasteIx].isNotEmpty && (redeals < 0 || s.passes < redeals);
  }

  @override
  void stock(SolState s) {
    final st = s.piles[stockIx];
    if (stockToTableau) {
      final n = stockDealPiles > 0 ? stockDealPiles : tabCount;
      for (var i = 0; i < n && st.isNotEmpty; i++) {
        s.piles[tabStart + i].add(st.removeLast());
      }
    } else if (st.isNotEmpty) {
      for (var i = 0; i < draw && st.isNotEmpty; i++) {
        s.piles[wasteIx].add(st.removeLast());
      }
    } else {
      final w = s.piles[wasteIx];
      st.addAll(w.reversed);
      w.clear();
      s.passes++;
    }
    s.down[stockIx] = st.length;
    if (wasteIx >= 0) s.down[wasteIx] = 0;
  }

  @override
  bool isWon(SolState s) {
    if (!foundations) return s.piles.sublist(foundStart, foundStart + foundationCount).every((f) => f.length == 13);
    var n = 0;
    for (var f = 0; f < foundationCount; f++) {
      n += s.piles[foundStart + f].length;
    }
    return n == totalCards;
  }

  @override
  late final int totalCards = makeDeck().length;

  @override
  int progress(SolState s) {
    var n = 0;
    for (var f = 0; f < foundationCount; f++) {
      n += s.piles[foundStart + f].length;
    }
    return n;
  }

  @override
  int priority(SolState s, SolMove m) {
    if (m.isStock) return 9;
    final tk = kindOf(m.to), fk = kindOf(m.from);
    if (tk == PileKind.foundation) return 0;
    if (fk == PileKind.tableau && m.index > 0 && m.index == s.down[m.from]) return 1;
    if (fk == PileKind.tableau && m.index == 0 && s.piles[m.to].isNotEmpty) return 2; // sütunu boşaltır
    if (fk == PileKind.waste || fk == PileKind.reserve) return 3;
    if (fk == PileKind.cell && tk == PileKind.tableau) return 3;
    if (tk == PileKind.tableau && s.piles[m.to].isEmpty) return 6;
    if (tk == PileKind.cell) return 7;
    return 5;
  }

  @override
  bool useless(SolState s, SolMove m) {
    if (m.isStock) return false;
    final fk = kindOf(m.from), tk = kindOf(m.to);
    if (fk == PileKind.cell && tk == PileKind.cell) return true;
    if (fk != PileKind.tableau || tk != PileKind.tableau) return false;
    final src = s.piles[m.from];
    // Bütün sütunu (altında kapalı kart yokken) boş sütuna taşımak.
    if (m.index == 0 && s.piles[m.to].isEmpty) return true;
    // Zaten doğal yerinde duran seriyi başka sütuna kaydırmak.
    if (m.index > 0 && m.index > s.down[m.from] && _follows(src[m.index - 1], src[m.index], seqBuild)) {
      return true;
    }
    return false;
  }

  @override
  List<int> tapTargets(SolState s, int from, int index) {
    final t = super.tapTargets(s, from, index);
    int rank(int p) {
      final k = kindOf(p);
      if (k == PileKind.foundation) return 0;
      if (k == PileKind.tableau && s.piles[p].isNotEmpty) return 1;
      if (k == PileKind.tableau) return 2;
      return 3;
    }

    t.sort((a, b) => rank(a).compareTo(rank(b)));
    return t;
  }

  @override
  bool canAutoFinish(SolState s) {
    if (!foundations) return false;
    if (hasStock && s.piles[stockIx].isNotEmpty) return false;
    if (hasWaste && s.piles[wasteIx].isNotEmpty) return false;
    if (reserve > 0 && s.piles[reserveIx].isNotEmpty) return false;
    for (var i = 0; i < tabCount; i++) {
      if (s.down[tabStart + i] > 0) return false;
    }
    return !isWon(s);
  }

  /// Bitirme için sıradaki temel hamlesi.
  SolMove? nextFinishMove(SolState s) {
    for (final m in legalMoves(s)) {
      if (!m.isStock && kindOf(m.to) == PileKind.foundation) return m;
    }
    return null;
  }
}
