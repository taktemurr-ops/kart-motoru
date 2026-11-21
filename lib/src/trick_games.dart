import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'trick_engine.dart';
import 'trick_rules.dart';

final _2c = makeCard(2, kClubs);
final _qs = makeCard(12, kSpades);
final _kh = makeCard(13, kHearts);

/// Tahmini el sayısı: yapay zekânın ihalesi için kaba ölçü.
double estimateTricks(List<KCard> hand, int trump) {
  var t = 0.0;
  for (var s = 0; s < 4; s++) {
    final cards = hand.where((c) => suitOf(c) == s).map((c) => rankOf(c) == 1 ? 14 : rankOf(c)).toList();
    if (cards.contains(14)) t += 1;
    if (cards.contains(13) && cards.length >= 2) t += 0.7;
    if (cards.contains(12) && cards.length >= 3) t += 0.4;
    if (s == trump) t += (cards.length - 3).clamp(0, 13) * 0.8;
  }
  return t;
}

int longestSuit(List<KCard> hand) {
  var best = 0, bestScore = -1;
  for (var s = 0; s < 4; s++) {
    final cs = hand.where((c) => suitOf(c) == s).toList();
    final sc = cs.length * 10 + cs.fold<int>(0, (a, c) => a + (rankOf(c) == 1 ? 14 : rankOf(c)));
    if (sc > bestScore) {
      bestScore = sc;
      best = s;
    }
  }
  return best;
}

// ---------------------------------------------------------------- Hearts

/// Kupa Kaçırma (Hearts): kupalar 1, maça kızı 13 ceza. Az ceza alan kazanır.
class HeartsRules extends TrickRules {
  const HeartsRules();

  @override
  bool get avoidTricks => true;

  @override
  void startPlay(TrickState s) {
    super.startPlay(s);
    for (var p = 0; p < seats; p++) {
      if (s.hands[p].contains(_2c)) {
        s.leader = p;
        s.turn = p;
      }
    }
  }

  @override
  List<KCard> leadOptions(TrickState s, int seat) {
    final h = s.hands[seat];
    if (s.played.isEmpty && h.contains(_2c)) return [_2c];
    if (s.extra == 0) {
      final nonHearts = h.where((c) => suitOf(c) != kHearts).toList();
      if (nonHearts.isNotEmpty) return nonHearts;
    }
    return List.of(h);
  }

  @override
  List<KCard> legalPlays(TrickState s, int seat) {
    final l = super.legalPlays(s, seat);
    if (s.trick.isNotEmpty && s.played.length < seats) {
      // İlk elde ceza kartı atılmaz (başka seçenek varsa).
      final clean = l.where((c) => suitOf(c) != kHearts && c != _qs).toList();
      if (clean.isNotEmpty) return clean;
    }
    return l;
  }

  @override
  void onPlay(TrickState s, int seat, KCard c) {
    if (suitOf(c) == kHearts) s.extra = 1;
  }

  @override
  int cardPoints(KCard c) => c == _qs ? 13 : (suitOf(c) == kHearts ? 1 : 0);

  List<int> penalties(TrickState s) => [for (final t in s.taken) t.fold(0, (a, c) => a + cardPoints(c))];

  @override
  List<int> handScores(TrickState s) {
    final p = penalties(s);
    final moon = p.indexWhere((x) => x == 26);
    if (moon >= 0) return [for (var i = 0; i < seats; i++) i == moon ? 0 : -26];
    return [for (final x in p) -x];
  }

  @override
  String status(TrickState s, String lang) {
    final p = penalties(s);
    return '${Strings.tx(lang, 'Ceza', 'Penalty')}: ${p.join(' · ')}';
  }
}

// ---------------------------------------------------------------- Spades

/// Maça Koz (Spades): eşli; herkes el tahmini söyler, maça kozdur.
class SpadesRules extends TrickRules {
  const SpadesRules();

  @override
  bool get partnerships => true;
  @override
  bool get hasBidding => true;

  @override
  List<int> legalBids(TrickState s, int seat) => [for (var b = 0; b <= 13; b++) b];

  @override
  String bidLabel(int bid, String lang) => bid == 0 ? Strings.tx(lang, 'Sıfır', 'Nil') : '$bid';

  @override
  int aiBid(TrickState s, int seat, SeededRandom r) {
    final e = estimateTricks(s.hands[seat], kSpades);
    final b = e.round().clamp(1, 13);
    return b;
  }

  @override
  void finishBidding(TrickState s) {
    s.trump = kSpades;
    startPlay(s);
  }

