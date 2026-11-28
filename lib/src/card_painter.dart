import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'cards.dart';
import 'studio_chrome.dart';
import 'table_theme.dart';
import 'tarot.dart';

/// Stüdyonun kendi kart tasarımı: fildişi zemin, büyük köşe yazısı, ortada
/// tek büyük renk simgesi; resimli kartlarda geometrik arma. Sırt deseni
/// oyunun paletinden gelir.
class CardStyle {
  final Color backA, backB;
  final bool fourColor;
  final bool colorBlind;

  /// İspanyol destesi: maça → kılıç, kupa → kupa, karo → altın, sinek →
  /// sopa; resimliler 10 (uşak), 11 (atlı), 12 (kral).
  final bool spanish;

  /// Sırt deseni (0 kafes, 1 çapraz şerit, 2 benek, 3 ışın, 4 dalga,
  /// 5 dama, 6 zikzak, 7 rozet); oyunun masa temasından gelir.
  final int back;
  const CardStyle({
    this.backA = const Color(0xFF1F5E8C),
    this.backB = const Color(0xFF2BB3B1),
    this.back = 0,
    this.fourColor = false,
    this.colorBlind = false,
    this.spanish = false,
  });

  static const ink = Color(0xFF1E2430);
  static const red = Color(0xFFCF3B35);
  static const orange = Color(0xFFD9772A);
  static const green = Color(0xFF2E8B57);
  static const paper = Color(0xFFFBF7EE);

  Color suitColor(int suit) {
    if (spanish) return const [Color(0xFF2B5FA8), Color(0xFFC0392B), Color(0xFFB8860B), Color(0xFF2E7D32)][suit];
    if (fourColor || colorBlind) {
      return const [ink, red, orange, green][suit];
    }
    return suit == kHearts || suit == kDiamonds ? red : ink;
  }
}

/// Koyu zemin üstündeki yazıda takım rengi (kırmızılar açık ton, siyahlar beyaz).
Color suitOnDark(int suit) =>
    suit == kHearts || suit == kDiamonds ? const Color(0xFFFF8A80) : Colors.white;

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

/// İspanyol destesinin renk simgeleri (birim kare): 0 kılıç (espadas),
/// 1 kupa (copas), 2 altın (oros), 3 sopa (bastos).
Path spanishSuitPath(int suit) {
  final p = Path();
  switch (suit) {
    case kSpades: // kılıç: ince uzun bıçak, balçak ve kabza
      p
        ..moveTo(0.5, 0.02)
        ..lineTo(0.58, 0.14)
        ..lineTo(0.57, 0.68)
        ..lineTo(0.43, 0.68)
        ..lineTo(0.42, 0.14)
        ..close()
        ..addRRect(RRect.fromLTRBR(0.22, 0.66, 0.78, 0.74, const Radius.circular(0.04)))
        ..addRect(const Rect.fromLTRB(0.45, 0.74, 0.55, 0.9))
        ..addOval(Rect.fromCircle(center: const Offset(0.5, 0.93), radius: 0.06));
    case kHearts: // kupa: kadeh
      p
        ..moveTo(0.16, 0.1)
        ..lineTo(0.84, 0.1)
        ..quadraticBezierTo(0.84, 0.52, 0.56, 0.58)
        ..lineTo(0.56, 0.8)
        ..quadraticBezierTo(0.74, 0.84, 0.78, 0.94)
        ..lineTo(0.22, 0.94)
        ..quadraticBezierTo(0.26, 0.84, 0.44, 0.8)
        ..lineTo(0.44, 0.58)
        ..quadraticBezierTo(0.16, 0.52, 0.16, 0.1)
        ..close();
    case kDiamonds: // altın: halkalı sikke
      p
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: const Offset(0.5, 0.5), radius: 0.46))
        ..addOval(Rect.fromCircle(center: const Offset(0.5, 0.5), radius: 0.34))
        ..addOval(Rect.fromCircle(center: const Offset(0.5, 0.5), radius: 0.14));
    default: // sopa: boğumlu değnek
      p
        ..moveTo(0.36, 0.04)
        ..quadraticBezierTo(0.5, 0.0, 0.64, 0.04)
        ..lineTo(0.6, 0.3)
        ..quadraticBezierTo(0.66, 0.34, 0.6, 0.4)
        ..lineTo(0.57, 0.62)
        ..quadraticBezierTo(0.63, 0.66, 0.57, 0.7)
        ..lineTo(0.55, 0.96)
        ..lineTo(0.45, 0.96)
        ..lineTo(0.43, 0.7)
        ..quadraticBezierTo(0.37, 0.66, 0.43, 0.62)
        ..lineTo(0.4, 0.4)
        ..quadraticBezierTo(0.34, 0.34, 0.4, 0.3)
        ..close();
  }
  return p;
}

