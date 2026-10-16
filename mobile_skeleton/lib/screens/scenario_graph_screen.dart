import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/scenario_graph.dart';

class ScenarioGraphScreen extends StatefulWidget {
  const ScenarioGraphScreen({super.key, this.assetPath = d01AssetPath});

  static const d01AssetPath = 'assets/scenarios/d01_scenario_graph.json';
  final String assetPath;

  @override
  State<ScenarioGraphScreen> createState() => _ScenarioGraphScreenState();
}

class _ScenarioGraphScreenState extends State<ScenarioGraphScreen> {
  AssetBundle? _bundle;
  late Future<ScenarioGraph> _loading;

  Future<ScenarioGraph> _load() async => ScenarioGraph.fromJsonString(
    await _bundle!.loadString(widget.assetPath, cache: false),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bundle = DefaultAssetBundle.of(context);
    if (_bundle != bundle) {
      _bundle = bundle;
      _loading = _load();
    }
  }

  @override
  void didUpdateWidget(covariant ScenarioGraphScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) _loading = _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      title: const Text('Senaryo Grafı'),
      backgroundColor: const Color(0xFF142540),
      foregroundColor: Colors.white,
    ),
    body: SafeArea(
      child: FutureBuilder<ScenarioGraph>(
        future: _loading,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 36),
                    const SizedBox(height: 12),
                    const Text('Senaryo grafı açılamadı.'),
                    const SizedBox(height: 8),
                    Text(
                      error is FormatException
                          ? 'Örnek senaryo doğrulanamadı: ${error.message}'
                          : 'Örnek dosyası okunamadı. Uygulamayı yeniden '
                                'başlatıp tekrar deneyebilirsiniz.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () {
                        final loading = _load();
                        setState(() {
                          _loading = loading;
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tekrar dene'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Senaryo grafı yükleniyor',
              ),
            );
          }
          return _GraphView(graph: snapshot.data!);
        },
      ),
    ),
  );
}

const _navy = Color(0xFF142540);
const _background = Color(0xFFF3F5F8);
const _bodyStyle = TextStyle(
  inherit: false,
  fontFamily: 'Roboto',
  letterSpacing: 0,
  fontSize: 13,
  height: 1.3,
  color: _navy,
);
const _headingStyle = TextStyle(
  inherit: false,
  fontFamily: 'Roboto',
  letterSpacing: 0,
  fontSize: 15,
  height: 1.2,
  color: _navy,
  fontWeight: FontWeight.bold,
);
const _edgeStyle = TextStyle(
  inherit: false,
  fontFamily: 'Roboto',
  letterSpacing: 0,
  fontSize: 12,
  height: 1.25,
  color: _navy,
);

String _title(ScenarioGraph graph, ScenarioScene scene) =>
    scene.title?.trim().isNotEmpty == true
    ? scene.title!
    : 'Sahne ${graph.scenes.indexOf(scene) + 1}';
String _summary(ScenarioScene scene) => scene.summary?.trim().isNotEmpty == true
    ? scene.summary!
    : scene.description;
String _label(ScenarioGraph graph, ScenarioTransition edge) =>
    edge.label?.trim().isNotEmpty == true
    ? edge.label!
    : _title(graph, graph.scenes.firstWhere((s) => s.id == edge.toSceneId));
String _role(ScenarioGraph graph, String id) => [
  if (id == graph.startSceneId) 'Başlangıç',
  if (graph.endSceneIds.contains(id)) 'Bitiş',
].join(' · ');

