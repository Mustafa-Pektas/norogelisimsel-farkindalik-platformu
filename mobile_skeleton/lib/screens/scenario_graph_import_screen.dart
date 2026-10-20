import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/behavior_cards.dart';
import '../models/local_model_option.dart';
import '../models/scenario_graph.dart';
import '../models/scenario_input.dart';
import '../models/scenario_generation_request.dart';
import '../models/scenario_workspace_draft.dart';
import '../services/llama_model_service.dart';
import '../services/llamadart_test_runtime.dart';
import '../services/local_llama_test_service.dart';
import '../services/scenario_graph_converter.dart';
import '../services/scenario_generation_service.dart';
import '../services/scenario_draft_store.dart';
import '../widgets/local_llama_test_card.dart';
import 'scenario_graph_screen.dart';

enum _InputType { scenario, graph }

/// JSON doğrulama/görüntüleme ve açık kullanıcı eylemiyle yerel metin taslağı.
class ScenarioGraphImportScreen extends StatefulWidget {
  const ScenarioGraphImportScreen({
    super.key,
    this.scenarioService,
    this.initialScenarioContent = false,
    this.generationService = const UnavailableScenarioGenerationService(),
    this.draftStore = const ScenarioDraftStore(),
  });

  /// Doğrudan Stüdyo girişi içerikle başlar; eski hazır graf yolu korunur.
  final bool initialScenarioContent;

  /// Kontrollü test bağımlılığı; ekran bu oturumun servisini kapatır.
  final LocalLlamaTestService? scenarioService;
  /// Bu yol yerel D01 demosundan ayrıdır; ekran yalnız başlattığı işi kapatır.
  final ScenarioGenerationService generationService;
  final ScenarioDraftStore draftStore;

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
  final _requestAge = TextEditingController();
  final _requestContext = TextEditingController();
  final _requestInstructions = TextEditingController();
  BehaviorCard? _requestCard;
  ScenarioGenerationRequest? _requestDraft;
  String? _requestCardError;
  String? _requestAgeError;
  String? _requestContextError;
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
  static int _generationSequence = 0;
  int _generationEpoch = 0;
  ScenarioGenerationJob? _generationJob;
  final _closedGenerationJobs = Expando<bool>();
  bool _generationBusy = false;
  bool _generationCancelling = false;
  String? _generationStatus;
  String? _generationError;
  String? _generationRaw;
  ScenarioGenerationRequest? _responseRequest;
  String? _responseScenarioId;
  ScenarioGenerationRequest? _editorRequest;
  String? _editorScenarioId;
  bool _generationEdited = false;
  bool _confirmingTransfer = false;
  bool _draftLoading = true;
  bool _draftWriting = false;
  bool _restoringDraft = false;
  int _workspaceRevision = 0;
  int? _savedRevision;
  int _formRestoreVersion = 0;
  String? _draftNotice;
  String? _draftError;
  String _restoredDemoRaw = '';
  final _controllerTexts = <TextEditingController, String>{};

  void _workspaceChanged() {
    if (!mounted || _restoringDraft) return;
    setState(() { ++_workspaceRevision; });
  }

  ScenarioWorkspaceDraft _snapshot() => ScenarioWorkspaceDraft(
    inputType: _type.name,
    scenarioJson: _isScenario ? _json.text : _drafts[_InputType.scenario]!,
    graphJson: _isScenario ? _drafts[_InputType.graph]! : _json.text,
    behaviorId: _requestCard?.id, cardVersion: _requestCard?.cardVersion,
    ageText: _requestAge.text, contextText: _requestContext.text,
    instructionsText: _requestInstructions.text, generationRaw: _generationRaw,
    responseRequest: _responseRequest, responseScenarioId: _responseScenarioId,
    editorRequest: _editorRequest, editorScenarioId: _editorScenarioId,
    generationEdited: _generationEdited, demoDraft: _demoDraft, demoEdited: _demoEdited,
    demoRaw: _modelDemo.state.text.isNotEmpty ? _modelDemo.state.text : _restoredDemoRaw,
  );

