import 'package:studio_core/core/rng.dart';

import 'cards.dart';
import 'mahjong.dart';
import 'table_engine.dart';
import 'tile_painter.dart';

// ------------------------------------------------------------ hızlı shanten

/// Renk (ya da onur taşları) başına ayrıştırma önbelleği: 9 (onurda 7)
/// sayının taban-5 anahtarı → (grup, yarım grup, çift) üçlülerinin Pareto
/// kümesi; m*100 + t*10 + p biçiminde.
final Map<int, List<int>> _partCache = {};

bool _dominates(int b, int a) => b ~/ 100 >= a ~/ 100 && (b ~/ 10) % 10 >= (a ~/ 10) % 10 && b % 10 >= a % 10;

List<int> _prune(Iterable<int> xs) {
  final l = xs.toSet().toList();
  return [
    for (final a in l)
      if (!l.any((b) => b != a && _dominates(b, a))) a
  ];
}

List<int> _parts(List<int> c, int from, int len, bool seq) {
  var key = seq ? 1 : 2;
  var any = false;
  for (var i = 0; i < len; i++) {
    key = key * 5 + c[from + i];
    if (c[from + i] > 0) any = true;
  }
  if (!any) return const [0];
  final hit = _partCache[key];
  if (hit != null) return hit;
  final x = [for (var i = 0; i < len; i++) c[from + i]];
  final out = <int>{};
  void rec(int i, int m, int t, int p) {
    while (i < len && x[i] == 0) {
      i++;
    }
    if (i >= len) {
      out.add(m * 100 + (t > 9 ? 9 : t) * 10 + p);
      return;
    }
    if (x[i] >= 3) {
      x[i] -= 3;
      rec(i, m + 1, t, p);
      x[i] += 3;
    }
    if (seq && i + 2 < len && x[i + 1] > 0 && x[i + 2] > 0) {
      x[i]--;
      x[i + 1]--;
      x[i + 2]--;
      rec(i, m + 1, t, p);
      x[i]++;
      x[i + 1]++;
      x[i + 2]++;
    }
    if (x[i] >= 2) {
      x[i] -= 2;
      if (p == 0) rec(i, m, t, 1);
      rec(i, m, t + 1, p);
      x[i] += 2;
    }
    if (seq && i + 1 < len && x[i + 1] > 0) {
      x[i]--;
      x[i + 1]--;
      rec(i, m, t + 1, p);
      x[i]++;
      x[i + 1]++;
    }
    if (seq && i + 2 < len && x[i + 2] > 0) {
      x[i]--;
      x[i + 2]--;
      rec(i, m, t + 1, p);
      x[i]++;
      x[i + 2]++;
    }
    x[i]--;
    rec(i, m, t, p);
    x[i]++;
  }

  rec(0, 0, 0, 0);
  final r = _prune(out);
  if (_partCache.length > 200000) _partCache.clear();
  _partCache[key] = r;
  return r;
}

/// [mjShanten] ile aynı sonucu veren, renk başına önbellekli hızlı shanten.
int mjShantenFast(List<int> c, int need, {bool sevenPairs = false}) {
  var cur = const [0];
  for (var g = 0; g < 4; g++) {
    final l = g < 3 ? _parts(c, g * 9, 9, true) : _parts(c, 27, 7, false);
    if (l.length == 1 && l.first == 0) continue;
    final nx = <int>{};
    for (final a in cur) {
      for (final b in l) {
        var m = a ~/ 100 + b ~/ 100;
        var t = (a ~/ 10) % 10 + (b ~/ 10) % 10;
        var p = a % 10 + b % 10;
        if (m > need) m = need;
        if (t > need) t = need;
        if (p > 1) p = 1;
        nx.add(m * 100 + t * 10 + p);
      }
    }
    cur = _prune(nx);
  }
  var best = 2 * need;
  for (final v in cur) {
    final m = v ~/ 100, t = (v ~/ 10) % 10, p = v % 10;
    final tt = t < need - m ? t : need - m;
    final sh = 2 * need - 2 * m - tt - p;
    if (sh < best) best = sh;
  }
  if (sevenPairs) {
    var pairs = 0, kinds = 0;
    for (final x in c) {
      if (x >= 2) pairs++;
      if (x >= 1) kinds++;
    }
    final sp = 6 - pairs + (kinds < 7 ? 7 - kinds : 0);
    if (sp < best) best = sp;
  }
  return best;
}

/// Yalnızca üçlülerle (toitoi) shanten.
int mjShantenPungs(List<int> c, int need) {
  var m = 0, pairs = 0;
  for (final x in c) {
    if (x >= 3) {
      m++;
    } else if (x == 2) {
      pairs++;
    }
  }
  if (m > need) m = need;
  final p = pairs > 0 ? 1 : 0;
  final rest = pairs - p;
  return 2 * need - 2 * m - p - (rest < need - m ? rest : need - m);
}

