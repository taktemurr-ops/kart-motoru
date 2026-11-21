import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'cards.dart';
import 'kart_texts.dart';
import 'rummy.dart' show kMeldsLabel;
import 'table_engine.dart';
import 'table_games2.dart' show rankName;

/// Kanasta ailesi (Kanasta, El ve Ayak): iki deste, ikiler joker. Perler aynı
/// sayıdaki kartlardan oluşur (en az 2 doğal, joker doğaldan az, en çok 3).
/// 7 kartlık per "kanasta"dır: jokersiz 500, jokerli 300 puan. Desteden iki
/// kart çekilir; atık destesinin üstündeki kartla iki doğal kartın varsa bütün
/// atığı alabilirsin. İlk açılış en az 50 puan olmalı.
///
/// El ve Ayak: herkesin bir "el"i ve kapalı bir "ayak"ı vardır; el bitince
/// ayak alınır. Bitmek için ayağı almış ve iki kanasta yapmış olmalısın.
class CanastaRules extends TableRules {
  final bool handAndFoot;
  const CanastaRules({this.handAndFoot = false});

  @override
  int get seats => 2;
  @override
  List<KCard> deck() => buildDeck(decks: 2);

  static const _wild = 2;
  static const _meldBase = 4; // piles[4 + p*14 + rank]
  static int meldIx(int p, int rank) => _meldBase + p * 14 + rank;
  static int footIx(int p) => _meldBase + 28 + p;

  static const _footLabel = [
    'Ayak', 'Foot', 'Fuß', 'Pie', 'Pied', 'القدم', 'پا', 'רגל', 'پاؤں', 'Нога', 'Нога', 'Stopa', 'Noha', 'Picior', 'Láb', 'Πόδι',
    'Piede', 'Pé', 'Voet', 'Fot', 'Fod', 'Fot', 'Jalka', '足', '발', '脚', 'पैर', 'পা', 'Kaki', 'Kaki', 'เท้า', 'Chân', 'Paa',
  ];
  static const _rivalMelds = [
    'Rakibin perleri', 'Rival\'s melds', 'Meldungen des Gegners', 'Combinaciones del rival', 'Combinaisons adverses', 'تشكيلات الخصم',
    'دست‌های حریف', 'צירופי היריב', 'مخالف کے ملاپ', 'Комбинации соперника', 'Комбінації суперника', 'Układy rywala', 'Kombinace soupeře',
    'Combinațiile adversarului', 'Az ellenfél kombinációi', 'Συνδυασμοί αντιπάλου', 'Combinazioni avversarie', 'Combinações do rival',
    'Combinaties van tegenstander', 'Motståndarens kombinationer', 'Modstanderens kombinationer', 'Motstanderens kombinasjoner',
    'Vastustajan yhdistelmät', '相手の役', '상대의 조합', '对手的组合', 'प्रतिद्वंद्वी के संयोजन', 'প্রতিপক্ষের সংযোগ', 'Kombinasi lawan',
    'Kombinasi lawan', 'ชุดไพ่ของคู่แข่ง', 'Bộ bài đối thủ', 'Mga meld ng kalaban',
  ];

  @override
  List<PileView> get pileViews => const [
        PileView('Deste', 'Stock', faceUp: false),
        PileView('Atık', 'Discard'),
        PileView('Perler', 'Melds', spread: true, maxShown: 48, labels: kMeldsLabel),
        PileView('Rakip', 'Rival', spread: true, maxShown: 48, labels: _rivalMelds),
      ];

  @override
  Set<int> get hiddenPiles => {0, if (handAndFoot) ...[footIx(0), footIx(1)]};

  static int value(KCard c) {
    final r = rankOf(c);
    if (r == 1 || r == _wild) return 20;
    if (r >= 8) return 10;
    return 5;
  }

  static bool isWild(KCard c) => rankOf(c) == _wild;

