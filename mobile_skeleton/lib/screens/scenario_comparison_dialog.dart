import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/scenario_generation_request.dart';
import '../models/scenario_generation_result.dart';
import '../models/scenario_input.dart';
import '../widgets/scenario_narrative_cards.dart';
import '../services/http_scenario_generation_service.dart';
import '../services/scenario_generation_service.dart';

// 223bc7d _runLiveComparisonDialog uyarlaması: üç kol, tablo ve ham ayrıntılar.
// Otomatik başlangıç, sabit risk eşikleri ve ilk hatada sonuç kaybı alınmadı.
class ScenarioComparisonDialog extends StatefulWidget {
  const ScenarioComparisonDialog({super.key, required this.request, required this.service,
    this.initialSelection = 'ALL', this.onContinue});
  final ScenarioGenerationRequest request;
  final HttpScenarioGenerationService service;
  final String initialSelection;
  final Future<void> Function(ScenarioGenerationResult, HttpScenarioGenerationService)? onContinue;
  @override
  State<ScenarioComparisonDialog> createState() => _ScenarioComparisonDialogState();
}

class _Trial {
  _Trial(this.arm, this.preview);
  final String arm;
  final Map<String, dynamic> preview;
  String status = 'Başlatılmadı';
  String? raw, error;
  Map<String, dynamic>? measurement, continuity;
  ScenarioGenerationResult? result;
  Map<String, dynamic> toJson() => {'arm': arm, 'status': status, 'rawResponse': raw,
    'error': error, 'measurement': measurement, 'textualContinuity': continuity, 'preview': preview,
    'selectedResult': result?.toJson()};
}

class _ScenarioComparisonDialogState extends State<ScenarioComparisonDialog> {
  static const _validSelections = {'ALL', 'A', 'B', 'C'};
  late String _selection;
  final _previews = <String, Map<String, dynamic>>{};
  final _trials = <_Trial>[];
  final _closed = Expando<bool>();
  final _accessKey = TextEditingController();
  HttpScenarioComparisonJob? _job;
  bool _busy = false, _allowClose = false, _confirmingClose = false;
  int _epoch = 0;
  _Trial? _active;
  String? _notice;
  bool _openingResult = false;

  @override
  void initState() {
    super.initState();
    if (!_validSelections.contains(widget.initialSelection)) {
      throw ArgumentError.value(widget.initialSelection, 'initialSelection', 'ALL, A, B veya C olmalıdır.');
    }
    _selection = widget.initialSelection;
    _accessKey.text = widget.service.resolveAccessKey?.call() ?? '';
  }

  HttpScenarioGenerationService get _sessionService =>
      widget.service.withAccessKey(() => _accessKey.text.trim());
  List<String> get _arms => _selection == 'ALL' ? ['A', 'B', 'C'] : [_selection];
  bool get _ready => _arms.every(_previews.containsKey) &&
    _arms.map((a) => _previews[a]!['protocolId']).toSet().length == 1;

  Future<void> _disposeJob(HttpScenarioComparisonJob job) async {
    if (_closed[job] == true) return;
    _closed[job] = true;
    try { await job.dispose(); } catch (_) { /* Arayüz/diğer sonuçlar korunur. */ }
  }

