import 'package:studio_core/core/rng.dart';

import 'cards.dart';
import 'trick_engine.dart';

/// El alma oyunları için yapay zekâ. Görünmeyen kartlar her denemede
/// bilinenlere uygun biçimde rastgele dağıtılır (renk bitmişse o renk
/// verilmez), el sonuna kadar hızlı bir politikayla oynanır ve her aday kart
/// için ortalama sonuç alınır. Deneme sayısı arttıkça rakip güçlenir.
class TrickAI {
  final TrickRules rules;
  final int samples;
  final SeededRandom r;
  TrickAI(this.rules, this.samples, this.r);

  int bid(TrickState s, int seat) => rules.aiBid(s, seat, r);

  KCard play(TrickState s, int seat) {
    final legal = rules.legalPlays(s, seat);
    if (legal.length == 1 || samples <= 0) return legal.length == 1 ? legal.first : quick(rules, s, seat, r);
    final score = List<double>.filled(legal.length, 0);
    for (var k = 0; k < samples; k++) {
      final world = determinize(s, seat);
      for (var i = 0; i < legal.length; i++) {
        final w = world.copy();
        rules.play(w, seat, legal[i]);
        rollout(rules, w, r);
        score[i] += rules.utility(w, seat);
      }
    }
    var best = 0;
    for (var i = 1; i < legal.length; i++) {
      if (score[i] > score[best]) best = i;
    }
    return legal[best];
  }

  /// Bilinmeyen kartları diğer koltuklara (ve kapalı kartlara) dağıt.
  TrickState determinize(TrickState s, int seat) {
    final w = s.copy();
    final known = <KCard>{...s.hands[seat], ...s.played};
    final pool = <KCard>[
      for (var p = 0; p < s.seats; p++)
        if (p != seat) ...s.hands[p],
      ...s.kitty,
    ]..removeWhere(known.contains);
    shuffleCards(pool, r);
    // Önce renk kısıtı olan koltuklara uygun kartları ver.
    final need = [for (var p = 0; p < s.seats; p++) p == seat ? 0 : s.hands[p].length];
    for (var p = 0; p < s.seats; p++) {
      if (p != seat) w.hands[p].clear();
    }
    final order = [for (var p = 0; p < s.seats; p++) if (p != seat) p]
      ..sort((a, b) => s.voids[b].length.compareTo(s.voids[a].length));
    final rest = <KCard>[];
    for (final c in pool) {
      var placed = false;
      for (final p in order) {
        if (w.hands[p].length < need[p] && !s.voids[p].contains(rules.effSuit(s, c))) {
          w.hands[p].add(c);
          placed = true;
          break;
        }
      }
      if (!placed) rest.add(c);
    }
    // Kısıt yüzünden yer bulamayanlar: boş kalan yerlere (en iyi çaba).
    for (final c in rest) {
      var placed = false;
      for (final p in order) {
        if (w.hands[p].length < need[p]) {
          w.hands[p].add(c);
          placed = true;
          break;
        }
      }
      if (!placed) w.kitty.add(c);
    }
    w.kitty
      ..clear()
      ..addAll(rest.where((c) => !w.hands.any((h) => h.contains(c))));
    return w;
  }

  /// Hızlı politika: elin sonuna kadar oyna.
  static void rollout(TrickRules rules, TrickState w, SeededRandom r) {
    var guard = 0;
    while (w.phase == TrickPhase.play && guard++ < 200) {
      final seat = w.turn;
      rules.play(w, seat, quick(rules, w, seat, r));
    }
  }

  /// Basit ama makul kart seçimi: son oynayan ucuz kazanabiliyorsa kazanır,
  /// yoksa en küçük kartı atar; çıkışta rastgele.
  static KCard quick(TrickRules rules, TrickState s, int seat, SeededRandom r) {
    final legal = rules.legalPlays(s, seat);
    if (legal.length == 1) return legal.first;
    if (s.trick.isEmpty) {
      if (rules.avoidIn(s)) {
        final sorted = List.of(legal)..sort((a, b) => rules.strength(a).compareTo(rules.strength(b)));
        return sorted.first;
      }
      return legal[r.nextInt(legal.length)];
    }
    final lead = rules.effSuit(s, s.trick.first);
    // Şu an kazanan kart
    var best = s.trick.first;
    var bestIx = 0;
    for (var i = 1; i < s.trick.length; i++) {
      if (rules.beats(s, s.trick[i], best, lead)) {
        best = s.trick[i];
        bestIx = i;
      }
    }
    final winnerSeat = (s.leader + bestIx) % s.seats;
    final partnerWinning = winnerSeat != seat && rules.teammates(s, seat, winnerSeat);
    int low(KCard a, KCard b) => (rules.strength(a) + (rules.isTrump(s, a) ? 40 : 0))
        .compareTo(rules.strength(b) + (rules.isTrump(s, b) ? 40 : 0));
    final sorted = List.of(legal)..sort(low);
    if (rules.avoidIn(s)) {
      final safe = sorted.where((c) => !rules.beats(s, c, best, lead)).toList();
      return safe.isNotEmpty ? safe.last : sorted.last;
    }
    if (partnerWinning) return sorted.first;
    final winners = sorted.where((c) => rules.beats(s, c, best, lead)).toList();
    final last = s.trick.length == s.seats - 1;
    if (winners.isNotEmpty && (last || r.chance(0.6))) return winners.first;
    return sorted.first;
  }
}
