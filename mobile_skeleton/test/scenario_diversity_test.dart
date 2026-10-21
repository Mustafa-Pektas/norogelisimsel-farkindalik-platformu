import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/services/synthetic_video_service.dart';

void main() {
  group('Klinik Senaryo ve Video Prompt Çeşitlilik Motoru Testleri', () {
    test('SyntheticVideoPromptService 6 farklı zengin klinik aktivite profili içerir', () {
      expect(SyntheticVideoPromptService.clinicalProfiles.length, equals(6));

      final profileIds = SyntheticVideoPromptService.clinicalProfiles.map((p) => p.id).toList();
      expect(profileIds, containsAll([
        'CAR_WHEEL',
        'TRAIN_TRACK',
        'SHAPE_SORTER',
        'BLOCKS_ALIGNMENT',
        'SPINNING_GEARS',
        'NESTING_CUPS',
      ]));
    });

    test('generateDoctorScenario farklı variationSeed değerlerinde farklı materyal ve aktiviteler üretir', () {
      final scenario0 = SyntheticVideoPromptService.generateDoctorScenario(
        variationSeed: 0,
        ontologyCodes: ['ONT-01'],
      );

      final scenario1 = SyntheticVideoPromptService.generateDoctorScenario(
        variationSeed: 1,
        ontologyCodes: ['ONT-01'],
      );

      final scenario2 = SyntheticVideoPromptService.generateDoctorScenario(
        variationSeed: 2,
        ontologyCodes: ['ONT-01'],
      );

      // Farklı tohumlar farklı materyaller ve test kurguları üretmelidir
      expect(scenario0.materialsUsed, isNot(equals(scenario1.materialsUsed)));
      expect(scenario1.materialsUsed, isNot(equals(scenario2.materialsUsed)));

      expect(scenario0.stimulusProtocol, isNot(equals(scenario1.stimulusProtocol)));
      expect(scenario1.stimulusProtocol, isNot(equals(scenario2.stimulusProtocol)));

      // Lokomotif ve Ray Seti (Seed 1)
      expect(scenario1.materialsUsed, contains('Lokomotif'));
      // Şekil Kutusu (Seed 2)
      expect(scenario2.materialsUsed, contains('Şekil Kutusu'));
    });

    test('generateSession farklı variationSeed değerlerinde farklı video promptları üretir', () {
      final session0 = SyntheticVideoPromptService.generateSession(
        variationSeed: 0,
        ontologyCodes: ['ONT-01'],
        totalTargetSec: 180,
      );

      final session1 = SyntheticVideoPromptService.generateSession(
        variationSeed: 1,
        ontologyCodes: ['ONT-01'],
        totalTargetSec: 180,
      );

      final prompt0 = session0.steps.first.universalPrompt;
      final prompt1 = session1.steps.first.universalPrompt;

      // Seed 0 bloklar/araba içerirken Seed 1 tren/ray seti içermelidir
      expect(prompt0, isNot(equals(prompt1)));
      expect(prompt1, contains('train'));
    });
  });
}
