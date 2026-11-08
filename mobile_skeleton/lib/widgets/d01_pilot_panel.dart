import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/d01_pilot_result.dart';
import '../models/d01_marked_input.dart';
import '../services/d01_pilot_service.dart';

/// Tracking belongs to this mounted panel. Closing it never cancels the server job.
class D01PilotPanel extends StatefulWidget {
  const D01PilotPanel({
    super.key,
    required this.video,
    required this.videoIdentity,
    required this.duration,
    required this.openingVideo,
    required this.onSeek,
    this.fastAnalysis = false,
    this.targetPoint,
    this.userMarked = false,
    this.roi,
    this.currentPosition,
    this.onUserMarkedChanged,
    this.onBusyChanged,
    this.api = const HttpD01PilotApi(),
    this.initialAccessKey = '',
    this.pollInterval = const Duration(seconds: 5),
    this.trackingLimit = const Duration(minutes: 20),
  });
  final ValueChanged<bool>? onBusyChanged;
  final bool userMarked;
  final bool fastAnalysis;
  final List<double>? targetPoint;
  final D01Roi? roi;
  final Duration Function()? currentPosition;
  final ValueChanged<bool>? onUserMarkedChanged;
  final File? video;
  final Object? videoIdentity;
  final Duration duration;
  final bool openingVideo;
  final Future<void> Function(Duration) onSeek;
  final D01PilotApi api;
  final String initialAccessKey;
  final Duration pollInterval, trackingLimit;
  @override
  State<D01PilotPanel> createState() => _D01PilotPanelState();
}

class _D01PilotPanelState extends State<D01PilotPanel> {
  late final TextEditingController _key;
  final _address = TextEditingController(text: HttpD01PilotApi.defaultAddress);
  D01PilotTask? _task;
  D01PilotResult? _result;
  D01PilotStatus? _status;
  String? _message;
  String _stage = 'idle';
  Duration? _callStart, _callEnd;
  Timer? _timer;
  final _elapsed = Stopwatch();
  final _visibleClock = Stopwatch();
  final _resultAnchor = GlobalKey();
  int _generation = 0;
  int _cancelRevision = 0;
  bool _polling = false, _cancelling = false, _cancelAccepted = false;

  @override
  void initState() {
    super.initState();
    _key = TextEditingController(text: widget.initialAccessKey);
  }

