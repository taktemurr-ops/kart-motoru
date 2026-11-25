import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'kart_texts.dart';
import 'trick_engine.dart';

const _suitSym = ['♠', '♥', '♦', '♣'];

/// Yalnızca valelerin (ve bazen kızların) koz olduğu oyunlarda "sanal koz rengi".
const kVirtualTrump = 4;

// ---------------------------------------------------------------- Skat

/// Skat: üç kişi, 32 kart, onar kart + 2 kartlık skat. İhaleyi alan skatı alır,
/// iki kart gömer ve diğer ikisine karşı oynar. Renk oyununda valeler ve seçilen
/// renk koz; Grand'da yalnızca valeler; Null'da koz yok ve hiç el alınmamalı.
/// As 11, On 10, Papaz 4, Kız 3, Vale 2: renk ve Grand'da 61 puan gerekir.
/// Herkes pas derse Ramsch: herkes kendine, en az puan alan kazanır.
class SkatRules extends TrickRules {
  const SkatRules();

  /// Liste: 12 el (herkes dört kez dağıtır).
  @override
  MatchFormat get matchFormat => const MatchFormat(deals: 12);

  // Oyun türü (contract): 1 ♦, 2 ♥, 3 ♠, 4 Null, 5 ♣, 6 Grand, 7 Ramsch.
  // İhale kodu: tür + 10 × ek (1 Hand: skat alınmaz, 2 Ouvert: açık; Null'da).
  // Ek, oyun sırasında [TrickState.extra]'da; matadorlar [TrickState.aux]'ta.
  static const _contractSuit = {1: kDiamonds, 2: kHearts, 3: kSpades, 5: kClubs};
  static const nullGame = 4, grand = 6, ramsch = 7;
  static const hand = 1, ouvert = 2;

  /// Temel değerler: ♦ 9, ♥ 10, ♠ 11, ♣ 12, Grand 24.
  static const base = {1: 9, 2: 10, 3: 11, 5: 12, grand: 24};

  /// Null değerleri: Null 23, Null Hand 35, Null Ouvert 46, Null Ouvert Hand 59.
  static const nullValue = {0: 23, hand: 35, ouvert: 46, hand | ouvert: 59};

  static const bidCodes = [1, 2, 3, nullGame, 5, 11, 12, 13, 14, 15, 24, grand, 34, 16];

  /// İhalenin en küçük oyun değeri (ihale sırası buna göre: 18, 20, 22, 23 …).
  static int bidValue(int code) {
    if (code <= 0) return 0;
    final g = code % 10, f = code ~/ 10;
    if (g == nullGame) return nullValue[f] ?? 23;
    return base[g]! * (2 + (f & hand));
  }

  bool _null(TrickState s) => s.contract == nullGame;
  static const _jackPow = {kClubs: 4, kSpades: 3, kHearts: 2, kDiamonds: 1};
  static const _plainPow = {1: 8, 10: 7, 13: 6, 12: 5, 9: 4, 8: 3, 7: 2};
  static const _nullPow = {1: 8, 13: 7, 12: 6, 11: 5, 10: 4, 9: 3, 8: 2, 7: 1};

  /// Koz sırası (en büyükten): dört vale, sonra renk oyununda kozun A 10 K D 9 8 7'si.
  static List<KCard> trumpOrder(int game) => [
        for (final su in const [kClubs, kSpades, kHearts, kDiamonds]) makeCard(11, su),
        if (_contractSuit.containsKey(game))
          for (final r in const [1, 10, 13, 12, 9, 8, 7]) makeCard(r, _contractSuit[game]!),
      ];

  /// Matadorlar: en büyük kozdan başlayan kesintisiz dizide "ile" ya da "olmadan".
  static int matadors(List<KCard> cards, int game) {
    final order = trumpOrder(game);
    final has = [for (final c in order) cards.any((x) => rankOf(x) == rankOf(c) && suitOf(x) == suitOf(c))];
    var n = 1;
    while (n < has.length && has[n] == has[0]) {
      n++;
    }
    return n;
  }

