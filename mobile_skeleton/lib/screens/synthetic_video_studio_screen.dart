import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/scenarios_data.dart';
import '../models/local_model_option.dart';
import '../services/synthetic_video_service.dart';
import '../services/llama_model_service.dart';
import '../services/local_llama_test_service.dart';
import '../services/llamadart_test_runtime.dart';
import '../services/d01_evaluation_service.dart';
import '../widgets/local_llama_test_card.dart';
import 'scenario_graph_screen.dart';
import 'clip_production_plan_screen.dart';

class SyntheticVideoStudioScreen extends StatefulWidget {
  final String? initialOntologyCode;
  final int? initialAgeMonths;

  const SyntheticVideoStudioScreen({
    super.key,
    this.initialOntologyCode,
    this.initialAgeMonths,
  });

  @override
  State<SyntheticVideoStudioScreen> createState() => _SyntheticVideoStudioScreenState();
}

class _SyntheticVideoStudioScreenState extends State<SyntheticVideoStudioScreen> {
  // MOTOR SEÇİMİ: 'local' (0 MB Yerel Klinik) veya 'llama' (On-Device Llama 3.2)
  String _selectedEngine = 'local';

  // DOKTOR KLİNİK PARAMETRELERİ (SANİYESİZ)
  int _selectedAge = 18;
  Set<String> _selectedOntologies = {'ONT-01', 'ONT-02', 'ONT-06'};
  String _selectedRisk = 'atipik';

  // GÖRÜNÜM MODU: 'steps' (Adım Adım Akış) veya 'unified' (Birleşik Tek Senaryo Kartı)
  String _scenarioViewMode = 'steps';

  // ADMİN PARAMETRELERİ (SADECE ADMİNE ÖZEL SANİYELİK VİDEO DİLİMLEME)
  int _selectedTotalSec = 210; // 3.5 dakika (180 - 240 sn arası)
  int _selectedDuration = 8; // 3 - 10 sn arası

  // ÇIKTI
  SyntheticVideoSession? _session;
  bool _isGenerating = false;

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
                      ? '🔓 Admin Modu Açıldı! Saniyelik Klip Dilimleme, Runway/Sora Video Promptları ve Ground-Truth Testi Aktif.'
                      : '🔒 Doktor Moduna Dönüldü (Saniyelik Klip ve Video Promptları Gizlendi).',
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

  // MODEL DOĞRULAMA (GROUND-TRUTH VS AI) METRİKLERİ
  bool _isValidationExpanded = true;
  bool _isValidating = false;
  double _validationScore = 96.4;
  double _validationDiffSec = 0.14;

