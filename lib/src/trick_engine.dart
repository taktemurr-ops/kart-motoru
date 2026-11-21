import 'dart:convert';

import 'package:studio_core/core/rng.dart';

import 'cards.dart';

/// El alma oyunları (Batak, King, Hearts, Spades, Briç, Belote …) için ortak
/// durum ve kurallar. Koltuk 0 oyuncudur; ortaklıkta 0–2 ve 1–3 eştir.
enum TrickPhase { bidding, play, over }

class TrickState {
  final int seats;
  final List<List<KCard>> hands;
  final List<List<KCard>> taken;
  final List<int> tricks;
  final List<int?> bids;
  final List<KCard> trick = [];
  final List<KCard> kitty;
  final List<Set<int>> voids; // herkesin bildiği: koltuğun hangi renkleri yok
  final List<KCard> played = [];
  final List<int> winners = []; // her elin kazananı, sırayla
  int leader, turn, dealer;
  int trump; // -1: kozsuz
  TrickPhase phase;
  int declarer; // ihaleyi alan (yoksa -1)
  int contract; // ihale değeri / oyun türü (oyuna özel)
  int bidTurns = 0;
  int extra = 0; // oyuna özel (ör. kupa kırıldı mı)
  int lastWinner = -1;

  TrickState({
    required this.seats,
    required this.hands,
    required this.kitty,
    required this.dealer,
    this.trump = -1,
  })  : taken = List.generate(seats, (_) => <KCard>[]),
        tricks = List.filled(seats, 0),
        bids = List.filled(seats, null),
        voids = List.generate(seats, (_) => <int>{}),
        leader = (dealer + 1) % seats,
        turn = (dealer + 1) % seats,
        phase = TrickPhase.bidding,
        declarer = -1,
        contract = 0;

  TrickState copy() {
    final c = TrickState(
      seats: seats,
      hands: [for (final h in hands) List.of(h)],
      kitty: List.of(kitty),
      dealer: dealer,
      trump: trump,
    );
    for (var i = 0; i < seats; i++) {
      c.taken[i].addAll(taken[i]);
      c.tricks[i] = tricks[i];
      c.bids[i] = bids[i];
      c.voids[i].addAll(voids[i]);
    }
    c.trick.addAll(trick);
    c.played.addAll(played);
    c.winners.addAll(winners);
    c
      ..leader = leader
      ..turn = turn
      ..phase = phase
      ..declarer = declarer
      ..contract = contract
      ..bidTurns = bidTurns
      ..extra = extra
      ..lastWinner = lastWinner;
    return c;
  }

  int partnerOf(int seat) => (seat + 2) % seats;

  Map<String, Object?> toJson() => {
        'n': seats,
        'h': hands,
        'k': kitty,
        'tk': taken,
        'tr': tricks,
        'b': bids,
        't': trick,
        'v': [for (final v in voids) v.toList()],
        'p': played,
        'w': winners,
        'x': [leader, turn, dealer, trump, phase.index, declarer, contract, bidTurns, extra, lastWinner],
      };

  static List<KCard> _l(Object? o) => [for (final c in o as List) (c as num).toInt()];

  static TrickState fromJson(Map<String, dynamic> j) {
    final n = (j['n'] as num).toInt();
    final s = TrickState(
      seats: n,
      hands: [for (final h in j['h'] as List) _l(h)],
      kitty: _l(j['k']),
      dealer: 0,
    );
    final tk = j['tk'] as List;
    final b = j['b'] as List;
    final v = j['v'] as List;
    for (var i = 0; i < n; i++) {
      s.taken[i].addAll(_l(tk[i]));
      s.tricks[i] = ((j['tr'] as List)[i] as num).toInt();
      s.bids[i] = (b[i] as num?)?.toInt();
      s.voids[i].addAll(_l(v[i]));
    }
    s.trick.addAll(_l(j['t']));
    s.played.addAll(_l(j['p']));
    if (j['w'] != null) s.winners.addAll(_l(j['w']));
    final x = _l(j['x']);
    s
      ..leader = x[0]
      ..turn = x[1]
      ..dealer = x[2]
      ..trump = x[3]
      ..phase = TrickPhase.values[x[4]]
      ..declarer = x[5]
      ..contract = x[6]
      ..bidTurns = x[7]
      ..extra = x[8]
      ..lastWinner = x[9];
    return s;
  }

  String serialize() => jsonEncode(toJson());
}

/// Bir el alma oyununun kuralları.
abstract class TrickRules {
  const TrickRules();

  int get seats => 4;
  bool get partnerships => false;
  int get handSize => 13;

  List<KCard> deck() => buildDeck();

  /// Elin çıkış sırasındaki gücü (büyük olan alır).
  int strength(KCard c) => rankOf(c) == 1 ? 14 : rankOf(c);

