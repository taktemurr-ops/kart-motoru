import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'kart_texts.dart';
import 'trick_engine.dart';
import 'trick_games.dart' show estimateTricks;

const _suitSym = ['♠', '♥', '♦', '♣'];

/// Aynı renkteki (kırmızı/siyah) diğer desen.
int sameColorSuit(int s) => const [3, 2, 1, 0][s];

/// Koz seçmeli dörtlü ortaklı oyunların ortak ihalesi: sırayla "pas" ya da
/// bir koz rengi söylenir; ilk söyleyen kozu alır. Herkes pas derse dağıtan
/// zorla seçer. (bid 0: pas, 100+renk: koz)
mixin _NameTrump on TrickRules {
  static const trumpBase = 100;

  /// İlk turda yalnızca açık kartın rengi söylenebilir (Euchre); null: hepsi.
  int? firstRoundSuit(TrickState s) => null;

  @override
  bool get hasBidding => true;

  @override
  List<int> legalBids(TrickState s, int seat) {
    final up = firstRoundSuit(s);
    final round2 = s.bidTurns >= seats;
    final suits = up == null || round2 ? [for (var t = 0; t < 4; t++) if (!(round2 && t == up)) t] : [up];
    final forced = seat == s.dealer && (up == null ? s.bidTurns >= seats - 1 : s.bidTurns >= 2 * seats - 1);
    return [if (!forced) 0, for (final t in suits) trumpBase + t];
  }

  @override
  String bidLabel(int bid, String lang) => bid >= trumpBase ? _suitSym[bid - trumpBase] : Strings.tx(lang, 'Pas', 'Pass');

  @override
  void applyBid(TrickState s, int seat, int bid) {
    super.applyBid(s, seat, bid);
    if (bid >= trumpBase) {
      s.trump = bid - trumpBase;
      s.declarer = seat;
    }
  }

  @override
  bool biddingOver(TrickState s) => s.trump >= 0;

  /// Bir renk koz olursa beklenen güç.
  double trumpStrength(List<KCard> hand, int trump);
  double get bidThreshold;

  @override
  int aiBid(TrickState s, int seat, SeededRandom r) {
    final legal = legalBids(s, seat);
    var best = -1, bestV = -1.0;
    for (final b in legal) {
      if (b < trumpBase) continue;
      final v = trumpStrength(s.hands[seat], b - trumpBase);
      if (v > bestV) {
        bestV = v;
        best = b;
      }
    }
    if (!legal.contains(0)) return best;
    return bestV >= bidThreshold + (r.nextInt(3) - 1) * 0.2 ? best : 0;
  }

  @override
  void finishBidding(TrickState s) {
    startPlay(s);
    s.leader = (s.dealer + 1) % seats;
    s.turn = s.leader;
  }

  String makersText(TrickState s, String lang) {
    if (s.declarer < 0) return '';
    final us = s.declarer % 2 == 0;
    return '${kt(lang, 'makers')}: ${us ? Strings.tx(lang, 'Biz', 'Us') : Strings.tx(lang, 'Onlar', 'Them')}';
  }
}

// ---------------------------------------------------------------- Euchre

/// Euchre: 24 kart (9–As), dörtlü ortaklı, beşer kart. Kozun valesi (sağ
/// bower) en büyük, aynı renkteki diğer vale (sol bower) ikinci koz.
/// Kozu söyleyen taraf 3 el alırsa 1, beşini alırsa 2 puan; alamazsa
/// karşı taraf 2 puan yazar.
class EuchreRules extends TrickRules with _NameTrump {
  const EuchreRules();

  @override
  MatchFormat get matchFormat => const MatchFormat(target: 10);

  @override
  bool get partnerships => true;
  @override
  int get handSize => 5;
  @override
  List<KCard> deck() => buildDeck(ranks: const [1, 9, 10, 11, 12, 13]);

  @override
  int? firstRoundSuit(TrickState s) => suitOf(s.kitty.first);

  @override
  int strength(KCard c) => rankOf(c) == 1 ? 14 : rankOf(c);