  @override
  List<KCard> leadOptions(TrickState s, int seat) {
    final h = s.hands[seat];
    if (s.extra == 0) {
      final non = h.where((c) => suitOf(c) != kSpades).toList();
      if (non.isNotEmpty) return non;
    }
    return List.of(h);
  }

  @override
  void onPlay(TrickState s, int seat, KCard c) {
    if (suitOf(c) == kSpades) s.extra = 1;
  }

  int teamScore(TrickState s, int team) {
    var score = 0;
    var bid = 0, tricks = 0;
    for (final p in [team, team + 2]) {
      final b = s.bids[p] ?? 0;
      if (b == 0) {
        score += s.tricks[p] == 0 ? 100 : -100;
      } else {
        bid += b;
      }
      tricks += s.tricks[p];
    }
    if (bid > 0) score += tricks >= bid ? 10 * bid + (tricks - bid) : -10 * bid;
    return score;
  }

  @override
  List<int> handScores(TrickState s) {
    final a = teamScore(s, 0), b = teamScore(s, 1);
    return [a, b, a, b];
  }

  @override
  String status(TrickState s, String lang) {
    if (s.phase == TrickPhase.bidding) return '';
    final b0 = (s.bids[0] ?? 0) + (s.bids[2] ?? 0), b1 = (s.bids[1] ?? 0) + (s.bids[3] ?? 0);
    return '${Strings.tx(lang, 'Biz', 'Us')}: ${s.tricks[0] + s.tricks[2]}/$b0  ·  '
        '${Strings.tx(lang, 'Onlar', 'Them')}: ${s.tricks[1] + s.tricks[3]}/$b1';
  }
}

// ---------------------------------------------------------------- Batak

/// İhaleli Batak: en yüksek ihaleyi veren kozu seçer. Renge uymak ve
/// yükseltmek zorunludur; renk yoksa koz atılır. Koz açılmadan kozla çıkılmaz.
class BatakRules extends TrickRules {
  /// Eşli Batak: 0–2 ve 1–3 ortak.
  final bool pairs;

  /// Koz maça: ihale yok, maça hep kozdur; herkes el sayısı söyler.
  final bool spadesTrump;
  final int minBid;
  const BatakRules({this.pairs = false, this.spadesTrump = false, this.minBid = 5});

  @override
  bool get partnerships => pairs;
  @override
  bool get hasBidding => true;

  static const pass = 0;
  static const trumpBase = 100;

  int _high(TrickState s) => s.bids.whereType<int>().where((b) => b < trumpBase).fold(0, (a, b) => b > a ? b : a);

  @override
  List<int> legalBids(TrickState s, int seat) {
    if (s.extra == 2) return [for (var t = 0; t < 4; t++) trumpBase + t];
    if (spadesTrump) return [for (var b = 1; b <= 13; b++) b];
    final h = _high(s);
    return [pass, for (var b = (h < minBid ? minBid : h + 1); b <= 13; b++) b];
  }

  @override
  String bidLabel(int bid, String lang) {
    if (bid >= trumpBase) return ['♠', '♥', '♦', '♣'][bid - trumpBase];
    if (bid == pass && !spadesTrump) return Strings.tx(lang, 'Pas', 'Pass');
    return '$bid';
  }

