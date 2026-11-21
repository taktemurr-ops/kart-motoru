import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'cards.dart';

/// Stüdyonun kendi kart tasarımı: fildişi zemin, büyük köşe yazısı, ortada
/// tek büyük renk simgesi; resimli kartlarda geometrik arma. Sırt deseni
/// oyunun paletinden gelir.
class CardStyle {
  final Color backA, backB;
  final bool fourColor;
  final bool colorBlind;
  const CardStyle({
    this.backA = const Color(0xFF1F5E8C),
    this.backB = const Color(0xFF2BB3B1),
    this.fourColor = false,
    this.colorBlind = false,
  });

  static const ink = Color(0xFF1E2430);
  static const red = Color(0xFFCF3B35);
  static const orange = Color(0xFFD9772A);
  static const green = Color(0xFF2E8B57);
  static const paper = Color(0xFFFBF7EE);

  Color suitColor(int suit) {
    if (fourColor || colorBlind) {
      return const [ink, red, orange, green][suit];
    }
    return suit == kHearts || suit == kDiamonds ? red : ink;
  }
}

/// Birim karede (0..1) renk simgesi.
Path suitPath(int suit) {
  final p = Path();
  switch (suit) {
    case kHearts:
      p
        ..moveTo(0.5, 0.95)
        ..cubicTo(0.30, 0.78, 0.02, 0.58, 0.04, 0.33)
        ..cubicTo(0.06, 0.12, 0.30, 0.02, 0.50, 0.24)
        ..cubicTo(0.70, 0.02, 0.94, 0.12, 0.96, 0.33)
        ..cubicTo(0.98, 0.58, 0.70, 0.78, 0.5, 0.95)
        ..close();
    case kDiamonds:
      // Hafif içbükey kenarlı baklava.
      p
        ..moveTo(0.5, 0.02)
        ..quadraticBezierTo(0.62, 0.32, 0.90, 0.5)
        ..quadraticBezierTo(0.62, 0.68, 0.5, 0.98)
        ..quadraticBezierTo(0.38, 0.68, 0.10, 0.5)
        ..quadraticBezierTo(0.38, 0.32, 0.5, 0.02)
        ..close();
    case kSpades:
      p
        ..moveTo(0.5, 0.03)
        ..cubicTo(0.70, 0.24, 0.98, 0.40, 0.96, 0.62)
        ..cubicTo(0.94, 0.80, 0.70, 0.86, 0.54, 0.70)
        ..quadraticBezierTo(0.58, 0.86, 0.70, 0.97)
        ..lineTo(0.30, 0.97)
        ..quadraticBezierTo(0.42, 0.86, 0.46, 0.70)
        ..cubicTo(0.30, 0.86, 0.06, 0.80, 0.04, 0.62)
        ..cubicTo(0.02, 0.40, 0.30, 0.24, 0.5, 0.03)
        ..close();
    default: // sinek
      p
        ..addOval(Rect.fromCircle(center: const Offset(0.5, 0.27), radius: 0.22))
        ..addOval(Rect.fromCircle(center: const Offset(0.25, 0.58), radius: 0.22))
        ..addOval(Rect.fromCircle(center: const Offset(0.75, 0.58), radius: 0.22))
        ..moveTo(0.46, 0.55)
        ..quadraticBezierTo(0.44, 0.84, 0.30, 0.97)
        ..lineTo(0.70, 0.97)
        ..quadraticBezierTo(0.56, 0.84, 0.54, 0.55)
        ..close();
  }
  return p;
}

final _suitCache = <int, Path>{};

void paintSuit(Canvas c, int suit, Rect r, Color color) {
  final base = _suitCache.putIfAbsent(suit, () => suitPath(suit));
  final m = Float64List.fromList([r.width, 0, 0, 0, 0, r.height, 0, 0, 0, 0, 1, 0, r.left, r.top, 0, 1]);
  c.drawPath(base.transform(m), Paint()..color = color);
}

final _textCache = <String, TextPainter>{};

TextPainter _label(String s, double size, Color color, {FontWeight w = FontWeight.w800}) {
  final key = '$s|${size.toStringAsFixed(1)}|${color.toARGB32()}|${w.value}';
  return _textCache.putIfAbsent(key, () {
    if (_textCache.length > 600) _textCache.clear();
    return TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, fontWeight: w, color: color, height: 1.0)),
      textDirection: TextDirection.ltr,
    )..layout();
  });
}

/// Kartı [r] dikdörtgenine çizer.
void paintCard(Canvas c, Rect r, KCard card, {required bool faceUp, required CardStyle style, bool highlight = false, bool dim = false}) {
  final radius = Radius.circular(r.width * 0.10);
  final rr = RRect.fromRectAndRadius(r, radius);
  // Gölge
  c.drawRRect(rr.shift(Offset(0, r.width * 0.025)), Paint()..color = Colors.black.withValues(alpha: 0.22));
  if (!faceUp) {
    _paintBack(c, rr, style);
  } else {
    _paintFace(c, rr, card, style);
  }
  if (dim) c.drawRRect(rr, Paint()..color = Colors.black.withValues(alpha: 0.35));
  if (highlight) {
    c.drawRRect(
        rr.inflate(1.5),
        Paint()
          ..color = const Color(0xFFFFC53D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.5, r.width * 0.05));
  }
}