/// İspanyol destesinde resimlilerin yazısı.
String spanishRankLabel(int rank) => switch (rank) {
      11 => '10',
      12 => '11',
      13 => '12',
      _ => '$rank',
    };

final _suitCache = <int, Path>{};

void paintSuit(Canvas c, int suit, Rect r, Color color, {bool spanish = false}) {
  final base = _suitCache.putIfAbsent(spanish ? suit + 10 : suit, () => spanish ? spanishSuitPath(suit) : suitPath(suit));
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
  _backPattern(c, inner.outerRect, s.back, r.width);
  c.restore();
  c.drawRRect(
      inner,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, r.width * 0.025));
  // Ortada arma: desene göre dört ya da sekiz kollu yıldız.
  final ctr = r.center;
  final a = r.width * 0.2;
  final arms = s.back.isEven ? 4 : 8;
  final star = Path();
  for (var i = 0; i < arms * 2; i++) {
    final ang = -math.pi / 2 + i * math.pi / arms;
    final rad = i.isEven ? a : a * (arms == 4 ? 0.38 : 0.5);
    final pt = Offset(ctr.dx + math.cos(ang) * rad, ctr.dy + math.sin(ang) * rad);
    i == 0 ? star.moveTo(pt.dx, pt.dy) : star.lineTo(pt.dx, pt.dy);
  }
  star.close();
  c.drawCircle(ctr, a * 1.15, Paint()..color = Colors.white.withValues(alpha: 0.16));
  c.drawPath(star, Paint()..color = Colors.white.withValues(alpha: 0.85));
}

