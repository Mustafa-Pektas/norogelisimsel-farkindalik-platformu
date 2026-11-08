import 'd01_marked_input.dart';

// Experimental head-motion API only. No response/target/clinical classification.
class D01PilotException implements Exception {
  const D01PilotException(this.code);
  final String code;
  String get message => switch (code) {
    'fast_runtime_not_configured' => 'Sunucuda hızlı analiz ortamı veya yüz modeli yapılandırılmamış.',
    'invalid_target' => 'Hedef yüz noktası geçersiz. Videonun ilk karesinde çocuğun yüzünü yeniden belirtin.',
    'fast_cli_failed' => 'Hızlı analiz tamamlanamadı; yeni analiz otomatik başlatılmadı.',
    'unauthorized' => 'Ekip erişim anahtarı eksik veya geçersiz.',
    'pilot_busy' =>
      'Sunucuda başka bir analiz devam ediyor. Yeni yükleme yapılmadı.',
    'unsupported_video' => 'Bu video desteklenmiyor. Yalnız iki denetlenmiş D01 videosu kabul edilir.',
    'roi_required' => 'Bu video için yeni video işaretlemesini açıp baş bölgesini ve çağrı zamanlarını seçin.',
    'invalid_roi' =>
      'Baş bölgesi görüntü sınırları içinde olmalı. Bölgeyi yeniden seçin.',
    'profile_roi_fixed' => 'Bu hazır video otomatik baş bölgesi kullanır; yeni video işaretlemesini kapatın.',
    'invalid_manual_times' =>
      'Çağrı başlangıcı ve bitişi video içinde ve sıralı olmalı.',
    'unsupported_fps' => 'Bu pilot yalnız 24 FPS videoları destekliyor.',
    'unsupported_timeline' =>
      'Video zaman çizgisi sabit 24 FPS koşuluyla uyuşmuyor.',
    'video_too_long' => 'Yeni video en fazla 30 saniye olabilir.',
    'invalid_video' =>
      'Video çözümlenemedi veya görüntü boyutları desteklenmiyor.',
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
      endConfirmed = _time(json['end_confirmation_time_s']),
      callStartDifference = _time(json['start_minus_manual_call_start_s']),
      callEndDifference = _time(json['start_minus_manual_call_end_s']),
      callPhase = json['callPhase'] is String
          ? json['callPhase'] as String
          : null {
    if (!RegExp(r'^candidate_\d+$').hasMatch(id) ||
        !json.containsKey('movement_start_s') ||
        !json.containsKey('movement_end_s') ||
        !json.containsKey('start_confirmation_time_s') ||
        !json.containsKey('end_confirmation_time_s') ||
        !json.containsKey('start_minus_manual_call_start_s') ||
        !json.containsKey('start_minus_manual_call_end_s')) {
      throw const D01PilotException('invalid_contract');
    }
  }
  final String id;
  final String? callPhase;
  final double? start,
      end,
      startConfirmed,
      endConfirmed,
      callStartDifference,
      callEndDifference;
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
    String? expectedVideoHash,
    D01MarkedInput? expectedMarkedInput,
    D01FastInput? expectedFastInput,
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
    if (json['schemaVersion'] == 'd01-pilot-api-1.2') {
      userMarked = false;
      sourceRoi = null;
      fast = true;
      _readFast(json, expectedJobId, expectedVideoHash, expectedFastInput);
      return;
    }
    if (expectedFastInput != null) {
      throw const D01PilotException('invalid_contract');
    }
    final marked = json['schemaVersion'] == 'd01-pilot-api-1.1';
    userMarked = marked;
    sourceRoi = marked ? expectedMarkedInput?.roi : null;
    if ((!marked && json['schemaVersion'] != 'd01-pilot-api-1.0') ||
        jobId != expectedJobId ||
        !_jobId.hasMatch(jobId) ||
        (!marked && d01PilotProfiles[profileId] != videoHash) ||
        (marked &&
            (json['profileId'] != null ||
                expectedVideoHash == null ||
                videoHash != expectedVideoHash ||
                expectedMarkedInput == null)) ||
        (!marked && expectedMarkedInput != null) ||
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
    double? durationS;
    if (marked) {
      final source = pilotMap(json['source']);
      final roi = pilotMap(source['roi']);
      final video = pilotMap(source['video']);
      final expected = expectedMarkedInput!;
      durationS = _time(video['durationS']);
      if (source['schemaVersion'] != 'd01-input-source-1.0' ||
          source['type'] != 'user_marked' ||
          source['validation'] !=
              'media_bounds_only_not_content_or_ROI_quality_approval' ||
          video['fps'] != 24 ||
          durationS == null ||
          durationS <= 0 ||
          durationS > 30 ||
          video['durationSource'] != 'decoded_CFR_video_frame_extent' ||
          _count(video['decodedFrames']) != processed ||
          (durationS - processed! / 24).abs() > .001 ||
          _count(video['width']) == null ||
          _count(video['height']) == null ||
          video['width'] <= 0 ||
          video['height'] <= 0 ||
          expected.roi.x + expected.roi.width > video['width'] ||
          expected.roi.y + expected.roi.height > video['height'] ||
          expected.callEnd.inMilliseconds / 1000 > durationS ||
          expected.roi.toJson().entries.any(
            (e) => roi[e.key] is! int || roi[e.key] != e.value,
          ) ||
          roi['human_supplied'] != true ||
          roi['padding_ltrb_source_px'] is! List ||
          (roi['padding_ltrb_source_px'] as List).length != 4 ||
          (roi['padding_ltrb_source_px'] as List).any((v) => v != 0)) {
        throw const D01PilotException('invalid_contract');
      }
    }
    final manual = pilotMap(json['manualTimes']);
    for (final name in [
      'call_start_s',
      'call_end_s',
      'response_start_s',
      'response_end_s',
    ]) {
      final m = pilotMap(manual[name]);
      final expected = marked && name == 'call_start_s'
          ? expectedMarkedInput!.callStart.inMilliseconds / 1000
          : marked && name == 'call_end_s'
          ? expectedMarkedInput!.callEnd.inMilliseconds / 1000
          : null;
      if (!m.containsKey('time_s') ||
          m['time_s'] != expected ||
          m['source'] != (expected == null ? null : 'manual_user_input')) {
        throw const D01PilotException('invalid_contract');
      }
    }
    for (final c in [...raw, ...ema]) {
      final expectedStart = marked && c.start != null
          ? c.start! - expectedMarkedInput!.callStart.inMilliseconds / 1000
          : null;
      final expectedEnd = marked && c.start != null
          ? c.start! - expectedMarkedInput!.callEnd.inMilliseconds / 1000
          : null;
      if ((expectedStart == null
              ? c.callStartDifference != null
              : c.callStartDifference == null ||
                    (c.callStartDifference! - expectedStart).abs() > 1e-6) ||
          (expectedEnd == null
              ? c.callEndDifference != null
              : c.callEndDifference == null ||
                    (c.callEndDifference! - expectedEnd).abs() > 1e-6)) {
        throw const D01PilotException('invalid_contract');
      }
    }
    callStart = _time(pilotMap(manual['call_start_s'])['time_s']);
    callEnd = _time(pilotMap(manual['call_end_s'])['time_s']);
  }
  bool fast = false;
  Map<String, int> coverage = const {};
  String? targetSelection, identityStatus;
  List<Map<String, dynamic>> missingPoseIntervals = const [];
  Map<String, double?> timings = const {};
  void _readFast(
    Map<String, dynamic> json,
    String expectedId,
    String? expectedHash,
    D01FastInput? input,
  ) {
    Never bad() => throw const D01PilotException('invalid_contract');
    if (input == null ||
        expectedHash == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(videoHash) ||
        videoHash != expectedHash ||
        !_jobId.hasMatch(jobId) ||
        jobId != expectedId ||
        json['profileId'] != null ||
        processed == null ||
        processed! <= 0 ||
        valid == null ||
        invalid == null ||
        valid! + invalid! != processed ||
        json['algorithmicTarget'] != 'not_determined' ||
        json['clockAlignmentVerified'] != false ||
        json['manualCandidateStatus'] != 'unreviewed' ||
        json['interpretation'] !=
            'temporal_relations_only_not_response_or_target_classification' ||
        json['settling'] is! List) {
      bad();
    }
    final source = pilotMap(json['source']),
        video = pilotMap(pilotMap(json['source'])['video']);
    final duration = _time(video['durationS']);
    targetSelection = source['targetSelection'] as String?;
    identityStatus = source['identityStatus'] as String?;
    if (source['schemaVersion'] != 'd01-input-source-1.2' ||
        source['type'] != 'automatic_face_tracking' ||
        source['method'] != 'mediapipe_pnp_flow' ||
        video['fps'] != 24 ||
        _count(video['width']) == null ||
        video['width'] <= 0 ||
        _count(video['height']) == null ||
        video['height'] <= 0 ||
        video['decodedFrames'] != processed ||
        duration == null ||
        duration <= 0 ||
        duration > 30 ||
        (duration - processed! / 24).abs() > .001 ||
        !const [
          'manual_initial_point',
          'single_face_candidate_role_unverified',
          'not_determined',
        ].contains(targetSelection) ||
        !const [
          'ambiguous_or_unselected',
          'continuity_candidate_not_biometric_identity',
        ].contains(identityStatus) ||
        (targetSelection == 'manual_initial_point' &&
            input.targetPoint == null)) {
      bad();
    }
    final expectedStart = input.callStart == null
        ? null
        : input.callStart!.inMilliseconds / 1000;
    final expectedEnd = input.callEnd == null
        ? null
        : input.callEnd!.inMilliseconds / 1000;
    final manual = pilotMap(json['manualTimes']);
    for (final key in [
      'call_start_s',
      'call_end_s',
      'response_start_s',
      'response_end_s',
    ]) {
      final expected = key == 'call_start_s'
          ? expectedStart
          : key == 'call_end_s'
          ? expectedEnd
          : null;
      final item = pilotMap(manual[key]);
      if (item['time_s'] != expected ||
          item['source'] != (expected == null ? null : 'manual_user_input') ||
          expected != null && (expected < 0 || expected > duration)) {
        bad();
      }
    }
    callStart = expectedStart;
    callEnd = expectedEnd;
    final rawCoverage = pilotMap(json['coverage']);
    coverage = {
      for (final key in [
        'poseFrames',
        'flowOnlyFrames',
        'lostFrames',
        'ambiguousFrames',
        'totalFrames',
      ])
        key: _count(rawCoverage[key]) ?? -1,
    };
    if (coverage.values.any((v) => v < 0 || v > processed!) ||
        coverage['totalFrames'] != processed ||
        coverage['poseFrames'] != valid) {
      bad();
    }
    if (json['missingPoseIntervals'] is! List) {
      bad();
    }
    missingPoseIntervals = (json['missingPoseIntervals'] as List).map((v) {
      final row = pilotMap(v),
          a = _time(pilotMap(v)['startS']),
          b = _time(pilotMap(v)['endS']);
      if (a == null ||
          b == null ||
          a < 0 ||
          b < a ||
          b > duration ||
          (_count(row['frames']) ?? 0) <= 0) {
        bad();
      }
      return row;
    }).toList();
    final times = pilotMap(json['timings']);
    timings = {for (final e in times.entries) e.key: _time(e.value)};
    if (timings.values.any((v) => v != null && v < 0)) {
      bad();
    }
    for (final c in [...raw, ...ema]) {
      for (final t in [c.start,c.end,c.startConfirmed,c.endConfirmed]) {
        if (t != null && (t < 0 || t > duration)) { bad(); }
      }
      if (c.start != null && c.end != null && c.end! < c.start!) { bad(); }
      final phase = callStart == null
          ? 'call_unknown'
          : c.start == null
          ? 'unknown_movement_start'
          : c.start! < callStart!
          ? 'before_call'
          : c.start! <= callEnd!
          ? 'during_call'
          : 'after_call';
      if (c.callPhase != phase) {
        bad();
      }
      for (final pair in [
        (c.callStartDifference, callStart),
        (c.callEndDifference, callEnd),
      ]) {
        final expected = c.start == null || pair.$2 == null
            ? null
            : c.start! - pair.$2!;
        if (expected == null
            ? pair.$1 != null
            : pair.$1 == null || (pair.$1! - expected).abs() > 1e-6) {
          bad();
        }
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
  late final bool userMarked;
  late final D01Roi? sourceRoi;
  late final double? callStart, callEnd;
  final List<D01MotionCandidate> raw, ema;
  late final int? processed, valid, invalid;
}
