import 'dart:convert';

class VeoPromptStep {
  final int stepNumber;
  final String blockId;
  final String blockType; // BASE_PLAY, STIMULUS, REACTION_RED, etc.
  final int startSec;
  final int endSec;
  final int durationSec;
  final String? ontologyCode;
  final String phaseName;
  final String title;
  final String cameraMovement;
  final String actionDescription;
  final String clinicalVoiceover;
  final String veoPrompt;
  final String veoExtendNote;
  final Map<String, dynamic> groundTruth;

  VeoPromptStep({
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
    required this.clinicalVoiceover,
    required this.veoPrompt,
    required this.veoExtendNote,
    required this.groundTruth,
  });
}

class VeoPromptSession {
  final String title;
  final int targetAgeMonths;
  final int totalDurationSec;
  final int blockDurationSec;
  final int totalStepsCount;
  final String characterDescription;
  final String environmentDescription;
  final List<VeoPromptStep> steps;

  VeoPromptSession({
    required this.title,
    required this.targetAgeMonths,
    required this.totalDurationSec,
    required this.blockDurationSec,
    required this.totalStepsCount,
    required this.characterDescription,
    required this.environmentDescription,
    required this.steps,
  });

  String _formatTime(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String exportFullMarkdown() {
    final sb = StringBuffer();
    sb.writeln('# Klinik Gözlem ve Video Simülasyon Senaryosu');
    sb.writeln('**Hedef Yaş Grubu:** $targetAgeMonths Ay');
    sb.writeln('**Toplam Süre:** ${_formatTime(totalDurationSec)} ($totalDurationSec sn • $totalStepsCount Klip)');
    sb.writeln('**Klip Başına Süre:** ${blockDurationSec}s');
    sb.writeln('\n---\n');

    for (final s in steps) {
      final start = _formatTime(s.startSec);
      final end = _formatTime(s.endSec);
      sb.writeln('## Adım ${s.stepNumber} [$start - $end] — ${s.title}');
      sb.writeln('- **Faz:** ${s.phaseName}');
      sb.writeln('- **Eylem:** ${s.actionDescription}');
      sb.writeln('- **Kamera Açısı:** ${s.cameraMovement}');
      sb.writeln('- **Klinik Değerlendirme:** ${s.clinicalVoiceover}\n');
      sb.writeln('```text');
      sb.writeln(s.veoPrompt);
      sb.writeln('```\n');
      sb.writeln('---\n');
    }
    return sb.toString();
  }

  String exportGroundTruthJson() {
    final data = {
      'session': {
        'target_age_months': targetAgeMonths,
        'total_duration_sec': totalDurationSec,
        'total_steps': totalStepsCount,
        'clip_duration_sec': blockDurationSec,
      },
      'steps': steps.map((s) => {
        'step': s.stepNumber,
        'time': '${_formatTime(s.startSec)} - ${_formatTime(s.endSec)}',
        'title': s.title,
        'phase': s.phaseName,
        'action': s.actionDescription,
        if (s.ontologyCode != null) 'ontology': s.ontologyCode,
        'ground_truth': s.groundTruth,
      }).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }
}

class VeoPromptService {
  /// 24 Adımlık tam Google Veo seansını yerel RAG motoruyla üretir
  static VeoPromptSession generateSession({
    int ageMonths = 18,
    int blockDurationSec = 8,
    String riskProfile = 'atipik', // 'atipik', 'tipik', 'karma'
  }) {
    final dur = blockDurationSec.clamp(3, 10);

    const charSpec =
        '18-month-old toddler boy with cherubic facial proportions, soft, fine curly golden-brown baby hair with natural wisps, warm hazel eyes with corneal catchlights, rounded rosy cheeks, smooth infant skin texture. Anatomy: chubby toddler hands with five distinct fingers, barefoot on carpet pile. Wardrobe: vintage mustard-yellow finely ribbed corduroy dungarees with two embossed matte brass buckles over a crisp heather-white 100% organic cotton crewneck tee.';

    const envSpec =
        'spacious Scandinavian minimalist nursery playroom, clean matte eggshell-white painted walls, European natural ash hardwood floor beneath a high-density low-pile cream wool rug with geometric textures, soft diffused 3800K natural morning daylight from large window. Props: beechwood cubic blocks, red wooden toy convertible car, pastel-blue stacking cup, clear acrylic toy box.';

    const styleAnchor =
        'Cinematic 4K, photorealistic, Arri Alexa 35, Cooke S7/i 40mm lens, aperture f/2.0, 24fps, authentic infant physics, anatomically accurate hands with five fingers, zero morphing, zero artifacts.';

    String makeMarks(String p1, String p2, String p3) {
      final t1 = (dur / 3).round().clamp(1, dur);
      final t2 = ((2 * dur) / 3).round().clamp(2, dur);
      return '[00:00-00:${t1.toString().padLeft(2, '0')}s]: $p1 [00:${t1.toString().padLeft(2, '0')}s-00:${t2.toString().padLeft(2, '0')}s]: $p2 [00:${t2.toString().padLeft(2, '0')}s-00:${dur.toString().padLeft(2, '0')}s]: $p3';
    }

    final rawDefs = [
      // FAZ 1: SERBEST OYUN
      {
        'title': 'Bloklarla Doğal Oyun Başlangıcı',
        'type': 'BASE_PLAY',
        'phase': 'Faz 1: Serbest Oyun',
        'cam': 'Static locked-off tripod shot at 35cm toddler eye-level, 40mm lens',
        'action': 'Çocuk halıda bağdaş kurmuş iki ahşap bloğu ritmik şekilde birbirine vurur.',
        'p1': 'Toddler sits cross-legged on the plush cream geometric rug, holding one beechwood block in each hand, gently tapping them together.',
        'p2': 'Concentrates on the tactile sound, shifting balance slightly, fingers naturally adjusting grip on the smooth wooden grain.',
        'p3': 'Slowly separates hands, placing the left block down onto the rug while keeping eyes focused downward in calm independent play.',
        'vo': 'Gözlem seansı 18 aylık çocuğun serbest oyunuyla başlıyor. Çevresel bir dış uyaran olmadan nesnelerle spontane etkileşimi izleniyor.',
        'gt': {'is_test': false, 'activity': 'FREE_PLAY_BLOCKS', 'risk': 'NEUTRAL'},
      },
      {
        'title': 'İkinci Bloğu Kule Yapmaya Çalışma',
        'type': 'BASE_PLAY',
        'phase': 'Faz 1: Serbest Oyun',
        'cam': 'Static eye-level shot, slow imperceptible smooth zoom-in toward working hands',
        'action': 'Çocuk yerdeki bloğun üstüne elindeki diğer bloğu dikkatlice koymaya çalışır.',
        'p1': 'Toddler holds the second beechwood cube directly above the base block on the rug, wrist wobbling with fine motor concentration.',
        'p2': 'Carefully balances the top cube onto the bottom cube, releasing fingers slowly with focused infant caution.',
        'p3': 'Pulls hands back to rest gently on thighs, watching the two-block tower remain standing without falling.',
        'vo': 'Çocuğun fonksiyonel motor planlama ve el-göz koordinasyonu becerileri kaydediliyor.',
        'gt': {'is_test': false, 'activity': 'BLOCK_STACKING', 'risk': 'NEUTRAL'},
      },
      {
        'title': 'Kırmızı Oyun Arabasına Uzanma',
        'type': 'BASE_PLAY',
        'phase': 'Faz 1: Serbest Oyun',
        'cam': 'Low-angle tripod shot from the side, capturing side profile of child and floor props',
        'action': 'Çocuk blokları bırakıp halıda 30 cm mesafedeki kırmızı ahşap arabaya uzanır.',
        'p1': 'Toddler leans torso forward slightly, extending right arm across the cream rug toward the cherry-red wooden convertible car.',
        'p2': 'Fingers close around the wooden car body, pulling it closer between knees with smooth natural toddler arm kinematics.',
        'p3': 'Places car flat on its four wheels on the rug pile, resting palm gently over the car roof.',
        'vo': 'Çocuk nesne değiştirirken dikkat aktarımını bağımsız olarak yönetebiliyor.',
        'gt': {'is_test': false, 'activity': 'OBJECT_TRANSITION_CAR', 'risk': 'NEUTRAL'},
      },

      // FAZ 2: TEST 1 (ONT-01 İSME TEPKİ)
      {
        'title': 'ONT-01 Uyaranı — Yetişkin Arkadan İsim Seslenir',
        'type': 'STIMULUS',
        'phase': 'Faz 2: Test 1 (ONT-01)',
        'ont': 'ONT-01',
        'cam': 'Over-the-shoulder medium shot from behind the child; adult face strictly out of frame',
        'action': 'Çocuk arabayla ilgilenirken, arkasındaki yetişkin net bir sesle "Ali!" diye seslenir (t₀).',
        'p1': 'Toddler remains seated examining the car hood. Behind the child, an adult leans forward slightly without physical contact.',
        'p2': 'Adult vocalizes clear verbal auditory stimulus: calls the child\'s name "Ali!" in a warm, firm maternal voice.',
        'p3': 'Adult pauses 2 seconds, then repeats the name clearly: "Ali!". Toddler\'s hands stay resting on the red car body.',
        'vo': 'Birinci klinik test: İsme tepki (ONT-01). Yetişkin çocuğun arkasından görüş açısına girmeden adıyla sesleniyor. Yönelme hızı ölçülecek.',
        'gt': {'is_test': true, 'event': 'STIMULUS_CALL_NAME', 'ontology': 'ONT-01'},
      },
      {
        'title': 'ONT-01 Tepkisi — Kırmızı Dal (Atipik Tepkisizlik & Hiperfokus)',
        'type': 'REACTION_RED',
        'phase': 'Faz 2: Test 1 (ONT-01)',
        'ont': 'ONT-01',
        'cam': 'Tight 50mm close-up focusing intensely on toddler\'s face, eyes, and fingers on the toy',
        'action': 'Çocuk ismine hiç tepki vermez (Tepkisiz, Δt > 3.0s). Başını hiç kaldırmaz, tekeri parmağıyla döndürmeye kilitlenir.',
        'p1': 'Despite the clear vocal call behind, toddler exhibits complete absence of head orienting; head yaw angle remains under 8 degrees.',
        'p2': 'Eyes remain rigidly glued to the front wheel of the red wooden car; index finger begins repeatedly flicking the wheel rim back and forth.',
        'p3': 'Completely absorbed in solitary spinning; zero facial shift, flat neutral affect, total absence of eye contact or social orienting.',
        'vo': 'Atipik risk göstergesi: Dikkat edilirse çocuk tekrarlanan çağrıya rağmen başını çevirmedi ve göz teması kurmadı (ONT-01: Δt > 3.0s).',
        'gt': {'is_test': true, 'branch': 'RED_ATYPICAL', 'ontology': 'ONT-01', 'latency': '> 3.0s', 'cv_label': 'FAIL_ATYPICAL', 'head_yaw': '< 10 deg'},
      },
      {
        'title': 'ONT-01 Sonrası — Normale ve Oyuna Dönüş',
        'type': 'TRANSITION',
        'phase': 'Faz 2: Test 1 (ONT-01)',
        'ont': 'ONT-01',
        'cam': 'Smooth continuous pull-back on motorized slider to wide establishing tripod shot',
        'action': 'Kamera geniş açıya çekilir, çocuk arabayı halıda hafifçe ileri iter, serbest oyuna döner.',
        'p1': 'Toddler releases the wheel spin, placing palm flat on the geometric rug pile.',
        'p2': 'Pushes the red wooden car forward 20 cm, watching it roll smoothly across the ash wood border.',
        'p3': 'Sits peacefully in balanced toddler posture, returning to baseline calm playtime state.',
        'vo': 'Test tamamlandıktan sonra çocuk serbest oyun rutinine geri dönüyor.',
        'gt': {'is_test': false, 'activity': 'TRANSITION_TO_PLAY', 'risk': 'NEUTRAL'},
      },

      // FAZ 3: SERBEST OYUN & SIRALAMA
      {
        'title': 'Blokları Doğrusal Hat Halinde Dizme (Line-Up)',
        'type': 'BASE_PLAY',
        'phase': 'Faz 3: Serbest Oyun',
        'cam': 'Medium high-angle shot (60 degrees) looking down at child and the neat row of toys on the rug',
        'action': 'Çocuk ahşap blokları üst üste koymak yerine yan yana cetvel gibi düz bir çizgi halinde dizer.',
        'p1': 'Toddler picks up three beechwood blocks sequentially, setting them down side by side in an exact rigid straight line on the rug seam.',
        'p2': 'Carefully nudges the edges with fingertips until all three cubes are perfectly aligned millimeter by millimeter.',
        'p3': 'Bends head down close to floor level, squinting to inspect the straightness of the wooden block line. Intense focus.',
        'vo': 'Burada çocuğun blokları sembolik kule yapmak yerine katı bir çizgi halinde sıralama eğilimi gözleniyor. Bu, erken stereotipik düzen takıntısı göstergelerindendir.',
        'gt': {'is_test': false, 'activity': 'LINE_UP_BEHAVIOR', 'risk': 'MONITORING'},
      },
      {
        'title': 'Mavi İstifleme Kupasına Uzanma',
        'type': 'BASE_PLAY',
        'phase': 'Faz 3: Serbest Oyun',
        'cam': 'Eye-level medium shot at 40cm, stable locked-off framing',
        'action': 'Çocuk yerdeki mavi plastik kupayı alır, ters çevirip tabanına bakar.',
        'p1': 'Toddler shifts sitting posture, reaching left hand over to the pastel-blue cylindrical stacking cup.',
        'p2': 'Lifts the cup up, inverting it with two hands to examine the circular bottom base.',
        'p3': 'Taps the plastic base against knee, feeling the smooth matte texture in quiet solitary observation.',
        'vo': 'Çocuk nesne değiştirirken nesnelerin fiziksel özelliklerine duyusal ilgi gösteriyor.',
        'gt': {'is_test': false, 'activity': 'EXPLORE_BLUE_CUP', 'risk': 'NEUTRAL'},
      },

      // FAZ 4: TEST 2 (ONT-02 ORTAK DİKKAT)
      {
        'title': 'ONT-02 Uyaranı — Yetişkin Uzaktaki Balonu Gösterir',
        'type': 'STIMULUS',
        'phase': 'Faz 4: Test 2 (ONT-02)',
        'ont': 'ONT-02',
        'cam': 'Medium wide shot capturing child sitting on rug while adult\'s arm enters frame on the right side',
        'action': 'Yetişkin parmağıyla odanın diğer köşesindeki büyük sarı balonu gösterir: "Ali bak sarı balona!" (t₀).',
        'p1': 'Toddler sits holding the blue cup in both hands on the rug.',
        'p2': 'Adult extends right arm clearly into frame, index finger pointing upward across the room toward a large yellow ball, saying "Ali, look at the big balloon!".',
        'p3': 'Adult holds pointing vector completely static for 3 full seconds, encouraging gaze following.',
        'vo': 'İkinci test: Ortak dikkate yanıt (ONT-02 / RJA). Yetişkin belirgin bir işaret jestiyle uzaktaki nesneyi gösteriyor.',
        'gt': {'is_test': true, 'event': 'POINTING_STIMULUS', 'ontology': 'ONT-02'},
      },
      {
        'title': 'ONT-02 Tepkisi — Sarı Dal (Sınırda Gecikmeli & Kararsız Yanıt)',
        'type': 'REACTION_YELLOW',
        'phase': 'Faz 4: Test 2 (ONT-02)',
        'ont': 'ONT-02',
        'cam': 'Medium close-up framing child\'s face and upper torso at eye level',
        'action': 'Çocuk 2.5 saniye sonra başını yarım çevirir (Sarı Eşik), işaret edilen balona değil sadece yetişkinin eline kısa bakar.',
        'p1': 'Toddler stays motionless looking at cup for 2 seconds. At 2.5s, head slowly begins a delayed, sluggish rotation.',
        'p2': 'Rotates head approx 30 degrees only toward adult\'s hand, offering a brief 0.5-second fleeting glance at the pointing finger.',
        'p3': 'Does NOT follow the line of sight to the distant balloon; drops gaze immediately back to the blue cup with flat neutral expression.',
        'vo': 'İzlem gerektiren sınırda tepki: Çocuk yönergeye gecikmeli baktı ancak hedef nesneye değil, yalnızca parmağa baktı (ONT-02: 2.0s < Δt ≤ 4.0s).',
        'gt': {'is_test': true, 'branch': 'YELLOW_BORDERLINE', 'ontology': 'ONT-02', 'latency': '2.5s', 'cv_label': 'BORDERLINE_WATCH'},
      },
      {
        'title': 'ONT-02 Sonrası — Mavi Kupayı Yere Bırakma',
        'type': 'TRANSITION',
        'phase': 'Faz 4: Test 2 (ONT-02)',
        'ont': 'ONT-02',
        'cam': 'Slow pull-back to wide shot, soft morning light illuminating child\'s posture',
        'action': 'Yetişkin kolunu çeker, çocuk mavi kupayı halıya bırakıp bağdaş kurmuş şekilde bekler.',
        'p1': 'Adult\'s pointing hand gently withdraws from the frame. Toddler lowers the blue cup to the rug surface.',
        'p2': 'Releases fingers, allowing cup to stand upright on the cream geometric wool.',
        'p3': 'Rests both palms comfortably on the carpet, taking a quiet calm breath in neutral sitting posture.',
        'vo': 'İşaret uyarını sonlandıktan sonra çocuk serbest oyun alanında dengeli pozisyonunu koruyor.',
        'gt': {'is_test': false, 'activity': 'TRANSITION_TO_PLAY', 'risk': 'NEUTRAL'},
      },

      // FAZ 5: TEKRARLAYICI VE DUYUSAL MOTOR BELİRTİLER
      {
        'title': 'Stereotipi — Kırmızı Arabanın Tekerleğini Sürekli Döndürme',
        'type': 'BASE_PLAY',
        'phase': 'Faz 5: Tekrarlayıcı Davranış',
        'cam': 'Tight macro close-up on child\'s small hands and the red wooden car wheel',
        'action': 'Çocuk arabayı sürmez, başını zemine yaklaştırıp tekerleği durmaksızın parmağıyla döndürür.',
        'p1': 'Toddler lowers upper body so cheek is only 15cm from the rug, staring horizontally at the front car wheel.',
        'p2': 'Right index finger flicks the rubberized wheel rim repeatedly at a rapid 3 Hz frequency, watching the rotating blur.',
        'p3': 'Maintains non-functional wheel spinning uninterrupted, showing deep sensory fascination with rotation physics.',
        'vo': 'Fonksiyonel olmayan tekrarlayıcı nesne kullanımı: Arabayı sürmek yerine tekerin dönüşüne görsel saplanma (hiperfokus).',
        'gt': {'is_test': false, 'activity': 'REPETITIVE_WHEEL_SPIN', 'risk': 'HIGH_ATYPICAL'},
      },
      {
        'title': 'Motor Belirti — İki Taraflı Heyecanlı El Çırpma (Hand-Flapping)',
        'type': 'BASE_PLAY',
        'phase': 'Faz 5: Tekrarlayıcı Davranış',
        'cam': 'Medium shot framing child from chest up, natural window light catchlights in eyes',
        'action': 'Çocuk teker dönerken aniden ellerini göğüs hizasına kaldırıp 2.5 saniye hızlıca çırpar.',
        'p1': 'Toddler straightens up from floor, suddenly lifting both wrists to mid-chest height with tense finger extension.',
        'p2': 'Exhibits rapid, bilateral hand-flapping (finger flutter) at 3-4 Hz frequency for 2.5 seconds with wide excited unblinking eyes.',
        'p3': 'Flapping subsides naturally; hands drop back down to knees as breathing returns to calm rhythmic state.',
        'vo': 'Uyarılma anında ortaya çıkan istemsiz iki taraflı el çırpma (hand flapping) motor stereotipisi belgelendi.',
        'gt': {'is_test': false, 'activity': 'HAND_FLAPPING_STEREOTYPY', 'risk': 'HIGH_ATYPICAL'},
      },
      {
        'title': 'Keşif — Şeffaf Kilitli Kutuyu Fark Etme',
        'type': 'BASE_PLAY',
        'phase': 'Faz 5: Tekrarlayıcı Davranış',
        'cam': 'Static eye-level wide shot capturing child and the transparent acrylic box on the rug',
        'action': 'Çocuk halıda 40 cm ileride duran, içinde renkli oyuncak olan kilitli şeffaf kutuyu fark eder.',
        'p1': 'Toddler sits still, eyes shifting across the cream rug until spotting a clear acrylic sensory container with a red snap lid.',
        'p2': 'Inside the transparent box, a bright yellow rubber duck toy is clearly visible, catching child\'s gaze.',
        'p3': 'Crawls forward two knee-steps, placing hands onto the clear plastic lid, trying to peer inside.',
        'vo': 'Çocuğun dikkati kilitli şeffaf kutudaki cazip nesneye yöneliyor.',
        'gt': {'is_test': false, 'activity': 'NOTICE_LOCKED_BOX', 'risk': 'NEUTRAL'},
      },

      // FAZ 6: TEST 3 (ONT-06 EL ALETİ OLARAK KULLANMA)
      {
        'title': 'ONT-06 Uyaranı — Kilitli Kutu ve Yetişkinin Sessiz Eli',
        'type': 'STIMULUS',
        'phase': 'Faz 6: Test 3 (ONT-06)',
        'ont': 'ONT-06',
        'cam': 'Medium profile two-shot showing child struggling with container and adult seated nearby',
        'action': 'Çocuk sıkı kapağı açamaz. Yetişkin sessizce elini halıya uzatıp hareketsiz bekler (t₀).',
        'p1': 'Toddler pulls and tugs firmly at the red snap lid of the acrylic container, but little fingers cannot pry it open.',
        'p2': 'Adult sitting beside places an open relaxed hand flat on the rug, 20 cm from the child, remaining completely silent.',
        'p3': 'Toddler pauses struggling with lid, turning eyes down toward the adult\'s stationary hand.',
        'vo': 'Üçüncü test: İstek bildirme ve el aleti kullanma (ONT-06). Çocuk yetişkinin yüzüne bakarak yardım mı isteyecek, yoksa elini mekanik alet gibi mi çekecek?',
        'gt': {'is_test': true, 'event': 'LOCKED_CONTAINER_TEST', 'ontology': 'ONT-06'},
      },
      {
        'title': 'ONT-06 Tepkisi — Kırmızı Dal (Göz Temassız El Sürükleme)',
        'type': 'REACTION_RED',
        'phase': 'Faz 6: Test 3 (ONT-06)',
        'ont': 'ONT-06',
        'cam': 'Medium close-up focusing on child\'s hands grasping adult\'s wrist and dragging it to the box',
        'action': 'Çocuk yetişkinin yüzüne HİÇ bakmadan bileğini tutar, cansız bir pense gibi kapağın üstüne sürükler.',
        'p1': 'Toddler grabs adult\'s wrist with both small hands with total absence of eye contact; does not glance at adult\'s face for even a fraction of a second.',
        'p2': 'Physically drags adult\'s inert hand mechanically over the acrylic box lid, pushing adult fingers onto the red latch like a tool.',
        'p3': 'Eyes remain 100% glued to the red plastic latch. Treats adult purely as a mechanical instrument (Hand-Leading / Hand as a Tool).',
        'vo': 'Kritik atipik bulgu (ONT-06 Kırmızı Eşik): Çocuk yetişkinle göz teması kurmaksızın yetişkinin elini kutuyu açacak cansız bir araç gibi kullandı.',
        'gt': {'is_test': true, 'branch': 'RED_ATYPICAL', 'ontology': 'ONT-06', 'cv_label': 'HAND_AS_TOOL_FAIL'},
      },
      {
        'title': 'Kutunun Açılması — Sarı Ördeğin Çıkarılması',
        'type': 'TRANSITION',
        'phase': 'Faz 6: Test 3 (ONT-06)',
        'ont': 'ONT-06',
        'cam': 'Medium shot, warm ambient light, steady framing',
        'action': 'Yetişkin kapağı açar, çocuk içindeki sarı ördeği alıp halıda oturur.',
        'p1': 'Adult smoothly clicks open the red lid. Toddler immediately reaches inside and grasps the small yellow rubber duck.',
        'p2': 'Pulls the duck out, holding it close to chest while turning it over in fingers.',
        'p3': 'Sits comfortably back on the cream rug, tactilely exploring the soft rubber toy.',
        'vo': 'İstek karşılandıktan sonra çocuk hedefine ulaştı ve sakin oyununa döndü.',
        'gt': {'is_test': false, 'activity': 'RETRIEVE_DUCK', 'risk': 'NEUTRAL'},
      },

      // FAZ 7: TEST 4 (ONT-08 SOSYAL GÜLÜMSEME / CE-EE OYUNU)
      {
        'title': 'ONT-08 Uyaranı — Yetişkin Tülle "Ce-ee!" (Peek-a-boo) Başlatır',
        'type': 'STIMULUS',
        'phase': 'Faz 7: Test 4 (ONT-08)',
        'ont': 'ONT-08',
        'cam': 'Eye-level medium shot framing child directly, with adult\'s hands holding a sheer silk cloth in front',
        'action': 'Yetişkin yüzünü pastel ipek tülle kapatıp "Ce-ee!" diyerek açar, neşeyle gülümser (t₀).',
        'p1': 'Toddler sits holding the rubber duck. In front, adult covers own face with a sheer pastel silk cloth, animated voice: "Where am I?...".',
        'p2': 'Adult drops cloth down with an enthusiastic, joyful "Peek-a-boo!", smiling warmly with wide open expressive eyes.',
        'p3': 'Adult holds radiant social smile for 3 seconds, waiting for reciprocal shared affect from toddler.',
        'vo': 'Dördüncü test: Sosyal gülümseme ve karşılıklı neşe paylaşımı (ONT-08 / Shared Affect). Karşılıklı sosyal oyunda çocuğun duygulanım tepkisi ölçülüyor.',
        'gt': {'is_test': true, 'event': 'PEEKABOO_STIMULUS', 'ontology': 'ONT-08'},
      },
      {
        'title': 'ONT-08 Tepkisi — Sarı Dal (Donuk Yüz İfadesi & Gülümsememe)',
        'type': 'REACTION_YELLOW',
        'phase': 'Faz 7: Test 4 (ONT-08)',
        'ont': 'ONT-08',
        'cam': 'Tight portrait close-up on child\'s facial landmarks and mouth corners',
        'action': 'Çocuk yetişkine kısa bakar ancak hiç gülümsemez; ağız kenarları kalkmaz (AU12 yok), donuk nötr ifade.',
        'p1': 'Toddler looks at adult\'s smiling face for 1.2 seconds, but facial expression remains completely flat and serious.',
        'p2': 'Zero zygomaticus major muscle activation (Facial Action Unit AU12 absent); mouth line stays completely straight and motionless.',
        'p3': 'Breaks gaze passively, looking back down at the yellow duck with neutral indifference, missing social reciprocity.',
        'vo': 'Sınırda klinik gösterge (ONT-08 Sarı Eşik): Çocuk yetişkinin neşeli sosyal oyununa gülümsemeyle eşlik etmedi (Lack of shared enjoyment).',
        'gt': {'is_test': true, 'branch': 'YELLOW_BORDERLINE', 'ontology': 'ONT-08', 'cv_label': 'FLAT_AFFECT_WATCH'},
      },
      {
        'title': 'ONT-08 Sonrası — Kahverengi Peluş Ayıya Yönelme',
        'type': 'TRANSITION',
        'phase': 'Faz 7: Test 4 (ONT-08)',
        'ont': 'ONT-08',
        'cam': 'Slow pull-back to wide establishing shot, soft natural morning window lighting',
        'action': 'Yetişkin tülü toplar, çocuk halıda duran küçük kahverengi peluş ayıya uzanır.',
        'p1': 'Adult quietly sets the silk cloth aside. Toddler shifts knees across the cream rug pile.',
        'p2': 'Reaches both hands toward a 25cm soft brown plush teddy bear resting beside the wooden blocks.',
        'p3': 'Pulls the teddy bear into lap, sitting comfortably in independent solace.',
        'vo': 'Sosyal oyun denemesi bittikten sonra çocuk dokunsal nesne keşfine yöneliyor.',
        'gt': {'is_test': false, 'activity': 'REACH_TEDDY_BEAR', 'risk': 'NEUTRAL'},
      },

      // FAZ 8: SEANS KAPANIŞI
      {
        'title': 'Kapanış — Peluş Ayıya Sarılma ve Dokunsal Rahatlama',
        'type': 'BASE_PLAY',
        'phase': 'Faz 8: Kapanış & Sakinleşme',
        'cam': 'Medium shot at 40cm height, gentle warm lighting',
        'action': 'Çocuk peluş ayıyı iki eliyle göğsüne bastırır, sakin oturur.',
        'p1': 'Toddler gently wraps arms around the plush teddy bear, pressing soft fur against the yellow corduroy dungarees.',
        'p2': 'Strokes the plush bear ear with thumb, looking quietly toward the sunlight across the ash floor.',
        'p3': 'Remains in peaceful resting sitting posture, breathing gently.',
        'vo': 'Çocuğun dokunsal regülasyon ve sakinleşme davranışı gözleniyor.',
        'gt': {'is_test': false, 'activity': 'HUG_TEDDY_BEAR', 'risk': 'NEUTRAL'},
      },
      {
        'title': 'Kapanış — Kalın Karton Kitabın Sayfalarını Çevirme',
        'type': 'BASE_PLAY',
        'phase': 'Faz 8: Kapanış & Sakinleşme',
        'cam': '45-degree angle medium shot looking down at child and book',
        'action': 'Çocuk yerdeki kalın resimli çocuk kitabını açar, sayfayı parmaklarıyla çevirir.',
        'p1': 'Toddler sets teddy bear down and opens a sturdy cardboard picture book resting on the rug.',
        'p2': 'Uses pincer grip thumb and index finger to turn a thick cardboard page with focused infant motor control.',
        'p3': 'Stares down at the bright animal illustrations on the page, sitting quietly in golden window light.',
        'vo': 'Görsel ilgi ve ince motor sayfa çevirme becerileri izleniyor.',
        'gt': {'is_test': false, 'activity': 'PAGE_TURNING', 'risk': 'NEUTRAL'},
      },
      {
        'title': 'Kapanış — Mavi Kupayı Şeffaf Kutuya Geri Bırakma',
        'type': 'BASE_PLAY',
        'phase': 'Faz 8: Kapanış & Sakinleşme',
        'cam': 'Static wide tripod shot, symmetrical framing',
        'action': 'Çocuk yerdeki mavi kupayı alıp açık duran şeffaf kutunun içine geri bırakır.',
        'p1': 'Toddler reaches over, picks up the pastel-blue stacking cup from the rug pile.',
        'p2': 'Carefully drops the cup inside the open acrylic container with a gentle clinking sound.',
        'p3': 'Pulls hands back, resting them serenely on knees in centered balance.',
        'vo': 'Spontane toplama ve nesne yerleştirme davranışı gözlemlendi.',
        'gt': {'is_test': false, 'activity': 'OBJECT_CLEANUP', 'risk': 'NEUTRAL'},
      },
      {
        'title': 'Kapanış — Halıda Sakin Oturma ve Seansın Tamamlanması',
        'type': 'BASE_PLAY',
        'phase': 'Faz 8: Kapanış & Sakinleşme',
        'cam': 'Slow cinematic pull-back tracking out to full wide room perspective, fading gently',
        'action': 'Kamera yavaşça geriye çekilir; çocuk oyuncakların ortasında huzurla oturur, seans tamamlanır.',
        'p1': 'Toddler sits serenely in the center of the cream geometric rug, surrounded by the wooden blocks, red car, and teddy bear.',
        'p2': 'Hands rest softly in lap, head held naturally upright in warm sunbeams streaming through the nursery window.',
        'p3': 'Camera holds a tranquil wide composition as the 3.2-minute clinical screening observation concludes seamlessly.',
        'vo': 'Kennedy Krieger 18 Ay Erken Çocukluk Otizm Tarama Seansı başarıyla tamamlandı. Tüm klinik parametreler kaydedildi.',
        'gt': {'is_test': false, 'activity': 'SESSION_CONCLUDED', 'risk': 'NEUTRAL'},
      },
    ];

    final steps = <VeoPromptStep>[];
    var curSec = 0;
    var stepIndex = 1;

    for (final item in rawDefs) {
      final choreo = makeMarks(item['p1'] as String, item['p2'] as String, item['p3'] as String);
      final bId = 'CLIP_${stepIndex.toString().padLeft(2, '0')}_${item['type']}';

      String promptText;
      String extendNote;

      if (stepIndex == 1) {
        extendNote = 'YENİ VİDEO: Bu promptu Google Veo\'ya ilk başlangıç videosu olarak verin (Süre: ${dur}s).';
        promptText =
            'A wide full-shot cinematic video of a $charSpec. Setting: Seated comfortably on the floor in a $envSpec. Camera: ${item['cam']}. Second-by-second timeline actions: $choreo. Cinematic standards: $styleAnchor.';
      } else {
        final prevId = steps.last.blockId;
        extendNote = 'EXTEND VIDEO: Google Veo\'da $prevId klibinin son karesinden "Extend" yapın (Süre: ${dur}s).';
        promptText =
            'Continuing seamlessly from the exact ending frame and body pose of the previous shot. Subject: Same $charSpec. Setting: Same $envSpec, exact same carpet position and room geometry. Camera movement: ${item['cam']}. Second-by-second action sequence: $choreo. Strict continuity: Maintain exact facial features, curly hair parting, lighting angle (3800K), and wood textures without morphing. Aesthetics: $styleAnchor.';
      }

      steps.add(
        VeoPromptStep(
          stepNumber: stepIndex,
          blockId: bId,
          blockType: item['type'] as String,
          startSec: curSec,
          endSec: curSec + dur,
          durationSec: dur,
          ontologyCode: item['ont'] as String?,
          phaseName: item['phase'] as String,
          title: item['title'] as String,
          cameraMovement: item['cam'] as String,
          actionDescription: item['action'] as String,
          clinicalVoiceover: item['vo'] as String,
          veoPrompt: promptText,
          veoExtendNote: extendNote,
          groundTruth: item['gt'] as Map<String, dynamic>,
        ),
      );

      curSec += dur;
      stepIndex++;
    }

    return VeoPromptSession(
      title: 'Kennedy Krieger 18 Ay Erken Otizm Klinik Gözlem Seansı (Google Veo)',
      targetAgeMonths: ageMonths,
      totalDurationSec: curSec,
      blockDurationSec: dur,
      totalStepsCount: steps.length,
      characterDescription: charSpec,
      environmentDescription: envSpec,
      steps: steps,
    );
  }
}
