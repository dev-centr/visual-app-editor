import 'package:flutter/material.dart';

import 'package:vae_core/vae_core.dart';

import '../preview/renderer.dart';
import 'editor_state.dart';
import 'theme.dart';

/// Center canvas: the page rendered in-process inside a device frame.
class CanvasView extends StatelessWidget {
  const CanvasView(this.s, {super.key});
  final EditorState s;

  @override
  Widget build(BuildContext context) {
    final root = s.page?.root;
    final dev = s.device;
    final cfg = s.project?.config;
    final theme = ThemeData(
      colorSchemeSeed: Color(cfg?.seedColor ?? 0xFF6750A4),
      brightness: (cfg?.dark ?? false) ? Brightness.dark : Brightness.light,
    );
    return Container(
      color: Bench.canvas,
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _DotGrid())),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(40),
            child: Transform.scale(
              scale: s.zoom,
              child: Container(
                width: dev.width + 24,
                height: dev.height + 24,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF050607),
                  borderRadius: BorderRadius.circular(dev.mode == DeviceMode.phone ? 48 : dev.frame ? 20 : 4),
                  border: Border.all(color: const Color(0xFF3A444B), width: 2),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, 12))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(dev.mode == DeviceMode.phone ? 38 : dev.frame ? 10 : 0),
                  child: Theme(
                    data: theme,
                    child: Material(
                      child: MediaQuery(
                        data: MediaQueryData(size: Size(dev.width, dev.height), padding: EdgeInsets.only(top: dev.safeTop, bottom: dev.safeBottom)),
                        child: root == null
                            ? const Center(child: Text('Open a project and pick a page'))
                            : _SafeBuild(key: ValueKey(s.source.hashCode), builder: () => PreviewRenderer(selectedPath: s.selectedPath, onSelect: s.select).build(root)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Container(
            decoration: BoxDecoration(color: Bench.panel, borderRadius: BorderRadius.circular(8), border: Border.all(color: Bench.border)),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.remove, size: 16), onPressed: () => s.setZoom(s.zoom - .1)),
              Text('${(s.zoom * 100).round()}%', style: const TextStyle(fontSize: 12)),
              IconButton(icon: const Icon(Icons.add, size: 16), onPressed: () => s.setZoom(s.zoom + .1)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _SafeBuild extends StatelessWidget {
  const _SafeBuild({super.key, required this.builder});
  final Widget Function() builder;
  @override
  Widget build(BuildContext context) {
    try {
      return builder();
    } catch (e) {
      return Center(child: Text('Preview error: $e', style: const TextStyle(color: Colors.red)));
    }
  }
}

class _DotGrid extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF1C2226);
    for (double x = 0; x < size.width; x += 22) {
      for (double y = 0; y < size.height; y += 22) {
        canvas.drawCircle(Offset(x, y), 1, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
