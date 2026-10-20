import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/models/scenario_clip_plan.dart';
import 'package:neuro_awareness_app/models/scenario_graph.dart';
import 'package:neuro_awareness_app/screens/clip_production_plan_screen.dart';
import 'package:neuro_awareness_app/screens/graph_playback_screen.dart';

import 'support/fake_graph_playback.dart';

class _Bundle extends CachingAssetBundle {
  _Bundle(this.sources);
  final Map<String, String> sources;
  @override
  Future<String> loadString(String key, {bool cache = true}) async => sources[key]!;
  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

void main() {
  final sources = {
    for (final path in [ClipProductionPlanScreen.d01GraphAssetPath,
        ClipProductionPlanScreen.d01PlanAssetPath]) path: File(path).readAsStringSync(),
  };
  final graph = ScenarioGraph.fromJsonString(sources[ClipProductionPlanScreen.d01GraphAssetPath]!);
  final plan = ScenarioClipPlan.fromJsonString(sources[ClipProductionPlanScreen.d01PlanAssetPath]!);
  late GraphPlaybackHarness harness;
  setUp(() { harness = GraphPlaybackHarness(graph, plan); });

  Widget screen() => GraphPlaybackScreen(graph: harness.graph, plan: harness.plan,
      videoStore: harness.store, createPlayer: harness.create);

  Future<void> mount(WidgetTester tester, {double scale = 1}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: screen(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final button = find.byKey(ValueKey(key));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    harness.players.last.finish();
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Future<void> toggleDetails(WidgetTester tester, int index) async {
    final tile = find.byKey(ValueKey(
      'graph-playback-choice-details:${harness.graph.startSceneId}:$index',
    ));
    final header = find.descendant(of: tile, matching: find.text('Geçiş ayrıntıları'));
    await tester.ensureVisible(header);
    await tester.tap(header);
    await tester.pumpAndSettle();
  }

  ScenarioGraph withChoiceText({String? label, String? targetTitle}) {
    final first = graph.transitions.firstWhere((edge) => edge.fromSceneId == graph.startSceneId);
    return ScenarioGraph.fromJson({
      ...graph.toJson(),
      'transitions': [
        for (final edge in graph.transitions)
          {...edge.toJson(), if (identical(edge, first)) 'label': label},
      ],
      'scenes': [
        for (final scene in graph.scenes)
          {...scene.toJson(), if (scene.id == first.toSceneId) 'title': targetTitle},
      ],
    });
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(harness.live, 0);
    expect(harness.maximumLive, lessThanOrEqualTo(1));
    expect(harness.store.mutations, 0);
    expect(tester.takeException(), isNull);
  }

  testWidgets('Mevcut debug üretim girişi geliştirici oynatma yolunu korur', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(DefaultAssetBundle(bundle: _Bundle(sources),
      child: MaterialApp(home: ClipProductionPlanScreen(videoStore: harness.store))));
    await tester.pumpAndSettle();
    await tap(tester, 'open-graph-playback');
    expect(find.byType(GraphPlaybackScreen), findsOneWidget);
    expect(find.text('Geliştirici denemesi; video içeriği ve sürekliliği doğrulanmadı'), findsOneWidget);
    expect(find.text('Başlat'), findsOneWidget);
    expect(harness.players, isEmpty);
    await unmount(tester);
  });

  for (var branch = 0; branch < 2; branch++) {
    testWidgets('Dal $branch kullanıcı seçimiyle oynar ve bitiş klibinden sonra tamamlanır', (tester) async {
      await mount(tester);
      expect(harness.players, isEmpty);
      await tap(tester, 'graph-playback-start');
      // Hedef süre çoktan geçse de bitiş olayı olmadan klip değişmemeli.
      await tester.pump(const Duration(seconds: 30));
      expect(harness.players, hasLength(1));
      expect(find.text('Senaryo tamamlandı'), findsNothing);
      await finish(tester);
      final choices = graph.transitions.where((edge) => edge.fromSceneId == graph.startSceneId).toList();
      for (var i = 0; i < choices.length; i++) {
        final edge = choices[i];
        final button = find.byKey(ValueKey('graph-playback-choice:$i'));
        expect(find.descendant(of: button, matching: find.text(edge.label!)), findsOneWidget);
        expect(find.descendant(of: button, matching: find.text(edge.description)), findsNothing);
        expect(find.text(edge.description), findsNothing);
        await toggleDetails(tester, i);
        expect(find.text(edge.description), findsOneWidget);
        await toggleDetails(tester, i);
        expect(find.text(edge.description), findsNothing);
      }
      expect(harness.live, 0);
      await tap(tester, 'graph-playback-choice:$branch');
      final scene = choices[branch].toSceneId;
      final clips = plan.clipsForScene(scene);
      expect(harness.players.last.id, clips.first.id);
      for (var i = 1; i < clips.length; i++) {
        await finish(tester);
        expect(harness.players.last.id, clips[i].id);
      }
      await finish(tester); // Tek çıkış terminal sahneye otomatik ilerler.
      expect(find.text('Senaryo tamamlandı'), findsNothing);
      await finish(tester);
      expect(find.text('Senaryo tamamlandı'), findsOneWidget);
      await tap(tester, 'graph-playback-restart');
      expect(harness.players.last.id, plan.clipsForScene(graph.startSceneId).first.id);
      expect(find.text('Senaryo tamamlandı'), findsNothing);
      await unmount(tester);
    });
  }

  for (final variant in [
    (name: 'kısa label başlığa tercih edilir', label: 'Kısa seçenek',
      title: 'Hedef sahne başlığı', expected: 'Kısa seçenek'),
    (name: 'label yoksa hedef başlığı kullanılır', label: null,
      title: 'Hedef sahne başlığı', expected: 'Hedef sahne başlığı'),
    (name: 'label ve başlık yoksa açıklama kullanılır', label: null,
      title: null, expected: graph.transitions.first.description),
    (name: 'boş label ve başlıkta açıklama kullanılır', label: '  ',
      title: '  ', expected: graph.transitions.first.description),
  ]) {
    testWidgets(variant.name, (tester) async {
      final fixture = withChoiceText(label: variant.label, targetTitle: variant.title);
      harness = GraphPlaybackHarness(fixture, plan);
      await mount(tester);
      await tap(tester, 'graph-playback-start');
      await finish(tester);
      final button = find.byKey(const ValueKey('graph-playback-choice:0'));
      expect(find.descendant(of: button, matching: find.text(variant.expected)), findsOneWidget);
      final edge = fixture.transitions.firstWhere((item) => item.fromSceneId == fixture.startSceneId);
      await toggleDetails(tester, 0);
      expect(tester.widget<SelectableText>(find.byKey(
        const ValueKey('graph-playback-choice-description:0'),
      )).data, edge.description);
      await tap(tester, 'graph-playback-choice:0');
      expect(harness.players.last.id, plan.clipsForScene(edge.toSceneId).first.id);
      await unmount(tester);
    });
  }

  testWidgets('Dar ekran ve büyük yazıda seçenek sarılır; tam ayrıntı kaydırılıp kapatılır', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const label = 'Dar ekranda büyük yazıyla bütünü okunabilen uzun bir alternatif başlığı';
    harness = GraphPlaybackHarness(withChoiceText(label: label), plan);
    await mount(tester, scale: 2);
    await tap(tester, 'graph-playback-start');
    await finish(tester);
    final button = find.byKey(const ValueKey('graph-playback-choice:0'));
    await tester.ensureVisible(button);
    expect(button.hitTestable(), findsOneWidget);
    final text = tester.widget<Text>(find.descendant(of: button, matching: find.text(label)));
    expect(text.softWrap, isTrue);
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: button, matching: find.byType(RichText)),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.getSize(button).height, greaterThan(80));
    expect(tester.getSize(button).width, lessThanOrEqualTo(320));
    await toggleDetails(tester, 0);
    final description = find.byKey(const ValueKey('graph-playback-choice-description:0'));
    final fullText = tester.widget<SelectableText>(description);
    expect(fullText.data, harness.graph.transitions.first.description);
    expect(fullText.maxLines, isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('graph-playback-choice:1')));
    expect(tester.takeException(), isNull);
    await toggleDetails(tester, 0);
    expect(description, findsNothing);
    await tap(tester, 'graph-playback-choice:1');
    final chosen = harness.graph.transitions.where(
      (edge) => edge.fromSceneId == harness.graph.startSceneId,
    ).elementAt(1);
    expect(harness.players.last.id, plan.clipsForScene(chosen.toSceneId).first.id);
    await unmount(tester);
  });

  testWidgets('Eksik klip kimlikleriyle gösterilir, atlanmaz ve eşlemesi silinmez', (tester) async {
    final clip = plan.clipsForScene(graph.startSceneId).first;
    harness.store.missingFile = clip.id;
    await mount(tester);
    await tap(tester, 'graph-playback-start');
    expect(find.textContaining('Kayıtlı video dosyası bulunamadı.'), findsOneWidget);
    final error = tester.widget<Text>(find.byKey(const ValueKey('graph-playback-error'))).data!;
    expect(error, contains(graph.startSceneId));
    expect(error, contains(clip.id));
    expect(harness.store.bindings, contains(clip.id));
    expect(harness.players, isEmpty);
    await unmount(tester);
  });

  testWidgets('Arka plan duraklatır; dönüşte yalnız kullanıcı tekrar oynatır', (tester) async {
    await mount(tester);
    await tap(tester, 'graph-playback-start');
    final player = harness.players.single;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(player.playing, isFalse);
    final playCount = harness.events.where((event) => event.startsWith('play:')).length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Devam et'), findsOneWidget);
    expect(harness.events.where((event) => event.startsWith('play:')).length, playCount);
    await tap(tester, 'graph-playback-toggle');
    expect(player.playing, isTrue);
    await tap(tester, 'graph-playback-toggle');
    expect(player.playing, isFalse);
    await unmount(tester);
  });

  testWidgets('Yükleme sırasında geri çıkış kaynakları kapatır; geç sonuç oynatmaz', (tester) async {
    final gate = Completer<void>();
    harness.nextOpenGate = gate;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () {
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen()));
      }, child: const Text('Grafı aç')),
    ))));
    await tester.tap(find.text('Grafı aç'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('graph-playback-start')));
    await tester.pump();
    expect(find.text('Video yükleniyor…'), findsOneWidget);
    expect(harness.players, hasLength(1));
    await tester.pageBack();
    await tester.pump();
    expect(harness.live, 0);
    expect(harness.players.single.playing, isFalse);
    gate.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(harness.events.where((event) => event.startsWith('play:')), isEmpty);
    await unmount(tester);
  });

  testWidgets('Oynatma hatası akışı durdurup mevcut oynatıcıyı kapatır', (tester) async {
    await mount(tester);
    await tap(tester, 'graph-playback-start');
    harness.players.single.fail();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.textContaining('oynatma hatası oluştu.'), findsOneWidget);
    expect(harness.live, 0);
    expect(find.byKey(const ValueKey('graph-playback-toggle')), findsNothing);
    await unmount(tester);
  });
}