  /// Oyunun değeri ve kazanılıp kazanılmadığı. Renk/Grand: temel × (matador
  /// + oyun 1 + Hand + Schneider + Schwarz). Null: sabit değer.
  (int, bool) gameValue(TrickState s) {
    final d = s.declarer;
    final f = s.extra;
    if (_null(s)) return (nullValue[f & 3] ?? 23, s.tricks[d] == 0);
    final p = points(s)[d];
    final schneider = p >= 90 || p <= 30;
    final schwarz = s.tricks[d] == 10 || s.tricks[d] == 0;
    final mult = s.aux.clamp(1, 11) + 1 + (f & hand) + (schneider ? 1 : 0) + (schwarz ? 1 : 0);
    return (base[s.contract]! * mult, p >= 61);
  }

  /// Seeger-Fabian listesi: kazanan ilan eden oyun değeri + 50; kaybeden
  /// iki kat değer + 50 verir, rakiplerin her biri 40 alır. Ramsch'ta herkes
  /// aldığı göz puanı kadar eksi yazar.
  @override
  List<int> matchPoints(TrickState s) {
    if (s.contract == ramsch) return handScores(s);
    final d = s.declarer;
    if (d < 0) return List.filled(seats, 0);
    final (v, won) = gameValue(s);
    return [for (var i = 0; i < seats; i++) i == d ? (won ? v + 50 : -2 * v - 50) : (won ? 0 : 40)];
  }

  @override
  int get seats => 3;
  @override
  int get handSize => 10;
  @override
  bool get hasBidding => true;
  @override
  List<KCard> deck() => buildDeck(ranks: const [1, 7, 8, 9, 10, 11, 12, 13]);

  @override
  int strength(KCard c) => rankOf(c) == 11 ? 10 + _jackPow[suitOf(c)]! : _plainPow[rankOf(c)]!;

  @override
  int cardPoints(KCard c) => const {1: 11, 10: 10, 13: 4, 12: 3, 11: 2}[rankOf(c)] ?? 0;

  @override
  int effSuit(TrickState s, KCard c) => rankOf(c) == 11 && !_null(s) && s.trump >= 0 ? s.trump : suitOf(c);

  int power(TrickState s, KCard c) {
    if (_null(s)) return _nullPow[rankOf(c)]!;
    if (rankOf(c) == 11) return 30 + _jackPow[suitOf(c)]!;
    return (isTrump(s, c) ? 20 : 0) + _plainPow[rankOf(c)]!;
  }

  @override
  bool beats(TrickState s, KCard a, KCard b, int lead) {
    final ta = isTrump(s, a), tb = isTrump(s, b);
    if (ta != tb) return ta;
    if (effSuit(s, a) != effSuit(s, b)) return false;
    return power(s, a) > power(s, b);
  }

  int _high(TrickState s) => s.bids.whereType<int>().fold<int>(0, (a, b) => bidValue(b) > bidValue(a) ? b : a);

  @override
  List<int> legalBids(TrickState s, int seat) {
    final h = bidValue(_high(s));
    return [0, for (final c in bidCodes) if (bidValue(c) > h) c];
  }

  @override
  String bidLabel(int bid, String lang) {
    if (bid == 0) return Strings.tx(lang, 'Pas', 'Pass');
    if (bid == ramsch) return kt(lang, 'least');
    final g = bid % 10, f = bid ~/ 10;
    final name = switch (g) {
      nullGame => kt(lang, 'null'),
      grand => kt(lang, 'grand'),
      _ => _suitSym[_contractSuit[g]!],
    };
    return '$name${f & hand != 0 ? ' ${kt(lang, 'skatHand')}' : ''}${f & ouvert != 0 ? ' ${kt(lang, 'ouvert')}' : ''} · ${bidValue(bid)}';
  }

  @override
  bool biddingOver(TrickState s) => s.bidTurns >= seats;

