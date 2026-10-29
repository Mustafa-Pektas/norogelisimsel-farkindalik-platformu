import 'dart:io';

import 'package:neuro_awareness_app/models/d01_pilot_result.dart';
import 'package:neuro_awareness_app/services/d01_pilot_service.dart';

const pilotTestId = '228c9ed0-7e78-44af-90d6-550c4e478e07';
Map<String, dynamic> pilotStatusJson([
  String state = 'running',
  String? code,
]) => {
  'jobId': pilotTestId,
  'status': state,
  'code': code,
  'profileId': 'd01-second-reviewed',
  'interruptRequested': false,
};
Map<String, dynamic> pilotResultJson() => {
  'schemaVersion': 'd01-pilot-api-1.0',
  'jobId': pilotTestId,
  'profileId': 'd01-second-reviewed',
  'videoHash': d01PilotProfiles['d01-second-reviewed'],
  'counts': {'processed': 168, 'valid': 168, 'invalid': 0},
  'algorithmicTarget': 'not_determined',
  'manualCandidateStatus': 'unreviewed',
  'clockAlignmentVerified': false,
  'interpretation':
      'temporal_relations_only_not_response_or_target_classification',
  'manualTimes': {
    for (final k in [
      'call_start_s',
      'call_end_s',
      'response_start_s',
      'response_end_s',
    ])
      k: <String, dynamic>{'time_s': null, 'source': null},
  },
  'settling': <dynamic>[],
  'movements': {
    for (final method in ['raw', 'ema_050'])
      method: [
        <String, dynamic>{
          'candidate_id': 'candidate_001',
          'movement_start_s': 1.5,
          'movement_end_s': 2.5,
          'start_confirmation_time_s': 1.625,
          'end_confirmation_time_s': 2.7,
          'start_minus_manual_call_start_s': null,
          'start_minus_manual_call_end_s': null,
        },
      ],
  },
};

class ControlledPilotApi implements D01PilotApi {
  final List<ControlledPilotTask> tasks = [];
  final List<String> keys = [], addresses = [];
  final List<File> videos = [];
  ControlledPilotTask Function()? makeTask;
  @override
  D01PilotTask create({
    required File video,
    required String address,
    required String accessKey,
  }) {
    keys.add(accessKey);
    addresses.add(address);
    videos.add(video);
    final task = makeTask?.call() ?? ControlledPilotTask();
    tasks.add(task);
    return task;
  }
}

class ControlledPilotTask implements D01PilotTask {
  @override
  String? jobId;
  int submits = 0, polls = 0, cancels = 0, closes = 0, results = 0;
  Future<D01PilotStatus> Function()? readStatus;
  Future<void> Function()? onCancel;
  Future<D01PilotStatus> Function()? onSubmit;
  Future<D01PilotResult> Function()? readResult;
  @override
  Future<D01PilotStatus> submit() async {
    submits++;
    final s =
        await (onSubmit?.call() ??
            Future.value(D01PilotStatus.fromJson(pilotStatusJson())));
    jobId = s.jobId;
    return s;
  }

  @override
  Future<D01PilotStatus> status() async {
    polls++;
    final read = readStatus;
    if (read != null) {
      return read();
    }
    return D01PilotStatus.fromJson(pilotStatusJson());
  }

  @override
  Future<D01PilotResult> result() async {
    results++;
    final read = readResult;
    if (read != null) {
      return read();
    }
    return D01PilotResult.fromJson(
      pilotResultJson(),
      expectedJobId: pilotTestId,
    );
  }

  @override
  Future<void> cancel() async {
    cancels++;
    await onCancel?.call();
  }

  @override
  void close() {
    closes++;
  }
}
