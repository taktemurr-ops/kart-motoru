import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'kart_texts.dart';
import 'trick_engine.dart';
import 'trick_games.dart' show estimateTricks, longestSuit;
import 'trick_rules.dart' show TrickGoal;

/// Orta Doğu, İran ve Güney Asya'nın eşli el alma oyunları: Tarneeb, Hokm,
/// Baloot, 29 ve Trix'in el alma sözleşmeleri.

const _suitSym = ['♠', '♥', '♦', '♣'];

String _us(String lang) => Strings.tx(lang, 'Biz', 'Us');
String _them(String lang) => Strings.tx(lang, 'Onlar', 'Them');
String _pass(String lang) => Strings.tx(lang, 'Pas', 'Pass');
String _trumpWord(String lang) => Strings.tx(lang, 'Koz', 'Trump');

/// "Biz: 5 · Onlar: 3" (koltuk 0 tarafı "biz").
String _teamLine(String lang, int a, int b) => '${_us(lang)}: $a  ·  ${_them(lang)}: $b';

// tr en de es fr ar fa he ur ru uk pl cs ro hu el it pt nl sv da nb fi ja ko zh hi bn id ms th vi fil
const kTrumpHidden = [
  'Koz gizli', 'Trump hidden', 'Trumpf verdeckt', 'Triunfo oculto', 'Atout caché', 'الحكم مخفي', 'حکم پنهان', 'השליט מוסתר',
  'ترپ چھپا ہے', 'Козырь скрыт', 'Козир прихований', 'Atu ukryte', 'Trumf skrytý', 'Atu ascuns', 'Adu rejtve', 'Ατού κρυφό',
  'Briscola nascosta', 'Trunfo oculto', 'Troef verborgen', 'Trumf dold', 'Trumf skjult', 'Trumf skjult', 'Valtti piilossa',
  '切り札は伏せ札', '으뜸패 숨김', '将牌未亮', 'तुरुप छिपा है', 'তুরুপ লুকানো', 'Truf tersembunyi', 'Trup tersembunyi',
  'ทรัมป์ซ่อนอยู่', 'Chủ bài đang úp', 'Nakatago ang trumpo',
];

int _teamTricks(TrickState s, int team) => s.tricks[team] + s.tricks[team + 2];

/// Sırayla artırılan ihale: pas diyen ihaleden çıkar. Biri ihale verip
/// diğer herkes pas deyince ihale biter; hiç kimse vermezse dağıtan en
/// düşük ihaleyi almak zorundadır. Sonra ihaleyi alan kozu seçer.
/// bids[p]: 0 pas, >0 son ihalesi; extra 2: koz seçimi, 3: seçildi.
mixin _Auction on TrickRules {
  static const trumpBase = 100;
  int get minBid;
  int get maxBid;

  int _high(TrickState s) => s.bids.whereType<int>().where((b) => b < trumpBase).fold<int>(0, (a, b) => b > a ? b : a);

  @override
  bool get hasBidding => true;

  @override
  List<int> legalBids(TrickState s, int seat) {
    if (s.extra == 2) return [for (var t = 0; t < 4; t++) trumpBase + t];
    final h = _high(s);
    return [0, for (var b = h < minBid ? minBid : h + 1; b <= maxBid; b++) b];
  }

  @override
  String bidLabel(int bid, String lang) {
    if (bid >= trumpBase) return _suitSym[bid - trumpBase];
    return bid == 0 ? _pass(lang) : '$bid';
  }

  @override
  void applyBid(TrickState s, int seat, int bid) {
    if (bid >= trumpBase) {
      chooseTrump(s, bid - trumpBase);
      s.extra = 3;
      return;
    }
    s.bids[seat] = bid;
    s.bidTurns++;
    if (bid > 0) {
      s.declarer = seat;
      s.contract = bid;
    }
    for (var k = 1; k <= seats; k++) {
      final p = (seat + k) % seats;
      if (s.bids[p] != 0) {
        s.turn = p;
        break;
      }
    }
  }

  /// İhaleyi alan kozu seçtiğinde (29'da koz kapalı tutulur).
  void chooseTrump(TrickState s, int suit) => s.trump = suit;

  @override
  bool biddingOver(TrickState s) {
    if (s.extra == 3) return true;
    if (s.extra == 2) return false;
    final passed = s.bids.where((b) => b == 0).length;
    if (s.declarer >= 0 && (passed >= seats - 1 || s.contract >= maxBid)) {
      s.extra = 2;
      s.turn = s.declarer;
    } else if (passed >= seats) {
      // Herkes pas: dağıtan en düşük ihaleyi almak zorunda.
      s.declarer = s.dealer;
      s.contract = minBid;
      s.bids[s.dealer] = minBid;
      s.extra = 2;
      s.turn = s.dealer;
    }
    return false;
  }

  /// Yapay zekânın verebileceği en yüksek ihale (elin gücüne göre).
  int bidLimit(TrickState s, int seat, SeededRandom r);
  int bestTrump(List<KCard> hand);

  @override
  int aiBid(TrickState s, int seat, SeededRandom r) {
    if (s.extra == 2) return trumpBase + bestTrump(s.hands[seat]);
    final legal = legalBids(s, seat);
    // Eşi en yüksek ihaledeyse onu geçmez.
    if (s.declarer >= 0 && s.declarer == (seat + 2) % seats) return 0;
    final limit = bidLimit(s, seat, r);
    final first = legal.length > 1 ? legal[1] : 0;
    return first > 0 && first <= limit ? first : 0;
  }

  String makersLine(TrickState s, String lang) {
    if (s.declarer < 0) return '';
    return '${kt(lang, 'makers')}: ${s.declarer % 2 == 0 ? _us(lang) : _them(lang)}';
  }
}