  @override
  int aiBid(TrickState s, int seat, SeededRandom r) {
    final h = s.hands[seat];
    final jacks = h.where((c) => rankOf(c) == 11).length;
    final aces = h.where((c) => rankOf(c) == 1).length;
    var best = 0;
    var bestV = 0.0;
    for (final g in [1, 2, 3, 5]) {
      final t = _contractSuit[g]!;
      final v = jacks * 1.1 + h.where((c) => suitOf(c) == t && rankOf(c) != 11).length * 0.75 + aces * 0.55;
      if (v > bestV) {
        bestV = v;
        best = g;
      }
    }
    final low = h.where((c) => rankOf(c) <= 9 && rankOf(c) != 1).length;
    var choice = 0;
    if (jacks >= 3 && aces >= 2) {
      choice = jacks == 4 && aces >= 3 ? grand + 10 : grand;
    } else if (bestV >= 5.0 + (r.nextInt(3) - 1) * 0.3) {
      // Çok güçlü elde skatı almadan (Hand) oyna.
      choice = bestV >= 6.6 ? best + 10 : best;
    } else if (low >= 7 && aces == 0) {
      // Bütün renklerde küçük kartlarla Null; hepsi küçükse açık (Ouvert).
      choice = low >= 9 ? nullGame + 20 : nullGame;
    }
    return bidValue(choice) > bidValue(_high(s)) ? choice : 0;
  }

  @override
  void finishBidding(TrickState s) {
    var best = -1, bestBid = 0;
    for (var p = 0; p < seats; p++) {
      final b = s.bids[p] ?? 0;
      if (bidValue(b) > bidValue(bestBid)) {
        bestBid = b;
        best = p;
      }
    }
    if (best < 0) {
      s.contract = ramsch;
      s.trump = kVirtualTrump;
      s.declarer = -1;
    } else {
      final g = bestBid % 10;
      s.declarer = best;
      s.contract = g;
      s.extra = bestBid ~/ 10;
      s.trump = g == nullGame ? -1 : (g == grand ? kVirtualTrump : _contractSuit[g]!);
      final h = s.hands[best];
      // Matadorlar elle skatın birlikte (12 kart) sayılır.
      s.aux = g == nullGame ? 0 : matadors([...h, ...s.kitty], g);
      if (s.extra & hand != 0) {
        // Hand: skat kapalı kalır, sonunda ilan edenin sayılır.
        s.taken[best].addAll(s.kitty);
        s.kitty.clear();
      } else {
        // Skatı al, en zayıf iki kartı göm (gömülenler ihaleciye sayılır).
        h.addAll(s.kitty);
        s.kitty.clear();
        final order = List.of(h)
          ..sort((a, b) {
            int key(KCard c) => _null(s) ? -power(s, c) : (isTrump(s, c) ? 100 : 0) + power(s, c) * 2 - cardPoints(c);
            return key(a).compareTo(key(b));
          });
        for (final c in order.take(2)) {
          h.remove(c);
          s.taken[best].add(c);
        }
      }
    }
    startPlay(s);
    s.leader = (s.dealer + 1) % seats;
    s.turn = s.leader;
  }

  /// Null Ouvert'te ilan edenin eli herkese açıktır.
  @override
  bool openHand(TrickState s, int seat) =>
      s.phase != TrickPhase.bidding && _null(s) && s.extra & ouvert != 0 && seat == s.declarer;

  @override
  bool teammates(TrickState s, int a, int b) => a == b || (s.declarer >= 0 && a != s.declarer && b != s.declarer);

  @override
  bool avoidIn(TrickState s) => s.contract == ramsch || (_null(s) && s.turn == s.declarer);

  List<int> points(TrickState s) => [for (final t in s.taken) t.fold<int>(0, (a, c) => a + cardPoints(c))];

  @override
  List<int> handScores(TrickState s) {
    final p = points(s);
    if (s.contract == ramsch) return [for (final x in p) -x];
    final d = s.declarer;
    if (d < 0) return List.filled(seats, 0);
    final won = _null(s) ? s.tricks[d] == 0 : p[d] >= 61;
    return [for (var i = 0; i < seats; i++) (i == d) == won ? 1 : -1];
  }

