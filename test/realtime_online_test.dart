import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/net_sync.dart';

/// Hızlı kart oyunlarının çevrimiçi katmanı: durum yazımı, koltuk döndürme,
/// çok oyunculu eylemler, ev sahibi → misafir eşitlemesi ve devralma.
void main() {
  RtLevel levelOf(RtKind kind, [int n = 300]) {
    final rules = RealtimeRules(gameId: 'rt-${kind.name}', kind: kind);
    final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
    return rules.build(planner.spec(n)).puzzle;
  }

  RtGame played(RtKind kind, int ms) {
    final g = RtGame.create(levelOf(kind));
    for (var t = 0; t < ms && !g.over; t += 20) {
      g.botAct();
      g.advance(20);
    }
    return g;
  }

  test('çevrimiçi masa: Kemps dört, diğerleri iki kişilik', () {
    for (final k in RtKind.values) {
      final rules = RealtimeRules(gameId: 'x', kind: k);
      expect(rules.localPlayers, k == RtKind.kemps ? 4 : 2);
      expect(RtGame.create(levelOf(k)).seats, k == RtKind.kemps ? 4 : 2);
    }
  });

  for (final kind in RtKind.values) {
    test('${kind.name}: durum yazılıp okununca aynı; döndürme geri alınabilir', () {
      final g = played(kind, 4000);
      final wire = encodeNums(g.encode());
      final copy = RtGame.create(levelOf(kind))..decode(decodeInts(wire));
      expect(encodeNums(copy.encode()), wire);
      expect(copy.scoreOf(0), g.scoreOf(0));
      for (var i = 0; i < copy.seats; i++) {
        copy.rotate(1);
      }
      expect(encodeNums(copy.encode()), wire);
      copy.rotate(1);
      expect(copy.scoreOf(0), g.scoreOf(1));
    });
  }

  test('çevrimdışı akış değişmedi: aynı bölüm aynı sonucu verir', () {
    for (final kind in RtKind.values) {
      final a = played(kind, 60000), b = played(kind, 60000);
      expect(a.encode(), b.encode(), reason: kind.name);
    }
  });

  group('Snap', () {
    SnapGame open() {
      final g = SnapGame(levelOf(RtKind.snap))
        ..ai[0] = false
        ..ai[1] = false
        ..fairMs = 350;
      for (var i = 0; i < 20000 && !g.snapOpen && !g.over; i++) {
        g.advance(10);
      }
      return g;
    }

    test('aynı anda basışta ağ gecikmesine bakılmaz, tepkisi hızlı olan alır', () {
      final g = open();
      expect(g.snapOpen, isTrue);
      final f = g.flips;
      final before = g.stacks[1].length + g.center.length;
      // ev sahibinin basışı önce ulaşır ama misafir daha hızlı tepki vermiş
      expect(g.act(0, 'S$f,320'), isTrue);
      g.advance(100);
      expect(g.act(1, 'S$f,210'), isTrue);
      g.advance(400);
      expect(g.lastWinner, 1);
      expect(g.stacks[1].length, before);
      // deste alındıktan sonra gelen basış ceza almaz
      final mine = g.stacks[0].length;
      expect(g.act(0, 'S$f,400'), isFalse);
      expect(g.stacks[0].length, mine);
    });

    test('yanlış yakalama iki kart kaybettirir; eski desteye basış yok sayılır', () {
      final g = SnapGame(levelOf(RtKind.snap))
        ..ai[1] = false
        ..fairMs = 350;
      while (!g.over && (g.snapOpen || g.flips == 0)) {
        g.advance(10);
      }
      expect(g.snapOpen, isFalse);
      final a = g.stacks[1].length, b = g.stacks[0].length;
      expect(g.act(1, 'S${g.flips},100'), isFalse);
      expect(g.stacks[1].length, a - 2);
      expect(g.stacks[0].length, b + 2);
      expect(g.act(1, 'S${g.flips - 1},100'), isFalse);
      expect(g.stacks[1].length, a - 2);
    });
  });

  test('Kemps: dörtlüsü olmadan Kemps diyen kaybeder; botlar yalnızca bot koltuklarında', () {
    final g = KempsGame(levelOf(RtKind.kemps));
    g.ai
      ..[0] = false
      ..[2] = false;
    final h = List.of(g.hands[2]);
    final has = KempsGame.hasFour(h);
    expect(g.act(2, 'K'), has);
    expect(g.over, isTrue);
    expect(g.winnerSeat, has ? 2 : 3);
  });

  test('Kemps: koltuk döndürme her oyuncuya kendi elini altta gösterir', () {
    final g = KempsGame(levelOf(RtKind.kemps));
    final h2 = List.of(g.hands[2]);
    final v = RtGame.create(levelOf(RtKind.kemps)) as KempsGame
      ..decode(g.encode())
      ..rotate(2);
    expect(v.hands[0], h2);
    expect(v.hands[2], g.hands[0]);
  });

  test('Hız: misafirin kartları ağdan ev sahibine gider; ev sahibi düşünce misafir devralır ve bitirir', () {
    final level = levelOf(RtKind.speed);
    final host = RtGame.create(level) as SpeedGame;
    final toGuest = <String>[];
    var now = 0;
    final hs = NetSync(mySeat: 0, seats: 2, humans: {0, 1}, send: toGuest.add, snapGapMs: 100);
    final gs = NetSync(mySeat: 1, seats: 2, humans: {0, 1}, send: (d) => hs.receive(1, d, now), snapGapMs: 100);
    var hostUp = true;
    var took = false;
    SpeedGame? mine; // devraldıktan sonra misafirin yürüttüğü oyun
    var guestPlays = 0;
    var lastPlayAt = -1000;
    for (now = 0; now < 400000; now += 50) {
      // misafir: ekranındaki (son anlık durum) oynanabilir bir kartı oynar
      final l = gs.latest;
      if (!took && l != null && now - lastPlayAt > 400 && gs.pending == 0) {
        final v = RtGame.create(level) as SpeedGame
          ..decode(decodeInts(l.payload));
        for (final c in v.hands[1]) {
          if (v.targetFor(c) != null) {
            gs.act('P$c');
            guestPlays++;
            lastPlayAt = now;
            break;
          }
        }
      }
      gs.pump(now);
      if (hostUp) {
        for (var p = 0; p < 2; p++) {
          host.ai[p] = !hs.live(p, now);
        }
        host.ai[0] = true; // ev sahibinin oyuncusu yerine bot
        for (final (seat, a) in hs.takeActions()) {
          host.act(seat, a);
        }
        host.advance(50);
        final last = now >= 20000 || host.over;
        hs.publish(host.time, encodeNums(host.encode()), now, force: last);
        if (last) hostUp = false;
      }
      for (final m in toGuest) {
        gs.receive(0, m, now);
      }
      toGuest.clear();
      if (!took && gs.checkTakeover(now)) {
        took = true;
        mine = RtGame.create(level) as SpeedGame
          ..decode(decodeInts(gs.latest!.payload));
        mine.ai[0] = true;
        mine.ai[1] = true;
      }
      final x = mine;
      if (x != null) {
        if (x.over) break;
        x.advance(50);
      }
    }
    expect(guestPlays, greaterThan(0));
    expect(host.scoreOf(1), greaterThan(0));
    // misafirin son gördüğü durum ev sahibininkiyle aynı
    expect(gs.latest!.payload, encodeNums(host.encode()));
    if (!host.over) {
      expect(took, isTrue);
      expect(gs.isHost, isTrue);
      expect(mine!.over, isTrue);
    }
  });
}
