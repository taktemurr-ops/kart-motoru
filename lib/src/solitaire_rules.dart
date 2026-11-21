import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import 'cards.dart';
import 'solitaire_engine.dart';

/// Bir solitaire bölümü: kurallar + başlangıç dağıtımı.
class SolLevel {
  final SolitaireVariant variant;
  final SolState start;
  final int seed, difficulty;
  const SolLevel(this.variant, this.start, this.seed, this.difficulty);
}

/// Bütün solitaire oyunlarının ortak bölüm kuralları. Her dağıtım çözücüyle
/// denenir; çözülemeyen ya da çözücünün sınırını aşan dağıtım reddedilir,
/// sıradaki tohumla yenisi kurulur. Böylece her bölümün çözümü vardır.
class SolitaireRules extends GameRules<SolLevel> {
  @override
  final String gameId;
  final SolitaireVariant Function(int difficulty) variantFor;
  final int nodeCap;
  final int levels;

  /// Bazı türlerde (Saat gibi) karar yoktur; çözücü yerine benzetim yeter.
  final bool Function(SolLevel l)? customCheck;

  /// Kendi dağıtımını kuran türler (ör. Saat: yalnızca kazanılan dağıtımlar).
  final SolState Function(SolitaireVariant v, SeededRandom r)? dealOverride;

  SolitaireRules({
    required this.gameId,
    required this.variantFor,
    this.nodeCap = 25000,
    this.levels = 100000,
    this.customCheck,
    this.dealOverride,
  });

  @override
  int get levelCount => levels;

  @override
  List<String> get optionalMechanics => const [];

  @override
  List<GameModeId> get modes => const [GameModeId.campaign, GameModeId.daily, GameModeId.weekly, GameModeId.challenge];

  @override
  List<GameStat> get gameStats => const [
        GameStat('cards_home', 'Yerine giden kart', 'Cards home', scale: 300),
        GameStat('clean_wins', 'İpucusuz galibiyet', 'Wins without hints', scale: 5),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('home', 'cards_home', [60, 150, 400]),
        MissionTemplate('clean', 'clean_wins', [1, 3, 6]),
      ];

  @override
  SolLevel generate(LevelSpec spec) {
    final v = variantFor(spec.difficulty.clamp(1, 10));
    final r = SeededRandom(mixSeed([spec.seed, 52]));
    final o = dealOverride;
    if (o != null) return SolLevel(v, o(v, r), spec.seed, spec.difficulty);
    final deck = v.makeDeck();
    shuffleCards(deck, r);
    return SolLevel(v, v.deal(deck), spec.seed, spec.difficulty);
  }

  @override
  Validation validate(SolLevel level, LevelSpec spec) {
    final c = customCheck;
    if (c != null) return c(level) ? const Validation.ok(1) : const Validation.fail('custom check');
    final r = solveSolitaire(level.variant, level.start, nodeCap: nodeCap);
    if (!r.solved) return Validation.fail(r.exhausted ? 'solver cap' : 'unsolvable');
    return Validation.ok(r.moves!.length);
  }

  /// Hiç hata vermeyen üretim: istenen zorlukta olmazsa zorluğu adım adım
  /// düşürür; en sonda kolay ayarla çok sayıda tohum dener.
  @override
  GeneratedLevel<SolLevel> build(LevelSpec spec, {int maxAttempts = 40}) {
    for (var d = spec.difficulty; d >= 1; d -= 2) {
      final sp = d == spec.difficulty ? spec : spec.copyWith(difficulty: d, seed: mixSeed([spec.seed, d, 77]));
      for (var attempt = 0; attempt < (d == spec.difficulty ? maxAttempts : 15); attempt++) {
        final s = attempt == 0 ? sp : sp.copyWith(seed: mixSeed([sp.seed, attempt, 4049]));
        final p = generate(s);
        final v = validate(p, s);
        if (v.ok) return GeneratedLevel(s, p, v, attempt);
      }
    }
    final easy = spec.copyWith(difficulty: 1, mechanics: const []);
    for (var attempt = 0; attempt < 500; attempt++) {
      final s = easy.copyWith(seed: mixSeed([spec.seed, attempt, 99991]));
      final p = generate(s);
      final v = validate(p, s);
      if (v.ok) return GeneratedLevel(s, p, v, attempt);
    }
    final p = generate(easy);
    return GeneratedLevel(easy, p, const Validation.ok(0), 999);
  }

  static int stars({required bool won, required int hints, required int undos}) {
    if (!won) return 0;
    if (hints == 0 && undos == 0) return 3;
    return hints == 0 ? 2 : 1;
  }
}
