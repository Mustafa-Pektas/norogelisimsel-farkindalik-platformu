import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/scenario_clip_plan.dart';
import '../models/scenario_graph.dart';
import '../services/clip_video_store.dart';
import 'clip_video_preview_screen.dart';
import 'graph_playback_screen.dart';

typedef LoadedClipPlan = ({ScenarioGraph graph, ScenarioClipPlan plan});

/// Yerel üretim hazırlığı; kullanıcı yetkilendirmesi veya video doğrulaması değildir.
class ClipProductionPlanScreen extends StatefulWidget {
  const ClipProductionPlanScreen({
    super.key,
    this.graphAssetPath = d01GraphAssetPath,
    this.planAssetPath = d01PlanAssetPath,
    this.videoStore,
    this.pickVideo,
    this.providedPlan,
    this.rawPlanJson,
    this.sourceContext,
  });

  static const d01GraphAssetPath = 'assets/scenarios/d01_scenario_graph.json';
  static const d01PlanAssetPath = 'assets/scenarios/d01_clip_plan.json';

  /// Üretim alanı ve doğrudan D01 oynatma girişi aynı doğrulamayı kullanır.
  static Future<LoadedClipPlan> loadPlanAssets(
    AssetBundle bundle, {
    String graphAssetPath = d01GraphAssetPath,
    String planAssetPath = d01PlanAssetPath,
  }) async {
    final sources = await Future.wait([
      bundle.loadString(graphAssetPath, cache: false),
      bundle.loadString(planAssetPath, cache: false),
    ]);
    final graph = ScenarioGraph.fromJsonString(sources[0]);
    final plan = ScenarioClipPlan.fromJsonString(sources[1]);
    plan.validateAgainst(graph);
    return (graph: graph, plan: plan);
  }

  /// Sunucudan gelen plan yalnız inceleme içindir; eski video deposuna erişmez.
  final LoadedClipPlan? providedPlan;
  final String? rawPlanJson;
  /// Kaynak plan JSON şemasına eklenmez; özgün cevap/kimlik ayrı dışa aktarılır.
  final Map<String, dynamic>? sourceContext;
  final String graphAssetPath;
  final String planAssetPath;
  final ClipVideoStore? videoStore;
  final Future<XFile?> Function()? pickVideo;

  @override
  State<ClipProductionPlanScreen> createState() => _ClipProductionPlanScreenState();
}

class _ClipProductionPlanScreenState extends State<ClipProductionPlanScreen> {
  AssetBundle? _bundle;
  late Future<LoadedClipPlan> _loading;
  late ClipVideoStore _videoStore;
  Map<String, ClipVideoBinding> _bindings = {};
  Map<String, bool> _videoExists = {};
  final _videoMessages = <String, String>{};
  bool _bindingsReady = false;
  String? _bindingError;
  String? _busyClip;
  String? _currentPlanId;
  int _loadEpoch = 0;

  @override
  void initState() {
    super.initState();
    _videoStore = widget.videoStore ?? ClipVideoStore(documentsDirectory: getApplicationDocumentsDirectory);
  }

  Future<LoadedClipPlan> _load() async {
    final epoch = ++_loadEpoch;
    final provided = widget.providedPlan;
    if (provided != null) {
      provided.graph.validate();
      provided.plan.validateAgainst(provided.graph);
      provided.plan.d01ObservationDurations(provided.graph, requireTiming: true);
      return provided;
    }
    final data = await ClipProductionPlanScreen.loadPlanAssets(
      _bundle!, graphAssetPath: widget.graphAssetPath, planAssetPath: widget.planAssetPath,
    );
    final graph = data.graph;
    final plan = data.plan;
    try {
      final bindings = await _videoStore.loadPlan(plan.planId);
      final exists = <String, bool>{};
      for (final entry in bindings.entries) {
        exists[entry.key] = await _videoStore.fileExists(entry.value);
      }
      if (mounted && epoch == _loadEpoch) {
        _bindings = Map.of(bindings);
        _videoExists = exists;
        _bindingsReady = true;
        _bindingError = null;
      }
    } catch (_) {
      if (mounted && epoch == _loadEpoch) {
        _bindings = {};
        _videoExists = {};
        _bindingsReady = false;
        _bindingError = 'Video eşlemeleri okunamadı. Kayıtlar değiştirilmedi; yeniden yüklemeyi deneyin.';
      }
    }
    if (mounted && epoch == _loadEpoch) _currentPlanId = plan.planId;
    return (graph: graph, plan: plan);
  }

