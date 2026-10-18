import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/models/local_model_option.dart';
import 'package:neuro_awareness_app/models/scenario_input.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_import_screen.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_screen.dart';
import 'package:neuro_awareness_app/services/local_llama_test_service.dart';
import 'package:neuro_awareness_app/services/scenario_graph_converter.dart';

// Yalnız UI akışını sınar. Bu cevaplar gerçek model sonucu değildir.
// Model/native motor ve cihazdaki kayıtlar kullanılmaz; asset fixture'ı salt okunur.
class _DemoService extends LocalLlamaTestService {
  _DemoService(this.output, {this.failure, this.hold = false}) : super(
    request: LocalLlamaTestRequest.d01GraphDemo,
    resolveModel: () async => throw StateError('Test dosya açmamalı.'),
    createRuntime: (_) => throw StateError('Test native motor açmamalı.'),
  );

  final String output;
  final String? failure;
  final bool hold;
  final _events = StreamController<LocalLlamaTestState>.broadcast();
  final _gate = Completer<void>();
  LocalLlamaTestState _current = const LocalLlamaTestState();
  int runs = 0;
  int cancellations = 0;
  int disposals = 0;
  bool _closed = false;

  @override
  LocalLlamaTestState get state => _current;
  @override
  Stream<LocalLlamaTestState> get states => _events.stream;
  @override
  bool get canRun => !_closed && !_current.isBusy;

  void _emit(LocalLlamaPhase phase, {String text = '', String? error}) {
    _current = LocalLlamaTestState(phase: phase, text: text, error: error);
    _events.add(_current);
  }

  @override
  Future<void> run() async {
    if (!canRun) throw StateError('İkinci çağrı kabul edilmemeli.');
    runs++;
    _emit(LocalLlamaPhase.loading);
    if (hold) {
      _emit(LocalLlamaPhase.generating, text: output);
      await _gate.future;
      return;
    }
    _emit(failure == null ? LocalLlamaPhase.completed : LocalLlamaPhase.error,
        text: output, error: failure);
  }

  @override
  void cancel() {
    cancellations++;
    _emit(LocalLlamaPhase.cancelled, text: output);
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    disposals++;
    if (!_gate.isCompleted) _gate.complete();
    await _events.close();
  }
}

class _NoAssets extends CachingAssetBundle {
  final reads = <String>[];
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    reads.add(key);
    throw StateError('Model demosu sabit graf/plan asseti okumamalı.');
  }
  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