  @override
  String status(TrickState s, String lang) {
    if (s.phase == TrickPhase.bidding) return '';
    final p = points(s);
    if (s.contract == ramsch) return '${kt(lang, 'least')}: ${p.join(' · ')}';
    final d = s.declarer;
    final game = bidLabel(s.contract + 10 * s.extra, lang);
    if (_null(s)) return '$game  ·  ${kt(lang, 'declarer')}: ${s.tricks[d]}';
    final def = p.fold<int>(0, (a, b) => a + b) - p[d];
    return '$game  ·  ${kt(lang, 'declarer')}: ${p[d]} / 61  ·  ${Strings.tx(lang, 'Onlar', 'Them')}: $def';
  }
}

// ---------------------------------------------------------------- Sheepshead

/// Sheepshead (Schafkopf ailesi), dört kişilik: kızlar, valeler ve bütün
/// karolar her zaman koz. "Al" diyen tek başına diğer üçüne karşı oynar ve
/// 120 puanın en az 61'ini almalı. Herkes pas derse en az puan alan kazanır.
class SheepsheadRules extends TrickRules {
  const SheepsheadRules();

  @override
  MatchFormat get matchFormat => const MatchFormat(deals: 12);

  /// Herkes pas (en az alan kazanır): en az puanı alan +3, diğerleri −1.
  @override
  List<int> matchPoints(TrickState s) {
    if (s.declarer >= 0) return handScores(s);
    final p = points(s);
    var low = 0;
    for (var i = 1; i < seats; i++) {
      if (p[i] < p[low]) low = i;
    }
    return [for (var i = 0; i < seats; i++) i == low ? 3 : -1];
  }

  @override
  int get handSize => 8;
  @override
  bool get hasBidding => true;
  @override
  List<KCard> deck() => buildDeck(ranks: const [1, 7, 8, 9, 10, 11, 12, 13]);

  static const _faceSuitPow = {kClubs: 4, kSpades: 3, kHearts: 2, kDiamonds: 1};
  static const _plainPow = {1: 6, 10: 5, 13: 4, 9: 3, 8: 2, 7: 1};

  @override
  int strength(KCard c) => _trumpPow(c) ?? _plainPow[rankOf(c)]!;

  static int? _trumpPow(KCard c) {
    final r = rankOf(c), su = suitOf(c);
    if (r == 12) return 40 + _faceSuitPow[su]!;
    if (r == 11) return 30 + _faceSuitPow[su]!;
    if (su == kDiamonds) return 20 + _plainPow[r]!;
    return null;
  }

  @override
  int cardPoints(KCard c) => const {1: 11, 10: 10, 13: 4, 12: 3, 11: 2}[rankOf(c)] ?? 0;

  @override
  int effSuit(TrickState s, KCard c) => _trumpPow(c) != null ? kVirtualTrump : suitOf(c);

  @override
  TrickState deal(List<KCard> shuffled, int dealer) {
    final s = super.deal(shuffled, dealer);
    s.trump = kVirtualTrump;
    return s;
  }

  @override
  bool beats(TrickState s, KCard a, KCard b, int lead) {
    final ta = isTrump(s, a), tb = isTrump(s, b);
    if (ta != tb) return ta;
    if (effSuit(s, a) != effSuit(s, b)) return false;
    return strength(a) > strength(b);
  }

  @override
  List<int> legalBids(TrickState s, int seat) => s.declarer >= 0 ? const [0] : const [0, 1];

  @override
  String bidLabel(int bid, String lang) => bid == 1 ? kt(lang, 'pick') : Strings.tx(lang, 'Pas', 'Pass');

  @override
  void applyBid(TrickState s, int seat, int bid) {
    super.applyBid(s, seat, bid);
    if (bid == 1 && s.declarer < 0) s.declarer = seat;
  }

  @override
  bool biddingOver(TrickState s) => s.declarer >= 0 || s.bidTurns >= seats;

  @override
  int aiBid(TrickState s, int seat, SeededRandom r) {
    final h = s.hands[seat];
    final trumps = h.where((c) => _trumpPow(c) != null).toList();
    final high = trumps.where((c) => rankOf(c) == 12).length;
    final aces = h.where((c) => rankOf(c) == 1 && suitOf(c) != kDiamonds).length;
    final v = trumps.length + high * 0.8 + aces * 0.5;
    return v >= 6.2 + (r.nextInt(3) - 1) * 0.4 ? 1 : 0;
  }

