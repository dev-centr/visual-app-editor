import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:widget_bench/main.dart';
import 'package:widget_bench/src/ui/editor_state.dart';

void main() {
  testWidgets('opens the sample project and renders the canvas', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('wb');
    for (final f in Directory('example/sample_app').listSync(recursive: true).whereType<File>()) {
      final out = File(p.join(tmp.path, p.relative(f.path, from: 'example/sample_app')));
      out.parent.createSync(recursive: true);
      f.copySync(out.path);
    }
    tester.view.physicalSize = const Size(2400, 1400);
    tester.view.devicePixelRatio = 1;
    final s = EditorState();
    s.openProject(tmp.path);
    expect(s.error, isNull);
    await tester.pumpWidget(WidgetBenchApp(s));
    await tester.pump();
    expect(find.text('Good morning'), findsWidgets);
    expect(find.text('Widget Tree'), findsOneWidget);
    s.selectedPath = [0, 1, 0];
    s.insertSnippet("Text('From test')");
    await tester.pump();
    expect(find.text('From test'), findsWidgets);
    s.save();
    expect(File(p.join(tmp.path, 'lib/pages/home_page.dart')).readAsStringSync(), contains("Text('From test')"));
    addTearDown(tester.view.reset);
  });
}
