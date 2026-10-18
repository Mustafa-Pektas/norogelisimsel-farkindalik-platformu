import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/screens/simulation_mode_screen.dart';
import 'package:neuro_awareness_app/screens/synthetic_video_studio_screen.dart';
import 'package:neuro_awareness_app/services/llama_model_service.dart';
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

  test('Eski Llama senaryo yolu şablonla aynı içeriktedir; kaynak iddiası yoktur', () async {
    final local = SyntheticVideoPromptService.generateSession(
      ageMonths: 30,
      totalTargetSec: 24,
      blockDurationSec: 8,
      riskProfile: 'tipik',
      ontologyCodes: ['ONT-01'],
    );
    final legacy = await LlamaModelService.generateWithLlama(
      ageMonths: 30,
      totalTargetSec: 24,
      blockDurationSec: 8,
      riskProfile: 'tipik',
      ontologyCodes: ['ONT-01'],
    );
    expect(local.title, contains('Şablon Senaryo Taslağı'));
    expect(legacy.title, local.title);
    expect(legacy.title, isNot(contains('Llama')));
    expect(legacy.exportDoctorCleanScenario(), local.exportDoctorCleanScenario());
    expect(legacy.exportDoctorCleanScenario(), contains('Şablon Senaryo Taslağı'));
    expect(legacy.exportGroundTruthJson(), local.exportGroundTruthJson());
  });

  test('Eski doktor şablonu da Llama çıkarımı kaynağı iddia etmez', () async {
    final result = await LlamaModelService.generateDoctorScenarioWithLlama(
      ageMonths: 30,
      ontologyCode: 'ONT-01',
      riskProfile: 'tipik',
    );
    expect(result.engineUsed, 'Hazır şablon; model çıkarımı yapılmadı');
    expect(result.exportDoctorMarkdown(), isNot(contains('On-Device (GGUF)')));
  });

  testWidgets('Şablon düğmesi, yükleme ve çıktı gerçek kaynaklarını gösterir', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: SyntheticVideoStudioScreen()));
    await tester.tap(find.text('Şablon örnekleri'));
    await tester.pump();
    expect(find.byKey(const ValueKey('template-scenario-loading')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('generate-template-scenario'));
    expect(find.widgetWithText(ElevatedButton, 'Şablondan senaryo oluştur'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('template-scenario-title'))).data,
        contains('Şablon Senaryo Taslağı'));
    expect(find.textContaining('Hazır şablondan oluşturulmuş taslaktır'), findsOneWidget);
    expect(find.text('Llama 3.2 İle Senaryo Üret'), findsNothing);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(find.text('Şablon senaryo taslağı hazırlanıyor...'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('template-scenario-source')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final screen in [
    (title: 'Senaryo Stüdyosu', widget: const SyntheticVideoStudioScreen()),
    (title: 'Senaryo & Simülasyon', widget: const SimulationModeScreen()),
  ]) {
    testWidgets('${screen.title}: eski ölçümsüz kart güven/başarı sonucu sunmaz', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: screen.widget));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text(screen.title));
      }
      await tester.pumpAndSettle();
      if (screen.widget is SyntheticVideoStudioScreen) {
        final templates = find.text('Şablon örnekleri');
        await tester.ensureVisible(templates);
        await tester.tap(templates);
        await tester.pumpAndSettle();
      }
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
