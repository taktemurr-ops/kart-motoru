import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'card_painter.dart';
import 'cards.dart';
import 'kart_texts.dart';
import 'match.dart';
import 'table_rules.dart';
import 'table_view.dart';
import 'trick_rules.dart';
import 'trick_view.dart';

/// "Maç" modu: hedef puana (ya da el sayısına) kadar çok elli oyun. Her el
/// mevcut masa ekranında ([TrickHandView] / [TableHandView]) oynanır; puan
/// tablosu tutulur, dağıtan döner, maç kaydedilip sürdürülebilir.
///
/// Çevrimiçi masada her hamle `d<el>|<hamle>` biçiminde gönderilir; maçın
/// türü ev sahibinin "m:1"/"m:0" mesajıyla, King/Trix sözleşmesi seçenin
/// `d<el>|k:<seçim>` mesajıyla belirlenir. Böylece maç geçmişten aynen
/// yeniden oynanır.
class MatchView extends StatefulWidget {
  final PlayContext ctx;
  const MatchView({super.key, required this.ctx});

  /// Bu oyun ekranı maç olarak mı açılmalı (Maç modu ya da çok oyunculu masa).
  static bool wants(PlayContext ctx) {
    final mode = ctx.spec.mode;
    if (mode != GameModeId.endless && mode != GameModeId.versus && mode != GameModeId.online) return false;
    return MatchPlan.of(ctx.generated.puzzle) != null;
  }

  @override
  State<MatchView> createState() => _MatchViewState();
}

enum _Phase { mode, single, choose, play, between, over }

class _MatchViewState extends State<MatchView> {
  late MatchPlan plan;
  late MatchState m;
  _Phase phase = _Phase.play;
  Object? level;
  Map<String, Object?> handResume = const {};
  int handKey = 0;
  bool _uncovered = false;
  bool _finished = false;
  Timer? _timer, _auto;
  StreamSubscription<(int, String)>? _sub;
  final List<(int, String)> _log = [];
  _DealLink? _link;
  late int _difficulty, _samples;

  PlayContext get ctx => widget.ctx;
  MatchLink? get net => ctx.match;
  String get lang => ctx.lang;
  bool get _multi => ctx.seats.isNotEmpty;
  int get me => net?.mySeat ?? 0;
  bool _isLocal(int seat) => _multi ? ctx.role(seat) == SeatRole.local : seat == 0;
  bool _isAi(int seat) => _multi ? (ctx.role(seat) == SeatRole.ai || (net?.dropped.contains(seat) ?? false)) : seat != 0;

