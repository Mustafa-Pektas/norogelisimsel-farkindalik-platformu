import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/clip_video_store.dart';
import '../services/http_scenario_generation_service.dart';
import '../services/graph_playback_controller.dart';
import 'scenario_graph_screen.dart';
import 'clip_production_plan_screen.dart';
import 'scenario_graph_import_screen.dart';
import 'graph_playback_screen.dart';

class SyntheticVideoStudioScreen extends StatefulWidget {
  /// Kontrollü oynatma testleri; verilmezse mevcut yerel eşleme/oynatıcı kullanılır.
  final ClipVideoStore? playbackVideoStore;
  final GraphClipPlayer Function(File)? createPlaybackPlayer;

  const SyntheticVideoStudioScreen({
    super.key,
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
                      title: const Text('Senaryo ve graf hazırlama'),
                      subtitle: const Text(
                        'Sunucudan taslak isteyin; yanıtı inceleyip grafa dönüştürün.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ScenarioGraphImportScreen(
                            initialScenarioContent: true,
                            generationService: HttpScenarioGenerationService(),
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
                      title: const Text('D01 klipleri ve video eşleme'),
                      subtitle: const Text(
                        'Hazır örneğin promptlarını inceleyin, videoları bağlayın ve akışı deneyin.',
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
              ),
          ],
        ),
      ),
    );
  }

}
