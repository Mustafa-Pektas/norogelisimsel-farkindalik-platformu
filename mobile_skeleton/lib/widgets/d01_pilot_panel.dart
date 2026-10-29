import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/d01_pilot_result.dart';
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
    this.api = const HttpD01PilotApi(),
    this.initialAccessKey = '',
    this.pollInterval = const Duration(seconds: 5),
    this.trackingLimit = const Duration(minutes: 20),
  });
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
  Timer? _timer;
  final _elapsed = Stopwatch();
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
      _status = null;
      _result = null;
      _message = null;
      _stage = 'idle';
    }
  }

  void _stop() {
    ++_generation;
    _timer?.cancel();
    _timer = null;
    _task?.close();
    _task = null;
    _polling = false;
    _cancelling = false;
    _cancelAccepted = false;
    _elapsed.stop();
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
    D01PilotTask task;
    try {
      task = widget.api.create(
        video: widget.video!,
        address: _address.text,
        accessKey: _key.text,
      );
    } catch (e) {
      setState(() => _message = _error(e));
      return;
    }
    final generation = ++_generation;
    _task = task;
    _elapsed.reset();
    _elapsed.start();
    setState(() {
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
          _stage = 'completed';
          _message = null;
        });
        task.close();
        _task = null;
      } else if (status.terminal) {
        setState(() {
          _status = status;
          _stage = status.status == 'interrupted' ? 'cancelled' : 'error';
          _message = status.code == 'cancelled_locally'
              ? null
              : D01PilotException(status.code ?? status.status).message;
        });
        task.close();
        _task = null;
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
          _message = _error(e);
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

  Widget _candidate(D01MotionCandidate c, String method) => ListTile(
    key: ValueKey('pilot-$method-${c.id}'),
    contentPadding: EdgeInsets.zero,
    title: Text('Aday aralığı: ${_time(c.start)} – ${_time(c.end)}'),
    subtitle: Text(
      'Başlangıç doğrulaması: ${_time(c.startConfirmed)}\n'
      'Bitiş doğrulaması: ${_time(c.endConfirmed)}',
    ),
    enabled: !widget.openingVideo && c.canSeek(widget.duration),
    onTap: !widget.openingVideo && c.canSeek(widget.duration)
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
        const Text(
          'Yalnız iki denetlenmiş D01 videosu desteklenir. Baş hareketi adaylarını gösterir; '
          'isme tepkiyi veya doğru kişiye yönelmeyi belirlemez. Analiz birkaç dakika sürebilir.',
        ),
        const Text(
          'Çağrı zamanı gönderilmez. Manuel zamanlar bilinmiyor; yerleşme, hareket bitişi değildir.',
        ),
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
          'error' => 'İşlem veya bağlantı hatası.',
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
              onPressed: ready && !active ? _start : null,
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
          const SizedBox(height: 12),
          Text(
            'İşlenen: ${result.processed} · Geçerli: ${result.valid} · Geçersiz: ${result.invalid}',
          ),
          SelectableText(
            'Sunucunun doğruladığı video SHA256: ${result.videoHash}',
          ),
          const Text(
            'Adaya dokunmak videoda başlangıca gider; oynatmayı başlatmaz. '
            'Eksik/geçersiz aralıklar ve video açılırken kısayollar devre dışıdır.',
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
