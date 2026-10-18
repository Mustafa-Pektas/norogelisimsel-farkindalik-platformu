import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/local_model_option.dart';
import '../models/scenario_graph.dart';
import '../models/scenario_input.dart';
import '../services/llama_model_service.dart';
import '../services/llamadart_test_runtime.dart';
import '../services/local_llama_test_service.dart';
import '../services/scenario_graph_converter.dart';
import '../widgets/local_llama_test_card.dart';
import 'scenario_graph_screen.dart';

enum _InputType { scenario, graph }

/// Yalnız oturum içi JSON doğrulama ve görüntüleme; dosya veya eşleme yazmaz.
class ScenarioGraphImportScreen extends StatefulWidget {
  const ScenarioGraphImportScreen({
    super.key,
    this.scenarioService,
    this.initialScenarioContent = false,
  });

  /// Doğrudan Stüdyo girişi içerikle başlar; eski hazır graf yolu korunur.
  final bool initialScenarioContent;

  /// Kontrollü test bağımlılığı; ekran bu oturumun servisini kapatır.
  final LocalLlamaTestService? scenarioService;

  static const d01InputAssetPath = 'assets/scenarios/d01_scenario_input.json';
  static const convertedSourceLabel = 'Senaryo içeriğinden dönüştürüldü';
  static const sourceDisclaimer =
      'Kaynak alanı doğrulanmış köken kanıtı değildir.';

  @override
  State<ScenarioGraphImportScreen> createState() =>
      _ScenarioGraphImportScreenState();
}

class _ScenarioGraphImportScreenState extends State<ScenarioGraphImportScreen> {
  final _json = TextEditingController();
  final _drafts = {_InputType.graph: '', _InputType.scenario: ''};
  _InputType _type = _InputType.graph;
  ScenarioGraph? _validated;
  ScenarioInput? _scenarioInput;
  String? _error;
  bool _loadingExample = false;
  late final LocalLlamaTestService _modelDemo;
  StreamSubscription<LocalLlamaTestState>? _modelSubscription;
  bool _demoDraft = false;
  bool _demoEdited = false;
  String? _formatNormalization;
  bool _confirmingExit = false;
  bool _allowExit = false;

  bool get _isScenario => _type == _InputType.scenario;
  bool get _busy => _loadingExample || _modelDemo.state.isBusy;
  bool get _hasDraft =>
      _modelDemo.state.isBusy ||
      _modelDemo.state.text.isNotEmpty ||
      _json.text.trim().isNotEmpty ||
      _drafts.entries.any((entry) =>
          entry.key != _type && entry.value.trim().isNotEmpty);

  Future<void> _requestExit() async {
    if (_confirmingExit || _allowExit) return;
    if (!_hasDraft) {
      Navigator.of(context).pop();
      return;
    }
    _confirmingExit = true;
    final route = ModalRoute.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Taslağı bırakıp çıkılsın mı?'),
        content: const Text(
          'Bu ekrandaki taslak kaydedilmez. Süren üretim varsa iptal edilir.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('scenario-import-exit'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Çık'),
          ),
          FilledButton(
            key: const ValueKey('scenario-import-stay'),
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Ekranda kal'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _confirmingExit = false;
    if (leave != true) return;
    setState(() {
      _allowExit = true;
    });
    // PopScope'un onaylanan çıkışa izin veren yeni değeri çizilsin.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || route?.isCurrent != true) return;
    Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();
    _type = widget.initialScenarioContent ? _InputType.scenario : _InputType.graph;
    _modelDemo = widget.scenarioService ??
        LocalLlamaTestService(
          request: LocalLlamaTestRequest.d01GraphDemo,
          resolveModel: () => LlamaModelService.getModelFile(
            model: LocalModelOption.qwen3,
          ),
          createRuntime: LlamadartTestRuntime.new,
        );
    _modelSubscription = _modelDemo.states.listen(_modelChanged);
  }

