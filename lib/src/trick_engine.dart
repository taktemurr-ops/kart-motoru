import 'dart:convert';

import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

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

  /// Maç modunda oynanan el (ör. herkes pas derse yeniden dağıtılır).
  bool matchPlay = false;

  /// Oyuna özel ek sayaç (ör. 29'da kozu bu elde açtıran koltuk).
  int aux = -1;

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
      ..lastWinner = lastWinner
      ..matchPlay = matchPlay
      ..aux = aux;
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
        'x': [leader, turn, dealer, trump, phase.index, declarer, contract, bidTurns, extra, lastWinner, matchPlay ? 1 : 0, aux],
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
      ..lastWinner = x[9]
      ..matchPlay = x.length > 10 && x[10] == 1
      ..aux = x.length > 11 ? x[11] : -1;
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

  /// İhale düğmelerinin üstündeki soru.
  String bidPrompt(TrickState s, String lang) => Strings.tx(lang, 'İhalen?', 'Your bid?');

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
    final lead = effSuit(s, s.trick.first);
    final follow = h.where((c) => effSuit(s, c) == lead).toList();
    return follow.isNotEmpty ? follow : List.of(h);
  }

  List<KCard> leadOptions(TrickState s, int seat) => List.of(s.hands[seat]);

  /// Masadaki elin kazananı (koltuk).
  int trickWinner(TrickState s) {
    final lead = effSuit(s, s.trick.first);
    var best = 0;
    for (var i = 1; i < s.trick.length; i++) {
      if (beats(s, s.trick[i], s.trick[best], lead)) best = i;
    }
    return (s.leader + best) % seats;
  }

  bool beats(TrickState s, KCard a, KCard b, int lead) {
    final ta = isTrump(s, a), tb = isTrump(s, b);
    if (ta != tb) return ta;
    if (effSuit(s, a) != effSuit(s, b)) return false;
    return strength(a) > strength(b);
  }

  void play(TrickState s, int seat, KCard c) {
    if (s.trick.isNotEmpty && effSuit(s, c) != effSuit(s, s.trick.first)) {
      s.voids[seat].add(effSuit(s, s.trick.first));
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
      if (teammates(s, seat, i)) continue;
      if (sc[i] > best) best = sc[i];
    }
    return (sc[seat] - best).toDouble();
  }

  /// Kartın oyundaki rengi (Euchre'de sol bower, Skat'ta valeler koz rengidir).
  int effSuit(TrickState s, KCard c) => suitOf(c);

  bool isTrump(TrickState s, KCard c) => s.trump >= 0 && effSuit(s, c) == s.trump;

  /// İki koltuk aynı tarafta mı (ihaleyi alan tek başına oynayan oyunlarda değişir).
  bool teammates(TrickState s, int a, int b) => a == b || (partnerships && b == s.partnerOf(a));

  /// Hearts gibi oyunlarda el almaktan kaçınılır (hızlı politika için).
  bool get avoidTricks => false;
  bool avoidIn(TrickState s) => avoidTricks;

  /// Koltuğun eli herkese açık mı (ör. Skat'ta Null Ouvert).
  bool openHand(TrickState s, int seat) => false;

  /// Kartın puan değeri (puanlı oyunlarda; yoksa 0).
  int cardPoints(KCard c) => 0;

  /// El devam ederken ekranda gösterilecek kısa durum (ör. "İhale: 7").
  String status(TrickState s, String lang) => '';

  // ---- oyun sırasında kartsız hamleler (ör. 29'da "koz açtır") ----
  List<int> playActions(TrickState s, int seat) => const [];
  String playActionLabel(int action, String lang) => '$action';
  void applyPlayAction(TrickState s, int seat, int action) {}

  /// Yapay zekânın kartsız hamle kararı (null: kart oyna).
  int? aiPlayAction(TrickState s, int seat, SeededRandom r) => null;

  // ---- maç (çok elli oyun) ----
  /// Maç biçimi (hedef puan ya da el sayısı); null: maç modu yok.
  MatchFormat? get matchFormat => null;

  /// Bitmiş bir elin maç puanları (koltuk başına; ortaklıkta eşler aynı).
  List<int> matchPoints(TrickState s) => handScores(s);

  /// Maçın [deal]. eli için kurallar (ör. Oh Hell'de el büyüklüğü değişir).
  TrickRules rulesForDeal(int deal) => this;

  /// Maçın [deal]. eli için kurallar; [history] o ana kadar sayılan ellerin
  /// taraf puanları (ör. Briç Chicago'da zon, önceki elin kazananı).
  TrickRules rulesForMatch(int deal, List<List<int>> history) => rulesForDeal(deal);

  /// Maç biçiminin oyuna özel kısa yazısı (null: hedef/el sayısı gösterilir).
  String? matchLabel(String lang) => null;

  /// El oynanmadan bitti mi (herkes pas: yeniden dağıtılır).
  bool thrownIn(TrickState s) => s.phase == TrickPhase.over && s.played.isEmpty;
}