void _showScene(
  BuildContext context,
  ScenarioGraph graph,
  ScenarioScene scene,
) {
  final outgoing = graph.transitions.where((e) => e.fromSceneId == scene.id);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .65,
      minChildSize: .35,
      maxChildSize: .95,
      builder: (context, controller) => Column(
        key: const ValueKey('scene-details'),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 8, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _title(graph, scene),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Ayrıntıları kapat',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              key: const ValueKey('scene-details-scroll'),
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                if (_role(graph, scene.id).isNotEmpty)
                  Text(
                    _role(graph, scene.id),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _navy,
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  scene.description,
                  key: const ValueKey('scene-full-description'),
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    color: _navy,
                  ),
                ),
                const Divider(height: 32),
                const Text(
                  'Devam bağlantıları',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 8),
                if (outgoing.isEmpty)
                  const Text('Bu bir bitiş sahnesidir. Devam bağlantısı yok.'),
                for (final edge in outgoing)
                  Padding(
                    key: ValueKey(
                      'detail-transition:${graph.transitions.indexOf(edge)}',
                    ),
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.arrow_forward,
                              size: 20,
                              color: _navy,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _title(
                                  graph,
                                  graph.scenes.firstWhere(
                                    (s) => s.id == edge.toSceneId,
                                  ),
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _navy,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          edge.description,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.5,
                            color: _navy,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _GraphView extends StatefulWidget {
  const _GraphView({required this.graph});
  final ScenarioGraph graph;
  @override
  State<_GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends State<_GraphView> {
  final _transform = TransformationController();
  Size? _lastCanvas;
  Size? _lastViewport;
  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _fit(Size canvas, Size viewport) {
    final scale =
        (math.min(
                  viewport.width / canvas.width,
                  viewport.height / canvas.height,
                ) *
                .94)
            .clamp(.1, 1.0);
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
        (viewport.width - canvas.width * scale) / 2,
        (viewport.height - canvas.height * scale) / 2,
        0,
      );
  }

  void _zoom(double factor) {
    final viewport = _lastViewport;
    if (viewport == null) return;
    final center = viewport.center(Offset.zero);
    final point = _transform.toScene(center);
    final scale = (_transform.value.getMaxScaleOnAxis() * factor).clamp(
      .1,
      3.0,
    );
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
        center.dx - point.dx * scale,
        center.dy - point.dy * scale,
        0,
      );
  }

  @override
  Widget build(BuildContext context) {
    final graph = widget.graph;
    final layout = _GraphLayout(graph, MediaQuery.textScalerOf(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Elle hazırlanmış örnek',
                style: _bodyStyle.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),
              Text(
                '${graph.behaviorId} · Planlanan senaryo; gözlem değildir.',
                style: _edgeStyle,
              ),
            ],
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Uzaklaştır',
              onPressed: () => _zoom(1 / 1.25),
              icon: const Icon(Icons.remove, color: _navy),
            ),
            IconButton(
              tooltip: 'Yakınlaştır',
              onPressed: () => _zoom(1.25),
              icon: const Icon(Icons.add, color: _navy),
            ),
            TextButton.icon(
              key: const ValueKey('show-all'),
              onPressed: () {
                if (_lastViewport != null) _fit(layout.size, _lastViewport!);
              },
              icon: const Icon(Icons.fit_screen),
              label: const Text('Tümünü göster'),
              style: TextButton.styleFrom(foregroundColor: _navy),
            ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewport = constraints.biggest;
              if (_lastCanvas != layout.size || _lastViewport != viewport) {
                _lastCanvas = layout.size;
                _lastViewport = viewport;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _fit(layout.size, viewport);
                });
              }
              return ColoredBox(
                color: _background,
                child: InteractiveViewer(
                  key: const ValueKey('scenario-graph-viewer'),
                  transformationController: _transform,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(160),
                  minScale: .1,
                  maxScale: 3,
                  child: SizedBox(
                    width: layout.size.width,
                    height: layout.size.height,
                    child: CustomPaint(
                      painter: _ConnectionsPainter(layout),
                      child: Stack(
                        children: [
                          for (final scene in graph.scenes)
                            Positioned.fromRect(
                              rect: layout.nodes[scene.id]!,
                              child: Semantics(
                                button: true,
                                label:
                                    '${_title(graph, scene)}, ayrıntıları aç',
                                child: Material(
                                  key: ValueKey('scene:${scene.id}'),
                                  color: Colors.white,
                                  elevation: 1,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: const BorderSide(
                                      color: Color(0xFFBAC4D0),
                                    ),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () =>
                                        _showScene(context, graph, scene),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _title(graph, scene),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: _headingStyle,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _summary(scene),
                                            key: ValueKey(
                                              'summary:${scene.id}',
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: _bodyStyle,
                                          ),
                                          if (_role(
                                            graph,
                                            scene.id,
                                          ).isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Icon(
                                                  scene.id == graph.startSceneId
                                                      ? Icons
                                                            .play_circle_outline
                                                      : Icons.outlined_flag,
                                                  size: 18,
                                                  color: _navy,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    _role(graph, scene.id),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: _edgeStyle,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          for (var i = 0; i < layout.edges.length; i++)
                            Positioned.fromRect(
                              rect: layout.edges[i].label,
                              child: DecoratedBox(
                                key: ValueKey('transition:$i'),
                                decoration: BoxDecoration(
                                  color: _background,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Text(
                                    _label(graph, graph.transitions[i]),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: _edgeStyle,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GraphLayout {
  _GraphLayout(ScenarioGraph graph, TextScaler scaler) {
    const nodeWidth = 176.0;
    const horizontalGap = 24.0;
    const labelWidth = 170.0;
    double height(String text, TextStyle style, double width, {int? maxLines}) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: maxLines,
        ellipsis: maxLines == null ? null : '…',
      )..layout(maxWidth: width);
      return painter.height;
    }

    final depth = {graph.startSceneId: 0};
    final queue = [graph.startSceneId];
    final outgoing = <String, List<String>>{};
    for (final edge in graph.transitions) {
      outgoing.putIfAbsent(edge.fromSceneId, () => []).add(edge.toSceneId);
    }
    for (var i = 0; i < queue.length; i++) {
      for (final next in outgoing[queue[i]] ?? <String>[]) {
        if (!depth.containsKey(next)) {
          depth[next] = depth[queue[i]]! + 1;
          queue.add(next);
        }
      }
    }
    final layers = List.generate(
      depth.values.reduce(math.max) + 1,
      (_) => <ScenarioScene>[],
    );
    for (final scene in graph.scenes) {
      layers[depth[scene.id]!].add(scene);
    }
    final widths = [
      for (final layer in layers)
        layer.length * (nodeWidth + horizontalGap) - horizontalGap,
    ];
    final baseWidth = widths.reduce(math.max) + 32;
    final labelHeights = [
      for (final edge in graph.transitions)
        height(_label(graph, edge), _edgeStyle, labelWidth - 8, maxLines: 2) +
            8,
    ];
    final gap = (labelHeights.isEmpty ? 0 : labelHeights.reduce(math.max)) + 32;
    var y = 16.0;
    for (var layerIndex = 0; layerIndex < layers.length; layerIndex++) {
      final layer = layers[layerIndex];
      final rowHeight = layer
          .map(
            (scene) =>
                height(
                  _title(graph, scene),
                  _headingStyle,
                  nodeWidth - 24,
                  maxLines: 2,
                ) +
                height(
                  _summary(scene),
                  _bodyStyle,
                  nodeWidth - 24,
                  maxLines: 2,
                ) +
                30 +
                (_role(graph, scene.id).isEmpty
                    ? 0
                    : 6 +
                          math.max(
                            18,
                            height(
                              _role(graph, scene.id),
                              _edgeStyle,
                              nodeWidth - 46,
                              maxLines: 1,
                            ),
                          )),
          )
          .reduce(math.max);
      for (var i = 0; i < layer.length; i++) {
        nodes[layer[i].id] = Rect.fromLTWH(
          (baseWidth - widths[layerIndex]) / 2 +
              i * (nodeWidth + horizontalGap),
          y,
          nodeWidth,
          rowHeight,
        );
      }
      y += rowHeight + gap;
    }
    var sideLanes = 0;
    for (var i = 0; i < graph.transitions.length; i++) {
      final edge = graph.transitions[i];
      final from = nodes[edge.fromSceneId]!;
      final to = nodes[edge.toSceneId]!;
      final path = Path();
      late Rect label;
      late Offset tip;
      late Offset direction;
      if (to.top > from.bottom) {
        final split = from.bottom + 12;
        path.moveTo(from.center.dx, from.bottom);
        path.lineTo(from.center.dx, split);
        path.lineTo(to.center.dx, split);
        path.lineTo(to.center.dx, to.top);
        label = Rect.fromCenter(
          center: Offset(to.center.dx, (split + to.top) / 2),
          width: labelWidth,
          height: labelHeights[i],
        );
        tip = to.topCenter;
        direction = const Offset(0, 1);
      } else {
        // Geri bağlantılar/döngüler ayrı dış kanallara alınır.
        final lane =
            baseWidth + 30 + sideLanes++ * (labelWidth + 40) + labelWidth / 2;
        path.moveTo(from.right, from.center.dy);
        path.lineTo(lane, from.center.dy - 30);
        path.lineTo(lane, to.center.dy + 30);
        path.lineTo(to.right, to.center.dy);
        label = Rect.fromCenter(
          center: Offset(lane, (from.center.dy + to.center.dy) / 2),
          width: labelWidth,
          height: labelHeights[i],
        );
        tip = to.centerRight;
        direction = const Offset(-1, 0);
      }
      edges.add(_Edge(path, label, tip, direction));
    }
    size = Size(baseWidth + sideLanes * (labelWidth + 40), y - gap + 16);
  }
  final nodes = <String, Rect>{};
  final edges = <_Edge>[];
  late final Size size;
}

class _Edge {
  _Edge(this.path, this.label, this.tip, this.direction);
  final Path path;
  final Rect label;
  final Offset tip;
  final Offset direction;
}

class _ConnectionsPainter extends CustomPainter {
  _ConnectionsPainter(this.layout);
  final _GraphLayout layout;
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFF596C82)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final fill = Paint()..color = line.color;
    for (final edge in layout.edges) {
      canvas.drawPath(edge.path, line);
      final across = Offset(-edge.direction.dy, edge.direction.dx);
      final arrow = Path()..moveTo(edge.tip.dx, edge.tip.dy);
      final left = edge.tip - edge.direction * 8 + across * 4;
      final right = edge.tip - edge.direction * 8 - across * 4;
      arrow.lineTo(left.dx, left.dy);
      arrow.lineTo(right.dx, right.dy);
      arrow.close();
      canvas.drawPath(arrow, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionsPainter oldDelegate) =>
      oldDelegate.layout != layout;
}
