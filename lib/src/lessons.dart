import 'dart:math' as math;

import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'lesson_texts.dart';
import 'mahjong.dart';
import 'okey.dart';
import 'tile_painter.dart';

// ======================================================================
// Öğretici dersler: Okey, 101 Okey, Riichi, Klasik ve Hong Kong Mahjong.
// Her ders bilgi adımlarından, motorun kurallarıyla denetlenen alıştırma
// görevlerinden ve koçlu bir alıştırma elinden oluşur.

/// Ders yazısı (33 dil); {n} gibi yer tutucular doldurulur.
String lessonText(String key, String lang, [Map<String, Object> p = const {}]) {
  var s = Strings.pick(kLessonTexts[key] ?? const ['?'], lang);
  p.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

enum LessonCourse { okey, okey101, riichi, classic, hongKong }

/// Okey taşı: renk 0 sarı, 1 mavi, 2 siyah, 3 kırmızı; sayı 1..13; kopya 0/1.
KCard okeyTile(int color, int number, [int copy = 0]) => copy * 52 + color * 13 + number - 1;

/// Mahjong taşı: tür (0..33) ve kopya.
KCard mjTile(int kind, [int copy = 0]) => 2000 + kind * 4 + copy;

/// Kısa yazımla mahjong türü: 'p' daire, 's' bambu, 'm' karakter (ör. 5p);
/// rüzgâr E S W N, ejder R G Wh.
int mjKindOf(String code) {
  const honors = {'E': 27, 'S': 28, 'W': 29, 'N': 30, 'R': 31, 'G': 32, 'Wh': 33};
  if (honors.containsKey(code)) return honors[code]!;
  final n = int.parse(code.substring(0, code.length - 1));
  final suit = 'psm'.indexOf(code[code.length - 1]);
  return suit * 9 + n - 1;
}

/// Kısa yazımla el ('1p 2p 3p ...'); aynı tür tekrarlanınca kopyalar artar.
List<KCard> mjHand(String codes) {
  final used = <int, int>{};
  return [
    for (final c in codes.split(' ').where((x) => x.isNotEmpty))
      () {
        final k = mjKindOf(c);
        final copy = used[k] ?? 0;
        used[k] = copy + 1;
        return mjTile(k, copy);
      }()
  ];
}

// ---- Görevler -------------------------------------------------------------

sealed class LessonTask {
  const LessonTask();
}

/// Istakadan taş seçme. [single]: tek dokunuşla denetlenir.
class PickTilesTask extends LessonTask {
  final String prompt;
  final List<KCard> tiles;
  final bool Function(List<KCard> picked) check;
  final List<int> solution;
  final bool single;
  const PickTilesTask({required this.prompt, required this.tiles, required this.check, required this.solution, this.single = false});
}

/// Hazır gruplardan seçme (101 açılışı).
class PickGroupsTask extends LessonTask {
  final String prompt;
  final List<List<KCard>> groups;
  final int okeyKind;
  final List<int> solution;
  const PickGroupsTask({required this.prompt, required this.groups, required this.okeyKind, required this.solution});

  int value(int g) => okeyGroupValue([for (final t in groups[g]) okeyMeaning(t, okeyKind)]);

  /// Seçilen grupların hepsi geçerli ve toplam en az 101 mi.
  bool check(Set<int> sel) => sel.isNotEmpty && sel.every((g) => value(g) >= 0) && sel.fold<int>(0, (a, g) => a + value(g)) >= 101;
}

/// Çoktan seçmeli soru.
class ChoiceTask extends LessonTask {
  final String prompt;
  final List<String Function(String lang)> options;
  final int correct;
  const ChoiceTask({required this.prompt, required this.options, required this.correct});
}

enum PracticeKind { okey, mahjong, open101 }

/// Koçlu alıştırma eli.
class PracticeTask extends LessonTask {
  final PracticeKind kind;
  final int seed;
  const PracticeTask(this.kind, this.seed);
}

class LessonStep {
  final String title;
  final String body;
  final int style;
  final List<KCard> tiles;

  /// Çizimde vurgulanan taşların sırası.
  final Set<int> marked;
  final LessonTask? task;
  const LessonStep({required this.title, required this.body, this.style = kTileOkey, this.tiles = const [], this.marked = const {}, this.task});
}

// ---- Denetleyiciler -------------------------------------------------------

const _noOkey = 999;

List<int> _m(List<KCard> t, int okeyKind) => [for (final x in t) okeyMeaning(x, okeyKind)];

/// Okey: seçilen taşlar tek bir seri mi (aynı renk ardışık, en az 3).
bool okeyIsRun(List<KCard> t, int okeyKind) {
  final m = _m(t, okeyKind);
  if (m.length < 3 || okeyGroupValue(m) < 0) return false;
  final nat = m.where((x) => x >= 0).toList();
  return nat.map((x) => x ~/ 13).toSet().length == 1 && nat.map((x) => x % 13).toSet().length == nat.length;
}

/// Okey: seçilen taşlar aynı sayının farklı renkleri mi (3 ya da 4).
bool okeyIsSet(List<KCard> t, int okeyKind) {
  final m = _m(t, okeyKind);
  if (m.length < 3 || m.length > 4) return false;
  final nat = m.where((x) => x >= 0).toList();
  return nat.isNotEmpty && nat.every((x) => x % 13 == nat.first % 13) && nat.map((x) => x ~/ 13).toSet().length == nat.length;
}

/// Mahjong: sıralı üçlü.
bool mjIsChow(List<KCard> t) {
  if (t.length != 3) return false;
  final k = [for (final x in t) mjKind(x)]..sort();
  return mjSuited(k[0]) && k[0] ~/ 9 == k[2] ~/ 9 && k[1] == k[0] + 1 && k[2] == k[0] + 2;
}

/// Mahjong: aynı üç taş.
bool mjIsPung(List<KCard> t) => t.length == 3 && t.every((x) => mjKind(x) == mjKind(t.first));

List<int> mjCounts(List<KCard> tiles) {
  final c = List.filled(34, 0);
  for (final t in tiles) {
    final k = mjKind(t);
    if (k < 34) c[k]++;
  }
  return c;
}

/// 14 taşlık el tamam mı (dört grup + çift ya da yedi çift).
bool mjWinning(List<KCard> tiles) {
  final c = mjCounts(tiles);
  return mjComplete(List.of(c), 4) || mjSevenPairs(c);
}

/// 101: taşlar geçerli perlere tam bölünebiliyorsa en yüksek toplam, yoksa -1.
int okeyBestPartition(List<int> meanings) {
  final cnt = List.filled(52, 0);
  var w = 0;
  for (final m in meanings) {
    if (m < 0) {
      w++;
    } else {
      cnt[m]++;
    }
  }
  final memo = <String, int>{};
  int best(int wl) {
    var f = -1;
    for (var i = 0; i < 52; i++) {
      if (cnt[i] > 0) {
        f = i;
        break;
      }
    }
    if (f < 0) return wl == 0 ? 0 : -1;
    final key = '${cnt.join(',')}/$wl';
    final cached = memo[key];
    if (cached != null) return cached;
    var out = -1;
    final c = f ~/ 13, n = f % 13;
    cnt[f]--;
    // Set: f ile aynı sayının diğer renkleri + jokerler.
    final others = [for (var oc = 0; oc < 4; oc++) if (oc != c && cnt[oc * 13 + n] > 0) oc * 13 + n];
    for (var mask = 0; mask < 1 << others.length; mask++) {
      final pick = [for (var k = 0; k < others.length; k++) if ((mask >> k) & 1 == 1) others[k]];
      for (var wu = 0; wu <= wl; wu++) {
        final size = 1 + pick.length + wu;
        if (size < 3 || size > 4) continue;
        for (final x in pick) {
          cnt[x]--;
        }
        final r = best(wl - wu);
        if (r >= 0 && r + (n + 1) * size > out) out = r + (n + 1) * size;
        for (final x in pick) {
          cnt[x]++;
        }
      }
    }
    // Seri: f'nin konumunu (n ya da 1 için 13) içeren her pencere.
    for (final pos in [n, if (n == 0) 13]) {
      for (var s = 0; s <= pos; s++) {
        for (var e = pos; e <= 13; e++) {
          if (e - s + 1 < 3 || (s == 0 && e == 13)) continue;
          final used = <int>[];
          var wu = 0, value = 0;
          var ok = true;
          for (var p = s; p <= e && ok; p++) {
            value += p == 13 ? 1 : p + 1;
            if (p == pos) continue;
            final idx = c * 13 + p % 13;
            if (cnt[idx] > 0) {
              cnt[idx]--;
              used.add(idx);
            } else {
              wu++;
              if (wu > wl) ok = false;
            }
          }
          if (ok) {
            final r = best(wl - wu);
            if (r >= 0 && r + value > out) out = r + value;
          }
          for (final x in used) {
            cnt[x]++;
          }
        }
      }
    }
    cnt[f]++;
    memo[key] = out;
    return out;
  }

  return best(w);
}

// ---- Alıştırma elleri ------------------------------------------------------

/// Okey alıştırması: 15 taşla başlanır; at, çek, bitir.
class OkeyPractice {
  final KCard indicator;
  final int okeyKind;
  final List<KCard> hand;
  final List<KCard> stock;
  KCard? lastDrawn;
  bool won = false;

  OkeyPractice._(this.indicator, this.okeyKind, this.hand, this.stock);

  factory OkeyPractice(int seed) {
    final r = SeededRandom(mixSeed([seed, 7101]));
    for (var attempt = 0; attempt < 50; attempt++) {
      final p = _build(r);
      if (p != null) return p;
    }
    return _build(SeededRandom(1))!;
  }

  static OkeyPractice? _build(SeededRandom r) {
    final used = <KCard>{};
    KCard? take(int meaning) {
      for (final copy in [0, 1]) {
        final t = copy * 52 + meaning;
        if (used.add(t)) return t;
      }
      return null;
    }

    final indicator = r.nextInt(52);
    used.add(indicator);
    final kind = okeyKindFrom(indicator);
    final groups = <List<KCard>>[];
    // İki seri (4 ve 3) ve iki per (4 ve 3): 14 taş.
    for (final (isRun, size) in [(true, 4), (true, 3), (false, 4), (false, 3)]) {
      final g = <KCard>[];
      if (isRun) {
        final c = r.nextInt(4), st = r.nextInt(13 - size + 1);
        for (var p = st; p < st + size; p++) {
          final m = c * 13 + p;
          final t = m == kind ? null : take(m);
          if (t == null) return null;
          g.add(t);
        }
      } else {
        final n = r.nextInt(13);
        final colors = [0, 1, 2, 3]..shuffle(_Rand(r));
        for (final c in colors.take(size)) {
          final m = c * 13 + n;
          final t = m == kind ? null : take(m);
          if (t == null) return null;
          g.add(t);
        }
      }
      groups.add(g);
    }
    final full = [for (final g in groups) ...g];
    final idx = [for (var i = 0; i < full.length; i++) i]..shuffle(_Rand(r));
    final need = [full[idx[0]], full[idx[1]]];
    final hand = [for (final t in full) if (!need.contains(t)) t];
    // Dışarıda kalan üç taş ve çekilecek taşlar.
    // Boş taşlar: eldeki hiçbir taşla per kurmaya yakın olmayanlar.
    bool loose(int t) {
      final x = t % 52;
      for (final y in [...full, ...need].map((v) => v % 52)) {
        if (x % 13 == y % 13) return false;
        if (x ~/ 13 == y ~/ 13 && ((x % 13) - (y % 13)).abs() <= 2) return false;
      }
      return true;
    }

    final pool = [for (var t = 0; t < 106; t++) if (!used.contains(t) && !isOkeyFalseJoker(t) && t % 52 != kind) t]..shuffle(_Rand(r));
    final junkAll = pool.where(loose).toList();
    if (junkAll.length < 4) return null;
    // Boş taşlar kendi aralarında da per kurmasın: her biri farklı sayı.
    final junk = <KCard>[];
    for (final t in junkAll) {
      if (junk.any((j) => j % 13 == t % 13 || (j % 52 ~/ 13 == t % 52 ~/ 13 && ((j % 13) - (t % 13)).abs() <= 2))) continue;
      junk.add(t);
      if (junk.length == 4) break;
    }
    if (junk.length < 4) return null;
    pool.removeWhere(junk.contains);
    hand.addAll(junk.take(3));
    // Çekme sırası (sondan çekilir): gerekli, boş, gerekli, sonra kalanlar.
    final order = [need[0], junk[3], need[1], ...pool.take(14)];
    final stock = order.reversed.toList();
    final p = OkeyPractice._(indicator, kind, hand, stock);
    p._sort();
    if (p.canFinish) return null;
    return p;
  }

  List<int> get meanings => _m(hand, okeyKind);

  void _sort() {
    hand.sort((a, b) {
      final ma = okeyMeaning(a, okeyKind), mb = okeyMeaning(b, okeyKind);
      return (ma < 0 ? 999 : ma).compareTo(mb < 0 ? 999 : mb);
    });
  }

  /// Bu taş atılırsa el biter mi.
  bool finishesWith(KCard t) {
    final rest = [...hand]..remove(t);
    final m = _m(rest, okeyKind);
    return okeyAllGrouped(m) || okeyPairCount(m) >= 7;
  }

  bool get canFinish => hand.length == 15 && hand.any(finishesWith);

  int _cover(List<KCard> tiles) => okeyCoverPlan(_m(tiles, okeyKind)).$1;

  /// Koçun önerisi: bitiriyorsa o taş; değilse perlere en az katkısı olan.
  KCard coach() {
    for (final t in hand) {
      if (finishesWith(t)) return t;
    }
    var best = hand.first, bv = -1 << 30;
    final m = meanings;
    for (var i = 0; i < hand.length; i++) {
      if (m[i] < 0) continue;
      final rest = [...hand]..removeAt(i);
      final v = _cover(rest) * 100 - okeyKeepScore(m, i);
      if (v > bv) {
        bv = v;
        best = hand[i];
      }
    }
    return best;
  }

  /// Atış iyi miydi: perlerdeki taş sayısı en iyi atıştaki kadar kalıyor mu.
  bool isGoodDiscard(KCard t) {
    if (finishesWith(t)) return true;
    var bestCover = 0;
    for (var i = 0; i < hand.length; i++) {
      final rest = [...hand]..removeAt(i);
      final c = _cover(rest);
      if (c > bestCover) bestCover = c;
    }
    return _cover([...hand]..remove(t)) >= bestCover;
  }

  /// Taşı at; el bittiyse true. Bitmediyse desteden yeni taş çekilir.
  bool discard(KCard t) {
    if (finishesWith(t)) {
      hand.remove(t);
      won = true;
      return true;
    }
    hand.remove(t);
    if (stock.isNotEmpty) {
      lastDrawn = stock.removeLast();
      hand.add(lastDrawn!);
      _sort();
    } else {
      lastDrawn = null;
    }
    return false;
  }

  bool get outOfTiles => !won && hand.length < 15;
}

/// Mahjong alıştırması: 14 taşla başlanır; at, çek, tamamlayınca kazan.
class MahjongPractice {
  final List<KCard> hand;
  final List<KCard> stock;
  KCard? lastDrawn;
  bool won = false;

  MahjongPractice._(this.hand, this.stock);

  factory MahjongPractice(int seed) {
    final r = SeededRandom(mixSeed([seed, 7202]));
    for (var attempt = 0; attempt < 50; attempt++) {
      final p = _build(r);
      if (p != null) return p;
    }
    return _build(SeededRandom(2))!;
  }

  static MahjongPractice? _build(SeededRandom r) {
    final count = List.filled(34, 0);
    final full = <KCard>[];
    bool add(int k) {
      if (count[k] >= 4) return false;
      full.add(mjTile(k, count[k]));
      count[k]++;
      return true;
    }

    for (var g = 0; g < 4; g++) {
      if (r.chance(0.65)) {
        final suit = r.nextInt(3), st = r.nextInt(7);
        for (var i = 0; i < 3; i++) {
          if (!add(suit * 9 + st + i)) return null;
        }
      } else {
        final k = r.nextInt(34);
        for (var i = 0; i < 3; i++) {
          if (!add(k)) return null;
        }
      }
    }
    final pk = r.nextInt(34);
    if (!add(pk) || !add(pk)) return null;
    final idx = [for (var i = 0; i < full.length; i++) i]..shuffle(_Rand(r));
    final need = [full[idx[0]], full[idx[1]]];
    final hand = [for (final t in full) if (!need.contains(t)) t];
    final pool = <KCard>[
      for (var k = 0; k < 34; k++)
        for (var c = count[k]; c < 4; c++) mjTile(k, c)
    ]..shuffle(_Rand(r));
    // Gerekli taşlarla aynı türden olmayan iki boş taş.
    // Boş taşlar: eldeki hiçbir türe yakın olmayanlar, birbirinden de uzak.
    bool near(int a, int b) => a == b || (mjSuited(a) && mjSuited(b) && a ~/ 9 == b ~/ 9 && (a - b).abs() <= 2);
    final fullKinds = [for (final t in full) mjKind(t)];
    final junk = <KCard>[];
    for (final t in pool) {
      final k = mjKind(t);
      if (fullKinds.any((f) => near(f, k)) || junk.any((j) => near(mjKind(j), k))) continue;
      junk.add(t);
      if (junk.length == 3) break;
    }
    if (junk.length < 3) return null;
    hand.addAll(junk.take(2));
    final rest = pool.where((t) => !junk.contains(t)).take(16).toList();
    final order = [need[0], junk[2], need[1], ...rest];
    final p = MahjongPractice._(hand, order.reversed.toList());
    p.hand.sort();
    if (mjWinning(p.hand)) return null;
    return p;
  }

  bool get canWin => hand.length == 14 && mjWinning(hand);

  int _shanten(List<KCard> tiles) => mjShanten(mjCounts(tiles), 4, sevenPairs: true);

  /// Koçun önerisi: hazıra uzaklığı en az artıran atış; eşitse yalnız kalan şeref taşı.
  KCard coach() {
    var best = hand.first, bv = 1 << 30;
    for (final t in hand) {
      final rest = [...hand]..remove(t);
      final k = mjKind(t);
      // Eşitlikte en yalnız taş: aynı tür ya da aynı renkte ±2 komşu sayısı.
      var neighbours = 0;
      for (final x in rest) {
        final y = mjKind(x);
        if (y == k) neighbours += 3;
        if (mjSuited(k) && mjSuited(y) && y ~/ 9 == k ~/ 9 && y != k && (y - k).abs() <= 2) neighbours += 3 - (y - k).abs();
      }
      final v = _shanten(rest) * 100 + neighbours;
      if (v < bv) {
        bv = v;
        best = t;
      }
    }
    return best;
  }

  bool isGoodDiscard(KCard t) {
    var bestS = 99;
    for (final x in hand) {
      final s = _shanten([...hand]..remove(x));
      if (s < bestS) bestS = s;
    }
    return _shanten([...hand]..remove(t)) <= bestS;
  }

  void discard(KCard t) {
    hand.remove(t);
    if (stock.isNotEmpty) {
      lastDrawn = stock.removeLast();
      hand.add(lastDrawn!);
      hand.sort();
    } else {
      lastDrawn = null;
    }
  }

  bool get outOfTiles => !won && hand.length < 14;
}

/// 101 açılış alıştırması: 22 taşlık ıstaka, en az 101'lik perler seçilir.
class Open101Practice {
  final int okeyKind;
  final List<KCard> hand;

  /// Örnek çözüm: grup grup taş sıraları.
  final List<List<KCard>> plan;

  Open101Practice._(this.okeyKind, this.hand, this.plan);

  factory Open101Practice(int seed) {
    final r = SeededRandom(mixSeed([seed, 7303]));
    final used = <KCard>{};
    KCard? take(int m) {
      for (final copy in [0, 1]) {
        if (used.add(copy * 52 + m)) return copy * 52 + m;
      }
      return null;
    }

    // Okey küçük bir sayı (gösterge 1..4): yüksek perlere karışmaz.
    final indicator = r.nextInt(4) * 13 + r.nextInt(4);
    used.add(indicator);
    final kind = okeyKindFrom(indicator);
    final plan = <List<KCard>>[];
    var total = 0;
    var guard = 0;
    while (total < 105 && guard++ < 50) {
      final g = <KCard>[];
      if (r.chance(0.5)) {
        final n = 9 + r.nextInt(4); // 10..13
        final colors = [0, 1, 2, 3]..shuffle(_Rand(r));
        for (final c in colors.take(3)) {
          final t = take(c * 13 + n);
          if (t != null) g.add(t);
        }
        if (g.length < 3) continue;
        total += (n + 1) * 3;
      } else {
        final c = r.nextInt(4), st = 7 + r.nextInt(4); // 8..13
        var v = 0;
        for (var p = st; p < st + 3 && p < 13; p++) {
          final t = take(c * 13 + p);
          if (t != null) g.add(t);
          v += p + 1;
        }
        if (g.length < 3) continue;
        total += v;
      }
      plan.add(g);
    }
    final hand = [for (final g in plan) ...g];
    final pool = [for (var t = 0; t < 106; t++) if (!used.contains(t) && !isOkeyFalseJoker(t) && t % 52 != kind && t % 13 < 7) t]..shuffle(_Rand(r));
    hand.addAll(pool.take(22 - hand.length));
    hand.sort((a, b) => (a % 52).compareTo(b % 52));
    return Open101Practice._(kind, hand, plan);
  }

  /// Seçim geçerli perlere bölünüyorsa toplamı, yoksa -1.
  int value(List<KCard> picked) => picked.length < 3 ? -1 : okeyBestPartition(_m(picked, okeyKind));
}

/// Karıştırma için SeededRandom'u dart:math Random olarak kullan (belirlenimci).
class _Rand implements math.Random {
  final SeededRandom r;
  _Rand(this.r);
  @override
  int nextInt(int max) => r.nextInt(max);
  @override
  double nextDouble() => r.nextDouble();
  @override
  bool nextBool() => r.nextInt(2) == 1;
}

// ---- Mahjong el değeri (oyunun kendi puanlamasıyla) -----------------------

/// 14 taşlık kapalı elin değeri: Riichi'de han (dora yok), Hong Kong'da fan,
/// Klasik'te puan. Oturan doğu, tur rüzgârı doğu, çiçek yok.
int mjHandValue(MahjongStyle style, List<KCard> hand14, {bool selfDraw = true}) {
  final rules = MahjongRules(style);
  final s = rules.deal(rules.deck(), 0);
  s.hands[0]
    ..clear()
    ..addAll(hand14.sublist(0, 13));
  for (var p = 0; p < rules.seats; p++) {
    s.piles[rules.exposedBase + p].clear();
    s.piles[rules.codeBase + p].clear();
  }
  final kinds = {for (final t in hand14) mjKind(t)};
  s.vars[3] = [for (var k = 0; k < 34; k++) if (!kinds.contains(k)) k].first;
  s.vars[4] = 0;
  s.vars[7] = 0;
  return rules.winValue(s, 0, hand14.last, selfDraw: selfDraw);
}

/// Doğru değerin çevresinde dört seçenek ve doğrunun yeri.
(List<int>, int) valueOptions(int v, int seed) {
  final lo = v - 1 - seed % 3;
  final opts = [for (var i = 0; i < 4; i++) (lo + i).clamp(1, 99)];
  return (opts, opts.indexOf(v));
}

// ---- Dersler -----------------------------------------------------------------

/// Riichi yaku sorusunun eli: yalnız 2-8 (tanyao).
final kYakuHand = mjHand('2p 3p 4p 5s 6s 7s 3m 4m 5m 6s 6s 6s 8m 8m');

/// Puan sorusunun eli: tek renk + ejder üçlüsü.
final kHanHand = mjHand('1m 2m 3m 4m 5m 6m 7m 8m 9m R R R 5m 5m');

/// Fan / klasik puan sorusunun eli: hepsi üçlü + doğu.
final kFanHand = mjHand('2p 2p 2p 5s 5s 5s 8m 8m 8m E E E 9p 9p');

/// Bekleyiş sorusunun 13 taşı (3p ya da 6p bekler).
final kWaitHand = mjHand('1p 2p 3p 4s 5s 6s 7m 8m 9m 2s 2s 4p 5p');

List<LessonStep> _okeyBasics() {
  final ind = okeyTile(1, 7);
  final kind = okeyKindFrom(ind);
  final runRack = [okeyTile(3, 4), okeyTile(1, 4), okeyTile(3, 5), okeyTile(2, 7), okeyTile(3, 6), okeyTile(0, 9), okeyTile(3, 9), okeyTile(1, 5)];
  final setRack = [okeyTile(0, 7), okeyTile(3, 8), okeyTile(1, 7), okeyTile(2, 2), okeyTile(3, 7), okeyTile(1, 9), okeyTile(0, 7, 1)];
  return [
    LessonStep(
      title: 'ok_tiles_t',
      body: 'ok_tiles_b',
      tiles: [okeyTile(0, 1), okeyTile(1, 5), okeyTile(2, 9), okeyTile(3, 13), kOkeyFalseJoker],
    ),
    LessonStep(
      title: 'ok_okey_t',
      body: 'ok_okey_b',
      tiles: [ind],
      marked: const {0},
      task: PickTilesTask(
        prompt: 'ok_okey_q',
        tiles: [okeyTile(3, 8), okeyTile(1, 6), okeyTile(1, 8), okeyTile(2, 8), okeyTile(1, 9)],
        check: (p) => p.length == 1 && okeyMeaning(p.first, kind) < 0,
        solution: const [2],
        single: true,
      ),
    ),
    LessonStep(
      title: 'ok_run_t',
      body: 'ok_run_b',
      tiles: [okeyTile(3, 4), okeyTile(3, 5), okeyTile(3, 6)],
      task: PickTilesTask(prompt: 'ok_run_q', tiles: runRack, check: (p) => okeyIsRun(p, _noOkey), solution: const [0, 2, 4]),
    ),
    LessonStep(
      title: 'ok_set_t',
      body: 'ok_set_b',
      tiles: [okeyTile(0, 7), okeyTile(1, 7), okeyTile(3, 7)],
      task: PickTilesTask(prompt: 'ok_set_q', tiles: setRack, check: (p) => okeyIsSet(p, _noOkey), solution: const [0, 2, 4]),
    ),
  ];
}

LessonStep _okeyJoker() {
  final ind = okeyTile(3, 2);
  final kind = okeyKindFrom(ind);
  return LessonStep(
    title: 'ok_joker_t',
    body: 'ok_joker_q',
    tiles: [ind],
    marked: const {0},
    task: PickTilesTask(
      prompt: 'select_hint',
      tiles: [okeyTile(2, 9), okeyTile(1, 5), okeyTile(3, 3), okeyTile(2, 11), okeyTile(0, 12), okeyTile(2, 2)],
      check: (p) => okeyIsRun(p, kind) && p.any((t) => okeyMeaning(t, kind) < 0),
      solution: const [0, 2, 3],
    ),
  );
}

List<LessonStep> _mahjongBasics() => [
      LessonStep(
        title: 'mj_tiles_t',
        body: 'mj_tiles_b',
        style: kTileMahjong,
        tiles: mjHand('1p 5p 9p 1s 5s 9s 1m 5m 9m E S W N R G Wh'),
      ),
      LessonStep(
        title: 'mj_hand_t',
        body: 'mj_hand_b',
        style: kTileMahjong,
        tiles: mjHand('1p 2p 3p 4s 5s 6s 7m 8m 9m E E E 5p 5p'),
        task: PickTilesTask(prompt: 'mj_chow_q', tiles: mjHand('3p 7s 4p E 5p 2m 9s 7s'), check: mjIsChow, solution: const [0, 2, 4]),
      ),
      LessonStep(
        title: 'mj_hand_t',
        body: 'mj_pung_q',
        style: kTileMahjong,
        task: PickTilesTask(prompt: 'select_hint', tiles: mjHand('R 2s R 6m R 2s N'), check: mjIsPung, solution: const [0, 2, 4]),
      ),
      LessonStep(
        title: 'mj_wait_t',
        body: 'mj_wait_b',
        style: kTileMahjong,
        tiles: kWaitHand,
        task: PickTilesTask(
          prompt: 'mj_wait_t',
          tiles: mjHand('9m 3p 5s N 6p'),
          check: (p) => p.length == 1 && mjWinning([...kWaitHand, p.first]),
          solution: const [1],
          single: true,
        ),
      ),
    ];

/// Ders adımları.
List<LessonStep> buildCourse(LessonCourse course) {
  switch (course) {
    case LessonCourse.okey:
      return [
        ..._okeyBasics(),
        _okeyJoker(),
        LessonStep(
          title: 'ok_turn_t',
          body: 'ok_turn_b',
          tiles: [
            okeyTile(3, 1), okeyTile(3, 2), okeyTile(3, 3), okeyTile(3, 4), //
            okeyTile(1, 9), okeyTile(1, 10), okeyTile(1, 11),
            okeyTile(0, 5), okeyTile(2, 5), okeyTile(3, 5),
            okeyTile(0, 12), okeyTile(1, 12), okeyTile(2, 12), okeyTile(3, 12),
          ],
        ),
        const LessonStep(title: 'ok_score_t', body: 'ok_score_b'),
        const LessonStep(title: 'practice_t', body: 'practice_b', task: PracticeTask(PracticeKind.okey, 11)),
      ];
    case LessonCourse.okey101:
      final groups = [
        [okeyTile(2, 13), okeyTile(0, 13), okeyTile(1, 13)],
        [okeyTile(3, 10), okeyTile(3, 11), okeyTile(3, 12)],
        [okeyTile(1, 7), okeyTile(1, 8), okeyTile(1, 9)],
        [okeyTile(0, 11), okeyTile(3, 11, 1), okeyTile(2, 11)],
        [okeyTile(3, 5), okeyTile(1, 6), okeyTile(2, 7)],
      ];
      final meld = [okeyTile(3, 5), okeyTile(3, 6), okeyTile(3, 7)];
      return [
        ..._okeyBasics(),
        LessonStep(
          title: 'o101_open_t',
          body: 'o101_open_b',
          task: PickGroupsTask(prompt: 'o101_open_q', groups: groups, okeyKind: _noOkey, solution: const [0, 1, 3]),
        ),
        LessonStep(
          title: 'o101_pairs_t',
          body: 'o101_pairs_b',
          tiles: [
            okeyTile(0, 3), okeyTile(0, 3, 1), okeyTile(1, 8), okeyTile(1, 8, 1), okeyTile(2, 12), //
            okeyTile(2, 12, 1), okeyTile(3, 5), okeyTile(3, 5, 1), okeyTile(0, 10), okeyTile(0, 10, 1),
          ],
        ),
        LessonStep(
          title: 'o101_add_t',
          body: 'o101_add_b',
          tiles: meld,
          task: PickTilesTask(
            prompt: 'select_hint',
            tiles: [okeyTile(3, 9), okeyTile(1, 7), okeyTile(3, 4), okeyTile(2, 8)],
            check: (p) => p.length == 1 && okeyIsRun([...meld, p.first], _noOkey),
            solution: const [2],
            single: true,
          ),
        ),
        const LessonStep(title: 'o101_pen_t', body: 'o101_pen_b'),
        const LessonStep(title: 'open_t', body: 'open_b', task: PracticeTask(PracticeKind.open101, 21)),
      ];
    case LessonCourse.riichi:
      final (opts, correct) = valueOptions(mjHandValue(MahjongStyle.riichi, kHanHand), 1);
      return [
        ..._mahjongBasics(),
        LessonStep(
          title: 'ri_yaku_t',
          body: 'ri_yaku_b',
          style: kTileMahjong,
          tiles: kYakuHand,
          task: ChoiceTask(
            prompt: 'ri_yaku_q',
            options: [
              (l) => lessonText('yaku_tanyao', l),
              (l) => lessonText('yaku_yakuhai', l),
              (l) => lessonText('yaku_chiitoi', l),
              (l) => lessonText('yaku_flush', l),
            ],
            correct: 0,
          ),
        ),
        LessonStep(title: 'ri_riichi_t', body: 'ri_riichi_b', style: kTileMahjong, tiles: kYakuHand.sublist(0, 13)),
        LessonStep(
          title: 'ri_score_t',
          body: 'ri_score_b',
          style: kTileMahjong,
          tiles: kHanHand,
          task: ChoiceTask(prompt: 'ri_score_t', options: [for (final o in opts) (l) => lessonText('han_n', l, {'n': o})], correct: correct),
        ),
        const LessonStep(title: 'practice_t', body: 'practice_b', style: kTileMahjong, task: PracticeTask(PracticeKind.mahjong, 31)),
      ];
    case LessonCourse.classic:
      final (opts, correct) = valueOptions(mjHandValue(MahjongStyle.classic, kFanHand), 2);
      return [
        ..._mahjongBasics(),
        LessonStep(
          title: 'cl_score_t',
          body: 'cl_score_b',
          style: kTileMahjong,
          tiles: kFanHand,
          task: ChoiceTask(prompt: 'cl_score_t', options: [for (final o in opts) (l) => lessonText('pts_n', l, {'n': o})], correct: correct),
        ),
        const LessonStep(title: 'practice_t', body: 'practice_b', style: kTileMahjong, task: PracticeTask(PracticeKind.mahjong, 41)),
      ];
    case LessonCourse.hongKong:
      final (opts, correct) = valueOptions(mjHandValue(MahjongStyle.hongKong, kFanHand), 0);
      return [
        ..._mahjongBasics(),
        const LessonStep(title: 'hk_flowers_t', body: 'hk_flowers_b', style: kTileMahjong, tiles: [2200, 2201, 2204, 2205]),
        LessonStep(
          title: 'hk_fan_t',
          body: 'hk_fan_b',
          style: kTileMahjong,
          tiles: kFanHand,
          task: ChoiceTask(prompt: 'hk_fan_t', options: [for (final o in opts) (l) => lessonText('fan_n', l, {'n': o})], correct: correct),
        ),
        const LessonStep(title: 'practice_t', body: 'practice_b', style: kTileMahjong, task: PracticeTask(PracticeKind.mahjong, 51)),
      ];
  }
}
