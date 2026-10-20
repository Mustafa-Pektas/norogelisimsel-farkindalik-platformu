import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/local_model_option.dart';
import '../services/llama_model_service.dart';
import '../services/local_llama_test_service.dart';
import '../services/llamadart_test_runtime.dart';
import '../services/d01_evaluation_service.dart';
import '../services/clip_video_store.dart';
import '../services/graph_playback_controller.dart';
import '../widgets/local_llama_test_card.dart';
import 'scenario_graph_screen.dart';
import 'clip_production_plan_screen.dart';
import 'scenario_graph_import_screen.dart';
import 'graph_playback_screen.dart';

class SyntheticVideoStudioScreen extends StatefulWidget {
  /// Kontrollü widget testi için; bu ekran verilen servisi de kapatır.
  final LocalLlamaTestService? modelTestService;
  /// Kontrollü oynatma testleri; verilmezse mevcut yerel eşleme/oynatıcı kullanılır.
  final ClipVideoStore? playbackVideoStore;
  final GraphClipPlayer Function(File)? createPlaybackPlayer;

  const SyntheticVideoStudioScreen({
    super.key,
    this.modelTestService,
    this.playbackVideoStore,
    this.createPlaybackPlayer,
  });

  @override
  State<SyntheticVideoStudioScreen> createState() => _SyntheticVideoStudioScreenState();
}

class _SyntheticVideoStudioScreenState extends State<SyntheticVideoStudioScreen> {
  bool _openingD01Playback = false;

  Future<void> _openD01Playback() async {
    if (_openingD01Playback) return;
    setState(() { _openingD01Playback = true; });
    final bundle = DefaultAssetBundle.of(context);
    final store = widget.playbackVideoStore ??
        ClipVideoStore(documentsDirectory: getApplicationDocumentsDirectory);
    Future<LoadedClipPlan>? loading;
    var left = false;
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PopScope<void>(
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) left = true;
          },
          child: FutureBuilder<LoadedClipPlan>(
            future: loading ??= ClipProductionPlanScreen.loadPlanAssets(bundle),
            builder: (context, snapshot) {
              // Geri çıkış animasyonu sürerken gelen yükleme oyuncu oluşturmaz.
              if (left || !mounted) return const SizedBox.shrink();
              final data = snapshot.data;
              if (data != null) {
                return GraphPlaybackScreen(
                  graph: data.graph,
                  plan: data.plan,
                  videoStore: store,
                  createPlayer: widget.createPlaybackPlayer,
                  title: 'D01 videolu örnek',
                  notice: 'Örnek videoların içeriği ve sürekliliği doğrulanmadı.',
                );
              }
              return Scaffold(
                appBar: AppBar(
                  title: const Text('D01 videolu örnek'),
                  backgroundColor: const Color(0xFF142540),
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
                        : const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text('Örnek hazırlanıyor…'),
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ));
    } finally {
      if (mounted) setState(() { _openingD01Playback = false; });
    }
  }

  // LLAMA MODEL DURUMU
  bool _isLlamaDownloaded = false;
  bool _isLlamaDownloading = false;
  LlamaDownloadStatus _downloadStatus = LlamaDownloadStatus();
  StreamSubscription<LlamaDownloadStatus>? _downloadSub;
  late final LocalLlamaTestService _modelTest;
  final _d01Test = LocalLlamaTestService(
    request: LocalLlamaTestRequest.d01,
    resolveModel: LlamaModelService.getModelFile,
    createRuntime: LlamadartTestRuntime.new,
  );
  final _d01EnglishTest = LocalLlamaTestService(
    request: LocalLlamaTestRequest.d01English,
    resolveModel: LlamaModelService.getModelFile,
    createRuntime: LlamadartTestRuntime.new,
  );
  final _qwenTest = LocalLlamaTestService(
    request: LocalLlamaTestRequest.d01Qwen,
    resolveModel: () =>
        LlamaModelService.getModelFile(model: LocalModelOption.qwen3),
    createRuntime: LlamadartTestRuntime.new,
  );
  final _qwenStartTest = LocalLlamaTestService(
    request: LocalLlamaTestRequest.qwenCommonStart,
    resolveModel: () =>
        LlamaModelService.getModelFile(model: LocalModelOption.qwen3),
    createRuntime: LlamadartTestRuntime.new,
  );
  LocalModelOption _comparisonModel = LocalModelOption.qwen3;
  late final _d01Evaluation = D01EvaluationService(
    loadProtocol: () =>
        rootBundle.loadString('assets/evaluations/d01_qwen_v1.json'),
    resolveRecordsRoot: () async {
      final documents = await getApplicationDocumentsDirectory();
      return Directory('${documents.path}/evaluations/d01_qwen');
    },
    resolveModel: (model) => LlamaModelService.getModelFile(model: model),
    createRuntime: LlamadartTestRuntime.new,
    executionSource: 'llamadart_native',
  );
  StreamSubscription<D01EvaluationState>? _evaluationSub;
  String? get _evaluationDisabledReason => _d01Evaluation.state.isBusy
      ? 'Altı denemelik değerlendirme sürerken tekli testler kapalıdır.'
      : null;
  bool _isComparisonDownloaded = false;
  bool _isComparisonDownloading = false;
  LlamaDownloadStatus _comparisonDownloadStatus = LlamaDownloadStatus(
    totalBytes: LocalModelOption.qwen3.estimatedBytes,
  );
  StreamSubscription<LlamaDownloadStatus>? _comparisonDownloadSub;

