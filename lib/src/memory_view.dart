import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/strings.dart';

import 'card_painter.dart';
import 'table_theme.dart';
import 'memory_engine.dart';
import 'studio_chrome.dart';

/// Kart hafıza ekranı.
class MemoryView extends StatefulWidget {
  final PlayContext ctx;
  const MemoryView({super.key, required this.ctx});

  @override
  State<MemoryView> createState() => _MemoryViewState();
}

class _MemoryViewState extends State<MemoryView> {
  late MemoryLevel level;
  late MemoryGame game;
  final Set<int> _open = {};
  final Set<int> _flash = {};
  bool _busy = false, _ended = false, _peeking = false;
  int _seconds = 0, _hints = 0;
  Timer? _timer;
  double _cw = 40, _ch = 56, _gap = 6, _ox = 0, _oy = 0;

  PlayContext get ctx => widget.ctx;

  @override
  void initState() {
    super.initState();
    level = (ctx.generated as GeneratedLevel<MemoryLevel>).puzzle;
    final snap = ctx.resume['snap'];
    game = snap is String ? MemoryGame.restore(level, snap) : MemoryGame(level);
    _seconds = (ctx.resume['secs'] as num?)?.toInt() ?? 0;
    _hints = (ctx.resume['hints'] as num?)?.toInt() ?? 0;
    if (snap is! String && level.peekSeconds > 0) {
      _peeking = true;
      Future.delayed(Duration(seconds: level.peekSeconds), () {
        if (mounted) setState(() => _peeking = false);
      });
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_ended && !_peeking && mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _persist() => ctx.saveResume({'snap': game.serialize(), 'secs': _seconds, 'hints': _hints});

  CardStyle get _style => kartCardStyle(context, ctx);

  void _tap(int i) {
    if (_busy || _ended || _peeking || game.matched.contains(i) || _open.contains(i)) return;
    final res = game.pick(i);
    setState(() => _open.add(i));
    ctx.sfx(Sfx.tap);
    if (res == null) return;
    if (res) {
      ctx.sfx(Sfx.place);
      setState(_open.clear);
      _persist();
      if (game.won) _end();
      return;
    }
    _busy = true;
    ctx.sfx(Sfx.error);
    Future.delayed(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      setState(() {
        _open.clear();
        _busy = false;
      });
      _persist();
    });
  }

  Future<void> _useHint() async {
    if (_ended || _busy || _peeking || !await ctx.requestHint()) return;
    final h = game.hint();
    if (h == null) return;
    _hints++;
    setState(() => _flash..add(h.$1)..add(h.$2));
    _persist();
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) setState(_flash.clear);
    });
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    ctx.sfx(Sfx.win);
    final stars = game.stars(_hints);
    ctx.finish(RoundResult(
      won: true,
      score: math.max(10, level.pairs * 40 - game.misses * 6 + (stars == 3 ? 100 : 0)),
      stars: stars,
      seconds: _seconds,
      moves: game.moves,
      hintsUsed: _hints,
      undosUsed: 0,
      gameStats: {'pairs_found': level.pairs, 'sharp_boards': stars == 3 ? 1 : 0},
    ));
  }

  String get _ruleText => Strings.pick(switch (level.match) {
        MemoryMatch.exact => _tExact,
        MemoryMatch.rankColor => _tRankColor,
        MemoryMatch.rank => _tRank,
      }, ctx.lang);

  @override
  Widget build(BuildContext context) => FeltTable(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth - 16, h = cons.maxHeight - 120;
      _gap = 6;
      _cw = math.min((w - _gap * (level.cols - 1)) / level.cols, ((h - _gap * (level.rows - 1)) / level.rows) / 1.4);
      _cw = math.max(18, _cw);
      _ch = _cw * 1.4;
      final bw = level.cols * _cw + (level.cols - 1) * _gap, bh = level.rows * _ch + (level.rows - 1) * _gap;
      _ox = (cons.maxWidth - bw) / 2;
      _oy = 0;
      return Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Expanded(
              child: Text(
                '$_ruleText · ${Strings.pick(_tMoves, ctx.lang)}: ${game.moves}',
                style: const TextStyle(color: kStudioText, fontWeight: FontWeight.w800, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            StudioTag(icon: Icons.timer_outlined, text: '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}'),
          ]),
        ),
        Expanded(
          child: Center(
            child: GestureDetector(
              onTapUp: (d) {
                final p = d.localPosition - Offset(_ox, _oy);
                final c = (p.dx / (_cw + _gap)).floor(), r = (p.dy / (_ch + _gap)).floor();
                if (c < 0 || r < 0 || c >= level.cols || r >= level.rows) return;
                _tap(r * level.cols + c);
              },
              child: Semantics(
                label: 'cards',
                child: SizedBox(
                  width: cons.maxWidth,
                  height: bh,
                  child: CustomPaint(painter: _Painter(this)),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            StudioRoundAction(onPressed: _ended ? null : _useHint, icon: Icons.lightbulb, tooltip: ctx.t('hint')),
            StudioTag(icon: Icons.style_rounded, text: '${Strings.pick(_tPairs, ctx.lang)}: ${game.matched.length ~/ 2} / ${level.pairs}'),
          ]),
        ),
      ]);
    });
  }
}

