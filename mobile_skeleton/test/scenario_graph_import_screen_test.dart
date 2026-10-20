import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_awareness_app/models/behavior_cards.dart';
import 'package:neuro_awareness_app/models/scenario_graph.dart';
import 'package:neuro_awareness_app/screens/clip_production_plan_screen.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_import_screen.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_screen.dart';
import 'package:neuro_awareness_app/services/clip_video_store.dart';

class _ImportBundle extends CachingAssetBundle {
  _ImportBundle(this.sources, {this.read});
  final Map<String, String> sources;
  final Future<String> Function(String key)? read;
  final reads = <String>[];

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    reads.add(key);
    if (read != null) return read!(key);
    if (!sources.containsKey(key)) throw StateError('Beklenmeyen asset okuması.');
    return sources[key]!;
  }

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

class _NoVideos extends ClipVideoStore {
  _NoVideos() : super(documentsDirectory: () async {
    throw StateError('İçe aktarma testi gerçek belge dizinine erişmemeli.');
  });
  int reads = 0;
  @override
  Future<Map<String, ClipVideoBinding>> loadPlan(String planId) async {
    reads++;
    return {};
  }
}

Widget _app(_ImportBundle bundle, {Widget home = const ScenarioGraphImportScreen()}) =>
    DefaultAssetBundle(bundle: bundle, child: MaterialApp(home: home));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  // Salt okunur asset fixture'ları test başlamadan belleğe alınır; async IO yok.
  final originalText = File(ScenarioGraphScreen.d01AssetPath).readAsStringSync();
  final original = ScenarioGraph.fromJsonString(originalText);
  final planText = File(ClipProductionPlanScreen.d01PlanAssetPath).readAsStringSync();
  final scenarioText = File(ScenarioGraphImportScreen.d01InputAssetPath).readAsStringSync();
  final scenarioJson = jsonDecode(scenarioText) as Map<String, dynamic>;
  final oldExampleExists = File('examples/d01_scenario_input.json').existsSync();
  final assetDefinitions = File('pubspec.yaml').readAsLinesSync();
  final importedJson = {
    ...original.toJson(),
    'scenarioId': 'ice-aktarilan-test-001',
    'title': 'Kullanıcı taslağı',
    'scenes': [
      for (final scene in original.scenes)
        {...scene.toJson(), if (scene.id == original.startSceneId) 'title': 'Kullanıcı başlangıcı'},
    ],
  };
  final validText = jsonEncode(importedJson);
  final expected = ScenarioGraph.fromJsonString(validText);

  Future<void> enter(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), text);
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final title = switch (key) {
      'scenario-import-format-details' => 'Biçim ve kaynak ayrıntıları',
      'scenario-import-request-form' => 'Senaryo üretim isteği',
      _ => null,
    };
    final target = title != null
        ? find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(title))
        : find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  for (final scenario in [false, true]) {
    testWidgets('320 piksel ve büyük yazı: ${scenario ? 'senaryo' : 'graf'} ana eylemleri erişilir', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final bundle = _ImportBundle({});
      await tester.pumpWidget(DefaultAssetBundle(
        bundle: bundle,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: ScenarioGraphImportScreen(initialScenarioContent: scenario),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Teknik geliştirici arayüzü:'), findsNothing);
      expect(find.textContaining('D01 demo metadata’sını uygulama sağlar:'), findsNothing);
      expect(tester.widget<ExpansionTile>(
        find.byKey(const ValueKey('scenario-import-format-details')),
      ).initiallyExpanded, isFalse);
      final editor = find.byKey(const ValueKey('scenario-import-json'));
      await tester.ensureVisible(editor);
      expect(editor.hitTestable(), findsOneWidget);
      final text = scenario ? scenarioText : validText;
      await enter(tester, text);
      await tap(tester, 'scenario-import-validate');
      expect(find.byKey(const ValueKey('scenario-import-summary')), findsOneWidget);
      final field = tester.widget<TextField>(editor).controller!;
      await tap(tester, 'scenario-import-format-details');
      expect(find.textContaining('Teknik geliştirici arayüzü:'), findsOneWidget);
      if (scenario) {
        expect(find.textContaining('Kaynak (girdi beyanı):'), findsOneWidget);
      }
      await tap(tester, 'scenario-import-format-details');
      expect(field.text, text);
      expect(find.byKey(const ValueKey('scenario-import-summary')), findsOneWidget);
      if (scenario) {
        await tap(tester, 'scenario-import-request-form');
        await tap(tester, 'scenario-request-behavior');
        final item = find.text(BehaviorCards.all.first.title).last;
        await tester.scrollUntilVisible(item, 100, scrollable: find.byType(Scrollable).last);
        await tester.tap(item);
        await tester.pumpAndSettle();
        for (final entry in [('age', '12'), ('context', 'Evde oyuncaklarla.'),
          ('instructions', 'Gün ışığında.')]) {
          final input = find.byKey(ValueKey('scenario-request-${entry.$1}'));
          await tester.ensureVisible(input);
          expect(input.hitTestable(), findsOneWidget);
          await tester.enterText(input, entry.$2);
          await tester.pumpAndSettle();
        }
        final validate = find.byKey(const ValueKey('scenario-request-validate'));
        await tester.ensureVisible(validate);
        expect(validate.hitTestable(), findsOneWidget);
        await tap(tester, 'scenario-request-validate');
        expect(find.byKey(const ValueKey('scenario-request-summary')), findsOneWidget);
        expect(find.text('Karakter yaşı: 12 ay'), findsOneWidget);
        expect(field.text, text);
        expect(find.byKey(const ValueKey('scenario-import-summary')), findsOneWidget);
        await tap(tester, 'scenario-import-request-form');
      } else {
        expect(find.byKey(const ValueKey('scenario-import-request-form')), findsNothing);
      }
      final view = find.byKey(const ValueKey('scenario-import-view'));
      await tester.ensureVisible(view);
      expect(view.hitTestable(), findsOneWidget);
      expect(tester.widget<OutlinedButton>(view).onPressed, isNotNull);
      await tap(tester, 'scenario-import-view');
      final viewer = tester.widget<ScenarioGraphScreen>(find.byType(ScenarioGraphScreen));
      final graph = viewer.graph!;
      expect(graph.scenarioId, scenario ? scenarioJson['scenarioId'] : expected.scenarioId);
      final graphArea = find.byType(InteractiveViewer);
      expect(tester.getSize(graphArea).height, greaterThan(0));
      final transform = tester.widget<InteractiveViewer>(graphArea).transformationController!;
      final fitted = transform.value.clone();
      final source = find.byKey(const ValueKey('scenario-graph-source-scroll'));
      expect(find.descendant(of: source, matching: find.text(
        viewer.sourceLabel ?? ScenarioGraphScreen.importedSourceLabel,
      )), findsOneWidget);
      if (scenario) {
        final scrollable = find.descendant(of: source, matching: find.byType(Scrollable));
        final position = tester.state<ScrollableState>(scrollable).position;
        expect(position.maxScrollExtent, greaterThan(0));
        await tester.drag(source, Offset(0, -position.maxScrollExtent - 100));
        await tester.pumpAndSettle();
        expect(position.pixels, closeTo(position.maxScrollExtent, 1));
        expect(transform.value, fitted);
      }
      final zoomIn = find.byTooltip('Yakınlaştır');
      final zoomOut = find.byTooltip('Uzaklaştır');
      final showAll = find.byKey(const ValueKey('show-all'));
      for (final control in [zoomIn, zoomOut, showAll]) {
        expect(control.hitTestable(), findsOneWidget);
      }
      await tester.tap(zoomIn);
      await tester.pumpAndSettle();
      expect(transform.value.getMaxScaleOnAxis(), greaterThan(fitted.getMaxScaleOnAxis()));
      final zoomed = transform.value.clone();
      await tester.drag(graphArea, const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(transform.value, isNot(equals(zoomed)));
      await tester.tap(zoomOut);
      await tester.pumpAndSettle();
      await tester.tap(showAll);
      await tester.pumpAndSettle();
      expect(transform.value, fitted);
      final firstScene = graph.scenes.firstWhere((scene) => scene.id == graph.startSceneId);
      await tester.tap(find.byKey(ValueKey('scene:${firstScene.id}')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('scene-full-description'))).data,
          firstScene.description);
      await tester.tap(find.byTooltip('Ayrıntıları kapat'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scene-details')), findsNothing);
      expect(bundle.reads, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('Geçerli JSON özetlenir; doğrulanmış nesne asset okumadan doğru kaynakla açılır', (tester) async {
    final bundle = _ImportBundle({});
    await tester.pumpWidget(_app(bundle));
    await enter(tester, validText);
    await tap(tester, 'scenario-import-validate');
    expect(find.text('Senaryo kimliği: ${expected.scenarioId}'), findsOneWidget);
    expect(find.text('Davranış: ${expected.behaviorId} · Kart sürümü: ${expected.cardVersion}'), findsOneWidget);
    expect(find.text('Sahne: ${expected.scenes.length} · Bağlantı: ${expected.transitions.length}'), findsOneWidget);
    expect(find.text('Graf yapısı geçerli; içerik doğrulanmadı.'), findsOneWidget);
    await tap(tester, 'scenario-import-view');
    final viewer = tester.widget<ScenarioGraphScreen>(find.byType(ScenarioGraphScreen));
    expect(viewer.graph!.toJson(), expected.toJson());
    expect(find.text(ScenarioGraphScreen.importedSourceLabel), findsOneWidget);
    expect(find.text('Elle hazırlanmış örnek'), findsNothing);
    for (final scene in expected.scenes) {
      expect(find.byKey(ValueKey('scene:${scene.id}')), findsOneWidget);
    }
    expect(bundle.reads, isEmpty);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('scenario-import-json'))).controller!.text,
        validText);
    expect(tester.takeException(), isNull);
  });

  for (final invalid in [
    (name: 'Boş metin', text: '', message: 'Lütfen doğrulamak için'),
    (name: 'Bozuk JSON', text: '{', message: 'JSON okunamadı'),
    (name: 'Geçersiz sahne referansı',
      text: jsonEncode({...importedJson, 'startSceneId': 'olmayan_sahne'}),
      message: 'mevcut bir sahneye bağlanmıyor'),
    (name: 'Tekrarlı sahne kimliği',
      text: jsonEncode({...importedJson,
        'scenes': [...expected.scenes.map((scene) => scene.toJson()), expected.scenes.first.toJson()]}),
      message: 'Tekrarlı sahne kimliği'),
    (name: 'Bitiş sahnesi yok',
      text: jsonEncode({...importedJson, 'endSceneIds': <String>[]}),
      message: 'En az bir bitiş sahnesi'),
  ]) {
    testWidgets('${invalid.name}: hata anlaşılır, görüntüleme kapalı ve örnek okunmaz', (tester) async {
      final bundle = _ImportBundle({});
      await tester.pumpWidget(_app(bundle));
      await enter(tester, invalid.text);
      await tap(tester, 'scenario-import-validate');
      final error = tester.widget<Text>(find.byKey(const ValueKey('scenario-import-error')));
      expect(error.data, contains(invalid.message));
      expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
      expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('scenario-import-view'))).onPressed,
          isNull);
      expect(bundle.reads, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Düzenleme eski doğrulamayı temizler; yeniden doğrulama yapılmadan graf açılamaz', (tester) async {
    final bundle = _ImportBundle({});
    await tester.pumpWidget(_app(bundle));
    await enter(tester, validText);
    await tap(tester, 'scenario-import-validate');
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsOneWidget);
    await enter(tester, '{');
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('scenario-import-view'))).onPressed,
        isNull);
    await tap(tester, 'scenario-import-validate');
    expect(find.byKey(const ValueKey('scenario-import-error')), findsOneWidget);
    await enter(tester, validText);
    expect(find.byKey(const ValueKey('scenario-import-error')), findsNothing);
    await tap(tester, 'scenario-import-validate');
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsOneWidget);
    expect(bundle.reads, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dışarıdan graf güncellenir; nesne kaldırıldığında mevcut D01 asset yolu çalışır', (tester) async {
    final bundle = _ImportBundle({ScenarioGraphScreen.d01AssetPath: originalText});
    await tester.pumpWidget(_app(bundle, home: ScenarioGraphScreen(graph: expected)));
    await tester.pumpAndSettle();
    expect(find.text('Kullanıcı başlangıcı'), findsOneWidget);
    expect(bundle.reads, isEmpty);
    final changed = ScenarioGraph.fromJson({...expected.toJson(),
      'scenes': [for (final scene in expected.scenes)
        {...scene.toJson(), if (scene.id == expected.startSceneId) 'title': 'Yeni başlangıç'}]});
    await tester.pumpWidget(_app(bundle, home: ScenarioGraphScreen(graph: changed)));
    await tester.pumpAndSettle();
    expect(find.text('Yeni başlangıç'), findsOneWidget);
    expect(find.text('Kullanıcı başlangıcı'), findsNothing);
    expect(bundle.reads, isEmpty);
    await tester.pumpWidget(_app(bundle, home: const ScenarioGraphScreen()));
    await tester.pumpAndSettle();
    expect(bundle.reads, [ScenarioGraphScreen.d01AssetPath]);
    expect(find.text('Elle hazırlanmış örnek'), findsOneWidget);
    expect(find.text(ScenarioGraphScreen.importedSourceLabel), findsNothing);
    expect(find.text(original.scenes.firstWhere((scene) => scene.id == original.startSceneId).title!),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Klip planında tekrarlayan içe aktarma girişi yoktur; eşleme yüklemesi korunur', (tester) async {
    final store = _NoVideos();
    final bundle = _ImportBundle({
      ClipProductionPlanScreen.d01GraphAssetPath: originalText,
      ClipProductionPlanScreen.d01PlanAssetPath: planText,
    });
    await tester.pumpWidget(_app(bundle, home: ClipProductionPlanScreen(videoStore: store)));
    await tester.pumpAndSettle();
    expect(store.reads, 1);
    expect(find.byKey(const ValueKey('open-scenario-graph-import')), findsNothing);
    expect(find.text('Senaryo / graf içe aktar'), findsNothing);
    expect(find.byKey(const ValueKey('open-graph-playback')), findsOneWidget);
    expect(find.byType(ClipProductionPlanScreen), findsOneWidget);
    expect(find.byType(ScenarioGraphImportScreen), findsNothing);
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    expect(store.reads, 1);
    expect(bundle.reads, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  for (final source in ['manual_example', 'model_output']) {
    testWidgets('Senaryo içeriği: $source kaynağıyla dönüştürülür ve görüntülenir', (tester) async {
      final alternatives = scenarioJson['alternatives'] as List;
      final chosen = source == 'model_output' ? alternatives.take(1).toList() : alternatives;
      final text = jsonEncode({...scenarioJson, 'source': source, 'alternatives': chosen});
      final count = chosen.length;
      final bundle = _ImportBundle({});
      await tester.pumpWidget(_app(bundle));
      await tap(tester, 'scenario-import-mode-scenario');
      expect(find.text('Graf oluştur'), findsOneWidget);
      expect(find.textContaining('Teknik geliştirici arayüzü:'), findsNothing);
      await tap(tester, 'scenario-import-format-details');
      expect(find.textContaining('Teknik geliştirici arayüzü:'), findsOneWidget);
      await enter(tester, text);
      await tap(tester, 'scenario-import-validate');

      expect(find.text('Senaryo kimliği: ${scenarioJson['scenarioId']}'), findsOneWidget);
      expect(find.text('Alternatif: $count'), findsOneWidget);
      expect(find.text('Sahne: ${1 + 2 * count} · Bağlantı: ${2 * count}'), findsOneWidget);
      expect(find.text(ScenarioGraphImportScreen.convertedSourceLabel), findsOneWidget);
      expect(find.text(ScenarioGraphScreen.importedSourceLabel), findsNothing);
      expect(find.textContaining('Kaynak (girdi beyanı):'), findsOneWidget);
      expect(find.textContaining('($source)'), findsOneWidget);
      expect(find.text(ScenarioGraphImportScreen.sourceDisclaimer), findsOneWidget);

      await tap(tester, 'scenario-import-view');
      final viewer = tester.widget<ScenarioGraphScreen>(find.byType(ScenarioGraphScreen));
      final graph = viewer.graph!;
      expect(graph.scenarioId, scenarioJson['scenarioId']);
      expect(graph.scenes, hasLength(1 + 2 * count));
      expect(graph.scenes.first.description, scenarioJson['commonStart']);
      for (var i = 0; i < count; i++) {
        expect(graph.scenes[1 + 2 * i].description, chosen[i]['continuation']);
        expect(graph.scenes[2 + 2 * i].description, chosen[i]['ending']);
      }
      expect(graph.validate, returnsNormally);
      expect(viewer.sourceLabel, contains('Senaryo içeriğinden dönüştürüldü'));
      expect(viewer.sourceLabel, contains('($source)'));
      expect(viewer.sourceLabel, contains('Kaynak alanı doğrulanmış köken kanıtı değildir.'));
      expect(find.textContaining('Senaryo içeriğinden dönüştürüldü'), findsOneWidget);
      expect(find.textContaining('($source)'), findsOneWidget);
      expect(find.text(ScenarioGraphScreen.importedSourceLabel), findsNothing);
      expect(bundle.reads, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scenario-import-summary')), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('scenario-import-json'))).controller!.text,
          text);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Elle hazırlanmış örnek tek assetten yüklenir; açık işlemle graf oluşturulur', (tester) async {
    expect(oldExampleExists, isFalse);
    expect(assetDefinitions.map((line) => line.trim()),
        contains('- ${ScenarioGraphImportScreen.d01InputAssetPath}'));
    final bundle = _ImportBundle({ScenarioGraphImportScreen.d01InputAssetPath: scenarioText});
    await tester.pumpWidget(_app(bundle));
    expect(find.byKey(const ValueKey('scenario-import-load-example')), findsNothing);
    await tap(tester, 'scenario-import-mode-scenario');
    await tap(tester, 'scenario-import-load-example');
    expect(bundle.reads, [ScenarioGraphImportScreen.d01InputAssetPath]);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('scenario-import-json'))).controller!.text,
        scenarioText);
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('scenario-import-view'))).onPressed,
        isNull);
    await tap(tester, 'scenario-import-validate');
    expect(find.text('Alternatif: 2'), findsOneWidget);
    await tap(tester, 'scenario-import-format-details');
    expect(find.text('Kaynak (girdi beyanı): Elle hazırlanmış örnek (manual_example)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final invalid in [
    (name: 'Boş içerik', text: '', message: 'senaryo içeriği JSON metni'),
    (name: 'Bozuk içerik JSON', text: '{', message: 'JSON okunamadı'),
    (name: 'Bitiş eksik',
      text: jsonEncode({...scenarioJson, 'alternatives': [
        {'title': 'Devam', 'continuation': 'Var olan devam.'},
      ]}), message: 'ending'),
    (name: 'Alternatif yok',
      text: jsonEncode({...scenarioJson, 'alternatives': []}), message: 'en az bir alternatif'),
    (name: 'Kaynak belirsiz',
      text: jsonEncode({...scenarioJson, 'source': 'bilinmiyor'}), message: 'source'),
    (name: 'Hazır graf yanlış türde', text: validText, message: 'desteklenmeyen alan'),
  ]) {
    testWidgets('${invalid.name}: dönüşüm hatası gösterilir, içerik uydurulmaz', (tester) async {
      final bundle = _ImportBundle({});
      await tester.pumpWidget(_app(bundle));
      await tap(tester, 'scenario-import-mode-scenario');
      await enter(tester, invalid.text);
      await tap(tester, 'scenario-import-validate');
      final error = tester.widget<Text>(find.byKey(const ValueKey('scenario-import-error')));
      expect(error.data, contains(invalid.message));
      expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
      expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('scenario-import-view'))).onPressed,
          isNull);
      expect(bundle.reads, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Düzenleme ve tür değişimi sonucu temizler; iki türün metinleri ayrı korunur', (tester) async {
    final bundle = _ImportBundle({});
    await tester.pumpWidget(_app(bundle));
    await enter(tester, validText);
    await tap(tester, 'scenario-import-validate');
    await tap(tester, 'scenario-import-mode-scenario');
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    await enter(tester, scenarioText);
    await tap(tester, 'scenario-import-validate');
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsOneWidget);
    await enter(tester, '{');
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('scenario-import-view'))).onPressed,
        isNull);
    await tap(tester, 'scenario-import-validate');
    expect(find.byKey(const ValueKey('scenario-import-error')), findsOneWidget);
    await tap(tester, 'scenario-import-mode-graph');
    expect(find.byKey(const ValueKey('scenario-import-error')), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('scenario-import-json'))).controller!.text,
        validText);
    await tap(tester, 'scenario-import-validate');
    await tap(tester, 'scenario-import-view');
    final viewer = tester.widget<ScenarioGraphScreen>(find.byType(ScenarioGraphScreen));
    expect(viewer.sourceLabel, isNull);
    expect(find.text(ScenarioGraphScreen.importedSourceLabel), findsOneWidget);
    expect(find.textContaining('Senaryo içeriğinden dönüştürüldü'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(tester, 'scenario-import-mode-scenario');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('scenario-import-json'))).controller!.text,
        '{');
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    expect(bundle.reads, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Örnek okunamazsa metin korunur; hata gösterilir ve yeniden denenebilir', (tester) async {
    final bundle = _ImportBundle({});
    await tester.pumpWidget(_app(bundle));
    await tap(tester, 'scenario-import-mode-scenario');
    await enter(tester, scenarioText);
    await tap(tester, 'scenario-import-validate');
    await tap(tester, 'scenario-import-load-example');
    expect(find.textContaining('D01 örneği okunamadı'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('scenario-import-json'))).controller!.text,
        scenarioText);
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('scenario-import-view'))).onPressed,
        isNull);
    bundle.sources[ScenarioGraphImportScreen.d01InputAssetPath] = scenarioText;
    await tap(tester, 'scenario-import-load-example');
    expect(find.byKey(const ValueKey('scenario-import-error')), findsNothing);
    await tap(tester, 'scenario-import-validate');
    expect(find.text('Alternatif: 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Örnek yüklenirken işlemler kilitlenir; geri çıkıştan sonraki sonuç güvenle bırakılır', (tester) async {
    final loading = Completer<String>();
    final bundle = _ImportBundle({}, read: (_) => loading.future);
    await tester.pumpWidget(_app(bundle));
    await tap(tester, 'scenario-import-mode-scenario');
    final loadButton = find.byKey(const ValueKey('scenario-import-load-example'));
    await tester.ensureVisible(loadButton);
    await tester.tap(loadButton);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('scenario-import-validate'))).onPressed,
        isNull);
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('scenario-import-mode-graph'))).onSelected,
        isNull);
    await tester.pumpWidget(_app(bundle, home: const Scaffold(body: Text('Kapatıldı'))));
    loading.complete(scenarioText);
    await tester.pumpAndSettle();
    expect(find.text('Kapatıldı'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
