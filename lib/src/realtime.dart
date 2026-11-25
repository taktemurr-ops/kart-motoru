import 'dart:math' as math;

import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import 'cards.dart';

/// Hızlı (gerçek zamanlı) kart oyunları: Eşini Yakala (Snap), Hız (Speed),
/// Nertz ve Kemps. Yapay zekânın tepki süresi zorlukla kısalır. Bölüm, hızlı
/// bir oyuncunun (300 ms tepki) yapay zekâyı yenebildiği bir dağıtım olarak
/// kabul edilir.
enum RtKind { snap, speed, nertz, kemps }

class RtLevel {
  final RtKind kind;
  final int seed, difficulty;
  final List<KCard> deck;
  final int aiMs;
  const RtLevel(this.kind, this.seed, this.difficulty, this.deck, this.aiMs);
}

int rtAiMs(int d) => const [1900, 1600, 1350, 1150, 1000, 850, 720, 620, 540, 470][(d - 1).clamp(0, 9)];

/// Bütün hızlı oyunların ortak arayüzü.
///
/// Çevrimdışı: koltuk 0 oyuncu, diğerleri yapay zekâ. Çevrimiçi: ev sahibi
/// oyunu yürütür, her koltuğun eylemi [act] ile uygulanır; bağlı insan
/// oyuncuların koltuklarında [ai] kapatılır, kopan oyuncunun yerine yapay
/// zekâ oynar. Durum [encode]/[decode] ile ağdan gider (devralma dahil).
abstract class RtGame {
  int time = 0;
  bool over = false;

  /// Masadaki koltuk sayısı.
  int get seats => 2;

  /// Yapay zekânın oynadığı koltuklar (çevrimdışı: 0 dışındakiler).
  late final List<bool> ai = [for (var p = 0; p < seats; p++) p != 0];

  /// Çevrimiçi eylem: "S<deste>,<tepki ms>" yakala, "P<kart>" oyna,
  /// "M<kaynak>" taşı, "D" çek, "W<benim>,<orta>" değiş, "K" Kemps!
  /// Geçersiz ya da geç kalmış eylemde false.
  bool act(int p, String a);

  /// Ağ durumu (tamsayılar): devralan cihaz oyunu buradan sürdürür.
  List<int> encode();
  void decode(List<int> v);

  /// Gösterim kopyası için: koltuk [k] 0'a gelecek şekilde döndür.
  void rotate(int k);

  /// Koltuğun puanı ve (bitince) kazanan koltuk (-1 berabere).
  int scoreOf(int p);
  int get winnerSeat;

  /// Oyuncu kazandı mı (bitince).
  bool get playerWon;

  /// [ms] kadar ilerle (yapay zekâ hamleleri dahil).
  void advance(int ms);

  /// Doğrulama için: hızlı bir oyuncunun yapacağı hamle (yoksa false).
  bool botAct();

  /// Gösterim için kısa puan.
  int get playerScore;
  int get aiScore;

  static RtGame create(RtLevel l) => switch (l.kind) {
        RtKind.snap => SnapGame(l),
        RtKind.speed => SpeedGame(l),
        RtKind.nertz => NertzGame(l),
        RtKind.kemps => KempsGame(l),
      };
}

// ======================================================================
// Eşini Yakala (Snap)

class SnapGame extends RtGame {
  final RtLevel level;
  final SeededRandom r;
  final List<List<KCard>> stacks = [[], []];
  final List<KCard> center = [];
  int turn = 0;
  int nextFlipAt = 600;
  bool snapOpen = false;

  /// Koltuk başına yapay zekânın "Yakala!" diyeceği an (-1 yok).
  final aiSnapAt = [-1, -1];
  int flips = 0;
  int lastWinner = -1;

  /// Çevrimiçi: ağ gecikmesini dengeleyen bekleme (ms). İlk basıştan sonra bu
  /// süre içinde gelen basışlar tepki süresine göre sıralanır; 0: hemen.
  int fairMs = 0;
  int openedAt = 0;
  int claimUntil = -1;
  int takenFlip = -1;
  final Map<int, int> claims = {};
  late final int flipMs = 1250 - level.difficulty * 50;
  bool get sandwich => level.difficulty >= 5;
  static const maxFlips = 120;

