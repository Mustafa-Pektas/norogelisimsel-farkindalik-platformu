import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_awareness_app/models/local_model_option.dart';
import 'package:neuro_awareness_app/services/llama_model_service.dart';

void main() {
  Future<Directory> scratch() async {
    final dir = await Directory('.dart_tool')
        .createTemp('model_download_check_');
    addTearDown(() async {
      expect(dir.absolute.parent.path, Directory('.dart_tool').absolute.path);
      await dir.delete(recursive: true);
    });
    return dir;
  }

  test(
    'Qwen yanlış/eksik indirmesi Llama dosyasına dokunmaz, doğru URL kullanır',
    () async {
      final dir = await scratch();
      final llama = await File('${dir.path}/${LocalModelOption.llama.fileName}')
          .writeAsString('TEST: existing Llama sentinel');
      final target = File('${dir.path}/${LocalModelOption.qwen3.fileName}');
      final client = MockClient((request) async {
        expect(request.url.toString(), LocalModelOption.qwen3.downloadUrl);
        return http.Response.bytes([71, 71, 85, 70], 200);
      });
      final states = await LlamaModelService.downloadModel(
        model: LocalModelOption.qwen3,
        client: client,
        resolveFile: () async => target,
      ).toList();
      expect(states.last.error, contains('Eksik indirme'));
      expect(states.any((s) => !s.isDownloading && s.progress == 1), isFalse);
      expect(await target.exists(), isFalse);
      expect(await File('${target.path}.part').exists(), isFalse);
      expect(await llama.readAsString(), 'TEST: existing Llama sentinel');
    },
  );

  test('HTTP hatasında başka model veya başarılı sonuç verilmez', () async {
    final dir = await scratch();
    final target = File('${dir.path}/qwen.gguf');
    final states = await LlamaModelService.downloadModel(
      model: LocalModelOption.qwen3,
      client: MockClient((_) async => http.Response('test denied', 403)),
      resolveFile: () async => target,
    ).toList();
    expect(states.last.error, contains('HTTP 403'));
    expect(await target.exists(), isFalse);
  });

  test(
    'Mevcut eksik Qwen dosyası üzerine yazılmaz; HTTP isteği yapılmaz',
    () async {
      final dir = await scratch();
      final target = await File('${dir.path}/qwen.gguf')
          .writeAsString('TEST: preserve this');
      var calls = 0;
      final states = await LlamaModelService.downloadModel(
        model: LocalModelOption.qwen3,
        client: MockClient((_) async {
          calls++;
          return http.Response('', 200);
        }),
        resolveFile: () async => target,
      ).toList();
      expect(states.last.error, contains('üzerine yazılmadı'));
      expect(calls, 0);
      expect(await target.readAsString(), 'TEST: preserve this');
    },
  );

  test('Qwen indirmesi ancak akış dinlenince başlar; indirmeler ortak kilidi kullanır', () async {
    final dir = await scratch();
    var calls = 0;
    final stream = LlamaModelService.downloadModel(
      model: LocalModelOption.qwen3,
      client: MockClient((_) async {
        calls++;
        return http.Response('', 200);
      }),
      resolveFile: () async => File('${dir.path}/qwen.gguf'),
    );
    expect(calls, 0);
    final iterator = StreamIterator(stream);
    expect(
      await iterator.moveNext(),
      isTrue,
    ); // İlk bağlantı durumu; henüz HTTP yok.
    final other = await LlamaModelService.downloadModel().toList();
    expect(other.single.error, contains('Başka bir model indirmesi'));
    LlamaModelService.cancelDownload(model: LocalModelOption.qwen3);
    while (await iterator.moveNext()) {
      expect(iterator.current.progress, lessThan(1));
    }
    expect(calls, 0);
    await iterator.cancel();
  });

  test('Qwen aktarım sırasında iptal edilirse kısmi dosya kalmaz', () async {
    final dir = await scratch();
    final target = File('${dir.path}/qwen.gguf');
    LlamaDownloadStatus? last;
    await for (final state in LlamaModelService.downloadModel(
      model: LocalModelOption.qwen3,
      client: MockClient(
        (_) async => http.Response.bytes([71, 71, 85, 70], 200),
      ),
      resolveFile: () async => target,
    )) {
      if (state.downloadedBytes > 0) {
        LlamaModelService.cancelDownload(model: LocalModelOption.qwen3);
      }
      last = state;
    }
    expect(last!.statusMessage, 'İndirme iptal edildi');
    expect(last.error, isNull);
    expect(await target.exists(), isFalse);
    expect(await File('${target.path}.part').exists(), isFalse);
  });

  test('Ortak indirici tamamlanan test aktarımını atomik taşır; GGUF olmayanı reddeder', () async {
    // Küçük HTTP fixture'ları yalnızca indirici kontrolüdür; gerçek model değildir.
    SharedPreferences.setMockInitialValues({});
    final dir = await scratch();
    for (final valid in [true, false]) {
      final target = File('${dir.path}/test_$valid.gguf');
      final states = await LlamaModelService.downloadModel(
        client: MockClient(
          (_) async => http.Response(valid ? 'GGUFtest' : 'HTMLtest', 200),
        ),
        resolveFile: () async => target,
      ).toList();
      expect(await target.exists(), valid);
      expect(await File('${target.path}.part').exists(), isFalse);
      if (valid) {
        expect(states.last.progress, 1);
        expect(states.last.error, isNull);
        expect(await target.readAsString(), 'GGUFtest');
      } else {
        expect(states.last.error, contains('GGUF başlığı yok'));
      }
    }
  });
}
