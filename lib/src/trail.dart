import 'dart:convert';

import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import 'cards.dart';

/// Kart Yolu: açık kartlardan bir ızgara. Bir karttan başla, her adımda
/// komşu (yan ya da çapraz) bir karta geç; geçtiğin kart masadan kalkar.
/// İki kart bağlıysa geçilebilir. Bütün kartları tek yolda topla.
enum TrailLink {
  /// Aynı desen ya da aynı sayı.
  suitOrRank,

  /// Aynı desen ya da bir büyük/küçük sayı.
  suitOrStep,

  /// Yalnızca bir büyük/küçük sayı (Papaz–As da komşu).
  step,
}

bool trailLinked(TrailLink m, KCard a, KCard b) {
  final ra = rankOf(a), rb = rankOf(b);
  final step = (ra - rb).abs() == 1 || (ra - rb).abs() == 12;
  return switch (m) {
    TrailLink.suitOrRank => suitOf(a) == suitOf(b) || ra == rb,
    TrailLink.suitOrStep => suitOf(a) == suitOf(b) || step,
    TrailLink.step => step,
  };
}

class TrailLevel {
  final int cols, rows;
  final List<KCard> cards;
  final TrailLink link;
  final List<int> solution;
  final int seed;
  const TrailLevel(this.cols, this.rows, this.cards, this.link, this.solution, this.seed);

  int get size => cols * rows;

  bool adjacent(int a, int b) {
    final dc = (a % cols - b % cols).abs(), dr = (a ~/ cols - b ~/ cols).abs();
    return a != b && dc <= 1 && dr <= 1;
  }

  bool canStep(int from, int to) => adjacent(from, to) && trailLinked(link, cards[from], cards[to]);
}

class TrailGame {
  final TrailLevel level;
  final List<int> path = [];
  int undos = 0;
  TrailGame(this.level);

  bool get won => path.length == level.size;
  bool taken(int i) => path.contains(i);

  bool canTap(int i) {
    if (i < 0 || i >= level.size || taken(i)) return false;
    return path.isEmpty || level.canStep(path.last, i);
  }

  bool tap(int i) {
    if (!canTap(i)) return false;
    path.add(i);
    return true;
  }

  void undo() {
    if (path.isEmpty) return;
    path.removeLast();
    undos++;
  }

  /// Bundan sonra gidilebilecek kare yoksa ve bitmediyse: sıkıştın.
  bool get stuck => path.isNotEmpty && !won && !List.generate(level.size, (i) => i).any(canTap);

  /// İpucu: mevcut yoldan devam eden bir çözümün sıradaki karesi; çözüm
  /// yoksa null (geri al gerekir).
  int? hint() {
    if (path.isEmpty) return level.solution.first;
    final ok = path.length <= level.solution.length && _prefixMatches();
    if (ok) return level.solution[path.length];
    final rest = solveFrom(level, path, 8000);
    return rest == null || rest.isEmpty ? null : rest.first;
  }

  bool _prefixMatches() {
    for (var i = 0; i < path.length; i++) {
      if (path[i] != level.solution[i]) return false;
    }
    return true;
  }

  String serialize() => jsonEncode({'p': path, 'u': undos});

  static TrailGame restore(TrailLevel l, String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    final g = TrailGame(l);
    g.path.addAll([for (final x in j['p'] as List) (x as num).toInt()]);
    g.undos = (j['u'] as num?)?.toInt() ?? 0;
    return g;
  }
}

/// Yolun geri kalanını bulmaya çalışır (derinlik öncelikli, en az çıkışlı
/// kare önce). [budget] düğüm sınırı.
List<int>? solveFrom(TrailLevel l, List<int> prefix, int budget) {
  final used = List<bool>.filled(l.size, false);
  for (final p in prefix) {
    used[p] = true;
  }
  final out = <int>[];
  var nodes = 0;
  List<int> nexts(int from) => [
        for (var i = 0; i < l.size; i++)
          if (!used[i] && (from < 0 || l.canStep(from, i))) i
      ];
  int degree(int i) {
    var n = 0;
    for (var j = 0; j < l.size; j++) {
      if (!used[j] && j != i && l.canStep(i, j)) n++;
    }
    return n;
  }

  bool go(int from, int left) {
    if (left == 0) return true;
    if (++nodes > budget) return false;
    final ns = nexts(from)..sort((a, b) => degree(a).compareTo(degree(b)));
    for (final n in ns) {
      used[n] = true;
      out.add(n);
      if (go(n, left - 1)) return true;
      out.removeLast();
      used[n] = false;
      if (nodes > budget) return false;
    }
    return false;
  }

  return go(prefix.isEmpty ? -1 : prefix.last, l.size - prefix.length) ? out : null;
}