  Future<void> _selectVideo(String planId, String clipId) async {
    if (!_bindingsReady || _busyClip != null) return;
    setState(() {
      _busyClip = clipId;
      _videoMessages.remove(clipId);
    });
    var selecting = true;
    try {
      final selected = await (widget.pickVideo?.call() ?? ImagePicker().pickVideo(source: ImageSource.gallery));
      if (selected == null || !mounted) return; // İptal: mevcut eşlemeye dokunma.
      selecting = false;
      final result = await _videoStore.attach(
        planId: planId, clipId: clipId, source: File(selected.path), fileName: selected.name,
      );
      if (mounted && _currentPlanId == planId) {
        setState(() {
          _bindings[clipId] = result.binding;
          _videoExists[clipId] = true;
          if (result.warning != null) _videoMessages[clipId] = result.warning!;
        });
      }
    } catch (_) {
      if (mounted && _currentPlanId == planId) {
        setState(() {
          _videoMessages[clipId] = selecting
              ? 'Video seçilemedi. Galeri iznini kontrol edip tekrar deneyin; önceki eşleme korundu.'
              : 'Video kopyalanamadı veya eşleme kaydedilemedi. Önceki eşleme korundu.';
        });
      }
    } finally {
      if (mounted) setState(() { _busyClip = null; });
    }
  }

  Future<void> _removeVideo(String planId, String clipId) async {
    if (!_bindingsReady || _busyClip != null) return;
    setState(() {
      _busyClip = clipId;
      _videoMessages.remove(clipId);
    });
    try {
      final warning = await _videoStore.remove(planId: planId, clipId: clipId);
      if (mounted && _currentPlanId == planId) {
        setState(() {
          _bindings.remove(clipId);
          _videoExists.remove(clipId);
          if (warning != null) _videoMessages[clipId] = warning;
        });
      }
    } catch (_) {
      if (mounted && _currentPlanId == planId) {
        setState(() {
          _videoMessages[clipId] = 'Bağlantı kaldırılamadı; kayıt hatası nedeniyle önceki eşleme korundu.';
        });
      }
    } finally {
      if (mounted) setState(() { _busyClip = null; });
    }
  }

