import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scenarios_data.dart';

class LlmRagService {
  static const String _apiKeyPrefKey = 'user_gemini_api_key';

  /// Cihazda saklanan Gemini API Anahtarını getirir
  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_apiKeyPrefKey);
    return (key != null && key.trim().isNotEmpty) ? key.trim() : null;
  }

  /// Kullanıcının girdiği API anahtarını kaydeder
  static Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyPrefKey, key.trim());
  }

  /// Saklanan API anahtarını temizler
  static Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiKeyPrefKey);
  }

  /// RAG + LLM Senaryo Üretim Pipeline'ı
  static Future<ScenarioModel> generateScenario({
    required int ageMonths,
    required String behaviorCode,
    required String contextEnvironment,
    required String specificItems,
    Function(String stepMessage)? onProgress,
  }) async {
    final ageGroup = _getAgeGroup(ageMonths);
    final ctx = contextEnvironment.trim().isEmpty ? 'Ev ortamında serbest oyun alanı' : contextEnvironment.trim();
    final items = specificItems.trim().isEmpty ? 'oyuncaklar' : specificItems.trim();

    onProgress?.call('1. Adım: RAG Bilgi Tabanı Taranıyor (Klinik PDF Ontolojileri)...');
    await Future.delayed(const Duration(milliseconds: 300));

    // 1. ADIM: RAG RETRIEVAL (Tasarım belgelerinden klinik kuralları çekme)
    final ragRules = _retrieveClinicalRules(behaviorCode, ageGroup);

    onProgress?.call('2. Adım: LLM Senaryo ve FSM Durum Ağacını Kuruyor...');

    final apiKey = await getApiKey();
    ScenarioModel? generatedScenario;

    // Eğer kullanıcı bir Gemini API Key girdiyse, gerçek Gemini LLM'e bağlan
    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        generatedScenario = await _callGeminiApi(
          apiKey: apiKey,
          ageMonths: ageMonths,
          ageGroup: ageGroup,
          behaviorCode: behaviorCode,
          ctx: ctx,
          items: items,
          ragRules: ragRules,
        );
      } catch (e) {
        debugPrint('Gemini API çağrısı başarısız, yerel motora geçiliyor: $e');
      }
    }

    // API Key yoksa veya API çağrısı başarısız olduysa, akıllı yerel motorla üret (Fallback)
    generatedScenario ??= _generateLocalClinicalScenario(
      ageMonths: ageMonths,
      ageGroup: ageGroup,
      behaviorCode: behaviorCode,
      ctx: ctx,
      items: items,
      ragRules: ragRules,
      isAiGenerated: apiKey != null && apiKey.isNotEmpty,
    );

    onProgress?.call('3. Adım: Senaryo Başarıyla FSM Grafiğine Eklendi.');
    await Future.delayed(const Duration(milliseconds: 200));

    // Senaryoyu listeye ekle
    ScenariosRepository.addGeneratedScenario(generatedScenario);

    return generatedScenario;
  }

  static String _getAgeGroup(int months) {
    if (months < 18) return '12–18 Ay';
    if (months < 24) return '18–24 Ay';
    return '24–36 Ay';
  }

  /// RAG RETRIEVAL: Klinik kuralları cımbızla çeker
  static Map<String, dynamic> _retrieveClinicalRules(String code, String ageGroup) {
    // Tasarım belgelerindeki referans ontolojiyi bul
    final baseScenario = ScenariosRepository.allScenarios.firstWhere(
      (s) => s.code == code,
      orElse: () => ScenariosRepository.allScenarios.first,
    );

    final branches = baseScenario.getBranchesForAge(ageGroup);
    final expectedAction = baseScenario.ageBreakdowns[ageGroup] ?? baseScenario.antecedent;

    return {
      'code': baseScenario.code,
      'title': baseScenario.title,
      'category': baseScenario.category,
      'expectedAction': expectedAction,
      'riskThreshold': baseScenario.riskThreshold,
      'measurementCriteria': baseScenario.measurementCriteria,
      'green': branches.isNotEmpty ? branches[0] : null,
      'yellow': branches.length > 1 ? branches[1] : null,
      'red': branches.length > 2 ? branches[2] : null,
    };
  }

  /// GERÇEK GOOGLE GEMINI API ÇAĞRISI
  static Future<ScenarioModel> _callGeminiApi({
    required String apiKey,
    required int ageMonths,
    required String ageGroup,
    required String behaviorCode,
    required String ctx,
    required String items,
    required Map<String, dynamic> ragRules,
  }) async {
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey',
    );

    final prompt = '''
Sen klinik bir çocuk gelişimi uzmanı ve otizm tarama pedagojisisin (ADOS-2 ve M-CHAT-R).
Aşağıdaki RAG klinik ontoloji kurallarına ve kullanıcının ev ortamına dayanarak YENİ bir test senaryosu ve 3 FSM dalı (Yeşil, Sarı, Kırmızı) üret.
ASLA "otizm teşhisi" koyma. Çıktıyı SADECE geçerli bir JSON olarak ver.

[KLİNİK RAG BİLGİLERİ]:
- Davranış: ${ragRules['title']} (${ragRules['code']})
- Çocuğun Yaşı: $ageMonths Ay (Klinik Grup: $ageGroup)
- Beklenen Yaş Gelişim Normu: ${ragRules['expectedAction']}
- Atipik Risk Eşiği: ${ragRules['riskThreshold']}

[KULLANICININ ORTAMI]:
- Mekan / Durum: $ctx
- Kullanılacak Nesneler: $items

LÜTFEN SADECE ŞU JSON FORMATINDA CEVAP VER:
{
  "title": "$ctx - ${ragRules['title']}",
  "antecedent": "Öncül uyaran açıklaması (t0)",
  "instruction": "Ebeveyn yönergesi (nasıl yapılır)",
  "green_title": "Tipik Yanıt Başlığı",
  "green_latency": "${ragRules['green']?.latency ?? 'Δt ≤ 2.0 sn'}",
  "green_details": "Yeşil dalda çocuğun bu ortamda yapacağı eylem",
  "yellow_title": "İzlem Gerektiren Tepki",
  "yellow_latency": "${ragRules['yellow']?.latency ?? 'Δt > 3.0 sn'}",
  "yellow_details": "Sarı dalda çocuğun gecikmeli eylemi",
  "red_title": "Gelişimsel Risk / Atipik",
  "red_latency": "${ragRules['red']?.latency ?? 'Tepkisiz'}",
  "red_details": "Kırmızı dalda tepkisizlik veya atipik eylem"
}
''';

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.4,
          'responseMimeType': 'application/json',
        }
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final rawText = data['candidates'][0]['content']['parts'][0]['text'] as String;
      final parsed = jsonDecode(rawText);

      return _buildScenarioModelFromParsed(
        parsed: parsed,
        behaviorCode: behaviorCode,
        ageMonths: ageMonths,
        ageGroup: ageGroup,
        ragRules: ragRules,
        ctx: ctx,
      );
    } else {
      throw Exception('Gemini API Hatası: ${response.statusCode} - ${response.body}');
    }
  }

  /// YEREL KLİNİK SENTETİK MOTOR (API Olmadığında veya Çevrimdışı Çalışır)
  static ScenarioModel _generateLocalClinicalScenario({
    required int ageMonths,
    required String ageGroup,
    required String behaviorCode,
    required String ctx,
    required String items,
    required Map<String, dynamic> ragRules,
    required bool isAiGenerated,
  }) {
    final title = '$ctx — ${ragRules['title']}';
    String antecedent;
    String instruction;

    if (behaviorCode == 'ONT-01') {
      antecedent = 'Çocuk $ctx alanında $items ile odaklanmışken, yetişkin 1.5m gerisinden net sesle adını seslenir (t₀).';
      instruction = 'Nasıl Yapılır: Görüş alanına girmeden arkasından 1 kez adını söyleyin; 3 sn içinde dönmezse tekrarlayın.';
    } else if (behaviorCode == 'ONT-02') {
      antecedent = '$ctx ortamında yetişkin uzaktaki $items nesnesini parmağıyla göstererek "Bak oradaki $items!" der (t₀).';
      instruction = 'Nasıl Yapılır: 1 metre uzaktaki $items nesnesini işaret edin; parmağa mı yoksa nesneye mi baktığını izleyin.';
    } else if (behaviorCode == 'ONT-04') {
      antecedent = '$ctx içinde çocuğun ilgisini çekecek $items belirir veya hareket eder (t₀).';
      instruction = 'Nasıl Yapılır: İlgiyi paylaşmak için işaret parmağını uzatıp yetişkine bakıp bakmadığını gözlemleyin.';
    } else if (behaviorCode == 'ONT-06') {
      antecedent = 'Çocuğun açmakta zorlanacağı kapalı/kilitli bir $items önüne konur (t₀).';
      instruction = 'Nasıl Yapılır: Çocuğun göz temasıyla yardım mı istediğini, yoksa eli alet gibi mi çektiğini izleyin.';
    } else {
      antecedent = '$ctx alanında $items ile etkileşim başlatılır ve standart öncül uyaran sunulur (t₀).';
      instruction = 'Nasıl Yapılır: $ctx ortamında standart ADOS-2/M-CHAT protokolünü uygulayın.';
    }

    final ScenarioBranchModel greenRef = ragRules['green'] as ScenarioBranchModel;
    final ScenarioBranchModel yellowRef = ragRules['yellow'] as ScenarioBranchModel;
    final ScenarioBranchModel redRef = ragRules['red'] as ScenarioBranchModel;

    final branches = [
      ScenarioBranchModel(
        title: greenRef.title,
        level: 'YEŞİL',
        color: Colors.green,
        latency: greenRef.latency,
        details: 'Çocuk $ctx içinde uyaran verildiğinde ${greenRef.latency} sürede ${greenRef.details}',
        clinicalOutcome: '$ageGroup normlarında tipik yanıt. Klinik beklenti (${ragRules['expectedAction']}) karşılandı.',
      ),
      ScenarioBranchModel(
        title: yellowRef.title,
        level: 'SARI',
        color: Colors.orange,
        latency: yellowRef.latency,
        details: 'Çocuk $ctx ortamında gecikmeli olarak (${yellowRef.latency}) ${yellowRef.details}',
        clinicalOutcome: '$ageGroup izlem kategorisi. Gelişimsel takip önerilir.',
      ),
      ScenarioBranchModel(
        title: redRef.title,
        level: 'KIRMIZI',
        color: Colors.red,
        latency: redRef.latency,
        details: 'Çocuk $ctx ortamında ${redRef.details}',
        clinicalOutcome: 'M-CHAT-R erken risk eşiği: ${ragRules['riskThreshold']}. Uzman değerlendirmesi önerilir.',
      ),
    ];

    return ScenarioModel(
      code: 'AI-${ragRules['code']}',
      title: title,
      category: 'Kişiselleştirilmiş Senaryo (${ragRules['category']})',
      ageRange: '$ageMonths Ay ($ageGroup)',
      minAgeMonths: ageMonths,
      maxAgeMonths: ageMonths,
      antecedent: antecedent,
      instruction: instruction,
      measurementCriteria: ragRules['measurementCriteria'] ?? 'Bilgisayarlı görü çıkarımı',
      riskThreshold: ragRules['riskThreshold'] ?? 'Gelişimsel risk',
      ageBreakdowns: {
        ageGroup: ragRules['expectedAction'] ?? 'Gelişimsel norm',
      },
      branches: branches,
      ageSpecificBranches: {
        ageGroup: branches,
      },
    );
  }

  static ScenarioModel _buildScenarioModelFromParsed({
    required Map<String, dynamic> parsed,
    required String behaviorCode,
    required int ageMonths,
    required String ageGroup,
    required Map<String, dynamic> ragRules,
    required String ctx,
  }) {
    final branches = [
      ScenarioBranchModel(
        title: parsed['green_title'] ?? 'Tipik Yanıt',
        level: 'YEŞİL',
        color: Colors.green,
        latency: parsed['green_latency'] ?? 'Δt ≤ 2.0 sn',
        details: parsed['green_details'] ?? 'Tipik eylem gerçekleşti.',
        clinicalOutcome: '$ageGroup normlarında tipik yanıt. $ctx ortamında beklenen davranış tam sergilendi.',
      ),
      ScenarioBranchModel(
        title: parsed['yellow_title'] ?? 'İzlem Gerektiren Tepki',
        level: 'SARI',
        color: Colors.orange,
        latency: parsed['yellow_latency'] ?? 'Δt > 3.0 sn',
        details: parsed['yellow_details'] ?? 'Gecikmeli tepki verildi.',
        clinicalOutcome: '$ageGroup gelişimsel izlem kategorisi. 2-4 hafta sonra yeniden gözlem önerilir.',
      ),
      ScenarioBranchModel(
        title: parsed['red_title'] ?? 'Gelişimsel Risk / Atipik',
        level: 'KIRMIZI',
        color: Colors.red,
        latency: parsed['red_latency'] ?? 'Tepkisiz',
        details: parsed['red_details'] ?? 'Tepkisiz veya atipik davranış.',
        clinicalOutcome: 'M-CHAT-R ve ADOS-2 standartlarına göre erken risk eşiği: ${ragRules['riskThreshold']}.',
      ),
    ];

    return ScenarioModel(
      code: 'AI-${ragRules['code']}',
      title: parsed['title'] ?? '$ctx — ${ragRules['title']}',
      category: 'Gemini LLM Üretimi (${ragRules['category']})',
      ageRange: '$ageMonths Ay ($ageGroup)',
      minAgeMonths: ageMonths,
      maxAgeMonths: ageMonths,
      antecedent: parsed['antecedent'] ?? 'Öncül uyaran sunulur.',
      instruction: parsed['instruction'] ?? 'Nasıl yapılır yönergesi.',
      measurementCriteria: ragRules['measurementCriteria'] ?? 'Bilgisayarlı görü çıkarımı',
      riskThreshold: ragRules['riskThreshold'] ?? 'Gelişimsel risk',
      ageBreakdowns: {
        ageGroup: ragRules['expectedAction'] ?? 'Gelişimsel norm',
      },
      branches: branches,
      ageSpecificBranches: {
        ageGroup: branches,
      },
    );
  }
}