  @override
  void initState() {
    super.initState();
    _modelTest = widget.modelTestService ?? LocalLlamaTestService(
      resolveModel: LlamaModelService.getModelFile,
      createRuntime: LlamadartTestRuntime.new,
    );
    _evaluationSub = _d01Evaluation.states.listen((_) {
      if (mounted) setState(() {});
    });
    _checkLlamaStatus();
    _checkComparisonStatus();
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    unawaited(_modelTest.dispose());
    unawaited(_d01Test.dispose());
    unawaited(_d01EnglishTest.dispose());
    unawaited(_qwenTest.dispose());
    unawaited(_qwenStartTest.dispose());
    _evaluationSub?.cancel();
    unawaited(_d01Evaluation.dispose());
    if (_isComparisonDownloading) {
      LlamaModelService.cancelDownload(model: _comparisonModel);
    }
    _comparisonDownloadSub?.cancel();
    super.dispose();
  }

  Future<void> _checkLlamaStatus() async {
    final downloaded = await LlamaModelService.isModelDownloaded();
    if (mounted) {
      setState(() => _isLlamaDownloaded = downloaded);
    }
  }

  Future<void> _checkComparisonStatus() async {
    final model = _comparisonModel;
    final downloaded = await LlamaModelService.isModelDownloaded(
      model: model,
    );
    if (mounted && model == _comparisonModel) {
      setState(() => _isComparisonDownloaded = downloaded);
    }
  }

  void _startComparisonDownload() {
    if (_isLlamaDownloading || _isComparisonDownloading || !_qwenTest.canRun || _d01Evaluation.state.isBusy) return;
    setState(() {
      _isComparisonDownloading = true;
      _comparisonDownloadStatus = LlamaDownloadStatus(
        isDownloading: true,
        totalBytes: _comparisonModel.estimatedBytes,
      );
    });
    _comparisonDownloadSub =
        LlamaModelService.downloadModel(model: _comparisonModel).listen(
          (status) {
            if (!mounted) return;
            setState(() {
              _comparisonDownloadStatus = status;
              _isComparisonDownloading = status.isDownloading;
              if (!status.isDownloading && status.progress >= 1 && status.error == null) {
                _isComparisonDownloaded = true;
              }
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _isComparisonDownloading = false;
              _comparisonDownloadStatus = LlamaDownloadStatus(
                error: error.toString(),
              );
            });
          },
        );
  }

