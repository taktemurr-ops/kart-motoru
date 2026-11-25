import 'dart:math' as math;

import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'kart_texts.dart';
import 'table_engine.dart';
import 'tile_painter.dart';

// ======================================================================
// Okey taşlarının anlamı ve per denetimi

/// Göstergeden okey türü: aynı renk, bir büyük sayı (13'ten sonra 1).
int okeyKindFrom(KCard indicator) => okeyColor(indicator) * 13 + okeyNumber(indicator) % 13;

/// Taşın anlamı: -1 joker (okey), aksi halde renk * 13 + (sayı - 1).
/// Sahte okey, okeyin yerine geçer.
int okeyMeaning(KCard t, int okeyKind) {
  if (isOkeyFalseJoker(t)) return okeyKind;
  return t % 52 == okeyKind ? -1 : t % 52;
}

const _okeyDots = ['🟡', '🔵', '⚫', '🔴'];
String okeyName(int meaning) => meaning < 0 ? '★' : '${_okeyDots[meaning ~/ 13]}${meaning % 13 + 1}';

/// Bütün taşlar perlere (en az 3'lü set ya da seri) bölünebiliyor mu?
bool okeyAllGrouped(List<int> meanings) {
  final cnt = List.filled(52, 0);
  var w = 0;
  for (final m in meanings) {
    if (m < 0) {
      w++;
    } else {
      cnt[m]++;
    }
  }
  return _grp(cnt, w);
}

bool _grp(List<int> cnt, int w) {
  var f = -1;
  for (var i = 0; i < 52; i++) {
    if (cnt[i] > 0) {
      f = i;
      break;
    }
  }
  if (f < 0) return w == 0 || w >= 3;
  final c = f ~/ 13, n0 = f % 13;
  cnt[f]--;
  try {
    // Set: aynı sayı, farklı renkler (3 ya da 4).
    final others = [for (var oc = 0; oc < 4; oc++) if (oc != c && cnt[oc * 13 + n0] > 0) oc * 13 + n0];
    for (var mask = 0; mask < 1 << others.length; mask++) {
      final pick = [for (var k = 0; k < others.length; k++) if ((mask >> k) & 1 == 1) others[k]];
      for (var wu = 0; wu <= w; wu++) {
        final size = 1 + pick.length + wu;
        if (size < 3 || size > 4) continue;
        for (final x in pick) {
          cnt[x]--;
        }
        final ok = _grp(cnt, w - wu);
        for (final x in pick) {
          cnt[x]++;
        }
        if (ok) return true;
      }
    }
    // Seri: aynı renk, ardışık. Konum 13, 13'ten sonraki 1'dir.
    bool ext(int s, int e, int wl, int len) {
      if (len >= 3 && _grp(cnt, wl)) return true;
      final nx = e + 1;
      if (nx > 13 || (nx == 13 && s == 0)) return false;
      final idx = c * 13 + nx % 13;
      if (cnt[idx] > 0) {
        cnt[idx]--;
        final ok = ext(s, nx, wl, len + 1);
        cnt[idx]++;
        if (ok) return true;
      }
      return wl > 0 && ext(s, nx, wl - 1, len + 1);
    }

    for (var s = n0 - (w < n0 ? w : n0); s <= n0; s++) {
      if (ext(s, n0, w - (n0 - s), n0 - s + 1)) return true;
    }
    if (n0 == 0) {
      // 1, serinin sonunda (… 12, 13, 1).
      bool fill(int pos, int wl) {
        if (pos > 12) return _grp(cnt, wl);
        final idx = c * 13 + pos;
        if (cnt[idx] > 0) {
          cnt[idx]--;
          final ok = fill(pos + 1, wl);
          cnt[idx]++;
          if (ok) return true;
        }
        return wl > 0 && fill(pos + 1, wl - 1);
      }

      for (var s = 11; s >= 1; s--) {
        if (fill(s, w)) return true;
      }
    }
    return false;
  } finally {
    cnt[f]++;
  }
}

/// Yedi (ya da [need]) çift: aynı taşlar ya da joker + herhangi bir taş.
int okeyPairCount(List<int> meanings) {
  final cnt = <int, int>{};
  var w = 0;
  for (final m in meanings) {
    if (m < 0) {
      w++;
    } else {
      cnt[m] = (cnt[m] ?? 0) + 1;
    }
  }
  var pairs = 0, singles = 0;
  for (final v in cnt.values) {
    pairs += v ~/ 2;
    singles += v % 2;
  }
  final use = math.min(w, singles);
  return pairs + use + (w - use) ~/ 2;
}

