import 'dart:io';
import '../services/graph_playback_controller.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/clip_video_store.dart';
import 'package:flutter/services.dart';
import '../models/scenarios_data.dart';
import '../models/behavior_cards.dart';
import '../models/scenario_generation_request.dart';
import '../models/scenario_behavior_ref.dart';
import '../models/scenario_input.dart';
import '../widgets/scenario_narrative_cards.dart';
import '../models/scenario_generation_result.dart';
import '../services/scenario_draft_store.dart';
import '../services/clip_plan_generation_service.dart';
import '../services/scenario_generation_service.dart';
import 'graph_playback_screen.dart';
import 'clip_production_plan_screen.dart';
import 'scenario_graph_import_screen.dart';
import 'scenario_comparison_dialog.dart';
import '../services/synthetic_video_service.dart';
import '../services/server_api_service.dart';
import '../services/http_scenario_generation_service.dart';
import 'scenario_graph_screen.dart';

class BundledGraphPlaybackExample {
  const BundledGraphPlaybackExample({
    required this.id,
    required this.title,
    required this.graphAssetPath,
    required this.planAssetPath,
    required this.videoAssetsByClipId,
    required this.notice,
  });

  final String id;
  final String title;
  final String graphAssetPath;
  final String planAssetPath;
  final Map<String, String> videoAssetsByClipId;
  final String notice;
}

const d01NameTurningExample = BundledGraphPlaybackExample(
  id: 'd01_name_turning_20261024',
  title: 'D01 videolu örneği: İsme yönelme',
  graphAssetPath: 'assets/scenarios/d01_name_turning_graph.json',
  planAssetPath: 'assets/scenarios/d01_name_turning_clip_plan.json',
  videoAssetsByClipId: {
    'd01_name_common': 'assets/videos/d01_name_turning/20261024200425.mp4',
    'd01_name_mother_1': 'assets/videos/d01_name_turning/20261024200833.mp4',
    'd01_name_mother_2': 'assets/videos/d01_name_turning/20261024204922.mp4',
    'd01_name_play_1': 'assets/videos/d01_name_turning/20261024201633.mp4',
    'd01_name_play_2': 'assets/videos/d01_name_turning/20261024202154.mp4',
    'd01_name_other_1': 'assets/videos/d01_name_turning/20261024202847.mp4',
    'd01_name_other_2': 'assets/videos/d01_name_turning/20261024203806.mp4',
  },
  notice: 'İnsan incelemesiyle hazırlanmış kısa sentetik oynatma örneğidir; otomatik analiz sonucu değildir. Video içeriği, sürekliliği ve gözlem süresi doğrulanmamıştır.',
);

const d02PointingDirectionExample = BundledGraphPlaybackExample(
  id: 'd02_pointing_direction_20261024',
  title: 'D02 videolu örneği: İşaret yönü',
  graphAssetPath: 'assets/scenarios/d02_pointing_direction_graph.json',
  planAssetPath: 'assets/scenarios/d02_pointing_direction_clip_plan.json',
  videoAssetsByClipId: {
    'd02_point_common': 'assets/videos/d02_pointing_direction/20261024214654.mp4',
    'd02_point_shelf_1': 'assets/videos/d02_pointing_direction/20261024220131.mp4',
    'd02_point_shelf_2': 'assets/videos/d02_pointing_direction/20261024225140.mp4',
    'd02_point_table_1': 'assets/videos/d02_pointing_direction/20261024222918.mp4',
    'd02_point_table_2': 'assets/videos/d02_pointing_direction/20261024224133.mp4',
  },
  notice: 'Raf yönüne dönme etiketi doğru nesneye bakışın doğrulandığı anlamına gelmez. Bu kısa sentetik örnek otomatik analiz sonucu değildir; içerik ve süreklilik ayrıca incelenmelidir.',
);

class SyntheticVideoStudioScreen extends StatefulWidget {
  final String? initialOntologyCode;
  final int? initialAgeMonths;
  final ClipVideoStore? playbackVideoStore;
  final GraphClipPlayer Function(File)? createPlaybackPlayer;
  final HttpScenarioGenerationService? comparisonService;
  final ScenarioGenerationService? generationService;
  final ScenarioDraftStore? scenarioDraftStore;
  final ClipPlanGenerationService? clipPlanService;

  const SyntheticVideoStudioScreen({
    super.key,
    this.initialOntologyCode,
    this.initialAgeMonths,
    this.playbackVideoStore,
    this.createPlaybackPlayer,
    this.comparisonService,
    this.generationService,
    this.scenarioDraftStore,
    this.clipPlanService,
  });

  @override
  State<SyntheticVideoStudioScreen> createState() => _SyntheticVideoStudioScreenState();
}

class _SyntheticVideoStudioScreenState extends State<SyntheticVideoStudioScreen> {
  bool _openingD01Playback = false;

  Future<LoadedClipPlan> _loadBundledExample(
    AssetBundle bundle,
    ClipVideoStore store,
    BundledGraphPlaybackExample example,
    bool Function() isCancelled,
  ) async {
    final loaded = await ClipProductionPlanScreen.loadPlanAssets(
      bundle,
      graphAssetPath: example.graphAssetPath,
      planAssetPath: example.planAssetPath,
    );
    if (isCancelled()) throw StateError('Örnek yüklemesi iptal edildi.');
    final clipIds = loaded.plan.clips.map((clip) => clip.id).toSet();
    if (clipIds.length != example.videoAssetsByClipId.length ||
        !clipIds.containsAll(example.videoAssetsByClipId.keys)) {
      throw const FormatException('Örnek video eşlemeleri klip planıyla uyuşmuyor.');
    }

    var bindings = await store.loadPlan(loaded.plan.planId);
    for (final clip in loaded.plan.clips) {
      if (isCancelled()) throw StateError('Örnek yüklemesi iptal edildi.');
      final current = bindings[clip.id];
      if (current != null) {
        if (!await store.fileExists(current)) {
          throw FileSystemException('Örnek klibinin kayıtlı video kopyası bulunamadı: ${clip.id}.');
        }
        continue;
      }
      final assetPath = example.videoAssetsByClipId[clip.id]!;
      final data = await bundle.load(assetPath);
      if (isCancelled()) throw StateError('Örnek yüklemesi iptal edildi.');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await store.attachBytes(
        planId: loaded.plan.planId,
        clipId: clip.id,
        bytes: bytes,
        fileName: assetPath.split('/').last,
      );
      bindings = await store.loadPlan(loaded.plan.planId);
    }
    for (final clip in loaded.plan.clips) {
      final binding = bindings[clip.id];
      if (binding == null || !await store.fileExists(binding)) {
        throw FileSystemException('Örnek klibinin videosu kullanılamıyor: ${clip.id}.');
      }
    }
    return loaded;
  }

