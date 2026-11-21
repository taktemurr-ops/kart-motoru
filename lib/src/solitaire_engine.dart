import 'dart:convert';

import 'cards.dart';

/// Yığın türleri. Görünüm ve çözücü bunlara göre davranır.
enum PileKind { stock, waste, foundation, tableau, cell, reserve, free }

/// Yığının ekrandaki yeri: kart genişliği / yüksekliği biriminde.
enum Fan { none, down, right, rightLast3 }

class PileSpec {
  final PileKind kind;
  final double x, y;
  final Fan fan;
  final String? label;
  final int? suitHint;
  const PileSpec(this.kind, this.x, this.y, {this.fan = Fan.none, this.label, this.suitHint});
}

/// Oyun durumu: yığınlar ve her yığının alttaki kapalı kart sayısı.
class SolState {
  final List<List<KCard>> piles;
  final List<int> down;
  int passes;
  int counter; // oyuna özel sayaç (ör. Spider'da tamamlanan seri)

  SolState(this.piles, this.down, {this.passes = 0, this.counter = 0});

  SolState copy() =>
      SolState([for (final p in piles) List<KCard>.of(p)], List<int>.of(down), passes: passes, counter: counter);

  bool faceUp(int pile, int index) => index >= down[pile];
  KCard? top(int pile) => piles[pile].isEmpty ? null : piles[pile].last;

  String key() {
    final b = StringBuffer();
    for (var i = 0; i < piles.length; i++) {
      b
        ..write(down[i])
        ..write(':')
        ..write(piles[i].join(','))
        ..write('|');
    }
    b
      ..write(passes)
      ..write('/')
      ..write(counter);
    return b.toString();
  }

  Map<String, Object> toJson() => {'p': piles, 'd': down, 's': passes, 'c': counter};

  static SolState fromJson(Map<String, dynamic> j) => SolState(
        [for (final p in j['p'] as List) [for (final c in p as List) (c as num).toInt()]],
        [for (final d in j['d'] as List) (d as num).toInt()],
        passes: (j['s'] as num?)?.toInt() ?? 0,
        counter: (j['c'] as num?)?.toInt() ?? 0,
      );
}

/// Hamle: [from] yığınının [index]. kartından itibaren [to] yığınına.
/// from == -1: deste hamlesi (kart çek / dağıt).
class SolMove {
  final int from, index, to;
  const SolMove(this.from, this.index, this.to);
  const SolMove.stock()
      : from = -1,
        index = 0,
        to = -1;
  bool get isStock => from < 0;
  @override
  bool operator ==(Object o) => o is SolMove && o.from == from && o.index == index && o.to == to;
  @override
  int get hashCode => Object.hash(from, index, to);
  List<int> toJson() => [from, index, to];
  @override
  String toString() => isStock ? 'stock' : '$from[$index]->$to';
}

/// Bir solitaire türünün kuralları.
abstract class SolitaireVariant {
  const SolitaireVariant();

  /// Yerleşim (sıra yığın indekslerini belirler).
  List<PileSpec> get layout;

  /// Tahtanın kart birimindeki genişliği ve (fan hariç) yüksekliği.
  double get boardWidth;
  double get boardHeight;

  List<KCard> makeDeck() => buildDeck();

  SolState deal(List<KCard> shuffled);

  /// Toplam kart sayısı (ilerleme için).
  int get totalCards => makeDeck().length;

  bool canPick(SolState s, int pile, int index);
  bool canDrop(SolState s, int from, int index, int to);

  /// Kartları taşır; ardından [afterMove].
  void move(SolState s, int from, int index, int to) {
    final moving = s.piles[from].sublist(index);
    s.piles[from].removeRange(index, s.piles[from].length);
    s.piles[to].addAll(moving);
    afterMove(s);
  }

  /// Varsayılan: açık kartı kalmayan yığının üstünü çevir.
  void afterMove(SolState s) {
    final l = layout;
    for (var i = 0; i < s.piles.length; i++) {
      final k = l[i].kind;
      if (k != PileKind.tableau && k != PileKind.reserve) continue;
      if (s.down[i] > 0 && s.down[i] >= s.piles[i].length) s.down[i] = s.piles[i].length - 1;
      if (s.down[i] < 0) s.down[i] = 0;
    }
  }

  bool canStock(SolState s) => false;
  void stock(SolState s) {}

  bool isWon(SolState s);

  /// Temele (ya da çıkışa) giden kart sayısı.
  int progress(SolState s);

  /// Hamle önceliği: küçük olan önce denenir (çözücü, ipucu, dokunma).
  int priority(SolState s, SolMove m) => 5;

  /// Çözücüde bariz faydasız hamleleri ele.
  bool useless(SolState s, SolMove m) => false;

  /// Bir kartı dokunarak gönderirken tercih sırası.
  List<int> tapTargets(SolState s, int from, int index) =>
      [for (var t = 0; t < s.piles.length; t++) if (t != from && canDrop(s, from, index, t)) t];

