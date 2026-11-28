/// Her kart oyununun kendi masası: çuha rengi, dokusu, masa kenarı (ahşap /
/// deri), ortadaki süsleme ve kart sırtı. Görseller stüdyonun kendi geometrik
/// çizimleridir; onaylı dış çerçeve (vurgu kenarı) korunur, yalnız oyun alanı
/// oyuna özgü olur. Oyun kimliği, oyunun AppState kapsamından okunur; kapsam
/// yoksa (ör. birim testleri) klasik yeşil masa kullanılır.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:studio_core/app/app_state.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/theme.dart' show Palettes;

import 'card_painter.dart';

/// Çuha dokusu.
enum FeltPattern { grain, diamonds, kilim, rings, pinstripe, arabesque, hexes, waves, stars, checks, scales, chevron }

/// Masanın ortasındaki soluk süsleme.
enum TableOrnament { none, rosette, star8, compass, laurel, tulip, knot, sun }

class KartTableTheme {
  final String id;
  final Color feltLight, feltMid, feltDark;
  final FeltPattern pattern;
  final TableOrnament ornament;
  final Color railLight, railDark;

  /// Süsleme ve kenar kakması rengi.
  final Color trim;
  final Color backA, backB;

  /// Kart sırtı deseni ([paintCard] içinde, 0–7).
  final int back;

  const KartTableTheme({
    this.id = '',
    required this.feltLight,
    required this.feltMid,
    required this.feltDark,
    required this.pattern,
    required this.ornament,
    required this.railLight,
    required this.railDark,
    required this.trim,
    required this.backA,
    required this.backB,
    required this.back,
  });

  // Çuha renkleri: (orta ışık, ana, kenar).
  static const _felts = <List<Color>>[
    [Color(0xFF2F8A5B), Color(0xFF1C6143), Color(0xFF123F2C)], // 0 klasik yeşil
    [Color(0xFF2A8C8C), Color(0xFF17605F), Color(0xFF0D3C3D)], // 1 deniz yeşili
    [Color(0xFF9A3242), Color(0xFF6E1F2D), Color(0xFF42111A)], // 2 bordo
    [Color(0xFF3463AE), Color(0xFF21437F), Color(0xFF13274F)], // 3 kraliyet mavisi
    [Color(0xFF25577F), Color(0xFF183D5E), Color(0xFF0C2338)], // 4 gece lacivert
    [Color(0xFF74418A), Color(0xFF512A61), Color(0xFF2F1739)], // 5 patlıcan moru
    [Color(0xFFA9553C), Color(0xFF7E3A29), Color(0xFF4B2016)], // 6 kiremit
    [Color(0xFF6F813A), Color(0xFF4F5D27), Color(0xFF2F3816)], // 7 zeytin
    [Color(0xFF4E5965), Color(0xFF353D47), Color(0xFF1E2329)], // 8 arduvaz
    [Color(0xFF8E5D2D), Color(0xFF67421D), Color(0xFF3D260F)], // 9 tütün
    [Color(0xFF1F9C7A), Color(0xFF137358), Color(0xFF0A4836)], // 10 yeşim
    [Color(0xFF3F4394), Color(0xFF292C69), Color(0xFF16183F)], // 11 çivit
    [Color(0xFFA8495E), Color(0xFF7C3244), Color(0xFF4B1C28)], // 12 gül kurusu
    [Color(0xFF2182A4), Color(0xFF155D77), Color(0xFF0B384A)], // 13 İznik turkuazı
    [Color(0xFFA0822E), Color(0xFF77601E), Color(0xFF473A0F)], // 14 safran
    [Color(0xFF316F42), Color(0xFF204F2E), Color(0xFF112E19)], // 15 çam
  ];