  @override
  void didUpdateWidget(covariant D01PilotPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.videoIdentity, widget.videoIdentity) ||
        oldWidget.video?.path != widget.video?.path) {
      _stop();
      _callStart = null;
      _callEnd = null;
      _status = null;
      _result = null;
      _message = null;
      _stage = 'idle';
    }
  }

  double? _visibleElapsed;
  D01FastInput get _fastInput => D01FastInput(
    targetPoint: widget.userMarked && widget.targetPoint != null ? List<double>.unmodifiable(widget.targetPoint!) : null,
    callStart: _callStart,
    callEnd: _callEnd,
  );
  bool get _inputValid => widget.fastAnalysis
      ? _fastInput.validFor(widget.duration) &&
            (!widget.userMarked || widget.targetPoint != null)
      : !widget.userMarked || (_marked?.validFor(widget.duration) ?? false);
  D01MarkedInput? get _marked =>
      widget.roi == null || _callStart == null || _callEnd == null
      ? null
      : D01MarkedInput(widget.roi!, _callStart!, _callEnd!);

  void _stop() {
    ++_generation;
    _timer?.cancel();
    _timer = null;
    _task?.close();
    _task = null;
    widget.onBusyChanged?.call(false);
    _polling = false;
    _cancelling = false;
    _cancelAccepted = false;
    _elapsed.stop();
    _visibleClock.stop();
  }

  bool _current(int generation, D01PilotTask task) =>
      mounted && generation == _generation && identical(task, _task);
  void _schedule() {
    _timer?.cancel();
    if (_task != null && !_polling && !_cancelling && _stage != 'error') {
      _timer = Timer(widget.pollInterval, _poll);
    }
  }

  Future<void> _start() async {
    if (_task != null ||
        widget.video == null ||
        widget.videoIdentity == null ||
        widget.openingVideo) {
      return;
    }
    if (!_inputValid) {
      setState(
        () => _message = widget.fastAnalysis ? 'Hedef yüzü ve isteğe bağlı çağrı işaretlerinin sırasını kontrol edin.' : 'Baş bölgesini ve video içinde sıralı çağrı zamanlarını işaretleyin.',
      );
      return;
    }
    D01PilotTask task;
    try {
      task = widget.api.create(
        video: widget.video!,
        address: _address.text,
        accessKey: _key.text,
        markedInput: !widget.fastAnalysis && widget.userMarked ? _marked : null,
        fastInput: widget.fastAnalysis ? _fastInput : null,
      );
    } catch (e) {
      setState(() => _message = _error(e));
      return;
    }
    final generation = ++_generation;
    _task = task;
    widget.onBusyChanged?.call(true);
    _elapsed.reset();
    _elapsed.start();
    _visibleClock..reset()..start();
    setState(() {
      _visibleElapsed = null;
      _stage = 'uploading';
      _status = null;
      _result = null;
      _message = null;
      _cancelAccepted = false;
      _cancelling = false;
    });
    try {
      final status = await task.submit();
      if (!_current(generation, task)) {
        return;
      }
      setState(() {
        _status = status;
        _stage = 'running';
      });
      await _poll();
    } catch (e) {
      if (!_current(generation, task)) {
        return;
      }
      setState(() {
        _stage = 'error';
        _message = _error(e);
      });
      if (task.jobId == null) {
        task.close();
        _task = null;
        widget.onBusyChanged?.call(false);
      }
    }
  }

  Future<void> _poll() async {
    final task = _task;
    if (task == null || _polling || _cancelling || task.jobId == null) {
      return;
    }
    _timer?.cancel();
    final generation = _generation;
    final cancelRevision = _cancelRevision;
    _polling = true;
    try {
      if (_elapsed.elapsed >= widget.trackingLimit) {
        throw const D01PilotException('tracking_timeout');
      }
      final status = await task.status();
      if (!_current(generation, task) ||
          cancelRevision != _cancelRevision ||
          _cancelling) {
        return;
      }
      if (status.status == 'completed') {
        if (_cancelAccepted) {
          throw const D01PilotException('invalid_contract');
        }
        final result = await task.result();
        if (!_current(generation, task) ||
            cancelRevision != _cancelRevision ||
            _cancelling) {
          return;
        }
        setState(() {
          _status = status;
          _result = result;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted || generation != _generation || !identical(_result, result)) { return; }
            final anchorContext = _resultAnchor.currentContext;
            if (anchorContext == null || !anchorContext.mounted) { return; }
            try {
              await Scrollable.ensureVisible(anchorContext, duration: const Duration(milliseconds: 250));
            } catch (_) { return; }
            if (mounted &&
                generation == _generation &&
                identical(_result, result)) {
              _visibleClock.stop();
              setState(
                () => _visibleElapsed = _visibleClock.elapsedMicroseconds / 1e6,
              );
            }
          });
          _stage = 'completed';
          _message = null;
        });
        task.close();
        _task = null;
        widget.onBusyChanged?.call(false);
      } else if (status.terminal) {
        setState(() {
          _status = status;
          _stage = status.code == 'analysis_timeout'
              ? 'timeout'
              : status.status == 'interrupted'
              ? 'cancelled'
              : 'failed';
          _message = status.code == 'cancelled_locally'
              ? null
              : D01PilotException(status.code ?? status.status).message;
        });
        task.close();
        _task = null;
        widget.onBusyChanged?.call(false);
      } else {
        setState(() {
          _status = status;
          _stage = 'running';
        });
      }
    } catch (e) {
      if (_current(generation, task) &&
          cancelRevision == _cancelRevision &&
          !_cancelling) {
        setState(() {
          _stage = 'error';
          _message = '${_error(e)} Sunucudaki işin durduğu doğrulanmadı.';
        });
      }
    } finally {
      if (_current(generation, task)) {
        _polling = false;
        _schedule();
      } else if (generation == _generation) {
        _polling = false;
      }
    }
  }

  Future<void> _cancel() async {
    final task = _task;
    if (task == null || task.jobId == null || _cancelling || _cancelAccepted) {
      return;
    }
    final generation = _generation;
    ++_cancelRevision;
    _timer?.cancel();
    setState(() {
      _cancelling = true;
      _message = null;
    });
    try {
      await task.cancel();
      if (!_current(generation, task)) {
        return;
      }
      setState(() {
        _cancelAccepted = true;
        _stage = 'running';
      });
    } catch (e) {
      if (_current(generation, task)) {
        setState(() {
          _message = 'İptal doğrulanamadı. ${_error(e)}';
        });
      }
    } finally {
      if (_current(generation, task)) {
        setState(() => _cancelling = false);
        _schedule();
      }
    }
  }

  String _error(Object e) => e is D01PilotException
      ? e.message
      : const D01PilotException('connection_error').message;
  String _time(double? t) =>
      t == null ? 'bilinmiyor' : '${t.toStringAsFixed(3)} sn';

  bool _canSeek(D01MotionCandidate c) => !widget.openingVideo &&
    (_result?.fast == true ? c.start != null && c.start! >= 0 && c.start! < widget.duration.inMicroseconds / 1e6 &&
      (c.end == null || c.end! >= c.start! && c.end! <= widget.duration.inMicroseconds / 1e6) : c.canSeek(widget.duration));
  Widget _candidate(D01MotionCandidate c, String method) => ListTile(
    key: ValueKey('pilot-$method-${c.id}'),
    contentPadding: EdgeInsets.zero,
    title: Text('Başlangıç adayı: ${_time(c.start)}'),
    subtitle: Text(
      '${c.end == null ? 'Bitiş belirlenemedi' : 'Düşük hız ölçütüne göre bitiş adayı: ${_time(c.end)}'}\n'
      'Başlangıç doğrulaması: ${_time(c.startConfirmed)}\n'
      'Bitiş doğrulaması: ${_time(c.endConfirmed)}\n'
      'Çağrı başlangıcına göre: ${_time(c.callStartDifference)}\n'
      'Çağrı bitişine göre: ${_time(c.callEndDifference)}'
      '${c.callPhase == null ? "" : "\n${switch (c.callPhase) {
              'before_call' => 'Çağrıdan önce başlayan hareket; yeni tepki sayılmaz.',
              'during_call' => 'Çağrı sırasında başlayan aday.',
              'after_call' => 'Çağrıdan sonra başlayan aday; nedensellik belirlenmedi.',
              'unknown_movement_start' => 'Hareket başlangıcı bilinmiyor.',
              _ => 'Çağrı zamanı bilinmiyor.',
            }}"}',
    ),
    enabled: _canSeek(c),
    onTap: _canSeek(c)
        ? () => widget.onSeek(Duration(microseconds: (c.start! * 1e6).round()))
        : null,
  );

  @override
  Widget build(BuildContext context) {
    final active = _task != null;
    final ready =
        widget.video != null &&
        widget.videoIdentity != null &&
        !widget.openingVideo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Deneysel D01 baş hareketi analizi',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          widget.fastAnalysis
              ? 'Hızlı yüz takibi ve baş hareketi adayları. Birden fazla yüz varsa ilk karede çocuğun yüzüne dokunarak hedefi belirtin; dikdörtgen çizmeniz gerekmez. Belirsiz hedef ve takip kaybında poz ölçülmez. Bu, isme tepki veya doğru kişiye yönelme analizi değildir.'
              : 'İki hazır video otomatik ROI kullanır. Yeni videoda baş bölgesini ve çağrı zamanlarını işaretleyin. Baş hareketi adaylarını gösterir; isme tepkiyi veya doğru kişiye yönelmeyi belirlemez. Analiz birkaç dakika sürebilir.',
        ),
        const Text(
          'İşaretler kullanıcı adayıdır; yerleşme, hareket bitişi değildir. Yeni video: 24 FPS, en çok 30 sn / 25 MiB.',
        ),
        if (widget.onUserMarkedChanged != null)
          SwitchListTile(
            key: const ValueKey('pilot-user-marked'),
            title: Text(
              widget.fastAnalysis
                  ? 'Hedef yüzü belirt'
                  : 'Yeni video için işaretleme',
            ),
            subtitle: Text(
              widget.fastAnalysis
                  ? 'Videoyu başa alın; önizlemenin ilk karesindeki çocuğun yüzüne dokunun. Tek yüz bulunması çocuk kimliğini doğrulamaz.'
                  : 'Önizlemeye dönüp çocuğun başını çevreleyen bir dikdörtgen çizin.',
            ),
            value: widget.userMarked,
            onChanged: active
                ? null
                : (value) {
                    setState(() {
                      _callStart = null;
                      _callEnd = null;
                    });
                    widget.onUserMarkedChanged!(value);
                  },
          ),
        if (widget.userMarked) ...[
          Text(
            widget.fastAnalysis
                ? (widget.targetPoint == null
                      ? 'Hedef yüz henüz belirtilmedi.'
                      : 'Başlangıç yüz noktası seçildi; kimlik devamlılığı kesin doğrulanmış değildir.')
                : widget.roi == null
                ? 'Baş bölgesi henüz seçilmedi.'
                : 'Baş bölgesi: ${widget.roi!.toJson()}',
          ),
        ],
        if (widget.userMarked || widget.fastAnalysis) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const ValueKey('pilot-mark-call-start'),
                onPressed: !ready || active
                    ? null
                    : () => setState(
                        () => _callStart = widget.currentPosition?.call(),
                      ),
                child: const Text('Bu konumu çağrı başlangıcı yap'),
              ),
              OutlinedButton(
                key: const ValueKey('pilot-mark-call-end'),
                onPressed: !ready || active
                    ? null
                    : () => setState(
                        () => _callEnd = widget.currentPosition?.call(),
                      ),
                child: const Text('Bu konumu çağrı bitişi yap'),
              ),
            ],
          ),
          Text(
            'Çağrı: ${_callStart == null ? "bilinmiyor" : _time(_callStart!.inMilliseconds / 1000)} – ${_callEnd == null ? "bilinmiyor" : _time(_callEnd!.inMilliseconds / 1000)}',
            key: const ValueKey('pilot-call-marks'),
          ),
          if (widget.fastAnalysis)
            const Text(
              'Çağrı işaretleri isteğe bağlıdır. İkisini de işaretleyin veya ikisini de boş bırakın. Bilinmiyorsa yalnız baş hareketi raporlanır.',
            ),
          TextButton(
            key: const ValueKey('pilot-clear-call'),
            onPressed: active
                ? null
                : () => setState(() {
                    _callStart = null;
                    _callEnd = null;
                  }),
            child: const Text('Çağrı işaretlerini temizle'),
          ),
          if (!_inputValid)
            const Text(
              'Hedef ve çağrı işaretlerini kontrol edin; çağrı başlangıcı/bitişi birlikte ve video içinde olmalı.',
            ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('pilot-address'),
          controller: _address,
          enabled: !active,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Pilot sunucusu',
            hintText: 'http://10.0.2.2:8000',
            helperText: 'Yalnız bu oturumda kullanılır; senaryo sunucusu ayarını değiştirmez.',
            helperMaxLines: 4,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('pilot-key'),
          controller: _key,
          enabled: !active,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Ekip anahtarı'),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('pilot-clear-key'),
            onPressed: active ? null : () => setState(_key.clear),
            child: const Text('Anahtarı temizle'),
          ),
        ),
        Text(switch (_stage) {
          'uploading' => 'Video yükleniyor; kabul yanıtı bekleniyor.',
          'running' =>
            _cancelAccepted || _status?.interruptRequested == true
                ? 'İptal istendi; sunucudaki işin kapanışı bekleniyor.'
                : 'Pilot analiz işleniyor.',
          'completed' =>
            'Pilot tamamlandı; bu bir davranış doğruluğu onayı değildir.',
          'cancelled' => 'Pilot işi kesildi.',
          'timeout' => 'Sunucu süre sınırına ulaştı; analiz tamamlanmadı.',
          'failed' => 'Sunucu pilot analizi tamamlayamadı.',
          'error' =>
            active && _task?.jobId != null
                ? 'İş takibi kesildi; sunucudaki iş devam ediyor olabilir.'
                : 'Pilot isteği başlatılamadı.',
          _ =>
            ready
                ? 'Video hazır. Analizi açıkça başlatabilirsiniz.'
                : 'Önce video seçip açın.',
        }, key: const ValueKey('pilot-stage')),
        if (_status != null) SelectableText('İş kimliği: ${_status!.jobId}'),
        if (_stage == 'running')
          Text(
            _status?.processedFrames == null
                ? 'Sunucu kare ilerlemesi bildirmiyor.'
                : 'İşlenen kare: ${_status!.processedFrames}'
                      '${_status!.totalFrames == null ? '' : ' / ${_status!.totalFrames}'}',
          ),
        if (_message != null)
          Text(_message!, key: const ValueKey('pilot-message')),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: const ValueKey('pilot-start'),
              onPressed: ready && !active && _inputValid ? _start : null,
              child: const Text('Pilot analizi başlat'),
            ),
            if (active && _stage == 'error' && _task?.jobId != null)
              OutlinedButton(
                key: const ValueKey('pilot-resume'),
                onPressed: _polling || _cancelling
                    ? null
                    : () {
                        _elapsed.reset();
                        setState(() {
                          _stage = 'running';
                          _message = null;
                        });
                        _poll();
                      },
                child: const Text('Aynı işi yeniden takip et'),
              ),
            if (active && _task?.jobId != null)
              OutlinedButton(
                key: const ValueKey('pilot-cancel'),
                onPressed: _cancelling || _cancelAccepted ? null : _cancel,
                child: const Text('Sunucudaki işi iptal et'),
              ),
          ],
        ),
        const Text(
          'Ekrandan çıkmak veya video değiştirmek yalnız istemci takibini durdurur; '
          'sunucudaki işi iptal etmez. Bağlantı kesilirse yeni iş otomatik başlatılmaz.',
        ),
        if (_result case final result?) ...[
          SizedBox(key: _resultAnchor, height: 12),
          if (_visibleElapsed != null)
            Text(
              'Başlatmadan görünür sonuca: ${_visibleElapsed!.toStringAsFixed(3)} sn',
              key: const ValueKey('pilot-visible-elapsed'),
            ),
          if (result.fast) ...[
            const Text(
              'MediaPipe/PnP · Optik akış yalnız takip içindir; akış karelerinde mutlak açı ölçülmez.',
            ),
            Text(
              'Poz: ${result.coverage['poseFrames']} / ${result.coverage['totalFrames']} · Yalnız akış: ${result.coverage['flowOnlyFrames']} · Kayıp: ${result.coverage['lostFrames']} · Belirsiz: ${result.coverage['ambiguousFrames']}',
              key: const ValueKey('pilot-coverage'),
            ),
            Text(
              result.targetSelection == 'not_determined'
                  ? 'Hedef güvenilir seçilemedi. İlk karede yüzü belirtip ayrı bir analiz başlatabilirsiniz; mevcut sonuç poz kanıtı değildir.'
                  : 'Takip edilen yüz insan tarafından çocuk olarak ayrıca kontrol edilmelidir; biyometrik kimlik doğrulanmadı.',
            ),
            for (final gap in result.missingPoseIntervals)
              Text(
                'Poz ölçülemeyen aralık: ${_time((gap['startS'] as num).toDouble())} – ${_time((gap['endS'] as num).toDouble())}',
              ),
            Text(
              result.callStart == null
                  ? 'Çağrı zamanı bilinmiyor; çağrıya göre değerlendirme yapılamaz.'
                  : 'Kullanıcı çağrı işareti: ${_time(result.callStart)} – ${_time(result.callEnd)}',
            ),
            ExpansionTile(
              title: const Text('Ölçüm süreleri'),
              children: [
                TextButton(key: const ValueKey('pilot-copy-measurement'), onPressed: _visibleElapsed == null ? null : () async {
                  final generation = _generation;
                  try {
                    await Clipboard.setData(ClipboardData(text: jsonEncode({
                      'schemaVersion': 'd01-mobile-observation-1.0', 'jobId': result.jobId,
                      'videoHash': result.videoHash, 'method': 'mediapipe_pnp_flow',
                      'startToVisibleSeconds': _visibleElapsed, 'serverTimings': result.timings,
                      'coverage': result.coverage, 'clinicalClassification': null,
                    })));
                  } catch (_) {
                    if (mounted && generation == _generation) { setState(() => _message = 'Ölçüm özeti kopyalanamadı.'); }
                  }
                }, child: const Text('Ölçüm özetini kopyala')),
                for (final e in result.timings.entries)
                  ListTile(
                    title: Text(e.key),
                    subtitle: Text(
                      e.value == null
                          ? 'Bilinmiyor'
                          : '${e.value!.toStringAsFixed(3)} sn',
                    ),
                  ),
              ],
            ),
          ],
          if (result.userMarked)
            Text(
              'Analiz edilen baş bölgesi: ${result.sourceRoi!.toJson()}\nSonuçtaki çağrı (kullanıcı işareti): ${_time(result.callStart)} – ${_time(result.callEnd)}',
            ),
          Text(
            'İşlenen: ${result.processed} · Geçerli: ${result.valid} · Geçersiz: ${result.invalid}',
          ),
          SelectableText(
            'Sunucunun doğruladığı video SHA256: ${result.videoHash}',
          ),
          const Text(
            'Adaya dokunmak videoda başlangıca gider; oynatmayı başlatmaz. '
            'Başlangıcı bilinmeyen veya süre dışındaki adaylar ve video açılırken kısayollar devre dışıdır. Bilinmeyen bitiş tamamlanmış hareket sayılmaz.',
          ),
          const Text(
            'Düşük hız ölçütüne göre bitiş adayı, ana dönüşün görsel olarak tamamlandığı anı göstermeyebilir.',
          ),
          const Text(
            'Ham matrislerden adaylar',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (result.raw.isEmpty)
            const Text('Aday bulunmadı; bu “tepki yok” anlamına gelmez.'),
          for (final c in result.raw) _candidate(c, 'raw'),
          const Text(
            'EMA α=0.50 adayları',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (result.ema.isEmpty)
            const Text('Aday bulunmadı; bu “tepki yok” anlamına gelmez.'),
          for (final c in result.ema) _candidate(c, 'ema'),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _stop();
    _address.dispose();
    _key.dispose();
    super.dispose();
  }
}
