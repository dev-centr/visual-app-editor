import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vae_core/vae_core.dart';
import 'package:vae_protocol/vae_protocol.dart';

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

  Future<RpcPeer> _connect() async {
    final existing = _peer;
    if (existing != null) return existing;
    final p = await Process.start(command.first, command.skip(1).toList(), workingDirectory: workingDirectory, runInShell: Platform.isWindows);
    _proc = p;
    p.stderr.transform(utf8.decoder).listen(stderr.write);
    final peer = RpcPeer(p.stdout.transform(const MessageDecoder()), (m) => p.stdin.add(encodeMessage(m)));
    _peer = peer;
    return peer;
  }

  @override
  Future<List<PageInfo>> pages(String path, String source) async {
    final r = await (await _connect()).request('adapter/pages', {'path': path, 'source': source}) as List;
    return [for (final x in r) PageInfo.fromJson((x as Map).cast())];
  }

  @override
  Future<String> applyEdit(String path, String source, String page, EditOp op) async {
    try {
      final r = await (await _connect()).request('adapter/applyEdit', {'path': path, 'source': source, 'page': page, 'op': op.toJson()}) as Map;
      return r['source'] as String;
    } on RpcException catch (e) {
      throw SourceEditException(e.message);
    }
  }

  @override
  Future<Toolkit?> loadToolkit(ToolkitManifest manifest, String projectRoot) async {
    final r = await (await _connect()).request('adapter/loadToolkit', {'manifest': manifest.toJson(), 'projectRoot': projectRoot});
    if (r == null) return null;
    final widgets = [for (final w in (r as Map)['widgets'] as List) WidgetSpec.fromJson((w as Map).cast())];
    return Toolkit(manifest, widgets);
  }

  Future<void> dispose() async {
    await _peer?.close();
    _proc?.kill();
  }
}
