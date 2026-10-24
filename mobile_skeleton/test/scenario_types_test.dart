import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_awareness_app/screens/synthetic_video_studio_screen.dart';
// Mevcut paketin kontrollü platform sınırı; cihaz dosyası açılmaz.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _NoDocuments extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      throw StateError('Bu test model dosyası açmamalı.');
}

void main() {
  late PathProviderPlatform originalPaths;
  setUp(() {
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoDocuments();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  tearDown(() {
    PathProviderPlatform.instance = originalPaths;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('Beş dokunuş admini açıp kapatır; iki mevcut tür ve hazırlama girişleri korunur',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: SyntheticVideoStudioScreen()));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(SyntheticVideoStudioScreen));
    for (final key in ['open-d01-playback', 'open-scenario-graph',
      'open-scenario-content', 'open-clip-production-plan']) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(find.text('Doktor Klinik Protokolü'), findsOneWidget);
    expect(find.text('ADMİN'), findsNothing);
    final title = find.byKey(const ValueKey('studio-admin-title'));
    for (var i = 0; i < 5; i++) {
      await tester.tap(title);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('ADMİN'), findsOneWidget);
    expect(find.text('Tür 1: Doktor Protokolü'), findsOneWidget);
    expect(find.text('Tür 2: Video Stüdyosu'), findsOneWidget);
    expect(find.byKey(const ValueKey('unmeasured-validation')), findsOneWidget);
    await tester.ensureVisible(find.text('Tür 1: Doktor Protokolü'));
    await tester.tap(find.text('Tür 1: Doktor Protokolü'));
    await tester.pumpAndSettle();
    expect(find.text('Doktor Klinik Protokolü'), findsOneWidget);
    await tester.tap(find.text('Tür 2: Video Stüdyosu'));
    await tester.pumpAndSettle();
    expect(find.text('Sentetik Video Stüdyosu'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.tap(title);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('ADMİN'), findsNothing);
    expect(find.text('Tür 1: Doktor Protokolü'), findsNothing);
    expect(find.text('Doktor Klinik Protokolü'), findsOneWidget);
    expect(tester.state(find.byType(SyntheticVideoStudioScreen)), same(state));
    expect(tester.widget<Text>(find.byKey(const ValueKey('studio-template-source'))).data,
      contains('Hazır şablon; model çıkarımı yapılmadı'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}