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
    sb.writeln('**Kaynak:** $engineUsed');
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
  bool get isUnreviewedGenerationDraft => riskProfile == 'planlanan_taslak';
  String get sourceLabel => isUnreviewedGenerationDraft
      ? 'Sunucu üretim taslağı; içerik ve video doğrulanmadı'
      : 'Hazır şablon; model çıkarımı yapılmadı';

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
    sb.writeln('**Kaynak:** $sourceLabel');
    sb.writeln('**Hedef Yaş Grubu:** $targetAgeMonths Ay');
    if (isUnreviewedGenerationDraft) {
      sb.writeln('**Durum:** 26 sahnelik üretim taslağı; video veya gözlenmiş davranış değildir.\n');
    } else {
      sb.writeln('**Gözlem Durumu:** ${riskProfile.toUpperCase()}\n');
    }
    for (final s in steps) {
      sb.writeln('### Adım ${s.stepNumber}: ${s.title}');
      sb.writeln('${s.actionDescription}\n');
    }
    return sb.toString();
  }

  /// Tüm seansı evrensel promptlar ve klinik kontrol listesiyle Markdown formatında dışa aktarır
  String exportFullMarkdown() {
    final sb = StringBuffer();
    sb.writeln(isUnreviewedGenerationDraft
        ? '# 26 Sahnelik Üretim Taslağı ve Video Promptları'
        : '# Şablon Senaryo Taslağı ve Video Üretim Promptları');
    sb.writeln('**Kaynak:** $sourceLabel');
    sb.writeln('**Uyumlu Modeller:** Google Veo, Runway Gen-3, Luma Dream Machine, Kling AI, OpenAI Sora, Pika');
    sb.writeln('**Hedef Yaş Grubu:** $targetAgeMonths Ay');
    sb.writeln('**Toplam Seans Süresi:** ${_formatTime(totalDurationSec)} ($totalDurationSec sn • $totalStepsCount Sıralı Klip)');
    sb.writeln('**Klip Başına Süre:** ${blockDurationSec}s');
    if (isUnreviewedGenerationDraft) {
      sb.writeln('**Durum:** Planlanan içerik; video veya gözlenmiş davranış doğrulanmadı.');
    } else {
      sb.writeln('**Gözlem Profili:** ${riskProfile.toUpperCase()}');
    }
    sb.writeln('\n---\n');

    for (final s in steps) {
      sb.writeln('### KLİP ${s.stepNumber.toString().padLeft(2, '0')} [${s.timeFormatted}] — ${s.title}');
      sb.writeln('- **Faz:** ${s.phaseName}');
      sb.writeln('- **Planlanan eylem:** ${s.actionDescription}');
      if (!isUnreviewedGenerationDraft) {
        sb.writeln('- **Klinik Gözlem Kontrol Listesi:** ${s.clinicalChecklist}');
      }
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
    sb.writeln('// Kaynak: $sourceLabel');
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
        'source': sourceLabel,
        'content_status': 'planned_unreviewed',
        'target_age_months': targetAgeMonths,
        'total_duration_sec': totalDurationSec,
        'clip_duration_sec': blockDurationSec,
        'total_steps': totalStepsCount,
        'risk_profile': isUnreviewedGenerationDraft ? null : riskProfile,
        if (isUnreviewedGenerationDraft) 'artifact_type': 'planned_unreviewed_26_scene_draft',
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
        if (!isUnreviewedGenerationDraft) 'clinical_checklist': s.clinicalChecklist,
        'camera': s.cameraMovement,
        'continuity_directive': s.continuityNote,
        'prompt': s.universalPrompt,
        'metadata': s.metadata,
      }).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }
}

/// Klinik aktivite, materyal ve davranışsal çeşitlilik profili
class ClinicalActivityProfile {
  final String id;
  final String toyNameTr;
  final String materialsTr;
  final String materialsEn;
  final String basePlayTitle;
  final String basePlayActionTr;
  final String basePlayP1En;
  final String basePlayP2En;
  final String basePlayP3En;
  final String basePlayStep2Title;
  final String basePlayStep2ActionTr;
  final String basePlayStep2P1En;
  final String basePlayStep2P2En;
  final String basePlayStep2P3En;
  final String ont01StimulusActionTr;
  final String ont01StimulusP1En;
  final String ont01StimulusP2En;
  final String ont01StimulusP3En;
  final String ont01AtypicalActionTr;
  final String ont01AtypicalP1En;
  final String ont01AtypicalP2En;
  final String ont01AtypicalP3En;
  final String ont01DelayedActionTr;
  final String ont01DelayedP1En;
  final String ont01TypicalActionTr;
  final String ont01TypicalP1En;
  final String ont01TransitionActionTr;
  final String ont01TransitionP1En;
  final String ont01TransitionP2En;
  final String cooldownActionTr;
  final String cooldownP1En;
  final String cooldownP2En;
  final String environmentTr;
  final String environmentPropsEn;

  const ClinicalActivityProfile({
    required this.id,
    required this.toyNameTr,
    required this.materialsTr,
    required this.materialsEn,
    required this.basePlayTitle,
    required this.basePlayActionTr,
    required this.basePlayP1En,
    required this.basePlayP2En,
    required this.basePlayP3En,
    required this.basePlayStep2Title,
    required this.basePlayStep2ActionTr,
    required this.basePlayStep2P1En,
    required this.basePlayStep2P2En,
    required this.basePlayStep2P3En,
    required this.ont01StimulusActionTr,
    required this.ont01StimulusP1En,
    required this.ont01StimulusP2En,
    required this.ont01StimulusP3En,
    required this.ont01AtypicalActionTr,
    required this.ont01AtypicalP1En,
    required this.ont01AtypicalP2En,
    required this.ont01AtypicalP3En,
    required this.ont01DelayedActionTr,
    required this.ont01DelayedP1En,
    required this.ont01TypicalActionTr,
    required this.ont01TypicalP1En,
    required this.ont01TransitionActionTr,
    required this.ont01TransitionP1En,
    required this.ont01TransitionP2En,
    required this.cooldownActionTr,
    required this.cooldownP1En,
    required this.cooldownP2En,
    required this.environmentTr,
    required this.environmentPropsEn,
  });
}

