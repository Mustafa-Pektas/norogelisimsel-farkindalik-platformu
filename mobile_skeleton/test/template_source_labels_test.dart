import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_awareness_app/screens/simulation_mode_screen.dart';
import 'package:neuro_awareness_app/screens/synthetic_video_studio_screen.dart';
import 'package:neuro_awareness_app/services/synthetic_video_service.dart';
// Mevcut path_provider paketinin kontrollü test sınırı; yeni paket yok.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _NoDocuments extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      throw StateError('Bu test dosya sistemi veya model açmamalı.');
}

void main() {
  late PathProviderPlatform originalPaths;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoDocuments();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  tearDown(() {
    PathProviderPlatform.instance = originalPaths;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('Ortak eski şablon servisi kaynak ve dışa aktarmada model çıkarımı iddia etmez', () {
    final result = SyntheticVideoPromptService.generateSession(
      ageMonths: 30, totalTargetSec: 24, blockDurationSec: 8,
      riskProfile: 'tipik', ontologyCodes: ['ONT-01'],
    );
    expect(result.title, contains('Şablon Senaryo Taslağı'));
    expect(result.title, isNot(contains('Llama')));
    expect(result.exportDoctorCleanScenario(), contains('Şablon Senaryo Taslağı'));
    final metadata = (jsonDecode(result.exportGroundTruthJson()) as Map)['session_meta'] as Map;
    expect(metadata['source'], 'Hazır şablon; model çıkarımı yapılmadı');
    expect(metadata['content_status'], 'planned_unreviewed');
    expect(result.exportEnglishPromptsOnly(), contains('Hazır şablon; model çıkarımı yapılmadı'));
    expect(result.exportEnglishPromptsOnly(), contains(result.steps.first.universalPrompt));
    expect(result.exportFullMarkdown(), contains('Hazır şablon; model çıkarımı yapılmadı'));
  });

  test('Eski doktor şablonu da Llama çıkarımı kaynağı iddia etmez', () async {
    final result = SyntheticVideoPromptService.generateDoctorScenario(
      ageMonths: 30,
      ontologyCode: 'ONT-01',
      riskProfile: 'tipik',
    );
    expect(result.engineUsed, 'Hazır şablon; model çıkarımı yapılmadı');
    expect(result.exportDoctorMarkdown(), contains('Hazır şablon; model çıkarımı yapılmadı'));
    expect(result.exportDoctorMarkdown(), isNot(contains('On-Device (GGUF)')));
  });

  testWidgets('Stüdyo çevrimdışı şablon üretimi ve export kaynağı doğrudur; admin ölçüm uydurmaz', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await tester.pumpWidget(const MaterialApp(home: SyntheticVideoStudioScreen()));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('studio-template-source'))).data,
      contains('Hazır şablon; model çıkarımı yapılmadı'));
    final generate = find.byKey(const ValueKey('studio-generate-scenario'));
    await tester.ensureVisible(generate);
    expect(tester.widget<ElevatedButton>(generate).onPressed, isNotNull);
    await tester.tap(generate);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Klinik Protokolü Kopyala (Markdown)'));
    await tester.pumpAndSettle();
    expect(copied, contains('Hazır şablon; model çıkarımı yapılmadı'));
    expect(copied, isNot(contains('On-Device (GGUF)')));
    final title = find.byKey(const ValueKey('studio-admin-title'));
    for (var i = 0; i < 5; i++) {
      await tester.tap(title);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('ADMİN'), findsOneWidget);
    expect(find.byKey(const ValueKey('unmeasured-validation')), findsOneWidget);
    expect(find.text('Ölçülmedi / doğrulama hizmeti bağlı değil.'), findsOneWidget);
    expect(find.textContaining('Güven: %'), findsNothing);
    expect(find.textContaining('Zamanlama Sapması:'), findsNothing);
    expect(find.text('DOĞRULANDI'), findsNothing);
    await tester.tap(find.byTooltip('Tüm Video Promptlarını Kopyala (Admin)'));
    await tester.pumpAndSettle();
    expect(copied, contains('Hazır şablon; model çıkarımı yapılmadı'));
    await tester.tap(find.byTooltip('JSON Dışa Aktar (Admin)'));
    await tester.pumpAndSettle();
    final metadata = (jsonDecode(copied!) as Map)['session_meta'] as Map;
    expect(metadata['source'], 'Hazır şablon; model çıkarımı yapılmadı');
    expect(metadata['content_status'], 'planned_unreviewed');
    for (final key in ['open-scenario-graph', 'open-scenario-content', 'open-clip-production-plan']) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  for (final screen in [
    (title: 'Senaryo & Simülasyon', widget: const SimulationModeScreen()),
  ]) {
    testWidgets('${screen.title}: eski ölçümsüz kart güven/başarı sonucu sunmaz', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: screen.widget));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      // Eski Simülasyon ekranının mekanizması bu görevin kapsamında değil.
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text(screen.title));
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('unmeasured-validation')), findsOneWidget);
      expect(find.textContaining('Gerçek ölçüm olmadığı için'), findsOneWidget);
      expect(find.textContaining('Güven: %'), findsNothing);
      expect(find.textContaining('Zamanlama Sapması:'), findsNothing);
      expect(find.text('DOĞRULANDI'), findsNothing);
      expect(find.text('Ground-Truth Testini Yeniden Çalıştır'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