  @override
  void initState() {
    super.initState();
    final p = ctx.generated.puzzle;
    plan = MatchPlan.of(p)!;
    if (p is TrickLevel) {
      _difficulty = p.difficulty;
      _samples = p.aiSamples;
    } else if (p is TableLevel) {
      _difficulty = p.difficulty;
      _samples = p.aiSamples;
    } else {
      _difficulty = 4;
      _samples = 4;
    }
    final saved = ctx.resume['match'];
    // Çevrimiçi maç her zaman hamle geçmişinden yeniden kurulur.
    if (net == null && saved is String) {
      m = MatchState.fromJson(jsonDecode(saved) as Map<String, dynamic>);
      final h = ctx.resume['hand'];
      if (h is String && h.isNotEmpty) handResume = Map<String, Object?>.from(jsonDecode(h) as Map);
    } else {
      m = MatchState.start(plan, ctx.spec.seed);
    }
    if (ctx.spec.mode == GameModeId.endless) m.mode = 1;
    final n = net;
    if (n != null) {
      _log.addAll(n.history);
      _sub = n.moves.listen(_onMsg);
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (phase == _Phase.over || !mounted) return;
      m.secs++;
      // Çevrimiçi: seçim bekleyen koltuk düştüyse ev sahibi onun yerine seçer.
      if (net != null && (phase == _Phase.choose || phase == _Phase.mode) && m.secs % 3 == 0) _next();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _next(resume: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _auto?.cancel();
    _sub?.cancel();
    _link?.close();
    super.dispose();
  }

  void _persist() {
    ctx.saveResume({'match': jsonEncode(m.toJson()), 'hand': jsonEncode(handResume), 'secs': m.secs});
  }

  // ---- çevrimiçi mesajlar ----------------------------------------------------

  void _onMsg((int, String) e) {
    _log.add(e);
    _link?.push(e);
    if (!mounted) return;
    if (phase == _Phase.mode && e.$2.startsWith('m:')) _next();
    if (phase == _Phase.choose && e.$2.startsWith('d${m.dealt}|k:')) _next();
  }

  int? _logMode() {
    for (final e in _log) {
      if (e.$2.startsWith('m:')) return int.tryParse(e.$2.substring(2));
    }
    return null;
  }

  int? _logChoice(int deal) {
    final pre = 'd$deal|k:';
    for (final e in _log) {
      if (e.$2.startsWith(pre)) return int.tryParse(e.$2.substring(pre.length));
    }
    return null;
  }

  /// Geçmişte bu elden sonraki ellere ait hamle var mı (yeniden oynatma).
  bool _replaying() {
    for (final e in _log) {
      final s = e.$2;
      if (!s.startsWith('d')) continue;
      final i = s.indexOf('|');
      final d = i > 1 ? int.tryParse(s.substring(1, i)) : null;
      if (d != null && d >= m.dealt) return true;
    }
    return false;
  }

  // ---- akış ---------------------------------------------------------------

  void _next({bool resume = false}) {
    if (!mounted) return;
    if (m.mode < 0) {
      final lm = _logMode();
      if (lm != null) {
        m.mode = lm == 1 ? 1 : 0;
      } else {
        setState(() => phase = _Phase.mode);
        return;
      }
    }
    if (m.mode == 0) {
      _link?.close();
      _link = net == null ? null : _DealLink(net!, '', _log, skip: 'm:');
      setState(() => phase = _Phase.single);
      return;
    }
    final out = plan.outcome(m);
    if (out != null) {
      _over();
      return;
    }
    final c = plan.chooser(m);
    if (c >= 0 && m.choice < 0) {
      final logged = _logChoice(m.dealt);
      if (logged != null && plan.options(m).contains(logged)) {
        m.choice = logged;
      } else if (_isAi(c) && (net == null || net!.isHost)) {
        final o = plan.aiOption(m, SeededRandom(mixSeed([m.seed, m.dealt, 77])));
        unawaited(net?.send('d${m.dealt}|k:$o', asSeat: c));
        m.choice = o;
      } else {
        setState(() {
          phase = _Phase.choose;
          _uncovered = !ctx.passAndPlay;
        });
        return;
      }
    }
    _startDeal(keepResume: resume);
  }

  void _setMode(int v) {
    if (m.mode >= 0) return;
    unawaited(net?.send('m:$v'));
    m.mode = v;
    _persist();
    _next();
  }

  void _pick(int o) {
    if (phase != _Phase.choose || !plan.options(m).contains(o)) return;
    final c = plan.chooser(m);
    unawaited(net?.send('d${m.dealt}|k:$o', asSeat: net != null && c != me ? c : null));
    m.choice = o;
    ctx.sfx(Sfx.tap);
    _startDeal();
  }

  String _caption(String lang) {
    final parts = <String>[
      plan.dealName(m, lang),
      if (plan.chooser(m) >= 0 && m.choice >= 0) plan.optionLabel(m.choice, lang),
      '${kt(lang, 'dealer')}: ${_seatName(plan.dealerOf(m))}',
    ];
    return parts.join('  ·  ');
  }

  void _startDeal({bool keepResume = false}) {
    if (!keepResume) handResume = const {};
    level = plan.level(m, difficulty: _difficulty, samples: _samples, caption: _caption);
    _link?.close();
    _link = net == null ? null : _DealLink(net!, 'd${m.dealt}|', _log);
    handKey++;
    setState(() => phase = _Phase.play);
    _persist();
  }

  void _handOver(Object end) {
    final lv = level;
    if (lv == null || phase != _Phase.play) return;
    final pts = plan.score(lv, end);
    plan.record(m, pts);
    handResume = const {};
    _persist();
    if (pts == null) {
      // Herkes pas: yeniden dağıt.
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(kt(lang, 'redeal')), duration: const Duration(seconds: 2)));
      _next();
      return;
    }
    if (plan.outcome(m) != null) {
      _over();
      return;
    }
    setState(() => phase = _Phase.between);
    _auto?.cancel();
    if (net != null) {
      if (_replaying()) {
        _next();
        return;
      }
      _auto = Timer(const Duration(seconds: 6), () {
        if (mounted && phase == _Phase.between) _next();
      });
    }
  }

