import 'dart:convert';

import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import 'cards.dart';

/// Kart Karesi: verilen kartları kare ızgaraya diz; satır, sütun (ve ileri
/// bölümlerde köşegen) toplamları hedef sayıya eşit olsun. As 1, resimli
/// kartlar 10 sayılır.
int squareValue(KCard c) => rankOf(c) >= 10 ? 10 : rankOf(c);

class SquareLevel {
  final int n;
  final int target;

  /// Tutturulması gereken çizgi sayısı (satırlar + sütunlar [+ köşegenler]).
  final int required;
  final bool diagonals;
  final List<KCard> cards;

  /// Çözüm: hücre → kart sırası ([cards] içindeki).
  final List<int> solution;
  final int seed;
  const SquareLevel(this.n, this.target, this.required, this.diagonals, this.cards, this.solution, this.seed);

  int get lineCount => 2 * n + (diagonals ? 2 : 0);
}

class SquareGame {
  final SquareLevel level;

  /// hücre → kart sırası (yoksa -1).
  final List<int> grid;
  int moves = 0;
  SquareGame(this.level) : grid = List.filled(level.n * level.n, -1);

  bool placed(int card) => grid.contains(card);
  List<int> get tray => [for (var i = 0; i < level.cards.length; i++) if (!placed(i)) i];

  List<List<int>> get lines {
    final n = level.n;
    return [
      for (var r = 0; r < n; r++) [for (var c = 0; c < n; c++) r * n + c],
      for (var c = 0; c < n; c++) [for (var r = 0; r < n; r++) r * n + c],
      if (level.diagonals) ...[
        [for (var i = 0; i < n; i++) i * n + i],
        [for (var i = 0; i < n; i++) i * n + (n - 1 - i)],
      ],
    ];
  }

  /// Çizginin toplamı; boş hücre varsa null.
  int? lineSum(List<int> cells) {
    var s = 0;
    for (final c in cells) {
      if (grid[c] < 0) return null;
      s += squareValue(level.cards[grid[c]]);
    }
    return s;
  }

  /// Boş hücreler dahil kısmi toplam (ekranda gösterilir).
  int partialSum(List<int> cells) => cells.fold<int>(0, (a, c) => a + (grid[c] < 0 ? 0 : squareValue(level.cards[grid[c]])));

  int get goodLines => lines.where((l) => lineSum(l) == level.target).length;
  bool get full => !grid.contains(-1);
  bool get won => full && goodLines >= level.required;

  /// Kartı hücreye koy; hücredeki kart (varsa) kartın eski yerine gider.
  void put(int card, int cell) {
    final from = grid.indexOf(card);
    final prev = grid[cell];
    if (from == cell) return;
    grid[cell] = card;
    if (from >= 0) grid[from] = prev;
    moves++;
  }

  /// Kartı ızgaradan kaldır.
  void lift(int cell) {
    if (grid[cell] < 0) return;
    grid[cell] = -1;
    moves++;
  }

  /// İpucu: değeri çözümle uyuşmayan ilk hücre ve oraya gidecek kart.
  (int card, int cell)? hint() {
    final sol = level.solution;
    int want(int cell) => squareValue(level.cards[sol[cell]]);
    bool right(int cell) => grid[cell] >= 0 && squareValue(level.cards[grid[cell]]) == want(cell);
    for (var cell = 0; cell < grid.length; cell++) {
      if (right(cell)) continue;
      // Önce eldeki kartlardan, yoksa yanlış yerdeki bir karttan.
      for (final k in tray) {
        if (squareValue(level.cards[k]) == want(cell)) return (k, cell);
      }
      for (var o = 0; o < grid.length; o++) {
        if (o != cell && !right(o) && grid[o] >= 0 && squareValue(level.cards[grid[o]]) == want(cell)) return (grid[o], cell);
      }
    }
    return null;
  }

  String serialize() => jsonEncode({'g': grid, 'm': moves});

  static SquareGame restore(SquareLevel l, String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    final g = SquareGame(l);
    final gr = j['g'] as List;
    for (var i = 0; i < g.grid.length && i < gr.length; i++) {
      g.grid[i] = (gr[i] as num).toInt();
    }
    g.moves = (j['m'] as num?)?.toInt() ?? 0;
    return g;
  }
}

