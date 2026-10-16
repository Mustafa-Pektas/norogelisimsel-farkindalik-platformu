import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:neuro_awareness_app/services/llamadart_test_runtime.dart';
import 'package:neuro_awareness_app/services/local_llama_test_service.dart';
import 'package:neuro_awareness_app/models/local_model_option.dart';

// Gerçek yayımlanmış paket türleriyle API sınırı kontrol edilir; model yüklenmez.
class _RecordingEngine extends Fake implements LlamaEngine {
  LlamaModel? model;
  ModelParams? modelParams;
  List<LlamaChatMessage>? messages;
  GenerationParams? generationParams;
  Object? generationError;
  bool? enableThinking;
  bool cancelled = false;
  bool disposed = false;
  int? templateTokens = 50;
  int contextSize = 2048;
  List<LlamaChatMessage>? templateMessages;
  DateTime? templateNow;
  DateTime? generationTemplateNow;
  int createCalls = 0;
  Stream<LlamaCompletionChunk>? output;
  bool qwenProfile = false;
  bool closedThinking = true;
  String qwenArchitecture = 'qwen3';

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #getMetadata:
        return Future.value(<String, String>{
          'tokenizer.chat_template': 'UNIT TEST TEMPLATE',
          if (qwenProfile) 'general.architecture': qwenArchitecture,
        });
      case #getContextSize:
        return Future.value(contextSize);
      case #chatTemplate:
        templateMessages =
            invocation.positionalArguments.single as List<LlamaChatMessage>;
        templateNow = invocation.namedArguments[#templateNow] as DateTime;
        return Future.value(
          LlamaChatTemplateResult(
            prompt: qwenProfile
                ? '<|im_start|>user\n${templateMessages!.single.content}<|im_end|>\n<|im_start|>assistant\n<think>\n${closedThinking ? '\n</think>\n\n' : ''}'
                : 'UNIT TEST: formatted prompt',
            tokenCount: templateTokens,
            additionalStops: const ['<|eot_id|>'],
          ),
        );
      case #setModel:
        model = invocation.positionalArguments.single as LlamaModel;
        modelParams = invocation.namedArguments[#params] as ModelParams;
        return Future<void>.value();
      case #create:
        createCalls++;
        generationTemplateNow =
            invocation.namedArguments[#templateNow] as DateTime;
        messages =
            invocation.positionalArguments.single as List<LlamaChatMessage>;
        generationParams =
            invocation.namedArguments[#params] as GenerationParams;
        enableThinking = invocation.namedArguments[#enableThinking] as bool;
        return output ??
            (generationError == null
                ? const Stream<LlamaCompletionChunk>.empty()
                : Stream<LlamaCompletionChunk>.error(generationError!));
      case #cancelGeneration:
        cancelled = true;
        return null;
      case #dispose:
        disposed = true;
        return Future<void>.value();
      default:
        return super.noSuchMethod(invocation);
    }
  }
}

void main() {
  for (final request in [
    LocalLlamaTestRequest.greeting,
    LocalLlamaTestRequest.d01,
    LocalLlamaTestRequest.d01English,
    LocalLlamaTestRequest.d01Qwen,
  ]) {
    test(
      '${request.id}: yayımlanmış llamadart API yerel dosya, CPU, istek ve token sınırını alır',
      () async {
        final qwen = request.model == LocalModelOption.qwen3;
        final engine = _RecordingEngine()..qwenProfile = qwen;
        final runtime = LlamadartTestRuntime(request, engine: engine);
        await runtime.load('/existing/model.gguf');
        expect(engine.model!.source.path, '/existing/model.gguf');
        expect(
          engine.modelParams!.contextSize,
          request == LocalLlamaTestRequest.greeting ? 512 : 2048,
        );
        expect(engine.modelParams!.device, ComputeDevice.cpu);
        expect(engine.modelParams!.gpuLayers, 0);
        await runtime.generate().drain<void>();
        expect(engine.messages!.single.role, LlamaChatRole.user);
        expect(engine.messages!.single.content, request.prompt);
        expect(
          engine.generationParams!.maxTokens,
          request == LocalLlamaTestRequest.greeting ? 32 : 384,
        );
        expect(engine.enableThinking, isFalse);
        // İstenen örnekleme ayarlarını değiştirmedik.
        expect(engine.generationParams!.temp, qwen ? 0.7 : 0.8);
        expect(engine.generationParams!.topK, qwen ? 20 : 40);
        expect(engine.generationParams!.topP, qwen ? 0.8 : 0.9);
        expect(engine.generationParams!.minP, 0);
        expect(engine.generationParams!.penalty, qwen ? 1.0 : 1.1);
        expect(engine.generationParams!.presencePenalty, 0);
        expect(engine.generationParams!.seed, isNull);
        expect(engine.generationParams!.stopSequences, isEmpty);
        expect(engine.generationParams!.grammar, isNull);
        if (request != LocalLlamaTestRequest.greeting) {
          expect(identical(engine.templateMessages, engine.messages), isTrue);
          expect(engine.templateNow, engine.generationTemplateNow);
          expect(
            runtime.diagnostics['Şablonlu istek tokenı (addSpecial=false)'],
            '50',
          );
          expect(runtime.diagnostics['API bitiş nedeni'], 'Henüz raporlanmadı');
          expect(
            engine.messages!.single.content,
            isNot('UNIT TEST: formatted prompt'),
          );
        }
        runtime.cancelGeneration();
        await runtime.dispose();
        expect(engine.cancelled && engine.disposed, isTrue);
      },
    );
  }
  test(
    'Qwen3 paket şablonunda düşünme kapatılır; aynı Türkçe istek korunur',
    () {
      // Bu fixture kurulu paketin Qwen3-4B şablonudur; aday 1.7B GGUF değildir.
      // Gerçek adayın şablonu runtime'da ayrıca kontrol edilmeden üretim başlamaz.
      final source = File('test/fixtures/qwen3_package_4b_template.jinja')
          .readAsStringSync();
      expect(
        LocalLlamaTestRequest.d01Qwen.prompt,
        LocalLlamaTestRequest.d01.prompt,
      );
      final messages = [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: LocalLlamaTestRequest.d01Qwen.prompt,
        ),
      ];
      for (final thinking in [true, false]) {
        final result = ChatTemplateEngine.render(
          templateSource: source,
          messages: messages,
          metadata: const {},
          addAssistant: true,
          enableThinking: thinking,
        );
        expect(result.prompt, contains(LocalLlamaTestRequest.d01.prompt));
        expect(result.prompt.endsWith('<think>\n\n</think>\n\n'), !thinking);
        expect(result.grammar, isNull);
        expect(result.prompt, isNot(contains('# Tools')));
      }
    },
  );
  for (final wrongArchitecture in [true, false]) {
    test(
      'Qwen ${wrongArchitecture ? 'mimari' : 'düşünmesiz şablon'} doğrulanmazsa başka modele geçmez',
      () async {
        final engine = _RecordingEngine()
          ..qwenProfile = true
          ..qwenArchitecture = wrongArchitecture ? 'llama' : 'qwen3'
          ..closedThinking = wrongArchitecture;
        final runtime = LlamadartTestRuntime(
          LocalLlamaTestRequest.d01Qwen,
          engine: engine,
        );
        await expectLater(runtime.generate(), emitsError(isA<StateError>()));
        expect(engine.createCalls, 0);
        await runtime.dispose();
      },
    );
  }
  for (final request in [
    LocalLlamaTestRequest.d01,
    LocalLlamaTestRequest.d01English,
  ]) {
    test(
      '${request.id}: cihaz GGUF şablonu araç talimatı eklemeden doğru rolleri render eder',
      () {
        // Yalnızca mevcut cihaz dosyasından okunan şablon; model çıkarımı yoktur.
        final metadata = (jsonDecode(
          File('test/fixtures/llama32_device_template.json').readAsStringSync(),
        ) as Map<String, dynamic>).cast<String, String>();
        final result = ChatTemplateEngine.render(
          templateSource: metadata['tokenizer.chat_template'],
          metadata: metadata,
          messages: [
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: request.prompt,
            ),
          ],
          addAssistant: true,
          enableThinking: false,
          now: DateTime.utc(2026, 10, 16),
        );
        expect(
          result.prompt,
          startsWith(
            '<|begin_of_text|><|start_header_id|>system<|end_header_id|>',
          ),
        );
        expect(
          result.prompt,
          contains(
            '<|start_header_id|>user<|end_header_id|>\n\n${request.prompt}<|eot_id|>',
          ),
        );
        expect(result.prompt.split(request.prompt).length, 2);
        expect(
          result.prompt,
          endsWith('<|start_header_id|>assistant<|end_header_id|>\n\n'),
        );
        expect(result.prompt, isNot(contains('Environment: ipython')));
        expect(result.prompt, isNot(contains('Given the following functions')));
        expect(result.prompt, isNot(contains('To call a function')));
        expect(result.prompt, isNot(contains('Respond in the format')));
        expect(result.grammar, isNull);
        expect(result.grammarTriggers, isEmpty);
        expect(result.stopSequences, ['<|eot_id|>']);
      },
    );
  }
  test(
    'D01 native API hatası cevap şablonuyla değiştirilmeden aktarılır',
    () async {
      final failure = StateError('test: native üretim hatası');
      final engine = _RecordingEngine()..generationError = failure;
      final runtime = LlamadartTestRuntime(
        LocalLlamaTestRequest.d01,
        engine: engine,
      );
      await expectLater(runtime.generate(), emitsError(same(failure)));
      await runtime.dispose();
    },
  );
  test(
    'Şablonlu token sayımı çıktı rezerviyle bağlamı aşarsa üretim başlamaz',
    () async {
      final engine = _RecordingEngine()..templateTokens = 2000;
      final runtime = LlamadartTestRuntime(
        LocalLlamaTestRequest.d01,
        engine: engine,
      );
      await expectLater(runtime.generate(), emitsError(isA<StateError>()));
      expect(engine.createCalls, 0);
      await runtime.dispose();
    },
  );
  test('Token sayısı raporlanmazsa tahmini bir sayı gösterilmez', () async {
    final engine = _RecordingEngine()..templateTokens = null;
    final runtime = LlamadartTestRuntime(
      LocalLlamaTestRequest.d01,
      engine: engine,
    );
    await runtime.generate().drain<void>();
    expect(
      runtime.diagnostics['Şablonlu istek tokenı (addSpecial=false)'],
      'Ölçüm raporlanmadı',
    );
    expect(runtime.diagnostics.containsKey('Native istek tokenı'), isFalse);
    await runtime.dispose();
  });
  test(
    'Ham cevap aynen korunur; native tokenlar ve length bitişi kaybolmaz',
    () async {
      const raw = '  TEST: ham cevap\nJSON da olsa değiştirilmez.  ';
      Map<String, dynamic> chunk(Map<String, dynamic> delta, String? reason) =>
          {
            'id': 'unit-only',
            'object': 'chat.completion.chunk',
            'created': 0,
            'model': 'unit-only',
            'choices': [
              {'index': 0, 'delta': delta, 'finish_reason': reason},
            ],
          };
      final finalChunk = chunk({}, 'length')
        ..['usage'] = {
          'prompt_tokens': 51,
          'completion_tokens': 384,
          'prompt_tokens_details': {'cached_tokens': 0},
        };
      final engine = _RecordingEngine()
        ..output = Stream.fromIterable([
          LlamaCompletionChunk.fromJson(chunk({'content': raw}, null)),
          LlamaCompletionChunk.fromJson(finalChunk),
        ]);
      final runtime = LlamadartTestRuntime(
        LocalLlamaTestRequest.d01,
        engine: engine,
      );
      expect(await runtime.generate().join(), raw);
      expect(runtime.diagnostics['API bitiş nedeni'], 'length');
      expect(runtime.diagnostics['Native istek tokenı'], '51');
      expect(runtime.diagnostics['Native üretilen token'], '384');
      expect(runtime.diagnostics['Native önbellekten token'], '0');
      await runtime.dispose();
    },
  );
}
