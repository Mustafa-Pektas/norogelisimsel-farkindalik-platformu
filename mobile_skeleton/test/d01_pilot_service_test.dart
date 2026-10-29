import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_awareness_app/models/d01_pilot_result.dart';
import 'package:neuro_awareness_app/services/d01_pilot_service.dart';
import 'package:neuro_awareness_app/services/server_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/d01_pilot_fixtures.dart';

class _ClosingClient extends MockClient {
  _ClosingClient(super.fn);
  int closes = 0;
  @override
  void close() {
    closes++;
    super.close();
  }
}

void main() {
  late Directory temp;
  late File video;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pilot-http-test-');
    video = await File('${temp.path}/fixture.mp4')
        .writeAsBytes([10, 20, 30, 40]);
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  http.Response json(Object data, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(data)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  Matcher error(String code) =>
      isA<D01PilotException>().having((e) => e.code, 'code', code);

  test('Multipart -> job -> result: same Bearer, no manual fields; independent address and no stored key', () async {
    SharedPreferences.setMockInitialValues({
      'custom_server_base_url': 'https://scenario.example',
    });
    final seen = <http.Request>[];
    final service = HttpD01PilotApi(
      clientFactory: () => MockClient((r) async {
        seen.add(r);
        expect(r.headers['Authorization'], 'Bearer test-session-only');
        expect(r.url.origin, 'http://127.0.0.1:9999');
        expect(r.followRedirects, isFalse);
        if (r.method == 'POST') {
          expect(r.headers['content-type'], startsWith('multipart/form-data'));
          expect(r.body, contains('name="video"'));
          expect(r.body, isNot(contains('callStartS')));
          expect(r.body, isNot(contains('callEndS')));
          expect(r.body, isNot(contains(video.path)));
          return json({'jobId': pilotTestId, 'status': 'running'}, 202);
        }
        if (r.url.path.endsWith('/result')) return json(pilotResultJson());
        if (r.method == 'DELETE') {
          return json({'code': 'local_interrupt_requested'}, 202);
        }
        return json(pilotStatusJson('completed'));
      }),
    );
    final task = service.create(
      video: video,
      address: 'http://127.0.0.1:9999',
      accessKey: 'test-session-only',
    );
    expect((await task.submit()).jobId, pilotTestId);
    expect((await task.status()).status, 'completed');
    final result = await task.result();
    expect(result.raw.single.start, 1.5);
    expect(result.ema.single.endConfirmed, 2.7);
    await task.cancel();
    task.close();
    task.close();
    expect(seen.map((r) => r.method), ['POST', 'GET', 'GET', 'DELETE']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'custom_server_base_url'});
    expect(await ServerApiService.getBaseUrl(), 'https://scenario.example');
  });

  for (final entry in {
    401: 'unauthorized',
    429: 'pilot_busy',
    422: 'unsupported_video',
    413: 'video_too_large',
    404: 'job_not_found',
  }.entries) {
    test(
      'HTTP ${entry.key} becomes safe ${entry.value}; no legacy fallback',
      () async {
        var calls = 0;
        final api = HttpD01PilotApi(
          clientFactory: () => MockClient((r) async {
            calls++;
            expect(r.url.path, '/api/pilot-d01/jobs');
            return json({
              'code': entry.value,
              'error': 'private server traceback',
            }, entry.key);
          }),
        );
        final task = api.create(
          video: video,
          address: 'http://localhost:8000',
          accessKey: 'test',
        );
        await expectLater(task.submit(), throwsA(error(entry.value)));
        task.close();
        expect(calls, 1);
        expect(
          D01PilotException(entry.value).toString(),
          isNot(contains('private')),
        );
      },
    );
  }

  test('Timeout closes request; explicit status retry uses same job and never resubmits', () async {
    var statuses = 0, uploads = 0;
    final gate = Completer<http.Response>();
    final api = HttpD01PilotApi(
      timeout: const Duration(milliseconds: 30),
      clientFactory: () => MockClient((r) async {
        if (r.method == 'POST') {
          uploads++;
          return json(pilotStatusJson(), 202);
        }
        statuses++;
        if (statuses == 1) return gate.future;
        return json(pilotStatusJson('interrupted', 'analysis_timeout'));
      }),
    );
    final task = api.create(
      video: video,
      address: 'http://localhost',
      accessKey: 'test',
    );
    await task.submit();
    await expectLater(task.status(), throwsA(error('http_timeout')));
    gate.complete(json(pilotStatusJson('completed')));
    expect((await task.status()).code, 'analysis_timeout');
    expect(uploads, 1);
    task.close();
  });

  for (final corruption in [
    'schema',
    'job',
    'profile',
    'manual',
    'counts',
    'malformed',
  ]) {
    test(
      'Reject $corruption response; never silently fill contract fields',
      () async {
        final data = pilotResultJson();
        switch (corruption) {
          case 'schema':
            data['schemaVersion'] = 'old';
          case 'job':
            data['jobId'] = 'another-job';
          case 'profile':
            data['videoHash'] = '0' * 64;
          case 'manual':
            (data['manualTimes'] as Map)['call_start_s']['time_s'] = 0;
          case 'counts':
            data['counts']['valid'] = 167;
        }
        final api = HttpD01PilotApi(
          clientFactory: () => MockClient(
            (r) async => r.method == 'POST'
                ? json(pilotStatusJson(), 202)
                : corruption == 'malformed'
                ? http.Response('not json', 200)
                : json(data),
          ),
        );
        final task = api.create(
          video: video,
          address: 'http://localhost',
          accessKey: 'test',
        );
        await task.submit();
        await expectLater(task.result(), throwsA(error('invalid_contract')));
        task.close();
      },
    );
  }

  test('Same path with modified bytes cannot receive old result', () async {
    final api = HttpD01PilotApi(
      clientFactory: () => MockClient(
        (r) async => json(
          r.method == 'POST' ? pilotStatusJson() : pilotResultJson(),
          r.method == 'POST' ? 202 : 200,
        ),
      ),
    );
    final task = api.create(
      video: video,
      address: 'http://localhost',
      accessKey: 'test',
    );
    await task.submit();
    await video.writeAsBytes([10, 20, 30, 41]);
    await expectLater(task.result(), throwsA(error('video_changed')));
    task.close();
  });

  test('Double upload is rejected; local close sends no DELETE', () async {
    final seen = <String>[];
    final api = HttpD01PilotApi(
      clientFactory: () => MockClient((r) async {
        seen.add(r.method);
        return json(pilotStatusJson(), 202);
      }),
    );
    final task = api.create(
      video: video,
      address: 'http://localhost',
      accessKey: 'test',
    );
    await task.submit();
    await expectLater(task.submit(), throwsA(error('request_failed')));
    task.close();
    task.close();
    expect(seen, ['POST']);
  });

  test('Closing an in-flight request closes each owned client exactly once; late response is rejected', () async {
    final clients = <_ClosingClient>[];
    final started = Completer<void>();
    final reply = Completer<http.Response>();
    final api = HttpD01PilotApi(
      clientFactory: () {
        final client = _ClosingClient((r) async {
          if (r.method == 'POST') return json(pilotStatusJson(), 202);
          expect(r.method, 'GET');
          started.complete();
          return reply.future;
        });
        clients.add(client);
        return client;
      },
    );
    final task = api.create(
      video: video,
      address: 'http://localhost',
      accessKey: 'test',
    );
    await task.submit();
    final pending = task.status();
    await started.future;
    task.close();
    task.close();
    reply.complete(json(pilotStatusJson('completed')));
    await expectLater(pending, throwsA(error('connection_error')));
    expect(clients, hasLength(2));
    expect(clients.map((c) => c.closes), [1, 1]);
  });

  test('Bad address/empty key and oversize upload are rejected without an HTTP call', () async {
    var calls = 0;
    final api = HttpD01PilotApi(
      clientFactory: () => MockClient((r) async {
        calls++;
        return json(pilotStatusJson(), 202);
      }),
    );
    for (final address in [
      '',
      'file:///video',
      'http://user:password@host',
      'http://host?key=no',
    ]) {
      expect(
        () => api.create(video: video, address: address, accessKey: 'test'),
        throwsA(error('invalid_address')),
      );
    }
    expect(
      () =>
          api.create(video: video, address: 'http://localhost', accessKey: ''),
      throwsA(error('unauthorized')),
    );
    final file = await video.open(mode: FileMode.write);
    await file.truncate(25 * 1024 * 1024 + 1);
    await file.close();
    final task = api.create(
      video: video,
      address: 'http://localhost',
      accessKey: 'test',
    );
    await expectLater(task.submit(), throwsA(error('video_too_large')));
    task.close();
    expect(calls, 0);
  });

  test('Unknown bounds stay unknown; impossible intervals cannot seek; no percent inferred', () {
    final data = pilotResultJson();
    final c = data['movements']['raw'][0] as Map;
    c['movement_start_s'] = null;
    final unknown = D01PilotResult.fromJson(
      data,
      expectedJobId: pilotTestId,
    ).raw.single;
    expect(unknown.start, isNull);
    expect(unknown.canSeek(const Duration(seconds: 7)), isFalse);
    for (final bounds in [
      [-1, 2],
      [3, 2],
      [1, 8],
    ]) {
      c['movement_start_s'] = bounds[0];
      c['movement_end_s'] = bounds[1];
      expect(
        D01PilotResult.fromJson(
          data,
          expectedJobId: pilotTestId,
        ).raw.single.canSeek(const Duration(seconds: 7)),
        isFalse,
      );
    }
    expect(D01PilotStatus.fromJson(pilotStatusJson()).processedFrames, isNull);
  });
}
