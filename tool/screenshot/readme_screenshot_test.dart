// Renders the full editor UI (real widgets, real fonts) for the sample
// project to docs/modules/ROOT/images/screenshot.png. Run on a machine with the Flutter
// SDK: `flutter test tool/screenshot/readme_screenshot_test.dart`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:widget_bench/main.dart';
import 'package:widget_bench/src/toolkit/registry.dart';
import 'package:widget_bench/src/ui/editor_state.dart';

Future<void> _font(String family, String file) async {
  final sdk = ToolkitRegistry.flutterSdkRoot()!;
  final f = File(p.join(sdk, 'bin', 'cache', 'artifacts', 'material_fonts', file));
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  await loader.load();
}

void main() {
  testWidgets('readme screenshot', (tester) async {
    await tester.runAsync(() async {
      await _font('Roboto', 'Roboto-Regular.ttf');
      await _font('Roboto', 'Roboto-Medium.ttf');
      await _font('Roboto', 'Roboto-Bold.ttf');
      await _font('MaterialIcons', 'MaterialIcons-Regular.otf');
      final consolas = File(r'C:\Windows\Fonts\consola.ttf');
      if (consolas.existsSync()) {
        await (FontLoader('Consolas')..addFont(Future.value(ByteData.sublistView(consolas.readAsBytesSync())))).load();
      }
    });
    final tmp = Directory.systemTemp.createTempSync('wbshot');
    for (final f in Directory('example/sample_app').listSync(recursive: true).whereType<File>()) {
      final out = File(p.join(tmp.path, p.relative(f.path, from: 'example/sample_app')));
      out.parent.createSync(recursive: true);
      f.copySync(out.path);
    }
    tester.view.physicalSize = const Size(1600, 940);
    tester.view.devicePixelRatio = 1;
    final s = EditorState();
    await tester.runAsync(s.init);
    s.openProject(tmp.path);
    s.selectedPath = [0, 1, 0, 4];
    s.zoom = 0.82;
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: WidgetBenchApp(s)));
    await tester.pump(const Duration(milliseconds: 300));
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 1);
      return img.toByteData(format: ui.ImageByteFormat.png);
    });
    final out = File('docs/modules/ROOT/images/screenshot.png')..parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    addTearDown(tester.view.reset);
  });
}