// ---------------------------------------------------------------- Tarneeb

/// Tarneeb (Levant): 52 kart, dörtlü ortaklı, 13'er kart. İhale 7–13 el;
/// ihaleyi alan kozu (tarneeb) seçer ve ilk eli açar. Renge uymak zorunlu,
/// rengin yoksa istediğini atarsın. Alan taraf ihalesini tutturursa aldığı
/// el kadar, tutturamazsa ihale kadar eksi yazar; karşı taraf aldığı elleri
/// yazar.
class TarneebRules extends TrickRules with _Auction {
  const TarneebRules();

  @override
  bool get partnerships => true;
  @override
  int get minBid => 7;
  @override
  int get maxBid => 13;

  @override
  int bidLimit(TrickState s, int seat, SeededRandom r) {
    final h = s.hands[seat];
    final e = estimateTricks(h, longestSuit(h)) + 2.2 + (r.nextDouble() - 0.5) * 0.6;
    return e.floor();
  }

  @override
  int bestTrump(List<KCard> hand) => longestSuit(hand);

  @override
  void finishBidding(TrickState s) {
    s.extra = 0;
    startPlay(s);
    s.leader = s.declarer;
    s.turn = s.declarer;
  }

  @override
  List<int> handScores(TrickState s) {
    final out = List<int>.filled(seats, 0);
    for (var p = 0; p < seats; p++) {
      final t = _teamTricks(s, p % 2);
      if (s.declarer >= 0 && p % 2 == s.declarer % 2) {
        out[p] = t >= s.contract ? t : -s.contract;
      } else {
        out[p] = t;
      }
    }
    return out;
  }

  @override
  String status(TrickState s, String lang) {
    if (s.declarer < 0) return '';
    final tr = s.trump >= 0 ? '  ·  ${_trumpWord(lang)}: ${_suitSym[s.trump]}' : '';
    return '${Strings.tx(lang, 'İhale', 'Contract')}: ${s.contract}$tr  ·  ${makersLine(s, lang)}';
  }
}

// ---------------------------------------------------------------- Hokm

/// Hokm (İran): 52 kart, dörtlü ortaklı. Dağıtılan ilk Ası alan "hakem"
/// olur; önce herkese 5 kart verilir, hakem bu beş karta bakıp kozu (hokm)
/// söyler, sonra kalanlar 4+4 dağıtılır. Hakem ilk eli açar. Renge uymak
/// zorunlu; rengin yoksa istediğini atarsın. 7 eli ilk alan taraf eli kazanır:
/// 1 puan; karşı taraf hiç el alamadıysa "kot" 2 puan, hakemin tarafı kot
/// olduysa 3 puan.
class HokmRules extends TrickRules {
  const HokmRules();

  static const trumpBase = 100;

  @override
  bool get partnerships => true;
  @override
  bool get hasBidding => true;

  @override
  TrickState deal(List<KCard> shuffled, int dealer) {
    // Hakem: dağıtılan ilk As'ı alan oyuncu.
    var hakem = (dealer + 1) % seats;
    for (var k = 0; k < shuffled.length; k++) {
      if (rankOf(shuffled[k]) == 1) {
        hakem = (dealer + 1 + k) % seats;
        break;
      }
    }
    final hands = List.generate(seats, (_) => <KCard>[]);
    var k = 0;
    for (var i = 0; i < seats; i++) {
      for (var j = 0; j < 5; j++) {
        hands[(hakem + i) % seats].add(shuffled[k++]);
      }
    }
    for (final h in hands) {
      sortHand(h, -1);
    }
    final s = TrickState(seats: seats, hands: hands, kitty: shuffled.sublist(k), dealer: dealer);
    s
      ..declarer = hakem
      ..leader = hakem
      ..turn = hakem;
    return s;
  }

  @override
  List<int> legalBids(TrickState s, int seat) => [for (var t = 0; t < 4; t++) trumpBase + t];