/// Bütün satır ve sütunları (istenirse köşegenleri de) hedefe eşit bir değer
/// ızgarası kur.
List<int>? _valueGrid(int n, int target, bool diag, SeededRandom r, int tries) {
  final avail = List<int>.generate(11, (v) => v == 10 ? 16 : (v == 0 ? 0 : 4));
  for (var t = 0; t < tries; t++) {
    final g = List<int>.filled(n * n, 0);
    for (var i = 0; i < n - 1; i++) {
      for (var j = 0; j < n - 1; j++) {
        g[i * n + j] = 1 + r.nextInt(10);
      }
    }
    var ok = true;
    for (var i = 0; i < n - 1 && ok; i++) {
      var s = 0;
      for (var j = 0; j < n - 1; j++) {
        s += g[i * n + j];
      }
      final v = target - s;
      if (v < 1 || v > 10) ok = false;
      g[i * n + n - 1] = v;
    }
    for (var j = 0; j < n && ok; j++) {
      var s = 0;
      for (var i = 0; i < n - 1; i++) {
        s += g[i * n + j];
      }
      final v = target - s;
      if (v < 1 || v > 10) ok = false;
      g[(n - 1) * n + j] = v;
    }
    if (!ok) continue;
    // Son satır toplamı (köşe tutarlılığı) kendiliğinden hedefe eşit.
    if (diag) {
      var d1 = 0, d2 = 0;
      for (var i = 0; i < n; i++) {
        d1 += g[i * n + i];
        d2 += g[i * n + n - 1 - i];
      }
      if (d1 != target || d2 != target) continue;
    }
    final cnt = List<int>.filled(11, 0);
    for (final v in g) {
      cnt[v]++;
    }
    if ([for (var v = 1; v <= 10; v++) cnt[v] <= avail[v]].every((x) => x)) return g;
  }
  return null;
}

SquareLevel generateSquareLevel(LevelSpec spec) {
  final d = spec.difficulty.clamp(1, 10);
  final n = d <= 3 ? 3 : 4;
  final target = n == 3 ? 15 : 21;
  final diag = d >= 9;
  final required = switch (d) { 1 => 3, 2 => 4, 3 => 6, 4 => 4, 5 => 5, 6 => 6, 7 => 7, 8 => 8, 9 => 9, _ => 10 };
  for (var attempt = 0;; attempt++) {
    final r = SeededRandom(mixSeed([spec.seed, 515, attempt]));
    final vals = _valueGrid(n, target, diag, r, diag ? 400000 : 20000);
    if (vals == null) continue;
    // Değerlere kart seç: 10 için 10, Vale, Kız ya da Papaz.
    final byVal = <int, List<KCard>>{};
    for (final c in buildDeck()) {
      byVal.putIfAbsent(squareValue(c), () => []).add(c);
    }
    for (final l in byVal.values) {
      shuffleCards(l, r);
    }
    final solCards = [for (final v in vals) byVal[v]!.removeLast()];
    final order = List<int>.generate(solCards.length, (i) => i);
    shuffleCards(order, r);
    // cards[k] = solCards[order[k]] → çözümde hücre c, cards'taki sırası order.indexOf(c).
    final cards = [for (final o in order) solCards[o]];
    final solution = [for (var c = 0; c < solCards.length; c++) order.indexOf(c)];
    return SquareLevel(n, target, required, diag, cards, solution, spec.seed);
  }
}

class SquareRules extends GameRules<SquareLevel> {
  @override
  final String gameId;
  SquareRules({required this.gameId});

  @override
  int get levelCount => 100000;

  @override
  List<String> get optionalMechanics => const [];

  @override
  List<GameModeId> get modes => const [GameModeId.campaign, GameModeId.daily, GameModeId.weekly, GameModeId.challenge];

  @override
  List<GameStat> get gameStats => const [
        GameStat('lines_made', 'Tutan çizgi', 'Lines made', scale: 100),
        GameStat('perfect_squares', 'Kusursuz kare', 'Perfect squares', scale: 5),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('lines', 'lines_made', [15, 45, 120]),
        MissionTemplate('perfect', 'perfect_squares', [1, 3, 6]),
      ];

  @override
  SquareLevel generate(LevelSpec spec) => generateSquareLevel(spec);

  @override
  Validation validate(SquareLevel level, LevelSpec spec) {
    final g = SquareGame(level);
    for (var c = 0; c < level.solution.length; c++) {
      g.put(level.solution[c], c);
    }
    return g.won && g.goodLines == level.lineCount ? Validation.ok(level.required) : const Validation.fail('bad');
  }
}