  @override
  void finishBidding(TrickState s) {
    startPlay(s);
    s.leader = (s.dealer + 1) % seats;
    s.turn = s.leader;
  }

  @override
  bool teammates(TrickState s, int a, int b) => a == b || (s.declarer >= 0 && a != s.declarer && b != s.declarer);

  @override
  bool avoidIn(TrickState s) => s.declarer < 0;

  List<int> points(TrickState s) => [for (final t in s.taken) t.fold<int>(0, (a, c) => a + cardPoints(c))];

  @override
  List<int> handScores(TrickState s) {
    final p = points(s);
    final d = s.declarer;
    if (d < 0) return [for (final x in p) -x];
    final won = p[d] >= 61;
    return [for (var i = 0; i < seats; i++) (i == d) == won ? (i == d ? 3 : 1) : (i == d ? -3 : -1)];
  }

  @override
  String status(TrickState s, String lang) {
    if (s.phase == TrickPhase.bidding) return '';
    final p = points(s);
    final d = s.declarer;
    if (d < 0) return '${kt(lang, 'least')}: ${p.join(' · ')}';
    final def = p.fold<int>(0, (a, b) => a + b) - p[d];
    return '${kt(lang, 'declarer')}: ${p[d]} / 61  ·  ${Strings.tx(lang, 'Onlar', 'Them')}: $def';
  }
}

// ---------------------------------------------------------------- Kontrat Briç

/// Kontrat briç (açık el olmadan): dört kişi, ortaklı. İhale düzey (1–7) ve
/// renk/kozsuz ile yapılır; art arda üç pas ihaleyi bitirir. İhaleyi alan
/// taraf 6 + düzey el almalıdır.
class ContractBridgeRules extends TrickRules {
  /// Chicago'da elin sırası (0–3; -1: tek el, zon yok). 1. el kimse zonlu
  /// değil, 2. ve 3. elde dağıtanın tarafı zonlu, 4. elde herkes zonlu.
  final int chicago;
  const ContractBridgeRules({this.chicago = -1});

  /// Chicago: dört el.
  @override
  MatchFormat get matchFormat => const MatchFormat(deals: 4);

  @override
  TrickRules rulesForDeal(int deal) => ContractBridgeRules(chicago: deal % 4);

  @override
  String? matchLabel(String lang) => 'Chicago  ·  4 × ${kt(lang, 'deal')}';

  @override
  bool get partnerships => true;
  @override
  bool get hasBidding => true;

  // bid = 1 + (düzey-1)*5 + renk sırası (♣ ♦ ♥ ♠ NT); 36 kontr (X), 37 sürkontr (XX).
  // Katlama durumu TrickState.aux'ta: 1 kontr, 2 sürkontr.
  static const double_ = 36, redouble = 37;
  static const _strainSuit = [kClubs, kDiamonds, kHearts, kSpades, -1];
  static int level(int bid) => (bid - 1) ~/ 5 + 1;
  static int strain(int bid) => (bid - 1) % 5;

  /// Taraf ([side] 0/1) bu elde zonlu mu?
  bool vulnerable(TrickState s, int side) => switch (chicago) {
        1 || 2 => side == s.dealer % 2,
        3 => true,
        _ => false,
      };

  int doubled(TrickState s) => s.aux < 0 ? 0 : s.aux;

  bool _canDouble(TrickState s, int seat) => s.contract > 0 && doubled(s) == 0 && seat % 2 != s.declarer % 2;
  bool _canRedouble(TrickState s, int seat) => s.contract > 0 && doubled(s) == 1 && seat % 2 == s.declarer % 2;

  @override
  List<int> legalBids(TrickState s, int seat) => [
        0,
        for (var b = s.contract + 1; b <= 35 && b <= s.contract + 15; b++) b,
        if (_canDouble(s, seat)) double_,
        if (_canRedouble(s, seat)) redouble,
      ];

