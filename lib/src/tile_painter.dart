import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cards.dart';

/// Masa taşları (okey, domino, mahjong) için kodlar ve çizim.
///
/// Okey: 0..103 = deste * 52 + renk * 13 + (sayı - 1); 104, 105 sahte okey.
/// Renk sırası: 0 sarı, 1 mavi, 2 siyah, 3 kırmızı.
/// Domino: 1000 + a * 7 + b (a ≤ b, 0..6); çift dokuzlu 1200 + a * 10 + b.
/// Mahjong: 2000 + tür * 4 + kopya. Tür 0..8 daire, 9..17 bambu,
/// 18..26 karakter, 27..30 rüzgâr (doğu, güney, batı, kuzey), 31..33 ejder
/// (kırmızı, yeşil, beyaz).
const kTileCard = 0, kTileOkey = 1, kTileDomino = 2, kTileMahjong = 3;

const kOkeyFalseJoker = 104;
bool isOkeyFalseJoker(KCard t) => t >= 104 && t < 106;
int okeyColor(KCard t) => (t % 52) ~/ 13;
int okeyNumber(KCard t) => t % 13 + 1;

KCard dominoTile(int a, int b) => a <= b ? 1000 + a * 7 + b : 1000 + b * 7 + a;

/// Çift dokuzlu takım (0..9): 1200 + a * 10 + b (a ≤ b).
KCard dominoTile9(int a, int b) => a <= b ? 1200 + a * 10 + b : 1200 + b * 10 + a;

/// Sırada ters duran domino: +100 (çizimde alt yarı üste gelir).
bool dominoIsFlipped(KCard t) => (t >= 1100 && t < 1200) || (t >= 1300 && t < 1400);
KCard dominoFlipped(KCard t) => dominoIsFlipped(t) ? t - 100 : t + 100;
KCard dominoBase(KCard t) => dominoIsFlipped(t) ? t - 100 : t;
int dominoA(KCard t) {
  final b = dominoBase(t);
  return b >= 1200 ? (b - 1200) ~/ 10 : (b - 1000) ~/ 7;
}

int dominoB(KCard t) {
  final b = dominoBase(t);
  return b >= 1200 ? (b - 1200) % 10 : (b - 1000) % 7;
}

/// Çiçek ve mevsim taşları: 2200..2207 (tür 34..41).
int mjKind(KCard t) => t >= 2200 ? 34 + t - 2200 : (t - 2000) ~/ 4;

const _ivory = Color(0xFFF7F1E1);
const _edge = Color(0xFFD9CBA6);
const okeyInks = [Color(0xFFD99A00), Color(0xFF1F63B5), Color(0xFF1E2430), Color(0xFFC8322B)];
const _mjRed = Color(0xFFC8322B), _mjGreen = Color(0xFF1E7D4F), _mjBlue = Color(0xFF1F4E9A);

void _text(Canvas c, String t, Offset o, double size, Color color, {FontWeight w = FontWeight.w800}) {
  final tp = TextPainter(
    text: TextSpan(text: t, style: TextStyle(fontSize: size, color: color, fontWeight: w, height: 1)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, o - Offset(tp.width / 2, tp.height / 2));
}

RRect _body(Canvas c, Rect r, {Color face = _ivory}) {
  final rr = RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.14));
  c.drawRRect(rr.shift(Offset(0, r.width * 0.05)), Paint()..color = _edge);
  c.drawRRect(rr.shift(Offset(0, r.width * 0.08)), Paint()..color = Colors.black.withValues(alpha: 0.18));
  c.drawRRect(rr, Paint()..color = face);
  c.drawRRect(
      rr.deflate(r.width * 0.05),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, r.width * 0.03));
  return rr;
}

/// Kapalı taş sırtı.
void _back(Canvas c, Rect r, Color a, Color b) {
  final rr = RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.14));
  c.drawRRect(rr.shift(Offset(0, r.width * 0.06)), Paint()..color = Colors.black.withValues(alpha: 0.22));
  c.drawRRect(rr, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [a, b]).createShader(r));
  c.drawRRect(
      rr.deflate(r.width * 0.12),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, r.width * 0.04));
}

