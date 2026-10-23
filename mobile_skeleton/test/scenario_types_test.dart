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

  testWidgets('Normal örnek, açık ekip araçları ve yerel model araçları yoktur; beş dokunuş admin açmaz',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: const SyntheticVideoStudioScreen()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('open-d01-playback')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-scenario-graph')), findsOneWidget);
    expect(find.byKey(const ValueKey('studio-content-preparation')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-scenario-content')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-clip-production-plan')), findsOneWidget);
    expect(find.byKey(const ValueKey('studio-technical-tests'), skipOffstage: false), findsNothing);
    expect(find.text('Eski şablon araçları'), findsNothing);
    expect(find.text('Normal (Tipik)'), findsNothing);

    final title = find.descendant(of: find.byType(AppBar),
        matching: find.text('Simülasyon ve Eğitim'));
    for (var i = 0; i < 5; i++) {
      await tester.tap(title);
      await tester.pump();
    }
    expect(find.text('ADMİN'), findsNothing);
    expect(find.text('Tür 1: Doktor Protokolü'), findsNothing);
    expect(find.text('Tür 2: Video Stüdyosu'), findsNothing);
    expect(find.text('Saniyelik Klip Dilimleme & Prompt Ayarları (Admin)'), findsNothing);
    expect(find.byKey(const ValueKey('studio-technical-tests'), skipOffstage: false), findsNothing);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