  @override
  TableState deal(List<KCard> shuffled, int dealer) {
    final deck = List.of(shuffled);
    final n = handAndFoot ? 11 : 13;
    final hands = [<KCard>[], <KCard>[]];
    final feet = [<KCard>[], <KCard>[]];
    for (var r = 0; r < n; r++) {
      for (var p = 0; p < 2; p++) {
        hands[p].add(deck.removeLast());
        if (handAndFoot) feet[p].add(deck.removeLast());
      }
    }
    for (final h in hands) {
      _sort(h);
    }
    final piles = <List<KCard>>[deck, [deck.removeLast()], [], [], for (var i = 0; i < 28; i++) <KCard>[], feet[0], feet[1]];
    return TableState(seats: 2, hands: hands, piles: piles, turn: (dealer + 1) % 2);
  }

  void _sort(List<KCard> h) => h.sort((a, b) => (rankOf(a) * 10 + suitOf(a)).compareTo(rankOf(b) * 10 + suitOf(b)));

  bool opened(TableState s, int p) => (s.vars[1] >> p) & 1 == 1;
  bool footTaken(TableState s, int p) => (s.vars[2] >> p) & 1 == 1;

  List<KCard> meld(TableState s, int p, int rank) => s.piles[meldIx(p, rank)];
  int naturals(List<KCard> m) => m.where((c) => !isWild(c)).length;
  int wilds(List<KCard> m) => m.where(isWild).length;
  bool okMeld(int nat, int wild) => nat >= 2 && wild <= 3 && wild < nat && nat + wild >= 3;

  int canastas(TableState s, int p) {
    var n = 0;
    for (var r = 1; r <= 13; r++) {
      if (meld(s, p, r).length >= 7) n++;
    }
    return n;
  }

  bool canGoOut(TableState s, int p) => handAndFoot ? footTaken(s, p) && canastas(s, p) >= 2 : canastas(s, p) >= 1;

  int openMin(TableState s, int p) => 50;

  /// Açılış: elde en az 3 (ya da jokerle tamamlanabilen 2) doğal kartı olan
  /// bütün sayılar; toplam en az 50 puan.
  List<KCard>? openingCards(TableState s, int p, {KCard? extra}) {
    final h = [...s.hands[p], if (extra != null) extra];
    final wildsLeft = h.where(isWild).toList();
    final out = <KCard>[];
    final byRank = <int, List<KCard>>{};
    for (final c in h) {
      if (!isWild(c)) byRank.putIfAbsent(rankOf(c), () => []).add(c);
    }
    for (final e in byRank.entries) {
      final nat = e.value;
      if (nat.length >= 3) {
        out.addAll(nat);
      } else if (nat.length == 2 && wildsLeft.isNotEmpty) {
        out
          ..addAll(nat)
          ..add(wildsLeft.removeLast());
      }
    }
    if (out.isEmpty) return null;
    final v = out.fold<int>(0, (a, c) => a + value(c));
    if (v < openMin(s, p)) return null;
    // Elde en az bir kart kalmalı (ya da bitmeye izin olmalı)
    if (out.length >= h.length && !canGoOut(s, p)) return null;
    return out;
  }

  bool canTakePile(TableState s, int p) {
    if (s.piles[1].isEmpty) return false;
    final top = s.piles[1].last;
    if (isWild(top)) return false;
    final r = rankOf(top);
    final nat = s.hands[p].where((c) => rankOf(c) == r).length;
    if (opened(s, p)) return nat >= 2 || (meld(s, p, r).isNotEmpty && nat >= 1);
    return nat >= 2 && openingCards(s, p, extra: top) != null;
  }