// ------------------------------------------------------------ planlar

/// El planı (Riichi'de her elin en az bir yakusu olmalı): serbest (kapalı
/// elde riichi ya da güvence altındaki yakuhai), tanyao, honitsu/chinitsu
/// (renk 0..2), toitoi, yakuhai çifti (pon beklenir).
enum MjPlan { free, tanyao, honitsu, chinitsu, toitoi, yakuhaiPair }

class _Plan {
  final MjPlan kind;
  final int suit;
  const _Plan(this.kind, [this.suit = -1]);

  bool allows(int k) => switch (kind) {
        MjPlan.tanyao => !mjTerminalOrHonor(k),
        MjPlan.honitsu => k >= 27 || k ~/ 9 == suit,
        MjPlan.chinitsu => k < 27 && k ~/ 9 == suit,
        _ => true,
      };

  int get bonus => switch (kind) {
        MjPlan.free => 0,
        MjPlan.tanyao => 15,
        MjPlan.honitsu => 60,
        MjPlan.chinitsu => 120,
        MjPlan.toitoi => 40,
        MjPlan.yakuhaiPair => -60,
      };
}

/// Mahjong yapay zekâsı: shanten + ukeire ile atış seçimi, Riichi'de yaku
/// planlaması (açık elde yaku kalmayacaksa almaz), riichi ilanı ve riichi
/// diyen rakibe karşı savunma (genbutsu, suji, görünen onurlar).
/// [skill] 0 kolay (yalnızca shanten, savunma yok), 1 orta (ukeire, yalnızca
/// genbutsu), 2 zor (ukeire, değer, suji, it/çekil kararı).
class MahjongBrain {
  final MahjongRules R;
  final TableState s;
  final int p;
  final int skill;
  late final List<int> visible = _visible();
  late final int need = 4 - R.openSets(s, p);
  late final bool closed = R.concealed(s, p);
  late final bool menzen = R.codes(s, p).isEmpty;
  MahjongBrain(this.R, this.s, this.p, this.skill);

  List<int> _visible() {
    final v = List.filled(34, 0);
    void add(KCard t) {
      final k = mjKind(t);
      if (k < 34) v[k]++;
    }

    s.hands[p].forEach(add);
    s.piles[1].forEach(add);
    for (var q = 0; q < s.seats; q++) {
      s.piles[R.exposedBase + q].forEach(add);
    }
    if (R.riichiLike && s.piles[0].isNotEmpty) add(s.piles[0].first);
    if (R.style == MahjongStyle.sanma) {
      for (var k = 19; k <= 25; k++) {
        v[k] = 4;
      }
    }
    return v;
  }

  int rem(int k) => visible[k] >= 4 ? 0 : 4 - visible[k];

  bool yakuhai(int k) => k >= 31 || k == 27 + R.seatWind(s, p) || (R.riichiLike && k == 27 + R.roundWind.clamp(0, 3));

  /// Açık gruplarda yakuhai üçlüsü var mı?
  bool get _meldYakuhai => R.codes(s, p).any((c) => c % 100 != 1 && yakuhai(c ~/ 100));

  List<int> get _meldKinds => [
        for (final c in R.codes(s, p))
          for (var j = 0; j < (c % 100 == 1 ? 3 : 1); j++) c ~/ 100 + j
      ];

  /// Açık gruplara göre geçerli planlar (klasik/HK'de yalnızca serbest).
  List<_Plan> plans({List<int>? extraMeld, bool forceOpen = false}) {
    if (!R.riichiLike) return const [_Plan(MjPlan.free)];
    final mk = [..._meldKinds, ...?extraMeld];
    final open = forceOpen || !closed;
    final chow = R.codes(s, p).any((c) => c % 100 == 1) || (extraMeld != null && extraMeld.length == 3 && extraMeld[0] != extraMeld[1]);
    final out = <_Plan>[];
    final yakuhaiMeld = _meldYakuhai || (extraMeld != null && extraMeld[0] == extraMeld[1] && yakuhai(extraMeld[0]));
    if (!open || yakuhaiMeld || _secured(R.counts(s.hands[p]))) out.add(const _Plan(MjPlan.free));
    if (mk.every((k) => !mjTerminalOrHonor(k))) out.add(const _Plan(MjPlan.tanyao));
    // Honitsu/chinitsu: en çok taşı olan renk.
    final per = [0, 0, 0];
    for (final t in s.hands[p]) {
      final k = mjKind(t);
      if (k < 27) per[k ~/ 9]++;
    }
    for (final k in mk) {
      if (k < 27) per[k ~/ 9] += 2;
    }
    var su = 0;
    for (var i = 1; i < 3; i++) {
      if (per[i] > per[su]) su = i;
    }
    if (R.style == MahjongStyle.sanma && su == 2) su = per[0] >= per[1] ? 0 : 1;
    if (mk.every((k) => k >= 27 || k ~/ 9 == su)) out.add(_Plan(MjPlan.honitsu, su));
    if (mk.every((k) => k < 27 && k ~/ 9 == su)) out.add(_Plan(MjPlan.chinitsu, su));
    if (!chow) out.add(const _Plan(MjPlan.toitoi));
    if (open && !yakuhaiMeld) out.add(const _Plan(MjPlan.yakuhaiPair));
    return out;
  }

