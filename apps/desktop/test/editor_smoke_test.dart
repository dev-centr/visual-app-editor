import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:visual_app_editor/main.dart';
import 'package:visual_app_editor/src/ui/editor_state.dart';

void main() {
  testWidgets('opens the sample project and renders the canvas', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('wb');
    for (final f in Directory('assets/sample_app').listSync(recursive: true).whereType<File>()) {
      final out = File(p.join(tmp.path, p.relative(f.path, from: 'assets/sample_app')));
      out.parent.createSync(recursive: true);
      f.copySync(out.path);
    }
    tester.view.physicalSize = const Size(2400, 1400);
    tester.view.devicePixelRatio = 1;
    final s = EditorState();
    await tester.runAsync(() async {
      await s.init();
      await s.openProject(tmp.path);
    });
    expect(s.error, isNull);
    await tester.pumpWidget(VisualAppEditorApp(s));
    await tester.pump();
    expect(find.text('Good morning'), findsWidgets);
    expect(find.text('Widget Tree'), findsOneWidget);
    s.selectedPath = [0, 1, 0];
    await tester.runAsync(() => s.insertSnippet("Text('From test')"));
    await tester.pump();
    expect(find.text('From test'), findsWidgets);
    await tester.runAsync(s.save);
    expect(File(p.join(tmp.path, 'lib/pages/home_page.dart')).readAsStringSync(), contains("Text('From test')"));
    addTearDown(tester.view.reset);
  });
}