  Future<void> _preview() async {
    if (_busy) return;
    final epoch = ++_epoch;
    final arms = _arms;
    setState(() { _busy = true; _notice = null; _previews.clear(); });
    try {
      for (final arm in arms) {
        if (!mounted || epoch != _epoch) return;
        final job = _sessionService.startComparison(widget.request, arm: arm, preview: true);
        _job = job;
        try {
          final result = await job.result;
          if (!mounted || epoch != _epoch) return;
          setState(() { _previews[arm] = Map<String, dynamic>.from(result['preview'] as Map); });
        } finally { if (identical(_job, job)) _job = null; await _disposeJob(job); }
      }
      if (mounted && epoch == _epoch && !_ready) {
        setState(() { _notice = 'Model/kaynak protokolü değişti; önizlemeyi yenileyin.'; });
      }
    } catch (error) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _notice = error is ScenarioGenerationFailure ? error.message : 'İstem önizlemesi alınamadı.';
        });
      }
    } finally { if (mounted && epoch == _epoch) setState(() { _busy = false; }); }
  }

  Future<void> _run() async {
    if (_busy || !_ready) return;
    final epoch = ++_epoch;
    final batch = [for (final arm in _arms) _Trial(arm, _previews[arm]!)];
    setState(() { _busy = true; _notice = null; _trials.addAll(batch); });
    try {
      for (final trial in batch) {
        if (!mounted || epoch != _epoch) return;
        _active = trial;
        setState(() { trial.status = 'Yanıt bekleniyor'; });
        final job = _sessionService.startComparison(widget.request, arm: trial.arm, preview: false,
          protocolId: trial.preview['protocolId'] as String);
        _job = job;
        try {
          final result = await job.result;
          if (!mounted || epoch != _epoch) return;
          trial.raw = result['rawResponse'] as String?;
          final narrative = ScenarioGenerationResult.fromServer(widget.request, result);
          setState(() {
            trial.status = 'Yapısal olarak geçerli — içerik incelenmedi';
            trial.raw = result['rawResponse'] as String;
            trial.result = narrative;
            trial.measurement = result['measurement'] is Map ? Map<String, dynamic>.from(result['measurement'] as Map) : null;
            trial.continuity = result['textualContinuity'] is Map ? Map<String, dynamic>.from(result['textualContinuity'] as Map) : null;
          });
        } catch (error) {
          if (!mounted || epoch != _epoch) return;
          setState(() {
            trial.status = 'Hata';
            trial.error = error is ScenarioGenerationFailure ? error.message : 'Karşılaştırma isteği tamamlanamadı.';
            if (error is ScenarioGenerationFailure) {
              trial.raw = error.rawResponse; trial.measurement = error.measurement;
            }
          });
        } finally { if (identical(_job, job)) _job = null; await _disposeJob(job); }
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() { _busy = false; _active = null; });
    }
  }

  void _cancel() {
    if (!_busy) return;
    ++_epoch;
    final job = _job; _job = null;
    setState(() {
      _busy = false;
      _active?.status = 'Yerel izleme durduruldu'; _active = null;
      _notice = 'Kalan kollar başlatılmadı. Sunucudaki işin iptali doğrulanmadı; kapasite dolu kalabilir.';
    });
    if (job != null) {
      unawaited(job.cancel().catchError((Object _) {}));
      unawaited(_disposeJob(job));
    }
  }

  Future<void> _close() async {
    if (_busy || _confirmingClose) return;
    _confirmingClose = true;
    try {
      final confirmed = _trials.isEmpty || await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Karşılaştırma kapatılsın mı?'),
        content: const Text('Sonuçlar yalnız bu oturumdadır. Kapatmadan önce kopyalayabilirsiniz.'),
        actions: [TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Ekranda kal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kapat'))],
      )) == true;
      if (!mounted || !confirmed) return;
      setState(() { _allowClose = true; });
      Navigator.of(context).pop();
    } finally { _confirmingClose = false; }
  }

  Future<void> _copy(String text) async {
    try { await Clipboard.setData(ClipboardData(text: text)); }
    catch (_) { if (mounted) setState(() { _notice = 'Kopyalanamadı.'; }); }
  }
  @override
  void dispose() {
    ++_epoch;
    final job = _job;
    if (job != null) unawaited(_disposeJob(job));
    _accessKey.dispose();
    super.dispose();
  }

  String _value(Object? value) => value?.toString() ?? 'Bilinmiyor';

  Widget _mobileMetric(_Trial trial, String id, String label, Object? value) =>
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 170),
        child: Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              Text(_value(value), key: ValueKey('comparison-metric-$id-${trial.arm}'), softWrap: true),
            ],
          ),
        ),
      );

  Widget _resultSummary(_Trial trial, int index) => Card(
        key: ValueKey('comparison-result-summary-${trial.arm}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${index + 1}. Kol ${trial.arm} — ${trial.status}', softWrap: true),
              const SizedBox(height: 8),
              Wrap(
                children: [
                  _mobileMetric(trial, 'provider-ms', 'Sağlayıcı süresi (ms)', trial.measurement?['providerDurationMs']),
                  _mobileMetric(trial, 'endpoint-ms', 'Toplam istek süresi (ms)', trial.measurement?['endpointDurationMs']),
                  _mobileMetric(trial, 'prompt-tokens', 'Girdi tokenı', trial.measurement?['promptTokens']),
                  _mobileMetric(trial, 'output-tokens', 'Çıktı tokenı', trial.measurement?['outputTokens']),
                ],
              ),
            ],
          ),
        ),
      );

  Future<void> _continue(_Trial trial) async {
    final result = trial.result;
    if (_busy || _openingResult || result == null || widget.onContinue == null) return;
    setState(() { _openingResult = true; });
    try { await widget.onContinue!(result, _sessionService); }
    finally { if (mounted) setState(() { _openingResult = false; }); }
  }
  Widget _raw(String text, Key key) => ConstrainedBox(constraints: const BoxConstraints(maxHeight: 220),
    child: SingleChildScrollView(child: SelectableText(text, key: key)));

  @override
  Widget build(BuildContext context) => PopScope<void>(canPop: _allowClose,
    onPopInvokedWithResult: (didPop, result) { if (!didPop) unawaited(_close()); },
    child: Dialog(insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SizedBox(width: 960, height: MediaQuery.sizeOf(context).height * 0.85,
      child: SingleChildScrollView(
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Deneysel karşılaştırma — A / B / C', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Aynı form ve tek anlatı sözleşmesi: ortak başlangıç ve alternatif devam/bitişler. '
            'Kollar yalnız kaynak miktarında farklılaşır. Yapısal geçerlilik içerik onayı değildir.'),
          TextField(
            key: const ValueKey('comparison-team-access-key'),
            controller: _accessKey,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            readOnly: _busy,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Ekip erişim anahtarı (yerel geliştirmede boş)',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                key: const ValueKey('comparison-team-access-clear'),
                tooltip: 'Erişim anahtarını temizle',
                onPressed: _busy || _accessKey.text.isEmpty
                    ? null
                    : () => setState(() { _accessKey.clear(); }),
                icon: const Icon(Icons.clear),
              ),
            ),
          ),
          const Text('Anahtar yalnız bu karşılaştırma penceresi açıkken bellekte tutulur.'),
          Card(
            key: const ValueKey('comparison-request-summary'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Davranışlar: ${widget.request.cards.map((card) => '${card.id} — ${card.title} (kart ${card.cardVersion})').join('; ')}',
                    key: const ValueKey('comparison-request-behaviors'), softWrap: true),
                  Text('Yaş grubu: ${widget.request.ageDescription}', key: const ValueKey('comparison-request-age')),
                  Text('Senaryo düzeni: ${widget.request.linear ? '26 sahnelik doğrusal anlatı' : 'Alternatifli anlatı'}',
                    key: const ValueKey('comparison-request-structure'), softWrap: true),
                  Text('Ortam: ${widget.request.sceneContext}', softWrap: true),
                  if (widget.request.additionalInstructions != null)
                    Text('Ek yönerge: ${widget.request.additionalInstructions}', softWrap: true),
                ],
              ),
            ),
          ),
          Card(
            key: const ValueKey('comparison-source-arms'),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kaynak farkı'),
                  SizedBox(height: 6),
                  Text('A — Ek kart metni yok; ortak görev ve güvenlik talimatları ile seçili davranış adları korunur.'),
                  Text('B — Seçilen bütün davranış kartlarının metni ve ortak kart kuralları eklenir.'),
                  Text('C — Kanonik davranış kartı dosyasının tüm içeriği eklenir.'),
                  Text('Üç kol aynı istek, görev, anlatı sözleşmesi, model ve ayarları kullanır; yalnız kaynak bağlamı miktarı değişir.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(key: const ValueKey('comparison-arms'), initialValue: _selection,
            isExpanded: true, itemHeight: null,
            decoration: const InputDecoration(labelText: 'Çalıştırılacak kollar'),
            items: const [DropdownMenuItem(value: 'ALL', child: Text('A → B → C')),
              DropdownMenuItem(value: 'A', child: Text('A — Temel istem')),
              DropdownMenuItem(value: 'B', child: Text('B — Seçili kaynak')),
              DropdownMenuItem(value: 'C', child: Text('C — Geniş bağlam'))],
            onChanged: _busy ? null : (value) => setState(() { _selection = value!; })),
          Text('Başlatılırsa ${_arms.join(' → ')}: en fazla ${_arms.length} sağlayıcı çağrısı; sırayla, tekrar yok. Kota/ücret kullanabilir.',
            key: const ValueKey('comparison-call-count')),
          const Text('1. İstemleri inceleyin (model çağrısı yok). 2. Ayrı Başlat eylemiyle gerçek denemeyi çalıştırın.'),
          OutlinedButton(key: const ValueKey('comparison-preview'), onPressed: _busy ? null : _preview,
            child: const Text('İstemleri incele — 0 model çağrısı')),
          for (final entry in _previews.entries) ExpansionTile(key: ValueKey('comparison-preview-${entry.key}'),
            title: Text('${entry.key} — ${entry.value['sourceMode']}'), children: [
              Text('Model: ${entry.value['model']}; ayarlar: ${jsonEncode(entry.value['settings'])}'),
              Text('Kaynak: ${jsonEncode(entry.value['source'])}'),
              const Text('Gerçek sistem istemi'), _raw(entry.value['system'] as String, ValueKey('comparison-system-${entry.key}')),
              const Text('Gerçek kullanıcı istemi'), _raw(entry.value['user'] as String, ValueKey('comparison-user-${entry.key}')),
            ]),
          if (_notice != null) Text(_notice!, key: const ValueKey('comparison-notice')),
          if (_trials.isNotEmpty) ...[
            const Text('Sonuçlar — önceki hatalar da korunur'),
            LayoutBuilder(builder: (context, constraints) {
              if (constraints.maxWidth < 560) {
                return Column(
                  key: const ValueKey('comparison-results-narrow'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (var i = 0; i < _trials.length; i++) _resultSummary(_trials[i], i)],
                );
              }
              return SingleChildScrollView(
                key: const ValueKey('comparison-results-wide'),
                scrollDirection: Axis.horizontal,
                child: DataTable(dataRowMinHeight: 56, dataRowMaxHeight: 120, columns: const [
                  DataColumn(label: Text('Kol')), DataColumn(label: Text('Durum')), DataColumn(label: Text('Sağlayıcı ms')),
                  DataColumn(label: Text('İstek ms')), DataColumn(label: Text('Girdi token')), DataColumn(label: Text('Çıktı token')),
                ], rows: [for (var i = 0; i < _trials.length; i++) DataRow(cells: [
                  DataCell(Text('${i + 1}: ${_trials[i].arm}', softWrap: true)), DataCell(Text(_trials[i].status, softWrap: true)),
                  DataCell(Text(_value(_trials[i].measurement?['providerDurationMs']))),
                  DataCell(Text(_value(_trials[i].measurement?['endpointDurationMs']))),
                  DataCell(Text(_value(_trials[i].measurement?['promptTokens']))),
                  DataCell(Text(_value(_trials[i].measurement?['outputTokens']))),
                ])]),
              );
            }),
            for (var i = 0; i < _trials.length; i++) ExpansionTile(key: ValueKey('comparison-result-$i'),
              title: Text('${i + 1}. ${_trials[i].arm} — ${_trials[i].status}'), children: [
                Text('Model: ${_trials[i].preview['model']}; ayarlar: ${jsonEncode(_trials[i].preview['settings'])}'),
                Text('Ölçüm durumu: ${_value(_trials[i].measurement?['outcome'])}; '
                  'iş kimliği: ${_value(_trials[i].measurement?['requestId'])}'),
                if (_trials[i].error != null) Text(_trials[i].error!),
                if (_trials[i].continuity != null) Text('Metinsel geçiş uyumu: ${_trials[i].continuity!['matchedCount']} / '
                  '${_trials[i].continuity!['totalTransitions']}. Klinik/anlamsal doğrulama değildir.'),
                if (_trials[i].raw != null) ...[
                  _raw(_trials[i].raw!, ValueKey('comparison-raw-$i')),
                  TextButton(onPressed: () => _copy(_trials[i].raw!), child: const Text('Tam ham cevabı kopyala')),
                ],
                if (_trials[i].result != null && widget.onContinue != null)
                  FilledButton(key: ValueKey('comparison-continue-$i'),
                    onPressed: _busy || _openingResult ? null : () => _continue(_trials[i]),
                    child: const Text('Bu senaryoyla devam et')),
                if (_trials[i].result != null) ScenarioNarrativeCards(request: widget.request,
                  input: ScenarioInput.fromJsonString(widget.request.prepareInput(_trials[i].result!.rawResponse,
                    scenarioId: _trials[i].result!.scenarioId, edited: false).json)),
              ]),
            TextButton(key: const ValueKey('comparison-copy-all'), onPressed: () => _copy(jsonEncode({
              'request': widget.request.toJson(), 'results': _trials.map((t) => t.toJson()).toList(),
            })), child: const Text('İstemler ve tüm sonuçları kopyala')),
          ],
          const Text('Çıktılar incelenmemiş taslaktır; yapısal geçerlilik içerik onayı değildir. Sonuçlar oturumluktur.'),
        ]),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(key: const ValueKey('comparison-start'), onPressed: _busy || !_ready ? null : _run,
            child: Text('${_arms.join(' → ')} başlat — en fazla ${_arms.length} çağrı')),
          if (_busy) OutlinedButton(key: const ValueKey('comparison-cancel'), onPressed: _cancel, child: const Text('Yerel izlemeyi durdur')),
          TextButton(key: const ValueKey('comparison-close'), onPressed: _busy ? null : _close, child: const Text('Kapat')),
        ]),
      ]))),
    )));
}