  @override
  List<TAction> legalActions(TableState s) {
    final p = s.turn;
    final h = s.hands[p];
    if (s.vars[0] == 0) {
      return [const TAction(1, [], 0), if (canTakePile(s, p)) const TAction(1, [], 1)];
    }
    final out = <TAction>[];
    final remaining = h.length;
    bool leaves(int used) => remaining - used > 0 || canGoOut(s, p);
    if (!opened(s, p)) {
      final o = openingCards(s, p);
      if (o != null) out.add(TAction(5, o));
    } else {
      final byRank = <int, List<KCard>>{};
      for (final c in h) {
        if (!isWild(c)) byRank.putIfAbsent(rankOf(c), () => []).add(c);
      }
      final ws = h.where(isWild).toList();
      for (final e in byRank.entries) {
        final m = meld(s, p, e.key);
        if (m.isEmpty) {
          for (var w = 0; w <= ws.length && w <= 3; w++) {
            if (okMeld(e.value.length, w) && leaves(e.value.length + w)) out.add(TAction(2, [...e.value, ...ws.take(w)]));
          }
        } else if (leaves(1)) {
          out.add(TAction(3, [e.value.first], e.key));
        }
      }
      if (ws.isNotEmpty && leaves(1)) {
        for (var r = 1; r <= 13; r++) {
          final m = meld(s, p, r);
          if (m.isNotEmpty && okMeld(naturals(m), wilds(m) + 1)) out.add(TAction(3, [ws.first], r));
        }
      }
    }
    for (final c in h) {
      if (h.length > 1 || canGoOut(s, p) || (handAndFoot && !footTaken(s, p))) out.add(TAction(0, [c]));
    }
    if (out.isEmpty && h.isNotEmpty) out.add(TAction(0, [h.first]));
    return out;
  }

  void _refresh(TableState s) {
    for (var p = 0; p < 2; p++) {
      s.piles[2 + p]
        ..clear()
        ..addAll([for (var r = 1; r <= 13; r++) ...meld(s, p, r)]);
    }
  }

  void _addToMelds(TableState s, int p, List<KCard> cards) {
    // Doğallar kendi sayısına; jokerler en çok doğalı olan uygun pere
    for (final c in cards.where((c) => !isWild(c))) {
      meld(s, p, rankOf(c)).add(c);
    }
    for (final w in cards.where(isWild)) {
      var best = -1;
      for (var r = 1; r <= 13; r++) {
        final m = meld(s, p, r);
        if (m.isNotEmpty && okMeld(naturals(m), wilds(m) + 1) && (best < 0 || naturals(m) > naturals(meld(s, p, best)))) best = r;
      }
      if (best >= 0) meld(s, p, best).add(w);
    }
    _refresh(s);
  }

  @override
  void apply(TableState s, TAction a) {
    final p = s.turn;
    final h = s.hands[p];
    s.lastSeat = p;
    s.last = a;
    switch (a.kind) {
      case 1:
        if (a.target == 1) {
          final top = s.piles[1].removeLast();
          final r = rankOf(top);
          final rest = List.of(s.piles[1]);
          s.piles[1].clear();
          if (!opened(s, p)) {
            final o = openingCards(s, p, extra: top)!;
            for (final c in o) {
              if (c != top) h.remove(c);
            }
            _addToMelds(s, p, o);
            s.vars[1] |= 1 << p;
          } else {
            final nat = h.where((c) => rankOf(c) == r).take(meld(s, p, r).isEmpty ? 2 : 1).toList();
            for (final c in nat) {
              h.remove(c);
            }
            _addToMelds(s, p, [top, ...nat]);
          }
          h.addAll(rest);
        } else {
          for (var k = 0; k < 2; k++) {
            if (s.piles[0].isEmpty) _reshuffle(s);
            if (s.over) return;
            if (s.piles[0].isNotEmpty) h.add(s.piles[0].removeLast());
          }
        }
        _sort(h);
        s.vars[0] = 1;
      case 5:
        for (final c in a.cards) {
          h.remove(c);
        }
        _addToMelds(s, p, a.cards);
        s.vars[1] |= 1 << p;
      case 2:
        for (final c in a.cards) {
          h.remove(c);
        }
        _addToMelds(s, p, a.cards);
      case 3:
        h.remove(a.cards.first);
        meld(s, p, a.target).add(a.cards.first);
        _refresh(s);
      case 0:
        h.remove(a.cards.first);
        s.piles[1].add(a.cards.first);
        s.vars[0] = 0;
        s.turn = 1 - p;
    }
    if (h.isEmpty) {
      if (handAndFoot && !footTaken(s, p)) {
        h.addAll(s.piles[footIx(p)]);
        s.piles[footIx(p)].clear();
        s.vars[2] |= 1 << p;
        _sort(h);
      } else if (canGoOut(s, p)) {
        _finish(s, p);
      }
    }
  }