/// Tek bir grubun (set ya da seri) değeri; geçersizse -1. Jokerler temsil
/// ettikleri sayıyla sayılır.
int okeyGroupValue(List<int> meanings) {
  if (meanings.length < 3) return -1;
  final nat = meanings.where((m) => m >= 0).toList();
  final w = meanings.length - nat.length;
  if (nat.isEmpty) return -1;
  // Set
  if (meanings.length <= 4 && nat.every((m) => m % 13 == nat.first % 13) && nat.map((m) => m ~/ 13).toSet().length == nat.length) {
    return (nat.first % 13 + 1) * meanings.length;
  }
  // Seri
  if (nat.map((m) => m ~/ 13).toSet().length != 1) return -1;
  final len = meanings.length;
  // Doğal taşların konumları; 1 hem 0 hem 13 olabilir.
  for (final hiAce in [false, true]) {
    final pos = [for (final m in nat) (m % 13 == 0 && hiAce) ? 13 : m % 13]..sort();
    if (pos.toSet().length != pos.length) continue;
    final span = pos.last - pos.first + 1;
    if (span > len) continue;
    final gaps = span - pos.length;
    if (gaps > w) continue;
    // Kalan jokerleri olabildiğince yukarı, sığmazsa aşağı yerleştir.
    var s = pos.first;
    var e = pos.last + (w - gaps);
    final top = pos.first == 0 ? 12 : 13;
    if (e > top) {
      s -= e - top;
      e = top;
    }
    if (s < 0 || (s == 0 && e == 13)) continue;
    var v = 0;
    for (var p = s; p <= e; p++) {
      v += p == 13 ? 1 : p + 1;
    }
    return v;
  }
  return -1;
}

/// Elin en iyi bölünüşü: perlere giren en çok taş ve dışarıda kalan doğal
/// taşların anlamları. Durumlar not alınarak bir kez aranır.
(int, List<int>) okeyCoverPlan(List<int> meanings) {
  final cnt = List.filled(52, 0);
  var w = 0;
  for (final m in meanings) {
    if (m < 0) {
      w++;
    } else {
      cnt[m]++;
    }
  }
  final memo = <(int, int, int), int>{};
  (int, int, int) key(int wl) {
    var lo = 0, hi = 0;
    for (var i = 0; i < 26; i++) {
      lo |= cnt[i] << (2 * i);
      hi |= cnt[26 + i] << (2 * i);
    }
    return (lo, hi, wl);
  }

  // Bir durumdaki seçenekler: (kullanılan doğal taşlar, kullanılan joker, kapsanan).
  List<(List<int>, int, int)> options(int wl) {
    var f = -1;
    for (var i = 0; i < 52; i++) {
      if (cnt[i] > 0) {
        f = i;
        break;
      }
    }
    if (f < 0) return const [];
    final out = <(List<int>, int, int)>[([f], 0, 0)];
    final c = f ~/ 13, n0 = f % 13;
    final others = [for (var oc = 0; oc < 4; oc++) if (oc != c && cnt[oc * 13 + n0] > 0) oc * 13 + n0];
    for (var mask = 0; mask < 1 << others.length; mask++) {
      final pick = [f, for (var k = 0; k < others.length; k++) if ((mask >> k) & 1 == 1) others[k]];
      for (var wu = 0; wu <= wl; wu++) {
        final size = pick.length + wu;
        if (size >= 3 && size <= 4) out.add((pick, wu, size));
      }
    }
    // Seriler: f'nin önü jokerle doldurulabilir, arkası taş ya da jokerle uzar.
    for (var st = n0 - (wl < n0 ? wl : n0); st <= n0; st++) {
      final used = <int>[f];
      var wu = n0 - st;
      cnt[f]--;
      final taken = <int>[];
      for (var e = n0 + 1; e <= 13; e++) {
        if (e == 13 && st == 0) break;
        final idx = c * 13 + e % 13;
        if (cnt[idx] > 0) {
          cnt[idx]--;
          taken.add(idx);
          used.add(idx);
        } else if (wu < wl) {
          wu++;
        } else {
          break;
        }
        final len = e - st + 1;
        if (len >= 3) out.add((List.of(used), wu, len));
      }
      if (n0 - st + 1 >= 3) out.add(([f], n0 - st, n0 - st + 1));
      for (final x in taken) {
        cnt[x]++;
      }
      cnt[f]++;
    }
    if (n0 == 0) {
      // 1 sonda: … 12, 13, 1.
      for (var st = 11; st >= 1; st--) {
        final used = <int>[f];
        var wu = 0;
        var ok = true;
        for (var pos = st; pos <= 12; pos++) {
          final idx = c * 13 + pos;
          final have = cnt[idx] - used.where((x) => x == idx).length;
          if (have > 0) {
            used.add(idx);
          } else if (wu < wl) {
            wu++;
          } else {
            ok = false;
            break;
          }
        }
        if (ok) out.add((used, wu, 14 - st));
      }
    }
    return out;
  }

  int best(int wl) {
    final k = key(wl);
    final m = memo[k];
    if (m != null) return m;
    var v = 0;
    for (final (used, wu, cov) in options(wl)) {
      for (final x in used) {
        cnt[x]--;
      }
      final r = cov + best(wl - wu);
      for (final x in used) {
        cnt[x]++;
      }
      if (r > v) v = r;
    }
    memo[k] = v;
    return v;
  }

  final total = best(w);
  // Çözümü yeniden kur; dışarıda kalan taşları topla.
  final skipped = <int>[];
  var wl = w;
  while (true) {
    final opts = options(wl);
    if (opts.isEmpty) break;
    final target = best(wl);
    var found = false;
    for (final (used, wu, cov) in opts) {
      for (final x in used) {
        cnt[x]--;
      }
      final r = cov + best(wl - wu);
      if (r == target) {
        if (cov == 0) skipped.add(used.first);
        wl -= wu;
        found = true;
        break;
      }
      for (final x in used) {
        cnt[x]++;
      }
    }
    if (!found) break;
  }
  return (total, skipped);
}

