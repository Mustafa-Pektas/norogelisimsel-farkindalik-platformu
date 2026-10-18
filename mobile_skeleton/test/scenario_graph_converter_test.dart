import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/models/scenario_graph.dart';
import 'package:neuro_awareness_app/models/scenario_input.dart';
import 'package:neuro_awareness_app/services/scenario_graph_converter.dart';

void main() {
  // Gerçek dosya okuması testin sanal zaman/bekleme döngüsüne bırakılmaz.
  final exampleText = File('assets/scenarios/d01_scenario_input.json').readAsStringSync();
  Map<String, dynamic> example() =>
      jsonDecode(exampleText) as Map<String, dynamic>;
  const converter = ScenarioGraphConverter();

  Matcher invalid(String field) => throwsA(
    isA<FormatException>().having(
      (error) => error.message,
      'alanı belirten hata',
      contains(field),
    ),
  );

  test('Elle hazırlanmış D01 girdisinden doğrulanmış graf üretilir', () {
    final input = ScenarioInput.fromJsonString(exampleText);
    final graph = converter.convert(input);

    expect(graph.schemaVersion, input.schemaVersion);
    expect(graph.scenarioId, input.scenarioId);
    expect(graph.title, input.title);
    expect(graph.language, 'tr');
    expect(graph.ageMonths, 30);
    expect(graph.behaviorId, 'D01');
    expect(graph.cardVersion, '0.2');
    expect(input.source, ScenarioInputSource.manualExample);
    expect(graph.authoringNote, contains('Elle hazırlanmış örnek'));
    expect(graph.authoringNote, contains('gözlenmiş davranış'));
    expect(graph.scenes.length, 5);
    expect(graph.transitions.length, 4);
    expect(graph.endSceneIds, ['ending_1', 'ending_2']);
    expect(graph.scenes.first.description, input.commonStart);
    for (var i = 0; i < input.alternatives.length; i++) {
      final alternative = input.alternatives[i];
      expect(graph.scenes[1 + 2 * i].description, alternative.continuation);
      expect(graph.scenes[2 + 2 * i].description, alternative.ending);
    }
    expect(graph.validate, returnsNormally);
    expect(
      ScenarioGraph.fromJsonString(graph.toJsonString()).toJson(),
      graph.toJson(),
    );
  });

  test('Anlatı metinleri boşluk ve satır sonları dahil aynen korunur', () {
    final json = example();
    const opening = '  Ortak başlangıç.\nİkinci satır.  ';
    const continuation = '\tDevam metni.\n';
    const ending = '\nBitiş metni.  ';
    json['commonStart'] = opening;
    json['alternatives'] = [
      {'title': ' Kısa başlık ', 'continuation': continuation, 'ending': ending},
    ];
    final graph = converter.convert(ScenarioInput.fromJson(json));

    expect(graph.scenes[0].description, opening);
    expect(graph.scenes[1].description, continuation);
    expect(graph.scenes[2].description, ending);
    expect(graph.scenes[1].title, ' Kısa başlık ');
    expect(graph.transitions[0].label, ' Kısa başlık ');
    expect(graph.transitions[0].description, continuation);
    expect(graph.transitions[1].description, ending);
  });

  for (final count in [1, 2, 3, 5]) {
    test('$count alternatif: bütün yollar ayrı devam ve bitişe bağlanır', () {
      final json = example();
      json['alternatives'] = [
        for (var i = 1; i <= count; i++)
          {'title': 'Yol $i', 'continuation': 'Devam $i', 'ending': 'Son $i'},
      ];
      final input = ScenarioInput.fromJson(json);
      final graph = converter.convert(input);

      expect(graph.startSceneId, 'start');
      expect(graph.scenes.length, 1 + 2 * count);
      expect(
        graph.scenes.map((scene) => scene.id).toSet().length,
        graph.scenes.length,
      );
      expect(graph.transitions.length, 2 * count);
      expect(graph.endSceneIds.length, count);
      expect(
        graph.transitions.where((edge) => edge.fromSceneId == 'start').length,
        count,
      );
      for (var i = 1; i <= count; i++) {
        final entry = graph.transitions.singleWhere(
          (edge) => edge.toSceneId == 'alternative_$i',
        );
        final exit = graph.transitions.singleWhere(
          (edge) => edge.fromSceneId == 'alternative_$i',
        );
        expect(entry.fromSceneId, 'start');
        expect(entry.label, 'Yol $i');
        expect(exit.toSceneId, 'ending_$i');
        expect(graph.endSceneIds, contains(exit.toSceneId));
        expect(
          graph.transitions.where((edge) => edge.fromSceneId == 'ending_$i'),
          isEmpty,
        );
      }
      expect(graph.validate, returnsNormally);
      expect(converter.convert(input).toJson(), graph.toJson());
    });
  }

  test('Model kaynağı beyanı korunur; servis çıkarım veya onay iddia etmez', () {
    final json = example()..['source'] = 'model_output';
    final input = ScenarioInput.fromJson(json);
    final graph = converter.convert(input);
    expect(input.source, ScenarioInputSource.modelOutput);
    expect(graph.authoringNote, contains('Kaynak beyanı: gerçek model çıktısı'));
    expect(graph.authoringNote, contains('bu servis çıkarım çalıştırmaz'));
    expect(graph.authoringNote, contains('doğruluğu bu dönüşümle onaylanmaz'));
  });

  for (final field in [
    'schemaVersion',
    'scenarioId',
    'title',
    'language',
    'ageMonths',
    'behaviorId',
    'cardVersion',
    'source',
    'commonStart',
    'alternatives',
  ]) {
    test('Eksik $field alanı içerik uydurmak yerine hata verir', () {
      final json = example()..remove(field);
      expect(() => ScenarioInput.fromJson(json), invalid(field));
    });
  }

  for (final field in ['title', 'continuation', 'ending']) {
    test('Alternatifte eksik/boş/yanlış türde $field alanı reddedilir', () {
      for (final value in [null, '', ' \n ', 7]) {
        final json = example();
        final alternative = (json['alternatives'] as List).first as Map;
        if (value == null) {
          alternative.remove(field);
        } else {
          alternative[field] = value;
        }
        expect(() => ScenarioInput.fromJson(json), invalid('alternatives[0]'));
        expect(() => ScenarioInput.fromJson(json), invalid(field));
      }
    });
  }

  test('Boş başlangıç, bilinmeyen kaynak/sürüm ve geçersiz yaş reddedilir', () {
    for (final entry in <String, Object>{
      'commonStart': '  ',
      'source': 'belirsiz',
      'schemaVersion': '9.0',
      'ageMonths': 0,
    }.entries) {
      final json = example()..[entry.key] = entry.value;
      final context = entry.key == 'schemaVersion' ? 'sürümü' : entry.key;
      expect(() => ScenarioInput.fromJson(json), invalid(context));
    }
    final wrongType = example()..['ageMonths'] = 30.5;
    expect(() => ScenarioInput.fromJson(wrongType), invalid('ageMonths'));
  });

  test('Alternatifler eksik, boş veya nesne yerine metin olamaz', () {
    for (final value in <Object>[
      <Object>[],
      'Yol ekle',
      ['eksik alanlar'],
    ]) {
      final json = example()..['alternatives'] = value;
      expect(() => ScenarioInput.fromJson(json), invalid('alternatives'));
    }
  });

  test('Graf alanları ve iç içe dallar sessizce yok sayılmaz', () {
    final withIds = example()..['startSceneId'] = 'kullanici-kimligi';
    expect(() => ScenarioInput.fromJson(withIds), invalid('startSceneId'));
    final nested = example();
    ((nested['alternatives'] as List).first as Map)['alternatives'] = [];
    expect(() => ScenarioInput.fromJson(nested), invalid('alternatives[0]'));
  });

  test('Bozuk JSON ve nesne olmayan kök anlaşılır hata verir', () {
    expect(() => ScenarioInput.fromJsonString('{'), invalid('JSON okunamadı'));
    expect(() => ScenarioInput.fromJsonString('[]'), invalid('JSON kökü'));
  });

  test('Doğrudan kurucu da boş içerik kabul etmez', () {
    expect(
      () => ScenarioInputAlternative(
        title: 'Yol',
        continuation: ' ',
        ending: 'Son',
      ),
      invalid('devam metni'),
    );
    final input = ScenarioInput.fromJson(example());
    expect(
      () => input.alternatives.add(input.alternatives.first),
      throwsUnsupportedError,
    );
  });
}
