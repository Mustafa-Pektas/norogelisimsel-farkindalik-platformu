import 'dart:convert';

import 'package:llamadart/llamadart.dart';

import '../models/local_model_option.dart';
import 'local_llama_test_service.dart';

/// llamadart 0.12.0 yayımlanmış API'si. Native backend kendi worker isolate'ını
/// kullanır. Yerel dosya yüklenir; model indirme veya hazır cevapla hata gizleme yoktur.
class LlamadartTestRuntime implements LocalLlamaTestRuntime {
  LlamadartTestRuntime(this.request, {LlamaEngine? engine})
    : _engine = engine ?? LlamaEngine(LlamaBackend());
  final LocalLlamaTestRequest request;
  final LlamaEngine _engine;
  final _diagnostics = <String, String>{};
  String? _loadedPath;
  @override
  Map<String, String> get diagnostics => Map.unmodifiable(_diagnostics);

  @override
  Future<void> load(String path) {
    _loadedPath = path;
    return _engine.setModel(
      LlamaModel(ModelSource.path(path)),
      params: ModelParams(
        contextSize: request.contextSize,
        device: ComputeDevice.cpu,
        gpuLayers: 0,
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
        batchSize: 64,
        microBatchSize: 64,
      ),
    );
  }

  @override
  Stream<String> generate() async* {
    final messages = [
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: request.prompt),
    ];
    final qwen = request.model == LocalModelOption.qwen3;
    final params = qwen
        ? GenerationParams(
            maxTokens: request.maxTokens,
            temp: 0.7,
            topP: 0.8,
            topK: 20,
            minP: 0,
            penalty: 1.0,
            presencePenalty: 0,
          )
        : GenerationParams(maxTokens: request.maxTokens);
    final inspect =
        request.id == LocalLlamaTestRequest.d01.id ||
        request.id == LocalLlamaTestRequest.d01English.id ||
        qwen;
    // İnceleme ve create aynı tarih bağlamıyla aynı şablonu render etsin.
    final templateNow = DateTime.now().toUtc();
    if (inspect) {
      _diagnostics.clear();
      _diagnostics['Model kimliği'] = request.model.id;
      _diagnostics['Model dosyası'] = _loadedPath ?? 'Henüz yüklenmedi';
      _diagnostics['Gönderilen mesajlar'] = jsonEncode([
        for (final m in messages) {'role': m.role.name, 'content': m.content},
      ]);
      _diagnostics['İstenen sınırlar'] =
          'bağlam=${request.contextSize}, çıktı=${params.maxTokens}';
      _diagnostics['Örnekleme'] =
          'temp=${params.temp}, topK=${params.topK}, topP=${params.topP}, '
          'minP=${params.minP}, penalty=${params.penalty}, presencePenalty=${params.presencePenalty}, '
          'seed=${params.seed ?? 'belirtilmedi (native zaman tabanlı)'}, reusePromptPrefix=${params.reusePromptPrefix}';
      _diagnostics['API bitiş nedeni'] = 'Henüz raporlanmadı';
      final metadata = await _engine.getMetadata();
      _diagnostics['GGUF model adı'] =
          metadata['general.name'] ?? 'Raporlanmadı';
      _diagnostics['GGUF mimarisi'] =
          metadata['general.architecture'] ?? 'Raporlanmadı';
      _diagnostics['GGUF sohbet şablonu'] =
          metadata['tokenizer.chat_template'] ?? 'Metadata içinde bulunamadı';
      if (qwen &&
          (metadata['general.architecture'] != 'qwen3' ||
              (metadata['tokenizer.chat_template'] ?? '').trim().isEmpty)) {
        throw StateError(
          'Qwen3 mimarisi ve GGUF sohbet şablonu doğrulanamadı; başka modele veya şablona geçilmedi.',
        );
      }
      final context = await _engine.getContextSize();
      _diagnostics['Motorun bildirdiği bağlam kapasitesi'] = '$context';
      final template = await _engine.chatTemplate(
        messages,
        enableThinking: false,
        includeTokenCount: true,
        templateNow: templateNow,
      );
      _diagnostics['Şablon uygulanmış istek'] = template.prompt;
      if (qwen) {
        final closedThinking = RegExp(
          r'<\|im_start\|>assistant\s*<think>\s*</think>\s*$',
        ).hasMatch(template.prompt);
        _diagnostics['Düşünmesiz şablon kontrolü'] = closedThinking
            ? 'enableThinking=false; assistant başlangıcında boş <think></think> bloğu doğrulandı.'
            : 'Başarısız: beklenen kapalı düşünme başlangıcı bulunamadı.';
        if (!closedThinking) {
          throw StateError(
            'Qwen düşünmesiz sohbet şablonu doğrulanamadı; üretim başlatılmadı.',
          );
        }
      }
      _diagnostics['Şablon format kodu'] = '${template.format}';
      _diagnostics['Şablonlu istek tokenı (addSpecial=false)'] =
          template.tokenCount?.toString() ?? 'Ölçüm raporlanmadı';
      _diagnostics['Etkin metin durdurma dizileri'] = jsonEncode(
        {...template.stopSequences, ...params.stopSequences}.toList(),
      );
      if (template.tokenCount case final int tokens) {
        if (tokens + params.maxTokens > context) {
          throw StateError(
            'Şablonlu istek ($tokens token) ve çıktı rezervi '
            '(${params.maxTokens}) motorun bildirdiği bağlam kapasitesini ($context) aşıyor.',
          );
        }
      }
    }
    // Şablonlu metni create'e vermiyoruz: ham user mesajı yalnızca motor
    // tarafından şablonlanır. Yukarıdaki chatTemplate çağrısı inceleme içindir.
    await for (final chunk in _engine.create(
      messages,
      params: params,
      enableThinking: false,
      templateNow: templateNow,
    )) {
      if (inspect) {
        for (final choice in chunk.choices) {
          if (choice.finishReason != null) {
            _diagnostics['API bitiş nedeni'] = choice.finishReason!;
          }
        }
        final usage = chunk.usage;
        if (usage != null) {
          _diagnostics['Native istek tokenı'] = '${usage.promptTokens}';
          _diagnostics['Native üretilen token'] = '${usage.completionTokens}';
          _diagnostics['Native önbellekten token'] =
              usage.cachedPromptTokens?.toString() ?? 'Raporlanmadı';
        }
      }
      yield chunk.text;
    }
  }

  @override
  void cancelGeneration() => _engine.cancelGeneration();

  @override
  Future<void> dispose() => _engine.dispose();
}
