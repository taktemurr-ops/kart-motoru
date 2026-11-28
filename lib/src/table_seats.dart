/// Masa oyunlarının oyuncu yerleri: yuvarlak avatar (sıra halkası, takım
/// rengi), ad, durum hapları (alınan el, ihale, dağıtan) ve rakibin kapalı
/// kart yelpazesi. Piyasadaki masa oyunlarının alışılmış düzeni; çizimler
/// stüdyonun kendi geometrik avatarlarıdır.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/core/strings.dart';

import 'card_painter.dart';
import 'studio_chrome.dart';

/// Yapay zekâ oyuncularının adları (dile göre).
String botName(int seat, String lang, {int salt = 0}) {
  const tr = ['Deniz', 'Ece', 'Kaan', 'Lale', 'Arda', 'Nil', 'Emre', 'Su'];
  const en = ['Alex', 'Mia', 'Leo', 'Nora', 'Sam', 'Ivy', 'Max', 'Zoe'];
  final list = lang == 'tr' ? tr : en;
  return list[(seat * 3 + salt) % list.length];
}

/// Avatar rengi (koltuğa göre).
Color seatColor(int seat) => const [
      Color(0xFF3D7BD9),
      Color(0xFFD9573D),
      Color(0xFF3DAF7A),
      Color(0xFFB45BD0),
      Color(0xFFE0A030),
      Color(0xFF3AB0C0),
    ][seat % 6];

/// Yuvarlak avatar: baş harf, koltuk rengi; sırası gelince dönen halka.
class SeatAvatar extends StatefulWidget {
  final String name;
  final int seat;
  final bool active;
  final double size;
  final Color? ring;
  const SeatAvatar({super.key, required this.name, required this.seat, this.active = false, this.size = 46, this.ring});

  @override
  State<SeatAvatar> createState() => _SeatAvatarState();
}

class _SeatAvatarState extends State<SeatAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.active) _spin.repeat();
  }

  @override
  void didUpdateWidget(SeatAvatar old) {
    super.didUpdateWidget(old);
    if (widget.active && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.active && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = StudioLook.of(context);
    final s = widget.size;
    final col = seatColor(widget.seat);
    final initial = widget.name.isEmpty ? '?' : widget.name.characters.first.toUpperCase();
    final face = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(col, Colors.white, 0.25)!, Color.lerp(col, Colors.black, 0.35)!],
        ),
        border: Border.all(color: widget.ring ?? Colors.white.withValues(alpha: 0.8), width: widget.ring != null ? 2.6 : 1.6),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: Text(initial,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: s * 0.44, height: 1.0)),
    );
    return SizedBox(
      width: s + 10,
      height: s + 10,
      child: Stack(alignment: Alignment.center, children: [
        if (widget.active)
          AnimatedBuilder(
            animation: _spin,
            builder: (_, __) => CustomPaint(
              size: Size(s + 10, s + 10),
              painter: _RingP(_spin.value, look.accent),
            ),
          ),
        face,
      ]),
    );
  }
}

class _RingP extends CustomPainter {
  final double t;
  final Color c;
  _RingP(this.t, this.c);
  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(2);
    canvas.drawCircle(r.center, r.width / 2, Paint()..color = const Color(0xFFFFD45A).withValues(alpha: 0.25));
    canvas.drawArc(
        r,
        t * 2 * math.pi,
        math.pi * 1.3,
        false,
        Paint()
          ..shader = SweepGradient(colors: [c.withValues(alpha: 0), const Color(0xFFFFD45A)], transform: GradientRotation(t * 2 * math.pi))
              .createShader(r)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _RingP o) => o.t != t;
}

/// Küçük durum hapı (masada).
class SeatPill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? color;
  final Color? textColor;
  const SeatPill(this.text, {super.key, this.icon, this.color, this.textColor});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color ?? Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: textColor ?? Colors.white), const SizedBox(width: 3)],
          Text(text,
              style: TextStyle(color: textColor ?? Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800, height: 1.15)),
        ]),
      );
}

/// Rakibin kapalı kartları: küçük yelpaze ve sayı.
class CardBackFan extends StatelessWidget {
  final int count;
  final CardStyle style;
  final double cardW;
  final bool vertical;
  const CardBackFan({super.key, required this.count, required this.style, this.cardW = 20, this.vertical = false});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return SizedBox(width: cardW, height: cardW * 1.4);
    final shown = math.min(count, 13);
    final step = cardW * (shown > 8 ? 0.32 : 0.42);
    final len = cardW + step * (shown - 1);
    final size = vertical ? Size(cardW * 1.4 + 6, len) : Size(len, cardW * 1.4 + 6);
    return Stack(clipBehavior: Clip.none, children: [
      CustomPaint(size: size, painter: _FanP(shown, style, cardW, step, vertical)),
      PositionedDirectional(
        end: -6,
        bottom: -6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white54, width: 0.8),
          ),
          child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
        ),
      ),
    ]);
  }
}

class _FanP extends CustomPainter {
  final int n;
  final CardStyle style;
  final double w, step;
  final bool vertical;
  _FanP(this.n, this.style, this.w, this.step, this.vertical);

