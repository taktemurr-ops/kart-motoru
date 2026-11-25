import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'table_engine.dart';
import 'table_rules.dart';
import 'trick_ai.dart';
import 'trick_engine.dart';
import 'trick_games.dart' show KingRules, estimateTricks, longestSuit;
import 'trick_games5.dart' show TrixRules, kTrixContracts;
import 'trick_rules.dart';
import 'trix.dart' show TrixLayoutRules;

/// Bir maçın (çok elli oyunun) kayıtlı durumu. Bütün eller [seed]'den
/// türetildiği için aynı seçimler ve hamlelerle her cihazda aynı maç oluşur
/// (devam ettirme ve çevrimiçi yeniden oynatma).
class MatchState {
  final int seed;
  final int startDealer;

  /// Dağıtılan el sayısı (herkes pas deyip yeniden dağıtılanlar dahil).
  int dealt = 0;

  /// Sayılan her elin taraf puanları (ortaklıkta 2 taraf, yoksa koltuk başına).
  final List<List<int>> points = [];

  /// Sayılan ellerin seçimi (King/Trix sözleşmesi; yoksa -1) ve seçen koltuk.
  final List<int> choices = [];
  final List<int> choosers = [];

  /// Şu anki elin seçimi (-1: henüz seçilmedi).
  int choice = -1;

  /// Çok oyunculu masada: -1 sorulmadı, 0 tek el, 1 maç.
  int mode = -1;

  int secs = 0;

  MatchState(this.seed, this.startDealer);

  factory MatchState.start(MatchPlan plan, int seed) =>
      MatchState(seed, SeededRandom(mixSeed([seed, 31])).nextInt(plan.seats));

  int get played => points.length;

  List<int> totals(int sides) {
    final t = List<int>.filled(sides, 0);
    for (final p in points) {
      for (var i = 0; i < sides && i < p.length; i++) {
        t[i] += p[i];
      }
    }
    return t;
  }

  Map<String, Object?> toJson() => {
        'seed': seed,
        'sd': startDealer,
        'dealt': dealt,
        'pts': points,
        'ch': choices,
        'cs': choosers,
        'c': choice,
        'm': mode,
        'secs': secs,
      };

  static List<int> _l(Object? o) => [for (final x in (o as List?) ?? const []) (x as num).toInt()];

  static MatchState fromJson(Map<String, dynamic> j) {
    final m = MatchState((j['seed'] as num).toInt(), (j['sd'] as num).toInt());
    m.dealt = (j['dealt'] as num?)?.toInt() ?? 0;
    for (final p in (j['pts'] as List?) ?? const []) {
      m.points.add(_l(p));
    }
    m.choices.addAll(_l(j['ch']));
    m.choosers.addAll(_l(j['cs']));
    m.choice = (j['c'] as num?)?.toInt() ?? -1;
    m.mode = (j['m'] as num?)?.toInt() ?? -1;
    m.secs = (j['secs'] as num?)?.toInt() ?? 0;
    return m;
  }
}

/// Bir oyunun maç planı: eller nasıl dağıtılır, kim sözleşme seçer, el
/// bitince kim kaç puan alır.
abstract class MatchPlan {
  int get seats;
  bool get partnerships;
  MatchFormat get format;

  int get sides => partnerships ? 2 : seats;
  int sideOf(int seat) => partnerships ? seat % 2 : seat;

  /// Bu elin dağıtanı.
  int dealerOf(MatchState m) => (m.startDealer + m.dealt) % seats;

  int dealSeed(MatchState m) => mixSeed([m.seed, m.dealt, 6061]);

  /// Bu elde sözleşmeyi seçen koltuk (-1: seçim yok).
  int chooser(MatchState m) => -1;
  List<int> options(MatchState m) => const [];
  String optionLabel(int option, String lang) => '$option';
  int aiOption(MatchState m, SeededRandom r) => options(m).first;

  /// Seçim ekranında gösterilecek el (seçen koltuğun kartları).
  List<KCard> chooserHand(MatchState m) => const [];

  /// Elin başlangıcı: [TrickLevel] ya da [TableLevel].
  Object level(MatchState m, {int difficulty = 4, int samples = 4, String Function(String lang)? caption});

  /// Bitmiş elin taraf puanları; null: el oynanmadı (yeniden dağıtılır).
  List<int>? score(Object level, Object end);