  bool _right(TrickState s, KCard c) => s.trump >= 0 && rankOf(c) == 11 && suitOf(c) == s.trump;
  bool _left(TrickState s, KCard c) => s.trump >= 0 && rankOf(c) == 11 && suitOf(c) == sameColorSuit(s.trump);

  @override
  int effSuit(TrickState s, KCard c) => _left(s, c) ? s.trump : suitOf(c);

  int power(TrickState s, KCard c) => _right(s, c) ? 30 : (_left(s, c) ? 29 : strength(c));

  @override
  bool beats(TrickState s, KCard a, KCard b, int lead) {
    final ta = isTrump(s, a), tb = isTrump(s, b);
    if (ta != tb) return ta;
    if (effSuit(s, a) != effSuit(s, b)) return false;
    return power(s, a) > power(s, b);
  }

  @override
  double trumpStrength(List<KCard> hand, int trump) {
    var v = 0.0;
    for (final c in hand) {
      final isR = rankOf(c) == 11 && suitOf(c) == trump, isL = rankOf(c) == 11 && suitOf(c) == sameColorSuit(trump);
      if (isR) {
        v += 1.0;
      } else if (isL) {
        v += 0.85;
      } else if (suitOf(c) == trump) {
        v += rankOf(c) == 1 ? 0.75 : 0.45;
      } else if (rankOf(c) == 1) {
        v += 0.6;
      }
    }
    return v;
  }

  @override
  double get bidThreshold => 2.6;

  int makersTricks(TrickState s) => s.tricks[s.declarer] + s.tricks[s.partnerOf(s.declarer)];

  @override
  List<int> handScores(TrickState s) {
    final out = List<int>.filled(seats, 0);
    if (s.declarer < 0) return out;
    final t = makersTricks(s);
    final mk = s.declarer % 2;
    final mkPts = t == 5 ? 2 : (t >= 3 ? 1 : 0);
    final dfPts = t >= 3 ? 0 : 2;
    for (var p = 0; p < seats; p++) {
      out[p] = p % 2 == mk ? mkPts : dfPts;
    }
    return out;
  }

  @override
  String status(TrickState s, String lang) {
    final m = makersText(s, lang);
    if (m.isEmpty) return '${kt(lang, 'upCard')}: ${_suitSym[suitOf(s.kitty.first)]}';
    return m;
  }
}

// ---------------------------------------------------------------- Belote ailesi

/// Belote / Klaverjas / Jass: 32 (Jass: 36) kart, dörtlü ortaklı. Kozda Vale
/// ve Dokuz en büyük. Renge uymak, kozda yükseltmek ve renk yoksa koz atmak
/// zorunlu (Belote ve Jass'ta eşin elde ise serbest). Kozu söyleyen taraf
/// toplam puanın yarısından fazlasını almalı; alamazsa bütün puan karşıya.
class BeloteRules extends TrickRules with _NameTrump {
  /// Klaverjas (Rotterdam): eş el alıyor olsa bile koz atmak zorunlu.
  final bool alwaysTrump;

  /// Jass: 36 kart (6'lar dahil), son el 5 puan.
  final bool jass;
  const BeloteRules({this.alwaysTrump = false, this.jass = false});

  /// Belote ve Jass 1000 puana; Klaverjas 16 el.
  @override
  MatchFormat get matchFormat => alwaysTrump ? const MatchFormat(deals: 16) : const MatchFormat(target: 1000);

  @override
  bool get partnerships => true;
  @override
  int get handSize => jass ? 9 : 8;
  @override
  List<KCard> deck() => buildDeck(ranks: jass ? const [1, 6, 7, 8, 9, 10, 11, 12, 13] : const [1, 7, 8, 9, 10, 11, 12, 13]);

  static const _trumpPow = {11: 9, 9: 8, 1: 7, 10: 6, 13: 5, 12: 4, 8: 3, 7: 2, 6: 1};
  static const _plainPow = {1: 9, 10: 8, 13: 7, 12: 6, 11: 5, 9: 4, 8: 3, 7: 2, 6: 1};
  static const _trumpPts = {11: 20, 9: 14, 1: 11, 10: 10, 13: 4, 12: 3};
  static const _plainPts = {1: 11, 10: 10, 13: 4, 12: 3, 11: 2};

