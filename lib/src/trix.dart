import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'kart_texts.dart';
import 'table_engine.dart';
import 'table_rules.dart';
import 'trick_games5.dart';
import 'trick_rules.dart';

/// Trix sözleşmesi (dizme): her renk Vale'den başlayarak yukarı (Kız, Papaz,
/// As) ve aşağı (10 … 2) dizilir. Sıran gelince oynayabileceğin bir kartı
/// koymak zorundasın; yoksa pas. Elini bitirenler sırayla +200, +150, +100,
/// +50 puan alır. piles[renk]: o renkte dizilen kartlar (küçükten büyüğe).
class TrixLayoutRules extends TableRules {
  const TrixLayoutRules();

  static const _sym = ['♠', '♥', '♦', '♣'];
  static const prizes = [200, 150, 100, 50];

  @override
  int get seats => 4;

  @override
  Set<int> get hiddenPiles => const {};

  @override
  List<PileView> get pileViews => [
        for (var i = 0; i < 4; i++) PileView(_sym[i], _sym[i], spread: true, maxShown: 13, labels: List.filled(33, _sym[i])),
      ];

  /// As en büyük: 2 … 14.
  static int value(KCard c) => rankOf(c) == 1 ? 14 : rankOf(c);

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final hands = List.generate(4, (_) => <KCard>[]);
    for (var i = 0; i < 52; i++) {
      hands[(dealer + 1 + i) % 4].add(shuffled[i]);
    }
    for (final h in hands) {
      h.sort((a, b) => (suitOf(a) * 20 + value(a)).compareTo(suitOf(b) * 20 + value(b)));
    }
    return TableState(seats: 4, hands: hands, piles: [<KCard>[], <KCard>[], <KCard>[], <KCard>[]], turn: (dealer + 1) % 4);
  }

  bool playable(TableState s, KCard c) {
    final p = s.piles[suitOf(c)];
    final v = value(c);
    if (p.isEmpty) return v == 11;
    return v == value(p.last) + 1 || v == value(p.first) - 1;
  }

  @override
  List<TAction> legalActions(TableState s) {
    if (s.over) return const [];
    final out = [for (final c in s.hands[s.turn]) if (playable(s, c)) TAction(0, [c])];
    return out.isEmpty ? const [TAction(1)] : out;
  }

  void _next(TableState s) {
    for (var k = 1; k <= 4; k++) {
      final p = (s.turn + k) % 4;
      if (s.hands[p].isNotEmpty) {
        s.turn = p;
        return;
      }
    }
  }

  @override
  void apply(TableState s, TAction a) {
    final seat = s.turn;
    s.lastSeat = seat;
    s.last = a;
    if (a.kind == 0) {
      final c = a.cards.first;
      s.hands[seat].remove(c);
      final p = s.piles[suitOf(c)]
        ..add(c)
        ..sort((x, y) => value(x).compareTo(value(y)));
      assert(p.isNotEmpty);
      if (s.hands[seat].isEmpty) {
        s.scores[seat] = prizes[s.vars[0]];
        s.vars[0]++;
        if (s.vars[0] >= 3) {
          for (var q = 0; q < 4; q++) {
            if (s.hands[q].isNotEmpty) {
              s.scores[q] = prizes[3];
              s.captured[q].addAll(s.hands[q]);
              s.hands[q].clear();
            }
          }
          s.over = true;
          return;
        }
      }
    }
    _next(s);
  }

  /// Hızlı politika: elde devamı olan kartları ve uç kartları önce oyna,
  /// rakiplere yol açan Valeleri sona bırak.
  @override
  TAction quick(TableState s, SeededRandom r) {
    final l = legalActions(s);
    if (l.length == 1) return l.first;
    final h = s.hands[s.turn];
    var best = l.first;
    var bestV = -1e9;
    for (final a in l) {
      final c = a.cards.first;
      final v = value(c);
      var score = 0.0;
      // Kendi elimde bu yönde devam eden kartlar.
      final up = v >= 11;
      for (final o in h) {
        if (suitOf(o) != suitOf(c) || o == c) continue;
        final ov = value(o);
        if (up ? ov > v : ov < v) score += 1;
      }
      if (v == 11) score -= 0.5;
      score += r.nextDouble() * 0.3;
      if (score > bestV) {
        bestV = score;
        best = a;
      }
    }
    return best;
  }

  @override
  String actionLabel(TAction a, String lang) => Strings.tx(lang, 'Pas', 'Pass');

  @override
  String status(TableState s, String lang) => Strings.pick(kTrixContracts[4], lang);
}

