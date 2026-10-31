import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:neuro_awareness_app/screens/video_analysis_screen.dart';
import 'package:neuro_awareness_app/widgets/expandable_finding_card.dart';
import 'package:neuro_awareness_app/widgets/finding_notification_pill.dart';
import 'package:neuro_awareness_app/widgets/floating_video_controls.dart';
import 'package:neuro_awareness_app/widgets/fullscreen_video_screen.dart';
import 'package:neuro_awareness_app/services/d01_pilot_service.dart';
import 'package:neuro_awareness_app/models/d01_pilot_result.dart';
import 'support/d01_pilot_fixtures.dart';
// Mevcut video_player paketinin test sınırı; gerçek video motoru kullanılmaz.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _VideoPlatform extends VideoPlayerPlatform {
  final sources = <DataSource>[];
  final events = <int, StreamController<VideoEvent>>{};
  final positions = <int, Duration>{};
  final calls = <String>[];
  bool holdInitialize = false;
  bool failInitialize = false;
  bool holdCreate = false;
  final createGates = <int, Completer<void>>{};

  void ready(int id) {
    if (events[id]!.isClosed) return;
    calls.add('initialized:$id');
    events[id]!.add(VideoEvent(
      eventType: VideoEventType.initialized,
      size: const Size(640, 360),
      duration: const Duration(seconds: 120),
    ));
  }

  void fail(int id) {
    if (events[id]!.isClosed) return;
    events[id]!.addError(PlatformException(
      code: 'TEST_CODEC', message: 'Kontrollü açılış hatası',
    ));
  }

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = sources.length;
    sources.add(options.dataSource);
    calls.add('create:$id');
    final stream = StreamController<VideoEvent>(onCancel: () async {});
    // done Future'ını abonelik iptal edilmeden testin kendi alanında oluştur.
    // Aksi halde dispose içindeki close(), iptal edilmiş akış için SDK'nın
    // root zone'daki ortak Future'ını döndürür; pumpAndSettle onu beklemez.
    unawaited(stream.done);
    events[id] = stream;
    if (failInitialize) {
      fail(id);
    } else if (!holdInitialize) {
      ready(id);
    }
    if (holdCreate) {
      final gate = Completer<void>();
      createGates[id] = gate;
      await gate.future;
    }
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose:$playerId');
    await events[playerId]!.close();
    calls.add('disposed:$playerId');
  }

  @override
  Future<void> play(int playerId) async { calls.add('play:$playerId'); }
  @override
  Future<void> pause(int playerId) async { calls.add('pause:$playerId'); }
  @override
  Future<void> seekTo(int playerId, Duration position) async {
    positions[playerId] = position;
  }
  @override
  Future<Duration> getPosition(int playerId) async => positions[playerId] ?? Duration.zero;
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox.expand();
}

