import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/net_sync.dart';
import 'package:studio_core/core/net_texts.dart';

import 'card_painter.dart';
import 'cards.dart';
import 'kart_texts.dart';
import 'realtime.dart';

/// Hızlı kart oyunlarının ortak ekranı.
///
/// Çevrimiçi masada (ctx.match) ev sahibi oyunu yürütür ve değişiklikte
/// (en çok 10 Hz) anlık durum yayınlar; diğer oyuncuların dokunuşları sıra
/// numaralı eylem olarak gider ("Yakala!", kart oyna ...). Bağlantısı kopanın
/// yerine yapay zekâ oynar, ev sahibi koparsa bir misafir devralır.
/// Her oyuncu masayı kendi koltuğu altta olacak şekilde görür.
class RealtimeView extends StatefulWidget {
  final PlayContext ctx;
  const RealtimeView({super.key, required this.ctx});

  @override
  State<RealtimeView> createState() => _RealtimeViewState();
}

class _RealtimeViewState extends State<RealtimeView> {
  late RtLevel level;
  late RtGame g;

  /// Ekrana çizilen oyun (çevrimdışı: [g]; çevrimiçi: bu koltuğa döndürülmüş kopya).
  late RtGame shown;
  Timer? _timer;
  bool _ended = false;
  KCard? _sel;
  int _flash = 0;

  // ---- çevrimiçi ----
  NetSync? _sync;
  final NetNotes _notes = NetNotes();
  StreamSubscription<(int, String)>? _sub;
  final Stopwatch _clock = Stopwatch()..start();
  int _me = 0;
  String _lastKey = '';
  bool _overSent = false;
  int _overAt = -1;
  NetSnap? _shownFrom;
  int _seenFlip = -1, _seenFlipAt = 0;

  PlayContext get ctx => widget.ctx;
  bool get _online => _sync != null;
  int get _now => _clock.elapsedMilliseconds;

  RealtimeLink? get _rt {
    final Object? l = ctx.match;
    return l is RealtimeLink ? l : null;
  }

  @override
  void initState() {
    super.initState();
    level = (ctx.generated as GeneratedLevel<RtLevel>).puzzle;
    g = RtGame.create(level);
    shown = g;
    final m = ctx.match;
    if (m != null) _startOnline(m);
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || _ended) return;
      final sync = _sync;
      if (sync != null) {
        _onlineTick(sync);
        return;
      }
      final before = (g.playerScore, g.aiScore);
      g.advance(50);
      if (_flash > 0) _flash -= 50;
      setState(() {});
      if ((g.playerScore, g.aiScore) != before && g.aiScore > before.$2) ctx.sfx(Sfx.tap);
      if (g.over) _end();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  // ---- çevrimiçi ----

  void _startOnline(MatchLink m) {
    _me = m.mySeat;
    final names = m.names;
    _sync = NetSync(
      mySeat: _me,
      seats: math.max(g.seats, names.length),
      humans: {
        for (var i = 0; i < names.length; i++)
          if (names[i].isNotEmpty) i
      },
      snapGapMs: 100,
      send: (d) {
        final rt = _rt;
        if (rt != null) unawaited(rt.pulse(d).catchError((Object _) {}));
      },
    );
    final x = g;
    if (x is SnapGame) x.fairMs = 350;
    _sub = _rt?.pulses.listen((p) => _sync?.receive(p.$1, p.$2, _now));
    _refreshShown(_now);
  }

  void _onlineTick(NetSync s) {
    final now = _now;
    _notes.update(s, now);
    s.takeDemoted();
    final res = s.takeResume();
    if (res != null && s.isHost) g.decode(decodeInts(res.payload));
    if (!s.isHost && s.checkTakeover(now)) {
      final l = s.latest;
      if (l != null) g.decode(decodeInts(l.payload));
    }
    if (s.isHost) {
      for (var p = 0; p < g.seats; p++) {
        g.ai[p] = !s.live(p, now);
      }
      for (final (seat, a) in s.takeActions()) {
        g.act(seat, a);
      }
      g.advance(50);
      final enc = g.encode();
      final key = encodeNums(enc.sublist(1)); // saat hariç
      final force = g.over && !_overSent;
      s.publish(g.time, encodeNums(enc), now, changed: key != _lastKey, force: force);
      if (force) _overSent = true;
      _lastKey = key;
    } else {
      s.pump(now);
    }
    if (_flash > 0) _flash -= 50;
    final winner = _refreshShown(now);
    setState(() {});
    if (winner != null) {
      if (_overAt < 0) _overAt = now;
      if (now - _overAt > 600) _endOnline(winner);
    }
  }

