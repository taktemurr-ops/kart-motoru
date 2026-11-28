// Taş masası ekran görüntüleri: Okey ailesi (ve Mahjong, Domino) bölümleri
// gerçek hamlelerle sonuna kadar oynanır; açılış, oyun ortası ve el sonu
// tablosu telefon ve tablet boyutunda PNG olarak SHOTS_DIR'e yazılır.
// Yalnız SHOTS_DIR verilince çalışır (oyun testi iş akışı).
@Tags(['shots'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';
import 'package:kart_motoru/src/okey_texts.dart';
import 'package:kart_motoru/src/studio_chrome.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';

final _out = Platform.environment['SHOTS_DIR'];
final _log = <String>[];

Future<void> _loadFonts() async {
  Future<void> load(String family, Iterable<File> files) async {
    final l = FontLoader(family);
    var n = 0;
    for (final f in files) {
      if (!f.existsSync()) continue;
      l.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      n++;
    }
    if (n > 0) await l.load();
  }

  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final mf = Directory('${artifacts.path}/material_fonts');
  if (mf.existsSync()) {
    final all = mf.listSync().whereType<File>().toList();
    await load('Roboto', all.where((f) => f.path.contains('Roboto-') && f.path.endsWith('.ttf')));
    await load('MaterialIcons', all.where((f) => f.path.contains('MaterialIcons')));
  }
  const noto = '/usr/share/fonts/truetype/noto';
  await load('Noto Naskh Arabic', [File('$noto/NotoNaskhArabic-Regular.ttf'), File('$noto/NotoNaskhArabic-Bold.ttf')]);
  await load('Noto Sans CJK', [File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'), File('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc')]);
  await load('Noto Color Emoji', [File('$noto/NotoColorEmoji.ttf')]);
}

PlayContext _ctx(GeneratedLevel gl, String lang, {List<SeatRole> seats = const [], void Function(RoundResult)? fin}) => PlayContext(
      spec: gl.spec,
      generated: gl,
      resume: const {},
      pieceColors: const [Color(0xFF3E6FB0), Color(0xFFC8553D)],
      background: const [Color(0xFF1A2E5C), Color(0xFF3A6FC4)],
      colorBlind: false,
      reducedMotion: true,
      leftHanded: false,
      lang: lang,
      t: (k, [p = const {}]) => k,
      finish: fin ?? (_) {},
      saveResume: (_) {},
      requestHint: () async => true,
      requestBooster: () async => true,
      requestContinue: () async => false,
      sfx: (_) {},
      seats: seats,
    );

final _key = GlobalKey();

Widget _host(Widget child, String lang) => MaterialApp(
      theme: ThemeData(
        brightness: Brightness.light,
        extensions: const [StudioLook()],
        fontFamily: 'Roboto',
        fontFamilyFallback: const ['Noto Naskh Arabic', 'Noto Sans CJK', 'Noto Color Emoji'],
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF101426),
        body: RepaintBoundary(
          key: _key,
          child: Directionality(
            textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            child: child,
          ),
        ),
      ),
    );

Future<void> _shot(WidgetTester t, String name) async {
  await t.pump(const Duration(milliseconds: 50));
  final ro = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final img = await ro.toImage(pixelRatio: 1);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    File('$_out/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
  _log.add('shot $name');
}

void _size(WidgetTester t, Size s) {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = s;
}

const _phone = Size(393, 760);
const _tablet = Size(1280, 740);

bool _has(String text) => find.textContaining(text).evaluate().isNotEmpty;

Future<void> _tapText(WidgetTester t, String text) async {
  final f = find.textContaining(text);
  if (f.evaluate().isEmpty) return;
  await t.tap(f.first, warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 120));
}

/// Bütün koltukları yapay zekâ oynar; [at] saniyelerde ve el sonunda görüntü.
Future<String> _aiRun(WidgetTester t, String name, GeneratedLevel gl, String lang, {List<int> at = const [6, 16]}) async {
  RoundResult? res;
  final seats = List.filled((gl.puzzle as TableLevel).start.seats, SeatRole.ai);
  await t.pumpWidget(_host(TableView(ctx: _ctx(gl, lang, seats: seats, fin: (r) => res = r)), lang));
  await t.pump(const Duration(milliseconds: 300));
  var ms = 0;
  final cont = okt(lang, 'continue');
  while (ms < 240000) {
    await t.pump(const Duration(milliseconds: 100));
    ms += 100;
    if (at.contains(ms ~/ 1000) && ms % 1000 == 0) await _shot(t, '${name}_t${ms ~/ 1000}');
    if (_has(cont)) {
      await _shot(t, '${name}_sonu');
      await _tapText(t, cont);
      break;
    }
    if (res != null) break;
  }
  await t.pump(const Duration(milliseconds: 300));
  final out = '$name: ${ms ~/ 1000}s ${res == null ? 'SONUÇ YOK' : 'won=${res!.won} score=${res!.score}'}';
  _log.add(out);
  expect(t.takeException(), isNull, reason: name);
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
  return out;
}

/// Oyuncu (koltuk 0) arayüzden oynar: deste/atık, aç, per indir, işle, at.
Future<String> _humanRun(WidgetTester t, String name, GeneratedLevel gl, String lang, {int shotEvery = 0}) async {
  RoundResult? res;
  await t.pumpWidget(_host(TableView(ctx: _ctx(gl, lang, fin: (r) => res = r)), lang));
  await t.pump(const Duration(milliseconds: 400));
  await _shot(t, '${name}_acilis');
  final cont = okt(lang, 'continue');
  var moves = 0, idle = 0;
  while (moves < 400 && idle < 1200) {
    await t.pump(const Duration(milliseconds: 100));
    if (_has(cont)) {
      await _shot(t, '${name}_sonu');
      await _tapText(t, cont);
      break;
    }
    if (res != null) break;
    final status = find.textContaining(okt(lang, 'draw')).evaluate().isNotEmpty
        ? 'draw'
        : (find.textContaining(okt(lang, 'discard')).evaluate().isNotEmpty || find.textContaining(okt(lang, 'use')).evaluate().isNotEmpty
            ? 'play'
            : '');
    if (status.isEmpty) {
      idle++;
      continue;
    }
    idle = 0;
    moves++;
    if (shotEvery > 0 && moves % shotEvery == 0) await _shot(t, '${name}_h$moves');
    // İpucu (en usta oyuncunun hamlesi) arayüzden uygulanır.
    await t.tap(find.byIcon(Icons.lightbulb), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 200));
    final act = find.byKey(const ValueKey('ok-hint-act'));
    if (act.evaluate().isNotEmpty) {
      await t.tap(act.first, warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 150));
      continue;
    }
    final hinted = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('ok-hint-t'));
    final n = hinted.evaluate().length;
    if (n == 0) {
      // İpucu yoksa (olmamalı) desteden çek ya da son taşı at.
      if (status == 'draw') {
        await _tapText(t, kt(lang, 'drawStock'));
      } else {
        await t.tap(find.byType(Draggable<int>).last, warnIfMissed: false);
        await t.pump(const Duration(milliseconds: 100));
        await _tapText(t, okt(lang, 'discardBtn'));
      }
      continue;
    }
    for (var k = 0; k < n; k++) {
      await t.tap(hinted.at(k), warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 60));
    }
    for (final label in ['${okt(lang, 'lay')} (', okt(lang, 'add'), '${kt(lang, 'finish')} ✓', okt(lang, 'discardBtn')]) {
      final f = find.descendant(of: find.byType(StudioChoice), matching: find.textContaining(label));
      if (f.evaluate().isNotEmpty) {
        await t.tap(f.first, warnIfMissed: false);
        await t.pump(const Duration(milliseconds: 150));
        break;
      }
    }
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      await _shot(t, '${name}_uyari');
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextButton)).last);
      await t.pump(const Duration(milliseconds: 150));
    }
  }
  await t.pump(const Duration(milliseconds: 300));
  final out = '$name: hamle $moves ${res == null ? 'SONUÇ YOK' : 'won=${res!.won} score=${res!.score}'}';
  _log.add(out);
  expect(t.takeException(), isNull, reason: name);
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
  return out;
}