  @override
  int strength(KCard c) => _plainPow[rankOf(c)]!;

  int power(TrickState s, KCard c) => isTrump(s, c) ? 20 + _trumpPow[rankOf(c)]! : _plainPow[rankOf(c)]!;

  int points(TrickState s, KCard c) => (isTrump(s, c) ? _trumpPts : _plainPts)[rankOf(c)] ?? 0;

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
    var bestIx = 0;
    for (var i = 1; i < s.trick.length; i++) {
      if (beats(s, s.trick[i], s.trick[bestIx], lead)) bestIx = i;
    }
    final best = s.trick[bestIx];
    final winner = (s.leader + bestIx) % seats;
    final follow = h.where((c) => suitOf(c) == lead).toList();
    final trumps = h.where((c) => isTrump(s, c)).toList();
    List<KCard> over(List<KCard> l) {
      final o = l.where((c) => beats(s, c, best, lead)).toList();
      return o.isNotEmpty ? o : l;
    }

    if (follow.isNotEmpty) return lead == s.trump ? over(follow) : follow;
    if (!alwaysTrump && winner == s.partnerOf(seat)) return List.of(h);
    if (trumps.isNotEmpty) return over(trumps);
    return List.of(h);
  }

  @override
  double trumpStrength(List<KCard> hand, int trump) {
    var v = 0.0;
    for (final c in hand) {
      if (suitOf(c) == trump) {
        v += const {11: 1.6, 9: 1.2, 1: 0.9, 10: 0.7}[rankOf(c)] ?? 0.45;
      } else if (rankOf(c) == 1) {
        v += 0.8;
      } else if (rankOf(c) == 10) {
        v += 0.3;
      }
    }
    return v;
  }

  @override
  double get bidThreshold => jass ? 4.6 : 4.2;

  /// Kozun Papaz + Kızı aynı elde: 20 puan (bir kez).
  @override
  void startPlay(TrickState s) {
    super.startPlay(s);
    s.extra = 0;
    for (var p = 0; p < seats; p++) {
      final h = s.hands[p];
      if (s.trump >= 0 && h.contains(makeCard(13, s.trump)) && h.contains(makeCard(12, s.trump))) s.extra = 1 + p % 2;
    }
  }

  int get lastTrickBonus => jass ? 5 : 10;

  List<int> teamPoints(TrickState s) {
    final t = [0, 0];
    for (var p = 0; p < seats; p++) {
      for (final c in s.taken[p]) {
        t[p % 2] += points(s, c);
      }
    }
    if (s.lastWinner >= 0 && s.phase == TrickPhase.over) t[s.lastWinner % 2] += lastTrickBonus;
    if (s.extra > 0) t[s.extra - 1] += 20;
    return t;
  }

  @override
  List<int> handScores(TrickState s) {
    final t = teamPoints(s);
    if (s.declarer >= 0 && s.phase == TrickPhase.over) {
      final mk = s.declarer % 2;
      if (t[mk] <= t[1 - mk]) {
        t[1 - mk] += t[mk];
        t[mk] = 0;
      }
    }
    return [for (var p = 0; p < seats; p++) t[p % 2]];
  }

  @override
  String status(TrickState s, String lang) {
    final t = teamPoints(s);
    final m = makersText(s, lang);
    return '${m.isEmpty ? '' : '$m  ·  '}${Strings.tx(lang, 'Biz', 'Us')}: ${t[0]}  ·  ${Strings.tx(lang, 'Onlar', 'Them')}: ${t[1]}';
  }
}

// ---------------------------------------------------------------- Pinochle