/// Bir maçın bitiş koşulu: hedef puan, sabit el sayısı ya da ikisi.
class MatchFormat {
  /// Bu puana ulaşan taraf olunca maç biter (0: yok).
  final int target;

  /// Hedef yoksa oynanacak el sayısı; hedefle birlikte verilirse üst sınır.
  final int deals;

  /// En az puan kazanır (Hearts, Konken …).
  final bool lowWins;

  /// Bu kadar eksiye düşen taraf maçı kaybeder (29: −6).
  final int loseAt;

  /// Başlangıç puanı (Okey: 20). Verilirse toplamlar bu puandan başlar ve
  /// biri sıfıra (ya da altına) düşünce maç biter; en yüksek kazanır.
  final int start;

  const MatchFormat({this.target = 0, this.deals = 0, this.lowWins = false, this.loseAt = 0, this.start = 0});

  /// Toplamlara göre sonuç ([start] dahil): null sürüyor, -1 berabere, yoksa
  /// kazanan taraf.
  int? outcome(List<int> totals, int played) {
    final n = totals.length;
    if (loseAt > 0 && n == 2) {
      final down = [for (var i = 0; i < n; i++) totals[i] <= -loseAt];
      if (down[0] != down[1]) return down[0] ? 1 : 0;
    }
    final open = target > 0 || start > 0;
    final reached = (target > 0 && totals.any((t) => t >= target)) || (start > 0 && totals.any((t) => t <= 0));
    final cap = deals > 0 ? deals : (open ? 200 : 0);
    final done = open ? (reached || played >= cap) : (deals > 0 && played >= deals);
    if (!done) return null;
    var best = 0;
    for (var i = 1; i < n; i++) {
      if (lowWins ? totals[i] < totals[best] : totals[i] > totals[best]) best = i;
    }
    final ties = [for (var i = 0; i < n; i++) if (totals[i] == totals[best]) i].length;
    if (ties > 1) return open && played < cap ? null : -1;
    return best;
  }
}

/// Maç geçmişindeki satırların sütun toplamları.
List<int> sumRows(List<List<int>> rows, int n) {
  final t = List<int>.filled(n, 0);
  for (final r in rows) {
    for (var i = 0; i < n && i < r.length; i++) {
      t[i] += r[i];
    }
  }
  return t;
}

/// Maç geçmişinin son satırında en çok puan alan (tek) taraf; yoksa -1.
int lastRowWinner(List<List<int>> rows) {
  if (rows.isEmpty) return -1;
  final r = rows.last;
  var best = -1;
  for (var i = 0; i < r.length; i++) {
    if (r[i] > 0 && (best < 0 || r[i] > r[best])) best = i;
  }
  if (best >= 0 && r.where((x) => x == r[best]).length > 1) return -1;
  return best;
}
