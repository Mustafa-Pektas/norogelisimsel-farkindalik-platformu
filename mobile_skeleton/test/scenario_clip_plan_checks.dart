// Mevcut graf kontrolleriyle aynı, Flutter gerektirmeyen Dart kontrol biçimi.
// Uygulama kökünden:
// dart --disable-dart-dev --packages=.dart_tool/package_config.json test/scenario_clip_plan_checks.dart
import 'dart:convert';
import 'dart:io';

import 'package:neuro_awareness_app/models/scenario_clip_plan.dart';
import 'package:neuro_awareness_app/models/scenario_graph.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void invalid(void Function() action, String message) {
  try {
    action();
  } on FormatException catch (error) {
    check(
      error.message.contains(message),
      'Beklenen: $message; alınan: $error',
    );
    return;
  }
  throw StateError('Geçersiz veri kabul edildi: $message');
}

void immutable(void Function() action) {
  try {
    action();
  } on UnsupportedError {
    return;
  }
  throw StateError('Klip listesi dışarıdan değiştirilebildi.');
}

void main() {
  final graphFile = File('assets/scenarios/d01_scenario_graph.json');
  final originalGraph = graphFile.readAsStringSync();
  final graph = ScenarioGraph.fromJsonString(originalGraph);
  final input = File('assets/scenarios/d01_clip_plan.json').readAsStringSync();
  Map<String, dynamic> data() => jsonDecode(input) as Map<String, dynamic>;
  List<dynamic> clips(Map<String, dynamic> value) =>
      value['clips'] as List<dynamic>;
  final tests = <String, void Function()>{
    'Elle hazırlanmış örnek bütün beş sahneyi kapsar ve kayıpsız JSON dönüşür':
        () {
          final plan = ScenarioClipPlan.fromJsonString(input);
          plan.validateAgainst(graph);
          check(plan.clips.length == 7, 'Yedi ayrı üretim klibi');
          check(
            plan.authoringNote.startsWith('Elle hazırlanmış'),
            'Kaynak notu',
          );
          final restored = ScenarioClipPlan.fromJsonString(
            plan.toJsonString(pretty: true),
          );
          restored.validateAgainst(graph);
          check(
            restored.toJsonString() == plan.toJsonString(),
            'Kayıpsız dönüşüm',
          );
          check(
            plan.clips.every(
              (c) => c.targetDurationS > 0 && c.targetDurationS <= 8,
            ),
            'Üretim sınırı',
          );
        },
    'Ortak oyun çağrıdan önce biter; her alternatifin çağrılı ilk ve çağrısız devam klibi vardır': () {
      final plan = ScenarioClipPlan.fromJsonString(input);
      check(
        plan.clipsForScene('oyuncakla_oyun').length == 1,
        'Ortak oyun çoğaltılmadı',
      );
      check(
        plan.clipsForScene('isim_cagrisi').isEmpty,
        'Ayrı ortak çağrı klibi kaldırıldı',
      );
      for (final sceneId in ['yetiskine_yonelme', 'oyuna_devam']) {
        final sequence = plan.clipsForScene(sceneId);
        check(sequence.length == 2, 'Gözlem tek klibe sıkıştırılmadı');
        check(
          sequence[0].targetDurationS == 8 && sequence[1].targetDurationS == 8,
          'Çağrı ve devam aynı ilk klipte; ardından ayrı 8 saniyelik gözlem',
        );
        check(
          sequence.first.productionPrompt.contains('Anne doğal sesle yalnız bir kez “Deniz” der.') &&
              sequence.last.productionPrompt.contains('Yeni isim çağrısı yoktur.'),
          'Tek çağrı ilk klipte; devam klibinde tekrarlanmaz',
        );
        check(sequence.first.plannedAction.contains('aynı klipte'), 'İlgili devam çağrı ile aynı kliptedir');
      }
      check(plan.authoringNote.contains('Gerçek pencere çağrının videodaki bitişinden itibaren ölçülür.'),
          '10 saniye toplam klip süresinden değil gerçek çağrı bitişinden doğrulanır');
      for (final endId in graph.endSceneIds) {
        check(plan.clipsForScene(endId).isNotEmpty, 'Bitiş sahnesi kapsandı');
      }
    },
    'Her izlenen yolda tam tek çağrı ve eşleşen klip durumları bulunur': () {
      final plan = ScenarioClipPlan.fromJsonString(input);
      const call = 'Anne doğal sesle yalnız bir kez “Deniz” der.';
      final paths = <List<String>>[];
      void walk(String id, List<String> prefix) {
        check(!prefix.contains(id), 'D01 örneği döngü içermemeli');
        final path = [...prefix, id];
        if (graph.endSceneIds.contains(id)) {
          paths.add(path);
        } else {
          for (final edge in graph.transitions.where((edge) => edge.fromSceneId == id)) {
            walk(edge.toSceneId, path);
          }
        }
      }
      walk(graph.startSceneId, []);
      check(paths.length == 2, 'İki alternatif yol korunmalı');
      for (final path in paths) {
        final sequence = [for (final id in path) ...plan.clipsForScene(id)];
        check(sequence.length == 4, 'Ortak oyun, çağrılı ilk klip, gözlem devamı, bitiş');
        check(sequence.where((clip) => clip.productionPrompt.contains(call)).length == 1,
            'Her yolda tek çağrı içeren üretim promptu');
        check(!sequence.first.productionPrompt.contains(call), 'Ortak oyun çağrı içermez');
        check(sequence[1].productionPrompt.contains(call) && sequence[1].orderInScene == 1,
            'Çağrı alternatifin ilk klibindedir');
        check(sequence[1].productionPrompt.split(call).length == 2, 'Aynı ilk promptta tek çağrı talimatı');
        check(sequence.skip(2).every((clip) => clip.productionPrompt.contains('Yeni isim çağrısı yoktur.')),
            'Devam ve bitişte yeni çağrı yoktur');
        check(sequence.fold<double>(0, (sum, clip) => sum + clip.targetDurationS) == 24,
            'Her yolun toplam üretim hedefi 24 saniyedir; gözlem süresi değildir');
        for (var i = 1; i < sequence.length; i++) {
          check(sequence[i - 1].finalState == sequence[i].initialState,
              'Durum aktarımı: ${sequence[i - 1].id} → ${sequence[i].id}');
        }
      }
      // Bu kontroller planın metin/durum sözleşmesine aittir; video davranışı kararı değildir.
      check(plan.clipsForScene('yetiskine_yonelme').first.plannedAction.contains('başını annesine çevirir'),
          'Alternatif A yönelme içerir');
      check(plan.clipsForScene('oyuna_devam').first.plannedAction.contains('oyununu sürdürür'),
          'Alternatif B oyunu sürdürme içerir');
    },
    'Bütün üretim promptları yetişkinin çocuğa temasını açıkça yasaklar': () {
      final plan = ScenarioClipPlan.fromJsonString(input);
      for (final clip in plan.clips) {
        check(clip.productionPrompt.contains('Yetişkin çocuğa dokunmaz.'), 'Açık temas kısıtı: ${clip.id}');
        check(!RegExp(r'(^|[\s,])dokunma([.,\s]|$)').hasMatch(clip.productionPrompt),
            'Çocuğun oyuncakla temasını belirsiz biçimde yasaklama: ${clip.id}');
      }
    },
    'Klip sırası JSON liste konumundan bağımsızdır': () {
      final value = data();
      value['clips'] = clips(value).reversed.toList();
      final plan = ScenarioClipPlan.fromJson(value);
      plan.validateAgainst(graph);
      check(
        plan
                .clipsForScene('oyuna_devam')
                .map((c) => c.orderInScene)
                .join(',') ==
            '1,2',
        'Sıra sıralandı',
      );
    },
    'Boş ve tekrarlı kimlikler, boş içerik reddedilir': () {
      for (final field in [
        'id',
        'sceneId',
        'plannedAction',
        'initialState',
        'finalState',
        'productionPrompt',
      ]) {
        final value = data();
        (clips(value).first as Map)[field] = '  ';
        invalid(() => ScenarioClipPlan.fromJson(value), 'boş olamaz');
      }
      final duplicate = data();
      (clips(duplicate)[1] as Map)['id'] = (clips(duplicate)[0] as Map)['id'];
      invalid(
        () => ScenarioClipPlan.fromJson(duplicate),
        'Tekrarlı klip kimliği',
      );
    },
    'Sıfır, negatif, 8 üstü ve sonlu olmayan süreler reddedilir': () {
      for (final duration in [0, -1, 8.01, double.nan, double.infinity]) {
        final value = data();
        (clips(value).first as Map)['targetDurationS'] = duration;
        invalid(() => ScenarioClipPlan.fromJson(value), 'Klip süresi');
      }
      for (final duration in [0.25, 8]) {
        final value = data();
        (clips(value).first as Map)['targetDurationS'] = duration;
        ScenarioClipPlan.fromJson(value).validateAgainst(graph);
      }
    },
    'Sıra pozitif tam sayı, tekil ve kesintisiz olmalıdır': () {
      for (final order in [0, -1, 1.5]) {
        final value = data();
        (clips(value).first as Map)['orderInScene'] = order;
        invalid(() => ScenarioClipPlan.fromJson(value), 'orderInScene');
      }
      final duplicate = data();
      (clips(duplicate).firstWhere((clip) => clip['sceneId'] == 'yetiskine_yonelme' && clip['orderInScene'] == 2) as Map)['orderInScene'] = 1;
      invalid(
        () => ScenarioClipPlan.fromJson(duplicate),
        'Tekrarlı klip sırası',
      );
      final gap = data();
      (clips(gap).firstWhere((clip) => clip['sceneId'] == 'yetiskine_yonelme' && clip['orderInScene'] == 2) as Map)['orderInScene'] = 3;
      invalid(() => ScenarioClipPlan.fromJson(gap), 'kesintisiz');
    },
    'Yanlış senaryo, bilinmeyen sahne ve eksik bitiş reddedilir': () {
      final wrong = data()..['scenarioId'] = 'baska-graf';
      invalid(
        () => ScenarioClipPlan.fromJson(wrong).validateAgainst(graph),
        'başka senaryoya',
      );
      final unknown = data();
      (clips(unknown).last as Map)['sceneId'] = 'olmayan-sahne';
      invalid(
        () => ScenarioClipPlan.fromJson(unknown).validateAgainst(graph),
        'mevcut olmayan sahneye',
      );
      final missing = data();
      clips(missing).removeLast();
      invalid(
        () => ScenarioClipPlan.fromJson(missing).validateAgainst(graph),
        'eksik sahneler',
      );
    },
    'Bozuk JSON, alan türleri, boş plan ve şema hatası anlaşılırdır': () {
      invalid(() => ScenarioClipPlan.fromJsonString('{'), 'JSON okunamadı');
      invalid(() => ScenarioClipPlan.fromJsonString('[]'), 'JSON kökü');
      invalid(
        () => ScenarioClipPlan.fromJson(data()..['schemaVersion'] = '99'),
        'şema sürümü',
      );
      invalid(
        () => ScenarioClipPlan.fromJson(data()..['planId'] = ''),
        'Plan kimliği',
      );
      invalid(
        () => ScenarioClipPlan.fromJson(data()..['clips'] = []),
        'boş olamaz',
      );
      invalid(
        () => ScenarioClipPlan.fromJson(data()..['clips'] = null),
        'clips liste',
      );
      invalid(
        () => ScenarioClipPlan.fromJson(data()..['clips'] = [null]),
        'clips[0]',
      );
      final value = data();
      (clips(value).first as Map)['targetDurationS'] = '6';
      invalid(() => ScenarioClipPlan.fromJson(value), 'targetDurationS sayı');
      (clips(value).first as Map)['targetDurationS'] = 6;
      (clips(value).first as Map)['productionPrompt'] = false;
      invalid(() => ScenarioClipPlan.fromJson(value), 'productionPrompt metin');
    },
    'Plan, kaynak listeler ve JSON üzerinden grafı veya kendi kliplerini değiştirmez':
        () {
          final parsed = ScenarioClipPlan.fromJsonString(input);
          final source = parsed.clips.toList();
          final plan = ScenarioClipPlan(
            schemaVersion: parsed.schemaVersion,
            planId: parsed.planId,
            scenarioId: parsed.scenarioId,
            authoringNote: parsed.authoringNote,
            continuityNotes: parsed.continuityNotes,
            clips: source,
          );
          source.clear();
          check(plan.clips.length == 7, 'Savunmalı kopya');
          immutable(() => plan.clips.clear());
          immutable(() => plan.clipsForScene('yetiskine_yonelme').clear());
          (plan.toJson()['clips'] as List).clear();
          plan.validateAgainst(graph);
          check(
            plan.clips.length == 7,
            'JSON dışa aktarımı planı değiştirmedi',
          );
          check(
            graphFile.readAsStringSync() == originalGraph,
            'Mevcut graf dosyası korundu',
          );
          check(
            ScenarioGraph.fromJsonString(originalGraph).toJsonString() ==
                graph.toJsonString(),
            'Graf bellekte korundu',
          );
        },
  };
  var failed = 0;
  for (final entry in tests.entries) {
    try {
      entry.value();
      stdout.writeln('PASS: ${entry.key}');
    } catch (error, stack) {
      failed++;
      stderr.writeln('FAIL: ${entry.key}\n$error\n$stack');
    }
  }
  stdout.writeln(
    '${tests.length - failed}/${tests.length} hedefli kontrol geçti.',
  );
  if (failed != 0) exitCode = 1;
}
