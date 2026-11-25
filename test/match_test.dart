import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  group('maç sonucu', () {
    test('hedef puan: ulaşan en yüksek kazanır, eşitlikte sürer', () {
      const f = MatchFormat(target: 151);
      expect(f.outcome([100, 140], 3), isNull);
      expect(f.outcome([152, 140], 4), 0);
      expect(f.outcome([160, 170], 4), 1);
      expect(f.outcome([160, 160], 4), isNull);
    });

    test('en az puan kazanır (Hearts): biri 100\'e varınca biter', () {
      const f = MatchFormat(target: 100, lowWins: true);
      expect(f.outcome([40, 99, 60, 30], 5), isNull);
      expect(f.outcome([40, 104, 60, 30], 6), 3);
      expect(f.outcome([30, 104, 60, 30], 6), isNull);
    });

    test('sabit el sayısı: sonunda en yüksek, eşitse berabere', () {
      const f = MatchFormat(deals: 20);
      expect(f.outcome([10, 50, -20, 0], 19), isNull);
      expect(f.outcome([10, 50, -20, 0], 20), 1);
      expect(f.outcome([50, 50, -20, 0], 20), -1);
    });

    test('29: +6 kazanır, −6 kaybeder', () {
      const f = MatchFormat(target: 6, loseAt: 6);
      expect(f.outcome([3, -5], 9), isNull);
      expect(f.outcome([6, -2], 9), 0);
      expect(f.outcome([-6, 1], 9), 1);
      expect(f.outcome([2, -6], 9), 0);
    });

    test('durum kaydı aynen geri yüklenir', () {
      final m = MatchState(42, 3)
        ..dealt = 5
        ..choice = 2
        ..mode = 1
        ..secs = 77;
      m.points.addAll([
        [3, 1],
        [0, 2],
      ]);
      m.choices.addAll([-1, -1]);
      m.choosers.addAll([-1, -1]);
      final b = MatchState.fromJson(m.toJson());
      expect(b.toJson(), m.toJson());
      expect(b.totals(2), [3, 3]);
      expect(b.played, 2);
    });
  });

  group('maç modu', () {
    test('maçı olan oyunlar "Maç" mod kartını gösterir', () {
      final batak = TrickGameRules(gameId: 'oyun-batak', rulesFor: (_) => const BatakRules());
      expect(batak.modes, contains(GameModeId.endless));
      expect(batak.strings['mode_endless']![0], 'Maç');
      expect(batak.strings['mode_endless']!.length, 33);
      final durak = TableGameRules(gameId: 'oyun-durak', rulesFor: (_) => const DurakRules());
      expect(durak.modes, isNot(contains(GameModeId.endless)));
      expect(TrixGameRules(gameId: 'oyun-trix').modes, contains(GameModeId.endless));
      final pisti = TableGameRules(gameId: 'oyun-pisti', rulesFor: (_) => const PistiRules());
      final planner = LevelPlanner(gameId: 'oyun-pisti', optionalMechanics: const []);
      final gl = pisti.build(planner.run(GameModeId.endless, 1));
      expect(MatchPlan.of(gl.puzzle), isA<TableMatchPlan>());
    });

    final games = <String, MatchPlan>{
      'hearts': TrickMatchPlan(const HeartsRules()),
      'hokm': TrickMatchPlan(const HokmRules()),
      'tarneeb': TrickMatchPlan(const TarneebRules()),
      'baloot': TrickMatchPlan(const BalootRules()),
      '29': TrickMatchPlan(const TwentyNineRules()),
      'batak': TrickMatchPlan(const BatakRules()),
      'briscola': TrickMatchPlan(const BriscolaRules()),
      'sueca': TrickMatchPlan(const SuecaRules()),
      'euchre': TrickMatchPlan(const EuchreRules()),
      'spades': TrickMatchPlan(const SpadesRules()),
      'pisti': TableMatchPlan(const PistiRules()),
      'scopa': TableMatchPlan(const ScopaRules()),
      'gin': TableMatchPlan(const GinRummyRules()),
    };
    games.forEach((name, plan) {
      test('$name: maç yapay zekâyla sonuna kadar oynanır, puan tablosu tutar', () {
        final a = MatchPlan.simulate(plan, 11);
        final out = plan.outcome(a);
        expect(out, isNotNull, reason: name);
        final f = plan.format;
        final t = a.totals(plan.sides);
        if (out! >= 0 && f.loseAt == 0) {
          for (var i = 0; i < t.length; i++) {
            if (i != out) expect(f.lowWins ? t[out] < t[i] : t[out] > t[i], isTrue, reason: '$name $t');
          }
        }
        if (f.target > 0 && f.loseAt == 0 && a.played < 200) {
          expect(t.any((x) => x >= f.target), isTrue, reason: '$name $t');
        }
        if (f.target == 0) expect(a.played, f.deals, reason: name);
        // Aynı tohum: aynı maç.
        expect(MatchPlan.simulate(plan, 11).toJson(), a.toJson());
      });
    });

    test('dağıtan her elde döner', () {
      final plan = TrickMatchPlan(const BatakRules());
      final m = MatchState.start(plan, 9);
      final first = plan.dealerOf(m);
      final lv = plan.level(m) as TrickLevel;
      expect(lv.start.dealer, first);
      plan.record(m, [1, 2, 3, 4]);
      expect(plan.dealerOf(m), (first + 1) % 4);
      expect(m.totals(4), [1, 2, 3, 4]);
    });

    test('Oh Hell: el büyüklüğü iner ve yeniden çıkar', () {
      final plan = TrickMatchPlan(const OhHellRules(cards: 4));
      expect(plan.format.deals, 7);
      expect([for (var d = 0; d < 7; d++) (const OhHellRules(cards: 4).rulesForDeal(d) as OhHellRules).cards], [4, 3, 2, 1, 2, 3, 4]);
      final m = MatchState.start(plan, 3);
      m.points.addAll([
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]);
      final lv = plan.level(m) as TrickLevel;
      expect(lv.start.hands.every((h) => h.length == 2), isTrue);
    });

    test('Aşamalı Remi: her elin aşaması farklı', () {
      const r = RummyRules(players: 3, handSize: 10, contract: [false, false]);
      expect(r.matchFormat!.deals, 4);
      expect(r.matchFormat!.lowWins, isTrue);
      expect((r.rulesForDeal(3) as RummyRules).contract, [false, false, false]);
      expect((r.rulesForDeal(1) as RummyRules).contract, [false, true]);
    });
  });

  group('King ve Trix maçı', () {
    test('King: 20 el; herkes 3 ceza ve 2 koz seçer, her ceza iki kez', () {
      final plan = KingMatchPlan(const KingRules());
      final m = MatchPlan.simulate(plan, 21);
      expect(m.played, 20);
      expect(plan.outcome(m), isNotNull);
      for (var c = 0; c < 4; c++) {
        final mine = [for (var i = 0; i < 20; i++) if (m.choosers[i] == c) m.choices[i]];
        expect(mine.length, 5);
        expect(mine.where((o) => o >= 10).length, 2);
        expect(mine.where((o) => o < 10).length, 3);
      }
      for (var t = 0; t < 6; t++) {
        expect(m.choices.where((o) => o == t).length, 2);
      }
    });

    test('King: seçilen koz oyunu ve seçen ilk eli açar', () {
      final plan = KingMatchPlan(const KingRules());
      final m = MatchState.start(plan, 4);
      expect(plan.options(m), containsAll([0, 1, 2, 3, 4, 5, 10, 11, 12, 13]));
      m.choice = 12;
      final lv = plan.level(m) as TrickLevel;
      expect(lv.start.contract, 6);
      expect(lv.start.trump, kDiamonds);
      expect(lv.start.leader, plan.chooser(m));
      expect(plan.chooserHand(m).toSet(), lv.start.hands[plan.chooser(m)].toSet());
    });

    test('Trix: 4 krallık × 5 sözleşme; krallığın sahibi seçer ve döner', () {
      final plan = TrixMatchPlan();
      final m = MatchPlan.simulate(plan, 8);
      expect(m.played, 20);
      expect(plan.outcome(m), isNotNull);
      for (var k = 0; k < 4; k++) {
        final ch = m.choices.sublist(k * 5, k * 5 + 5)..sort();
        expect(ch, [0, 1, 2, 3, 4]);
        expect(m.choosers.sublist(k * 5, k * 5 + 5).toSet(), {(m.choosers[0] + k) % 4});
      }
      // Trix elinde dağıtılan ödüllerin toplamı 500.
      final trixDeal = m.choices.indexOf(4);
      expect(m.points[trixDeal].fold<int>(0, (a, b) => a + b), 500);
    });

    test('Trix: krallığın sahibi ilk eli açar, kalan sözleşmeler sunulur', () {
      final plan = TrixMatchPlan();
      final m = MatchState.start(plan, 6);
      final king = plan.chooser(m);
      m.choice = 3;
      final lv = plan.level(m) as TrickLevel;
      expect(lv.start.leader, king);
      plan.record(m, [0, -15, 0, 0]);
      expect(plan.options(m), [0, 1, 2, 4]);
      m.choice = 4;
      final lay = plan.level(m) as TableLevel;
      expect(lay.start.turn, king);
    });

    test('Trix: Kupa Papazı katlanır; alan −150, katlayan +75', () {
      const r = TrixRules(0);
      final s = r.deal(buildDeck(), 0);
      final kh = makeCard(13, kHearts);
      final holder = [for (var p = 0; p < 4; p++) if (s.hands[p].contains(kh)) p].single;
      expect(s.phase, TrickPhase.bidding);
      expect(s.turn, holder);
      expect(r.legalBids(s, holder), [0, TrixRules.khBit]);
      r.applyBid(s, holder, TrixRules.khBit);
      expect(r.biddingOver(s), isTrue);
      r.finishBidding(s);
      expect(s.phase, TrickPhase.play);
      final other = (holder + 1) % 4;
      s.taken[other].add(kh);
      final sc = r.handScores(s);
      expect(sc[other], -150);
      expect(sc[holder], 75);
      // Katlayan kendisi alırsa yalnız iki kat ceza.
      s.taken[other].remove(kh);
      s.taken[holder].add(kh);
      expect(r.handScores(s)[holder], -150);
      expect(r.handScores(s).where((x) => x > 0), isEmpty);
    });

    test('Trix: kızlar tek tek katlanabilir', () {
      const r = TrixRules(1);
      final s = r.deal(buildDeck(), 0);
      final p = s.turn;
      final mask = r.doubleMask(s, p);
      expect(mask, isNot(0));
      expect(r.legalBids(s, p).length, 1 << mask.toRadixString(2).replaceAll('0', '').length);
      const noDouble = TrixRules(2);
      expect(noDouble.deal(buildDeck(), 0).phase, TrickPhase.play);
    });
  });

  group('herkes pas ve 29 kozu', () {
    test('Tarneeb maçta herkes pas: el yeniden dağıtılır', () {
      const r = TarneebRules();
      final s = r.deal(r.deck(), 0)..matchPlay = true;
      for (var i = 0; i < 4; i++) {
        r.applyBid(s, s.turn, 0);
        if (r.biddingOver(s)) r.finishBidding(s);
      }
      expect(s.phase, TrickPhase.over);
      expect(r.thrownIn(s), isTrue);
      final plan = TrickMatchPlan(r);
      final m = MatchState.start(plan, 1);
      final d0 = plan.dealerOf(m);
      plan.record(m, plan.score(TrickLevel(r, s, TrickGoal.win, 1, 1, 0), s));
      expect(m.played, 0);
      expect(m.dealt, 1);
      expect(plan.dealerOf(m), (d0 + 1) % 4);
    });

    test('Baloot maçta iki tur pas: yeniden dağıtılır; bölümde dağıtan zorunlu', () {
      const r = BalootRules();
      final s = r.deal(r.deck(), 0)..matchPlay = true;
      for (var i = 0; i < 8; i++) {
        expect(r.legalBids(s, s.turn), contains(0));
        r.applyBid(s, s.turn, 0);
        if (r.biddingOver(s)) r.finishBidding(s);
      }
      expect(s.phase, TrickPhase.over);
      expect(r.thrownIn(s), isTrue);
      final lv = r.deal(r.deck(), 0);
      for (var i = 0; i < 7; i++) {
        r.applyBid(lv, lv.turn, 0);
      }
      expect(r.legalBids(lv, lv.turn), isNot(contains(0)));
    });

    test('29 maçta herkes pas: yeniden dağıtılır', () {
      const r = TwentyNineRules();
      final s = r.deal(r.deck(), 0)..matchPlay = true;
      for (var i = 0; i < 4; i++) {
        r.applyBid(s, s.turn, 0);
        if (r.biddingOver(s)) r.finishBidding(s);
      }
      expect(r.thrownIn(s), isTrue);
    });

    test('29: rengi olmayan "koz açtır" der; açtıran koz atmak zorunda', () {
      const r = TwentyNineRules();
      final s = r.deal(r.deck(), 0);
      r.applyBid(s, s.turn, 16);
      r.biddingOver(s);
      for (var i = 0; i < 3; i++) {
        r.applyBid(s, s.turn, 0);
        r.biddingOver(s);
      }
      r.applyBid(s, s.turn, 100 + kHearts);
      r.finishBidding(s);
      final lead = s.turn, next = (lead + 1) % 4, third = (lead + 2) % 4;
      s.hands[lead]
        ..clear()
        ..add(makeCard(1, kSpades));
      s.hands[next]
        ..clear()
        ..addAll([makeCard(7, kHearts), makeCard(8, kClubs)]);
      s.hands[third]
        ..clear()
        ..addAll([makeCard(9, kHearts), makeCard(13, kDiamonds)]);
      r.play(s, lead, makeCard(1, kSpades));
      expect(r.playActions(s, next), [TwentyNineRules.showTrump]);
      // Açtırmadan istediğini atabilir.
      expect(r.legalPlays(s, next).length, 2);
      r.applyPlayAction(s, next, TwentyNineRules.showTrump);
      expect(s.trump, kHearts);
      expect(r.playActions(s, next), isEmpty);
      expect(r.legalPlays(s, next), [makeCard(7, kHearts)]);
      r.play(s, next, makeCard(7, kHearts));
      // Açtırmayan oyuncu serbest.
      expect(r.legalPlays(s, third).length, 2);
      final back = TrickState.fromJson(s.toJson());
      expect(back.aux, next);
      expect(back.serialize(), s.serialize());
    });

    test('29 maç puanı: tutturan +1, tutturamayan −1', () {
      const r = TwentyNineRules();
      final s = r.deal(r.deck(), 0);
      s
        ..declarer = 1
        ..contract = 16
        ..phase = TrickPhase.over;
      s.taken[1].addAll(r.deck().where((c) => rankOf(c) == 11 || rankOf(c) == 9));
      expect(r.matchPoints(s), [0, 1, 0, 1]);
      s.taken[1].clear();
      expect(r.matchPoints(s), [0, -1, 0, -1]);
    });
  });
}
