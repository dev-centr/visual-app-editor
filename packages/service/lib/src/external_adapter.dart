import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vae_core/vae_core.dart';
import 'package:vae_protocol/vae_protocol.dart';

/// The adapter process could not be started or died. Surfaced to clients as
/// [ErrorCodes.adapterFailed] instead of an empty result.
class AdapterProcessException implements Exception {
  AdapterProcessException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// An adapter living in another process (e.g. the Node/TypeScript React
/// adapter), reached over the same framing with `adapter/*` methods.
class ExternalAdapter extends LanguageAdapter {
  ExternalAdapter({required this.id, required this.extensions, required this.command, this.workingDirectory});

  @override
  final String id;
  @override
  final List<String> extensions;
  final List<String> command;
  final String? workingDirectory;

  Process? _proc;
  RpcPeer? _peer;
  int? _exitCode;
  final _stderr = StringBuffer();

  String get _label => '$id adapter (${command.join(' ')})';

  String _failure(String what) {
    final err = _stderr.toString().trim();
    final tail = err.length > 1500 ? err.substring(err.length - 1500) : err;
    return '$_label $what${tail.isEmpty ? '' : ':\n$tail'}';
  }

  Future<RpcPeer> _connect() async {
    final existing = _peer;
    if (existing != null && _exitCode == null) return existing;
    if (existing != null) throw AdapterProcessException(_failure('exited with code $_exitCode'));
    final Process p;
    try {
      p = await Process.start(command.first, command.skip(1).toList(), workingDirectory: workingDirectory, runInShell: Platform.isWindows);
    } on ProcessException catch (e) {
      throw AdapterProcessException('$_label could not start: ${e.message}');
    }
    _proc = p;
    p.stderr.transform(utf8.decoder).listen((s) {
      _stderr.write(s);
      stderr.write(s);
    });
    final peer = RpcPeer(p.stdout.transform(const MessageDecoder()), (m) {
      if (_exitCode == null) p.stdin.add(encodeMessage(m));
    });
    _peer = peer;
    unawaited(p.exitCode.then((c) async {
      _exitCode = c;
      // Let stderr drain so the message carries the cause.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await peer.close();
    }));
    return peer;
  }

  Future<Object?> _call(String method, Map<String, Object?> params) async {
    final peer = await _connect();
    try {
      return await peer.request(method, params);
    } on RpcException catch (e) {
      if (_exitCode != null || e.message == 'Connection closed') {
        throw AdapterProcessException(_failure('exited with code ${_exitCode ?? '?'}'));
      }
      rethrow;
    }
  }

  @override
  Future<List<PageInfo>> pages(String path, String source) async {
    final r = await _call('adapter/pages', {'path': path, 'source': source}) as List;
    return [for (final x in r) PageInfo.fromJson((x as Map).cast())];
  }

  @override
  Future<String> applyEdit(String path, String source, String page, EditOp op) async {
    try {
      final r = await _call('adapter/applyEdit', {'path': path, 'source': source, 'page': page, 'op': op.toJson()}) as Map;
      return r['source'] as String;
    } on RpcException catch (e) {
      throw SourceEditException(e.message);
    }
  }

  @override
  Future<Toolkit?> loadToolkit(ToolkitManifest manifest, String projectRoot) async {
    final r = await _call('adapter/loadToolkit', {'manifest': manifest.toJson(), 'projectRoot': projectRoot});
    if (r == null) return null;
    final widgets = [for (final w in (r as Map)['widgets'] as List) WidgetSpec.fromJson((w as Map).cast())];
    return Toolkit(manifest, widgets);
  }

  Future<void> dispose() async {
    await _peer?.close();
    _proc?.kill();
  }
}
