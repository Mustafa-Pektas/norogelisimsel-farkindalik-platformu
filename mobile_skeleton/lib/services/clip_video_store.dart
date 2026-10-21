import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Yalnızca yerel dosya eşlemesi; video/gözlem doğrulaması içermez.
class ClipVideoBinding {
  ClipVideoBinding({
    required this.planId,
    required this.clipId,
    required this.relativePath,
    required this.fileName,
  }) {
    if (planId.trim().isEmpty || clipId.trim().isEmpty ||
        fileName.trim().isEmpty || fileName.contains(RegExp(r'[/\\]'))) {
      throw const FormatException('Video eşlemesinin kimliği veya dosya adı geçersiz.');
    }
    if (!RegExp(r'^clip_videos/import_[a-zA-Z0-9_-]+/video\.[a-zA-Z0-9]{1,8}$').hasMatch(relativePath)) {
      throw const FormatException('Video yolu uygulama belge dizinine göreli olmalıdır.');
    }
  }

  factory ClipVideoBinding.fromJson(dynamic value) {
    if (value is! Map<String, dynamic> ||
        ['planId', 'clipId', 'relativePath', 'fileName'].any((key) => value[key] is! String)) {
      throw const FormatException('Video eşlemesi okunamadı.');
    }
    return ClipVideoBinding(
      planId: value['planId'] as String,
      clipId: value['clipId'] as String,
      relativePath: value['relativePath'] as String,
      fileName: value['fileName'] as String,
    );
  }

  final String planId;
  final String clipId;
  final String relativePath;
  final String fileName;

  Map<String, dynamic> toJson() => {
    'planId': planId,
    'clipId': clipId,
    'relativePath': relativePath,
    'fileName': fileName,
  };
}

typedef ClipVideoAttachResult = ({ClipVideoBinding binding, String? warning});

/// JSON önce aynı dosya sistemindeki geçici dosyaya yazılıp flush edilir;
/// rename başarılı olana kadar eski indeks ve video değiştirilmez.
/// Kopyalama/kayıt başarısızsa eski eşleme geçerli kalır. Galeri kaynağı silinmez.
class ClipVideoStore {
  ClipVideoStore({
    required this.documentsDirectory,
    Future<File> Function(File source, String destination)? copyVideo,
    Future<void> Function(File temporary, File index)? publishIndex,
  }) : _copyVideo = copyVideo ?? ((source, destination) => source.copy(destination)),
       _publishIndex = publishIndex ?? ((temporary, index) async { await temporary.rename(index.path); });

  static const indexFileName = 'clip_video_bindings.json';
  final Future<Directory> Function() documentsDirectory;
  final Future<File> Function(File, String) _copyVideo;
  final Future<void> Function(File, File) _publishIndex;

  // Aynı uygulama sürecinde iki ekran/depo örneği eşzamanlı indeks ezmesin.
  static Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }

  Future<Map<(String, String), ClipVideoBinding>> _read(Directory root) async {
    final index = File('${root.path}/$indexFileName');
    if (!await index.exists()) return {};
    final raw = jsonDecode(await index.readAsString());
    if (raw is! Map<String, dynamic> || raw['schemaVersion'] != '1.0' || raw['bindings'] is! List) {
      throw const FormatException('Yerel video eşleme kaydı geçersiz; üzerine yazılmadı.');
    }
    final result = <(String, String), ClipVideoBinding>{};
    final paths = <String>{};
    for (final value in raw['bindings'] as List) {
      final binding = ClipVideoBinding.fromJson(value);
      final key = (binding.planId, binding.clipId);
      if (result.containsKey(key)) throw const FormatException('Tekrarlı video eşlemesi.');
      if (!paths.add(binding.relativePath)) throw const FormatException('Aynı uygulama kopyası birden fazla eşlemeye ait olamaz.');
      result[key] = binding;
    }
    return result;
  }

  Future<Map<String, ClipVideoBinding>> loadPlan(String planId) => _serial(() async {
    final all = await _read(await documentsDirectory());
    return Map.unmodifiable({for (final binding in all.values)
      if (binding.planId == planId) binding.clipId: binding});
  });

  Future<File> fileFor(ClipVideoBinding binding) async =>
      File('${(await documentsDirectory()).path}/${binding.relativePath}');

  Future<bool> fileExists(ClipVideoBinding binding) async => (await fileFor(binding)).exists();

  Future<String?> _cleanTemporary(File file, Directory directory) async {
    try {
      if (await file.exists()) await file.delete();
      if (await directory.exists()) await directory.delete(); // Yalnız boş, bu işleme ait klasör.
      return null;
    } catch (_) {
      return 'Geçici uygulama kopyası temizlenemedi.';
    }
  }

  Future<String?> _deleteOwnedCopy(ClipVideoBinding? binding) async {
    if (binding == null) return null;
    try {
      final file = await fileFor(binding);
      if (await file.exists()) await file.delete();
      if (await file.parent.exists()) await file.parent.delete();
      return null;
    } catch (_) {
      return 'Eşleme kaydedildi; eski uygulama kopyası temizlenemedi.';
    }
  }

  Future<String?> _save(Directory root, Iterable<ClipVideoBinding> bindings) async {
    await root.create(recursive: true);
    final temporaryDirectory = await root.createTemp('clip_binding_txn_');
    final temporary = File('${temporaryDirectory.path}/index.json');
    try {
      await temporary.writeAsString(const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': '1.0',
        'bindings': [for (final binding in bindings) binding.toJson()],
      }), flush: true);
      await _publishIndex(temporary, File('${root.path}/$indexFileName'));
    } catch (_) {
      await _cleanTemporary(temporary, temporaryDirectory);
      rethrow;
    }
    return _cleanTemporary(temporary, temporaryDirectory);
  }

  Future<ClipVideoAttachResult> attach({
    required String planId,
    required String clipId,
    required File source,
    required String fileName,
  }) => _serial(() async {
    final root = await documentsDirectory();
    final all = await _read(root);
    final old = all[(planId, clipId)];
    final expectedBytes = await source.length();
    if (expectedBytes <= 0) throw const FileSystemException('Seçilen video boş.');
    final media = await Directory('${root.path}/clip_videos').create(recursive: true);
    final directory = await media.createTemp('import_');
    final name = fileName.split(RegExp(r'[/\\]')).last;
    final extension = RegExp(r'\.[a-zA-Z0-9]{1,8}$').firstMatch(name)?.group(0) ?? '.video';
    final folder = directory.uri.pathSegments.where((part) => part.isNotEmpty).last;
    final relative = 'clip_videos/$folder/video$extension';
    final target = File('${root.path}/$relative');
    late ClipVideoBinding binding;
    String? warning;
    try {
      binding = ClipVideoBinding(planId: planId, clipId: clipId, relativePath: relative, fileName: name);
      await _copyVideo(source, target.path);
      if (await target.length() != expectedBytes) {
        throw const FileSystemException('Video kopyası tamamlanamadı.');
      }
      all[(planId, clipId)] = binding;
      warning = await _save(root, all.values);
    } catch (_) {
      await _cleanTemporary(target, directory);
      rethrow;
    }
    final cleanup = await _deleteOwnedCopy(old);
    return (binding: binding, warning: warning ?? cleanup);
  });

  Future<String?> remove({required String planId, required String clipId}) => _serial(() async {
    final root = await documentsDirectory();
    final all = await _read(root);
    final old = all.remove((planId, clipId));
    if (old == null) return null;
    final warning = await _save(root, all.values);
    final cleanup = await _deleteOwnedCopy(old);
    return warning ?? cleanup;
  });
}
