import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/local_model_option.dart';
import 'local_llama_test_service.dart';

class D01EvaluationTask {
  const D01EvaluationTask(this.id, this.title, this.prompt);
  final String id;
  final String title;
  final String prompt;

  LocalLlamaTestRequest get request => requestFor(LocalModelOption.qwen3);

  LocalLlamaTestRequest requestFor(LocalModelOption model) =>
      LocalLlamaTestRequest(
        id: 'd01-evaluation-$id',
        title: title,
        actionLabel: '',
        description: 'İnsan değerlendirmesi bekleyen planlı sahne taslağı.',
        prompt: prompt,
        contextSize: 2048,
        maxTokens: 160,
        model: model,
      );
}

class D01EvaluationProtocol {
  D01EvaluationProtocol._(this.id, List<D01EvaluationTask> tasks)
    : tasks = List.unmodifiable(tasks);

  factory D01EvaluationProtocol.parse(String source) {
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic> ||
        value['schema_version'] != '1.0' ||
        value['protocol_id'] is! String ||
        (value['protocol_id'] as String).trim().isEmpty ||
        value['tasks'] is! List ||
        (value['tasks'] as List).length != 3) {
      throw const FormatException('D01 değerlendirme planı okunamadı.');
    }
    final tasks = <D01EvaluationTask>[];
    for (final task in value['tasks'] as List) {
      if (task is! Map<String, dynamic> ||
          ['id', 'title', 'prompt'].any(
            (k) => task[k] is! String || (task[k] as String).trim().isEmpty,
          )) {
        throw const FormatException(
          'Her görev kimlik, başlık ve tam istem içermelidir.',
        );
      }
      tasks.add(
        D01EvaluationTask(
          task['id'] as String,
          task['title'] as String,
          task['prompt'] as String,
        ),
      );
    }
    if (tasks.map((t) => t.id).join(',') !=
        'common_start,turn_to_mother,continue_playing') {
      throw const FormatException(
        'Üç D01 görevi beklenen sırada ve benzersiz olmalıdır.',
      );
    }
    return D01EvaluationProtocol._(value['protocol_id'] as String, tasks);
  }

  final String id;
  final List<D01EvaluationTask> tasks;
  static const settings = {
    'device': 'cpu',
    'gpu_layers': 0,
    'context_tokens': 2048,
    'max_output_tokens': 160,
    'enable_thinking': false,
    'temperature': 0.7,
    'top_p': 0.8,
    'top_k': 20,
    'min_p': 0.0,
    'repeat_penalty': 1.0,
    'presence_penalty': 0.0,
    'seed': null,
    'reuse_prompt_prefix': true,
    'runtime_package': 'llamadart 0.12.0',
    'threads': 2,
    'batch_threads': 2,
    'batch_size': 64,
    'micro_batch_size': 64,
  };
  static const humanFields = [
    'Anlaşılır Türkçe',
    'Zorunlu olayların bulunması',
    'Doğru olay sırası',
    'Yasaklanan ek olayların bulunmaması',
    'İstenen çıktı biçimi',
  ];
}

class D01EvaluationState {
  const D01EvaluationState({
    this.isBusy = false,
    this.message = 'Henüz çalıştırılmadı.',
    this.runId,
    this.attempted = 0,
    this.error,
  });
  final bool isBusy;
  final String message;
  final String? runId;
  final int attempted;
  final String? error;
}

/// Seçilen modelle her planlı denemeye yeni servis/motor açar.
/// İçeriğe başarı etiketi atamaz; iki tekrar, hata üzerine otomatik retry değildir.
class D01EvaluationService {
  D01EvaluationService({
    required this.loadProtocol,
    required this.resolveRecordsRoot,
    required this.resolveModel,
    required this.createRuntime,
    required this.executionSource,
  });

