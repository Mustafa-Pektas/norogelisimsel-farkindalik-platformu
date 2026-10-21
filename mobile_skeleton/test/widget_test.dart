import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/main.dart';
import 'package:neuro_awareness_app/models/behavior_cards.dart';
import 'package:neuro_awareness_app/screens/home_screen.dart';
import 'package:neuro_awareness_app/screens/ontology_detail_screen.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_import_screen.dart';
import 'package:neuro_awareness_app/screens/synthetic_video_studio_screen.dart';
import 'package:neuro_awareness_app/screens/video_analysis_screen.dart';
import 'package:neuro_awareness_app/widgets/floating_video_controls.dart';
import 'package:neuro_awareness_app/widgets/age_slider_card.dart';
// Mevcut testlerdeki platform sınırları; gerçek dosya/model/video motoru yok.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _NoDocuments extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      throw StateError('Ana panel testi model dosyasına erişmemeli.');
}

class _VideoPlatform extends VideoPlayerPlatform {
  int players = 0;
  int plays = 0;
  int pauses = 0;
  final positions = <int, Duration>{};

  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => players++;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(VideoEvent(
    eventType: VideoEventType.initialized,
    size: const Size(640, 360),
    duration: const Duration(seconds: 120),
  ));
  @override
  Future<void> dispose(int playerId) async {}
  @override
  Future<void> play(int playerId) async { plays++; }
  @override
  Future<void> pause(int playerId) async { pauses++; }
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
  late PathProviderPlatform originalPaths;
  late VideoPlayerPlatform originalVideo;
  late _VideoPlatform video;

