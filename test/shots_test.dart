// Oyun testi ekran görüntüleri: oyunun masası oyuncu gözüyle (açılış, ihale,
// el ortası, el sonu tablosu) telefon ve tablette; bütün el motorun botuyla
// oynanır. Yalnız "shots" işinde çalışır: flutter test --tags shots --run-skipped
@Tags(['shots'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/studio_look.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';

Future<void> _fonts() async {
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
  await load('Noto Sans CJK JP', [File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')]);
}

final _shotKey = GlobalKey();
RoundResult? _finished;

PlayContext _ctx(GeneratedLevel gl, String lang) => PlayContext(
      spec: gl.spec,
      generated: gl,
      resume: const {},
      pieceColors: const [Color(0xFF3075C4), Color(0xFF2BB3B1)],
      background: const [Color(0xFF1A2E5C), Color(0xFF3A6FC4)],
      colorBlind: false,
      reducedMotion: false,
      leftHanded: false,
      lang: lang,
      t: (k, [p = const {}]) => k,
      finish: (r) => _finished = r,
      saveResume: (_) {},
      requestHint: () async => true,
      requestBooster: () async => true,
      requestContinue: () async => false,
      sfx: (_) {},
    );

Widget _host(Widget child, String lang) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        fontFamily: lang == 'ar' ? 'Noto Naskh Arabic' : (lang == 'ja' ? 'Noto Sans CJK JP' : 'Roboto'),
        extensions: [StudioLook.fromSeed(const Color(0xFFB5563A))],
      ),
      home: RepaintBoundary(
        key: _shotKey,
        child: Scaffold(
          backgroundColor: const Color(0xFF1A2348),
          body: SafeArea(
            child: Directionality(
              textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
              child: child,
            ),
          ),
        ),
      ),
    );

Future<void> _shot(WidgetTester t, String name) async {
  await t.pump(const Duration(milliseconds: 50));
  await t.runAsync(() async {
    final b = _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/shots').createSync(recursive: true);
    File('build/shots/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// Oyunu [ms] boyunca ilerlet (botlar ve animasyonlar).
Future<void> _run(WidgetTester t, int ms) async {
  for (var e = 0; e < ms; e += 100) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

class _Case {
  final String id;
  final GameRules rules;
  final Widget Function(PlayContext) view;
  _Case(this.id, this.rules, this.view);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _fonts();
  });

  final cases = [
    _Case('oyun-batak', TrickGameRules(gameId: 'oyun-batak', rulesFor: (_) => const BatakRules()), (c) => TrickView(ctx: c)),
    _Case('oyun-batak-cesit-esli', TrickGameRules(gameId: 'oyun-batak-cesit-esli', rulesFor: (_) => const BatakRules(pairs: true)),
        (c) => TrickView(ctx: c)),
    _Case('oyun-king', TrickGameRules(gameId: 'oyun-king', rulesFor: (_) => const KingRules()), (c) => TrickView(ctx: c)),
    _Case('oyun-hearts', TrickGameRules(gameId: 'oyun-hearts', rulesFor: (_) => const HeartsRules()), (c) => TrickView(ctx: c)),
    _Case('oyun-spades', TrickGameRules(gameId: 'oyun-spades', rulesFor: (_) => const SpadesRules()), (c) => TrickView(ctx: c)),
    _Case('oyun-kontrat-bric', TrickGameRules(gameId: 'oyun-kontrat-bric', rulesFor: (_) => const ContractBridgeRules()),
        (c) => TrickView(ctx: c)),
    _Case('oyun-skat', TrickGameRules(gameId: 'oyun-skat', rulesFor: (_) => const SkatRules()), (c) => TrickView(ctx: c)),
    _Case('oyun-belot', TrickGameRules(gameId: 'oyun-belot', rulesFor: (_) => const BeloteRules()), (c) => TrickView(ctx: c)),
    _Case('oyun-pisti', TableGameRules(gameId: 'oyun-pisti', rulesFor: (_) => const PistiRules()), (c) => TableView(ctx: c)),
    _Case('oyun-konken',
        TableGameRules(gameId: 'oyun-konken', rulesFor: (_) => const RummyRules(players: 3, handSize: 13, decks: 2, openMin: 51)),
        (c) => TableView(ctx: c)),
    _Case('oyun-durak', TableGameRules(gameId: 'oyun-durak', rulesFor: (_) => const DurakRules()), (c) => TableView(ctx: c)),
    _Case('oyun-klondike-solitaire', SolitaireRules(gameId: 'oyun-klondike-solitaire', variantFor: (d) => klondike(d)),
        (c) => SolitaireView(ctx: c)),
  ];
  final only = Platform.environment['SHOTS_ONLY'] ?? '';
  final levels = (Platform.environment['SHOTS_LEVELS'] ?? '1,3,10').split(',').map(int.parse).toList();
  const sizes = {'tel': Size(393, 852), 'tab': Size(1280, 800)};

  for (final c in cases) {
    if (only.isNotEmpty && !only.split(',').contains(c.id)) continue;
    for (final lv in levels) {
      for (final sz in sizes.entries) {
        if (sz.key == 'tab' && lv != levels.first) continue;
        for (final lang in lv == levels.first && sz.key == 'tel' ? const ['tr', 'ar', 'ja'] : const ['tr']) {
          testWidgets('${c.id} L$lv ${sz.key} $lang', (t) async {
            t.view.physicalSize = sz.value;
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.reset);
            KartTableTheme.debugGameId = c.id;
            KartAutoPilot.on.value = false;
            _finished = null;
            final planner = LevelPlanner(gameId: c.rules.gameId, optionalMechanics: const []);
            final gl = c.rules.build(planner.spec(lv));
            final name = '${c.id}_L${lv}_${sz.key}_$lang';
            await t.pumpWidget(_host(c.view(_ctx(gl, lang)), lang));
            await _run(t, 2500);
            await _shot(t, '${name}_1acilis');
            if (lang != 'tr') {
              await t.pumpWidget(const SizedBox());
              await _run(t, 1000);
              return;
            }
            // Oyuncu gibi: bütün eli bot oynar.
            KartAutoPilot.on.value = true;
            await _run(t, 9000);
            await _shot(t, '${name}_2orta');
            for (var i = 0; i < 60 && _finished == null; i++) {
              await _run(t, 2000);
              final more = find.text('Devam');
              if (more.evaluate().isNotEmpty) {
                await _shot(t, '${name}_3son');
                await t.tap(more.first);
                await _run(t, 300);
                break;
              }
            }
            if (_finished == null) await _shot(t, '${name}_3son');
            // ignore: avoid_print
            print('SONUC|$name|${_finished?.won}|${_finished?.score}|${_finished?.headline}');
            KartAutoPilot.on.value = false;
            await t.pumpWidget(const SizedBox());
            await _run(t, 1000);
          }, timeout: const Timeout(Duration(minutes: 6)));
        }
      }
    }
  }
}