/// Pinochle: 48 kart (9–As, iki deste), dörtlü ortaklı. İhale puanla yapılır,
/// ihaleyi alan kozu seçer. Deklarasyonlar (evlilik, pinochle, dört as…)
/// sayılır, sonra eller oynanır: As, On ve Papaz 1'er puan, son el 1 puan.
/// Renge uymak, eli geçmeye çalışmak, renk yoksa koz atmak zorunlu.
class PinochleRules extends TrickRules {
  const PinochleRules();

  @override
  MatchFormat get matchFormat => const MatchFormat(target: 150);

  @override
  bool get partnerships => true;
  @override
  int get handSize => 12;
  @override
  bool get hasBidding => true;
  @override
  List<KCard> deck() => buildDeck(decks: 2, ranks: const [1, 9, 10, 11, 12, 13]);

  static const _pow = {1: 6, 10: 5, 13: 4, 12: 3, 11: 2, 9: 1};
  static const minBid = 15, maxBid = 50, trumpBase = 100;

  @override
  int strength(KCard c) => _pow[rankOf(c)]!;

  @override
  int cardPoints(KCard c) => const {1: 1, 10: 1, 13: 1}[rankOf(c)] ?? 0;

  int _high(TrickState s) => s.bids.whereType<int>().where((b) => b < trumpBase).fold<int>(0, (a, b) => b > a ? b : a);

  @override
  List<int> legalBids(TrickState s, int seat) {
    if (s.extra == 2) return [for (var t = 0; t < 4; t++) trumpBase + t];
    final h = _high(s);
    return [0, for (var b = h < minBid ? minBid : h + 1; b <= maxBid; b++) b];
  }

  @override
  String bidLabel(int bid, String lang) {
    if (bid >= trumpBase) return _suitSym[bid - trumpBase];
    return bid == 0 ? Strings.tx(lang, 'Pas', 'Pass') : '$bid';
  }

  @override
  void applyBid(TrickState s, int seat, int bid) {
    if (bid >= trumpBase) {
      s.trump = bid - trumpBase;
      s.extra = 3;
      return;
    }
    super.applyBid(s, seat, bid);
  }

  @override
  bool biddingOver(TrickState s) {
    if (s.extra == 3) return true;
    if (s.bidTurns >= seats && s.extra != 2) {
      var best = -1, bestBid = 0;
      for (var p = 0; p < seats; p++) {
        final b = s.bids[p] ?? 0;
        if (b > bestBid) {
          bestBid = b;
          best = p;
        }
      }
      if (best < 0) {
        best = s.dealer;
        bestBid = minBid;
        s.bids[best] = minBid;
      }
      s.declarer = best;
      s.contract = bestBid;
      s.extra = 2;
      s.turn = best;
    }
    return false;
  }

  /// Bir elin bir koz rengindeki deklarasyon puanı.
  static int meld(List<KCard> hand, int trump) {
    int count(int rank, int suit) => hand.where((c) => rankOf(c) == rank && suitOf(c) == suit).length;
    var m = 0;
    // Koz serisi (As, On, Papaz, Kız, Vale)
    final run = [1, 10, 13, 12, 11].map((r) => count(r, trump)).reduce((a, b) => a < b ? a : b);
    m += run * 15;
    for (var su = 0; su < 4; su++) {
      var marr = [count(13, su), count(12, su)].reduce((a, b) => a < b ? a : b);
      if (su == trump) marr -= run;
      m += marr * (su == trump ? 4 : 2);
    }
    final pin = [count(12, kSpades), count(11, kDiamonds)].reduce((a, b) => a < b ? a : b);
    m += pin == 2 ? 30 : pin * 4;
    for (final (rank, pts) in [(1, 10), (13, 8), (12, 6), (11, 4)]) {
      final around = [for (var su = 0; su < 4; su++) count(rank, su)].reduce((a, b) => a < b ? a : b);
      m += around == 2 ? pts * 10 : around * pts;
    }
    m += count(9, trump);
    return m;
  }