void main() {
  final example = jsonDecode(
    File(ScenarioGraphImportScreen.d01InputAssetPath).readAsStringSync(),
  ) as Map<String, dynamic>;
  final content = jsonEncode({
    'commonStart': example['commonStart'],
    'alternatives': example['alternatives'],
  });
  const request = LocalLlamaTestRequest.d01GraphDemo;

  Future<void> mount(WidgetTester tester, _DemoService service, _NoAssets bundle) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: bundle,
      child: MaterialApp(home: ScenarioGraphImportScreen(scenarioService: service)),
    ));
    await tester.pumpAndSettle();
    await tap(tester, 'scenario-import-mode-scenario');
    expect(service.runs, 0);
  }

  String editor(WidgetTester tester) => tester.widget<TextField>(
    find.byKey(const ValueKey('scenario-import-json')),
  ).controller!.text;

  void expectRaw(WidgetTester tester, String raw) {
    expect(tester.widget<SelectableText>(
      find.byKey(ValueKey('${request.id}-response')),
    ).data, raw);
  }

  test('Demo isteği mevcut Qwen, CPU runtime sınırları ve içerik sözleşmesini kullanır', () {
    expect(request.model, LocalModelOption.qwen3);
    expect(request.contextSize, 2048);
    expect(request.maxTokens, 768);
    expect(request.prompt, contains('commonStart'));
    expect(request.prompt, contains('continuation'));
    expect(request.prompt, contains('ending'));
    expect(request.prompt, contains('Markdown, kod çiti veya ek açıklama yazma'));
    expect(request.prompt, contains('Sahne kimliği, kenar veya startSceneId üretme'));
  });

  testWidgets('Tek kullanıcı çağrısı: ham cevap korunur, metadata eklenir ve graf açılır', (tester) async {
    final service = _DemoService(' \n$content\n');
    final bundle = _NoAssets();
    await mount(tester, service, bundle);
    await tap(tester, '${request.id}-start');
    expect(service.runs, 1);
    expectRaw(tester, ' \n$content\n');
    expect(find.byKey(const ValueKey('scenario-import-normalization')), findsNothing);
    final input = ScenarioInput.fromJsonString(editor(tester));
    expect(input.commonStart, example['commonStart']);
    expect(input.scenarioId, LocalLlamaTestRequest.d01GraphDemoMetadata['scenarioId']);
    expect(input.source, ScenarioInputSource.modelOutput);
    expect(input.alternatives[0].continuation, example['alternatives'][0]['continuation']);
    expect(input.alternatives[1].ending, example['alternatives'][1]['ending']);
    expect(find.text('Alternatif: 2'), findsOneWidget);
    await tap(tester, 'scenario-import-view');
    final viewer = tester.widget<ScenarioGraphScreen>(find.byType(ScenarioGraphScreen));
    expect(viewer.graph!.scenes.length, 5);
    expect(viewer.graph!.transitions.length, 4);
    expect(viewer.graph!.scenes.first.description, example['commonStart']);
    expect(viewer.sourceLabel, contains('(model_output)'));
    expect(find.text(ScenarioGraphScreen.importedSourceLabel), findsNothing);
    expect(bundle.reads, isEmpty);
    expect(service.runs, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(service.disposals, 1);
  });

  // Baş/son boşluk ve satır sonları da anlatının parçası olarak korunmalı.
  final formatFields = {
    'commonStart': ' \n${example['commonStart']}\n ',
    'alternatives': [
      for (final alternative in example['alternatives'])
        {
          'title': ' ${alternative['title']} ',
          'continuation': ' \n${alternative['continuation']}\n ',
          'ending': ' ${alternative['ending']} ',
        },
    ],
  };
  final formatContent = jsonEncode(formatFields);
  final wrapped = jsonEncode({'scenarioInput': formatFields});
  for (final formatted in [
    ('JSON çiti', '```json\n$formatContent\n```', true, false),
    ('Tek sarmalayıcı', wrapped, false, true),
    ('Çit ve sarmalayıcı', ' \r\n```json\r\n$wrapped\r\n```\r\n ', true, true),
  ]) {
    testWidgets('${formatted.$1}: yalnız biçim açılır, ham cevap ve bütün anlatılar korunur', (tester) async {
      final service = _DemoService(formatted.$2);
      await mount(tester, service, _NoAssets());
      await tap(tester, '${request.id}-start');
      expectRaw(tester, formatted.$2);
      expect(find.byKey(const ValueKey('scenario-import-error')), findsNothing);
      expect(find.byKey(const ValueKey('scenario-import-summary')), findsOneWidget);
      final normalized = jsonDecode(editor(tester)) as Map<String, dynamic>;
      expect(normalized['commonStart'], formatFields['commonStart']);
      expect(normalized['alternatives'], formatFields['alternatives']);
      expect(normalized.containsKey('scenarioInput'), isFalse);
      final input = ScenarioInput.fromJson(normalized);
      expect(input.source, ScenarioInputSource.modelOutput);
      expect(input.scenarioId, LocalLlamaTestRequest.d01GraphDemoMetadata['scenarioId']);
      final notice = tester.widget<Text>(
        find.byKey(const ValueKey('scenario-import-normalization')),
      ).data!;
      expect(notice.contains('JSON çiti kaldırıldı'), formatted.$3);
      expect(notice.contains('scenarioInput sarmalayıcısı açıldı'), formatted.$4);
      // Editördeki normalleştirilmiş kopya tekrar doğrulanabilir; çıkarım yok.
      await tap(tester, 'scenario-import-validate');
      expect(find.byKey(const ValueKey('scenario-import-summary')), findsOneWidget);
      expectRaw(tester, formatted.$2);
      expect(service.runs, 1);
      await tap(tester, 'scenario-import-view');
      final graph = tester.widget<ScenarioGraphScreen>(
        find.byType(ScenarioGraphScreen),
      ).graph!;
      expect(graph.scenes.first.description, input.commonStart);
      for (var index = 0; index < input.alternatives.length; index++) {
        expect(graph.scenes[1 + 2 * index].description,
            input.alternatives[index].continuation);
        expect(graph.scenes[2 + 2 * index].description,
            input.alternatives[index].ending);
      }
      expect(graph.validate, returnsNormally);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final invalid in [
    ('Ön açıklama', 'Cevap:\n```json\n$content\n```'),
    ('Son açıklama', '```json\n$content\n```\nBitti.'),
    ('İki kod bloğu', '```json\n$content\n```\n```json\n$content\n```'),
    ('Eksik çit', '```json\n$content'),
    ('Bozuk JSON', '```json\n{"scenarioInput": {"commonStart": "Eksik",}}\n```'),
    ('Yan alanlı sarmalayıcı', jsonEncode({'scenarioInput': jsonDecode(content), 'extra': 'Ek metin'})),
    ('Nesne olmayan sarmalayıcı', '{"scenarioInput": "Metin"}'),
    ('İç içe sarmalayıcı', jsonEncode({'scenarioInput': jsonDecode(wrapped)})),
    ('Eksik anlatı', '{"commonStart":"Sadece ortak metin."}'),
    ('Çitli ve sarmalı eksik anlatı', '```json\n{"scenarioInput":{"commonStart":"Sadece ortak metin."}}\n```'),
    ('Eksik dal', jsonEncode({'commonStart': example['commonStart'],
      'alternatives': [example['alternatives'][0]]})),
  ]) {
    testWidgets('${invalid.$1}: hata gösterilir; içerik tamamlanmaz ve tekrar denenmez', (tester) async {
      final service = _DemoService(invalid.$2);
      await mount(tester, service, _NoAssets());
      await tap(tester, '${request.id}-start');
      expectRaw(tester, invalid.$2);
      expect(find.byKey(const ValueKey('scenario-import-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
      expect(tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('scenario-import-view')),
      ).onPressed, isNull);
      expect(service.runs, 1);
      if (invalid.$1 == 'Bozuk JSON') expect(editor(tester), invalid.$2);
      if (invalid.$1 == 'Eksik anlatı') {
        expect(jsonDecode(editor(tester)).containsKey('alternatives'), isFalse);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('Kullanıcı düzeltmesi ham cevabı değiştirmez; kaynak graf notunda da ayrılır', (tester) async {
    const raw = '{"commonStart":"Eksik taslak"}';
    final service = _DemoService(raw);
    await mount(tester, service, _NoAssets());
    await tap(tester, '${request.id}-start');
    await tester.enterText(find.byKey(const ValueKey('scenario-import-json')), content);
    await tester.pump();
    await tap(tester, 'scenario-import-validate');
    final input = ScenarioInput.fromJsonString(editor(tester));
    expect(input.source, ScenarioInputSource.editedModelOutput);
    expectRaw(tester, raw);
    expect(service.runs, 1);
    await tap(tester, 'scenario-import-view');
    final viewer = tester.widget<ScenarioGraphScreen>(find.byType(ScenarioGraphScreen));
    expect(viewer.sourceLabel, contains('(model_output_edited)'));
    expect(viewer.graph!.authoringNote, contains('kullanıcı tarafından düzenlenmiş'));
    expect(viewer.graph!.scenes.first.description, example['commonStart']);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Model hatası kısmi cevabı korur; şablon veya graf üretmez', (tester) async {
    final service = _DemoService('KISMİ TEST METNİ', failure: 'Model indirilmedi');
    await mount(tester, service, _NoAssets());
    await tap(tester, '${request.id}-start');
    expectRaw(tester, 'KISMİ TEST METNİ');
    expect(find.textContaining('Modelden taslak alınamadı: Model indirilmedi'), findsOneWidget);
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    expect(editor(tester), isEmpty);
    expect(service.runs, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Üretim sırasında düzenleme kilitli; iptal kısmi cevabı grafa taşımaz', (tester) async {
    final service = _DemoService('KISMİ', hold: true);
    await mount(tester, service, _NoAssets());
    final start = find.byKey(ValueKey('${request.id}-start'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pump();
    expect(tester.widget<TextField>(
      find.byKey(const ValueKey('scenario-import-json')),
    ).readOnly, isTrue);
    expect(tester.widget<FilledButton>(start).onPressed, isNull);
    final cancel = find.byKey(ValueKey('${request.id}-cancel'));
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(service.cancellations, 1);
    expect(find.textContaining('kısmi cevap grafa aktarılmadı'), findsOneWidget);
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    expectRaw(tester, 'KISMİ');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(service.disposals, 1);
  });

  test('Düzenlenmiş kaynak mevcut sözleşme ve dönüştürücüyle korunur', () {
    final input = ScenarioInput.fromJson({
      ...example,
      'source': 'model_output_edited',
    });
    final graph = const ScenarioGraphConverter().convert(input);
    expect(graph.authoringNote, contains('değiştirilmemiş ham model cevabı değildir'));
    expect(graph.validate, returnsNormally);
  });

  testWidgets('Üretim sürerken ekran kapanırsa servis bırakılır; geç sonuç uygulanmaz', (tester) async {
    final service = _DemoService('KISMİ', hold: true);
    await mount(tester, service, _NoAssets());
    final start = find.byKey(ValueKey('${request.id}-start'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(service.disposals, 1);
    expect(service.runs, 1);
    expect(tester.takeException(), isNull);
  });
}

Future<void> tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}
