import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/models/scenario_graph.dart';
import 'package:neuro_awareness_app/models/scenario_input.dart';
import 'package:neuro_awareness_app/services/scenario_graph_converter.dart';
import 'package:neuro_awareness_app/models/scenario_generation_request.dart';
import 'package:neuro_awareness_app/services/clip_plan_generation_service.dart';

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
  test('Çoklu davranış (D01 + D02) sıralı aşamalı girdi 11 sahneli 4 katmanlı karar ağacına dönüşür', () {
    final multiJson = {
      'schemaVersion': '1.1',
      'scenarioId': 'd01-d02-multi',
      'title': 'D01 ve D02 Karar Ağacı',
      'language': 'tr',
      'ageMonths': 24,
      'behaviorId': 'D01',
      'cardVersion': '0.2',
      'behaviors': [
        {'behaviorId': 'D01', 'cardVersion': '0.2'},
        {'behaviorId': 'D02', 'cardVersion': '0.2'},
      ],
      'source': 'model_output',
      'commonStart': 'Kum havuzunda oynayan çocuk ve yakındaki yetişkin.',
      'commonBehaviorIds': ['D01', 'D02'],
      'stages': [
        {
          'stageIndex': 1,
          'behaviorId': 'D01',
          'title': 'Aşama 1: İsme Tepki Gözlemi',
          'prompt': 'Yetişkin doğal ses tonuyla "Ali" diye seslenir.',
          'branches': [
            {
              'branchType': 'typical',
              'title': 'İsme Tepki Gözlendi',
              'continuation': 'Ali seslenişi duyunca küreği bırakıp başını yetişkine çevirir.',
            },
            {
              'branchType': 'atypical',
              'title': 'İsme Tepki Gözlenmedi',
              'continuation': 'Ali kumla oynamaya devam eder, başını çevirmez.',
            },
          ],
        },
        {
          'stageIndex': 2,
          'behaviorId': 'D02',
          'title': 'Aşama 2: İşaret Edilen Hedefe Yönelme Gözlemi',
          'prompt': 'Yetişkin işaret parmağıyla uzaktaki renkli kovayı işaret eder.',
          'branches': [
            {
              'branchType': 'typical',
              'title': 'İsme Yönelen Çocuk: İşarete Yönelme Gözlendi',
              'continuation': 'Ali işaret edilen kovaya başını ve bakışını çevirir.',
              'ending': 'Ortak dikkat işarete yönelme başarıyla gözlendi.',
            },
            {
              'branchType': 'atypical',
              'title': 'İşarete Yönelme Gözlenmedi',
              'continuation': 'Ali işaret edilen yöne bakmaz, kendi önüne odaklanır.',
              'ending': 'İşaret edilen hedefe yönelme gerçekleşmedi.',
            },
          ],
        },
      ],
      'alternatives': [
        {
          'title': 'D01(+) / D02(+)',
          'continuation': 'Aşama 1 ve 2 olumlu.',
          'ending': 'Hem isme tepki hem işarete yönelme yaş grubuna uygun gözlendi.',
          'behaviorIds': ['D01', 'D02'],
        },
        {
          'title': 'D01(+) / D02(-)',
          'continuation': 'Aşama 1 olumlu, Aşama 2 olumsuz.',
          'ending': 'İsme tepki var, işarete yönelme yok.',
          'behaviorIds': ['D01', 'D02'],
        },
        {
          'title': 'D01(-) / D02(+)',
          'continuation': 'Aşama 1 olumsuz, Aşama 2 olumlu.',
          'ending': 'İsme tepki yok, işarete yönelme var.',
          'behaviorIds': ['D01', 'D02'],
        },
        {
          'title': 'D01(-) / D02(-)',
          'continuation': 'Aşama 1 ve 2 olumsuz.',
          'ending': 'Ne isme tepki ne de işarete yönelme gözlendi.',
          'behaviorIds': ['D01', 'D02'],
        },
      ],
    };

    const keys = ['+D01+D02', '+D01-D02', '-D01+D02', '-D01-D02'];
    final alternatives = multiJson['alternatives'] as List;
    for (var i = 0; i < keys.length; i++) {
      (alternatives[i] as Map)['outcomeKey'] = keys[i];
    }
    final input = ScenarioInput.fromJson(multiJson);
    expect(input.stages, isNotNull);
    expect(input.stages!.length, 2);

    final graph = converter.convert(input);

    // 1 start + 2 stage1 + 4 stage2 + 4 endings = 11 scenes!
    expect(graph.scenes.length, 11);
    // 2 (start->s1) + 4 (s1->s2) + 4 (s2->endings) = 10 transitions!
    expect(graph.transitions.length, 10);
    // 4 distinct ending paths
    expect(graph.endSceneIds.length, 4);
    void verifyEveryPath(Map<String, dynamic> value) {
      final parsed = ScenarioInput.fromJson(value);
      final converted = converter.convert(parsed);
      for (final key in keys) {
        var current = converted.startSceneId;
        for (var i = 0; i < parsed.stages!.length; i++) {
          final branchType = key[i * 4] == '+' ? 'typical' : 'atypical';
          final branch = parsed.stages![i].branches.singleWhere((b) => b.branchType == branchType);
          current = converted.transitions.singleWhere((t) => t.fromSceneId == current && t.label == branch.title).toSceneId;
        }
        final end = converted.transitions.singleWhere((t) => t.fromSceneId == current).toSceneId;
        expect(converted.endSceneIds, contains(end));
        expect(converted.scenes.singleWhere((s) => s.id == end).description,
          parsed.alternatives.singleWhere((a) => a.outcomeKey == key).ending);
      }
    }
    Map<String, dynamic> copy() => jsonDecode(jsonEncode(multiJson)) as Map<String, dynamic>;
    verifyEveryPath(multiJson);
    final request = ScenarioGenerationRequest.fromJson({
      'requestVersion': '2.0', 'behaviors': multiJson['behaviors'],
      'ageMonths': 24, 'sceneContext': 'Controlled context',
    });
    final prepared = request.prepareInput(jsonEncode({
      for (final key in ['commonStart', 'commonBehaviorIds', 'stages', 'alternatives']) key: multiJson[key],
      'structure': 'branched',
    }), scenarioId: 'generated-path-test', edited: true);
    final editorJson = jsonDecode(prepared.json) as Map<String, dynamic>;
    verifyEveryPath(editorJson);
    final planRequest = ClipPlanGenerationRequest(request: request,
      graph: converter.convert(ScenarioInput.fromJson(editorJson)), planId: 'generated-path-plan');
    expect(planRequest.graph.scenarioId, 'generated-path-test');
    expect(planRequest.graph.endSceneIds, hasLength(4));
    expect((planRequest.toJson()['graph'] as Map)['endSceneIds'], planRequest.graph.endSceneIds);
    final reordered = copy();
    reordered['alternatives'] = (reordered['alternatives'] as List).reversed.toList();
    for (final stage in reordered['stages'] as List) {
      stage['branches'] = (stage['branches'] as List).reversed.toList();
    }
    verifyEveryPath(reordered);
    void rejects(void Function(Map<String, dynamic>) mutate) {
      final invalid = copy(); mutate(invalid);
      expect(() => converter.convert(ScenarioInput.fromJson(invalid)), throwsFormatException);
    }
    rejects((v) => v.remove('stages'));
    rejects((v) => v['stages'][1] = v['stages'][0]);
    rejects((v) => v['stages'] = (v['stages'] as List).reversed.toList());
    rejects((v) => v['stages'][0]['stageIndex'] = 2);
    rejects((v) => (v['stages'][0] as Map).remove('stageIndex'));
    rejects((v) => v['stages'][0]['branches'][1]['branchType'] = 'typical');
    rejects((v) => (v['stages'][0]['branches'] as List).removeLast());
    rejects((v) => v['stages'][1]['behaviorId'] = 'D10');
    rejects((v) => (v['alternatives'] as List).removeLast());
    rejects((v) => v['alternatives'][1]['outcomeKey'] = v['alternatives'][0]['outcomeKey']);
    rejects((v) => (v['alternatives'][0] as Map).remove('outcomeKey'));
    rejects((v) => v['alternatives'][0]['outcomeKey'] = '+D02+D01');

    // Validation passes completely (reachability, DAG structure, behavior coverage)
    expect(graph.validate, returnsNormally);
    expect(graph.authoringNote, contains('Planlanan çok aşamalı sıralı gözlem grafıdır'));
  });
}