  @override
  String bidLabel(int bid, String lang) => _suitSym[(bid - trumpBase).clamp(0, 3)];

  @override
  void applyBid(TrickState s, int seat, int bid) {
    s.bids[seat] = bid;
    s.bidTurns++;
    s.trump = bid - trumpBase;
  }

  @override
  bool biddingOver(TrickState s) => s.trump >= 0;

  @override
  int aiBid(TrickState s, int seat, SeededRandom r) {
    final h = s.hands[seat];
    var best = 0, bestV = -1.0;
    for (var t = 0; t < 4; t++) {
      var v = 0.0;
      for (final c in h) {
        if (suitOf(c) != t) continue;
        v += 2 + (const {1: 4, 13: 3, 12: 2, 11: 1}[rankOf(c)] ?? 0);
      }
      v += r.nextDouble() * 0.1;
      if (v > bestV) {
        bestV = v;
        best = t;
      }
    }
    return trumpBase + best;
  }

  @override
  void finishBidding(TrickState s) {
    // Kalan kartlar hakemden başlayarak 4+4 dağıtılır.
    final hakem = s.declarer;
    var k = 0;
    for (var round = 0; round < 2; round++) {
      for (var i = 0; i < seats; i++) {
        final p = (hakem + i) % seats;
        s.hands[p].addAll(s.kitty.sublist(k, k + 4));
        k += 4;
      }
    }
    s.kitty.clear();
    startPlay(s);
    s.leader = hakem;
    s.turn = hakem;
  }

  @override
  void afterTrick(TrickState s, int winner) {
    if (_teamTricks(s, 0) >= 7 || _teamTricks(s, 1) >= 7) s.phase = TrickPhase.over;
  }

  /// Elin puanı (kazanan taraf için 1, 2 ya da 3); -1: el bitmedi.
  int winnerTeam(TrickState s) => _teamTricks(s, 0) >= 7 ? 0 : (_teamTricks(s, 1) >= 7 ? 1 : -1);

  int handPoints(TrickState s) {
    final w = winnerTeam(s);
    if (w < 0) return 0;
    if (_teamTricks(s, 1 - w) > 0) return 1;
    return (1 - w) == s.declarer % 2 ? 3 : 2;
  }

  @override
  List<int> handScores(TrickState s) {
    final w = winnerTeam(s);
    final pts = handPoints(s);
    return [for (var p = 0; p < seats; p++) (p % 2 == w ? pts * 100 : 0) + _teamTricks(s, p % 2)];
  }

  @override
  String status(TrickState s, String lang) {
    final tr = s.trump >= 0 ? '${_trumpWord(lang)}: ${_suitSym[s.trump]}  ·  ' : '';
    final hk = '${kt(lang, 'makers')}: ${s.declarer % 2 == 0 ? _us(lang) : _them(lang)}';
    return '$tr$hk  ·  ${_teamLine(lang, _teamTricks(s, 0), _teamTricks(s, 1))} / 7';
  }
}

// ---------------------------------------------------------------- Baloot

/// Baloot (Suudi Arabistan): 32 kart, dörtlü ortaklı. Herkese 5 kart, bir
/// kart açılır. İhalede "Hokm" (açık kartın rengi koz; ikinci turda başka
/// renk) ya da "Sun" (kozsuz) söylenir; Sun, Hokm'u geçer. Alan açık kartla
/// iki kart daha, diğerleri üçer kart alır (herkes 8). Kozda Vale (20) ve
/// Dokuz (14) en büyüktür. Hokm'da renge uymak, kozda yükseltmek ve rengin
/// yoksa koz atmak zorunlu (eşin eli alıyorsa serbest); Sun'da yalnız renge
/// uyulur. Alan taraf puanların yarısından fazlasını alamazsa bütün puan
/// karşıya gider. Kozun Papaz+Kızı aynı eldeyse "baloot": 2 oyun puanı.
class BalootRules extends TrickRules {
  const BalootRules();

  static const sunBid = 200, hokmBase = 100;

  @override
  bool get partnerships => true;
  @override
  bool get hasBidding => true;
  @override
  int get handSize => 8;
  @override
  List<KCard> deck() => buildDeck(ranks: const [1, 7, 8, 9, 10, 11, 12, 13]);

  static const _trumpPow = {11: 8, 9: 7, 1: 6, 10: 5, 13: 4, 12: 3, 8: 2, 7: 1};
  static const _plainPow = {1: 8, 10: 7, 13: 6, 12: 5, 11: 4, 9: 3, 8: 2, 7: 1};
  static const _trumpPts = {11: 20, 9: 14, 1: 11, 10: 10, 13: 4, 12: 3};
  static const _plainPts = {1: 11, 10: 10, 13: 4, 12: 3, 11: 2};

  @override
  int strength(KCard c) => _plainPow[rankOf(c)]!;

