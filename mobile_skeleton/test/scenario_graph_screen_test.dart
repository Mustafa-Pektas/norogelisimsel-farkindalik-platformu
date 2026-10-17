import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/models/scenario_graph.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_screen.dart';
import 'package:neuro_awareness_app/screens/synthetic_video_studio_screen.dart';

class _ScenarioBundle extends CachingAssetBundle {
  _ScenarioBundle(this.read);
  final Future<String> Function() read;

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    if (key != ScenarioGraphScreen.d01AssetPath) {
      return Future.error(FlutterError('Beklenmeyen asset yolu: $key'));
    }
    return read();
  }

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

Widget _app(
  AssetBundle bundle, {
  Widget home = const ScenarioGraphScreen(),
  double textScale = 1,
}) => DefaultAssetBundle(
  bundle: bundle,
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  ),
);

void _expectOverview(WidgetTester tester, ScenarioGraph graph) {
  final viewport = tester.getRect(find.byType(InteractiveViewer));
  final boxes = [
    for (final scene in graph.scenes)
      tester.getRect(find.byKey(ValueKey('scene:${scene.id}'))),
    for (var i = 0; i < graph.transitions.length; i++)
      tester.getRect(find.byKey(ValueKey('transition:$i'))),
  ];
  for (var i = 0; i < boxes.length; i++) {
    expect(
      viewport.inflate(1).contains(boxes[i].topLeft),
      isTrue,
      reason: '$i üst sınır',
    );
    expect(
      viewport.inflate(1).contains(boxes[i].bottomRight),
      isTrue,
      reason: '$i alt sınır',
    );
    for (var j = i + 1; j < boxes.length; j++) {
      expect(
        boxes[i].overlaps(boxes[j]),
        isFalse,
        reason: '$i ve $j çakışmamalı',
      );
    }
  }
}