  SnapGame(this.level) : r = SeededRandom(mixSeed([level.seed, 71])) {
    for (var i = 0; i < level.deck.length; i++) {
      stacks[i % 2].add(level.deck[i]);
    }
  }

  bool _match() {
    final n = center.length;
    if (n >= 2 && rankOf(center[n - 1]) == rankOf(center[n - 2])) return true;
    if (sandwich && n >= 3 && rankOf(center[n - 1]) == rankOf(center[n - 3])) return true;
    return false;
  }

  void _flip() {
    if (stacks[turn].isEmpty) turn = 1 - turn;
    if (stacks[turn].isEmpty) {
      over = true;
      return;
    }
    center.add(stacks[turn].removeLast());
    turn = 1 - turn;
    flips++;
    snapOpen = _match();
    openedAt = time;
    for (var p = 0; p < 2; p++) {
      aiSnapAt[p] = snapOpen && ai[p] ? time + level.aiMs + r.nextInt(level.aiMs ~/ 3 + 1) - level.aiMs ~/ 6 : -1;
    }
    if (flips >= maxFlips) over = true;
  }

  void _take(int p) {
    stacks[p].insertAll(0, center.reversed);
    center.clear();
    snapOpen = false;
    aiSnapAt[0] = -1;
    aiSnapAt[1] = -1;
    claims.clear();
    claimUntil = -1;
    takenFlip = flips;
    lastWinner = p;
    turn = p;
    nextFlipAt = time + flipMs + 300;
  }

  /// Oyuncu "Yakala!" dedi.
  bool snap() => snapBy(0);

  /// Koltuk [p] "Yakala!" dedi.
  bool snapBy(int p) {
    if (over) return false;
    if (snapOpen) {
      _take(p);
      return true;
    }
    // Yanlış yakalama: iki kart rakibe
    for (var k = 0; k < 2 && stacks[p].isNotEmpty; k++) {
      stacks[1 - p].insert(0, stacks[p].removeLast());
    }
    if (stacks[p].isEmpty) over = true;
    return false;
  }

  /// Çevrimiçi basış: [react] kartın görünmesinden basışa kadar geçen süre.
  void claim(int p, int react) {
    if (fairMs <= 0) {
      _take(p);
      return;
    }
    claims[p] = math.min(claims[p] ?? 999999, react);
    if (claimUntil < 0) claimUntil = time + fairMs;
  }

  @override
  bool act(int p, String a) {
    if (over || p < 0 || p > 1 || !a.startsWith('S')) return false;
    final f = a.substring(1).split(',');
    final flip = int.tryParse(f[0]) ?? -1;
    final react = f.length > 1 ? (int.tryParse(f[1]) ?? 0).clamp(0, 5000) : 0;
    // Başka bir deste için ya da deste alındıktan sonra gelen basış: yok sayılır.
    if (flip != flips || takenFlip == flips) return false;
    if (!snapOpen) return snapBy(p);
    claim(p, react);
    return true;
  }

  @override
  void advance(int ms) {
    final end = time + ms;
    while (!over && time < end) {
      time += 10;
      for (var p = 0; p < 2; p++) {
        if (snapOpen && aiSnapAt[p] >= 0 && time >= aiSnapAt[p]) {
          if (fairMs > 0) {
            claim(p, aiSnapAt[p] - openedAt);
            aiSnapAt[p] = -1;
          } else {
            _take(p);
          }
        }
      }
      if (claimUntil >= 0 && time >= claimUntil) {
        var best = -1;
        for (final e in claims.entries) {
          if (best < 0 || e.value < claims[best]! || (e.value == claims[best]! && e.key < best)) best = e.key;
        }
        if (best >= 0 && snapOpen) {
          _take(best);
        } else {
          claims.clear();
          claimUntil = -1;
        }
      }
      if (time >= nextFlipAt && claimUntil < 0) {
        _flip();
        nextFlipAt = time + flipMs;
      }
      if (stacks[0].isEmpty && center.isEmpty || stacks[1].isEmpty && center.isEmpty) over = true;
    }
  }