  int power(TrickState s, KCard c) => isTrump(s, c) ? 20 + _trumpPow[rankOf(c)]! : _plainPow[rankOf(c)]!;
  int points(TrickState s, KCard c) => (isTrump(s, c) ? _trumpPts : _plainPts)[rankOf(c)] ?? 0;

  @override
  TrickState deal(List<KCard> shuffled, int dealer) {
    final hands = List.generate(seats, (_) => <KCard>[]);
    var k = 0;
    for (final n in const [3, 2]) {
      for (var i = 1; i <= seats; i++) {
        hands[(dealer + i) % seats].addAll(shuffled.sublist(k, k + n));
        k += n;
      }
    }
    for (final h in hands) {
      sortHand(h, -1);
    }
    // kitty[0]: açık kart (ihale kartı).
    return TrickState(seats: seats, hands: hands, kitty: shuffled.sublist(k), dealer: dealer);
  }

  int upSuit(TrickState s) => suitOf(s.kitty.first);

  @override
  List<int> legalBids(TrickState s, int seat) {
    final up = upSuit(s);
    if (s.bidTurns < seats) {
      return s.contract == 1 ? [0, sunBid] : [0, hokmBase + up, sunBid];
    }
    final forced = seat == s.dealer && s.bidTurns >= 2 * seats - 1;
    return [if (!forced) 0, for (var t = 0; t < 4; t++) if (t != up) hokmBase + t, sunBid];
  }

  @override
  String bidLabel(int bid, String lang) {
    if (bid == sunBid) return kt(lang, 'noTrump');
    if (bid >= hokmBase) return '${_trumpWord(lang)} ${_suitSym[bid - hokmBase]}';
    return _pass(lang);
  }

  @override
  void applyBid(TrickState s, int seat, int bid) {
    super.applyBid(s, seat, bid);
    if (bid == sunBid) {
      s
        ..contract = 2
        ..declarer = seat
        ..trump = -1;
    } else if (bid >= hokmBase) {
      s
        ..contract = 1
        ..declarer = seat
        ..trump = bid - hokmBase;
    }
  }

  @override
  bool biddingOver(TrickState s) {
    if (s.contract == 2) return true;
    if (s.contract == 1 && (s.bidTurns >= seats)) return true;
    return s.bidTurns >= 2 * seats;
  }

  double _hokmStrength(List<KCard> hand, int trump) {
    var v = 0.0;
    for (final c in hand) {
      if (suitOf(c) == trump) {
        v += const {11: 1.7, 9: 1.3, 1: 0.9, 10: 0.7}[rankOf(c)] ?? 0.45;
      } else if (rankOf(c) == 1) {
        v += 0.8;
      } else if (rankOf(c) == 10) {
        v += 0.3;
      }
    }
    return v;
  }

  double _sunStrength(List<KCard> hand) {
    var v = 0.0;
    for (final c in hand) {
      v += const {1: 1.0, 10: 0.55, 13: 0.25}[rankOf(c)] ?? 0;
    }
    return v;
  }

  @override
  int aiBid(TrickState s, int seat, SeededRandom r) {
    final legal = legalBids(s, seat);
    final h = [...s.hands[seat], s.kitty.first];
    final noise = (r.nextDouble() - 0.5) * 0.3;
    if (s.declarer >= 0 && s.declarer % 2 == seat % 2) return legal.contains(0) ? 0 : legal.last;
    if (_sunStrength(h) + noise >= 2.9 && legal.contains(sunBid)) return sunBid;
    var best = -1, bestV = -1.0;
    for (final b in legal) {
      if (b < hokmBase || b == sunBid) continue;
      final v = _hokmStrength(h, b - hokmBase);
      if (v > bestV) {
        bestV = v;
        best = b;
      }
    }
    if (best >= 0 && (bestV + noise >= 3.4 || !legal.contains(0))) return best;
    if (!legal.contains(0)) return legal.last;
    return 0;
  }

  @override
  void finishBidding(TrickState s) {
    final up = s.kitty.removeAt(0);
    s.hands[s.declarer].add(up);
    var k = 0;
    for (var i = 1; i <= seats; i++) {
      final p = (s.dealer + i) % seats;
      final n = p == s.declarer ? 2 : 3;
      s.hands[p].addAll(s.kitty.sublist(k, k + n));
      k += n;
    }
    s.kitty.clear();
    startPlay(s);
    s.leader = (s.dealer + 1) % seats;
    s.turn = s.leader;
    // Baloot: kozun Papaz + Kızı aynı elde (extra: 1 + taraf).
    s.extra = 0;
    if (s.contract == 1) {
      for (var p = 0; p < seats; p++) {
        final h = s.hands[p];
        if (h.contains(makeCard(13, s.trump)) && h.contains(makeCard(12, s.trump))) s.extra = 1 + p % 2;
      }
    }
  }