  void _over() {
    if (phase == _Phase.over) return;
    final out = plan.outcome(m) ?? -1;
    final won = _iWon(out);
    ctx.sfx(won ? Sfx.win : Sfx.lose);
    final n = net;
    if (n != null) unawaited(n.finish(out < 0 ? -1 : out, iWon: won));
    setState(() => phase = _Phase.over);
    _persist();
  }

  bool _iWon(int out) {
    if (out < 0) return false;
    if (_multi && net == null) return true;
    return out == plan.sideOf(me);
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    final out = plan.outcome(m) ?? -1;
    final won = _iWon(out);
    final trick = level is TrickLevel || ctx.generated.puzzle is TrickLevel;
    ctx.finish(RoundResult(
      won: won,
      score: won ? 600 : 60,
      stars: won ? 3 : 0,
      seconds: m.secs,
      moves: m.dealt,
      headline: out < 0
          ? ctx.t('draw_title')
          : (_multi && net == null ? '${kt(lang, 'matchOver')}: ${_sideName(out)}' : null),
      gameStats: trick ? {'hands_won': won ? 1 : 0} : {'games_won': won ? 1 : 0},
    ));
  }

  // ---- adlar --------------------------------------------------------------

  String _seatName(int seat) {
    final n = plan.seats;
    if (_multi && (ctx.passAndPlay || ctx.role(seat) != SeatRole.ai)) {
      return seat == me && net != null ? Strings.tx(lang, 'Sen', 'You') : ctx.seatName(seat);
    }
    if (seat == me) return Strings.tx(lang, 'Sen', 'You');
    final rel = (seat - me + n) % n;
    if (n == 2) return kt(lang, 'rival');
    if (n == 3) return rel == 1 ? Strings.tx(lang, 'Sol', 'Left') : Strings.tx(lang, 'Sağ', 'Right');
    if (plan.partnerships && rel == 2) return Strings.tx(lang, 'Eşin', 'Partner');
    return [
      '',
      Strings.tx(lang, 'Sol', 'Left'),
      Strings.tx(lang, 'Karşı', 'Across'),
      Strings.tx(lang, 'Sağ', 'Right'),
    ][rel % 4];
  }

  String _sideName(int side) {
    if (!plan.partnerships) return _seatName(side);
    if (ctx.passAndPlay) return '${ctx.seatName(side)} + ${ctx.seatName(side + 2)}';
    return side == plan.sideOf(me) ? Strings.tx(lang, 'Biz', 'Us') : Strings.tx(lang, 'Onlar', 'Them');
  }

  String _formatLine() {
    final own = plan.formatLabel(lang);
    if (own != null) return own;
    final f = plan.format;
    if (f.target > 0) {
      return '${kt(lang, 'target')}: ${f.target}${f.lowWins ? '  ·  ${kt(lang, 'least')}' : ''}';
    }
    if (f.start > 0) return '${kt(lang, 'startPts')}: ${f.start}';
    return '${f.deals} × ${kt(lang, 'deal')}${f.lowWins ? '  ·  ${kt(lang, 'least')}' : ''}';
  }

  // ---- görünüm --------------------------------------------------------------

