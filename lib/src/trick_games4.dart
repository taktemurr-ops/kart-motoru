import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'kart_texts.dart';
import 'trick_engine.dart';

const _suitSym = ['♠', '♥', '♦', '♣'];

/// Yalnızca valelerin (ve bazen kızların) koz olduğu oyunlarda "sanal koz rengi".
const kVirtualTrump = 4;

// ---------------------------------------------------------------- Skat

/// Skat: üç kişi, 32 kart, onar kart + 2 kartlık skat. Gerçek sayısal ihale
/// (Reizen): önce orta el (Mittelhand) öndeki ele (Vorhand) 18, 20, 22, 23 …
/// söyler, öndeki "tutar" ya da pas der; kalan, arka ele (Hinterhand) karşı
/// aynı biçimde devam eder. İhaleyi alan skatı alıp iki kart gömer (ya da
/// Hand oynar) ve oyununu ilan eder. Renk oyununda valeler ve seçilen renk
/// koz; Grand'da yalnızca valeler; Null'da koz yok ve hiç el alınmamalı.
/// Hand oyunlarında Schneider/Schwarz önceden ilan edilebilir; Grand Ouvert
/// açık elle bütün elleri almayı gerektirir. Oyun değeri ihaleye ulaşmazsa
/// (aşırı ihale) oyun kaybedilir. As 11, On 10, Papaz 4, Kız 3, Vale 2:
/// renk ve Grand'da 61 puan gerekir. Herkes pas derse Ramsch: en az puan
/// alan kazanır. Para yok, yalnızca puan listesi.
class SkatRules extends TrickRules {
  const SkatRules();

  /// Liste: 12 el (herkes dört kez dağıtır).
  @override
  MatchFormat get matchFormat => const MatchFormat(deals: 12);

  // Oyun türü (contract): 1 ♦, 2 ♥, 3 ♠, 4 Null, 5 ♣, 6 Grand, 7 Ramsch.
  // Ekler [TrickState.extra]'da (bit): 1 Hand, 2 Ouvert, 4 Schneider ilanı,
  // 8 Schwarz ilanı. Matadorlar [TrickState.aux]'ta; ihale değeri ilan edenin
  // [TrickState.bids] kaydında.
  static const _contractSuit = {1: kDiamonds, 2: kHearts, 3: kSpades, 5: kClubs};
  static const nullGame = 4, grand = 6, ramsch = 7;
  static const hand = 1, ouvert = 2, schneiderAnnounced = 4, schwarzAnnounced = 8;

  /// Temel değerler: ♦ 9, ♥ 10, ♠ 11, ♣ 12, Grand 24.
  static const base = {1: 9, 2: 10, 3: 11, 5: 12, grand: 24};

  /// Null değerleri: Null 23, Null Hand 35, Null Ouvert 46, Null Ouvert Hand 59.
  static const nullValue = {0: 23, hand: 35, ouvert: 46, hand | ouvert: 59};

  // İhale kodları: 0 pas, 1 tutarım, 2 Hand, 3 skatı al, 18..264 ihale
  // değeri, 1000 + oyun + 10 × ekler ilan, 2000 + kart gömme.
  static const pass = 0, hold = 1, playHand = 2, pickUp = 3, declareBase = 1000, buryBase = 2000;

  /// İhale aşaması ([TrickState.aux] ihale sırasında): 0 orta el öndekine,
  /// 1 arka el kazanana söyler, 2 öndeki tek başına 18 der mi, 3 skat ya da
  /// Hand, 4 iki kart gömme, 5 oyun ilanı, 99 bitti.
  static const stageDone = 99;

  /// Bütün geçerli ihale değerleri (18, 20, 22, 23, 24, 27, 30 … 264).
  static final List<int> bidValues = () {
    final v = <int>{...nullValue.values};
    for (final b in const [9, 10, 11, 12]) {
      for (var m = 2; m <= 18; m++) {
        v.add(b * m);
      }
    }
    for (var m = 2; m <= 11; m++) {
      v.add(24 * m);
    }
    return (v.where((x) => x >= 18).toList()..sort());
  }();

