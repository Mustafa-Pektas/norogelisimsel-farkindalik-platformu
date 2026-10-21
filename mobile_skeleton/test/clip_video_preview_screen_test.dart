import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/models/scenario_clip_plan.dart';
import 'package:neuro_awareness_app/screens/clip_production_plan_screen.dart';
import 'package:neuro_awareness_app/screens/clip_video_preview_screen.dart';
import 'package:neuro_awareness_app/services/clip_video_store.dart';
// Mevcut video_player paketinin platform test sınırı; yeni bağımlılık eklenmez.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

// Gerçek dosya, path_provider, video motoru veya codec çağrılmaz.
class _Store extends ClipVideoStore {
  _Store(this.binding) : super(documentsDirectory: () async {
    throw StateError('Önizleme widget testi gerçek belge dizinine erişmemeli.');
  });

  final ClipVideoBinding binding;
  bool bound = true;
  bool missing = false;
  int mutations = 0;
  Future<File>? fileGate;

  @override
  Future<Map<String, ClipVideoBinding>> loadPlan(String planId) async =>
      bound && binding.planId == planId ? {binding.clipId: binding} : {};

  @override
  Future<bool> fileExists(ClipVideoBinding binding) async => !missing;

  @override
  Future<File> fileFor(ClipVideoBinding binding) async {
    final gate = fileGate;
    if (gate != null) return await gate;
    return File('TEST_ONLY_DOCUMENTS/${binding.relativePath}');
  }

  @override
  Future<ClipVideoAttachResult> attach({required String planId, required String clipId,
      required File source, required String fileName}) async {
    mutations++;
    throw StateError('Önizleme eşlemeyi değiştirmemeli.');
  }

  @override
  Future<String?> remove({required String planId, required String clipId}) async {
    mutations++;
    throw StateError('Önizleme eşlemeyi kaldırmamalı.');
  }
}

class _VideoPlatform extends VideoPlayerPlatform {
  final calls = <String>[];
  final sources = <DataSource>[];
  final streams = <int, StreamController<VideoEvent>>{};
  final seeks = <Duration>[];
  bool holdInitialize = false;
  bool failInitialize = false;

  VideoEvent get initialized => VideoEvent(
    eventType: VideoEventType.initialized,
    size: const Size(640, 360),
    duration: const Duration(seconds: 8),
  );

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = sources.length;
    sources.add(options.dataSource);
    final stream = StreamController<VideoEvent>(
      // Async dönüş iptal Future'ını testin kendi alanında oluşturur.
      // Void dönüşte SDK'nın ortak null Future'ı kullanılır; controller.dispose
      // devamı sanal mikro görev kuyruğunun dışında kalabilir.
      onCancel: () async { calls.add('cancel:$id'); },
    );
    streams[id] = stream;
    if (failInitialize) {
      stream.addError(PlatformException(code: 'TEST_CODEC', message: 'TEST: codec error'));
    } else if (!holdInitialize) {
      stream.add(initialized);
    }
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async { calls.add('dispose:$playerId'); }

  @override
  Future<void> play(int playerId) async { calls.add('play:$playerId'); }

  @override
  Future<void> pause(int playerId) async { calls.add('pause:$playerId'); }