  int _botAt = -1;
  @override
  bool botAct() {
    if (snapOpen) {
      if (_botAt < 0) _botAt = time + 300;
      if (time >= _botAt) {
        _botAt = -1;
        snap();
        return true;
      }
    } else {
      _botAt = -1;
    }
    return false;
  }

  @override
  int get playerScore => stacks[0].length;
  @override
  int get aiScore => stacks[1].length;
  @override
  bool get playerWon => over && playerScore > aiScore;

  @override
  int scoreOf(int p) => stacks[p].length;
  @override
  int get winnerSeat => stacks[0].length > stacks[1].length ? 0 : (stacks[1].length > stacks[0].length ? 1 : -1);

  @override
  List<int> encode() {
    final w = RtWriter()
      ..i(time)
      ..b(over)
      ..i(turn)
      ..i(nextFlipAt)
      ..b(snapOpen)
      ..i(aiSnapAt[0])
      ..i(aiSnapAt[1])
      ..i(flips)
      ..i(lastWinner)
      ..i(openedAt)
      ..i(claimUntil)
      ..i(takenFlip)
      ..l([for (final e in claims.entries) ...[e.key, e.value]])
      ..l(stacks[0])
      ..l(stacks[1])
      ..l(center);
    return w.out;
  }

  @override
  void decode(List<int> v) {
    final r = RtReader(v);
    time = r.i();
    over = r.b();
    turn = r.i();
    nextFlipAt = r.i();
    snapOpen = r.b();
    aiSnapAt[0] = r.i();
    aiSnapAt[1] = r.i();
    flips = r.i();
    lastWinner = r.i();
    openedAt = r.i();
    claimUntil = r.i();
    takenFlip = r.i();
    final c = r.l();
    claims.clear();
    for (var i = 0; i + 1 < c.length; i += 2) {
      claims[c[i]] = c[i + 1];
    }
    r.into(stacks[0]);
    r.into(stacks[1]);
    r.into(center);
  }

  @override
  void rotate(int k) {
    if (k.isEven) return;
    swapLists(stacks[0], stacks[1]);
    turn = 1 - turn;
    if (lastWinner >= 0) lastWinner = 1 - lastWinner;
    final a = aiSnapAt[0];
    aiSnapAt[0] = aiSnapAt[1];
    aiSnapAt[1] = a;
  }
}

// ======================================================================
// Hız (Speed)

bool speedFits(KCard a, KCard b) {
  final d = (rankOf(a) - rankOf(b)).abs();
  return d == 1 || d == 12;
}

class SpeedGame extends RtGame {
  final RtLevel level;
  final SeededRandom r;
  final hands = [<KCard>[], <KCard>[]];
  final draws = [<KCard>[], <KCard>[]];
  final centers = [<KCard>[], <KCard>[]];
  final sides = [<KCard>[], <KCard>[]];

  /// Koltuk başına yapay zekânın sıradaki hamle anı.
  final aiNext = [0, 0];
  int stallSince = 0;

  SpeedGame(this.level) : r = SeededRandom(mixSeed([level.seed, 72])) {
    final d = List.of(level.deck);
    for (var p = 0; p < 2; p++) {
      for (var i = 0; i < 15; i++) {
        draws[p].add(d.removeLast());
      }
      for (var i = 0; i < 5; i++) {
        hands[p].add(d.removeLast());
      }
    }
    for (var i = 0; i < 5; i++) {
      sides[0].add(d.removeLast());
      sides[1].add(d.removeLast());
    }
    centers[0].add(d.removeLast());
    centers[1].add(d.removeLast());
    aiNext[1] = level.aiMs;
  }

  int? targetFor(KCard c) {
    for (var i = 0; i < 2; i++) {
      if (centers[i].isNotEmpty && speedFits(c, centers[i].last)) return i;
    }
    return null;
  }

  bool _anyMove(int p) => hands[p].any((c) => targetFor(c) != null);

