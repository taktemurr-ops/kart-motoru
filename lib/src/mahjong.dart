import 'package:studio_core/core/rng.dart';

import 'cards.dart';
import 'kart_texts.dart';
import 'table_engine.dart';
import 'tile_painter.dart';

/// Mahjong türleri: 0..8 daire, 9..17 bambu, 18..26 karakter, 27..30 rüzgâr
/// (doğu, güney, batı, kuzey), 31..33 ejder; 34..41 çiçek/mevsim.
bool mjSuited(int k) => k < 27;
bool mjHonor(int k) => k >= 27 && k < 34;
bool mjTerminalOrHonor(int k) => mjHonor(k) || (mjSuited(k) && (k % 9 == 0 || k % 9 == 8));

enum MahjongStyle { classic, riichi, hongKong, sanma }

/// Elin 4 grup + 1 çift (ya da yedi çift) olup olmadığı. [counts] 34 türlük
/// sayılar, [sets] gereken grup sayısı.
bool mjComplete(List<int> counts, int sets) {
  for (var k = 0; k < 34; k++) {
    if (counts[k] < 2) continue;
    counts[k] -= 2;
    final ok = _sets(counts, sets, chows: true);
    counts[k] += 2;
    if (ok) return true;
  }
  return false;
}

/// Yalnızca üçlülerle (chow olmadan) çözülebiliyor mu?
bool mjCompleteNoChow(List<int> counts, int sets) {
  for (var k = 0; k < 34; k++) {
    if (counts[k] < 2) continue;
    counts[k] -= 2;
    final ok = _sets(counts, sets, chows: false);
    counts[k] += 2;
    if (ok) return true;
  }
  return false;
}

bool _sets(List<int> c, int need, {required bool chows}) {
  var f = -1;
  for (var k = 0; k < 34; k++) {
    if (c[k] > 0) {
      f = k;
      break;
    }
  }
  if (f < 0) return need == 0;
  if (need == 0) return false;
  if (c[f] >= 3) {
    c[f] -= 3;
    final ok = _sets(c, need - 1, chows: chows);
    c[f] += 3;
    if (ok) return true;
  }
  if (chows && mjSuited(f) && f % 9 <= 6 && c[f + 1] > 0 && c[f + 2] > 0) {
    c[f]--;
    c[f + 1]--;
    c[f + 2]--;
    final ok = _sets(c, need - 1, chows: chows);
    c[f]++;
    c[f + 1]++;
    c[f + 2]++;
    if (ok) return true;
  }
  return false;
}

/// Hazıra uzaklık (shanten): -1 tamam, 0 bir taş eksik (tenpai). [needSets]
/// kapalı elde gereken grup sayısı; [sevenPairs] yedi çifti de hesaba katar.
int mjShanten(List<int> c, int needSets, {bool sevenPairs = false}) {
  var best = 2 * needSets;
  var sets = 0, part = 0, pair = 0;
  void scan(int k) {
    while (k < 34 && c[k] == 0) {
      k++;
    }
    if (k >= 34) {
      final p = part < needSets - sets ? part : needSets - sets;
      final v = 2 * needSets - 2 * sets - p - pair;
      if (v < best) best = v;
      return;
    }
    if (c[k] >= 3) {
      c[k] -= 3;
      sets++;
      scan(k);
      sets--;
      c[k] += 3;
    }
    final suited = k < 27;
    if (suited && k % 9 <= 6 && c[k + 1] > 0 && c[k + 2] > 0) {
      c[k]--;
      c[k + 1]--;
      c[k + 2]--;
      sets++;
      scan(k);
      sets--;
      c[k]++;
      c[k + 1]++;
      c[k + 2]++;
    }
    if (pair == 0 && c[k] >= 2) {
      c[k] -= 2;
      pair = 1;
      scan(k);
      pair = 0;
      c[k] += 2;
    }
    if (sets + part < needSets) {
      if (c[k] >= 2) {
        c[k] -= 2;
        part++;
        scan(k);
        part--;
        c[k] += 2;
      }
      if (suited && k % 9 <= 7 && c[k + 1] > 0) {
        c[k]--;
        c[k + 1]--;
        part++;
        scan(k);
        part--;
        c[k]++;
        c[k + 1]++;
      }
      if (suited && k % 9 <= 6 && c[k + 2] > 0) {
        c[k]--;
        c[k + 2]--;
        part++;
        scan(k);
        part--;
        c[k]++;
        c[k + 2]++;
      }
    }
    c[k]--;
    scan(k);
    c[k]++;
  }

  scan(0);
  var v = best;
  if (sevenPairs) {
    var pairs = 0, kinds = 0;
    for (final x in c) {
      if (x >= 2) pairs++;
      if (x >= 1) kinds++;
    }
    final sp = 6 - pairs + (kinds < 7 ? 7 - kinds : 0);
    if (sp < v) v = sp;
  }
  return v;
}