  Future<void> _loadDraft() async {
    final revision = _workspaceRevision;
    try {
      final draft = await widget.draftStore.load();
      if (!mounted) return;
      if (_workspaceRevision != revision || _busy) {
        setState(() {
          _draftNotice = 'Kayıtlı taslak yüklenmedi; bu oturumdaki değişiklikler korundu.';
        });
        return;
      }
      if (draft == null) return;
      _restoringDraft = true;
      try {
        setState(() {
          _type = draft.inputType == 'scenario' ? _InputType.scenario : _InputType.graph;
          _drafts[_InputType.scenario] = draft.scenarioJson;
          _drafts[_InputType.graph] = draft.graphJson;
          _json.text = _drafts[_type]!;
          _requestAge.text = draft.ageText;
          _requestContext.text = draft.contextText;
          _requestInstructions.text = draft.instructionsText;
          _requestCard = draft.behaviorId == null ? null :
              BehaviorCards.all.firstWhere((card) => card.id == draft.behaviorId);
          ++_formRestoreVersion;
          _generationRaw = draft.generationRaw;
          _responseRequest = draft.responseRequest;
          _responseScenarioId = draft.responseScenarioId;
          _editorRequest = draft.editorRequest;
          _editorScenarioId = draft.editorScenarioId;
          _generationEdited = draft.generationEdited;
          _demoDraft = draft.demoDraft;
          _demoEdited = draft.demoEdited;
          _restoredDemoRaw = draft.demoRaw;
          _requestDraft = null;
          _validated = null;
          _scenarioInput = null;
          _error = null;
          _formatNormalization = null;
          _savedRevision = _workspaceRevision;
          _draftNotice = 'Kayıtlı taslak yüklendi. Grafı yeniden doğrulayın; iş durumu geri yüklenmedi.';
        });
      } finally {
        _restoringDraft = false;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _draftError = 'Kayıtlı taslak okunamadı veya sürümü desteklenmiyor. '
            'Mevcut içerik ve kayıt değiştirilmedi.';
      });
    } finally {
      if (mounted) setState(() { _draftLoading = false; });
    }
  }

  Future<void> _saveDraft() async {
    if (_draftLoading || _draftWriting) return;
    final revision = _workspaceRevision;
    setState(() {
      _draftWriting = true;
      _draftError = null;
      _draftNotice = null;
    });
    try {
      final draft = _snapshot();
      await widget.draftStore.save(draft);
      if (!mounted) return;
      setState(() {
        _savedRevision = revision;
        _draftNotice = revision == _workspaceRevision ? 'Taslak bu cihazda kaydedildi.'
            : 'Önceki an kaydedildi; yeni değişiklikler kaydedilmedi.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _draftError = 'Taslak kaydedilemedi. Ekrandaki içeriğiniz korundu.'; });
    } finally {
      if (mounted) setState(() { _draftWriting = false; });
    }
  }

  Future<void> _deleteDraft() async {
    if (_draftLoading || _draftWriting) return;
    setState(() { _draftWriting = true; });
    try {
      final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Kayıtlı taslak silinsin mi?'),
        content: const Text('Yalnız cihazdaki kayıtlı kopya silinir. Ekrandaki taslak korunur.'),
        actions: [
          FilledButton(autofocus: true, onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Kaydı sil')),
        ],
      ));
      if (confirmed != true || !mounted) return;
      await widget.draftStore.delete();
      if (!mounted) return;
      setState(() {
        _savedRevision = null;
        _draftError = null;
        _draftNotice = 'Kayıtlı kopya silindi. Ekrandaki taslak korunuyor; otomatik kaydedilmez.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _draftError = 'Kayıtlı taslak silinemedi. Ekrandaki içerik korundu.'; });
    } finally {
      if (mounted) setState(() { _draftWriting = false; });
    }
  }

  bool get _isScenario => _type == _InputType.scenario;
  bool get _busy => _loadingExample || _modelDemo.state.isBusy || _generationBusy;
  bool get _hasDraft =>
      _modelDemo.state.isBusy ||
      _modelDemo.state.text.isNotEmpty ||
      _restoredDemoRaw.isNotEmpty ||
      _generationBusy || _generationRaw != null ||
      _json.text.trim().isNotEmpty ||
      _requestCard != null ||
      _requestAge.text.isNotEmpty ||
      _requestContext.text.isNotEmpty ||
      _requestInstructions.text.isNotEmpty ||
      _drafts.entries.any((entry) =>
          entry.key != _type && entry.value.trim().isNotEmpty);

  void _requestEdited() {
    _workspaceChanged();
    setState(() {
      _requestDraft = null;
      _requestCardError = null;
      _requestAgeError = null;
      _requestContextError = null;
    });
  }

  void _validateRequest() {
    if (_busy) return;
    final card = _requestCard;
    final ageText = _requestAge.text.trim();
    final age = RegExp(r'^[0-9]+$').hasMatch(ageText)
        ? int.tryParse(ageText) : null;
    final validAge = age != null && age >= 12 && age <= 36;
    final validContext = _requestContext.text.trim().isNotEmpty;
    setState(() {
      _requestCardError = card == null ? 'Hedef davranış seçin.' : null;
      _requestAgeError = validAge ? null : '12–36 arasında tam ay girin.';
      _requestContextError = validContext ? null : 'Sahne/ortam bağlamını girin.';
      _requestDraft = card != null && age != null && validAge && validContext
          ? ScenarioGenerationRequest(behaviorId: card.id, cardVersion: card.cardVersion,
              ageMonths: age, sceneContext: _requestContext.text,
              additionalInstructions: _requestInstructions.text.trim().isEmpty
                  ? null : _requestInstructions.text)
          : null;
    });
  }

  Future<void> _closeGeneration(ScenarioGenerationJob job, {required bool cancel}) async {
    if (_closedGenerationJobs[job] == true) return;
    _closedGenerationJobs[job] = true;
    try {
      if (cancel) {
        unawaited(job.cancel().catchError((Object error) {
          debugPrint('Senaryo üretimi iptal edilemedi.');
        }));
      }
    } catch (_) {
      debugPrint('Senaryo üretimi iptal edilemedi.');
    } finally {
      try {
        await job.dispose();
      } catch (_) {
        debugPrint('Senaryo üretim kaynakları kapatılamadı.');
      }
    }
  }

  Future<void> _generate() async {
    final request = _requestDraft;
    if (_busy || request == null || !widget.generationService.isAvailable) return;
    final epoch = ++_generationEpoch;
    _workspaceChanged();
    final scenarioId = 'generated-${DateTime.now().microsecondsSinceEpoch}-${++_generationSequence}';
    ScenarioGenerationJob? job;
    setState(() {
      _generationBusy = true;
      _generationStatus = 'Senaryo taslağı isteniyor';
      _generationError = null;
    });
    try {
      job = widget.generationService.start(request);
      _generationJob = job;
      final raw = await job.response;
      if (!mounted || epoch != _generationEpoch) return;
      _workspaceChanged();
      setState(() {
        _generationRaw = raw;
        _responseRequest = request;
        _responseScenarioId = scenarioId;
        _generationStatus = 'Ham cevap alındı; henüz doğrulanmadı.';
      });
    } catch (_) {
      if (!mounted || epoch != _generationEpoch) return;
      setState(() {
        _generationStatus = 'Üretim hatası';
        _generationError = 'Taslak alınamadı. Mevcut editör ve ham cevap korundu.';
      });
    } finally {
      // İptal yolu aynı işin sahibi olarak kalır; bekleyen iptali dispose ile bitirme.
      if (mounted && epoch == _generationEpoch) {
        setState(() { _generationBusy = false; });
        if (identical(_generationJob, job)) _generationJob = null;
        if (job != null) unawaited(_closeGeneration(job, cancel: false));
      }
    }
  }

  Future<void> _cancelGeneration() async {
    if (!_generationBusy || _generationCancelling) return;
    final job = _generationJob;
    final epoch = ++_generationEpoch;
    setState(() {
      _generationCancelling = true;
      _generationStatus = 'İptal bekleniyor';
    });
    try {
      if (job != null) await job.cancel();
      if (!mounted || epoch != _generationEpoch) return;
      setState(() { _generationStatus = 'Üretim iptal edildi.'; });
    } catch (_) {
      if (!mounted || epoch != _generationEpoch) return;
      setState(() {
        _generationStatus = 'İptal hatası';
        _generationError = 'Sonuç takibi durduruldu; hizmetin iptali doğrulanamadı.';
      });
    } finally {
      if (identical(_generationJob, job)) _generationJob = null;
      if (job != null) unawaited(_closeGeneration(job, cancel: false));
      if (mounted && epoch == _generationEpoch) {
        setState(() {
          _generationBusy = false;
          _generationCancelling = false;
        });
      }
    }
  }

  Future<void> _transferGeneration() async {
    final raw = _generationRaw;
    final request = _responseRequest;
    final scenarioId = _responseScenarioId;
    if (_busy || _confirmingTransfer || !_isScenario || raw == null ||
        request == null || scenarioId == null) {
      return;
    }
    final epoch = _generationEpoch;
    _confirmingTransfer = true;
    try {
      if (_json.text.isNotEmpty) {
        final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
          title: const Text('Editördeki taslak değiştirilsin mi?'),
          content: const Text('Ham cevap ayrı kalır. Aktarım mevcut JSON ve doğrulama sonucunu değiştirir.'),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(context, false), autofocus: true,
              child: const Text('Taslağı koru')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Aktar')),
          ],
        ));
        if (confirmed != true) return;
      }
      if (!mounted || epoch != _generationEpoch || _busy || !_isScenario) return;
      final prepared = request.prepareInput(raw, scenarioId: scenarioId, edited: false);
      setState(() {
        _json.text = prepared.json;
        _editorRequest = request;
        _editorScenarioId = scenarioId;
        _generationEdited = false;
        _demoDraft = false;
        _demoEdited = false;
        _validated = null;
        _scenarioInput = null;
        _error = null;
        _generationError = null;
        _formatNormalization = prepared.normalization;
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() { _generationError = 'Aktarılamadı: ${error.message} Ham cevap ve editör korundu.'; });
    } finally {
      _confirmingTransfer = false;
    }
  }

  Widget _requestForm() {
    final draft = _requestDraft;
    return ExpansionTile(
      key: const ValueKey('scenario-import-request-form'),
      title: const Text('Senaryo üretim isteği'),
      initiallyExpanded: false,
      maintainState: true,
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.generationService.availabilityMessage,
          key: const ValueKey('scenario-generation-availability')),
        const SizedBox(height: 12),
        DropdownButtonFormField<BehaviorCard>(
          key: const ValueKey('scenario-request-behavior'),
          initialValue: _requestCard,
          isExpanded: true,
          isDense: false,
          itemHeight: null,
          decoration: InputDecoration(
            labelText: 'Hedef davranış',
            border: const OutlineInputBorder(),
            errorText: _requestCardError,
            errorMaxLines: 6,
          ),
          items: [
            for (final card in BehaviorCards.all)
              DropdownMenuItem(value: card, child: Text(card.title)),
          ],
          onChanged: _busy ? null : (card) {
            _requestCard = card;
            _requestEdited();
          },
        ),
        if (_requestCard != null)
          Text('Kart sürümü: ${_requestCard!.cardVersion}',
              key: const ValueKey('scenario-request-card-version')),
        const SizedBox(height: 12),
        const Text('Karakter yaşı (ay, zorunlu)'),
        TextField(
          key: const ValueKey('scenario-request-age'),
          controller: _requestAge,
          readOnly: _busy,
          keyboardType: const TextInputType.numberWithOptions(),
          decoration: InputDecoration(
            hintText: '12–36',
            border: const OutlineInputBorder(),
            errorText: _requestAgeError,
            errorMaxLines: 6,
          ),
          onChanged: (_) => _requestEdited(),
        ),
        const SizedBox(height: 12),
        const Text('Sahne / ortam bağlamı (zorunlu)'),
        TextField(
          key: const ValueKey('scenario-request-context'),
          controller: _requestContext,
          readOnly: _busy,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            errorText: _requestContextError,
            errorMaxLines: 6,
          ),
          onChanged: (_) => _requestEdited(),
        ),
        const SizedBox(height: 12),
        const Text('Ek yönerge (isteğe bağlı)'),
        TextField(
          key: const ValueKey('scenario-request-instructions'),
          controller: _requestInstructions,
          readOnly: _busy,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onChanged: (_) => _requestEdited(),
        ),
        const SizedBox(height: 8),
        const Text('Ek yönerge kart kurallarını değiştiremez. '
            'Kart seçimi, doğrulanmış üretim veya analiz desteği anlamına gelmez.'),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const ValueKey('scenario-request-validate'),
            onPressed: _busy ? null : _validateRequest,
            child: const Text('İstek taslağını doğrula'),
          ),
        ),
        if (draft != null)
          Column(
            key: const ValueKey('scenario-request-summary'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              const Text('Doğrulanmış istek özeti — içerik onayı değildir.'),
              Text('Davranış: ${draft.card.title}'),
              Text('Kart sürümü: ${draft.card.cardVersion}'),
              Text('Karakter yaşı: ${draft.ageMonths} ay'),
              Text('Bağlam: ${draft.sceneContext}'),
              if (draft.additionalInstructions != null)
                Text('Ek yönerge: ${draft.additionalInstructions}'),
              if (draft.ageMonths < 30)
                const Text('Bu yaş için görev uyarlaması gerekli.'),
              const Text('Yalnız alanlar doğrulandı; kart/içerik uygunluğu onaylanmadı.'),
            ],
          ),
        if (widget.generationService.isAvailable)
          FilledButton(
            key: const ValueKey('scenario-generation-start'),
            onPressed: _busy || draft == null ? null : _generate,
            child: const Text('Senaryo taslağı iste'),
          ),
        if (_generationRaw != null) ...[
          const Text('Hizmetin ham cevabı — içerik onaylanmadı'),
          Text('Bu cevap: ${_responseRequest!.behaviorId}, kart ${_responseRequest!.cardVersion}, '
            '${_responseRequest!.ageMonths} ay. Metadata uygulamada bu istekten eklenir.'),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: SingleChildScrollView(child: SelectableText(_generationRaw!,
              key: const ValueKey('scenario-generation-raw'))),
          ),
          OutlinedButton(
            key: const ValueKey('scenario-generation-transfer'),
            onPressed: _busy ? null : _transferGeneration,
            child: const Text('Cevabı JSON editörüne aktar'),
          ),
        ],
      ],
    );
  }

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
          'Kaydedilmemiş değişiklikler kaybolabilir. Süren üretim varsa iptal edilir.',
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
    for (final controller in [_json, _requestAge, _requestContext, _requestInstructions]) {
      _controllerTexts[controller] = controller.text;
      controller.addListener(() {
        final previous = _controllerTexts[controller];
        _controllerTexts[controller] = controller.text;
        if (previous != controller.text) _workspaceChanged();
      });
    }
    unawaited(_loadDraft());
  }

  void _modelChanged(LocalLlamaTestState state) {
    if (!mounted) return;
    _workspaceChanged();
    if (state.phase == LocalLlamaPhase.completed) {
      setState(() {
        _editorRequest = null;
        _editorScenarioId = null;
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
        _restoredDemoRaw = '';
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
    _workspaceChanged();
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
    if (_isScenario && _editorRequest != null) _generationEdited = true;
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
          if (_editorRequest != null) {
            final prepared = _editorRequest!.prepareInput(_json.text,
              scenarioId: _editorScenarioId!, edited: _generationEdited);
            _json.text = prepared.json;
            normalization = prepared.normalization ?? normalization;
          } else if (_demoDraft) {
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
    _workspaceChanged();
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
        _editorRequest = null;
        _editorScenarioId = null;
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
    ++_generationEpoch;
    final job = _generationJob;
    _generationJob = null;
    if (job != null) unawaited(_closeGeneration(job, cancel: !_generationCancelling));
    unawaited(_modelSubscription?.cancel());
    unawaited(_modelDemo.dispose());
    _json.dispose();
    _requestAge.dispose();
    _requestContext.dispose();
    _requestInstructions.dispose();
    super.dispose();
  }

  Future<void> _copyRawResponse() async {
    final raw = _modelDemo.state.text.isNotEmpty ? _modelDemo.state.text : _restoredDemoRaw;
    if (raw.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: raw));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ham cevap kopyalandı.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ham cevap kopyalanamadı.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final graph = _validated;
    final input = _scenarioInput;
    final model = _modelDemo.state;
    final modelStatus = switch (model.phase) {
      LocalLlamaPhase.idle => 'Henüz üretim denenmedi',
      LocalLlamaPhase.loading => 'Model yükleniyor',
      LocalLlamaPhase.generating => 'Metin üretiliyor',
      LocalLlamaPhase.cancelling => 'İptal bekleniyor',
      LocalLlamaPhase.closing => 'Kaynaklar kapatılıyor',
      LocalLlamaPhase.completed => 'Tamamlandı',
      LocalLlamaPhase.cancelled => 'İptal edildi',
      LocalLlamaPhase.error => 'Hata',
    };
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
                    : 'Hazır grafı doğrula',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(_isScenario
                  ? 'Ortak başlangıç ve alternatifleri içeren JSON’u girip graf oluşturun.'
                  : 'Sahne ve bağlantıları içeren JSON’u doğrulayıp grafı açın.'),
              const SizedBox(height: 8),
              const Text(
                'Taslağı bu cihazda saklamak için Taslağı kaydet’i kullanın. '
                'Çalışan işler ve doğrulanmış graf geri yüklenmez.',
                key: ValueKey('scenario-import-session'),
              ),
              if (_draftLoading)
                const Text('Kayıtlı taslak okunuyor…', key: ValueKey('scenario-draft-loading')),
              if (_draftWriting)
                const Text('Kayıt işlemi sürüyor…'),
              if (_draftError != null)
                Text(_draftError!, key: const ValueKey('scenario-draft-error')),
              if (_draftNotice != null)
                Text(_draftNotice!, key: const ValueKey('scenario-draft-notice')),
              if (_savedRevision != null && _savedRevision != _workspaceRevision)
                const Text('Kaydedilmemiş değişiklikler var.', key: ValueKey('scenario-draft-dirty')),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton(
                  key: const ValueKey('scenario-draft-save'),
                  onPressed: _draftLoading || _draftWriting ? null : _saveDraft,
                  child: const Text('Taslağı kaydet'),
                ),
                TextButton(
                  key: const ValueKey('scenario-draft-delete'),
                  onPressed: _draftLoading || _draftWriting ? null : _deleteDraft,
                  child: const Text('Kayıtlı taslağı sil'),
                ),
              ]),
              const Text('Bu graf, hazır D01 klip planına ve videolarına bağlı değildir.'),
              if (_generationStatus != null) ...[
                Text(_generationStatus!, key: const ValueKey('scenario-generation-status')),
                if (_generationError != null)
                  Text(_generationError!, key: const ValueKey('scenario-generation-error')),
                if (_generationBusy)
                  OutlinedButton(
                    key: const ValueKey('scenario-generation-cancel'),
                    onPressed: _generationCancelling ? null : _cancelGeneration,
                    child: const Text('Üretimi iptal et'),
                  ),
              ],
              if (_isScenario && model.phase != LocalLlamaPhase.idle) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Model: $modelStatus',
                        key: const ValueKey('scenario-import-model-status')),
                    if (model.isBusy)
                      OutlinedButton(
                        key: const ValueKey('scenario-import-model-cancel'),
                        onPressed: model.phase == LocalLlamaPhase.cancelling ||
                                model.phase == LocalLlamaPhase.closing
                            ? null : _modelDemo.cancel,
                        child: const Text('İptal'),
                      ),
                  ],
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
                  OutlinedButton.icon(
                    key: const ValueKey('scenario-import-view'),
                    onPressed: graph == null || _busy ? null : _viewGraph,
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('Grafı görüntüle'),
                  ),
                  if (_isScenario)
                    OutlinedButton.icon(
                      key: const ValueKey('scenario-import-load-example'),
                      onPressed: _busy ? null : _loadExample,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Elle hazırlanmış D01 örneğini yükle'),
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
                const Text(
                  'Biçim normalizasyonu uygulandı. Ayrıntılar aşağıdadır.',
                  key: ValueKey('scenario-import-normalization'),
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
                    ],
                    Text('Davranış: ${graph.behaviorId} · Kart sürümü: ${graph.cardVersion}'),
                    Text('Sahne: ${graph.scenes.length} · Bağlantı: ${graph.transitions.length}'),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (kDebugMode && _isScenario) ...[
                KeyedSubtree(key: ValueKey('restored-form-$_formRestoreVersion'), child: _requestForm()),
                const SizedBox(height: 12),
              ],
              ExpansionTile(
                key: const ValueKey('scenario-import-format-details'),
                title: const Text('Biçim ve kaynak ayrıntıları'),
                initiallyExpanded: false,
                maintainState: true,
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_isScenario
                      ? 'Teknik geliştirici arayüzü: senaryo içeriğini JSON olarak '
                          'yapıştırın. Ortak başlangıç ve alternatiflerin metinlerini '
                          'girin; sahne/kenar kimlikleri veya startSceneId girmeyin. '
                          'Yalnız tek dallanma düzeyi desteklenir.'
                      : 'Teknik geliştirici arayüzü: sahneleri ve bağlantıları '
                          'içeren hazır graf JSON metnini yapıştırın.'),
                  const SizedBox(height: 8),
                  const Text('Planlanan içerik, davranışın gerçekleştiğine dair kanıt değildir.'),
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
                    if (input != null) Text(_sourceText(input)),
                    if (_formatNormalization != null)
                      Text(_formatNormalization!,
                          key: const ValueKey('scenario-import-normalization-details')),
                  ] else
                    const Text(ScenarioGraphScreen.importedSourceLabel),
                ],
              ),
              if (_isScenario) ...[
                const SizedBox(height: 12),
                ExpansionTile(
                  key: const ValueKey('scenario-import-model-demo'),
                  title: const Text('Modelden taslak al — D01, 30 ay'),
                  initiallyExpanded: false,
                  maintainState: true,
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (model.text.isNotEmpty || _restoredDemoRaw.isNotEmpty)
                      OutlinedButton.icon(
                        key: const ValueKey('scenario-import-copy-raw'),
                        onPressed: _copyRawResponse,
                        icon: const Icon(Icons.copy),
                        label: const Text('Ham cevabı kopyala'),
                      ),
                    if (_restoredDemoRaw.isNotEmpty) ...[
                      const Text('Kayıtlı yerel D01 demo ham cevabı — üretim durumu geri yüklenmedi.'),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 240),
                        child: SingleChildScrollView(child: SelectableText(_restoredDemoRaw,
                          key: const ValueKey('scenario-restored-demo-raw'))),
                      ),
                    ],
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: SingleChildScrollView(
                        key: const ValueKey('scenario-import-model-scroll'),
                        child: LocalLlamaTestCard(
                          service: _modelDemo,
                          enabled: !_loadingExample && !_generationBusy,
                          disabledReason: _generationBusy
                              ? 'Senaryo isteği sürerken yerel demo başlatılamaz.'
                              : 'Örnek yüklenirken model üretimi kapalıdır.',
                        ),
                      ),
                    ),
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