  @override
  int aiBid(TrickState s, int seat, SeededRandom r) {
    final h = s.hands[seat];
    if (s.extra == 2) {
      var best = 0, bv = -1.0;
      for (var t = 0; t < 4; t++) {
        final v = meld(h, t) + estimateTricks(h, t) * 2;
        if (v > bv) {
          bv = v;
          best = t;
        }
      }
      return trumpBase + best;
    }
    var est = 0.0;
    for (var t = 0; t < 4; t++) {
      final v = meld(h, t) + h.where((c) => suitOf(c) == t).length * 1.2 + 9;
      if (v > est) est = v;
    }
    final want = est.floor() + r.nextInt(3) - 1;
    final legal = legalBids(s, seat);
    final options = legal.where((b) => b > 0 && b <= want).toList();
    return options.isEmpty ? 0 : options.first;
  }

  @override
  void finishBidding(TrickState s) {
    startPlay(s);
    s.leader = s.declarer;
    s.turn = s.declarer;
    s.extra = 0;
  }

  @override
  List<KCard> legalPlays(TrickState s, int seat) {
    final h = s.hands[seat];
    if (s.trick.isEmpty) return List.of(h);
    final lead = suitOf(s.trick.first);
    var best = s.trick.first;
    for (final c in s.trick.skip(1)) {
      if (beats(s, c, best, lead)) best = c;
    }
    List<KCard> over(List<KCard> l) {
      final o = l.where((c) => beats(s, c, best, lead)).toList();
      return o.isNotEmpty ? o : l;
    }

    final follow = h.where((c) => suitOf(c) == lead).toList();
    if (follow.isNotEmpty) return over(follow);
    final trumps = h.where((c) => suitOf(c) == s.trump).toList();
    if (trumps.isNotEmpty) return over(trumps);
    return List.of(h);
  }

  /// Takımların deklarasyonu, elde kalan + oynanan kartlardan hesaplanır:
  /// her koltuğun başlangıç eli = elindekiler + oynadıkları.
  List<int> teamMeld(TrickState s) {
    if (s.trump < 0) return [0, 0];
    final start = [for (var p = 0; p < seats; p++) <KCard>[...s.hands[p]]];
    // Oynanan kartların sahibi: el sırasından çıkarılır.
    var leader = (s.dealer + 1) % seats;
    leader = s.declarer >= 0 ? s.declarer : leader;
    var i = 0;
    for (var t = 0; t * seats < s.played.length; t++) {
      for (var k = 0; k < seats && i < s.played.length; k++, i++) {
        start[(leader + k) % seats].add(s.played[i]);
      }
      if (t < s.winners.length) leader = s.winners[t];
    }
    final m = [0, 0];
    for (var p = 0; p < seats; p++) {
      m[p % 2] += meld(start[p], s.trump);
    }
    return m;
  }

  List<int> counters(TrickState s) {
    final t = [0, 0];
    for (var p = 0; p < seats; p++) {
      t[p % 2] += s.taken[p].fold<int>(0, (a, c) => a + cardPoints(c));
    }
    if (s.phase == TrickPhase.over && s.lastWinner >= 0) t[s.lastWinner % 2] += 1;
    return t;
  }

  @override
  List<int> handScores(TrickState s) {
    final m = teamMeld(s), c = counters(s);
    final tot = [m[0] + c[0], m[1] + c[1]];
    if (s.declarer >= 0) {
      final mk = s.declarer % 2;
      if (c[mk] == 0 || tot[mk] < s.contract) tot[mk] = -s.contract;
      if (c[1 - mk] == 0) tot[1 - mk] = 0;
    }
    return [for (var p = 0; p < seats; p++) tot[p % 2]];
  }

  @override
  String status(TrickState s, String lang) {
    if (s.declarer < 0) return '';
    final m = teamMeld(s), c = counters(s);
    return '${Strings.tx(lang, 'İhale', 'Contract')}: ${s.contract}  ·  ${kt(lang, 'meld')}: ${m[0]}/${m[1]}  ·  '
        '${Strings.tx(lang, 'Biz', 'Us')}: ${m[0] + c[0]}  ·  ${Strings.tx(lang, 'Onlar', 'Them')}: ${m[1] + c[1]}';
  }
}