  /// Elin sonucunu maça yaz.
  void record(MatchState m, List<int>? sidePoints) {
    if (sidePoints != null) {
      m.choosers.add(chooser(m));
      m.points.add(sidePoints);
      m.choices.add(m.choice);
    }
    m.dealt++;
    m.choice = -1;
  }

  /// null: maç sürüyor; -1 berabere; yoksa kazanan taraf.
  int? outcome(MatchState m) => format.outcome(m.totals(sides), m.played);

  List<int> toSides(List<int> seatPoints) =>
      partnerships ? [seatPoints[0], seatPoints[1]] : List.of(seatPoints);

  /// Bölümün kurallarına göre maç planı (maç modu olmayan oyunda null).
  static MatchPlan? of(Object? puzzle) {
    if (puzzle is TrickLevel) {
      final r = puzzle.rules;
      if (r is TrixRules) return TrixMatchPlan();
      if (r is KingRules) return KingMatchPlan(r);
      return r.matchFormat == null ? null : TrickMatchPlan(r);
    }
    if (puzzle is TableLevel) {
      final r = puzzle.rules;
      if (r is TrixLayoutRules) return TrixMatchPlan();
      return r.matchFormat == null ? null : TableMatchPlan(r);
    }
    return null;
  }

  /// Bütün maçı hızlı yapay zekâyla oynat (testler ve denge için).
  static MatchState simulate(MatchPlan plan, int seed, {int maxDeals = 400}) {
    final m = MatchState.start(plan, seed);
    final r = SeededRandom(mixSeed([seed, 5]));
    while (plan.outcome(m) == null && m.dealt < maxDeals) {
      if (plan.chooser(m) >= 0) m.choice = plan.aiOption(m, r);
      final lv = plan.level(m, difficulty: 1, samples: 0);
      final Object end = lv is TrickLevel ? playOut(lv, r) : TableGameRules.simulate(lv as TableLevel, seed: m.dealt, quick: true);
      plan.record(m, plan.score(lv, end));
    }
    return m;
  }

  /// Bir el alma elini sonuna kadar hızlı politikayla oynat.
  static TrickState playOut(TrickLevel l, SeededRandom r) {
    final s = l.start.copy();
    final ai = TrickAI(l.rules, 0, r);
    var guard = 0;
    while (s.phase != TrickPhase.over && guard++ < 800) {
      final seat = s.turn;
      if (s.phase == TrickPhase.bidding) {
        l.rules.applyBid(s, seat, ai.bid(s, seat));
        if (l.rules.biddingOver(s)) l.rules.finishBidding(s);
        continue;
      }
      final a = ai.action(s, seat);
      if (a != null) {
        l.rules.applyPlayAction(s, seat, a);
        continue;
      }
      l.rules.play(s, seat, ai.play(s, seat));
    }
    return s;
  }
}

TrickGoal _trickGoal(String Function(String lang)? caption) =>
    TrickGoal((r, s) => true, (r, s, lang) => caption?.call(lang) ?? '');

TableGoal _tableGoal(String Function(String lang)? caption) =>
    TableGoal((r, s) => true, (r, s, lang) => caption?.call(lang) ?? '');

/// El alma oyunlarının maçı: dağıtan sırayla döner.
class TrickMatchPlan extends MatchPlan {
  final TrickRules base;
  TrickMatchPlan(this.base);

  @override
  int get seats => base.seats;
  @override
  bool get partnerships => base.partnerships;
  @override
  MatchFormat get format => base.matchFormat ?? const MatchFormat(deals: 1);

  TrickRules rulesFor(MatchState m) => base.rulesForDeal(m.played);

  TrickState dealState(MatchState m, TrickRules rules) {
    final deck = rules.deck();
    shuffleCards(deck, SeededRandom(dealSeed(m)));
    final s = rules.deal(deck, dealerOf(m));
    s.matchPlay = true;
    return s;
  }

  @override
  Object level(MatchState m, {int difficulty = 4, int samples = 4, String Function(String lang)? caption}) {
    final rules = rulesFor(m);
    return TrickLevel(rules, dealState(m, rules), _trickGoal(caption), dealSeed(m), difficulty, samples);
  }

  @override
  List<int>? score(Object level, Object end) {
    final l = level as TrickLevel;
    final s = end as TrickState;
    if (l.rules.thrownIn(s)) return null;
    return toSides(l.rules.matchPoints(s));
  }
}