  /// Planın 13 (ya da daha az) taşlık el için shanten'i; plan geçersizse 99.
  int planShanten(List<int> c, _Plan pl, int need, bool sevenPairs) {
    switch (pl.kind) {
      case MjPlan.free:
        return mjShantenFast(c, need, sevenPairs: sevenPairs);
      case MjPlan.toitoi:
        return mjShantenPungs(c, need);
      case MjPlan.yakuhaiPair:
        // Yakuhai çifti elde kalmalı ve son taşı görünmemeli.
        var ok = false;
        for (var k = 27; k < 34; k++) {
          if (c[k] >= 2 && yakuhai(k) && (c[k] >= 3 || rem(k) > 0)) ok = true;
        }
        if (!ok) return 99;
        return mjShantenFast(c, need) + 1;
      default:
        final f = [for (var k = 0; k < 34; k++) pl.allows(k) ? c[k] : 0];
        return mjShantenFast(f, need, sevenPairs: sevenPairs && pl.kind != MjPlan.chinitsu);
    }
  }

  /// Serbest plan Riichi'de ancak kapalı elde ya da yakuhai üçlüsüyle geçerli.
  bool freeValid(List<int> c, bool open, bool yakuhaiMeld) => !R.riichiLike || !open || yakuhaiMeld || _secured(c);

  /// Kapalı elde yaku güvencesi: kapalı yakuhai üçlüsü de serbest planı açar.
  bool _secured(List<int> c) {
    for (var k = 27; k < 34; k++) {
      if (c[k] >= 3 && yakuhai(k)) return true;
    }
    return false;
  }

  /// Plan ile birlikte ukeire (shanten'i düşüren görünmeyen taş sayısı).
  double ukeire(List<int> c, _Plan pl, int need, bool sevenPairs, int sh) {
    var u = 0.0;
    final river = _riverKinds(p);
    for (var k = 0; k < 34; k++) {
      final n = rem(k);
      if (n == 0 || !pl.allows(k)) continue;
      c[k]++;
      final v = planShanten(c, pl, need, sevenPairs);
      c[k]--;
      if (v < sh) u += (sh == 0 && R.riichiLike && river.contains(k)) ? n * 0.3 : n.toDouble();
    }
    return u;
  }

  Set<int> _riverKinds(int q) {
    final i = R.riverBase + q;
    if (i >= s.piles.length) return const {};
    return {for (final t in s.piles[i]) mjKind(t)};
  }

  /// Riichi diyen rakipler.
  List<int> get threats => [for (var q = 0; q < s.seats; q++) if (q != p && R.inRiichi(s, q)) q];

  /// Taşın tehlikesi (0 güvenli … 10 çok tehlikeli).
  int danger(int k) {
    var worst = 0;
    for (final o in threats) {
      final river = _riverKinds(o);
      int d;
      if (river.contains(k)) {
        d = 0;
      } else if (k >= 27) {
        final v = visible[k];
        d = v >= 3 ? 1 : (v == 2 ? 3 : 6);
      } else if (skill < 2) {
        d = 8;
      } else {
        final n = k % 9;
        final lo = n >= 3 && river.contains(k - 3);
        final hi = n <= 5 && river.contains(k + 3);
        final suji = n <= 2 ? hi : (n >= 6 ? lo : lo && hi);
        if (suji) {
          d = (n == 0 || n == 8) ? 1 : 3;
        } else if (n >= 3 && n <= 5 && (lo || hi)) {
          d = 6;
        } else {
          d = (n == 0 || n == 8) ? 6 : (n == 1 || n == 7 ? 8 : 10);
        }
      }
      if (d > worst) worst = d;
    }
    return worst;
  }