  @override
  String bidLabel(int bid, String lang) {
    if (bid == 0) return Strings.tx(lang, 'Pas', 'Pass');
    if (bid == double_) return 'X';
    if (bid == redouble) return 'XX';
    final st = strain(bid);
    return '${level(bid)}${st == 4 ? kt(lang, 'noTrump') : _suitSym[_strainSuit[st]]}';
  }

  @override
  void applyBid(TrickState s, int seat, int bid) {
    super.applyBid(s, seat, bid);
    if (bid == double_ || bid == redouble) {
      s.aux = bid == double_ ? 1 : 2;
      s.extra = 0;
    } else if (bid > 0) {
      s.contract = bid;
      s.declarer = seat;
      s.extra = 0;
      s.aux = 0;
    } else {
      s.extra++;
    }
  }

  @override
  bool biddingOver(TrickState s) => (s.contract > 0 && s.extra >= 3) || (s.contract == 0 && s.extra >= 4);

  static int hcp(List<KCard> h) => h.fold<int>(0, (a, c) => a + (const {1: 4, 13: 3, 12: 2, 11: 1}[rankOf(c)] ?? 0));

  @override
  int aiBid(TrickState s, int seat, SeededRandom r) {
    final h = s.hands[seat];
    final pts = hcp(h);
    final lens = [for (var su = 0; su < 4; su++) h.where((c) => suitOf(c) == su).length];
    final partnerBid = s.bids[s.partnerOf(seat)];
    final partnerIn = partnerBid != null && partnerBid > 0 && partnerBid < double_;
    // Tahmini ortak güç
    final team = pts + (partnerIn ? 12 : 4) + (r.nextInt(3) - 1);
    // Rakibin yüksek kontratına karşı güçlü savunma: kontr.
    if (_canDouble(s, seat) && level(s.contract) >= 3 && pts >= 14 && pts + (partnerIn ? 10 : 0) >= 16 + level(s.contract) - 3) {
      return double_;
    }
    if (_canRedouble(s, seat) && pts >= 16) return redouble;
    if (team < 20 && !(s.contract == 0 && pts >= 12)) return 0;
    final balanced = lens.every((l) => l >= 2) && lens.where((l) => l == 2).length <= 1;
    var st = 4;
    if (!balanced || pts < 15) {
      var best = 0;
      for (var su = 1; su < 4; su++) {
        if (lens[su] > lens[best]) best = su;
      }
      st = _strainSuit.indexOf(best);
    }
    if (partnerIn && s.contract > 0 && strain(partnerBid) < 4 && lens[_strainSuit[strain(partnerBid)]] >= 3) {
      st = strain(partnerBid);
    }
    final maxLevel = ((team - 20) ~/ 3 + 1).clamp(1, 7);
    for (var lv = 1; lv <= maxLevel; lv++) {
      final b = 1 + (lv - 1) * 5 + st;
      if (b > s.contract) return b;
    }
    return 0;
  }

  @override
  void finishBidding(TrickState s) {
    if (s.contract == 0 && s.matchPlay) {
      // Maçta herkes pas: el yeniden dağıtılır.
      s.phase = TrickPhase.over;
      return;
    }
    if (s.contract == 0) {
      // Herkes pas: dağıtan 1 kozsuz oynar.
      s.contract = 5;
      s.declarer = s.dealer;
      s.aux = 0;
    }
    final su = _strainSuit[strain(s.contract)];
    s.trump = su;
    s.extra = 0;
    startPlay(s);
    s.leader = (s.declarer + 1) % seats;
    s.turn = s.leader;
  }

  int need(TrickState s) => 6 + level(s.contract);

