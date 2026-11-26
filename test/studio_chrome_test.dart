import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kart_motoru/kart_motoru.dart';
import 'package:kart_motoru/src/studio_chrome.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';

PlayContext _ctx(GeneratedLevel gl, String lang) => PlayContext(
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
      finish: (_) {},
      saveResume: (_) {},
      requestHint: () async => true,
      requestBooster: () async => true,
      requestContinue: () async => false,
      sfx: (_) {},
    );

/// Oyun ekranının sarmalayıcısı: oyun alanı eski (açık) temayla, palet tema
/// uzantısıyla gelir (studio-core play.dart gibi).
Widget _host(Widget child, {StudioLook look = const StudioLook()}) => MaterialApp(
      theme: ThemeData(brightness: Brightness.light, extensions: [look]),
      home: Scaffold(body: SafeArea(child: child)),
    );

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Görünümdeki bütün yazılar: koyu stüdyo zemininde okunur olmalı (siyah
/// yazı yalnız kendi açık zeminini çizen hap/rozetlerde olur).
void _expectLightText(WidgetTester t) {
  final ok = {StudioChoice, StudioSeatBadge, StudioButton};
  for (final e in find.byType(RichText).evaluate()) {
    final r = e.renderObject as RenderParagraph;
    final c = r.text.style?.color;
    if (c == null) continue;
    var inside = false;
    e.visitAncestorElements((a) {
      if (ok.contains(a.widget.runtimeType)) {
        inside = true;
        return false;
      }
      return true;
    });
    if (inside) continue;
    expect(c.computeLuminance(), greaterThan(0.35), reason: 'koyu zeminde okunmayan yazı: "${r.text.toPlainText()}"');
  }
}

Future<void> _tapAround(WidgetTester t) async {
  final size = t.view.physicalSize / t.view.devicePixelRatio;
  for (var y = 80.0; y < size.height - 10; y += size.height / 7) {
    for (var x = 30.0; x < size.width; x += size.width / 4) {
      await t.tapAt(Offset(x, y));
      await t.pump(const Duration(milliseconds: 150));
    }
  }
}

void main() {
  testWidgets('StudioChrome: koyu stüdyo teması, diyalog paleti', (t) async {
    const look = StudioLook();
    late BuildContext inner;
    await t.pumpWidget(_host(StudioChrome(child: Builder(builder: (c) {
      inner = c;
      return const SizedBox();
    }))));
    expect(Theme.of(inner).brightness, Brightness.dark);
    expect(Theme.of(inner).dialogTheme.backgroundColor, look.sheet);
    showDialog<void>(context: inner, builder: (c) => const AlertDialog(title: Text('x')));
    await t.pumpAndSettle();
    final dialog = t.widget<Material>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(Material)).first);
    expect(dialog.color, look.sheet);
  });

  testWidgets('seçim düğmesi, koltuk etiketi, örtü: koyu paletlerde okunur', (t) async {
    for (final look in [const StudioLook(), StudioLook.fromSeed(const Color(0xFFB5563A)), StudioLook.fromSeed(const Color(0xFF2E8B57))]) {
      await t.pumpWidget(_host(
        look: look,
        StudioChrome(
          child: Column(children: [
            const StudioSeatBadge(title: 'Sol', detail: 'El: 3'),
            const StudioSeatBadge(title: 'Sen', detail: 'El: 1', active: true),
            StudioChoice(label: '7', onPressed: () {}),
            StudioChoice(label: '8', hinted: true, onPressed: () {}),
            StudioChoice(label: '9', selected: true, onPressed: () {}),
            StudioCover(text: 'Ver', sub: 'Dokun', onTap: () {}),
            const StudioTag(text: 'Koz ♥', icon: Icons.timer_outlined),
            StudioRoundAction(icon: Icons.lightbulb, tooltip: 'hint', onPressed: () {}),
          ]),
        ),
      ));
      expect(t.takeException(), isNull);
      // Seçili hap ve etkin koltukta yazı, vurgu rengine göre seçilir.
      expect(_contrast(look.onAccent, look.accent), greaterThan(4.5));
      expect(_contrast(kStudioText, look.sheet), greaterThan(7));
      expect(_contrast(kStudioTextDim, look.base), greaterThan(7));
      expect(_contrast(const Color(0xFF2A1E05), const Color(0xFFFFC14A)), greaterThan(7));
    }
  });

  final cases = <String, (GameRules, Widget Function(PlayContext))>{
    'batak': (TrickGameRules(gameId: 't-batak', rulesFor: (_) => const BatakRules()), (c) => TrickView(ctx: c)),
    'king': (TrickGameRules(gameId: 't-king', rulesFor: (_) => const KingRules()), (c) => TrickView(ctx: c)),
    'okey': (
      TableGameRules(gameId: 't-okey', rulesFor: (_) => const OkeyRules(), aiScale: 0.1, quickValidate: true),
      (c) => TableView(ctx: c)
    ),
    '31': (TableGameRules(gameId: 't-31', rulesFor: (_) => const ThirtyOneRules()), (c) => TableView(ctx: c)),
    'klondike': (SolitaireRules(gameId: 't-sol', variantFor: (d) => klondike(d)), (c) => SolitaireView(ctx: c)),
    'hafiza': (MemoryRules(gameId: 't-mem'), (c) => MemoryView(ctx: c)),
    'yol': (TrailRules(gameId: 't-trail'), (c) => TrailView(ctx: c)),
    'kare': (SquareRules(gameId: 't-sq'), (c) => SquareView(ctx: c)),
    'hiz': (RealtimeRules(gameId: 't-hiz', kind: RtKind.speed), (c) => RealtimeView(ctx: c)),
    'esini-yakala': (RealtimeRules(gameId: 't-snap', kind: RtKind.snap), (c) => RealtimeView(ctx: c)),
  };

  for (final e in cases.entries) {
    for (final lang in const ['tr', 'ar']) {
      testWidgets('${e.key} ($lang): masa onaylı tasarımla açılır, yazılar okunur', (t) async {
        t.view.physicalSize = const Size(1080, 2280);
        t.view.devicePixelRatio = 2.75;
        addTearDown(t.view.reset);
        final (rules, view) = e.value;
        final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
        final gl = rules.build(planner.spec(4));
        await t.pumpWidget(_host(Directionality(
          textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          child: view(_ctx(gl, lang)),
        )));
        await t.pump(const Duration(milliseconds: 400));
        expect(t.takeException(), isNull);
        final chrome = t.element(find.byType(StudioChrome).first);
        final inner = t.element(find.descendant(of: find.byWidget(chrome.widget), matching: find.byType(LayoutBuilder)).first);
        expect(Theme.of(inner).brightness, Brightness.dark);
        _expectLightText(t);
        await _tapAround(t);
        await t.pump(const Duration(seconds: 2));
        expect(t.takeException(), isNull);
        _expectLightText(t);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 5));
      });
    }
  }

  testWidgets('maç: mod paneli, sözleşme/puan tablosu diyaloğu stüdyo görünümünde', (t) async {
    t.view.physicalSize = const Size(1080, 2280);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
    final rules = TrickGameRules(gameId: 't-batak-mac', rulesFor: (_) => const BatakRules());
    final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
    final gl = rules.build(planner.spec(1, mode: GameModeId.endless));
    final c = _ctx(gl, 'tr');
    expect(MatchView.wants(c), isTrue);
    await t.pumpWidget(_host(TrickView(ctx: c)));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(StudioBoardPanel), findsWidgets);
    _expectLightText(t);
    // Mod seçimi sorulursa maçı seç.
    if (find.byIcon(Icons.table_rows_rounded).evaluate().isEmpty) {
      await t.tap(find.byType(StudioButton).first);
      await t.pump(const Duration(milliseconds: 600));
    }
    expect(t.takeException(), isNull);
    // Puan tablosu diyaloğu.
    await t.tap(find.byIcon(Icons.table_rows_rounded));
    await t.pump(const Duration(milliseconds: 600));
    final dlg = find.byType(AlertDialog);
    expect(dlg, findsOneWidget);
    final look = StudioLook.of(t.element(dlg));
    expect(Theme.of(t.element(dlg)).dialogTheme.backgroundColor, look.sheet);
    _expectLightText(t);
    await t.tap(find.descendant(of: dlg, matching: find.byType(StudioButton)));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(AlertDialog), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('maç: mod seçim paneli (iki kişilik) stüdyo düğmeleriyle açılır', (t) async {
    t.view.physicalSize = const Size(1080, 2280);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
    final rules = TrickGameRules(gameId: 't-king-mac', rulesFor: (_) => const KingRules());
    final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
    final gl = rules.build(planner.spec(1, mode: GameModeId.versus));
    final c = _ctx(gl, 'tr');
    await t.pumpWidget(_host(TrickView(ctx: c)));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
    _expectLightText(t);
    final buttons = find.byType(StudioButton);
    if (buttons.evaluate().isNotEmpty) {
      await t.tap(buttons.first);
      await t.pump(const Duration(milliseconds: 600));
      expect(t.takeException(), isNull);
      _expectLightText(t);
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });
}
