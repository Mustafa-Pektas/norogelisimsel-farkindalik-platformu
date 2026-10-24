import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/behavior_cards.dart';
import '../models/scenario_graph.dart';
import '../models/scenario_clip_plan.dart';
import '../services/clip_plan_generation_service.dart';
import '../services/http_scenario_generation_service.dart';
import 'clip_production_plan_screen.dart';
import '../models/scenario_input.dart';
import '../models/scenario_generation_request.dart';
import '../models/scenario_generation_result.dart';
import '../widgets/scenario_narrative_cards.dart';
import '../models/scenario_workspace_draft.dart';
import '../services/scenario_graph_converter.dart';
import '../services/scenario_generation_service.dart';
import '../services/scenario_draft_store.dart';
import 'scenario_graph_screen.dart';

enum _InputType { scenario, graph }

/// Stüdyo sonucunu inceleme, JSON düzenleme, doğrulama, graf ve klip planı.
class ScenarioGraphImportScreen extends StatefulWidget {
  const ScenarioGraphImportScreen({
    super.key,
    this.initialScenarioContent = false,
    this.generationService = const UnavailableScenarioGenerationService(),
    this.draftStore = const ScenarioDraftStore(),
    this.clipPlanService = const HttpScenarioGenerationService(),
    this.incomingResult,
  });

  /// Doğrudan Stüdyo girişi içerikle başlar; eski hazır graf yolu korunur.
  final bool initialScenarioContent;

  /// Eski çağrıların kaynak uyumluluğu için; ekran senaryo üretimi başlatmaz.
  final ScenarioGenerationService generationService;
  final ScenarioDraftStore draftStore;
  final ClipPlanGenerationService clipPlanService;
  final ScenarioGenerationResult? incomingResult;

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
  // Oturum dışına taşınmaz; _snapshot ve kayıt dinleyicilerine dahil edilmez.
  final _teamAccessKey = TextEditingController();
  BehaviorCard? _requestCard;
  ScenarioGenerationRequest? _requestDraft;
  final _drafts = {_InputType.graph: '', _InputType.scenario: ''};
  _InputType _type = _InputType.graph;
  ScenarioGraph? _validated;
  ScenarioInput? _scenarioInput;
  String? _error;
  bool _planBusy = false;
  int _planEpoch = 0;
  ScenarioGenerationJob? _planJob;
  ScenarioGraph? _planGraph;
  ScenarioGenerationRequest? _planSourceRequest;
  ScenarioClipPlan? _clipPlan;
  String? _planRaw;
  String? _clipPlanRaw;
  String? _planError;
  String? _planNotice;
  bool _openingPlan = false;
  bool _loadingExample = false;
  bool _demoDraft = false;
  bool _demoEdited = false;
  String? _formatNormalization;
  bool _confirmingExit = false;
  bool _allowExit = false;
  static int _generationSequence = 0;
  int _generationEpoch = 0;
  final _closedGenerationJobs = Expando<bool>();
  String? _generationError;
  String? _generationRaw;
  ScenarioGenerationResult? _responseResult, _editorResult, _pendingResult;
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
    demoRaw: _restoredDemoRaw,
    responseResult: _responseResult, editorResult: _editorResult, pendingResult: _pendingResult,
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
          _generationRaw = draft.generationRaw;
          _responseResult = draft.responseResult;
          _editorResult = draft.editorResult;
          _pendingResult ??= draft.pendingResult;
          _responseRequest = draft.responseRequest;
          _responseScenarioId = draft.responseScenarioId;
          _editorRequest = draft.editorRequest;
          _editorScenarioId = draft.editorScenarioId;
          _generationEdited = draft.generationEdited;
          _demoDraft = draft.demoDraft;
          _demoEdited = draft.demoEdited;
          _restoredDemoRaw = draft.demoRaw;
          _requestDraft = draft.editorRequest ?? draft.responseRequest;
          _validated = null;
          _scenarioInput = null;
          _error = null;
          _formatNormalization = null;
          _savedRevision = widget.incomingResult == null ? _workspaceRevision : null;
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
  bool get _busy => _loadingExample || _planBusy;
  bool get _hasDraft =>
      _planBusy || _planRaw != null || _restoredDemoRaw.isNotEmpty ||
      _pendingResult != null || _generationRaw != null ||
      _json.text.trim().isNotEmpty ||
      _requestCard != null ||
      _requestAge.text.isNotEmpty ||
      _requestContext.text.isNotEmpty ||
      _requestInstructions.text.isNotEmpty ||
      _drafts.entries.any((entry) =>
          entry.key != _type && entry.value.trim().isNotEmpty);

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
        _editorResult = _responseResult;
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