  /// Gösterilen oyunu yenile; oyun bittiyse kazanan koltuğu döndürür.
  int? _refreshShown(int now) {
    final s = _sync;
    if (s == null) return null;
    if (s.isHost) {
      if (_me == 0) {
        shown = g;
      } else {
        shown = RtGame.create(level)
          ..decode(g.encode())
          ..rotate(_me);
      }
      _shownFrom = null;
      _noteFlip(now);
      return g.over ? g.winnerSeat : null;
    }
    final l = s.latest;
    if (l == null) {
      if (!identical(shown, g) || _me == 0) return null;
      shown = RtGame.create(level)..rotate(_me);
      return null;
    }
    int? winner;
    if (!identical(l, _shownFrom)) {
      final v = RtGame.create(level)..decode(decodeInts(l.payload));
      if (v.over) winner = v.winnerSeat;
      v.rotate(_me);
      shown = v;
      _shownFrom = l;
    } else if (shown.over) {
      final v = RtGame.create(level)..decode(decodeInts(l.payload));
      winner = v.winnerSeat;
    }
    if (!shown.over) shown.time = l.t + (now - l.at);
    _noteFlip(now);
    return winner;
  }

  /// Snap: yeni açılan kartın bu ekranda görüldüğü an (tepki süresi için).
  void _noteFlip(int now) {
    final x = shown;
    if (x is SnapGame && x.flips != _seenFlip) {
      _seenFlip = x.flips;
      _seenFlipAt = now;
    }
  }

  /// Çevrimiçi eylem gönder (ev sahibinde bir sonraki tikte uygulanır).
  void _send(String a) {
    _sync?.act(a);
    ctx.sfx(Sfx.tap);
  }

  /// Gösterimdeki koltuğun (0 = ben) adı; yapay zekâ oynuyorsa 🤖.
  String _nameOf(int i) {
    final s = _sync;
    final n = math.max(g.seats, ctx.match?.names.length ?? 0);
    final seat = (i + _me) % n;
    final bot = s == null ? false : (s.isHost ? !s.live(seat, _now) : (s.latest?.isBot(seat) ?? false));
    return netSeatLabel(ctx.lang, ctx.seatName(seat), bot: bot);
  }

  void _endOnline(int winner) {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    final won = winner == _me;
    final m = ctx.match;
    if (m != null) unawaited(m.finish(winner, iWon: won).catchError((Object _) {}));
    ctx.sfx(won ? Sfx.win : Sfx.lose);
    final mine = shown.scoreOf(0);
    ctx.finish(RoundResult(
      won: won,
      score: math.max(0, mine * 10 + (won ? 300 : 0)),
      stars: won ? 2 : 0,
      seconds: shown.time ~/ 1000,
      gameStats: {'quick_wins': won ? 1 : 0, 'cards_won': math.max(0, mine)},
    ));
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    final won = g.playerWon;
    ctx.sfx(won ? Sfx.win : Sfx.lose);
    final margin = (g.playerScore - g.aiScore).abs();
    ctx.finish(RoundResult(
      won: won,
      score: math.max(0, g.playerScore * 10 + (won ? 300 : 0)),
      stars: RealtimeRules.stars(won, level.kind == RtKind.kemps ? 10 - g.time ~/ 6000 : margin),
      seconds: g.time ~/ 1000,
      moves: 0,
      hintsUsed: 0,
      undosUsed: 0,
      gameStats: {'quick_wins': won ? 1 : 0, 'cards_won': math.max(0, g.playerScore)},
    ));
  }

  CardStyle get _style => CardStyle(
        backA: ctx.pieceColors.isNotEmpty ? ctx.pieceColors[0] : const Color(0xFF1F5E8C),
        backB: ctx.pieceColors.length > 1 ? ctx.pieceColors[1] : const Color(0xFF2BB3B1),
        colorBlind: ctx.colorBlind,
      );