  @override
  bool beats(TrickState s, KCard a, KCard b, int lead) {
    final ta = isTrump(s, a), tb = isTrump(s, b);
    if (ta != tb) return ta;
    if (suitOf(a) != suitOf(b)) return false;
    return power(s, a) > power(s, b);
  }

  @override
  List<KCard> legalPlays(TrickState s, int seat) {
    final h = s.hands[seat];
    if (s.trick.isEmpty) return List.of(h);
    final lead = suitOf(s.trick.first);
    final follow = h.where((c) => suitOf(c) == lead).toList();
    if (s.contract != 1) return follow.isNotEmpty ? follow : List.of(h);
    var bestIx = 0;
    for (var i = 1; i < s.trick.length; i++) {
      if (beats(s, s.trick[i], s.trick[bestIx], lead)) bestIx = i;
    }
    final best = s.trick[bestIx];
    final winner = (s.leader + bestIx) % seats;
    List<KCard> over(List<KCard> l) {
      final o = l.where((c) => beats(s, c, best, lead)).toList();
      return o.isNotEmpty ? o : l;
    }

    if (follow.isNotEmpty) return lead == s.trump ? over(follow) : follow;
    if (winner == s.partnerOf(seat)) return List.of(h);
    final trumps = h.where((c) => isTrump(s, c)).toList();
    if (trumps.isNotEmpty) return over(trumps);
    return List.of(h);
  }

  int get _sunTotal => 130;
  int get _hokmTotal => 162;

  List<int> rawPoints(TrickState s) {
    final t = [0, 0];
    for (var p = 0; p < seats; p++) {
      for (final c in s.taken[p]) {
        t[p % 2] += points(s, c);
      }
    }
    if (s.phase == TrickPhase.over && s.lastWinner >= 0) t[s.lastWinner % 2] += 10;
    return t;
  }

  /// Oyun puanları (Sun: ham puan × 2 / 10, Hokm: ham puan / 10).
  List<int> gamePoints(TrickState s) {
    final raw = rawPoints(s);
    if (s.declarer < 0) return const [0, 0];
    final total = s.contract == 2 ? _sunTotal : _hokmTotal;
    if (s.phase == TrickPhase.over) {
      final mk = s.declarer % 2;
      if (raw[mk] * 2 <= total) {
        raw[1 - mk] = total;
        raw[mk] = 0;
      }
    }
    final gp = [for (final r in raw) s.contract == 2 ? (r * 2 / 10).round() : ((r + 4) ~/ 10)];
    if (s.extra > 0) gp[s.extra - 1] += 2;
    return gp;
  }

  @override
  List<int> handScores(TrickState s) {
    final gp = gamePoints(s);
    final raw = rawPoints(s);
    return [for (var p = 0; p < seats; p++) gp[p % 2] * 1000 + raw[p % 2]];
  }

  @override
  String status(TrickState s, String lang) {
    if (s.phase == TrickPhase.bidding) {
      return '${kt(lang, 'upCard')}: ${rankLabel(rankOf(s.kitty.first))}${_suitSym[suitOf(s.kitty.first)]}';
    }
    final mode = s.contract == 2 ? kt(lang, 'noTrump') : '${_trumpWord(lang)} ${_suitSym[s.trump.clamp(0, 3)]}';
    final t = rawPoints(s);
    return '$mode  ·  ${kt(lang, 'makers')}: ${s.declarer % 2 == 0 ? _us(lang) : _them(lang)}  ·  ${_teamLine(lang, t[0], t[1])}';
  }
}

// ---------------------------------------------------------------- 29

/// 29 (Güney Asya): 32 kart, dörtlü ortaklı. Güç ve puan sırası: Vale (3),
/// Dokuz (2), As (1), On (1), Papaz, Kız, 8, 7 — toplam 28 puan. Dörder kart
/// dağıtılınca 16–28 arası ihale yapılır; ihaleyi alan kozu kapalı seçer,
/// sonra dörder kart daha dağıtılır. Rengin yoksa koz açılır ve elinde koz
/// varsa koz atmak zorundasın; koz açılmadan atılan koz renkleri koz sayılmaz.
/// Koz açıldıktan sonra kozun Papaz+Kızı ("çift") bir eldeyse ihale o tarafın
/// lehine 4 değişir. Alan taraf ihalesi kadar puan alırsa kazanır.
class TwentyNineRules extends TrickRules with _Auction {
  const TwentyNineRules();

  @override
  bool get partnerships => true;
  @override
  int get handSize => 8;
  @override
  int get minBid => 16;
  @override
  int get maxBid => 28;
  @override
  List<KCard> deck() => buildDeck(ranks: const [1, 7, 8, 9, 10, 11, 12, 13]);

  static const _pow = {11: 8, 9: 7, 1: 6, 10: 5, 13: 4, 12: 3, 8: 2, 7: 1};
  static const _pts = {11: 3, 9: 2, 1: 1, 10: 1};