  PlayContext _subCtx(Object lv) {
    final GeneratedLevel gen = lv is TrickLevel
        ? GeneratedLevel<TrickLevel>(ctx.spec, lv, const Validation.ok(0), 0)
        : GeneratedLevel<TableLevel>(ctx.spec, lv as TableLevel, const Validation.ok(0), 0);
    return PlayContext(
      spec: ctx.spec,
      generated: gen,
      resume: handResume,
      pieceColors: ctx.pieceColors,
      background: ctx.background,
      colorBlind: ctx.colorBlind,
      reducedMotion: ctx.reducedMotion,
      leftHanded: ctx.leftHanded,
      lang: ctx.lang,
      t: ctx.t,
      finish: (_) {},
      saveResume: (h) {
        handResume = Map<String, Object?>.of(h);
        _persist();
      },
      requestHint: ctx.requestHint,
      requestBooster: ctx.requestBooster,
      requestContinue: ctx.requestContinue,
      sfx: ctx.sfx,
      sound: ctx.sound,
      seats: ctx.seats,
      match: _link,
    );
  }

  /// Çok oyunculu masada tek el: özgün bağlam, "m:" mesajları süzülür.
  PlayContext _singleCtx() => PlayContext(
        spec: ctx.spec,
        generated: ctx.generated,
        resume: ctx.resume,
        pieceColors: ctx.pieceColors,
        background: ctx.background,
        colorBlind: ctx.colorBlind,
        reducedMotion: ctx.reducedMotion,
        leftHanded: ctx.leftHanded,
        lang: ctx.lang,
        t: ctx.t,
        finish: ctx.finish,
        // Mod seçimi kaydı korunur: devam edince yeniden sorulmaz.
        saveResume: (h) => ctx.saveResume({...h, 'match': jsonEncode(m.toJson())}),
        requestHint: ctx.requestHint,
        requestBooster: ctx.requestBooster,
        requestContinue: ctx.requestContinue,
        sfx: ctx.sfx,
        sound: ctx.sound,
        seats: ctx.seats,
        match: _link == null ? null : _FinishingLink(_link!, net!),
      );

  @override
  Widget build(BuildContext context) {
    if (phase == _Phase.single) {
      final c = _singleCtx();
      return ctx.generated.puzzle is TrickLevel ? TrickHandView(ctx: c) : TableHandView(ctx: c);
    }
    final lv = level;
    Widget body;
    if (phase == _Phase.play && lv != null) {
      final c = _subCtx(lv);
      body = lv is TrickLevel
          ? TrickHandView(key: ValueKey('h$handKey'), ctx: c, onHandOver: _handOver)
          : TableHandView(key: ValueKey('h$handKey'), ctx: c, onHandOver: _handOver);
    } else if (phase == _Phase.mode) {
      body = FeltTable(child: Center(child: _modePanel()));
    } else if (phase == _Phase.choose) {
      body = FeltTable(child: Center(child: _choosePanel()));
    } else if (phase == _Phase.between || phase == _Phase.over) {
      body = FeltTable(child: Center(child: _scorePanel(isLast: phase == _Phase.over)));
    } else {
      body = const FeltTable(child: SizedBox.expand());
    }
    return Column(children: [
      if (phase != _Phase.mode) _header(context),
      Expanded(child: body),
    ]);
  }