  setUp(() {
    originalPaths = PathProviderPlatform.instance;
    originalVideo = VideoPlayerPlatform.instance;
    PathProviderPlatform.instance = _NoDocuments();
    video = _VideoPlatform();
    VideoPlayerPlatform.instance = video;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  tearDown(() {
    PathProviderPlatform.instance = originalPaths;
    VideoPlayerPlatform.instance = originalVideo;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const NeuroAwarenessApp());
    await tester.pumpAndSettle();
  }

  Finder dashboardEntry(String title) => find.descendant(
    of: find.byType(SingleChildScrollView).first,
    matching: find.text(title),
  );

  Finder destination(String label) => find.byWidgetPredicate(
    (widget) => widget is NavigationDestination && widget.label == label,
  );

  void expectTab(WidgetTester tester, int index) {
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, index);
    final stack = tester.widget<IndexedStack>(find.byWidgetPredicate(
      (widget) => widget is IndexedStack &&
          widget.children.any((child) => child is VideoAnalysisScreen),
    ));
    expect(stack.index, index);
    if (index == 1) {
      expect(stack.children[index], isA<VideoAnalysisScreen>());
      expect(find.byType(VideoAnalysisScreen), findsOneWidget);
    } else if (index == 2) {
      expect(stack.children[index], isA<SyntheticVideoStudioScreen>());
      expect(find.byType(SyntheticVideoStudioScreen), findsOneWidget);
    }
  }

  Future<void> close(WidgetTester tester, {int expectedPlays = 0}) async {
    expect(video.players, 1);
    expect(video.plays, expectedPlays);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> toggleBehaviorSection(WidgetTester tester, String title) async {
    final heading = find.text(title);
    await tester.ensureVisible(heading);
    await tester.tap(heading);
    await tester.pumpAndSettle();
  }


  for (final exit in ['alt sekme', 'sistem geri', 'aynı karede geri dönüş']) {
    testWidgets('Video Analizi: $exit duraklatır; dönüş aynı oynatıcı ve konumu korur', (tester) async {
      await mount(tester);
      await tester.tap(destination('Video Analizi'));
      await tester.pumpAndSettle();
      final videoScreen = tester.state(find.byType(VideoAnalysisScreen));
      final current = tester.widget<FloatingVideoControls>(
        find.byType(FloatingVideoControls),
      ).controller;
      await current.seekTo(const Duration(seconds: 6));
      await current.play();
      await tester.pump();
      expect(current.value.isPlaying, isTrue);
      final plays = video.plays;
      final pauses = video.pauses;
      if (exit == 'sistem geri') {
        await tester.binding.handlePopRoute();
      } else if (exit == 'aynı karede geri dönüş') {
        final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
        nav.onDestinationSelected!(0);
        nav.onDestinationSelected!(1);
      } else {
        await tester.tap(destination('Ana\u00A0Panel'));
      }
      await tester.pumpAndSettle();
      expect(current.value.isPlaying, isFalse);
      expect(current.value.position, const Duration(seconds: 6));
      expect(video.pauses, greaterThan(pauses));
      expect(video.plays, plays);
      if (exit != 'aynı karede geri dönüş') {
        expectTab(tester, 0);
        await tester.tap(destination('Video Analizi'));
        await tester.pumpAndSettle();
      }
      expectTab(tester, 1);
      expect(tester.state(find.byType(VideoAnalysisScreen)), same(videoScreen));
      expect(tester.widget<FloatingVideoControls>(
        find.byType(FloatingVideoControls),
      ).controller, same(current));
      expect(current.value.isPlaying, isFalse);
      expect(current.value.position, const Duration(seconds: 6));
      expect(video.players, 1);
      expect(video.plays, plays);
      final play = find.widgetWithIcon(IconButton, Icons.play_arrow_rounded);
      await tester.ensureVisible(play);
      await tester.tap(play);
      await tester.pump();
      expect(current.value.isPlaying, isTrue);
      expect(video.plays, plays + 1);
      await current.pause();
      await close(tester, expectedPlays: plays + 1);
    });
  }

  testWidgets('Ana panelde tam olarak D01–D10 gösterilir; eski eşik ve norm kartları yoktur', (tester) async {
    await mount(tester);
    final tiles = tester.widgetList<ListTile>(find.byWidgetPredicate(
      (widget) => widget is ListTile &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('behavior-card:'),
    )).toList();
    expect(tiles, hasLength(10));
    expect(find.text('Davranışları tanıyın'), findsOneWidget);
    expect(find.text('Videolarda incelenen davranışlar hakkında bilgi edinin.'), findsOneWidget);
    expect(find.textContaining('Kart sürümü'), findsNothing);
    expect(find.textContaining(BehaviorCards.sourceName), findsNothing);
    expect(find.textContaining('İlk teknik pilot'), findsNothing);
    for (var i = 0; i < 10; i++) {
      final card = BehaviorCards.all[i];
      expect(tiles[i].key, ValueKey('behavior-card:D${(i + 1).toString().padLeft(2, '0')}'));
      expect((tiles[i].title! as Text).data, card.title);
      expect((tiles[i].subtitle! as Text).data, card.summary);
    }
    expect(find.text('12 Hedef Davranış & Yaş Normları'), findsNothing);
    expect(find.textContaining('Gözlem Eşiği:'), findsNothing);
    expect(find.textContaining('Beklenen:'), findsNothing);
    expect(find.textContaining('ONT-'), findsNothing);
    expect(find.text('Şablon yaşı'), findsNothing);
    expect(find.byType(AgeSliderCard), findsNothing);
    expect(find.textContaining('Yaş seçimi yalnız Şablon örnekleri içindir'), findsNothing);
    expect(dashboardEntry('Video Analizi'), findsOneWidget);
    expect(dashboardEntry('Simülasyon ve Eğitim'), findsOneWidget);
    await close(tester);
  });

  testWidgets('Sekme dönüşü ve Home rebuildi şablon üretmez; Stüdyo state ve servisleri korunur', (tester) async {
    await mount(tester);
    await tester.tap(destination('Simülasyon ve Eğitim'));
    await tester.pumpAndSettle();
    final studio = tester.state(find.byType(SyntheticVideoStudioScreen));

    void expectRetained() {
      expect(tester.state(find.byType(SyntheticVideoStudioScreen)), same(studio));
      expect(find.text('Eski şablon araçları', skipOffstage: false), findsNothing);
      for (final key in ['studio-template-examples', 'generate-template-scenario',
        'template-scenario-loading', 'template-scenario-title']) {
        expect(find.byKey(ValueKey(key), skipOffstage: false), findsNothing);
      }
    }

    expectRetained();
    await tester.tap(destination('Ana\u00A0Panel'));
    await tester.pumpAndSettle();
    expectTab(tester, 0);
    await tester.tap(destination('Simülasyon ve Eğitim'));
    await tester.pumpAndSettle();
    expectRetained();
    tester.element(find.byType(HomeScreen)).markNeedsBuild();
    await tester.pumpAndSettle();
    expectRetained();
    await close(tester);
  });

  for (final card in BehaviorCards.all) {
    testWidgets('${card.id}: kullanıcı içeriği doğru karttır; tam gözlem bilgisi debug ekip bölümündedir', (tester) async {
      await mount(tester);
      final entry = find.byKey(ValueKey('behavior-card:${card.id}'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final detail = tester.widget<OntologyDetailScreen>(find.byType(OntologyDetailScreen));
      expect(detail.card, same(card));
      final title = tester.widget<AppBar>(find.byType(AppBar)).title! as Text;
      expect(title.data, card.title);
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(tester.widget<Text>(
        find.byKey(const ValueKey('behavior-detail-title')),
      ).data, card.title);
      for (final field in [
        ('behavior-purpose', card.purpose),
        ('behavior-preparation', card.preparation),
        ('behavior-instruction', card.instruction),
      ]) {
        expect(tester.widget<Text>(find.byKey(ValueKey(field.$1))).data, field.$2);
      }
      expect(find.text('Bu bilgiler davranışları tanımak içindir; tanı veya '
          'yaşa göre gelişim değerlendirmesi değildir.'), findsOneWidget);
      expect(find.byKey(const ValueKey('open-d01-model-demo'), skipOffstage: false), findsNothing);
      expect(find.byKey(const ValueKey('d01-demo-scope'), skipOffstage: false), findsNothing);
      expect(find.textContaining('Şablon yaşı'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(ScenarioGraphImportScreen), findsNothing);

      expect(kDebugMode, isTrue); // Widget koşusu release görünürlüğü kanıtı değildir.
      final team = find.byKey(ValueKey('behavior-team-details:${card.id}'));
      expect(team, findsOneWidget);
      expect(find.byType(ExpansionTile), findsOneWidget);
      expect(tester.widget<ExpansionTile>(team).initiallyExpanded, isFalse);
      expect(tester.widget<ExpansionTile>(team).maintainState, isTrue);
      expect(find.textContaining('yetkilendirme değildir'), findsOneWidget);
      final source = 'Kart sürümü: ${card.cardVersion} · Kaynak: ${BehaviorCards.sourceName}';
      expect(find.text(source), findsNothing);
      expect(find.textContaining(BehaviorCards.sourceName), findsNothing);
      expect(find.text(BehaviorCards.scope), findsNothing);
      expect(find.text(BehaviorCards.ageScope), findsNothing);
      expect(find.byKey(const ValueKey('behavior-window')), findsNothing);
      expect(find.text(BehaviorCards.windowNotice), findsNothing);
      for (var i = 0; i < card.conditions.length; i++) {
        expect(find.byKey(ValueKey('behavior-condition:${card.id}:$i')), findsNothing);
      }

      await toggleBehaviorSection(tester, 'Ekip için gözlem ayrıntıları');
      for (var i = 0; i < card.conditions.length; i++) {
        expect(find.text(BehaviorCards.conditionLabels[i]), findsOneWidget);
        final condition = find.byKey(ValueKey('behavior-condition:${card.id}:$i'));
        expect(condition, findsOneWidget);
        expect(tester.widget<Text>(condition).data, card.conditions[i]);
      }
      final lastRule = find.byKey(ValueKey(
        'behavior-condition:${card.id}:${card.conditions.length - 1}',
      ));
      await tester.ensureVisible(lastRule);
      await tester.pumpAndSettle();
      expect(lastRule.hitTestable(), findsOneWidget);
      expect(find.text(source), findsOneWidget);
      expect(find.text(BehaviorCards.scope), findsOneWidget);
      expect(find.text(BehaviorCards.ageScope), findsOneWidget);
      expect(find.text(BehaviorCards.windowNotice), findsOneWidget);
      expect(tester.widget<Text>(
        find.byKey(const ValueKey('behavior-window')),
      ).data, card.pilotWindowSeconds == 10
          ? 'Uyaran veya gösterilen hareket tamamlandıktan sonra 10 saniyelik '
              'kesintisiz gözlem planlanır. Uyaran sırasında başlayan yanıtlar da kaydedilir.'
          : 'Koşullar hazır olduktan sonra 20 saniyelik gözlem fırsatı planlanır. '
              'Malzemeye ilgi ve erişim ayrıca dikkate alınır.');
      final windowNotice = find.text(BehaviorCards.windowNotice);
      await tester.ensureVisible(windowNotice);
      await tester.pumpAndSettle();
      expect(windowNotice.hitTestable(), findsOneWidget);
      expect(find.textContaining('Gözlem Eşiği'), findsNothing);
      expect(find.textContaining('Bu Yaşta Ne Beklenir'), findsNothing);
      expect(find.textContaining('Tipik'), findsNothing);
      expect(find.textContaining('Şüpheli / Risk'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      expect(find.text('Bu Davranış İçin Senaryo Üret'), findsNothing);
      expect(find.text('Videodan Analiz Et'), findsNothing);
      await toggleBehaviorSection(tester, 'Ekip için gözlem ayrıntıları');
      expect(find.text(source), findsNothing);
      expect(find.text(BehaviorCards.ageScope), findsNothing);
      expect(find.text(BehaviorCards.windowNotice), findsNothing);
      expect(find.byKey(ValueKey('behavior-condition:${card.id}:0')), findsNothing);
      expect(tester.widget<Text>(
        find.byKey(const ValueKey('behavior-instruction')),
      ).data, card.instruction);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expectTab(tester, 0);
      await close(tester);
    });
  }

  for (final id in ['D08', 'D10']) {
    testWidgets('$id: 320 piksel ve büyük yazıda tam ad, temel içerik ve geri kontrolü erişilebilir', (tester) async {
      final card = BehaviorCards.all.firstWhere((card) => card.id == id);
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(builder: (context) => Scaffold(
          body: Center(child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => OntologyDetailScreen(card: card),
            )),
            child: const Text('Ayrıntıyı aç'),
          )),
        )),
      ));
      await tester.tap(find.text('Ayrıntıyı aç'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final back = find.byType(BackButton);
      expect(back.hitTestable(), findsOneWidget);
      final backBounds = tester.getRect(back);
      expect(backBounds.left, greaterThanOrEqualTo(0));
      expect(backBounds.right, lessThanOrEqualTo(320));
      final appTitle = tester.widget<AppBar>(find.byType(AppBar)).title! as Text;
      expect(appTitle.data, card.title);
      expect(appTitle.maxLines, 1);
      expect(appTitle.overflow, TextOverflow.ellipsis);
      final fullTitle = tester.widget<Text>(
        find.byKey(const ValueKey('behavior-detail-title')),
      );
      expect(fullTitle.data, card.title);
      expect(fullTitle.maxLines, isNull);
      expect(fullTitle.overflow, isNot(TextOverflow.ellipsis));
      for (final field in [
        ('behavior-purpose', card.purpose),
        ('behavior-preparation', card.preparation),
        ('behavior-instruction', card.instruction),
      ]) {
        final content = find.byKey(ValueKey(field.$1));
        await tester.ensureVisible(content);
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(content).data, field.$2);
        expect(content.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      expect(back.hitTestable(), findsOneWidget);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.byType(OntologyDetailScreen), findsNothing);
      expect(find.text('Ayrıntıyı aç'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(video.players, 0);
    });
  }

  testWidgets('Ana panel girişleri bugünkü işlevleri anlatır; video adı sekmeyle tutarlıdır', (tester) async {
    await mount(tester);
    expect(find.text('Nörogelişimsel Farkındalık Platformu'), findsOneWidget);
    expect(find.byTooltip('Gemini API Anahtarı'), findsNothing);
    expect(find.byIcon(Icons.key_outlined), findsNothing);
    expect(dashboardEntry('Video Analizi'), findsOneWidget);
    expect(destination('Video Analizi'), findsOneWidget);
    expect(find.text('Video seçip izleyin. Otomatik analiz bağlantısı henüz tamamlanmadı.'), findsOneWidget);
    expect(dashboardEntry('Simülasyon ve Eğitim'), findsOneWidget);
    expect(find.text('Hazır D01 örneğinin akışını inceleyin.'),
        findsOneWidget);
    expect(find.textContaining('otomatik zaman damgalı kanıt analizi'), findsNothing);
    expect(find.textContaining('Klinik davranış akışı, seans kurgulama'), findsNothing);
    expectTab(tester, 0);
    await close(tester);
  });

  for (final entry in [
    (title: 'Video Analizi', tabLabel: 'Video Analizi', index: 1),
    (title: 'Simülasyon ve Eğitim', tabLabel: 'Simülasyon ve Eğitim', index: 2),
  ]) {
    testWidgets('${entry.title}: ana panel kartı doğru sekmeyi açar', (tester) async {
      await mount(tester);
      final card = dashboardEntry(entry.title);
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expectTab(tester, entry.index);
      if (entry.index == 1) {
        expect(find.widgetWithText(AppBar, 'Video Analizi'), findsOneWidget);
        expect(find.byTooltip('Gemini API Anahtarı'), findsNothing);
        expect(find.text('Video seç'), findsOneWidget);
        expect(find.text('Bu video analiz edilmedi. Video seçip izleyebilirsiniz; '
            'otomatik analiz bağlantısı henüz tamamlanmadı.'), findsOneWidget);
        expect(find.textContaining('Risk Saptanmadı'), findsNothing);
      }
      await close(tester);
    });

    testWidgets('${entry.title}: alt sekme aynı hedefi açar ve ana panele dönülür', (tester) async {
      await mount(tester);
      await tester.tap(destination(entry.tabLabel));
      await tester.pumpAndSettle();
      expectTab(tester, entry.index);
      await tester.tap(destination('Ana\u00A0Panel'));
      await tester.pumpAndSettle();
      expectTab(tester, 0);
      expect(dashboardEntry(entry.title), findsOneWidget);
      await close(tester);
    });
  }
}