void _paintBack(Canvas c, RRect rr, CardStyle s) {
  final r = rr.outerRect;
  c.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [s.backA, s.backB])
            .createShader(r));
  final inner = rr.deflate(r.width * 0.07);
  c.save();
  c.clipRRect(inner);
  // Kafes deseni: küçük baklavalar.
  final step = r.width * 0.16;
  final p = Paint()..color = Colors.white.withValues(alpha: 0.13);
  for (var y = inner.top - step; y < inner.bottom + step; y += step) {
    for (var x = inner.left - step; x < inner.right + step; x += step) {
      final o = ((y - inner.top) / step).round().isOdd ? step / 2 : 0.0;
      final cx = x + o, cy = y;
      final d = step * 0.28;
      c.drawPath(
          Path()
            ..moveTo(cx, cy - d)
            ..lineTo(cx + d, cy)
            ..lineTo(cx, cy + d)
            ..lineTo(cx - d, cy)
            ..close(),
          p);
    }
  }
  c.restore();
  c.drawRRect(
      inner,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, r.width * 0.025));
  // Ortada dört kollu yıldız arması.
  final ctr = r.center;
  final a = r.width * 0.2;
  final star = Path();
  for (var i = 0; i < 8; i++) {
    final ang = -math.pi / 2 + i * math.pi / 4;
    final rad = i.isEven ? a : a * 0.38;
    final pt = Offset(ctr.dx + math.cos(ang) * rad, ctr.dy + math.sin(ang) * rad);
    i == 0 ? star.moveTo(pt.dx, pt.dy) : star.lineTo(pt.dx, pt.dy);
  }
  star.close();
  c.drawCircle(ctr, a * 1.15, Paint()..color = Colors.white.withValues(alpha: 0.16));
  c.drawPath(star, Paint()..color = Colors.white.withValues(alpha: 0.85));
}

void _paintFace(Canvas c, RRect rr, KCard card, CardStyle s) {
  final r = rr.outerRect;
  final w = r.width;
  c.drawRRect(rr, Paint()..color = CardStyle.paper);
  c.drawRRect(
      rr,
      Paint()
        ..color = const Color(0xFFD9D1C0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, w * 0.015));
  final rank = rankOf(card), suit = suitOf(card);
  final col = s.suitColor(suit);
  // Köşe: değer + küçük simge (sol üst), ters köşe (sağ alt).
  final fs = w * 0.30;
  final lab = _label(rankLabel(rank), fs, col);
  final lx = r.left + w * 0.07, ly = r.top + w * 0.05;
  lab.paint(c, Offset(lx, ly));
  final small = w * 0.20;
  paintSuit(c, suit, Rect.fromLTWH(lx + (lab.width - small) / 2, ly + lab.height + w * 0.02, small, small), col);
  c.save();
  c.translate(r.right, r.bottom);
  c.rotate(math.pi);
  lab.paint(c, Offset(w * 0.07, w * 0.05));
  c.restore();
  // Orta
  final body = Rect.fromLTRB(r.left + w * 0.22, r.top + r.height * 0.24, r.right - w * 0.22, r.bottom - r.height * 0.24);
  if (rank >= 11) {
    // Arma: yumuşak renkli çerçeve, büyük harf, üstte ve altta simge.
    final frame = RRect.fromRectAndRadius(body, Radius.circular(w * 0.08));
    c.drawRRect(frame, Paint()..color = col.withValues(alpha: 0.10));
    c.drawRRect(
        frame,
        Paint()
          ..color = col.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, w * 0.02));
    final big = _label(rankLabel(rank), body.height * 0.42, col, w: FontWeight.w900);
    big.paint(c, body.center - Offset(big.width / 2, big.height / 2));
    final g = body.width * 0.28;
    paintSuit(c, suit, Rect.fromCenter(center: Offset(body.center.dx, body.top + g * 0.75), width: g, height: g), col);
    paintSuit(c, suit, Rect.fromCenter(center: Offset(body.center.dx, body.bottom - g * 0.75), width: g, height: g), col);
    // Köşe süsleri
    final d = w * 0.05;
    for (final o in [body.topLeft, body.topRight, body.bottomLeft, body.bottomRight]) {
      c.drawPath(
          Path()
            ..moveTo(o.dx, o.dy - d)
            ..lineTo(o.dx + d, o.dy)
            ..lineTo(o.dx, o.dy + d)
            ..lineTo(o.dx - d, o.dy)
            ..close(),
          Paint()..color = col.withValues(alpha: 0.7));
    }
  } else {
    final g = math.min(body.width, body.height) * (rank == 1 ? 0.95 : 0.75);
    paintSuit(c, suit, Rect.fromCenter(center: body.center.translate(0, r.height * 0.04), width: g, height: g), col);
  }
}

/// Boş yuva (temel, boş sütun) çizimi.
void paintSlot(Canvas c, Rect r, {String? label, int? suit}) {
  final rr = RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.10));
  c.drawRRect(rr, Paint()..color = Colors.white.withValues(alpha: 0.08));
  c.drawRRect(
      rr,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
  if (suit != null) {
    final g = r.width * 0.45;
    paintSuit(c, suit, Rect.fromCenter(center: r.center, width: g, height: g), Colors.white.withValues(alpha: 0.25));
  } else if (label != null) {
    final t = _label(label, r.width * 0.34, Colors.white.withValues(alpha: 0.35));
    t.paint(c, r.center - Offset(t.width / 2, t.height / 2));
  }
}
