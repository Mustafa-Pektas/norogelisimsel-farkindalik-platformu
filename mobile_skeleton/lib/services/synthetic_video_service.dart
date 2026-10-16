import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/scenarios_data.dart';

/// Doktorlar / Klinik Değerlendiriciler İçin Saniyesiz Senaryo Dalı
class DoctorScenarioBranch {
  final String title;
  final String level; // YEŞİL, SARI, KIRMIZI
  final Color color;
  final String latency;
  final String details;
  final String clinicalOutcome;

  const DoctorScenarioBranch({
    required this.title,
    required this.level,
    required this.color,
    required this.latency,
    required this.details,
    required this.clinicalOutcome,
  });
}

/// Klinik Araştırmacılar ve Hekimler İçin Test Kurgusu ve AI Ölçüm Parametreleri
class DoctorClinicalScenario {
  final String code;
  final String title;
  final String category;
  final int targetAgeMonths;
  final String ageGroupLabel;
  final String riskProfile;
  final String engineUsed;
  final String expectedNorm;
  final String riskThreshold;
  final String clinicEnvironment;
  final String materialsUsed;
  final String stimulusProtocol; // Uyaran ve Test Kurgusu
  final List<DoctorScenarioBranch> branches; // Referans Davranış Aralıkları
  final List<String> visionMetrics; // AI & Biyomekanik Ölçüm Parametreleri
  final String measurementCriteria; // Görüntü işleme kriterleri
  final String technicalNote;

  const DoctorClinicalScenario({
    required this.code,
    required this.title,
    required this.category,
    required this.targetAgeMonths,
    required this.ageGroupLabel,
    required this.riskProfile,
    required this.engineUsed,
    required this.expectedNorm,
    required this.riskThreshold,
    required this.clinicEnvironment,
    required this.materialsUsed,
    required this.stimulusProtocol,
    required this.branches,
    required this.visionMetrics,
    required this.measurementCriteria,
    required this.technicalNote,
  });

  /// Test adımlarını ve gözlem detaylarını Markdown olarak dışa aktarır
  String exportDoctorMarkdown() {
    final sb = StringBuffer();
    sb.writeln('# [$code] $title — Test ve Gözlem Detayları');
    sb.writeln('**Yaş Grubu:** $targetAgeMonths Ay ($ageGroupLabel)');
    sb.writeln('**Gözlem Durumu:** ${riskProfile.toUpperCase()}');
    sb.writeln('**Üretim Motoru:** $engineUsed');
    sb.writeln('**Beklenen Normal Davranış:** $expectedNorm\n');
    sb.writeln('## 1. Test Nasıl Yapılacak?');
    sb.writeln(stimulusProtocol);
    sb.writeln('\n**Ortam:** $clinicEnvironment');
    sb.writeln('**Kullanılacak Eşyalar:** $materialsUsed\n');
    sb.writeln('## 2. Çocuk Nasıl Tepki Verebilir?');
    for (final b in branches) {
      sb.writeln('### [${b.level}] ${b.title}');
      sb.writeln('- **Tepki Süresi:** ${b.latency}');
      sb.writeln('- **Davranış:** ${b.details}');
      sb.writeln('- **Sonuç:** ${b.clinicalOutcome}\n');
    }
    sb.writeln('## 3. Kamera ve Sistemin Takip Ettiği Noktalar');
    for (final c in visionMetrics) {
      sb.writeln('- $c');
    }
    sb.writeln('\n*Not: $technicalNote*');
    return sb.toString();
  }
}

/// Her bir 3-10 saniyelik video klibinin evrensel tanımı (Tüm Video Yapay Zekalarıyla Uyumlu)
class SyntheticVideoStep {
  final int stepNumber;
  final String blockId;
  final String blockType; // BASE_PLAY, STIMULUS, REACTION, TRANSITION, COOLDOWN
  final int startSec;
  final int endSec;
  final int durationSec;
  final String? ontologyCode; // ONT-01, ONT-02, ONT-06, ONT-08 vb.
  final String phaseName;
  final String title;
  final String cameraMovement;
  final String actionDescription;
  final String clinicalChecklist; // Gözlem kontrol listesi (teşhis/eğitim içermez)
  final String universalPrompt; // Tüm AI modelleri (Veo, Runway, Luma, Kling, Sora) ile uyumlu İngilizce prompt
  final String continuityNote; // Video uzatma / extend veya yeni sahne direktifi
  final Map<String, dynamic> metadata;

  SyntheticVideoStep({
    required this.stepNumber,
    required this.blockId,
    required this.blockType,
    required this.startSec,
    required this.endSec,
    required this.durationSec,
    this.ontologyCode,
    required this.phaseName,
    required this.title,
    required this.cameraMovement,
    required this.actionDescription,
    required this.clinicalChecklist,
    required this.universalPrompt,
    required this.continuityNote,
    required this.metadata,
  });

  String get timeFormatted {
    final m1 = (startSec ~/ 60).toString().padLeft(2, '0');
    final s1 = (startSec % 60).toString().padLeft(2, '0');
    final m2 = (endSec ~/ 60).toString().padLeft(2, '0');
    final s2 = (endSec % 60).toString().padLeft(2, '0');
    return '$m1:$s1 - $m2:$s2';
  }
}

/// 3-4 Dakikalık oturumun tamamını temsil eden veri modeli
class SyntheticVideoSession {
  final String title;
  final int targetAgeMonths;
  final int totalDurationSec;
  final int blockDurationSec;
  final int totalStepsCount;
  final String riskProfile;
  final String characterDescription;
  final String environmentDescription;
  final List<SyntheticVideoStep> steps;

  SyntheticVideoSession({
    required this.title,
    required this.targetAgeMonths,
    required this.totalDurationSec,
    required this.blockDurationSec,
    required this.totalStepsCount,
    required this.riskProfile,
    required this.characterDescription,
    required this.environmentDescription,
    required this.steps,
  });

