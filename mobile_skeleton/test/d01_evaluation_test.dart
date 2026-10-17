import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/models/local_model_option.dart';
import 'package:neuro_awareness_app/services/d01_evaluation_service.dart';
import 'package:neuro_awareness_app/services/local_llama_test_service.dart';

import 'support/fake_local_llama_runtime.dart';

void main() {
  Future<({Directory temp, Directory records, File model})> setup() async {
    final temp = await Directory('.dart_tool').createTemp('d01_eval_test_');
    final model = await File('${temp.path}/test_only.gguf')
        .writeAsString('UNIT TEST ONLY');
    addTearDown(() async {
      expect(temp.absolute.parent.path, Directory('.dart_tool').absolute.path);
      await temp.delete(recursive: true);
    });
    return (
      temp: temp,
      records: Directory('${temp.path}/records'),
      model: model,
    );
  }

  Future<String> plan() =>
      File('assets/evaluations/d01_qwen_v1.json').readAsString();

  test('MiniCPM seçimi altı sabit istemi, ayarları ve ham kayıtları doğru modele bağlar', () async {
    final env = await setup();
    final originalPlan = await plan();
    final protocol = D01EvaluationProtocol.parse(originalPlan);
    final requests = <LocalLlamaTestRequest>[];
    final resolved = <LocalModelOption>[];
    const raw = '  TEST: <think></think> {"istenmeyen": "ham cevap"}\n';
    final service = D01EvaluationService(
      loadProtocol: () async => originalPlan,
      resolveRecordsRoot: () async => env.records,
      resolveModel: (model) async {
        resolved.add(model);
        return env.model;
      },
      executionSource: 'test_double',
      createRuntime: (request) {
        requests.add(request);
        return FakeLocalLlamaRuntime()
          ..diagnosticValues = {
            'API bitiş nedeni': 'length',
            'Native üretilen token': '160',
          }
          ..output = () => Stream.value(raw);
      },
    );
    addTearDown(service.dispose);
    await service.run(model: LocalModelOption.miniCpmTurkish);
    expect(resolved, [LocalModelOption.miniCpmTurkish]);
    expect(requests, hasLength(6));
    for (var i = 0; i < 6; i++) {
      final request = requests[i];
      expect(request.model, LocalModelOption.miniCpmTurkish);
      expect(request.prompt, protocol.tasks[i ~/ 2].prompt);
      expect(request.contextSize, 2048);
      expect(request.maxTokens, 160);
      final record = service.records[i];
      expect(record['model_id'], LocalModelOption.miniCpmTurkish.id);
      expect(record['model_file'], LocalModelOption.miniCpmTurkish.fileName);
      expect(record['settings'], D01EvaluationProtocol.settings);
      expect(record['raw_response'], raw);
      expect(record['completion_tokens'], 160);
      expect(record['finish_reason'], 'length');
      expect((record['human_evaluation'] as Map).values, everyElement(isNull));
    }
    final firstRun = env.records.listSync().single as Directory;
    final before = File('${firstRun.path}/common_start_1.json')
        .readAsBytesSync();
    await service.run(); // Önceki Qwen yolu da ayrı çalışma olarak korunur.
    expect(resolved.last, LocalModelOption.qwen3);
    expect(service.records.first['model_id'], LocalModelOption.qwen3.id);
    expect(env.records.listSync(), hasLength(2));
    expect(
      File('${firstRun.path}/common_start_1.json').readAsBytesSync(),
      before,
    );
    expect(await plan(), originalPlan);
  });

  test('Sabit plan önce kaydedilir; altı temiz deneme ham metni, ölçümleri ve boş değerlendirmeyi korur', () async {
    final env = await setup();
    final requests = <LocalLlamaTestRequest>[];
    final runtimes = <FakeLocalLlamaRuntime>[];
    var loads = 0;
    const raw = '  TEST: {"success": true, "sahne": "bozuk cevap"}\n  ';
    final service = D01EvaluationService(
      loadProtocol: () {
        loads++;
        return plan();
      },
      resolveRecordsRoot: () async => env.records,
      resolveModel: (_) async => env.model,
      executionSource: 'test_double',
      createRuntime: (request) {
        final run = env.records.listSync().single as Directory;
        final snapshot = jsonDecode(
          File('${run.path}/protocol.json').readAsStringSync(),
        ) as Map;
        expect(snapshot['tasks'], hasLength(3));
        expect(run.listSync().whereType<File>(), hasLength(7));
        requests.add(request);
        final runtime = FakeLocalLlamaRuntime()
          ..diagnosticValues = {
            'API bitiş nedeni': 'stop',
            'Native istek tokenı': '121',
            'Native üretilen token': '32',
            'Native önbellekten token': '0',
            'Model dosyası': env.model.absolute.path,
          }
          ..output = () => Stream.value(raw);
        runtimes.add(runtime);
        return runtime;
      },
    );
    await service.run();
    expect(loads, 1);
    expect(service.state.error, isNull);
    expect(service.state.attempted, 6);
    expect(requests.map((r) => r.id), [
      'd01-evaluation-common_start',
      'd01-evaluation-common_start',
      'd01-evaluation-turn_to_mother',
      'd01-evaluation-turn_to_mother',
      'd01-evaluation-continue_playing',
      'd01-evaluation-continue_playing',
    ]);
    expect(runtimes.toSet(), hasLength(6));
    expect(
      runtimes.every((r) => r.disposals == 1 && r.generations == 1),
      isTrue,
    );
    for (var i = 0; i < 6; i++) {
      expect(requests[i].model, LocalModelOption.qwen3);
      expect(requests[i].contextSize, 2048);
      expect(requests[i].maxTokens, 160);
      if (i.isOdd) expect(requests[i].prompt, requests[i - 1].prompt);
      final record = service.records[i];
      expect(record['raw_response'], raw);
      expect(record['prompt'], requests[i].prompt);
      expect(record['prompt_tokens'], 121);
      expect(record['completion_tokens'], 32);
      expect(record['finish_reason'], 'stop');
      expect(record['elapsed_s'], isA<double>());
      expect(record['human_evaluation'], {
        for (final name in D01EvaluationProtocol.humanFields) name: null,
      });
      expect(record['execution_source'], 'test_double');
      final run = env.records.listSync().single as Directory;
      expect(
        jsonDecode(
          File('${run.path}/${record['attempt_id']}.json').readAsStringSync(),
        ),
        record,
      );
    }
    final export = service.exportJson();
    expect(
      jsonDecode(export).toString(),
      isNot(contains(env.model.absolute.path)),
    );
    expect(
      jsonDecode(export).toString(),
      isNot(contains(env.records.absolute.path)),
    );
    expect(jsonDecode(export)['evaluation_status'], 'human_review_pending');
    await service.dispose();
  });

  test('Teknik hatanın kısmi cevabı değiştirilmez; plan dışı retry veya yol dışa aktarımı yoktur', () async {
    final env = await setup();
    var created = 0;
    final service = D01EvaluationService(
      loadProtocol: plan,
      resolveRecordsRoot: () async => env.records,
      resolveModel: (_) async => env.model,
      executionSource: 'test_double',
      createRuntime: (_) {
        final index = created++;
        return FakeLocalLlamaRuntime()
          ..output = () async* {
            yield 'TEST: partial $index';
            if (index == 2) throw StateError('TEST error ${env.model.path}');
          };
      },
    );
    await service.run();
    expect(created, 6);
    expect(service.records[2]['execution_status'], 'error');
    expect(service.records[2]['raw_response'], 'TEST: partial 2');
    expect(service.records[2]['prompt_tokens'], isNull);
    expect(service.records[2]['finish_reason'], isNull);
    expect(
      jsonDecode(service.exportJson()).toString(),
      isNot(contains(env.model.path)),
    );
    expect(service.records[2]['error'], contains('[yerel_yol]'));
    await service.dispose();
  });

  test('İptal kalan denemeleri pending bırakır ve ikinci değerlendirme aynı anda başlamaz', () async {
    final env = await setup();
    final runtime = FakeLocalLlamaRuntime()..loadGate = Completer<void>();
    var created = 0;
    final service = D01EvaluationService(
      loadProtocol: plan,
      resolveRecordsRoot: () async => env.records,
      resolveModel: (_) async => env.model,
      executionSource: 'test_double',
      createRuntime: (_) {
        created++;
        return runtime;
      },
    );
    final running = service.run();
    await runtime.loadStarted.future;
    expect(() => service.run(), throwsStateError);
    service.cancel();
    runtime.loadGate!.complete();
    await running;
    expect(created, 1);
    expect(runtime.disposals, 1);
    expect(service.records.first['execution_status'], 'cancelled');
    expect(
      service.records
          .skip(1)
          .every(
            (r) =>
                r['execution_status'] == 'pending' && r['raw_response'] == null,
          ),
      isTrue,
    );
    await service.dispose();
  });

  test('Eksik modelde sahte sonuç veya otomatik indirme yerine plan ve açık hata kalır', () async {
    final env = await setup();
    var created = 0;
    final service = D01EvaluationService(
      loadProtocol: plan,
      resolveRecordsRoot: () async => env.records,
      resolveModel: (_) async => File('${env.temp.path}/missing.gguf'),
      executionSource: 'test_double',
      createRuntime: (_) {
        created++;
        return FakeLocalLlamaRuntime();
      },
    );
    await service.run();
    expect(created, 0);
    expect(service.state.error, contains('Model indirilmedi'));
    expect(service.records, hasLength(6));
    expect(
      service.records.every(
        (r) => r['raw_response'] == null && r['execution_status'] == 'pending',
      ),
      isTrue,
    );
    await service.dispose();
  });

  test(
    'Yeni değerlendirme ayrı klasöre gider; önceki kayıtlar üzerine yazılmaz',
    () async {
      final env = await setup();
      final service = D01EvaluationService(
        loadProtocol: plan,
        resolveRecordsRoot: () async => env.records,
        resolveModel: (_) async => env.model,
        executionSource: 'test_double',
        createRuntime: (_) => FakeLocalLlamaRuntime(),
      );
      await service.run();
      final first = env.records.listSync().single as Directory;
      final original = File('${first.path}/common_start_1.json')
          .readAsBytesSync();
      await service.run();
      expect(env.records.listSync(), hasLength(2));
      expect(
        File('${first.path}/common_start_1.json').readAsBytesSync(),
        original,
      );
      await service.dispose();
    },
  );

  test(
    'Plan diske yazılamıyorsa kayıtsız model çıkarımı başlatılmaz',
    () async {
      final env = await setup();
      final blocked = await File('${env.temp.path}/not_a_directory')
          .writeAsString('TEST');
      var created = 0;
      final service = D01EvaluationService(
        loadProtocol: plan,
        resolveRecordsRoot: () async => Directory(blocked.path),
        resolveModel: (_) async => env.model,
        executionSource: 'test_double',
        createRuntime: (_) {
          created++;
          return FakeLocalLlamaRuntime();
        },
      );
      await service.run();
      expect(created, 0);
      expect(service.state.error, isNotNull);
      expect(service.canExport, isFalse);
      await service.dispose();
    },
  );

  test('Plan geçersizse çıkarım ve kayıt oluşturma başlamaz', () async {
    final env = await setup();
    var created = 0;
    final service = D01EvaluationService(
      loadProtocol: () async => '{}',
      resolveRecordsRoot: () async => env.records,
      resolveModel: (_) async => env.model,
      executionSource: 'test_double',
      createRuntime: (_) {
        created++;
        return FakeLocalLlamaRuntime();
      },
    );
    await service.run();
    expect(created, 0);
    expect(service.state.error, contains('planı okunamadı'));
    expect(await env.records.exists(), isFalse);
    await service.dispose();
  });
}