  void _modelChanged(LocalLlamaTestState state) {
    if (!mounted) return;
    if (state.phase == LocalLlamaPhase.completed) {
      setState(() {
        _demoDraft = true;
        _demoEdited = false;
        _formatNormalization = null;
        _json.text = state.text;
      });
      _validate();
      return;
    }
    setState(() {
      if (state.phase == LocalLlamaPhase.loading) {
        _validated = null;
        _scenarioInput = null;
        _error = null;
        _formatNormalization = null;
      } else if (state.phase == LocalLlamaPhase.error) {
        _error = 'Modelden taslak alınamadı: ${state.error}';
      } else if (state.phase == LocalLlamaPhase.cancelled) {
        _error = 'Üretim iptal edildi; kısmi cevap grafa aktarılmadı.';
      }
    });
  }

  (String, String?) _demoInputJson(String text) {
    // Ham cevap serviste aynen durur. Yalnız editördeki kopya metadata alır.
    // Yalnız tam cevabı çevreleyen biçim açılır; JSON/içerik onarılmaz.
    var json = text.trim();
    final changes = <String>[];
    final fence = RegExp(
      r'^```json[ \t]*\r?\n([\s\S]*?)\r?\n```$',
      caseSensitive: false,
    ).firstMatch(json);
    if (fence != null && fence.end == json.length) {
      json = fence.group(1)!;
      changes.add('Dış Markdown JSON çiti kaldırıldı.');
    }
    var decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Model cevabı bir JSON nesnesi olmalıdır.');
    }
    if (decoded.containsKey('scenarioInput')) {
      if (decoded.length != 1 ||
          decoded['scenarioInput'] is! Map<String, dynamic>) {
        throw const FormatException(
          'scenarioInput sarmalayıcısı tek alan olmalı ve bir JSON nesnesi içermelidir.',
        );
      }
      decoded = decoded['scenarioInput'] as Map<String, dynamic>;
      changes.add('Tek scenarioInput sarmalayıcısı açıldı.');
    }
    final normalized = const JsonEncoder.withIndent('  ').convert({
      ...decoded,
      ...LocalLlamaTestRequest.d01GraphDemoMetadata,
      'source': _demoEdited ? 'model_output_edited' : 'model_output',
    });
    return (
      normalized,
      changes.isEmpty ? null : 'Biçim normalizasyonu: ${changes.join(' ')} '
          'Ham cevap ve anlatı metinleri değiştirilmedi.',
    );
  }

  void _selectType(_InputType type) {
    if (_busy || type == _type) return;
    _drafts[_type] = _json.text;
    _json.text = _drafts[type]!;
    setState(() {
      _type = type;
      _validated = null;
      _scenarioInput = null;
      _error = null;
    });
  }

  void _edited(String _) {
    if (_isScenario && _demoDraft) _demoEdited = true;
    setState(() {
      _validated = null;
      _scenarioInput = null;
      _error = null;
      _formatNormalization = null;
    });
  }

  void _validate() {
    if (_busy) return;
    ScenarioGraph? graph;
    ScenarioInput? input;
    String? error;
    var normalization = _formatNormalization;
    if (_json.text.trim().isEmpty) {
      error = _isScenario
          ? 'Graf oluşturmak için senaryo içeriği JSON metni yapıştırın.'
          : 'Lütfen doğrulamak için bir senaryo JSON metni yapıştırın.';
    } else {
      try {
        if (_isScenario) {
          if (_demoDraft) {
            final (json, notice) = _demoInputJson(_json.text);
            _json.text = json;
            normalization = notice ?? normalization;
          }
          input = ScenarioInput.fromJsonString(_json.text);
          if (_demoDraft && input.alternatives.length != 2) {
            throw const FormatException(
              'D01 demosunda iki alternatif gerekir; eksik dal eklenmedi.',
            );
          }
          graph = const ScenarioGraphConverter().convert(input);
        } else {
          graph = ScenarioGraph.fromJsonString(_json.text);
        }
      } on FormatException catch (exception) {
        error =
            '${_isScenario ? 'Graf oluşturulamadı' : 'Graf doğrulanamadı'}: '
            '${exception.message}';
      } catch (_) {
        error = 'Graf doğrulanırken beklenmeyen bir hata oluştu. '
            'JSON metnini kontrol edip tekrar deneyin.';
      }
    }
    if (error != null && _isScenario && _demoDraft) {
      error =
          '$error JSON alanını düzeltip Graf oluştur ile yeniden doğrulayın; '
          'otomatik içerik tamamlama yapılmadı.';
    }
    setState(() {
      _validated = graph;
      _scenarioInput = graph == null ? null : input;
      _error = error;
      _formatNormalization = normalization;
    });
  }

  Future<void> _loadExample() async {
    if (_busy || !_isScenario) return;
    final bundle = DefaultAssetBundle.of(context);
    setState(() {
      _loadingExample = true;
      _validated = null;
      _scenarioInput = null;
      _error = null;
    });
    try {
      final text = await bundle.loadString(
        ScenarioGraphImportScreen.d01InputAssetPath,
        cache: false,
      );
      if (!mounted) return;
      setState(() {
        _json.text = text;
        _demoDraft = false;
        _demoEdited = false;
        _formatNormalization = null;
        _loadingExample = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingExample = false;
        _error = 'Elle hazırlanmış D01 örneği okunamadı. '
            'Mevcut JSON metni korundu; tekrar deneyebilirsiniz.';
      });
    }
  }

  String _sourceText(ScenarioInput input) {
    final source = switch (input.source) {
      ScenarioInputSource.manualExample =>
        'Elle hazırlanmış örnek (manual_example)',
      ScenarioInputSource.modelOutput => 'Gerçek model çıktısı (model_output)',
      ScenarioInputSource.editedModelOutput =>
        'Kullanıcı tarafından düzenlenmiş model taslağı (model_output_edited)',
    };
    return 'Kaynak (girdi beyanı): $source';
  }

  void _viewGraph() {
    final graph = _validated;
    if (graph == null || _busy) return;
    final input = _scenarioInput;
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ScenarioGraphScreen(
        graph: graph,
        sourceLabel: input == null
            ? null
            : '${ScenarioGraphImportScreen.convertedSourceLabel}\n'
                '${_sourceText(input)}\n'
                '${ScenarioGraphImportScreen.sourceDisclaimer}',
      ),
    ));
  }

  @override
  void dispose() {
    unawaited(_modelSubscription?.cancel());
    unawaited(_modelDemo.dispose());
    _json.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final graph = _validated;
    final input = _scenarioInput;
    final screen = Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: ModalRoute.of(context)?.canPop == true
            ? BackButton(onPressed: _requestExit)
            : null,
        title: const Text('Senaryo / graf içe aktar'),
        backgroundColor: const Color(0xFF142540),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    key: const ValueKey('scenario-import-mode-scenario'),
                    label: const Text('Senaryo içeriği'),
                    selected: _isScenario,
                    onSelected: _busy
                        ? null
                        : (_) => _selectType(_InputType.scenario),
                  ),
                  ChoiceChip(
                    key: const ValueKey('scenario-import-mode-graph'),
                    label: const Text('Hazır graf'),
                    selected: !_isScenario,
                    onSelected: _busy
                        ? null
                        : (_) => _selectType(_InputType.graph),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _isScenario
                    ? 'Senaryo içeriğinden graf oluştur'
                    : ScenarioGraphScreen.importedSourceLabel,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(_isScenario
                  ? 'Teknik geliştirici arayüzü: senaryo içeriğini JSON olarak '
                      'yapıştırın. Ortak başlangıç ve alternatiflerin metinlerini '
                      'girin; sahne/kenar kimlikleri veya startSceneId girmeyin. '
                      'Yalnız tek dallanma düzeyi desteklenir.'
                  : 'Teknik geliştirici arayüzü: sahneleri ve bağlantıları '
                      'içeren hazır graf JSON metnini yapıştırın.'),
              const SizedBox(height: 8),
              const Text('Taslak yalnızca bu oturumda görüntülenir; kalıcı olarak '
                  'kaydedilmez ve davranışın gerçekleştiğine dair kanıt değildir.'),
              if (_isScenario) ...[
                const SizedBox(height: 8),
                const Text(ScenarioGraphImportScreen.sourceDisclaimer),
                const SizedBox(height: 12),
                const Text(
                  'D01 demo metadata’sını uygulama sağlar: şema, senaryo kimliği, '
                  'başlık, dil, 30 ay, D01/kart 0.2 ve kaynak. '
                  'Model yalnız ortak başlangıç ile alternatif başlık/devam/bitiş '
                  'metinlerini sağlar. Düzenlenen JSON ham cevap sayılmaz.',
                ),
                const Text(
                  'Demo biçim normalizasyonu: yalnız tüm cevabı çevreleyen '
                  'Markdown JSON çiti ve tek scenarioInput sarmalayıcısı '
                  'kabul edilir. Ek açıklama veya bozuk JSON onarılmaz; '
                  'eksik anlatı tamamlanmaz.',
                ),
                const SizedBox(height: 8),
                LocalLlamaTestCard(
                  service: _modelDemo,
                  enabled: !_loadingExample,
                  disabledReason: 'Örnek yüklenirken model üretimi kapalıdır.',
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('scenario-import-json'),
                controller: _json,
                readOnly: _busy,
                minLines: 6,
                maxLines: 12,
                keyboardType: TextInputType.multiline,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: _edited,
                decoration: InputDecoration(
                  labelText: _isScenario
                      ? 'Senaryo içeriği JSON metni'
                      : 'Senaryo JSON metni',
                  hintText: 'JSON metnini buraya yapıştırın.',
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('scenario-import-validate'),
                    onPressed: _busy ? null : _validate,
                    icon: const Icon(Icons.check),
                    label: Text(_isScenario ? 'Graf oluştur' : 'Doğrula'),
                  ),
                  if (_isScenario)
                    OutlinedButton.icon(
                      key: const ValueKey('scenario-import-load-example'),
                      onPressed: _busy ? null : _loadExample,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Elle hazırlanmış D01 örneğini yükle'),
                    ),
                  OutlinedButton.icon(
                    key: const ValueKey('scenario-import-view'),
                    onPressed: graph == null || _busy
                        ? null
                        : _viewGraph,
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('Grafı görüntüle'),
                  ),
                ],
              ),
              if (_loadingExample) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(
                  semanticsLabel: 'D01 örneği yükleniyor',
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, key: const ValueKey('scenario-import-error')),
              ],
              if (_isScenario && _formatNormalization != null) ...[
                const SizedBox(height: 12),
                Text(
                  _formatNormalization!,
                  key: const ValueKey('scenario-import-normalization'),
                ),
              ],
              if (graph != null) ...[
                const SizedBox(height: 16),
                Column(
                  key: const ValueKey('scenario-import-summary'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Graf yapısı geçerli; içerik doğrulanmadı.'),
                    Text('Senaryo kimliği: ${graph.scenarioId}'),
                    if (input != null) ...[
                      const Text(ScenarioGraphImportScreen.convertedSourceLabel),
                      Text('Alternatif: ${input.alternatives.length}'),
                      Text(_sourceText(input)),
                    ],
                    Text('Davranış: ${graph.behaviorId} · Kart sürümü: ${graph.cardVersion}'),
                    Text('Sahne: ${graph.scenes.length} · Bağlantı: ${graph.transitions.length}'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return PopScope<void>(
      canPop: _allowExit || !_hasDraft,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_requestExit());
        }
      },
      child: screen,
    );
  }
}