bool mjSevenPairs(List<int> counts) {
  var pairs = 0;
  for (final v in counts) {
    if (v == 2) {
      pairs++;
    } else if (v != 0) {
      return false;
    }
  }
  return pairs == 7;
}

/// Mahjong: dört (sanma'da üç) oyuncu, 13 taş. Sırası gelen duvardan çeker ve
/// bir taş atar. Atılan taşı başka oyuncular alabilir: kazanmak için
/// (öncelikli), üçlü/dörtlü tamamlamak için ya da yalnızca sıradaki oyuncu
/// sıralı üçlü için. Dört grup ve bir çift (ya da yedi çift) toplayan kazanır.
///
/// piles: 0 duvar (kapalı), 1 atıklar, 2..2+n açık grupları, 2+n..2+2n grup
/// kodları (gösterilmez: tür*100 + çeşit; 1 sıralı, 2 üçlü, 3 açık dörtlü,
/// 4 kapalı dörtlü).
/// vars: 0 aşama (0 çek, 1 at, 2 kazanma sorusu, 3 üçlü/dörtlü sorusu,
/// 4 sıralı sorusu), 1 atan, 2 sorulan sıra (atandan uzaklık), 3 dora türü,
/// 4 riichi bitleri, 5 kazanan + 1, 6 son çekilen taş + 1, 7 dağıtan,
/// 8 kendi çekişiyle mi kazandı.
class MahjongRules extends TableRules {
  final MahjongStyle style;

  /// Tur rüzgârı (0 doğu, 1 güney, 2 batı, 3 kuzey): o rüzgârın üçlüsü bir
  /// puan daha getirir. Maçta turlarla ilerler.
  final int roundWind;
  const MahjongRules([this.style = MahjongStyle.classic, this.roundWind = 0]);

  /// Maç: Riichi/Sanma Doğu + Güney turu (25.000 puanla başlanır); klasik ve
  /// Hong Kong dört rüzgâr turu. Sonuç [MahjongMatchPlan]'da hesaplanır.
  @override
  MatchFormat get matchFormat => riichiLike ? MatchFormat(start: 25000, deals: seats * 2) : MatchFormat(deals: seats * 4);

  /// Hong Kong "yarı acı" ödeme çizelgesi (fan başına, ödeyen başına).
  static const hkPay = [1, 2, 4, 8, 16, 24, 32, 48, 64, 96, 128];

  /// Riichi: han → ron değeri (çocuk / doğu).
  static int riichiPay(int han, {required bool dealer}) {
    const child = [1000, 2000, 3900, 7700, 8000, 12000, 12000, 16000, 16000, 16000, 24000, 24000, 32000];
    const east = [1500, 2900, 5800, 11600, 12000, 18000, 18000, 24000, 24000, 24000, 36000, 36000, 48000];
    final i = (han - 1).clamp(0, 12);
    return dealer ? east[i] : child[i];
  }