/// 0 İNTERNET, 0 KOTA İLE ÇALIŞAN EVRENSEL SENTETİK VİDEO VE SENARYO MOTORU
class SyntheticVideoPromptService {
  /// Farklı seanslarda tekrarı önleyen zengin klinik aktivite kütüphanesi
  static const List<ClinicalActivityProfile> clinicalProfiles = [
    // 0: Klasik Bloklar ve Kırmızı Ahşap Araba (Teker çevirme fiksasyonu)
    ClinicalActivityProfile(
      id: 'CAR_WHEEL',
      toyNameTr: 'Kırmızı Ahşap Araba ve Kayın Bloklar',
      materialsTr: 'Standart Klinik Test Seti: 2-3 adet pürüzsüz ahşap blok, kırmızı ahşap araba, duvarda renkli görsel, şeffaf kilitli kutu.',
      materialsEn: 'smooth beechwood cubic blocks, cherry-red wooden convertible toy car, pastel-blue stacking cups, clear acrylic toy box',
      basePlayTitle: 'Bloklarla Doğal Oyun Başlangıcı',
      basePlayActionTr: 'Çocuk halıda bağdaş kurmuş iki ahşap bloğu ritmik şekilde birbirine hafifçe vurur.',
      basePlayP1En: 'Toddler sits on the plush cream geometric rug, holding one beechwood block in each hand, gently tapping them together.',
      basePlayP2En: 'Concentrates on the tactile sound, shifting balance slightly, fingers naturally adjusting grip on smooth wooden grain.',
      basePlayP3En: 'Slowly places the left block down onto the rug while keeping eyes focused downward in calm independent play.',
      basePlayStep2Title: 'İkinci Bloğu Üst Üste Koyma Denemesi',
      basePlayStep2ActionTr: 'Çocuk yerdeki bloğun üstüne elindeki diğer bloğu dikkatlice koymaya çalışır.',
      basePlayStep2P1En: 'Toddler holds the second beechwood cube directly above the base block, wrist steadying with fine motor concentration.',
      basePlayStep2P2En: 'Carefully balances top cube onto bottom cube, releasing fingers slowly with focused caution.',
      basePlayStep2P3En: 'Pulls hands back gently to thighs, watching the two-block tower stand stably.',
      ont01StimulusActionTr: 'Çocuk arabayla ilgilenirken, arkasındaki yetişkin net bir sesle adını seslenir (t₀).',
      ont01StimulusP1En: 'Toddler remains seated examining the car hood. Behind the child, adult leans forward slightly without physical contact.',
      ont01StimulusP2En: 'Adult delivers clear verbal auditory stimulus: calls the child\'s name in a firm, warm voice: "Ali!".',
      ont01StimulusP3En: 'Adult pauses 2 seconds, then repeats the name clearly: "Ali!". Child\'s hands remain on the red car.',
      ont01AtypicalActionTr: 'Çocuk ismine hiç tepki vermez (Δt > 3.0s). Başını kaldırmaz, arabanın tekerini döndürmeye devam eder.',
      ont01AtypicalP1En: 'Despite clear vocal call, toddler exhibits complete absence of head orienting; head yaw angle stays under 5 degrees.',
      ont01AtypicalP2En: 'Eyes remain rigidly glued to the red car wheel; index finger repeatedly spins wheel with zero social glance.',
      ont01AtypicalP3En: 'Total absence of eye contact or head orienting; unperturbed solitary fixation.',
      ont01DelayedActionTr: 'Çocuk çağrıldıktan 2.5 saniye sonra yavaşça başını hafifçe yana çevirir, kısa bakar.',
      ont01DelayedP1En: 'Toddler stays looking at car for 2 seconds, then slowly begins a sluggish, delayed head rotation toward the voice.',
      ont01TypicalActionTr: 'Çocuk seslenildiği anda (1.2 saniye içinde) başını hızla yetişkine çevirir ve gülümseyerek göz teması kurar.',
      ont01TypicalP1En: 'Within 1.2 seconds of hearing name, toddler smoothly rotates head 65 degrees toward the adult voice.',
      ont01TransitionActionTr: 'Kamera geniş açıya çekilir, çocuk arabayı halıda hafifçe ileri iter, serbest oyuna döner.',
      ont01TransitionP1En: 'Toddler places palm flat on the geometric rug pile next to the car.',
      ont01TransitionP2En: 'Pushes the red wooden car forward 25 cm, watching wheels roll across the floor.',
      cooldownActionTr: 'Çocuk peluş oyuncağı iki eliyle göğsüne bastırır, sakin oturur.',
      cooldownP1En: 'Toddler gently wraps arms around small plush teddy bear resting beside blocks, pressing fur against clothing.',
      cooldownP2En: 'Strokes plush ear with thumb, looking quietly toward sunlight across ash wood floor.',
      environmentTr: 'Sakin ve yapılandırılmış klinik gözlem odası; dikkat dağıtıcı harici ekranlar kapalı, yerde geometrik desenli halı.',
      environmentPropsEn: 'Props: smooth beechwood cubic blocks, cherry-red wooden convertible toy car, pastel-blue stacking cups, clear acrylic toy box.',
    ),

    // 1: Manyetik Ahşap Tren ve Dairesel Ray Seti (Lokomotif tekeri göz hizasında hipnotik döndürme)
    ClinicalActivityProfile(
      id: 'TRAIN_TRACK',
      toyNameTr: 'Ahşap Lokomotif ve Dairesel Ray Seti',
      materialsTr: 'Klinik Tren Seti: Doğal kayın ağacı ray parçaları, manyetik bağlantılı kırmızı lokomotif ve kömür vagonu, şeffaf kilitli kutu.',
      materialsEn: 'curved beechwood interlocking train tracks, cherry-red wooden steam locomotive with magnetic coupling, coal tender wagon with miniature black wheels, clear acrylic observation box',
      basePlayTitle: 'Rayları Birleştirme ve Lokomotif Sürüşü',
      basePlayActionTr: 'Çocuk halıda iki ahşap ray parçasını birbirine geçirmeye çalışır ve lokomotifi rayın üstüne koyar.',
      basePlayP1En: 'Toddler sits comfortably on the cream rug, fitting two curved beechwood train track segments together with both hands.',
      basePlayP2En: 'Picks up the cherry-red wooden locomotive, feeling the magnetic coupler click gently against the palm.',
      basePlayP3En: 'Carefully aligns locomotive wheels onto the wooden groove of the circular track.',
      basePlayStep2Title: 'Lokomotifi Ray Boyunca İtme',
      basePlayStep2ActionTr: 'Çocuk lokomotifi rayların kıvrımında parmağıyla dikkatlice ileri doğru sürer.',
      basePlayStep2P1En: 'Toddler gently pushes the red locomotive around the curved track section, wrist following the wooden curve.',
      basePlayStep2P2En: 'Listens to the rhythmic tactile wooden click as the magnetic wagon glides smoothly behind.',
      basePlayStep2P3En: 'Pauses at the curve apex, tilting head downward to inspect the alignment with high focus.',
      ont01StimulusActionTr: 'Çocuk lokomotifle ilgilenirken, arkasındaki yetişkin net bir sesle adını seslenir (t₀).',
      ont01StimulusP1En: 'Toddler remains seated examining the train engine. Behind child, adult leans forward slightly without physical contact.',
      ont01StimulusP2En: 'Adult delivers clear auditory stimulus: calls the child\'s name in a firm, warm voice: "Ali!".',
      ont01StimulusP3En: 'Adult pauses 2 seconds, then repeats the name clearly: "Ali!". Child\'s fingers remain clamped on the locomotive.',
      ont01AtypicalActionTr: 'Çocuk ismine hiç tepki vermez (Δt > 3.0s). Lokomotifi tam göz hizasına kaldırarak küçük tekerini takıntılı şekilde hızlıca döndürür.',
      ont01AtypicalP1En: 'Despite clear vocal call, toddler exhibits complete absence of head orienting; lifts the red locomotive to eye level.',
      ont01AtypicalP2En: 'Index finger rapidly and repetitively spins the black locomotive wheel 2 inches from eyes in narrow visual fixation.',
      ont01AtypicalP3En: 'Total lack of social awareness; gaze completely absorbed by the spinning wheel rim, oblivious to surrounding voice.',
      ont01DelayedActionTr: 'Çocuk çağrıldıktan 2.5 saniye sonra yavaşça başını hafifçe yana çevirir, kısa bakar.',
      ont01DelayedP1En: 'Toddler freezes wheel movement for 2 seconds, then slowly executes a sluggish 30-degree head turn toward the voice.',
      ont01TypicalActionTr: 'Çocuk seslenildiği anda (1.2 saniye içinde) başını hızla yetişkine çevirir ve gülümseyerek göz teması kurar.',
      ont01TypicalP1En: 'Within 1.2 seconds of hearing name, toddler sets locomotive down and turns head 65 degrees toward adult with an open reciprocal smile.',
      ont01TransitionActionTr: 'Kamera geniş açıya çekilir, çocuk lokomotifi rayın üzerine bırakıp vagonu bağlamaya yönelir.',
      ont01TransitionP1En: 'Toddler lowers the locomotive gently back onto the wooden tracks.',
      ont01TransitionP2En: 'Reaches for the small coal wagon, rolling both connected pieces smoothly forward along the curve.',
      cooldownActionTr: 'Çocuk lokomotifi rayın kenarına bırakıp ellerini dizlerine koyarak sakinleşir.',
      cooldownP1En: 'Toddler places both train cars neatly side-by-side on the ash floor beside the rug border.',
      cooldownP2En: 'Rests hands quietly in lap, looking peacefully across the sunlit room as observation ends.',
      environmentTr: 'Aydınlık ve düzenli klinik oyun alanı; yerde dairesel ray döşeli geometrik halı, yumuşak gün ışığı.',
      environmentPropsEn: 'Props: curved beechwood interlocking train tracks, cherry-red wooden steam locomotive, magnetic coal tender, clear acrylic box.',
    ),

    // 2: Huş Ağacı Geometrik Şekil Kutusu (Prizmayı ışığa tutup yan bakış - Lateral Glance)
    ClinicalActivityProfile(
      id: 'SHAPE_SORTER',
      toyNameTr: 'Geometrik Şekil Kutusu ve Renkli Prizmalar',
      materialsTr: 'Klinik Şekil Kutusu: Huş ağacından şekil yerleştirme küpü (üçgen, silindir, kare delikler), renkli prizmalar ve kilitli şeffaf kutu.',
      materialsEn: 'natural birchwood shape sorter cube with geometric cutouts, vibrant triangular and hexagonal wooden prisms, clear acrylic container',
      basePlayTitle: 'Şekil Kutusu ve Blokları İnceleme',
      basePlayActionTr: 'Çocuk huş ağacı şekil kutusunun deliklerini parmaklarıyla yoklar ve elindeki üçgen prizmayı deliğe denk getirmeye çalışır.',
      basePlayP1En: 'Toddler sits upright on the plush rug, turning the natural birchwood shape cube to find the triangular opening.',
      basePlayP2En: 'Holds a smooth turquoise triangular prism with pincer grasp, attempting to orient the edges with the cutout slot.',
      basePlayP3En: 'Concentrates intensely as the wooden prism drops through the slot with a satisfying muted thud.',
      basePlayStep2Title: 'İkinci Şekli Yerleştirme Girişimi',
      basePlayStep2ActionTr: 'Çocuk sarı silindir bloğu alıp kutunun üstündeki dairesel deliğe doğru odaklar.',
      basePlayStep2P1En: 'Picks up a bright yellow wooden cylinder, tapping the circular base against the wooden sorter lid.',
      basePlayStep2P2En: 'Slowly centers the cylinder over the round hole, feeling the wooden rim with thumb.',
      basePlayStep2P3En: 'Releases the block smoothly, watching it vanish into the box with focused curiosity.',
      ont01StimulusActionTr: 'Çocuk renkli prizmayı incelerken, arkasındaki yetişkin net bir sesle adını seslenir (t₀).',
      ont01StimulusP1En: 'Toddler holds the triangular prism close to face. Behind child, adult sits motionless at 1.5m distance.',
      ont01StimulusP2En: 'Adult delivers clear vocal prompt calling the child\'s name: "Ali!".',
      ont01StimulusP3En: 'Adult pauses 2 seconds, repeating the name distinctly: "Ali!". Toddler does not turn.',
      ont01AtypicalActionTr: 'Çocuk ismine hiç tepki vermez (Δt > 3.0s). Üçgen bloğu pencereden gelen ışığa tutup başını eğerek göz ucuyla (yan bakış - lateral glance) köşesine kilitlenir.',
      ont01AtypicalP1En: 'Despite loud call, toddler demonstrates zero head turn; tilts head at an acute angle toward window sunlight.',
      ont01AtypicalP2En: 'Fixates on the prism corner through peripheral lateral eye glance, squinting slightly with completely flat facial affect.',
      ont01AtypicalP3En: 'Zero orientation to adult; repetitive micro-movements of prism angle catching light reflections.',
      ont01DelayedActionTr: 'Çocuk çağrıldıktan 2.5 saniye sonra yavaşça başını hafifçe yana çevirir, kısa bakar.',
      ont01DelayedP1En: 'Toddler lowers the prism after 2.5 seconds, offering a brief 0.5s glance toward adult before looking back to sorter.',
      ont01TypicalActionTr: 'Çocuk seslenildiği anda (1.2 saniye içinde) başını hızla yetişkine çevirir ve gülümseyerek göz teması kurar.',
      ont01TypicalP1En: 'Within 1.2 seconds, toddler turns head 60 degrees, holds up the blue triangle with a proud communicative smile.',
      ont01TransitionActionTr: 'Kamera geniş açıya çekilir, çocuk prizmayı kutunun üstüne bırakır, serbest oyuna döner.',
      ont01TransitionP1En: 'Toddler sets the turquoise triangle on top of the sorter cube.',
      ont01TransitionP2En: 'Rests hands on rug beside the box, sitting in balanced upright posture.',
      cooldownActionTr: 'Çocuk şekil kutusunun kapağını kapatıp sakince oturur.',
      cooldownP1En: 'Toddler places palm flat on the wooden sorter lid, taking a slow steady breath.',
      cooldownP2En: 'Looks calmly toward the soft morning sunbeams on the floor as the session concludes.',
      environmentTr: 'Geniş pencereli sakin klinik odası; yerde geometrik yün halı ve doğal ahşap zemin, dingin gün ışığı.',
      environmentPropsEn: 'Props: natural birchwood shape sorter cube, triangular and cylindrical wooden blocks, acrylic box.',
    ),

    // 3: Denge Blokları ve Çizgisel Hizalama (Perseverative Linear Alignment)
    ClinicalActivityProfile(
      id: 'BLOCKS_ALIGNMENT',
      toyNameTr: 'Kayın Ağacı Denge Blokları ve Kule Seti',
      materialsTr: 'Klinik Blok Seti: 8 adet doğal kayın ağacı silindirik ve kübik blok, mat pastel boyalı denge çubukları, şeffaf kilitli kutu.',
      materialsEn: 'natural beechwood cubic building blocks, muted pastel wooden balancing bars, transparent observation box',
      basePlayTitle: 'Ahşap Bloklarla Kule ve Sıralama Başlangıcı',
      basePlayActionTr: 'Çocuk halıda üç ahşap bloğu yan yana koyup aralarındaki mesafeyi milimetrik olarak düzeltir.',
      basePlayP1En: 'Toddler sits cross-legged on the geometric rug, carefully placing three beechwood blocks in a straight line.',
      basePlayP2En: 'Uses thumb and forefinger to nudge the middle block with obsessive precision, aligning outer edges.',
      basePlayP3En: 'Steps fingers back, sighting along the line at eye level to verify perfect linear orientation.',
      basePlayStep2Title: 'Dördüncü Bloğu Sıraya Ekleme',
      basePlayStep2ActionTr: 'Çocuk dördüncü bloğu sıranın ucuna ekler ve halının bordür çizgisiyle tam paralel hizalar.',
      basePlayStep2P1En: 'Picks up a fourth wooden cube, placing it exactly 1 centimeter from the previous block.',
      basePlayStep2P2En: 'Gently taps the side to ensure seamless parallel alignment along the rug border pattern.',
      basePlayStep2P3En: 'Remains crouched low, admiring the uninterrupted row with serious, intent focus.',
      ont01StimulusActionTr: 'Çocuk blokları dizerken, arkasındaki yetişkin net bir sesle adını seslenir (t₀).',
      ont01StimulusP1En: 'Toddler sits intensely focused on block row. Behind child, adult leans forward in seated posture.',
      ont01StimulusP2En: 'Adult calls out child\'s name in a firm, audible voice: "Ali!".',
      ont01StimulusP3En: 'Adult waits 2 seconds, repeating "Ali!" without touch. Child remains absorbed in alignment.',
      ont01AtypicalActionTr: 'Çocuk ismine hiç tepki vermez (Δt > 3.0s). Başını hiç kaldırmaz; blok hizası bozulmasın diye tüm dikkatini çizgiye verip beşinci bloğu eklemeyi sürdürür.',
      ont01AtypicalP1En: 'Despite vocal call, toddler exhibits zero postural orienting; head stays rigidly angled downward at block line.',
      ont01AtypicalP2En: 'Reaches for a fifth block with laser-focused perseveration, adjusting its position to preserve unbroken symmetry.',
      ont01AtypicalP3En: 'Total auditory filtering; zero social acknowledgement, completely immersed in perseverative sorting.',
      ont01DelayedActionTr: 'Çocuk çağrıldıktan 2.5 saniye sonra yavaşça başını hafifçe yana çevirir, kısa bakar.',
      ont01DelayedP1En: 'Toddler hesitates for 2 seconds with hand on block, then rotates head 30 degrees for a quick fleeting look.',
      ont01TypicalActionTr: 'Çocuk seslenildiği anda (1.2 saniye içinde) başını hızla yetişkine çevirir ve gülümseyerek göz teması kurar.',
      ont01TypicalP1En: 'Within 1.2 seconds of hearing name, toddler drops hands to lap, spins head 70 degrees with a bright welcoming smile.',
      ont01TransitionActionTr: 'Kamera geriye çekilir, çocuk blok sırasını halıda bırakıp dinlenme pozisyonuna geçer.',
      ont01TransitionP1En: 'Toddler rests palms flat on carpet beside the neatly aligned blocks.',
      ont01TransitionP2En: 'Breathes evenly in calm sitting posture, returning to baseline presence.',
      cooldownActionTr: 'Çocuk blokları sakince kutunun yanına toplar ve rahatlar.',
      cooldownP1En: 'Toddler gathers the wooden cubes together in a neat central group.',
      cooldownP2En: 'Sits quietly on the rug in serene composure as clinical evaluation concludes.',
      environmentTr: 'Sade İskandinav tarzı klinik oda; yerde açık renk geometrik yün halı, doğal ahşap zemin ve sabah ışığı.',
      environmentPropsEn: 'Props: natural beechwood building cubes, balancing bars, clear acrylic storage container.',
    ),

    // 4: Mekanik Dişli Çark Tablası (Dönen dişlilere donuk ve hipnotik kilitlenme)
    ClinicalActivityProfile(
      id: 'SPINNING_GEARS',
      toyNameTr: 'Renkli Ahşap Dişli Çark Tablası',
      materialsTr: 'Klinik Dişli Seti: Ahşap zemin üzerine monte birbirine kenetlenen pastel renkli dişli çarklar ve kilitli şeffaf kutu.',
      materialsEn: 'interlocking pastel-colored wooden mechanical gears on an ash wood baseboard, circular cogs, clear acrylic observation box',
      basePlayTitle: 'Dişli Tablasında Çarkları Çevirme',
      basePlayActionTr: 'Çocuk halıda dişli tablasının sarı ana çarkını tutarak yavaşça çevirir ve diğer çarkların dönüşünü izler.',
      basePlayP1En: 'Toddler sits on the cream rug, placing index finger on the handle of the large yellow center gear.',
      basePlayP2En: 'Rotates the gear steadily, watching the interlocking teeth engage with turquoise and orange cogs.',
      basePlayP3En: 'Observes the synchronized rotational motion with sustained tactile and visual attention.',
      basePlayStep2Title: 'Hızlı Döndürme ve Ritim Gözlemi',
      basePlayStep2ActionTr: 'Çocuk çarkları daha hızlı çevirir, parmak ucunu dönen dişlerin üzerinde hafifçe gezdirir.',
      basePlayStep2P1En: 'Spins the main gear with greater velocity, producing a soft rhythmic whirring vibration.',
      basePlayStep2P2En: 'Hovers fingertips millimeters above the spinning teeth, fascinated by the moving pattern.',
      basePlayStep2P3En: 'Leans upper body forward, maintaining steady two-hand stabilization on the baseboard.',
      ont01StimulusActionTr: 'Çocuk dönen çarkları izlerken, arkasındaki yetişkin net bir sesle adını seslenir (t₀).',
      ont01StimulusP1En: 'Toddler remains leaning over the spinning gear board. Behind child, adult sits calmly at 1.5m.',
      ont01StimulusP2En: 'Adult issues clear auditory call: "Ali!".',
      ont01StimulusP3En: 'Adult pauses 2 seconds, repeating the name clearly: "Ali!". Toddler continues spinning gears.',
      ont01AtypicalActionTr: 'Çocuk ismine hiç tepki vermez (Δt > 3.0s). Yüzünü dişlilerin 10 cm yakınına indirip hipnotik ve donuk bir bakışla dönen çarklara kilitlenir.',
      ont01AtypicalP1En: 'Despite loud verbal call, toddler shows zero startle or head orientation; bends head 10cm from spinning cogs.',
      ont01AtypicalP2En: 'Eyes fixate in a trance-like unblinking gaze onto the rotating pastel gear teeth; affect is completely flat.',
      ont01AtypicalP3En: 'Completely oblivious to human voice; repetitive continuous finger flicking of the primary cog.',
      ont01DelayedActionTr: 'Çocuk çağrıldıktan 2.5 saniye sonra yavaşça başını hafifçe yana çevirir, kısa bakar.',
      ont01DelayedP1En: 'Toddler slows the gear rotation after 2.5 seconds, slowly turning head 35 degrees with an expressionless look.',
      ont01TypicalActionTr: 'Çocuk seslenildiği anda (1.2 saniye içinde) başını hızla yetişkine çevirir ve gülümseyerek göz teması kurar.',
      ont01TypicalP1En: 'Within 1.2 seconds, toddler releases the gear and swings head around 65 degrees, sharing a joyful eye-contact grin.',
      ont01TransitionActionTr: 'Kamera geniş açıya çekilir, çarklar yavaşlayıp durur, çocuk sakin nefes alır.',
      ont01TransitionP1En: 'The spinning gears decelerate to a complete stop on the board.',
      ont01TransitionP2En: 'Toddler sits back upright on the rug, resting hands comfortably at sides.',
      cooldownActionTr: 'Çocuk ellerini dizlerine koyup dingin duruşa geçer.',
      cooldownP1En: 'Toddler sits centered on the geometric rug, peaceful and still beside the stationary gear toy.',
      cooldownP2En: 'Breathes rhythmically, gazing comfortably toward the sunlit room as observation ends.',
      environmentTr: 'Geniş ve aydınlık klinik odası; zemin üzerinde ahşap oyuncaklar ve geometrik halı, sakin atmosfer.',
      environmentPropsEn: 'Props: interlocking pastel wooden gear board, circular cogs, clear acrylic container.',
    ),

    // 5: Pastel Duyusal Kaplar ve Dokunsal Regülasyon (Sensory Self-Absorption)
    ClinicalActivityProfile(
      id: 'NESTING_CUPS',
      toyNameTr: 'Pastel İç İçe Geçen Duyusal Kaplar',
      materialsTr: 'Klinik Duyusal Set: 6 adet kademeli boyutta mat pastel silikon duyusal kap, dokunsal çıngırak ve kilitli şeffaf kutu.',
      materialsEn: 'graduated matte pastel-toned silicone nesting cups, tactile wooden sensory shaker, clear observation box',
      basePlayTitle: 'Duyusal Kapları Ayırma ve Dizme',
      basePlayActionTr: 'Çocuk iç içe geçmiş kapları tek tek çekip çıkarır, halının üstüne ters çevirerek dizer.',
      basePlayP1En: 'Toddler sits cross-legged on the soft wool rug, holding the nested stack of matte pastel cups.',
      basePlayP2En: 'Pulls the smallest sage-green cup from the stack, turning it upside down onto the carpet pile.',
      basePlayP3En: 'Extracts the second terracotta cup with focused bilateral coordination, placing it alongside the first.',
      basePlayStep2Title: 'Kule Oluşturma veya İç İçe Geçirme',
      basePlayStep2ActionTr: 'Çocuk kapları büyüklük sırasına göre üst üste koyarak küçük bir kule yapmayı dener.',
      basePlayStep2P1En: 'Carefully balances the third cream cup atop the inverted base, steadying it with both index fingers.',
      basePlayStep2P2En: 'Rests palms gently around the cup base, checking stability with gentle toddler touch.',
      basePlayStep2P3En: 'Leans back slightly, observing the colorful nested stack with serene contentment.',
      ont01StimulusActionTr: 'Çocuk duyusal kapla oynarken, arkasındaki yetişkin net bir sesle adını seslenir (t₀).',
      ont01StimulusP1En: 'Toddler holds the small pastel cup close to chest. Behind child, adult sits quietly at 1.5m.',
      ont01StimulusP2En: 'Adult calls child\'s name in a firm, natural voice: "Ali!".',
      ont01StimulusP3En: 'Adult pauses 2 seconds, repeating "Ali!" clearly. Child remains absorbed in tactile sensation.',
      ont01AtypicalActionTr: 'Çocuk ismine hiç tepki vermez (Δt > 3.0s). Kabı kulağına dayayıp parmağıyla kenarına ritmik tık tık vurarak dış sesleri tamamen bloke eder (Duyusal kendi içine çekilme).',
      ont01AtypicalP1En: 'Despite audible call, toddler exhibits zero head orienting; raises the silicone cup directly over the right ear.',
      ont01AtypicalP2En: 'Taps the cup rim rhythmically with index finger, eyes drifting slightly unfocused in sensory self-soothing.',
      ont01AtypicalP3En: 'Zero reciprocal connection; external acoustic vocalizations are entirely filtered out in solitary state.',
      ont01DelayedActionTr: 'Çocuk çağrıldıktan 2.5 saniye sonra yavaşça başını hafifçe yana çevirir, kısa bakar.',
      ont01DelayedP1En: 'Toddler lowers cup from ear after 2.5s, sluggishly turning head toward adult with a neutral expression.',
      ont01TypicalActionTr: 'Çocuk seslenildiği anda (1.2 saniye içinde) başını hızla yetişkine çevirir ve gülümseyerek göz teması kurar.',
      ont01TypicalP1En: 'Within 1.2 seconds, toddler turns head 65 degrees, offering the little green cup forward with a joyful smile.',
      ont01TransitionActionTr: 'Kamera geniş açıya çekilir, çocuk kabı halıya koyup rahatlar.',
      ont01TransitionP1En: 'Toddler places the pastel cup gently back on the rug beside the other stacked cups.',
      ont01TransitionP2En: 'Rests hands open on knees, sitting peacefully in balanced toddler posture.',
      cooldownActionTr: 'Çocuk kapları iç içe toplayıp seansı dingin şekilde tamamlar.',
      cooldownP1En: 'Toddler nests the two smaller cups inside the large base with smooth relaxed movements.',
      cooldownP2En: 'Sits quietly on the rug, breathing calmly in warm morning light as observation ends.',
      environmentTr: 'Huzurlu ve yumuşak ışıklı klinik oda; geometrik yün halı ve pastel duyusal materyaller.',
      environmentPropsEn: 'Props: graduated matte pastel silicone nesting cups, tactile wooden shaker, acrylic toy container.',
    ),
  ];

