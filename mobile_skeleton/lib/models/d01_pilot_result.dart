// Experimental head-motion API only. No response/target/clinical classification.
class D01PilotException implements Exception {
  const D01PilotException(this.code);
  final String code;
  String get message => switch (code) {
    'unauthorized' => 'Ekip erişim anahtarı eksik veya geçersiz.',
    'pilot_busy' =>
      'Sunucuda başka bir analiz devam ediyor. Yeni yükleme yapılmadı.',
    'unsupported_video' => 'Bu video desteklenmiyor. Yalnız iki denetlenmiş D01 videosu kabul edilir.',
    'video_too_large' ||
    'request_too_large' => 'Video 25 MiB yükleme sınırını aşıyor.',
    'analysis_timeout' =>
      'Sunucu analiz süre sınırına ulaştı; iş tamamlanmadı.',
    'http_timeout' =>
      'Bağlantı zaman aşımına uğradı. Sunucudaki iş devam ediyor olabilir.',
    'tracking_timeout' =>
      'İstemci takip süresi doldu. Sunucudaki iş devam ediyor olabilir.',
    'connection_error' =>
      'Sunucuya bağlanılamadı. Yeni analiz otomatik başlatılmadı.',
    'invalid_address' =>
      'Pilot sunucusu için geçerli bir HTTP/HTTPS adresi girin.',
    'job_not_found' => 'İş bulunamadı veya saklama süresi doldu.',
    'video_changed' =>
      'Video dosyası değişmiş; önceki sonuç bu videoya uygulanmadı.',
    'invalid_contract' => 'Pilot yanıtı beklenen sözleşmeyle uyuşmuyor.',
    'interrupted' || 'cancelled_locally' => 'Pilot işi sunucuda kesildi.',
    'cli_failed' ||
    'cli_start_failed' ||
    'invalid_cli_result' => 'Sunucu pilot analizi tamamlayamadı.',
    _ => 'Pilot isteği tamamlanamadı. İş kimliği varsa takibi yeniden deneyebilirsiniz.',
  };
  @override
  String toString() => message; // Never include headers, URLs or raw server errors.
}

Map<String, dynamic> pilotMap(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const D01PilotException('invalid_contract');
  }
  return value;
}

final _jobId = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
const d01PilotProfiles = {
  'd01-first-reviewed':
      '6f127ff5387de2e0399d548ce21a3799710b0ec75ad594ef1ac2e5fe91e4c451',
  'd01-second-reviewed':
      'b6e12246983f8852f2cef4397b328ec9c0412294564a17212a4021a653eaf605',
};

int? _count(Object? v) {
  if (v == null) {
    return null;
  }
  if (v is! int || v < 0) {
    throw const D01PilotException('invalid_contract');
  }
  return v;
}

double? _time(Object? v) {
  if (v == null) {
    return null;
  }
  if (v is! num || !v.isFinite) {
    throw const D01PilotException('invalid_contract');
  }
  return v.toDouble();
}

class D01PilotStatus {
  D01PilotStatus.fromJson(Map<String, dynamic> json)
    : jobId = json['jobId'] is String ? json['jobId'] as String : '',
      status = json['status'] is String ? json['status'] as String : '',
      code = json['code'] is String ? json['code'] as String : null,
      profileId = json['profileId'] is String
          ? json['profileId'] as String
          : null,
      interruptRequested = json['interruptRequested'] == true,
      processedFrames = _count(json['processedFrames']),
      totalFrames = _count(json['totalFrames']) {
    if ((json['code'] != null && json['code'] is! String) ||
        (json['profileId'] != null && json['profileId'] is! String) ||
        (json.containsKey('interruptRequested') &&
            json['interruptRequested'] is! bool) ||
        !_jobId.hasMatch(jobId) ||
        !const [
          'uploading',
          'running',
          'completed',
          'failed',
          'interrupted',
        ].contains(status) ||
        (profileId != null && !d01PilotProfiles.containsKey(profileId)) ||
        (processedFrames != null &&
            totalFrames != null &&
            processedFrames! > totalFrames!)) {
      throw const D01PilotException('invalid_contract');
    }
  }
  final String jobId, status;
  final String? code, profileId;
  final bool interruptRequested;
  final int? processedFrames, totalFrames;
  bool get terminal =>
      const ['completed', 'failed', 'interrupted'].contains(status);
}