/// Izgarada rastgele bir Hamilton yolu (8 komşuluk).
List<int>? _randomPath(int cols, int rows, SeededRandom r) {
  final n = cols * rows;
  final used = List<bool>.filled(n, false);
  final out = <int>[];
  var nodes = 0;
  List<int> nb(int i) => [
        for (var dr = -1; dr <= 1; dr++)
          for (var dc = -1; dc <= 1; dc++)
            if ((dr != 0 || dc != 0) &&
                i % cols + dc >= 0 &&
                i % cols + dc < cols &&
                i ~/ cols + dr >= 0 &&
                i ~/ cols + dr < rows &&
                !used[i + dr * cols + dc])
              i + dr * cols + dc
      ];
  bool go(int at, int left) {
    if (left == 0) return true;
    if (++nodes > 20000) return false;
    final ns = nb(at);
    shuffleCards(ns, r);
    ns.sort((a, b) => nb(a).length.compareTo(nb(b).length));
    for (final x in ns) {
      used[x] = true;
      out.add(x);
      if (go(x, left - 1)) return true;
      out.removeLast();
      used[x] = false;
    }
    return false;
  }

  final start = r.nextInt(n);
  used[start] = true;
  out.add(start);
  return go(start, n - 1) ? out : null;
}

/// Yol boyunca kartları dağıt: ardışık kartlar bağlı, hepsi farklı.
List<KCard>? _assign(int len, TrailLink link, SeededRandom r) {
  final deck = buildDeck();
  shuffleCards(deck, r);
  final used = <KCard>{};
  final seq = <KCard>[];
  final useCount = List.filled(14, 0);
  var nodes = 0;
  bool go() {
    if (seq.length == len) return true;
    if (++nodes > 40000) return false;
    final cand = deck.where((c) => !used.contains(c) && (seq.isEmpty || trailLinked(link, seq.last, c))).toList();
    shuffleCards(cand, r);
    // Az kullanılan sayılar önce: uzun yollarda sayı tükenmesin.
    cand.sort((a, b) => useCount[rankOf(a)].compareTo(useCount[rankOf(b)]));
    for (final c in cand.take(6)) {
      used.add(c);
      seq.add(c);
      useCount[rankOf(c)]++;
      if (go()) return true;
      useCount[rankOf(c)]--;
      seq.removeLast();
      used.remove(c);
    }
    return false;
  }

  return go() ? seq : null;
}

TrailLevel generateTrailLevel(LevelSpec spec) {
  final d = spec.difficulty.clamp(1, 10);
  const sizes = [(3, 3), (4, 3), (4, 4), (5, 4), (5, 5), (6, 5), (6, 6), (6, 6), (7, 6), (7, 7)];
  final (cols, rows) = sizes[d - 1];
  final link = d <= 3 ? TrailLink.suitOrRank : (d <= 6 ? TrailLink.suitOrStep : TrailLink.step);
  for (var attempt = 0;; attempt++) {
    final r = SeededRandom(mixSeed([spec.seed, 911, attempt]));
    final path = _randomPath(cols, rows, r);
    if (path == null) continue;
    final seq = _assign(path.length, link, r);
    if (seq == null) continue;
    final cards = List<KCard>.filled(cols * rows, 0);
    for (var i = 0; i < path.length; i++) {
      cards[path[i]] = seq[i];
    }
    return TrailLevel(cols, rows, cards, link, path, spec.seed);
  }
}

class TrailRules extends GameRules<TrailLevel> {
  @override
  final String gameId;
  TrailRules({required this.gameId});

  @override
  int get levelCount => 100000;

  @override
  List<String> get optionalMechanics => const [];

  @override
  List<GameModeId> get modes => const [GameModeId.campaign, GameModeId.daily, GameModeId.weekly, GameModeId.challenge];

  @override
  List<GameStat> get gameStats => const [
        GameStat('cards_linked', 'Bağlanan kart', 'Cards linked', scale: 100),
        GameStat('clean_trails', 'Temiz yol', 'Clean trails', scale: 5),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('linked', 'cards_linked', [30, 90, 220]),
        MissionTemplate('clean', 'clean_trails', [1, 3, 6]),
      ];

  @override
  TrailLevel generate(LevelSpec spec) => generateTrailLevel(spec);

  /// Saklanan çözüm adım adım geçerli olmalı.
  @override
  Validation validate(TrailLevel level, LevelSpec spec) {
    final g = TrailGame(level);
    for (final i in level.solution) {
      if (!g.tap(i)) return const Validation.fail('bad step');
    }
    return g.won ? Validation.ok(level.size) : const Validation.fail('short');
  }
}