/// Taşı [r] içine çizer. [style] kTileOkey / kTileDomino / kTileMahjong.
void paintTile(Canvas c, Rect r, KCard t, int style,
    {required bool faceUp, Color backA = const Color(0xFF1F7A6B), Color backB = const Color(0xFF155247), bool highlight = false, bool dim = false, bool colorBlind = false}) {
  if (!faceUp) {
    _back(c, r, backA, backB);
  } else {
    switch (style) {
      case kTileOkey:
        _okey(c, r, t, colorBlind);
      case kTileDomino:
        _domino(c, r, t);
      default:
        _mahjong(c, r, t);
    }
  }
  final rr = RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.14));
  if (dim) c.drawRRect(rr, Paint()..color = Colors.black.withValues(alpha: 0.35));
  if (highlight) {
    c.drawRRect(
        rr.inflate(1.5),
        Paint()
          ..color = const Color(0xFFFFC53D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.5, r.width * 0.06));
  }
}

void _okey(Canvas c, Rect r, KCard t, bool colorBlind) {
  _body(c, r);
  final w = r.width;
  if (isOkeyFalseJoker(t)) {
    // Sahte okey: iç içe iki yonca halkası.
    final o = r.center;
    for (var k = 0; k < 4; k++) {
      final a = k * math.pi / 2;
      c.drawCircle(o + Offset(math.cos(a), math.sin(a)) * w * 0.14, w * 0.12, Paint()..color = const Color(0xFF2E8B57));
    }
    c.drawCircle(o, w * 0.07, Paint()..color = _ivory);
    return;
  }
  final col = okeyInks[okeyColor(t)];
  _text(c, '${okeyNumber(t)}', Offset(r.center.dx, r.top + r.height * 0.36), w * 0.5, col);
  // Sayının altında renk işareti; renk körü kipinde dört farklı biçim.
  final o = Offset(r.center.dx, r.top + r.height * 0.72), d = w * 0.1;
  final p = Paint()..color = col;
  switch (colorBlind ? okeyColor(t) : 0) {
    case 1:
      c.drawRect(Rect.fromCircle(center: o, radius: d), p);
    case 2:
      c.drawPath(
          Path()
            ..moveTo(o.dx, o.dy - d * 1.2)
            ..lineTo(o.dx + d * 1.2, o.dy + d)
            ..lineTo(o.dx - d * 1.2, o.dy + d)
            ..close(),
          p);
    case 3:
      c.drawPath(
          Path()
            ..moveTo(o.dx, o.dy - d * 1.3)
            ..lineTo(o.dx + d * 1.3, o.dy)
            ..lineTo(o.dx, o.dy + d * 1.3)
            ..lineTo(o.dx - d * 1.3, o.dy)
            ..close(),
          p);
    default:
      c.drawCircle(o, d, p);
  }
}

void _pips(Canvas c, Rect half, int n) {
  const pos = {
    0: <(double, double)>[],
    1: [(0.5, 0.5)],
    2: [(0.27, 0.27), (0.73, 0.73)],
    3: [(0.25, 0.25), (0.5, 0.5), (0.75, 0.75)],
    4: [(0.27, 0.27), (0.73, 0.27), (0.27, 0.73), (0.73, 0.73)],
    5: [(0.25, 0.25), (0.75, 0.25), (0.5, 0.5), (0.25, 0.75), (0.75, 0.75)],
    6: [(0.27, 0.22), (0.73, 0.22), (0.27, 0.5), (0.73, 0.5), (0.27, 0.78), (0.73, 0.78)],
    7: [(0.27, 0.22), (0.73, 0.22), (0.27, 0.5), (0.5, 0.5), (0.73, 0.5), (0.27, 0.78), (0.73, 0.78)],
    8: [(0.22, 0.2), (0.5, 0.2), (0.78, 0.2), (0.22, 0.5), (0.78, 0.5), (0.22, 0.8), (0.5, 0.8), (0.78, 0.8)],
    9: [(0.22, 0.2), (0.5, 0.2), (0.78, 0.2), (0.22, 0.5), (0.5, 0.5), (0.78, 0.5), (0.22, 0.8), (0.5, 0.8), (0.78, 0.8)],
  };
  final rad = math.min(half.width, half.height) * (n > 6 ? 0.085 : 0.1);
  for (final (x, y) in pos[n]!) {
    c.drawCircle(Offset(half.left + x * half.width, half.top + y * half.height), rad, Paint()..color = const Color(0xFF1E2430));
  }
}