  Future<void> _openBundledExample(BundledGraphPlaybackExample example) async {
    if (_openingD01Playback) return;
    setState(() { _openingD01Playback = true; });
    final bundle = DefaultAssetBundle.of(context);
    final store = widget.playbackVideoStore ??
        ClipVideoStore(documentsDirectory: getApplicationDocumentsDirectory);
    var left = false;
    final loading = _loadBundledExample(bundle, store, example, () => left || !mounted);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PopScope<void>(
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) left = true;
            },
            child: FutureBuilder<LoadedClipPlan>(
              future: loading,
              builder: (context, snapshot) {
                if (left || !mounted) return const SizedBox.shrink();
                if (snapshot.hasData) {
                  return GraphPlaybackScreen(
                    graph: snapshot.data!.graph,
                    plan: snapshot.data!.plan,
                    videoStore: store,
                    createPlayer: widget.createPlaybackPlayer,
                    title: example.title,
                    notice: example.notice,
                  );
                }
                return Scaffold(
                  appBar: AppBar(
                    title: Text(example.title),
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                  ),
                  body: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: snapshot.hasError
                          ? Text(
                              '${example.title} açılamadı. Video eşlemesini veya paket kaynağını kontrol edin.',
                              key: ValueKey('${example.id}-load-error'),
                            )
                          : const CircularProgressIndicator(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() { _openingD01Playback = false; });
    }
  }

  Future<void> _openD01Playback() async {
    if (_openingD01Playback) return;
    setState(() { _openingD01Playback = true; });
    final bundle = DefaultAssetBundle.of(context);
    final store = widget.playbackVideoStore ??
        ClipVideoStore(documentsDirectory: getApplicationDocumentsDirectory);
    Future<LoadedClipPlan>? loading;
    var left = false;
    try {
      await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PopScope<void>(
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) left = true;
          },
          child: FutureBuilder<LoadedClipPlan>(
          future: loading ??= ClipProductionPlanScreen.loadPlanAssets(bundle),
          builder: (context, snapshot) {
            if (left || !mounted) return const SizedBox.shrink();
            if (snapshot.hasData) {
              return GraphPlaybackScreen(
                graph: snapshot.data!.graph,
                plan: snapshot.data!.plan,
                videoStore: store,
                createPlayer: widget.createPlaybackPlayer,
                title: 'D01 videolu örnek',
                notice: 'Örnek videoların içeriği ve sürekliliği doğrulanmadı.',
              );
            }
            return Scaffold(
              appBar: AppBar(
                title: const Text('D01 videolu örnek'),
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
              ),
              body: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: snapshot.hasError
                      ? const Text(
                          'D01 videolu örnek açılamadı. Daha sonra tekrar deneyebilirsiniz.',
                          key: ValueKey('d01-playback-load-error'),
                        )
                      : const CircularProgressIndicator(),
                ),
              ),
            );
          },
        ),
        ),
      ),
    );
    } finally {
      if (mounted) setState(() { _openingD01Playback = false; });
    }
  }

  // SENARYO TÜRÜ: 'doctor' (Tür 1: Doktor Klinik Senaryosu - Saniyesiz) veya 'video' (Tür 2: Sentetik Video & Prompt Stüdyosu - Saniyeli)
  String _scenarioType = 'doctor';

  // MOTOR SEÇİMİ: 'local' (0 MB Yerel Klinik), 'server' (Sunucu Gemini AI)
  String _selectedEngine = 'local';
  Map<String, dynamic>? get _lastBenchmark => _normalResult?.measurement;
  Map<String, dynamic>? get _lastComparison => _normalResult == null ? null :
      {'model': _normalResult!.model, 'sourceMode': 'Ortak anlatı sözleşmesi'};
  String? get _lastArm => _normalResult?.arm;

  // DOKTOR KLİNİK PARAMETRELERİ (SANİYESİZ)
  int _selectedAge = 18;
  Set<String> _selectedOntologies = {'D01', 'D02', 'D03'};
  String _selectedRisk = 'atipik';

  // GÖRÜNÜM MODU: 'steps' (Adım Adım Akış) veya 'unified' (Birleşik Tek Senaryo Kartı)
  String _scenarioViewMode = 'steps';

  // ADMİN PARAMETRELERİ (SADECE ADMİNE ÖZEL SANİYELİK VİDEO DİLİMLEME)
  int _selectedTotalSec = 210; // 3.5 dakika (180 - 240 sn arası)
  int _selectedDuration = 8; // 3 - 10 sn arası

  // ÇIKTILAR (TÜR 1 ve TÜR 2)
  DoctorClinicalScenario? _doctorScenario;
  SyntheticVideoSession? _session;
  bool _isGenerating = false;
  int _generationRequest = 0;
  final TextEditingController _teamAccessKeyController = TextEditingController();
  ScenarioGenerationJob? _activeNarrativeJob;
  final _closedNarrativeJobs = Expando<bool>();
  final _productionAge = TextEditingController();
  final _productionContext = TextEditingController();
  final _productionInstructions = TextEditingController();
  ScenarioGenerationRequest? _productionRequest;
  String? _productionSignature, _productionError, _normalError, _normalErrorRaw;
  ScenarioGenerationResult? _normalResult;
  bool _openingWorkspace = false;
  String _productionStructure = 'branched';
  bool _productionGoals = false, _productionAttempted = false;
  bool _openingComparison = false;
  bool _confirmingStudioExit = false, _allowStudioExit = false;
  bool get _hasProductionDraft {
    final initial = widget.initialOntologyCode == null ? {'D01', 'D02', 'D03'} : {widget.initialOntologyCode!};
    return (_isGenerating && _selectedEngine == 'server') || _normalResult != null || _normalErrorRaw != null ||
      _productionContext.text.isNotEmpty || _productionInstructions.text.isNotEmpty ||
      (_productionAge.text.isNotEmpty && _productionAge.text != (widget.initialAgeMonths ?? 18).toString()) ||
      _productionGoals || _productionStructure != 'branched' ||
      _selectedOntologies.length != initial.length || !initial.every(_selectedOntologies.contains);
  }
  String get _currentProductionSignature => jsonEncode([
    _selectedOntologies.toList(), _productionAge.text, _productionContext.text, _productionInstructions.text,
    _productionStructure, _productionGoals, if (_productionGoals || _productionStructure == 'linear26') ...[_selectedTotalSec, _selectedDuration]]);
  String? get _productionAgeError {
    final value = _productionAge.text.trim();
    if (value.isEmpty && !_productionAttempted) return null;
    final age = RegExp(r'^[0-9]+$').hasMatch(value) ? int.tryParse(value) : null;
    return age == null || age < 12 || age > 36 ? '12–36 arasında tam ay girin.' : null;
  }
  String? get _productionContextError => _productionAttempted && _productionContext.text.trim().isEmpty
    ? 'Ortamı ve sahneyi kısaca yazın.' : null;

  HttpScenarioGenerationService get _httpService =>
      (widget.comparisonService ?? const HttpScenarioGenerationService())
        .withAccessKey(() => _teamAccessKeyController.text.trim());

  ScenarioGenerationRequest? _validatedProductionRequest() {
    setState(() { _productionAttempted = true; });
    try {
      if (_selectedOntologies.isEmpty) {
        throw const FormatException('En az bir davranış seçin.');
      }
      final cards = BehaviorCards.all.where((card) => _selectedOntologies.contains(card.id)).toList();
      if (cards.length != _selectedOntologies.length) throw const FormatException('Güncel D01–D10 kartlarını seçin.');
      final ageText = _productionAge.text.trim();
      final age = RegExp(r'^[0-9]+$').hasMatch(ageText) ? int.tryParse(ageText) : null;
      if (age == null || age < 12 || age > 36) throw const FormatException('12–36 arasında tam ay girin.');
      if (_productionContext.text.trim().isEmpty) throw const FormatException('Ortamı ve sahneyi kısaca yazın.');
      final request = ScenarioGenerationRequest(behaviorId: cards.first.id,
        cardVersion: cards.first.cardVersion, behaviors: [for (final card in cards)
          ScenarioBehaviorRef(behaviorId: card.id, cardVersion: card.cardVersion)],
        ageMonths: age, sceneContext: _productionContext.text,
        additionalInstructions: _productionInstructions.text.trim().isEmpty ? null : _productionInstructions.text,
        production: _productionGoals || _productionStructure == 'linear26' ? ScenarioProductionSettings(
          structure: _productionStructure, targetDurationS: _selectedTotalSec, maxClipDurationS: _selectedDuration) : null);
      final signature = _currentProductionSignature;
      if (_productionSignature != signature) {
        _productionRequest = request;
        _productionSignature = signature;
      }
      setState(() { _productionError = null; });
      return _productionRequest;
    } on FormatException catch (error) {
      setState(() { _productionError = error.message.toString(); _productionRequest = null; _productionSignature = null; });
      return null;
    }
  }

  Future<void> _closeNarrativeJob(ScenarioGenerationJob job, {bool cancel = false}) async {
    if (_closedNarrativeJobs[job] == true) return;
    _closedNarrativeJobs[job] = true;
    if (cancel) unawaited(Future<void>.sync(job.cancel).catchError((Object _) {}));
    try { await job.dispose(); } catch (_) { /* Önceki sonuç korunur. */ }
  }

  Future<void> _openWorkspace([ScenarioGenerationResult? result, HttpScenarioGenerationService? service]) async {
    if (_openingWorkspace) return;
    _openingWorkspace = true;
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ScenarioGraphImportScreen(
        initialScenarioContent: true, incomingResult: result,
        draftStore: widget.scenarioDraftStore ?? const ScenarioDraftStore(),
        clipPlanService: widget.clipPlanService ?? service ?? _httpService)));
    } finally { _openingWorkspace = false; }
  }

  Future<void> _requestStudioExit() async {
    if (_confirmingStudioExit || _allowStudioExit) return;
    _confirmingStudioExit = true;
    try {
      final leave = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Stüdyo taslağı bırakılıp çıkılsın mı?'),
        content: const Text('Kaydedilmemiş bilgiler kaybolabilir. Süren isteğin yerel izlemesi durdurulur; '
          'sunucu işinin iptali doğrulanmış sayılmaz.'),
        actions: [FilledButton(key: const ValueKey('studio-exit-stay'), autofocus: true,
          onPressed: () => Navigator.pop(ctx, false), child: const Text('Ekranda kal')),
          TextButton(key: const ValueKey('studio-exit-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Çık'))]));
      if (!mounted || leave != true) return;
      setState(() { _allowStudioExit = true; });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && ModalRoute.of(context)?.isCurrent == true) Navigator.of(context).pop();
    } finally { _confirmingStudioExit = false; }
  }

  Widget _serverRequestFields() => Column(
    key: const ValueKey('studio-request-form'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Seçtiğiniz davranışlar ve bu bilgiler üretimde birlikte kullanılır.'),
      const SizedBox(height: 12),
      TextField(key: const ValueKey('scenario-request-context'), controller: _productionContext,
        readOnly: _isGenerating, minLines: 2, maxLines: 4,
        decoration: const InputDecoration(labelText: 'Ortam ve sahne', helperText: 'Bu alan gereklidir.',
          helperMaxLines: 2, border: OutlineInputBorder())),
      if (_productionContextError != null) Text(_productionContextError!,
        key: ValueKey(_productionAgeError == null ? 'scenario-request-error' : 'scenario-request-context-error'),
        style: TextStyle(color: Theme.of(context).colorScheme.error)),
      const SizedBox(height: 10),
      TextField(key: const ValueKey('scenario-request-instructions'), controller: _productionInstructions,
        readOnly: _isGenerating, minLines: 1, maxLines: 4,
        decoration: const InputDecoration(labelText: 'Ek yönerge', helperText: 'İsteğe bağlı.', helperMaxLines: 2,
          border: OutlineInputBorder())),
      const SizedBox(height: 12),
      const Text('Senaryonun düzeni', style: TextStyle(fontWeight: FontWeight.bold)),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final entry in (const {'branched': 'Alternatifli anlatı', 'linear26': '26 sahnelik doğrusal anlatı'}).entries)
          ChoiceChip(key: ValueKey('scenario-structure-${entry.key}'), label: Text(entry.value),
            selectedColor: const Color(0xFFDDEBFF), labelStyle: const TextStyle(color: Color(0xFF142540)),
            selected: _productionStructure == entry.key, onSelected: _isGenerating ? null : (_) => setState(() {
              _productionStructure = entry.key; _productionRequest = null; _productionSignature = null; _productionError = null;
            })),
      ]),
      Text(_productionStructure == 'linear26' ? '26 sahne sırayla ilerler; kendiliğinden alternatif eklenmez.'
        : 'Ortak başlangıcın ardından birbirinden ayrı devamlar hazırlanır.'),
      if (_productionStructure == 'linear26' && _selectedTotalSec > 26 * _selectedDuration)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '26 sahneye birer klip ve klip başına en fazla $_selectedDuration sn varsayımıyla '
            'hedef süreye ulaşılamaz. En az ${(_selectedTotalSec + _selectedDuration - 1) ~/ _selectedDuration} klip gerekir; '
            'klip sayısı sabit değildir ve bir sahne birden fazla klip içerebilir.',
            key: const ValueKey('scenario-production-duration-capacity-note'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ExpansionTile(title: const Text('Süre ve klip hedefleri'), maintainState: true, children: [
        if (_productionStructure != 'linear26') SwitchListTile(key: const ValueKey('scenario-production-goals'),
          title: const Text('Süre hedefi belirt'), value: _productionGoals,
          onChanged: _isGenerating ? null : (value) => setState(() { _productionGoals = value; _productionRequest = null; _productionError = null; })),
        if (_productionGoals || _productionStructure == 'linear26') ...[
          _buildTimePickerField(title: 'Toplam süre hedefi', currentValue: _selectedTotalSec, options: const [30,60,120,210],
            minCustomSec: 1, maxCustomSec: 3600, onSelected: (value) {
              if (!_isGenerating) setState(() { _selectedTotalSec = value; _productionRequest = null; _productionError = null; });
            }),
          _buildTimePickerField(title: 'Klip başına zorunlu üst sınır', currentValue: _selectedDuration, options: const [4,6,8],
            minCustomSec: 1, maxCustomSec: 8, onSelected: (value) {
              if (!_isGenerating) setState(() { _selectedDuration = value; _productionRequest = null; _productionError = null; });
            }),
          const Text('Toplam süre bir hedeftir; klip başına üst sınır zorunludur. Sahne veya klip sayısı hedef süreyi garanti etmez. Planlanan yol süreleri sonuçta ayrı gösterilir; video süresi değildir.'),
        ],
      ]),
      ExpansionTile(key: const ValueKey('scenario-request-rules'), title: const Text('Kaynak ve kullanım sınırları'), children: [
        for (final card in BehaviorCards.all.where((card) => _selectedOntologies.contains(card.id)))
          Text('${card.title} · Kart sürümü: ${card.cardVersion}'),
        const Text('Ek yönerge kart kurallarını değiştirmez. Seçilebilir kartlar doğrulanmış analiz desteği değildir. '
          'Eski gözlem profili ve Doktor/Video türü çevrimdışı şablona aittir. Anahtarsız gizli admin girişi yetkilendirme değildir.'),
      ]),
      OutlinedButton(key: const ValueKey('scenario-request-validate'),
        onPressed: _isGenerating ? null : _validatedProductionRequest,
        child: const Text('Üretim isteğini doğrula')),
      if (_productionError != null && _productionAgeError == null && _productionContextError == null)
        Text(_productionError!, key: const ValueKey('scenario-request-error')),
      if (_productionRequest != null && _productionSignature == _currentProductionSignature)
        Text('${_productionRequest!.cards.map((card) => card.title).join(' / ')} · '
          '${_productionRequest!.ageMonths} ay\n${_productionRequest!.sceneContext}',
          key: const ValueKey('scenario-request-summary')),
    ],
  );

  Widget _normalResultView() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (_isGenerating && _selectedEngine == 'server')
      const Text('Senaryo yanıtı bekleniyor…', key: ValueKey('scenario-generation-status')),
    if (_normalError != null) Text(_normalError!, key: const ValueKey('scenario-generation-error')),
    if (_normalErrorRaw != null) ExpansionTile(key: const ValueKey('studio-error-raw-details'),
      title: const Text('Başarısız isteğin ham cevabı'), children: [
      SizedBox(height: 200, child: SingleChildScrollView(child: SelectableText(_normalErrorRaw!,
        key: const ValueKey('scenario-generation-error-raw')))),
      TextButton(onPressed: () => _copyToClipboard(_normalErrorRaw!, 'Ham hata cevabı kopyalandı.'),
        child: const Text('Ham hata cevabını kopyala')),
    ]),
    if (_normalResult != null) ...[
      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('2. İncele',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF142540)))),
      Text(_normalResult!.summary, key: const ValueKey('studio-result-summary')),
      const Text('Yapı geçerli; içerik henüz onaylanmadı. Önceki sonuç form değişse de kendi isteğine aittir.'),
      FilledButton(key: const ValueKey('studio-continue-result'),
        onPressed: _isGenerating || _openingWorkspace ? null : () => _openWorkspace(_normalResult),
        child: const Text('Bu senaryoyla devam et')),
      ScenarioNarrativeCards(input: ScenarioInput.fromJsonString(_normalResult!.request.prepareInput(
        _normalResult!.rawResponse, scenarioId: _normalResult!.scenarioId, edited: false).json), request: _normalResult!.request),
      ExpansionTile(key: const ValueKey('studio-result-details'), title: const Text('Tam ham cevap ve üretim kaynağı'), children: [
        SizedBox(height: 220, child: SingleChildScrollView(child: SelectableText(_normalResult!.rawResponse,
          key: const ValueKey('scenario-generation-raw')))),
        SelectableText(jsonEncode(_normalResult!.toJson()..remove('rawResponse'))),
        TextButton(key: const ValueKey('studio-copy-result-raw'), onPressed: () => _copyToClipboard(_normalResult!.rawResponse, 'Ham cevap kopyalandı.'),
          child: const Text('Tam ham cevabı kopyala')),
      ]),
    ],
  ]);

  // ADMİN MODU (EASTER EGG - BAŞLIĞA 5 TIKLA AÇILIR)
  int _easterEggTapCount = 0;
  DateTime? _lastEasterEggTap;
  bool _isAdminMode = false;

  void _handleEasterEggTap() {
    final now = DateTime.now();
    if (_lastEasterEggTap == null || now.difference(_lastEasterEggTap!) > const Duration(seconds: 2)) {
      _easterEggTapCount = 1;
    } else {
      _easterEggTapCount++;
    }
    _lastEasterEggTap = now;

    if (_easterEggTapCount >= 5) {
      _easterEggTapCount = 0;
      HapticFeedback.heavyImpact();
      setState(() {
        _isAdminMode = !_isAdminMode;
        _scenarioType = _isAdminMode ? 'video' : 'doctor';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                _isAdminMode ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isAdminMode
                      ? 'Gelişmiş Stüdyo Modu Açıldı (Klip Parametreleri ve Doğrulama Paneli Aktif).'
                      : 'Doktor Moduna Dönüldü.',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: _isAdminMode ? const Color(0xFF0F172A) : const Color(0xFF475569),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );
    } else if (_easterEggTapCount >= 2) {
      HapticFeedback.lightImpact();
    }
  }

  // KLİP VE VİDEO PARAMETRELERİ (ADMİN AKORDİYON AYARLARI)
  bool _isClipSettingsExpanded = false;

  // SAHNE AKORDİYONU (AÇIK OLAN SAHNE İNDEKSLERİ)
  final Set<int> _expandedSceneIndices = {};

  void _toggleSceneExpanded(int index) {
    setState(() {
      if (_expandedSceneIndices.contains(index)) {
        _expandedSceneIndices.remove(index);
      } else {
        _expandedSceneIndices.add(index);
      }
    });
  }

  void _toggleAllScenesExpanded(bool expand, int totalCount) {
    setState(() {
      if (expand) {
        _expandedSceneIndices.addAll(List.generate(totalCount, (i) => i));
      } else {
        _expandedSceneIndices.clear();
      }
    });
  }

  String _formatTimeRange(int startSec, int endSec) {
    String fmt(int s) =>
        '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
    return '${fmt(startSec)} - ${fmt(endSec)}';
  }

  String get _sharedCharacterPrompt {
    return 'Cinematic 35mm film still, locked-off stationary tripod at 45cm low child-eye level, f/2.8 aperture, soft 5500K diffused morning natural daylight. '
        'A photorealistic $_selectedAge-month-old toddler with short brown hair, wearing a solid powder-blue crewneck cotton t-shirt and charcoal knit joggers, sitting barefoot on a Scandinavian light ash wooden floor with a navy-and-cream geometric wool rug. '
        'In the background, an adult female clinician in a beige knit sweater is seated quietly observing. '
        'Anatomically accurate hands with five distinct fingers, stable physics, no morphing, 4K photorealistic documentary realism.';
  }

  // MODEL DOĞRULAMA (GROUND-TRUTH VS AI) METRİKLERİ
  bool _isValidationExpanded = true;



  @override
  void initState() {
    super.initState();
    if (widget.initialOntologyCode != null) {
      _selectedOntologies = {widget.initialOntologyCode!};
    }
    if (widget.initialAgeMonths != null) {
      _selectedAge = widget.initialAgeMonths!;
    }
    _productionAge.text = _selectedAge.toString();
    for (final controller in [_productionAge, _productionContext, _productionInstructions]) {
      controller.addListener(() {
        if (mounted) setState(() { _productionRequest = null; _productionSignature = null; _productionError = null; });
      });
    }
    ServerApiService.getBaseUrl().then((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _generateScenario();
      }
    });
  }

  @override
  void didUpdateWidget(covariant SyntheticVideoStudioScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool shouldRegenerate = false;
    if (widget.initialOntologyCode != null && widget.initialOntologyCode != oldWidget.initialOntologyCode) {
      _selectedOntologies = {widget.initialOntologyCode!, ..._selectedOntologies};
      shouldRegenerate = true;
    }
    if (widget.initialAgeMonths != null && widget.initialAgeMonths != oldWidget.initialAgeMonths) {
      _selectedAge = widget.initialAgeMonths!;
      _productionAge.text = _selectedAge.toString();
      shouldRegenerate = true;
    }
    // Yalnız yerel şablon otomatik yenilenebilir; sunucu/model çağrısı
    // kullanıcı eylemi olmadan başlatılmaz.
    if (shouldRegenerate && _selectedEngine != 'server') {
      _generateScenario();
    }
  }

  @override
  void dispose() {
    ++_generationRequest;
    final activeJob = _activeNarrativeJob;
    _activeNarrativeJob = null;
    if (activeJob != null) {
      unawaited(_closeNarrativeJob(activeJob, cancel: true));
    }
    _teamAccessKeyController.dispose();
    _productionAge.dispose();
    _productionContext.dispose();
    _productionInstructions.dispose();
    super.dispose();
  }

  String _getRiskLabel(String risk) {
    switch (risk.toLowerCase()) {
      case 'atipik':
        return 'Şüpheli / Atipik';
      case 'gecikmeli':
        return 'Gecikmeli';
      case 'tipik':
        return 'Normal (Tipik)';
      default:
        return risk;
    }
  }

  int _generationSeed = 0;

  void _generateScenario({bool incrementSeed = false}) {
    if (_isGenerating) return;
    final server = _selectedEngine == 'server';
    final productionRequest = server ? _validatedProductionRequest() : null;
    if (server && productionRequest == null) return;
    if (incrementSeed) {
      _generationSeed++;
    }
    final request = ++_generationRequest;
    if (_selectedOntologies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce bir davranış seçin.')),
      );
      return;
    }
    final currentSeed = _generationSeed;
    setState(() => _isGenerating = true);
    Future.delayed(const Duration(milliseconds: 250), () async {
      if (!mounted || request != _generationRequest) return;
      if (server) {
        ScenarioGenerationJob? job;
        String? receivedRaw;
        try {
          final snapshot = productionRequest!;
          final service = widget.generationService ?? _httpService;
          if (!service.isAvailable) throw ScenarioGenerationFailure(service.availabilityMessage);
          job = (service is HttpScenarioGenerationService
              ? service.withAccessKey(() => _teamAccessKeyController.text.trim()) : service).start(snapshot);
          _activeNarrativeJob = job;
          final raw = await job.response;
          receivedRaw = raw;
          if (!mounted || request != _generationRequest) return;
          final metadata = job is ScenarioGenerationMetadataJob
              ? (job as ScenarioGenerationMetadataJob).metadata
              : null;
          final result = ScenarioGenerationResult.fromServer(snapshot,
            {'rawResponse': raw, ...?metadata});
          setState(() { _normalResult = result; _normalError = null; _normalErrorRaw = null; });
        } catch (error) {
          if (!mounted || request != _generationRequest) return;
          setState(() {
            _normalError = error is ScenarioGenerationFailure ? error.message :
              error is FormatException ? error.message.toString() : 'Senaryo alınamadı; önceki sonuç korundu.';
            _normalErrorRaw = error is ScenarioGenerationFailure ? error.rawResponse ?? receivedRaw : receivedRaw;
          });
        } finally {
          if (job != null) unawaited(_closeNarrativeJob(job));
          if (identical(_activeNarrativeJob, job)) _activeNarrativeJob = null;
          if (mounted && request == _generationRequest) setState(() { _isGenerating = false; });
        }      } else {
        // YEREL MOTOR (LOCAL RULE-BASED)
        if (_scenarioType == 'doctor') {
          final doc = SyntheticVideoPromptService.generateDoctorScenario(
            ageMonths: _selectedAge,
            ontologyCodes: _selectedOntologies.toList(),
            riskProfile: _selectedRisk,
            variationSeed: currentSeed,
          );
          final sess = SyntheticVideoPromptService.generateSession(
            ageMonths: _selectedAge,
            totalTargetSec: _selectedTotalSec,
            blockDurationSec: _selectedDuration,
            riskProfile: _selectedRisk,
            ontologyCodes: _selectedOntologies.toList(),
            variationSeed: currentSeed,
          );
          if (mounted) {
            setState(() {
              _doctorScenario = doc;
              _session = sess;
              _isGenerating = false;
            });
          }
        } else {
          final sess = SyntheticVideoPromptService.generateSession(
            ageMonths: _selectedAge,
            totalTargetSec: _selectedTotalSec,
            blockDurationSec: _selectedDuration,
            riskProfile: _selectedRisk,
            ontologyCodes: _selectedOntologies.toList(),
            variationSeed: currentSeed,
          );
          if (mounted) {
            setState(() {
              _session = sess;
              _isGenerating = false;
            });
          }
        }
      }
    });
  }

  Future<void> _cancelServerGeneration() async {
    if (!_isGenerating || _selectedEngine != 'server') return;
    final epoch = ++_generationRequest;
    final job = _activeNarrativeJob;
    _activeNarrativeJob = null;
    setState(() {
      _isGenerating = false;
      _normalError = 'Yerel bekleme durduruldu; sunucudaki model işinin iptali doğrulanmadı.';
    });
    if (job != null) {
      final cancellation = Future<void>.sync(job.cancel);
      unawaited(_closeNarrativeJob(job));
      try {
        await cancellation;
        if (mounted && epoch == _generationRequest) setState(() { _normalError = 'Üretim hizmeti iptal bildirdi; önceki sonuç korundu.'; });
      } on ScenarioGenerationCancellationUnconfirmed {
        // HTTP bağlantısını bırakmak sağlayıcı iptali değildir.
      } catch (_) {
        if (mounted && epoch == _generationRequest) {
          setState(() {
            _normalError = 'İptal isteği başarısız; yerel sonuç takibi durduruldu. Sunucu işinin durduğu doğrulanmadı.';
          });
        }
      }
    }
  }

  void _copyToClipboard(String text, String successMsg) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(successMsg, style: const TextStyle(fontSize: 13))),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        toolbarHeight: MediaQuery.textScalerOf(context).scale(14.5) > 20 ? 160 : kToolbarHeight,
        title: GestureDetector(
          key: const ValueKey('studio-admin-title'),
          behavior: HitTestBehavior.opaque,
          onTap: _handleEasterEggTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Text(
                  _selectedEngine == 'server' ? 'Senaryo hazırlama' : _scenarioType == 'doctor'
                      ? 'Doktor Klinik Protokolü'
                      : 'Sentetik Video Stüdyosu',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                ),
              if (_isAdminMode) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'ADMİN',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_selectedEngine == 'server')
            IconButton(icon: const Icon(Icons.copy_all_outlined, size: 20), tooltip: 'Sunucu ham cevabını kopyala',
              onPressed: _normalResult == null ? null : () => _copyToClipboard(_normalResult!.rawResponse, 'Tam ham cevap kopyalandı.'))
          else if (_scenarioType == 'doctor' && _doctorScenario != null)
            IconButton(
              icon: const Icon(Icons.copy_all_outlined, size: 20),
              tooltip: 'Klinik Protokolü Kopyala (Markdown)',
              onPressed: () {
                _copyToClipboard(
                  _doctorScenario!.exportDoctorMarkdown(),
                  'Klinik protokol ve karar dalları panoya kopyalandı!',
                );
              },
            )
          else if (_scenarioType == 'video' && _session != null)
            IconButton(
              icon: const Icon(Icons.copy_all_outlined, size: 20),
              tooltip: _isAdminMode ? 'Tüm Video Promptlarını Kopyala (Admin)' : 'Senaryoyu Kopyala',
              onPressed: () {
                if (_isAdminMode) {
                  _copyToClipboard(
                    _session!.exportEnglishPromptsOnly(),
                    'Tüm video promptları panoya kopyalandı!',
                  );
                } else {
                  _copyToClipboard(
                    _session!.exportDoctorCleanScenario(),
                    'Klinik gözlem senaryosu panoya kopyalandı!',
                  );
                }
              },
            ),
          if (_selectedEngine != 'server' && _scenarioType == 'video' && _isAdminMode && _session != null) ...[
            IconButton(
              icon: const Icon(Icons.data_object_outlined, size: 20),
              tooltip: 'JSON Dışa Aktar (Admin)',
              onPressed: () {
                _copyToClipboard(
                  _session!.exportGroundTruthJson(),
                  'Senaryo JSON formatında kopyalandı!',
                );
              },
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ADMİN BİLGİLENDİRME ŞERİDİ VE TÜR DEĞİŞTİRİCİ (SADECE GİZLİ ADMİN MODUNDA GÖRÜNÜR)
            if (_isAdminMode) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF38BDF8), size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Gelişmiş Stüdyo Modu Açık (Klip dilimleme ve doğrulama araçları aktif)',
                        style: TextStyle(fontSize: 11.5, color: Colors.white, height: 1.3),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF38BDF8),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () {
                        setState(() {
                          _isAdminMode = false;
                          _scenarioType = 'doctor';
                        });
                      },
                      child: const Text('Kapat', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // SENARYO TÜRÜ SEÇİCİ (SADECE ADMİNDE GÖRÜNÜR)
              _buildScenarioTypeSwitcher(),
              if (_selectedEngine == 'server') const Text(
                'Doktor/Video tür araçları çevrimdışı şablon içindir. Kullanmak için Yerel motoru seçin.'),
              const SizedBox(height: 14),
            ],

            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('1. Hazırla',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF142540)))),
            // Aynı form; sunucu anlatısı veya açıkça etiketlenmiş çevrimdışı şablon.
            _buildEngineSelectorCard(),
            const SizedBox(height: 14),



            // 2. DOKTOR PARAMETRE AYARLARI KARTI (SANİYESİZ, KLİNİK ODAKLI)
            _buildDoctorConfigCard(),
            const SizedBox(height: 14),
            _normalResultView(),
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Hazır örnekler ve diğer araçlar',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF142540)))),
            Material(
              key: const ValueKey('studio-tools-surface'),
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  ListTile(
                    key: const ValueKey('open-d01-playback'),
                    enabled: !_openingD01Playback,
                    dense: true,
                    leading: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.play_circle_outline_rounded, color: Color(0xFF2563EB), size: 20),
                    ),
                    title: const Text('Hazır D01 örneği: videolu dallı oynatma', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: _openingD01Playback ? null : _openD01Playback,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF1F5F9)),
                  ListTile(
                    key: const ValueKey('open-d01-name-turning-playback'),
                    enabled: !_openingD01Playback,
                    dense: true,
                    leading: const Icon(Icons.account_tree_outlined, color: Color(0xFF2563EB)),
                    title: const Text('D01 örneği: İsme yönelme'),
                    subtitle: const Text('Ortak başlangıç ve seçilebilir üç kısa devam.'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: _openingD01Playback ? null : () => _openBundledExample(d01NameTurningExample),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF1F5F9)),
                  ListTile(
                    key: const ValueKey('open-d02-pointing-playback'),
                    enabled: !_openingD01Playback,
                    dense: true,
                    leading: const Icon(Icons.assistant_direction_outlined, color: Color(0xFF2563EB)),
                    title: const Text('D02 örneği: İşaret yönü'),
                    subtitle: const Text('Ortak başlangıç ve seçilebilir iki kısa devam.'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: _openingD01Playback ? null : () => _openBundledExample(d02PointingDirectionExample),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF1F5F9)),
                  ListTile(
                    key: const ValueKey('open-clip-production-plan'),
                    dense: true,
                    leading: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.video_library_outlined, color: Color(0xFF0F172A), size: 20),
                    ),
                    title: const Text('Hazır D01 klip planı ve video eşleme', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const ClipProductionPlanScreen()),
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF1F5F9)),
                  ListTile(
                    key: const ValueKey('open-scenario-content'),
                    dense: true,
                    leading: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.input_rounded, color: Color(0xFF10B981), size: 20),
                    ),
                    title: const Text('Dallı senaryo → graf → klip planı', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: const Text('Yeni taslaklar sabit D01 videolarına bağlı değildir.'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => _openWorkspace(),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF1F5F9)),
                  ListTile(
                    key: const ValueKey('open-scenario-graph'),
                    dense: true,
                    leading: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF64748B).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.account_tree_outlined, color: Color(0xFF64748B), size: 20),
                    ),
                    title: const Text('Hazır D01 grafını görüntüle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const ScenarioGraphScreen()),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),



            // 3. MODEL DOĞRULAMA (GROUND-TRUTH VE BAŞARIM TESTİ - SADECE GİZLİ ADMİN MODUNDA)
            if (_isAdminMode) ...[
              _buildModelValidationCard(),
              const SizedBox(height: 16),
            ],

            // 5. ÜRETİLEN SENARYO VE KLİNİK AKIŞ
            if (_isGenerating)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: Color(0xFF0F172A)),
                      SizedBox(height: 14),
                      Text(
                        'Senaryo Oluşturuluyor...',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                      ),
                    ],
                  ),
                ),
              )
            else if (_selectedEngine != 'server' && _scenarioType == 'doctor' && _doctorScenario != null) ...[
              _buildDoctorScenarioView(_doctorScenario!),
            ] else if (_selectedEngine != 'server' && _scenarioType == 'video' && _session != null) ...[
              if (_session!.isUnreviewedGenerationDraft)
                Container(
                  key: const ValueKey('studio-unreviewed-26-scene-draft'),
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('26 sahnelik üretim taslağıdır; içerik ve video incelenmemiştir. Planlanan olaylar gözlenmiş bulgu değildir.'),
                ),
              if (!_session!.isUnreviewedGenerationDraft)
                const Text('Hazır şablon; model çıkarımı yapılmadı',
                    key: ValueKey('studio-template-source')),
              // GÖRÜNÜM SEÇENEĞİ (Adım Adım / Tek Metin Birleşik)
              _buildViewModeToggle(),
              const SizedBox(height: 10),

              if (_scenarioViewMode == 'steps') ...[
                if (_isAdminMode || _scenarioType == 'video') ...[
                  _buildAdminClipsHeader(),
                  const SizedBox(height: 12),
                ],
                // ORTAK KARAKTER & ORTAM ŞABLONU (AYRI VE NET KUTU)
                _buildSharedEnvironmentCard(),
                // SAHNE SAHNE KATLANABİLİR KLİP AKORDİYONU (1. YOL)
                _buildSceneAccordionSection(),
              ] else ...[
                _buildUnifiedScenarioCard(),
              ],
            ],
          ],
        ),
      ),
    );
    if (ModalRoute.of(context)?.canPop != true) return screen;
    return PopScope<void>(canPop: _allowStudioExit || !_hasProductionDraft,
      onPopInvokedWithResult: (didPop, result) { if (!didPop) unawaited(_requestStudioExit()); }, child: screen);
  }

  /// Gölge dışarıda; renk/kenarlık ve dokunma mürekkebi aynı Material'da çizilir.
  Widget _buildCardSurface({required EdgeInsetsGeometry padding,
    required BoxDecoration decoration, required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: decoration.borderRadius, boxShadow: decoration.boxShadow),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: decoration.borderRadius,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: decoration.copyWith(boxShadow: const <BoxShadow>[]),
          padding: padding,
          child: child,
        ),
      ),
    );
  }

  /// HİBRİT MOTOR SEÇİCİ (2 MOTOR: 0 MB YEREL KLİNİK vs SUNUCU GEMINI AI)
  Widget _buildEngineSelectorCard() {
    final isLocal = _selectedEngine == 'local';
    final isServer = _selectedEngine == 'server';

    return _buildCardSurface(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Row(
                children: [
                  Icon(Icons.tune_rounded, size: 18, color: Color(0xFF0F172A)),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'Üretim Motoru',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A)),
                  )),
                ],
              ),
              Wrap(
                spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isServer ? const Color(0xFF10B981).withValues(alpha: 0.1) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isServer ? 'Sunucu • Gemini AI' : 'Yerel • Çevrimdışı',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: isServer ? const Color(0xFF047857) : const Color(0xFF475569),
                      ),
                    ),
                  ),
                  if (isServer) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined, size: 16, color: Color(0xFF2563EB)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Gelişmiş bağlantı ayarları',
                      onPressed: _showServerConfigDialog,
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // MOTOR 1: YEREL MOTOR (ÇEVRİMDIŞI)
              Expanded(
                child: InkWell(
                  key: const ValueKey('studio-engine-local'),
                  onTap: _isGenerating ? null : () {
                    setState(() => _selectedEngine = 'local');
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                    decoration: BoxDecoration(
                      color: isLocal ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isLocal ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                        width: isLocal ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.bolt_rounded,
                          color: isLocal ? Colors.amberAccent : const Color(0xFF64748B),
                          size: 24,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Yerel Motor',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isLocal ? Colors.white : const Color(0xFF1E293B),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Çevrimdışı Şablon',
                          style: TextStyle(
                            fontSize: 10,
                            color: isLocal ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // MOTOR 2: YEREL SUNUCU (GEMINI AI)
              Expanded(
                child: InkWell(
                  key: const ValueKey('studio-engine-server'),
                  onTap: _isGenerating ? null : () {
                    setState(() => _selectedEngine = 'server');
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                    decoration: BoxDecoration(
                      color: isServer ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isServer ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                        width: isServer ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.cloud_sync_rounded,
                          color: isServer ? const Color(0xFF34D399) : const Color(0xFF64748B),
                          size: 24,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Sunucu (Gemini AI)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isServer ? Colors.white : const Color(0xFF1E293B),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Yapay Zeka (Bulut)',
                          style: TextStyle(
                            fontSize: 10,
                            color: isServer ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (isServer) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      const Icon(Icons.psychology_outlined, size: 16, color: Color(0xFF4F46E5)),
                      const SizedBox(width: 6),
                      const Text(
                        'Senaryo karşılaştırması:',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                      ),

                      InkWell(
                        key: const ValueKey('studio-open-comparison'),
                        onTap: _runLiveComparisonDialog,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFC7D2FE)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.compare_arrows_rounded, size: 13, color: Color(0xFF4F46E5)),
                              SizedBox(width: 4),
                              Flexible(child: Text(
                                'A/B/C karşılaştır',
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                              )),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6, runSpacing: 6, children: [
                      _buildArmChip('A', 'Kol A (Saf)', 'Ek kart yok', const Color(0xFF64748B)),
                      _buildArmChip('B', 'Kol B (RAG)', 'Hedef Kural', const Color(0xFF2563EB)),
                      _buildArmChip('C', 'Kol C (Full)', 'Tüm Kitaplık', const Color(0xFF7C3AED)),
                    ],
                  ),
                  if (_lastBenchmark != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Icon(Icons.speed_outlined, size: 14, color: Color(0xFF64748B)),
                          Text(
                            'Son çıktı (${_lastArm ?? 'normal'}) · sağlayıcı: ${_lastBenchmark!['providerDurationMs'] is num ? '${_lastBenchmark!['providerDurationMs']} ms' : 'Bilinmiyor'} · toplam: ${_lastBenchmark!['endpointDurationMs'] is num ? '${_lastBenchmark!['endpointDurationMs']} ms' : 'Bilinmiyor'}',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                          ),
                          Text(
                            'Model/kaynak: ${_lastComparison?['model'] ?? 'Bilinmiyor'} · ${_lastComparison?['sourceMode'] ?? 'Bilinmiyor'}',
                            style: const TextStyle(fontSize: 10.5, color: Color(0xFF334155)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('studio-team-access-key'),
              controller: _teamAccessKeyController,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              readOnly: _isGenerating,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Ekip anahtarı',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  key: const ValueKey('studio-team-access-clear'),
                  tooltip: 'Erişim anahtarını temizle',
                  onPressed: _isGenerating || _teamAccessKeyController.text.isEmpty
                      ? null
                      : () => setState(() { _teamAccessKeyController.clear(); }),
                  icon: const Icon(Icons.clear),
                ),
              ),
            ),
            const Text('Anahtar yalnız bu Stüdyo oturumu boyunca bellekte tutulur.'),
            const Text('Üretim tüm seçili kartları kullanır. Kaynakları kıyaslamak için A/B/C’yi açın.'),
          ],
        ],
      ),
    );
  }

  Widget _buildArmChip(String code, String title, String subtitle, Color activeColor) {
    final isSelected = ServerApiService.selectedArm == code;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 100, maxWidth: 220),
      child: InkWell(
        key: ValueKey('studio-arm-$code'),
        onTap: _isGenerating ? null : () {
          ServerApiService.setSelectedArm(code);
          setState(() {});
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? activeColor : const Color(0xFFCBD5E1),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? activeColor : const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 9,
                  color: isSelected ? activeColor : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runLiveComparisonDialog() async {
    if (_isGenerating || _openingComparison) return;
    final request = _validatedProductionRequest();
    if (request == null) return;
    _openingComparison = true;
    try {
      await showDialog<void>(context: context, barrierDismissible: false,
        builder: (_) => ScenarioComparisonDialog(request: request, service: _httpService,
          initialSelection: ServerApiService.selectedArm,
          onContinue: (result, service) => _openWorkspace(result, service)));
    } finally { _openingComparison = false; }
  }
  void _showServerConfigDialog() {
    final controller = TextEditingController(text: ServerApiService.baseUrl);
    String? testResult;
    bool isTesting = false;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.router_rounded, color: Color(0xFF2563EB), size: 22),
                  SizedBox(width: 8),
                  Text('Gelişmiş bağlantı ayarları', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Uygulama varsayılan sunucuya otomatik bağlanır. Yalnız farklı bir sunucu kullanıyorsanız adresi burada değiştirin.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: 'Sunucu Adresi (URL)',
                      hintText: 'http://192.168.110.42:8000',
                      prefixIcon: const Icon(Icons.link_rounded, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      ActionChip(
                        label: const Text('Örnek yerel adres', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          controller.text = 'http://192.168.110.42:8000';
                          setDialogState(() {});
                        },
                      ),
                      ActionChip(
                        label: const Text('Emülatör (10.0.2.2)', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          controller.text = 'http://10.0.2.2:8000';
                          setDialogState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Karşılaştırmada seçilecek kol:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('Kol B: Kural Enj. (RAG)', style: TextStyle(fontSize: 11)),
                        selected: ServerApiService.selectedArm == 'B',
                        selectedColor: const Color(0xFFDBEAFE),
                        onSelected: (val) {
                          if (val) {
                            ServerApiService.setSelectedArm('B');
                            setDialogState(() {});
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Kol A: Baseline (Saf)', style: TextStyle(fontSize: 11)),
                        selected: ServerApiService.selectedArm == 'A',
                        selectedColor: const Color(0xFFE2E8F0),
                        onSelected: (val) {
                          if (val) {
                            ServerApiService.setSelectedArm('A');
                            setDialogState(() {});
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Kol C: Full-Context', style: TextStyle(fontSize: 11)),
                        selected: ServerApiService.selectedArm == 'C',
                        selectedColor: const Color(0xFFF3E8FF),
                        onSelected: (val) {
                          if (val) {
                            ServerApiService.setSelectedArm('C');
                            setDialogState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                  if (testResult != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: testResult!.startsWith('Bağlantı Başarılı') ? const Color(0xFFF0FDF4) : const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: testResult!.startsWith('Bağlantı Başarılı') ? const Color(0xFFBBF7D0) : const Color(0xFFFECDD3),
                        ),
                      ),
                      child: Text(
                        testResult!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: testResult!.startsWith('Bağlantı Başarılı') ? const Color(0xFF166534) : const Color(0xFF9F1239),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                OutlinedButton.icon(
                  onPressed: isTesting
                      ? null
                      : () async {
                          setDialogState(() {
                            isTesting = true;
                            testResult = 'Bağlantı test ediliyor...';
                          });
                          final status = await ServerApiService.checkHealth(controller.text.trim());
                          setDialogState(() {
                            isTesting = false;
                            if (status.isOnline) {
                              testResult = 'Bağlantı Başarılı\nSunucu yanıt verdi; model erişimi bu kontrolle doğrulanmadı.';
                            } else {
                              testResult = 'Bağlantı Başarısız\n${status.message}\n(Bilgisayar ve telefon aynı Wi-Fi ağında mı?)';
                            }
                          });
                        },
                  icon: isTesting
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering_rounded, size: 14),
                  label: const Text('Test Et', style: TextStyle(fontSize: 11.5)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    await ServerApiService.setBaseUrl(controller.text.trim());
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                    setState(() {});
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Sunucu adresi kaydedildi: ${ServerApiService.baseUrl}'),
                        backgroundColor: const Color(0xFF0F172A),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: const Text('Kaydet', style: TextStyle(fontSize: 12)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showOntologyPicker() {
    if (_isGenerating) return;
    final tempSelected = Set<String>.from(_selectedOntologies);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final allBehaviors = BehaviorCards.all;

            return Container(
              height: MediaQuery.of(context).size.height * 0.78,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    // Tutamaç (Handle)
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Hedef Davranışları Seçin',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${tempSelected.length} / ${allBehaviors.length} davranış seçili (D01–D10)',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () {
                                  setModalState(() {
                                    if (tempSelected.length == allBehaviors.length) {
                                      tempSelected.clear();
                                      tempSelected.add(allBehaviors.first.id);
                                    } else {
                                      tempSelected.clear();
                                      tempSelected.addAll(allBehaviors.map((b) => b.id));
                                    }
                                  });
                                },
                                child: Text(
                                  tempSelected.length == allBehaviors.length ? 'Temizle' : 'Tümünü Seç',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                                onPressed: () => Navigator.pop(ctx),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    // 12 Davranış Listesi
                    Expanded(
                      child: ListView.separated(
                        itemCount: allBehaviors.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: Color(0xFFF1F5F9),
                        ),
                        itemBuilder: (context, index) {
                          final card = allBehaviors[index];
                          final isSelected = tempSelected.contains(card.id);

                          return InkWell(
                            onTap: () {
                              setModalState(() {
                                if (isSelected) {
                                  if (tempSelected.length > 1) {
                                    tempSelected.remove(card.id);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('En az 1 hedef davranış seçili olmalıdır.'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                } else {
                                  tempSelected.add(card.id);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              child: Row(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFF0F172A) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                                        width: 1.8,
                                      ),
                                    ),
                                    child: isSelected
                                        ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFF0F172A).withValues(alpha: 0.08) : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      card.id,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          card.title,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                        Text(
                                          card.summary,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Onaylama Butonu
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            if (tempSelected.isNotEmpty) {
                              setState(() {
                                _selectedOntologies = tempSelected;
                              });
                            }
                          },
                          child: Text(
                            'Seçimi Kaydet (${tempSelected.length} Davranış)',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// DOKTOR PARAMETRELERİ (SANİYESİZ: YAŞ, ÇOKLU ONTOLOJİ, RİSK)
  Widget _buildDoctorConfigCard() {
    final allScenarios = ScenariosRepository.allScenarios;

    return _buildCardSurface(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. YAŞ SEÇİCİ
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Row(
                children: [
                  Icon(Icons.child_care_rounded, size: 18, color: Color(0xFF0F172A)),
                  SizedBox(width: 6),
                  Expanded(child: Text(
                    'Çocuğun Yaşı',
                    style: TextStyle(fontSize: 13.5, color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
                  )),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _selectedEngine == 'server' ? '12–36 ay' : '$_selectedAge Ay',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                ),
              ),
            ],
          ),
          if (_selectedEngine == 'server') ...[
            const SizedBox(height: 16),
            TextField(key: const ValueKey('scenario-request-age'), controller: _productionAge,
              readOnly: _isGenerating, keyboardType: const TextInputType.numberWithOptions(),
              decoration: const InputDecoration(labelText: 'Yaş (ay)', floatingLabelBehavior: FloatingLabelBehavior.always,
                hintText: '12–36', border: OutlineInputBorder())),
            if (_productionAgeError != null) Padding(padding: const EdgeInsets.only(top: 6),
              child: Text(_productionAgeError!, key: const ValueKey('scenario-request-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
          ]
          else Slider(
            value: _selectedAge.toDouble(),
            min: 12,
            max: 36,
            divisions: 24,
            activeColor: const Color(0xFF0F172A),
            inactiveColor: const Color(0xFFE2E8F0),
            label: '$_selectedAge Ay',
            onChanged: _isGenerating ? null : (val) {
              setState(() { _selectedAge = val.round(); _productionAge.text = _selectedAge.toString(); });
            },
          ),
          const SizedBox(height: 10),

          // 2. HEDEF DAVRANIŞLAR (ÇOKLU SEÇİM)
          const Text(
            'Hedef Davranışlar',
            style: TextStyle(fontSize: 13, color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._selectedOntologies.map((code) {
                final behaviorMatch = BehaviorCards.all.where((b) => b.id == code).firstOrNull;
                final titleText = behaviorMatch?.title ?? allScenarios.where((s) => s.code == code).firstOrNull?.title ?? code;
                return Container(
                  padding: const EdgeInsets.only(left: 8, top: 5, bottom: 5, right: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          code,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          titleText,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                        ),
                      )),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () {
                          if (_isGenerating) return;
                          if (_selectedOntologies.length > 1) {
                            setState(() {
                              _selectedOntologies.remove(code);
                            });
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('En az bir hedef davranış seçili olmalıdır.'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        behavior: HitTestBehavior.opaque,
                        child: const Padding(
                          padding: EdgeInsets.all(4.0),
                          child: Icon(Icons.close_rounded, size: 14, color: Color(0xFF64748B)),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              GestureDetector(
                onTap: _showOntologyPicker,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 15, color: Color(0xFF0F172A)),
                      SizedBox(width: 4),
                      Flexible(child: Text(
                        'Davranış Ekle',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      )),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_selectedEngine == 'server') _serverRequestFields(),
          // Yalnız eski çevrimdışı şablona ait parametreler.
          if (_selectedEngine != 'server') ...[
          const Text(
            'Gözlem Durumu',
            style: TextStyle(fontSize: 13, color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildRiskChip('atipik', 'Şüpheli / Atipik', Colors.red.shade700),
              _buildRiskChip('gecikmeli', 'Gecikmeli', Colors.amber.shade800),
              _buildRiskChip('tipik', 'Normal (Tipik)', Colors.green.shade700),
            ],
          ),
          ],

          // 4. EĞER ADMİN VİDEO MODUNDAYSA: KLİP VE VİDEO PARAMETRELERİ (AKORDİYON)
          if (_selectedEngine != 'server' && _isAdminMode && _scenarioType == 'video') ...[
            const SizedBox(height: 14),
            _buildAdminVideoSlicingCard(),
          ],
          const SizedBox(height: 16),

          // SENARYOYU YENİLE / ÜRET BUTONU (TÜM PARAMETRELERİN ALTINDA)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const ValueKey('studio-generate-scenario'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isGenerating ? null : () => _generateScenario(incrementSeed: true),
              icon: _isGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                _isGenerating
                    ? (_selectedEngine == 'server'
                        ? 'Senaryo taslağı hazırlanıyor...'
                        : 'Promptlar Yenileniyor...')
                    : (_scenarioType == 'doctor'
                        ? (_selectedEngine == 'server'
                            ? 'Senaryo üret'
                            : 'Klinik Protokolü Yenile')
                        : (_selectedEngine == 'server'
                            ? 'Senaryo üret'
                            : 'Sentetik Video Promptlarını Yenile')),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
          if (_isGenerating && _selectedEngine == 'server')
            TextButton.icon(
              key: const ValueKey('studio-cancel-generation'),
              onPressed: _cancelServerGeneration,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('İsteği durdur'),
            ),
        ],
      ),
    );
  }

  Future<void> _showCustomSecondsDialog({
    required String title,
    required int currentValue,
    required int minSec,
    required int maxSec,
    required ValueChanged<int> onSaved,
  }) async {
    final controller = TextEditingController(text: currentValue.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lütfen saniye cinsinden süre girin ($minSec - $maxSec saniye):', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  suffixText: 'saniye',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('İptal', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed != null && parsed >= minSec && parsed <= maxSec) {
                  Navigator.of(ctx).pop(parsed);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Lütfen $minSec ile $maxSec arasında geçerli bir saniye girin.')),
                  );
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
    if (result != null) {
      onSaved(result);
    }
  }

  Widget _buildTimePickerField({
    required String title,
    required int currentValue,
    required List<int> options,
    required ValueChanged<int> onSelected,
    required int minCustomSec,
    required int maxCustomSec,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 6),
        PopupMenuButton<int>(
          enabled: !_isGenerating,
          position: PopupMenuPosition.under,
          offset: const Offset(0, 4),
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          elevation: 4,
          onSelected: (val) {
            if (val == -1) {
              _showCustomSecondsDialog(
                title: title,
                currentValue: currentValue,
                minSec: minCustomSec,
                maxSec: maxCustomSec,
                onSaved: onSelected,
              );
            } else {
              onSelected(val);
            }
          },
          itemBuilder: (context) {
            final allOptions = options.contains(currentValue)
                ? options
                : ([...options, currentValue]..sort());

            return [
              ...allOptions.map((sec) {
                final isSelected = sec == currentValue;
                return PopupMenuItem<int>(
                  value: sec,
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 18,
                        color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        '$sec saniye',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF334155),
                        ),
                      )),
                    ],
                  ),
                );
              }),
              const PopupMenuDivider(),
              const PopupMenuItem<int>(
                value: -1,
                child: Row(
                  children: [
                    Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF0284C7)),
                    SizedBox(width: 10),
                    Expanded(child: Text(
                      'Özel Süre Gir...',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0284C7),
                      ),
                    )),
                  ],
                ),
              ),
            ];
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(
                  '$currentValue saniye',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
                )),
                const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF475569)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// SADECE ADMİNE ÖZEL: KLİP VE VİDEO PARAMETRELERİ (AKORDİYON VE AÇILIR LİSTE)
  Widget _buildAdminVideoSlicingCard() {
    final minimumClips = (_selectedTotalSec + _selectedDuration - 1) ~/ _selectedDuration;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TIKLANABİLİR BAŞLIK (AKORDİYON)
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _isClipSettingsExpanded = !_isClipSettingsExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.tune_rounded, color: Color(0xFF0F172A), size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Klip ve Video Parametreleri',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  // KAPALIYKEN ÖZET BİLGİ ROZETİ (SADECE SANİYE)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      '$_selectedTotalSec sn • $_selectedDuration sn / klip',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _isClipSettingsExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF64748B),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // GENİŞLEYEN AÇILIR LİSTE ALANI
          if (_isClipSettingsExpanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 14),
                  const Text(
                    'Sentetik video üretim seansı ve sahne süresi dilimleme ayarları:',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 14),

                  // AÇILIR LİSTE 1: TOPLAM SEANS SÜRESİ
                  _buildTimePickerField(
                    title: 'Toplam Seans Süresi',
                    currentValue: _selectedTotalSec,
                    options: const [180, 210, 240],
                    minCustomSec: 60,
                    maxCustomSec: 600,
                    onSelected: (val) {
                      setState(() => _selectedTotalSec = val);
                    },
                  ),
                  const SizedBox(height: 14),

                  // AÇILIR LİSTE 2: KLİP BAŞINA SÜRE
                  _buildTimePickerField(
                    title: 'Klip Başına Süre',
                    currentValue: _selectedDuration,
                    options: const [4, 5, 6, 8, 10],
                    minCustomSec: 2,
                    maxCustomSec: 30,
                    onSelected: (val) {
                      setState(() => _selectedDuration = val);
                    },
                  ),
                  const SizedBox(height: 14),

                  // HESAPLANAN DİLİMLEME PLANI (DİNAMİK)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.analytics_outlined, size: 16, color: Color(0xFF0284C7)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Süre hedefi $_selectedTotalSec sn; klip başına hedef üst sınır $_selectedDuration sn. '
                            'Teorik asgari klip sayısı $minimumClips; sahne sayısı ayrıdır ve bir sahne birden fazla klip içerebilir.',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRiskChip(String key, String label, Color color) {
    final sel = _selectedRisk == key;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      selectedColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: sel ? color : const Color(0xFFE2E8F0)),
      backgroundColor: const Color(0xFFF1F5F9),
      labelStyle: TextStyle(
        color: sel ? color : const Color(0xFF475569),
        fontWeight: sel ? FontWeight.bold : FontWeight.normal,
        fontSize: 11.5,
      ),
      onSelected: (val) {
        if (val) {
          setState(() => _selectedRisk = key);
        }
      },
    );
  }

  Widget _buildModelValidationCard() {
    return Container(
      key: const ValueKey('unmeasured-validation'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const ValueKey('studio-validation-toggle'),
            onTap: () => setState(() => _isValidationExpanded = !_isValidationExpanded),
            child: Row(
              children: [
                const Icon(Icons.fact_check_rounded, color: Color(0xFF0284C7), size: 18),
                const SizedBox(width: 10),
                const Expanded(child: Text('Model Doğrulama & Başarım Testi',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5))),
                Icon(_isValidationExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
              ],
            ),
          ),
          if (_isValidationExpanded) ...[
            const SizedBox(height: 12),
            const Text('Ölçülmedi / doğrulama hizmeti bağlı değil.'),
            const SizedBox(height: 8),
            const Text('Gerçek ölçüm olmadığı için güven, zamanlama sapması veya doğrulandı sonucu gösterilmez. '
              'Üretim taslağındaki planlanan olay ve süreler video gözlemi değildir.'),
            const SizedBox(height: 12),
            const ElevatedButton(
              onPressed: null,
              child: Text('Doğrulama hizmeti bağlı değil'),
            ),
          ],
        ],
      ),
    );
  }
  Widget _buildAdminClipsHeader() {
    final minutes = (_session!.totalDurationSec / 60).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Toplam ${_session!.steps.length} Sıralı Klip',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'ADMİN PROMPT',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '$minutes Dk Toplam • Her Klip ${_session!.blockDurationSec} sn',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
              ),
            ],
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              elevation: 0,
            ),
            onPressed: () {
              _copyToClipboard(
                _session!.exportEnglishPromptsOnly(),
                'Tüm video promptları kopyalandı! Runway / Sora içine sırayla yapıştırabilirsiniz.',
              );
            },
            icon: const Icon(Icons.copy_all, size: 14),
            label: const Text('Tüm Promptlar', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildViewModeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (_scenarioViewMode != 'steps') {
                  setState(() => _scenarioViewMode = 'steps');
                }
              },
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _scenarioViewMode == 'steps' ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: _scenarioViewMode == 'steps'
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.format_list_numbered_rounded,
                      size: 16,
                      color: _scenarioViewMode == 'steps' ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Adım Adım',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: _scenarioViewMode == 'steps' ? FontWeight.bold : FontWeight.w500,
                        color: _scenarioViewMode == 'steps' ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (_scenarioViewMode != 'unified') {
                  setState(() => _scenarioViewMode = 'unified');
                }
              },
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _scenarioViewMode == 'unified' ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: _scenarioViewMode == 'unified'
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.article_rounded,
                      size: 16,
                      color: _scenarioViewMode == 'unified' ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Tek Metin (Birleşik)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: _scenarioViewMode == 'unified' ? FontWeight.bold : FontWeight.w500,
                        color: _scenarioViewMode == 'unified' ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _cleanTitle(String rawTitle) {
    String cleaned = rawTitle.replaceAll(RegExp(r'\[ONT-\d+\]\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\([^)]*\)'), '');
    return cleaned.trim();
  }

  String _generateUnifiedScenarioText(SyntheticVideoSession session) {
    final sb = StringBuffer();
    final allScenarios = ScenariosRepository.allScenarios;
    final riskLabel = _getRiskLabel(_selectedRisk);

    int stepNum = 1;

    // 1. BAŞLANGIÇ
    final baseSteps = session.steps.where((s) => s.blockType == 'BASE_PLAY').toList();
    sb.writeln('1. HAZIRLIK VE SERBEST OYUN BAŞLANGICI');
    if (baseSteps.isNotEmpty) {
      sb.writeln('• Ne Yapılmalı: ${baseSteps.map((s) => s.actionDescription).join(' ')}');
    } else {
      sb.writeln('• Ne Yapılmalı: Çocuk odaya alınır ve halı üzerinde sevdiği oyuncaklarla serbest oyuna başlaması sağlanır.');
    }
    sb.writeln('• Videodaki Çocuk Eylemi (Simülasyon): Çocuk oyuncaklarla kendi halinde meşgul olur; kamera ve yetişkin doğal gözlem mesafesinde yer alır.\n');
    stepNum++;

    // 2. SEÇİLEN DAVRANIŞLAR (SIRASIYLA)
    for (final code in _selectedOntologies) {
      final behaviorMatch = BehaviorCards.all.where((b) => b.id == code).firstOrNull;
      final cleanTitle = behaviorMatch != null ? behaviorMatch.title : _cleanTitle(allScenarios.where((s) => s.code == code).firstOrNull?.title ?? code);
      final ontSteps = session.steps.where((s) => s.ontologyCode == code).toList();
      final stim = ontSteps.firstWhere((s) => s.blockType == 'STIMULUS', orElse: () => ontSteps.first);
      final react = ontSteps.firstWhere((s) => s.blockType == 'REACTION', orElse: () => ontSteps.first);
      final trans = ontSteps.where((s) => s.blockType == 'TRANSITION').firstOrNull;

      sb.writeln('$stepNum. $cleanTitle GÖZLEMİ');
      sb.writeln('• Ne Yapılmalı (Yetişkin): ${stim.actionDescription}');
      sb.writeln('• Videodaki Çocuk Eylemi (Simülasyon - $riskLabel): ${react.actionDescription}');
      if (trans != null && trans.actionDescription.isNotEmpty) {
        sb.writeln('• Oyuna Geçiş: ${trans.actionDescription}');
      }
      sb.writeln();
      stepNum++;
    }

    // 3. KAPANIŞ
    final cooldownSteps = session.steps.where((s) => s.blockType == 'COOLDOWN').toList();
    sb.writeln('$stepNum. SEANS KAPANIŞI');
    if (cooldownSteps.isNotEmpty) {
      sb.writeln('• Ne Yapılmalı: ${cooldownSteps.map((s) => s.actionDescription).join(' ')}');
    } else {
      sb.writeln('• Ne Yapılmalı: Gözlem ve çekim tamamlanır. Çocukla pozitif bir vedalaşma yapılarak seans sonlandırılır.');
    }
    sb.writeln('• Videodaki Çocuk Eylemi (Simülasyon): Çocuk sakinleşerek oyununu bırakır veya ebeveynine yönelir.');

    return sb.toString().trim();
  }

  TextSpan _buildUnifiedTextSpan(SyntheticVideoSession session, Color riskColor) {
    final spans = <InlineSpan>[];
    final allScenarios = ScenariosRepository.allScenarios;
    final riskLabel = _getRiskLabel(_selectedRisk);

    int stepNum = 1;

    // 1. BAŞLANGIÇ
    final baseSteps = session.steps.where((s) => s.blockType == 'BASE_PLAY').toList();
    spans.add(TextSpan(
      text: '$stepNum. HAZIRLIK VE SERBEST OYUN BAŞLANGICI\n',
      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 13),
    ));
    spans.add(const TextSpan(
      text: '• Ne Yapılmalı: ',
      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0284C7), fontSize: 12.5),
    ));
    spans.add(TextSpan(
      text: '${baseSteps.isNotEmpty ? baseSteps.map((s) => s.actionDescription).join(' ') : 'Çocuk odaya alınır ve halı üzerinde sevdiği oyuncaklarla serbest oyuna başlaması sağlanır.'}\n',
      style: const TextStyle(color: Color(0xFF334155), fontSize: 12.5),
    ));
    spans.add(const TextSpan(
      text: '• Videodaki Çocuk Eylemi (Simülasyon): ',
      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 12.5),
    ));
    spans.add(const TextSpan(
      text: 'Çocuk oyuncaklarla kendi halinde meşgul olur; kamera ve uygulayıcı doğal mesafede konumlanır.\n\n',
      style: TextStyle(color: Color(0xFF334155), fontSize: 12.5),
    ));
    stepNum++;

    // 2. SEÇİLEN DAVRANIŞLAR
    for (final code in _selectedOntologies) {
      final scen = allScenarios.firstWhere(
        (s) => s.code == code,
        orElse: () => allScenarios.first,
      );
      final cleanTitle = _cleanTitle(scen.title);
      final ontSteps = session.steps.where((s) => s.ontologyCode == code).toList();
      final stim = ontSteps.firstWhere((s) => s.blockType == 'STIMULUS', orElse: () => ontSteps.first);
      final react = ontSteps.firstWhere((s) => s.blockType == 'REACTION', orElse: () => ontSteps.first);
      final trans = ontSteps.where((s) => s.blockType == 'TRANSITION').firstOrNull;

      spans.add(TextSpan(
        text: '$stepNum. $cleanTitle GÖZLEMİ\n',
        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 13),
      ));
      spans.add(const TextSpan(
        text: '• Ne Yapılmalı (Yetişkin): ',
        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0284C7), fontSize: 12.5),
      ));
      spans.add(TextSpan(
        text: '${stim.actionDescription}\n',
        style: const TextStyle(color: Color(0xFF334155), fontSize: 12.5),
      ));
      spans.add(TextSpan(
        text: '• Videodaki Çocuk Eylemi ($riskLabel): ',
        style: TextStyle(fontWeight: FontWeight.bold, color: riskColor, fontSize: 12.5),
      ));
      spans.add(TextSpan(
        text: '${react.actionDescription}\n',
        style: const TextStyle(color: Color(0xFF334155), fontSize: 12.5),
      ));
      if (trans != null && trans.actionDescription.isNotEmpty) {
        spans.add(const TextSpan(
          text: '• Oyuna Geçiş: ',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 12.5),
        ));
        spans.add(TextSpan(
          text: '${trans.actionDescription}\n',
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
        ));
      }
      spans.add(const TextSpan(text: '\n'));
      stepNum++;
    }

    // 3. KAPANIŞ
    final cooldownSteps = session.steps.where((s) => s.blockType == 'COOLDOWN').toList();
    spans.add(TextSpan(
      text: '$stepNum. SEANS KAPANIŞI\n',
      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 13),
    ));
    spans.add(const TextSpan(
      text: '• Ne Yapılmalı: ',
      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0284C7), fontSize: 12.5),
    ));
    spans.add(TextSpan(
      text: '${cooldownSteps.isNotEmpty ? cooldownSteps.map((s) => s.actionDescription).join(' ') : 'Gözlem ve çekim tamamlanır. Çocukla pozitif bir vedalaşma yapılarak seans sonlandırılır.'}\n',
      style: const TextStyle(color: Color(0xFF334155), fontSize: 12.5),
    ));
    spans.add(const TextSpan(
      text: '• Videodaki Çocuk Eylemi (Simülasyon): ',
      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 12.5),
    ));
    spans.add(const TextSpan(
      text: 'Çocuk sakinleşerek oyununu bırakır veya ebeveynine yönelir.',
      style: TextStyle(color: Color(0xFF334155), fontSize: 12.5),
    ));

    return TextSpan(children: spans);
  }

  Widget _buildUnifiedScenarioCard() {
    if (_session == null) return const SizedBox.shrink();

    final session = _session!;
    Color riskColor = session.isUnreviewedGenerationDraft
        ? const Color(0xFF475569)
        : const Color(0xFF10B981);
    if (!session.isUnreviewedGenerationDraft && _selectedRisk == 'atipik') {
      riskColor = const Color(0xFFEF4444);
    }
    if (!session.isUnreviewedGenerationDraft && _selectedRisk == 'gecikmeli') {
      riskColor = const Color(0xFFF59E0B);
    }

    final minutes = (session.totalDurationSec / 60).toStringAsFixed(1);
    final unifiedText = _generateUnifiedScenarioText(session);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ÜST BAŞLIK VE KOPYALA BUTONU
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.description_rounded, size: 18, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sıralı Seans Senaryosu',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Tek Blokta Sırasıyla Tüm Uygulama Akışı',
                            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  _copyToClipboard(unifiedText, 'Senaryo metni panoya kopyalandı!');
                },
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text('Kopyala', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F172A),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ROZETLER
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${session.targetAgeMonths} Ay',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: riskColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: riskColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  session.isUnreviewedGenerationDraft
                      ? 'Planlanan taslak'
                      : _getRiskLabel(_selectedRisk),
                  style: TextStyle(color: riskColor, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  session.isUnreviewedGenerationDraft
                      ? 'Planlanan süre: $minutes dk'
                      : '~$minutes Dk Toplam',
                  style: const TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // TEK BİR BLOK İÇERİSİNDE TÜM SENARYO METNİ
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: SelectableText.rich(
              _buildUnifiedTextSpan(session, riskColor),
              style: const TextStyle(
                height: 1.55,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScenarioTypeSwitcher() {
    final isDoctor = _scenarioType == 'doctor';
    final isVideo = _scenarioType == 'video';

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // TÜR 1: DOKTOR KLİNİK SENARYOSU (SANİYESİZ)
          Expanded(
            child: InkWell(
              onTap: _selectedEngine == 'server' || _isGenerating ? null : () {
                if (_scenarioType != 'doctor') {
                  setState(() => _scenarioType = 'doctor');
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                decoration: BoxDecoration(
                  color: isDoctor ? const Color(0xFF2563EB) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.medical_services_rounded,
                          color: isDoctor ? Colors.white : const Color(0xFF94A3B8),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(
                          'Tür 1: Doktor Protokolü',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDoctor ? Colors.white : const Color(0xFFCBD5E1),
                          ),
                        )),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Saniyesiz • Protokol ve Karar Dalları',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: isDoctor ? const Color(0xFFDBEAFE) : const Color(0xFF64748B),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // TÜR 2: SENTETİK VİDEO & PROMPT STÜDYOSU (SANİYELİ)
          Expanded(
            child: InkWell(
              onTap: _selectedEngine == 'server' || _isGenerating ? null : () {
                if (_scenarioType != 'video') {
                  setState(() => _scenarioType = 'video');
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                decoration: BoxDecoration(
                  color: isVideo ? const Color(0xFF0284C7) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.movie_creation_rounded,
                          color: isVideo ? Colors.white : const Color(0xFF94A3B8),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(
                          'Tür 2: Video Stüdyosu',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isVideo ? Colors.white : const Color(0xFFCBD5E1),
                          ),
                        )),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Saniyeli • Veo / Sora Promptları',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: isVideo ? const Color(0xFFE0F2FE) : const Color(0xFF64748B),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// TÜR 1: DOKTOR KLİNİK DEĞERLENDİRME VE FSM PROTOKOL GÖRÜNÜMÜ
  Widget _buildDoctorScenarioView(DoctorClinicalScenario doc) {
    Color riskColor = const Color(0xFF10B981);
    if (_selectedRisk == 'atipik') riskColor = const Color(0xFFEF4444);
    if (_selectedRisk == 'gecikmeli') riskColor = const Color(0xFFF59E0B);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. DOKTOR PROTOKOL BAŞLIK KARTI
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.medical_information_rounded, size: 22, color: Color(0xFF2563EB)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${doc.category} • Kod: ${doc.code}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ROZETLER
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${doc.targetAgeMonths} Ay (${doc.ageGroupLabel})',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: riskColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: riskColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'Profil: ${doc.riskProfile.toUpperCase()}',
                      style: TextStyle(color: riskColor, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Text(
                      'Motor: ${doc.engineUsed}',
                      key: const ValueKey('studio-template-source'),
                      style: const TextStyle(color: Color(0xFF334155), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // GELİŞİMSEL NORM KUTUSU
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.check_circle_outline_rounded, size: 15, color: Color(0xFF16A34A)),
                        SizedBox(width: 6),
                        Expanded(child: Text(
                          'Eski şablon açıklaması — klinik norm olarak doğrulanmadı',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                        )),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      doc.expectedNorm,
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF1E293B), height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. ORTAM VE MATERYALLER KARTI
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.room_preferences_rounded, size: 16, color: Color(0xFF0F172A)),
                  SizedBox(width: 6),
                  Expanded(child: Text(
                    'Klinik Ortam ve Test Materyalleri',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  )),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📍 ', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), height: 1.3),
                        children: [
                          const TextSpan(text: 'Ortam Şartları: ', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                          TextSpan(text: doc.clinicEnvironment),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📦 ', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), height: 1.3),
                        children: [
                          const TextSpan(text: 'Kullanılacak Araçlar: ', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                          TextSpan(text: doc.materialsUsed),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 3. ADIM ADIM KLİNİK TEST & UYARAN PROTOKOLÜ
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.format_list_bulleted_rounded, size: 18, color: Color(0xFF2563EB)),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    '1. Klinik Test & Uyaran Protokolü',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  )),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Uygulayıcı uzmanın sırayla takip edeceği gözlem adımları:',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: SelectableText(
                  doc.stimulusProtocol,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B), height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ORTAK KARAKTER & ORTAM ŞABLONU (AYRI VE NET KUTU)
        _buildSharedEnvironmentCard(),

        // SAHNE SAHNE KATLANABİLİR KLİP AKORDİYONU (1. YOL)
        _buildSceneAccordionSection(),

        // 4. ÇOCUK NASIL TEPKİ VEREBİLİR? (FSM REFERANS DAVRANIŞ ARALIKLARI)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.alt_route_rounded, size: 18, color: Color(0xFF0F172A)),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    '2. Olası Davranışsal Tepkiler (Gözlem Dalları)',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  )),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Çocuğun verebileceği olası tepkiler ve klinik anlamları:',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              ...doc.branches.map((b) => _buildDoctorBranchCard(b)),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // PROTOKOLÜ KOPYALA BUTONU
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: () {
              _copyToClipboard(
                doc.exportDoctorMarkdown(),
                'Klinik protokol Markdown formatında panoya kopyalandı!',
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text(
              'Protokolü Markdown Olarak Kopyala',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildDoctorBranchCard(DoctorScenarioBranch branch) {
    Color bg = const Color(0xFFF8FAFC);
    Color border = const Color(0xFFE2E8F0);
    Color tagBg = const Color(0xFFE2E8F0);
    Color tagText = const Color(0xFF334155);

    if (branch.level == 'YEŞİL') {
      bg = const Color(0xFFF0FDF4);
      border = const Color(0xFFBBF7D0);
      tagBg = const Color(0xFFDCFCE7);
      tagText = const Color(0xFF15803D);
    } else if (branch.level == 'SARI') {
      bg = const Color(0xFFFFFBEB);
      border = const Color(0xFFFDE68A);
      tagBg = const Color(0xFFFEF3C7);
      tagText = const Color(0xFFB45309);
    } else if (branch.level == 'KIRMIZI') {
      bg = const Color(0xFFFEF2F2);
      border = const Color(0xFFFECACA);
      tagBg = const Color(0xFFFEE2E2);
      tagText = const Color(0xFFB91C1C);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: tagBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  branch.level,
                  style: TextStyle(color: tagText, fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: border),
                ),
                child: Text(
                  'Eski şablondaki süre: ${branch.latency}',
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            branch.title,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 4),
          Text(
            branch.details,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), height: 1.35),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 14, color: tagText),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Klinik Anlam: ${branch.clinicalOutcome}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tagText),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// ORTAK KARAKTER VE ORTAM ŞABLONU (AYRI VE NET KUTU)
  Widget _buildSharedEnvironmentCard() {
    if (_session == null || _session!.steps.isEmpty) {
      return const SizedBox.shrink();
    }
    final characterPrompt = _sharedCharacterPrompt;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.person_pin_circle_rounded, size: 18, color: Color(0xFF2563EB)),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(child: Text(
                    'Ortak Karakter & Ortam Şablonu',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  )),
                ],
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  _copyToClipboard(
                    characterPrompt,
                    'Ortak karakter ve ortam şablonu kopyalandı!',
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF0F172A)),
                label: const Text(
                  'Kopyala',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Tüm sahnelerde kamera açısı, oda görünümü ve çocuk profili sabittir:',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: SelectableText(
              characterPrompt,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  /// SAHNE SAHNE KATLANABİLİR KLİP AKORDİYON LİSTESİ
  Widget _buildSceneAccordionSection() {
    if (_session == null || _session!.steps.isEmpty) {
      return const SizedBox.shrink();
    }

    final steps = _session!.steps;
    final allExpanded = _expandedSceneIndices.length == steps.length;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.movie_filter_rounded, size: 18, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${steps.length} Sahnelik Veo Klip Planı',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${(_session!.totalDurationSec / 60).toStringAsFixed(1)} Dakika • ${steps.first.durationSec} Sn Dilimler',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ],
                  )),
                ],
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                onPressed: () => _toggleAllScenesExpanded(!allExpanded, steps.length),
                icon: Icon(
                  allExpanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
                  size: 16,
                ),
                label: Text(
                  allExpanded ? 'Kapat' : 'Tümünü Aç',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(steps.length, (index) => _buildSceneAccordionItem(steps[index], index)),
        ],
      ),
    );
  }

  /// TEK BİR SAHNENİN KATLANABİLİR AKORDİYON KARTI
  Widget _buildSceneAccordionItem(SyntheticVideoStep step, int index) {
    final isExpanded = _expandedSceneIndices.contains(index);
    final timeRange = _formatTimeRange(step.startSec, step.endSec);

    Color phaseColor;
    Color phaseBg;
    String phaseLabel = step.phaseName;
    if (phaseLabel == 'TABAN' || phaseLabel == 'BASE_PLAY') {
      phaseColor = const Color(0xFF0284C7);
      phaseBg = const Color(0xFFE0F2FE);
      phaseLabel = 'Taban';
    } else if (phaseLabel == 'UYARAN' || phaseLabel == 'STIMULUS') {
      phaseColor = const Color(0xFF7C3AED);
      phaseBg = const Color(0xFFEDE9FE);
      phaseLabel = 'Uyaran';
    } else {
      phaseColor = const Color(0xFF16A34A);
      phaseBg = const Color(0xFFDCFCE7);
      phaseLabel = 'Kapanış';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExpanded ? phaseColor.withValues(alpha: 0.5) : const Color(0xFFE2E8F0),
          width: isExpanded ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // BAŞLIK ŞERİDİ (Tıklanabilir)
          InkWell(
            onTap: () => _toggleSceneExpanded(index),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                  // FAZ ROZETİ
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: phaseBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      phaseLabel,
                      style: TextStyle(
                        color: phaseColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // SAHNE VE ZAMAN
                  Text(
                      '🎬 Sahne ${step.stepNumber} ($timeRange)',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                  ),
                  // KOPYALA BUTONU (Şeritte Hızlıca)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: () {
                      _copyToClipboard(
                        step.universalPrompt,
                        'Sahne ${step.stepNumber} promptu panoya kopyalandı!',
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 13, color: Color(0xFF334155)),
                    label: const Text(
                      'Kopyala',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                    ),
                  ),
                    ],
                  )),
                  const SizedBox(width: 6),
                  // OK İKONU
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF64748B),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // AÇILAN DETAY ALANI
          if (isExpanded) ...[
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // SAHNEYE ÖZEL EYLEM (ODASIZ/KARAKTERSİZ NET EYLEM)
                  const Text(
                    'Kamera Önü Eylemi:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      step.actionDescription.isNotEmpty ? step.actionDescription : step.universalPrompt,
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF1E293B), height: 1.35),
                    ),
                  ),
                  if (step.metadata['dialogue'] != null && step.metadata['dialogue'].toString().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: Color(0xFF2563EB)),
                        const SizedBox(width: 6),
                        Text(
                          'Replik (${step.metadata['speaker'] == 'ADULT' ? 'Terapist' : 'Çocuk'}): "${step.metadata['dialogue']}"',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2563EB)),
                        ),
                      ],
                    ),
                  ],
                  if (step.clinicalChecklist.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.medical_services_outlined, size: 14, color: Color(0xFF64748B)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Klinik Gözlem: ${step.clinicalChecklist}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  // TAM VEO PROMPT KUTUSU VE KOPYALA BUTONU
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            _copyToClipboard(
                              step.universalPrompt,
                              'Sahne ${step.stepNumber} tam Veo promptu kopyalandı!',
                            );
                          },
                          icon: const Icon(Icons.copy_all_rounded, size: 14, color: Color(0xFF0F172A)),
                          label: const Text(
                            'Tam Veo Promptu',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            _copyToClipboard(
                              step.actionDescription.isNotEmpty ? step.actionDescription : step.universalPrompt,
                              'Sahne ${step.stepNumber} eylemi kopyalandı!',
                            );
                          },
                          icon: const Icon(Icons.content_cut_rounded, size: 14, color: Color(0xFF475569)),
                          label: const Text(
                            'Sadece Eylemi Kopyala',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
