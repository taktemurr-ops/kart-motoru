import 'package:studio_core/core/rng.dart';

import 'cards.dart';
import 'table_engine.dart';

/// Masa oyunları için yapay zekâ: gizli kartlar her denemede yeniden
/// dağıtılır, her aday hamle hızlı politikayla sonuna kadar oynanır.
class TableAI {
  final TableRules rules;
  final int samples;
  final SeededRandom r;
  TableAI(this.rules, this.samples, this.r);

  TAction choose(TableState s) {
    final legal = rules.legalActions(s);
    if (legal.length == 1 || samples <= 0 || rules.heuristicAI) return legal.length == 1 ? legal.first : rules.quick(s, r);
    var cands = legal;
    if (cands.length > 14) {
      shuffleList(cands = List.of(legal), r);
      cands = cands.take(13).toList()..add(rules.quick(s, r));
    }
    final seat = s.turn;
    final score = List<double>.filled(cands.length, 0);
    for (var k = 0; k < samples; k++) {
      final world = determinize(s, seat);
      for (var i = 0; i < cands.length; i++) {
        final w = world.copy();
        rules.apply(w, cands[i]);
        rollout(rules, w, r);
        score[i] += rules.utility(w, seat);
      }
    }
    var best = 0;
    for (var i = 1; i < cands.length; i++) {
      if (score[i] > score[best]) best = i;
    }
    return cands[best];
  }

  TableState determinize(TableState s, int seat) {
    final w = s.copy();
    if (rules.revealHands) return w;
    final known = rules.knownCards(s, seat).toSet();
    final pool = <KCard>[];
    for (var p = 0; p < s.seats; p++) {
      if (p == seat) continue;
      for (final c in s.hands[p]) {
        if (!known.contains(c)) pool.add(c);
      }
    }
    for (final i in rules.hiddenPiles) {
      if (i < s.piles.length) pool.addAll(s.piles[i]);
    }
    shuffleCards(pool, r);
    var k = 0;
    for (var p = 0; p < s.seats; p++) {
      if (p == seat) continue;
      final keep = s.hands[p].where(known.contains).toList();
      final n = s.hands[p].length - keep.length;
      w.hands[p]
        ..clear()
        ..addAll(keep)
        ..addAll(pool.sublist(k, k + n));
      k += n;
    }
    for (final i in rules.hiddenPiles) {
      if (i >= s.piles.length) continue;
      final n = s.piles[i].length;
      w.piles[i]
        ..clear()
        ..addAll(pool.sublist(k, k + n));
      k += n;
    }
    rules.afterDeterminize(w);
    return w;
  }

  static void rollout(TableRules rules, TableState w, SeededRandom r) {
    var guard = 0;
    while (!w.over && guard++ < 400) {
      rules.apply(w, rules.quick(w, r));
    }
  }
}

void shuffleList<T>(List<T> l, SeededRandom r) {
  for (var i = l.length - 1; i > 0; i--) {
    final j = r.nextInt(i + 1);
    final t = l[i];
    l[i] = l[j];
    l[j] = t;
  }
}