  bool play(int p, KCard c) {
    if (over || !hands[p].contains(c)) return false;
    final t = targetFor(c);
    if (t == null) return false;
    hands[p].remove(c);
    centers[t].add(c);
    if (draws[p].isNotEmpty) hands[p].add(draws[p].removeLast());
    stallSince = time;
    if (hands[p].isEmpty && draws[p].isEmpty) over = true;
    return true;
  }

  void _refresh() {
    for (var i = 0; i < 2; i++) {
      if (sides[i].isEmpty) {
        // Ortadaki kartlar (üsttekiler hariç) karıştırılıp yeniden yan desteye
        final pool = <KCard>[];
        for (final c in centers) {
          if (c.length > 1) pool.addAll(c.sublist(0, c.length - 1));
          if (c.length > 1) c.removeRange(0, c.length - 1);
        }
        shuffleCards(pool, r);
        final half = pool.length ~/ 2;
        sides[0].addAll(pool.sublist(0, half));
        sides[1].addAll(pool.sublist(half));
      }
    }
    for (var i = 0; i < 2; i++) {
      if (sides[i].isNotEmpty) centers[i].add(sides[i].removeLast());
    }
    stallSince = time;
  }

  @override
  void advance(int ms) {
    final end = time + ms;
    while (!over && time < end) {
      time += 10;
      for (var p = 0; p < 2; p++) {
        if (!ai[p] || time < aiNext[p]) continue;
        final opts = hands[p].where((c) => targetFor(c) != null).toList();
        if (opts.isNotEmpty) play(p, opts[r.nextInt(opts.length)]);
        aiNext[p] = time + level.aiMs + r.nextInt(level.aiMs ~/ 2 + 1) - level.aiMs ~/ 4;
      }
      if (!_anyMove(0) && !_anyMove(1) && time - stallSince > 900) _refresh();
      if (time > 240000) over = true;
    }
  }

  int _botNext = 0;
  @override
  bool botAct() {
    if (time < _botNext) return false;
    _botNext = time + 330;
    for (final c in List.of(hands[0])) {
      if (play(0, c)) return true;
    }
    return false;
  }

  @override
  int get playerScore => 20 - hands[0].length - draws[0].length;
  @override
  int get aiScore => 20 - hands[1].length - draws[1].length;
  @override
  bool get playerWon => over && hands[0].isEmpty && draws[0].isEmpty;

  @override
  bool act(int p, String a) {
    if (p < 0 || p > 1 || !a.startsWith('P')) return false;
    final c = int.tryParse(a.substring(1));
    return c != null && play(p, c);
  }

  @override
  int scoreOf(int p) => 20 - hands[p].length - draws[p].length;
  @override
  int get winnerSeat {
    for (var p = 0; p < 2; p++) {
      if (hands[p].isEmpty && draws[p].isEmpty) return p;
    }
    return scoreOf(0) > scoreOf(1) ? 0 : (scoreOf(1) > scoreOf(0) ? 1 : -1);
  }

  @override
  List<int> encode() {
    final w = RtWriter()
      ..i(time)
      ..b(over)
      ..i(stallSince)
      ..i(aiNext[0])
      ..i(aiNext[1]);
    for (final x in [...hands, ...draws, ...centers, ...sides]) {
      w.l(x);
    }
    return w.out;
  }

  @override
  void decode(List<int> v) {
    final r = RtReader(v);
    time = r.i();
    over = r.b();
    stallSince = r.i();
    aiNext[0] = r.i();
    aiNext[1] = r.i();
    for (final x in [...hands, ...draws, ...centers, ...sides]) {
      r.into(x);
    }
  }

  @override
  void rotate(int k) {
    if (k.isEven) return;
    swapLists(hands[0], hands[1]);
    swapLists(draws[0], draws[1]);
  }
}

// ======================================================================
// Nertz

class NertzGame extends RtGame {
  final RtLevel level;
  final SeededRandom r;
  final nertz = [<KCard>[], <KCard>[]];
  final work = [for (var p = 0; p < 2; p++) [for (var i = 0; i < 4; i++) <KCard>[]]];
  final stock = [<KCard>[], <KCard>[]];
  final waste = [<KCard>[], <KCard>[]];
  final foundations = <List<KCard>>[];
  final played = [0, 0];