  Widget _card(KCard? c, double w, {bool up = true, bool hl = false, VoidCallback? onTap}) {
    final body = SizedBox(
      width: w,
      height: w * 1.4,
      child: c == null ? CustomPaint(painter: _SlotP()) : CustomPaint(painter: _CardP(c, up, _style, hl)),
    );
    return onTap == null ? body : GestureDetector(onTap: onTap, child: body);
  }

  Widget _badge(String text, {bool active = false}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? cs.primaryContainer : cs.surfaceContainerHigh.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  String get _you => netYou(ctx.lang);
  String get _rival => _online ? _nameOf(1) : kt(ctx.lang, 'rival');

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth;
      final cw = math.min(74.0, w / 7);
      final body = switch (shown) {
        SnapGame s => _snap(s, cw),
        SpeedGame s => _speed(s, cw),
        NertzGame s => _nertz(s, math.min(60.0, w / 9)),
        KempsGame s => _kemps(s, cw),
        _ => const SizedBox(),
      };
      final note = _online ? netNoteText(ctx.lang, _notes.note, _notes.seat >= 0 ? ctx.seatName(_notes.seat) : '') : '';
      if (note.isEmpty) return body;
      return Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: Text(note, textAlign: TextAlign.center, maxLines: 2, style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(child: body),
      ]);
    });
  }

  Widget _scoreBar() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          Expanded(
              child: Text('$_you: ${shown.playerScore}  ·  $_rival: ${shown.aiScore}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall)),
          const Icon(Icons.timer_outlined, size: 18),
          Text(' ${shown.time ~/ 60000}:${(shown.time ~/ 1000 % 60).toString().padLeft(2, '0')}'),
        ]),
      );

  // ---- Eşini Yakala
  Widget _snap(SnapGame s, double cw) {
    final top = s.center.length > 3 ? s.center.sublist(s.center.length - 3) : s.center;
    return Column(children: [
      _scoreBar(),
      _badge('$_rival · 🂠 ${s.stacks[1].length}', active: s.turn == 1),
      Expanded(
        child: Center(
          child: SizedBox(
            width: cw * 2.6,
            height: cw * 1.4 + 20,
            child: Stack(children: [
              for (var i = 0; i < top.length; i++)
                Positioned(left: i * cw * 0.55, top: i * 6.0, child: _card(top[i], cw, hl: s.snapOpen && i == top.length - 1)),
            ]),
          ),
        ),
      ),
      _badge('$_you · 🂠 ${s.stacks[0].length}', active: s.turn == 0),
      Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          height: 64,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _flash > 0 ? const Color(0xFFE2574C) : null),
            onPressed: _ended
                ? null
                : () {
                    if (_online) {
                      _send('S${s.flips},${_now - _seenFlipAt}');
                      return;
                    }
                    final ok = s.snap();
                    ctx.sfx(ok ? Sfx.coin : Sfx.error);
                    if (!ok) _flash = 400;
                    setState(() {});
                  },
            child: Text(kt(ctx.lang, 'snap'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          ),
        ),
      ),
    ]);
  }

  // ---- Hız
  Widget _speed(SpeedGame s, double cw) {
    return Column(children: [
      _scoreBar(),
      _badge('$_rival · ${s.hands[1].length} + ${s.draws[1].length}'),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _card(s.hands[1].isNotEmpty ? s.hands[1].first : null, cw * 0.7, up: false),
        const SizedBox(width: 12),
        for (var i = 0; i < 2; i++) ...[
          _card(s.centers[i].isNotEmpty ? s.centers[i].last : null, cw * 1.15),
          const SizedBox(width: 12),
        ],
        Text('↻ ${s.sides[0].length + s.sides[1].length}'),
      ]),
      const Spacer(),
      Wrap(alignment: WrapAlignment.center, spacing: 6, children: [
        for (final c in s.hands[0])
          _card(c, cw, hl: s.targetFor(c) != null, onTap: () {
            if (_online) return _send('P$c');
            final ok = s.play(0, c);
            ctx.sfx(ok ? Sfx.place : Sfx.error);
            setState(() {});
            if (s.over) _end();
          }),
      ]),
      const SizedBox(height: 6),
      _badge('$_you · 🂠 ${s.draws[0].length}'),
      const SizedBox(height: 10),
    ]);
  }

  // ---- Nertz
  Widget _nertz(NertzGame s, double cw) {
    Widget pile(List<KCard> p, int src, {bool fan = false}) {
      if (!fan || p.length <= 1) {
        return _card(p.isNotEmpty ? p.last : null, cw, onTap: () => _nertzMove(s, src));
      }
      final show = p.length > 6 ? p.sublist(p.length - 6) : p;
      return GestureDetector(
        onTap: () => _nertzMove(s, src),
        child: SizedBox(
          width: cw,
          height: cw * 1.4 + (show.length - 1) * cw * 0.32,
          child: Stack(children: [
            for (var i = 0; i < show.length; i++) Positioned(top: i * cw * 0.32, child: _card(show[i], cw)),
          ]),
        ),
      );
    }

    return Column(children: [
      _scoreBar(),
      _badge('$_rival · ${kt(ctx.lang, 'nertz')}: ${s.nertz[1].length}'),
      Padding(
        padding: const EdgeInsets.all(6),
        child: Column(children: [
          Text(kt(ctx.lang, 'foundations'), style: Theme.of(context).textTheme.labelSmall),
          Wrap(spacing: 3, runSpacing: 3, alignment: WrapAlignment.center, children: [
            for (final f in s.foundations) _card(f.last, cw * 0.62),
          ]),
        ]),
      ),
      const Spacer(),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < 4; i++) pile(s.work[0][i], i + 2, fan: true),
      ]),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        Column(children: [
          pile(s.nertz[0], 0),
          Text('${kt(ctx.lang, 'nertz')}: ${s.nertz[0].length}', style: Theme.of(context).textTheme.labelSmall),
        ]),
        GestureDetector(
          onTap: () {
            if (_online) return _send('D');
            s.draw(0);
            ctx.sfx(Sfx.tap);
            setState(() {});
          },
          child: _card(s.stock[0].isNotEmpty ? s.stock[0].last : null, cw, up: false),
        ),
        pile(s.waste[0], 1),
      ]),
      const SizedBox(height: 10),
    ]);
  }

  void _nertzMove(NertzGame s, int src) {
    if (_online) return _send('M$src');
    final ok = s.moveFrom(0, src);
    ctx.sfx(ok ? Sfx.place : Sfx.error);
    setState(() {});
    if (s.over) _end();
  }

  // ---- Kemps
  Widget _kemps(KempsGame s, double cw) {
    return Column(children: [
      _scoreBar(),
      Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
        for (var p = 1; p < 4; p++) _badge(_online ? _nameOf(p) : '$_rival $p'),
      ]),
      const Spacer(),
      Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
        for (final c in s.center)
          _card(c, cw, onTap: () {
            final m = _sel;
            if (m == null) return;
            if (_online) {
              _send('W$m,$c');
              setState(() => _sel = null);
              return;
            }
            final ok = s.swap(0, m, c);
            ctx.sfx(ok ? Sfx.place : Sfx.error);
            setState(() => _sel = null);
          }),
      ]),
      const Spacer(),
      Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
        for (final c in s.hands[0]) _card(c, cw * 1.1, hl: _sel == c, onTap: () => setState(() => _sel = _sel == c ? null : c)),
      ]),
      Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: _ended
                ? null
                : () {
                    if (_online) return _send('K');
                    s.declare();
                    setState(() {});
                    _end();
                  },
            child: Text(kt(ctx.lang, 'kemps'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          ),
        ),
      ),
    ]);
  }
}

class _CardP extends CustomPainter {
  final KCard c;
  final bool up, hl;
  final CardStyle style;
  _CardP(this.c, this.up, this.style, this.hl);
  @override
  void paint(Canvas canvas, Size size) => paintCard(canvas, Offset.zero & size, c, faceUp: up, style: style, highlight: hl);
  @override
  bool shouldRepaint(covariant _CardP o) => o.c != c || o.up != up || o.hl != hl || o.style != style;
}

class _SlotP extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => paintSlot(canvas, Offset.zero & size);
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
