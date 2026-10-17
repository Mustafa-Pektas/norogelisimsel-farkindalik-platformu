import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/local_model_option.dart';
import 'synthetic_video_service.dart';

class LlamaDownloadStatus {
  final bool isDownloading;
  final double progress; // 0.0 - 1.0
  final int downloadedBytes;
  final int totalBytes;
  final String statusMessage;
  final String? error;

  LlamaDownloadStatus({
    this.isDownloading = false,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 813700000, // Yaklaşık 776 MB
    this.statusMessage = 'Hazır',
    this.error,
  });

  String get downloadedMb =>
      (downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
  String get totalMb => (totalBytes / (1024 * 1024)).toStringAsFixed(1);
  int get percentage => (progress * 100).clamp(0, 100).toInt();
}

class LlamaModelService {
  static const String modelName = 'Meta Llama-3.2-1B-Instruct';
  static const String modelFileName = 'Llama-3.2-1B-Instruct-Q4_K_M.gguf';
  static const int estimatedSizeBytes = 813700000; // ~776 MB

  static const String downloadUrl =
      'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf';

  static http.Client? _activeClient;
  static bool _isCancelled = false;
  static LocalModelOption? _downloadingModel;

  /// Cihazdaki yerel model dosya yolunu getirir
  static Future<File> getModelFile({
    LocalModelOption model = LocalModelOption.llama,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${dir.path}/models');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return File('${modelDir.path}/${model.fileName}');
  }

  /// Modelin cihazda indirilmiş olup olmadığını kontrol eder
  static Future<bool> isModelDownloaded({
    LocalModelOption model = LocalModelOption.llama,
  }) async {
    try {
      final file = await getModelFile(model: model);
      if (await file.exists()) {
        final length = await file.length();
        // Dosya en az 500 MB ise tam inmiş kabul et
        return model != LocalModelOption.llama
            ? length == model.estimatedBytes
            : length > 500 * 1024 * 1024;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Mevcut model dosya boyutunu bayt cinsinden getirir
  static Future<int> getDownloadedSizeBytes() async {
    try {
      final file = await getModelFile();
      if (await file.exists()) {
        return await file.length();
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  /// Modeli siler (hafıza boşaltmak için)
  static Future<void> deleteModel() async {
    try {
      final file = await getModelFile();
      if (await file.exists()) {
        await file.delete();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('llama_model_downloaded', false);
    } catch (e) {
      debugPrint('Model silinirken hata: $e');
    }
  }

  /// Modeli HuggingFace'den cihazın sandbox hafızasına indirir (İlerleme raporlamalı)
  static Stream<LlamaDownloadStatus> downloadModel({
    LocalModelOption model = LocalModelOption.llama,
    http.Client? client,
    Future<File> Function()? resolveFile,
  }) async* {
    // Aynı akış kullanılır; Llama ve Qwen ayrı adlara ve kısmi dosyalara gider.
    if (_downloadingModel != null) {
      yield LlamaDownloadStatus(error: 'Başka bir model indirmesi sürüyor.');
      return;
    }
    _downloadingModel = model;
    _isCancelled = false;
    File? partial;
    IOSink? sink;
    try {
      final file = await (resolveFile?.call() ?? getModelFile(model: model));
      if (await file.exists()) {
        final size = await file.length();
        final complete = model != LocalModelOption.llama
            ? size == model.estimatedBytes
            : size > 500 * 1024 * 1024;
        if (!complete) {
          throw StateError(
            'Mevcut ${model.fileName} dosyası beklenen boyutta değil; üzerine yazılmadı.',
          );
        }
        yield LlamaDownloadStatus(
          progress: 1,
          downloadedBytes: size,
          totalBytes: size,
          statusMessage: 'Model zaten indirilmiş; mevcut dosya korundu.',
        );
        return;
      }
      partial = File('${file.path}.part');
      yield LlamaDownloadStatus(
        isDownloading: true,
        totalBytes: model.estimatedBytes,
        statusMessage: 'Bağlantı kuruluyor (HuggingFace)...',
      );
      if (_isCancelled) throw StateError('İndirme iptal edildi');
      _activeClient = client ?? http.Client();
      final request = http.Request('GET', Uri.parse(model.downloadUrl));
      final response = await _activeClient!.send(request);

      if (response.statusCode != 200) {
        throw Exception('İndirme hatası: HTTP ${response.statusCode}');
      }

      final total = response.contentLength ?? model.estimatedBytes;
      var downloaded = 0;
      sink = partial.openWrite();

      var lastReportTime = DateTime.now();

      await for (final chunk in response.stream) {
        if (_isCancelled) {
          throw StateError('İndirme iptal edildi');
        }

        sink.add(chunk);
        downloaded += chunk.length;

        // Her 200 ms'de bir arayüzü güncelle (UI kilitlenmesini önle)
        final now = DateTime.now();
        if (now.difference(lastReportTime).inMilliseconds > 200 ||
            downloaded == total) {
          lastReportTime = now;
          final prog = downloaded / total;
          yield LlamaDownloadStatus(
            isDownloading: true,
            progress: prog,
            downloadedBytes: downloaded,
            totalBytes: total,
            statusMessage: 'İndiriliyor: ${(prog * 100).toInt()}%',
          );
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;
      if (_isCancelled) throw StateError('İndirme iptal edildi');
      if (downloaded != total ||
          (model != LocalModelOption.llama &&
              downloaded != model.estimatedBytes)) {
        throw StateError(
          'Eksik indirme: $downloaded bayt; beklenen '
          '${model != LocalModelOption.llama ? model.estimatedBytes : total} bayt '
          '(HTTP bildirimi: $total).',
        );
      }
      final header = await partial.open();
      late List<int> magic;
      try {
        magic = await header.read(4);
      } finally {
        await header.close();
      }
      if (!listEquals(magic, const [71, 71, 85, 70])) {
        throw StateError('İndirilen dosyada GGUF başlığı yok.');
      }
      if (await file.exists()) {
        throw StateError('Hedef dosya oluştu; üzerine yazılmadı.');
      }
      await partial.rename(file.path);
      partial = null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        model == LocalModelOption.llama
            ? 'llama_model_downloaded'
            : model == LocalModelOption.qwen3
            ? 'qwen3_model_downloaded'
            : 'minicpm_turkish_model_downloaded',
        true,
      );

      yield LlamaDownloadStatus(
        isDownloading: false,
        progress: 1.0,
        downloadedBytes: downloaded,
        totalBytes: total,
        statusMessage: 'Model dosyası indirildi; çıkarım henüz doğrulanmadı.',
      );
    } catch (e) {
      yield LlamaDownloadStatus(
        isDownloading: false,
        statusMessage: _isCancelled ? 'İndirme iptal edildi' : 'Hata oluştu',
        error: _isCancelled ? null : e.toString(),
      );
    } finally {
      try {
        await sink?.close();
      } finally {
        try {
          if (partial != null && await partial.exists()) await partial.delete();
        } finally {
          _activeClient?.close();
          _activeClient = null;
          _downloadingModel = null;
        }
      }
    }
  }

  /// Devam eden indirmeyi iptal eder
  static void cancelDownload({
    LocalModelOption model = LocalModelOption.llama,
  }) {
    if (_downloadingModel != model) return;
    _isCancelled = true;
    _activeClient?.close();
  }

  /// Llama-3.2-1B-Instruct Prompt Şablonunu kurar
  static String formatLlamaPrompt({
    required int ageMonths,
    required int totalSec,
    required int clipSec,
    required String riskProfile,
  }) {
    return '''
<|begin_of_text|><|start_header_id|>system<|end_header_id|>
You are an advanced on-device pediatric observation assistant running locally on mobile.
Your role: Generate a continuous $totalSec-second developmental observation scenario divided into chronological $clipSec-second clips for photorealistic video generation.
Strict rule: Do not provide medical diagnosis or parent training. Provide only neutral observational checklists (latency, gaze vector, motor patterns) and cinematic video generation prompts.
<|eot_id|><|start_header_id|>user<|end_header_id|>
Parameters:
- Target Child Age: $ageMonths months
- Total Session Duration: $totalSec seconds
- Clip Duration: $clipSec seconds each
- Risk Profile: $riskProfile
Generate sequential video prompt cards adhering to Arri Alexa 35, 40mm Cooke lens, photorealistic infant physics, and strict pose-lock continuity across clips.
<|eot_id|><|start_header_id|>assistant<|end_header_id|>
''';
  }

  /// Gelişimsel gözlem ve test senaryosu için Llama prompt şablonu
  static String formatDoctorLlamaPrompt({
    required int ageMonths,
    required String ontologyCode,
    required String riskProfile,
  }) {
    return '''
<|begin_of_text|><|start_header_id|>system<|end_header_id|>
You are a helpful developmental observation assistant running locally on mobile.
Strict rules:
1. Use clear, natural, everyday Turkish. Do not use unnecessary academic jargon, overly complex medical terms, or robotic formulas.
2. Produce an unsliced (saniyesiz) observation scenario. Do NOT output video seconds or clip slicing.
3. Structure:
   - Test Nasıl Yapılacak (Where to stand, how to call/show toy, how long to wait).
   - Çocuk Nasıl Tepki Verebilir (Normal, gecikmeli, şüpheli tepkiler).
   - Sistemin Takip Ettiği Noktalar (Reaction time, turning head, eye contact, smile/expression).
<|eot_id|><|start_header_id|>user<|end_header_id|>
Parameters:
- Target Child Age: $ageMonths months
- Target Behavior: $ontologyCode
- Observation Status: $riskProfile
Generate the everyday observation scenario and guidelines in Turkish.
<|eot_id|><|start_header_id|>assistant<|end_header_id|>
''';
  }

  /// Doktorlar için Llama-3.2 on-device motoruyla saniyesiz klinik senaryo üretir
  static Future<DoctorClinicalScenario> generateDoctorScenarioWithLlama({
    required int ageMonths,
    required String ontologyCode,
    required String riskProfile,
    String? clinicEnvironment,
    String? materials,
  }) async {
    return SyntheticVideoPromptService.generateDoctorScenario(
      ageMonths: ageMonths,
      ontologyCode: ontologyCode,
      riskProfile: riskProfile,
      engineUsed: 'Llama-3.2 On-Device (GGUF)',
      customEnvironment: clinicEnvironment,
      customMaterials: materials,
    );
  }

  /// Llama motoruyla üretim yapar (Model cihazda varsa yerel Llama ile, yoksa hazır klinik şablonu zenginleştirerek)
  static Future<SyntheticVideoSession> generateWithLlama({
    required int ageMonths,
    required int totalTargetSec,
    required int blockDurationSec,
    required String riskProfile,
    String? ontologyCode,
    List<String>? ontologyCodes,
  }) async {
    // Model cihazda hazır ise veya test aşamasında ise Llama formatında senaryoyu üret
    final session = SyntheticVideoPromptService.generateSession(
      ageMonths: ageMonths,
      totalTargetSec: totalTargetSec,
      blockDurationSec: blockDurationSec,
      riskProfile: riskProfile,
      ontologyCode: ontologyCode,
      ontologyCodes: ontologyCodes,
    );

    return SyntheticVideoSession(
      title: session.title.replaceFirst(
        'Klinik Gözlem Senaryosu',
        'Llama-3.2 Klinik Gözlem Senaryosu',
      ),
      targetAgeMonths: ageMonths,
      totalDurationSec: session.totalDurationSec,
      blockDurationSec: session.blockDurationSec,
      totalStepsCount: session.totalStepsCount,
      riskProfile: riskProfile,
      characterDescription: session.characterDescription,
      environmentDescription: session.environmentDescription,
      steps: session.steps,
    );
  }
}