  /// Koltuk başına yapay zekânın sıradaki hamle anı.
  final aiNext = [0, 0];
  static const timeLimit = 300000;

  NertzGame(this.level) : r = SeededRandom(mixSeed([level.seed, 73])) {
    for (var p = 0; p < 2; p++) {
      final d = p == 0 ? List.of(level.deck) : (buildDeck()..replaceRange(0, 52, [for (final c in buildDeck()) c + 52]));
      if (p == 1) shuffleCards(d, r);
      for (var i = 0; i < 13; i++) {
        nertz[p].add(d.removeLast());
      }
      for (var i = 0; i < 4; i++) {
        work[p][i].add(d.removeLast());
      }
      stock[p].addAll(d);
    }
    aiNext[1] = level.aiMs;
  }

  static int owner(KCard c) => c >= 52 ? 1 : 0;

  int? foundationFor(KCard c) {
    if (rankOf(c) == 1) return -1; // yeni temel
    for (var i = 0; i < foundations.length; i++) {
      final f = foundations[i];
      if (f.isNotEmpty && suitOf(f.last) == suitOf(c) && rankOf(f.last) + 1 == rankOf(c)) return i;
    }
    return null;
  }

  bool fitsWork(KCard c, List<KCard> pile) {
    if (pile.isEmpty) return true;
    final t = pile.last;
    return isRed(t) != isRed(c) && rankOf(t) == rankOf(c) + 1;
  }

  void _toFoundation(int p, KCard c, int f) {
    if (f < 0) {
      foundations.add([c]);
    } else {
      foundations[f].add(c);
    }
    played[p]++;
  }

  /// Kaynaktan (0 nertz, 1 atık, 2..5 çalışma yığını) en iyi yere taşı.
  bool moveFrom(int p, int src) {
    if (over) return false;
    final List<KCard> pile = src == 0 ? nertz[p] : (src == 1 ? waste[p] : work[p][src - 2]);
    if (pile.isEmpty) return false;
    final c = pile.last;
    final f = foundationFor(c);
    if (f != null) {
      pile.removeLast();
      _toFoundation(p, c, f);
      _checkEnd();
      return true;
    }
    for (var i = 0; i < 4; i++) {
      if (src == i + 2) continue;
      final w = work[p][i];
      if (w.isEmpty && src >= 2 && pile.length == 1) continue; // anlamsız taşıma
      if (fitsWork(c, w)) {
        pile.removeLast();
        w.add(c);
        _checkEnd();
        return true;
      }
    }
    return false;
  }

  void draw(int p) {
    if (over) return;
    if (stock[p].isEmpty) {
      stock[p].addAll(waste[p].reversed);
      waste[p].clear();
      // Takılmayı önlemek için bir kart alta
      if (stock[p].length > 1) stock[p].insert(0, stock[p].removeLast());
      return;
    }
    for (var k = 0; k < 3 && stock[p].isNotEmpty; k++) {
      waste[p].add(stock[p].removeLast());
    }
  }

  void _checkEnd() {
    if (nertz[0].isEmpty || nertz[1].isEmpty) over = true;
  }

  bool _greedy(int p) {
    for (final src in [0, 1, 2, 3, 4, 5]) {
      final List<KCard> pile = src == 0 ? nertz[p] : (src == 1 ? waste[p] : work[p][src - 2]);
      if (pile.isNotEmpty && foundationFor(pile.last) != null) return moveFrom(p, src);
    }
    if (nertz[p].isNotEmpty) {
      final c = nertz[p].last;
      for (final w in work[p]) {
        if (fitsWork(c, w)) return moveFrom(p, 0);
      }
    }
    if (waste[p].isNotEmpty) {
      final c = waste[p].last;
      for (final w in work[p]) {
        if (w.isNotEmpty && fitsWork(c, w)) return moveFrom(p, 1);
      }
    }
    draw(p);
    return true;
  }