  // Masa kenarı: (açık, koyu).
  static const _rails = <List<Color>>[
    [Color(0xFF9A6A42), Color(0xFF5A3A22)], // 0 ceviz
    [Color(0xFFA04A33), Color(0xFF5E2418)], // 1 maun
    [Color(0xFFC09A62), Color(0xFF7A5A32)], // 2 meşe
    [Color(0xFF4F443C), Color(0xFF1F1A17)], // 3 abanoz
    [Color(0xFF3A3A44), Color(0xFF15151B)], // 4 siyah deri
    [Color(0xFF7A2E2E), Color(0xFF3E1414)], // 5 kızıl deri
    [Color(0xFFB98A4A), Color(0xFF6E4A1E)], // 6 kehribar
  ];

  // Süsleme / kakma renkleri.
  static const _trims = <Color>[
    Color(0xFFF2D38A), // 0 altın
    Color(0xFFE9E4D6), // 1 fildişi
    Color(0xFFB8D8E8), // 2 gümüş mavi
    Color(0xFFF0B49A), // 3 bakır
  ];

  // Kart sırtı renk çiftleri.
  static const _backs = <List<Color>>[
    [Color(0xFF1F5E8C), Color(0xFF2BB3B1)], // 0 deniz
    [Color(0xFF8E1F2E), Color(0xFFD0563E)], // 1 al
    [Color(0xFF1E3A6E), Color(0xFFC9A44A)], // 2 lacivert-altın
    [Color(0xFF2F6B3A), Color(0xFF9CC46A)], // 3 yeşil
    [Color(0xFF5B2F7A), Color(0xFFC46AA8)], // 4 mor
    [Color(0xFF2B2B33), Color(0xFF8A7A5A)], // 5 kömür-bronz
    [Color(0xFFB4532A), Color(0xFFF0B04A)], // 6 turuncu
    [Color(0xFF0F5F66), Color(0xFFE0C27A)], // 7 petrol-kum
    [Color(0xFF6E1E3A), Color(0xFF3E5FA8)], // 8 vişne-mavi
    [Color(0xFF3B4A5A), Color(0xFF8FB3C8)], // 9 çelik
    [Color(0xFF7A4A1E), Color(0xFFD8A35A)], // 10 kahve
    [Color(0xFF233D2B), Color(0xFFC94A3A)], // 11 yeşil-kırmızı
  ];