/// Ucuz taş değeri: komşuları (aynı sayı başka renk, aynı renk ±1/±2) çok olan
/// taş tutulur. Joker hiç atılmaz.
int okeyKeepScore(List<int> m, int i) {
  final x = m[i];
  if (x < 0) return 1000;
  var sc = 0;
  final colors = <int>{};
  for (var j = 0; j < m.length; j++) {
    if (j == i || m[j] < 0) continue;
    final y = m[j];
    if (y == x) sc += 3;
    if (y % 13 == x % 13 && y ~/ 13 != x ~/ 13) colors.add(y ~/ 13);
    if (y ~/ 13 == x ~/ 13) {
      final d = ((y % 13) - (x % 13)).abs();
      if (d == 1 || d == 12) sc += 4;
      if (d == 2 || d == 11) sc += 2;
    }
  }
  return sc + colors.length * 4;
}

// ======================================================================
// Okey

/// Okey: 106 taş, gösterge ve okey. Sırası gelen ya desteden ya da önceki
/// oyuncunun attığı taşı alır, sonra bir taş atar. 14 taşın hepsi perlere
/// (set ya da seri) ya da yedi çifte ayrılınca son taşı atıp eli bitirir.
///
/// piles: 0 deste (kapalı), 1 atık, 2 gösterge.
/// vars: 0 aşama (0 çek, 1 at), 1 okey türü, 2 bitiren + 1.
class OkeyRules extends TableRules {
  final int players;
  final bool partners;

  /// Katlamalı: çiftle ya da okey atarak bitirmek puanı ikiye katlar
  /// (ikisi birden dört kat); göstergeyi elinde tutan başta 1 puan alır.
  final bool doubling;

  /// Göstergenin eşini elinde tutan gösterir: diğerleri 1 puan kaybeder
  /// (maçta her zaman; Katlamalı'da bölümde de).
  final bool showIndicator;
  const OkeyRules({this.players = 4, this.partners = false, this.doubling = false, this.showIndicator = false});

  /// Maç: herkes 20 puanla başlar. Biri bitirince diğerleri 2 (okey atarak
  /// ya da çiftle 4) puan kaybeder; göstergeyi gösteren için diğerleri 1
  /// kaybeder. Puanı sıfıra inen olunca maç biter, en yüksek kazanır.
  @override
  MatchFormat get matchFormat => const MatchFormat(start: 20);

  @override
  TableRules rulesForMatch(int deal, List<List<int>> history) =>
      OkeyRules(players: players, partners: partners, doubling: doubling, showIndicator: true);

  /// Elin kazandırdığı puanlar diğerlerinden düşülür (eşli oyunda karşı taraftan).
  @override
  List<int> matchPoints(TableState s) {
    final sc = s.scores;
    if (partners) {
      return [for (var p = 0; p < seats; p++) -sc[(p + 1) % seats]];
    }
    final sum = sc.fold<int>(0, (a, b) => a + b);
    return [for (var p = 0; p < seats; p++) -(sum - sc[p])];
  }

  @override
  String? matchLabel(String lang) => '${kt(lang, 'startPts')}: 20  ·  ${kt(lang, 'okeyDown')}';

  @override
  int get seats => players;
  @override
  bool get partnerships => partners;
  @override
  int get tileStyle => kTileOkey;
  @override
  double get tileAspect => 1.38;
  @override
  List<KCard> deck() => [for (var i = 0; i < 106; i++) i];

