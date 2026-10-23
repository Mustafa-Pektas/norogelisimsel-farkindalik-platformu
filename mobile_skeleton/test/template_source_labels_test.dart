import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
    expect(result.exportGroundTruthJson(), isNotEmpty);
    expect(result.exportEnglishPromptsOnly(), isNotEmpty);
  });

  test('Eski doktor şablonu da Llama çıkarımı kaynağı iddia etmez', () async {
    final result = SyntheticVideoPromptService.generateDoctorScenario(
      ageMonths: 30,
      ontologyCode: 'ONT-01',
      riskProfile: 'tipik',
    );
    expect(result.engineUsed, 'Hazır şablon; model çıkarımı yapılmadı');
    expect(result.exportDoctorMarkdown(), isNot(contains('On-Device (GGUF)')));
  });

  testWidgets('Aktif Stüdyo eski şablon üretim ve export arayüzünü içermez', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: SyntheticVideoStudioScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Eski şablon araçları', skipOffstage: false), findsNothing);
    for (final key in ['studio-template-examples', 'generate-template-scenario',
      'template-scenario-loading', 'template-scenario-title',
      'template-scenario-source', 'show-template-clip-details', 'unmeasured-validation']) {
      expect(find.byKey(ValueKey(key), skipOffstage: false), findsNothing);
    }
    expect(find.byTooltip('Senaryoyu Kopyala', skipOffstage: false), findsNothing);
    expect(find.byTooltip('Şablon JSON’unu kopyala', skipOffstage: false), findsNothing);
    expect(find.textContaining('Şablon Senaryo Taslağı', skipOffstage: false), findsNothing);
    expect(find.textContaining('Güven: %'), findsNothing);
    expect(find.text('DOĞRULANDI'), findsNothing);
    expect(find.byKey(const ValueKey('open-scenario-graph')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-scenario-content')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-clip-production-plan')), findsOneWidget);
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