/// King (Türk usulü): 20 el. Seçen sırayla döner ve ilk eli açar; herkes
/// 3 ceza ve 2 koz seçer, her ceza en çok iki kez oynanır. Seçenekler:
/// 0–5 ceza (el, kupa, erkek, kız, son iki, rıfkı), 10+renk koz.
class KingMatchPlan extends TrickMatchPlan {
  KingMatchPlan(KingRules super.base);

  KingRules get king => base as KingRules;

  @override
  MatchFormat get format => const MatchFormat(deals: 20);

  @override
  int chooser(MatchState m) => (m.startDealer + 1 + m.played) % 4;

  @override
  int dealerOf(MatchState m) => (chooser(m) + 3) % 4;

  @override
  List<int> options(MatchState m) {
    final c = chooser(m);
    var koz = 0, ceza = 0;
    final used = List<int>.filled(6, 0);
    for (var i = 0; i < m.choices.length; i++) {
      final o = m.choices[i];
      if (o >= 10) {
        if (m.choosers[i] == c) koz++;
      } else if (o >= 0) {
        used[o]++;
        if (m.choosers[i] == c) ceza++;
      }
    }
    final out = <int>[
      if (ceza < 3)
        for (var t = 0; t < 6; t++)
          if (used[t] < 2) t,
      if (koz < 2)
        for (var su = 0; su < 4; su++) 10 + su,
    ];
    return out.isEmpty ? const [10, 11, 12, 13] : out;
  }

  @override
  String optionLabel(int option, String lang) => option >= 10
      ? '${Strings.tx(lang, 'Koz', 'Trumps')} ${const ['♠', '♥', '♦', '♣'][option - 10]}'
      : king.contractName(option, lang);

  @override
  List<KCard> chooserHand(MatchState m) => dealState(m, base).hands[chooser(m)];

  /// Elin her sözleşmedeki tahmini cezasına göre seç.
  @override
  int aiOption(MatchState m, SeededRandom r) {
    final opts = options(m);
    final h = chooserHand(m);
    int count(bool Function(KCard c) f) => h.where(f).length;
    final hearts = count((c) => suitOf(c) == kHearts);
    final high = count((c) => rankOf(c) == 1 || rankOf(c) >= 12);
    final cost = <int, double>{
      0: high * 50.0,
      1: count((c) => suitOf(c) == kHearts && (rankOf(c) == 1 || rankOf(c) >= 10)) * 30.0 + (hearts > 4 ? 30 : 0),
      2: count((c) => rankOf(c) == 13 || rankOf(c) == 11) * 50.0,
      3: count((c) => rankOf(c) == 12) * 80.0,
      4: high * 25.0,
      5: h.contains(makeCard(13, kHearts)) ? (hearts <= 3 ? 320.0 : 120.0) : 40.0,
    };
    var best = opts.first;
    var bestV = double.infinity;
    for (final o in opts) {
      final double v;
      if (o >= 10) {
        // Koz: beklenen el başına +50 (negatif maliyet).
        v = -estimateTricks(h, o - 10) * 50 - (o - 10 == longestSuit(h) ? 40 : 0) + 120;
      } else {
        v = cost[o]!;
      }
      final noisy = v + r.nextDouble() * 10;
      if (noisy < bestV) {
        bestV = noisy;
        best = o;
      }
    }
    return best;
  }

  @override
  Object level(MatchState m, {int difficulty = 4, int samples = 4, String Function(String lang)? caption}) {
    final s = dealState(m, base);
    final o = m.choice < 0 ? 0 : m.choice;
    king.applyContract(s, o >= 10 ? 6 : o, o >= 10 ? o - 10 : -1);
    return TrickLevel(base, s, _trickGoal(caption), dealSeed(m), difficulty, samples);
  }
}

/// Trix: dört krallık × beş sözleşme. İlk krallık Kupa 7'liyi alanındır,
/// sonra krallık sırayla geçer. Krallığın sahibi her elde kartlarına bakıp
/// kalan sözleşmelerden birini seçer ve ilk eli açar. Seçenekler 0–4
/// ([kTrixContracts]).
class TrixMatchPlan extends MatchPlan {
  @override
  int get seats => 4;
  @override
  bool get partnerships => false;
  @override
  MatchFormat get format => const MatchFormat(deals: 20);