  Widget _header(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = plan.totals(m);
    return Material(
      color: cs.surfaceContainerHigh,
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(kt(lang, 'scoreboard')),
            content: SizedBox(width: 420, child: _scoreTable(context)),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(kt(lang, 'done')))],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(children: [
            Icon(Icons.emoji_events_outlined, size: 18, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (var i = 0; i < plan.sides; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text('${_sideName(i)} ${t[i]}',
                          style: TextStyle(
                              fontWeight: i == plan.sideOf(me) ? FontWeight.w800 : FontWeight.w500, fontSize: 13)),
                    ),
                ]),
              ),
            ),
            Text(_formatLine(), style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(width: 4),
            Icon(Icons.table_rows_outlined, size: 16, color: cs.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }

  Widget _scoreTable(BuildContext context) {
    final sides = plan.sides;
    final t = plan.totals(m);
    final bold = Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800);
    Widget cell(String s, {TextStyle? st, bool left = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          child: Text(s, style: st, textAlign: left ? TextAlign.start : TextAlign.end),
        );
    final rows = <TableRow>[
      TableRow(children: [
        cell(kt(lang, 'deal'), st: bold, left: true),
        for (var i = 0; i < sides; i++) cell(_sideName(i), st: bold),
      ]),
      if (plan.format.start > 0)
        TableRow(children: [
          cell(kt(lang, 'startPts'), left: true),
          for (var i = 0; i < sides; i++) cell('${plan.format.start}'),
        ]),
      for (var d = 0; d < m.points.length; d++)
        TableRow(children: [
          cell('${d + 1}${(plan.rowLabel(m, d, lang) ?? '').isEmpty ? '' : ' · ${plan.rowLabel(m, d, lang)}'}', left: true),
          for (var i = 0; i < sides; i++) cell('${i < m.points[d].length ? m.points[d][i] : 0}'),
        ]),
      TableRow(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerColor))),
        children: [
          cell('Σ', st: bold, left: true),
          for (var i = 0; i < sides; i++) cell('${t[i]}', st: bold),
        ],
      ),
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 380),
      child: SingleChildScrollView(
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: const {0: FlexColumnWidth(2.2)},
          children: rows,
        ),
      ),
    );
  }

  Widget _card(Widget child) => Card(
        margin: const EdgeInsets.all(16),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      );

  Widget _modePanel() {
    final host = net == null || net!.isHost;
    if (!host) {
      return _card(Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(kt(lang, 'waitHost'), textAlign: TextAlign.center),
      ]));
    }
    return _card(Column(mainAxisSize: MainAxisSize.min, children: [
      Text(kt(lang, 'howToPlay'), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 14),
      SizedBox(
        width: 280,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: const Icon(Icons.emoji_events),
          onPressed: () => _setMode(1),
          label: Text('${kt(lang, 'match')}  ·  ${_formatLine()}', textAlign: TextAlign.center),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: 280,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: const Icon(Icons.style),
          onPressed: () => _setMode(0),
          label: Text(kt(lang, 'singleHand')),
        ),
      ),
    ]));
  }

  CardStyle get _style => CardStyle(
        backA: ctx.pieceColors.isNotEmpty ? ctx.pieceColors[0] : const Color(0xFF1F5E8C),
        backB: ctx.pieceColors.length > 1 ? ctx.pieceColors[1] : const Color(0xFF2BB3B1),
        colorBlind: ctx.colorBlind,
      );

  Widget _choosePanel() {
    final c = plan.chooser(m);
    final local = _isLocal(c);
    final title = plan is TrixMatchPlan
        ? '${kt(lang, 'kingdom')} ${(plan as TrixMatchPlan).kingdom(m) + 1}/4  ·  ${_seatName(c)}'
        : '${kt(lang, 'deal')} ${m.played + 1}/${plan.format.deals}  ·  ${_seatName(c)}';
    if (!local) {
      return _card(Column(mainAxisSize: MainAxisSize.min, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(kt(lang, 'choosing')),
      ]));
    }
    if (!_uncovered) {
      return _card(InkWell(
        onTap: () => setState(() => _uncovered = true),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.swap_horiz, size: 32),
          Text(ctx.t('pass_device', {'p': ctx.seatName(c)}),
              textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(ctx.t('tap_when_ready')),
        ]),
      ));
    }
    final hand = plan.chooserHand(m);
    return LayoutBuilder(builder: (context, cons) {
      final cw = math.min(46.0, (cons.maxWidth - 64) / 7.5);
      return SingleChildScrollView(
        child: _card(Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(kt(lang, 'chooseContract'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Wrap(spacing: 2, runSpacing: 4, alignment: WrapAlignment.center, children: [
            for (final k in hand)
              SizedBox(width: cw, height: cw * 1.4, child: CustomPaint(painter: _MiniCard(k, _style))),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            for (final o in plan.options(m))
              FilledButton.tonal(onPressed: () => _pick(o), child: Text(plan.optionLabel(o, lang))),
          ]),
        ])),
      );
    });
  }

  Widget _scorePanel({required bool isLast}) {
    final out = isLast ? (plan.outcome(m) ?? -1) : null;
    final title = isLast
        ? (out! < 0 ? ctx.t('draw_title') : '${kt(lang, 'matchOver')}: ${_sideName(out)}')
        : '${kt(lang, 'deal')} ${m.played}  ·  ${kt(lang, 'scoreboard')}';
    return SingleChildScrollView(
      child: _card(Column(mainAxisSize: MainAxisSize.min, children: [
        if (isLast) Icon(out! >= 0 && _iWon(out) ? Icons.emoji_events : Icons.flag, size: 40, color: const Color(0xFFFFB300)),
        Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(_formatLine(), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        SizedBox(width: 420, child: _scoreTable(context)),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(220, 48)),
          icon: Icon(isLast ? Icons.check : Icons.play_arrow),
          onPressed: isLast
              ? _finish
              : () {
                  _auto?.cancel();
                  _next();
                },
          label: Text(isLast ? kt(lang, 'done') : kt(lang, 'nextDeal')),
        ),
      ])),
    );
  }
}