  static const _labelsIndicator = [
    'Gösterge', 'Indicator', 'Anzeiger', 'Indicador', 'Indicateur', 'المؤشر', 'نشانگر', 'מחוון', 'اشارہ', 'Указатель', 'Покажчик', 'Wskaźnik', 'Ukazatel', 'Indicator', 'Jelző', 'Δείκτης', 'Indicatore', 'Indicador', 'Wijzer', 'Visare', 'Viser', 'Viser', 'Osoitin', '表示牌', '표시패', '指示牌', 'संकेतक', 'নির্দেশক', 'Penunjuk', 'Penunjuk', 'ตัวบอก', 'Quân chỉ', 'Tagapagpahiwatig',
  ];

  @override
  List<PileView> get pileViews => const [
        PileView('Deste', 'Stock', faceUp: false),
        PileView('Atık', 'Discard'),
        PileView('Gösterge', 'Indicator', labels: _labelsIndicator),
      ];

  int kind(TableState s) => s.vars[1];
  List<int> meanings(TableState s, List<KCard> tiles) => [for (final t in tiles) okeyMeaning(t, kind(s))];

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final deck = List.of(shuffled);
    var ind = deck.removeLast();
    while (isOkeyFalseJoker(ind)) {
      deck.insert(0, ind);
      ind = deck.removeLast();
    }
    final starter = (dealer + 1) % seats;
    final hands = [for (var p = 0; p < seats; p++) <KCard>[]];
    for (var p = 0; p < seats; p++) {
      for (var k = 0; k < 14; k++) {
        hands[p].add(deck.removeLast());
      }
    }
    hands[starter].add(deck.removeLast());
    final s = TableState(seats: seats, hands: hands, piles: [deck, [], [ind]], turn: starter);
    s.vars[1] = okeyKindFrom(ind);
    s.vars[0] = 1;
    for (final h in hands) {
      _sort(s, h);
    }
    if (doubling || showIndicator) {
      // Göstergenin eşini elinde tutan 1 puan alır.
      for (var p = 0; p < seats; p++) {
        if (hands[p].any((t) => t != ind && !isOkeyFalseJoker(t) && t % 52 == ind % 52)) _award(s, p, 1);
      }
    }
    return s;
  }

  void _award(TableState s, int p, int pts) {
    s.scores[p] += pts;
    if (partners) s.scores[(p + 2) % seats] += pts;
  }

  void _sort(TableState s, List<KCard> h) {
    final k = kind(s);
    h.sort((a, b) {
      final ma = okeyMeaning(a, k), mb = okeyMeaning(b, k);
      return (ma < 0 ? 999 : ma).compareTo(mb < 0 ? 999 : mb);
    });
  }

  /// [hand] taşlarından [d] atılınca kalan el bitmiş mi? 1 per, 2 çift, 0 değil.
  int _finishKind(TableState s, List<KCard> hand, KCard d) {
    final rest = [...hand]..remove(d);
    final m = meanings(s, rest);
    if (okeyAllGrouped(m)) return 1;
    if (okeyPairCount(m) >= 7) return 2;
    return 0;
  }

  @override
  List<TAction> legalActions(TableState s) {
    if (s.over) return const [];
    final h = s.hands[s.turn];
    if (s.vars[0] == 0) {
      return [
        const TAction(1, [], 0),
        if (s.piles[1].isNotEmpty) const TAction(1, [], 1),
      ];
    }
    final out = <TAction>[];
    final seen = <int>{};
    for (final t in h) {
      final key = isOkeyFalseJoker(t) ? 200 : t % 52;
      if (!seen.add(key)) continue;
      if (_finishKind(s, h, t) > 0) out.add(TAction(9, [t]));
      out.add(TAction(0, [t]));
    }
    return out;
  }

  @override
  void apply(TableState s, TAction a) {
    final p = s.turn;
    final h = s.hands[p];
    s.lastSeat = p;
    s.last = a;
    switch (a.kind) {
      case 1:
        if (a.target == 1 && s.piles[1].isNotEmpty) {
          h.add(s.piles[1].removeLast());
        } else {
          if (s.piles[0].isEmpty) {
            s.over = true; // deste bitti: kimse kazanmadı
            return;
          }
          h.add(s.piles[0].removeLast());
        }
        _sort(s, h);
        s.vars[0] = 1;
      case 9:
        final t = a.cards.first;
        final kindDone = _finishKind(s, h, t);
        h.remove(t);
        s.piles[1].add(t);
        var pts = 2;
        final okeyOut = okeyMeaning(t, kind(s)) < 0;
        if (doubling) {
          if (kindDone == 2) pts *= 2;
          if (okeyOut) pts *= 2;
        } else if (kindDone == 2 || okeyOut) {
          pts = 4;
        }
        _award(s, p, pts);
        s.vars[2] = p + 1;
        s.over = true;
      default:
        h.remove(a.cards.first);
        s.piles[1].add(a.cards.first);
        s.vars[0] = 0;
        s.turn = (p + 1) % seats;
    }
  }

  @override
  List<int> finalScores(TableState s) => s.scores;

  @override
  String actionLabel(TAction a, String lang) => switch (a.kind) {
        1 => a.target == 0 ? kt(lang, 'drawStock') : kt(lang, 'takeDiscard'),
        9 => '${kt(lang, 'finish')} ✓',
        _ => '→ ${a.cards.length}',
      };

  @override
  bool isCardPlay(TAction a) => a.kind == 0;

  @override
  TAction quick(TableState s, SeededRandom r) {
    final p = s.turn;
    final h = s.hands[p];
    if (s.vars[0] == 0) {
      if (s.piles[1].isNotEmpty) {
        final t = s.piles[1].last;
        if (okeyMeaning(t, kind(s)) < 0) return const TAction(1, [], 1);
        final before = okeyCoverPlan(meanings(s, h)).$1;
        final after = okeyCoverPlan(meanings(s, [...h, t])).$1;
        if (after > before) return const TAction(1, [], 1);
      }
      return const TAction(1, [], 0);
    }
    final m = meanings(s, h);
    final (_, skipped) = okeyCoverPlan(m);
    if (skipped.length <= 1) {
      for (final t in h) {
        if ((skipped.isEmpty || t % 52 == skipped.first || (isOkeyFalseJoker(t) && kind(s) == skipped.first)) && _finishKind(s, h, t) > 0) {
          return TAction(9, [t]);
        }
      }
    }
    if (okeyPairCount(m) >= 7) {
      for (final t in h) {
        if (_finishKind(s, h, t) > 0) return TAction(9, [t]);
      }
    }
    // Dışarıda kalanlardan en az komşusu olanı at.
    var best = -1, bv = 1 << 30;
    for (var i = 0; i < h.length; i++) {
      if (m[i] < 0) continue;
      final out = skipped.contains(m[i]);
      final v = okeyKeepScore(m, i) * 4 + (out ? 0 : 1000) + r.nextInt(3);
      if (v < bv) {
        bv = v;
        best = i;
      }
    }
    if (best < 0) best = 0;
    return TAction(0, [h[best]]);
  }

  @override
  String status(TableState s, String lang) =>
      'Okey: ${okeyName(kind(s))}  ·  ${Strings.tx(lang, 'Deste', 'Stock')}: ${s.piles[0].length}';
}