  /// Oyun → [çuha, doku, süs, kenar, kakma, sırt rengi, sırt deseni].
  static const Map<String, List<int>> _games = {
    // Rakipli el alma oyunları
    'oyun-batak': [2, 2, 1, 1, 0, 2, 7],
    'oyun-batak-cesitleri': [6, 1, 2, 0, 0, 1, 0],
    'oyun-batak-cesit-esli': [6, 1, 2, 0, 0, 1, 0],
    'oyun-batak-cesit-kozmaca': [8, 2, 3, 4, 0, 5, 7],
    'oyun-batak-cesit-esli-kozmaca': [4, 2, 1, 3, 0, 2, 3],
    'oyun-batak-cesit-buyuk': [12, 1, 6, 1, 0, 1, 6],
    'oyun-batak-cesit-esli-buyuk': [10, 2, 5, 0, 0, 7, 0],
    'oyun-king': [3, 5, 2, 2, 0, 2, 3],
    'oyun-hearts': [12, 10, 1, 5, 1, 1, 2],
    'oyun-spades': [8, 4, 3, 4, 2, 5, 6],
    'oyun-bric-benzeri-whist': [15, 9, 4, 0, 1, 3, 1],
    'oyun-kontrat-bric': [4, 9, 3, 3, 0, 2, 1],
    'oyun-oh-hell': [5, 8, 7, 3, 0, 4, 3],
    'oyun-briscola': [7, 1, 4, 2, 1, 1, 4],
    'oyun-sueca': [13, 7, 6, 2, 1, 7, 4],
    'oyun-euchre': [9, 9, 5, 2, 1, 10, 1],
    'oyun-belot': [11, 8, 2, 0, 0, 8, 0],
    'oyun-klaverjas': [1, 3, 7, 2, 1, 9, 5],
    'oyun-jass': [6, 9, 4, 0, 1, 11, 5],
    'oyun-pinokl': [9, 1, 6, 6, 0, 10, 6],
    'oyun-skat': [7, 6, 3, 3, 0, 3, 5],
    'oyun-koyun-basi': [15, 11, 5, 0, 1, 3, 4],
    'oyun-tarneeb': [10, 5, 2, 6, 0, 7, 7],
    'oyun-trix': [2, 5, 7, 6, 0, 1, 3],
    'oyun-baloot': [14, 5, 1, 6, 1, 6, 7],
    'oyun-hokm': [13, 5, 6, 1, 0, 8, 7],
    'oyun-yirmi-dokuz': [12, 2, 7, 1, 0, 6, 2],
    'oyun-bezik': [5, 4, 5, 3, 0, 4, 1],
    'oyun-tarok': [11, 10, 7, 3, 0, 5, 3],
    'oyun-doppelkopf': [8, 6, 3, 0, 1, 9, 6],
    // Masada toplama / eşleme / el boşaltma
    'oyun-pisti': [0, 2, 5, 0, 0, 1, 0],
    'oyun-scopa': [10, 1, 7, 2, 1, 11, 2],
    'oyun-toplam-al': [1, 11, 1, 0, 1, 0, 2],
    'oyun-renk-esle-kart-oyunu': [3, 8, 7, 4, 1, 6, 3],
    'oyun-savas': [8, 11, 4, 5, 3, 1, 6],
    'oyun-baskan': [11, 5, 6, 3, 0, 4, 6],
    'oyun-papaz-kacti': [9, 10, 5, 0, 1, 10, 2],
    'oyun-balik-tut': [13, 7, 3, 2, 2, 0, 4],
    'oyun-blof': [12, 4, 6, 4, 0, 8, 5],
    'oyun-31': [15, 1, 7, 1, 0, 3, 0],
    'oyun-durak': [4, 2, 6, 1, 0, 8, 1],
    'oyun-cribbage': [9, 4, 3, 2, 1, 10, 5],
    // Remi ailesi
    'oyun-konken': [1, 2, 1, 1, 0, 7, 3],
    'oyun-gin-remi': [10, 9, 4, 3, 1, 3, 6],
    'oyun-kart-remi': [6, 7, 2, 0, 1, 6, 1],
    'oyun-asamali-remi': [3, 11, 5, 2, 1, 9, 2],
    'oyun-kanasta': [14, 2, 7, 6, 1, 1, 4],
    'oyun-el-ve-ayak': [5, 10, 4, 2, 1, 4, 0],
    'oyun-cincon': [14, 9, 6, 1, 1, 11, 7],
    'oyun-burako': [2, 3, 5, 6, 0, 7, 6],
    // Hız ve diğer
    'oyun-snap': [6, 8, 7, 4, 1, 6, 6],
    'oyun-hiz': [13, 11, 3, 4, 2, 0, 3],
    'oyun-nertz': [7, 3, 5, 2, 1, 3, 2],
    'oyun-kemps': [12, 7, 4, 3, 1, 4, 5],
    'oyun-kart-hafiza': [5, 8, 1, 2, 1, 4, 7],
    'oyun-kart-yolu': [10, 7, 7, 2, 1, 7, 6],
    'oyun-kart-karesi': [6, 6, 2, 1, 0, 6, 5],
    // Solitaire
    'oyun-klondike-solitaire': [0, 0, 2, 0, 0, 0, 0],
    'oyun-spider-solitaire': [5, 6, 6, 3, 2, 4, 6],
    'oyun-freecell': [4, 6, 3, 2, 1, 9, 1],
    'oyun-pyramid-solitaire': [14, 11, 7, 6, 0, 10, 3],
    'oyun-tripeaks-solitaire': [13, 11, 7, 2, 1, 7, 3],
    'oyun-golf-solitaire': [15, 4, 4, 2, 1, 3, 1],
    'oyun-yukon-solitaire': [4, 3, 3, 3, 2, 9, 4],
    'oyun-scorpion-solitaire': [6, 11, 6, 3, 0, 5, 6],
    'oyun-forty-thieves': [11, 1, 2, 3, 0, 8, 2],
    'oyun-canfield': [2, 0, 5, 1, 0, 1, 1],
    'oyun-accordion-solitaire': [7, 4, 5, 0, 1, 3, 4],
    'oyun-clock-solitaire': [8, 3, 3, 4, 0, 5, 3],
    'oyun-solitaire-cesitleri': [1, 0, 2, 0, 0, 0, 7],
  };