class _MiniCard extends CustomPainter {
  final KCard c;
  final CardStyle style;
  _MiniCard(this.c, this.style);
  @override
  void paint(Canvas canvas, Size size) => paintCard(canvas, Offset.zero & size, c, faceUp: true, style: style);
  @override
  bool shouldRepaint(covariant _MiniCard o) => o.c != c || o.style != style;
}

/// Maçın bir elinin ağ bağlantısı: hamleler `d<el>|` önekiyle gider; yalnız
/// bu elin hamleleri ekrana iletilir. Elin sonu maçı bitirmez.
class _DealLink implements MatchLink {
  final MatchLink inner;
  final String prefix;
  final List<(int, String)> log;
  final String? skip;
  final _ctl = StreamController<(int, String)>.broadcast();
  bool _closed = false;

  _DealLink(this.inner, this.prefix, this.log, {this.skip});

  bool _mine(String s) => s.startsWith(prefix) && (skip == null || !s.startsWith(skip!)) && (prefix.isNotEmpty || !s.startsWith('d'));

  void push((int, String) e) {
    if (!_closed && _mine(e.$2)) _ctl.add((e.$1, e.$2.substring(prefix.length)));
  }

  void close() {
    _closed = true;
    unawaited(_ctl.close());
  }

  @override
  int get mySeat => inner.mySeat;
  @override
  int get seed => inner.seed;
  @override
  List<String> get names => inner.names;
  @override
  bool get isHost => inner.isHost;
  @override
  Set<int> get dropped => inner.dropped;
  @override
  Stream<(int, String)> get moves => _ctl.stream;
  @override
  List<(int, String)> get history => [
        for (final e in log)
          if (_mine(e.$2)) (e.$1, e.$2.substring(prefix.length)),
      ];
  @override
  Future<void> send(String move, {int? asSeat}) => inner.send('$prefix$move', asSeat: asSeat);
  @override
  Future<void> finish(int winner, {bool? iWon}) async {}
}

/// Tek el oynanan çok oyunculu masada maçı bitiren bağlantı.
class _FinishingLink implements MatchLink {
  final _DealLink link;
  final MatchLink inner;
  _FinishingLink(this.link, this.inner);

  @override
  int get mySeat => link.mySeat;
  @override
  int get seed => link.seed;
  @override
  List<String> get names => link.names;
  @override
  bool get isHost => link.isHost;
  @override
  Set<int> get dropped => link.dropped;
  @override
  Stream<(int, String)> get moves => link.moves;
  @override
  List<(int, String)> get history => link.history;
  @override
  Future<void> send(String move, {int? asSeat}) => link.send(move, asSeat: asSeat);
  @override
  Future<void> finish(int winner, {bool? iWon}) => inner.finish(winner, iWon: iWon);
}