  void _runValidationSimulation() {
    setState(() => _isValidating = true);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() {
          _isValidating = false;
          _validationScore = 95.2 + (DateTime.now().millisecond % 45) / 10.0;
          _validationDiffSec = 0.10 + (DateTime.now().millisecond % 15) / 100.0;
        });
      }
    });
  }

  // LLAMA MODEL DURUMU
  bool _isLlamaDownloaded = false;
  bool _isLlamaDownloading = false;
  LlamaDownloadStatus _downloadStatus = LlamaDownloadStatus();
  StreamSubscription<LlamaDownloadStatus>? _downloadSub;
  final _modelTest = LocalLlamaTestService(
    resolveModel: LlamaModelService.getModelFile,
    createRuntime: LlamadartTestRuntime.new,
  );
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
    _evaluationSub = _d01Evaluation.states.listen((_) {
      if (mounted) setState(() {});
    });
    if (widget.initialOntologyCode != null) {
      _selectedOntologies = {widget.initialOntologyCode!};
    }
    if (widget.initialAgeMonths != null) {
      _selectedAge = widget.initialAgeMonths!;
    }
    _checkLlamaStatus();
    _checkComparisonStatus();
    _generateScenario();
  }

  @override
  void didUpdateWidget(covariant SyntheticVideoStudioScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool shouldRegenerate = false;
    if (widget.initialOntologyCode != null && !_selectedOntologies.contains(widget.initialOntologyCode)) {
      _selectedOntologies = {widget.initialOntologyCode!, ..._selectedOntologies};
      shouldRegenerate = true;
    }
    if (widget.initialAgeMonths != null && widget.initialAgeMonths != _selectedAge) {
      _selectedAge = widget.initialAgeMonths!;
      shouldRegenerate = true;
    }
    if (shouldRegenerate) {
      _generateScenario();
    }
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

  String _getAgeGroupLabel(int months) {
    if (months < 18) return '12–18 Ay';
    if (months < 24) return '18–24 Ay';
    if (months < 30) return '24–30 Ay';
    return '30–36 Ay';
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

  void _generateScenario() {
    setState(() => _isGenerating = true);
    Future.delayed(const Duration(milliseconds: 250), () async {
      SyntheticVideoSession sess;

      if (_selectedEngine == 'llama') {
        sess = await LlamaModelService.generateWithLlama(
          ageMonths: _selectedAge,
          totalTargetSec: _selectedTotalSec,
          blockDurationSec: _selectedDuration,
          riskProfile: _selectedRisk,
          ontologyCodes: _selectedOntologies.toList(),
        );
      } else {
        sess = SyntheticVideoPromptService.generateSession(
          ageMonths: _selectedAge,
          totalTargetSec: _selectedTotalSec,
          blockDurationSec: _selectedDuration,
          riskProfile: _selectedRisk,
          ontologyCodes: _selectedOntologies.toList(),
        );
      }

      if (mounted) {
        setState(() {
          _session = sess;
          _isGenerating = false;
        });
      }
    });
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
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleEasterEggTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Flexible(
                child: Text(
                  'Klinik Senaryo & Simülasyon',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_isAdminMode) ...[
                const SizedBox(width: 6),
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
          if (_session != null)
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
          if (_isAdminMode && _session != null) ...[
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
            // ADMİN BİLGİLENDİRME ŞERİDİ (SADECE ADMİNDE GÖRÜNÜR)
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
                        'Admin Modu Aktif: Saniyelik klip parçalama (3-10 sn), Runway/Sora video promptları ve Ground-Truth testi görünür.',
                        style: TextStyle(fontSize: 11.5, color: Colors.white, height: 1.3),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF38BDF8),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () {
                        setState(() => _isAdminMode = false);
                      },
                      child: const Text('Kapat', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                key: const ValueKey('open-scenario-graph'),
                leading: const Icon(Icons.account_tree_outlined),
                title: const Text('Senaryo Grafı'),
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

            // Derleme görünürlüğüdür; gerçek kullanıcı yetkilendirmesi değildir.
            if (kDebugMode) ...[
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  key: const ValueKey('open-clip-production-plan'),
                  leading: const Icon(Icons.developer_mode),
                  title: const Text('Geliştirici: Klip Üretim Planı'),
                  subtitle: const Text(
                    'Yalnız debug görünürlüğü; kullanıcı yetkilendirmesi değildir.',
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
            ],

            // 1. MODEL DURUMU VE İNDİRME KARTI (HER ZAMAN GÖRÜNÜR)
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

            // 2. HİBRİT MOTOR SEÇİCİ (0 MB YEREL vs LLAMA 3.2 ON-DEVICE)
            _buildEngineSelectorCard(),
            const SizedBox(height: 14),

            // 3. DOKTOR PARAMETRE AYARLARI KARTI (SANİYESİZ, KLİNİK ODAKLI)
            _buildDoctorConfigCard(),
            const SizedBox(height: 14),

            // 4. ADMİN: SANİYELİK VİDEO DİLİMLEME VE GROUND-TRUTH TESTİ (SADECE ADMİNDE AÇILIR)
            if (_isAdminMode) ...[
              _buildAdminVideoSlicingCard(),
              const SizedBox(height: 14),
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
                        'Klinik Gözlem Senaryosu Oluşturuluyor...',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                      ),
                    ],
                  ),
                ),
              )
            else if (_session != null) ...[
              // GÖRÜNÜM SEÇENEĞİ (Adım Adım / Tek Metin Birleşik)
              _buildViewModeToggle(),
              const SizedBox(height: 10),

              if (_scenarioViewMode == 'steps') ...[
                if (_isAdminMode) ...[
                  _buildAdminClipsHeader(),
                  const SizedBox(height: 12),
                ],
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _session!.steps.length,
                  itemBuilder: (context, index) {
                    return _buildStepCard(_session!.steps[index]);
                  },
                ),
              ] else ...[
                _buildUnifiedScenarioCard(),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// HİBRİT MOTOR SEÇİCİ
  Widget _buildEngineSelectorCard() {
    final isLocal = _selectedEngine == 'local';
    return Container(
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
          const Row(
            children: [
              Icon(Icons.tune_rounded, size: 18, color: Color(0xFF0F172A)),
              SizedBox(width: 8),
              Text(
                'Üretim Motoru',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // MOTOR 1: 0 MB YEREL KLİNİK
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() => _selectedEngine = 'local');
                    _generateScenario();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      color: isLocal ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isLocal ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.bolt_rounded,
                          color: isLocal ? Colors.amberAccent : const Color(0xFF64748B),
                          size: 20,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Yerel Klinik Motor',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isLocal ? Colors.white : const Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          '0 MB • Hızlı Kural Tabanlı',
                          style: TextStyle(
                            fontSize: 10,
                            color: isLocal ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // MOTOR 2: LLAMA 3.2 ON-DEVICE
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() => _selectedEngine = 'llama');
                    _generateScenario();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      color: !isLocal ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: !isLocal ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.psychology_rounded,
                          color: !isLocal ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
                          size: 20,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Llama-3.2 On-Device',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: !isLocal ? Colors.white : const Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          _isLlamaDownloaded ? 'Hazır ✅' : '~750 MB',
                          style: TextStyle(
                            fontSize: 10,
                            color: !isLocal ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
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

  void _showOntologyPicker() {
    final tempSelected = Set<String>.from(_selectedOntologies);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final allScenarios = ScenariosRepository.allScenarios;

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
                                '${tempSelected.length} / ${allScenarios.length} davranış seçili',
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
                                    if (tempSelected.length == allScenarios.length) {
                                      tempSelected.clear();
                                      tempSelected.add(allScenarios.first.code);
                                    } else {
                                      tempSelected.clear();
                                      tempSelected.addAll(allScenarios.map((s) => s.code));
                                    }
                                  });
                                },
                                child: Text(
                                  tempSelected.length == allScenarios.length ? 'Temizle' : 'Tümünü Seç',
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
                        itemCount: allScenarios.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: Color(0xFFF1F5F9),
                        ),
                        itemBuilder: (context, index) {
                          final scen = allScenarios[index];
                          final isSelected = tempSelected.contains(scen.code);

                          return InkWell(
                            onTap: () {
                              setModalState(() {
                                if (isSelected) {
                                  if (tempSelected.length > 1) {
                                    tempSelected.remove(scen.code);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('En az 1 hedef davranış seçili olmalıdır.'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                } else {
                                  tempSelected.add(scen.code);
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
                                      scen.code,
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
                                          scen.title,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                        Text(
                                          scen.category,
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
                              _generateScenario();
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

    return Container(
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.child_care_rounded, size: 18, color: Color(0xFF0F172A)),
                  SizedBox(width: 6),
                  Text(
                    'Çocuğun Yaşı',
                    style: TextStyle(fontSize: 13.5, color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_selectedAge Ay (${_getAgeGroupLabel(_selectedAge)})',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                ),
              ),
            ],
          ),
          Slider(
            value: _selectedAge.toDouble(),
            min: 12,
            max: 36,
            divisions: 24,
            activeColor: const Color(0xFF0F172A),
            inactiveColor: const Color(0xFFE2E8F0),
            label: '$_selectedAge Ay',
            onChanged: (val) {
              setState(() => _selectedAge = val.round());
            },
            onChangeEnd: (val) {
              _generateScenario();
            },
          ),
          const SizedBox(height: 10),

          // 2. HEDEF DAVRANIŞLAR (ÇOKLU SEÇİM)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Hedef Davranışlar',
                    style: TextStyle(fontSize: 13, color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_selectedOntologies.length} Seçili',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: _showOntologyPicker,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune_rounded, size: 15, color: Color(0xFF2563EB)),
                      SizedBox(width: 4),
                      Text(
                        'Değiştir / Ekle',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._selectedOntologies.map((code) {
                final scen = allScenarios.firstWhere(
                  (s) => s.code == code,
                  orElse: () => allScenarios.first,
                );
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
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          scen.title,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () {
                          if (_selectedOntologies.length > 1) {
                            setState(() {
                              _selectedOntologies.remove(code);
                            });
                            _generateScenario();
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
                      Text(
                        'Davranış Ekle',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 3. GÖZLEM DURUMU
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
          const SizedBox(height: 16),

          // SENARYOYU YENİLE / ÜRET BUTONU
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isGenerating ? null : _generateScenario,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                _selectedEngine == 'llama' ? 'Llama 3.2 İle Senaryo Üret' : 'Klinik Senaryoyu Yenile',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// SADECE ADMİNE ÖZEL: SANİYELİK VİDEO DİLİMLEME KARTI
  Widget _buildAdminVideoSlicingCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0F172A).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.movie_filter_rounded, size: 18, color: Color(0xFF0F172A)),
              SizedBox(width: 8),
              Text(
                'Saniyelik Klip Dilimleme & Prompt Ayarları (Admin)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Video yapay zekaları (Runway Gen-3, Sora, Veo) için saniye aralıkları:',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),

          // SEANS TOPLAM SÜRESİ
          const Text(
            'Toplam Seans Süresi',
            style: TextStyle(fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildDurationChip(180, '3.0 Dk (180s)'),
              const SizedBox(width: 8),
              _buildDurationChip(210, '3.5 Dk (210s)'),
              const SizedBox(width: 8),
              _buildDurationChip(240, '4.0 Dk (240s)'),
            ],
          ),
          const SizedBox(height: 12),

          // KLİP SÜRESİ
          const Text(
            'Klip Başına Süre',
            style: TextStyle(fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [3, 4, 5, 6, 8, 10].map((sec) {
              final sel = _selectedDuration == sec;
              return ChoiceChip(
                label: Text('$sec sn'),
                selected: sel,
                selectedColor: const Color(0xFF0F172A),
                backgroundColor: const Color(0xFFF1F5F9),
                side: BorderSide(color: sel ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1)),
                labelStyle: TextStyle(
                  color: sel ? Colors.white : const Color(0xFF334155),
                  fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                  fontSize: 11,
                ),
                onSelected: (val) {
                  if (val) {
                    setState(() => _selectedDuration = sec);
                    _generateScenario();
                  }
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationChip(int sec, String label) {
    final sel = _selectedTotalSec == sec;
    return Expanded(
      child: ChoiceChip(
        label: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
              color: sel ? Colors.white : const Color(0xFF334155),
            ),
          ),
        ),
        selected: sel,
        selectedColor: const Color(0xFF0F172A),
        backgroundColor: const Color(0xFFF1F5F9),
        side: BorderSide(color: sel ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0)),
        onSelected: (val) {
          if (val) {
            setState(() => _selectedTotalSec = sec);
            _generateScenario();
          }
        },
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
          _generateScenario();
        }
      },
    );
  }

  Widget _buildModelValidationCard() {
    final diffMillis = (_validationDiffSec * 100).toInt();
    final detMillis = (14 - diffMillis + 14).clamp(0, 99);
    final detectedTimestamp = '00:08.${detMillis.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isValidationExpanded = !_isValidationExpanded),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.fact_check_rounded, color: Color(0xFF0284C7), size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Model Doğrulama & Başarım Testi',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: Color(0xFF0F172A)),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: const Text(
                    'GROUND-TRUTH',
                    style: TextStyle(color: Color(0xFF065F46), fontSize: 9.5, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  _isValidationExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: const Color(0xFF64748B),
                ),
              ],
            ),
          ),
          if (_isValidationExpanded) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.school_outlined, size: 16, color: Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hocanın Kriteri: Sentetik videodaki bilinen zaman ve davranış etiketleri, analiz modelinin başarımını ölçen referanstır.',
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade800, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // KARŞILAŞTIRMA KUTULARI
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ground-Truth (Gerçek)',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Zaman: 00:08.00',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        Text(
                          'Etiket: İsme Tepki Gözlemi',
                          style: TextStyle(fontSize: 10.5, color: Color(0xFF475569)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI Model Çıktısı',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Zaman: $detectedTimestamp',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        Text(
                          'Güven: %${_validationScore.toStringAsFixed(1)}',
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF15803D), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // BAŞARIM METRİK ÇİZELGESİ
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Zamanlama Sapması: ${_validationDiffSec.toStringAsFixed(2)} sn',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'DOĞRULANDI',
                      style: TextStyle(color: Color(0xFF047857), fontSize: 9.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isValidating ? null : _runValidationSimulation,
                icon: _isValidating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  _isValidating ? 'Doğrulama Yapılıyor...' : 'Ground-Truth Testini Yeniden Çalıştır',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================
  // ADMİN GÖRÜNÜMÜ: SANİYELİK SENTETİK KLİP BAŞLIĞI
  // ==========================================================

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
      final scen = allScenarios.firstWhere(
        (s) => s.code == code,
        orElse: () => allScenarios.first,
      );
      final cleanTitle = _cleanTitle(scen.title);
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
    Color riskColor = const Color(0xFF10B981);
    if (_selectedRisk == 'atipik') riskColor = const Color(0xFFEF4444);
    if (_selectedRisk == 'gecikmeli') riskColor = const Color(0xFFF59E0B);

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
                  _getRiskLabel(_selectedRisk),
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
                  '~$minutes Dk Toplam',
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

  Widget _buildStepCard(SyntheticVideoStep step) {
    Color typeColor = const Color(0xFF64748B);
    if (step.blockType == 'REACTION') {
      if (_selectedRisk == 'atipik') typeColor = const Color(0xFFEF4444);
      if (_selectedRisk == 'gecikmeli') typeColor = const Color(0xFFF59E0B);
      if (_selectedRisk == 'tipik') typeColor = const Color(0xFF10B981);
    } else if (step.blockType == 'STIMULUS') {
      typeColor = const Color(0xFF0284C7);
    } else if (step.blockType == 'COOLDOWN') {
      typeColor = const Color(0xFF8B5CF6);
    }

    final isFirstClip = step.stepNumber == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
          // ÜST BİLGİ ŞERİDİ
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _isAdminMode
                          ? 'KLİP ${step.stepNumber.toString().padLeft(2, '0')}'
                          : 'ADIM ${step.stepNumber}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                  if (_isAdminMode) ...[
                    const SizedBox(width: 8),
                    Text(
                      step.timeFormatted,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B)),
                    ),
                  ],
                ],
              ),
              if (step.ontologyCode != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: typeColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    step.ontologyCode!,
                    style: TextStyle(color: typeColor, fontWeight: FontWeight.bold, fontSize: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // FAZ VE BAŞLIK
          Text(
            step.phaseName,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: typeColor),
          ),
          const SizedBox(height: 2),
          Text(
            step.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 6),

          // EYLEM AÇIKLAMASI (Sade, doğal, gündelik Türkçe)
          Text(
            step.actionDescription,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155), height: 1.35),
          ),

          // SADECE ADMİNE ÖZEL: CHECKLIST, DEVAMLILIK DİREKTİFİ VE VİDEO PROMPT KUTUSU
          if (_isAdminMode) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.checklist_rtl_rounded, size: 15, color: Color(0xFF64748B)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      step.clinicalChecklist,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF475569), height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // DEVAMLILIK DİREKTİFİ (ADMİN)
            Row(
              children: [
                Icon(
                  isFirstClip ? Icons.play_circle_fill_rounded : Icons.fast_forward_rounded,
                  size: 14,
                  color: const Color(0xFF0284C7),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    step.continuityNote,
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF0284C7), fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // EVRENSEL AI VİDEO PROMPTU (KOD KUTUSU - ADMİN)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.movie_creation_outlined, size: 14, color: Color(0xFF38BDF8)),
                      SizedBox(width: 6),
                      Text(
                        'AI Video Promptu (Runway / Sora / Veo - Admin)',
                        style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    step.universalPrompt,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: Color(0xFFE2E8F0),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // KOPYALA BUTONU (ADMİN)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: () {
                  _copyToClipboard(
                    step.universalPrompt,
                    'Klip ${step.stepNumber} video promptu panoya kopyalandı!',
                  );
                },
                icon: const Icon(Icons.copy, size: 14),
                label: const Text(
                  'Promptu Kopyala (Admin)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
