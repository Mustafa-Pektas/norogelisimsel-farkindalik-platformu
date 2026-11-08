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

const id = '12345678-1234-4123-8123-123456789abc';
const input = D01FastInput(targetPoint: [.3,.46], callStart: Duration(milliseconds: 401),callEnd: Duration(milliseconds: 1152));
Map<String,dynamic> fixture() => jsonDecode(File('test/fixtures/d01_fast_result.json').readAsStringSync()) as Map<String,dynamic>;
D01PilotResult result(Map<String,dynamic> json) => D01PilotResult.fromJson(json, expectedJobId: id,
  expectedVideoHash: fixture()['videoHash'] as String, expectedFastInput: input);

void main() {
  test('API1.2 preserves missing ends, phases, coverage and hash binding', () {
    final r=result(fixture()); expect(r.fast,isTrue);expect(r.raw.single.end,isNull);
    expect(r.raw.single.callPhase,'after_call');expect(r.coverage['poseFrames'],43);
    final wrong=fixture()..['videoHash']=List.filled(64,'f').join();
    expect(()=>result(wrong),throwsA(isA<D01PilotException>()));
    final preexisting=fixture();
    for(final mode in ['raw','ema_050']) {
      final c=((preexisting['movements'] as Map)[mode] as List).single as Map;
      c['movement_start_s']=.1;c['start_minus_manual_call_start_s']=-.301;c['start_minus_manual_call_end_s']=-1.052;c['callPhase']='after_call';
    }
    expect(()=>result(preexisting),throwsA(isA<D01PilotException>()));
    final empty=fixture();
    (empty['movements'] as Map)['raw']=<Map<String,dynamic>>[];
    (empty['movements'] as Map)['ema_050']=<Map<String,dynamic>>[];
    expect(result(empty).raw,isEmpty);
  });
  test('Fast multipart sends no ROI or movement labels; optional call marks stay absent',() async {
    final dir=Directory.systemTemp.createTempSync('fast-http-');addTearDown(()=>dir.deleteSync(recursive:true));
    final video=File('${dir.path}/video.mp4')..writeAsBytesSync([1,2,3]);
    final api=HttpD01PilotApi(clientFactory:()=>MockClient((request) async {
      expect(request.headers['Authorization'],'Bearer session-only');
      expect(request.body,contains('mediapipe_pnp_flow'));expect(request.body,isNot(contains('name="roi"')));
      expect(request.body,isNot(contains('callStartS')));expect(request.body,isNot(contains('response_start')));
      return http.Response(jsonEncode({'jobId':id,'status':'running','videoHash':fixture()['videoHash'],'sourceType':'automatic_face_tracking'}),202);
    }));
    final task=api.create(video:video,address:'http://127.0.0.1:8000',accessKey:'session-only',fastInput:const D01FastInput());
    expect((await task.submit()).jobId,id);task.close();
  });
  testWidgets('Fast empty or incomplete result is visible, seek preserves known start despite missing end', (tester) async {
    final api=ControlledPilotApi();
    api.makeTask=(){ final t=ControlledPilotTask();t.readStatus=()async=>D01PilotStatus.fromJson({'jobId':id,'status':'completed'});t.readResult=()async=>result(fixture());return t;};
    Duration? sought;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:D01PilotPanel(
      fastAnalysis:true,video:File('controlled.mp4'),videoIdentity:Object(),duration:const Duration(seconds:7),openingVideo:false,
      onSeek:(t)async{sought=t;},api:api,initialAccessKey:'session-only',pollInterval:const Duration(milliseconds:1),
    )))));
    await tester.enterText(find.byKey(const ValueKey('pilot-address')),'http://127.0.0.1:8000');
    await tester.ensureVisible(find.byKey(const ValueKey('pilot-start')));await tester.tap(find.byKey(const ValueKey('pilot-start')));await tester.pumpAndSettle();
    expect(api.fastInputs.single,isNotNull);expect(find.byKey(const ValueKey('pilot-coverage')),findsOneWidget);
    final candidate=find.byKey(const ValueKey('pilot-raw-candidate_001'));
    await tester.ensureVisible(candidate);await tester.tap(candidate);await tester.pump();
    expect(sought,const Duration(microseconds:1583333));
    await tester.pumpWidget(const SizedBox.shrink());await tester.pump();
    expect(api.tasks.single.cancels,0);
  });
}