const kTrixFirstGoal = [
  'Elini ilk sen bitir', 'Be first to empty your hand', 'Leere als Erster deine Hand', 'Sé el primero en vaciar tu mano',
  'Videz votre main en premier', 'كن أول من يُنهي أوراقه', 'اول دستت را تمام کن', 'היו הראשונים לרוקן את היד',
  'سب سے پہلے اپنے پتے ختم کریں', 'Первым избавьтесь от карт', 'Першим позбудьтеся карт', 'Pozbądź się kart jako pierwszy',
  'Zbav se karet jako první', 'Termină primul cărțile', 'Elsőként tedd le minden lapod', 'Άδειασε πρώτος το χέρι σου',
  'Svuota per primo la mano', 'Seja o primeiro a esvaziar a mão', 'Speel als eerste je hand leeg', 'Bli först av med dina kort',
  'Bliv først af med dine kort', 'Bli først kvitt kortene', 'Pelaa kätesi tyhjäksi ensimmäisenä', '最初に手札をなくそう',
  '가장 먼저 패를 모두 내세요', '第一个出完手牌', 'सबसे पहले अपने पत्ते ख़त्म करें', 'সবার আগে হাতের তাস শেষ করুন',
  'Jadilah yang pertama menghabiskan kartu', 'Jadi yang pertama habiskan kad', 'ลงไพ่ในมือให้หมดก่อนใคร',
  'Hãy là người đầu tiên đánh hết bài', 'Unang ubusin ang iyong baraha',
];

final trixFirstGoal = TableGoal(
  (r, s) => r.utility(s, 0) > 0,
  (r, s, lang) => Strings.pick(kTrixFirstGoal, lang),
);

/// Trix (Levant "krallık" oyunu): her bölüm beş sözleşmeden biri — Kupa
/// Papazı, Kızlar, Karolar, Eller (el alma, cezalı) ya da Trix (dizme).
/// Sözleşme bölümün tohumundan seçilir (çevrimiçide herkeste aynı).
class TrixGameRules extends GameRules<Object> {
  @override
  final String gameId;
  final List<TrickGameRules> trick;
  final TableGameRules layout;

  TrixGameRules({required this.gameId})
      : trick = [
          for (var c = 0; c < 4; c++) TrickGameRules(gameId: gameId, rulesFor: (_) => TrixRules(c), goalFor: (_) => trixAvoidGoal),
        ],
        layout = TableGameRules(gameId: gameId, rulesFor: (_) => const TrixLayoutRules(), goalFor: (_) => trixFirstGoal);

  /// Bölümün sözleşmesi: 0..3 el alma, 4 Trix.
  static int contractOf(LevelSpec spec) => mixSeed([spec.seed, 5151]).abs() % 5;

  @override
  int get levelCount => 100000;

  @override
  int get localPlayers => 4;

  @override
  List<String> get optionalMechanics => const [];

  /// Maç modu: dört krallık × beş sözleşme (krallığın sahibi seçer).
  @override
  List<GameModeId> get modes =>
      const [GameModeId.campaign, GameModeId.daily, GameModeId.weekly, GameModeId.challenge, GameModeId.endless];

  @override
  Map<String, List<String>> get strings => kMatchModeStrings;

  @override
  List<GameStat> get gameStats => const [
        GameStat('tricks_taken', 'Alınan el', 'Tricks taken', scale: 100),
        GameStat('hands_won', 'Kazanılan oyun', 'Hands won', scale: 10),
        GameStat('games_won', 'Kazanılan oyun', 'Games won', scale: 10),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('hands', 'hands_won', [1, 3, 6]),
        MissionTemplate('games', 'games_won', [1, 2, 4]),
      ];

  @override
  Object generate(LevelSpec spec) {
    final c = contractOf(spec);
    return c == 4 ? layout.generate(spec) : trick[c].generate(spec);
  }

  @override
  Validation validate(Object puzzle, LevelSpec spec) {
    if (puzzle is TableLevel) return layout.validate(puzzle, spec);
    final l = puzzle as TrickLevel;
    return trick[(l.rules as TrixRules).contract].validate(l, spec);
  }

  /// Her bölüm kendi türünde üretilir (ekranlar türe göre seçilir).
  @override
  GeneratedLevel<Object> build(LevelSpec spec, {int maxAttempts = 40}) {
    final c = contractOf(spec);
    return c == 4 ? layout.build(spec, maxAttempts: maxAttempts) : trick[c].build(spec, maxAttempts: maxAttempts);
  }
}