  /// Elin maç puanları: Riichi'de gerçek puan değerleri, Hong Kong'da fan
  /// çizelgesi; atan (ron) bütün değeri öder, kendi çekişte herkes payını öder.
  @override
  List<int> matchPoints(TableState s) {
    final w = s.vars[5] - 1;
    if (w < 0 || style == MahjongStyle.classic) return List.of(s.scores);
    final han = s.scores[w] ~/ (seats - 1);
    final tsumo = s.vars[8] == 1;
    final int total;
    if (style == MahjongStyle.hongKong) {
      total = hkPay[han.clamp(0, 10)] * (seats - 1);
    } else {
      total = riichiPay(han, dealer: seatWind(s, w) == 0);
    }
    final out = List<int>.filled(seats, 0);
    if (tsumo) {
      final each = ((total / (seats - 1)) / 100).ceil() * 100;
      final per = style == MahjongStyle.hongKong ? total ~/ (seats - 1) : each;
      for (var p = 0; p < seats; p++) {
        if (p != w) out[p] = -per;
      }
      out[w] = per * (seats - 1);
    } else {
      var from = -1;
      for (var p = 0; p < seats; p++) {
        if (p != w && s.scores[p] < 0) from = p;
      }
      if (from < 0) return List.of(s.scores);
      out[from] = -total;
      out[w] = total;
    }
    return out;
  }

  bool get riichiLike => style == MahjongStyle.riichi || style == MahjongStyle.sanma;
  bool get flowers => style == MahjongStyle.hongKong;

  @override
  int get seats => style == MahjongStyle.sanma ? 3 : 4;
  @override
  int get tileStyle => kTileMahjong;
  @override
  double get tileAspect => 1.36;

  @override
  List<KCard> deck() => [
        for (var k = 0; k < 34; k++)
          if (!(style == MahjongStyle.sanma && k >= 19 && k <= 25))
            for (var c = 0; c < 4; c++) 2000 + k * 4 + c,
        if (flowers)
          for (var i = 0; i < 8; i++) 2200 + i,
      ];

  static const _you = [
    'Sen', 'You', 'Du', 'Tú', 'Vous', 'أنت', 'تو', 'את/ה', 'آپ', 'Вы', 'Ви', 'Ty', 'Ty', 'Tu', 'Te', 'Εσύ', 'Tu', 'Você', 'Jij', 'Du', 'Dig', 'Deg', 'Sinä', 'あなた', '나', '你', 'आप', 'আপনি', 'Kamu', 'Anda', 'คุณ', 'Bạn', 'Ikaw',
  ];
  static const _wall = [
    'Duvar', 'Wall', 'Mauer', 'Muro', 'Mur', 'الجدار', 'دیوار', 'חומה', 'دیوار', 'Стена', 'Стіна', 'Mur', 'Zeď', 'Zid', 'Fal', 'Τείχος', 'Muro', 'Muralha', 'Muur', 'Mur', 'Mur', 'Mur', 'Muuri', '山', '패산', '牌墙', 'दीवार', 'দেয়াল', 'Tembok', 'Tembok', 'กำแพง', 'Tường', 'Pader',
  ];
  static const _discards = [
    'Atılanlar', 'Discards', 'Abwürfe', 'Descartes', 'Défausses', 'المرميات', 'دورریخته‌ها', 'זרוקים', 'پھینکے گئے', 'Сброс', 'Скид', 'Odrzucone', 'Odhozené', 'Aruncate', 'Dobottak', 'Πεταμένα', 'Scarti', 'Descartes', 'Afgelegd', 'Slängda', 'Kasserede', 'Kastede', 'Hylätyt', '捨て牌', '버림패', '弃牌', 'फेंके गए', 'ফেলা টুকরো', 'Buangan', 'Buangan', 'ที่ทิ้ง', 'Quân bỏ', 'Itinapon',
  ];

  @override
  List<PileView> get pileViews => [
        const PileView('Duvar', 'Wall', faceUp: false, labels: _wall),
        const PileView('Atılanlar', 'Discards', spread: true, maxShown: 48, labels: _discards),
        const PileView('Sen', 'You', spread: true, maxShown: 20, labels: _you),
        for (var p = 1; p < seats; p++) PileView('Rakip $p', 'Rival $p', spread: true, maxShown: 20, labels: [for (final r in kKartTexts['rival']!) '$r $p']),
      ];