  int firstKing(MatchState m) {
    final deck = buildDeck();
    shuffleCards(deck, SeededRandom(mixSeed([m.seed, 0, 6061])));
    final k = deck.indexOf(makeCard(7, kHearts));
    return (m.startDealer + 1 + k % 4) % 4;
  }

  int kingdom(MatchState m) => m.played ~/ 5;

  @override
  int chooser(MatchState m) => (firstKing(m) + kingdom(m)) % 4;

  @override
  List<int> options(MatchState m) {
    final from = kingdom(m) * 5;
    final used = {for (var i = from; i < m.choices.length; i++) m.choices[i]};
    return [for (var c = 0; c < 5; c++) if (!used.contains(c)) c];
  }

  @override
  String optionLabel(int option, String lang) => Strings.pick(kTrixContracts[option.clamp(0, 4)], lang);

  List<KCard> _deck(MatchState m) {
    final deck = buildDeck();
    shuffleCards(deck, SeededRandom(dealSeed(m)));
    return deck;
  }

  @override
  List<KCard> chooserHand(MatchState m) => const TrixRules(3).deal(_deck(m), dealerOf(m)).hands[chooser(m)];

  /// Elin sözleşmelerdeki tahmini cezası (küçük olan seçilir).
  @override
  int aiOption(MatchState m, SeededRandom r) {
    final opts = options(m);
    final h = chooserHand(m);
    int count(bool Function(KCard c) f) => h.where(f).length;
    final hearts = count((c) => suitOf(c) == kHearts);
    double cost(int c) => switch (c) {
          0 => h.contains(makeCard(13, kHearts)) ? (hearts <= 3 ? 60 : 25) : 8,
          1 => count((c) => rankOf(c) == 12) * 14.0 + count((c) => rankOf(c) == 1 || rankOf(c) == 13) * 4,
          2 => count((c) => suitOf(c) == kDiamonds && (rankOf(c) == 1 || rankOf(c) >= 10)) * 9.0,
          3 => count((c) => rankOf(c) == 1 || rankOf(c) >= 12) * 7.0,
          // Trix: Valeler ve onlara yakın kartlar elini hızlı bitirir.
          _ => 40 - count((c) => rankOf(c) >= 9 && rankOf(c) <= 12) * 5.0,
        };
    var best = opts.first;
    var bestV = double.infinity;
    for (final o in opts) {
      final v = cost(o) + r.nextDouble() * 6;
      if (v < bestV) {
        bestV = v;
        best = o;
      }
    }
    return best;
  }

  @override
  Object level(MatchState m, {int difficulty = 4, int samples = 4, String Function(String lang)? caption}) {
    final c = m.choice < 0 ? options(m).first : m.choice;
    final king = chooser(m);
    if (c == 4) {
      const rules = TrixLayoutRules();
      final s = rules.deal(_deck(m), dealerOf(m));
      s.turn = king;
      return TableLevel(rules, s, _tableGoal(caption), dealSeed(m), difficulty, samples);
    }
    final rules = TrixRules(c, king: king);
    final s = rules.deal(_deck(m), dealerOf(m));
    s.matchPlay = true;
    return TrickLevel(rules, s, _trickGoal(caption), dealSeed(m), difficulty, samples);
  }

  @override
  List<int>? score(Object level, Object end) {
    if (level is TableLevel) return List.of(level.rules.finalScores(end as TableState));
    final l = level as TrickLevel;
    return l.rules.handScores(end as TrickState);
  }
}

/// Masa oyunlarının (Pişti, Scopa, Remi, Kanasta, Cribbage …) maçı.
class TableMatchPlan extends MatchPlan {
  final TableRules base;
  TableMatchPlan(this.base);

  @override
  int get seats => base.seats;
  @override
  bool get partnerships => base.partnerships;
  @override
  MatchFormat get format => base.matchFormat ?? const MatchFormat(deals: 1);

  @override
  Object level(MatchState m, {int difficulty = 4, int samples = 4, String Function(String lang)? caption}) {
    final rules = base.rulesForDeal(m.played);
    final deck = rules.deck();
    shuffleCards(deck, SeededRandom(dealSeed(m)));
    return TableLevel(rules, rules.deal(deck, dealerOf(m)), _tableGoal(caption), dealSeed(m), difficulty, samples);
  }

  @override
  List<int>? score(Object level, Object end) {
    final l = level as TableLevel;
    return toSides(l.rules.matchPoints(end as TableState));
  }
}