  static int nextBid(int current) => bidValues.firstWhere((v) => v > current, orElse: () => 0);

  static int vorhand(TrickState s) => (s.dealer + 1) % 3;
  static int mittelhand(TrickState s) => (s.dealer + 2) % 3;
  static int hinterhand(TrickState s) => s.dealer;
  static int stage(TrickState s) => s.aux < 0 ? 0 : s.aux;
  static int _sayer(TrickState s) => stage(s) == 0 ? mittelhand(s) : hinterhand(s);

  /// İhaleyi alan ilan edenin ihale değeri.
  static int bidOf(TrickState s) => s.declarer < 0 ? 0 : (s.bids[s.declarer] ?? 0);

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

  /// İlan eklerini tamamla: Ouvert → Schwarz ilanı, Schwarz → Schneider ilanı;
  /// ilanlar yalnızca Hand oyununda.
  static int normalizeFlags(int game, int f) {
    if (game == nullGame) return f & (hand | ouvert);
    if (f & ouvert != 0) f |= schwarzAnnounced | hand;
    if (f & schwarzAnnounced != 0) f |= schneiderAnnounced;
    if (f & hand == 0) f &= ~(schneiderAnnounced | schwarzAnnounced | ouvert);
    return f;
  }

  /// Oyunun değeri ve kazanılıp kazanılmadığı. Renk/Grand: temel × (matador
  /// + oyun 1 + Hand + Schneider + ilanı + Schwarz + ilanı + Ouvert). Null:
  /// sabit değer. Değer ihaleye ulaşmazsa oyun kaybedilir ve değer ihaleyi
  /// karşılayan en küçük temel katıdır (aşırı ihale).
  (int, bool) gameValue(TrickState s) {
    final d = s.declarer;
    final f = s.extra;
    final bid = bidOf(s);
    if (_null(s)) {
      final v = nullValue[f & 3] ?? 23;
      return (v, s.tricks[d] == 0 && v >= bid);
    }
    final p = points(s)[d];
    final schneider = p >= 90 || p <= 30;
    final schwarz = s.tricks[d] == 10 || s.tricks[d] == 0;
    final annS = f & schneiderAnnounced != 0, annSw = f & schwarzAnnounced != 0, open = f & ouvert != 0;
    final mult = s.aux.clamp(1, 11) +
        1 +
        (f & hand) +
        (schneider ? 1 : 0) +
        (annS ? 1 : 0) +
        (schwarz ? 1 : 0) +
        (annSw ? 1 : 0) +
        (open ? 1 : 0);
    final b = base[s.contract]!;
    var v = b * mult;
    var won = p >= 61 && (!annS || p >= 90) && (!annSw || s.tricks[d] == 10);
    if (v < bid) {
      won = false;
      v = ((bid + b - 1) ~/ b) * b;
    }
    return (v, won);
  }

