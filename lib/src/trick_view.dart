import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'card_painter.dart';
import 'cards.dart';
import 'trick_ai.dart';
import 'trick_engine.dart';
import 'trick_rules.dart';

/// Rakipli kart oyunlarının ortak masası: dört (ya da daha az) koltuk, ortada
/// el, altta oyuncunun eli; ihale düğmeleri; ipucu ve geri al.
class TrickView extends StatefulWidget {
  final PlayContext ctx;
  const TrickView({super.key, required this.ctx});

  @override
  State<TrickView> createState() => _TrickViewState();
}

class _TrickViewState extends State<TrickView> {
  late TrickLevel level;
  late TrickState s;
  late List<TrickAI> ais;
  final List<String> _undo = [];
  int _seconds = 0, _hints = 0, _undos = 0;
  Timer? _timer;
  bool _ended = false, _busy = false;
  KCard? _hintCard;
  int? _hintBid;
  List<KCard> _shownTrick = const [];
  int _shownLeader = 0, _shownWinner = -1;

  PlayContext get ctx => widget.ctx;
  TrickRules get rules => level.rules;

  @override
  void initState() {
    super.initState();
    level = (ctx.generated as GeneratedLevel<TrickLevel>).puzzle;
    final snap = ctx.resume['snap'];
    s = snap is String ? TrickState.fromJson(_decode(snap)) : level.start.copy();
    _seconds = (ctx.resume['secs'] as num?)?.toInt() ?? 0;
    _hints = (ctx.resume['hints'] as num?)?.toInt() ?? 0;
    final r = SeededRandom(mixSeed([level.seed, 99, _seconds]));
    ais = [
      for (var p = 0; p < s.seats; p++)
        TrickAI(rules, rules.partnerships && p == 2 ? 16 : level.aiSamples, r),
    ];
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_ended && mounted) setState(() => _seconds++);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
  }

  static Map<String, dynamic> _decode(String s) => jsonDecode(s) as Map<String, dynamic>;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _persist() => ctx.saveResume({'snap': s.serialize(), 'secs': _seconds, 'hints': _hints});

  Duration get _pace => ctx.reducedMotion ? const Duration(milliseconds: 150) : const Duration(milliseconds: 520);

  /// Yapay zekâ koltuklarını sırası gelince oynat.
  Future<void> _advance() async {
    if (_busy) return;
    _busy = true;
    while (mounted && !_ended && s.phase != TrickPhase.over && s.turn != 0) {
      await Future<void>.delayed(_pace);
      if (!mounted) return;
      final seat = s.turn;
      if (s.phase == TrickPhase.bidding) {
        rules.applyBid(s, seat, ais[seat].bid(s, seat));
        if (rules.biddingOver(s)) rules.finishBidding(s);
        setState(() {});
      } else {
        await _playCard(seat, ais[seat].play(s, seat));
      }
    }
    _busy = false;
    _persist();
    if (s.phase == TrickPhase.over) _end();
  }

  Future<void> _playCard(int seat, KCard c) async {
    final before = List<KCard>.of(s.trick);
    final leader = s.leader;
    rules.play(s, seat, c);
    ctx.sfx(Sfx.place);
    if (before.length == s.seats - 1) {
      // El tamamlandı: kartları kısa süre göster, kazananı işaretle.
      setState(() {
        _shownTrick = [...before, c];
        _shownLeader = leader;
        _shownWinner = s.lastWinner;
      });
      await Future<void>.delayed(_pace * 1.6);
      if (!mounted) return;
      ctx.sfx(s.lastWinner == 0 || (rules.partnerships && s.lastWinner == 2) ? Sfx.coin : Sfx.tap);
      setState(() => _shownTrick = const []);
    } else {
      setState(() {});
    }
  }

  Future<void> _humanPlay(KCard c) async {
    if (_ended || _busy || s.turn != 0 || s.phase != TrickPhase.play) return;
    if (!rules.legalPlays(s, 0).contains(c)) {
      ctx.sfx(Sfx.error);
      return;
    }
    _undo.add(s.serialize());
    _hintCard = null;
    _busy = true;
    await _playCard(0, c);
    _busy = false;
    _persist();
    _advance();
  }

  void _humanBid(int bid) {
    if (_ended || _busy || s.turn != 0 || s.phase != TrickPhase.bidding) return;
    _undo.add(s.serialize());
    rules.applyBid(s, 0, bid);
    if (rules.biddingOver(s)) rules.finishBidding(s);
    setState(() => _hintBid = null);
    _persist();
    _advance();
  }

  void _doUndo() {
    if (_undo.isEmpty || _busy || _ended) return;
    setState(() {
      s = TrickState.fromJson(_decode(_undo.removeLast()));
      _undos++;
      _hintCard = null;
      _shownTrick = const [];
    });
    _persist();
  }

  Future<void> _hint() async {
    if (_ended || _busy || s.turn != 0 || !await ctx.requestHint()) return;
    _hints++;
    final adv = TrickAI(rules, 30, SeededRandom(mixSeed([level.seed, _seconds, 3])));
    setState(() {
      if (s.phase == TrickPhase.bidding) {
        _hintBid = adv.bid(s, 0);
      } else {
        _hintCard = adv.play(s, 0);
      }
    });
    _persist();
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    final won = level.goal.check(rules, s);
    ctx.sfx(won ? Sfx.win : Sfx.lose);
    final mine = s.tricks[0] + (rules.partnerships ? s.tricks[2] : 0);
    ctx.finish(RoundResult(
      won: won,
      score: math.max(0, (rules.utility(s, 0) * 10).round() + mine * 20 + (won ? 300 : 0)),
      stars: TrickGameRules.stars(won: won, hints: _hints, undos: _undos),
      seconds: _seconds,
      moves: s.played.length,
      hintsUsed: _hints,
      undosUsed: _undos,
      gameStats: {'tricks_taken': s.tricks[0], 'hands_won': won ? 1 : 0},
    ));
  }

  // ---- görünüm ----

  CardStyle get _style => CardStyle(
        backA: ctx.pieceColors.isNotEmpty ? ctx.pieceColors[0] : const Color(0xFF1F5E8C),
        backB: ctx.pieceColors.length > 1 ? ctx.pieceColors[1] : const Color(0xFF2BB3B1),
        colorBlind: ctx.colorBlind,
      );

  /// Koltuğun ekrandaki yeri: 0 alt, sonra saat yönünde.
  Alignment _seatAlign(int seat) {
    final n = s.seats;
    if (n == 2) return seat == 0 ? Alignment.bottomCenter : Alignment.topCenter;
    if (n == 3) return const [Alignment.bottomCenter, Alignment.centerLeft, Alignment.centerRight][seat];
    return const [Alignment.bottomCenter, Alignment.centerLeft, Alignment.topCenter, Alignment.centerRight][seat % 4];
  }

  String _seatName(int seat) {
    if (seat == 0) return Strings.tx(ctx.lang, 'Sen', 'You');
    if (rules.partnerships && seat == 2) return Strings.tx(ctx.lang, 'Eşin', 'Partner');
    final a = _seatAlign(seat);
    if (a == Alignment.centerLeft) return Strings.tx(ctx.lang, 'Sol', 'Left');
    if (a == Alignment.centerRight) return Strings.tx(ctx.lang, 'Sağ', 'Right');
    return Strings.tx(ctx.lang, 'Karşı', 'Across');
  }

  Widget _seatBadge(int seat) {
    final bid = s.bids[seat];
    final active = s.turn == seat && s.phase != TrickPhase.over;
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? cs.primaryContainer : cs.surfaceContainerHigh.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: active ? cs.primary : Colors.transparent, width: 2),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_seatName(seat), style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('${Strings.tx(ctx.lang, 'El', 'Tricks')}: ${s.tricks[seat]}'
            '${bid != null ? '  ·  ${rules.bidLabel(bid, ctx.lang)}' : ''}'
            '${seat != 0 ? '  ·  🂠${s.hands[seat].length}' : ''}',
            style: const TextStyle(fontSize: 12)),
      ]),
    );
  }

  Widget _card(KCard c, double w, {bool up = true, bool dim = false, bool hl = false}) => SizedBox(
        width: w,
        height: w * 1.4,
        child: CustomPaint(painter: _CardP(c, up, _style, dim, hl)),
      );

  @override
  Widget build(BuildContext context) {
    final trumpTxt = s.trump >= 0 ? ['♠', '♥', '♦', '♣'][s.trump] : null;
    final status = rules.status(s, ctx.lang);
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth, h = cons.maxHeight;
      final handLen = math.max(1, s.hands[0].length);
      final cw = math.min(76.0, math.min(w / (handLen * 0.62 + 0.6), h * 0.16));
      final tw = math.min(70.0, w * 0.15);
      final legal = s.turn == 0 && s.phase == TrickPhase.play ? rules.legalPlays(s, 0).toSet() : <KCard>{};
      final trickCards = _shownTrick.isNotEmpty ? _shownTrick : s.trick;
      final trickLeader = _shownTrick.isNotEmpty ? _shownLeader : s.leader;
      return Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            Expanded(
              child: Text(level.goal.text(rules, s, ctx.lang),
                  style: Theme.of(context).textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            if (trumpTxt != null)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: Text('${Strings.tx(ctx.lang, 'Koz', 'Trump')} $trumpTxt',
                    style: TextStyle(color: _style.suitColor(s.trump), fontWeight: FontWeight.w800)),
              ),
            const SizedBox(width: 8),
            const Icon(Icons.timer_outlined, size: 18),
            Text(' ${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}'),
          ]),
        ),
        if (status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(status, style: Theme.of(context).textTheme.bodySmall),
          ),
        Expanded(
          child: Stack(children: [
            for (var p = 1; p < s.seats; p++)
              Align(alignment: _seatAlign(p), child: Padding(padding: const EdgeInsets.all(6), child: _seatBadge(p))),
            // Ortadaki el
            Center(
              child: SizedBox(
                width: tw * 3.4,
                height: tw * 1.4 * 2.6,
                child: Stack(children: [
                  for (var i = 0; i < trickCards.length; i++)
                    () {
                      final seat = (trickLeader + i) % s.seats;
                      final a = _seatAlign(seat);
                      return Align(
                        alignment: Alignment(a.x * 0.7, a.y * 0.75),
                        child: AnimatedScale(
                          scale: _shownWinner == seat && _shownTrick.isNotEmpty ? 1.08 : 1,
                          duration: const Duration(milliseconds: 200),
                          child: _card(trickCards[i], tw, hl: _shownWinner == seat && _shownTrick.isNotEmpty),
                        ),
                      );
                    }(),
                ]),
              ),
            ),
            if (s.phase == TrickPhase.bidding && s.turn == 0 && !_busy)
              Align(
                alignment: const Alignment(0, 0.55),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(Strings.tx(ctx.lang, 'İhalen?', 'Your bid?'), style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
                        for (final b in rules.legalBids(s, 0))
                          FilledButton.tonal(
                            style: _hintBid == b
                                ? FilledButton.styleFrom(backgroundColor: const Color(0xFFFFC53D))
                                : null,
                            onPressed: () => _humanBid(b),
                            child: Text(rules.bidLabel(b, ctx.lang)),
                          ),
                      ]),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
        _seatBadge(0),
        const SizedBox(height: 4),
        // Oyuncunun eli
        SizedBox(
          height: cw * 1.4 + 18,
          child: LayoutBuilder(builder: (context, c2) {
            final n = s.hands[0].length;
            final step = n <= 1 ? 0.0 : math.min(cw * 0.95, (c2.maxWidth - cw - 8) / (n - 1));
            final total = cw + step * math.max(0, n - 1);
            final left0 = (c2.maxWidth - total) / 2;
            return Stack(children: [
              for (var i = 0; i < n; i++)
                () {
                  final c = s.hands[0][i];
                  final ok = legal.contains(c);
                  return AnimatedPositioned(
                    key: ValueKey(c),
                    duration: const Duration(milliseconds: 180),
                    left: left0 + step * i,
                    top: ok ? 0 : 14,
                    child: GestureDetector(
                      onTap: () => _humanPlay(c),
                      child: _card(c, cw, dim: s.phase == TrickPhase.play && s.turn == 0 && !ok, hl: _hintCard == c),
                    ),
                  );
                }(),
            ]);
          }),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            IconButton.filledTonal(
                onPressed: _ended || _busy || s.turn != 0 ? null : _hint,
                icon: const Icon(Icons.lightbulb),
                tooltip: ctx.t('hint')),
            IconButton.filledTonal(
                onPressed: _undo.isNotEmpty && !_busy && !_ended ? _doUndo : null,
                icon: const Icon(Icons.undo),
                tooltip: ctx.t('undo')),
          ]),
        ),
      ]);
    });
  }
}

class _CardP extends CustomPainter {
  final KCard c;
  final bool up, dim, hl;
  final CardStyle style;
  _CardP(this.c, this.up, this.style, this.dim, this.hl);
  @override
  void paint(Canvas canvas, Size size) =>
      paintCard(canvas, Offset.zero & size, c, faceUp: up, style: style, dim: dim, highlight: hl);
  @override
  bool shouldRepaint(covariant _CardP o) => o.c != c || o.up != up || o.dim != dim || o.hl != hl || o.style != style;
}