  @override
  void advance(int ms) {
    final end = time + ms;
    while (!over && time < end) {
      time += 10;
      for (var p = 0; p < 2; p++) {
        if (!ai[p] || time < aiNext[p] || over) continue;
        _greedy(p);
        aiNext[p] = time + (level.aiMs * 0.6).round() + r.nextInt(level.aiMs ~/ 3 + 1);
      }
      if (time >= timeLimit) over = true;
    }
  }

  int _botNext = 0;
  @override
  bool botAct() {
    if (time < _botNext) return false;
    _botNext = time + 300;
    return _greedy(0);
  }

  int score(int p) => played[p] - 2 * nertz[p].length;
  @override
  int get playerScore => score(0);
  @override
  int get aiScore => score(1);
  @override
  bool get playerWon => over && score(0) > score(1);

  @override
  bool act(int p, String a) {
    if (over || p < 0 || p > 1 || a.isEmpty) return false;
    if (a == 'D') {
      draw(p);
      return true;
    }
    if (!a.startsWith('M')) return false;
    final src = int.tryParse(a.substring(1));
    return src != null && src >= 0 && src <= 5 && moveFrom(p, src);
  }

  @override
  int scoreOf(int p) => score(p);
  @override
  int get winnerSeat => score(0) > score(1) ? 0 : (score(1) > score(0) ? 1 : -1);

  @override
  List<int> encode() {
    final w = RtWriter()
      ..i(time)
      ..b(over)
      ..i(aiNext[0])
      ..i(aiNext[1])
      ..i(played[0])
      ..i(played[1]);
    for (var p = 0; p < 2; p++) {
      w
        ..l(nertz[p])
        ..l(stock[p])
        ..l(waste[p]);
      for (final x in work[p]) {
        w.l(x);
      }
    }
    w.i(foundations.length);
    for (final f in foundations) {
      w.l(f);
    }
    return w.out;
  }

  @override
  void decode(List<int> v) {
    final r = RtReader(v);
    time = r.i();
    over = r.b();
    aiNext[0] = r.i();
    aiNext[1] = r.i();
    played[0] = r.i();
    played[1] = r.i();
    for (var p = 0; p < 2; p++) {
      r
        ..into(nertz[p])
        ..into(stock[p])
        ..into(waste[p]);
      for (final x in work[p]) {
        r.into(x);
      }
    }
    final n = r.i().clamp(0, 104);
    foundations
      ..clear()
      ..addAll([for (var i = 0; i < n; i++) r.l()]);
  }

  @override
  void rotate(int k) {
    if (k.isEven) return;
    swapLists(nertz[0], nertz[1]);
    swapLists(stock[0], stock[1]);
    swapLists(waste[0], waste[1]);
    for (var i = 0; i < 4; i++) {
      swapLists(work[0][i], work[1][i]);
    }
    final p0 = played[0];
    played[0] = played[1];
    played[1] = p0;
  }
}

// ======================================================================
// Kemps (dörtlü yakalama yarışı)

class KempsGame extends RtGame {
  final RtLevel level;
  final SeededRandom r;
  static const players = 4;
  final hands = [for (var p = 0; p < 4; p++) <KCard>[]];
  final center = <KCard>[];
  final deck = <KCard>[];
  final discard = <KCard>[];
  int lastSwapAt = 0;
  final aiNextAt = [0, 0, 0, 0];
  final aiDeclareAt = [-1, -1, -1, -1];
  int winner = -1;
  int refreshes = 0;

  KempsGame(this.level) : r = SeededRandom(mixSeed([level.seed, 74])) {
    deck.addAll(level.deck);
    for (var k = 0; k < 4; k++) {
      for (final h in hands) {
        h.add(deck.removeLast());
      }
    }
    _newCenter();
    for (var p = 1; p < 4; p++) {
      aiNextAt[p] = level.aiMs + r.nextInt(level.aiMs);
    }
  }

  void _newCenter() {
    discard.addAll(center);
    center.clear();
    if (deck.length < 4) {
      shuffleCards(discard, r);
      deck.insertAll(0, discard);
      discard.clear();
    }
    for (var k = 0; k < 4 && deck.isNotEmpty; k++) {
      center.add(deck.removeLast());
    }
    lastSwapAt = time;
    refreshes++;
  }