  String _formatTime(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Doktorlar ve kullanıcılar için saniyesiz, sade senaryo akışı
  String exportDoctorCleanScenario() {
    final sb = StringBuffer();
    sb.writeln('# $title\n');
    sb.writeln('**Hedef Yaş Grubu:** $targetAgeMonths Ay');
    sb.writeln('**Gözlem Durumu:** ${riskProfile.toUpperCase()}\n');
    for (final s in steps) {
      sb.writeln('### Adım ${s.stepNumber}: ${s.title}');
      sb.writeln('${s.actionDescription}\n');
    }
    return sb.toString();
  }

  /// Tüm seansı evrensel promptlar ve klinik kontrol listesiyle Markdown formatında dışa aktarır
  String exportFullMarkdown() {
    final sb = StringBuffer();
    sb.writeln('# Sentetik Klinik Gözlem Seansı ve Video Üretim Promptları');
    sb.writeln('**Uyumlu Modeller:** Google Veo, Runway Gen-3, Luma Dream Machine, Kling AI, OpenAI Sora, Pika');
    sb.writeln('**Hedef Yaş Grubu:** $targetAgeMonths Ay');
    sb.writeln('**Toplam Seans Süresi:** ${_formatTime(totalDurationSec)} ($totalDurationSec sn • $totalStepsCount Sıralı Klip)');
    sb.writeln('**Klip Başına Süre:** ${blockDurationSec}s');
    sb.writeln('**Gözlem Profili:** ${riskProfile.toUpperCase()}');
    sb.writeln('\n---\n');

    for (final s in steps) {
      sb.writeln('### KLİP ${s.stepNumber.toString().padLeft(2, '0')} [${s.timeFormatted}] — ${s.title}');
      sb.writeln('- **Faz:** ${s.phaseName}');
      sb.writeln('- **Sahnede Gerçekleşen Eylem:** ${s.actionDescription}');
      sb.writeln('- **Klinik Gözlem Kontrol Listesi:** ${s.clinicalChecklist}');
      sb.writeln('- **Kamera Açısı & Lens:** ${s.cameraMovement}');
      sb.writeln('- **Devamlılık Direktifi:** ${s.continuityNote}\n');
      sb.writeln('```text');
      sb.writeln(s.universalPrompt);
      sb.writeln('```\n');
      sb.writeln('---\n');
    }
    return sb.toString();
  }

  /// Sadece İngilizce video promptlarını sırasıyla listeler
  String exportEnglishPromptsOnly() {
    final sb = StringBuffer();
    for (final s in steps) {
      sb.writeln('// CLIP ${s.stepNumber.toString().padLeft(2, '0')} (${s.timeFormatted}) - ${s.title}');
      sb.writeln(s.universalPrompt);
      sb.writeln('\n');
    }
    return sb.toString();
  }

  /// Makine tarafından okunabilir JSON yapısı
  String exportGroundTruthJson() {
    final data = {
      'session_meta': {
        'target_age_months': targetAgeMonths,
        'total_duration_sec': totalDurationSec,
        'clip_duration_sec': blockDurationSec,
        'total_steps': totalStepsCount,
        'risk_profile': riskProfile,
        'supported_ai_engines': ['Google Veo', 'Runway Gen-3', 'Luma Dream Machine', 'Kling AI', 'Sora'],
      },
      'character': characterDescription,
      'environment': environmentDescription,
      'clips': steps.map((s) => {
        'clip_index': s.stepNumber,
        'block_id': s.blockId,
        'timestamp': s.timeFormatted,
        'start_sec': s.startSec,
        'end_sec': s.endSec,
        'phase': s.phaseName,
        'title': s.title,
        if (s.ontologyCode != null) 'ontology': s.ontologyCode,
        'clinical_checklist': s.clinicalChecklist,
        'camera': s.cameraMovement,
        'continuity_directive': s.continuityNote,
        'prompt': s.universalPrompt,
        'metadata': s.metadata,
      }).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }
}

/// 0 İNTERNET, 0 KOTA İLE ÇALIŞAN EVRENSEL SENTETİK VİDEO VE SENARYO MOTORU
class SyntheticVideoPromptService {
  /// DOKTORLAR VE KLİNİK DEĞERLENDİRİCİLER İÇİN SANİYESİZ SEANS SENARYOSU
  static DoctorClinicalScenario generateDoctorScenario({
    int ageMonths = 18,
    String ontologyCode = 'ONT-01',
    String riskProfile = 'atipik',
    String engineUsed = '0 MB Yerel Klinik Motoru',
    String? customEnvironment,
    String? customMaterials,
  }) {
    // 1. Hedef Ontolojiyi bul
    final base = ScenariosRepository.allScenarios.firstWhere(
      (s) => s.code == ontologyCode,
      orElse: () => ScenariosRepository.allScenarios.first,
    );

    // 2. Yaş grubunu ve yaşa özel beklentiyi belirle
    String ageGroupLabel;
    if (ageMonths < 18) {
      ageGroupLabel = '12–18 Ay';
    } else if (ageMonths < 24) {
      ageGroupLabel = '18–24 Ay';
    } else {
      ageGroupLabel = '24–36 Ay';
    }

    final expectedNorm = base.ageBreakdowns[ageGroupLabel] ??
        'Bu gelişim döneminde sesli ve görsel uyarana yönelik amaçlı yönelim ve göz kontağı beklenir.';

    // 3. Ortam ve Kullanılacak Eşyalar
    final env = (customEnvironment != null && customEnvironment.trim().isNotEmpty)
        ? customEnvironment.trim()
        : 'Sakin bir oda; televizyon veya telefon gibi dikkat dağıtıcılar kapalı, yerde halı veya alçak bir masa.';

    final mat = (customMaterials != null && customMaterials.trim().isNotEmpty)
        ? customMaterials.trim()
        : 'Çocuğun ilgisini çekecek 2-3 ahşap blok, çıngırak veya oyuncak araba.';

    // 4. Test Nasıl Yapılacak? (Adım adım uygulama)
    final stimulusText = '''
• Nerede Durulacak: Çocuğun biraz arkasında veya çaprazında (1-1.5 metre mesafede), doğrudan görüş açısına girmeden durun. Çocuğun elindeki oyuncağa dokunmayın.
• Nasıl Seslenilecek: Normal bir ses tonuyla, bağırmadan 1 kez adını söyleyin (veya oyuncağı gösterin).
• Ne Kadar Beklenecek: Seslendikten sonra hemen araya girmeyin, çocuğun tepki vermesi için 3 saniye bekleyin.
• Bakmazsa Ne Yapılacak: 3 saniye içinde bakmazsa, aynı şekilde bir kez daha seslenin. En fazla 3 kere deneyin.''';

    // 5. Davranışsal Dallanma (FSM Branches)
    final rawBranches = base.getBranchesForAge(ageGroupLabel);
    final branches = <DoctorScenarioBranch>[];

    for (final rb in rawBranches) {
      branches.add(
        DoctorScenarioBranch(
          title: rb.title,
          level: rb.level,
          color: rb.color,
          latency: rb.latency,
          details: rb.details,
          clinicalOutcome: rb.clinicalOutcome,
        ),
      );
    }

    if (branches.isEmpty) {
      branches.addAll([
        const DoctorScenarioBranch(
          title: 'Hemen Döner ve Gülümser (Normal)',
          level: 'YEŞİL',
          color: Colors.green,
          latency: '1.5 saniye içinde',
          details: 'Seslenir seslenmez 1.5 saniye içinde kafasını çevirir, gözünüzün içine bakar ve güler yüzle karşılık verir.',
          clinicalOutcome: 'Yaşına tam uygun, beklenen normal tepki.',
        ),
        const DoctorScenarioBranch(
          title: 'Geç Döner / Yavaş Kalır (Takip Edilmeli)',
          level: 'SARI',
          color: Colors.amber,
          latency: '1.5 - 3 saniye',
          details: 'İlk seslenişte bakmaz, ikinci seslenişte yavaşça döner ve çok kısa bakar.',
          clinicalOutcome: 'Dikkat dağınıklığı veya hafif gecikme; tekrar gözlemlemek faydalı olur.',
        ),
        const DoctorScenarioBranch(
          title: 'Hiç Bakmaz / Oralı Olmaz (Şüpheli)',
          level: 'KIRMIZI',
          color: Colors.red,
          latency: '3 saniyeden uzun / Yanıtsız',
          details: '3 defa seslenseniz de hiç oralı olmaz, oyuncağına dalıp gider, sesin nereden geldiğine bakmaz.',
          clinicalOutcome: 'Dikkat çeken bir durum; bir uzmanın çocuğu detaylı incelemesi iyi olur.',
        ),
      ]);
    }

    // 6. Sistemin İzlediği Noktalar
    final visionMetrics = [
      'Tepki Süresi: Çocuğa seslendikten sonra kafasını çevirmesi kaç saniye sürdü? (1.5 saniye altı normal sayılır).',
      'Kafasını Çevirme: Sesi duyduğunda kafasını sese doğru net bir şekilde çevirdi mi?',
      'Göz Teması: Gözlerini doğrudan size çevirip en az 1 saniye baktı mı?',
      'Gülümseme ve Mimik: Bakarken yüzü güldü mü, karşılıklı bir etkileşim kurdu mu?',
      'Tekrarlayan Hareketler: Tek bir oyuncağa (örneğin teker çevirme) takılıp kalma veya ellerini sallama gibi hareketler var mı?',
    ];

    return DoctorClinicalScenario(
      code: base.code,
      title: base.title,
      category: base.category,
      targetAgeMonths: ageMonths,
      ageGroupLabel: ageGroupLabel,
      riskProfile: riskProfile,
      engineUsed: engineUsed,
      expectedNorm: expectedNorm,
      riskThreshold: base.riskThreshold,
      clinicEnvironment: env,
      materialsUsed: mat,
      stimulusProtocol: stimulusText,
      branches: branches,
      visionMetrics: visionMetrics,
      measurementCriteria: base.measurementCriteria,
      technicalNote: 'Bu sistem teşhis koymaz; sadece çocuğun tepkilerini ve sürelerini daha rahat takip edebilmeniz için yardımcı bir araçtır.',
    );
  }

  /// Dinamik parametrelere göre 3-4 dakikalık eksiksiz seans ve 3-10 sn evrensel klip promptlarını üretir (Admin)
  static SyntheticVideoSession generateSession({
    int ageMonths = 18,
    int totalTargetSec = 210, // 3.5 dakika (180 - 240 saniye arası)
    int blockDurationSec = 8,  // 3 - 10 saniye arası
    String riskProfile = 'atipik', // 'atipik', 'tipik', 'gecikmeli'
    String? ontologyCode,
    List<String>? ontologyCodes,
  }) {
    final dur = blockDurationSec.clamp(3, 10);
    final targetSec = totalTargetSec.clamp(180, 240);

    // 1. Hedef davranış kodlarını belirle
    final List<String> targetOntologies = [];
    if (ontologyCodes != null && ontologyCodes.isNotEmpty) {
      targetOntologies.addAll(ontologyCodes);
    } else if (ontologyCode != null && ontologyCode.isNotEmpty) {
      targetOntologies.add(ontologyCode);
    } else {
      targetOntologies.addAll(['ONT-01', 'ONT-02']);
    }

    // 2. YAŞA ÖZEL KARAKTER VE ÇEVRE TANIMLARI (Fotogerçekçi devamlılık tokenları)
    final charSpec = _getCharacterSpec(ageMonths);
    final envSpec = _getEnvironmentSpec(ageMonths);
    const styleAnchor =
        'Cinematic 4K, photorealistic, Arri Alexa 35, Cooke S7/i 40mm lens, aperture f/2.0, 24fps, natural toddler kinematics, anatomically accurate hands with distinct five fingers, authentic skin subsurface scattering, zero morphing, zero artifacts.';

    // 3. KLİNİK FAZ ŞABLONLARI (Seçilen tüm ontolojileri dinamik oluşturur)
    final rawPhases = _buildClinicalPhases(ageMonths, riskProfile, targetOntologies);

    // 4. DOĞRUSAL DİLİMLEME VE SÜRE HESABI
    final steps = <SyntheticVideoStep>[];
    var currentSec = 0;
    var stepIndex = 1;
    var phasePointer = 0;

    while (currentSec < targetSec && phasePointer < rawPhases.length) {
      final phaseData = rawPhases[phasePointer];
      final clipEndSec = (currentSec + dur > targetSec) ? targetSec : currentSec + dur;
      final actualDuration = clipEndSec - currentSec;

      if (actualDuration < 2) break; // 2 saniyeden kısa artık klip bırakma

      final bId = 'CLIP_${stepIndex.toString().padLeft(2, '0')}_${phaseData['type']}';

      // İkinci bazlı eylem zamanlaması
      final choreo = _createChoreography(
        actualDuration,
        phaseData['p1'] as String,
        phaseData['p2'] as String,
        phaseData['p3'] as String,
      );

      String promptText;
      String continuityDirective;

      if (stepIndex == 1) {
        continuityDirective = 'BAŞLANGIÇ VİDEOSU (Tüm AI Modelleri): Bu promptu ilk klip olarak girin (Süre: ${actualDuration}s).';
        promptText =
            'A locked-off wide cinematic shot of a $charSpec. Setting: $envSpec. Camera: ${phaseData['cam']}. Second-by-second action sequence: $choreo. Continuity anchor: Maintain exact facial features, hair wisps, clothing textures, and natural morning daylight. Standards: $styleAnchor.';
      } else {
        final prevBlockId = steps.last.blockId;
        continuityDirective = 'DEVAM / UZATMA KLİBİ (Extend Video): $prevBlockId klibinin son karesinden "Extend / Continue Video" direktifiyle üretin (Süre: ${actualDuration}s).';
        promptText =
            'Continuing seamlessly from the exact ending pose and camera angle of the previous shot. Subject: Same $charSpec. Environment: Same $envSpec, exact room geometry. Camera movement: ${phaseData['cam']}. Timeline action: $choreo. Strict continuity: Lock facial identity, wardrobe colors, and room ambient lighting (3800K). Standards: $styleAnchor.';
      }

      steps.add(
        SyntheticVideoStep(
          stepNumber: stepIndex,
          blockId: bId,
          blockType: phaseData['type'] as String,
          startSec: currentSec,
          endSec: clipEndSec,
          durationSec: actualDuration,
          ontologyCode: phaseData['ont'] as String?,
          phaseName: phaseData['phase'] as String,
          title: phaseData['title'] as String,
          cameraMovement: phaseData['cam'] as String,
          actionDescription: phaseData['action'] as String,
          clinicalChecklist: phaseData['checklist'] as String,
          universalPrompt: promptText,
          continuityNote: continuityDirective,
          metadata: phaseData['meta'] as Map<String, dynamic>,
        ),
      );

      currentSec = clipEndSec;
      stepIndex++;
      phasePointer++;

      // Eğer süre dolmadan şablon biterse, kapanış ve serbest oyunla süreyi tamamla
      if (phasePointer >= rawPhases.length && currentSec < targetSec) {
        rawPhases.add(_createCooldownPhase(currentSec, targetSec));
      }
    }

    final ontLabel = targetOntologies.join(', ');
    return SyntheticVideoSession(
      title: '$ageMonths Ay Klinik Gözlem Senaryosu ($ontLabel)',
      targetAgeMonths: ageMonths,
      totalDurationSec: currentSec,
      blockDurationSec: dur,
      totalStepsCount: steps.length,
      riskProfile: riskProfile,
      characterDescription: charSpec,
      environmentDescription: envSpec,
      steps: steps,
    );
  }

  static String _createChoreography(int dur, String p1, String p2, String p3) {
    final t1 = (dur / 3).round().clamp(1, dur);
    final t2 = ((2 * dur) / 3).round().clamp(2, dur);
    return '[00:00-00:${t1.toString().padLeft(2, '0')}s]: $p1 [00:${t1.toString().padLeft(2, '0')}s-00:${t2.toString().padLeft(2, '0')}s]: $p2 [00:${t2.toString().padLeft(2, '0')}s-00:${dur.toString().padLeft(2, '0')}s]: $p3';
  }

  /// Yaşa göre fiziksel ve motor görünüm
  static String _getCharacterSpec(int age) {
    if (age <= 14) {
      return '12-month-old infant, cherubic rounded cheeks, fine wispy golden baby hair, soft warm skin, seated on carpet with occasional slight balance sway. Wardrobe: cream organic cotton soft knit romper with wooden buttons.';
    } else if (age <= 20) {
      return '18-month-old toddler boy with natural fine curly light-brown hair, expressive hazel eyes with corneal catchlights, chubby toddler hands with five distinct fingers, barefoot on rug. Wardrobe: mustard-yellow ribbed corduroy dungarees over a heather-white soft t-shirt.';
    } else if (age <= 28) {
      return '24-month-old toddler, balanced upright sitting posture, soft wavy chestnut hair, curious infant gaze, nimble toddler fingers. Wardrobe: navy denim toddler overalls over a soft heather-grey long-sleeve cotton shirt.';
    } else {
      return '36-month-old young child, clear focused gaze, soft brown hair parted naturally, agile fine motor hand movements. Wardrobe: olive-green cotton play trousers with elastic waistband and a warm oatmeal knit sweater.';
    }
  }

  /// Mekan ve nesne detayları
  static String _getEnvironmentSpec(int age) {
    return 'spacious Scandinavian minimalist nursery playroom, clean matte eggshell-white walls, European natural ash hardwood floor beneath a plush cream geometric wool rug, soft diffused 3800K natural morning window daylight. Props: smooth beechwood cubic blocks, cherry-red wooden convertible toy car, pastel-blue stacking cups, clear acrylic toy box.';
  }

  /// Klinik Faz Şablonları (Gözlem Kontrol Listesi formatında, birden fazla ontolojiyi sırayla kurgular)
  static List<Map<String, dynamic>> _buildClinicalPhases(int age, String risk, [dynamic ontologyTarget]) {
    final List<String> selectedCodes = [];
    if (ontologyTarget is List<String>) {
      selectedCodes.addAll(ontologyTarget);
    } else if (ontologyTarget is String && ontologyTarget.isNotEmpty) {
      selectedCodes.add(ontologyTarget);
    } else {
      selectedCodes.addAll(['ONT-01', 'ONT-02']);
    }

    final phases = <Map<String, dynamic>>[];

    // 1. FAZ 1: DOĞAL TABAN GÖZLEMİ (SERBEST OYUN)
    phases.addAll([
      {
        'title': 'Bloklarla Doğal Oyun Başlangıcı',
        'type': 'BASE_PLAY',
        'phase': 'Faz 1: Doğal Taban Gözlemi',
        'cam': 'Static locked-off tripod shot at 35cm eye-level, 40mm lens',
        'action': 'Çocuk halıda bağdaş kurmuş iki ahşap bloğu ritmik şekilde birbirine hafifçe vurur.',
        'p1': 'Toddler sits on the plush cream geometric rug, holding one beechwood block in each hand, gently tapping them together.',
        'p2': 'Concentrates on the tactile sound, shifting balance slightly, fingers naturally adjusting grip on smooth wooden grain.',
        'p3': 'Slowly places the left block down onto the rug while keeping eyes focused downward in calm independent play.',
        'checklist': 'Taban Motor Ölçümü: El-nesne kavrama (pincer/palmar), gövde dengesi, nesne manipülasyonu.',
        'meta': {'phase_code': 'P1_BASELINE', 'is_stimulus': false},
      },
      {
        'title': 'İkinci Bloğu Üst Üste Koyma Denemesi',
        'type': 'BASE_PLAY',
        'phase': 'Faz 1: Doğal Taban Gözlemi',
        'cam': 'Eye-level shot, slow imperceptible smooth zoom-in toward working toddler hands',
        'action': 'Çocuk yerdeki bloğun üstüne elindeki diğer bloğu dikkatlice koymaya çalışır.',
        'p1': 'Toddler holds the second beechwood cube directly above the base block, wrist steadying with fine motor concentration.',
        'p2': 'Carefully balances top cube onto bottom cube, releasing fingers slowly with focused caution.',
        'p3': 'Pulls hands back gently to thighs, watching the two-block tower stand stably.',
        'checklist': 'İnce Motor Koordinasyon: İki el koordinasyonu, kule yapma motor planlaması.',
        'meta': {'phase_code': 'P1_STACKING', 'is_stimulus': false},
      },
    ]);

    // 2. SEÇİLEN TÜM HEDEF DAVRANIŞLAR İÇİN UYARAN VE TEPKİ BLOKLARI
    int phaseNum = 2;
    for (final code in selectedCodes) {
      phases.addAll(_getPhasesForCode(code, age, risk, phaseNum++));
    }

    // 3. KAPANIS VE SEANS TAMAMLAMA
    phases.addAll([
      {
        'title': 'Kapanış — Peluş Ayıya Sarılma ve Sakinleşme',
        'type': 'COOLDOWN',
        'phase': 'Faz $phaseNum: Seans Kapanışı',
        'cam': 'Medium shot at 40cm height, gentle warm lighting',
        'action': 'Çocuk peluş ayıyı iki eliyle göğsüne bastırır, sakin oturur.',
        'p1': 'Toddler gently wraps arms around small plush teddy bear resting beside blocks, pressing fur against corduroy dungarees.',
        'p2': 'Strokes plush ear with thumb, looking quietly toward sunlight across ash wood floor.',
        'p3': 'Remains in peaceful resting sitting posture, breathing gently.',
        'checklist': 'Duyusal Regülasyon: Seans bitiminde dokunsal rahatlama ve dingin duruş.',
        'meta': {'phase_code': 'P_COOLDOWN'},
      },
      {
        'title': 'Kapanış — Halıda Sakin Oturma ve Seansın Tamamlanması',
        'type': 'COOLDOWN',
        'phase': 'Faz $phaseNum: Seans Kapanışı',
        'cam': 'Slow cinematic pull-back tracking out to full wide room perspective, fading gently',
        'action': 'Kamera yavaşça geriye çekilir; çocuk oyuncakların ortasında huzurla oturur, seans tamamlanır.',
        'p1': 'Toddler sits serenely in center of cream geometric rug, surrounded by wooden blocks, red car, and teddy bear.',
        'p2': 'Hands rest softly in lap, head held naturally upright in warm sunbeams streaming through window.',
        'p3': 'Camera holds tranquil wide composition as clinical screening observation concludes seamlessly.',
        'checklist': 'Seans Tamamlandı: Seçilen tüm ontolojik uyaranlar ve gözlemler başarıyla kaydedildi.',
        'meta': {'phase_code': 'P_COMPLETE'},
      },
    ]);

    return phases;
  }

  static List<Map<String, dynamic>> _getPhasesForCode(String code, int age, String risk, int phaseNum) {
    final isAtypical = risk == 'atipik';
    final isDelayed = risk == 'gecikmeli';

    switch (code) {
      case 'ONT-01':
        return [
          {
            'title': 'ONT-01 Uyaranı — Yetişkin Arkadan İsim Seslenir',
            'type': 'STIMULUS',
            'phase': 'Faz $phaseNum: İsme Tepki Gözlemi (ONT-01)',
            'ont': 'ONT-01',
            'cam': 'Over-the-shoulder medium shot from behind child; adult face strictly out of frame',
            'action': 'Çocuk arabayla ilgilenirken, arkasındaki yetişkin net bir sesle "Ali!" diye seslenir (t₀).',
            'p1': 'Toddler remains seated examining the car hood. Behind the child, adult leans forward slightly without physical contact.',
            'p2': 'Adult delivers clear verbal auditory stimulus: calls the child\'s name in a firm, warm voice: "Ali!".',
            'p3': 'Adult pauses 2 seconds, then repeats the name clearly: "Ali!". Child\'s hands remain on the red car.',
            'checklist': 'Uyaran Protokolü: Yetişkin görüş alanına girmeden arkadan net sesle seslenir. Zaman sayacı (t0) başlar.',
            'meta': {'phase_code': 'P${phaseNum}_ONT01_STIM', 'is_stimulus': true, 'ontology': 'ONT-01'},
          },
          {
            'title': isAtypical
                ? 'ONT-01 Tepkisi — Tepkisizlik / Nesneye Kilitlenme (Atipik)'
                : (isDelayed
                    ? 'ONT-01 Tepkisi — Gecikmeli Baş Dönüşü (Gecikmeli)'
                    : 'ONT-01 Tepkisi — Hızlı Yönelim ve Göz Teması (Tipik)'),
            'type': 'REACTION',
            'phase': 'Faz $phaseNum: İsme Tepki Gözlemi (ONT-01)',
            'ont': 'ONT-01',
            'cam': 'Tight 50mm close-up focusing on child\'s eyes, facial landmarks, and head rotation',
            'action': isAtypical
                ? 'Çocuk ismine hiç tepki vermez (Δt > 3.0s). Başını kaldırmaz, arabanın tekerini döndürmeye devam eder.'
                : (isDelayed
                    ? 'Çocuk çağrıldıktan 2.5 saniye sonra yavaşça başını hafifçe yana çevirir, kısa bakar.'
                    : 'Çocuk seslenildiği anda (1.2 saniye içinde) başını hızla yetişkine çevirir ve gülümseyerek göz teması kurar.'),
            'p1': isAtypical
                ? 'Despite clear vocal call, toddler exhibits complete absence of head orienting; head yaw angle stays under 5 degrees.'
                : (isDelayed
                    ? 'Toddler stays looking at car for 2 seconds, then slowly begins a sluggish, delayed head rotation toward the voice.'
                    : 'Within 1.2 seconds of hearing name, toddler smoothly rotates head 65 degrees toward the adult voice.'),
            'p2': isAtypical
                ? 'Eyes remain rigidly glued to the red car wheel; index finger repeatedly spins wheel with zero social glance.'
                : (isDelayed
                    ? 'Offers a brief 0.5-second fleeting glance toward adult\'s body level, but quickly lowers gaze back to the car.'
                    : 'Establishes direct, warm eye contact with adult; mouth curls into an open curious toddler smile.'),
            'p3': isAtypical
                ? 'Total absence of eye contact or head orienting; unperturbed solitary fixation.'
                : (isDelayed
                    ? 'Neutral, expressionless face; turns back to the toy without reciprocal smile.'
                    : 'Maintains sustained social connection for 2 full seconds before naturally glancing back to play.'),
            'checklist': isAtypical
                ? 'Klinik Ölçüt: Baş yönelim açısı < 10°, Tepki gecikmesi Δt > 3.0s (Tepkisiz), Göz teması: Yok.'
                : (isDelayed
                    ? 'Klinik Ölçüt: Baş yönelim açısı 35°, Tepki gecikmesi 2.0s < Δt ≤ 4.0s (Gecikmeli), Göz teması: Kısa.'
                    : 'Klinik Ölçüt: Baş yönelim açısı > 60°, Tepki gecikmesi Δt ≤ 1.5s (Hızlı), Göz teması: Doğrudan ve tebessümlü.'),
            'meta': {'phase_code': 'P${phaseNum}_ONT01_REACT', 'risk_variant': risk},
          },
          {
            'title': 'ONT-01 Sonrası — Oyuna Geri Dönüş Geçişi',
            'type': 'TRANSITION',
            'phase': 'Faz $phaseNum: İsme Tepki Gözlemi (ONT-01)',
            'cam': 'Smooth continuous pull-back on motorized slider to wide establishing shot',
            'action': 'Kamera geniş açıya çekilir, çocuk arabayı halıda hafifçe ileri iter, serbest oyuna döner.',
            'p1': 'Toddler places palm flat on the geometric rug pile next to the car.',
            'p2': 'Pushes the red wooden car forward 25 cm, watching wheels roll across the floor.',
            'p3': 'Sits in stable posture, returning to baseline calm playtime state.',
            'checklist': 'Geçiş Davranışı: Uyarandan sonra oyun ortamına regüle olma süreci.',
            'meta': {'phase_code': 'P${phaseNum}_TRANSITION'},
          },
        ];

      case 'ONT-02':
        return [
          {
            'title': 'ONT-02 Uyaranı — Yetişkin Uzaktaki Balonu İşaret Eder',
            'type': 'STIMULUS',
            'phase': 'Faz $phaseNum: Ortak Dikkat Gözlemi (ONT-02)',
            'ont': 'ONT-02',
            'cam': 'Medium wide shot capturing child on rug while adult\'s arm enters frame on right',
            'action': 'Yetişkin parmağıyla odanın diğer köşesindeki büyük sarı balonu gösterir: "Ali bak balona!" (t₀).',
            'p1': 'Toddler sits holding the blue cup in both hands on the rug.',
            'p2': 'Adult extends right arm into frame, index finger pointing upward across room toward a large yellow ball: "Ali, look at the big balloon!".',
            'p3': 'Adult holds pointing vector completely static for 3 full seconds, encouraging gaze following.',
            'checklist': 'Uyaran Protokolü: Yetişkin belirgin işaret parmağı jesti ve ses tonuyla 2.5m uzaktaki hedefi gösterir (t0).',
            'meta': {'phase_code': 'P${phaseNum}_ONT02_STIM', 'is_stimulus': true, 'ontology': 'ONT-02'},
          },
          {
            'title': isAtypical
                ? 'ONT-02 Tepkisi — İşareti Görmezden Gelme (Atipik)'
                : (isDelayed
                    ? 'ONT-02 Tepkisi — Sadece Parmağa Bakma (Gecikmeli)'
                    : 'ONT-02 Tepkisi — İşaret Edilen Hedefe Bakış (Tipik)'),
            'type': 'REACTION',
            'phase': 'Faz $phaseNum: Ortak Dikkat Gözlemi (ONT-02)',
            'ont': 'ONT-02',
            'cam': 'Medium close-up framing child\'s head, eye vector, and facial affect',
            'action': isAtypical
                ? 'Çocuk işaret edilen yöne bakmaz, elindeki kupaya bakmayı sürdürür.'
                : (isDelayed
                    ? 'Çocuk 2 saniye sonra başını yarım çevirir; uzaktaki balona değil sadece işaret eden parmağa bakar.'
                    : 'Çocuk işaret edildiği anda hemen yetişkinin parmak doğrultusunu takip ederek uzaktaki balona bakar ve tebessüm eder.'),
            'p1': isAtypical
                ? 'Toddler shows zero gaze shift; eyes remain rigidly focused on the plastic cup in hand.'
                : (isDelayed
                    ? 'Toddler slowly turns head toward adult\'s outstretched hand, but gaze halts strictly at the finger tip.'
                    : 'Toddler instantly follows the pointing vector; head and eye gaze track across room directly to the yellow balloon.'),
            'p2': isAtypical
                ? 'Does not acknowledge the pointing hand or distant target; emotion remains flat and isolated.'
                : (isDelayed
                    ? 'Stares blankly at adult\'s finger for 1 second, failing to project gaze to the distant balloon.'
                    : 'Locks gaze onto distant balloon for 2 seconds, eyes widening with curious comprehension.'),
            'p3': isAtypical
                ? 'Continues turning the cup; zero joint visual attention.'
                : (isDelayed
                    ? 'Drops head back to cup without looking at balloon or sharing affect.'
                    : 'Turns gaze back to adult\'s face with a shared smile, confirming mutual awareness.'),
            'checklist': isAtypical
                ? 'Klinik Ölçüt: Bakış vektörü değişimi: 0° (Hedefe yönelim yok).'
                : (isDelayed
                    ? 'Klinik Ölçüt: Bakış sadece parmak ucunda takılı kalır, uzaktaki hedefe projeksiyon yok.'
                    : 'Klinik Ölçüt: Bakış vektörü parmak ucundan uzaktaki balona aktarılır, üçlü dikkat döngüsü tamamlanır.'),
            'meta': {'phase_code': 'P${phaseNum}_ONT02_REACT', 'risk_variant': risk},
          },
          {
            'title': 'ONT-02 Sonrası — Mavi Kupayı Yere Koyma',
            'type': 'TRANSITION',
            'phase': 'Faz $phaseNum: Ortak Dikkat Gözlemi (ONT-02)',
            'cam': 'Slow pull-back to wide shot, soft morning light illuminating posture',
            'action': 'Yetişkin kolunu çeker, çocuk mavi kupayı halıya bırakıp bağdaş kurmuş bekler.',
            'p1': 'Adult\'s pointing hand gently withdraws from frame. Toddler lowers blue cup to the rug.',
            'p2': 'Releases fingers, allowing cup to stand upright on the geometric wool.',
            'p3': 'Rests both palms comfortably on carpet, taking a quiet calm breath in neutral posture.',
            'checklist': 'Geçiş Davranışı: İşaret uyarını sonrası sakin duruş.',
            'meta': {'phase_code': 'P${phaseNum}_TRANSITION'},
          },
        ];

      case 'ONT-06':
        return [
          {
            'title': 'ONT-06 Uyaranı — Kilitli Kutu ve Yetişkinin Hareketsiz Eli',
            'type': 'STIMULUS',
            'phase': 'Faz $phaseNum: İstek Bildirme / İletişim Gözlemi (ONT-06)',
            'ont': 'ONT-06',
            'cam': 'Medium profile two-shot showing child struggling with lid and adult seated nearby',
            'action': 'Çocuk kapağı açamaz. Yetişkin sessizce elini halıya uzatıp hareketsiz bekler (t₀).',
            'p1': 'Toddler pulls firmly at the red snap lid of the acrylic container, but little fingers cannot pry it open.',
            'p2': 'Adult seated beside places an open relaxed hand flat on the rug, 20 cm from child, remaining completely silent.',
            'p3': 'Toddler pauses struggling with lid, turning eyes down toward the adult\'s stationary hand.',
            'checklist': 'Uyaran Protokolü: Yetişkin sözel komut vermeden elini nötr şekilde halıya koyar (t0).',
            'meta': {'phase_code': 'P${phaseNum}_ONT06_STIM', 'is_stimulus': true, 'ontology': 'ONT-06'},
          },
          {
            'title': isAtypical
                ? 'ONT-06 Tepkisi — Göz Temassız Eli Alet Gibi Çekme (Atipik)'
                : (isDelayed
                    ? 'ONT-06 Tepkisi — Tereddütlü Dokunma ve Kısa Bakış (Gecikmeli)'
                    : 'ONT-06 Tepkisi — Göz Teması Kurarak Yardım İsteme (Tipik)'),
            'type': 'REACTION',
            'phase': 'Faz $phaseNum: İstek Bildirme / İletişim Gözlemi (ONT-06)',
            'ont': 'ONT-06',
            'cam': 'Medium close-up focusing on toddler\'s hands interacting with adult\'s hand',
            'action': isAtypical
                ? 'Çocuk yetişkinin yüzüne HİÇ bakmadan bileğini tutar, cansız bir pense gibi kutu kapağına sürükler.'
                : (isDelayed
                    ? 'Çocuk yetişkinin parmağına hafifçe dokunur, kısa süre kararsız bakar ancak net işaret etmez.'
                    : 'Çocuk önce yetişkinin gözlerine bakar, kutuyu gösterip işaret parmağıyla hafifçe dokunarak yardım ister.'),
            'p1': isAtypical
                ? 'Toddler grabs adult\'s wrist with small hands without ever glancing at adult\'s face.'
                : (isDelayed
                    ? 'Toddler tentatively taps adult\'s fingers, glancing briefly toward chest level with hesitation.'
                    : 'Toddler raises head and looks directly into adult\'s eyes with an inquiring facial expression.'),
            'p2': isAtypical
                ? 'Mechanically drags adult\'s inert hand onto the box lid, pushing adult fingers onto the red latch like a tool.'
                : (isDelayed
                    ? 'Pauses with uncertain expression, awaiting adult initiative.'
                    : 'Alternates gaze between adult\'s eyes and the box latch, pointing with index finger while vocalizing a gentle sound.'),
            'p3': isAtypical
                ? 'Eyes stay 100% glued to the red plastic latch. Treats adult purely as a mechanical instrument (hand-as-a-tool).'
                : (isDelayed
                    ? 'Subtly shifts weight back on rug.'
                    : 'Reaches out to touch adult\'s fingers gently, smiling as if requesting assistance socially.'),
            'checklist': isAtypical
                ? 'Klinik Ölçüt: Göz teması: Yok, İletişim tarzı: Yetişkinin elini mekanik bir alet (pense) gibi kullanma.'
                : (isDelayed
                    ? 'Klinik Ölçüt: Göz teması: Kısa/belirsiz, İletişim tarzı: Kararsız fiziksel temas.'
                    : 'Klinik Ölçüt: Göz teması: Doğrudan, İletişim tarzı: Sosyal işaret ve bakış aktarımı ile yardım isteme.'),
            'meta': {'phase_code': 'P${phaseNum}_ONT06_REACT', 'risk_variant': risk},
          },
          {
            'title': 'Kutunun Açılması — Oyuncağın Alınması',
            'type': 'TRANSITION',
            'phase': 'Faz $phaseNum: İstek Bildirme / İletişim Gözlemi (ONT-06)',
            'cam': 'Medium shot, warm ambient morning light, steady framing',
            'action': 'Kapak açılır, çocuk içindeki sarı plastik oyuncağı alıp halıda oturur.',
            'p1': 'Adult smoothly unlatches the red lid. Toddler immediately reaches inside and grasps the toy.',
            'p2': 'Pulls the toy out, holding it close to chest while turning it over in fingers.',
            'p3': 'Sits comfortably back on the cream rug, tactilely exploring soft toy.',
            'checklist': 'Geçiş Davranışı: İstek gerçekleştikten sonra sakin nesne inceleme.',
            'meta': {'phase_code': 'P${phaseNum}_TRANSITION'},
          },
        ];

      case 'ONT-07':
      case 'ONT-08':
        return [
          {
            'title': '[$code] Uyaranı — Yetişkin Tülle "Ce-ee!" (Peek-a-boo) Başlatır',
            'type': 'STIMULUS',
            'phase': 'Faz $phaseNum: Karşılıklı Sosyal Etkileşim ($code)',
            'ont': code,
            'cam': 'Eye-level medium shot framing child directly, adult hands holding silk cloth in front',
            'action': 'Yetişkin yüzünü pastel ipek tülle kapatıp "Ce-ee!" diyerek açar, neşeyle gülümser (t₀).',
            'p1': 'Toddler sits holding a toy. In front, adult covers own face with sheer pastel silk cloth: "Where am I?...".',
            'p2': 'Adult drops cloth down with an enthusiastic, joyful "Peek-a-boo!", smiling warmly with expressive open eyes.',
            'p3': 'Adult holds radiant social smile for 3 seconds, inviting reciprocal shared affect from toddler.',
            'checklist': 'Uyaran Protokolü: Ce-ee (Peek-a-boo) oyunuyla karşılıklı duygulanım uyarımı sunulur (t0).',
            'meta': {'phase_code': 'P${phaseNum}_${code}_STIM', 'is_stimulus': true, 'ontology': code},
          },
          {
            'title': isAtypical
                ? '[$code] Tepkisi — Donuk Yüz İfadesi & Katılmama (Atipik)'
                : (isDelayed
                    ? '[$code] Tepkisi — Gecikmeli Tepki ve Kısıtlı Mimik (Gecikmeli)'
                    : '[$code] Tepkisi — Karşılıklı Neşeli Sosyal Katılım (Tipik)'),
            'type': 'REACTION',
            'phase': 'Faz $phaseNum: Karşılıklı Sosyal Etkileşim ($code)',
            'ont': code,
            'cam': 'Tight portrait close-up on child\'s facial landmarks and mouth corners',
            'action': isAtypical
                ? 'Çocuk yetişkine kısa bakar ancak hiç gülümsemez; ağız kenarları kalkmaz, donuk nötr ifade.'
                : (isDelayed
                    ? 'Çocuk birkaç saniye bekledikten sonra hafifçe gülümser, heyecanı çabuk söner.'
                    : 'Çocuk yetişkine bakarak neşeyle güler, ellerini çırpar ve oyunun devamını hevesle bekler.'),
            'p1': isAtypical
                ? 'Toddler looks at adult\'s smiling face for 1.2 seconds, but facial expression remains completely flat and serious.'
                : (isDelayed
                    ? 'Toddler hesitates for 2 seconds before offering a weak, subdued smile.'
                    : 'Toddler instantly beams with delight upon seeing adult appear, eyes sparkling with reciprocal joy.'),
            'p2': isAtypical
                ? 'Zero zygomaticus major muscle activation; mouth line remains strictly straight and motionless.'
                : (isDelayed
                    ? 'Mild facial expression change with delayed response.'
                    : 'Full bilateral zygomaticus activation; wide open-mouth smile with joyful vocal giggle.'),
            'p3': isAtypical
                ? 'Breaks gaze passively, looking back down at toys with neutral indifference.'
                : (isDelayed
                    ? 'Returns quietly to floor play.'
                    : 'Reaches little hands toward the silk cloth, inviting another round of playful social engagement.'),
            'checklist': isAtypical
                ? 'Klinik Ölçüt: Duygulanım paylaşımı: Yok (Duygulanım donukluğu).'
                : (isDelayed
                    ? 'Klinik Ölçüt: Duygulanım paylaşımı: Kısıtlı veya gecikmeli.'
                    : 'Klinik Ölçüt: Duygulanım paylaşımı: Güçlü ve iki taraflı (Paylaşılan neşe).'),
            'meta': {'phase_code': 'P${phaseNum}_${code}_REACT', 'risk_variant': risk},
          },
          {
            'title': '[$code] Sonrası — Serbest Oyuna Sakince Dönüş',
            'type': 'TRANSITION',
            'phase': 'Faz $phaseNum: Karşılıklı Sosyal Etkileşim ($code)',
            'cam': 'Smooth pull-back to wide shot, gentle lighting',
            'action': 'Yetişkin tülü halıya bırakır, çocuk sakinleşip oyuncaklarına yönelir.',
            'p1': 'Adult gently folds the silk cloth on the rug.',
            'p2': 'Toddler touches the soft cloth, breathing in calm rhythm.',
            'p3': 'Transitions smoothly to baseline toy play.',
            'checklist': 'Geçiş Davranışı: Sosyal oyundan sonra kendi kendine regülasyon.',
            'meta': {'phase_code': 'P${phaseNum}_TRANSITION'},
          },
        ];

      default:
        final sc = ScenariosRepository.allScenarios.firstWhere(
          (s) => s.code == code,
          orElse: () => ScenariosRepository.allScenarios.first,
        );
        final ageGroupLabel = (age < 18) ? '12–18 Ay' : ((age < 24) ? '18–24 Ay' : '24–36 Ay');
        final rawBranches = sc.getBranchesForAge(ageGroupLabel);

        final branch = isAtypical
            ? rawBranches.firstWhere((b) => b.level == 'KIRMIZI', orElse: () => rawBranches.last)
            : (isDelayed
                ? rawBranches.firstWhere((b) => b.level == 'SARI', orElse: () => rawBranches.first)
                : rawBranches.firstWhere((b) => b.level == 'YEŞİL', orElse: () => rawBranches.first));

        final stimulusDesc = sc.antecedent;
        final reactionDesc = branch.details;

        return [
          {
            'title': '[${sc.code}] Uyaranı — ${sc.title}',
            'type': 'STIMULUS',
            'phase': 'Faz $phaseNum: ${sc.title} Gözlemi (${sc.code})',
            'ont': sc.code,
            'cam': 'Medium two-shot framing child and adult interaction zone, 40mm lens',
            'action': stimulusDesc,
            'p1': 'Adult initiates targeted observation: $stimulusDesc.',
            'p2': 'Maintains consistent body position without intrusive physical touch.',
            'p3': 'Waits 3 seconds observing child\'s natural response latency.',
            'checklist': 'Uyaran Protokolü: ${sc.antecedent}',
            'meta': {'phase_code': 'P${phaseNum}_${sc.code}_STIM', 'is_stimulus': true, 'ontology': sc.code},
          },
          {
            'title': '[${sc.code}] Tepkisi — ${branch.title} (${branch.level == "KIRMIZI" ? "Atipik" : (branch.level == "SARI" ? "Gecikmeli" : "Tipik")})',
            'type': 'REACTION',
            'phase': 'Faz $phaseNum: ${sc.title} Gözlemi (${sc.code})',
            'ont': sc.code,
            'cam': 'Close-up on child\'s eyes, facial expression, and upper body gesture',
            'action': reactionDesc,
            'p1': 'Toddler exhibits behavioral response: $reactionDesc.',
            'p2': 'Latency noted: ${branch.latency}. Risk alignment: ${branch.level}.',
            'p3': 'Maintains postural and affective composure corresponding to $risk profile.',
            'checklist': 'Klinik Ölçüt (${branch.level}): ${branch.details} (Tepki Süresi: ${branch.latency})',
            'meta': {'phase_code': 'P${phaseNum}_${sc.code}_REACT', 'risk_variant': risk},
          },
          {
            'title': '[${sc.code}] Sonrası — Oyuna Devam Geçişi',
            'type': 'TRANSITION',
            'phase': 'Faz $phaseNum: ${sc.title} Gözlemi (${sc.code})',
            'cam': 'Smooth wide-angle pull-back establishing comfortable nursery environment',
            'action': 'Yetişkin geriye çekilir, çocuk halıdaki oyuncaklarıyla bağımsız oyununa geri döner.',
            'p1': 'Adult gently withdraws focus, leaving child unhurried.',
            'p2': 'Toddler shifts gaze back to rug props in natural movement.',
            'p3': 'Maintains relaxed baseline sitting posture.',
            'checklist': 'Geçiş Davranışı: Gözlem adımından sonra doğal oyun regülasyonu.',
            'meta': {'phase_code': 'P${phaseNum}_TRANSITION'},
          },
        ];
    }
  }

  static Map<String, dynamic> _createCooldownPhase(int cur, int target) {
    return {
      'title': 'Serbest Sakinleşme ve Oyun Tamamlama',
      'type': 'COOLDOWN',
      'phase': 'Faz 8: Seans Kapanışı',
      'cam': 'Static wide shot, gentle natural morning light',
      'action': 'Çocuk halıda sakin şekilde oyuncakları incelemeye devam eder.',
      'p1': 'Toddler sits calmly on the cream rug, turning a wooden block in hands.',
      'p2': 'Places the block gently next to the red toy car, breathing peacefully.',
      'p3': 'Rests both hands on knees, looking toward the sunlit floor in quiet contentment.',
      'checklist': 'Dinginlik Gözlemi: Seans sonu spontane dikkat ve dinginlik.',
      'meta': {'phase_code': 'P8_EXTRA_COOLDOWN'},
    };
  }
}