void _backPattern(Canvas c, Rect r, int kind, double w) {
  final p = Paint()..color = Colors.white.withValues(alpha: 0.13);
  final line = Paint()
    ..color = Colors.white.withValues(alpha: 0.16)
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.8, w * 0.018);
  final step = w * 0.16;
  switch (kind) {
    case 1: // çapraz şerit
      for (var x = r.left - r.height; x < r.right; x += step) {
        c.drawLine(Offset(x, r.bottom), Offset(x + r.height, r.top), line);
      }
    case 2: // benek
      var row = 0;
      for (var y = r.top; y < r.bottom + step; y += step * 0.8) {
        for (var x = r.left + (row.isOdd ? step / 2 : 0); x < r.right + step; x += step) {
          c.drawCircle(Offset(x, y), step * 0.18, p);
        }
        row++;
      }
    case 3: // ışın
      final ctr = r.center;
      for (var k = 0; k < 24; k++) {
        final a = k * math.pi / 12;
        if (k.isEven) {
          c.drawPath(
              Path()
                ..moveTo(ctr.dx, ctr.dy)
                ..lineTo(ctr.dx + math.cos(a) * r.longestSide, ctr.dy + math.sin(a) * r.longestSide)
                ..lineTo(ctr.dx + math.cos(a + math.pi / 12) * r.longestSide, ctr.dy + math.sin(a + math.pi / 12) * r.longestSide)
                ..close(),
              p);
        }
      }
    case 4: // dalga
      for (var y = r.top; y < r.bottom + step; y += step * 0.7) {
        final path = Path()..moveTo(r.left, y);
        for (var x = r.left; x <= r.right; x += w * 0.04) {
          path.lineTo(x, y + math.sin((x - r.left) / (w * 0.08)) * step * 0.18);
        }
        c.drawPath(path, line);
      }
    case 5: // dama
      final g = step * 0.9;
      for (var y = r.top; y < r.bottom; y += g) {
        for (var x = r.left; x < r.right; x += g) {
          if ((((x - r.left) + (y - r.top)) / g).round().isEven) c.drawRect(Rect.fromLTWH(x, y, g, g), p);
        }
      }
    case 6: // zikzak
      for (var y = r.top; y < r.bottom + step; y += step * 0.75) {
        final path = Path()..moveTo(r.left, y);
        var up = true;
        for (var x = r.left; x <= r.right + step; x += step * 0.5) {
          path.lineTo(x, y + (up ? 0 : step * 0.35));
          up = !up;
        }
        c.drawPath(path, line);
      }
    case 7: // rozet: iç içe halkalar ve taç yaprakları
      final ctr = r.center;
      for (var rad = w * 0.12; rad < r.longestSide; rad += w * 0.12) {
        c.drawCircle(ctr, rad, line);
      }
      for (var k = 0; k < 8; k++) {
        final a = k * math.pi / 4;
        c.drawCircle(Offset(ctr.dx + math.cos(a) * w * 0.3, ctr.dy + math.sin(a) * w * 0.3), w * 0.08, p);
      }
    default: // kafes: küçük baklavalar
      for (var y = r.top - step; y < r.bottom + step; y += step) {
        for (var x = r.left - step; x < r.right + step; x += step) {
          final o = ((y - r.top) / step).round().isOdd ? step / 2 : 0.0;
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
  }
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
  if (isTarotSpecial(card)) {
    _paintTarot(c, r, card, s);
    return;
  }
  final rank = rankOf(card), suit = suitOf(card);
  final col = s.suitColor(suit);
  // Köşe: değer + küçük simge (sol üst), ters köşe (sağ alt).
  final fs = w * 0.30;
  final lab = _label((s.spanish ? spanishRankLabel(rank) : rankLabel(rank)), fs, col);
  final lx = r.left + w * 0.07, ly = r.top + w * 0.05;
  lab.paint(c, Offset(lx, ly));
  final small = w * 0.20;
  paintSuit(c, suit, Rect.fromLTWH(lx + (lab.width - small) / 2, ly + lab.height + w * 0.02, small, small), col, spanish: s.spanish);
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
    final big = _label((s.spanish ? spanishRankLabel(rank) : rankLabel(rank)), body.height * 0.42, col, w: FontWeight.w900);
    big.paint(c, body.center - Offset(big.width / 2, big.height / 2));
    final g = body.width * 0.28;
    paintSuit(c, suit, Rect.fromCenter(center: Offset(body.center.dx, body.top + g * 0.75), width: g, height: g), col, spanish: s.spanish);
    paintSuit(c, suit, Rect.fromCenter(center: Offset(body.center.dx, body.bottom - g * 0.75), width: g, height: g), col, spanish: s.spanish);
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
  } else if (rank == 1 || w < 46) {
    final g = math.min(body.width, body.height) * (rank == 1 ? 0.95 : 0.75);
    paintSuit(c, suit, Rect.fromCenter(center: body.center.translate(0, r.height * 0.04), width: g, height: g), col, spanish: s.spanish);
  } else {
    // Gerçek iskambil gibi: değer kadar simge, klasik dizilişte; alt yarıdakiler ters.
    final pips = _pips[rank.clamp(2, 10)]!;
    final area = Rect.fromLTRB(r.left + w * 0.34, r.top + r.height * 0.17, r.right - w * 0.34, r.bottom - r.height * 0.17);
    final g = math.min(w * 0.17, area.height * (rank >= 9 ? 0.19 : 0.23));
    for (final (px, py) in pips) {
      final o = Offset(area.left + area.width * px, area.top + area.height * py);
      if (py > 0.5) {
        c.save();
        c.translate(o.dx, o.dy);
        c.rotate(math.pi);
        paintSuit(c, suit, Rect.fromCenter(center: Offset.zero, width: g, height: g), col, spanish: s.spanish);
        c.restore();
      } else {
        paintSuit(c, suit, Rect.fromCenter(center: o, width: g, height: g), col, spanish: s.spanish);
      }
    }
  }
}