  Widget _videoControls(String planId, String clipId) {
    final binding = _bindings[clipId];
    final status = !_bindingsReady ? 'Video durumu okunamadı'
        : binding == null ? 'Video yok'
        : _videoExists[clipId] == true ? 'Video bağlı' : 'Dosya bulunamadı';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Text(status, key: ValueKey('clip-video-status:$clipId'), style: const TextStyle(fontWeight: FontWeight.bold)),
        if (binding != null) SelectableText(binding.fileName, key: ValueKey('clip-video-name:$clipId')),
        const Text('İncelenmedi: video bağlanması davranışı, süreyi veya sürekliliği doğrulamaz.'),
        if (binding != null) const Text('Başka bir video seçerek değiştirebilirsiniz.'),
        if (_videoMessages[clipId] case final String message)
          Text(message, key: ValueKey('clip-video-message:$clipId')),
        if (_busyClip == clipId) const LinearProgressIndicator(),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            if (_bindingsReady && binding != null && _videoExists[clipId] == true)
              OutlinedButton.icon(
                key: ValueKey('preview-clip-video:$clipId'),
                onPressed: _busyClip != null ? null : () {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ClipVideoPreviewScreen(
                      binding: binding,
                      videoStore: _videoStore,
                    ),
                  ));
                },
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Videoyu izle'),
              ),
            OutlinedButton.icon(
              key: ValueKey('select-clip-video:$clipId'),
              onPressed: !_bindingsReady || _busyClip != null ? null : () => _selectVideo(planId, clipId),
              icon: const Icon(Icons.video_library_outlined),
              label: const Text('Video seç'),
            ),
            if (binding != null)
              TextButton(
                key: ValueKey('remove-clip-video:$clipId'),
                onPressed: !_bindingsReady || _busyClip != null ? null : () => _removeVideo(planId, clipId),
                child: const Text('Bağlantıyı kaldır'),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _export(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tam metin kopyalandı.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Metin kopyalanamadı.')));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bundle = DefaultAssetBundle.of(context);
    if (_bundle != bundle) {
      _bundle = bundle;
      _loading = _load();
    }
  }

  @override
  void didUpdateWidget(covariant ClipProductionPlanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoStore != widget.videoStore) {
      _videoStore = widget.videoStore ?? ClipVideoStore(documentsDirectory: getApplicationDocumentsDirectory);
    }
    if (oldWidget.providedPlan != widget.providedPlan || oldWidget.graphAssetPath != widget.graphAssetPath ||
        oldWidget.planAssetPath != widget.planAssetPath || oldWidget.videoStore != widget.videoStore) {
      _loading = _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      title: const Text('Klip Üretim Planı'),
      backgroundColor: _navy,
      foregroundColor: Colors.white,
    ),
    body: SafeArea(
      child: FutureBuilder<LoadedClipPlan>(
        future: _loading,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Klip üretim planı açılamadı.'),
                    const SizedBox(height: 8),
                    Text(error is FormatException
                        ? 'Graf veya klip planı doğrulanamadı: ${error.message}'
                        : 'Örnek dosyaları okunamadı. Tekrar deneyebilirsiniz.'),
                    OutlinedButton(
                      onPressed: () {
                        final loading = _load();
                        setState(() {
                          _loading = loading;
                        });
                      },
                      child: const Text('Tekrar dene'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final durationTarget = _productionTarget(widget.sourceContext);
          final clipLimit = _productionClipLimit(widget.sourceContext);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.providedPlan == null
                    ? 'Elle hazırlanmış üretim planıdır; video veya gözlem kanıtı değildir'
                    : 'Sunucudan üretilmiş plan taslağı; içerik onayı veya hazır video değildir. D01 videolarına bağlı değildir.',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: _navy),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hazır D01 için “Grafı dene” kontrolü yalnız debug derlemesinde görünür. '
                  'Bu görünürlük kullanıcı yetkilendirmesi değildir; üretilen planın içeriği ayrıca incelenmelidir.',
                ),
                const SizedBox(height: 8),
                Text('${data.graph.scenes.length} sahne · ${data.plan.clips.length} klip kaydı · zorunlu klip üst sınırı $clipLimit sn',
                  key: const ValueKey('clip-plan-count-summary')),
                Text('Davranışlar: ${data.graph.behaviors.map((ref) => ref.behaviorId).join(', ')}',
                  key: const ValueKey('clip-plan-behavior-summary')),
                const Text('Sahne ve klip sayıları farklıdır; bir sahnede birden fazla klip olabilir. Dalların süreleri birbirine eklenmez.'),
                if (durationTarget != null)
                  Text('Toplam süre hedefi: $durationTarget sn (hedef; gerçek video ölçümü değildir).',
                    key: const ValueKey('clip-plan-duration-target')),
                _buildPathDurationSummary(data.graph, data.plan, durationTarget),
                if (widget.sourceContext != null) ...[
                  Text('Senaryo: ${data.graph.scenarioId} · kaynak: ${widget.sourceContext!['source']}',
                    key: const ValueKey('clip-plan-source')),
                  OutlinedButton(key: const ValueKey('export-plan-source'),
                    onPressed: () => _export(jsonEncode(widget.sourceContext)),
                    child: const Text('Özgün istek, ham cevap ve üretim kaynağını kopyala')),
                ],
                if (kDebugMode && widget.providedPlan == null)
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('open-graph-playback'),
                        onPressed: _busyClip != null ? null : () {
                          Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => GraphPlaybackScreen(
                              graph: data.graph,
                              plan: data.plan,
                              videoStore: _videoStore,
                            ),
                          ));
                        },
                        icon: const Icon(Icons.account_tree_outlined),
                        label: const Text('Grafı dene'),
                      ),
                    ],
                  ),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    key: const ValueKey('export-plan-json'),
                    onPressed: () => _export(widget.rawPlanJson ?? data.plan.toJsonString(pretty: true)),
                    icon: const Icon(Icons.copy), label: const Text('Plan JSON’unu kopyala'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('export-plan-prompts'),
                    onPressed: () => _export(planPromptText(data.graph, data.plan)),
                    icon: const Icon(Icons.copy), label: const Text('Tüm promptları kopyala'),
                  ),
                ]),
                if (data.plan.visualSuggestions != null)
                  ExpansionTile(title: const Text('Üretilmiş görsel öneriler — incelenmedi'),
                    children: [SelectableText(data.plan.visualSuggestions!)]),
                if (_bindingError != null) ...[
                  Text(_bindingError!),
                  TextButton(
                    onPressed: _busyClip != null ? null : () {
                      final loading = _load();
                      setState(() { _loading = loading; });
                    },
                    child: const Text('Video eşlemelerini yeniden yükle'),
                  ),
                ],
                ExpansionTile(
                  title: const Text('Planlama ve gözlem sınırları'),
                  children: [
                    SelectableText(data.plan.authoringNote),
                    if (data.plan.d01CallTiming != null) ...[
                      const Text('Planlanan çağrı bitişleri — ölçülmüş video zamanı değildir'),
                      for (final call in data.plan.d01CallTiming!)
                        Text('${call.clipId}: klip içinde ${call.callEndS} sn'),
                      for (final entry in data.plan.d01ObservationDurations(data.graph).entries)
                        Text('${entry.key}: çağrı sonrası planlanan ${entry.value} sn'),
                      const Text('Bu süre hesabı klinik tepki eşiği veya kesintisiz video kanıtı değildir.'),
                    ],
                  ],
                ),
                ExpansionTile(
                  title: const Text('Karakter, ortam ve nesne sürekliliği'),
                  children: [SelectableText(data.plan.continuityNotes)],
                ),
                for (final section in _sections(data.graph)) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 20, bottom: 8),
                    child: Text(section.title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _navy)),
                  ),
                  for (final scene in section.scenes)
                    Card(
                      color: const Color(0xFFF3F5F8),
                      child: ExpansionTile(
                        key: ValueKey('clip-scene:${scene.id}'),
                        title: Text(scene.title ?? scene.id),
                        subtitle: Text(
                          '${data.graph.scenes.indexOf(scene) + 1}. sahne · ${scene.id} · ${data.plan.clipsForScene(scene.id).length} klip · '
                          '${data.plan.clipsForScene(scene.id).fold<double>(0, (sum, clip) => sum + clip.targetDurationS)} sn planlandı · '
                          '${data.graph.behaviorIdsFor(scene).join(', ')}'
                          '${scene.id == data.graph.startSceneId ? ' · Başlangıç' : ''}'
                          '${data.graph.endSceneIds.contains(scene.id) ? ' · Bitiş' : ''}',
                        ),
                        children: [
                          for (final clip in data.plan.clipsForScene(scene.id))
                            _ClipDetails(clip: clip, behaviorIds: data.graph.behaviorIdsFor(scene), videoControls: widget.providedPlan == null
                              ? _videoControls(data.plan.planId, clip.id) : const SizedBox.shrink()),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    ),
  );
}

