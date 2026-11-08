import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_awareness_app/models/d01_marked_input.dart';
import 'package:neuro_awareness_app/models/d01_pilot_result.dart';
import 'package:neuro_awareness_app/services/d01_pilot_service.dart';
import 'package:neuro_awareness_app/widgets/d01_pilot_panel.dart';
import 'support/d01_pilot_fixtures.dart';

const marked = D01MarkedInput(D01Roi(10, 20, 100, 100), Duration(milliseconds: 400), Duration(milliseconds: 1150));
final hash = List.filled(64, 'd').join();
Map<String, dynamic> customResult({bool empty = false}) {
  final r = pilotResultJson();
  r['schemaVersion'] = 'd01-pilot-api-1.1'; r['profileId'] = null; r['videoHash'] = hash;
  r['source'] = {
    'schemaVersion': 'd01-input-source-1.0', 'type': 'user_marked',
    'validation': 'media_bounds_only_not_content_or_ROI_quality_approval',
    'roi': {...marked.roi.toJson(), 'human_supplied': true, 'padding_ltrb_source_px': [0,0,0,0]},
    'video': {'width': 640, 'height': 480, 'fps': 24, 'durationS': 7, 'decodedFrames': 168, 'durationSource': 'decoded_CFR_video_frame_extent'},
  };
  final times = r['manualTimes'] as Map;
  times['call_start_s'] = {'time_s': .4, 'source': 'manual_user_input'};
  times['call_end_s'] = {'time_s': 1.15, 'source': 'manual_user_input'};
  for (final mode in ['raw', 'ema_050']) {
    final movements = r['movements'] as Map;
    if (empty) { movements[mode] = <Map<String, dynamic>>[]; continue; }
    final candidate = (movements[mode] as List).single as Map;
    candidate['start_minus_manual_call_start_s'] = 1.1;
    candidate['start_minus_manual_call_end_s'] = .35;
  }
  return r;
}