const _pips = <int, List<(double, double)>>{
  2: [(0.5, 0), (0.5, 1)],
  3: [(0.5, 0), (0.5, 0.5), (0.5, 1)],
  4: [(0, 0), (1, 0), (0, 1), (1, 1)],
  5: [(0, 0), (1, 0), (0.5, 0.5), (0, 1), (1, 1)],
  6: [(0, 0), (1, 0), (0, 0.5), (1, 0.5), (0, 1), (1, 1)],
  7: [(0, 0), (1, 0), (0.5, 0.25), (0, 0.5), (1, 0.5), (0, 1), (1, 1)],
  8: [(0, 0), (1, 0), (0.5, 0.25), (0, 0.5), (1, 0.5), (0.5, 0.75), (0, 1), (1, 1)],
  9: [(0, 0), (1, 0), (0, 1 / 3), (1, 1 / 3), (0.5, 0.5), (0, 2 / 3), (1, 2 / 3), (0, 1), (1, 1)],
  10: [(0, 0), (1, 0), (0.5, 1 / 6), (0, 1 / 3), (1, 1 / 3), (0, 2 / 3), (1, 2 / 3), (0.5, 5 / 6), (0, 1), (1, 1)],
};

/// 78'lik destenin özel kartları: at (süvari), numaralı kozlar ve Kaçak.
/// Kozlar resimsiz: büyük numara, altın şerit ve basamak çubuğu.
void _paintTarot(Canvas c, Rect r, KCard card, CardStyle s) {
  final w = r.width;
  final body = Rect.fromLTRB(r.left + w * 0.16, r.top + r.height * 0.22, r.right - w * 0.16, r.bottom - r.height * 0.22);
  if (isTarotKnight(card)) {
    final suit = card - kTarotKnight;
    final col = s.suitColor(suit);
    final lab = _label('C', w * 0.30, col);
    lab.paint(c, Offset(r.left + w * 0.07, r.top + w * 0.05));
    final small = w * 0.20;
    paintSuit(c, suit, Rect.fromLTWH(r.left + w * 0.07 + (lab.width - small) / 2, r.top + w * 0.07 + lab.height, small, small), col);
    c.save();
    c.translate(r.right, r.bottom);
    c.rotate(math.pi);
    lab.paint(c, Offset(w * 0.07, w * 0.05));
    c.restore();
    final frame = RRect.fromRectAndRadius(body.deflate(w * 0.06), Radius.circular(w * 0.30));
    c.drawRRect(frame, Paint()..color = col.withValues(alpha: 0.10));
    c.drawRRect(
        frame,
        Paint()
          ..color = col.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, w * 0.02));
    final g = body.width * 0.42;
    paintSuit(c, suit, Rect.fromCenter(center: body.center, width: g, height: g), col);
    // Üstte ve altta iki küçük nal kemeri.
    final arc = Paint()
      ..color = col.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * 0.03);
    final a = body.width * 0.22;
    c.drawArc(Rect.fromCenter(center: Offset(body.center.dx, body.top + a * 0.9), width: a * 2, height: a * 1.4), math.pi, math.pi, false, arc);
    c.drawArc(Rect.fromCenter(center: Offset(body.center.dx, body.bottom - a * 0.9), width: a * 2, height: a * 1.4), 0, math.pi, false, arc);
    return;
  }
  const gold = Color(0xFFB07A1E);
  const deep = Color(0xFF2A3F6B);
  final band = RRect.fromRectAndRadius(Rect.fromLTRB(r.left + w * 0.05, r.top + w * 0.05, r.right - w * 0.05, r.bottom - w * 0.05), Radius.circular(w * 0.07));
  c.drawRRect(
      band,
      Paint()
        ..color = gold.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, w * 0.025));
  if (card == kTarotExcuse) {
    final lab = _label('★', w * 0.26, deep);
    lab.paint(c, Offset(r.left + w * 0.09, r.top + w * 0.07));
    c.save();
    c.translate(r.right, r.bottom);
    c.rotate(math.pi);
    lab.paint(c, Offset(w * 0.09, w * 0.07));
    c.restore();
    final ctr = body.center;
    final a = body.width * 0.42;
    final star = Path();
    for (var i = 0; i < 10; i++) {
      final ang = -math.pi / 2 + i * math.pi / 5;
      final rad = i.isEven ? a : a * 0.45;
      final pt = Offset(ctr.dx + math.cos(ang) * rad, ctr.dy + math.sin(ang) * rad);
      i == 0 ? star.moveTo(pt.dx, pt.dy) : star.lineTo(pt.dx, pt.dy);
    }
    star.close();
    c.drawCircle(ctr, a * 1.1, Paint()..color = gold.withValues(alpha: 0.15));
    c.drawPath(star, Paint()..color = gold);
    return;
  }
  final n = tarotTrumpNo(card);
  final lab = _label('$n', w * 0.27, deep);
  lab.paint(c, Offset(r.left + w * 0.09, r.top + w * 0.07));
  c.save();
  c.translate(r.right, r.bottom);
  c.rotate(math.pi);
  lab.paint(c, Offset(w * 0.09, w * 0.07));
  c.restore();
  // Orta: altın rozet içinde büyük numara.
  final ctr = body.center;
  final rad = body.width * 0.48;
  c.drawCircle(ctr, rad, Paint()..color = deep.withValues(alpha: 0.10));
  c.drawCircle(
      ctr,
      rad,
      Paint()
        ..color = gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, w * 0.03));
  final big = _label('$n', rad * 1.0, deep, w: FontWeight.w900);
  big.paint(c, ctr - Offset(big.width / 2, big.height / 2));
  // Basamak çubuğu: kozun gücü (1–21) alt kenarda dolan şerit.
  final bar = Rect.fromLTWH(body.left, body.bottom + r.height * 0.06, body.width, r.height * 0.035);
  c.drawRRect(RRect.fromRectAndRadius(bar, Radius.circular(bar.height)), Paint()..color = deep.withValues(alpha: 0.12));
  c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(bar.left, bar.top, bar.width * n / 21, bar.height), Radius.circular(bar.height)),
      Paint()..color = gold);
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

/// Kâğıt oyunlarının masası: koyu yeşil çuha, ortada ışık, kenarda gölge.
class FeltTable extends StatelessWidget {
  final Widget child;
  const FeltTable({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final look = StudioLook.of(context);
    // Masa (çuha, kenar, süsleme, kart sırtı) oyunun kendi sanatıdır ve her
    // oyunda farklıdır (KartTableTheme); onaylı tasarımın çerçevesi (vurgu
    // kenarı, yuvarlak köşe) dünya zemininin üstüne oturur. İçindeki bütün
    // arayüz (etiket, seçici, diyalog) koyu stüdyo temasıyla çizilir.
    return StudioChrome(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: look.accent.withValues(alpha: 0.55), width: 1.4),
          ),
          child: KartTableSurface(theme: KartTableTheme.of(context), child: child),
        ),
      ),
    );
  }
}