const _navy = Color(0xFF142540);

class _ClipDetails extends StatelessWidget {
  const _ClipDetails({required this.clip, required this.videoControls, required this.behaviorIds});
  final PlannedClip clip;
  final Widget videoControls;
  final List<String> behaviorIds;

  Widget _field(String title, String value) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        SelectableText(value),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('production-clip:${clip.id}'),
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 8),
    color: Colors.white,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${clip.orderInScene}. klip · Hedef süre: ${clip.targetDurationS} sn',
            style: const TextStyle(fontWeight: FontWeight.bold, color: _navy)),
        SelectableText(clip.id),
        Text('Bu klibin sahnesindeki davranışlar: ${behaviorIds.join(', ')}'),
        _field('Planlanan eylem', clip.plannedAction),
        _field('Başlangıç durumu', clip.initialState),
        _field('Bitiş durumu', clip.finalState),
        videoControls,
        _field('Tam üretim promptu', clip.productionPrompt),
        if (clip.voiceoverInstructions != null)
          _field('Ayrı seslendirme yönergeleri', clip.voiceoverInstructions!),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: ValueKey('copy-clip-prompt:${clip.id}'),
          onPressed: () async {
            try {
              await Clipboard.setData(ClipboardData(text: clip.productionPrompt));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Üretim promptu kopyalandı.')),
                );
              }
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Prompt kopyalanamadı. Tekrar deneyin.')),
                );
              }
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('Promptu kopyala'),
        ),
      ],
    ),
  );
}