void main() {
  // Aynı asset okunur; ikinci bir senaryo fixture kopyası tutulmaz.
  final fixture = File(ScenarioGraphScreen.d01AssetPath).readAsStringSync();
  final graph = ScenarioGraph.fromJsonString(fixture);

  testWidgets(
    'İlk açılışta beş sahne ve çakışmayan dört bağlantıyla iki çağrı alternatifi görünür',
    (tester) async {
      expect(File('examples/d01_scenario_graph.json').existsSync(), isFalse);
      expect(
        File('pubspec.yaml').readAsLinesSync().map((line) => line.trim()),
        contains('- ${ScenarioGraphScreen.d01AssetPath}'),
      );
      final loading = Completer<String>();
      await tester.pumpWidget(_app(_ScenarioBundle(() => loading.future)));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      loading.complete(fixture);
      await tester.pumpAndSettle();
      expect(graph.scenes, hasLength(5));
      expect(graph.transitions, hasLength(4));
      expect(find.textContaining('Elle hazırlanmış örnek'), findsOneWidget);
      expect(
        find.textContaining('Planlanan senaryo; gözlem değildir'),
        findsOneWidget,
      );
      for (final scene in graph.scenes) {
        expect(find.byKey(ValueKey('scene:${scene.id}')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(ValueKey('scene:${scene.id}')),
            matching: find.text(scene.title!),
          ),
          findsOneWidget,
        );
        expect(find.text(scene.description), findsNothing);
        final summary = tester.widget<Text>(
          find.byKey(ValueKey('summary:${scene.id}')),
        );
        expect(summary.data, scene.summary);
        expect(summary.maxLines, 2);
        expect(summary.overflow, TextOverflow.ellipsis);
      }
      for (var i = 0; i < graph.transitions.length; i++) {
        expect(find.byKey(ValueKey('transition:$i')), findsOneWidget);
        expect(find.text(graph.transitions[i].description), findsNothing);
      }
      expect(find.text('Başlangıç'), findsOneWidget);
      expect(find.text('Bitiş'), findsNWidgets(2));
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.outlined_flag), findsNWidgets(2));
      _expectOverview(tester, graph);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scene in graph.scenes) {
    testWidgets('${scene.id}: dokunma tam açıklama ve devamları açar', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_ScenarioBundle(() async => fixture)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('scene:${scene.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scene-details')), findsOneWidget);
      final description = tester.widget<Text>(
        find.byKey(const ValueKey('scene-full-description')),
      );
      expect(description.data, scene.description);
      expect(description.maxLines, isNull);
      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('scene-details-scroll')),
        matching: find.byType(Scrollable),
      );
      for (var i = 0; i < graph.transitions.length; i++) {
        final edge = graph.transitions[i];
        if (edge.fromSceneId != scene.id) continue;
        final link = find.byKey(ValueKey('detail-transition:$i'));
        await tester.scrollUntilVisible(link, 100, scrollable: scrollable);
        expect(
          find.descendant(of: link, matching: find.text(edge.description)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: link,
            matching: find.text(
              graph.scenes.firstWhere((s) => s.id == edge.toSceneId).title!,
            ),
          ),
          findsOneWidget,
        );
      }
      if (graph.endSceneIds.contains(scene.id)) {
        await tester.scrollUntilVisible(
          find.text('Bu bir bitiş sahnesidir. Devam bağlantısı yok.'),
          100,
          scrollable: scrollable,
        );
      }
      await tester.tap(find.byTooltip('Ayrıntıları kapat'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scene-details')), findsNothing);
      _expectOverview(tester, graph);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Dar ekranda iki kat yazıyla ayrıntılar son bağlantıya kadar kaydırılır',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(_ScenarioBundle(() async => fixture), textScale: 2),
      );
      await tester.pumpAndSettle();
      _expectOverview(tester, graph);
      await tester.tap(find.byKey(const ValueKey('scene:oyuncakla_oyun')));
      await tester.pumpAndSettle();
      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('scene-details-scroll')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('detail-transition:1')),
        120,
        scrollable: scrollable,
      );
      final state = tester.state<ScrollableState>(scrollable);
      expect(state.position.pixels, greaterThan(0));
      await tester.drag(scrollable, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(find.text(graph.transitions[1].description), findsOneWidget);
      await tester.tap(find.byTooltip('Ayrıntıları kapat'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Kısa alanları olmayan eski JSON da açılır ve tam açıklamayı korur',
    (tester) async {
      final old = jsonDecode(fixture) as Map<String, dynamic>;
      for (final scene in old['scenes'] as List) {
        scene.remove('title');
        scene.remove('summary');
      }
      for (final edge in old['transitions'] as List) {
        edge.remove('label');
      }
      await tester.pumpWidget(
        _app(_ScenarioBundle(() async => jsonEncode(old))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sahne 1'), findsOneWidget);
      for (final scene in graph.scenes) {
        expect(
          tester
              .widget<Text>(find.byKey(ValueKey('summary:${scene.id}')))
              .maxLines,
          2,
        );
      }
      await tester.tap(find.byKey(const ValueKey('scene:oyuncakla_oyun')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('scene-full-description')))
            .data,
        graph.scenes.first.description,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Geçersiz graf bağlantısı uygulamayı çökertmeden açıklanır', (
    tester,
  ) async {
    final invalid = jsonDecode(fixture) as Map<String, dynamic>;
    invalid['transitions'][0]['toSceneId'] = 'olmayan_sahne';
    await tester.pumpWidget(
      _app(_ScenarioBundle(() async => jsonEncode(invalid))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Senaryo grafı açılamadı.'), findsOneWidget);
    expect(find.textContaining('Örnek senaryo doğrulanamadı:'), findsOneWidget);
    expect(find.textContaining('olmayan_sahne'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Asset okuma hatası gösterilir ve yeniden deneme çalışır', (
    tester,
  ) async {
    var attempts = 0;
    final bundle = _ScenarioBundle(() async {
      if (attempts++ == 0) throw StateError('Test için asset okunamadı');
      return fixture;
    });
    await tester.pumpWidget(_app(bundle));
    await tester.pumpAndSettle();
    expect(find.textContaining('Örnek dosyası okunamadı.'), findsOneWidget);
    await tester.tap(find.text('Tekrar dene'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byKey(const ValueKey('scene:yetiskine_yonelme')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dar ekranda büyük metin, kaydırma, yakınlaştırma ve sığdırma', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(_ScenarioBundle(() async => fixture), textScale: 2),
    );
    await tester.pumpAndSettle();
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final controller = viewer.transformationController!;
    final fitScale = controller.value.getMaxScaleOnAxis();
    _expectOverview(tester, graph);
    await tester.tap(find.byTooltip('Yakınlaştır'));
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(fitScale));
    final beforePan = controller.value.clone();
    await tester.drag(find.byType(InteractiveViewer), const Offset(30, 30));
    await tester.pumpAndSettle();
    expect(controller.value, isNot(equals(beforePan)));
    await tester.tap(find.byTooltip('Uzaklaştır'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('show-all')));
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(fitScale, 1e-6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stüdyodaki Senaryo Grafı girişi örnek ekranı açar', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _ScenarioBundle(() async => fixture),
        home: const SyntheticVideoStudioScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-scenario-graph')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Elle hazırlanmış örnek'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
