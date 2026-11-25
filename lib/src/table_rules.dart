import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'kart_texts.dart';
import 'table_ai.dart';
import 'table_engine.dart';

class TableGoal {
  final bool Function(TableRules r, TableState s) check;
  final String Function(TableRules r, TableState s, String lang) text;
  const TableGoal(this.check, this.text);

  static final win = TableGoal(
    (r, s) => r.utility(s, 0) > 0,
    (r, s, lang) => Strings.tx(lang, 'Oyunu kazan', 'Win the game'),
  );
}

class TableLevel {
  final TableRules rules;
  final TableState start;
  final TableGoal goal;
  final int seed, difficulty, aiSamples;
  const TableLevel(this.rules, this.start, this.goal, this.seed, this.difficulty, this.aiSamples);
}

/// Sıra tabanlı masa oyunlarının bölüm kuralları: bir el, zorlukla güçlenen
/// rakipler; oyuncunun yerine oynayan güçlü yapay zekâ hedefi tutturabiliyorsa
/// bölüm kabul edilir.
class TableGameRules extends GameRules<TableLevel> {
  @override
  final String gameId;
  final TableRules Function(int difficulty) rulesFor;
  final TableGoal Function(int difficulty) goalFor;
  final int levels;

  /// Ağır oyunlarda yapay zekâ deneme sayısını küçültmek için çarpan.
  final double aiScale;

  /// Doğrulamada bütün koltuklar hızlı politikayla oynar (uzun, çok kişilik
  /// taş oyunlarında bölüm üretimini hızlı tutar).
  final bool quickValidate;

  TableGameRules(
      {required this.gameId, required this.rulesFor, TableGoal Function(int)? goalFor, this.levels = 100000, this.aiScale = 1, this.quickValidate = false})
      : goalFor = goalFor ?? ((_) => TableGoal.win);

  @override
  int get levelCount => levels;

  /// Aynı cihazda oynanabilecek en çok kişi (masanın koltuk sayısı).
  @override
  int get localPlayers => rulesFor(1).seats;

  static bool versus(LevelSpec spec) => spec.mode == GameModeId.versus || spec.mode == GameModeId.online;
  @override
  List<String> get optionalMechanics => const [];
  /// Maç modu var mı (çok elli, hedef puanlı oyun).
  bool get hasMatch => rulesFor(1).matchFormat != null;

  @override
  List<GameModeId> get modes => [
        GameModeId.campaign,
        GameModeId.daily,
        GameModeId.weekly,
        GameModeId.challenge,
        if (hasMatch) GameModeId.endless,
      ];

  /// "Sonsuz" mod kartı bu oyunlarda "Maç" olarak görünür.
  @override
  Map<String, List<String>> get strings => hasMatch ? kMatchModeStrings : const {};
  @override
  List<GameStat> get gameStats => const [
        GameStat('cards_won', 'Kazanılan kart', 'Cards won', scale: 200),
        GameStat('games_won', 'Kazanılan oyun', 'Games won', scale: 10),
      ];
  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('cards', 'cards_won', [20, 60, 150]),
        MissionTemplate('games', 'games_won', [1, 3, 6]),
      ];

  static int samplesFor(int d) => const [0, 1, 2, 4, 6, 8, 12, 16, 20, 26][(d - 1).clamp(0, 9)];

  @override
  TableLevel generate(LevelSpec spec) {
    final d = spec.difficulty.clamp(1, 10);
    final rules = rulesFor(d);
    final r = SeededRandom(mixSeed([spec.seed, 3131]));
    final deck = rules.deck();
    shuffleCards(deck, r);
    return TableLevel(rules, rules.deal(deck, r.nextInt(rules.seats)), goalFor(d), spec.seed, d, (samplesFor(d) * aiScale).round());
  }

  static TableState simulate(TableLevel l, {int seat0Samples = 16, int seed = 7, bool quick = false}) {
    final s = l.start.copy();
    final r = SeededRandom(mixSeed([l.seed, seed]));
    final ais = [for (var p = 0; p < s.seats; p++) TableAI(l.rules, quick ? 0 : (p == 0 ? seat0Samples : l.aiSamples), r)];
    var guard = 0;
    while (!s.over && guard++ < 1500) {
      l.rules.apply(s, ais[s.turn].choose(s));
    }
    return s;
  }

  @override
  Validation validate(TableLevel level, LevelSpec spec) {
    if (versus(spec) || spec.mode == GameModeId.endless) return const Validation.ok(0);
    final end = simulate(level, seat0Samples: (16 * aiScale).round().clamp(4, 16), quick: quickValidate);
    if (!end.over) return const Validation.fail('did not finish');
    if (!level.goal.check(level.rules, end)) return const Validation.fail('goal not reached');
    return Validation.ok(end.captured[0].length);
  }

  static int stars({required bool won, required int hints, required int undos}) {
    if (!won) return 0;
    if (hints == 0 && undos == 0) return 3;
    return hints == 0 ? 2 : 1;
  }
}