typedef _Section = ({String title, List<ScenarioScene> scenes});
typedef _PathDuration = ({String label, double seconds});

int? _productionTarget(Map<String, dynamic>? sourceContext) {
  final request = sourceContext?['request'];
  if (request is! Map) return null;
  final production = request['production'];
  if (production is! Map) return null;
  final target = production['targetDurationS'];
  return target is int && target > 0 ? target : null;
}

int _productionClipLimit(Map<String, dynamic>? sourceContext) {
  final request = sourceContext?['request'];
  if (request is! Map) return 8;
  final production = request['production'];
  if (production is! Map) return 8;
  final limit = production['maxClipDurationS'];
  return limit is int && limit > 0 && limit <= 8 ? limit : 8;
}

List<_PathDuration> _pathDurations(ScenarioGraph graph, ScenarioClipPlan plan) {
  final outgoing = <String, List<ScenarioTransition>>{
    for (final scene in graph.scenes)
      scene.id: graph.transitions.where((edge) => edge.fromSceneId == scene.id).toList(),
  };
  final paths = <_PathDuration>[];
  var cycle = false;
  var tooMany = false;

  void visit(String sceneId, Set<String> ancestors, List<String> branchLabels, double seconds) {
    if (cycle || tooMany) return;
    if (ancestors.contains(sceneId)) {
      cycle = true;
      return;
    }
    final nextAncestors = {...ancestors, sceneId};
    final sceneDuration = plan.clipsForScene(sceneId).fold<double>(
      0,
      (total, clip) => total + clip.targetDurationS,
    );
    final nextSeconds = seconds + sceneDuration;
    if (graph.endSceneIds.contains(sceneId)) {
      if (paths.length == 100) {
        tooMany = true;
        return;
      }
      paths.add((
        label: branchLabels.isEmpty ? 'Tek doğrusal yol' : branchLabels.join(' → '),
        seconds: nextSeconds,
      ));
      return;
    }
    final edges = outgoing[sceneId] ?? const <ScenarioTransition>[];
    if (edges.isEmpty) {
      cycle = true; // Yapısal olarak terminal olmayan ve bitişe ulaşmayan yol.
      return;
    }
    for (final edge in edges) {
      final label = edge.label?.trim().isNotEmpty == true ? edge.label!.trim() : edge.description;
      visit(edge.toSceneId, nextAncestors,
        edges.length > 1 ? [...branchLabels, label] : branchLabels, nextSeconds);
    }
  }

  visit(graph.startSceneId, const <String>{}, const <String>[], 0);
  if (cycle) throw const FormatException('Döngü veya tamamlanmayan yol nedeniyle tek bir sonlu süre hesaplanamıyor.');
  if (tooMany) throw const FormatException('Yol sayısı özet sınırını aşıyor; süreler ayrı ayrı gösterilemiyor.');
  if (paths.isEmpty) throw const FormatException('Başlangıçtan bir bitişe giden süre hesaplanamadı.');
  return paths;
}