  /// İlan eden tarafın puanı (eksi: batık). Kontrat puanı (♣♦ 20, ♥♠ 30,
  /// kozsuz ilk el 40 sonra 30; kontrla ×2, sürkontrla ×4), 100 ve üstü
  /// oyun bonusu (zonsuz 300, zonlu 500) yoksa kısmi bonus 50, küçük şlem
  /// 500/750, büyük şlem 1000/1500, kontr/sürkontr bonusu 50/100, fazla
  /// eller ve batık cezaları standart çizelgeye göre.
  int contractScore(TrickState s) {
    final d = s.declarer;
    final t = s.tricks[d] + s.tricks[s.partnerOf(d)];
    final n = need(s);
    final lv = level(s.contract), st = strain(s.contract);
    final dbl = doubled(s);
    final vul = vulnerable(s, d % 2);
    if (t >= n) {
      final per = st < 2 ? 20 : 30;
      var trick = st == 4 ? 40 + (lv - 1) * 30 : lv * per;
      trick *= const [1, 2, 4][dbl];
      var sc = trick + (trick >= 100 ? (vul ? 500 : 300) : 50);
      if (lv == 6) sc += vul ? 750 : 500;
      if (lv == 7) sc += vul ? 1500 : 1000;
      sc += const [0, 50, 100][dbl];
      final over = t - n;
      sc += over * (dbl == 0 ? per : (vul ? 200 : 100) * dbl);
      return sc;
    }
    final u = n - t;
    if (dbl == 0) return -u * (vul ? 100 : 50);
    final down = vul ? 200 + 300 * (u - 1) : 100 + 200 * (u - 1).clamp(0, 2) + 300 * (u - 3).clamp(0, 13);
    return -down * dbl;
  }

  @override
  List<int> handScores(TrickState s) {
    if (s.declarer < 0) return List.filled(seats, 0);
    final d = s.declarer % 2;
    final v = contractScore(s);
    return [for (var p = 0; p < seats; p++) p % 2 == d ? v : -v];
  }

  /// Chicago: puan, puanı kazanan tarafa yazılır (batıkta savunmaya).
  @override
  List<int> matchPoints(TrickState s) => [for (final x in handScores(s)) x > 0 ? x : 0];

  @override
  String status(TrickState s, String lang) {
    final vul = [
      if (chicago >= 0)
        '${kt(lang, 'vulnerable')}: ${[
          if (vulnerable(s, 0)) Strings.tx(lang, 'Biz', 'Us'),
          if (vulnerable(s, 1)) Strings.tx(lang, 'Onlar', 'Them'),
        ].join(' + ').ifEmpty('—')}',
    ];
    if (s.contract == 0 || s.phase == TrickPhase.bidding) return vul.join();
    final t = s.tricks[s.declarer] + s.tricks[s.partnerOf(s.declarer)];
    final who = s.declarer % 2 == 0 ? Strings.tx(lang, 'Biz', 'Us') : Strings.tx(lang, 'Onlar', 'Them');
    final x = const ['', ' X', ' XX'][doubled(s)];
    return [
      '${Strings.tx(lang, 'İhale', 'Contract')}: ${bidLabel(s.contract, lang)}$x ($who)  ·  $t / ${need(s)}',
      ...vul,
    ].join('  ·  ');
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

// ---------------------------------------------------------------- Bezik

/// Bezik: iki kişi, 64 kart (iki deste, 7–As). Açılan kartın rengi koz.
/// Deste bitene kadar renge uymak gerekmez; eli alan desteden ilk çeker ve
/// elindeki bir birleşimi açıklayabilir (evlilik 20, koz evliliği 40, bezik
/// 40, dört vale 40, dört kız 60, dört papaz 80, dört as 100, koz serisi 250,
/// çift bezik 500). As ve On'lar 10'ar puan. Deste bitince renge uymak ve
/// eli geçmek zorunlu.
class BezikRules extends TrickRules {
  const BezikRules();

  @override
  MatchFormat get matchFormat => const MatchFormat(target: 1000);

  @override
  int get seats => 2;
  @override
  int get handSize => 8;
  @override
  List<KCard> deck() => buildDeck(decks: 2, ranks: const [1, 7, 8, 9, 10, 11, 12, 13]);

  static const _pow = {1: 8, 10: 7, 13: 6, 12: 5, 11: 4, 9: 3, 8: 2, 7: 1};

  @override
  int strength(KCard c) => _pow[rankOf(c)]!;

  @override
  int cardPoints(KCard c) => rankOf(c) == 1 || rankOf(c) == 10 ? 10 : 0;

