import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/d01_pilot_result.dart';

abstract interface class D01PilotApi {
  D01PilotTask create({
    required File video,
    required String address,
    required String accessKey,
  });
}

abstract interface class D01PilotTask {
  String? get jobId;
  Future<D01PilotStatus> submit();
  Future<D01PilotStatus> status();
  Future<D01PilotResult> result();
  Future<void>
  cancel(); // DELETE is explicit; 202 is not terminal confirmation.
  void close(); // Local tracking only; must never send DELETE.
}

class HttpD01PilotApi implements D01PilotApi {
  const HttpD01PilotApi({
    this.clientFactory,
    this.timeout = const Duration(seconds: 30),
  });
  static const defaultAddress = String.fromEnvironment('D01_PILOT_SERVER_URL');
  final http.Client Function()? clientFactory;
  final Duration timeout;
  @override
  D01PilotTask create({
    required File video,
    required String address,
    required String accessKey,
  }) {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path != '' && uri.path != '/')) {
      throw const D01PilotException('invalid_address');
    }
    final key = accessKey.trim();
    if (!RegExp(r'^[\x21-\x7e]+$').hasMatch(key)) {
      throw const D01PilotException('unauthorized');
    }
    return _HttpPilotTask(
      video,
      uri,
      key,
      clientFactory ?? http.Client.new,
      timeout,
    );
  }
}

class _HttpPilotTask implements D01PilotTask {
  _HttpPilotTask(
    this.video,
    this.address,
    this.accessKey,
    this.clientFactory,
    this.timeout,
  );
  final File video;
  final Uri address;
  final String accessKey;
  final http.Client Function() clientFactory;
  final Set<http.Client> clients = {};
  final Duration timeout;
  bool closed = false, submitted = false;
  List<int>? sourceBytes;
  String? _jobId;
  String? _profileId;
  @override
  String? get jobId => _jobId;

  Future<Map<String, dynamic>> _send(
    http.BaseRequest request,
    int expected,
  ) async {
    if (closed) {
      throw const D01PilotException('connection_error');
    }
    final client = clientFactory();
    clients.add(client);
    request.headers['Authorization'] = 'Bearer $accessKey';
    request.followRedirects =
        false; // Do not forward a team credential to another origin.
    try {
      return await (() async {
        final response = await client.send(request);
        var size = 0;
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          size += chunk.length;
          if (size > 256 * 1024) {
            throw const D01PilotException('invalid_contract');
          }
          bytes.addAll(chunk);
        }
        if (closed) {
          throw const D01PilotException('connection_error');
        }
        if (response.statusCode != expected) {
          if (response.statusCode == 401) {
            throw const D01PilotException('unauthorized');
          }
          String? code;
          try {
            code = pilotMap(jsonDecode(utf8.decode(bytes)))['code'] as String?;
          } catch (_) {
            /* Sanitized below. */
          }
          throw D01PilotException(
            code ??
                (response.statusCode == 413
                    ? 'video_too_large'
                    : 'request_failed'),
          );
        }
        return pilotMap(jsonDecode(utf8.decode(bytes)));
      })().timeout(timeout);
    } on TimeoutException {
      throw const D01PilotException('http_timeout');
    } on D01PilotException {
      rethrow;
    } on FormatException {
      throw const D01PilotException('invalid_contract');
    } catch (_) {
      throw const D01PilotException('connection_error');
    } finally {
      if (clients.remove(client)) {
        client.close();
      }
    }
  }

  Uri _uri([String suffix = '']) =>
      address.replace(path: '/api/pilot-d01/jobs$suffix');
  String _id() => _jobId ?? (throw const D01PilotException('invalid_contract'));

  @override
  Future<D01PilotStatus> submit() async {
    if (submitted) {
      throw const D01PilotException('request_failed');
    }
    submitted = true;
    try {
      if (await video.length() > 25 * 1024 * 1024) {
        throw const D01PilotException('video_too_large');
      }
      final bytes = await video.readAsBytes();
      if (bytes.isEmpty || bytes.length > 25 * 1024 * 1024) {
        throw const D01PilotException('video_too_large');
      }
      sourceBytes = bytes;
      final upload = http.MultipartRequest('POST', _uri())
        ..files.add(
          http.MultipartFile.fromBytes('video', bytes, filename: 'pilot.mp4'),
        );
      // No call times, paths, ROI, recorded matrices or model commands are sent.
      final accepted = D01PilotStatus.fromJson(await _send(upload, 202));
      _jobId = accepted.jobId;
      return accepted;
    } on D01PilotException {
      rethrow;
    } catch (_) {
      throw const D01PilotException('connection_error');
    }
  }

  @override
  Future<D01PilotStatus> status() async {
    final s = D01PilotStatus.fromJson(
      await _send(http.Request('GET', _uri('/${_id()}')), 200),
    );
    if (s.jobId != _jobId ||
        (_profileId != null && s.profileId != _profileId)) {
      throw const D01PilotException('invalid_contract');
    }
    _profileId = s.profileId;
    return s;
  }

  @override
  Future<D01PilotResult> result() async {
    final r = D01PilotResult.fromJson(
      await _send(http.Request('GET', _uri('/${_id()}/result')), 200),
      expectedJobId: _id(),
    );
    var matchingBytes = false;
    try {
      final source = sourceBytes;
      matchingBytes =
          source != null &&
          await video.length() == source.length &&
          listEquals(await video.readAsBytes(), source);
    } on FileSystemException {
      matchingBytes = false;
    }
    if ((_profileId != null && r.profileId != _profileId) || !matchingBytes) {
      throw const D01PilotException('video_changed');
    }
    // Server verifies SHA256/profile. Bind that result to the job AND exact uploaded
    // bytes; a local path alone is never used as proof of matching video content.
    return r;
  }

  @override
  Future<void> cancel() async {
    final r = await _send(http.Request('DELETE', _uri('/${_id()}')), 202);
    if (r['code'] != 'local_interrupt_requested') {
      throw const D01PilotException('invalid_contract');
    }
  }

  @override
  void close() {
    if (closed) {
      return;
    }
    closed = true;
    for (final client in clients.toList()) {
      client.close();
    }
    clients.clear();
  }
}