  Future<void> _acceptResult() async {
    final result = _pendingResult;
    if (result == null || _draftLoading || _busy || _confirmingTransfer) return;
    _confirmingTransfer = true;
    try {
      if (_json.text.isNotEmpty || _drafts.values.any((text) => text.isNotEmpty) || _generationRaw != null) {
        final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
          title: const Text('Editördeki taslak değiştirilsin mi?'),
          content: const Text('Seçilen sonucun ham cevabı ayrı tutulur. Mevcut editör, ham kayıt ve doğrulama '
            'yalnız onayınızla değişir; cihazdaki kayıt otomatik olarak yazılmaz.'),
          actions: [FilledButton(autofocus: true, onPressed: () => Navigator.pop(context, false), child: const Text('Taslağı koru')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Aktar'))]));
        if (confirmed != true) return;
      }
      if (!mounted || _busy) return;
      final prepared = result.request.prepareInput(result.rawResponse, scenarioId: result.scenarioId, edited: false);
      _workspaceChanged();
      setState(() {
        _drafts[_type] = _json.text;
        _type = _InputType.scenario;
        _json.text = prepared.json;
        _generationRaw = result.rawResponse;
        _responseResult = result; _editorResult = result; _pendingResult = null;
        _responseRequest = result.request; _editorRequest = result.request; _requestDraft = result.request;
        _responseScenarioId = result.scenarioId; _editorScenarioId = result.scenarioId;
        _requestCard = result.request.card;
        _requestAge.text = result.request.ageMonths.toString();
        _requestContext.text = result.request.sceneContext;
        _requestInstructions.text = result.request.additionalInstructions ?? '';
        _generationEdited = false; _demoDraft = false; _demoEdited = false;
        _validated = null; _scenarioInput = null; _error = null; _generationError = null;
        _formatNormalization = prepared.normalization;
      });
    } on FormatException catch (error) {
      if (mounted) setState(() { _generationError = error.message.toString(); });
    } finally { _confirmingTransfer = false; }
  }

  Widget _resultReview() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (_pendingResult != null) ...[
      Text('Stüdyo’dan seçilen sonuç: ${_pendingResult!.summary}', key: const ValueKey('scenario-incoming-result')),
      const Text('Mevcut taslak henüz değiştirilmedi. Aktarım yeni model çağrısı yapmaz.'),
      ExpansionTile(title: const Text('Gelen tam ham cevabı incele'), children: [
        SizedBox(height: 220, child: SingleChildScrollView(child: SelectableText(_pendingResult!.rawResponse,
          key: const ValueKey('scenario-incoming-raw')))),
      ]),
      FilledButton(key: const ValueKey('scenario-accept-result'),
        onPressed: _draftLoading || _busy ? null : _acceptResult,
        child: const Text('Seçilen sonucu JSON editörüne aktar')),
    ],
    if (_generationError != null) Text(_generationError!, key: const ValueKey('scenario-generation-error')),
    if (_generationRaw != null) ExpansionTile(
      key: const ValueKey('scenario-generation-raw-details'), title: const Text('Ham cevap ve kaynak'), maintainState: true,
      children: [
        if (_responseResult != null) Text(_responseResult!.summary),
        const Text('Ham cevap düzenlenmiş JSON değildir; içerik onayı anlamına gelmez.'),
        SizedBox(height: 240, child: SingleChildScrollView(child: SelectableText(_generationRaw!,
          key: const ValueKey('scenario-generation-raw')))),
        OutlinedButton(key: const ValueKey('scenario-generation-copy-raw'),
          onPressed: () => _copyRawText(_generationRaw!), child: const Text('Ham cevabı kopyala')),
        OutlinedButton(key: const ValueKey('scenario-generation-transfer'),
          onPressed: _busy || !_isScenario ? null : _transferGeneration, child: const Text('Cevabı JSON editörüne aktar')),
      ]),
    if (_editorResult != null) ExpansionTile(title: const Text('Senaryonun üretim kaynağı'), children: [
      Text(_editorResult!.summary),
      Text(_generationEdited ? 'Kullanıcı tarafından düzenlenmiş model taslağı (model_output_edited)' : 'Model çıktısı (model_output)'),
      SizedBox(height: 180, child: SingleChildScrollView(child: SelectableText(jsonEncode(
        _editorResult!.toJson()..remove('rawResponse'))))),
    ]),
  ]);

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
          'Kaydedilmemiş değişiklikler kaybolabilir. Süren klip planı isteği varsa yerel izleme durdurulur.',
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
    _pendingResult = widget.incomingResult;
    final planService = widget.clipPlanService;
    if (planService is HttpScenarioGenerationService) _teamAccessKey.text = planService.resolveAccessKey?.call() ?? '';
    _type = widget.initialScenarioContent ? _InputType.scenario : _InputType.graph;
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