class _Painter extends CustomPainter {
  final _MemoryViewState v;
  _Painter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final lv = v.level;
    final style = v._style;
    for (var i = 0; i < lv.cards.length; i++) {
      final c = i % lv.cols, r = i ~/ lv.cols;
      final rect = Rect.fromLTWH(v._ox + c * (v._cw + v._gap), v._oy + r * (v._ch + v._gap), v._cw, v._ch);
      final done = v.game.matched.contains(i);
      final up = done || v._peeking || v._open.contains(i) || v._flash.contains(i);
      paintCard(canvas, rect, lv.cards[i], faceUp: up, style: style, highlight: v._flash.contains(i), dim: done);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// tr en de es fr ar fa he ur ru uk pl cs ro hu el it pt nl sv da nb fi ja ko zh hi bn id ms th vi fil
const _tExact = ['Aynı iki kartı bul', 'Find two identical cards', 'Finde zwei gleiche Karten', 'Encuentra dos cartas iguales', 'Trouvez deux cartes identiques', 'اعثر على بطاقتين متطابقتين', 'دو کارت یکسان پیدا کن', 'מצאו שני קלפים זהים', 'دو ایک جیسے کارڈ ڈھونڈیں', 'Найдите две одинаковые карты', 'Знайдіть дві однакові карти', 'Znajdź dwie takie same karty', 'Najdi dvě stejné karty', 'Găsește două cărți identice', 'Keress két egyforma lapot', 'Βρες δύο ίδια φύλλα', 'Trova due carte uguali', 'Encontre duas cartas iguais', 'Vind twee dezelfde kaarten', 'Hitta två likadana kort', 'Find to ens kort', 'Finn to like kort', 'Etsi kaksi samaa korttia', '同じカードを2枚探そう', '똑같은 카드 두 장 찾기', '找出两张相同的牌', 'दो एक जैसे पत्ते ढूँढें', 'দুটি একই তাস খুঁজুন', 'Temukan dua kartu sama', 'Cari dua kad sama', 'หาไพ่สองใบที่เหมือนกัน', 'Tìm hai lá giống nhau', 'Hanapin ang dalawang magkaparehong baraha'];
const _tRankColor = ['Aynı sayı, aynı renk', 'Same rank, same colour', 'Gleicher Wert, gleiche Farbe', 'Mismo valor, mismo color', 'Même valeur, même couleur', 'نفس القيمة ونفس اللون', 'هم‌ارزش و هم‌رنگ', 'אותו ערך, אותו צבע', 'ایک درجہ، ایک رنگت', 'То же значение и цвет', 'Те саме значення і колір', 'Ta sama wartość i kolor', 'Stejná hodnota i barva', 'Aceeași valoare și culoare', 'Azonos érték és szín', 'Ίδια αξία, ίδιο χρώμα', 'Stesso valore, stesso colore', 'Mesmo valor, mesma cor', 'Zelfde waarde, zelfde kleur', 'Samma valör, samma kulör', 'Samme værdi, samme farve', 'Samme verdi, samme farge', 'Sama arvo, sama väri', '同じ数で同じ色', '같은 숫자, 같은 색', '点数相同、颜色相同', 'एक ही अंक, एक ही रंगत', 'একই মান, একই বর্ণ', 'Nilai sama, warna sama', 'Nilai sama, warna sama', 'แต้มเดียวกัน สีเดียวกัน', 'Cùng số, cùng màu', 'Parehong halaga at kulay'];
const _tRank = ['Aynı sayı yeter', 'Same rank is enough', 'Gleicher Wert genügt', 'Basta el mismo valor', 'La même valeur suffit', 'تكفي نفس القيمة', 'هم‌ارزش کافی است', 'מספיק אותו ערך', 'ایک ہی درجہ کافی ہے', 'Достаточно того же значения', 'Досить того ж значення', 'Wystarczy ta sama wartość', 'Stačí stejná hodnota', 'Ajunge aceeași valoare', 'Elég az azonos érték', 'Αρκεί η ίδια αξία', 'Basta lo stesso valore', 'Basta o mesmo valor', 'Zelfde waarde is genoeg', 'Samma valör räcker', 'Samme værdi er nok', 'Samme verdi er nok', 'Sama arvo riittää', '同じ数ならOK', '같은 숫자면 충분해요', '点数相同即可', 'एक ही अंक काफ़ी है', 'একই মান হলেই চলবে', 'Nilai sama sudah cukup', 'Nilai sama sudah memadai', 'แต้มเดียวกันก็พอ', 'Cùng số là đủ', 'Sapat na ang parehong halaga'];
const _tMoves = ['Hamle', 'Moves', 'Züge', 'Jugadas', 'Coups', 'الحركات', 'حرکت', 'מהלכים', 'چالیں', 'Ходы', 'Ходи', 'Ruchy', 'Tahy', 'Mutări', 'Lépés', 'Κινήσεις', 'Mosse', 'Jogadas', 'Zetten', 'Drag', 'Træk', 'Trekk', 'Siirrot', '手数', '이동', '步数', 'चालें', 'চাল', 'Langkah', 'Langkah', 'ตา', 'Lượt', 'Galaw'];
const _tPairs = ['Eş', 'Pairs', 'Paare', 'Parejas', 'Paires', 'الأزواج', 'جفت', 'זוגות', 'جوڑے', 'Пары', 'Пари', 'Pary', 'Páry', 'Perechi', 'Párok', 'Ζευγάρια', 'Coppie', 'Pares', 'Paren', 'Par', 'Par', 'Par', 'Parit', 'ペア', '짝', '配对', 'जोड़े', 'জোড়া', 'Pasangan', 'Pasangan', 'คู่', 'Cặp', 'Pares'];