class D01MotionCandidate {
  D01MotionCandidate.fromJson(Map<String, dynamic> json)
    : id = json['candidate_id'] is String ? json['candidate_id'] as String : '',
      start = _time(json['movement_start_s']),
      end = _time(json['movement_end_s']),
      startConfirmed = _time(json['start_confirmation_time_s']),
      endConfirmed = _time(json['end_confirmation_time_s']) {
    if (!RegExp(r'^candidate_\d+$').hasMatch(id) ||
        !json.containsKey('movement_start_s') ||
        !json.containsKey('movement_end_s') ||
        !json.containsKey('start_confirmation_time_s') ||
        !json.containsKey('end_confirmation_time_s') ||
        !json.containsKey('start_minus_manual_call_start_s') ||
        !json.containsKey('start_minus_manual_call_end_s') ||
        json['start_minus_manual_call_start_s'] != null ||
        json['start_minus_manual_call_end_s'] != null) {
      throw const D01PilotException('invalid_contract');
    }
  }
  final String id;
  final double? start, end, startConfirmed, endConfirmed;
  // Bad/missing bounds are visible, but never turned into an arbitrary seek.
  bool canSeek(Duration duration) =>
      start != null &&
      end != null &&
      start! >= 0 &&
      end! >= start! &&
      end! <= duration.inMicroseconds / 1e6 &&
      start! < duration.inMicroseconds / 1e6;
}

class D01PilotResult {
  D01PilotResult.fromJson(
    Map<String, dynamic> json, {
    required String expectedJobId,
  }) : jobId = json['jobId'] is String ? json['jobId'] as String : '',
       profileId = json['profileId'] is String
           ? json['profileId'] as String
           : '',
       videoHash = json['videoHash'] is String
           ? json['videoHash'] as String
           : '',
       raw = _candidates(pilotMap(json['movements'])['raw']),
       ema = _candidates(pilotMap(json['movements'])['ema_050']) {
    final counts = pilotMap(json['counts']);
    processed = _count(counts['processed']);
    valid = _count(counts['valid']);
    invalid = _count(counts['invalid']);
    if (json['schemaVersion'] != 'd01-pilot-api-1.0' ||
        jobId != expectedJobId ||
        !_jobId.hasMatch(jobId) ||
        d01PilotProfiles[profileId] != videoHash ||
        processed == null ||
        processed == 0 ||
        valid == null ||
        invalid == null ||
        valid! + invalid! != processed ||
        json['algorithmicTarget'] != 'not_determined' ||
        json['clockAlignmentVerified'] != false ||
        json['manualCandidateStatus'] != 'unreviewed' ||
        json['interpretation'] !=
            'temporal_relations_only_not_response_or_target_classification' ||
        json['settling'] is! List) {
      throw const D01PilotException('invalid_contract');
    }
    final manual = pilotMap(json['manualTimes']);
    for (final name in [
      'call_start_s',
      'call_end_s',
      'response_start_s',
      'response_end_s',
    ]) {
      final m = pilotMap(manual[name]);
      if (!m.containsKey('time_s') ||
          m['time_s'] != null ||
          m['source'] != null) {
        throw const D01PilotException('invalid_contract');
      }
    }
  }
  static List<D01MotionCandidate> _candidates(Object? value) {
    if (value is! List || value.length > 1000) {
      throw const D01PilotException('invalid_contract');
    }
    final candidates = value
        .map((v) => D01MotionCandidate.fromJson(pilotMap(v)))
        .toList(growable: false);
    if (candidates.map((v) => v.id).toSet().length != candidates.length) {
      throw const D01PilotException('invalid_contract');
    }
    return List.unmodifiable(candidates);
  }

  final String jobId, profileId, videoHash;
  final List<D01MotionCandidate> raw, ema;
  late final int? processed, valid, invalid;
}
