// Server-shaped controlled D01/D02 plans; no LLM, gallery, file IO or native codec.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:neuro_awareness_app/models/scenario_age_group.dart';
import 'package:neuro_awareness_app/models/scenario_graph.dart';
import 'package:neuro_awareness_app/models/scenario_clip_plan.dart';
import 'package:neuro_awareness_app/screens/clip_production_plan_screen.dart';
import 'package:neuro_awareness_app/screens/graph_playback_screen.dart';
import 'package:neuro_awareness_app/services/clip_video_store.dart';
import 'support/fake_graph_playback.dart';

LoadedClipPlan generated(String behavior) {
  final graph = ScenarioGraph(schemaVersion: '1.2', scenarioId: 'new-$behavior-story', title: 'New $behavior', language: 'tr',
    ageGroup: ScenarioAgeGroup.months24To36, behaviorId: behavior, cardVersion: '0.2', startSceneId: 'start',
    scenes: [for (final id in ['start','branch_a','branch_b']) ScenarioScene(id:id,title:id,description:'Controlled $id',behaviorIds:[behavior])],
    transitions: [for (final id in ['branch_a','branch_b']) ScenarioTransition(fromSceneId:'start',toSceneId:id,label:id,description:'Choose $id')],
    endSceneIds: ['branch_a','branch_b']);
  final plan = ScenarioClipPlan(schemaVersion:'1.1',planId:'generated-new-$behavior-plan',scenarioId:graph.scenarioId,
    ageGroup:ScenarioAgeGroup.months24To36,authoringNote:'Controlled unapproved server-shaped fixture',continuityNotes:'Controlled context',
    d01CallTiming: behavior=='D01' ? [D01PlannedCall(clipId:'start_1',callEndS:3)] : null,
    clips:[for (final scene in graph.scenes) for (var order=1;order<=(scene.id=='start'?1:2);order++) PlannedClip(
      id:'${scene.id}_$order',sceneId:scene.id,orderInScene:order,targetDurationS:scene.id=='start'?4:6,
      plannedAction:'Controlled action',initialState:'Before',finalState:'After',productionPrompt:'Full prompt',voiceoverInstructions:'Separate voice')]);
  return (graph:graph,plan:plan);
}

class _AttachStore extends FakeGraphStore {
  _AttachStore(super.plan);
  @override
  Future<ClipVideoAttachResult> attach({required String planId,required String clipId,required File source,required String fileName}) async {
    mutations++;
    final binding=ClipVideoBinding(planId:planId,clipId:clipId,relativePath:'clip_videos/import_NEW/video.mp4',fileName:fileName);
    bindings[clipId]=binding;return(binding:binding,warning:null);
  }
}

void main() {
  Future<void> tap(WidgetTester tester,String key) async {
    final finder=find.byKey(ValueKey(key));await tester.ensureVisible(finder);await tester.pumpAndSettle();
    expect(finder.hitTestable(),findsOneWidget);await tester.tap(finder);await tester.pumpAndSettle();
  }
  Future<void> mount(WidgetTester tester,LoadedClipPlan data,FakeGraphStore store,{GraphPlaybackHarness? harness,Future<XFile?> Function()? pick}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(home:ClipProductionPlanScreen(providedPlan:data,videoStore:store,
      createPlaybackPlayer:harness?.create,pickVideo:pick)));
    await tester.pumpAndSettle();
  }
  for (final behavior in ['D01','D02']) {
    for (var branch=0;branch<2;branch++) {
      testWidgets('$behavior generated plan -> existing player -> branch $branch exact files and completed-path replay', (tester) async {
        final data=generated(behavior);final h=GraphPlaybackHarness(data.graph,data.plan);
        await mount(tester,data,h.store,harness:h);
        expect(find.byKey(const ValueKey('plan-missing-video-bindings')),findsNothing);
        await tap(tester,'open-graph-playback');expect(find.byType(GraphPlaybackScreen),findsOneWidget);
        expect(h.players,isEmpty,reason:'No player before explicit Start');
        await tap(tester,'graph-playback-start');
        expect(h.events,contains('play:start_1'));
        h.latestPlayerForClip('start_1').finish();await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('graph-playback-choice:0')),findsOneWidget);
        expect(find.byKey(const ValueKey('graph-playback-choice:1')),findsOneWidget);
        final selected=branch==0?'branch_a':'branch_b';final other=branch==0?'branch_b':'branch_a';
        await tap(tester,'graph-playback-choice:$branch');
        for (var order=1;order<=2;order++) {
          final id='${selected}_$order';
          expect(tester.widget<Text>(find.byKey(const ValueKey('graph-playback-current'))).data,contains('Klip: $id'));
          expect(h.events,contains('play:$id'));
          expect(h.events.any((e)=>e=='play:${other}_1'),isFalse);
          h.latestPlayerForClip(id).finish();await tester.pumpAndSettle();
        }
        expect(find.byKey(const ValueKey('graph-playback-completed')),findsOneWidget);
        await tap(tester,'graph-playback-replay-path');
        for (final id in ['start_1','${selected}_1','${selected}_2']) {
          expect(tester.widget<Text>(find.byKey(const ValueKey('graph-playback-current'))).data,contains('Klip: $id'));
          expect(find.byKey(const ValueKey('graph-playback-choice:0')),findsNothing);
          h.latestPlayerForClip(id).finish();await tester.pumpAndSettle();
        }
        expect(h.events.where((e)=>e.startsWith('play:')).toList(),[
          'play:start_1','play:${selected}_1','play:${selected}_2','play:start_1','play:${selected}_1','play:${selected}_2']);
        await tester.pumpWidget(const SizedBox.shrink());await tester.pumpAndSettle();
        expect(h.live,0);expect(h.maximumLive,lessThanOrEqualTo(2));expect(h.maximumPlaying,lessThanOrEqualTo(1));
        expect(h.store.mutations,0);expect(tester.takeException(),isNull);
      });
    }
    testWidgets('$behavior missing mapping named, picker associates only current plan/clip', (tester) async {
      final data=generated(behavior);final store=_AttachStore(data.plan)..bindings.remove('branch_b_2');
      await mount(tester,data,store,pick:() async=>XFile('chosen-$behavior.mp4'));
      expect(find.byKey(const ValueKey('clip-missing-mapping:branch_b_2')),findsOneWidget);
      final scene=find.byKey(const ValueKey('clip-scene:branch_b'));
      final header=find.descendant(of:scene,matching:find.text('branch_b'));
      await tester.ensureVisible(header);await tester.pumpAndSettle();await tester.tap(header);await tester.pumpAndSettle();
      await tap(tester,'select-clip-video:branch_b_2');
      expect(store.bindings['branch_b_2']!.planId,data.plan.planId);
      expect(store.bindings['branch_b_2']!.fileName,'chosen-$behavior.mp4');
      expect(find.byKey(const ValueKey('clip-missing-mapping:branch_b_2')),findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());await tester.pumpAndSettle();
    });
  }
  testWidgets('Equal clip IDs in another plan never provide generated-plan videos', (tester) async {
    final old=generated('D01');final fresh=generated('D02');final store=FakeGraphStore(old.plan);
    await mount(tester,fresh,store);
    for(final clip in fresh.plan.clips) {
      expect(find.byKey(ValueKey('clip-missing-mapping:${clip.id}')),findsOneWidget);
    }
    expect(store.mutations,0);await tester.pumpWidget(const SizedBox.shrink());await tester.pumpAndSettle();
  });
}
