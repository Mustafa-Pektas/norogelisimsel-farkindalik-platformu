import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:neuro_awareness_app/screens/video_analysis_screen.dart';
import 'package:neuro_awareness_app/models/video_analysis.dart';
import 'package:neuro_awareness_app/services/video_analysis_service.dart';
import 'package:neuro_awareness_app/widgets/expandable_finding_card.dart';
import 'package:neuro_awareness_app/widgets/finding_notification_pill.dart';
import 'package:neuro_awareness_app/widgets/floating_video_controls.dart';
import 'package:neuro_awareness_app/widgets/fullscreen_video_screen.dart';
// Mevcut video_player paketinin test sınırı; gerçek video motoru kullanılmaz.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _AnalysisService implements VideoAnalysisService {
  final requests = <VideoAnalysisRequest>[];
  final jobs = <_AnalysisJob>[];
  bool failStart = false;
  @override
  bool get isAvailable => true;
  @override
  String get scopeDescription => 'Kontrollü hizmet kapsamı: yalnız test davranışı.';
  @override
  VideoAnalysisJob start(VideoAnalysisRequest request) {
    if (failStart) throw StateError('Kontrollü başlangıç hatası');
    requests.add(request);
    final job = _AnalysisJob(request);
    jobs.add(job);
    addTearDown(() async {
      // done testi akışı FakeAsync içinde kapatıp kapanışı bekler.
      // Aynı done Future'ını dışarıdaki teardown'da yeniden beklemek,
      // artık ilerlemeyen FakeAsync alanına geç bir dinleyici ekler.
      if (!job.controller.isClosed) {
        await job.controller.close();
      }
    });
    return job;
  }
}