// ======================================================================
// 101 Okey

/// 101 Okey: 21 taş (başlayan 22). Elini açmak için perlerin toplamı en az
/// 101 olmalı ya da en az beş çift açılmalı. Açan oyuncu yeni per açabilir ve
/// masadaki perlere taş işleyebilir. Elini ilk bitiren kazanır; ceza puanları:
/// açmayan 202, açan elindeki taşların toplamı, bitiren -101 (okey atarak
/// bitirirse -202). Çiftle açanın cezası iki katıdır.
///
/// piles: 0 deste, 1 atık, 2 gösterge, 3 masadaki perler (gösterim), 4+ perler.
/// vars: 0 aşama, 1 okey türü, 2 açanlar (bit), 3 çiftle açanlar (bit).
class Okey101Rules extends OkeyRules {
  const Okey101Rules({super.players = 4, super.partners = false});

  /// Maç: önceden belirlenen sayıda el (9) oynanır; ceza puanları toplanır,
  /// en az cezası olan kazanır.
  @override
  MatchFormat get matchFormat => const MatchFormat(deals: 9, lowWins: true);

  @override
  TableRules rulesForMatch(int deal, List<List<int>> history) => this;

  /// Elin ceza puanları. Deste biter de kimse bitiremezse el sayılmaz;
  /// yalnız elinde okey (joker) tutan, her biri için 101 ceza yazar.
  @override
  List<int> matchPoints(TableState s) {
    final finished = s.hands.any((h) => h.isEmpty);
    final pen = <int>[
      for (var p = 0; p < seats; p++)
        finished ? -s.scores[p] : 101 * s.hands[p].where((t) => okeyMeaning(t, kind(s)) < 0).length,
    ];
    if (partners && !finished) {
      return [for (var p = 0; p < seats; p++) pen[p] + pen[(p + 2) % seats]];
    }
    return pen;
  }

  @override
  String? matchLabel(String lang) => '9 × ${kt(lang, 'deal')}  ·  ${kt(lang, 'least')}';