  @override
  int aiBid(TrickState s, int seat, SeededRandom r) {
    final h = s.hands[seat];
    if (s.extra == 2) return trumpBase + longestSuit(h);
    if (spadesTrump) return estimateTricks(h, kSpades).round().clamp(1, 13);
    final e = estimateTricks(h, longestSuit(h)) + (pairs ? 1.5 : 0);
    final want = e.floor();
    final legal = legalBids(s, seat);
    if (want >= minBid && legal.contains(want)) return want;
    return pass;
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
    if (spadesTrump) return s.bidTurns >= seats;
    if (s.extra == 3) return true;
    if (s.bidTurns >= seats && s.extra != 2) {
      // Tur bitti: ihaleyi alan kozu seçer.
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
        s.bids[best] = minBid;
        bestBid = minBid;
      }
      s.declarer = best;
      s.contract = bestBid;
      s.extra = 2;
      s.turn = best;
    }
    return false;
  }

  @override
  void finishBidding(TrickState s) {
    if (spadesTrump) {
      s.trump = kSpades;
      startPlay(s);
      return;
    }
    s.extra = 0;
    startPlay(s);
    s.leader = s.declarer;
    s.turn = s.declarer;
  }

  @override
  List<KCard> leadOptions(TrickState s, int seat) {
    final h = s.hands[seat];
    if (s.extra == 0 && s.trump >= 0) {
      final non = h.where((c) => suitOf(c) != s.trump).toList();
      if (non.isNotEmpty) return non;
    }
    return List.of(h);
  }

  @override
  List<KCard> legalPlays(TrickState s, int seat) {
    final h = s.hands[seat];
    if (s.trick.isEmpty) return leadOptions(s, seat);
    final lead = suitOf(s.trick.first);
    var best = s.trick.first;
    for (final c in s.trick.skip(1)) {
      if (beats(s, c, best, lead)) best = c;
    }
    final follow = h.where((c) => suitOf(c) == lead).toList();
    if (follow.isNotEmpty) {
      final higher = follow.where((c) => beats(s, c, best, lead)).toList();
      return higher.isNotEmpty ? higher : follow;
    }
    final trumps = h.where((c) => suitOf(c) == s.trump).toList();
    if (trumps.isNotEmpty) {
      final higher = trumps.where((c) => beats(s, c, best, lead)).toList();
      return higher.isNotEmpty ? higher : trumps;
    }
    return List.of(h);
  }

  @override
  void onPlay(TrickState s, int seat, KCard c) {
    if (suitOf(c) == s.trump) s.extra = 1;
  }

  @override
  List<int> handScores(TrickState s) {
    final out = List<int>.filled(seats, 0);
    for (var p = 0; p < seats; p++) {
      final t = pairs ? s.tricks[p] + s.tricks[s.partnerOf(p)] : s.tricks[p];
      if (spadesTrump) {
        final b = s.bids[p] ?? 0;
        out[p] = s.tricks[p] >= b ? b * 10 + (s.tricks[p] - b) : -b * 10;
      } else if (p == s.declarer || (pairs && s.partnerOf(p) == s.declarer)) {
        out[p] = t >= s.contract ? t : -s.contract;
      } else {
        out[p] = t;
      }
    }
    if (spadesTrump && pairs) {
      for (var p = 0; p < 2; p++) {
        final sum = out[p] + out[p + 2];
        out[p] = sum;
        out[p + 2] = sum;
      }
    }
    return out;
  }

  @override
  String status(TrickState s, String lang) {
    if (s.declarer < 0) return '';
    return '${Strings.tx(lang, 'İhale', 'Contract')}: ${s.contract}';
  }
}

// ---------------------------------------------------------------- Whist

/// Briç benzeri Whist: eşli; koz, dağıtıcının son kartının rengidir.
/// Yedinci elden sonraki her el bir puan.
class WhistRules extends TrickRules {
  const WhistRules();

  @override
  bool get partnerships => true;

  @override
  TrickState deal(List<KCard> shuffled, int dealer) {
    final s = super.deal(shuffled, dealer);
    s.trump = suitOf(shuffled[seats * handSize - 1]);
    for (final h in s.hands) {
      sortHand(h, s.trump);
    }
    return s;
  }

  @override
  List<int> handScores(TrickState s) {
    final a = s.tricks[0] + s.tricks[2], b = s.tricks[1] + s.tricks[3];
    return [a, b, a, b];
  }

  @override
  String status(TrickState s, String lang) =>
      '${Strings.tx(lang, 'Biz', 'Us')}: ${s.tricks[0] + s.tricks[2]}  ·  ${Strings.tx(lang, 'Onlar', 'Them')}: ${s.tricks[1] + s.tricks[3]}';
}

// ---------------------------------------------------------------- Oh Hell

/// Tahmin (Oh Hell): herkes tam olarak kaç el alacağını söyler. Dağıtıcının
/// tahmini toplamı kart sayısına eşitleyemez. Tam tutturan kazanır.
class OhHellRules extends TrickRules {
  final int cards;
  const OhHellRules({this.cards = 7});

  @override
  int get handSize => cards;
  @override
  bool get hasBidding => true;

  @override
  TrickState deal(List<KCard> shuffled, int dealer) {
    final s = super.deal(shuffled, dealer);
    s.trump = s.kitty.isNotEmpty ? suitOf(s.kitty.first) : -1;
    return s;
  }

  @override
  List<int> legalBids(TrickState s, int seat) {
    final all = [for (var b = 0; b <= cards; b++) b];
    if (seat == s.dealer) {
      final sum = s.bids.whereType<int>().fold(0, (a, b) => a + b);
      all.remove(cards - sum);
    }
    return all;
  }