  /// Aşırı ihale: oyun değeri ihaleye ulaşmadı.
  bool overbid(TrickState s) {
    if (s.declarer < 0 || s.contract == ramsch) return false;
    final saved = s.bids[s.declarer];
    s.bids[s.declarer] = 0;
    final (v, _) = gameValue(s);
    s.bids[s.declarer] = saved;
    return v < bidOf(s);
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

  // ---- ihale (Reizen) ----

  @override
  void setupAfterDeal(TrickState s) {
    s
      ..aux = 0
      ..contract = 0
      ..extra = 0
      ..declarer = vorhand(s)
      ..turn = mittelhand(s);
  }

  /// Oyun ilanı seçenekleri: Hand'de Schneider/Schwarz ilanı ve Grand
  /// Ouvert; Null yalnızca değeri ihaleye yetiyorsa.
  List<int> declarations(TrickState s) {
    final h = s.extra & hand != 0;
    final bid = bidOf(s);
    return [
      for (final g in const [1, 2, 3, 5, grand]) ...[
        declareBase + g + 10 * (h ? hand : 0),
        if (h) declareBase + g + 10 * (hand | schneiderAnnounced),
        if (h) declareBase + g + 10 * (hand | schneiderAnnounced | schwarzAnnounced),
        if (h && g == grand) declareBase + g + 10 * (hand | ouvert | schneiderAnnounced | schwarzAnnounced),
      ],
      for (final f in h ? const [hand, hand | ouvert] : const [0, ouvert])
        if (nullValue[f]! >= bid) declareBase + nullGame + 10 * f,
    ];
  }

  @override
  List<int> legalBids(TrickState s, int seat) {
    if (seat != s.turn) return const [];
    switch (stage(s)) {
      case 0 || 1:
        if (seat == _sayer(s)) {
          final out = [pass];
          for (final v in bidValues) {
            if (v > s.contract && out.length < 7) out.add(v);
          }
          return out;
        }
        return const [hold, pass];
      case 2:
        return const [pass, 18];
      case 3:
        return const [pickUp, playHand];
      case 4:
        return [for (final c in s.hands[seat]) buryBase + c];
      case 5:
        return declarations(s);
    }
    return const [];
  }

  @override
  void applyBid(TrickState s, int seat, int bid) {
    s.bidTurns++;
    switch (stage(s)) {
      case 0 || 1:
        if (seat == _sayer(s)) {
          if (bid == pass) {
            s.bids[seat] = 0;
            _duelWon(s, s.declarer);
          } else {
            s.contract = bid;
            s.bids[seat] = bid;
            s.turn = s.declarer;
          }
        } else if (bid == hold) {
          s.bids[seat] = s.contract;
          s.turn = _sayer(s);
        } else {
          s.bids[seat] = 0;
          _duelWon(s, _sayer(s));
        }
      case 2:
        if (bid == 18) {
          s.contract = 18;
          s.bids[seat] = 18;
          _declarer(s, seat);
        } else {
          s.bids[seat] = 0;
          s.declarer = -1;
          s.aux = stageDone;
        }
      case 3:
        if (bid == playHand) {
          s.extra |= hand;
          s.aux = 5;
        } else {
          s.hands[seat].addAll(s.kitty);
          s.kitty.clear();
          sortHand(s.hands[seat], -1);
          s.aux = 4;
        }
      case 4:
        final c = bid - buryBase;
        s.hands[seat].remove(c);
        s.taken[seat].add(c);
        if (s.taken[seat].length >= 2) s.aux = 5;
      case 5:
        final code = bid - declareBase;
        final g = code % 10;
        s.contract = g;
        s.extra = normalizeFlags(g, code ~/ 10);
        s.aux = stageDone;
    }
  }

  /// Bir ihale düellosu bitti: ilk düellodan sonra arka el söyler; ikinciden
  /// sonra kazanan ilan eder (kimse söylemediyse öndeki 18 diyebilir).
  void _duelWon(TrickState s, int winner) {
    s.declarer = winner;
    if (stage(s) == 0) {
      s.aux = 1;
      s.turn = hinterhand(s);
    } else if (s.contract == 0) {
      s.aux = 2;
      s.turn = winner;
    } else {
      _declarer(s, winner);
    }
  }

  void _declarer(TrickState s, int seat) {
    s.declarer = seat;
    s.aux = 3;
    s.turn = seat;
  }

  @override
  bool biddingOver(TrickState s) => s.aux == stageDone;

  @override
  String bidPrompt(TrickState s, String lang) => switch (stage(s)) {
        0 || 1 => s.turn == _sayer(s) ? kt(lang, 'skatPromptSay') : '${kt(lang, 'skatBidNow')}: ${s.contract}',
        2 => kt(lang, 'skatPromptSay'),
        3 => '${kt(lang, 'skatPromptSkat')}  ·  ${bidOf(s)}',
        4 => '${kt(lang, 'skatPromptBury')} (${2 - s.taken[s.turn].length})',
        _ => '${kt(lang, 'skatPromptGame')}  ·  ${bidOf(s)}',
      };

  /// Oyunun adı (ör. "♣ Hand Schneider", "Grand Ouvert", "Null 23").
  String gameLabel(int game, int flags, String lang) {
    if (game == ramsch) return kt(lang, 'least');
    final name = switch (game) {
      nullGame => kt(lang, 'null'),
      grand => kt(lang, 'grand'),
      _ => _suitSym[_contractSuit[game]!],
    };
    final parts = [
      name,
      if (flags & hand != 0 && flags & ouvert == 0 || game == nullGame && flags & hand != 0) kt(lang, 'skatHand'),
      if (flags & ouvert != 0) kt(lang, 'ouvert'),
      if (game != nullGame && flags & ouvert == 0 && flags & schwarzAnnounced != 0)
        kt(lang, 'schwarz')
      else if (game != nullGame && flags & ouvert == 0 && flags & schneiderAnnounced != 0)
        kt(lang, 'schneider'),
    ];
    final v = game == nullGame ? nullValue[flags & 3]! : base[game]!;
    return '${parts.join(' ')} · ${game == nullGame ? v : '×$v'}';
  }

  @override
  String bidLabel(int bid, String lang) {
    if (bid == pass) return kt(lang, 'pass');
    if (bid == hold) return kt(lang, 'skatHold');
    if (bid == playHand) return kt(lang, 'skatHand');
    if (bid == pickUp) return kt(lang, 'skatPickUp');
    if (bid >= buryBase) {
      final c = bid - buryBase;
      return '${kt(lang, 'skatBury')} ${rankLabel(rankOf(c))}${_suitSym[suitOf(c)]}';
    }
    if (bid >= declareBase) {
      final code = bid - declareBase;
      return gameLabel(code % 10, code ~/ 10, lang);
    }
    return '$bid';
  }

  @override
  void finishBidding(TrickState s) {
    final d = s.declarer;
    if (d < 0) {
      s.contract = ramsch;
      s.trump = kVirtualTrump;
      s.extra = 0;
    } else {
      final g = s.contract;
      s.trump = g == nullGame ? -1 : (g == grand ? kVirtualTrump : _contractSuit[g]!);
      // Matadorlar elle skatın birlikte (12 kart) sayılır.
      s.aux = g == nullGame ? 0 : matadors([...s.hands[d], ...s.taken[d], ...s.kitty], g);
      // Hand: skat kapalı kalır, sonunda ilan edenin sayılır.
      s.taken[d].addAll(s.kitty);
      s.kitty.clear();
    }
    startPlay(s);
    s.leader = vorhand(s);
    s.turn = s.leader;
  }

  // ---- yapay zekâ ihalesi: elin en yüksek oyun değerini hesaplar ----

  /// Renk oyunu gücü (koz sayısı, yan asların, boş renklerin katkısı).
  static double suitScore(List<KCard> h, int game) {
    final t = _contractSuit[game]!;
    bool has(int r, int su) => h.any((c) => rankOf(c) == r && suitOf(c) == su);
    final jacks = h.where((c) => rankOf(c) == 11).length;
    var sc = (jacks + h.where((c) => suitOf(c) == t && rankOf(c) != 11).length).toDouble();
    if (has(11, kClubs)) sc += 0.5;
    if (has(11, kSpades)) sc += 0.25;
    if (has(1, t)) sc += 0.3;
    for (final su in const [kClubs, kSpades, kHearts, kDiamonds]) {
      if (su == t) continue;
      final side = h.where((c) => suitOf(c) == su && rankOf(c) != 11).toList();
      if (side.isEmpty) {
        sc += 0.5;
        continue;
      }
      if (has(1, su)) sc += 0.9;
      if (has(1, su) && has(10, su)) sc += 0.6;
      if (!has(1, su) && has(10, su) && side.length <= 2) sc -= 0.3;
    }
    return sc;
  }

  /// Grand gücü (valeler ve aslar/onlar).
  static double grandScore(List<KCard> h) {
    bool has(int r, int su) => h.any((c) => rankOf(c) == r && suitOf(c) == su);
    var sc = h.where((c) => rankOf(c) == 11).length * 1.4;
    if (has(11, kClubs)) sc += 0.4;
    for (final su in const [kClubs, kSpades, kHearts, kDiamonds]) {
      final side = h.where((c) => suitOf(c) == su && rankOf(c) != 11).length;
      if (has(1, su)) sc += 1.0;
      if (has(1, su) && has(10, su)) sc += 0.8;
      if (has(1, su) && side >= 4) sc += 0.5;
      if (!has(1, su) && has(10, su) && side >= 3) sc += 0.3;
    }
    return sc;
  }

  /// Null için güvensiz renk sayısı (her kartın altında yeterli küçük kart).
  static int nullRisk(List<KCard> h) {
    var risk = 0;
    for (final su in const [kClubs, kSpades, kHearts, kDiamonds]) {
      final idx = [for (final c in h) if (suitOf(c) == su) _nullPow[rankOf(c)]! - 1]..sort();
      for (var i = 0; i < idx.length; i++) {
        if (idx[i] > 2 * i) {
          risk++;
          break;
        }
      }
    }
    return risk;
  }

  static const _thrSkat = 6.0, _thrHand = 8.2;

  /// Elin gücü (eşiğe göre; ≥ 0 oynanabilir) ve tahmini değeri.
  /// [known] ilan edenin bildiği bütün kartlar (matador için), [h] eli.
  static (double, int) evaluate(List<KCard> h, List<KCard> known, int game, int flags, {bool exact = false}) {
    final isHand = flags & hand != 0;
    final thr = isHand ? _thrHand : _thrSkat;
    if (game == nullGame) {
      final risk = nullRisk(h);
      final allowed = isHand || flags & ouvert != 0 ? 0 : 1;
      final low = h.where((c) => rankOf(c) >= 7 && rankOf(c) <= 9).length;
      final sc = risk <= allowed && (flags & ouvert == 0 || low >= 7) ? 1.0 + low * 0.1 : -5.0 + low * 0.1 - risk;
      return (sc, nullValue[flags & 3]!);
    }
    final sc = (game == grand ? grandScore(h) : suitScore(h, game)) - thr - (flags & schneiderAnnounced != 0 ? 2.0 : 0);
    var m = matadors(known, game);
    // Elde olmayan skat "olmadan" sayısını bozabilir: temkinli tahmin.
    final top = known.any((c) => rankOf(c) == 11 && suitOf(c) == kClubs);
    if (!exact && !top && m > 1) m = 1;
    final b = base[game]!;
    final mult = m + 1 + (isHand ? 1 : 0) + (flags & schneiderAnnounced != 0 ? 1 : 0);
    return (sc, b * mult);
  }

  /// En yüksek güvenli ihale (oynanabilir oyunların en büyük değeri; yoksa 0).
  static int maxBid(List<KCard> h) {
    var best = 0;
    for (final g in const [1, 2, 3, 5, grand, nullGame]) {
      for (final f in const [0, hand]) {
        final (sc, v) = evaluate(h, h, g, f);
        if (sc >= 0 && v > best) best = v;
      }
    }
    return best;
  }

  /// İlan seçimi: ihaleye ulaşan en güçlü oyun.
  int _chooseDeclaration(TrickState s, int seat, List<int> options) {
    final known = [...s.hands[seat], ...s.taken[seat]];
    final exact = s.extra & hand == 0;
    final bid = bidOf(s);
    var best = options.first;
    var bv = double.negativeInfinity;
    for (final o in options) {
      final code = o - declareBase;
      final g = code % 10, f = normalizeFlags(g, code ~/ 10);
      if (f & (ouvert | schwarzAnnounced) != 0 && g != nullGame) continue;
      final (sc, v) = evaluate(s.hands[seat], known, g, f, exact: exact);
      var u = sc * 10 + v * 0.25;
      if (v < bid) u -= 1000;
      if (u > bv) {
        bv = u;
        best = o;
      }
    }
    return best;
  }

  /// Oyuna göre gömülecek en zayıf kart (kısa yan renkler, korunmasız onlar).
  KCard _buryCard(List<KCard> h, int game) {
    double key(KCard c) {
      if (game == nullGame) return -_nullPow[rankOf(c)]!.toDouble() - (h.where((x) => suitOf(x) == suitOf(c)).length <= 2 ? 2 : 0);
      final trump = rankOf(c) == 11 || (game != grand && suitOf(c) == _contractSuit[game]);
      if (trump) return 1000.0 + (rankOf(c) == 11 ? 20 : _plainPow[rankOf(c)]!);
      if (rankOf(c) == 1) return 500;
      final len = h.where((x) => suitOf(x) == suitOf(c) && rankOf(x) != 11).length;
      final protectedTen = rankOf(c) == 10 && h.any((x) => suitOf(x) == suitOf(c) && rankOf(x) == 1);
      return _plainPow[rankOf(c)]! * 2.0 - cardPoints(c) * 0.5 + len * 4 + (protectedTen ? 300 : 0);
    }

    final order = List.of(h)..sort((a, b) => key(a).compareTo(key(b)));
    return order.first;
  }

  /// 12 kartla en iyi oyun (gömmeden önce): her oyun için en zayıf ikisi atılır.
  int _bestGameWith12(TrickState s, int seat) {
    final bid = bidOf(s);
    var best = 1;
    var bv = double.negativeInfinity;
    for (final g in const [1, 2, 3, 5, grand, nullGame]) {
      final h = List.of(s.hands[seat]);
      for (var i = 0; i < 2; i++) {
        h.remove(_buryCard(h, g));
      }
      final (sc, v) = evaluate(h, s.hands[seat], g, 0, exact: true);
      var u = sc * 10 + v * 0.25;
      if (v < bid) u -= 1000;
      if (u > bv) {
        bv = u;
        best = g;
      }
    }
    return best;
  }

  @override
  int aiBid(TrickState s, int seat, SeededRandom r) {
    final h = s.hands[seat];
    switch (stage(s)) {
      case 0 || 1:
        final limit = maxBid(h);
        if (seat == _sayer(s)) {
          final n = nextBid(s.contract);
          return n > 0 && n <= limit ? n : pass;
        }
        return s.contract <= limit ? hold : pass;
      case 2:
        return maxBid(h) >= 18 ? 18 : pass;
      case 3:
        final bid = bidOf(s);
        for (final g in const [grand, 5, 3, 2, 1, nullGame]) {
          final (sc, v) = evaluate(h, h, g, hand);
          if (sc >= 0 && v >= bid) return playHand;
        }
        return pickUp;
      case 4:
        return buryBase + _buryCard(h, _bestGameWith12(s, seat));
      case 5:
        return _chooseDeclaration(s, seat, declarations(s));
    }
    return legalBids(s, seat).first;
  }

  /// Ouvert oyunlarında ilan edenin eli herkese açıktır.
  @override
  bool openHand(TrickState s, int seat) =>
      s.phase != TrickPhase.bidding && s.declarer >= 0 && s.contract != ramsch && s.extra & ouvert != 0 && seat == s.declarer;

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
    final won = gameValue(s).$2;
    return [for (var i = 0; i < seats; i++) (i == d) == won ? 1 : -1];
  }

  @override
  String status(TrickState s, String lang) {
    if (s.phase == TrickPhase.bidding) return s.contract > 0 && stage(s) <= 2 ? '${kt(lang, 'skatBidNow')}: ${s.contract}' : '';
    final p = points(s);
    if (s.contract == ramsch) return '${kt(lang, 'least')}: ${p.join(' · ')}';
    final d = s.declarer;
    final game = '${gameLabel(s.contract, s.extra, lang)}  ·  ${bidOf(s)}';
    final over = s.phase == TrickPhase.over && overbid(s) ? '  ·  ${kt(lang, 'overbid')}' : '';
    if (_null(s)) return '$game  ·  ${kt(lang, 'declarer')}: ${s.tricks[d]}$over';
    final def = p.fold<int>(0, (a, b) => a + b) - p[d];
    final need = s.extra & schwarzAnnounced != 0 ? '10 ✓' : (s.extra & schneiderAnnounced != 0 ? '90' : '61');
    return '$game  ·  ${kt(lang, 'declarer')}: ${p[d]} / $need  ·  ${Strings.tx(lang, 'Onlar', 'Them')}: $def$over';
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