  static final Map<String, KartTableTheme> _cache = {};

  /// Oyunun masa teması (bilinmeyen oyunlarda kimlikten türetilir).
  static KartTableTheme forGame(String id) => _cache.putIfAbsent(id, () {
        var spec = _games[id];
        if (spec == null) {
          var h = 7;
          for (final u in id.codeUnits) {
            h = (h * 31 + u) & 0x7fffffff;
          }
          spec = id.isEmpty
              ? const [0, 0, 2, 0, 0, 0, 0]
              : [h % _felts.length, (h ~/ 16) % 12, 1 + (h ~/ 192) % 7, (h ~/ 7) % _rails.length, (h ~/ 3) % _trims.length, (h ~/ 5) % _backs.length, (h ~/ 11) % 8];
        }
        final f = _felts[spec[0] % _felts.length];
        final r = _rails[spec[3] % _rails.length];
        final b = _backs[spec[5] % _backs.length];
        return KartTableTheme(
          id: id,
          feltLight: f[0],
          feltMid: f[1],
          feltDark: f[2],
          pattern: FeltPattern.values[spec[1] % FeltPattern.values.length],
          ornament: TableOrnament.values[spec[2] % TableOrnament.values.length],
          railLight: r[0],
          railDark: r[1],
          trim: _trims[spec[4] % _trims.length],
          backA: b[0],
          backB: b[1],
          back: spec[6] % 8,
        );
      });

  /// Ağaçtaki oyunun kimliği (oyunun AppState kapsamı); yoksa null.
  static String? gameIdOf(BuildContext context) {
    try {
      return ProviderScope.containerOf(context, listen: false).read(appStateProvider).config.gameId;
    } catch (_) {
      return null;
    }
  }

  static KartTableTheme of(BuildContext context) => forGame(gameIdOf(context) ?? debugGameId ?? '');

  /// Testlerde (AppState kapsamı yokken) kullanılacak oyun kimliği.
  static String? debugGameId;

  /// Bilinen bütün oyun kimlikleri (testler için).
  static Iterable<String> get knownGames => _games.keys;

  /// İki temanın oyun alanında ayırt edici imzası.
  String get signature => '${feltMid.toARGB32()}|${pattern.index}|${ornament.index}|${back}|${backA.toARGB32()}';
}

/// Oyunun kart stili: oyuncu mağazadan bir görünüm seçtiyse sırt onun
/// renklerini alır; varsayılan görünümde sırt oyunun kendi temasındandır.
CardStyle kartCardStyle(BuildContext context, PlayContext ctx, {bool spanish = false}) {
  final t = KartTableTheme.of(context);
  final def = Palettes.skin(0);
  final custom = ctx.pieceColors.length > 1 && ctx.pieceColors[0] != def[0];
  return CardStyle(
    backA: custom ? ctx.pieceColors[0] : t.backA,
    backB: custom ? ctx.pieceColors[1] : t.backB,
    back: t.back,
    colorBlind: ctx.colorBlind,
    spanish: spanish,
  );
}

/// Çuha: ışık, doku, masa çizgisi ve süsleme.
class FeltPainter extends CustomPainter {
  final KartTableTheme t;
  const FeltPainter(this.t);

  @override
  bool shouldRepaint(covariant FeltPainter o) => o.t != t;

