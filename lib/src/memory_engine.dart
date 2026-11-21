import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

import 'cards.dart';

/// Eşleşme kuralı: aynı kart, aynı sayı + aynı renk, ya da yalnızca aynı sayı.
enum MemoryMatch { exact, rankColor, rank }

/// Kart hafıza bölümü: kapalı kartlar bir ızgarada; eşlerini bul.
class MemoryLevel {
  final int cols, rows;
  final List<KCard> cards;
  final MemoryMatch match;

  /// Başta bütün kartların kaç saniye açık gösterileceği (0: hiç).
  final int peekSeconds;
  final int seed;
  const MemoryLevel(this.cols, this.rows, this.cards, this.match, this.peekSeconds, this.seed);

  int get pairs => cards.length ~/ 2;

  bool matches(KCard a, KCard b) => switch (match) {
        MemoryMatch.exact => rankOf(a) == rankOf(b) && suitOf(a) == suitOf(b),
        MemoryMatch.rankColor => rankOf(a) == rankOf(b) && isRed(a) == isRed(b),
        MemoryMatch.rank => rankOf(a) == rankOf(b),
      };

  /// 3 yıldız için en çok hamle (bir hamle = iki kart açmak).
  int get threeStarMoves => (pairs * 1.6).ceil();
  int get twoStarMoves => (pairs * 2.4).ceil();
}

/// Zorluk 1–10 → ızgara boyu, kural ve ön izleme.
MemoryLevel generateMemoryLevel(LevelSpec spec) {
  final d = spec.difficulty.clamp(1, 10);
  final r = SeededRandom(mixSeed([spec.seed, 67]));
  const sizes = [(3, 2), (4, 3), (4, 4), (5, 4), (6, 4), (6, 5), (6, 6), (6, 6), (7, 6), (8, 6)];
  final (cols, rows) = sizes[d - 1];
  final match = d <= 5
      ? MemoryMatch.exact
      : d <= 7
          ? MemoryMatch.rankColor
          : MemoryMatch.rank;
  final peek = d <= 2 ? 3 : (d <= 4 ? 2 : (d <= 6 ? 1 : 0));
  final pairs = cols * rows ~/ 2;
  final cards = <KCard>[];
  final used = <int>{};
  while (cards.length < pairs * 2) {
    final rank = 1 + r.nextInt(13);
    final suit = r.nextInt(4);
    switch (match) {
      case MemoryMatch.exact:
        final key = rank * 4 + suit;
        if (!used.add(key) && used.length < 52) continue;
        cards
          ..add(makeCard(rank, suit, 0))
          ..add(makeCard(rank, suit, 1));
      case MemoryMatch.rankColor:
        // Aynı renkteki iki farklı desen: maça+sinek ya da kupa+karo.
        final red = r.nextInt(2) == 1;
        final pair = red ? [kHearts, kDiamonds] : [kSpades, kClubs];
        final key = rank * 2 + (red ? 1 : 0);
        if (!used.add(key) && used.length < 26) continue;
        cards
          ..add(makeCard(rank, pair[0], 0))
          ..add(makeCard(rank, pair[1], 0));
      case MemoryMatch.rank:
        final s2 = (suit + 1 + r.nextInt(3)) % 4;
        cards
          ..add(makeCard(rank, suit, 0))
          ..add(makeCard(rank, s2, 1));
    }
  }
  shuffleCards(cards, r);
  return MemoryLevel(cols, rows, cards, match, peek, spec.seed);
}

/// Oyun durumu.
class MemoryGame {
  final MemoryLevel level;
  final Set<int> matched = {};
  int? first;
  int moves = 0;
  int misses = 0;

  /// Bir kez açılmış (görülmüş) kartlar: yapay "hatırlama" ipucu ve istatistik için.
  final Set<int> seen = {};

  MemoryGame(this.level);

  bool get won => matched.length == level.cards.length;

  /// Bir karta dokun. Dönüş: null (ilk kart açıldı), true (eş), false (eş değil).
  bool? pick(int i) {
    if (matched.contains(i) || i == first) return null;
    seen.add(i);
    final f = first;
    if (f == null) {
      first = i;
      return null;
    }
    first = null;
    moves++;
    if (level.matches(level.cards[f], level.cards[i])) {
      matched..add(f)..add(i);
      return true;
    }
    misses++;
    return false;
  }

  /// İpucu: henüz eşlenmemiş bir çift (açık ilk kart varsa onun eşi).
  (int, int)? hint() {
    final n = level.cards.length;
    final f = first;
    for (var a = 0; a < n; a++) {
      if (matched.contains(a)) continue;
      if (f != null && a != f) continue;
      for (var b = 0; b < n; b++) {
        if (b == a || matched.contains(b)) continue;
        if (level.matches(level.cards[a], level.cards[b])) return (a, b);
      }
    }
    return null;
  }

  int stars(int hints) {
    if (!won) return 0;
    if (hints == 0 && moves <= level.threeStarMoves) return 3;
    return moves <= level.twoStarMoves ? 2 : 1;
  }

  String serialize() => [matched.join(','), moves, misses, seen.join(',')].join('|');

  static MemoryGame restore(MemoryLevel level, String s) {
    final g = MemoryGame(level);
    final p = s.split('|');
    if (p.length < 4) return g;
    if (p[0].isNotEmpty) g.matched.addAll(p[0].split(',').map(int.parse));
    g.moves = int.tryParse(p[1]) ?? 0;
    g.misses = int.tryParse(p[2]) ?? 0;
    if (p[3].isNotEmpty) g.seen.addAll(p[3].split(',').map(int.parse));
    return g;
  }
}