  // ---- dağıtım ----
  TrickState deal(List<KCard> shuffled, int dealer) {
    final hands = List.generate(seats, (_) => <KCard>[]);
    var k = 0;
    for (var r = 0; r < handSize; r++) {
      for (var p = 0; p < seats; p++) {
        hands[(dealer + 1 + p) % seats].add(shuffled[k++]);
      }
    }
    for (final h in hands) {
      sortHand(h, -1);
    }
    final s = TrickState(seats: seats, hands: hands, kitty: shuffled.sublist(k), dealer: dealer);
    setupAfterDeal(s);
    return s;
  }

  /// Dağıtımdan sonra (ör. koz belirleme, ihale yoksa doğrudan oyun).
  void setupAfterDeal(TrickState s) {
    if (!hasBidding) startPlay(s);
  }

  void sortHand(List<KCard> h, int trump) {
    int key(KCard c) {
      final s = suitOf(c);
      final order = trump >= 0 ? (s == trump ? 4 : const [0, 1, 3, 2][s]) : const [0, 1, 3, 2][s];
      return order * 100 + strength(c);
    }

    h.sort((a, b) => key(a).compareTo(key(b)));
  }

  // ---- ihale ----
  bool get hasBidding => false;
  List<int> legalBids(TrickState s, int seat) => const [];
  String bidLabel(int bid, String lang) => '$bid';
  void applyBid(TrickState s, int seat, int bid) {
    s.bids[seat] = bid;
    s.bidTurns++;
    s.turn = (seat + 1) % seats;
  }

  bool biddingOver(TrickState s) => s.bidTurns >= seats;

  /// İhale bitince çağrılır: koz ve ilk eli belirleyip oyuna geçer.
  void finishBidding(TrickState s) => startPlay(s);
  int aiBid(TrickState s, int seat, SeededRandom r) => legalBids(s, seat).first;

  /// İhale bitince: koz, ilk elin sahibi.
  void startPlay(TrickState s) {
    s.phase = TrickPhase.play;
    s.leader = (s.dealer + 1) % seats;
    s.turn = s.leader;
    for (final h in s.hands) {
      sortHand(h, s.trump);
    }
  }

  // ---- oyun ----
  /// Varsayılan: renge uymak zorunlu.
  List<KCard> legalPlays(TrickState s, int seat) {
    final h = s.hands[seat];
    if (s.trick.isEmpty) return leadOptions(s, seat);
    final lead = suitOf(s.trick.first);
    final follow = h.where((c) => suitOf(c) == lead).toList();
    return follow.isNotEmpty ? follow : List.of(h);
  }

  List<KCard> leadOptions(TrickState s, int seat) => List.of(s.hands[seat]);

  /// Masadaki elin kazananı (koltuk).
  int trickWinner(TrickState s) {
    final lead = suitOf(s.trick.first);
    var best = 0;
    for (var i = 1; i < s.trick.length; i++) {
      if (beats(s, s.trick[i], s.trick[best], lead)) best = i;
    }
    return (s.leader + best) % seats;
  }

  bool beats(TrickState s, KCard a, KCard b, int lead) {
    final ta = suitOf(a) == s.trump, tb = suitOf(b) == s.trump;
    if (ta != tb) return ta;
    if (suitOf(a) != suitOf(b)) return false;
    return strength(a) > strength(b);
  }

  void play(TrickState s, int seat, KCard c) {
    if (s.trick.isNotEmpty && suitOf(c) != suitOf(s.trick.first)) {
      s.voids[seat].add(suitOf(s.trick.first));
    }
    s.hands[seat].remove(c);
    s.trick.add(c);
    s.played.add(c);
    onPlay(s, seat, c);
    if (s.trick.length == seats) {
      final w = trickWinner(s);
      s.tricks[w]++;
      s.taken[w].addAll(s.trick);
      s.lastWinner = w;
      s.winners.add(w);
      afterTrick(s, w);
      s.trick.clear();
      s.leader = w;
      s.turn = w;
      if (s.hands.every((h) => h.isEmpty)) {
        s.phase = TrickPhase.over;
        onHandOver(s);
      }
    } else {
      s.turn = (seat + 1) % seats;
    }
  }

  void onPlay(TrickState s, int seat, KCard c) {}
  void afterTrick(TrickState s, int winner) {}
  void onHandOver(TrickState s) {}

  /// El sonu puanları (koltuk başına; büyük olan iyi). Ortaklıkta eşler aynı.
  List<int> handScores(TrickState s);

  /// Yapay zekâ için: bir koltuğun bakış açısından sonucun değeri.
  double utility(TrickState s, int seat) {
    final sc = handScores(s);
    var best = -1 << 30;
    for (var i = 0; i < seats; i++) {
      if (i == seat || (partnerships && i == s.partnerOf(seat))) continue;
      if (sc[i] > best) best = sc[i];
    }
    return (sc[seat] - best).toDouble();
  }

  /// Hearts gibi oyunlarda el almaktan kaçınılır (hızlı politika için).
  bool get avoidTricks => false;
  bool avoidIn(TrickState s) => avoidTricks;

  /// Kartın puan değeri (puanlı oyunlarda; yoksa 0).
  int cardPoints(KCard c) => 0;

  /// El devam ederken ekranda gösterilecek kısa durum (ör. "İhale: 7").
  String status(TrickState s, String lang) => '';
}
