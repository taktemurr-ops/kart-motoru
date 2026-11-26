import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/strings.dart';

import 'card_painter.dart';
import 'trail.dart';
import 'studio_chrome.dart';

/// Kart Yolu ekranı.
class TrailView extends StatefulWidget {
  final PlayContext ctx;
  const TrailView({super.key, required this.ctx});

  @override
  State<TrailView> createState() => _TrailViewState();
}

class _TrailViewState extends State<TrailView> {
  late TrailLevel level;
  late TrailGame game;
  bool _ended = false;
  int _seconds = 0, _hints = 0;
  int? _flash;
  Timer? _timer;
  double _cw = 40, _ch = 56, _gap = 6, _ox = 0;

  PlayContext get ctx => widget.ctx;

  @override
  void initState() {
    super.initState();
    level = (ctx.generated as GeneratedLevel<TrailLevel>).puzzle;
    final snap = ctx.resume['snap'];
    game = snap is String ? TrailGame.restore(level, snap) : TrailGame(level);
    _seconds = (ctx.resume['secs'] as num?)?.toInt() ?? 0;
    _hints = (ctx.resume['hints'] as num?)?.toInt() ?? 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_ended && mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _persist() => ctx.saveResume({'snap': game.serialize(), 'secs': _seconds, 'hints': _hints});

  CardStyle get _style => CardStyle(
        backA: ctx.pieceColors.isNotEmpty ? ctx.pieceColors[0] : const Color(0xFF1F5E8C),
        backB: ctx.pieceColors.length > 1 ? ctx.pieceColors[1] : const Color(0xFF2BB3B1),
        colorBlind: ctx.colorBlind,
      );

  void _tap(int i) {
    if (_ended) return;
    if (game.tap(i)) {
      ctx.sfx(game.path.length == 1 ? Sfx.tap : Sfx.place);
      setState(() => _flash = null);
      _persist();
      if (game.won) _end();
    } else if (!game.taken(i)) {
      ctx.sfx(Sfx.error);
    }
  }

  void _undo() {
    if (_ended || game.path.isEmpty) return;
    setState(game.undo);
    _persist();
  }

  Future<void> _useHint() async {
    if (_ended || !await ctx.requestHint()) return;
    final h = game.hint();
    _hints++;
    setState(() => _flash = h);
    if (h == null) _undo();
    _persist();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    ctx.sfx(Sfx.win);
    final stars = _hints == 0 && game.undos == 0 ? 3 : (_hints == 0 ? 2 : 1);
    ctx.finish(RoundResult(
      won: true,
      score: math.max(10, level.size * 25 - game.undos * 5 - _hints * 20 + (stars == 3 ? 100 : 0)),
      stars: stars,
      seconds: _seconds,
      moves: game.path.length,
      hintsUsed: _hints,
      undosUsed: game.undos,
      gameStats: {'cards_linked': level.size, 'clean_trails': stars == 3 ? 1 : 0},
    ));
  }

  String get _ruleText => Strings.pick(switch (level.link) {
        TrailLink.suitOrRank => _tSuitOrRank,
        TrailLink.suitOrStep => _tSuitOrStep,
        TrailLink.step => _tStep,
      }, ctx.lang);

  Rect _rect(int i) => Rect.fromLTWH(_ox + (i % level.cols) * (_cw + _gap), (i ~/ level.cols) * (_ch + _gap), _cw, _ch);

  @override
  Widget build(BuildContext context) => FeltTable(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final info = game.path.isEmpty
        ? Strings.pick(_tStart, ctx.lang)
        : (game.stuck ? Strings.pick(_tStuck, ctx.lang) : '${game.path.length} / ${level.size}');
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth - 16, h = cons.maxHeight - 140;
      _gap = 6;
      _cw = math.min((w - _gap * (level.cols - 1)) / level.cols, ((h - _gap * (level.rows - 1)) / level.rows) / 1.4);
      _cw = math.max(18, _cw);
      _ch = _cw * 1.4;
      final bw = level.cols * _cw + (level.cols - 1) * _gap, bh = level.rows * _ch + (level.rows - 1) * _gap;
      _ox = (cons.maxWidth - bw) / 2;
      return Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Expanded(
              child: Text(_ruleText,
                  style: const TextStyle(color: kStudioText, fontWeight: FontWeight.w800, fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            StudioTag(icon: Icons.timer_outlined, text: '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}'),
          ]),
        ),
        Text(info,
            style: TextStyle(
                fontWeight: FontWeight.w800, color: game.stuck ? const Color(0xFFFF8A80) : kStudioText)),
        const SizedBox(height: 6),
        Expanded(
          child: Center(
            child: GestureDetector(
              onTapUp: (d) {
                final p = d.localPosition - Offset(_ox, 0);
                final c = (p.dx / (_cw + _gap)).floor(), r = (p.dy / (_ch + _gap)).floor();
                if (c < 0 || r < 0 || c >= level.cols || r >= level.rows) return;
                _tap(r * level.cols + c);
              },
              child: Semantics(
                label: 'cards',
                child: SizedBox(width: cons.maxWidth, height: bh, child: CustomPaint(painter: _Painter(this))),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            StudioRoundAction(onPressed: _ended ? null : _useHint, icon: Icons.lightbulb, tooltip: ctx.t('hint')),
            StudioRoundAction(onPressed: _ended || game.path.isEmpty ? null : _undo, icon: Icons.undo, tooltip: ctx.t('undo')),
          ]),
        ),
      ]);
    });
  }
}