  /// DOKTORLAR VE KLİNİK DEĞERLENDİRİCİLER İÇİN SANİYESİZ SEANS SENARYOSU (ÇOKLU-ONTOLOJİ DESTEKLİ)
  static DoctorClinicalScenario generateDoctorScenario({
    int ageMonths = 18,
    String? ontologyCode,
    List<String>? ontologyCodes,
    String riskProfile = 'atipik',
    String engineUsed = 'Hazır şablon; model çıkarımı yapılmadı',
    String? customEnvironment,
    String? customMaterials,
    int variationSeed = 0,
  }) {
    final profile = clinicalProfiles[variationSeed.abs() % clinicalProfiles.length];

    // 1. Hedef Ontolojileri belirle
    final List<String> targetCodes = [];
    if (ontologyCodes != null && ontologyCodes.isNotEmpty) {
      targetCodes.addAll(ontologyCodes);
    } else if (ontologyCode != null && ontologyCode.isNotEmpty) {
      targetCodes.add(ontologyCode);
    } else {
      targetCodes.addAll(['ONT-01', 'ONT-02', 'ONT-06']);
    }

    final selectedScenarios = targetCodes.map((c) => ScenariosRepository.allScenarios.firstWhere(
      (s) => s.code == c,
      orElse: () => ScenariosRepository.allScenarios.first,
    )).toList();

    final base = selectedScenarios.first;

    // 2. Yaş grubunu ve yaşa özel beklentiyi belirle
    String ageGroupLabel;
    if (ageMonths < 18) {
      ageGroupLabel = '12–18 Ay';
    } else if (ageMonths < 24) {
      ageGroupLabel = '18–24 Ay';
    } else {
      ageGroupLabel = '24–36 Ay';
    }

    final isMulti = targetCodes.length > 1;
    final title = isMulti
        ? 'Çoklu Klinik Değerlendirme Protokolü (${targetCodes.join(', ')})'
        : base.title;
    final code = isMulti ? targetCodes.join('+') : base.code;

    final expectedNormBuffer = StringBuffer();
    if (isMulti) {
      for (final s in selectedScenarios) {
        final norm = s.ageBreakdowns[ageGroupLabel] ?? 'Yaşa uygun amaçlı tepki ve etkileşim beklenir.';
        expectedNormBuffer.writeln('• [${s.code} ${s.title}]: $norm');
      }
    } else {
      expectedNormBuffer.write(base.ageBreakdowns[ageGroupLabel] ??
          'Bu gelişim döneminde sesli ve görsel uyarana yönelik amaçlı yönelim ve göz kontağı beklenir.');
    }
    final expectedNorm = expectedNormBuffer.toString();

    // 3. Ortam ve Kullanılacak Eşyalar
    final env = (customEnvironment != null && customEnvironment.trim().isNotEmpty)
        ? customEnvironment.trim()
        : profile.environmentTr;

    final mat = (customMaterials != null && customMaterials.trim().isNotEmpty)
        ? customMaterials.trim()
        : (isMulti ? profile.materialsTr : 'Çocuğun ilgisini çekecek ${profile.toyNameTr}.');

    // 4. Test Nasıl Yapılacak? (Adım adım uygulama)
    String stimulusText;
    if (isMulti) {
      final sb = StringBuffer();
      sb.writeln('Bu seans, tek bir oturumda ${targetCodes.length} hedef ontolojiyi kesintisiz ve sıralı olarak değerlendirir:\n');
      sb.writeln('• Adım 1 [Doğal Taban]: ${profile.basePlayActionTr} (30-45 saniye bağımsız nesne manipülasyonu ve motor dengesini gözlemleyin).');
      if (targetCodes.contains('ONT-01')) {
        sb.writeln('• Adım 2 [İsme Tepki - ONT-01]: Görüş açısına girmeden 1.5 metre arkasından doğal ve net sesle adını seslenin. Çocuk ${profile.toyNameTr} ile meşgulken 3 sn içinde dönmezse ikinci kez tekrarlayın.');
      }
      if (targetCodes.contains('ONT-02') || targetCodes.contains('ONT-03')) {
        sb.writeln('• Adım 3 [Ortak Dikkat - ONT-02/03]: Çocuğun dikkatini uzaktaki bir nesneye çekmek için parmağınızla göstererek "Bak oradaki!" deyin. Gözün parmağa mı yoksa hedefe mi kaydığını izleyin.');
      }
      if (targetCodes.contains('ONT-06') || targetCodes.contains('ONT-05')) {
        sb.writeln('• Adım 4 [İletişimsel İstek & El Aleti - ONT-06]: Çocuğun tek başına açamayacağı şeffaf kilitli kutuyu önüne bırakın. Yardım isteme şeklini (göz temasıyla talep vs. elinizi pense gibi alet olarak kullanma) gözlemleyin.');
      }
      sb.writeln('• Adım 5 [Kapanış & Regülasyon]: ${profile.cooldownActionTr}');
      stimulusText = sb.toString();
    } else {
      stimulusText = '''
• Nerede Durulacak: Çocuğun biraz arkasında veya çaprazında (1-1.5 metre mesafede), doğrudan görüş açısına girmeden durun. Çocuğun elindeki ${profile.toyNameTr} nesnesine dokunmayın.
• Nasıl Seslenilecek: Normal bir ses tonuyla, bağırmadan 1 kez adını söyleyin (veya oyuncağı gösterin).
• Ne Kadar Beklenecek: Seslendikten sonra hemen araya girmeyin, çocuğun tepki vermesi için 3 saniye bekleyin.
• Bakmazsa Ne Yapılacak: 3 saniye içinde bakmazsa, aynı şekilde bir kez daha seslenin. En fazla 3 kere deneyin.''';
    }

    // 5. Davranışsal Dallanma (FSM Branches)
    final branches = <DoctorScenarioBranch>[];
    if (isMulti) {
      branches.addAll([
        const DoctorScenarioBranch(
          title: 'Tam Normatif ve Entegre Tipik Yanıt (Normal)',
          level: 'YEŞİL',
          color: Colors.green,
          latency: 'Tüm fazlarda Δt ≤ 2.0 sn',
          details: 'İsme ilk seslenişte döner ve göz teması kurar. İşaret edilen nesneye anında üçgenleme yapar. Kilitli kutuyu açamadığında yetişkinin gözlerine bakarak jest ve mimiklerle yardım ister.',
          clinicalOutcome: 'Tüm test edilen ontolojilerde yaşa tam uygun tipik nörogelişimsel örüntü.',
        ),
        const DoctorScenarioBranch(
          title: 'Gecikmeli / Tekrarlı Uyaran Gerektiren Yanıt (İzlem)',
          level: 'SARI',
          color: Colors.amber,
          latency: 'Δt = 2.0 - 3.5 sn',
          details: 'İsme 2. seslenişte gecikmeli yönelir. İşaret edilen nesne yerine önce işaret parmağına takılır, nesneye sonradan bakar. Yardım isterken göz teması zayıf kalır.',
          clinicalOutcome: 'Gelişimsel izlem ve takip kategorisi. 3 ay sonra tekrar değerlendirme önerilir.',
        ),
        DoctorScenarioBranch(
          title: 'Çoklu Alanda Belirgin Atipik Yanıt (Erken Risk)',
          level: 'KIRMIZI',
          color: Colors.red,
          latency: 'Yanıtsız / Sürekli Direnç',
          details: '3 kez isme seslenilmesine rağmen hiç yönelmez (${profile.ont01AtypicalActionTr}). İşaret edilen yöne bakmaz, kendi elindeki nesneye kilitli kalır. Kilitli kutuda yetişkinin elini alet gibi mekanik olarak çekip kutuya bastırır (Hand-leading, sıfır göz teması).',
          clinicalOutcome: 'M-CHAT-R ve ADOS-2 kritik eşiği. Çocuk psikiyatrisi / gelişimsel pediatri uzman değerlendirmesi önerilir.',
        ),
      ]);
    } else {
      final rawBranches = base.getBranchesForAge(ageGroupLabel);
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
          DoctorScenarioBranch(
            title: 'Hiç Bakmaz / Oralı Olmaz (Şüpheli)',
            level: 'KIRMIZI',
            color: Colors.red,
            latency: '3 saniyeden uzun / Yanıtsız',
            details: '3 defa seslenseniz de hiç oralı olmaz, ${profile.toyNameTr} ile oynamaya dalıp gider (${profile.ont01AtypicalActionTr}), sesin nereden geldiğine bakmaz.',
            clinicalOutcome: 'Dikkat çeken bir durum; bir uzmanın çocuğu detaylı incelemesi iyi olur.',
          ),
        ]);
      }
    }

    // 6. Sistemin İzlediği Noktalar
    final visionMetrics = <String>[];
    if (isMulti) {
      if (targetCodes.contains('ONT-01')) {
        visionMetrics.add('ONT-01 İsme Tepki: Sese yönelik baş dönme gecikmesi (Δt ≤ 2.0 sn) ve dönüş açısı (Yaw ≥ 45°).');
      }
      if (targetCodes.contains('ONT-02') || targetCodes.contains('ONT-03')) {
        visionMetrics.add('ONT-02 Ortak Dikkat: Gözün işaret parmağı yerine hedef nesneye yönelim vektörü ve yüz üçgenlemesi.');
      }
      if (targetCodes.contains('ONT-06')) {
        visionMetrics.add('ONT-06 El Aleti Kullanımı: Yetişkinin elini mekanik alet gibi çekme (Hand-Leading) tespiti ve yardım anındaki göz teması.');
      }
      visionMetrics.add('Genel Motor & Regülasyon: El-parmak stereotipileri (tekerlek çevirme, flapping) ve duyusal regülasyon.');
    } else {
      visionMetrics.addAll([
        'Tepki Süresi: Çocuğa seslendikten sonra kafasını çevirmesi kaç saniye sürdü? (1.5 saniye altı normal sayılır).',
        'Kafasını Çevirme: Sesi duyduğunda kafasını sese doğru net bir şekilde çevirdi mi?',
        'Göz Teması: Gözlerini doğrudan size çevirip en az 1 saniye baktı mı?',
        'Gülümseme ve Mimik: Bakarken yüzü güldü mü, karşılıklı bir etkileşim kurdu mu?',
        'Tekrarlayan Hareketler: Tek bir oyuncağa (örneğin teker çevirme) takılıp kalma veya ellerini sallama gibi hareketler var mı?',
      ]);
    }

    return DoctorClinicalScenario(
      code: code,
      title: title,
      category: isMulti ? 'Çoklu Gelişimsel Değerlendirme' : base.category,
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
      measurementCriteria: isMulti ? 'Çoklu Biyomekanik ve Bilgisayarlı Görü Metrikleri' : base.measurementCriteria,
      technicalNote: 'Bu sistem teşhis koymaz; klinisyen ve uzmanların çoklu davranış gözlemlerini objektif metriklerle takip etmelerini sağlayan bir karar destek aracıdır.',
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
    int variationSeed = 0,
  }) {
    final dur = blockDurationSec.clamp(3, 10);
    final targetSec = totalTargetSec.clamp(180, 240);
    final profile = clinicalProfiles[variationSeed.abs() % clinicalProfiles.length];

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
    final envSpec = _getEnvironmentSpec(ageMonths, profile);
    const styleAnchor =
        'Cinematic 4K, photorealistic, Arri Alexa 35, Cooke S7/i 40mm lens, aperture f/2.0, 24fps, natural toddler kinematics, anatomically accurate hands with distinct five fingers, authentic skin subsurface scattering, zero morphing, zero artifacts.';

    // 3. KLİNİK FAZ ŞABLONLARI (Seçilen tüm ontolojileri dinamik oluşturur)
    final rawPhases = _buildClinicalPhases(ageMonths, riskProfile, targetOntologies, profile);

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
        rawPhases.add(_createCooldownPhase(currentSec, targetSec, profile));
      }
    }

    final ontLabel = targetOntologies.join(', ');
    return SyntheticVideoSession(
      title: '$ageMonths Ay Şablon Senaryo Taslağı ($ontLabel)',
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
  static String _getEnvironmentSpec(int age, [ClinicalActivityProfile? profile]) {
    final p = profile ?? clinicalProfiles.first;
    return 'spacious Scandinavian minimalist nursery playroom, clean matte eggshell-white walls, European natural ash hardwood floor beneath a plush cream geometric wool rug, soft diffused 3800K natural morning window daylight. ${p.environmentPropsEn}';
  }

  /// Klinik Faz Şablonları (Gözlem Kontrol Listesi formatında, birden fazla ontolojiyi sırayla kurgular)
  static List<Map<String, dynamic>> _buildClinicalPhases(int age, String risk, [dynamic ontologyTarget, ClinicalActivityProfile? profile]) {
    final p = profile ?? clinicalProfiles.first;
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
        'title': p.basePlayTitle,
        'type': 'BASE_PLAY',
        'phase': 'Faz 1: Doğal Taban Gözlemi',
        'cam': 'Static locked-off tripod shot at 35cm eye-level, 40mm lens',
        'action': p.basePlayActionTr,
        'p1': p.basePlayP1En,
        'p2': p.basePlayP2En,
        'p3': p.basePlayP3En,
        'checklist': 'Taban Motor Ölçümü: El-nesne kavrama (pincer/palmar), gövde dengesi, nesne manipülasyonu.',
        'meta': {'phase_code': 'P1_BASELINE', 'is_stimulus': false},
      },
      {
        'title': p.basePlayStep2Title,
        'type': 'BASE_PLAY',
        'phase': 'Faz 1: Doğal Taban Gözlemi',
        'cam': 'Eye-level shot, slow imperceptible smooth zoom-in toward working toddler hands',
        'action': p.basePlayStep2ActionTr,
        'p1': p.basePlayStep2P1En,
        'p2': p.basePlayStep2P2En,
        'p3': p.basePlayStep2P3En,
        'checklist': 'İnce Motor Koordinasyon: İki el koordinasyonu, kule yapma veya nesne hizalama motor planlaması.',
        'meta': {'phase_code': 'P1_STACKING', 'is_stimulus': false},
      },
    ]);

    // 2. SEÇİLEN TÜM HEDEF DAVRANIŞLAR İÇİN UYARAN VE TEPKİ BLOKLARI
    int phaseNum = 2;
    for (final code in selectedCodes) {
      phases.addAll(_getPhasesForCode(code, age, risk, phaseNum++, p));
    }

    // 3. KAPANIS VE SEANS TAMAMLAMA
    phases.addAll([
      {
        'title': 'Kapanış — ${p.toyNameTr} ile Sakinleşme',
        'type': 'COOLDOWN',
        'phase': 'Faz $phaseNum: Seans Kapanışı',
        'cam': 'Medium shot at 40cm height, gentle warm lighting',
        'action': p.cooldownActionTr,
        'p1': p.cooldownP1En,
        'p2': p.cooldownP2En,
        'p3': 'Remains in peaceful resting sitting posture, breathing gently.',
        'checklist': 'Duyusal Regülasyon: Seans bitiminde dokunsal rahatlama ve dingin duruş.',
        'meta': {'phase_code': 'P_COOLDOWN'},
      },
      {
        'title': 'Kapanış — Halıda Sakin Oturma ve Seansın Tamamlanması',
        'type': 'COOLDOWN',
        'phase': 'Faz $phaseNum: Seans Kapanışı',
        'cam': 'Slow cinematic pull-back tracking out to full wide room perspective, fading gently',
        'action': 'Kamera yavaşça geriye çekilir; çocuk oyun alanının ortasında huzurla oturur, seans tamamlanır.',
        'p1': 'Toddler sits serenely in center of cream geometric rug, surrounded by quiet play materials.',
        'p2': 'Hands rest softly in lap, head held naturally upright in warm sunbeams streaming through window.',
        'p3': 'Camera holds tranquil wide composition as clinical screening observation concludes seamlessly.',
        'checklist': 'Seans Tamamlandı: Seçilen tüm ontolojik uyaranlar ve gözlemler başarıyla kaydedildi.',
        'meta': {'phase_code': 'P_COMPLETE'},
      },
    ]);

    return phases;
  }

  static List<Map<String, dynamic>> _getPhasesForCode(String code, int age, String risk, int phaseNum, [ClinicalActivityProfile? profile]) {
    final p = profile ?? clinicalProfiles.first;
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
            'action': p.ont01StimulusActionTr,
            'p1': p.ont01StimulusP1En,
            'p2': p.ont01StimulusP2En,
            'p3': p.ont01StimulusP3En,
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
                ? p.ont01AtypicalActionTr
                : (isDelayed
                    ? p.ont01DelayedActionTr
                    : p.ont01TypicalActionTr),
            'p1': isAtypical
                ? p.ont01AtypicalP1En
                : (isDelayed
                    ? p.ont01DelayedP1En
                    : p.ont01TypicalP1En),
            'p2': isAtypical
                ? p.ont01AtypicalP2En
                : (isDelayed
                    ? 'Offers a brief 0.5-second fleeting glance toward adult\'s body level, but quickly lowers gaze back to the toy.'
                    : 'Establishes direct, warm eye contact with adult; mouth curls into an open curious toddler smile.'),
            'p3': isAtypical
                ? p.ont01AtypicalP3En
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
            'action': p.ont01TransitionActionTr,
            'p1': p.ont01TransitionP1En,
            'p2': p.ont01TransitionP2En,
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

  static Map<String, dynamic> _createCooldownPhase(int cur, int target, [ClinicalActivityProfile? profile]) {
    final p = profile ?? clinicalProfiles.first;
    return {
      'title': 'Serbest Sakinleşme ve Oyun Tamamlama',
      'type': 'COOLDOWN',
      'phase': 'Faz 8: Seans Kapanışı',
      'cam': 'Static wide shot, gentle natural morning light',
      'action': p.cooldownActionTr,
      'p1': p.cooldownP1En,
      'p2': p.cooldownP2En,
      'p3': 'Rests both hands on knees, looking toward the sunlit floor in quiet contentment.',
      'checklist': 'Dinginlik Gözlemi: Seans sonu spontane dikkat ve dinginlik.',
      'meta': {'phase_code': 'P8_EXTRA_COOLDOWN'},
    };
  }
}