  @override
  int strength(KCard c) => _pow[rankOf(c)]!;
  @override
  int cardPoints(KCard c) => _pts[rankOf(c)] ?? 0;

  @override
  TrickState deal(List<KCard> shuffled, int dealer) {
    final hands = List.generate(seats, (_) => <KCard>[]);
    var k = 0;
    for (var i = 1; i <= seats; i++) {
      hands[(dealer + i) % seats].addAll(shuffled.sublist(k, k + 4));
      k += 4;
    }
    for (final h in hands) {
      sortHand(h, -1);
    }
    return TrickState(seats: seats, hands: hands, kitty: shuffled.sublist(k), dealer: dealer);
  }

  /// Kapalı koz: extra = 10 + renk. Koz açılınca trump da bu renk olur.
  int hiddenSuit(TrickState s) => s.extra >= 10 ? s.extra - 10 : -1;
  bool revealed(TrickState s) => s.trump >= 0;

  @override
  void chooseTrump(TrickState s, int suit) {}

  @override
  void applyBid(TrickState s, int seat, int bid) {
    super.applyBid(s, seat, bid);
    if (bid >= _Auction.trumpBase) s.extra = 10 + bid - _Auction.trumpBase;
  }

  @override
  bool biddingOver(TrickState s) => s.extra >= 10 || super.biddingOver(s);

  @override
  int bidLimit(TrickState s, int seat, SeededRandom r) {
    final h = s.hands[seat];
    final t = bestTrump(h);
    var pts = 0;
    for (final c in h) {
      pts += cardPoints(c);
    }
    final trumps = h.where((c) => suitOf(c) == t).length;
    final jacks = h.where((c) => rankOf(c) == 11).length;
    final est = 12 + pts * 1.1 + trumps * 1.4 + jacks * 0.8 + (r.nextDouble() - 0.5);
    return est.floor().clamp(0, 28);
  }

  @override
  int bestTrump(List<KCard> hand) {
    var best = 0, bestV = -1;
    for (var t = 0; t < 4; t++) {
      var v = 0;
      for (final c in hand) {
        if (suitOf(c) == t) v += 10 + _pow[rankOf(c)]!;
      }
      if (v > bestV) {
        bestV = v;
        best = t;
      }
    }
    return best;
  }

  @override
  void finishBidding(TrickState s) {
    var k = 0;
    for (var i = 1; i <= seats; i++) {
      s.hands[(s.dealer + i) % seats].addAll(s.kitty.sublist(k, k + 4));
      k += 4;
    }
    s.kitty.clear();
    final hidden = s.extra;
    startPlay(s);
    s.trump = -1;
    s.extra = hidden;
    // Çift: kozun Papaz+Kızı aynı elde. bidTurns = 100 + taraf (yoksa 99).
    final h = hiddenSuit(s);
    s.bidTurns = 99;
    for (var p = 0; p < seats; p++) {
      if (s.hands[p].contains(makeCard(13, h)) && s.hands[p].contains(makeCard(12, h))) s.bidTurns = 100 + p % 2;
    }
    s.leader = (s.dealer + 1) % seats;
    s.turn = s.leader;
  }

  @override
  void sortHand(List<KCard> h, int trump) {
    int key(KCard c) => const [0, 1, 3, 2][suitOf(c)] * 100 + strength(c);
    h.sort((a, b) => key(a).compareTo(key(b)));
  }

  @override
  List<KCard> legalPlays(TrickState s, int seat) {
    final h = s.hands[seat];
    if (s.trick.isEmpty) return List.of(h);
    final lead = suitOf(s.trick.first);
    final follow = h.where((c) => suitOf(c) == lead).toList();
    if (follow.isNotEmpty) return follow;
    if (!revealed(s)) {
      // Rengi olmayan kozu açtırır ve elinde koz varsa koz atar.
      final hs = hiddenSuit(s);
      final trumps = h.where((c) => suitOf(c) == hs).toList();
      if (trumps.isNotEmpty) return trumps;
    }
    return List.of(h);
  }

  @override
  void onPlay(TrickState s, int seat, KCard c) {
    if (!revealed(s) && s.trick.length > 1 && suitOf(c) != suitOf(s.trick.first)) {
      s.trump = hiddenSuit(s);
      for (final hand in s.hands) {
        sortHand(hand, s.trump);
      }
    }
  }

  int pairTeam(TrickState s) => s.phase != TrickPhase.bidding && s.bidTurns >= 100 ? s.bidTurns - 100 : -1;

  /// Çift sayıldıktan sonraki hedef.
  int target(TrickState s) {
    var t = s.contract;
    final pt = pairTeam(s);
    if (revealed(s) && pt >= 0 && s.declarer >= 0) {
      t = pt == s.declarer % 2 ? t - 4 : t + 4;
    }
    return t.clamp(minBid, maxBid);
  }

