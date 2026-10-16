import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Runs the target project with `flutter run` (debug, hot-reload capable)
/// and forwards save events as hot reloads over the tool's stdin.
class LiveRunner {
  Process? _proc;
  final _log = StreamController<String>.broadcast();
  Stream<String> get log => _log.stream;
  bool get running => _proc != null;
  String? vmServiceUri;

  static String get defaultDevice => Platform.isWindows ? 'windows' : Platform.isMacOS ? 'macos' : 'linux';

  Future<void> start(String projectRoot, {String? device}) async {
    if (_proc != null) return;
    final p = await Process.start('flutter', ['run', '-d', device ?? defaultDevice], workingDirectory: projectRoot, runInShell: true);
    _proc = p;
    void pipe(Stream<List<int>> s) => s.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
          final m = RegExp(r'(http://127\.0\.0\.1:\d+/[^\s]*)').firstMatch(l);
          if (m != null && l.contains('VM Service')) vmServiceUri = m.group(1);
          _log.add(l);
        });
    pipe(p.stdout);
    pipe(p.stderr);
    unawaited(p.exitCode.then((c) {
      _log.add('flutter run exited ($c)');
      _proc = null;
    }));
  }

  void hotReload() => _proc?.stdin.write('r');
  void hotRestart() => _proc?.stdin.write('R');

  Future<void> stop() async {
    final p = _proc;
    if (p == null) return;
    p.stdin.write('q');
    await p.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
      p.kill();
      return -1;
    });
    _proc = null;
  }
}