  @override
  void paint(Canvas c, Size size) {
    final h = w * 1.4;
    for (var i = 0; i < n; i++) {
      final t = n <= 1 ? 0.0 : i / (n - 1) - 0.5;
      c.save();
      if (vertical) {
        c.translate(size.width / 2, h / 2 + step * i);
        c.rotate(math.pi / 2 + t * 0.25);
      } else {
        c.translate(w / 2 + step * i, h / 2 + 3 + t * t * 8);
        c.rotate(t * 0.35);
      }
      paintCard(c, Rect.fromCenter(center: Offset.zero, width: w, height: h), 0, faceUp: false, style: style);
      c.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FanP o) => o.n != n || o.w != w || o.style.backA != style.backA || o.style.back != style.back;
}

/// Masadaki bir oyuncunun yeri.
class TableSeat extends StatelessWidget {
  final String name;
  final int seat;
  final bool active;
  final int? cards;
  final CardStyle style;
  final List<Widget> pills;
  final bool partner;
  final bool dealer;
  final bool compact;
  final bool side; // sol/sağ koltuk (dar sütun)
  final Widget? extra;
  final String lang;
  const TableSeat({
    super.key,
    required this.name,
    required this.seat,
    required this.style,
    required this.lang,
    this.active = false,
    this.cards,
    this.pills = const [],
    this.partner = false,
    this.dealer = false,
    this.compact = false,
    this.side = false,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = Stack(clipBehavior: Clip.none, children: [
      SeatAvatar(
        name: name,
        seat: seat,
        active: active,
        size: compact ? 34 : 44,
        ring: partner ? const Color(0xFF7FE0A8) : null,
      ),
      if (dealer)
        Positioned(
          right: -2,
          top: -2,
          child: DealerCoin(lang: lang),
        ),
    ]);
    final label = SeatNameTag(
      text: partner ? '$name · ${Strings.tx(lang, 'Eş', 'Partner')}' : name,
      active: active,
      maxWidth: side ? 92 : 150,
    );
    final info = Wrap(spacing: 3, runSpacing: 3, alignment: WrapAlignment.center, children: pills);
    final fan = cards == null ? null : CardBackFan(count: cards!, style: style, cardW: side ? 17 : 19);
    return Semantics(
      label: name,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (fan != null && !side) Padding(padding: const EdgeInsets.only(bottom: 2), child: fan),
        avatar,
        label,
        if (pills.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: info),
        if (fan != null && side) Padding(padding: const EdgeInsets.only(top: 4), child: fan),
        if (extra != null) extra!,
      ]),
    );
  }
}

/// Oyuncu adı etiketi: sırası gelende vurgu renginde.
class SeatNameTag extends StatelessWidget {
  final String text;
  final bool active;
  final double maxWidth;
  const SeatNameTag({super.key, required this.text, this.active = false, this.maxWidth = 150});

  @override
  Widget build(BuildContext context) {
    final look = StudioLook.of(context);
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active ? look.accent.withValues(alpha: 0.92) : Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: active ? look.onAccent : Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5),
      ),
    );
  }
}

/// Dağıtan oyuncunun altın jetonu ("D").
class DealerCoin extends StatelessWidget {
  final String lang;
  final double size;
  const DealerCoin({super.key, required this.lang, this.size = 18});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: Strings.tx(lang, 'Dağıtan', 'Dealer'),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF2D38A),
            border: Border.all(color: Colors.black54),
          ),
          child: Text('D', style: TextStyle(color: const Color(0xFF3A2A08), fontSize: size * 0.58, fontWeight: FontWeight.w900, height: 1)),
        ),
      );
}

/// Koz göstergesi: büyük renk simgesi.
class TrumpBadge extends StatelessWidget {
  final int suit;
  final String label;
  const TrumpBadge({super.key, required this.suit, required this.label});

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF7EE),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF2D38A), width: 2),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 20, height: 20, child: CustomPaint(painter: SuitIconPainter(suit))),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Color(0xFF2A2A30), fontWeight: FontWeight.w900, fontSize: 12.5)),
          ]),
        ),
      );
}

/// Tek renk simgesi (gerçek iskambil renkleriyle).
class SuitIconPainter extends CustomPainter {
  final int suit;
  final Color? color;
  const SuitIconPainter(this.suit, {this.color});
  @override
  void paint(Canvas canvas, Size size) =>
      paintSuit(canvas, suit, Offset.zero & size, color ?? const CardStyle().suitColor(suit));
  @override
  bool shouldRepaint(covariant SuitIconPainter o) => o.suit != suit || o.color != color;
}

/// Masadaki koltuğun adı: çok oyunculuda oyuncunun adı; tek kişilikte
/// "Sen" ve yapay zekâ oyuncularının adları.
String tableSeatName(PlayContext ctx, int seat, int me, int seats) {
  if (ctx.seats.isNotEmpty && (ctx.passAndPlay || ctx.role(seat) != SeatRole.ai)) {
    return seat == me && ctx.match != null ? Strings.tx(ctx.lang, 'Sen', 'You') : ctx.seatName(seat);
  }
  if (seat == me) return Strings.tx(ctx.lang, 'Sen', 'You');
  return botName((seat - me + seats) % seats, ctx.lang, salt: ctx.spec.seed.abs() % 8);
}

/// Koltuğun masadaki yeri (alt = bu cihaz, sonra saat yönünde).
Alignment tableSeatAlign(int seat, int me, int n) {
  final k = (seat - me + n) % n;
  if (n == 2) return k == 0 ? Alignment.bottomCenter : Alignment.topCenter;
  if (n == 3) return const [Alignment.bottomCenter, Alignment.centerLeft, Alignment.centerRight][k];
  if (n == 4) return const [Alignment.bottomCenter, Alignment.centerLeft, Alignment.topCenter, Alignment.centerRight][k];
  final a = 2 * math.pi * k / n;
  return Alignment(-math.sin(a), math.cos(a));
}

/// Oyun testi için: açıkken bu cihazın koltuğunu da yapay zekâ oynar
/// (oyuncu gibi bütün eli bot hamleleriyle oynatıp ekran görüntüsü almak).
class KartAutoPilot {
  static final ValueNotifier<bool> on = ValueNotifier(false);
}