String _formatPlanSeconds(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

String _formatPlanDifference(double value) => value > 0
    ? '+${_formatPlanSeconds(value)}'
    : value < 0 ? '−${_formatPlanSeconds(value.abs())}' : '0';

Widget _buildPathDurationSummary(ScenarioGraph graph, ScenarioClipPlan plan, int? target) {
  late final List<_PathDuration> paths;
  try {
    paths = _pathDurations(graph, plan);
  } on FormatException catch (error) {
    return Text(error.message, key: const ValueKey('clip-plan-path-duration-error'));
  }
  return ExpansionTile(
    key: const ValueKey('clip-plan-path-durations'),
    initiallyExpanded: paths.length == 1,
    title: Text(paths.length == 1 ? 'Tek yolun planlanan süresi' : 'Her alternatif yolun planlanan süresi'),
    subtitle: Text(paths.length == 1 ? 'Tek yol' : '${paths.length} ayrı yol; süreler birleştirilmez'),
    children: [
      for (var index = 0; index < paths.length; index++)
        ListTile(
          key: ValueKey('clip-plan-path-duration:$index'),
          title: Text(paths[index].label),
          subtitle: Text(target == null
              ? 'Planlanan yol toplamı: ${_formatPlanSeconds(paths[index].seconds)} sn; video ölçümü değildir.'
              : 'Planlanan yol toplamı: ${_formatPlanSeconds(paths[index].seconds)} sn · hedef $target sn · '
                  'fark ${_formatPlanDifference(paths[index].seconds - target)} sn; video ölçümü değildir.'),
        ),
    ],
  );
}

/// İlk ayrımın ortak sahneleri bir kez, ayrı devamları kendi başlıklarında.
/// Dal seçmez; verilen grafın mevcut bağlantılarını görselleştirir.
List<_Section> _sections(ScenarioGraph graph) {
  final outgoing = {
    for (final scene in graph.scenes)
      scene.id: graph.transitions.where((edge) => edge.fromSceneId == scene.id).toList(),
  };
  final forks = graph.scenes.where((scene) => outgoing[scene.id]!.length > 1).toList();
  if (forks.isEmpty) return [(title: 'Ortak sahneler', scenes: graph.scenes)];
  final branches = outgoing[forks.first.id]!;
  Set<String> reachable(String start) {
    final seen = <String>{};
    final pending = [start];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (seen.add(id)) pending.addAll(outgoing[id]!.map((edge) => edge.toSceneId));
    }
    return seen;
  }
  final paths = [for (final branch in branches) reachable(branch.toSceneId)];
  int count(String id) => paths.where((path) => path.contains(id)).length;
  return [
    (title: branches.length == 2 ? 'Ortak sahneler · iki dal için tek kez'
        : 'Ortak sahneler · ${branches.length} dal için tek kez',
     scenes: graph.scenes.where((scene) => count(scene.id) != 1).toList()),
    for (var i = 0; i < branches.length; i++)
      (title: 'Alternatif: ${branches[i].label ?? branches[i].description}',
       scenes: graph.scenes.where((scene) => count(scene.id) == 1 && paths[i].contains(scene.id)).toList()),
  ];
}

/// Metinlerin tamamı ve sıraları korunur; görsel prompt/seslendirme karıştırılmaz.
String planPromptText(ScenarioGraph graph, ScenarioClipPlan plan) {
  plan.validateAgainst(graph);
  return [
    'Plan: ${plan.planId} / Senaryo: ${plan.scenarioId}',
    plan.authoringNote, 'Süreklilik:\n${plan.continuityNotes}',
    if (plan.d01CallTiming != null)
      for (final call in plan.d01CallTiming!)
        'Planlanan D01 çağrı bitişi: ${call.clipId}, klip içinde ${call.callEndS} sn (ölçüm değil)',
    if (plan.visualSuggestions != null) 'Üretilmiş görsel öneriler:\n${plan.visualSuggestions}',
    for (final scene in graph.scenes)
      for (final clip in plan.clipsForScene(scene.id))
        'Sahne: ${scene.id} / Davranışlar: ${graph.behaviorIdsFor(scene).join(', ')} / Klip: ${clip.id} / Sıra: ${clip.orderInScene} / Hedef süre: ${clip.targetDurationS} s\n'
        'Eylem:\n${clip.plannedAction}\nBaşlangıç:\n${clip.initialState}\nBitiş:\n${clip.finalState}\n'
        'Görsel üretim promptu:\n${clip.productionPrompt}\n'
        'Ayrı seslendirme yönergeleri:\n${clip.voiceoverInstructions ?? 'Belirtilmedi'}',
  ].join('\n\n');
}
