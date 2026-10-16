import 'package:flutter/material.dart';

import '../services/local_llama_test_service.dart';

class LocalLlamaTestCard extends StatelessWidget {
  const LocalLlamaTestCard({
    super.key,
    required this.service,
    this.enabled = true,
  });
  final LocalLlamaTestService service;
  final bool enabled;

  @override
  Widget build(BuildContext context) => StreamBuilder<LocalLlamaTestState>(
    stream: service.states,
    initialData: service.state,
    builder: (context, snapshot) {
      final state = snapshot.data!;
      final request = service.request;
      final label = switch (state.phase) {
        LocalLlamaPhase.idle => 'Henüz üretim denenmedi',
        LocalLlamaPhase.loading => 'Model yükleniyor',
        LocalLlamaPhase.generating => 'Metin üretiliyor',
        LocalLlamaPhase.cancelling => 'İptal bekleniyor',
        LocalLlamaPhase.closing => 'Kaynaklar kapatılıyor',
        LocalLlamaPhase.completed => 'Tamamlandı',
        LocalLlamaPhase.cancelled => 'İptal edildi',
        LocalLlamaPhase.error => 'Hata',
      };
      return Card(
        key: ValueKey('${request.id}-card'),
        color: Colors.white,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                request.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF142540),
                ),
              ),
              const SizedBox(height: 8),
              Text(request.description),
              const SizedBox(height: 8),
              Text('Model: ${request.model.name}'),
              SelectableText(request.model.id),
              Text(request.samplingDescription),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Modele gönderilen istek'),
                children: [SelectableText(request.prompt)],
              ),
              Text(
                'CPU · ${request.contextSize} token bağlam · En fazla ${request.maxTokens} yeni token',
              ),
              const SizedBox(height: 8),
              Text(label, key: ValueKey('${request.id}-status')),
              if (state.isBusy) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
              if (state.phase == LocalLlamaPhase.cancelling)
                const Text(
                  'Yükleme veya native işlem güvenle sonlanınca kaynaklar kapatılacak.',
                ),
              if (state.error != null)
                SelectableText(
                  state.error!,
                  key: ValueKey('${request.id}-error'),
                ),
              if (state.text.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  state.phase == LocalLlamaPhase.completed
                      ? 'Model cevabı'
                      : 'Kısmi model çıktısı',
                ),
                SelectableText(
                  state.text,
                  key: ValueKey('${request.id}-response'),
                ),
              ],
              if (state.phase != LocalLlamaPhase.idle)
                Text(
                  'Toplam: ${(state.elapsed.inMilliseconds / 1000).toStringAsFixed(2)} sn '
                  '· Üretim: ${(state.generationElapsed.inMilliseconds / 1000).toStringAsFixed(2)} sn',
                ),
              if (state.diagnostics['API bitiş nedeni']
                  case final String reason)
                Text('API bitiş nedeni: $reason'),
              if (state.diagnostics.isNotEmpty)
                ExpansionTile(
                  key: ValueKey('${request.id}-diagnostics'),
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Çıkarım ayrıntıları'),
                  children: [
                    for (final entry in state.diagnostics.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SelectableText(entry.value),
                          ],
                        ),
                      ),
                  ],
                ),
              if (state.diagnostics['API bitiş nedeni'] == 'length')
                const Text(
                  'Motor token veya bağlam sınırında durdu; cevap tamamlanmamış olabilir.',
                ),
              if (!enabled)
                const Text('Test için model indirmesinin bitmesini bekleyin.'),
              if (enabled && !state.isBusy && !service.canRun)
                const Text(
                  'Diğer model testinin bitmesini bekleyin. Kaynak kapatma hatası varsa uygulamayı yeniden başlatın.',
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: ValueKey('${request.id}-start'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF142540),
                    ),
                    onPressed: !enabled || state.isBusy || !service.canRun
                        ? null
                        : () async {
                            try {
                              await service.run();
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('$error')),
                                );
                              }
                            }
                          },
                    icon: const Icon(Icons.play_arrow),
                    label: Text(request.actionLabel),
                  ),
                  if (state.isBusy)
                    OutlinedButton(
                      key: ValueKey('${request.id}-cancel'),
                      onPressed:
                          state.phase == LocalLlamaPhase.cancelling ||
                              state.phase == LocalLlamaPhase.closing
                          ? null
                          : service.cancel,
                      child: const Text('İptal'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
