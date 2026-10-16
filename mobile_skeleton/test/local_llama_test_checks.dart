import 'dart:async';
import 'dart:io';

import 'package:neuro_awareness_app/services/local_llama_test_service.dart';

import 'support/fake_local_llama_runtime.dart';

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

Future<void> rejects(Future<void> future) async {
  try {
    await future;
  } on StateError {
    return;
  }
  throw StateError('İkinci istek reddedilmeliydi');
}

Future<void> main() async {
  final temp = await Directory('.dart_tool').createTemp('local_llama_check_');
  final file = await File('${temp.path}/test_boundary_only.gguf')
      .writeAsString('UNIT TEST ONLY');
  LocalLlamaTestService service(FakeLocalLlamaRuntime runtime) =>
      LocalLlamaTestService(
        resolveModel: () async => file,
        createRuntime: (_) => runtime,
      );
  final tests = <String, Future<void> Function()>{
    'Türkçe ve İngilizce D01 cevapları ayrıdır ve ortak native kilidi korur':
        () async {
          final trRuntime = FakeLocalLlamaRuntime()
            ..loadGate = Completer<void>()
            ..output = () => Stream.value('  TEST: Türkçe ham cevap  ');
          final enRuntime = FakeLocalLlamaRuntime()
            ..output = () => Stream.value('  TEST: raw English response  ');
          final tr = LocalLlamaTestService(
            request: LocalLlamaTestRequest.d01,
            resolveModel: () async => file,
            createRuntime: (_) => trRuntime,
          );
          final en = LocalLlamaTestService(
            request: LocalLlamaTestRequest.d01English,
            resolveModel: () async => file,
            createRuntime: (_) => enRuntime,
          );
          final running = tr.run();
          await trRuntime.loadStarted.future;
          await rejects(en.run());
          check(enRuntime.path == null, 'İngilizce motor eşzamanlı açılmaz');
          trRuntime.loadGate!.complete();
          await running;
          await en.run();
          check(
            tr.state.text == '  TEST: Türkçe ham cevap  ',
            'Türkçe çıktı değiştirilmez',
          );
          check(
            en.state.text == '  TEST: raw English response  ',
            'İngilizce çıktı ayrı korunur',
          );
          check(
            enRuntime.path == trRuntime.path,
            'Aynı yerel model kullanılır',
          );
          await tr.dispose();
          await en.dispose();
        },
    'Ölçümler kapanışta korunur, yeni denemede önceki değerler taşınmaz':
        () async {
          var attempt = 0;
          final s = LocalLlamaTestService(
            request: LocalLlamaTestRequest.d01,
            resolveModel: () async => file,
            createRuntime: (_) => FakeLocalLlamaRuntime()
              ..diagnosticValues = attempt++ == 0
                  ? const {'API bitiş nedeni': 'length'}
                  : const {},
          );
          await s.run();
          check(
            s.state.diagnostics['API bitiş nedeni'] == 'length',
            'Kapatılan runtime ölçümleri korunur',
          );
          await s.run();
          check(
            s.state.diagnostics.isEmpty,
            'Önceki ölçüm yeni denemeye aitmiş gibi taşınmaz',
          );
          await s.dispose();
        },
    'D01 isteği aynı yerel yola ve doğru runtime yapılandırmasına aktarılır':
        () async {
          LocalLlamaTestRequest? received;
          final runtime = FakeLocalLlamaRuntime();
          final s = LocalLlamaTestService(
            request: LocalLlamaTestRequest.d01,
            resolveModel: () async => file,
            createRuntime: (request) {
              received = request;
              return runtime;
            },
          );
          await s.run();
          check(
            identical(received, LocalLlamaTestRequest.d01),
            'Seçilen istek değiştirilmeden aktarılır',
          );
          check(
            runtime.path == file.path &&
                s.state.phase == LocalLlamaPhase.completed,
            'Aynı dosya, normal yaşam döngüsü',
          );
          await s.dispose();
        },
    'Merhaba çalışırken D01 ikinci bir native model açamaz': () async {
      final helloRuntime = FakeLocalLlamaRuntime()
        ..loadGate = Completer<void>();
      final hello = service(helloRuntime);
      final d01Runtime = FakeLocalLlamaRuntime();
      final d01 = LocalLlamaTestService(
        request: LocalLlamaTestRequest.d01,
        resolveModel: () async => file,
        createRuntime: (_) => d01Runtime,
      );
      final running = hello.run();
      await helloRuntime.loadStarted.future;
      await rejects(d01.run());
      check(
        d01Runtime.path == null && !d01.canRun,
        'D01 motoru açılmadan kilitlenir',
      );
      helloRuntime.loadGate!.complete();
      await running;
      check(d01.canRun, 'Merhaba temizlenince D01 çalışabilir');
      await d01.run();
      await hello.dispose();
      await d01.dispose();
    },
    'Eksik dosya hata verir ve native motoru oluşturmaz': () async {
      var created = false;
      final s = LocalLlamaTestService(
        resolveModel: () async => File('${temp.path}/missing.gguf'),
        createRuntime: (_) {
          created = true;
          return FakeLocalLlamaRuntime();
        },
      );
      await s.run();
      check(
        s.state.phase == LocalLlamaPhase.error &&
            s.state.error!.contains('Model indirilmedi'),
        'Eksik model',
      );
      check(!created, 'Model yokken native motor açılmamalı');
      await s.dispose();
    },
    'Yerel yol, akış metni, süre ve başarıdan önce kapatma korunur': () async {
      final runtime = FakeLocalLlamaRuntime();
      final s = service(runtime);
      final phases = <LocalLlamaPhase>[];
      final sub = s.states.listen((v) => phases.add(v.phase));
      await s.run();
      await Future<void>.delayed(Duration.zero);
      check(runtime.path == file.path, 'Aynı yerel dosya yolu');
      check(
        s.state.text == 'TEST ÇIKTISI' &&
            s.state.phase == LocalLlamaPhase.completed,
        'Akış birleştirilir',
      );
      check(
        phases.first == LocalLlamaPhase.loading &&
            phases.contains(LocalLlamaPhase.generating) &&
            phases[phases.length - 2] == LocalLlamaPhase.closing,
        'Durum sırası',
      );
      check(runtime.disposals == 1, 'Kaynaklar bir kez kapatılır');
      check(
        s.state.elapsed >= s.state.generationElapsed,
        'Toplam süre üretimi kapsar',
      );
      await sub.cancel();
      await s.dispose();
    },
    'Yükleme hatası gösterilir, üretime geçilmez, kaynaklar kapanır': () async {
      final runtime = FakeLocalLlamaRuntime()
        ..loadError = StateError('GGUF açılamadı');
      final s = service(runtime);
      await s.run();
      check(
        s.state.phase == LocalLlamaPhase.error &&
            s.state.error!.contains('GGUF açılamadı'),
        'Asıl hata korunur',
      );
      check(
        runtime.generations == 0 && runtime.disposals == 1,
        'Yükleme hatası temizlenir',
      );
      await s.dispose();
    },
    'Üretim hatasında kısmi metin korunur, başarı veya fallback üretilmez':
        () async {
          final runtime = FakeLocalLlamaRuntime()
            ..output = () async* {
              yield 'KISMİ TEST';
              throw StateError('decode hatası');
            };
          final s = service(runtime);
          await s.run();
          check(
            s.state.phase == LocalLlamaPhase.error &&
                s.state.text == 'KISMİ TEST' &&
                s.state.error!.contains('decode hatası'),
            'Hata ve kısmi çıktı',
          );
          await s.dispose();
        },
    'Boş çıktı başarı sayılmaz': () async {
      final runtime = FakeLocalLlamaRuntime()
        ..output = () => Stream.value('  ');
      final s = service(runtime);
      await s.run();
      check(
        s.state.phase == LocalLlamaPhase.error &&
            s.state.error!.contains('boş cevap'),
        'Boş metin',
      );
      await s.dispose();
    },
    'Dosya beklerken iptal edilirse model açılmaz': () async {
      final gate = Completer<File>();
      var created = false;
      final s = LocalLlamaTestService(
        resolveModel: () => gate.future,
        createRuntime: (_) {
          created = true;
          return FakeLocalLlamaRuntime();
        },
      );
      final running = s.run();
      s.cancel();
      check(s.state.isBusy, 'İptal tamamlanmış sayılmaz');
      gate.complete(file);
      await running;
      check(
        !created && s.state.phase == LocalLlamaPhase.cancelled,
        'İptal üretimi atlar',
      );
      await s.dispose();
    },
    'Yükleme iptali yüklemenin bitmesini ve kapatmayı bekler': () async {
      final runtime = FakeLocalLlamaRuntime()..loadGate = Completer<void>();
      final s = service(runtime);
      final running = s.run();
      await runtime.loadStarted.future;
      s.cancel();
      check(
        s.state.phase == LocalLlamaPhase.cancelling && runtime.disposals == 0,
        'Erken serbest bırakılmaz',
      );
      runtime.loadGate!.complete();
      await running;
      check(
        runtime.generations == 0 &&
            runtime.disposals == 1 &&
            s.state.phase == LocalLlamaPhase.cancelled,
        'Yükleme sonrası kapanır',
      );
      await s.dispose();
    },
    'Üretim iptali native iptali çağırır ve tamamlandı göstermez': () async {
      final stream = StreamController<String>();
      final runtime = FakeLocalLlamaRuntime()..output = () => stream.stream;
      runtime.onCancel = () => unawaited(stream.close());
      final s = service(runtime);
      final generating = s.states.firstWhere(
        (v) => v.phase == LocalLlamaPhase.generating,
      );
      final running = s.run();
      await generating;
      s.cancel();
      await running;
      check(
        runtime.cancellations == 1 &&
            s.state.phase == LocalLlamaPhase.cancelled &&
            runtime.disposals == 1,
        'Native iptal ve temizleme',
      );
      await s.dispose();
    },
    'Aynı ve farklı servislerde ikinci eşzamanlı istek reddedilir': () async {
      final runtime = FakeLocalLlamaRuntime()..loadGate = Completer<void>();
      final s = service(runtime);
      final other = service(FakeLocalLlamaRuntime());
      final running = s.run();
      await runtime.loadStarted.future;
      await rejects(s.run());
      await rejects(other.run());
      runtime.loadGate!.complete();
      await running;
      await other.run();
      check(
        other.state.phase == LocalLlamaPhase.completed,
        'Kilit kapanınca açılır',
      );
      await s.dispose();
      await other.dispose();
    },
    'Kapatma bitene kadar başarı gösterilmez ve yeni istek kilitlidir':
        () async {
          final runtime = FakeLocalLlamaRuntime()
            ..disposeGate = Completer<void>();
          final s = service(runtime);
          final running = s.run();
          await runtime.disposeStarted.future;
          check(
            s.state.phase == LocalLlamaPhase.closing && s.state.isBusy,
            'Kaynak kapatma da meşguldür',
          );
          await rejects(s.run());
          runtime.disposeGate!.complete();
          await running;
          check(
            s.state.phase == LocalLlamaPhase.completed,
            'Kapatma sonrası tamamlanır',
          );
          await s.dispose();
        },
    'Ekrandan ayrılma yükleme ve native temizlemeyi bekler; dispose tekrarı güvenlidir':
        () async {
          final runtime = FakeLocalLlamaRuntime()..loadGate = Completer<void>();
          final s = service(runtime);
          final running = s.run();
          await runtime.loadStarted.future;
          var closed = false;
          final closing = s.dispose().then((_) => closed = true);
          await Future<void>.delayed(Duration.zero);
          check(!closed, 'Yükleme sürerken dispose tamamlanmaz');
          runtime.loadGate!.complete();
          await running;
          await closing;
          await s.dispose();
          check(
            runtime.disposals == 1 && runtime.generations == 0,
            'Tek kapanış, üretim yok',
          );
          await rejects(s.run());
        },
    'Hatalı deneme sonrası yeni deneme temiz durumla başlar': () async {
      var attempt = 0;
      final s = LocalLlamaTestService(
        resolveModel: () async => file,
        createRuntime: (_) => attempt++ == 0
            ? (FakeLocalLlamaRuntime()..loadError = StateError('ilk hata'))
            : FakeLocalLlamaRuntime(),
      );
      await s.run();
      await s.run();
      check(
        s.state.phase == LocalLlamaPhase.completed &&
            s.state.error == null &&
            s.state.text == 'TEST ÇIKTISI',
        'Hata sıfırlanır',
      );
      await s.dispose();
    },
    // En son: başarısız native kapatma süreç kilidini bilinçli olarak korur.
    'Native kapatma hatasında hata gösterilir ve yeniden yükleme engellenir':
        () async {
          final runtime = FakeLocalLlamaRuntime()
            ..disposeError = StateError('native close');
          final s = service(runtime);
          await s.run();
          check(
            s.state.phase == LocalLlamaPhase.error &&
                s.state.error!.contains('Kaynaklar kapatılamadı'),
            'Temizlik hatası görünür',
          );
          await rejects(s.run());
          await s.dispose();
        },
  };
  var failures = 0;
  try {
    for (final test in tests.entries) {
      try {
        await test.value();
        stdout.writeln('PASS: ${test.key}');
      } catch (e, st) {
        failures++;
        stderr.writeln('FAIL: ${test.key}\n$e\n$st');
      }
    }
  } finally {
    // Yalnızca bu testin .dart_tool altında oluşturduğu dizin temizlenir.
    check(
      temp.absolute.parent.path == Directory('.dart_tool').absolute.path,
      'Test dizini sınırı',
    );
    await temp.delete(recursive: true);
  }
  stdout.writeln(
    '${tests.length - failures}/${tests.length} servis testi geçti.',
  );
  if (failures > 0) exitCode = 1;
}