  @override
  int aiBid(TrickState s, int seat, SeededRandom r) {
    final e = estimateTricks(s.hands[seat], s.trump).round().clamp(0, cards);
    final l = legalBids(s, seat);
    if (l.contains(e)) return e;
    return l.reduce((a, b) => (a - e).abs() <= (b - e).abs() ? a : b);
  }

  @override
  void finishBidding(TrickState s) {
    final t = s.trump;
    startPlay(s);
    s.trump = t;
    for (final h in s.hands) {
      sortHand(h, t);
    }
  }

  @override
  List<int> handScores(TrickState s) => [
        for (var p = 0; p < seats; p++) s.tricks[p] == (s.bids[p] ?? -1) ? 10 + s.tricks[p] : -(s.tricks[p] - (s.bids[p] ?? 0)).abs(),
      ];

  @override
  double utility(TrickState s, int seat) => handScores(s)[seat].toDouble();

  @override
  String status(TrickState s, String lang) => s.phase == TrickPhase.bidding
      ? ''
      : '${Strings.tx(lang, 'Tahmin', 'Bid')}: ${s.bids[0] ?? '-'}  ·  ${Strings.tx(lang, 'Alınan', 'Taken')}: ${s.tricks[0]}';

  static final exact = TrickGoal(
    (r, s) => s.tricks[0] == s.bids[0],
    (r, s, lang) => Strings.tx(lang, 'Tahminini tam tuttur', 'Make your bid exactly'),
  );
}

// ---------------------------------------------------------------- 40'lık desteler

const _italianRanks = [1, 2, 3, 4, 5, 6, 7, 11, 12, 13];

/// Briscola: iki kişilik; renge uyma yok, her elden sonra desteden çekilir.
/// As 11, Üç 10, Papaz 4, Kız 3, Vale 2 puan. 60'tan fazlası kazanır.
class BriscolaRules extends TrickRules {
  const BriscolaRules();

  @override
  int get seats => 2;
  @override
  int get handSize => 3;

  @override
  List<KCard> deck() => buildDeck(ranks: _italianRanks);

  static const _order = {1: 10, 3: 9, 13: 8, 12: 7, 11: 6, 7: 5, 6: 4, 5: 3, 4: 2, 2: 1};

  @override
  int strength(KCard c) => _order[rankOf(c)]!;

  @override
  int cardPoints(KCard c) => const {1: 11, 3: 10, 13: 4, 12: 3, 11: 2}[rankOf(c)] ?? 0;

  @override
  TrickState deal(List<KCard> shuffled, int dealer) {
    final s = super.deal(shuffled, dealer);
    // Açılan koz kartı destenin en altında: en son çekilir.
    s.trump = suitOf(s.kitty.first);
    for (final h in s.hands) {
      sortHand(h, s.trump);
    }
    return s;
  }

  @override
  List<KCard> legalPlays(TrickState s, int seat) => List.of(s.hands[seat]);

  @override
  void afterTrick(TrickState s, int winner) {
    for (final p in [winner, (winner + 1) % seats]) {
      if (s.kitty.isNotEmpty) s.hands[p].add(s.kitty.removeLast());
    }
    for (final h in s.hands) {
      sortHand(h, s.trump);
    }
  }

  List<int> points(TrickState s) => [for (final t in s.taken) t.fold(0, (a, c) => a + cardPoints(c))];

  @override
  List<int> handScores(TrickState s) => points(s);

  @override
  String status(TrickState s, String lang) =>
      '${Strings.tx(lang, 'Puan', 'Points')}: ${points(s).join(' · ')}  ·  ${Strings.tx(lang, 'Deste', 'Stock')}: ${s.kitty.length}';
}

/// Sueca: dört kişi, eşli; 40 kart, onar kart. Koz, dağıtıcının son kartı.
/// As 11, Yedi 10, Papaz 4, Vale 3, Kız 2 puan. Takım 60'tan fazlasıyla kazanır.
class SuecaRules extends TrickRules {
  const SuecaRules();

  @override
  bool get partnerships => true;
  @override
  int get handSize => 10;

  @override
  List<KCard> deck() => buildDeck(ranks: _italianRanks);

  static const _order = {1: 10, 7: 9, 13: 8, 11: 7, 12: 6, 6: 5, 5: 4, 4: 3, 3: 2, 2: 1};

  @override
  int strength(KCard c) => _order[rankOf(c)]!;