void main() {
  late VideoPlayerPlatform originalVideo;
  late _VideoPlatform platform;
  setUp(() {
    originalVideo = VideoPlayerPlatform.instance;
    platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  tearDown(() {
    VideoPlayerPlatform.instance = originalVideo;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> mount(WidgetTester tester, Future<XFile?> Function(ImageSource) pick,
      {bool settle = true, ValueNotifier<bool>? tabVisibility,
      Size surfaceSize = const Size(1000, 1000), double textScale = 1,
      bool pilot = false, D01PilotApi? pilotApi}) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: VideoAnalysisScreen(pickVideo: pick, tabVisibility: tabVisibility,
        experimentalD01: pilot, pilotApi: pilotApi),
    ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('Video Analysis opens experimental pilot without a new player or upload', (tester) async {
    final api = ControlledPilotApi();
    await mount(tester, (_) async => null, pilotApi: api);
    final players = platform.sources.length;
    final entry = find.byKey(const ValueKey('open-d01-pilot-analysis'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    final screen = tester.widget<VideoAnalysisScreen>(find.byType(VideoAnalysisScreen).last);
    expect(screen.experimentalD01, isTrue);
    expect(find.textContaining('Yalnız iki denetlenmiş D01'), findsOneWidget);
    expect(platform.sources.length, players);
    expect(api.tasks, isEmpty);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('open-d01-pilot-analysis')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    for (var id = 0; id < platform.sources.length; id++) {
      expect(platform.calls.where((call) => call == 'dispose:$id'), hasLength(1));
    }
    expect(tester.takeException(), isNull);
  });

  Future<void> pickFromGallery(WidgetTester tester, String label,
      {bool checkSourceLayout = false}) async {
    final button = find.byKey(const ValueKey('video-source-button'));
    expect(button, findsOneWidget, reason: 'Video kaynağı eylemi: $label');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final gallery = find.text('Galeri');
    expect(gallery, findsOneWidget, reason: 'Video kaynağı seçici açılmalı.');
    if (checkSourceLayout) {
      final heading = find.text('Video Kaynağı');
      final close = find.byKey(const ValueKey('video-source-close'));
      expect(heading, findsOneWidget);
      expect(close.hitTestable(), findsOneWidget);
      expect(tester.getRect(heading).right, lessThanOrEqualTo(tester.getRect(close).left),
          reason: 'Tam başlık kullanılabilir genişlikte satır kırmalı; kapatma düğmesini taşırmamalı.');
      expect(gallery.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(gallery);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Galeri'), findsNothing, reason: 'Seçimden sonra video kaynağı seçici kapanmalı.');
    await tester.pump();
  }

  void expectNoClinicalResults() {
    expect(find.byKey(const ValueKey('video-example-report')), findsNothing);
    expect(find.byType(ExpandableFindingCard), findsNothing);
    expect(find.byType(FindingNotificationPill), findsNothing);
    expect(find.text('Önemli Anlar'), findsNothing);
    expect(find.textContaining('Kanıt Noktası'), findsNothing);
    expect(find.textContaining('Örnek rapor'), findsNothing);
    expect(find.textContaining('Risk Saptanmadı'), findsNothing);
    expect(find.textContaining('Sınırda Tepki'), findsNothing);
    expect(find.textContaining('Klinik İnceleme'), findsNothing);
    expect(find.text('Videoyu Analiz Et'), findsNothing);
    expect(find.text('Analiz Aşamaları'), findsNothing);
  }

  void expectNoAnalysisResults() {
    expectNoClinicalResults();
  }

  FloatingVideoControls controls(WidgetTester tester) =>
      tester.widget<FloatingVideoControls>(find.byType(FloatingVideoControls));

  Future<void> checkFullscreen(WidgetTester tester, {required String expectedTitle}) async {
    final current = controls(tester).controller;
    final position = current.value.position;
    final isPlaying = current.value.isPlaying;
    await tester.pumpAndSettle();

    // pumpAndSettle bildirim süresini tüketmez. Açık başarı bildirimi ortak
    // ScaffoldMessenger ile tam ekrana taşınıp alttaki çıkışa dokunmayı engeller.
    // Bildirimi beklemek veya çıkış callback'ini atlamak yerine kullanıcı gibi kapat.
    final notification = find.byType(SnackBar);
    if (notification.evaluate().isNotEmpty) {
      expect(notification, findsOneWidget);
      await tester.drag(notification, Offset(0, tester.getSize(notification).height));
      await tester.pumpAndSettle();
      expect(notification, findsNothing);
    }

    final enterFullscreen = find.widgetWithIcon(IconButton, Icons.fullscreen_rounded);
    await tester.ensureVisible(enterFullscreen);
    expect(tester.widget<IconButton>(enterFullscreen).onPressed, isNotNull);
    expect(enterFullscreen.hitTestable(), findsOneWidget);
    await tester.tap(enterFullscreen);
    await tester.pumpAndSettle();
    final fullscreen = tester.widget<FullscreenVideoScreen>(find.byType(FullscreenVideoScreen));
    expect(fullscreen.controller, same(current));
    expect(current.value.position, position);
    expect(current.value.isPlaying, isPlaying);
    expect(fullscreen.findings, isEmpty);
    expect(fullscreen.title, expectedTitle);
    expectNoClinicalResults();
    final exitFullscreen = find.descendant(
      of: find.byType(FullscreenVideoScreen),
      matching: find.widgetWithIcon(IconButton, Icons.fullscreen_exit_rounded),
    );
    expect(exitFullscreen, findsOneWidget);
    expect(tester.widget<IconButton>(exitFullscreen).onPressed, isNotNull);
    expect(exitFullscreen.hitTestable(), findsOneWidget);
    await tester.tap(exitFullscreen);
    await tester.pumpAndSettle();
    expect(find.byType(FullscreenVideoScreen), findsNothing);
    expect(controls(tester).controller, same(current));
    expect(current.value.position, position);
    expect(current.value.isPlaying, isPlaying);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    for (var id = 0; id < platform.sources.length; id++) {
      expect(platform.calls.where((call) => call == 'dispose:$id'), hasLength(1));
      expect(platform.calls, contains('disposed:$id'));
    }
    expect(tester.takeException(), isNull);
  }

  Future<void> startPilot(WidgetTester tester) async {
    final address = find.byKey(const ValueKey('pilot-address'));
    await tester.ensureVisible(address);
    await tester.enterText(address, 'http://10.0.2.2:8000');
    final button = find.byKey(const ValueKey('pilot-start'));
    await tester.ensureVisible(button); await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('Pilot uses existing preview/fullscreen; seek pauses same controller without playing', (tester) async {
    // Establish and restore a valid foreground baseline, including on failure.
    void resumeLifecycle() {
      final binding = tester.binding;
      if (binding.lifecycleState == AppLifecycleState.paused) {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      }
      if (binding.lifecycleState == AppLifecycleState.hidden) {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      }
      if (binding.lifecycleState != AppLifecycleState.resumed) {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
    }
    resumeLifecycle();
    addTearDown(resumeLifecycle);
    final api = ControlledPilotApi();
    final task = ControlledPilotTask()
      ..readStatus = () async => D01PilotStatus.fromJson(pilotStatusJson('completed'));
    api.makeTask = () => task;
    await mount(tester, (_) async => XFile('second.mp4'), pilot: true, pilotApi: api);
    expect(platform.sources, isEmpty, reason: 'Pilot must not open a different default example.');
    expect(find.byTooltip('Gemini API Anahtarı'), findsNothing);
    await pickFromGallery(tester, 'Video seç');
    final controller = controls(tester).controller;
    await controller.play(); await tester.pump();
    await startPilot(tester);
    final candidate = find.byKey(const ValueKey('pilot-raw-candidate_001'));
    await tester.ensureVisible(candidate); await tester.tap(candidate); await tester.pumpAndSettle();
    expect(controls(tester).controller, same(controller));
    expect(controller.value.position, const Duration(milliseconds: 1500));
    expect(controller.value.isPlaying, isFalse);
    expect(platform.calls.where((x) => x == 'play:0'), hasLength(1));
    expect(task.submits, 1);
    await controller.play();
    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(controller.value.isPlaying, isFalse,
          reason: 'Video arka plana geçerken duraklamalı.');
    } finally {
      resumeLifecycle();
    }
    await tester.pump();
    expect(tester.binding.lifecycleState, AppLifecycleState.resumed);
    expect(controller.value.isPlaying, isFalse);
    expect(controls(tester).controller, same(controller));
    expect(controller.value.position, const Duration(milliseconds: 1500));
    await checkFullscreen(tester, expectedTitle: 'second.mp4');
    expect(find.byKey(const ValueKey('pilot-raw-candidate_001')), findsOneWidget);
    await close(tester);
  });

  testWidgets('Pilot 320px/double text keeps preview and start controls accessible', (tester) async {
    await mount(tester, (_) async => XFile('second.mp4'), pilot: true,
      pilotApi: ControlledPilotApi(), surfaceSize: const Size(320, 744), textScale: 2);
    await pickFromGallery(tester, 'Video seç', checkSourceLayout: true); await tester.pumpAndSettle();
    final preview = find.byType(FloatingVideoControls);
    await tester.ensureVisible(preview); await tester.pumpAndSettle();
    expect(controls(tester).wrapControls, isTrue);
    for (final icon in [Icons.play_arrow_rounded, Icons.replay_5_rounded,
      Icons.forward_5_rounded, Icons.volume_up_rounded, Icons.fullscreen_rounded]) {
      final control = find.descendant(of: preview, matching: find.widgetWithIcon(IconButton, icon));
      expect(control.hitTestable(), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    final start = find.byKey(const ValueKey('pilot-start'));
    await tester.ensureVisible(start); await tester.pumpAndSettle();
    expect(start.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('Pilot source cancel/failure preserves result; successful source change drops old identity', (tester) async {
    final api = ControlledPilotApi();
    final task = ControlledPilotTask()
      ..readStatus = () async => D01PilotStatus.fromJson(pilotStatusJson('completed'));
    api.makeTask = () => task;
    XFile? selection = XFile('second.mp4');
    await mount(tester, (_) async => selection, pilot: true, pilotApi: api);
    await pickFromGallery(tester, 'Video seç'); await startPilot(tester);
    final controller = controls(tester).controller;
    selection = null;
    await pickFromGallery(tester, 'Video değiştir');
    expect(controls(tester).controller, same(controller));
    expect(find.byKey(const ValueKey('pilot-raw-candidate_001')), findsOneWidget);
    platform.failInitialize = true; selection = XFile('bad.mp4');
    await pickFromGallery(tester, 'Video değiştir'); await tester.pumpAndSettle();
    expect(controls(tester).controller, same(controller));
    expect(find.byKey(const ValueKey('pilot-raw-candidate_001')), findsOneWidget);
    platform.failInitialize = false; selection = XFile('new.mp4');
    await pickFromGallery(tester, 'Video değiştir'); await tester.pumpAndSettle();
    expect(controls(tester).controller, isNot(same(controller)));
    expect(find.byKey(const ValueKey('pilot-raw-candidate_001')), findsNothing);
    expect(task.submits, 1); expect(task.cancels, 0);
    await close(tester);
  });




  testWidgets('Sekmeden hızlı ayrılıp dönmek seçili dosyayı ve konumu koruyarak duraklatır', (tester) async {
    final visibility = ValueNotifier<bool>(true);
    addTearDown(visibility.dispose);
    await mount(tester, (_) async => XFile('retained.mp4'), tabVisibility: visibility);
    await pickFromGallery(tester, 'Video seç');
    final current = controls(tester).controller;
    await current.seekTo(const Duration(seconds: 7));
    await current.play();
    await tester.pump();
    final sourceCount = platform.sources.length;
    final plays = platform.calls.where((call) => call == 'play:1').length;
    final pauses = platform.calls.where((call) => call == 'pause:1').length;

    // Arada build olmadan geri dönüş bile duraklatma bildirimini kaçırmamalı.
    visibility.value = false;
    visibility.value = true;
    await tester.pumpAndSettle();
    expect(current.value.isPlaying, isFalse);
    expect(current.value.position, const Duration(seconds: 7));
    expect(controls(tester).controller, same(current));
    expect(platform.sources, hasLength(sourceCount));
    expect(platform.sources.last.uri, contains('retained.mp4'));
    expect(find.text('retained.mp4'), findsOneWidget);
    expect(platform.calls.where((call) => call == 'pause:1').length, greaterThan(pauses));
    expect(platform.calls.where((call) => call == 'play:1'), hasLength(plays));
    expect(platform.calls, isNot(contains('dispose:1')));
    expectNoAnalysisResults();

    final play = find.widgetWithIcon(IconButton, Icons.play_arrow_rounded);
    await tester.ensureVisible(play);
    await tester.tap(play);
    await tester.pump();
    expect(current.value.isPlaying, isTrue);
    expect(platform.calls.where((call) => call == 'play:1'), hasLength(plays + 1));
    await current.pause();
    await checkFullscreen(tester, expectedTitle: 'retained.mp4');
    expect(controls(tester).controller, same(current));
    expect(current.value.position, const Duration(seconds: 7));
    await close(tester);
  });

  testWidgets('Görünürlük kaybolurken oynatıcı hazır değilse hata vermez; gizli açılış duraklar', (tester) async {
    final visibility = ValueNotifier<bool>(true);
    addTearDown(visibility.dispose);
    platform.holdInitialize = true;
    await mount(tester, (_) async => null, tabVisibility: visibility, settle: false);
    visibility.value = false;
    await tester.pump();
    expect(find.byType(FloatingVideoControls), findsNothing);
    expect(tester.takeException(), isNull);
    platform.ready(0);
    await tester.pumpAndSettle();
    final current = controls(tester).controller;
    expect(current.value.isInitialized, isTrue);
    expect(current.value.isPlaying, isFalse);
    expect(platform.calls, contains('pause:0'));
    expect(platform.calls.where((call) => call.startsWith('play:')), isEmpty);
    expect(find.byKey(const ValueKey('video-open-error')), findsNothing);
    visibility.value = true;
    await tester.pumpAndSettle();
    expect(controls(tester).controller, same(current));
    expect(current.value.isPlaying, isFalse);
    expect(platform.sources, hasLength(1));
    await close(tester);
  });

  for (final failCandidate in [false, true]) {
    testWidgets('Sekme dışındaki bekleyen aday ${failCandidate ? 'hata verse de eski videoyu korur' : 'açılsa da otomatik başlamaz'}', (tester) async {
      final visibility = ValueNotifier<bool>(true);
      addTearDown(visibility.dispose);
      var selected = 'working.mp4';
      await mount(tester, (_) async => XFile(selected), tabVisibility: visibility);
      await pickFromGallery(tester, 'Video seç');
      final previous = controls(tester).controller;
      await previous.seekTo(const Duration(seconds: 9));
      await previous.play();
      await tester.pump();
      platform.holdInitialize = true;
      selected = 'pending.mp4';
      await pickFromGallery(tester, 'Video değiştir');
      visibility.value = false;
      await tester.pump();
      expect(previous.value.isPlaying, isFalse);
      expect(previous.value.position, const Duration(seconds: 9));
      expect(controls(tester).controller, same(previous));
      expect(find.text('working.mp4'), findsOneWidget);
      expect(platform.calls, isNot(contains('dispose:1')));

      if (failCandidate) {
        platform.fail(2);
      } else {
        platform.ready(2);
      }
      await tester.pumpAndSettle();
      final retained = controls(tester).controller;
      expect(retained.value.isPlaying, isFalse);
      expect(platform.calls, isNot(contains('play:2')));
      if (failCandidate) {
        expect(retained, same(previous));
        expect(retained.value.position, const Duration(seconds: 9));
        expect(find.text('working.mp4'), findsOneWidget);
        expect(find.text('pending.mp4'), findsNothing);
        expect(platform.calls, contains('disposed:2'));
        expect(platform.calls, isNot(contains('dispose:1')));
        expect(find.byKey(const ValueKey('video-open-error')), findsOneWidget);
      } else {
        expect(retained, isNot(same(previous)));
        expect(find.text('pending.mp4'), findsOneWidget);
        expect(platform.calls, containsAllInOrder(['initialized:2', 'pause:2', 'dispose:1']));
        expect(find.byKey(const ValueKey('video-open-error')), findsNothing);
      }
      visibility.value = true;
      await tester.pumpAndSettle();
      expect(controls(tester).controller, same(retained));
      expect(retained.value.isPlaying, isFalse);
      expect(platform.sources, hasLength(3));
      expectNoAnalysisResults();
      await close(tester);
    });
  }

  testWidgets('Örnek ve seçilen videoda klinik bulgu yoktur; tam ekran aynı oynatıcıyı kullanır', (tester) async {
    final selections = <ImageSource>[];
    await mount(tester, (source) async {
      selections.add(source);
      return XFile('selected.mp4');
    });
    expect(find.widgetWithText(AppBar, 'Video Analizi'), findsOneWidget);
    expect(find.text('Video Analiz Modu'), findsNothing);
    expect(find.text('Video Yükle'), findsNothing);
    expect(find.byKey(const ValueKey('video-analysis-example-notice')), findsOneWidget);
    expect(find.text('Örnek video — analiz edilmedi.'), findsOneWidget);
    expectNoAnalysisResults();
    // Eski örnek bildirim aralığına gidilse de klinik içerik gösterilmemeli.
    final old = tester.widget<FloatingVideoControls>(find.byType(FloatingVideoControls)).controller;
    await old.seekTo(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expectNoAnalysisResults();
    await checkFullscreen(tester, expectedTitle: 'Örnek video — analiz edilmedi');
    expect(platform.sources, hasLength(1));
    expect(platform.calls, isNot(contains('dispose:0')));
    await pickFromGallery(tester, 'Video seç');
    expect(selections, [ImageSource.gallery]);
    expect(platform.sources.last.sourceType, DataSourceType.file);
    expect(platform.calls, containsAllInOrder(['dispose:0', 'disposed:0']),
        reason: 'Başarılı değişimden sonra önceki oynatıcı kapatılmalı.');
    expect(platform.calls, containsAllInOrder(['initialized:1', 'dispose:0']));
    expect(find.text('Video açıldı.'), findsOneWidget);
    expect(find.byKey(const ValueKey('video-analysis-example-notice')), findsNothing);
    expectNoAnalysisResults();

    final controls = tester.widget<FloatingVideoControls>(find.byType(FloatingVideoControls));
    await controls.controller.seekTo(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expectNoAnalysisResults();
    final play = find.widgetWithIcon(IconButton, Icons.play_arrow_rounded);
    await tester.ensureVisible(play);
    await tester.tap(play);
    await tester.pump();
    expect(platform.calls, contains('play:1'));
    await controls.controller.pause();
    await tester.pump(const Duration(seconds: 3));
    expectNoAnalysisResults();

    await checkFullscreen(tester, expectedTitle: 'selected.mp4');
    expect(find.text('selected.mp4'), findsOneWidget);
    expect(tester.widget<FloatingVideoControls>(find.byType(FloatingVideoControls)).controller,
        same(controls.controller));
    expectNoAnalysisResults();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Seçim iptalinde video korunur; örneğe dönüş de raporsuz izleme olarak kalır', (tester) async {
    XFile? selection = XFile('chosen.mp4');
    await mount(tester, (_) async => selection);
    await pickFromGallery(tester, 'Video seç');
    expect(platform.calls, containsAllInOrder(['dispose:0', 'disposed:0']),
        reason: 'Kapanış Future’ı testin sanal zamanında tamamlanmalı.');
    expectNoAnalysisResults();
    final sourceCount = platform.sources.length;
    final previous = controls(tester).controller;
    await previous.seekTo(const Duration(seconds: 7));
    selection = null;
    await pickFromGallery(tester, 'Video değiştir');
    expect(platform.sources, hasLength(sourceCount));
    expect(find.text('chosen.mp4'), findsOneWidget);
    expect(controls(tester).controller, same(previous));
    expect(previous.value.position, const Duration(seconds: 7));
    expectNoAnalysisResults();
    final restore = find.byKey(const ValueKey('video-reset-example'));
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(platform.sources.last.sourceType, DataSourceType.asset);
    expect(find.text('chosen.mp4'), findsNothing);
    expect(controls(tester).controller, isNot(same(previous)));
    expectNoAnalysisResults();
    await checkFullscreen(tester, expectedTitle: 'Örnek video — analiz edilmedi');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Aday açılana kadar çalışan örnek ve konumu korunur; yalnız başarıda değiştirilir', (tester) async {
    await mount(tester, (_) async => XFile('candidate.mp4'));
    final previous = controls(tester).controller;
    await previous.seekTo(const Duration(seconds: 6));
    await previous.play();
    await tester.pump();
    platform.holdInitialize = true;
    await pickFromGallery(tester, 'Video seç');
    expect(controls(tester).controller, same(previous));
    expect(previous.value.isPlaying, isTrue);
    expect(previous.value.position, const Duration(seconds: 6));
    expectNoAnalysisResults();
    expect(find.byKey(const ValueKey('video-opening')), findsOneWidget);
    expect(find.text('candidate.mp4'), findsNothing);
    expect(find.text('Video açıldı.'), findsNothing);
    expect(platform.calls, isNot(contains('dispose:0')));
    expect(controls(tester).onFullscreenToggle, isNull);
    platform.ready(1);
    await tester.pumpAndSettle();
    expect(controls(tester).controller, isNot(same(previous)));
    expect(platform.calls, containsAllInOrder(['initialized:1', 'dispose:0', 'disposed:0']));
    expect(find.text('candidate.mp4'), findsOneWidget);
    expect(find.text('Video açıldı.'), findsOneWidget);
    expectNoAnalysisResults();
    await close(tester);
  });

  testWidgets('Başarısız aday kapanır; çalışan kullanıcı videosu, seçimi ve konumu korunur', (tester) async {
    var selected = 'working.mp4';
    await mount(tester, (_) async => XFile(selected));
    await pickFromGallery(tester, 'Video seç');
    // Önceki başarılı yüklemenin bildirimi yeni başarısız denemeyle karışmasın.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    final previous = controls(tester).controller;
    await previous.seekTo(const Duration(seconds: 7));
    await previous.play();
    await tester.pump();
    selected = 'broken.mov';
    platform.failInitialize = true;
    await pickFromGallery(tester, 'Video değiştir');
    expect(platform.calls, containsAllInOrder(['dispose:2', 'disposed:2']));
    expect(platform.calls, isNot(contains('dispose:1')));
    expect(controls(tester).controller, same(previous));
    expect(previous.value.isPlaying, isTrue);
    expect(previous.value.position, const Duration(seconds: 7));
    expect(find.text('working.mp4'), findsOneWidget);
    expect(find.text('broken.mov'), findsNothing);
    expect(find.byKey(const ValueKey('video-open-error')), findsOneWidget);
    expect(find.text('Video açıldı.'), findsNothing);
    expect(find.byKey(const ValueKey('video-opening')), findsNothing);
    expectNoAnalysisResults();
    await previous.pause();
    await close(tester);
  });

  testWidgets('Seçici iptali veya hatası çalışan videoyu değiştirmez; aday oluşturulmaz', (tester) async {
    var failPicker = false;
    await mount(tester, (_) async {
      if (failPicker) throw StateError('Kontrollü seçici hatası');
      return null;
    });
    final previous = controls(tester).controller;
    await previous.seekTo(const Duration(seconds: 6));
    await pickFromGallery(tester, 'Video seç');
    expect(controls(tester).controller, same(previous));
    expect(find.byKey(const ValueKey('video-open-error')), findsNothing);
    expect(platform.sources, hasLength(1));
    failPicker = true;
    await pickFromGallery(tester, 'Video seç');
    expect(controls(tester).controller, same(previous));
    expect(previous.value.position, const Duration(seconds: 6));
    expectNoAnalysisResults();
    expect(platform.sources, hasLength(1));
    expect(find.text('Video seçilemedi. Mevcut videonuz korundu; tekrar deneyin.'), findsOneWidget);
    expect(find.text('Video açıldı.'), findsNothing);
    await close(tester);
  });

  testWidgets('Örnek açılamazsa yükleme biter; iptal hatayı korur ve yeniden deneme açar', (tester) async {
    platform.failInitialize = true;
    await mount(tester, (_) async => null);
    expect(platform.calls, containsAllInOrder(['dispose:0', 'disposed:0']));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(FloatingVideoControls), findsNothing);
    final error = tester.widget<Text>(find.byKey(const ValueKey('video-open-error'))).data;
    expect(error, contains('Örnek video açılamadı'));
    expect(find.byKey(const ValueKey('video-retry-example')), findsOneWidget);
    await pickFromGallery(tester, 'Video seç');
    expect(platform.sources, hasLength(1));
    expect(tester.widget<Text>(find.byKey(const ValueKey('video-open-error'))).data, error);
    platform.failInitialize = false;
    final retry = find.byKey(const ValueKey('video-retry-example'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(platform.sources, hasLength(2));
    expect(platform.sources.last.sourceType, DataSourceType.asset);
    expect(find.byType(FloatingVideoControls), findsOneWidget);
    expect(find.byKey(const ValueKey('video-open-error')), findsNothing);
    expect(find.text('Video açıldı.'), findsNothing);
    await close(tester);
  });

  testWidgets('Örnek hatasından sonra kullanıcı videosu seçilebilir; örnek rapor aktarılmaz', (tester) async {
    platform.failInitialize = true;
    await mount(tester, (_) async => XFile('recovery.mp4'));
    platform.failInitialize = false;
    await pickFromGallery(tester, 'Video seç');
    expect(find.text('recovery.mp4'), findsOneWidget);
    expect(find.byKey(const ValueKey('video-open-error')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expectNoAnalysisResults();
    await close(tester);
  });

  testWidgets('Örneğe dönüş başarısızsa kullanıcı videosu ve analiz edilmedi açıklaması korunur', (tester) async {
    await mount(tester, (_) async => XFile('keep.mp4'));
    await pickFromGallery(tester, 'Video seç');
    final previous = controls(tester).controller;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    platform.failInitialize = true;
    final restore = find.byKey(const ValueKey('video-reset-example'));
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(controls(tester).controller, same(previous));
    expect(find.text('keep.mp4'), findsOneWidget);
    expect(platform.calls, contains('disposed:2'));
    expect(platform.calls, isNot(contains('dispose:1')));
    expect(find.textContaining('Örnek video açılamadı'), findsOneWidget);
    expectNoAnalysisResults();
    await close(tester);
  });

  testWidgets('Eski seçicinin geç cevabı yeni seçimi değiştirmez ve oynatıcı oluşturmaz', (tester) async {
    final latePick = Completer<XFile?>();
    var selections = 0;
    await mount(tester, (_) {
      selections++;
      return selections == 1 ? latePick.future : Future.value(XFile('new.mp4'));
    });
    await pickFromGallery(tester, 'Video seç');
    await pickFromGallery(tester, 'Video seç');
    final current = controls(tester).controller;
    expect(find.text('new.mp4'), findsOneWidget);
    latePick.complete(XFile('late.mp4'));
    await tester.pumpAndSettle();
    expect(platform.sources, hasLength(2));
    expect(controls(tester).controller, same(current));
    expect(find.text('new.mp4'), findsOneWidget);
    expect(find.text('late.mp4'), findsNothing);
    expectNoAnalysisResults();
    await close(tester);
  });

  testWidgets('Eski adayın geç açılması veya hatası yeni videoya taşınmaz; aday yalnız bir kez kapanır', (tester) async {
    var selected = 'slow.mp4';
    await mount(tester, (_) async => XFile(selected));
    platform.holdInitialize = true;
    await pickFromGallery(tester, 'Video seç');
    platform.holdInitialize = false;
    selected = 'latest.mp4';
    await pickFromGallery(tester, 'Video seç');
    final current = controls(tester).controller;
    expect(platform.calls, contains('disposed:1'));
    platform.ready(1);
    platform.fail(1);
    await tester.pumpAndSettle();
    expect(controls(tester).controller, same(current));
    expect(find.text('latest.mp4'), findsOneWidget);
    expect(find.text('slow.mp4'), findsNothing);
    expect(find.byKey(const ValueKey('video-open-error')), findsNothing);
    expectNoAnalysisResults();
    await close(tester);
  });

  testWidgets('Bekleyen ilk örnek yeni kullanıcı videosunu geri alamaz', (tester) async {
    platform.holdInitialize = true;
    await mount(tester, (_) async => XFile('first.mp4'), settle: false);
    expect(platform.sources, hasLength(1));
    platform.holdInitialize = false;
    // İlk örnek hâlâ yüklenirken pumpAndSettle kullanmadan kaynağı seç.
    final upload = find.text('Video seç');
    await tester.ensureVisible(upload);
    await tester.tap(upload);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Galeri'));
    await tester.pumpAndSettle();
    final current = controls(tester).controller;
    platform.ready(0);
    await tester.pumpAndSettle();
    expect(controls(tester).controller, same(current));
    expect(find.text('first.mp4'), findsOneWidget);
    expectNoAnalysisResults();
    await close(tester);
  });

  for (final leaveScreen in [false, true]) {
    testWidgets('Geç native oluşturma ${leaveScreen ? 'kapanmış ekranı' : 'daha yeni seçimi'} etkilemez', (tester) async {
      var selected = 'late-create.mp4';
      await mount(tester, (_) async => XFile(selected));
      platform.holdCreate = true;
      await pickFromGallery(tester, 'Video seç');
      expect(platform.createGates.containsKey(1), isTrue);
      platform.holdCreate = false;
      selected = 'newest.mp4';
      if (leaveScreen) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } else {
        await pickFromGallery(tester, 'Video seç');
        expect(find.text('newest.mp4'), findsOneWidget);
      }
      expect(platform.calls, isNot(contains('dispose:1')),
          reason: 'video_player native oluşturma cevabını almadan kapatamaz.');
      platform.createGates[1]!.complete();
      await tester.pumpAndSettle();
      expect(platform.calls, contains('disposed:1'));
      expect(find.text('late-create.mp4'), findsNothing);
      if (leaveScreen) {
        expect(find.text('Video açıldı.'), findsNothing);
        expect(tester.takeException(), isNull);
      } else {
        expect(find.text('newest.mp4'), findsOneWidget);
        expectNoAnalysisResults();
      }
      await close(tester);
    });
  }

  testWidgets('Ekran kapandıktan sonra seçici cevabı işlenmez', (tester) async {
    final latePick = Completer<XFile?>();
    await mount(tester, (_) => latePick.future);
    await pickFromGallery(tester, 'Video seç');
    await close(tester);
    latePick.complete(XFile('after-exit.mp4'));
    await tester.pumpAndSettle();
    expect(platform.sources, hasLength(1));
    expect(find.text('Video açıldı.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ekran kapanınca bekleyen aday ve çalışan video kapanır; geç olay hata oluşturmaz', (tester) async {
    await mount(tester, (_) async => XFile('pending.mp4'));
    platform.holdInitialize = true;
    await pickFromGallery(tester, 'Video seç');
    await close(tester);
    platform.ready(1);
    platform.fail(1);
    await tester.pumpAndSettle();
    expect(find.text('Video açıldı.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