  final Future<String> Function() loadProtocol;
  final Future<Directory> Function() resolveRecordsRoot;
  final Future<File> Function(LocalModelOption model) resolveModel;
  final LocalLlamaTestRuntime Function(LocalLlamaTestRequest) createRuntime;
  // Üretimde 'llamadart_native'; kontrollü testlerde açıkça 'test_double'.
  final String executionSource;
  final _updates = StreamController<D01EvaluationState>.broadcast();
  D01EvaluationState state = const D01EvaluationState();
  Stream<D01EvaluationState> get states => _updates.stream;
  LocalLlamaTestService? _trial;
  Future<void>? _running;
  bool _cancelled = false;
  bool _disposed = false;
  Map<String, dynamic>? _snapshot;
  final _records = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> get records =>
      List.unmodifiable(_records.map(Map<String, dynamic>.unmodifiable));
  bool get canExport => _snapshot != null;
  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'protocol': _snapshot,
    'attempts': _records,
    'evaluation_status': 'human_review_pending',
    'run_execution': {
      'is_running': state.isBusy,
      'attempted': state.attempted,
      'cancel_requested': _cancelled,
      'error': state.error,
    },
  });

  void _emit(
    String message, {
    bool busy = true,
    int? attempted,
    String? error,
  }) {
    state = D01EvaluationState(
      isBusy: busy,
      message: message,
      runId: state.runId,
      attempted: attempted ?? state.attempted,
      error: error,
    );
    _updates.add(state);
  }

  Future<void> run({LocalModelOption model = LocalModelOption.qwen3}) {
    if (model != LocalModelOption.qwen3 &&
        model != LocalModelOption.miniCpmTurkish) {
      throw StateError('Bu değerlendirme için seçilen model desteklenmiyor.');
    }
    if (state.isBusy || _disposed) {
      throw StateError('Değerlendirme zaten çalışıyor veya kapatıldı.');
    }
    _cancelled = false;
    _snapshot = null;
    _records.clear();
    state = const D01EvaluationState();
    _emit('Sabit istem planı kaydediliyor.');
    return _running = _execute(model);
  }

  Future<void> _write(File file, Object value) async {
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
  }

  Future<void> _execute(LocalModelOption model) async {
    String? modelPath;
    Directory? directory;
    var finalMessage =
        'Altı deneme kaydedildi; insan değerlendirmesi bekliyor.';
    String? finalError;
    try {
      final protocol = D01EvaluationProtocol.parse(await loadProtocol());
      final root = await resolveRecordsRoot();
      await root.create(recursive: true);
      final prefix = DateTime.now().toUtc().toIso8601String().replaceAll(
        RegExp('[^0-9T]'),
        '',
      );
      directory = await root.createTemp('run_${prefix}_');
      final runId = directory.uri.pathSegments.where((s) => s.isNotEmpty).last;
      state = D01EvaluationState(isBusy: true, runId: runId);
      _snapshot = {
        'schema_version': '1.0',
        'protocol_id': protocol.id,
        'run_id': runId,
        'saved_before_inference_utc': DateTime.now().toUtc().toIso8601String(),
        'execution_source': executionSource,
        'model_id': model.id,
        'model_file': model.fileName,
        'settings': D01EvaluationProtocol.settings,
        'repetitions_per_task': 2,
        'tasks': [
          for (final t in protocol.tasks)
            {'task_id': t.id, 'title': t.title, 'prompt': t.prompt},
        ],
      };
      for (final task in protocol.tasks) {
        for (var repetition = 1; repetition <= 2; repetition++) {
          _records.add({
            'run_id': runId,
            'protocol_id': protocol.id,
            'task_id': task.id,
            'attempt_id': '${task.id}_$repetition',
            'repetition': repetition,
            'prompt': task.prompt,
            'model_id': model.id,
            'model_file': model.fileName,
            'settings': D01EvaluationProtocol.settings,
            'execution_source': executionSource,
            'execution_status': 'pending',
            'raw_response': null,
            'started_at_utc': null,
            'finished_at_utc': null,
            'elapsed_s': null,
            'generation_s': null,
            'prompt_tokens': null,
            'completion_tokens': null,
            'cached_prompt_tokens': null,
            'template_prompt_tokens_add_special_false': null,
            'finish_reason': null,
            'error': null,
            'human_evaluation': {
              for (final name in D01EvaluationProtocol.humanFields) name: null,
            },
          });
        }
      }
      // Bütün plan ve altı pending kayıt ilk model açılmadan diske yazılır.
      await _write(File('${directory.path}/protocol.json'), _snapshot!);
      for (final record in _records) {
        await _write(
          File('${directory.path}/${record['attempt_id']}.json'),
          record,
        );
      }
      _emit('İstem planı kaydedildi; altı bağımsız deneme hazırlanıyor.');
      final modelFile = await resolveModel(model);
      modelPath = modelFile.path;
      if (!await modelFile.exists()) {
        throw const FileSystemException('Model indirilmedi');
      }
      for (var i = 0; i < _records.length; i++) {
        if (_cancelled) break;
        final record = _records[i];
        final task = protocol.tasks[i ~/ 2];
        record['execution_status'] = 'running';
        record['started_at_utc'] = DateTime.now().toUtc().toIso8601String();
        await _write(
          File('${directory.path}/${record['attempt_id']}.json'),
          record,
        );
        final trial = LocalLlamaTestService(
          request: task.requestFor(model),
          resolveModel: () async => modelFile,
          createRuntime: createRuntime,
        );
        _trial = trial;
        _emit('${i + 1}/6 · ${task.title} · ${record['repetition']}. deneme');
        try {
          if (_cancelled) {
            record['execution_status'] = 'cancelled_before_inference';
            await _write(
              File('${directory.path}/${record['attempt_id']}.json'),
              record,
            );
            break;
          }
          await trial.run();
          final result = trial.state;
          final d = result.diagnostics;
          int? count(String key) => int.tryParse(d[key] ?? '');
          record.addAll({
            'execution_status': result.phase.name,
            'raw_response': result.text,
            'finished_at_utc': DateTime.now().toUtc().toIso8601String(),
            'elapsed_s': result.elapsed.inMicroseconds / 1000000,
            'generation_s': result.generationElapsed.inMicroseconds / 1000000,
            'prompt_tokens': count('Native istek tokenı'),
            'completion_tokens': count('Native üretilen token'),
            'cached_prompt_tokens': count('Native önbellekten token'),
            'template_prompt_tokens_add_special_false': count(
              'Şablonlu istek tokenı (addSpecial=false)',
            ),
            'reported_context_tokens': count(
              'Motorun bildirdiği bağlam kapasitesi',
            ),
            'finish_reason': d['API bitiş nedeni'] == 'Henüz raporlanmadı'
                ? null
                : d['API bitiş nedeni'],
            'reported_sampling': d['Örnekleme'],
            'rendered_prompt_preview': d['Şablon uygulanmış istek'],
            'thinking_template_check': d['Düşünmesiz şablon kontrolü'],
            'gguf_model_name': d['GGUF model adı'],
            'gguf_architecture': d['GGUF mimarisi'],
            'error': _safeError(result.error, modelPath, directory.path),
          });
          await _write(
            File('${directory.path}/${record['attempt_id']}.json'),
            record,
          );
          _emit(
            '${i + 1}/6 deneme kaydedildi; içerik değerlendirilmedi.',
            attempted: i + 1,
          );
          if (!trial.canRun) {
            throw StateError(
              'Native kaynak kapatma hatası; kalan denemeler çalıştırılmadı.',
            );
          }
        } catch (error) {
          if (record['execution_status'] == 'running') {
            record['execution_status'] = 'error';
            record['finished_at_utc'] = DateTime.now()
                .toUtc()
                .toIso8601String();
            record['raw_response'] = trial.state.text;
            record['error'] = _safeError(
              error.toString(),
              modelPath,
              directory.path,
            );
            await _write(
              File('${directory.path}/${record['attempt_id']}.json'),
              record,
            );
          }
          rethrow;
        } finally {
          await trial.dispose();
          _trial = null;
        }
      }
      if (_cancelled) {
        finalMessage = 'Değerlendirme durduruldu; mevcut kayıtlar korundu.';
      }
    } catch (error) {
      finalMessage = 'Değerlendirme teknik hata nedeniyle durdu.';
      finalError = _safeError(error.toString(), modelPath, directory?.path);
    } finally {
      if (directory != null && _snapshot != null) {
        try {
          await _write(File('${directory.path}/run_summary.json'), {
            'run_id': state.runId,
            'planned_attempts': 6,
            'attempted': state.attempted,
            'cancelled': _cancelled,
            'execution_error': finalError,
            'semantic_verdict': null,
          });
        } catch (error) {
          finalError =
              '${finalError ?? ''}\nOturum özeti kaydedilemedi: '
              '${_safeError(error.toString(), modelPath, directory.path)}';
          finalMessage = 'Kayıt hatası; mevcut kayıtları kontrol edin.';
        }
      }
      _emit(finalMessage, busy: false, error: finalError);
    }
  }

  String? _safeError(String? error, String? modelPath, String? recordsPath) {
    if (error == null) return null;
    var safe = error;
    for (final path in [modelPath, recordsPath]) {
      if (path != null && path.isNotEmpty) {
        safe = safe.replaceAll(path, '[yerel_yol]');
      }
    }
    return safe.replaceAll(
      RegExp(
        r'''(?:[A-Za-z]:[\\/]|/data/user/\d+/|/data/data/|/Users/|/home/)[^\s'"<>]*''',
      ),
      '[yerel_yol]',
    );
  }

  void cancel() {
    if (!state.isBusy) return;
    _cancelled = true;
    _trial?.cancel();
    _emit('Durdurma bekleniyor; native kaynaklar kapatılacak.');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    cancel();
    await _running;
    await _updates.close();
  }
}