  List<int> teamPoints(TrickState s) {
    final t = [0, 0];
    for (var p = 0; p < seats; p++) {
      for (final c in s.taken[p]) {
        t[p % 2] += cardPoints(c);
      }
    }
    return t;
  }

  @override
  List<int> handScores(TrickState s) {
    final t = teamPoints(s);
    if (s.declarer < 0) return [for (var p = 0; p < seats; p++) t[p % 2]];
    final mk = s.declarer % 2;
    final made = t[mk] >= target(s);
    return [for (var p = 0; p < seats; p++) ((p % 2 == mk) == made ? 100 : -100) + t[p % 2]];
  }

  @override
  String status(TrickState s, String lang) {
    if (s.declarer < 0 || s.phase == TrickPhase.bidding) return '';
    final t = teamPoints(s);
    final tr = revealed(s) ? '${_trumpWord(lang)}: ${_suitSym[s.trump]}' : Strings.pick(kTrumpHidden, lang);
    return '${Strings.tx(lang, 'İhale', 'Contract')}: ${target(s)}  ·  $tr  ·  ${makersLine(s, lang)}  ·  ${_teamLine(lang, t[0], t[1])}';
  }
}

// ---------------------------------------------------------------- Trix

/// Trix'in sözleşme adları (33 dil): 0 Kupa Papazı, 1 Kızlar, 2 Karolar,
/// 3 Eller (Ltoosh), 4 Trix (dizme).
const kTrixContracts = [
  ['Kupa Papazı', 'King of Hearts', 'Herzkönig', 'Rey de corazones', 'Roi de cœur', 'شيخ الكبة', 'شاه دل', 'מלך לב', 'پان کا بادشاہ', 'Червовый король', 'Червовий король', 'Król kier', 'Srdcový král', 'Popa de cupă', 'Kőr király', 'Ρήγας κούπα', 'Re di cuori', 'Rei de copas', 'Hartenheer', 'Hjärter kung', 'Hjerter konge', 'Hjerter konge', 'Herttakuningas', 'ハートのキング', '하트 킹', '红心K', 'पान का बादशाह', 'হরতনের সাহেব', 'King hati', 'Raja lekuk', 'คิงโพแดง', 'Già cơ', 'Hari ng puso'],
  ['Kızlar', 'Queens', 'Damen', 'Damas', 'Dames', 'البنات', 'بی‌بی‌ها', 'מלכות', 'بیگمات', 'Дамы', 'Дами', 'Damy', 'Dámy', 'Damele', 'Dámák', 'Ντάμες', 'Donne', 'Damas', 'Vrouwen', 'Damer', 'Damer', 'Damer', 'Kuningattaret', 'クイーン', '퀸', '皇后', 'बेगमें', 'বিবিরা', 'Ratu', 'Ratu', 'ควีน', 'Đầm', 'Mga reyna'],
  ['Karolar', 'Diamonds', 'Karos', 'Diamantes', 'Carreaux', 'الديناري', 'خشت‌ها', 'יהלומים', 'اینٹیں', 'Бубны', 'Бубни', 'Kara', 'Káry', 'Romburi', 'Kárók', 'Καρά', 'Quadri', 'Ouros', 'Ruiten', 'Ruter', 'Ruder', 'Ruter', 'Ruudut', 'ダイヤ', '다이아몬드', '方块', 'ईंटें', 'রুইতন', 'Wajik', 'Daiman', 'ข้าวหลามตัด', 'Rô', 'Diyamante'],
  ['Eller', 'Collections', 'Stiche', 'Bazas', 'Plis', 'لطوش', 'دست‌ها', 'לקיחות', 'ہاتھ', 'Взятки', 'Взятки', 'Lewy', 'Štychy', 'Levate', 'Ütések', 'Μπάζες', 'Prese', 'Vazas', 'Slagen', 'Stick', 'Stik', 'Stikk', 'Tikit', 'トリック', '트릭', '墩数', 'हाथ', 'হাত', 'Trik', 'Trik', 'กอง', 'Nước bài', 'Mga trick'],
  ['Triks', 'Trix', 'Trix', 'Trix', 'Trix', 'تركس', 'تریکس', 'טריקס', 'ٹرکس', 'Трикс', 'Трікс', 'Trix', 'Trix', 'Trix', 'Trix', 'Τρικς', 'Trix', 'Trix', 'Trix', 'Trix', 'Trix', 'Trix', 'Trix', 'トリックス', '트릭스', '特里克斯', 'ट्रिक्स', 'ট্রিক্স', 'Trix', 'Trix', 'ทริกซ์', 'Trix', 'Trix'],
];

