import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/services/local_llama_test_service.dart';
import 'package:neuro_awareness_app/widgets/local_llama_test_card.dart';

import 'support/fake_local_llama_runtime.dart';

void main() {
  Future<LocalLlamaTestService> prepare(
    WidgetTester tester,
    FakeLocalLlamaRuntime runtime, {
    bool missing = false,
    bool enabled = true,
    double scale = 1,
    LocalLlamaTestRequest request = LocalLlamaTestRequest.greeting,
  }) async {
    // Dosya yalnızca fake sınırından geçer; gerçek native/model testi değildir.
    final temp = await tester.runAsync(
      () => Directory('.dart_tool').createTemp('llama_card_check_'),
    );
    final file = File('${temp!.path}/unit_test_only.gguf');
    if (!missing) {
      await tester.runAsync(() => file.writeAsString('UNIT TEST ONLY'));
    }
    final service = LocalLlamaTestService(
      request: request,
      resolveModel: () async => file,
      createRuntime: (_) => runtime,
    );
    addTearDown(() async {
      await service.dispose();
      expect(temp.absolute.parent.path, Directory('.dart_tool').absolute.path);
      await temp.delete(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: LocalLlamaTestCard(service: service, enabled: enabled),
          ),
        ),
      ),
    );
    return service;
  }

  testWidgets(
    'Yükleniyor ve üretiliyor görünür; ikinci istek kilitlenir; gerçek akış alanı gösterilir',
    (tester) async {
      final stream = StreamController<String>(sync: true);
      final runtime = FakeLocalLlamaRuntime()
        ..loadGate = Completer<void>.sync()
        ..output = () => stream.stream;
      final service = await prepare(tester, runtime);
      // IO'nun tamamlanmasını gerçek async alanında bekleriz; native çağrı yoktur.
      late Future<void> running;
      await tester.runAsync(() async {
        running = service.run();
        await runtime.loadStarted.future;
      });
      await tester.pump();
      expect(find.text('Model yükleniyor'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('local-llama-test-start')),
            )
            .onPressed,
        isNull,
      );
      await tester.runAsync(() async {
        runtime.loadGate!.complete();
        await runtime.generationStarted.future;
      });
      await tester.pump();
      expect(find.text('Metin üretiliyor'), findsOneWidget);
      await tester.runAsync(() async {
        stream.add('TEST YANITI');
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(find.text('TEST YANITI'), findsOneWidget);
      await tester.runAsync(() async {
        await stream.close();
        await running;
      });
      await tester.pumpAndSettle();
      expect(find.text('Tamamlandı'), findsOneWidget);
      expect(find.text('Model cevabı'), findsOneWidget);
      expect(find.textContaining('Toplam:'), findsOneWidget);
      expect(runtime.disposals, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Eksik model düğmeden hata gösterir, sahte başarı göstermez', (
    tester,
  ) async {
    final service = await prepare(
      tester,
      FakeLocalLlamaRuntime(),
      missing: true,
    );
    await tester.runAsync(() async {
      final failed = service.states.firstWhere(
        (s) => s.phase == LocalLlamaPhase.error,
      );
      await tester.tap(find.byKey(const ValueKey('local-llama-test-start')));
      await failed;
    });
    await tester.pumpAndSettle();
    expect(service.state.phase, LocalLlamaPhase.error);
    expect(find.textContaining('Model indirilmedi'), findsOneWidget);
    expect(find.text('Model cevabı'), findsNothing);
    expect(find.text('Tamamlandı'), findsNothing);
  });

  testWidgets('İptal düğmesi yükleme bitene kadar kilidi korur', (
    tester,
  ) async {
    final runtime = FakeLocalLlamaRuntime()..loadGate = Completer<void>.sync();
    final service = await prepare(tester, runtime);
    late Future<void> running;
    await tester.runAsync(() async {
      running = service.run();
      await runtime.loadStarted.future;
    });
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('local-llama-test-cancel')));
    await tester.pump();
    expect(find.text('İptal bekleniyor'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('local-llama-test-start')),
          )
          .onPressed,
      isNull,
    );
    await tester.runAsync(() async {
      runtime.loadGate!.complete();
      await running;
    });
    await tester.pumpAndSettle();
    expect(find.text('İptal edildi'), findsOneWidget);
    expect(runtime.generations, 0);
    expect(find.text('Tamamlandı'), findsNothing);
  });

  testWidgets(
    'D01 düğmesi ayrı istekle ham cevabı, süreyi ve taslak bilgisini gösterir',
    (tester) async {
      final runtime = FakeLocalLlamaRuntime()
        ..output = () => Stream.value('TEST: ham model metni\nİki alternatif.');
      final service = await prepare(
        tester,
        runtime,
        request: LocalLlamaTestRequest.d01,
      );
      expect(find.text('D01 senaryo testi'), findsOneWidget);
      expect(
        find.textContaining('Planlanan alternatif senaryo taslağı'),
        findsOneWidget,
      );
      expect(
        find.text('CPU · 2048 token bağlam · En fazla 384 yeni token'),
        findsOneWidget,
      );
      await tester.runAsync(() async {
        final done = service.states.firstWhere(
          (s) => s.phase == LocalLlamaPhase.completed,
        );
        await tester.tap(find.byKey(const ValueKey('d01-scenario-test-start')));
        await done;
      });
      await tester.pumpAndSettle();
      expect(
        find.text('TEST: ham model metni\nİki alternatif.'),
        findsOneWidget,
      );
      expect(find.textContaining('Toplam:'), findsOneWidget);
      expect(find.text('Tamamlandı'), findsOneWidget);
      await tester.tap(find.text('Modele gönderilen istek'));
      await tester.pumpAndSettle();
      expect(find.text(LocalLlamaTestRequest.d01.prompt), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'D01 üretim hatası açıkça görünür; şablon veya başarı gösterilmez',
    (tester) async {
      final runtime = FakeLocalLlamaRuntime()
        ..generationError = StateError('test: D01 üretimi başarısız');
      final service = await prepare(
        tester,
        runtime,
        request: LocalLlamaTestRequest.d01,
      );
      await tester.runAsync(() async {
        final failed = service.states.firstWhere(
          (s) => s.phase == LocalLlamaPhase.error,
        );
        await tester.tap(find.byKey(const ValueKey('d01-scenario-test-start')));
        await failed;
      });
      await tester.pumpAndSettle();
      expect(
        find.textContaining('test: D01 üretimi başarısız'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('d01-scenario-test-response')),
        findsNothing,
      );
      expect(find.text('Tamamlandı'), findsNothing);
    },
  );

  testWidgets('D01 kartı dar ekranda büyük yazıyla kaydırılır', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await prepare(
      tester,
      FakeLocalLlamaRuntime(),
      request: LocalLlamaTestRequest.d01,
      scale: 2,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('d01-scenario-test-start')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'D01 ayrıntıları ölçümleri ve sınırda durmayı gösterir; cevap korunur',
    (tester) async {
      const raw = '  TEST: ham çıktı  ';
      final runtime = FakeLocalLlamaRuntime()
        ..diagnosticValues = {
          'API bitiş nedeni': 'length',
          'Native istek tokenı': 'TEST SAYIMI',
        }
        ..output = () => Stream.value(raw);
      final service = await prepare(
        tester,
        runtime,
        request: LocalLlamaTestRequest.d01,
      );
      await tester.runAsync(() async {
        final done = service.states.firstWhere(
          (s) => s.phase == LocalLlamaPhase.completed,
        );
        await tester.tap(find.byKey(const ValueKey('d01-scenario-test-start')));
        await done;
      });
      await tester.pumpAndSettle();
      expect(find.text(raw), findsOneWidget);
      await tester.ensureVisible(find.text('Çıkarım ayrıntıları'));
      await tester.tap(find.text('Çıkarım ayrıntıları'));
      await tester.pumpAndSettle();
      expect(find.text('TEST SAYIMI'), findsOneWidget);
      expect(
        find.textContaining('Motor token veya bağlam sınırında durdu'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'İngilizce D01 ayrı başlık, istek ve değişmemiş ham cevap gösterir',
    (tester) async {
      const raw = '  TEST: Beginning\nAlternative A\nAlternative B  ';
      final runtime = FakeLocalLlamaRuntime()..output = () => Stream.value(raw);
      final service = await prepare(
        tester,
        runtime,
        request: LocalLlamaTestRequest.d01English,
      );
      expect(find.text('D01 İngilizce karşılaştırma'), findsOneWidget);
      expect(find.text('D01 İngilizce dene'), findsOneWidget);
      await tester.runAsync(() async {
        final done = service.states.firstWhere(
          (s) => s.phase == LocalLlamaPhase.completed,
        );
        await tester.tap(find.byKey(const ValueKey('d01-english-test-start')));
        await done;
      });
      await tester.pumpAndSettle();
      expect(find.text(raw), findsOneWidget);
      await tester.ensureVisible(find.text('Modele gönderilen istek'));
      await tester.tap(find.text('Modele gönderilen istek'));
      await tester.pumpAndSettle();
      expect(
        find.text(LocalLlamaTestRequest.d01English.prompt),
        findsOneWidget,
      );
      expect(find.textContaining('Toplam:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Qwen kartı model kimliği, önerilen örnekleme ve ham cevabı gösterir',
    (tester) async {
      const raw = '  TEST: {"bozuk": "ham cevap"}  ';
      final runtime = FakeLocalLlamaRuntime()
        ..diagnosticValues = {'API bitiş nedeni': 'stop'}
        ..output = () => Stream.value(raw);
      final service = await prepare(
        tester,
        runtime,
        request: LocalLlamaTestRequest.d01Qwen,
      );
      expect(find.text('Qwen D01 karşılaştırma'), findsOneWidget);
      expect(find.text('unsloth/Qwen3-1.7B-GGUF'), findsOneWidget);
      expect(find.textContaining('sıcaklık 0.7'), findsOneWidget);
      await tester.runAsync(() async {
        final done = service.states.firstWhere(
          (s) => s.phase == LocalLlamaPhase.completed,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('d01-qwen3-test-start')),
        );
        await tester.tap(find.byKey(const ValueKey('d01-qwen3-test-start')));
        await done;
      });
      await tester.pumpAndSettle();
      expect(find.text(raw), findsOneWidget);
      expect(find.text('API bitiş nedeni: stop'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('İndirme sürerken test düğmesi devre dışıdır', (tester) async {
    final runtime = FakeLocalLlamaRuntime();
    await prepare(tester, runtime, enabled: false);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('local-llama-test-start')),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('indirmesinin bitmesini'), findsOneWidget);
    expect(runtime.path, isNull);
  });

  testWidgets('Dar ekranda iki kat yazı ile test kartı taşmadan kaydırılır', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await prepare(tester, FakeLocalLlamaRuntime(), scale: 2);
    await tester.ensureVisible(
      find.byKey(const ValueKey('local-llama-test-start')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
