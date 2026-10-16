import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'src/ui/editor_shell.dart';
import 'src/ui/editor_state.dart';
import 'src/ui/theme.dart';
import 'src/version.dart';

final _shotKey = GlobalKey();

Future<void> main(List<String> args) async {
  if (args.contains('--version')) {
    stdout.writeln('visual_app_editor $kVersion ($kBuildId)');
    exit(0);
  }
  WidgetsFlutterBinding.ensureInitialized();
  final state = EditorState();
  await state.init();
  final shotIdx = args.indexOf('--screenshot');
  final shotPath = shotIdx >= 0 && shotIdx + 1 < args.length ? args[shotIdx + 1] : null;
  final path = [for (var i = 0; i < args.length; i++) if (!args[i].startsWith('--') && (i == 0 || args[i - 1] != '--screenshot')) args[i]].firstOrNull;
  if (path != null) await state.openProject(path);
  runApp(RepaintBoundary(key: _shotKey, child: VisualAppEditorApp(state)));
  if (shotPath != null) {
    // Debug aid: render the window to a PNG once it settles, then quit.
    await Future<void>.delayed(const Duration(seconds: 4));
    final boundary = _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(shotPath).writeAsBytesSync(bytes!.buffer.asUint8List());
    exit(0);
  }
}

class VisualAppEditorApp extends StatelessWidget {
  const VisualAppEditorApp(this.state, {super.key});
  final EditorState state;
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Visual App Editor',
        debugShowCheckedModeBanner: false,
        theme: Bench.theme(),
        home: EditorShell(state),
      );
}