  // Eski v1 taslakları içindir; yeni üretim bu metadata’yı kullanmaz.
  (String, String?) _legacyDemoInputJson(String text) {
    // Geçmiş ham cevap aynen korunur. Yalnız eski editör kopyası metadata alır.
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
      'schemaVersion': '1.0',
      'scenarioId': 'd01-qwen-yerel-demo',
      'title': 'D01 yerel model senaryo taslağı',
      'language': 'tr', 'ageMonths': 30, 'behaviorId': 'D01', 'cardVersion': '0.2',
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
    if (_editorRequest != null) _generationEdited = true;
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
            final (json, notice) = _legacyDemoInputJson(_json.text);
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
        _editorResult = null;
        _requestDraft = null;
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

  ScenarioGenerationRequest? get _planRequest {
    final request = (_isScenario ? _editorRequest : null) ?? _requestDraft;
    final graph = _validated;
    if (request == null || graph == null || graph.behaviorId != request.behaviorId ||
        graph.cardVersion != request.cardVersion || graph.ageMonths != request.ageMonths ||
        jsonEncode(graph.behaviors.map((ref) => ref.toJson()).toList()) != jsonEncode(request.behaviors.map((ref) => ref.toJson()).toList()) ||
        (_editorResult != null && graph.scenarioId != _editorResult!.scenarioId)) {
      return null;
    }
    return request;
  }

  Future<void> _generatePlan() async {
    final graph = _validated;
    final request = _planRequest;
    if (_busy || graph == null || request == null) return;
    final epoch = ++_planEpoch;
    final input = ClipPlanGenerationRequest(request: request, graph: graph,
      planId: 'generated-${DateTime.now().microsecondsSinceEpoch}-${++_generationSequence}');
    setState(() { _planBusy = true; _planError = null; _planNotice = 'Sunucudan klip planı bekleniyor…'; });
    ScenarioGenerationJob? job;
    try {
      final service = widget.clipPlanService;
      job = (service is HttpScenarioGenerationService
        ? service.withAccessKey(() => _teamAccessKey.text.trim()) : service).startPlan(input);
      _planJob = job;
      final raw = await job.response;
      if (!mounted || epoch != _planEpoch) return;
      // Kontrollü servisler de aynı yerel sözleşmeden geçer.
      setState(() { _planRaw = raw; });
      final plan = ScenarioClipPlan.fromJsonString(raw);
      plan.validateAgainst(graph);
      if (plan.clips.any((clip) => clip.targetDurationS > (request.production?.maxClipDurationS ?? 8))) {
        throw const FormatException('Klip süresi seçilen üst sınırı aşıyor.');
      }
      plan.d01ObservationDurations(graph, requireTiming: true);
      if (plan.planId != input.planId || plan.visualSuggestions == null ||
          plan.clips.any((clip) => clip.voiceoverInstructions == null)) {
        throw const FormatException('Plan referansları veya ayrı ses/görsel alanları eksik.');
      }
      setState(() {
        _clipPlan = plan; _planGraph = graph; _clipPlanRaw = raw; _planSourceRequest = request;
        _planNotice = 'Plan yapısal olarak doğrulandı; içerik henüz onaylanmadı. İnceleyip dışa aktarın.';
      });
    } catch (error) {
      if (!mounted || epoch != _planEpoch) return;
      setState(() {
        _planNotice = null;
        _planError = error is FormatException ? error.message.toString() :
          error is ScenarioGenerationFailure ? error.message : 'Klip planı alınamadı; örnek plan eklenmedi.';
        if (error is ScenarioGenerationFailure && error.rawResponse != null) _planRaw = error.rawResponse;
      });
    } finally {
      if (job != null) await _closeGeneration(job, cancel: false);
      if (mounted && epoch == _planEpoch) {
        setState(() { _planBusy = false; _planJob = null; });
      }
    }
  }

  void _cancelPlan() {
    if (!_planBusy) return;
    ++_planEpoch;
    final job = _planJob;
    _planJob = null;
    setState(() {
      _planBusy = false;
      _planNotice = 'Yerel plan beklemesi durduruldu; sunucudaki üretimin iptali doğrulanmadı.';
    });
    if (job != null) unawaited(_closeGeneration(job, cancel: true));
  }

  Future<void> _viewPlan() async {
    if (_openingPlan || _busy || _clipPlan == null || _planGraph != _validated || _planSourceRequest != _planRequest) return;
    _openingPlan = true;
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
        ClipProductionPlanScreen(providedPlan: (graph: _planGraph!, plan: _clipPlan!), rawPlanJson: _clipPlanRaw,
          sourceContext: _editorResult == null ? null : {..._editorResult!.toJson(),
            'originalSource': 'model_output', 'source': _generationEdited ? 'model_output_edited' : 'model_output',
            'edited': _generationEdited, 'editorJson': _json.text, 'planId': _clipPlan!.planId,
            'inputType': _isScenario ? 'scenario' : 'graph', 'graph': _planGraph!.toJson()})));
    } finally {
      _openingPlan = false;
    }
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
                '${_editorResult?.summary ?? ''}\n'
                '${ScenarioGraphImportScreen.sourceDisclaimer}',
      ),
    ));
  }

  @override
  void dispose() {
    ++_planEpoch;
    final planJob = _planJob;
    _planJob = null;
    if (planJob != null) unawaited(_closeGeneration(planJob, cancel: true));
    ++_generationEpoch;

    _json.dispose();
    _requestAge.dispose();
    _requestContext.dispose();
    _requestInstructions.dispose();
    _teamAccessKey.dispose();
    super.dispose();
  }

  Future<void> _copyRawText(String raw) async {
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
    final screen = Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: ModalRoute.of(context)?.canPop == true
            ? BackButton(onPressed: _requestExit)
            : null,
        title: const Text('Senaryo çalışma alanı'),
        backgroundColor: const Color(0xFF142540),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (kDebugMode) ...[
                TextField(
                  key: const ValueKey('scenario-team-access-key'),
                  controller: _teamAccessKey,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  autofillHints: const [],
                  readOnly: _busy,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Ekip erişim anahtarı',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      key: const ValueKey('scenario-team-access-clear'),
                      tooltip: 'Erişim anahtarını temizle',
                      onPressed: _busy || _teamAccessKey.text.isEmpty ? null
                        : () => setState(() { _teamAccessKey.clear(); }),
                      icon: const Icon(Icons.clear),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text('Yalnız bu ekran oturumunda tutulur; taslağa kaydedilmez. '
                  'Yerel geliştirme için boş bırakılabilir.'),
                const SizedBox(height: 12),
              ],
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
                  ? 'Stüdyo sonucunu aktarın veya senaryo JSON’unu düzenleyip graf oluşturun.'
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
              const Text('Hazır D01 videoları bu senaryoya otomatik bağlanmaz.'),
              _resultReview(),
              if (_scenarioInput != null) ExpansionTile(title: const Text('Anlatı ve sahneleri incele'),
                children: [ScenarioNarrativeCards(input: _scenarioInput!, request: _editorRequest)]),
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
              if (graph != null) const Padding(padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('3. Üretime hazırla', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
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
                  if (graph != null && (kDebugMode || _editorRequest != null)) ...[
                    OutlinedButton.icon(
                      key: const ValueKey('scenario-request-clip-plan'),
                      onPressed: _busy || _planRequest == null ? null : _generatePlan,
                      icon: const Icon(Icons.movie_outlined), label: const Text('Klip ve prompt planı hazırla'),
                    ),
                    if (_clipPlan != null && _planGraph == graph && _planSourceRequest == _planRequest)
                      OutlinedButton(key: const ValueKey('scenario-view-clip-plan'),
                        onPressed: _busy ? null : _viewPlan, child: Text(_planError == null ? 'Klip planını incele' : 'Önceki geçerli planı incele')),
                  ],
                  if (_isScenario)
                    OutlinedButton.icon(
                      key: const ValueKey('scenario-import-load-example'),
                      onPressed: _busy ? null : _loadExample,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Elle hazırlanmış D01 örneğini yükle'),
                    ),
                ],
              ),
              if (kDebugMode && graph != null && _planRequest == null)
                const Text('Klip planı için Stüdyo’dan bu grafla eşleşen doğrulanmış istek ve sonuçla devam edin.'),
              if (_planNotice != null) Text(_planNotice!, key: const ValueKey('clip-plan-status')),
              if (_planError != null) Text(_planError!, key: const ValueKey('clip-plan-error')),
              if (_planBusy)
                TextButton(key: const ValueKey('cancel-clip-plan'), onPressed: _cancelPlan,
                  child: const Text('Plan beklemesini durdur')),
              if (_planRaw != null)
                ExpansionTile(title: const Text('Klip planının tam ham cevabı'), children: [
                  SizedBox(height: 180, child: SingleChildScrollView(child: SelectableText(_planRaw!))),
                  TextButton(onPressed: () => _copyRawText(_planRaw!), child: const Text('Ham planı kopyala')),
                  const Text('Plan bu oturumdadır; kalıcı taslak kaydına dahil değildir. İnceleme ekranından dışa aktarabilirsiniz.'),
                ]),
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
                    Text('Davranışlar: ${graph.behaviors.map((ref) => '${ref.behaviorId} (${ref.cardVersion})').join(', ')}'),
                    Text('Sahne: ${graph.scenes.length} · Bağlantı: ${graph.transitions.length}'),
                  ],
                ),
              ],
              const SizedBox(height: 16),
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
                      'Hizmet cevabının metadata’sı doğrulanmış istekten gelir: şema, senaryo kimliği, '
                      'başlık, dil, yaş, davranış/kart sürümü ve kaynak. '
                      'Model yalnız ortak başlangıç ile alternatif başlık/devam/bitiş '
                      'metinlerini sağlar. Düzenlenen JSON ham cevap sayılmaz.',
                    ),
                    const Text(
                      'Cevap biçim normalizasyonu: yalnız tüm cevabı çevreleyen '
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
              if (_restoredDemoRaw.isNotEmpty) ...[
                const SizedBox(height: 12),
                ExpansionTile(
                  key: const ValueKey('scenario-import-legacy-records'),
                  title: const Text('Geçmiş yerel demo kaydı'),
                  initiallyExpanded: false,
                  maintainState: true,
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Geçmiş ham cevaptır; yeni üretim veya içerik onayı değildir.'),
                    OutlinedButton.icon(
                      key: const ValueKey('scenario-import-copy-raw'),
                      onPressed: () => _copyRawText(_restoredDemoRaw),
                      icon: const Icon(Icons.copy),
                      label: const Text('Geçmiş ham cevabı kopyala'),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: SingleChildScrollView(
                        child: SelectableText(_restoredDemoRaw,
                          key: const ValueKey('scenario-restored-demo-raw')),
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
