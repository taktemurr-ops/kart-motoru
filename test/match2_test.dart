import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

/// Maç modu II: Skat oyun değeri, Briç Chicago, Gin bonusları, Cribbage'da
/// oyun içinde 121, King sözleşme adları; 31, Durak, Başkan, Okey, 101 Okey,
/// Domino ve Mahjong maçları.
void main() {
  group('Skat oyun değeri', () {
    const r = SkatRules();
    KCard c(int rank, int suit) => makeCard(rank, suit);

    test('matadorlar: ile / olmadan', () {
      expect(SkatRules.matadors([c(11, kClubs), c(11, kSpades), c(11, kDiamonds)], SkatRules.grand), 2);
      expect(SkatRules.matadors([c(11, kHearts), c(7, kHearts)], SkatRules.grand), 2);
      expect(
          SkatRules.matadors(
              [c(11, kClubs), c(11, kSpades), c(11, kHearts), c(11, kDiamonds), c(1, kHearts), c(10, kHearts), c(7, kHearts)], 2),
          6);
      expect(SkatRules.matadors([c(7, kHearts)], 2), 10);
    });

    test('ihale değerleri: 18, 20, 22, 23, 24, 27, 30 … 264', () {
      expect(SkatRules.bidValues.take(20).toList(), [18, 20, 22, 23, 24, 27, 30, 33, 35, 36, 40, 44, 45, 46, 48, 50, 54, 55, 59, 60]);
      expect(SkatRules.bidValues.last, 264);
      expect(SkatRules.nextBid(23), 24);
    });

    test('Reizen: orta el öndekine söyler, sonra arka el; kazanan ilan eder', () {
      final s = r.deal(r.deck(), 0);
      // Dağıtan 0: öndeki (Vorhand) 1, orta (Mittelhand) 2, arka (Hinterhand) 0.
      expect(s.turn, 2);
      expect(r.legalBids(s, 2), [0, 18, 20, 22, 23, 24, 27]);
      r.applyBid(s, 2, 18);
      expect(s.turn, 1);
      expect(r.legalBids(s, 1), [SkatRules.hold, SkatRules.pass]);
      r.applyBid(s, 1, SkatRules.hold);
      expect(s.turn, 2);
      r.applyBid(s, 2, 20);
      r.applyBid(s, 1, SkatRules.pass);
      // Orta el kazandı; arka el ona söyler.
      expect(s.turn, 0);
      expect(r.legalBids(s, 0).take(3).toList(), [0, 22, 23]);
      r.applyBid(s, 0, 22);
      expect(s.turn, 2);
      r.applyBid(s, 2, SkatRules.hold);
      r.applyBid(s, 0, SkatRules.pass);
      expect(s.declarer, 2);
      expect(SkatRules.bidOf(s), 22);
      expect(r.legalBids(s, 2), [SkatRules.pickUp, SkatRules.playHand]);
      // Skatı al, iki kart göm, ♣ ilan et.
      r.applyBid(s, 2, SkatRules.pickUp);
      expect(s.hands[2].length, 12);
      for (var i = 0; i < 2; i++) {
        r.applyBid(s, 2, r.legalBids(s, 2).first);
      }
      expect(s.hands[2].length, 10);
      final opts = r.legalBids(s, 2);
      expect(opts, contains(SkatRules.declareBase + 5));
      // Skat alındığında ilan ve Ouvert (Null dışında) yok; Null 23 < 22 değil.
      expect(opts.where((o) => (o - SkatRules.declareBase) ~/ 10 != 0 && (o - SkatRules.declareBase) % 10 != SkatRules.nullGame), isEmpty);
      r.applyBid(s, 2, SkatRules.declareBase + 5);
      expect(r.biddingOver(s), isTrue);
      r.finishBidding(s);
      expect((s.contract, s.declarer, s.taken[2].length, s.turn), (5, 2, 2, 1));
      expect(s.phase, TrickPhase.play);
    });

    test('herkes pas: öndeki 18 der ya da Ramsch', () {
      final s = r.deal(r.deck(), 0);
      r.applyBid(s, 2, SkatRules.pass);
      r.applyBid(s, 0, SkatRules.pass);
      expect(s.turn, 1);
      expect(r.legalBids(s, 1), [0, 18]);
      r.applyBid(s, 1, SkatRules.pass);
      expect(r.biddingOver(s), isTrue);
      r.finishBidding(s);
      expect(s.contract, SkatRules.ramsch);
    });

    test('Hand: Schneider/Schwarz ilanı ve Grand Ouvert', () {
      final s = r.deal(r.deck(), 0);
      r.applyBid(s, 2, SkatRules.pass);
      r.applyBid(s, 0, SkatRules.pass);
      r.applyBid(s, 1, 18);
      final kitty = List.of(s.kitty);
      r.applyBid(s, 1, SkatRules.playHand);
      final opts = r.legalBids(s, 1);
      const go = SkatRules.declareBase + SkatRules.grand + 10 * (SkatRules.hand | SkatRules.ouvert | SkatRules.schneiderAnnounced | SkatRules.schwarzAnnounced);
      expect(opts, contains(go));
      expect(opts, contains(SkatRules.declareBase + 5 + 10 * (SkatRules.hand | SkatRules.schneiderAnnounced)));
      expect(r.bidLabel(go, 'en').startsWith('Grand Ouvert'), isTrue);
      r.applyBid(s, 1, go);
      r.finishBidding(s);
      expect(s.taken[1], kitty);
      expect(r.openHand(s, 1), isTrue);
      expect(r.openHand(s, 0), isFalse);
      expect(SkatRules.normalizeFlags(5, SkatRules.ouvert), SkatRules.hand | SkatRules.ouvert | SkatRules.schneiderAnnounced | SkatRules.schwarzAnnounced);
      expect(SkatRules.normalizeFlags(5, SkatRules.schneiderAnnounced), 0);
    });

    test('yapay zekâ en yüksek oyun değerine kadar ihale eder', () {
      final strong = [
        for (final su in [kClubs, kSpades, kHearts, kDiamonds]) c(11, su),
        c(1, kClubs), c(10, kClubs), c(13, kClubs), c(1, kHearts), c(10, kHearts), c(1, kSpades),
      ];
      // Dört vale ile ♣: 12 × (4 + 1) = 60; Grand: 24 × 5 = 120.
      expect(SkatRules.maxBid(strong), greaterThanOrEqualTo(60));
      final weak = [c(7, kClubs), c(9, kHearts), c(13, kSpades), c(12, kDiamonds), c(10, kSpades), c(8, kHearts), c(13, kHearts), c(9, kDiamonds), c(1, kDiamonds), c(12, kClubs)];
      expect(SkatRules.maxBid(weak), 0);
    });

    TrickState played(int game, {int extra = 0, int matadors = 1}) {
      final s = r.deal(r.deck(), 0);
      s
        ..declarer = 0
        ..contract = game
        ..extra = extra
        ..aux = matadors
        ..phase = TrickPhase.over;
      for (final h in s.hands) {
        h.clear();
      }
      return s;
    }

    test('Grand, iki matadorla, Schneider: 24 × 4 = 96; Seeger-Fabian +146', () {
      final s = played(SkatRules.grand, matadors: 2);
      final lost = {c(10, kSpades), c(10, kHearts), c(13, kSpades)};
      s.taken[0].addAll(r.deck().where((x) => !lost.contains(x)));
      s.taken[1].addAll(lost);
      s.tricks[0] = 9;
      s.tricks[1] = 1;
      expect(r.gameValue(s), (96, true));
      expect(r.matchPoints(s), [146, 0, 0]);
    });

    test('kaybedilen Hand oyunu: iki kat değer + 50 eksi, rakiplere 40', () {
      final s = played(1, extra: SkatRules.hand, matadors: 1);
      s.taken[0].addAll(r.deck().where((x) => suitOf(x) == kDiamonds));
      s.taken[1].addAll(r.deck().where((x) => suitOf(x) != kDiamonds));
      s.tricks[0] = 2;
      s.tricks[1] = 8;
      // ♦ 9 × (1 + oyun + hand) = 27; puanı 30 → Schneider kaybı: 9 × 4 = 36.
      expect(r.gameValue(s).$1, 36);
      expect(r.matchPoints(s), [-122, 40, 40]);
    });

    test('Null değerleri ve açık el', () {
      final s = played(SkatRules.nullGame, extra: SkatRules.hand | SkatRules.ouvert, matadors: 0);
      expect(r.gameValue(s), (59, true));
      s.tricks[0] = 1;
      expect(r.gameValue(s), (59, false));
      s.phase = TrickPhase.play;
      expect(r.openHand(s, 0), isTrue);
      expect(r.openHand(s, 1), isFalse);
      s.extra = SkatRules.hand;
      expect(r.openHand(s, 0), isFalse);
    });

    test('aşırı ihale: değer ihaleye ulaşmazsa kayıp, değer ihaleyi karşılayan kat', () {
      final s = played(1, matadors: 1);
      s.bids[0] = 60;
      s.taken[0].addAll(r.deck().where((x) => suitOf(x) != kDiamonds));
      s.tricks[0] = 8;
      // ♦ 9 × (1 + 1 + Schneider 1) = 27 < 60 → kayıp, 9 × 7 = 63.
      expect(r.gameValue(s), (63, false));
      expect(r.overbid(s), isTrue);
      expect(r.matchPoints(s), [-176, 40, 40]);
    });

    test('ilanlı Schneider: 90 göz gerekir, değere iki kat eklenir', () {
      final s = played(5, extra: SkatRules.hand | SkatRules.schneiderAnnounced, matadors: 1);
      final lost = {c(1, kHearts), c(10, kHearts), c(13, kHearts)};
      s.taken[0].addAll(r.deck().where((x) => !lost.contains(x)));
      s.taken[1].addAll(lost);
      s.tricks[0] = 9;
      // 95 göz: ♣ 12 × (1 + 1 + Hand + Schneider + ilan) = 60, kazandı.
      expect(r.gameValue(s), (60, true));
      s.taken[0].remove(c(1, kSpades));
      s.taken[1].add(c(1, kSpades));
      // 84 göz: Schneider olmadı → ilan tutmadı, kayıp.
      expect(r.gameValue(s), (48, false));
    });

    test('yapay zekâ ihalesi: geçerli, Ramsch azınlıkta, ilan eden çoğunlukla kazanır', () {
      var ramsch = 0, declared = 0, won = 0;
      const n = 150;
      for (var g = 0; g < n; g++) {
        final rnd = SeededRandom(mixSeed([g, 31]));
        final deck = r.deck();
        shuffleCards(deck, rnd);
        final s = r.deal(deck, g % 3);
        final ai = TrickAI(r, 0, rnd);
        while (s.phase != TrickPhase.over) {
          final seat = s.turn;
          if (s.phase == TrickPhase.bidding) {
            final b = ai.bid(s, seat);
            expect(r.legalBids(s, seat), contains(b));
            r.applyBid(s, seat, b);
            if (r.biddingOver(s)) r.finishBidding(s);
          } else {
            r.play(s, seat, ai.play(s, seat));
          }
        }
        if (s.contract == SkatRules.ramsch) {
          ramsch++;
          continue;
        }
        declared++;
        expect(SkatRules.bidOf(s), greaterThanOrEqualTo(18));
        if (r.gameValue(s).$2) won++;
      }
      expect(ramsch, lessThan(n * 0.25));
      expect(won / declared, greaterThan(0.55));
      expect(won / declared, lessThan(0.95));
    });

    test('Skat maçı 12 el, yapay zekâyla biter', () {
      final plan = TrickMatchPlan(r);
      final m = MatchPlan.simulate(plan, 5);
      expect(m.played, 12);
      expect(plan.outcome(m), isNotNull);
    });
  });

  group('Briç Chicago', () {
    TrickState made(ContractBridgeRules r, int bid, int tricks, {int dbl = 0, int declarer = 0, int dealer = 0}) {
      final s = r.deal(r.deck(), dealer);
      s
        ..declarer = declarer
        ..contract = bid
        ..aux = dbl
        ..phase = TrickPhase.over;
      s.tricks[declarer] = tricks;
      return s;
    }

    int bid(int level, int strain) => 1 + (level - 1) * 5 + strain;
    const none = ContractBridgeRules(), both = ContractBridgeRules(chicago: 3);

    test('kontrat, oyun, kısmi ve şlem bonusları', () {
      expect(none.contractScore(made(none, bid(4, 3), 10)), 420);
      expect(both.contractScore(made(both, bid(4, 3), 10)), 620);
      expect(none.contractScore(made(none, bid(3, 4), 10)), 430);
      expect(none.contractScore(made(none, bid(2, 0), 8)), 90);
      expect(none.contractScore(made(none, bid(6, 2), 12)), 980);
      expect(both.contractScore(made(both, bid(7, 4), 13)), 2220);
    });

    test('kontr ve sürkontr', () {
      expect(none.contractScore(made(none, bid(1, 0), 7, dbl: 1)), 140);
      expect(none.contractScore(made(none, bid(2, 2), 5, dbl: 1)), -500);
      expect(both.contractScore(made(both, bid(2, 2), 7, dbl: 1)), -200);
      expect(both.contractScore(made(both, bid(7, 4), 13, dbl: 2)), 2980);
      expect(none.contractScore(made(none, bid(1, 4), 9, dbl: 1)), 180 + 200);
      expect(none.contractScore(made(none, bid(3, 0), 5, dbl: 0)), -200);
    });

    test('zon: 1. el yok, 2. ve 3. elde dağıtanın tarafı, 4. elde herkes', () {
      final rules = [for (var d = 0; d < 4; d++) const ContractBridgeRules().rulesForDeal(d) as ContractBridgeRules];
      final s = rules[1].deal(rules[1].deck(), 1);
      expect([rules[0].vulnerable(s, 0), rules[0].vulnerable(s, 1)], [false, false]);
      expect([rules[1].vulnerable(s, 0), rules[1].vulnerable(s, 1)], [false, true]);
      expect([rules[2].vulnerable(s, 0), rules[2].vulnerable(s, 1)], [false, true]);
      expect([rules[3].vulnerable(s, 0), rules[3].vulnerable(s, 1)], [true, true]);
    });

    test('kontr rakibe, sürkontr ilan eden tarafa açılır; puan kazanan tarafa yazılır', () {
      const r = ContractBridgeRules();
      final s = r.deal(r.deck(), 3);
      r.applyBid(s, 0, bid(2, 3));
      expect(r.legalBids(s, 1), contains(ContractBridgeRules.double_));
      expect(r.legalBids(s, 2), isNot(contains(ContractBridgeRules.double_)));
      r.applyBid(s, 1, ContractBridgeRules.double_);
      expect(r.legalBids(s, 2), contains(ContractBridgeRules.redouble));
      expect(r.legalBids(s, 3), isNot(contains(ContractBridgeRules.redouble)));
      expect(s.contract, bid(2, 3));
      expect(s.declarer, 0);
      expect(r.doubled(s), 1);
      for (var i = 0; i < 3; i++) {
        r.applyBid(s, s.turn, 0);
      }
      expect(r.biddingOver(s), isTrue);
      s.tricks[0] = 6;
      s.phase = TrickPhase.over;
      expect(r.matchPoints(s), [0, 300, 0, 300]);
    });

    test('Chicago maçı dört el sürer', () {
      final plan = TrickMatchPlan(const ContractBridgeRules());
      final m = MatchPlan.simulate(plan, 7);
      expect(m.played, 4);
      for (final row in m.points) {
        expect(row.every((x) => x >= 0), isTrue);
      }
    });
  });

  group('Gin Remi bonusları', () {
    test('oyun bonusu 100, her kazanılan el 25', () {
      final plan = GinMatchPlan(const GinRummyRules());
      final m = MatchState(1, 0);
      plan.record(m, [60, 0]);
      plan.record(m, [0, 10]);
      expect(plan.outcome(m), isNull);
      plan.record(m, [45, 0]);
      expect(m.points.last, [150, 25]);
      expect(m.choices.last, GinMatchPlan.bonusRow);
      expect(plan.outcome(m), 0);
      expect(plan.totals(m), [255, 35]);
    });

    test('shutout: kazananın bütün puanı iki katı', () {
      final plan = GinMatchPlan(const GinRummyRules());
      final m = MatchState(1, 0);
      plan.record(m, [0, 60]);
      plan.record(m, [0, 0]);
      plan.record(m, [0, 50]);
      expect(plan.outcome(m), 1);
      expect(plan.totals(m), [0, 2 * (110 + 100 + 50)]);
    });

    test('Gin maçı yapay zekâyla biter', () {
      final plan = GinMatchPlan(const GinRummyRules());
      final m = MatchPlan.simulate(plan, 11);
      final out = plan.outcome(m)!;
      expect(plan.handTotals(m)[out], greaterThanOrEqualTo(100));
      expect(m.choices.last, GinMatchPlan.bonusRow);
    });
  });

  group('Cribbage: 121 oyun sırasında', () {
    TableState pegging(CribbageRules r) {
      final s = r.deal(buildDeck(), 0);
      s.vars[0] = 1;
      s.vars[1] = 5;
      s.vars[2] = 0;
      s.piles[3]
        ..clear()
        ..add(makeCard(5, kSpades));
      s.hands[1]
        ..clear()
        ..addAll([makeCard(13, kHearts), makeCard(2, kDiamonds)]);
      s.hands[0]
        ..clear()
        ..add(makeCard(3, kClubs));
      s.turn = 1;
      return s;
    }

    test('maçta 121 olan sayma sırasında kazanır', () {
      final r = const CribbageRules().rulesForMatch(3, [
        [50, 60],
        [0, 59],
      ]) as CribbageRules;
      expect(r.carry, [50, 119]);
      final s = pegging(r);
      r.apply(s, TAction(0, [makeCard(13, kHearts)]));
      expect(s.scores[1], 2);
      expect(s.over, isTrue);
      expect(s.hands[1], isNotEmpty);
    });

    test('tek elde ve 121 uzaktayken el sürer', () {
      final s = pegging(const CribbageRules());
      const CribbageRules().apply(s, TAction(0, [makeCard(13, kHearts)]));
      expect(s.over, isFalse);
    });
  });

  test('King sözleşme adları 33 dilde', () {
    const k = KingRules();
    for (var c = 0; c < KingRules.contracts; c++) {
      expect(kKartTexts['kingC$c']!.length, 33);
      expect(k.contractName(c, 'de'), kKartTexts['kingC$c']![2]);
    }
    expect(k.contractName(5, 'tr'), 'Rıfkı');
    expect(KingMatchPlan(k).optionLabel(11, 'fr'), 'Atout ♥');
  });

  group('31, Durak ve Başkan maçları', () {
    test('31: en düşük el can kaybeder, kapatan en düşükse iki; 31 yapınca diğerleri', () {
      const r = ThirtyOneRules();
      final s = r.deal(buildDeck(), 0);
      s.hands[0] = [makeCard(10, kSpades), makeCard(9, kSpades), makeCard(2, kHearts)];
      s.hands[1] = [makeCard(13, kHearts), makeCard(12, kHearts), makeCard(3, kClubs)];
      s.hands[2] = [makeCard(1, kDiamonds), makeCard(13, kDiamonds), makeCard(12, kDiamonds)];
      expect(r.matchPoints(s), [1, 1, 0]);
      s.hands[2] = [makeCard(1, kDiamonds), makeCard(2, kClubs), makeCard(3, kHearts)];
      s.vars[1] = 2;
      expect(r.matchPoints(s), [0, 0, 2]);
      s.vars[1] = 1;
      expect(r.matchPoints(s), [0, 0, 1]);
      expect(r.matchFormat.target, ThirtyOneRules.lives);
    });

    test('Durak: maç modu var; önceki oyunu kazanan ilk saldırır', () {
      final durak = TableGameRules(gameId: 'oyun-durak', rulesFor: (_) => const DurakRules());
      expect(durak.modes, contains(GameModeId.endless));
      final r = const DurakRules().rulesForMatch(1, [
        [1, 0],
      ]) as DurakRules;
      expect(r.firstAttacker, 1);
      final s = r.deal(r.deck(), 0);
      expect(s.vars[0], 1);
      expect(s.turn, 1);
      s.scores[0] = -1;
      s.scores[1] = 1;
      expect(r.matchPoints(s), [1, 0]);
    });

    test('Başkan: sonuncu en iyi iki kartını başkana verir ve açar', () {
      final deck = buildDeck();
      final plain = const PresidentRules().deal(deck, 0);
      final r = const PresidentRules().rulesForMatch(1, [
        [0, 3, 1, 2],
      ]) as PresidentRules;
      final s = r.deal(deck, 0);
      final scumBest = (List.of(plain.hands[0])..sort((a, b) => PresidentRules.power(a).compareTo(PresidentRules.power(b)))).sublist(11);
      for (final c in scumBest) {
        expect(s.hands[1], contains(c));
        expect(s.hands[0], isNot(contains(c)));
      }
      expect(s.turn, 0);
      expect([for (final h in s.hands) h.length], [13, 13, 13, 13]);
    });
  });

  group('Okey ve 101 Okey maçı', () {
    test('Okey: 20 puanla başlanır, bitiren için diğerleri düşer', () {
      const r = OkeyRules();
      expect(r.matchFormat.start, 20);
      final s = r.deal(r.deck(), 0);
      s.scores.setAll(0, [0, 4, 1, 0]);
      expect(r.matchPoints(s), [-5, -1, -4, -5]);
      const e = OkeyRules(partners: true);
      final t = e.deal(e.deck(), 0);
      t.scores.setAll(0, [2, 0, 2, 0]);
      expect(e.matchPoints(t), [0, -2, 0, -2]);
      expect((r.rulesForMatch(0, const []) as OkeyRules).showIndicator, isTrue);
      final plan = TableMatchPlan(r);
      final m = MatchState(3, 0);
      plan.record(m, [-2, -2, 0, -2]);
      expect(plan.totals(m), [18, 18, 20, 18]);
      expect(plan.outcome(m), isNull);
      for (var i = 0; i < 9; i++) {
        plan.record(m, [-2, -2, 0, -2]);
      }
      expect(plan.outcome(m), 2);
    });

    test('101 Okey: 9 el, ceza toplamı en az olan kazanır; deste biterse yalnız okey cezası', () {
      const r = Okey101Rules();
      expect(r.matchFormat.deals, 9);
      expect(r.matchFormat.lowWins, isTrue);
      expect(identical(r.rulesForMatch(2, const []), r), isTrue);
      final s = r.deal(r.deck(), 0);
      final jokers = [for (final h in s.hands) h.where((t) => okeyMeaning(t, r.kind(s)) < 0).length * 101];
      expect(r.matchPoints(s), jokers);
      s.hands[2].clear();
      s.scores.setAll(0, [-202, -40, 101, -12]);
      expect(r.matchPoints(s), [202, 40, -101, 12]);
    });
  });

  group('Domino maçı', () {
    test('iki kişide 100, kalabalıkta 150; önceki eli kazanan açar', () {
      expect(const DominoRules(2).matchFormat.target, 100);
      expect(const DominoRules(4).matchFormat.target, 150);
      final r = const DominoRules(3).rulesForMatch(1, [
        [0, 0, 42],
      ]) as DominoRules;
      expect(r.opener, 2);
      expect(r.deal(r.deck(), 0).turn, 2);
    });
  });

  group('Mahjong maçı', () {
    test('doğu kazanırsa sürdürür, kaybederse geçer; dört doğudan sonra güney turu', () {
      final plan = MahjongMatchPlan(const MahjongRules(MahjongStyle.riichi));
      final m = MatchState(5, 0);
      expect(plan.dealerOf(m), 0);
      expect(plan.dealName(m, 'en'), '東1');
      plan.record(m, [3900, -3900, 0, 0]);
      expect(plan.dealerOf(m), 0);
      expect(plan.dealName(m, 'en'), '東1 +1');
      plan.record(m, [-1000, 1000, 0, 0]);
      expect(plan.dealerOf(m), 1);
      for (var p = 2; p <= 4; p++) {
        plan.record(m, [0, 0, 0, 0]);
      }
      expect(plan.round(m), 1);
      expect(plan.dealName(m, 'en'), '南1');
      expect(((plan.level(m) as TableLevel).rules as MahjongRules).roundWind, 1);
      expect(plan.outcome(m), isNull);
      plan.record(m, [-30000, 30000, 0, 0]);
      expect(plan.outcome(m), 1);
    });

    test('Riichi puanları: ron atan öder, kendi çekişte herkes payını', () {
      const r = MahjongRules(MahjongStyle.riichi);
      expect(MahjongRules.riichiPay(4, dealer: false), 7700);
      final s = r.deal(r.deck(), 0);
      s.vars[5] = 2;
      s.vars[8] = 0;
      s.scores.setAll(0, [-9, 9, 0, 0]);
      expect(r.matchPoints(s), [-3900, 3900, 0, 0]);
      s.vars[8] = 1;
      s.scores.setAll(0, [-3, 9, -3, -3]);
      expect(r.matchPoints(s), [-1300, 3900, -1300, -1300]);
    });

    test('klasik ve Hong Kong dört rüzgâr turu, Riichi hanchan', () {
      expect(MahjongMatchPlan(const MahjongRules()).rounds, 4);
      expect(MahjongMatchPlan(const MahjongRules(MahjongStyle.hongKong)).rounds, 4);
      expect(MahjongMatchPlan(const MahjongRules(MahjongStyle.sanma)).rounds, 2);
      final mj = TableGameRules(gameId: 'oyun-mahjong', rulesFor: (_) => const MahjongRules());
      expect(mj.modes, contains(GameModeId.endless));
      final planner = LevelPlanner(gameId: 'oyun-mahjong', optionalMechanics: const []);
      expect(MatchPlan.of(mj.build(planner.run(GameModeId.endless, 1)).puzzle), isA<MahjongMatchPlan>());
    });
  });

  group('yeni maçlar yapay zekâyla sonuna kadar oynanır', () {
    final plans = <String, MatchPlan>{
      'cribbage': TableMatchPlan(const CribbageRules()),
      '31': TableMatchPlan(const ThirtyOneRules()),
      'durak': TableMatchPlan(const DurakRules()),
      'president': TableMatchPlan(const PresidentRules()),
      'okey': TableMatchPlan(const OkeyRules()),
      'okey-esli': TableMatchPlan(const OkeyRules(partners: true)),
      'okey-katlamali': TableMatchPlan(const OkeyRules(doubling: true)),
      'okey101': TableMatchPlan(const Okey101Rules()),
      'domino': TableMatchPlan(const DominoRules(2)),
      'domino4': TableMatchPlan(const DominoRules(4)),
      'mahjong': MahjongMatchPlan(const MahjongRules()),
      'riichi': MahjongMatchPlan(const MahjongRules(MahjongStyle.riichi)),
      'hongkong': MahjongMatchPlan(const MahjongRules(MahjongStyle.hongKong)),
      'king': KingMatchPlan(const KingRules()),
    };
    plans.forEach((name, plan) {
      test(name, () {
        final a = MatchPlan.simulate(plan, 11);
        expect(plan.outcome(a), isNotNull, reason: name);
        expect(plan.formatLabel('tr') ?? plan.format.toString(), isNotEmpty);
        expect(MatchPlan.simulate(plan, 11).toJson(), a.toJson());
        if (name == 'cribbage') expect(plan.totals(a).any((t) => t >= 121), isTrue);
      });
    });

    test('masa taşı oyunlarında Maç mod kartı görünür', () {
      for (final r in <TableRules>[const OkeyRules(), const Okey101Rules(), const DominoRules(), const ThirtyOneRules(), const PresidentRules()]) {
        final g = TableGameRules(gameId: 'x', rulesFor: (_) => r);
        expect(g.modes, contains(GameModeId.endless));
        expect(g.strings['mode_endless']!.length, 33);
      }
    });
  });
}