  Widget _buildComparisonDownloadCard() => Card(
    color: Colors.white,
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<LocalModelOption>(
            key: const ValueKey('comparison-model-selector'),
            initialValue: _comparisonModel,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Karşılaştırma modeli'),
            items: [
              for (final model in [LocalModelOption.qwen3, LocalModelOption.miniCpmTurkish])
                DropdownMenuItem(value: model, child: Text(model.name)),
            ],
            onChanged: _isLlamaDownloading || _isComparisonDownloading ||
                !_qwenStartTest.canRun || _d01Evaluation.state.isBusy
                ? null
                : (model) {
                    if (model == null) return;
                    setState(() {
                      _comparisonModel = model;
                      _isComparisonDownloaded = false;
                      _comparisonDownloadStatus = LlamaDownloadStatus(totalBytes: model.estimatedBytes);
                    });
                    _checkComparisonStatus();
                  },
          ),
          Text(
            _comparisonModel.name,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF142540),
            ),
          ),
          const Text(
            'Ayrı model dosyası; mevcut modeller korunur. Seçim indirmeyi başlatmaz.',
          ),
          Text('Dosya boyutu: ${(_comparisonModel.estimatedBytes / (1024 * 1024)).toStringAsFixed(1)} MiB'),
          Text(
            _isComparisonDownloaded
                ? 'Model dosyası indirildi; üretim sonucu ayrı testte doğrulanır.'
                : 'Seçilen model indirilmedi.',
          ),
          if (_comparisonDownloadStatus.error != null)
            SelectableText(_comparisonDownloadStatus.error!),
          if (_isComparisonDownloading) ...[
            Text(
              '${_comparisonDownloadStatus.statusMessage} (${_comparisonDownloadStatus.downloadedMb} / ${_comparisonDownloadStatus.totalMb} MB)',
            ),
            LinearProgressIndicator(
              value: _comparisonDownloadStatus.progress.clamp(0, 1),
            ),
            TextButton(
              onPressed: () => LlamaModelService.cancelDownload(
                model: _comparisonModel,
              ),
              child: const Text('İndirmeyi iptal et'),
            ),
          ] else if (!_isComparisonDownloaded)
            FilledButton.icon(
              key: ValueKey(_comparisonModel == LocalModelOption.qwen3
                  ? 'download-qwen3' : 'download-minicpm-turkish'),
              onPressed: _isLlamaDownloading || !_qwenTest.canRun || _d01Evaluation.state.isBusy
                  ? null
                  : _startComparisonDownload,
              icon: const Icon(Icons.download),
              label: const Text('Seçilen modeli indir'),
            ),
          if (!_isComparisonDownloading &&
              _comparisonDownloadStatus.statusMessage == 'İndirme iptal edildi')
            const Text('Model indirmesi iptal edildi.'),
        ],
      ),
    ),
  );

  Widget _buildD01EvaluationControls() {
    final state = _d01Evaluation.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const Text(
          'Üç görev × iki tekrar · sabit istemler · insan değerlendirmesi bekler.',
        ),
        Text('Değerlendirme modeli: ${_comparisonModel.name}'),
        FilledButton.icon(
          key: const ValueKey('start-d01-evaluation'),
          onPressed:
              state.isBusy ||
                  _isLlamaDownloading ||
                  _isComparisonDownloading ||
                  !_qwenStartTest.canRun
              ? null
              : () async {
                  try {
                    await _d01Evaluation.run(model: _comparisonModel);
                  } catch (error) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Değerlendirme zaten çalışıyor veya kapatıldı.',
                          ),
                        ),
                      );
                    }
                  }
                },
          icon: const Icon(Icons.playlist_play),
          label: const Text('D01 değerlendirmesini başlat (6 deneme)'),
        ),
        Text(state.message, key: const ValueKey('d01-evaluation-status')),
        if (state.runId != null) Text('Kayıt: ${state.runId}'),
        if (state.error != null) SelectableText(state.error!),
        if (state.isBusy)
          TextButton(
            onPressed: _d01Evaluation.cancel,
            child: const Text('Değerlendirmeyi durdur'),
          ),
        if (_d01Evaluation.canExport) ...[
          TextButton.icon(
            key: const ValueKey('copy-d01-evaluation'),
            onPressed: () => _copyToClipboard(
              _d01Evaluation.exportJson(),
              'Değerlendirme JSON kayıtları panoya kopyalandı.',
            ),
            icon: const Icon(Icons.copy),
            label: const Text('Değerlendirme kayıtlarını kopyala'),
          ),
          ExpansionTile(
            title: const Text('Ham deneme kayıtları'),
            children: [
              for (final record in _d01Evaluation.records)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${record['attempt_id']} · ${record['execution_status']}',
                      ),
                      SelectableText(
                        record['raw_response'] as String? ??
                            'Henüz çıkarım yapılmadı.',
                      ),
                      if (record['elapsed_s'] != null)
                        Text(
                          'Toplam: ${record['elapsed_s']} sn · Bitiş: ${record['finish_reason']}',
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }


  void _startLlamaDownload() {
    setState(() {
      _isLlamaDownloading = true;
      _downloadStatus = LlamaDownloadStatus(isDownloading: true);
    });

    _downloadSub = LlamaModelService.downloadModel().listen(
      (status) {
        if (mounted) {
          setState(() {
            _downloadStatus = status;
            _isLlamaDownloading = status.isDownloading;
            if (!status.isDownloading && status.error == null && status.progress >= 1.0) {
              _isLlamaDownloaded = true;
            }
          });
        }
      },
      onError: (err) {
        if (mounted) {
          setState(() {
            _isLlamaDownloading = false;
            _downloadStatus = LlamaDownloadStatus(isDownloading: false, error: err.toString());
          });
        }
      },
    );
  }

  void _cancelLlamaDownload() {
    LlamaModelService.cancelDownload();
    _downloadSub?.cancel();
    setState(() {
      _isLlamaDownloading = false;
      _downloadStatus = LlamaDownloadStatus(isDownloading: false);
    });
  }

  Future<void> _deleteLlamaModel() async {
    await LlamaModelService.deleteModel();
    if (mounted) {
      setState(() {
        _isLlamaDownloaded = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Llama modeli cihazdan silindi, hafıza boşaltıldı.'),
          backgroundColor: Color(0xFF0F172A),
        ),
      );
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Simülasyon ve Eğitim',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hazır D01 örneği',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Elle hazırlanmış D01 örneğidir. Videoların içeriği ve sürekliliği doğrulanmadı.',
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('open-d01-playback'),
              onPressed: _openingD01Playback ? null : _openD01Playback,
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('D01 videolu örnek'),
            ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                key: const ValueKey('open-scenario-graph'),
                leading: const Icon(Icons.account_tree_outlined),
                title: const Text('Örnek akışı görüntüle'),
                subtitle: const Text('Elle hazırlanmış D01 örneğini incele'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ScenarioGraphScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Yalnız derleme görünürlüğü; kimlik doğrulaması değildir.
            if (kDebugMode)
              ExpansionTile(
                key: const ValueKey('studio-content-preparation'),
                title: const Text('İçerik hazırlama'),
                subtitle: const Text(
                  'Proje ekibi araçları · yalnız debug derlemede görünür. '
                  'Kimlik doğrulaması sağlamaz.',
                ),
                initiallyExpanded: true,
                maintainState: true,
                childrenPadding: const EdgeInsets.only(top: 12, bottom: 12),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      key: const ValueKey('open-scenario-content'),
                      leading: const Icon(Icons.edit_note),
                      title: const Text('Senaryodan graf oluştur'),
                      subtitle: const Text(
                        'Senaryo içeriğini girin veya model demosuyla taslak alın.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ScenarioGraphImportScreen(
                            initialScenarioContent: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Oluşan graf, hazır D01 klip planına ve videolarına bağlı değildir.',
                  ),
                  const SizedBox(height: 8),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      key: const ValueKey('open-clip-production-plan'),
                      leading: const Icon(Icons.developer_mode),
                      title: const Text('Klip planı ve videolu deneme'),
                      subtitle: const Text(
                        'Hazır D01 planı, video eşleme ve videolu akış denemesi.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ClipProductionPlanScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  ExpansionTile(
                    key: const ValueKey('studio-technical-tests'),
                    title: const Text('Teknik model denemeleri'),
                    initiallyExpanded: false,
                    maintainState: true,
                    childrenPadding: const EdgeInsets.only(top: 12, bottom: 12),
                    children: [
                      // Mevcut model yönetimi ve testler; kapanınca state korunur.
                      StreamBuilder<LocalLlamaTestState>(
                        stream: _modelTest.states,
                        initialData: _modelTest.state,
                        builder: (context, hello) => StreamBuilder<LocalLlamaTestState>(
                          stream: _d01Test.states,
                          initialData: _d01Test.state,
                          builder: (context, d01) => StreamBuilder<LocalLlamaTestState>(
                            stream: _d01EnglishTest.states,
                            initialData: _d01EnglishTest.state,
                            builder: (context, english) =>
                                StreamBuilder<LocalLlamaTestState>(
                                  stream: _qwenTest.states,
                                  initialData: _qwenTest.state,
                                  builder: (context, qwen) =>
                                      StreamBuilder<LocalLlamaTestState>(
                                        stream: _qwenStartTest.states,
                                        initialData: _qwenStartTest.state,
                                        builder: (context, start) => Column(
                                          children: [
                                            AbsorbPointer(
                                              absorbing:
                                                  hello.data!.isBusy ||
                                                  d01.data!.isBusy ||
                                                  english.data!.isBusy ||
                                                  qwen.data!.isBusy ||
                                                  start.data!.isBusy ||
                                                  _d01Evaluation.state.isBusy ||
                                                  _isComparisonDownloading,
                                              child: _buildLlamaManagementCard(),
                                            ),
                                            const SizedBox(height: 14),
                                            LocalLlamaTestCard(
                                              service: _modelTest,
                                              enabled:
                                                  !_isLlamaDownloading &&
                                                  !_isComparisonDownloading &&
                                                  !_d01Evaluation.state.isBusy,
                                              disabledReason: _evaluationDisabledReason,
                                            ),
                                            const SizedBox(height: 14),
                                            LocalLlamaTestCard(
                                              service: _d01Test,
                                              enabled:
                                                  !_isLlamaDownloading &&
                                                  !_isComparisonDownloading &&
                                                  !_d01Evaluation.state.isBusy,
                                              disabledReason: _evaluationDisabledReason,
                                            ),
                                            const SizedBox(height: 14),
                                            LocalLlamaTestCard(
                                              service: _d01EnglishTest,
                                              enabled:
                                                  !_isLlamaDownloading &&
                                                  !_isComparisonDownloading &&
                                                  !_d01Evaluation.state.isBusy,
                                              disabledReason: _evaluationDisabledReason,
                                            ),
                                            const SizedBox(height: 14),
                                            _buildComparisonDownloadCard(),
                                            const SizedBox(height: 14),
                                            LocalLlamaTestCard(
                                              service: _qwenTest,
                                              enabled:
                                                  !_isLlamaDownloading &&
                                                  !_isComparisonDownloading &&
                                                  !_d01Evaluation.state.isBusy,
                                              disabledReason: _evaluationDisabledReason,
                                            ),
                                            const SizedBox(height: 14),
                                            LocalLlamaTestCard(
                                              service: _qwenStartTest,
                                              footer: _buildD01EvaluationControls(),
                                              enabled:
                                                  !_isLlamaDownloading &&
                                                  !_isComparisonDownloading &&
                                                  !_d01Evaluation.state.isBusy,
                                              disabledReason: _evaluationDisabledReason,
                                            ),
                                          ],
                                        ),
                                      ),
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// LLAMA MODEL YÖNETİMİ VE İNDİRME KARTI
  Widget _buildLlamaManagementCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.memory_rounded, size: 18, color: Color(0xFF0284C7)),
                  SizedBox(width: 8),
                  Text(
                    'Llama-3.2-1B-Instruct GGUF',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _isLlamaDownloaded ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _isLlamaDownloaded ? 'İndirildi' : 'İndirilmedi',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _isLlamaDownloaded ? Colors.green.shade800 : Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_isLlamaDownloading) ...[
            Text(
              '${_downloadStatus.statusMessage} (${_downloadStatus.downloadedMb} MB / ${_downloadStatus.totalMb} MB)',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: _downloadStatus.progress,
              backgroundColor: const Color(0xFFE2E8F0),
              color: const Color(0xFF0284C7),
              minHeight: 6,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _cancelLlamaDownload,
                icon: const Icon(Icons.cancel_outlined, size: 14, color: Colors.red),
                label: const Text('İptal Et', style: TextStyle(color: Colors.red, fontSize: 11.5)),
              ),
            ),
          ] else if (!_isLlamaDownloaded) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 1,
                ),
                onPressed: _startLlamaDownload,
                icon: const Icon(Icons.cloud_download_rounded, size: 20),
                label: const Text(
                  'Modeli İndir (~776 MB)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Model Hazır (Çevrimdışı)',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF15803D), fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: _deleteLlamaModel,
                  icon: const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.red),
                  label: const Text('Modeli Sil', style: TextStyle(color: Colors.red, fontSize: 11)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