  static const _labelsMelds = [
    'Masa', 'Table', 'Tisch', 'Mesa', 'Table', 'الطاولة', 'میز', 'שולחן', 'میز', 'Стол', 'Стіл', 'Stół', 'Stůl', 'Masă', 'Asztal', 'Τραπέζι', 'Tavolo', 'Mesa', 'Tafel', 'Bord', 'Bord', 'Bord', 'Pöytä', '場', '테이블', '桌面', 'मेज़', 'টেবিল', 'Meja', 'Meja', 'โต๊ะ', 'Bàn', 'Mesa',
  ];

  @override
  List<PileView> get pileViews => const [
        PileView('Deste', 'Stock', faceUp: false),
        PileView('Atık', 'Discard'),
        PileView('Gösterge', 'Indicator', labels: OkeyRules._labelsIndicator),
        PileView('Masa', 'Table', spread: true, maxShown: 60, labels: _labelsMelds),
      ];

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final deck = List.of(shuffled);
    var ind = deck.removeLast();
    while (isOkeyFalseJoker(ind)) {
      deck.insert(0, ind);
      ind = deck.removeLast();
    }
    final starter = (dealer + 1) % seats;
    final hands = [for (var p = 0; p < seats; p++) <KCard>[]];
    for (var p = 0; p < seats; p++) {
      for (var k = 0; k < 21; k++) {
        hands[p].add(deck.removeLast());
      }
    }
    hands[starter].add(deck.removeLast());
    final s = TableState(seats: seats, hands: hands, piles: [deck, [], [ind], []], turn: starter);
    s.vars[1] = okeyKindFrom(ind);
    s.vars[0] = 1;
    for (final h in hands) {
      _sort(s, h);
    }
    return s;
  }

  bool opened(TableState s, int p) => (s.vars[2] >> p) & 1 == 1;
  bool pairOpened(TableState s, int p) => (s.vars[3] >> p) & 1 == 1;
  List<List<KCard>> melds(TableState s) => s.piles.length > 4 ? s.piles.sublist(4) : const [];

  int value(TableState s, KCard t) {
    final m = okeyMeaning(t, kind(s));
    return m < 0 ? 25 : m % 13 + 1;
  }

  /// Eldeki aday gruplar (set ve seriler, jokerle).
  List<List<KCard>> candidates(TableState s, List<KCard> hand) {
    final k = kind(s);
    final wild = [for (final t in hand) if (okeyMeaning(t, k) < 0) t];
    final byMeaning = <int, List<KCard>>{};
    for (final t in hand) {
      final m = okeyMeaning(t, k);
      if (m >= 0) byMeaning.putIfAbsent(m, () => []).add(t);
    }
    final out = <List<KCard>>[];
    for (var n = 0; n < 13; n++) {
      final cols = [for (var c = 0; c < 4; c++) if (byMeaning.containsKey(c * 13 + n)) byMeaning[c * 13 + n]!.first];
      for (var mask = 1; mask < 1 << cols.length; mask++) {
        final pick = [for (var i = 0; i < cols.length; i++) if ((mask >> i) & 1 == 1) cols[i]];
        for (var u = 0; u <= wild.length && pick.length + u <= 4; u++) {
          if (pick.length + u >= 3) out.add([...pick, ...wild.take(u)]);
        }
      }
    }
    for (var c = 0; c < 4; c++) {
      for (var st = 0; st <= 11; st++) {
        for (var e = st + 2; e <= 13; e++) {
          if (st == 0 && e == 13) continue;
          final g = <KCard>[];
          var wu = 0, nat = 0;
          for (var p = st; p <= e; p++) {
            final t = byMeaning[c * 13 + p % 13];
            if (t != null) {
              g.add(t.first);
              nat++;
            } else {
              wu++;
            }
          }
          if (nat == 0 || wu > wild.length) continue;
          if (wu > 0 && (byMeaning[c * 13 + st % 13] == null || byMeaning[c * 13 + e % 13] == null)) continue;
          out.add([...g, ...wild.take(wu)]);
        }
      }
    }
    return out.where((g) => okeyGroupValue(meanings(s, g)) > 0).toList();
  }

  /// Birbirine değmeyen grupların en değerli seçimi.
  (List<List<KCard>>, int) bestGroups(TableState s, List<KCard> hand) {
    final cands = candidates(s, hand)..sort((a, b) => b.length.compareTo(a.length));
    var best = <List<KCard>>[];
    var bestV = 0;
    final cur = <List<KCard>>[];
    final used = <KCard>{};
    var steps = 0;
    void go(int i, int v) {
      if (++steps > 15000) return;
      if (v > bestV) {
        bestV = v;
        best = List.of(cur);
      }
      for (var k = i; k < cands.length; k++) {
        final g = cands[k];
        if (g.any(used.contains)) continue;
        used.addAll(g);
        cur.add(g);
        go(k + 1, v + okeyGroupValue(meanings(s, g)));
        cur.removeLast();
        used.removeAll(g);
      }
    }

    go(0, 0);
    return (best, bestV);
  }

  List<List<KCard>> pairsIn(TableState s, List<KCard> hand) {
    final k = kind(s);
    final wild = [for (final t in hand) if (okeyMeaning(t, k) < 0) t];
    final by = <int, List<KCard>>{};
    for (final t in hand) {
      final m = okeyMeaning(t, k);
      if (m >= 0) by.putIfAbsent(m, () => []).add(t);
    }
    final out = <List<KCard>>[];
    final singles = <KCard>[];
    for (final l in by.values) {
      for (var i = 0; i + 1 < l.length; i += 2) {
        out.add([l[i], l[i + 1]]);
      }
      if (l.length.isOdd) singles.add(l.last);
    }
    singles.sort((a, b) => value(s, b).compareTo(value(s, a)));
    for (var i = 0; i < wild.length && i < singles.length; i++) {
      out.add([singles[i], wild[i]]);
    }
    return out;
  }

  static const _sep = -1;

  @override
  List<TAction> legalActions(TableState s) {
    if (s.over) return const [];
    final p = s.turn;
    final h = s.hands[p];
    if (s.vars[0] == 0) {
      return [
        const TAction(1, [], 0),
        if (s.piles[1].isNotEmpty && opened(s, p)) const TAction(1, [], 1),
      ];
    }
    final out = <TAction>[];
    if (!opened(s, p)) {
      final (gs, v) = bestGroups(s, h);
      if (v >= 101 && gs.fold<int>(0, (a, g) => a + g.length) < h.length) {
        out.add(TAction(5, [for (final g in gs) ...[...g, _sep]]));
      }
      final ps = pairsIn(s, h);
      if (ps.length >= 5 && ps.length * 2 < h.length) out.add(TAction(6, [for (final g in ps) ...[...g, _sep]]));
    } else {
      final rest = h.length;
      if (pairOpened(s, p)) {
        for (final g in pairsIn(s, h)) {
          if (g.length < rest) out.add(TAction(2, g));
        }
      } else {
        for (final g in candidates(s, h)) {
          if (g.length < rest) out.add(TAction(2, g));
        }
      }
      final ms = melds(s);
      final seen = <String>{};
      for (final t in h) {
        if (h.length <= 1) break;
        for (var i = 0; i < ms.length; i++) {
          if (ms[i].length == 2) continue; // çiftlere işlenmez
          if (okeyGroupValue(meanings(s, [...ms[i], t])) > 0 && seen.add('${okeyMeaning(t, kind(s))}/$i')) out.add(TAction(3, [t], i));
        }
      }
    }
    final seen = <int>{};
    for (final t in h) {
      final key = isOkeyFalseJoker(t) ? 200 : t % 52;
      if (seen.add(key)) out.add(TAction(0, [t]));
    }
    return out;
  }

  List<List<KCard>> _split(List<KCard> cards) {
    final out = <List<KCard>>[];
    var cur = <KCard>[];
    for (final c in cards) {
      if (c == _sep) {
        out.add(cur);
        cur = [];
      } else {
        cur.add(c);
      }
    }
    if (cur.isNotEmpty) out.add(cur);
    return out;
  }

  void _refresh(TableState s) {
    s.piles[3]
      ..clear()
      ..addAll([for (final m in melds(s)) ...m]);
  }

  @override
  void apply(TableState s, TAction a) {
    final p = s.turn;
    final h = s.hands[p];
    s.lastSeat = p;
    s.last = a;
    switch (a.kind) {
      case 1:
        if (a.target == 1 && s.piles[1].isNotEmpty) {
          h.add(s.piles[1].removeLast());
        } else {
          if (s.piles[0].isEmpty) {
            _end(s, -1, false);
            return;
          }
          h.add(s.piles[0].removeLast());
        }
        _sort(s, h);
        s.vars[0] = 1;
        return;
      case 5 || 6:
        for (final g in _split(a.cards)) {
          for (final t in g) {
            h.remove(t);
          }
          s.piles.add(g);
        }
        s.vars[2] |= 1 << p;
        if (a.kind == 6) s.vars[3] |= 1 << p;
        _refresh(s);
      case 2:
        for (final t in a.cards) {
          h.remove(t);
        }
        s.piles.add(List.of(a.cards));
        _refresh(s);
      case 3:
        h.remove(a.cards.first);
        s.piles[4 + a.target].add(a.cards.first);
        _refresh(s);
      default:
        final t = a.cards.first;
        h.remove(t);
        s.piles[1].add(t);
        if (h.isEmpty) {
          _end(s, p, okeyMeaning(t, kind(s)) < 0);
          return;
        }
        s.vars[0] = 0;
        s.turn = (p + 1) % seats;
    }
  }

  void _end(TableState s, int winner, bool okeyOut) {
    s.over = true;
    for (var p = 0; p < seats; p++) {
      int pen;
      if (p == winner) {
        pen = okeyOut ? -202 : -101;
      } else if (!opened(s, p)) {
        pen = 202;
      } else {
        pen = s.hands[p].fold<int>(0, (a, t) => a + value(s, t));
        if (pairOpened(s, p)) pen *= 2;
      }
      s.scores[p] = -pen;
    }
    if (partners) {
      for (var p = 0; p < 2; p++) {
        final team = s.scores[p] + s.scores[p + 2];
        s.scores[p] = s.scores[p + 2] = team;
      }
    }
  }

  @override
  String actionLabel(TAction a, String lang) => switch (a.kind) {
        1 => a.target == 0 ? kt(lang, 'drawStock') : kt(lang, 'takeDiscard'),
        5 => '${kt(lang, 'openHand')} ✓',
        6 => '${kt(lang, 'openHand')}: ${kt(lang, 'pairs')}',
        2 => '+ ${a.cards.length}',
        3 => '→ ${a.target + 1}',
        _ => '→',
      };

  @override
  TAction quick(TableState s, SeededRandom r) {
    final p = s.turn;
    final h = s.hands[p];
    final open = opened(s, p);
    if (s.vars[0] == 0) {
      // Açan oyuncu, atık taş masadaki bir pere işleniyor ya da elini
      // güçlendiriyorsa onu alır.
      if (open && s.piles[1].isNotEmpty) {
        final t = s.piles[1].last;
        if (okeyMeaning(t, kind(s)) < 0) return const TAction(1, [], 1);
        for (final mm in melds(s)) {
          if (mm.length > 2 && okeyGroupValue(meanings(s, [...mm, t])) > 0) return const TAction(1, [], 1);
        }
        if (!pairOpened(s, p)) {
          final before = okeyCoverPlan(meanings(s, h)).$1;
          final after = okeyCoverPlan(meanings(s, [...h, t])).$1;
          if (after > before) return const TAction(1, [], 1);
        }
      }
      return const TAction(1, [], 0);
    }
    final l = legalActions(s);
    if (!open) {
      final o5 = l.where((a) => a.kind == 5);
      if (o5.isNotEmpty) return o5.first;
      // Çiftle açmak yalnızca çiftler gerçekten güçlüyse.
      final o6 = l.where((a) => a.kind == 6);
      if (o6.isNotEmpty && pairsIn(s, h).length >= 6) return o6.first;
    } else {
      final lay = l.where((a) => a.kind == 2).toList()..sort((a, b) => b.cards.length.compareTo(a.cards.length));
      if (lay.isNotEmpty) return lay.first;
      final add = l.where((a) => a.kind == 3).toList();
      if (add.isNotEmpty) {
        // Jokeri ancak son çare olarak işle.
        add.sort((a, b) => (okeyMeaning(a.cards.first, kind(s)) < 0 ? 1 : 0).compareTo(okeyMeaning(b.cards.first, kind(s)) < 0 ? 1 : 0));
        return add.first;
      }
    }
    final m = meanings(s, h);
    final skipped = pairOpened(s, p) ? const <int>[] : okeyCoverPlan(m).$2;
    var best = -1, bv = 1 << 30;
    for (var i = 0; i < h.length; i++) {
      if (m[i] < 0 && h.length > 1) continue; // okey elde kalır
      final out = skipped.contains(m[i]);
      // Açmadan önce yüksek taşlar 101'e ulaşmak için değerlidir: dışarıda
      // kalan düşük taşları at. Açtıktan sonra ceza için yüksek taşları at.
      final vScore = open ? -value(s, h[i]) * 3 : value(s, h[i]) * 2;
      final v = okeyKeepScore(m, i) * 4 + (out ? 0 : 400) + vScore + r.nextInt(3);
      if (v < bv) {
        bv = v;
        best = i;
      }
    }
    if (best < 0) best = 0;
    return TAction(0, [h[best]]);
  }

  @override
  String status(TableState s, String lang) {
    final need = opened(s, 0) ? '✓' : '101+';
    return 'Okey: ${okeyName(kind(s))}  ·  ${kt(lang, 'need')}: $need  ·  ${Strings.tx(lang, 'Deste', 'Stock')}: ${s.piles[0].length}';
  }
}