  void _reshuffle(TableState s) {
    if (s.vars[3] >= 1 || s.piles[1].length < 4) {
      _finish(s, -1);
      return;
    }
    s.vars[3]++;
    final top = s.piles[1].removeLast();
    s.piles[0].addAll(s.piles[1].reversed);
    s.piles[1]
      ..clear()
      ..add(top);
  }

  List<int> points(TableState s) => [
        for (var p = 0; p < 2; p++)
          [
            for (var r = 1; r <= 13; r++)
              () {
                final m = meld(s, p, r);
                final base = m.fold<int>(0, (a, c) => a + value(c));
                if (m.length >= 7) return base + (wilds(m) == 0 ? 500 : 300);
                return base;
              }(),
          ].fold<int>(0, (a, b) => a + b) -
              s.hands[p].fold<int>(0, (a, c) => a + value(c)) -
              (handAndFoot ? s.piles[footIx(p)].fold<int>(0, (a, c) => a + value(c)) : 0) +
              (s.over && s.vars[4] == p + 1 ? 100 : 0),
      ];

  void _finish(TableState s, int winner) {
    s.over = true;
    s.vars[4] = winner + 1;
    final pt = points(s);
    s.scores[0] = pt[0];
    s.scores[1] = pt[1];
  }

  @override
  List<int> finalScores(TableState s) => s.over ? s.scores : points(s);

  @override
  String actionLabel(TAction a, String lang) => switch (a.kind) {
        1 => a.target == 0 ? kt(lang, 'drawStock') : Strings.tx(lang, 'Atıktan al', 'Take discard'),
        5 => '${kt(lang, 'meld')} ✓',
        2 => a.cards.map((c) => rankName(rankOf(c), lang)).join(' '),
        3 => '${rankName(rankOf(a.cards.first), lang)} → ${rankName(a.target, lang)}',
        _ => '${Strings.tx(lang, 'Atık', 'Discard')}: ${rankName(rankOf(a.cards.first), lang)}',
      };

  @override
  bool isCardPlay(TAction a) => a.kind == 0;

  @override
  TAction quick(TableState s, SeededRandom r) {
    final l = legalActions(s);
    if (s.vars[0] == 0) {
      if (l.length > 1 && s.piles[1].length >= 2) return l[1];
      return l.first;
    }
    for (final k in [5, 2, 3]) {
      final c = l.where((a) => a.kind == k).toList();
      if (c.isNotEmpty) return c[r.nextInt(c.length)];
    }
    // Tek kalan, değeri düşük kartları at; jokerleri tutma
    final h = s.hands[s.turn];
    final counts = <int, int>{};
    for (final c in h) {
      counts[rankOf(c)] = (counts[rankOf(c)] ?? 0) + 1;
    }
    final disc = l.where((a) => a.kind == 0).toList()
      ..sort((a, b) {
        int key(KCard c) => (isWild(c) ? 100 : 0) + counts[rankOf(c)]! * 10 + value(c) ~/ 5;
        return key(a.cards.first).compareTo(key(b.cards.first));
      });
    return disc.isNotEmpty ? disc.first : l.first;
  }

  @override
  String status(TableState s, String lang) {
    final pt = points(s);
    return '${Strings.tx(lang, 'Puan', 'Points')}: ${pt[0]} · ${pt[1]}  ·  ${Strings.tx(lang, 'Deste', 'Stock')}: ${s.piles[0].length}'
        '${handAndFoot ? '  ·  ${Strings.pick(_footLabel, lang)}: ${footTaken(s, 0) ? '✓' : s.piles[footIx(0)].length}' : ''}';
  }
}
