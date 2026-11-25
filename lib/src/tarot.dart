import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'kart_texts.dart';
import 'trick_engine.dart';
import 'trick_games4.dart' show kVirtualTrump;

// ---------------------------------------------------------------- 78'lik deste

/// 78 kartlık deste için ek kartlar. Renk kartları (As–10, Vale, Kız, Papaz)
/// normal kodlamayı kullanır; at (süvari) 200 + renk, numaralı kozlar
/// 300 + n (1–21), Kaçak (Excuse) 300.
const kTarotKnight = 200;
const kTarotTrump = 300;
const kTarotExcuse = 300;

bool isTarotKnight(KCard c) => c >= kTarotKnight && c < kTarotKnight + 4;
bool isTarotTrump(KCard c) => c > kTarotTrump && c <= kTarotTrump + 21;
bool isTarotSpecial(KCard c) => c >= kTarotKnight;
int tarotTrumpNo(KCard c) => c - kTarotTrump;

/// 78 kart: 56 renk kartı (14'er), 21 koz ve Kaçak.
List<KCard> buildTarotDeck() => [
      for (var s = 0; s < 4; s++) ...[
        for (var r = 1; r <= 13; r++) makeCard(r, s),
        kTarotKnight + s,
      ],
      for (var n = 1; n <= 21; n++) kTarotTrump + n,
      kTarotExcuse,
    ];

bool isOudler(KCard c) => c == kTarotExcuse || c == kTarotTrump + 1 || c == kTarotTrump + 21;

/// Kart puanı, iki katı olarak (yarım puan olmasın diye): toplam 182 = 91 × 2.
int tarotPoints2(KCard c) {
  if (isOudler(c)) return 9;
  if (isTarotKnight(c)) return 5;
  if (isTarotTrump(c)) return 1;
  return switch (rankOf(c)) { 13 => 9, 12 => 7, 11 => 3, _ => 1 };
}

// ---------------------------------------------------------------- Kurallar

/// Fransız usulü Tarok, dört kişi: 18'er kart, ortada 6 kartlık köpek.
/// En yüksek ihaleyi alan diğer üçüne karşı oynar. Renge uymak zorunlu;
/// renk yoksa koz, kozda da bir öncekini geçmek zorunlu. Kaçak her zaman
/// oynanabilir, el almaz ve sahibinde kalır. Gereken puan, alınan
/// anahtar kart (1, 21, Kaçak) sayısına göre 56 / 51 / 41 / 36.
class TarotRules extends TrickRules {
  const TarotRules();

  /// 12 el; alan oyuncu üç rakibe karşı oynar (sıfır toplamlı puan).
  @override
  MatchFormat get matchFormat => const MatchFormat(deals: 12);

  @override
  List<int> matchPoints(TrickState s) {
    final d = s.declarer;
    if (d < 0) return List.filled(seats, 0);
    final sc = handScores(s);
    return [for (var i = 0; i < seats; i++) i == d ? sc[d] * (seats - 1) : -sc[d]];
  }

  static const petite = 1, garde = 2, gardeSans = 3, gardeContre = 4;
  static const _need2 = [112, 102, 82, 72];
  static const _mult = [0, 1, 2, 4, 6];

  @override
  int get handSize => 18;
  @override
  bool get hasBidding => true;
  @override
  List<KCard> deck() => buildTarotDeck();

  @override
  int strength(KCard c) {
    if (c == kTarotExcuse) return 0;
    if (isTarotTrump(c)) return 20 + tarotTrumpNo(c);
    if (isTarotKnight(c)) return 12;
    final r = rankOf(c);
    return r <= 10 ? r : (r == 11 ? 11 : r + 1); // V 11, At 12, K 13, P 14
  }

  @override
  int cardPoints(KCard c) => tarotPoints2(c);

  @override
  int effSuit(TrickState s, KCard c) {
    if (c == kTarotExcuse) return 5;
    if (isTarotTrump(c)) return kVirtualTrump;
    if (isTarotKnight(c)) return c - kTarotKnight;
    return suitOf(c);
  }

  @override
  bool isTrump(TrickState s, KCard c) => isTarotTrump(c);

  @override
  void sortHand(List<KCard> h, int trump) {
    int key(KCard c) {
      if (c == kTarotExcuse) return 999;
      if (isTarotTrump(c)) return 500 + tarotTrumpNo(c);
      final su = isTarotKnight(c) ? c - kTarotKnight : suitOf(c);
      return const [0, 1, 3, 2][su] * 100 + strength(c);
    }

    h.sort((a, b) => key(a).compareTo(key(b)));
  }