  /// En iyi atış: (tür, shanten, plan). [only] riichi'de kilitli taş.
  (int, int, _Plan?) bestDiscard(SeededRandom r, {int? only}) {
    final c = R.counts(s.hands[p]);
    final sp = menzen;
    final ps = plans();
    final cands = <(int, int, _Plan, int)>[]; // tür, shanten, plan, bonus
    var minSh = 99;
    for (var k = 0; k < 34; k++) {
      if (c[k] == 0 || (only != null && k != only)) continue;
      c[k]--;
      var bs = 99;
      _Plan? bp;
      for (final pl in ps) {
        if (pl.kind == MjPlan.free && !freeValid(c, !closed, _meldYakuhai)) continue;
        final v = planShanten(c, pl, need, sp);
        if (v < bs || (v == bs && bp != null && pl.bonus > bp.bonus)) {
          bs = v;
          bp = pl;
        }
      }
      c[k]++;
      bp ??= const _Plan(MjPlan.free);
      if (bs < minSh) minSh = bs;
      cands.add((k, bs, bp, 0));
    }
    final th = threats;
    final iAmRiichi = R.inRiichi(s, p);
    // Kolay: arada bir hazıra uzaklığı gözden kaçırır.
    final careless = skill == 0 && r.nextInt(5) == 0;
    final fold = !iAmRiichi && th.isNotEmpty && skill >= 1 && (minSh >= 2 || (skill >= 2 && minSh == 1 && s.piles[0].length < 40) || minSh >= 90);
    var best = cands.first;
    var bestV = double.negativeInfinity;
    for (final e in cands) {
      final (k, sh, pl, _) = e;
      double v;
      if (fold) {
        v = -danger(k) * 1000.0 - sh * 10.0 + r.nextInt(3) * 0.1;
      } else {
        v = careless ? 0 : -sh * 1000.0;
        if (skill == 0) {
          v += -_useful(c, k) * 3.0 + r.nextInt(6);
        } else if (sh <= minSh) {
          c[k]--;
          v += ukeire(c, pl, need, menzen, sh) * 10;
          c[k]++;
          v += pl.bonus;
          if (skill >= 2) {
            if (R.riichiLike && k == s.vars[3]) v -= 40; // doradan vazgeçme
            if (k >= 27 && !yakuhai(k) && c[k] == 1) v += 6;
            if (th.isNotEmpty && !iAmRiichi) v -= danger(k) * (sh == 0 ? 4 : 25);
          }
          v += r.nextInt(2) * 0.5;
        }
      }
      if (v > bestV) {
        bestV = v;
        best = e;
      }
    }
    return (best.$1, best.$2, best.$3);
  }

  static int _useful(List<int> c, int k) {
    var v = (c[k] - 1) * 6;
    if (mjSuited(k)) {
      for (final d in const [-2, -1, 1, 2]) {
        final j = k + d;
        if (j >= 0 && j < 27 && j ~/ 9 == k ~/ 9 && c[j] > 0) v += d.abs() == 1 ? 3 : 2;
      }
      if (k % 9 == 0 || k % 9 == 8) v -= 1;
    } else {
      v -= 1;
    }
    return v;
  }

  /// Şu anki (13 taşlık) elin en iyi plan shanten'i.
  int currentShanten() {
    final c = R.counts(s.hands[p]);
    var best = 99;
    for (final pl in plans()) {
      if (pl.kind == MjPlan.free && !freeValid(c, !closed, _meldYakuhai)) continue;
      final v = planShanten(c, pl, need, menzen);
      if (v < best) best = v;
    }
    return best;
  }

  /// Atılan taşı alma kararı (pon/kan/chi): alıp en iyi taşı atınca yaku
  /// kalıyor ve hazıra yaklaşılıyorsa.
  bool wantsCall(TAction a, KCard tile) {
    final k = mjKind(tile);
    if (R.riichiLike && threats.isNotEmpty && skill >= 1 && currentShanten() >= 2) return false;
    if (R.riichiLike && a.kind == 4) return false; // açık kan yerine pon
    final now = currentShanten();
    final rest = [...s.hands[p]]..removeWhere(a.cards.contains);
    final c = R.counts(rest);
    final meld = a.kind == 5 ? [a.target, a.target + 1, a.target + 2] : [k, k, k];
    final ps = plans(extraMeld: meld, forceOpen: true);
    final n2 = need - 1;
    final yakuhaiPon = a.kind != 5 && yakuhai(k);
    var after = 99;
    for (var j = 0; j < 34; j++) {
      if (c[j] == 0) continue;
      c[j]--;
      for (final pl in ps) {
        if (pl.kind == MjPlan.yakuhaiPair) continue;
        if (pl.kind == MjPlan.free && !freeValid(c, true, yakuhaiPon || _meldYakuhai)) continue;
        final v = planShanten(c, pl, n2, false);
        if (v < after) after = v;
      }
      c[j]++;
    }
    if (!R.riichiLike) {
      final honorPung = a.kind != 5 && (k >= 31 || k == 27 + R.seatWind(s, p));
      return after < now || (honorPung && after <= now);
    }
    if (after >= 90) return false;
    // Zor: kapalı ve hazıra yakın elde (riichi şansı) ucuz açık elden kaçın.
    if (skill >= 2 && closed && now <= 1 && after > 0 && !yakuhaiPon) return false;
    return after < now || (yakuhaiPon && after <= now);
  }
}