void _domino(Canvas c, Rect r, KCard t) {
  // Dikey domino: oran 1:2, verilen kutunun ortasına sığdırılır.
  final h = math.min(r.height, r.width * 2), w = h / 2;
  final box = Rect.fromCenter(center: r.center, width: w, height: h);
  _body(c, box);
  final top = Rect.fromLTWH(box.left, box.top, w, h / 2), bottom = Rect.fromLTWH(box.left, box.top + h / 2, w, h / 2);
  c.drawLine(Offset(box.left + w * 0.15, box.center.dy), Offset(box.right - w * 0.15, box.center.dy),
      Paint()
        ..color = const Color(0xFF8C7B57)
        ..strokeWidth = math.max(1, w * 0.04));
  final flip = dominoIsFlipped(t);
  _pips(c, top.deflate(w * 0.06), flip ? dominoB(t) : dominoA(t));
  _pips(c, bottom.deflate(w * 0.06), flip ? dominoA(t) : dominoB(t));
}

const _winds = ['東', '南', '西', '北'];
const _numerals = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];

void _mahjong(Canvas c, Rect r, KCard t) {
  _body(c, r);
  final k = mjKind(t), w = r.width;
  final inner = r.deflate(w * 0.14);
  if (k < 9) {
    // Daireler.
    final n = k + 1;
    final cols = n <= 3 ? 1 : 2;
    final rows = (n / cols).ceil();
    final cw = inner.width / cols, ch = inner.height / rows;
    final rad = math.min(cw, ch) * 0.36;
    for (var i = 0; i < n; i++) {
      final cx = n <= 3 ? inner.center.dx : inner.left + (i % cols + 0.5) * cw;
      final cy = inner.top + ((n <= 3 ? i : i ~/ cols) + 0.5) * ch;
      final col = [_mjBlue, _mjGreen, _mjRed][i % 3];
      c.drawCircle(Offset(cx, cy), rad, Paint()..color = col);
      c.drawCircle(Offset(cx, cy), rad * 0.5, Paint()..color = _ivory);
    }
  } else if (k < 18) {
    // Bambu çubukları.
    final n = k - 8;
    final cols = n <= 3 ? n : 3;
    final rows = (n / cols).ceil();
    final cw = inner.width / cols, ch = inner.height / rows;
    for (var i = 0; i < n; i++) {
      final cx = inner.left + (i % cols + 0.5) * cw, cy = inner.top + (i ~/ cols + 0.5) * ch;
      final stick = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy), width: cw * 0.32, height: ch * 0.8), Radius.circular(cw * 0.12));
      c.drawRRect(stick, Paint()..color = i == 0 && n == 1 ? _mjRed : _mjGreen);
      c.drawLine(Offset(cx - cw * 0.16, cy), Offset(cx + cw * 0.16, cy), Paint()..color = _ivory..strokeWidth = math.max(1, ch * 0.05));
    }
  } else if (k < 27) {
    _text(c, _numerals[k - 18], Offset(r.center.dx, r.top + r.height * 0.33), w * 0.42, const Color(0xFF1E2430));
    _text(c, '萬', Offset(r.center.dx, r.top + r.height * 0.7), w * 0.42, _mjRed);
  } else if (k < 31) {
    _text(c, _winds[k - 27], r.center, w * 0.55, const Color(0xFF1E2430));
  } else if (k == 31) {
    _text(c, '中', r.center, w * 0.6, _mjRed);
  } else if (k == 32) {
    _text(c, '發', r.center, w * 0.6, _mjGreen);
  } else if (k >= 34) {
    // Çiçek (34..37) ve mevsim (38..41): beş yapraklı çiçek ve sıra numarası.
    final col = k < 38 ? _mjRed : _mjBlue;
    final o = Offset(r.center.dx, r.top + r.height * 0.42);
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 5;
      c.drawCircle(o + Offset(math.cos(a), math.sin(a)) * w * 0.15, w * 0.11, Paint()..color = col.withValues(alpha: 0.85));
    }
    c.drawCircle(o, w * 0.08, Paint()..color = const Color(0xFFE5B712));
    _text(c, '${(k - 34) % 4 + 1}', Offset(r.center.dx, r.top + r.height * 0.8), w * 0.26, const Color(0xFF1E2430));
  } else {
    c.drawRect(
        inner.deflate(w * 0.06),
        Paint()
          ..color = _mjBlue
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, w * 0.06));
  }
}
