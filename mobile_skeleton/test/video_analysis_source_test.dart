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

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = sources.length;
    sources.add(options.dataSource);
    final stream = StreamController<VideoEvent>(onCancel: () async {});
    // done Future'ını abonelik iptal edilmeden testin kendi alanında oluştur.
    // Aksi halde dispose içindeki close(), iptal edilmiş akış için SDK'nın
    // root zone'daki ortak Future'ını döndürür; pumpAndSettle onu beklemez.
    unawaited(stream.done);
    events[id] = stream;
    stream.add(VideoEvent(
      eventType: VideoEventType.initialized,
      size: const Size(640, 360),
      duration: const Duration(seconds: 120),
    ));
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

  Future<void> mount(WidgetTester tester, Future<XFile?> Function(ImageSource) pick) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: VideoAnalysisScreen(pickVideo: pick)));
    await tester.pumpAndSettle();
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
        reason: 'Eski oynatıcı kapanmadan seçim state güncellemesine ulaşamaz.');
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
}
