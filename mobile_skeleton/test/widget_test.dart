import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_awareness_app/main.dart';
import 'package:neuro_awareness_app/models/behavior_cards.dart';
import 'package:neuro_awareness_app/screens/ontology_detail_screen.dart';
import 'package:neuro_awareness_app/screens/scenario_graph_import_screen.dart';
import 'package:neuro_awareness_app/screens/synthetic_video_studio_screen.dart';
import 'package:neuro_awareness_app/screens/video_analysis_screen.dart';
import 'package:neuro_awareness_app/services/local_llama_test_service.dart';
import 'package:neuro_awareness_app/widgets/local_llama_test_card.dart';
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
  Future<void> pause(int playerId) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
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
    // Mevcut açılış şablonunun 250 ms beklemesini bitir; çıkarım başlatılmaz.
    await tester.pump(const Duration(milliseconds: 300));
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

  Future<void> close(WidgetTester tester) async {
    final cards = tester.widgetList<LocalLlamaTestCard>(
      find.byType(LocalLlamaTestCard, skipOffstage: false),
    ).toList();
    expect(cards, isNotEmpty);
    for (final card in cards) {
      expect(card.service.state.phase, LocalLlamaPhase.idle,
          reason: 'Gezinme gerçek model çıkarımı başlatmamalı.');
    }
    expect(video.players, 1);
    expect(video.plays, 0);
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

  testWidgets('Ana panelde tam olarak D01–D10 gösterilir; eski eşik ve norm kartları yoktur', (tester) async {
    await mount(tester);
    final tiles = tester.widgetList<ListTile>(find.byWidgetPredicate(
      (widget) => widget is ListTile &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('behavior-card:'),
    )).toList();
    expect(tiles, hasLength(10));
    expect(find.text('10 davranış kartı'), findsOneWidget);
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
    expect(find.text('Şablon yaşı'), findsOneWidget);
    await close(tester);
  });

  for (final card in BehaviorCards.all) {
    testWidgets('${card.id}: doğru kart ayrıntısı açılır; eski ONT üretimine geçiş yoktur', (tester) async {
      await mount(tester);
      final entry = find.byKey(ValueKey('behavior-card:${card.id}'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final detail = tester.widget<OntologyDetailScreen>(find.byType(OntologyDetailScreen));
      expect(detail.card, same(card));
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
      expect(find.text('Bilgilendirme amaçlıdır; tanı veya puanlama yapılmaz.'), findsOneWidget);
      final rules = find.byKey(ValueKey('behavior-observation-rules:${card.id}'));
      final technical = find.byKey(ValueKey('behavior-technical-info:${card.id}'));
      for (final section in [rules, technical]) {
        expect(tester.widget<ExpansionTile>(section).initiallyExpanded, isFalse);
      }
      for (var i = 0; i < card.conditions.length; i++) {
        expect(find.byKey(ValueKey('behavior-condition:${card.id}:$i')), findsNothing);
      }
      final source = 'Kart sürümü: ${card.cardVersion} · Kaynak: ${BehaviorCards.sourceName}';
      expect(find.text(source), findsNothing);
      expect(find.text(BehaviorCards.scope), findsNothing);
      expect(find.text(BehaviorCards.ageScope), findsNothing);
      expect(find.byKey(const ValueKey('behavior-window')), findsNothing);
      expect(find.text(BehaviorCards.windowNotice), findsNothing);
      if (card.id == 'D01') {
        final demo = find.byKey(const ValueKey('open-d01-model-demo'));
        expect(demo, findsOneWidget);
        expect(tester.getTopLeft(demo).dy, lessThan(tester.getTopLeft(rules).dy));
        expect(tester.getTopLeft(demo).dy, lessThan(tester.getTopLeft(technical).dy));
        expect(tester.widget<Text>(
          find.byKey(const ValueKey('d01-demo-scope')),
        ).data, '30 aylık Deniz için sabit demo; oluşan akış hazır videolara bağlı değildir.');
      }
      await toggleBehaviorSection(tester, 'Ayrıntılı gözlem kuralları');
      for (var i = 0; i < card.conditions.length; i++) {
        expect(find.text(BehaviorCards.conditionLabels[i]), findsOneWidget);
        expect(tester.widget<Text>(
          find.byKey(ValueKey('behavior-condition:${card.id}:$i')),
        ).data, card.conditions[i]);
      }
      final lastRule = find.byKey(ValueKey(
        'behavior-condition:${card.id}:${card.conditions.length - 1}',
      ));
      await tester.ensureVisible(lastRule);
      await tester.pumpAndSettle();
      expect(lastRule.hitTestable(), findsOneWidget);
      expect(find.text(BehaviorCards.ageScope), findsNothing);
      await toggleBehaviorSection(tester, 'Teknik bilgiler');
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
      if (card.id == 'D01') {
        expect(tester.widget<Text>(
          find.byKey(const ValueKey('d01-demo-technical-scope')),
        ).data, 'Mevcut D01 model demosu 30 aylık Deniz ile sınırlıdır. '
            'Şablon yaşı bu demoyu değiştirmez. Oluşan graf hazır D01 '
            'klip planına veya videolarına bağlı değildir.');
      }
      expect(find.textContaining('Gözlem Eşiği'), findsNothing);
      expect(find.textContaining('Bu Yaşta Ne Beklenir'), findsNothing);
      expect(find.textContaining('Tipik'), findsNothing);
      expect(find.textContaining('Şüpheli / Risk'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      expect(find.text('Bu Davranış İçin Senaryo Üret'), findsNothing);
      expect(find.text('Videodan Analiz Et'), findsNothing);
      if (card.id == 'D01') {
        expect(find.byKey(const ValueKey('open-d01-model-demo')), findsOneWidget);
        expect(find.byKey(const ValueKey('behavior-not-connected')), findsNothing);
      } else {
        expect(find.byKey(const ValueKey('behavior-not-connected')), findsOneWidget);
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(ElevatedButton), findsNothing);
        expect(find.byType(OutlinedButton), findsNothing);
      }
      expect(find.byType(ScenarioGraphImportScreen), findsNothing);
      await toggleBehaviorSection(tester, 'Ayrıntılı gözlem kuralları');
      await toggleBehaviorSection(tester, 'Teknik bilgiler');
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

  for (final age in [12.0, 36.0]) {
    testWidgets('Şablon yaşı $age iken D01 mevcut demoyu sabit 30 ayla açar', (tester) async {
      await mount(tester);
      tester.widget<AgeSliderCard>(find.byType(AgeSliderCard)).onChanged(age);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('behavior-card:D01'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(
        find.byKey(const ValueKey('d01-demo-scope')),
      ).data, contains('30 aylık Deniz'));
      final demo = find.byKey(const ValueKey('open-d01-model-demo'));
      await tester.ensureVisible(demo);
      await tester.tap(demo);
      await tester.pumpAndSettle();
      expect(find.byType(ScenarioGraphImportScreen), findsOneWidget);
      expect(tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('scenario-import-mode-scenario')),
      ).selected, isTrue);
      final request = tester.widget<LocalLlamaTestCard>(
        find.byType(LocalLlamaTestCard),
      ).service.request;
      expect(request, same(LocalLlamaTestRequest.d01GraphDemo));
      expect(request.prompt, contains('30 aylık Deniz'));
      expect(LocalLlamaTestRequest.d01GraphDemoMetadata['ageMonths'], 30);
      expect(LocalLlamaTestRequest.d01GraphDemoMetadata['behaviorId'], 'D01');
      expect(LocalLlamaTestRequest.d01GraphDemoMetadata['cardVersion'], '0.2');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(OntologyDetailScreen), findsOneWidget);
      await close(tester);
    });
  }

  testWidgets('Ana panel girişleri bugünkü işlevleri anlatır; video adı sekmeyle tutarlıdır', (tester) async {
    await mount(tester);
    expect(find.text('Nörogelişimsel Farkındalık Platformu'), findsOneWidget);
    expect(dashboardEntry('Video izle'), findsOneWidget);
    expect(destination('Video izle'), findsOneWidget);
    expect(find.text('Bir video seçip izleyin.'), findsOneWidget);
    expect(dashboardEntry('Senaryo Stüdyosu'), findsOneWidget);
    expect(find.text('Senaryo taslaklarını ve hazır örnekleri inceleyin. Yapay zekâ denemeleri ayrı çalışır.'),
        findsOneWidget);
    expect(find.textContaining('otomatik zaman damgalı kanıt analizi'), findsNothing);
    expect(find.textContaining('Klinik davranış akışı, seans kurgulama'), findsNothing);
    expectTab(tester, 0);
    await close(tester);
  });

  for (final entry in [
    (title: 'Video izle', tabLabel: 'Video izle', index: 1),
    (title: 'Senaryo Stüdyosu', tabLabel: 'Senaryo\u00A0Stüdyosu', index: 2),
  ]) {
    testWidgets('${entry.title}: ana panel kartı doğru sekmeyi açar', (tester) async {
      await mount(tester);
      final card = dashboardEntry(entry.title);
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expectTab(tester, entry.index);
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