  int get exposedBase => 2;
  int get codeBase => 2 + seats;

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final wall = List.of(shuffled);
    final hands = [for (var p = 0; p < seats; p++) <KCard>[]];
    final piles = <List<KCard>>[wall, [], for (var p = 0; p < seats * 2; p++) <KCard>[]];
    final s = TableState(seats: seats, hands: hands, piles: piles, vars: List.filled(12, 0), turn: dealer);
    for (var k = 0; k < 13; k++) {
      for (var p = 0; p < seats; p++) {
        _draw(s, p);
      }
    }
    for (final h in hands) {
      h.sort();
    }
    if (riichiLike) {
      // Dora göstergesi: duvarın başındaki taş; dora bir sonraki tür.
      final ind = mjKind(wall.first);
      s.vars[3] = ind < 27 ? (ind ~/ 9) * 9 + (ind % 9 + 1) % 9 : (ind < 31 ? 27 + (ind - 27 + 1) % 4 : 31 + (ind - 31 + 1) % 3);
    }
    s.vars[7] = dealer;
    s.vars[0] = 0;
    return s;
  }

  /// Duvardan bir taş çek; çiçekse açığa koy ve yenisini çek.
  bool _draw(TableState s, int p) {
    while (true) {
      if (s.piles[0].length <= (riichiLike ? 14 : 0)) return false;
      final t = s.piles[0].removeLast();
      if (mjKind(t) >= 34) {
        s.piles[exposedBase + p].add(t);
        continue;
      }
      s.hands[p].add(t);
      s.vars[6] = t + 1;
      return true;
    }
  }

  List<int> counts(List<KCard> tiles) {
    final c = List.filled(34, 0);
    for (final t in tiles) {
      final k = mjKind(t);
      if (k < 34) c[k]++;
    }
    return c;
  }

  List<int> codes(TableState s, int p) => s.piles[codeBase + p];
  int openSets(TableState s, int p) => codes(s, p).length;
  bool concealed(TableState s, int p) => codes(s, p).every((c) => c % 100 == 4);
  bool inRiichi(TableState s, int p) => (s.vars[4] >> p) & 1 == 1;
  int seatWind(TableState s, int p) => (p - s.vars[7] + seats) % seats;

  /// [extra] taşıyla birlikte elin tamam olup olmadığı ve puanı (yoksa -1).
  int winValue(TableState s, int p, KCard? extra, {required bool selfDraw}) {
    final tiles = [...s.hands[p], if (extra != null) extra];
    final c = counts(tiles);
    final need = 4 - openSets(s, p);
    final seven = openSets(s, p) == 0 && mjSevenPairs(c);
    if (!seven && !mjComplete(List.of(c), need)) return -1;
    // Bütün taşlar (açık gruplar dahil, çiçek hariç).
    final all = List.of(c);
    for (final code in codes(s, p)) {
      final k = code ~/ 100, kind = code % 100;
      if (kind == 1) {
        all[k]++;
        all[k + 1]++;
        all[k + 2]++;
      } else {
        all[k] += kind >= 3 ? 4 : 3;
      }
    }
    final suits = <int>{for (var k = 0; k < 27; k++) if (all[k] > 0) k ~/ 9};
    final honors = [for (var k = 27; k < 34; k++) all[k]].any((v) => v > 0);
    final full = suits.length == 1 && !honors;
    final half = suits.length == 1 && honors;
    final allPungs = !seven && codes(s, p).every((x) => x % 100 != 1) && mjCompleteNoChow(List.of(c), need);
    var dragons = 0;
    for (var k = 31; k < 34; k++) {
      if (all[k] >= 3) dragons++;
    }
    final sw = all[27 + seatWind(s, p)] >= 3 ? 1 : 0;
    final pw = all[27 + roundWind.clamp(0, 3)] >= 3 ? 1 : 0;
    final closed = concealed(s, p);
    final simples = [for (var k = 0; k < 34; k++) if (all[k] > 0) k].every((k) => !mjTerminalOrHonor(k));
    switch (style) {
      case MahjongStyle.classic:
        return 1 + (selfDraw ? 1 : 0) + (closed ? 1 : 0) + (full ? 4 : (half ? 2 : 0)) + (allPungs ? 2 : 0) + dragons + sw + pw + (seven ? 2 : 0);
      case MahjongStyle.hongKong:
        final fl = s.piles[exposedBase + p].where((t) => mjKind(t) >= 34).toList();
        final own = fl.where((t) => (mjKind(t) - 34) % 4 == seatWind(s, p)).length;
        final allChows = !seven && codes(s, p).every((x) => x % 100 == 1) && !mjCompleteNoChow(List.of(c), need) && dragons == 0;
        final fan = (selfDraw ? 1 : 0) + (closed ? 1 : 0) + (allPungs ? 3 : 0) + (full ? 7 : (half ? 3 : 0)) + (seven ? 4 : 0) + dragons + sw + pw + own + (fl.isEmpty ? 1 : 0) + (allChows ? 1 : 0);
        return fan >= 1 ? fan : -1;
      default:
        // Riichi: en az bir yaku gerekir; dora yaku sayılmaz.
        var han = 0;
        if (inRiichi(s, p)) han++;
        if (closed && selfDraw) han++;
        if (simples) han++;
        han += dragons + sw + pw;
        if (allPungs) han += 2;
        if (seven) han += 2;
        if (full) han += closed ? 6 : 5;
        if (half) han += closed ? 3 : 2;
        if (han == 0) return -1;
        return han + all[s.vars[3]];
    }
  }

  /// Atıldığında elin bir taş eksik (tenpai) kalıp kalmadığı.
  bool _tenpaiAfter(TableState s, int p, KCard discard) {
    final rest = [...s.hands[p]]..remove(discard);
    final c = counts(rest);
    final need = 4 - openSets(s, p);
    for (var k = 0; k < 34; k++) {
      if (style == MahjongStyle.sanma && k >= 19 && k <= 25) continue;
      if (c[k] >= 4) continue;
      c[k]++;
      final ok = mjComplete(List.of(c), need) || (openSets(s, p) == 0 && mjSevenPairs(c));
      c[k]--;
      if (ok) return true;
    }
    return false;
  }

  @override
  List<TAction> legalActions(TableState s) {
    if (s.over) return const [];
    final p = s.turn;
    final h = s.hands[p];
    switch (s.vars[0]) {
      case 0:
        return const [TAction(1)];
      case 1:
        final out = <TAction>[];
        if (winValue(s, p, null, selfDraw: true) > 0) out.add(const TAction(9));
        final c = counts(h);
        if (!inRiichi(s, p)) {
          for (var k = 0; k < 34; k++) {
            if (c[k] == 4) out.add(TAction(7, h.where((t) => mjKind(t) == k).toList()));
          }
          for (final code in codes(s, p)) {
            if (code % 100 == 2 && c[code ~/ 100] > 0) out.add(TAction(8, [h.firstWhere((t) => mjKind(t) == code ~/ 100)]));
          }
        }
        final last = s.vars[6] - 1;
        final locked = inRiichi(s, p) && h.contains(last);
        final seen = <int>{};
        for (final t in h) {
          if (locked && t != last) continue;
          if (!seen.add(mjKind(t))) continue;
          if (riichiLike && !inRiichi(s, p) && concealed(s, p) && s.piles[0].length > 18 && _tenpaiAfter(s, p, t)) out.add(TAction(6, [t]));
          out.add(TAction(0, [t]));
        }
        return out;
      case 2:
        return [const TAction(2), const TAction(9)];
      case 3:
        final t = s.piles[1].last;
        final k = mjKind(t);
        final mine = h.where((x) => mjKind(x) == k).toList();
        return [
          const TAction(2),
          if (mine.length >= 2) TAction(3, mine.take(2).toList()),
          if (mine.length >= 3) TAction(4, mine.take(3).toList()),
        ];
      default:
        final k = mjKind(s.piles[1].last);
        final out = <TAction>[const TAction(2)];
        KCard? find(int kind) {
          for (final x in h) {
            if (mjKind(x) == kind) return x;
          }
          return null;
        }

        for (final st in [k - 2, k - 1, k]) {
          if (st < 0 || st ~/ 9 != k ~/ 9 || st % 9 > 6 || !mjSuited(k)) continue;
          final need = [for (var j = st; j < st + 3; j++) if (j != k) j];
          final a = find(need[0]), b = find(need[1]);
          if (a != null && b != null) out.add(TAction(5, [a, b], st));
        }
        return out;
    }
  }

  /// Atılan taşı alabilecek ilk oyuncuya geç; kimse yoksa sıradaki çeker.
  void _nextClaim(TableState s) {
    final d = s.vars[1];
    final t = s.piles[1].last;
    final k = mjKind(t);
    while (s.vars[0] >= 2 && s.vars[0] <= 4) {
      final phase = s.vars[0];
      for (var off = s.vars[2] + 1; off < seats; off++) {
        final p = (d + off) % seats;
        bool can;
        if (phase == 2) {
          can = winValue(s, p, t, selfDraw: false) > 0;
        } else if (phase == 3) {
          can = !inRiichi(s, p) && s.hands[p].where((x) => mjKind(x) == k).length >= 2;
        } else {
          can = off == 1 && (!riichiLike || style == MahjongStyle.riichi) && !inRiichi(s, p);
          if (can) {
            s.turn = p;
            s.vars[2] = off;
            can = legalActions(s).length > 1;
          }
        }
        if (can) {
          s.turn = p;
          s.vars[2] = off;
          return;
        }
      }
      s.vars[2] = 0;
      if (phase == 2) {
        s.vars[0] = 3;
      } else if (phase == 3) {
        s.vars[0] = style == MahjongStyle.sanma ? 5 : 4;
      } else {
        s.vars[0] = 5;
      }
    }
    // Kimse almadı: sıradaki oyuncu çeker.
    s.turn = (d + 1) % seats;
    s.vars[0] = 0;
  }

  @override
  void apply(TableState s, TAction a) {
    final p = s.turn;
    final h = s.hands[p];
    s.lastSeat = p;
    s.last = a;
    switch (a.kind) {
      case 1:
        if (!_draw(s, p)) {
          s.over = true; // duvar bitti: berabere
          return;
        }
        h.sort();
        s.vars[0] = 1;
      case 0 || 6:
        final t = a.cards.first;
        h.remove(t);
        s.piles[1].add(t);
        if (a.kind == 6) s.vars[4] |= 1 << p;
        s.vars[1] = p;
        s.vars[2] = 0;
        s.vars[0] = 2;
        _nextClaim(s);
      case 9:
        if (s.vars[0] == 1) {
          _win(s, p, -1, winValue(s, p, null, selfDraw: true));
        } else {
          final t = s.piles[1].removeLast();
          final v = winValue(s, p, t, selfDraw: false);
          h.add(t);
          _win(s, p, s.vars[1], v);
        }
      case 2:
        _nextClaim(s);
      case 3 || 4 || 5:
        final t = s.piles[1].removeLast();
        for (final x in a.cards) {
          h.remove(x);
        }
        final group = [...a.cards, t]..sort();
        s.piles[exposedBase + p].addAll(group);
        final k = mjKind(t);
        codes(s, p).add(a.kind == 5 ? a.target * 100 + 1 : k * 100 + (a.kind == 4 ? 3 : 2));
        s.turn = p;
        s.vars[0] = 1;
        if (a.kind == 4 && !_draw(s, p)) {
          s.over = true;
          return;
        }
        h.sort();
      case 7 || 8:
        for (final x in a.cards) {
          h.remove(x);
        }
        s.piles[exposedBase + p].addAll(a.cards);
        final k = mjKind(a.cards.first);
        final cs = codes(s, p);
        if (a.kind == 7) {
          cs.add(k * 100 + 4);
        } else {
          final i = cs.indexOf(k * 100 + 2);
          cs[i] = k * 100 + 3;
        }
        if (!_draw(s, p)) {
          s.over = true;
          return;
        }
        h.sort();
    }
  }

  void _win(TableState s, int p, int from, int v) {
    s.over = true;
    s.vars[5] = p + 1;
    s.vars[8] = from < 0 ? 1 : 0;
    final pts = v < 1 ? 1 : v;
    if (from < 0) {
      for (var o = 0; o < seats; o++) {
        if (o == p) continue;
        s.scores[o] -= pts;
        s.scores[p] += pts;
      }
    } else {
      s.scores[from] -= pts * (seats - 1);
      s.scores[p] += pts * (seats - 1);
    }
  }

  @override
  String actionLabel(TAction a, String lang) => switch (a.kind) {
        1 => kt(lang, 'drawStock'),
        2 => kt(lang, 'pass'),
        3 => kt(lang, 'pung'),
        4 || 7 || 8 => kt(lang, 'kong'),
        5 => '${kt(lang, 'chow')} ${a.target % 9 + 1}-${a.target % 9 + 3}',
        6 => 'Riichi',
        9 => '${kt(lang, 'finish')} ✓',
        _ => '→',
      };

  @override
  bool isCardPlay(TAction a) => a.kind == 0;

  int _useful(List<int> c, int k) {
    if (k >= 34) return 99;
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

  int _shanten(TableState s, int p, List<KCard> tiles) =>
      mjShanten(counts(tiles), 4 - openSets(s, p), sevenPairs: openSets(s, p) == 0);

  /// Taş atıldıktan sonra en iyi shanten ve o taş.
  (int, KCard) _bestDiscard(TableState s, int p, List<KCard> hand, SeededRandom r, {KCard? only}) {
    final c = counts(hand);
    final need = 4 - openSets(s, p);
    final closed = openSets(s, p) == 0;
    var bv = 1 << 20, bt = hand.first, bs = 99;
    final seen = <int>{};
    for (final t in hand) {
      if (only != null && t != only) continue;
      final k = mjKind(t);
      if (!seen.add(k)) continue;
      c[k]--;
      final sh = mjShanten(c, need, sevenPairs: closed);
      c[k]++;
      final v = sh * 1000 - _useful(c, k) * 3 + r.nextInt(3);
      if (v < bv) {
        bv = v;
        bt = t;
        bs = sh;
      }
    }
    return (bs, bt);
  }

  @override
  TAction quick(TableState s, SeededRandom r) {
    final p = s.turn;
    final h = s.hands[p];
    switch (s.vars[0]) {
      case 0:
        return const TAction(1);
      case 2:
        return const TAction(9);
      case 1:
        if (winValue(s, p, null, selfDraw: true) > 0) return const TAction(9);
        final last = s.vars[6] - 1;
        final locked = inRiichi(s, p) && h.contains(last);
        final (sh, tile) = _bestDiscard(s, p, h, r, only: locked ? last : null);
        if (sh == 0 && riichiLike && !inRiichi(s, p) && concealed(s, p) && s.piles[0].length > 18) return TAction(6, [tile]);
        return TAction(0, [tile]);
    }
    final l = legalActions(s);
    if (l.length == 1) return l.first;
    // Alırsam ve en iyi taşı atarsam hazıra yaklaşıyor muyum?
    final now = _shanten(s, p, h);
    final t = s.piles[1].last;
    for (final a in l.reversed) {
      if (a.kind == 2) continue;
      final rest = [...h]..removeWhere(a.cards.contains);
      final need = 4 - openSets(s, p) - 1;
      final c = counts(rest);
      var after = 1 << 20;
      final seen = <int>{};
      for (final x in rest) {
        final k = mjKind(x);
        if (!seen.add(k)) continue;
        c[k]--;
        final v = mjShanten(c, need);
        c[k]++;
        if (v < after) after = v;
      }
      final honorPung = a.kind != 5 && (mjKind(t) >= 31 || mjKind(t) == 27 + seatWind(s, p));
      if (after < now || (honorPung && after <= now)) return a;
    }
    return const TAction(2);
  }

  static const _windGlyph = ['東', '南', '西', '北'];

  @override
  String status(TableState s, String lang) {
    final sw = _windGlyph[seatWind(s, 0)];
    final dora = riichiLike ? '  ·  Dora ${s.vars[3] < 27 ? '${s.vars[3] % 9 + 1}' : '★'}' : '';
    return '${_windGlyph[roundWind.clamp(0, 3)]}/$sw$dora  ·  🀫 ${s.piles[0].length}';
  }
}
