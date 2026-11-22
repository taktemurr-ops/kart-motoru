import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'trick_ai.dart';
import 'trick_engine.dart';

/// Bölüm hedefi: elin sonunda oyuncunun (koltuk 0) neyi başarması gerektiği.
class TrickGoal {
  final bool Function(TrickRules r, TrickState s) check;
  final String Function(TrickRules r, TrickState s, String lang) text;
  const TrickGoal(this.check, this.text);

  /// Varsayılan: eli kazan (puanın rakiplerin hepsinden yüksek).
  static final win = TrickGoal(
    (r, s) => r.utility(s, 0) > 0,
    (r, s, lang) => Strings.tx(lang, 'Eli kazan', 'Win the hand'),
  );
}

class TrickLevel {
  final TrickRules rules;
  final TrickState start;
  final TrickGoal goal;
  final int seed, difficulty, aiSamples;
  const TrickLevel(this.rules, this.start, this.goal, this.seed, this.difficulty, this.aiSamples);
}

/// Rakipli kart oyunlarının ortak bölüm kuralları: her bölüm bir el; rakip
/// gücü zorlukla artar. Dağıtım, oyuncunun yerine oynayan güçlü yapay zekâ
/// hedefi tutturabiliyorsa kabul edilir; böylece her bölüm kazanılabilir.
class TrickGameRules extends GameRules<TrickLevel> {
  @override
  final String gameId;
  final TrickRules Function(int difficulty) rulesFor;
  final TrickGoal Function(int difficulty) goalFor;
  final int levels;

  TrickGameRules({
    required this.gameId,
    required this.rulesFor,
    TrickGoal Function(int difficulty)? goalFor,
    this.levels = 100000,
  }) : goalFor = goalFor ?? ((_) => TrickGoal.win);

  @override
  int get levelCount => levels;

  /// Aynı cihazda oynanabilecek en çok kişi (masanın koltuk sayısı).
  @override
  int get localPlayers => rulesFor(1).seats;

  @override
  List<String> get optionalMechanics => const [];

  @override
  List<GameModeId> get modes => const [GameModeId.campaign, GameModeId.daily, GameModeId.weekly, GameModeId.challenge];

  @override
  List<GameStat> get gameStats => const [
        GameStat('tricks_taken', 'Alınan el', 'Tricks taken', scale: 100),
        GameStat('hands_won', 'Kazanılan oyun', 'Hands won', scale: 10),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('tricks', 'tricks_taken', [15, 40, 100]),
        MissionTemplate('hands', 'hands_won', [1, 3, 6]),
      ];

  static int samplesFor(int d) => const [0, 2, 4, 6, 10, 14, 20, 26, 34, 44][(d - 1).clamp(0, 9)];

  @override
  TrickLevel generate(LevelSpec spec) {
    final d = spec.difficulty.clamp(1, 10);
    final rules = rulesFor(d);
    final r = SeededRandom(mixSeed([spec.seed, 4242]));
    final deck = rules.deck();
    shuffleCards(deck, r);
    final dealer = r.nextInt(rules.seats);
    return TrickLevel(rules, rules.deal(deck, dealer), goalFor(d), spec.seed, d, samplesFor(d));
  }

  /// Bütün eli yapay zekâyla oynat. [seat0Samples]: oyuncunun yerine.
  static TrickState simulate(TrickLevel l, {int seat0Samples = 30, int seed = 7}) {
    final s = l.start.copy();
    final r = SeededRandom(mixSeed([l.seed, seed]));
    final ais = [
      for (var p = 0; p < s.seats; p++)
        TrickAI(l.rules, p == 0 ? seat0Samples : (l.rules.partnerships && p == 2 ? 16 : l.aiSamples), r),
    ];
    var guard = 0;
    while (s.phase != TrickPhase.over && guard++ < 500) {
      final seat = s.turn;
      if (s.phase == TrickPhase.bidding) {
        l.rules.applyBid(s, seat, ais[seat].bid(s, seat));
        if (l.rules.biddingOver(s)) l.rules.finishBidding(s);
      } else {
        l.rules.play(s, seat, ais[seat].play(s, seat));
      }
    }
    return s;
  }

  @override
  Validation validate(TrickLevel level, LevelSpec spec) {
    if (spec.mode == GameModeId.versus || spec.mode == GameModeId.online) return const Validation.ok(0);
    final end = simulate(level);
    if (end.phase != TrickPhase.over) return const Validation.fail('did not finish');
    if (!level.goal.check(level.rules, end)) return const Validation.fail('goal not reached');
    return Validation.ok(end.tricks[0]);
  }

  static int stars({required bool won, required int hints, required int undos}) {
    if (!won) return 0;
    if (hints == 0 && undos == 0) return 3;
    return hints == 0 ? 2 : 1;
  }
}
