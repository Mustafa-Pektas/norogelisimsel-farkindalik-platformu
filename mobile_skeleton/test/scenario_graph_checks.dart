// Ek paket veya Flutter çalıştırıcısı gerektirmeyen davranış testleri.
// Uygulama kökünden, mevcut paket çözümlemesiyle:
// dart --disable-dart-dev --packages=.dart_tool/package_config.json test/scenario_graph_checks.dart
import 'dart:convert';
import 'dart:io';

import 'package:neuro_awareness_app/models/scenario_graph.dart';

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _invalid(void Function() action, String messagePart) {
  try {
    action();
  } on FormatException catch (error) {
    _check(
      error.message.contains(messagePart),
      'Beklenen hata "$messagePart", alınan: ${error.message}',
    );
    return;
  }
  throw StateError('Geçersiz veri kabul edildi: $messagePart');
}

Map<String, dynamic> _base() => {
  'schemaVersion': '1.0',
  'scenarioId': 'test-senaryosu',
  'title': 'Türkçe taslak',
  'language': 'tr',
  'ageMonths': 30,
  'behaviorId': 'D01',
  'cardVersion': '0.2',
  'startSceneId': 'baslangic',
  'scenes': <dynamic>[
    {'id': 'baslangic', 'description': 'Başlangıç sahnesi'},
    {'id': 'bitis', 'description': 'Açık bitiş'},
  ],
  'transitions': <dynamic>[
    {
      'fromSceneId': 'baslangic',
      'toSceneId': 'bitis',
      'description': 'Bitişe devam et',
    },
  ],
  'endSceneIds': ['bitis'],
};

List<dynamic> _list(Map<String, dynamic> json, String key) =>
    json[key] as List<dynamic>;