  @override
  int cardPoints(KCard c) => const {1: 11, 7: 10, 13: 4, 11: 3, 12: 2}[rankOf(c)] ?? 0;

  @override
  TrickState deal(List<KCard> shuffled, int dealer) {
    final s = super.deal(shuffled, dealer);
    s.trump = suitOf(shuffled[seats * handSize - 1]);
    for (final h in s.hands) {
      sortHand(h, s.trump);
    }
    return s;
  }

  List<int> points(TrickState s) {
    final p = [for (final t in s.taken) t.fold(0, (a, c) => a + cardPoints(c))];
    return [p[0] + p[2], p[1] + p[3], p[0] + p[2], p[1] + p[3]];
  }

  @override
  List<int> handScores(TrickState s) => points(s);

  @override
  String status(TrickState s, String lang) {
    final p = points(s);
    return '${Strings.tx(lang, 'Biz', 'Us')}: ${p[0]}  ·  ${Strings.tx(lang, 'Onlar', 'Them')}: ${p[1]}';
  }
}

// ---------------------------------------------------------------- King

/// King: her el bir sözleşme. Ceza oyunlarında az ceza alan, koz oyununda
/// çok el alan kazanır. Sözleşme dağıtımla belirlenir.
class KingRules extends TrickRules {
  const KingRules();

  static const contracts = 7; // 0 el, 1 kupa, 2 erkek, 3 kız, 4 son iki, 5 rıfkı, 6 koz

  static const _tr = ['El Almaz', 'Kupa Almaz', 'Erkek Almaz', 'Kız Almaz', 'Son İki', 'Rıfkı', 'Koz'];
  static const _en = ['No Tricks', 'No Hearts', 'No Kings & Jacks', 'No Queens', 'Last Two', 'King of Hearts', 'Trumps'];

  String contractName(int c, String lang) => Strings.tx(lang, _tr[c], _en[c]);

  @override
  TrickState deal(List<KCard> shuffled, int dealer) {
    final s = super.deal(shuffled, dealer);
    s.contract = (shuffled[51] + shuffled[50]) % contracts;
    if (s.contract == 6) s.trump = suitOf(shuffled[49]);
    for (final h in s.hands) {
      sortHand(h, s.trump);
    }
    return s;
  }

  @override
  void startPlay(TrickState s) {
    final t = s.trump;
    super.startPlay(s);
    s.trump = t;
  }

  @override
  bool avoidIn(TrickState s) => s.contract != 6;

  bool _penalty(TrickState s, KCard c) => switch (s.contract) {
        1 => suitOf(c) == kHearts,
        2 => rankOf(c) == 13 || rankOf(c) == 11,
        3 => rankOf(c) == 12,
        5 => c == _kh,
        _ => false,
      };

  @override
  List<KCard> leadOptions(TrickState s, int seat) {
    final h = s.hands[seat];
    if ((s.contract == 1 || s.contract == 5) && s.extra == 0) {
      final non = h.where((c) => suitOf(c) != kHearts).toList();
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
    // Renk yoksa: ceza kartı varsa atmak zorunlu; koz oyununda koz atmak zorunlu.
    if (s.contract == 6 && s.trump >= 0) {
      final tr = h.where((c) => suitOf(c) == s.trump).toList();
      if (tr.isNotEmpty) return tr;
    }
    final pen = h.where((c) => _penalty(s, c)).toList();
    if (pen.isNotEmpty) return pen;
    return List.of(h);
  }

  @override
  void onPlay(TrickState s, int seat, KCard c) {
    if (suitOf(c) == kHearts) s.extra = 1;
  }

  @override
  List<int> handScores(TrickState s) {
    final out = List<int>.filled(seats, 0);
    for (var p = 0; p < seats; p++) {
      final t = s.taken[p];
      out[p] = switch (s.contract) {
        0 => -50 * s.tricks[p],
        1 => -30 * t.where((c) => suitOf(c) == kHearts).length,
        2 => -60 * t.where((c) => rankOf(c) == 13 || rankOf(c) == 11).length,
        3 => -100 * t.where((c) => rankOf(c) == 12).length,
        5 => t.contains(_kh) ? -320 : 0,
        6 => 50 * s.tricks[p],
        _ => 0,
      };
    }
    if (s.contract == 4) {
      // Son iki elin her biri -180.
      for (var i = 11; i < s.winners.length && i < 13; i++) {
        out[s.winners[i]] -= 180;
      }
    }
    return out;
  }

  @override
  String status(TrickState s, String lang) => contractName(s.contract, lang);
}