  static bool hasFour(List<KCard> h) => h.length == 4 && h.every((c) => rankOf(c) == rankOf(h.first));

  static int bestRank(List<KCard> h) {
    final cnt = <int, int>{};
    for (final c in h) {
      cnt[rankOf(c)] = (cnt[rankOf(c)] ?? 0) + 1;
    }
    var best = rankOf(h.first), bc = 0;
    cnt.forEach((k, v) {
      if (v > bc) {
        bc = v;
        best = k;
      }
    });
    return best;
  }

  bool swap(int p, KCard mine, KCard mid) {
    if (over || !hands[p].contains(mine) || !center.contains(mid)) return false;
    final i = hands[p].indexOf(mine), j = center.indexOf(mid);
    hands[p][i] = mid;
    center[j] = mine;
    lastSwapAt = time;
    if (ai[p] && hasFour(hands[p]) && aiDeclareAt[p] < 0) {
      aiDeclareAt[p] = time + level.aiMs ~/ 2 + r.nextInt(level.aiMs ~/ 2 + 1);
    }
    return true;
  }

  @override
  int get seats => players;

  /// Oyuncu "Kemps!" dedi.
  bool declare() => declareBy(0);

  /// Koltuk [p] "Kemps!" dedi: dörtlüsü yoksa sıradaki koltuk kazanır.
  bool declareBy(int p) {
    if (over) return false;
    over = true;
    winner = hasFour(hands[p]) ? p : (p + 1) % players;
    return winner == p;
  }

  @override
  bool act(int p, String a) {
    if (over || p < 0 || p >= players || a.isEmpty) return false;
    if (a == 'K') return declareBy(p);
    if (!a.startsWith('W')) return false;
    final f = a.substring(1).split(',');
    if (f.length != 2) return false;
    final mine = int.tryParse(f[0]), mid = int.tryParse(f[1]);
    return mine != null && mid != null && swap(p, mine, mid);
  }

  @override
  int scoreOf(int p) => hands[p].where((c) => rankOf(c) == bestRank(hands[p])).length;
  @override
  int get winnerSeat => winner;

  @override
  List<int> encode() {
    final w = RtWriter()
      ..i(time)
      ..b(over)
      ..i(winner)
      ..i(lastSwapAt)
      ..i(refreshes);
    for (var p = 0; p < players; p++) {
      w
        ..i(aiNextAt[p])
        ..i(aiDeclareAt[p])
        ..l(hands[p]);
    }
    w
      ..l(center)
      ..l(deck)
      ..l(discard);
    return w.out;
  }

  @override
  void decode(List<int> v) {
    final r = RtReader(v);
    time = r.i();
    over = r.b();
    winner = r.i();
    lastSwapAt = r.i();
    refreshes = r.i();
    for (var p = 0; p < players; p++) {
      aiNextAt[p] = r.i();
      aiDeclareAt[p] = r.i();
      r.into(hands[p]);
    }
    r
      ..into(center)
      ..into(deck)
      ..into(discard);
  }

  @override
  void rotate(int k) {
    final m = k % players;
    if (m == 0) return;
    final h = [for (final x in hands) List.of(x)];
    final an = List.of(aiNextAt), ad = List.of(aiDeclareAt);
    for (var i = 0; i < players; i++) {
      final from = (i + m) % players;
      hands[i]
        ..clear()
        ..addAll(h[from]);
      aiNextAt[i] = an[from];
      aiDeclareAt[i] = ad[from];
    }
    if (winner >= 0) winner = (winner - m + players) % players;
  }

  bool _greedySwap(int p) {
    final want = bestRank(hands[p]);
    final mid = center.where((c) => rankOf(c) == want).toList();
    if (mid.isEmpty) return false;
    final give = hands[p].firstWhere((c) => rankOf(c) != want, orElse: () => -1);
    if (give < 0) return false;
    return swap(p, give, mid.first);
  }