void main() {
  final tests = <String, void Function()>{
    'Türkçe D01 örneği ve JSON dönüşümü': () {
      final input = File('assets/scenarios/d01_scenario_graph.json')
          .readAsStringSync();
      final graph = ScenarioGraph.fromJsonString(input);
      _check(
        graph.behaviorId == 'D01' && graph.cardVersion == '0.2',
        'D01 sürümü',
      );
      _check(graph.ageMonths == 30 && graph.language == 'tr', 'Yaş ve dil');
      _check(graph.scenes.length == 5, 'Örneğin beş sahnesi olmalı');
      _check(
        graph.scenes.every((scene) => scene.id != 'isim_cagrisi') &&
            graph.transitions.length == 4,
        'Ayrı ortak çağrı düğümü kaldırılmalı; dört geçiş korunmalı',
      );
      final alternatives = graph.transitions
          .where((edge) => edge.fromSceneId == 'oyuncakla_oyun')
          .map((edge) => edge.toSceneId)
          .toSet();
      _check(
        alternatives.length == 2 &&
            alternatives.contains('yetiskine_yonelme') &&
            alternatives.contains('oyuna_devam'),
        'Çağrı öncesi ortak oyundan iki ayrı çağrı+devam alternatifine geçilmeli',
      );
      _check(graph.endSceneIds.length == 2, 'İki açık bitiş');
      _check(
        graph.authoringNote!.contains('Elle hazırlanmış'),
        'Taslak kaynağı',
      );
      final restored = ScenarioGraph.fromJsonString(
        graph.toJsonString(pretty: true),
      );
      _check(
        restored.toJsonString() == graph.toJsonString(),
        'Dönüşüm kayıpsız',
      );
      _check(
        restored.authoringNote == graph.authoringNote,
        'Taslak notu korunur',
      );
      final output = jsonDecode(graph.toJsonString()) as Map<String, dynamic>;
      _check(
        !output.containsKey('riskProfile') &&
            !output.containsKey('ground_truth') &&
            !output.containsKey('status'),
        'Taslak gözlem veya klinik sonuç taşımamalı',
      );
    },
    'Eski JSON görünüm alanları olmadan kayıpsız okunur': () {
      final input = _base();
      final graph = ScenarioGraph.fromJson(input);
      _check(graph.scenes.first.title == null, 'Başlık isteğe bağlı');
      _check(graph.scenes.first.summary == null, 'Özet isteğe bağlı');
      _check(graph.transitions.first.label == null, 'Etiket isteğe bağlı');
      _check(
        jsonEncode(graph.toJson()) == jsonEncode(input),
        'Eski JSON korunur',
      );
    },
    'Kısa görünüm metinleri tam açıklamalarla birlikte korunur': () {
      final input = _base();
      _list(
        input,
        'scenes',
      ).first.addAll({'title': 'Kısa başlık', 'summary': 'Kısa özet'});
      _list(input, 'transitions').first['label'] = 'Devam';
      final graph = ScenarioGraph.fromJsonString(
        ScenarioGraph.fromJson(input).toJsonString(),
      );
      _check(graph.scenes.first.title == 'Kısa başlık', 'Başlık dönüşümü');
      _check(graph.scenes.first.summary == 'Kısa özet', 'Özet dönüşümü');
      _check(
        graph.scenes.first.description == 'Başlangıç sahnesi',
        'Tam açıklama korunur',
      );
      _check(graph.transitions.first.label == 'Devam', 'Etiket dönüşümü');
      _check(
        graph.transitions.first.description == 'Bitişe devam et',
        'Tam geçiş korunur',
      );
    },
    'Görünüm alanlarının hatalı türleri anlaşılır hata verir': () {
      for (final field in ['title', 'summary']) {
        final data = _base();
        _list(data, 'scenes')[0] = <String, dynamic>{
          ..._list(data, 'scenes').first as Map<String, dynamic>,
          field: 5,
        };
        _invalid(() => ScenarioGraph.fromJson(data), field);
      }
      final data = _base();
      _list(data, 'transitions')[0] = <String, dynamic>{
        ..._list(data, 'transitions').first as Map<String, dynamic>,
        'label': [],
      };
      _invalid(() => ScenarioGraph.fromJson(data), 'label');
    },
    'Tek sahnelik başlangıç/bitiş geçerlidir': () {
      final data = _base();
      data['scenes'] = [
        {'id': 'baslangic', 'description': 'Tek sahne'},
      ];
      data['transitions'] = [];
      data['endSceneIds'] = ['baslangic'];
      ScenarioGraph.fromJson(data);
    },
    'Çıkışı olan döngü ve sırasız sahneler geçerlidir': () {
      final data = _base();
      _list(data, 'scenes').insert(0, {
        'id': 'tekrar',
        'description': 'Başlangıca dönebilen sahne',
      });
      _list(data, 'transitions').addAll([
        {
          'fromSceneId': 'baslangic',
          'toSceneId': 'tekrar',
          'description': 'Alternatif devam',
        },
        {
          'fromSceneId': 'tekrar',
          'toSceneId': 'baslangic',
          'description': 'Başlangıca dön',
        },
      ]);
      ScenarioGraph.fromJson(data);
    },
    'Boş senaryo kimliği reddedilir': () {
      _invalid(
        () => ScenarioGraph.fromJson(_base()..['scenarioId'] = '  '),
        'Senaryo kimliği',
      );
    },
    'Boş sahne kimliği reddedilir': () {
      final data = _base();
      (_list(data, 'scenes').first as Map)['id'] = '';
      _invalid(() => ScenarioGraph.fromJson(data), 'Sahne kimliği');
    },
    'Tekrarlı sahne kimliği reddedilir': () {
      final data = _base();
      _list(data, 'scenes').add({'id': 'bitis', 'description': 'Aynı kimlik'});
      _invalid(
        () => ScenarioGraph.fromJson(data),
        'Tekrarlı sahne kimliği: bitis',
      );
    },
    'Olmayan başlangıç reddedilir': () {
      _invalid(
        () => ScenarioGraph.fromJson(_base()..['startSceneId'] = 'yok'),
        'Başlangıç',
      );
    },
    'Olmayan geçiş kaynağı reddedilir': () {
      final data = _base();
      (_list(data, 'transitions').first as Map)['fromSceneId'] = 'yok';
      _invalid(() => ScenarioGraph.fromJson(data), 'Geçiş[0] kaynağı');
    },
    'Olmayan geçiş hedefi reddedilir': () {
      final data = _base();
      (_list(data, 'transitions').first as Map)['toSceneId'] = 'yok';
      _invalid(() => ScenarioGraph.fromJson(data), 'Geçiş[0] hedefi');
    },
    'Boş geçiş referansı reddedilir': () {
      final data = _base();
      (_list(data, 'transitions').first as Map)['toSceneId'] = ' ';
      _invalid(() => ScenarioGraph.fromJson(data), 'hedef sahne kimliği');
    },
    'Olmayan bitiş reddedilir': () {
      _invalid(
        () => ScenarioGraph.fromJson(_base()..['endSceneIds'] = ['yok']),
        'Bitiş',
      );
    },
    'Bitişsiz graf reddedilir': () {
      _invalid(
        () => ScenarioGraph.fromJson(_base()..['endSceneIds'] = []),
        'En az bir bitiş',
      );
    },
    'Tekrarlı bitiş reddedilir': () {
      _invalid(
        () => ScenarioGraph.fromJson(
          _base()..['endSceneIds'] = ['bitis', 'bitis'],
        ),
        'Tekrarlı bitiş',
      );
    },
    'Başlangıçtan kopuk sahne reddedilir': () {
      final data = _base();
      _list(data, 'scenes').add({'id': 'kopuk', 'description': 'Ulaşılamaz'});
      _invalid(
        () => ScenarioGraph.fromJson(data),
        'erişilemeyen sahneler: kopuk',
      );
    },
    'Bir dal bitse de diğer çıkmaz dal reddedilir': () {
      final data = _base();
      _list(data, 'scenes').add({'id': 'cikmaz', 'description': 'Çıkmaz dal'});
      _list(data, 'transitions').add({
        'fromSceneId': 'baslangic',
        'toSceneId': 'cikmaz',
        'description': 'Çıkmaza devam',
      });
      _invalid(
        () => ScenarioGraph.fromJson(data),
        'bitişe ulaşamayan sahneler: cikmaz',
      );
    },
    'Erişilebilir ama çıkışı olmayan döngü reddedilir': () {
      final data = _base();
      _list(data, 'scenes').add({'id': 'dongu', 'description': 'Kapalı döngü'});
      _list(data, 'transitions').addAll([
        {
          'fromSceneId': 'baslangic',
          'toSceneId': 'dongu',
          'description': 'Gir',
        },
        {
          'fromSceneId': 'dongu',
          'toSceneId': 'dongu',
          'description': 'Tekrarla',
        },
      ]);
      _invalid(
        () => ScenarioGraph.fromJson(data),
        'bitişe ulaşamayan sahneler: dongu',
      );
    },
    'Bitişten çıkış reddedilir': () {
      final data = _base();
      _list(data, 'transitions').add({
        'fromSceneId': 'bitis',
        'toSceneId': 'baslangic',
        'description': 'Terminalden çıkış',
      });
      _invalid(() => ScenarioGraph.fromJson(data), 'Bitiş sahnesinden çıkış');
    },
    'Bozuk JSON ve nesne olmayan kök anlaşılır hata verir': () {
      _invalid(() => ScenarioGraph.fromJsonString('{'), 'JSON okunamadı');
      _invalid(() => ScenarioGraph.fromJsonString('[]'), 'JSON kökü');
    },
    'Yanlış alan ve eleman türleri TypeError yerine FormatException verir': () {
      _invalid(
        () => ScenarioGraph.fromJson(_base()..['ageMonths'] = 30.5),
        'ageMonths',
      );
      _invalid(
        () => ScenarioGraph.fromJson(_base()..['scenes'] = {}),
        'scenes',
      );
      _invalid(
        () => ScenarioGraph.fromJson(_base()..['scenes'] = [null]),
        'scenes[0]',
      );
      _invalid(
        () => ScenarioGraph.fromJson(_base()..['endSceneIds'] = [4]),
        'endSceneIds[0]',
      );
      _invalid(
        () => ScenarioGraph.fromJson(_base()..remove('behaviorId')),
        'behaviorId',
      );
    },
    'Desteklenmeyen şema reddedilir': () {
      _invalid(
        () => ScenarioGraph.fromJson(_base()..['schemaVersion'] = '99'),
        'Desteklenmeyen şema',
      );
    },
    'Kurucu girdi listelerini kopyalar ve çıktıyı değiştirilemez tutar': () {
      final scenes = [ScenarioScene(id: 'tek', description: 'Tek sahne')];
      final ends = ['tek'];
      final graph = ScenarioGraph(
        schemaVersion: '1.0',
        scenarioId: 'kurucu',
        title: 'Taslak',
        language: 'tr',
        ageMonths: 30,
        behaviorId: 'D01',
        cardVersion: '0.2',
        startSceneId: 'tek',
        scenes: scenes,
        transitions: [],
        endSceneIds: ends,
      );
      scenes.clear();
      ends.clear();
      _check(
        graph.scenes.length == 1 && graph.endSceneIds.length == 1,
        'Savunmalı kopya',
      );
      try {
        graph.endSceneIds.clear();
        throw StateError('Graf listesi değiştirilebildi');
      } on UnsupportedError {
        // Beklenen: dışarıdan geçersiz graf oluşturulamaz.
      }
      final exported = graph.toJson();
      (exported['endSceneIds'] as List).clear();
      _check(
        graph.endSceneIds.length == 1,
        'JSON çıktısı grafı değiştirmemeli',
      );
      _invalid(
        () => ScenarioScene(id: '', description: 'Sahne'),
        'Sahne kimliği',
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
  stdout.writeln('${tests.length - failed}/${tests.length} test geçti.');
  if (failed != 0) exitCode = 1;
}
