import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ServerHealthStatus {
  final bool isOnline;
  final bool geminiConfigured;
  final String message;

  const ServerHealthStatus({
    required this.isOnline,
    required this.geminiConfigured,
    required this.message,
  });
}

class ServerApiService {
  static const String defaultBaseUrl = String.fromEnvironment(
    'SCENARIO_SERVER_URL',
    defaultValue: 'http://31.77.69.171',
  );
  static const Set<String> _legacyLocalServerUrls = {
    'http://10.0.2.2:8000',
    'http://10.0.2.2:18000',
  };
  static String baseUrl = defaultBaseUrl;
  static const String _serverUrlKey = 'custom_server_base_url';
  static String selectedArm = 'B';
  static const String _serverArmKey = 'custom_server_arm';

  /// Kayıtlı sunucu adresini yükler
  static Future<String> getBaseUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_serverUrlKey);
      if (saved != null && saved.trim().isNotEmpty) {
        final normalized = saved.trim();
        if (_legacyLocalServerUrls.contains(normalized)) {
          // Remove only the two app-provided emulator/tunnel endpoints. Any
          // other saved address belongs to the user and must remain intact.
          await prefs.remove(_serverUrlKey);
          baseUrl = defaultBaseUrl;
        } else {
          baseUrl = normalized;
        }
      } else {
        baseUrl = defaultBaseUrl;
      }
      final savedArm = prefs.getString(_serverArmKey);
      if (savedArm != null && ['A', 'B', 'C'].contains(savedArm)) {
        selectedArm = savedArm;
      }
    } catch (_) {}
    return baseUrl;
  }

  /// Deney kolunu ayarlar ('A' Baseline, 'B' Kural Enjeksiyonlu, 'C' Full-Context)
  static Future<void> setSelectedArm(String arm) async {
    selectedArm = ['A', 'B', 'C'].contains(arm) ? arm : 'B';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_serverArmKey, selectedArm);
    } catch (_) {}
  }

  /// Sunucu adresini günceller ve kaydeder
  static Future<void> setBaseUrl(String url) async {
    var cleanUrl = url.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'http://$cleanUrl';
    }
    // Sondaki slash'ı kaldır
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    baseUrl = cleanUrl;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_serverUrlKey, baseUrl);
    } catch (_) {}
  }

  /// Sunucu ayakta mı ve Gemini bağlı mı kontrol eder
  static Future<ServerHealthStatus> checkHealth([String? testUrl]) async {
    final target = testUrl ?? baseUrl;
    try {
      final res = await http
          .get(Uri.parse('$target/health'))
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return ServerHealthStatus(
          isOnline: true,
          geminiConfigured: data['geminiConfigured'] == true,
          message: data['message'] ?? 'Sunucu çevrimiçi.',
        );
      }
      return ServerHealthStatus(
        isOnline: false,
        geminiConfigured: false,
        message: 'Sunucu yanıt kodu: ${res.statusCode}',
      );
    } catch (e) {
      return ServerHealthStatus(
        isOnline: false,
        geminiConfigured: false,
        message: 'Sunucuya bağlanılamadı (${e.toString()})',
      );
    }
  }

  /// Sunucudaki Gemini Veo Motoru ile 26 sahneli klinik senaryo üretir (Timeout: 120 sn)
  static Future<Map<String, dynamic>> generateScenario({
    required int ageMonths,
    required String ontologyCode,
    required String riskProfile,
    String? arm,
    String childName = 'Deniz',
    String materials = 'Kırmızı Ahşap Araba ve Kayın Bloklar',
    String language = 'tr',
  }) async {
    final effectiveArm = arm ?? selectedArm;
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/generate-scenario'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'arm': effectiveArm,
            'ageMonths': ageMonths,
            'ontologyCode': ontologyCode,
            'ontologyCodes': [ontologyCode],
            'riskProfile': riskProfile.toUpperCase(),
            'childName': childName,
            'materials': materials,
            'language': language,
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data['success'] == true) {
        final sc = data['scenario'];
        Map<String, dynamic> result;
        if (sc is Map<String, dynamic>) {
          result = Map<String, dynamic>.from(sc);
        } else if (sc is Map) {
          result = Map<String, dynamic>.from(sc);
        } else {
          result = {'summary': sc.toString(), 'title': 'Klinik Protokol'};
        }

        // Metodoloji v2 Benchmark ve Doğrulama verilerini ekle
        result['_benchmark'] = data['benchmark'];
        result['_validation'] = data['validation'];
        result['_arm'] = data['arm'] ?? effectiveArm;
        result['_model'] = data['model'];
        return result;
      } else {
        throw Exception(data['error'] ?? 'Bilinmeyen sunucu hatası');
      }
    } else {
      final errBody = jsonDecode(utf8.decode(response.bodyBytes));
      throw Exception(errBody['error'] ?? 'Sunucu HTTP hatası: ${response.statusCode}');
    }
  }

  /// Seçilen videoyu sunucuya gönderip Gemini Vision ile analiz ettirir
  static Future<Map<String, dynamic>> analyzeVideo(File videoFile) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/analyze-video'),
    );

    request.files.add(
      await http.MultipartFile.fromPath('video', videoFile.path),
    );

    final streamedResponse = await request.send().timeout(const Duration(minutes: 2));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data['success'] == true) {
        return data['data'] as Map<String, dynamic>;
      } else {
        throw Exception(data['error'] ?? 'Video analiz hatası');
      }
    } else {
      final errBody = jsonDecode(utf8.decode(response.bodyBytes));
      throw Exception(errBody['error'] ?? 'Sunucu hatası: ${response.statusCode}');
    }
  }
}