  @override
  TrickState deal(List<KCard> shuffled, int dealer) {
    final s = super.deal(shuffled, dealer);
    s.trump = suitOf(s.kitty.first);
    s.bids[0] = 0;
    s.bids[1] = 0;
    for (final h in s.hands) {
      sortHand(h, s.trump);
    }
    return s;
  }

  @override
  List<KCard> legalPlays(TrickState s, int seat) {
    final h = s.hands[seat];
    if (s.trick.isEmpty || s.kitty.isNotEmpty) return List.of(h);
    final lead = suitOf(s.trick.first);
    final best = s.trick.first;
    final follow = h.where((c) => suitOf(c) == lead).toList();
    if (follow.isNotEmpty) {
      final over = follow.where((c) => beats(s, c, best, lead)).toList();
      return over.isNotEmpty ? over : follow;
    }
    final trumps = h.where((c) => suitOf(c) == s.trump).toList();
    return trumps.isNotEmpty ? trumps : List.of(h);
  }

  // Birleşim türleri (bit sırası, oyuncu başına 12 bit; extra = p0 | p1 << 12)
  static const _meldPts = [20, 20, 20, 40, 40, 500, 40, 60, 80, 100, 250];
  // 0–2: koz dışı evlilikler (renk sırasıyla, kozu atlayarak), 3 koz evliliği,
  // 4 bezik, 5 çift bezik, 6 dört vale, 7 dört kız, 8 dört papaz, 9 dört as, 10 seri

  static int bestMeld(List<KCard> h, int trump, int done) {
    int count(int r, int su) => h.where((c) => rankOf(c) == r && suitOf(c) == su).length;
    bool four(int r) => [for (var su = 0; su < 4; su++) count(r, su)].every((x) => x > 0);
    var bestBit = -1, bestPts = 0;
    void consider(int bit, bool ok) {
      if (ok && (done >> bit) & 1 == 0 && _meldPts[bit] > bestPts) {
        bestBit = bit;
        bestPts = _meldPts[bit];
      }
    }

    var k = 0;
    for (var su = 0; su < 4; su++) {
      if (su == trump) continue;
      consider(k++, count(13, su) > 0 && count(12, su) > 0);
    }
    consider(3, count(13, trump) > 0 && count(12, trump) > 0);
    consider(4, count(12, kSpades) > 0 && count(11, kDiamonds) > 0);
    consider(5, count(12, kSpades) > 1 && count(11, kDiamonds) > 1);
    consider(6, four(11));
    consider(7, four(12));
    consider(8, four(13));
    consider(9, four(1));
    consider(10, [1, 10, 13, 12, 11].every((r) => count(r, trump) > 0));
    return bestBit;
  }

  @override
  void afterTrick(TrickState s, int winner) {
    if (s.kitty.isNotEmpty) {
      final done = (s.extra >> (winner * 12)) & 0xFFF;
      final bit = bestMeld(s.hands[winner], s.trump, done);
      if (bit >= 0) {
        s.extra |= 1 << (bit + winner * 12);
        s.bids[winner] = (s.bids[winner] ?? 0) + _meldPts[bit];
      }
    }
    for (final p in [winner, (winner + 1) % seats]) {
      if (s.kitty.isNotEmpty) s.hands[p].add(s.kitty.removeLast());
    }
    for (final h in s.hands) {
      sortHand(h, s.trump);
    }
  }

  List<int> points(TrickState s) => [
        for (var p = 0; p < seats; p++)
          (s.bids[p] ?? 0) +
              s.taken[p].fold<int>(0, (a, c) => a + cardPoints(c)) +
              (s.phase == TrickPhase.over && s.lastWinner == p ? 10 : 0),
      ];

  @override
  List<int> handScores(TrickState s) => points(s);

  @override
  String bidLabel(int bid, String lang) => '${kt(lang, 'meld')} $bid';

  @override
  String status(TrickState s, String lang) =>
      '${Strings.tx(lang, 'Puan', 'Points')}: ${points(s).join(' · ')}  ·  ${Strings.tx(lang, 'Deste', 'Stock')}: ${s.kitty.length}';
}