  @override
  void paint(Canvas c, Size s) {
    final rect = Offset.zero & s;
    c.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, -0.15),
            radius: 1.05,
            colors: [t.feltLight, t.feltMid, t.feltDark],
            stops: const [0, 0.62, 1],
          ).createShader(rect));
    c.save();
    c.clipRect(rect);
    _pattern(c, s);
    c.restore();
    // Masa çizgisi: oyun alanını çevreleyen yarış pisti biçimli ince kakma.
    final inset = math.min(s.width, s.height) * 0.07 + 6;
    final track = RRect.fromRectAndRadius(rect.deflate(inset), Radius.circular(math.min(s.width, s.height) * 0.3));
    c.drawRRect(
        track,
        Paint()
          ..color = t.trim.withValues(alpha: 0.16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    c.drawRRect(
        track.deflate(5),
        Paint()
          ..color = t.trim.withValues(alpha: 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    _ornament(c, s.center(Offset.zero), math.min(s.width, s.height) * 0.2);
    // Kenarlarda yumuşak gölge (vinyet).
    c.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            radius: 0.95,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.28)],
            stops: const [0.7, 1],
          ).createShader(rect));
  }

  void _pattern(Canvas c, Size s) {
    final light = Paint()..color = Colors.white.withValues(alpha: 0.045);
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final dark = Paint()..color = Colors.black.withValues(alpha: 0.07);
    final r = math.Random(t.id.length + 11);
    // Her dokunun altında ince çuha tanesi.
    final grain = Paint()..color = Colors.white.withValues(alpha: 0.022);
    for (var i = 0; i < 220; i++) {
      c.drawCircle(Offset(r.nextDouble() * s.width, r.nextDouble() * s.height), 0.6 + r.nextDouble() * 0.9, grain);
    }
    switch (t.pattern) {
      case FeltPattern.grain:
        for (var i = 0; i < 160; i++) {
          c.drawCircle(Offset(r.nextDouble() * s.width, r.nextDouble() * s.height), 0.8 + r.nextDouble(), light);
        }
      case FeltPattern.diamonds:
        const g = 34.0;
        for (var x = -s.height; x < s.width + s.height; x += g) {
          c.drawLine(Offset(x, 0), Offset(x + s.height, s.height), line);
          c.drawLine(Offset(x, s.height), Offset(x + s.height, 0), line);
        }
      case FeltPattern.kilim:
        // Anadolu kilimi: yatay şeritlerde basamaklı baklavalar ve zikzak.
        const band = 96.0;
        for (var y = 30.0; y < s.height; y += band) {
          final zig = Path()..moveTo(0, y);
          for (var x = 0.0; x <= s.width + 12; x += 12) {
            zig.lineTo(x, y + ((x / 12).round().isEven ? 0 : 7));
          }
          c.drawPath(zig, line);
          for (var x = 24.0; x < s.width; x += 48) {
            final cy = y + 40;
            for (final d in [14.0, 8.0]) {
              c.drawPath(
                  Path()
                    ..moveTo(x, cy - d)
                    ..lineTo(x + d, cy)
                    ..lineTo(x, cy + d)
                    ..lineTo(x - d, cy)
                    ..close(),
                  d > 10 ? line : light);
            }
          }
        }
      case FeltPattern.rings:
        final ctr = s.center(Offset.zero);
        for (var rad = 26.0; rad < s.longestSide; rad += 26) {
          c.drawCircle(ctr, rad, line);
        }
      case FeltPattern.pinstripe:
        for (var x = 0.0; x < s.width; x += 14) {
          c.drawLine(Offset(x, 0), Offset(x, s.height), (x / 14).round() % 4 == 0 ? line : (Paint()..color = Colors.black.withValues(alpha: 0.05)));
        }
      case FeltPattern.arabesque:
        // Sekiz köşeli yıldız döşemesi (girih esinli).
        const g = 54.0;
        for (var y = 0.0; y < s.height + g; y += g) {
          for (var x = 0.0; x < s.width + g; x += g) {
            _star8(c, Offset(x, y), g * 0.3, line);
            c.drawCircle(Offset(x + g / 2, y + g / 2), 2.2, light);
          }
        }
      case FeltPattern.hexes:
        const rr = 20.0;
        final hw = rr * math.sqrt(3);
        var row = 0;
        for (var y = 0.0; y < s.height + rr * 2; y += rr * 1.5) {
          final off = row.isOdd ? hw / 2 : 0.0;
          for (var x = -hw; x < s.width + hw; x += hw) {
            final p = Path();
            for (var k = 0; k < 6; k++) {
              final a = math.pi / 6 + k * math.pi / 3;
              final pt = Offset(x + off + rr * math.cos(a), y + rr * math.sin(a));
              k == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
            }
            p.close();
            c.drawPath(p, line);
          }
          row++;
        }
      case FeltPattern.waves:
        for (var y = 0.0; y < s.height + 20; y += 22) {
          final p = Path()..moveTo(0, y);
          for (var x = 0.0; x <= s.width; x += 8) {
            p.lineTo(x, y + math.sin(x / 18 + y / 40) * 5);
          }
          c.drawPath(p, line);
        }
      case FeltPattern.stars:
        const g = 46.0;
        var row = 0;
        for (var y = 12.0; y < s.height; y += g) {
          for (var x = (row.isOdd ? g / 2 : 0.0) + 12; x < s.width; x += g) {
            final p = Path();
            for (var k = 0; k < 8; k++) {
              final a = -math.pi / 2 + k * math.pi / 4;
              final rad = k.isEven ? 6.0 : 2.0;
              final pt = Offset(x + rad * math.cos(a), y + rad * math.sin(a));
              k == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
            }
            c.drawPath(p..close(), light);
          }
          row++;
        }
      case FeltPattern.checks:
        const g = 40.0;
        for (var y = 0.0; y < s.height; y += g) {
          for (var x = 0.0; x < s.width; x += g) {
            if (((x + y) / g).round().isEven) c.drawRect(Rect.fromLTWH(x, y, g, g), dark);
          }
        }
      case FeltPattern.scales:
        // Dalga pulları (yarım daireler, kaydırmalı sıralar).
        const g = 30.0;
        var row = 0;
        for (var y = 0.0; y < s.height + g; y += g / 2) {
          for (var x = row.isOdd ? g / 2 : 0.0; x < s.width + g; x += g) {
            c.drawArc(Rect.fromCircle(center: Offset(x, y), radius: g / 2), math.pi, math.pi, false, line);
          }
          row++;
        }
      case FeltPattern.chevron:
        for (var y = 0.0; y < s.height + 20; y += 20) {
          final p = Path()..moveTo(0, y);
          var up = true;
          for (var x = 0.0; x <= s.width + 16; x += 16) {
            p.lineTo(x, y + (up ? 0 : 9));
            up = !up;
          }
          c.drawPath(p, line);
        }
    }
  }

  static void _star8(Canvas c, Offset o, double r, Paint p) {
    c.drawRect(Rect.fromCenter(center: o, width: r * 1.4, height: r * 1.4), p);
    c.save();
    c.translate(o.dx, o.dy);
    c.rotate(math.pi / 4);
    c.drawRect(Rect.fromCenter(center: Offset.zero, width: r * 1.4, height: r * 1.4), p);
    c.restore();
  }

  void _ornament(Canvas c, Offset o, double r) {
    final p = Paint()
      ..color = t.trim.withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final fill = Paint()..color = t.trim.withValues(alpha: 0.06);
    switch (t.ornament) {
      case TableOrnament.none:
        return;
      case TableOrnament.rosette:
        c.drawCircle(o, r * 0.34, p);
        for (var k = 0; k < 12; k++) {
          final a = k * math.pi / 6;
          c.drawCircle(o + Offset(math.cos(a), math.sin(a)) * r * 0.62, r * 0.28, p);
        }
        c.drawCircle(o, r * 0.92, p);
      case TableOrnament.star8:
        _star8(c, o, r * 0.9, p);
        _star8(c, o, r * 0.55, p);
        c.drawCircle(o, r * 0.3, fill);
        c.drawCircle(o, r, p);
      case TableOrnament.compass:
        final path = Path();
        for (var k = 0; k < 16; k++) {
          final a = -math.pi / 2 + k * math.pi / 8;
          final rad = k.isEven ? (k % 4 == 0 ? r : r * 0.62) : r * 0.2;
          final pt = o + Offset(math.cos(a), math.sin(a)) * rad;
          k == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
        }
        c.drawPath(path..close(), fill);
        c.drawPath(path, p);
        c.drawCircle(o, r * 0.75, p);
      case TableOrnament.laurel:
        for (final side in [-1.0, 1.0]) {
          for (var k = 0; k < 8; k++) {
            final a = math.pi / 2 + side * (0.35 + k * 0.32);
            final pt = o + Offset(math.cos(a), math.sin(a)) * r * 0.85;
            c.save();
            c.translate(pt.dx, pt.dy);
            c.rotate(a + side * 0.6);
            c.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 0.3, height: r * 0.12), fill);
            c.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 0.3, height: r * 0.12), p);
            c.restore();
          }
        }
      case TableOrnament.tulip:
        final path = Path()
          ..moveTo(o.dx, o.dy + r * 0.2)
          ..cubicTo(o.dx - r * 0.55, o.dy, o.dx - r * 0.5, o.dy - r * 0.55, o.dx - r * 0.3, o.dy - r * 0.75)
          ..quadraticBezierTo(o.dx - r * 0.15, o.dy - r * 0.35, o.dx, o.dy - r * 0.8)
          ..quadraticBezierTo(o.dx + r * 0.15, o.dy - r * 0.35, o.dx + r * 0.3, o.dy - r * 0.75)
          ..cubicTo(o.dx + r * 0.5, o.dy - r * 0.55, o.dx + r * 0.55, o.dy, o.dx, o.dy + r * 0.2)
          ..close();
        c.drawPath(path, fill);
        c.drawPath(path, p);
        c.drawLine(o + Offset(0, r * 0.2), o + Offset(0, r * 0.9), p);
        for (final side in [-1.0, 1.0]) {
          c.drawPath(
              Path()
                ..moveTo(o.dx, o.dy + r * 0.75)
                ..quadraticBezierTo(o.dx + side * r * 0.5, o.dy + r * 0.55, o.dx + side * r * 0.55, o.dy + r * 0.25),
              p);
        }
      case TableOrnament.knot:
        for (var k = 0; k < 4; k++) {
          c.save();
          c.translate(o.dx, o.dy);
          c.rotate(k * math.pi / 2);
          c.drawOval(Rect.fromLTWH(-r * 0.22, -r * 0.95, r * 0.44, r * 0.95), p);
          c.restore();
        }
        c.drawCircle(o, r * 0.18, fill);
      case TableOrnament.sun:
        c.drawCircle(o, r * 0.42, fill);
        c.drawCircle(o, r * 0.42, p);
        for (var k = 0; k < 24; k++) {
          final a = k * math.pi / 12;
          c.drawLine(o + Offset(math.cos(a), math.sin(a)) * r * 0.55, o + Offset(math.cos(a), math.sin(a)) * r * (k.isEven ? 0.95 : 0.75), p);
        }
    }
  }
}

/// Masa kenarı (ahşap/deri pervaz) ile çevrili çuha.
class KartTableSurface extends StatelessWidget {
  final KartTableTheme theme;
  final Widget child;
  const KartTableSurface({super.key, required this.theme, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.railLight, theme.railDark, theme.railLight.withValues(alpha: 0.9), theme.railDark],
          stops: const [0, 0.45, 0.6, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: theme.trim.withValues(alpha: 0.35), width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: CustomPaint(painter: FeltPainter(theme), child: child),
          ),
        ),
      ),
    );
  }
}
