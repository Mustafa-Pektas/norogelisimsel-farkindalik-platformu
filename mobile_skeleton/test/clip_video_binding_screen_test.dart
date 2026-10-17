import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:neuro_awareness_app/models/scenario_clip_plan.dart';
import 'package:neuro_awareness_app/screens/clip_production_plan_screen.dart';
import 'package:neuro_awareness_app/services/clip_video_store.dart';

// Yalnız UI sınırı; gerçek galeri veya video dosyası testi değildir.
class _MemoryStore extends ClipVideoStore {
  _MemoryStore() : super(documentsDirectory: () async => Directory('UNUSED_TEST_ROOT'));
  final bindings = <String, ClipVideoBinding>{};
  bool fail = false;
  bool missing = false;
  int attaches = 0;

  @override
  Future<Map<String, ClipVideoBinding>> loadPlan(String planId) async =>
      {for (final entry in bindings.entries) if (entry.value.planId == planId) entry.key: entry.value};
  @override
  Future<bool> fileExists(ClipVideoBinding binding) async => !missing;
  @override
  Future<ClipVideoAttachResult> attach({required String planId, required String clipId, required File source, required String fileName}) async {
    attaches++;
    if (fail) throw const FileSystemException('TEST: storage failure');
    final binding = ClipVideoBinding(planId: planId, clipId: clipId,
        relativePath: 'clip_videos/import_TEST$attaches/video.mov', fileName: fileName);
    bindings[clipId] = binding;
    return (binding: binding, warning: null);
  }
  @override
  Future<String?> remove({required String planId, required String clipId}) async {
    if (fail) throw const FileSystemException('TEST: storage failure');
    bindings.remove(clipId);
    return null;
  }
}

// Gerçek kayıt testi yüklemenin bitişini açıkça bekler; pumpAndSettle IO beklemez.
class _DiskStore extends ClipVideoStore {
  _DiskStore(Directory documents) : super(documentsDirectory: () async => documents);

  final loaded = Completer<Map<String, ClipVideoBinding>?>();
  final fileChecked = Completer<bool?>();

  @override
  Future<Map<String, ClipVideoBinding>> loadPlan(String planId) async {
    Map<String, ClipVideoBinding>? bindings;
    try {
      bindings = await super.loadPlan(planId);
      return bindings;
    } finally {
      if (!loaded.isCompleted) loaded.complete(bindings);
    }
  }

  @override
  Future<bool> fileExists(ClipVideoBinding binding) async {
    bool? exists;
    try {
      exists = await super.fileExists(binding);
      return exists;
    } finally {
      if (!fileChecked.isCompleted) fileChecked.complete(exists);
    }
  }
}

class _Bundle extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    // Asset fixture'ları belleğe alınır; plugin/IO beklemesi UI testine taşınmaz.
    return _sources[key]!;
  }
  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

final _sources = {
  for (final path in [ClipProductionPlanScreen.d01GraphAssetPath, ClipProductionPlanScreen.d01PlanAssetPath])
    path: File(path).readAsStringSync(),
};