  /// Elin rengini belirleyen kart: Kaçak dışındaki ilk kart.
  int _leadIx(TrickState s) {
    for (var i = 0; i < s.trick.length; i++) {
      if (s.trick[i] != kTarotExcuse) return i;
    }
    return -1;
  }

  int _highTrump(TrickState s) {
    var best = 0;
    for (final c in s.trick) {
      if (isTarotTrump(c) && tarotTrumpNo(c) > best) best = tarotTrumpNo(c);
    }
    return best;
  }

  @override
  List<KCard> legalPlays(TrickState s, int seat) {
    final h = s.hands[seat];
    final li = _leadIx(s);
    if (li < 0) return List.of(h);
    final lead = effSuit(s, s.trick[li]);
    final hasExcuse = h.contains(kTarotExcuse);
    List<KCard> withExcuse(List<KCard> l) => [...l, if (hasExcuse) kTarotExcuse];
    if (lead != kVirtualTrump) {
      final follow = h.where((c) => c != kTarotExcuse && effSuit(s, c) == lead).toList();
      if (follow.isNotEmpty) return withExcuse(follow);
    }
    final trumps = h.where(isTarotTrump).toList();
    if (trumps.isEmpty) return List.of(h);
    final hi = _highTrump(s);
    final over = trumps.where((c) => tarotTrumpNo(c) > hi).toList();
    return withExcuse(over.isNotEmpty ? over : trumps);
  }

  @override
  bool beats(TrickState s, KCard a, KCard b, int lead) {
    if (a == kTarotExcuse) return false;
    if (b == kTarotExcuse) return true;
    return super.beats(s, a, b, lead);
  }

  @override
  int trickWinner(TrickState s) {
    final li = _leadIx(s);
    var best = li < 0 ? 0 : li;
    final lead = effSuit(s, s.trick[best]);
    for (var i = 0; i < s.trick.length; i++) {
      if (i == best || s.trick[i] == kTarotExcuse) continue;
      if (beats(s, s.trick[i], s.trick[best], lead)) best = i;
    }
    return (s.leader + best) % seats;
  }

  @override
  void play(TrickState s, int seat, KCard c) {
    final before = Set.of(s.voids[seat]);
    final li = _leadIx(s);
    final lead = li < 0 ? -1 : effSuit(s, s.trick[li]);
    super.play(s, seat, c);
    // Kaçak renk bilgisi vermez; Kaçak öndeyken de renk sonradan belirlenir.
    s.voids[seat]
      ..clear()
      ..addAll(before);
    if (c == kTarotExcuse || lead < 0) return;
    final su = effSuit(s, c);
    if (su != lead) {
      s.voids[seat].add(lead);
      if (su != kVirtualTrump) s.voids[seat].add(kVirtualTrump);
    }
  }

  @override
  void afterTrick(TrickState s, int winner) {
    final i = s.trick.indexOf(kTarotExcuse);
    if (i < 0) return;
    final owner = (s.leader + i) % seats;
    if (teammates(s, owner, winner)) return;
    s.taken[winner].remove(kTarotExcuse);
    s.taken[owner].add(kTarotExcuse);
  }

  // ---- ihale ----
  int _high(TrickState s) => s.bids.whereType<int>().fold<int>(0, (a, b) => b > a ? b : a);

  @override
  List<int> legalBids(TrickState s, int seat) {
    final hi = _high(s);
    // Herkes pas geçtiyse dağıtan oynamak zorunda.
    final forced = seat == s.dealer && hi == 0;
    return [if (!forced) 0, for (var b = hi + 1; b <= gardeContre; b++) b];
  }

  @override
  String bidLabel(int bid, String lang) => switch (bid) {
        0 => Strings.tx(lang, 'Pas', 'Pass'),
        petite => kt(lang, 'petite'),
        garde => kt(lang, 'garde'),
        gardeSans => kt(lang, 'gardeSans'),
        _ => kt(lang, 'gardeContre'),
      };