const kTrixAvoidGoal = [
  'Cezadan kaç: en az cezayı sen al', 'Dodge the penalty: take the least', 'Weiche der Strafe aus: nimm am wenigsten', 'Esquiva la penalización: lleva la menor',
  'Évitez la pénalité : prenez le moins', 'تجنّب العقوبة: خذ الأقل', 'از جریمه فرار کن: کمترین را بگیر', 'התחמקו מהעונש: קחו הכי מעט',
  'جرمانے سے بچیں: سب سے کم لیں', 'Избегайте штрафа: возьмите меньше всех', 'Уникайте штрафу: візьміть найменше', 'Unikaj kar: weź najmniej',
  'Vyhni se trestu: ber nejméně', 'Evită penalizarea: ia cel mai puțin', 'Kerüld a büntetést: vidd a legkevesebbet', 'Απόφυγε την ποινή: πάρε τη λιγότερη',
  'Evita la penalità: prendi il meno', 'Fuja da penalidade: leve o mínimo', 'Ontloop de straf: neem het minst', 'Undvik straffet: ta minst',
  'Undgå straffen: tag mindst', 'Unngå straffen: ta minst', 'Vältä rangaistus: ota vähiten', '罰点を避けて最少に抑えよう', '벌점을 피해 가장 적게 받으세요',
  '躲开罚分：拿得最少', 'जुर्माने से बचें: सबसे कम लें', 'জরিমানা এড়ান: সবচেয়ে কম নিন', 'Hindari penalti: ambil paling sedikit',
  'Elak penalti: ambil paling sedikit', 'หลบแต้มเสีย: เก็บให้น้อยที่สุด', 'Né phạt: nhận ít nhất', 'Iwasan ang multa: kumuha ng pinakakaunti',
];

final trixAvoidGoal = TrickGoal(
  (r, s) => r.utility(s, 0) >= 0,
  (r, s, lang) => Strings.pick(kTrixAvoidGoal, lang),
);

/// Trix'in el alma sözleşmeleri (bireysel, 52 kart, 13'er kart):
/// 0 Kupa Papazı (−75; kupayla çıkılmaz, rengin yoksa Papaz'ı atmak zorunlu),
/// 1 Kızlar (her kız −25), 2 Karolar (her karo −10; karo atılmadan karoyla
/// çıkılmaz), 3 Eller (her el −15). Ceza kartlarının hepsi alınınca el biter.
class TrixRules extends TrickRules {
  final int contract;
  const TrixRules(this.contract);

  static final _kh = makeCard(13, kHearts);

  @override
  bool get avoidTricks => true;

  @override
  void setupAfterDeal(TrickState s) {
    s.contract = contract;
    startPlay(s);
  }

  @override
  List<KCard> leadOptions(TrickState s, int seat) {
    final h = s.hands[seat];
    final banned = contract == 0 ? kHearts : (contract == 2 && s.extra == 0 ? kDiamonds : -1);
    if (banned >= 0) {
      final non = h.where((c) => suitOf(c) != banned).toList();
      if (non.isNotEmpty) return non;
    }
    return List.of(h);
  }

  @override
  List<KCard> legalPlays(TrickState s, int seat) {
    if (s.trick.isEmpty) return leadOptions(s, seat);
    final h = s.hands[seat];
    final lead = suitOf(s.trick.first);
    final follow = h.where((c) => suitOf(c) == lead).toList();
    if (follow.isNotEmpty) return follow;
    if (contract == 0 && h.contains(_kh)) return [_kh];
    return List.of(h);
  }

  @override
  void onPlay(TrickState s, int seat, KCard c) {
    if (contract == 2 && suitOf(c) == kDiamonds) s.extra = 1;
  }

  int penaltyCards(List<KCard> taken) => switch (contract) {
        0 => taken.contains(_kh) ? 1 : 0,
        1 => taken.where((c) => rankOf(c) == 12).length,
        2 => taken.where((c) => suitOf(c) == kDiamonds).length,
        _ => 0,
      };

  @override
  void afterTrick(TrickState s, int winner) {
    final all = switch (contract) { 0 => 1, 1 => 4, 2 => 13, _ => 99 };
    var n = 0;
    for (final t in s.taken) {
      n += penaltyCards(t);
    }
    if (n >= all) s.phase = TrickPhase.over;
  }

  @override
  int cardPoints(KCard c) => switch (contract) {
        0 => c == _kh ? 75 : 0,
        1 => rankOf(c) == 12 ? 25 : 0,
        2 => suitOf(c) == kDiamonds ? 10 : 0,
        _ => 0,
      };

  @override
  List<int> handScores(TrickState s) => [
        for (var p = 0; p < seats; p++)
          switch (contract) {
            0 => -75 * penaltyCards(s.taken[p]),
            1 => -25 * penaltyCards(s.taken[p]),
            2 => -10 * penaltyCards(s.taken[p]),
            _ => -15 * s.tricks[p],
          }
      ];

  @override
  String status(TrickState s, String lang) {
    final sc = handScores(s);
    return '${Strings.pick(kTrixContracts[contract], lang)}  ·  ${sc.join(' / ')}';
  }
}
