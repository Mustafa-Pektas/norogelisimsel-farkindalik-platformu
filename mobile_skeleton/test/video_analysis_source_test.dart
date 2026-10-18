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
      {bool settle = true}) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: VideoAnalysisScreen(pickVideo: pick)));
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

  void expectNoCustomResults() {
    expect(find.byKey(const ValueKey('video-not-analyzed')), findsOneWidget);
    expect(find.byKey(const ValueKey('video-example-report')), findsNothing);
    expect(find.byType(ExpandableFindingCard), findsNothing);
    expect(find.byType(FindingNotificationPill), findsNothing);
    expect(find.text('Önemli Anlar'), findsNothing);
    expect(find.textContaining('Kanıt Noktası'), findsNothing);
    expect(find.textContaining('Risk Saptanmadı'), findsNothing);
    expect(find.text('Videoyu Analiz Et'), findsNothing);
    expect(find.text('Analiz Aşamaları'), findsNothing);
  }

  FloatingVideoControls controls(WidgetTester tester) =>
      tester.widget<FloatingVideoControls>(find.byType(FloatingVideoControls));

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    for (var id = 0; id < platform.sources.length; id++) {
      expect(platform.calls.where((call) => call == 'dispose:$id'), hasLength(1));
      expect(platform.calls, contains('disposed:$id'));
    }
    expect(tester.takeException(), isNull);
  }

  testWidgets('Sabit rapor örnektir; seçilen videoya ve tam ekrana taşınmaz', (tester) async {
    final selections = <ImageSource>[];
    await mount(tester, (source) async {
      selections.add(source);
      return XFile('selected.mp4');
    });
    expect(find.textContaining('Örnek rapor — sabit örnek bulgulardır'), findsOneWidget);
    expect(find.byType(ExpandableFindingCard), findsNWidgets(5));
    // Önce örnek videodaki bir bildirim etkinleştirilir; sonraki videoya sızmamalı.
    final old = tester.widget<FloatingVideoControls>(find.byType(FloatingVideoControls)).controller;
    await old.seekTo(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(tester.widget<FindingNotificationPill>(find.byType(FindingNotificationPill)).isVisible, isTrue);
    await pickFromGallery(tester, 'Video Yükle');
    expect(selections, [ImageSource.gallery]);
    expect(platform.sources.last.sourceType, DataSourceType.file);
    expect(platform.calls, containsAllInOrder(['dispose:0', 'disposed:0']),
        reason: 'Başarılı değişimden sonra önceki oynatıcı kapatılmalı.');
    expect(platform.calls, containsAllInOrder(['initialized:1', 'dispose:0']));
    expect(find.text('Video yüklendi.'), findsOneWidget);
    expectNoCustomResults();

    final controls = tester.widget<FloatingVideoControls>(find.byType(FloatingVideoControls));
    await controls.controller.seekTo(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expectNoCustomResults();
    final play = find.widgetWithIcon(IconButton, Icons.play_arrow_rounded);
    await tester.ensureVisible(play);
    await tester.tap(play);
    await tester.pump();
    expect(platform.calls, contains('play:1'));
    await controls.controller.pause();
    await tester.pump(const Duration(seconds: 3));
    expectNoCustomResults();

    controls.onFullscreenToggle!();
    await tester.pumpAndSettle();
    final fullscreen = tester.widget<FullscreenVideoScreen>(find.byType(FullscreenVideoScreen));
    expect(fullscreen.controller, same(controls.controller));
    expect(fullscreen.findings, isEmpty);
    expect(fullscreen.title, contains('analiz edilmedi'));
    final exitFullscreen = find.descendant(
      of: find.byType(FullscreenVideoScreen),
      matching: find.widgetWithIcon(IconButton, Icons.fullscreen_exit_rounded),
    );
    expect(exitFullscreen, findsOneWidget);
    await tester.tap(exitFullscreen);
    await tester.pumpAndSettle();
    expect(find.byType(FullscreenVideoScreen), findsNothing);
    expect(find.text('selected.mp4'), findsOneWidget);
    expect(tester.widget<FloatingVideoControls>(find.byType(FloatingVideoControls)).controller,
        same(controls.controller));
    expectNoCustomResults();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Seçim iptalinde video korunur; örneğe dönünce rapor örnek olarak gösterilir', (tester) async {
    XFile? selection = XFile('chosen.mp4');
    await mount(tester, (_) async => selection);
    await pickFromGallery(tester, 'Video Yükle');
    expect(platform.calls, containsAllInOrder(['dispose:0', 'disposed:0']),
        reason: 'Kapanış Future’ı testin sanal zamanında tamamlanmalı.');
    expectNoCustomResults();
    final sourceCount = platform.sources.length;
    selection = null;
    await pickFromGallery(tester, 'Video Değiştir');
    expect(platform.sources, hasLength(sourceCount));
    expect(find.text('chosen.mp4'), findsOneWidget);
    expectNoCustomResults();
    final restore = find.byTooltip('Örnek Video');
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(platform.sources.last.sourceType, DataSourceType.asset);
    expect(find.byKey(const ValueKey('video-example-report')), findsOneWidget);
    expect(find.byType(ExpandableFindingCard), findsNWidgets(5));
    expect(find.byKey(const ValueKey('video-not-analyzed')), findsNothing);
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
    await pickFromGallery(tester, 'Video Yükle');
    expect(controls(tester).controller, same(previous));
    expect(previous.value.isPlaying, isTrue);
    expect(previous.value.position, const Duration(seconds: 6));
    expect(find.byKey(const ValueKey('video-example-report')), findsOneWidget);
    expect(find.byKey(const ValueKey('video-opening')), findsOneWidget);
    expect(find.text('candidate.mp4'), findsNothing);
    expect(find.text('Video yüklendi.'), findsNothing);
    expect(platform.calls, isNot(contains('dispose:0')));
    expect(controls(tester).onFullscreenToggle, isNull);
    platform.ready(1);
    await tester.pumpAndSettle();
    expect(controls(tester).controller, isNot(same(previous)));
    expect(platform.calls, containsAllInOrder(['initialized:1', 'dispose:0', 'disposed:0']));
    expect(find.text('candidate.mp4'), findsOneWidget);
    expect(find.text('Video yüklendi.'), findsOneWidget);
    expectNoCustomResults();
    await close(tester);
  });

  testWidgets('Başarısız aday kapanır; çalışan kullanıcı videosu, seçimi ve konumu korunur', (tester) async {
    var selected = 'working.mp4';
    await mount(tester, (_) async => XFile(selected));
    await pickFromGallery(tester, 'Video Yükle');
    // Önceki başarılı yüklemenin bildirimi yeni başarısız denemeyle karışmasın.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    final previous = controls(tester).controller;
    await previous.seekTo(const Duration(seconds: 7));
    await previous.play();
    await tester.pump();
    selected = 'broken.mov';
    platform.failInitialize = true;
    await pickFromGallery(tester, 'Video Değiştir');
    expect(platform.calls, containsAllInOrder(['dispose:2', 'disposed:2']));
    expect(platform.calls, isNot(contains('dispose:1')));
    expect(controls(tester).controller, same(previous));
    expect(previous.value.isPlaying, isTrue);
    expect(previous.value.position, const Duration(seconds: 7));
    expect(find.text('working.mp4'), findsOneWidget);
    expect(find.text('broken.mov'), findsNothing);
    expect(find.byKey(const ValueKey('video-open-error')), findsOneWidget);
    expect(find.text('Video yüklendi.'), findsNothing);
    expect(find.byKey(const ValueKey('video-opening')), findsNothing);
    expectNoCustomResults();
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
    await pickFromGallery(tester, 'Video Yükle');
    expect(controls(tester).controller, same(previous));
    expect(find.byKey(const ValueKey('video-open-error')), findsNothing);
    expect(platform.sources, hasLength(1));
    failPicker = true;
    await pickFromGallery(tester, 'Video Yükle');
    expect(controls(tester).controller, same(previous));
    expect(previous.value.position, const Duration(seconds: 6));
    expect(find.byKey(const ValueKey('video-example-report')), findsOneWidget);
    expect(platform.sources, hasLength(1));
    expect(find.text('Video seçilemedi. Mevcut videonuz korundu; tekrar deneyin.'), findsOneWidget);
    expect(find.text('Video yüklendi.'), findsNothing);
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
    await pickFromGallery(tester, 'Video Yükle');
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
    expect(find.text('Video yüklendi.'), findsNothing);
    await close(tester);
  });

  testWidgets('Örnek hatasından sonra kullanıcı videosu seçilebilir; örnek rapor aktarılmaz', (tester) async {
    platform.failInitialize = true;
    await mount(tester, (_) async => XFile('recovery.mp4'));
    platform.failInitialize = false;
    await pickFromGallery(tester, 'Video Yükle');
    expect(find.text('recovery.mp4'), findsOneWidget);
    expect(find.byKey(const ValueKey('video-open-error')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expectNoCustomResults();
    await close(tester);
  });

  testWidgets('Örneğe dönüş başarısızsa kullanıcı videosu ve analiz edilmedi açıklaması korunur', (tester) async {
    await mount(tester, (_) async => XFile('keep.mp4'));
    await pickFromGallery(tester, 'Video Yükle');
    final previous = controls(tester).controller;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    platform.failInitialize = true;
    final restore = find.byTooltip('Örnek Video');
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(controls(tester).controller, same(previous));
    expect(find.text('keep.mp4'), findsOneWidget);
    expect(platform.calls, contains('disposed:2'));
    expect(platform.calls, isNot(contains('dispose:1')));
    expect(find.textContaining('Örnek video açılamadı'), findsOneWidget);
    expectNoCustomResults();
    await close(tester);
  });

  testWidgets('Eski seçicinin geç cevabı yeni seçimi değiştirmez ve oynatıcı oluşturmaz', (tester) async {
    final latePick = Completer<XFile?>();
    var selections = 0;
    await mount(tester, (_) {
      selections++;
      return selections == 1 ? latePick.future : Future.value(XFile('new.mp4'));
    });
    await pickFromGallery(tester, 'Video Yükle');
    await pickFromGallery(tester, 'Video Yükle');
    final current = controls(tester).controller;
    expect(find.text('new.mp4'), findsOneWidget);
    latePick.complete(XFile('late.mp4'));
    await tester.pumpAndSettle();
    expect(platform.sources, hasLength(2));
    expect(controls(tester).controller, same(current));
    expect(find.text('new.mp4'), findsOneWidget);
    expect(find.text('late.mp4'), findsNothing);
    expectNoCustomResults();
    await close(tester);
  });

  testWidgets('Eski adayın geç açılması veya hatası yeni videoya taşınmaz; aday yalnız bir kez kapanır', (tester) async {
    var selected = 'slow.mp4';
    await mount(tester, (_) async => XFile(selected));
    platform.holdInitialize = true;
    await pickFromGallery(tester, 'Video Yükle');
    platform.holdInitialize = false;
    selected = 'latest.mp4';
    await pickFromGallery(tester, 'Video Yükle');
    final current = controls(tester).controller;
    expect(platform.calls, contains('disposed:1'));
    platform.ready(1);
    platform.fail(1);
    await tester.pumpAndSettle();
    expect(controls(tester).controller, same(current));
    expect(find.text('latest.mp4'), findsOneWidget);
    expect(find.text('slow.mp4'), findsNothing);
    expect(find.byKey(const ValueKey('video-open-error')), findsNothing);
    expectNoCustomResults();
    await close(tester);
  });

  testWidgets('Bekleyen ilk örnek yeni kullanıcı videosunu geri alamaz', (tester) async {
    platform.holdInitialize = true;
    await mount(tester, (_) async => XFile('first.mp4'), settle: false);
    expect(platform.sources, hasLength(1));
    platform.holdInitialize = false;
    // İlk örnek hâlâ yüklenirken pumpAndSettle kullanmadan kaynağı seç.
    final upload = find.text('Video Yükle');
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
    expectNoCustomResults();
    await close(tester);
  });

  for (final leaveScreen in [false, true]) {
    testWidgets('Geç native oluşturma ${leaveScreen ? 'kapanmış ekranı' : 'daha yeni seçimi'} etkilemez', (tester) async {
      var selected = 'late-create.mp4';
      await mount(tester, (_) async => XFile(selected));
      platform.holdCreate = true;
      await pickFromGallery(tester, 'Video Yükle');
      expect(platform.createGates.containsKey(1), isTrue);
      platform.holdCreate = false;
      selected = 'newest.mp4';
      if (leaveScreen) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } else {
        await pickFromGallery(tester, 'Video Yükle');
        expect(find.text('newest.mp4'), findsOneWidget);
      }
      expect(platform.calls, isNot(contains('dispose:1')),
          reason: 'video_player native oluşturma cevabını almadan kapatamaz.');
      platform.createGates[1]!.complete();
      await tester.pumpAndSettle();
      expect(platform.calls, contains('disposed:1'));
      expect(find.text('late-create.mp4'), findsNothing);
      if (leaveScreen) {
        expect(find.text('Video yüklendi.'), findsNothing);
        expect(tester.takeException(), isNull);
      } else {
        expect(find.text('newest.mp4'), findsOneWidget);
        expectNoCustomResults();
      }
      await close(tester);
    });
  }

  testWidgets('Ekran kapandıktan sonra seçici cevabı işlenmez', (tester) async {
    final latePick = Completer<XFile?>();
    await mount(tester, (_) => latePick.future);
    await pickFromGallery(tester, 'Video Yükle');
    await close(tester);
    latePick.complete(XFile('after-exit.mp4'));
    await tester.pumpAndSettle();
    expect(platform.sources, hasLength(1));
    expect(find.text('Video yüklendi.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ekran kapanınca bekleyen aday ve çalışan video kapanır; geç olay hata oluşturmaz', (tester) async {
    await mount(tester, (_) async => XFile('pending.mp4'));
    platform.holdInitialize = true;
    await pickFromGallery(tester, 'Video Yükle');
    await close(tester);
    platform.ready(1);
    platform.fail(1);
    await tester.pumpAndSettle();
    expect(find.text('Video yüklendi.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
