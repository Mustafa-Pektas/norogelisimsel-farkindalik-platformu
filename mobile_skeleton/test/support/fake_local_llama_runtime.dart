import 'dart:async';

import 'package:neuro_awareness_app/services/local_llama_test_service.dart';

// Yalnızca yaşam döngüsü/UI testleri için. Gerçek çıkarım kanıtı değildir;
// uygulama bu dosyayı veya bu cevabı import etmez.
class FakeLocalLlamaRuntime implements LocalLlamaTestRuntime {
  Map<String, String> diagnosticValues = const {};
  @override
  Map<String, String> get diagnostics => diagnosticValues;
  Completer<void>? loadGate;
  Completer<void>? disposeGate;
  final loadStarted = Completer<void>.sync();
  final disposeStarted = Completer<void>.sync();
  final generationStarted = Completer<void>.sync();
  Object? loadError;
  Object? generationError;
  Object? disposeError;
  String? path;
  int generations = 0;
  int cancellations = 0;
  int disposals = 0;
  Stream<String> Function()? output;
  void Function()? onCancel;
  @override
  Future<void> load(String path) async {
    this.path = path;
    loadStarted.complete();
    await loadGate?.future;
    if (loadError != null) throw loadError!;
  }

  @override
  Stream<String> generate() {
    generations++;
    generationStarted.complete();
    if (output != null) return output!();
    if (generationError != null) return Stream.error(generationError!);
    return Stream.fromIterable(['TEST ', 'ÇIKTISI']);
  }

  @override
  void cancelGeneration() {
    cancellations++;
    onCancel?.call();
  }

  @override
  Future<void> dispose() async {
    disposals++;
    disposeStarted.complete();
    await disposeGate?.future;
    if (disposeError != null) throw disposeError!;
  }
}