  /// Temel tamamlanabilir mi (kalan her şey açık ve sıralı)?
  bool canAutoFinish(SolState s) => false;

  /// Bütün yasal hamleler (önceliğe göre sıralı).
  List<SolMove> legalMoves(SolState s) {
    final out = <SolMove>[];
    for (var p = 0; p < s.piles.length; p++) {
      final pile = s.piles[p];
      for (var i = 0; i < pile.length; i++) {
        if (!canPick(s, p, i)) continue;
        for (var t = 0; t < s.piles.length; t++) {
          if (t == p) continue;
          if (canDrop(s, p, i, t)) out.add(SolMove(p, i, t));
        }
      }
    }
    if (canStock(s)) out.add(const SolMove.stock());
    out.sort((a, b) => priority(s, a).compareTo(priority(s, b)));
    return out;
  }

  void apply(SolState s, SolMove m) {
    if (m.isStock) {
      stock(s);
      afterMove(s);
    } else {
      move(s, m.from, m.index, m.to);
    }
  }
}

/// Derinlik öncelikli çözücü. Çözüm bulunursa hamle listesi, bulunamazsa
/// null; düğüm sınırı aşılırsa da null ([SolveResult.exhausted] ayırt eder).
class SolveResult {
  final List<SolMove>? moves;
  final bool exhausted;
  final int nodes;
  const SolveResult(this.moves, this.exhausted, this.nodes);
  bool get solved => moves != null;
}

SolveResult solveSolitaire(SolitaireVariant v, SolState start, {int nodeCap = 60000, int maxDepth = 600}) {
  final seen = <String>{};
  var nodes = 0;
  var exhausted = false;
  final path = <SolMove>[];

  bool dfs(SolState s, int depth) {
    if (v.isWon(s)) return true;
    if (++nodes > nodeCap || depth > maxDepth) {
      exhausted = true;
      return false;
    }
    if (!seen.add(s.key())) return false;
    for (final m in v.legalMoves(s)) {
      if (v.useless(s, m)) continue;
      final n = s.copy();
      v.apply(n, m);
      path.add(m);
      if (dfs(n, depth + 1)) return true;
      path.removeLast();
      if (exhausted) return false;
    }
    return false;
  }

  final ok = dfs(start.copy(), 0);
  return SolveResult(ok ? List.of(path) : null, exhausted && !ok, nodes);
}

/// Oyun: durum + geçmiş + sayaçlar.
class SolGame {
  final SolitaireVariant v;
  SolState s;
  int moves = 0;
  final List<String> _history = [];

  // İpucu planı: bulunan çözüm, oyuncu ondan sapmadıkça yeniden çözülmez.
  List<SolMove>? _plan;
  String? _planKey;

  SolGame(this.v, SolState start) : s = start.copy();

  bool get won => v.isWon(s);
  bool get canUndo => _history.isNotEmpty;

  bool play(SolMove m) {
    if (m.isStock) {
      if (!v.canStock(s)) return false;
    } else if (!v.canPick(s, m.from, m.index) || !v.canDrop(s, m.from, m.index, m.to)) {
      return false;
    }
    final before = s.key();
    _history.add(jsonEncode(s.toJson()));
    if (_history.length > 400) _history.removeAt(0);
    v.apply(s, m);
    moves++;
    final plan = _plan;
    if (plan != null && plan.isNotEmpty && _planKey == before && plan.first == m) {
      plan.removeAt(0);
      _planKey = s.key();
    } else {
      _plan = null;
    }
    return true;
  }

  void undo() {
    if (_history.isEmpty) return;
    s = SolState.fromJson(jsonDecode(_history.removeLast()) as Map<String, dynamic>);
    moves++;
    _plan = null;
  }

  bool get stuck => v.legalMoves(s).isEmpty;

  SolMove? hint({int cap = 50000}) {
    final plan = _plan;
    if (plan != null && plan.isNotEmpty && _planKey == s.key()) return plan.first;
    final r = solveSolitaire(v, s, nodeCap: cap);
    if (r.solved && r.moves!.isNotEmpty) {
      _plan = List.of(r.moves!);
      _planKey = s.key();
      return _plan!.first;
    }
    // Çözüm bulunamadıysa en öncelikli yasal hamle.
    final l = v.legalMoves(s).where((m) => !v.useless(s, m)).toList();
    return l.isEmpty ? null : l.first;
  }

  String serialize() => jsonEncode({'s': s.toJson(), 'm': moves});

  static SolGame restore(SolitaireVariant v, SolState start, String snap) {
    final g = SolGame(v, start);
    final j = jsonDecode(snap) as Map<String, dynamic>;
    g.s = SolState.fromJson(j['s'] as Map<String, dynamic>);
    g.moves = (j['m'] as num).toInt();
    return g;
  }
}