void main() {
  final plan = ScenarioClipPlan.fromJsonString(_sources[ClipProductionPlanScreen.d01PlanAssetPath]!);
  final clip = plan.clipsForScene('oyuncakla_oyun').single;
  ClipVideoBinding oldBinding() => ClipVideoBinding(planId: plan.planId, clipId: clip.id,
      relativePath: 'clip_videos/import_OLD/video.mov', fileName: 'old.mov');
  Widget app(ClipVideoStore store, Future<XFile?> Function() picker) => DefaultAssetBundle(
    bundle: _Bundle(),
    child: MaterialApp(home: ClipProductionPlanScreen(videoStore: store, pickVideo: picker)),
  );
  Future<void> open(WidgetTester tester) async {
    await tester.pumpAndSettle();
    final scene = find.byKey(const ValueKey('clip-scene:oyuncakla_oyun'));
    await tester.ensureVisible(scene);
    await tester.tap(find.descendant(of: scene, matching: find.text('Oyuncakla oyun')));
    await tester.pumpAndSettle();
  }
  Future<void> tap(WidgetTester tester, String key) async {
    final button = find.byKey(ValueKey(key));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('İptal eşlemeyi korur; seçme değiştirir, kayıt hatası önceki eşlemeyi korur', (tester) async {
    final store = _MemoryStore()..bindings[clip.id] = oldBinding();
    var picks = 0;
    await tester.pumpWidget(app(store, () async {
      picks++;
      // Yerel XFile.name, name: parametresinden değil yolun sonundan gelir.
      // _MemoryStore bu yolu açmaz; gerçek video dosyası gerekmez.
      return picks == 1 ? null : XFile('new.mov');
    }));
    await open(tester);
    expect(find.text('Video bağlı'), findsOneWidget);
    expect(find.text('old.mov'), findsOneWidget);
    expect(find.textContaining('İncelenmedi'), findsOneWidget);
    await tap(tester, 'select-clip-video:${clip.id}');
    expect(store.attaches, 0);
    expect(find.text('old.mov'), findsOneWidget);
    await tap(tester, 'select-clip-video:${clip.id}');
    expect(store.attaches, 1);
    expect(find.text('new.mov'), findsOneWidget);
    store.fail = true;
    await tap(tester, 'select-clip-video:${clip.id}');
    expect(find.text('new.mov'), findsOneWidget);
    expect(find.textContaining('Video kopyalanamadı veya eşleme kaydedilemedi.'), findsOneWidget);
    await tap(tester, 'remove-clip-video:${clip.id}');
    expect(find.text('new.mov'), findsOneWidget);
    expect(find.textContaining('Bağlantı kaldırılamadı'), findsOneWidget);
    store.fail = false;
    await tap(tester, 'remove-clip-video:${clip.id}');
    expect(find.text('Video yok'), findsOneWidget);
    expect(store.bindings, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ekran yeniden açılınca eşleme yüklenir; eksik kopya dosya adıyla gösterilir', (tester) async {
    final root = (await tester.runAsync(
      () => Directory('.dart_tool').createTemp('clip_binding_widget_'),
    ))!;
    addTearDown(() async {
      expect(root.absolute.parent.path, Directory('.dart_tool').absolute.path);
      expect(root.uri.pathSegments.where((part) => part.isNotEmpty).last,
          startsWith('clip_binding_widget_'));
      await root.delete(recursive: true);
    });
    final documents = Directory('${root.path}/documents');
    late _DiskStore store;
    final saved = (await tester.runAsync(() async {
      // Completer'lar da IO'yu bekleyen runAsync alanında oluşturulmalıdır.
      // Sanal alanda oluşturulurlarsa complete() sanal mikro görev kuyruğunu
      // bekler; runAsync ise bu kuyruk çalıştırılmadan tamamlanamaz.
      store = _DiskStore(documents);
      final source = await File('${root.path}/old.mov').writeAsString('TEST BYTES ONLY');
      return store.attach(planId: plan.planId, clipId: clip.id,
          source: source, fileName: 'old.mov');
    }))!;
    Future<XFile?> noSelection() async => null;
    await tester.runAsync(() async {
      await tester.pumpWidget(app(store, noSelection));
      final bindings = await store.loaded.future;
      // Eşleme yoksa ekran fileExists çağırmaz: boşuna callback bekleme,
      // asıl yükleme sorununu bir beklenti hatasıyla bildir.
      expect(bindings, contains(clip.id));
      expect(await store.fileChecked.future, isTrue);
    });
    await open(tester);
    expect(find.text('Video bağlı'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    // Yalnız bu teste ait uygulama kopyası silinir; JSON kaydı korunur.
    await tester.runAsync(() async {
      await (await store.fileFor(saved.binding)).delete();
    });
    await tester.runAsync(() async {
      final reopened = _DiskStore(documents);
      await tester.pumpWidget(app(reopened, noSelection));
      final bindings = await reopened.loaded.future;
      expect(bindings, contains(clip.id));
      // Video silinse de JSON eşlemesi kalmalı ve fileExists false dönmeli.
      expect(await reopened.fileChecked.future, isFalse);
    });
    await open(tester);
    expect(find.text('Dosya bulunamadı'), findsOneWidget);
    expect(find.text('old.mov'), findsOneWidget);
    expect(find.byKey(ValueKey('remove-clip-video:${clip.id}')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