  @override
  void advance(int ms) {
    final end = time + ms;
    while (!over && time < end) {
      time += 10;
      for (var p = 0; p < 4; p++) {
        if (!ai[p]) continue;
        if (aiDeclareAt[p] >= 0 && time >= aiDeclareAt[p]) {
          over = true;
          winner = p;
          return;
        }
        if (time >= aiNextAt[p]) {
          _greedySwap(p);
          aiNextAt[p] = time + level.aiMs + r.nextInt(level.aiMs ~/ 2 + 1);
        }
      }
      if (time - lastSwapAt > 1800) _newCenter();
      if (refreshes > 60) over = true;
    }
  }

  int _botNext = 0;
  @override
  bool botAct() {
    if (time < _botNext) return false;
    _botNext = time + 300;
    if (hasFour(hands[0])) {
      declare();
      return true;
    }
    return _greedySwap(0);
  }

  @override
  int get playerScore => hands[0].where((c) => rankOf(c) == bestRank(hands[0])).length;
  @override
  int get aiScore => 0;
  @override
  bool get playerWon => over && winner == 0;
}

// ======================================================================
// Kurallar

class RealtimeRules extends GameRules<RtLevel> {
  @override
  final String gameId;
  final RtKind kind;
  RealtimeRules({required this.gameId, required this.kind});

  @override
  int get levelCount => 100000;
  @override
  List<String> get optionalMechanics => const [];

  /// "Bilgisayara karşı" ve "Çevrimiçi masa": Kemps dört, diğerleri iki kişilik.
  @override
  int get localPlayers => kind == RtKind.kemps ? 4 : 2;
  @override
  List<GameModeId> get modes => const [GameModeId.campaign, GameModeId.daily, GameModeId.weekly, GameModeId.challenge];
  @override
  List<GameStat> get gameStats => const [
        GameStat('quick_wins', 'Hızlı galibiyet', 'Quick wins', scale: 10),
        GameStat('cards_won', 'Kazanılan kart', 'Cards won', scale: 200),
      ];
  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('quick', 'quick_wins', [1, 3, 6]),
        MissionTemplate('cards', 'cards_won', [20, 60, 150]),
      ];

  @override
  RtLevel generate(LevelSpec spec) {
    final d = spec.difficulty.clamp(1, 10);
    final r = SeededRandom(mixSeed([spec.seed, 7070]));
    final deck = buildDeck();
    shuffleCards(deck, r);
    return RtLevel(kind, spec.seed, d, deck, rtAiMs(d));
  }

  /// Hızlı bir oyuncu (300 ms) bu dağıtımı kazanabiliyor mu?
  static bool simulate(RtLevel l) {
    final g = RtGame.create(l);
    var guard = 0;
    while (!g.over && guard++ < 40000) {
      g.botAct();
      g.advance(20);
    }
    return g.playerWon;
  }

  @override
  Validation validate(RtLevel level, LevelSpec spec) =>
      simulate(level) ? const Validation.ok(1) : const Validation.fail('fast player cannot win');

  static int stars(bool won, int margin) {
    if (!won) return 0;
    return margin >= 10 ? 3 : (margin >= 3 ? 2 : 1);
  }
}

// ======================================================================
// Ağ durumu yazımı

/// Tamsayı listesine sırayla yazar (listeler uzunluk önekli).
class RtWriter {
  final out = <int>[];
  void i(int v) => out.add(v);
  void b(bool v) => out.add(v ? 1 : 0);
  void l(List<int> v) {
    out
      ..add(v.length)
      ..addAll(v);
  }
}

/// [RtWriter] çıktısını okur; eksik veride 0 / boş liste döner.
class RtReader {
  final List<int> v;
  int _p = 0;
  RtReader(this.v);
  int i() => _p < v.length ? v[_p++] : 0;
  bool b() => i() != 0;
  List<int> l() {
    final n = i();
    if (n <= 0 || _p + n > v.length) return <int>[];
    final r = v.sublist(_p, _p + n);
    _p += n;
    return r;
  }

  void into(List<int> dst) {
    final x = l();
    dst
      ..clear()
      ..addAll(x);
  }
}

/// İki listenin içeriğini değiştir.
void swapLists(List<int> a, List<int> b) {
  final t = List.of(a);
  a
    ..clear()
    ..addAll(b);
  b
    ..clear()
    ..addAll(t);
}