class _AnalysisJob implements VideoAnalysisJob {
  _AnalysisJob(this.request);
  final VideoAnalysisRequest request;
  // İptalden sonra bildirim gönderebilen hatalı/geç hizmeti de sınar.
  final controller = StreamController<VideoAnalysisEvent>.broadcast();
  Completer<void>? cancelGate;
  bool failCancel = false;
  int cancellations = 0;
  int disposals = 0;
  @override
  Stream<VideoAnalysisEvent> get events => controller.stream;
  void emit(VideoAnalysisPhase phase, {VideoAnalysisResult? result, String? requestId}) {
    controller.add(VideoAnalysisEvent(requestId: requestId ?? request.requestId,
      phase: phase, result: result, message: phase == VideoAnalysisPhase.error ? 'Kontrollü hizmet hatası' : null));
  }
  void complete({List<VideoBehaviorResult> findings = const [], String? videoId}) =>
      emit(VideoAnalysisPhase.completed, result: VideoAnalysisResult(
        requestId: request.requestId, videoId: videoId ?? request.videoId, findings: findings));
  @override
  Future<void> cancel() async {
    ++cancellations;
    if (cancelGate != null) await cancelGate!.future;
    if (failCancel) throw StateError('Kontrollü iptal hatası');
  }
  @override
  Future<void> dispose() async {
    ++disposals;
    final gate = cancelGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }
}

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
      VideoAnalysisService analysisService = const UnavailableVideoAnalysisService(),
      Size surfaceSize = const Size(1000, 1000), double textScale = 1}) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: VideoAnalysisScreen(pickVideo: pick, tabVisibility: tabVisibility,
        analysisService: analysisService),
    ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> pickFromGallery(WidgetTester tester, String label) async {
    final button = find.text(label);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galeri'));
    await tester.pumpAndSettle();
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
    expect(find.byTooltip('Gemini API Anahtarı'), findsNothing);
    expect(find.byIcon(Icons.key_outlined), findsNothing);
  }

  void expectNoAnalysisResults() {
    expect(find.byKey(const ValueKey('video-not-analyzed')), findsOneWidget);
    expect(find.text('Bu video analiz edilmedi. Video seçip izleyebilirsiniz; '
        'otomatik analiz bağlantısı henüz tamamlanmadı.'), findsOneWidget);
    expectNoClinicalResults();
  }

  FloatingVideoControls controls(WidgetTester tester) =>
      tester.widget<FloatingVideoControls>(find.byType(FloatingVideoControls));

  TextField ageField(WidgetTester tester) => tester.widget<TextField>(
    find.byKey(const ValueKey('video-age-months')),
  );

  String ageText(WidgetTester tester) => ageField(tester).controller!.text;

  Future<void> enterAge(WidgetTester tester, String value,
      {bool dismissKeyboard = true}) async {
    final field = find.byKey(const ValueKey('video-age-months'));
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pump();
    if (dismissKeyboard) {
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }
  }

  Future<void> checkFullscreen(WidgetTester tester, {bool expectUnanalyzed = true}) async {
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
    expect(fullscreen.title, expectUnanalyzed
        ? contains('analiz edilmedi') : isNot(contains('analiz edilmedi')));
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
    if (expectUnanalyzed) expectNoAnalysisResults();
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

  testWidgets('Yaş boş veya 12–36 dahil tam ay kabul eder; geçersiz metni sessizce dönüştürmez', (tester) async {
    await mount(tester, (_) async => null);
    expect(ageField(tester).enabled, isTrue);
    expect(ageText(tester), isEmpty);
    expect(find.text('Yaş: Bilinmiyor'), findsOneWidget);
    expect(find.textContaining('kullanıcı beyanıdır; henüz otomatik analizde kullanılmaz'), findsOneWidget);
    expect(find.textContaining('12–36 aydır; tüm aralıkta analiz desteği doğrulanmadı'), findsOneWidget);
    final current = controls(tester).controller;
    await current.seekTo(const Duration(seconds: 9));
    final sources = platform.sources.length;
    final plays = platform.calls.where((call) => call.startsWith('play:')).length;
    // Aralık proje girdisi sınırıdır; klinik yorum veya otomatik düzeltme yoktur.
    for (final value in ['12', '36', '18']) {
      await enterAge(tester, value);
      expect(ageText(tester), value);
      expect(ageField(tester).decoration!.errorText, isNull);
      expect(find.text('Yaş: $value ay'), findsOneWidget);
    }
    for (final value in ['11', '37', '0', '-1', '30.5', 'abc', '1e2']) {
      await enterAge(tester, value);
      expect(ageText(tester), value);
      expect(ageField(tester).decoration!.errorText,
          '12–36 arasında tam ay girin veya boş bırakın.');
      expect(find.byKey(const ValueKey('video-age-summary')), findsNothing);
    }
    await enterAge(tester, '');
    expect(ageField(tester).decoration!.errorText, isNull);
    expect(find.text('Yaş: Bilinmiyor'), findsOneWidget);
    expect(controls(tester).controller, same(current));
    expect(current.value.position, const Duration(seconds: 9));
    expect(current.value.isPlaying, isFalse);
    expect(platform.sources, hasLength(sources));
    expect(platform.calls.where((call) => call.startsWith('play:')), hasLength(plays));
    await current.play();
    await tester.pump();
    final playingCalls = platform.calls.where((call) => call.startsWith('play:')).length;
    await enterAge(tester, '24');
    expect(current.value.isPlaying, isTrue);
    expect(current.value.position, const Duration(seconds: 9));
    expect(platform.calls.where((call) => call.startsWith('play:')), hasLength(playingCalls));
    expect(platform.sources, hasLength(sources));
    await current.pause();
    await close(tester);
  });

  testWidgets('Rebuild ve tam ekran dönüşü aynı videoya ait yaş metnini korur', (tester) async {
    Future<XFile?> pick(ImageSource source) async => XFile('age-context.mp4');
    await mount(tester, pick);
    await pickFromGallery(tester, 'Video seç');
    await enterAge(tester, '27');
    final state = tester.state(find.byType(VideoAnalysisScreen));
    final current = controls(tester).controller;
    await current.seekTo(const Duration(seconds: 8));
    final sourceCount = platform.sources.length;
    await mount(tester, pick);
    expect(tester.state(find.byType(VideoAnalysisScreen)), same(state));
    expect(controls(tester).controller, same(current));
    expect(current.value.position, const Duration(seconds: 8));
    expect(current.value.isPlaying, isFalse);
    expect(ageText(tester), '27');
    expect(platform.sources, hasLength(sourceCount));
    await checkFullscreen(tester);
    expect(ageText(tester), '27');
    expect(find.text('Yaş: 27 ay'), findsOneWidget);
    expect(platform.sources, hasLength(sourceCount));
    await close(tester);
  });

  testWidgets('320 piksel ve büyük yazıda klavye açıkken yaş alanı ve hatası erişilir', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await mount(tester, (_) async => null,
        surfaceSize: const Size(320, 640), textScale: 2);
    final current = controls(tester).controller;
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump();
    await enterAge(tester, '2.5', dismissKeyboard: false);
    final field = find.byKey(const ValueKey('video-age-months'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(field.hitTestable(), findsOneWidget);
    expect(find.text('12–36 arasında tam ay girin veya boş bırakın.'), findsOneWidget);
    final rect = tester.getRect(field);
    final scaffold = tester.getRect(find.byType(Scaffold));
    expect(rect.bottom, lessThanOrEqualTo(scaffold.bottom - 240 + 1));
    expect(rect.top, greaterThanOrEqualTo(scaffold.top + kToolbarHeight));
    await enterAge(tester, '23', dismissKeyboard: false);
    expect(ageText(tester), '23');
    expect(ageField(tester).decoration!.errorText, isNull);
    expect(controls(tester).controller, same(current));
    expect(platform.sources, hasLength(1));
    expect(current.value.isPlaying, isFalse);
    await close(tester);
  });

  testWidgets('Sekmeden hızlı ayrılıp dönmek seçili dosyayı ve konumu koruyarak duraklatır', (tester) async {
    final visibility = ValueNotifier<bool>(true);
    addTearDown(visibility.dispose);
    await mount(tester, (_) async => XFile('retained.mp4'), tabVisibility: visibility);
    await pickFromGallery(tester, 'Video seç');
    await enterAge(tester, '28');
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
    expect(ageText(tester), '28');
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
    await checkFullscreen(tester);
    expect(ageText(tester), '28');
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
    expectNoAnalysisResults();
    // Eski örnek bildirim aralığına gidilse de klinik içerik gösterilmemeli.
    final old = tester.widget<FloatingVideoControls>(find.byType(FloatingVideoControls)).controller;
    await old.seekTo(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expectNoAnalysisResults();
    await checkFullscreen(tester);
    expect(platform.sources, hasLength(1));
    expect(platform.calls, isNot(contains('dispose:0')));
    await pickFromGallery(tester, 'Video seç');
    expect(selections, [ImageSource.gallery]);
    expect(platform.sources.last.sourceType, DataSourceType.file);
    expect(platform.calls, containsAllInOrder(['dispose:0', 'disposed:0']),
        reason: 'Başarılı değişimden sonra önceki oynatıcı kapatılmalı.');
    expect(platform.calls, containsAllInOrder(['initialized:1', 'dispose:0']));
    expect(find.text('Video açıldı.'), findsOneWidget);
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

    await checkFullscreen(tester);
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
    await enterAge(tester, '25');
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
    expect(ageText(tester), '25');
    expectNoAnalysisResults();
    final restore = find.byTooltip('Örnek video');
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(platform.sources.last.sourceType, DataSourceType.asset);
    expect(find.text('chosen.mp4'), findsNothing);
    expect(controls(tester).controller, isNot(same(previous)));
    expect(ageText(tester), isEmpty);
    expect(find.text('Yaş: Bilinmiyor'), findsOneWidget);
    expectNoAnalysisResults();
    await checkFullscreen(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Aday açılana kadar çalışan örnek ve konumu korunur; yalnız başarıda değiştirilir', (tester) async {
    await mount(tester, (_) async => XFile('candidate.mp4'));
    await enterAge(tester, '29');
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
    expect(ageText(tester), '29');
    expect(ageField(tester).enabled, isFalse);
    expect(find.text('candidate.mp4'), findsNothing);
    expect(find.text('Video açıldı.'), findsNothing);
    expect(platform.calls, isNot(contains('dispose:0')));
    expect(controls(tester).onFullscreenToggle, isNull);
    platform.ready(1);
    await tester.pumpAndSettle();
    expect(controls(tester).controller, isNot(same(previous)));
    expect(platform.calls, containsAllInOrder(['initialized:1', 'dispose:0', 'disposed:0']));
    expect(find.text('candidate.mp4'), findsOneWidget);
    expect(ageText(tester), isEmpty);
    expect(ageField(tester).enabled, isTrue);
    expect(find.text('Video açıldı.'), findsOneWidget);
    expectNoAnalysisResults();
    await close(tester);
  });

  testWidgets('Başarısız aday kapanır; çalışan kullanıcı videosu, seçimi ve konumu korunur', (tester) async {
    var selected = 'working.mp4';
    await mount(tester, (_) async => XFile(selected));
    await pickFromGallery(tester, 'Video seç');
    await enterAge(tester, '30.5');
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
    expect(ageText(tester), '30.5');
    expect(ageField(tester).decoration!.errorText,
        '12–36 arasında tam ay girin veya boş bırakın.');
    expect(ageField(tester).enabled, isTrue);
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
    await enterAge(tester, '24');
    final previous = controls(tester).controller;
    await previous.seekTo(const Duration(seconds: 6));
    await pickFromGallery(tester, 'Video seç');
    expect(controls(tester).controller, same(previous));
    expect(find.byKey(const ValueKey('video-open-error')), findsNothing);
    expect(ageText(tester), '24');
    expect(platform.sources, hasLength(1));
    failPicker = true;
    await pickFromGallery(tester, 'Video seç');
    expect(controls(tester).controller, same(previous));
    expect(previous.value.position, const Duration(seconds: 6));
    expect(ageText(tester), '24');
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
    expect(ageField(tester).enabled, isFalse);
    expect(ageText(tester), isEmpty);
    expect(find.byKey(const ValueKey('video-age-summary')), findsNothing);
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
    expect(ageField(tester).enabled, isTrue);
    expect(ageText(tester), isEmpty);
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
    await enterAge(tester, '21');
    final previous = controls(tester).controller;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    platform.failInitialize = true;
    final restore = find.byTooltip('Örnek video');
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(controls(tester).controller, same(previous));
    expect(find.text('keep.mp4'), findsOneWidget);
    expect(ageText(tester), '21');
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
    await enterAge(tester, '26');
    expect(platform.calls, contains('disposed:1'));
    platform.ready(1);
    platform.fail(1);
    await tester.pumpAndSettle();
    expect(controls(tester).controller, same(current));
    expect(ageText(tester), '26');
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

  Future<void> analysisTap(WidgetTester tester, String key) async {
    final notification = find.byType(SnackBar);
    if (notification.evaluate().isNotEmpty) {
      await tester.drag(notification, Offset(0, tester.getSize(notification).height));
      await tester.pumpAndSettle();
    }
    final button = find.byKey(ValueKey(key));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('Bağlı olmayan hizmet sonuç veya analiz başlatma üretmez', (tester) async {
    await mount(tester, (_) async => null);
    expect(find.byKey(const ValueKey('video-analysis-start')), findsNothing);
    expect(find.text('Analiz hizmeti bağlı değil'), findsOneWidget);
    expect(find.text('Analiz sonuçları'), findsNothing);
    await close(tester);
  });

  testWidgets('Analiz isteği sabittir; durumlar hizmetten gelir ve çift başlatma engellenir', (tester) async {
    final service = _AnalysisService();
    await mount(tester, (_) async => null, analysisService: service);
    await enterAge(tester, '24');
    final player = controls(tester).controller;
    await analysisTap(tester, 'video-analysis-start');
    final request = service.requests.single;
    expect(request.sourceKind, VideoSourceKind.asset);
    expect(request.source, player.dataSource);
    expect(request.duration, player.value.duration);
    expect(request.ageMonths, 24);
    expect(find.text('Hizmet bildirimi bekleniyor'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('video-analysis-start'))).onPressed, isNull);
    expect(ageField(tester).enabled, isFalse);
    await tester.tap(find.byKey(const ValueKey('video-analysis-start')));
    await tester.pump();
    expect(service.requests, hasLength(1));
    final job = service.jobs.single;
    expect(job.controller.hasListener, isTrue);
    job.emit(VideoAnalysisPhase.sending);
    // Asenkron olay setState'i mikro görevde çalıştırır. İlk pump yalnız
    // olayı teslim edebilir; planlanan ekran karesini de tamamla.
    await tester.pumpAndSettle();
    expect(find.text('Gönderiliyor'), findsOneWidget);
    job.emit(VideoAnalysisPhase.processing);
    await tester.pumpAndSettle();
    expect(find.text('İşleniyor'), findsOneWidget);
    job.complete();
    await tester.pumpAndSettle();
    expect(find.text('Tamamlandı'), findsOneWidget);
    expect(find.textContaining('bu, davranışın gözlenmediği anlamına gelmez'), findsOneWidget);
    expect(job.disposals, 1);
    expect(job.cancellations, 0);
    expect(controls(tester).controller, same(player));
    await enterAge(tester, '25');
    expect(request.ageMonths, 24);
    expect(find.text('Analiz sonuçları'), findsNothing);
    await close(tester);
  });

  testWidgets('Geçersiz yaş analizi engeller; boş yaş bilinmiyor olarak gönderilir', (tester) async {
    final service = _AnalysisService();
    await mount(tester, (_) async => null, analysisService: service);
    await enterAge(tester, '37');
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('video-analysis-start'))).onPressed, isNull);
    expect(service.requests, isEmpty);
    await enterAge(tester, '');
    await analysisTap(tester, 'video-analysis-start');
    expect(service.requests.single.ageMonths, isNull);
    await close(tester);
    expect(service.jobs.single.cancellations, 1);
    expect(service.jobs.single.disposals, 1);
  });

  testWidgets('Video açılamadığında analiz kapalıdır; örnek yeniden açılabilir', (tester) async {
    final service = _AnalysisService();
    platform.failInitialize = true;
    await mount(tester, (_) async => null, analysisService: service);
    expect(find.text('Video seçilmedi. Önce bir video açın.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('video-analysis-start'))).onPressed, isNull);
    expect(service.requests, isEmpty);
    platform.failInitialize = false;
    await analysisTap(tester, 'video-retry-example');
    expect(find.text('Analize hazır'), findsOneWidget);
    await close(tester);
  });

  testWidgets('Dört gözlem durumu ve kanıt: dar ekranda aynı oynatıcı duraklayarak ilgili zamana gider', (tester) async {
    final service = _AnalysisService();
    await mount(tester, (_) async => null, analysisService: service,
      surfaceSize: const Size(320, 800), textScale: 2);
    final player = controls(tester).controller;
    await analysisTap(tester, 'video-analysis-start');
    service.jobs.single.complete(findings: [
      for (final (index, status) in ObservationStatus.values.indexed)
        VideoBehaviorResult(behaviorId: 'D01', cardVersion: '0.2', status: status,
          explanation: 'Hizmet gerekçesi $index',
          evidence: index == 0
              ? const AnalysisEvidence(startSeconds: 1.25, endSeconds: 3, timeSource: 'Ölçülmüş medya zamanı')
              : index == 1
                  ? const AnalysisEvidence(startSeconds: 8, endSeconds: 7, timeSource: 'Geçersiz')
                  : index == 2
                      ? const AnalysisEvidence(startSeconds: 1, endSeconds: 121, timeSource: 'Süre dışı')
                      : const AnalysisEvidence(startSeconds: double.nan, endSeconds: 3, timeSource: 'Bilinmiyor'),
          confidence: index == 0
              ? const AnalysisConfidence(value: 0, scale: '0–1', meaning: 'Hizmetin yöntem skoru', source: 'Kontrollü hizmet')
              : null),
    ]);
    await tester.pumpAndSettle();
    for (final status in ObservationStatus.values) {
      expect(find.text(status.label), findsOneWidget);
    }
    expect(find.textContaining('Güven: 0.0'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    for (final index in [1, 2, 3]) {
      expect(find.byKey(ValueKey('video-analysis-evidence-$index')), findsNothing);
    }
    await player.play();
    await tester.pump();
    await analysisTap(tester, 'video-analysis-evidence-0');
    expect(player.value.isPlaying, isFalse);
    expect(player.value.position, const Duration(milliseconds: 1250));
    expect(controls(tester).controller, same(player));
    expect(platform.sources, hasLength(1));
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  for (final failure in ['start', 'event', 'stream', 'done', 'identity', 'request']) {
    testWidgets('Analiz hatası açık gösterilir: $failure', (tester) async {
      final service = _AnalysisService()..failStart = failure == 'start';
      await mount(tester, (_) async => null, analysisService: service);
      await analysisTap(tester, 'video-analysis-start');
      if (failure != 'start') {
        final job = service.jobs.single;
        expect(job.controller.hasListener, isTrue);
        switch (failure) {
          case 'event': job.emit(VideoAnalysisPhase.error);
          case 'stream': job.controller.addError(StateError('Kontrollü akış hatası'));
          case 'done':
            final closed = job.controller.close();
            // done olayı ve kapanış Future'ı FakeAsync kuyruğundadır.
            // Kuyruğu ilerletmeden closed'u beklemek testi kilitler.
            await tester.pumpAndSettle();
            await closed;
            expect(job.controller.isClosed, isTrue);
            expect(job.controller.hasListener, isFalse);
          case 'identity': job.complete(videoId: 'başka-video');
          case 'request': job.emit(VideoAnalysisPhase.processing, requestId: 'başka-istek');
        }
        await tester.pumpAndSettle();
        expect(job.disposals, 1);
      }
      expect(find.text('Hata'), findsOneWidget);
      expect(find.byKey(const ValueKey('video-analysis-error')), findsOneWidget);
      expect(find.text('Tamamlandı'), findsNothing);
      expect(find.text('Analiz sonuçları'), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('video-analysis-start'))).onPressed, isNotNull);
      await close(tester);
    });
  }

  testWidgets('İptal kabul edilmeden ve sonrasında geç tamamlanma uygulanmaz', (tester) async {
    final service = _AnalysisService();
    await mount(tester, (_) async => null, analysisService: service);
    await analysisTap(tester, 'video-analysis-start');
    final first = service.jobs.single;
    first.cancelGate = Completer<void>();
    await analysisTap(tester, 'video-analysis-cancel');
    expect(find.text('İptal bekleniyor'), findsOneWidget);
    expect(first.cancellations, 1);
    expect(first.disposals, 0);
    expect(first.controller.hasListener, isFalse);
    first.complete();
    await tester.pumpAndSettle();
    expect(find.text('Tamamlandı'), findsNothing);
    first.cancelGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('İptal edildi'), findsOneWidget);
    expect(first.disposals, 1);
    await analysisTap(tester, 'video-analysis-start');
    first.complete();
    await tester.pumpAndSettle();
    expect(service.jobs, hasLength(2));
    expect(find.text('Tamamlandı'), findsNothing);
    await close(tester);
    service.jobs.last.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Hizmet iptal hatası başarı gibi sunulmaz', (tester) async {
    final service = _AnalysisService();
    await mount(tester, (_) async => null, analysisService: service);
    await analysisTap(tester, 'video-analysis-start');
    service.jobs.single.failCancel = true;
    await analysisTap(tester, 'video-analysis-cancel');
    expect(find.text('Sonuç takibi durduruldu; hizmetin iptali doğrulanamadı.'), findsOneWidget);
    expect(find.text('İptal edildi'), findsNothing);
    expect(service.jobs.single.cancellations, 1);
    expect(service.jobs.single.disposals, 1);
    await close(tester);
  });

  testWidgets('İptal beklenirken kapanış yerel kaynakları serbest bırakır', (tester) async {
    final service = _AnalysisService();
    await mount(tester, (_) async => null, analysisService: service);
    await analysisTap(tester, 'video-analysis-start');
    final job = service.jobs.single;
    job.cancelGate = Completer<void>();
    await analysisTap(tester, 'video-analysis-cancel');
    expect(job.cancellations, 1);
    expect(job.cancelGate!.isCompleted, isFalse);
    expect(job.disposals, 0);
    expect(job.controller.hasListener, isFalse);
    await close(tester);
    expect(job.cancellations, 1);
    expect(job.disposals, 1);
    job.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sekme dönüşü analiz isteğini ve sonucu korur; oynatma başlamaz', (tester) async {
    final service = _AnalysisService();
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await mount(tester, (_) async => null, analysisService: service, tabVisibility: visible);
    await enterAge(tester, '24');
    final player = controls(tester).controller;
    await player.seekTo(const Duration(seconds: 7));
    await player.play();
    await analysisTap(tester, 'video-analysis-start');
    visible.value = false;
    await tester.pumpAndSettle();
    service.jobs.single.complete();
    await tester.pumpAndSettle();
    visible.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Tamamlandı'), findsOneWidget);
    expect(controls(tester).controller, same(player));
    expect(player.value.isPlaying, isFalse);
    expect(player.value.position, const Duration(seconds: 7));
    expect(ageText(tester), '24');
    expect(service.requests, hasLength(1));
    await checkFullscreen(tester, expectUnanalyzed: false);
    expect(find.text('Tamamlandı'), findsOneWidget);
    await close(tester);
  });

  testWidgets('Seçim iptali ve açılış hatası video/yaş/sonucu korur; başarılı değişim temizler', (tester) async {
    final service = _AnalysisService();
    XFile? selection;
    await mount(tester, (_) async => selection, analysisService: service);
    await enterAge(tester, '30');
    final player = controls(tester).controller;
    await analysisTap(tester, 'video-analysis-start');
    service.jobs.single.complete(findings: const [VideoBehaviorResult(
      behaviorId: 'D01', cardVersion: '0.2', status: ObservationStatus.uncertain,
      explanation: 'Korunacak hizmet cevabı')]);
    await tester.pumpAndSettle();
    await pickFromGallery(tester, 'Video seç');
    expect(find.text('Korunacak hizmet cevabı'), findsOneWidget);
    selection = XFile('fail.mp4');
    platform.failInitialize = true;
    await pickFromGallery(tester, 'Video seç');
    expect(controls(tester).controller, same(player));
    expect(ageText(tester), '30');
    expect(find.text('Korunacak hizmet cevabı'), findsOneWidget);
    platform.failInitialize = false;
    selection = XFile('success.mp4');
    await pickFromGallery(tester, 'Video seç');
    expect(ageText(tester), isEmpty);
    expect(find.text('Analiz sonuçları'), findsNothing);
    await analysisTap(tester, 'video-analysis-start');
    expect(service.requests.last.videoId, isNot(service.requests.first.videoId));
    expect(service.requests.last.sourceKind, VideoSourceKind.file);
    expect(service.requests.last.ageMonths, isNull);
    await close(tester);
  });

  testWidgets('Başarılı video değişimi eski işi iptal eder; geç sonuç taşınmaz', (tester) async {
    final service = _AnalysisService();
    await mount(tester, (_) async => XFile('new.mp4'), analysisService: service);
    await analysisTap(tester, 'video-analysis-start');
    final old = service.jobs.single;
    await pickFromGallery(tester, 'Video seç');
    expect(old.cancellations, 1);
    expect(old.disposals, 1);
    old.complete();
    await tester.pumpAndSettle();
    expect(find.text('Tamamlandı'), findsNothing);
    expect(find.text('Analize hazır'), findsOneWidget);
    expect(find.text('new.mp4'), findsOneWidget);
    await close(tester);
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