  static double handValue(List<KCard> h) {
    var v = 0.0;
    for (final c in h) {
      if (isOudler(c)) {
        v += c == kTarotTrump + 1 ? 1.5 : 3;
      } else if (isTarotTrump(c)) {
        v += tarotTrumpNo(c) >= 16 ? 1.3 : 0.8;
      } else if (!isTarotKnight(c) && rankOf(c) == 13) {
        v += 1.4;
      } else if (!isTarotKnight(c) && rankOf(c) == 12) {
        v += 0.5;
      }
    }
    // Kısa renk (kesme şansı)
    for (var su = 0; su < 4; su++) {
      final n = h.where((c) => !isTarotTrump(c) && c != kTarotExcuse && (isTarotKnight(c) ? c - kTarotKnight : suitOf(c)) == su).length;
      if (n == 0) v += 1.2;
      if (n == 1) v += 0.5;
    }
    return v;
  }

  @override
  int aiBid(TrickState s, int seat, SeededRandom r) {
    final v = handValue(s.hands[seat]) + (r.nextInt(3) - 1) * 0.4;
    final want = v >= 24 ? gardeContre : (v >= 20 ? gardeSans : (v >= 15 ? garde : (v >= 11.5 ? petite : 0)));
    final legal = legalBids(s, seat);
    if (legal.contains(want)) return want;
    return legal.first == 0 ? 0 : legal.first;
  }

  @override
  void finishBidding(TrickState s) {
    var best = s.dealer, bestBid = 0;
    for (var k = 0; k < seats; k++) {
      final p = (s.dealer + 1 + k) % seats;
      final b = s.bids[p] ?? 0;
      if (b > bestBid) {
        bestBid = b;
        best = p;
      }
    }
    s.declarer = best;
    s.contract = bestBid == 0 ? petite : bestBid;
    s.trump = kVirtualTrump;
    if (s.contract <= garde) {
      // Köpeği al, en uygun 6 kartı göm (koz, Papaz ve anahtar kart gömülmez).
      final h = s.hands[best]..addAll(s.kitty);
      s.kitty.clear();
      final cand = h.where((c) => !isTarotTrump(c) && c != kTarotExcuse && !(rankOf(c) == 13 && !isTarotKnight(c))).toList();
      int suitLen(KCard c) => h.where((x) => !isTarotTrump(x) && x != kTarotExcuse && effSuit(s, x) == effSuit(s, c)).length;
      cand.sort((a, b) {
        // Önce kısa renkleri boşalt, sonra düşük kartlar.
        final la = suitLen(a), lb = suitLen(b);
        if (la != lb) return la.compareTo(lb);
        return strength(a).compareTo(strength(b));
      });
      final out = cand.take(6).toList();
      if (out.length < 6) {
        final more = h.where((c) => !out.contains(c) && !isOudler(c) && !(rankOf(c) == 13 && !isTarotKnight(c) && !isTarotTrump(c))).toList()
          ..sort((a, b) => strength(a).compareTo(strength(b)));
        out.addAll(more.take(6 - out.length));
      }
      for (final c in out) {
        h.remove(c);
        s.taken[best].add(c);
      }
    } else if (s.contract == gardeSans) {
      s.taken[best].addAll(s.kitty);
      s.kitty.clear();
    } else {
      s.taken[(best + 1) % seats].addAll(s.kitty);
      s.kitty.clear();
    }
    startPlay(s);
  }

  @override
  bool teammates(TrickState s, int a, int b) => a == b || (s.declarer >= 0 && a != s.declarer && b != s.declarer);

  int takerPoints2(TrickState s) => s.declarer < 0 ? 0 : s.taken[s.declarer].fold<int>(0, (a, c) => a + tarotPoints2(c));
  int takerOudlers(TrickState s) => s.declarer < 0 ? 0 : s.taken[s.declarer].where(isOudler).length;
  int need2(TrickState s) => _need2[takerOudlers(s).clamp(0, 3)];

  @override
  List<int> handScores(TrickState s) {
    final d = s.declarer;
    if (d < 0) return List.filled(seats, 0);
    final diff = takerPoints2(s) - need2(s);
    final won = diff >= 0;
    final v = (50 + diff.abs()) * _mult[s.contract.clamp(1, 4)];
    return [for (var i = 0; i < seats; i++) (i == d) == won ? v : -v];
  }

  static String half(int p2) => p2.isEven ? '${p2 ~/ 2}' : '${p2 ~/ 2}.5';

  @override
  String status(TrickState s, String lang) {
    if (s.phase == TrickPhase.bidding || s.declarer < 0) return '';
    return '${bidLabel(s.contract, lang)}  ·  ${kt(lang, 'declarer')}: ${half(takerPoints2(s))} / '
        '${kt(lang, 'need')} ${half(need2(s))}  ·  ${kt(lang, 'oudlers')}: ${takerOudlers(s)}';
  }
}