  @override
  Future<void> seekTo(int playerId, Duration position) async { seeks.add(position); }

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox(key: ValueKey('fake-video-surface'));
}

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
  final plan = ScenarioClipPlan.fromJsonString(sources[ClipProductionPlanScreen.d01PlanAssetPath]!);
  final clip = plan.clipsForScene('oyuncakla_oyun').single;
  late _Store store;
  late _VideoPlatform platform;
  late VideoPlayerPlatform previousPlatform;

  setUp(() {
    store = _Store(ClipVideoBinding(planId: plan.planId, clipId: clip.id,
        relativePath: 'clip_videos/import_TEST/video.mov', fileName: 'deniz.mov'));
    previousPlatform = VideoPlayerPlatform.instance;
    platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });

  tearDown(() async {
    for (final stream in platform.streams.values) { await stream.close(); }
    VideoPlayerPlatform.instance = previousPlatform;
    expect(store.mutations, 0);
  });

  Future<void> openPlan(WidgetTester tester) async {
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: _Bundle(sources),
      child: MaterialApp(home: ClipProductionPlanScreen(videoStore: store)),
    ));
    await tester.pumpAndSettle();
    final scene = find.byKey(const ValueKey('clip-scene:oyuncakla_oyun'));
    await tester.ensureVisible(scene);
    await tester.tap(find.descendant(of: scene, matching: find.text('Oyuncakla oyun')));
    await tester.pumpAndSettle();
  }

  Future<void> pushPreview(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () {
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
            ClipVideoPreviewScreen(binding: store.binding, videoStore: store)));
      }, child: const Text('Aç')),
    ))));
    await tester.tap(find.text('Aç'));
    // Bekleyen initialize için pumpAndSettle çağrılmaz; sonsuz yükleme
    // animasyonu yerine yalnız rota geçişi ve mikro görevler ilerletilir.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  Future<void> control(WidgetTester tester, String key) async {
    final button = find.byKey(ValueKey(key));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }

  testWidgets('Bağlı kopya ayrı ekranda açılır; otomatik başlamaz, oran ve kontroller korunur', (tester) async {
    await openPlan(tester);
    final preview = find.byKey(ValueKey('preview-clip-video:${clip.id}'));
    expect(find.text('Video bağlı'), findsOneWidget);
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.byType(ClipVideoPreviewScreen), findsOneWidget);
    expect(platform.sources.single.sourceType, DataSourceType.file);
    final copy = await store.fileFor(store.binding);
    expect(platform.sources.single.uri, copy.absolute.uri.toString());
    expect(platform.calls.where((call) => call.startsWith('play:')), isEmpty);
    expect(tester.widget<AspectRatio>(find.byKey(const ValueKey('clip-preview-aspect'))).aspectRatio,
        closeTo(640 / 360, 0.0001));
    expect(find.textContaining('İncelenmedi: videonun açılması'), findsOneWidget);
    await control(tester, 'clip-preview-play-pause');
    expect(platform.calls, contains('play:0'));
    expect(find.text('Duraklat'), findsOneWidget);
    await control(tester, 'clip-preview-play-pause');
    expect(platform.calls.last, 'pause:0');
    expect(find.text('Oynat'), findsOneWidget);
    await control(tester, 'clip-preview-play-pause');
    await control(tester, 'clip-preview-restart');
    expect(platform.seeks.last, Duration.zero);
    expect(find.text('Oynat'), findsOneWidget);
    await control(tester, 'clip-preview-play-pause');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(platform.calls.where((call) => call == 'dispose:0'), hasLength(1));
    expect(find.text('deniz.mov'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Eksik kopyada izleme düğmesi gösterilmez, dosya adı ve eşleme kalır', (tester) async {
    store.missing = true;
    await openPlan(tester);
    expect(find.text('Dosya bulunamadı'), findsOneWidget);
    expect(find.text('deniz.mov'), findsOneWidget);
    expect(find.byKey(ValueKey('preview-clip-video:${clip.id}')), findsNothing);
    expect(platform.sources, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bağlantı yokken izleme düğmesi gösterilmez', (tester) async {
    store.bound = false;
    await openPlan(tester);
    expect(find.text('Video yok'), findsOneWidget);
    expect(find.byKey(ValueKey('preview-clip-video:${clip.id}')), findsNothing);
    expect(platform.sources, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Listelemeden sonra kaybolan dosya anlaşılır hata verir, eşleme silinmez', (tester) async {
    await openPlan(tester);
    store.missing = true;
    final preview = find.byKey(ValueKey('preview-clip-video:${clip.id}'));
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.text('Video dosyası bulunamadı. Kayıtlı eşleme korunuyor.'), findsOneWidget);
    expect(platform.sources, isEmpty);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('deniz.mov'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Codec hatası gösterilir; geri çıkınca oluşturulan oynatıcı serbest bırakılır', (tester) async {
    platform.failInitialize = true;
    await pushPreview(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Video açılamadı.'), findsOneWidget);
    expect(find.byKey(const ValueKey('clip-preview-play-pause')), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(platform.calls.where((call) => call == 'dispose:0'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dosya çözülürken geri çıkılırsa geç sonuç oynatıcı oluşturmaz', (tester) async {
    final gate = Completer<File>();
    store.fileGate = gate.future;
    await pushPreview(tester);
    expect(find.text('Video yükleniyor…'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    gate.complete(File('TEST_ONLY_DOCUMENTS/late.mov'));
    await tester.pump();
    expect(platform.sources, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Video yüklenirken geri çıkılırsa kaynak kapanır; geç olay hata oluşturmaz', (tester) async {
    platform.holdInitialize = true;
    await pushPreview(tester);
    expect(find.text('Video yükleniyor…'), findsOneWidget);
    expect(platform.sources, hasLength(1));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(platform.calls, contains('cancel:0'));
    expect(platform.calls.where((call) => call == 'dispose:0'), hasLength(1));
    platform.streams[0]!.add(platform.initialized);
    await tester.pump();
    expect(platform.calls.where((call) => call.startsWith('play:')), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Açıldıktan sonraki oynatıcı hatası kullanıcıya gösterilir', (tester) async {
    await pushPreview(tester);
    await tester.pumpAndSettle();
    platform.streams[0]!.addError(PlatformException(code: 'TEST_PLAY', message: 'TEST: playback error'));
    // İlk pump async olayı teslim eder; dinleyici yeni bir çizim planlar.
    await tester.pump();
    // İkinci pump hata mesajını çizer; süre veya timeout artırılmaz.
    await tester.pump();
    expect(find.text('Video oynatılamadı. Kayıtlı eşleme korunuyor.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(platform.calls.where((call) => call == 'dispose:0'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
