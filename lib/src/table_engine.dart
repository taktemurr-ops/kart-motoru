import 'dart:convert';

import 'package:studio_core/core/rng.dart';

import 'cards.dart';

/// Sıra tabanlı "masa" oyunları (Pişti, Scopa, Renk Eşle, Durak, Başkan,
/// Papaz Kaçtı, Balık Tut, Blöf, 31 …) için ortak durum ve kurallar.
/// Koltuk 0 oyuncudur.

/// Bir hamle. [kind] oyuna özeldir; kartlar ve hedef isteğe bağlı.
class TAction {
  final int kind;
  final List<KCard> cards;
  final int target;
  const TAction(this.kind, [this.cards = const [], this.target = -1]);

  @override
  bool operator ==(Object o) =>
      o is TAction && o.kind == kind && o.target == target && _same(o.cards, cards);
  static bool _same(List<KCard> a, List<KCard> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(kind, target, Object.hashAll(cards));
  List<int> toJson() => [kind, target, ...cards];
  static TAction fromJson(List<dynamic> j) =>
      TAction((j[0] as num).toInt(), [for (final c in j.skip(2)) (c as num).toInt()], (j[1] as num).toInt());
}

class TableState {
  final int seats;
  final List<List<KCard>> hands;
  final List<List<KCard>> piles; // oyuna özel: çekme destesi, atık, masa …
  final List<List<KCard>> captured; // koltuk başına kazanılan kartlar
  final List<int> scores;
  final List<int> vars; // oyuna özel sayaçlar
  int turn;
  bool over = false;
  int lastSeat = -1;
  TAction? last;

  TableState({required this.seats, required this.hands, required this.piles, List<int>? vars, this.turn = 0})
      : captured = List.generate(seats, (_) => <KCard>[]),
        scores = List.filled(seats, 0),
        vars = vars ?? List.filled(8, 0);

  TableState copy() {
    final c = TableState(
      seats: seats,
      hands: [for (final h in hands) List.of(h)],
      piles: [for (final p in piles) List.of(p)],
      vars: List.of(vars),
      turn: turn,
    );
    for (var i = 0; i < seats; i++) {
      c.captured[i].addAll(captured[i]);
      c.scores[i] = scores[i];
    }
    c
      ..over = over
      ..lastSeat = lastSeat
      ..last = last;
    return c;
  }

  String serialize() => jsonEncode({
        'n': seats,
        'h': hands,
        'p': piles,
        'c': captured,
        's': scores,
        'v': vars,
        't': turn,
        'o': over,
        'ls': lastSeat,
        'la': last?.toJson(),
      });

  static List<KCard> _l(Object? o) => [for (final c in o as List) (c as num).toInt()];

  static TableState fromJson(String str) {
    final j = jsonDecode(str) as Map<String, dynamic>;
    final s = TableState(
      seats: (j['n'] as num).toInt(),
      hands: [for (final h in j['h'] as List) _l(h)],
      piles: [for (final p in j['p'] as List) _l(p)],
      vars: _l(j['v']),
      turn: (j['t'] as num).toInt(),
    );
    final c = j['c'] as List;
    for (var i = 0; i < s.seats; i++) {
      s.captured[i].addAll(_l(c[i]));
      s.scores[i] = ((j['s'] as List)[i] as num).toInt();
    }
    s
      ..over = j['o'] == true
      ..lastSeat = (j['ls'] as num).toInt()
      ..last = j['la'] == null ? null : TAction.fromJson(j['la'] as List);
    return s;
  }
}

/// Masada bir yığının nasıl gösterileceği.
class PileView {
  final String trLabel, enLabel;
  final bool faceUp;
  final bool spread; // masadaki kartlar yan yana mı
  final int maxShown; // yan yana gösterilecek en çok kart
  final List<String>? labels; // 33 dilde ad (verilirse trLabel/enLabel yerine)
  const PileView(this.trLabel, this.enLabel, {this.faceUp = true, this.spread = false, this.maxShown = 12, this.labels});
}

abstract class TableRules {
  const TableRules();

  int get seats => 2;
  bool get partnerships => false;
  List<KCard> deck() => buildDeck();
  List<PileView> get pileViews;

  /// Hangi yığınlar herkese kapalı (yapay zekâ bunları tahmin eder).
  Set<int> get hiddenPiles => const {0};

  TableState deal(List<KCard> shuffled, int dealer);

  List<TAction> legalActions(TableState s);
  void apply(TableState s, TAction a);

  /// Sonuç puanları (büyük olan iyi).
  List<int> finalScores(TableState s) => s.scores;

  double utility(TableState s, int seat) {
    final sc = finalScores(s);
    var best = -1 << 30;
    for (var i = 0; i < seats; i++) {
      if (i == seat || (partnerships && i == (seat + 2) % seats)) continue;
      if (sc[i] > best) best = sc[i];
    }
    return (sc[seat] - best).toDouble();
  }

  /// Kartsız ya da çok kartlı hamlelerin düğme yazısı.
  String actionLabel(TAction a, String lang) => '${a.kind}';

  /// Hamle bir karta dokunarak mı yapılır (tek kartlık oyna hamlesi)?
  bool isCardPlay(TAction a) => a.cards.length == 1 && a.kind == 0;

  /// Ekranda kısa durum.
  String status(TableState s, String lang) => '';

  /// Hızlı politika (yapay zekâ benzetimleri için). Varsayılan rastgele.
  TAction quick(TableState s, SeededRandom r) {
    final l = legalActions(s);
    return l[r.nextInt(l.length)];
  }

  /// Rakiplerin elleri kapalıdır; bilinmeyen kartlar her benzetimde yeniden
  /// dağıtılır. Bazı oyunlarda (Balık Tut) bilinen kartlar vardır.
  List<KCard> knownCards(TableState s, int seat) => const [];

  /// Gizli kartlar yeniden dağıtıldıktan sonra türetilmiş bilgileri düzelt.
  void afterDeterminize(TableState w) {}

  /// Koltuk elinin kaç kartının herkesçe görülebildiği (Durak'ta alınan kartlar).
  bool get revealHands => false;
}