void main() {
  final skip = _out == null;
  setUpAll(() async {
    if (!skip) await _loadFonts();
  });
  tearDownAll(() {
    if (skip) return;
    File('$_out/log.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync(_log.join('\n'));
  });

  final games = <String, TableGameRules>{
    '101': TableGameRules(gameId: 'oyun-101-okey', rulesFor: (_) => const Okey101Rules(), aiScale: 0.1, quickValidate: true),
    'okey': TableGameRules(gameId: 'oyun-okey', rulesFor: (_) => const OkeyRules(), aiScale: 0.1, quickValidate: true),
    'esli': TableGameRules(gameId: 'oyun-okey-cesit-esli', rulesFor: (_) => const OkeyRules(partners: true), aiScale: 0.1, quickValidate: true),
    'katlamali': TableGameRules(gameId: 'oyun-okey-cesit-katlamali', rulesFor: (_) => const OkeyRules(doubling: true), aiScale: 0.1, quickValidate: true),
    'iki': TableGameRules(gameId: 'oyun-okey-cesit-iki', rulesFor: (_) => const OkeyRules(players: 2), aiScale: 0.1, quickValidate: true),
    'mahjong': TableGameRules(gameId: 'oyun-mahjong', rulesFor: (_) => const MahjongRules(), aiScale: 0.1, quickValidate: true),
    'domino': TableGameRules(gameId: 'oyun-domino', rulesFor: (d) => DominoRules(d <= 4 ? 2 : 4), quickValidate: true),
  };
  GeneratedLevel lv(String g, int n) {
    final r = games[g]!;
    return r.build(LevelPlanner(gameId: r.gameId, optionalMechanics: const []).spec(n));
  }

  testWidgets('101 Okey: oyuncu oynar (1, 2, 3, 5, 10) ve botlar', (t) async {
    _size(t, _phone);
    for (final n in [1, 2, 3, 5, 10]) {
      await _humanRun(t, '101_b${n}_tel', lv('101', n), 'tr', shotEvery: n == 1 ? 6 : 0);
    }
    await _aiRun(t, '101_bot_tel', lv('101', 7), 'tr', at: const [5, 12, 20]);
    _size(t, _tablet);
    await _humanRun(t, '101_b4_tablet', lv('101', 4), 'tr', shotEvery: 8);
    await _aiRun(t, '101_bot_tablet', lv('101', 11), 'tr', at: const [8, 18]);
    _size(t, const Size(800, 1180));
    await _aiRun(t, '101_bot_tabdikey', lv('101', 12), 'tr', at: const [10]);
    _size(t, _phone);
    await _aiRun(t, '101_bot_ar', lv('101', 13), 'ar', at: const [8]);
    await _aiRun(t, '101_bot_ja', lv('101', 14), 'ja', at: const [8]);
    t.view.reset();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 30)));

  testWidgets('Okey: oyuncu oynar (1, 2, 3, 5, 10) ve botlar', (t) async {
    _size(t, _phone);
    for (final n in [1, 2, 3, 5, 10]) {
      await _humanRun(t, 'okey_b${n}_tel', lv('okey', n), 'tr', shotEvery: n == 1 ? 5 : 0);
    }
    await _aiRun(t, 'okey_bot_tel', lv('okey', 8), 'tr', at: const [6]);
    _size(t, _tablet);
    await _aiRun(t, 'okey_bot_tablet', lv('okey', 9), 'tr', at: const [6]);
    t.view.reset();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 30)));

  testWidgets('Okey çeşitleri ve diğer taş oyunları', (t) async {
    _size(t, _phone);
    for (final g in ['esli', 'katlamali', 'iki']) {
      await _humanRun(t, '${g}_b1_tel', lv(g, 1), 'tr');
      await _aiRun(t, '${g}_bot_tel', lv(g, 6), 'tr', at: const [6]);
    }
    for (final g in ['mahjong', 'domino']) {
      for (final n in [1, 5]) {
        await t.pumpWidget(_host(TableView(ctx: _ctx(lv(g, n), 'tr')), 'tr'));
        await t.pump(const Duration(milliseconds: 600));
        await _shot(t, '${g}_b${n}_tel');
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 2));
      }
      await _aiRun(t, '${g}_bot_tel', lv(g, 3), 'tr', at: const [5, 15]);
    }
    t.view.reset();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 30)));
}
