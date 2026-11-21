import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';

import 'memory_engine.dart';

/// Kart hafıza kuralları: 100.000 bölüm.
class MemoryRules extends GameRules<MemoryLevel> {
  @override
  final String gameId;
  MemoryRules({required this.gameId});

  @override
  int get levelCount => 100000;

  @override
  List<String> get optionalMechanics => const [];

  @override
  List<GameModeId> get modes => const [GameModeId.campaign, GameModeId.daily, GameModeId.weekly, GameModeId.challenge];

  @override
  List<GameStat> get gameStats => const [
        GameStat('pairs_found', 'Bulunan eş', 'Pairs found', scale: 100),
        GameStat('sharp_boards', 'Kusursuz tahta', 'Sharp boards', scale: 5),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('pairs', 'pairs_found', [20, 60, 150]),
        MissionTemplate('sharp', 'sharp_boards', [1, 3, 6]),
      ];

  @override
  MemoryLevel generate(LevelSpec spec) => generateMemoryLevel(spec);

  /// Her kart en az bir eşe sahip ve eşleşme sınıfları çift sayıda olmalı:
  /// açgözlü eşleme bütün kartları bitirebiliyorsa bölüm çözülebilir.
  @override
  Validation validate(MemoryLevel level, LevelSpec spec) {
    if (level.cards.length != level.cols * level.rows || level.cards.length.isOdd) {
      return const Validation.fail('size');
    }
    final g = MemoryGame(level);
    while (!g.won) {
      final h = g.hint();
      if (h == null) return const Validation.fail('unpairable');
      g.pick(h.$1);
      if (g.pick(h.$2) != true) return const Validation.fail('hint mismatch');
    }
    return Validation.ok(level.pairs);
  }
}
