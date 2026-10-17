// Birincil hedefli Dart kontrolü; Flutter veya gerçek video çözme gerektirmez.
// dart --disable-dart-dev --packages=.dart_tool/package_config.json test/clip_video_store_checks.dart
import 'dart:convert';
import 'dart:io';

import 'package:neuro_awareness_app/services/clip_video_store.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> fails(Future<dynamic> Function() action) async {
  try {
    await action();
  } on FileSystemException {
    return;
  } on FormatException {
    return;
  }
  throw StateError('Beklenen dosya/kayıt hatası oluşmadı.');
}

Future<void> main() async {
  final workspaceCache = Directory('.dart_tool').absolute;
  final tests = <String, Future<void> Function(Directory)>{
    'Kopya kalıcı dizine gider; göreli JSON yeni depo örneğinde aynı plan/klibi yükler': (temp) async {
      final docs = Directory('${temp.path}/documents');
      final source = await File('${temp.path}/gallery_fixture.bin').writeAsString('UNIT TEST FILE BYTES');
      final store = ClipVideoStore(documentsDirectory: () async => docs);
      final result = await store.attach(planId: 'plan-a', clipId: 'clip-1', source: source, fileName: 'galeri.mov');
      check(result.warning == null, 'Temizlik başarılı');
      check(await (await store.fileFor(result.binding)).readAsString() == await source.readAsString(), 'Baytlar korundu');
      final index = jsonDecode(await File('${docs.path}/${ClipVideoStore.indexFileName}').readAsString()) as Map;
      final entry = (index['bindings'] as List).single as Map;
      check(entry['relativePath'] == result.binding.relativePath &&
          (entry['relativePath'] as String).startsWith('clip_videos/import_'), 'Yalnız göreli uygulama yolu');
      check(entry.keys.toSet().difference({'planId','clipId','relativePath','fileName'}).isEmpty, 'Cihaz/kaynak yolu kaydedilmedi');
      final reopened = ClipVideoStore(documentsDirectory: () async => docs);
      final loaded = await reopened.loadPlan('plan-a');
      check(loaded['clip-1']?.fileName == 'galeri.mov', 'Yeniden açılış eşlemesi');
      check(await reopened.fileExists(loaded['clip-1']!), 'Kalıcı kopya mevcut');
      check((await reopened.loadPlan('plan-b')).isEmpty, 'Plan kimlikleri karışmaz');
      check(await source.exists(), 'Galeri kaynağı silinmedi');
    },
    'Değiştirme ve kaldırma yalnız uygulama kopyalarını temizler': (temp) async {
      final docs = Directory('${temp.path}/documents');
      final first = await File('${temp.path}/first.bin').writeAsString('TEST: FIRST SOURCE');
      final second = await File('${temp.path}/second.bin').writeAsString('TEST: SECOND SOURCE');
      final store = ClipVideoStore(documentsDirectory: () async => docs);
      final old = await store.attach(planId: 'p', clipId: 'c', source: first, fileName: 'first.mp4');
      final replacement = await store.attach(planId: 'p', clipId: 'c', source: second, fileName: 'second.mp4');
      check(!await store.fileExists(old.binding), 'Eski uygulama kopyası temizlendi');
      check(await store.fileExists(replacement.binding), 'Yeni kopya mevcut');
      check((await store.loadPlan('p'))['c']?.fileName == 'second.mp4', 'Yeni eşleme kaydedildi');
      await store.remove(planId: 'p', clipId: 'c');
      check((await store.loadPlan('p')).isEmpty, 'Eşleme kaldırıldı');
      check(!await store.fileExists(replacement.binding), 'Kaldırılan uygulama kopyası temizlendi');
      check(await first.exists() && await second.exists(), 'İki galeri kaynağı da korundu');
    },
    'Kopyalama yarıda hata verirse önceki JSON ve çalışan video aynen korunur': (temp) async {
      final docs = Directory('${temp.path}/documents');
      final source = await File('${temp.path}/source.bin').writeAsString('UNIT TEST: SOURCE');
      final store = ClipVideoStore(documentsDirectory: () async => docs);
      final old = await store.attach(planId: 'p', clipId: 'c', source: source, fileName: 'first.mov');
      final index = File('${docs.path}/${ClipVideoStore.indexFileName}');
      final original = await index.readAsString();
      final failing = ClipVideoStore(documentsDirectory: () async => docs, copyVideo: (file, path) async {
        await File(path).writeAsString('PARTIAL TEST BYTES');
        throw const FileSystemException('TEST: copy failure');
      });
      await fails(() => failing.attach(planId: 'p', clipId: 'c', source: source, fileName: 'new.mov'));
      check(await index.readAsString() == original, 'İndeks değişmedi');
      check(await store.fileExists(old.binding), 'Önceki video korunuyor');
      check(Directory('${docs.path}/clip_videos').listSync().length == 1, 'Yarım uygulama kopyası temizlendi');
      check(await source.readAsString() == 'UNIT TEST: SOURCE', 'Kaynak baytlar korundu');
    },
    'JSON yayınlama hatasında değiştirme ve kaldırma eski eşlemeyi bozmaz': (temp) async {
      final docs = Directory('${temp.path}/documents');
      final source = await File('${temp.path}/source.bin').writeAsString('UNIT TEST: SOURCE');
      final store = ClipVideoStore(documentsDirectory: () async => docs);
      final old = await store.attach(planId: 'p', clipId: 'c', source: source, fileName: 'old.mov');
      final index = File('${docs.path}/${ClipVideoStore.indexFileName}');
      final original = await index.readAsString();
      final failing = ClipVideoStore(documentsDirectory: () async => docs, publishIndex: (temporary, index) async {
        throw const FileSystemException('TEST: index publish failure');
      });
      await fails(() => failing.attach(planId: 'p', clipId: 'c', source: source, fileName: 'new.mov'));
      await fails(() => failing.remove(planId: 'p', clipId: 'c'));
      check(await index.readAsString() == original, 'Kayıt baytları korundu');
      check(await store.fileExists(old.binding), 'Önceki çalışan kopya duruyor');
      check((await store.loadPlan('p'))['c']?.fileName == 'old.mov', 'Önceki eşleme yükleniyor');
      check(Directory('${docs.path}/clip_videos').listSync().length == 1, 'Yeni başarısız kopya silindi');
    },
    'Eksik dosya eşlemesi saklanır, eksiklik bildirilebilir ve bağlantı kaldırılabilir': (temp) async {
      final docs = Directory('${temp.path}/documents');
      final source = await File('${temp.path}/source.bin').writeAsString('TEST: SOURCE');
      final store = ClipVideoStore(documentsDirectory: () async => docs);
      final result = await store.attach(planId: 'p', clipId: 'c', source: source, fileName: 'video.mov');
      await (await store.fileFor(result.binding)).delete();
      final loaded = (await store.loadPlan('p'))['c']!;
      check(!await store.fileExists(loaded), 'Dosya bulunamadı durumu');
      check(loaded.fileName == 'video.mov', 'Dosya adı korunur');
      await store.remove(planId: 'p', clipId: 'c');
      check((await store.loadPlan('p')).isEmpty && await source.exists(), 'Kaynağı silmeden kaldırma');
    },
    'Kayıttan sonraki temizlik sorunu yeni çalışan eşlemeyi geri almaz ve uyarı döner': (temp) async {
      final docs = Directory('${temp.path}/documents');
      final source = await File('${temp.path}/source.bin').writeAsString('TEST: SOURCE');
      final store = ClipVideoStore(documentsDirectory: () async => docs);
      final old = await store.attach(planId: 'p', clipId: 'c', source: source, fileName: 'old.mov');
      // Klasör boş değilse non-recursive temizlik başarısız olur; ek dosya silinmemeli.
      final retained = await File('${(await store.fileFor(old.binding)).parent.path}/retained_test_file').writeAsString('TEST: KEEP');
      final current = await store.attach(planId: 'p', clipId: 'c', source: source, fileName: 'new.mov');
      check(current.warning != null, 'Başarılı kayıt sonrası temizlik uyarısı');
      check((await store.loadPlan('p'))['c']?.fileName == 'new.mov', 'Yeni eşleme kalıcı');
      check(await store.fileExists(current.binding), 'Yeni dosya silinmedi');
      check(await retained.exists() && await source.exists(), 'Diğer dosyalar korunur');
    },
    'Bozuk kayıt ve dizin dışına çıkan yollar sessizce sıfırlanmaz': (temp) async {
      final docs = await Directory('${temp.path}/documents').create();
      final source = await File('${temp.path}/source.bin').writeAsString('TEST: SOURCE');
      final index = await File('${docs.path}/${ClipVideoStore.indexFileName}').writeAsString('{BROKEN TEST JSON');
      final store = ClipVideoStore(documentsDirectory: () async => docs);
      await fails(() => store.loadPlan('p'));
      await fails(() => store.attach(planId: 'p', clipId: 'c', source: source, fileName: 'new.mov'));
      check(await index.readAsString() == '{BROKEN TEST JSON', 'Bozuk kayıt ezilmedi');
      for (final path in ['../outside.mov', '/data/absolute.mov', r'C:\outside.mov']) {
        var rejected = false;
        try {
          ClipVideoBinding(planId: 'p', clipId: 'c', relativePath: path, fileName: 'video.mov');
        } on FormatException { rejected = true; }
        check(rejected, 'Geçersiz yol reddedilmeli');
      }
    },
    'İki depo örneğinin sıralı kayıtları farklı plan ve klipleri ezmez': (temp) async {
      final docs = Directory('${temp.path}/documents');
      final source = await File('${temp.path}/source.bin').writeAsString('TEST: SOURCE');
      final a = ClipVideoStore(documentsDirectory: () async => docs);
      final b = ClipVideoStore(documentsDirectory: () async => docs);
      await Future.wait([
        a.attach(planId: 'plan-a', clipId: 'same-clip', source: source, fileName: 'a.mov'),
        b.attach(planId: 'plan-b', clipId: 'same-clip', source: source, fileName: 'b.mov'),
      ]);
      check((await a.loadPlan('plan-a'))['same-clip']?.fileName == 'a.mov', 'Birinci plan');
      check((await b.loadPlan('plan-b'))['same-clip']?.fileName == 'b.mov', 'İkinci plan');
    },
  };
  var failed = 0;
  for (final entry in tests.entries) {
    final temp = await workspaceCache.createTemp('clip_video_store_check_');
    try {
      await entry.value(temp);
      stdout.writeln('PASS: ${entry.key}');
    } catch (error, stack) {
      failed++;
      stderr.writeln('FAIL: ${entry.key}\n$error\n$stack');
    } finally {
      final target = temp.absolute;
      if (target.parent.path != workspaceCache.path || !target.path.startsWith('${workspaceCache.path}${Platform.pathSeparator}clip_video_store_check_')) {
        throw StateError('Test temizlik yolu doğrulanamadı; silinmedi.');
      }
      await target.delete(recursive: true);
    }
  }
  stdout.writeln('${tests.length - failed}/${tests.length} hedefli dosya/eşleme kontrolü geçti.');
  if (failed != 0) exitCode = 1;
}