void main() {
  test('ROI conversion removes horizontal/vertical letterbox and rejects blank-only selection', () {
    expect(D01Roi.fromPreview(const Rect.fromLTWH(50, 25, 100, 50), const Size(200,100), const Size(1280,720))!.toJson(),
      {'x':280,'y':180,'width':720,'height':360});
    expect(D01Roi.fromPreview(const Rect.fromLTWH(0, 0, 20, 20), const Size(200,200), const Size(100,200)), isNull);
    expect(D01Roi.fromPreview(const Rect.fromLTWH(50, 0, 100, 200), const Size(200,200), const Size(100,200))!.toJson(),
      {'x':0,'y':0,'width':100,'height':200});
    expect(D01Roi.fromPreview(const Rect.fromLTWH(0,50,200,100), const Size(200,200), const Size(200,100))!.toJson(),
      {'x':0,'y':0,'width':200,'height':100});
  });
  test('1.0 preserved; 1.1 binds accepted hash, marked ROI, call interval and finite differences', () {
    expect(D01PilotResult.fromJson(pilotResultJson(), expectedJobId: pilotTestId).raw.single.callEndDifference, isNull);
    final result = D01PilotResult.fromJson(customResult(), expectedJobId: pilotTestId, expectedVideoHash: hash, expectedMarkedInput: marked);
    expect(result.raw.single.callStartDifference, 1.1);
    expect(result.raw.single.callEndDifference, .35);
    expect(D01PilotResult.fromJson(customResult(empty: true), expectedJobId: pilotTestId, expectedVideoHash: hash, expectedMarkedInput: marked).raw, isEmpty);
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (r) => r['jobId'] = 'bad', (r) => r['videoHash'] = '0' * 64,
      (r) => (r['source'] as Map)['type'] = 'unknown',
      (r) => ((r['source'] as Map)['video'] as Map)['fps'] = 30,
      (r) => ((r['source'] as Map)['roi'] as Map)['x'] = 11,
      (r) => ((r['manualTimes'] as Map)['call_end_s'] as Map)['time_s'] = 1.2,
    ]) {
      final r = customResult(); mutate(r);
      expect(() => D01PilotResult.fromJson(r, expectedJobId: pilotTestId, expectedVideoHash: hash, expectedMarkedInput: marked), throwsA(isA<D01PilotException>()));
    }
  });
  test('HTTP marked upload -> accepted job/hash -> status -> 1.1 result, no automatic extra POST', () async {
    final temp = await Directory.systemTemp.createTemp('marked-http-');
    final video = await File('${temp.path}/fixture.mp4').writeAsBytes([1,2,3]);
    var posts = 0;
    final api = HttpD01PilotApi(clientFactory: () => MockClient((request) async {
      Map<String,dynamic> body;
      if (request.method == 'POST') {
        posts++;
        expect(request.body, contains('name="roi"'));
        expect(request.body, contains('name="callStartS"'));
        expect(request.body, contains('0.400'));
        expect(request.body, isNot(contains('responseStartS')));
        body = {...pilotStatusJson(), 'profileId': null, 'videoHash': hash, 'sourceType': 'user_marked'};
      } else if (request.url.path.endsWith('/result')) { body = customResult(); }
      else { body = {...pilotStatusJson('completed'), 'profileId': null}; }
      return http.Response.bytes(utf8.encode(jsonEncode(body)), request.method == 'POST' ? 202 : 200);
    }));
    final task = api.create(video: video,address:'http://localhost',accessKey:'session',markedInput:marked);
    try {
      await task.submit(); await task.status();
      expect((await task.result()).raw.single.start,1.5);expect(posts,1);
      await video.writeAsBytes([3,2,1]);
      await expectLater(task.result(),throwsA(isA<D01PilotException>()));
    } finally { task.close(); await temp.delete(recursive:true); }
  });
  testWidgets('Video identity change clears call marks; missing marks prevent new submission', (tester) async {
    // The controlled API never reads this file. Real filesystem Futures inside
    // testWidgets' FakeAsync would require runAsync and add no coverage here.
    final file = File('marked-panel-fixture.mp4');
    final api = ControlledPilotApi(); Duration position = const Duration(milliseconds:400);
    Future<void> show(Object identity) => tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: D01PilotPanel(
      video:file, videoIdentity:identity,duration:const Duration(seconds:7),openingVideo:false,onSeek:(_) async {},api:api,
      userMarked:true,roi:marked.roi,currentPosition:()=>position,
    )))));
    final first = Object();await show(first);
    for (final key in ['pilot-mark-call-start','pilot-mark-call-end']) {
      if(key.endsWith('end')) { position = const Duration(milliseconds:1150); }
      final finder=find.byKey(ValueKey(key));await tester.ensureVisible(finder);await tester.pumpAndSettle();await tester.tap(finder);await tester.pump();
    }
    expect(find.textContaining('0.400'),findsOneWidget);
    await show(Object());await tester.pump();
    expect(find.textContaining('0.400'),findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('pilot-start'))).onPressed,isNull);
    expect(api.tasks,isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Marked input reaches task; empty successful result stays completed', (tester) async {
    final api = ControlledPilotApi();
    api.makeTask = () {
      final task = ControlledPilotTask();
      task.readStatus = () async => D01PilotStatus.fromJson({...pilotStatusJson('completed'), 'profileId': null});
      task.readResult = () async => D01PilotResult.fromJson(customResult(empty: true), expectedJobId: pilotTestId, expectedVideoHash: hash, expectedMarkedInput: marked);
      return task;
    };
    Duration position = marked.callStart;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: D01PilotPanel(
      video: File('controlled.mp4'), videoIdentity: 'same-video', duration: const Duration(seconds: 7),
      openingVideo: false, onSeek: (_) async {}, api: api, userMarked: true, roi: marked.roi, currentPosition: () => position,
    )))));
    for (final key in ['pilot-mark-call-start', 'pilot-mark-call-end', 'pilot-start']) {
      if (key == 'pilot-mark-call-end') { position = marked.callEnd; }
      final finder = find.byKey(ValueKey(key)); await tester.ensureVisible(finder); await tester.pumpAndSettle();
      await tester.tap(finder); await tester.pumpAndSettle();
    }
    expect(api.tasks, hasLength(1)); expect(api.marks.single!.roi.toJson(), marked.roi.toJson());
    expect(api.marks.single!.callStart, marked.callStart); expect(api.marks.single!.callEnd, marked.callEnd);
    expect(find.byKey(const ValueKey('pilot-stage')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('pilot-stage'))).data, contains('tamamlandı'));
    expect(find.text('Aday bulunmadı; bu “tepki yok” anlamına gelmez.'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