class _Painter extends CustomPainter {
  final _TrailViewState v;
  _Painter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final lv = v.level, g = v.game;
    final style = v._style;
    for (var i = 0; i < lv.size; i++) {
      final rect = v._rect(i);
      if (g.taken(i) && g.path.last != i) {
        paintSlot(canvas, rect);
        continue;
      }
      paintCard(canvas, rect, lv.cards[i], faceUp: true, style: style, highlight: v._flash == i || (g.path.isNotEmpty && g.path.last == i));
    }
    // Geçilen yolun çizgisi.
    if (g.path.length > 1) {
      final p = Path()..moveTo(v._rect(g.path.first).center.dx, v._rect(g.path.first).center.dy);
      for (final i in g.path.skip(1)) {
        p.lineTo(v._rect(i).center.dx, v._rect(i).center.dy);
      }
      canvas.drawPath(
          p,
          Paint()
            ..color = const Color(0xFFFFC53D).withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(3, v._cw * 0.08)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// tr en de es fr ar fa he ur ru uk pl cs ro hu el it pt nl sv da nb fi ja ko zh hi bn id ms th vi fil
const _tSuitOrRank = ['Aynı desen ya da aynı sayı', 'Same suit or same rank', 'Gleiche Farbe oder gleicher Wert', 'Mismo palo o mismo valor', 'Même enseigne ou même valeur', 'نفس النوع أو نفس الرقم', 'هم‌خال یا هم‌عدد', 'אותה צורה או אותו ערך', 'ایک ہی نشان یا ایک ہی نمبر', 'Та же масть или то же значение', 'Та сама масть або те саме значення', 'Ten sam kolor lub ta sama wartość', 'Stejná barva nebo stejná hodnota', 'Aceeași culoare sau aceeași valoare', 'Azonos szín vagy azonos érték', 'Ίδιο χρώμα ή ίδια αξία', 'Stesso seme o stesso valore', 'Mesmo naipe ou mesmo valor', 'Zelfde kleur of zelfde waarde', 'Samma färg eller samma valör', 'Samme kulør eller samme værdi', 'Samme farge eller samme verdi', 'Sama maa tai sama arvo', '同じマークか同じ数', '같은 무늬 또는 같은 숫자', '同花色或同点数', 'एक ही चिह्न या एक ही अंक', 'একই চিহ্ন বা একই মান', 'Jenis sama atau angka sama', 'Sut sama atau nombor sama', 'ดอกเดียวกันหรือแต้มเดียวกัน', 'Cùng chất hoặc cùng số', 'Parehong tipo o parehong numero'];
const _tSuitOrStep = ['Aynı desen ya da bir yanındaki sayı', 'Same suit or the next rank up or down', 'Gleiche Farbe oder Nachbarwert', 'Mismo palo o valor vecino', 'Même enseigne ou valeur voisine', 'نفس النوع أو الرقم المجاور', 'هم‌خال یا عدد کناری', 'אותה צורה או ערך סמוך', 'ایک ہی نشان یا ساتھ والا نمبر', 'Та же масть или соседнее значение', 'Та сама масть або сусіднє значення', 'Ten sam kolor lub sąsiednia wartość', 'Stejná barva nebo sousední hodnota', 'Aceeași culoare sau valoare vecină', 'Azonos szín vagy szomszédos érték', 'Ίδιο χρώμα ή γειτονική αξία', 'Stesso seme o valore vicino', 'Mesmo naipe ou valor vizinho', 'Zelfde kleur of buurwaarde', 'Samma färg eller grannvalör', 'Samme kulør eller nabo-værdi', 'Samme farge eller nabo-verdi', 'Sama maa tai viereinen arvo', '同じマークか隣の数', '같은 무늬 또는 이웃 숫자', '同花色或相邻点数', 'एक ही चिह्न या पास का अंक', 'একই চিহ্ন বা পাশের মান', 'Jenis sama atau angka tetangga', 'Sut sama atau nombor jiran', 'ดอกเดียวกันหรือแต้มติดกัน', 'Cùng chất hoặc số liền kề', 'Parehong tipo o katabing numero'];
const _tStep = ['Yalnızca bir yanındaki sayı (K–A da olur)', 'Only the next rank up or down (K–A too)', 'Nur Nachbarwert (auch K–A)', 'Solo valor vecino (K–A también)', 'Seulement valeur voisine (K–A aussi)', 'الرقم المجاور فقط (K–A أيضًا)', 'فقط عدد کناری (K–A هم)', 'רק ערך סמוך (גם K–A)', 'صرف ساتھ والا نمبر (K–A بھی)', 'Только соседнее значение (и K–A)', 'Лише сусіднє значення (і K–A)', 'Tylko sąsiednia wartość (też K–A)', 'Jen sousední hodnota (i K–A)', 'Doar valoare vecină (și K–A)', 'Csak szomszédos érték (K–A is)', 'Μόνο γειτονική αξία (και K–A)', 'Solo valore vicino (anche K–A)', 'Só valor vizinho (K–A também)', 'Alleen buurwaarde (ook K–A)', 'Bara grannvalör (även K–A)', 'Kun nabo-værdi (også K–A)', 'Bare nabo-verdi (også K–A)', 'Vain viereinen arvo (myös K–A)', '隣の数だけ（K–Aも可）', '이웃 숫자만 (K–A도)', '仅相邻点数（K–A也算）', 'केवल पास का अंक (K–A भी)', 'শুধু পাশের মান (K–A-ও)', 'Hanya angka tetangga (K–A juga)', 'Hanya nombor jiran (K–A juga)', 'เฉพาะแต้มติดกัน (K–A ด้วย)', 'Chỉ số liền kề (cả K–A)', 'Katabing numero lang (pati K–A)'];
const _tStuck = ['Yol kapandı, bir adım geri al', 'Dead end: undo a step', 'Sackgasse: mach einen Schritt rückgängig', 'Sin salida: deshaz un paso', 'Impasse : annulez un pas', 'طريق مسدود، تراجع خطوة', 'بن‌بست؛ یک قدم برگرد', 'מבוי סתום: בטלו צעד', 'راستہ بند، ایک قدم واپس لیں', 'Тупик: отмените шаг', 'Глухий кут: скасуйте крок', 'Ślepy zaułek: cofnij ruch', 'Slepá ulička: vrať krok', 'Fundătură: anulează un pas', 'Zsákutca: vonj vissza egy lépést', 'Αδιέξοδο: αναίρεσε ένα βήμα', 'Vicolo cieco: annulla un passo', 'Beco sem saída: desfaça um passo', 'Doodlopend: maak een stap ongedaan', 'Återvändsgränd: ångra ett steg', 'Blindgyde: fortryd et trin', 'Blindvei: angre et steg', 'Umpikuja: peru askel', '行き止まり。1手戻そう', '막다른 길: 한 걸음 되돌리기', '无路可走，撤销一步', 'रास्ता बंद, एक कदम वापस लें', 'পথ বন্ধ, এক ধাপ ফিরে যান', 'Jalan buntu, urungkan satu langkah', 'Jalan mati, buat asal satu langkah', 'ทางตัน ย้อนกลับหนึ่งก้าว', 'Ngõ cụt, hãy hoàn tác một bước', 'Wala nang daan, ibalik ang isang hakbang'];
const _tStart = ['Başlamak için bir kart seç', 'Pick any card to start', 'Wähle eine Karte zum Start', 'Elige una carta para empezar', 'Choisissez une carte pour commencer', 'اختر بطاقة للبدء', 'برای شروع یک کارت انتخاب کن', 'בחרו קלף כדי להתחיל', 'شروع کرنے کے لیے کارڈ چنیں', 'Выберите карту для начала', 'Оберіть карту для початку', 'Wybierz kartę, aby zacząć', 'Vyber kartu pro začátek', 'Alege o carte pentru a începe', 'Válassz egy lapot a kezdéshez', 'Διάλεξε ένα φύλλο για αρχή', 'Scegli una carta per iniziare', 'Escolha uma carta para começar', 'Kies een kaart om te beginnen', 'Välj ett kort för att börja', 'Vælg et kort for at starte', 'Velg et kort for å starte', 'Valitse kortti aloittaaksesi', '好きなカードから始めよう', '시작할 카드를 고르세요', '选一张牌开始', 'शुरू करने के लिए पत्ता चुनें', 'শুরু করতে একটি তাস বাছুন', 'Pilih kartu untuk mulai', 'Pilih kad untuk mula', 'เลือกไพ่เพื่อเริ่ม', 'Chọn một lá để bắt đầu', 'Pumili ng baraha para magsimula'];
