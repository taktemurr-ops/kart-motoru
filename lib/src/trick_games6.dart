
import 'cards.dart';
import 'trick_engine.dart';

/// Kozların ortak sanal rengi (bu dosyada; Skat'taki ile aynı değer).
const _trump = 4;

/// Doppelkopf: Almanya'nın dört kişilik çift desteli koz oyunu (48 kart:
/// 9, Vale, Kız, Papaz, On, As; her karttan iki tane). Onikişer kart.
/// Kozlar (büyükten küçüğe): kupa Onu, kızlar (♣ ♠ ♥ ♦), valeler (♣ ♠ ♥ ♦),
/// karo As, On, Papaz, Dokuz. Diğer renklerde As, On, Papaz, Dokuz (kupada
/// On koz olduğundan As, Papaz, Dokuz). Aynı iki karttan önce atılan alır.
/// Takımlar gizlidir: iki sinek Kızı elinde olanlar "Re", diğer ikisi
/// "Kontra"dır; kızlar oynandıkça takımlar ortaya çıkar. İki sinek Kızı aynı
/// eldeyse o oyuncu tek başına üç kişiye karşı oynar. Puanlar: As 11, On 10,
/// Papaz 4, Kız 3, Vale 2 (toplam 240). Re 121 ile, Kontra 120 ile kazanır.
/// Oyun değeri 1; kaybeden taraf 90'ın altında kalırsa +1, 60'ın altında +1,
/// 30'un altında +1, hiç el almazsa +1; Kontra kazanırsa +1. Tek başına
/// oynayan üç katını alır ya da verir. Para yok, yalnızca puan listesi.
/// aux: Re oyuncularının bit maskesi.
class DoppelkopfRules extends TrickRules {
  const DoppelkopfRules();

  @override
  int get handSize => 12;

  @override
  MatchFormat get matchFormat => const MatchFormat(deals: 8);

  @override
  List<KCard> deck() => buildDeck(decks: 2, ranks: const [1, 9, 10, 11, 12, 13]);

  static const _suitPow = {kClubs: 4, kSpades: 3, kHearts: 2, kDiamonds: 1};
  static const _plainPow = {1: 14, 10: 13, 13: 12, 9: 9};

  static bool trumpCard(KCard c) {
    final r = rankOf(c), su = suitOf(c);
    return r == 11 || r == 12 || su == kDiamonds || (su == kHearts && r == 10);
  }

  @override
  int strength(KCard c) {
    final r = rankOf(c), su = suitOf(c);
    if (su == kHearts && r == 10) return 100;
    if (r == 12) return 90 + _suitPow[su]!;
    if (r == 11) return 80 + _suitPow[su]!;
    if (su == kDiamonds) return 70 + _plainPow[r]! - 9;
    return _plainPow[r]!;
  }

  @override
  int cardPoints(KCard c) => const {1: 11, 10: 10, 13: 4, 12: 3, 11: 2}[rankOf(c)] ?? 0;

  @override
  int effSuit(TrickState s, KCard c) => trumpCard(c) ? _trump : suitOf(c);

  static bool clubQueen(KCard c) => rankOf(c) == 12 && suitOf(c) == kClubs;

  @override
  void sortHand(List<KCard> h, int trump) {
    int key(KCard c) => trumpCard(c) ? 500 + strength(c) : const [0, 1, 3, 2][suitOf(c)] * 100 + strength(c);
    h.sort((a, b) => key(a).compareTo(key(b)));
  }

  @override
  TrickState deal(List<KCard> shuffled, int dealer) {
    final s = super.deal(shuffled, dealer);
    s.trump = _trump;
    var mask = 0;
    for (var p = 0; p < seats; p++) {
      if (s.hands[p].any(clubQueen)) mask |= 1 << p;
    }
    s.aux = mask;
    // İki sinek Kızı tek elde: o oyuncu tek başına.
    s.declarer = (mask & (mask - 1)) == 0 ? mask.bitLength - 1 : -1;
    return s;
  }

  bool re(TrickState s, int p) => (s.aux >> p) & 1 == 1;

  @override
  bool beats(TrickState s, KCard a, KCard b, int lead) {
    final ta = isTrump(s, a), tb = isTrump(s, b);
    if (ta != tb) return ta;
    if (effSuit(s, a) != effSuit(s, b)) return false;
    return strength(a) > strength(b);
  }

  @override
  bool teammates(TrickState s, int a, int b) => a == b || re(s, a) == re(s, b);

  List<int> points(TrickState s) => [for (final t in s.taken) t.fold<int>(0, (a, c) => a + cardPoints(c))];

  int rePoints(TrickState s) {
    final p = points(s);
    var v = 0;
    for (var i = 0; i < seats; i++) {
      if (re(s, i)) v += p[i];
    }
    return v;
  }

  /// Re'nin kazanıp kazanmadığı ve oyun değeri.
  (bool, int) result(TrickState s) {
    final rp = rePoints(s);
    final reWon = rp >= 121;
    final loser = reWon ? 240 - rp : rp;
    var tricksLoser = 0;
    for (var i = 0; i < seats; i++) {
      if (re(s, i) != reWon) tricksLoser += s.tricks[i];
    }
    var v = 1;
    if (loser < 90) v++;
    if (loser < 60) v++;
    if (loser < 30) v++;
    if (tricksLoser == 0) v++;
    if (!reWon) v++;
    return (reWon, v);
  }

  @override
  List<int> handScores(TrickState s) {
    final (reWon, v) = result(s);
    final solo = s.declarer >= 0;
    return [
      for (var i = 0; i < seats; i++)
        () {
          final win = re(s, i) == reWon;
          final mult = solo && re(s, i) ? 3 : 1;
          return (win ? v : -v) * mult;
        }(),
    ];
  }

  @override
  String status(TrickState s, String lang) {
    final shown = s.played.where(clubQueen).length;
    final team = s.played.length == 48 || shown == 2;
    if (!team) return '♣Q: $shown/2';
    final rp = rePoints(s);
    return 'Re: $rp / 121  ·  Kontra: ${points(s).fold<int>(0, (a, b) => a + b) - rp}';
  }
}
