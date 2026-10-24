import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_awareness_app/models/scenario_generation_request.dart';
import 'package:neuro_awareness_app/models/scenario_input.dart';
import 'package:neuro_awareness_app/models/scenario_workspace_draft.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_import_screen.dart';
import 'package:neuro_awareness_app/services/scenario_draft_store.dart';

class _DraftStore extends ScenarioDraftStore {
  ScenarioWorkspaceDraft? value;
  Completer<ScenarioWorkspaceDraft?>? loadGate;
  Completer<void>? saveGate;
  bool failLoad = false;
  bool failSave = false;
  bool failDelete = false;
  int saves = 0;
  int deletes = 0;
  @override
  Future<ScenarioWorkspaceDraft?> load() async {
    if (failLoad) throw const FormatException('Kontrollü bozuk kayıt');
    if (loadGate != null) return loadGate!.future;
    return value;
  }
  @override
  Future<void> save(ScenarioWorkspaceDraft draft) async {
    ++saves;
    if (saveGate != null) await saveGate!.future;
    if (failSave) throw StateError('Kontrollü yazma hatası');
    value = ScenarioWorkspaceDraft.fromJsonString(draft.toJsonString());
  }
  @override
  Future<void> delete() async {
    ++deletes;
    if (failDelete) throw StateError('Kontrollü silme hatası');
    value = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final request = ScenarioGenerationRequest(behaviorId: 'D02', cardVersion: '0.2',
    ageMonths: 24, sceneContext: '  Evde  ', additionalInstructions: ' Sade ortam ');
  final raw = ' \n${jsonEncode({
    'commonStart': '  Ham başlangıç  ',
    'alternatives': [{'title': 'Devam', 'continuation': ' Ham devam ', 'ending': ' Ham bitiş '}],
  })}\n ';
  final edited = jsonDecode(request.prepareInput(raw, scenarioId: 'saved-scenario', edited: true).json)
      as Map<String, dynamic>;
  edited['commonStart'] = '  Ekibin düzenlediği başlangıç  ';
  ScenarioWorkspaceDraft sample({String type = 'scenario', bool demo = false}) => ScenarioWorkspaceDraft(
    inputType: type, scenarioJson: jsonEncode(edited), graphJson: '{"hazırGrafTaslağı": true}',
    ageText: '24', contextText: '  Evde  ', instructionsText: ' Sade ortam ',
    behaviorId: 'D02', cardVersion: '0.2', generationRaw: raw,
    responseRequest: request, responseScenarioId: 'saved-scenario',
    editorRequest: demo ? null : request, editorScenarioId: demo ? null : 'saved-scenario',
    generationEdited: true, demoRaw: ' \nÖnceki yerel demo cevabı\n ',
    demoDraft: demo, demoEdited: demo);

  test('Tek SharedPreferences kaydı kaynakları korur; silme başka anahtara dokunmaz', () async {
    SharedPreferences.setMockInitialValues({'unrelated_existing_key': 'koru'});
    const store = ScenarioDraftStore();
    await store.save(sample());
    final loaded = (await store.load())!;
    expect(loaded.generationRaw, raw);
    expect(loaded.scenarioJson, jsonEncode(edited));
    expect(loaded.responseRequest!.behaviorId, 'D02');
    expect(loaded.responseRequest!.ageMonths, 24);
    expect(loaded.editorScenarioId, 'saved-scenario');
    expect(loaded.demoRaw, ' \nÖnceki yerel demo cevabı\n ');
    final encoded = jsonDecode(loaded.toJsonString()) as Map<String, dynamic>;
    for (final field in ['validatedGraph', 'job', 'completed', 'generationStatus']) {
      expect(encoded.containsKey(field), isFalse);
    }
    await store.delete();
    expect(await store.load(), isNull);
    expect((await SharedPreferences.getInstance()).getString('unrelated_existing_key'), 'koru');
  });

  for (final corrupt in ['{bozuk', '{"version": 0}', '{"version": 2}']) {
    test('Bozuk/eski kayıt reddedilir ve değiştirilmez: $corrupt', () async {
      SharedPreferences.setMockInitialValues({ScenarioDraftStore.storageKey: corrupt});
      await expectLater(const ScenarioDraftStore().load(), throwsFormatException);
      expect((await SharedPreferences.getInstance()).getString(ScenarioDraftStore.storageKey), corrupt);
    });
  }
  test('Güncel olmayan kart veya ham cevap-kaynak ilişkisi sessizce düzeltilmez', () {
    final map = jsonDecode(sample().toJsonString()) as Map<String, dynamic>;
    map['cardVersion'] = '0.1';
    expect(() => ScenarioWorkspaceDraft.fromJsonString(jsonEncode(map)), throwsFormatException);
    map['cardVersion'] = '0.2';
    map['responseRequest'] = null;
    expect(() => ScenarioWorkspaceDraft.fromJsonString(jsonEncode(map)), throwsFormatException);
  });

  Future<void> mount(WidgetTester tester, _DraftStore store, {bool narrow = false}) async {
    await tester.binding.setSurfaceSize(narrow ? const Size(320, 800) : const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
        child: child!),
      home: ScenarioGraphImportScreen(initialScenarioContent: true,
        draftStore: store),
    ));
    await tester.pumpAndSettle();
  }
  Future<void> tap(WidgetTester tester, String key) async {
    final title = switch (key) {
      'scenario-import-request-form' => 'Senaryo üretim isteği',
      'scenario-import-legacy-records' => 'Geçmiş yerel demo kaydı',
      _ => null,
    };
    final target = title == null ? find.byKey(ValueKey(key)) : find.descendant(
      of: find.byKey(ValueKey(key)), matching: find.text(title));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }
  String editor(WidgetTester tester) => tester.widget<TextField>(
    find.byKey(const ValueKey('scenario-import-json'))).controller!.text;
  Future<void> edit(WidgetTester tester, String text) async {
    final field = find.byKey(const ValueKey('scenario-import-json'));
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets('Yeniden açılış formu/ham kaynakları ve iki JSON türünü korur; graf yeniden doğrulanır', (tester) async {
    final store = _DraftStore()..value = sample();
    await mount(tester, store);
    expect(editor(tester), jsonEncode(edited));
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('scenario-import-view'))).onPressed, isNull);
    expect(find.byKey(const ValueKey('scenario-generation-status')), findsNothing);
    expect(find.byKey(const ValueKey('scenario-import-request-form')), findsNothing);
    // Eski form alanları görünmez olsa da kayıt içinde kayıpsız korunur.
    await tap(tester, 'scenario-draft-save');
    expect(store.value!.ageText, '24');
    expect(store.value!.contextText, '  Evde  ');
    expect(store.value!.instructionsText, ' Sade ortam ');
    expect(store.value!.behaviorId, 'D02');
    await tap(tester, 'scenario-generation-raw-details');
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('scenario-generation-raw'))).data, raw);
    await tap(tester, 'scenario-import-legacy-records');
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('scenario-restored-demo-raw'))).data,
      ' \nÖnceki yerel demo cevabı\n ');

    await tap(tester, 'scenario-import-validate');
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsOneWidget);
    await tap(tester, 'scenario-draft-save');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await mount(tester, store);
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    await tap(tester, 'scenario-import-validate');
    expect(ScenarioInput.fromJsonString(editor(tester)).source, ScenarioInputSource.editedModelOutput);
    await tap(tester, 'scenario-import-mode-graph');
    expect(editor(tester), '{"hazırGrafTaslağı": true}');
    await edit(tester, '  Ayrı graf JSON taslağı  ');
    await tap(tester, 'scenario-draft-save');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await mount(tester, store);
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('scenario-import-mode-graph'))).selected, isTrue);
    expect(editor(tester), '  Ayrı graf JSON taslağı  ');
    await tap(tester, 'scenario-import-mode-scenario');
    expect(ScenarioInput.fromJsonString(editor(tester)).commonStart, '  Ekibin düzenlediği başlangıç  ');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Yüklenen taslak F04 ile korunur; bilinçli çıkış kayıtlı kopyayı silmez', (tester) async {
    final store = _DraftStore()..value = sample();
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(key: const ValueKey('open-workspace'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
          ScenarioGraphImportScreen(draftStore: store))),
        child: const Text('Çalışma alanını aç')),
    ))));
    await tap(tester, 'open-workspace');
    final before = editor(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tap(tester, 'scenario-import-stay');
    expect(editor(tester), before);
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);

    expect(store.saves, 0);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tap(tester, 'scenario-import-exit');
    expect(find.byType(ScenarioGraphImportScreen), findsNothing);
    expect(store.value!.scenarioJson, before);
    expect(store.deletes, 0);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Eski yerel demo kaydı ham metni, kaynak işaretlerini ve kopyalamayı korur', (tester) async {
    final saved = sample(demo: true);
    final store = _DraftStore()..value = saved;
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await mount(tester, store, narrow: true);
    expect(find.byKey(const ValueKey('scenario-import-model-demo'), skipOffstage: false), findsNothing);
    final history = find.byKey(const ValueKey('scenario-import-legacy-records'));
    expect(tester.widget<ExpansionTile>(history).initiallyExpanded, isFalse);
    final before = editor(tester);
    await tap(tester, 'scenario-import-legacy-records');
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('scenario-restored-demo-raw'))).data, saved.demoRaw);
    await tap(tester, 'scenario-import-copy-raw');
    expect(copied, saved.demoRaw);
    expect(copied, isNot(before));
    await tap(tester, 'scenario-draft-save');
    expect(store.value!.demoRaw, saved.demoRaw);
    expect(store.value!.demoDraft, isTrue);
    expect(store.value!.demoEdited, isTrue);
    expect(store.value!.scenarioJson, before);
    expect(store.value!.generationRaw, saved.generationRaw);
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });


  testWidgets('Yalnız geçmiş ham kayıt F04 ister; eski demo editörü mevcut doğrulamayla açılır', (tester) async {
    final legacyContent = jsonEncode({
      'commonStart': '  Eski ortak başlangıç  ',
      'alternatives': [
        {'title': 'Birinci', 'continuation': ' İlk devam ', 'ending': ' İlk bitiş '},
        {'title': 'İkinci', 'continuation': ' İkinci devam ', 'ending': ' İkinci bitiş '},
      ],
    });
    final saved = ScenarioWorkspaceDraft(inputType: 'scenario', scenarioJson: legacyContent,
      graphJson: '', ageText: '', contextText: '', instructionsText: '',
      demoRaw: ' \nESKİ HAM CEVAP\n ', demoDraft: true, demoEdited: true);
    final store = _DraftStore()..value = saved;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(key: const ValueKey('open-workspace'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
          ScenarioGraphImportScreen(draftStore: store))), child: const Text('Aç')),
    ))));
    await tap(tester, 'open-workspace');
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsNothing);
    await tap(tester, 'scenario-import-validate');
    final input = ScenarioInput.fromJsonString(editor(tester));
    expect(input.scenarioId, 'd01-qwen-yerel-demo');
    expect(input.behaviorId, 'D01');
    expect(input.ageMonths, 30);
    expect(input.source, ScenarioInputSource.editedModelOutput);
    expect(input.commonStart, '  Eski ortak başlangıç  ');
    expect(input.alternatives.first.continuation, ' İlk devam ');
    expect(find.byKey(const ValueKey('scenario-import-summary')), findsOneWidget);
    await edit(tester, '');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget); // Yalnız geçmiş ham cevap kaldı.
    await tap(tester, 'scenario-import-stay');
    await tap(tester, 'scenario-import-legacy-records');
    expect(tester.widget<SelectableText>(find.byKey(const ValueKey('scenario-restored-demo-raw'))).data, saved.demoRaw);
    expect(store.value!.demoRaw, saved.demoRaw);
    expect(store.saves, 0);
    expect(store.deletes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Geç yükleme yeni kullanıcı metnini ezmez; kapanmış ekrana uygulanmaz', (tester) async {
    final store = _DraftStore()..loadGate = Completer<ScenarioWorkspaceDraft?>();
    await mount(tester, store);
    await edit(tester, 'YENİ KULLANICI METNİ');
    store.loadGate!.complete(sample());
    await tester.pumpAndSettle();
    expect(editor(tester), 'YENİ KULLANICI METNİ');
    expect(find.textContaining('bu oturumdaki değişiklikler korundu'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final late = _DraftStore()..loadGate = Completer<ScenarioWorkspaceDraft?>();
    await mount(tester, late);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    late.loadGate!.complete(sample());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Okuma/yazma hatası taslağı korur; yanıltıcı kaydedildi sonucu yoktur', (tester) async {
    final store = _DraftStore()..failLoad = true..failSave = true;
    await mount(tester, store);
    expect(find.byKey(const ValueKey('scenario-draft-error')), findsOneWidget);
    await edit(tester, 'KORUNACAK METİN');
    await tap(tester, 'scenario-draft-save');
    expect(editor(tester), 'KORUNACAK METİN');
    expect(store.value, isNull);
    expect(find.text('Taslak bu cihazda kaydedildi.'), findsNothing);
    expect(find.text('Taslak kaydedilemedi. Ekrandaki içeriğiniz korundu.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Yazma sürerken yeni düzenleme kaydedilmiş sayılmaz', (tester) async {
    final store = _DraftStore()..saveGate = Completer<void>();
    await mount(tester, store);
    await edit(tester, 'İLK METİN');
    await tap(tester, 'scenario-draft-save');
    await edit(tester, 'DAHA YENİ METİN');
    store.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(store.value!.scenarioJson, 'İLK METİN');
    expect(editor(tester), 'DAHA YENİ METİN');
    expect(find.text('Taslak bu cihazda kaydedildi.'), findsNothing);
    expect(find.text('Önceki an kaydedildi; yeni değişiklikler kaydedilmedi.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Kayıt silme onaylıdır; ekrandaki taslak ve başarısız silmede kayıt korunur', (tester) async {
    final store = _DraftStore()..value = sample();
    await mount(tester, store, narrow: true);
    final before = editor(tester);
    await tap(tester, 'scenario-draft-delete');
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(store.deletes, 0);
    store.failDelete = true;
    await tap(tester, 'scenario-draft-delete');
    await tester.tap(find.text('Kaydı sil'));
    await tester.pumpAndSettle();
    expect(store.value, isNotNull);
    expect(editor(tester), before);
    expect(find.byKey(const ValueKey('scenario-draft-error')), findsOneWidget);
    store.failDelete = false;
    await tap(tester, 'scenario-draft-delete');
    await tester.tap(find.text('Kaydı sil'));
    await tester.pumpAndSettle();
    expect(store.value, isNull);
    expect(editor(tester), before);
    expect(store.saves, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await mount(tester, store);
    expect(editor(tester), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
