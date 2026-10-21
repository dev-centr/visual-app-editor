import 'dart:async';

import 'package:vae_core/vae_core.dart';
import 'package:vae_dart_adapter/vae_dart_adapter.dart';
import 'package:vae_protocol/vae_protocol.dart';

import 'external_adapter.dart';
import 'project.dart';

const serviceVersion = '0.1.0';

/// The headless editor service. Bind it to any [RpcPeer] (stdio, socket,
/// or an in-process pipe) and every front end gets the same behaviour.
class EditorService {
  EditorService(this.peer, {List<LanguageAdapter>? adapters}) : adapters = adapters ?? [DartFlutterAdapter()] {
    _register();
    for (final sdl in bundledToolkits.values) {
      _addManifests(sdl);
    }
  }

  final RpcPeer peer;
  final List<LanguageAdapter> adapters;
  final Map<String, ToolkitManifest> manifests = {};
  final Map<String, Toolkit> loaded = {};
  final List<String> log = [];
  Project? project;
  bool _initialized = false;
  final _shutdown = Completer<void>();
  Future<void> get onShutdown => _shutdown.future;

  void _addManifests(String sdl) {
    for (final m in ToolkitManifest.parse(sdl)) {
      manifests[m.id] = m;
    }
  }

  LanguageAdapter? adapterFor(String file) {
    for (final a in adapters) {
      if (a.handles(file)) return a;
    }
    return null;
  }

  LanguageAdapter? adapterById(String id) {
    for (final a in adapters) {
      if (a.id == id) return a;
    }
    return null;
  }

  Project get _proj => project ?? (throw RpcException(ErrorCodes.noProject, 'No project open'));

  String _file(Map<String, Object?> p) {
    final f = p['file'] as String? ?? (throw RpcException(ErrorCodes.invalidParams, 'file is required'));
    if (!_proj.sources.containsKey(f)) throw RpcException(ErrorCodes.notFound, 'Unknown file $f');
    return f;
  }

  void _register() {
    void on(String m, RpcHandler h, {bool needsInit = true}) => peer.on(m, (p) {
          if (needsInit && !_initialized) throw RpcException(ErrorCodes.notInitialized, 'Call initialize first');
          return _guard(() => h(p));
        });

    on(Methods.initialize, (p) {
      _initialized = true;
      for (final sdl in (p['manifests'] as List? ?? const [])) {
        _addManifests(sdl as String);
      }
      for (final e in (p['externalAdapters'] as List? ?? const [])) {
        final m = (e as Map).cast<String, Object?>();
        adapters.add(ExternalAdapter(
          id: m['id'] as String,
          extensions: [for (final x in m['extensions'] as List) '$x'],
          command: [for (final x in m['command'] as List) '$x'],
          workingDirectory: m['cwd'] as String?,
        ));
      }
      return {
        'serverInfo': {'name': 'vae_service', 'version': serviceVersion},
        'capabilities': {
          'adapters': [for (final a in adapters) {'id': a.id, 'extensions': a.extensions}],
          'editOps': const ['setArgument', 'removeArgument', 'setPositional', 'setText', 'insertChild', 'removeNode', 'wrapNode', 'moveInList', 'replaceSource'],
        },
      };
    }, needsInit: false);

    on(Methods.shutdown, (p) async {
      for (final a in adapters.whereType<ExternalAdapter>()) {
        await a.dispose();
      }
      // Complete after the response has been written.
      Timer(const Duration(milliseconds: 100), () {
        if (!_shutdown.isCompleted) _shutdown.complete();
      });
      return null;
    }, needsInit: false);

    on(Methods.projectOpen, (p) async {
      final root = p['root'] as String? ?? (throw RpcException(ErrorCodes.invalidParams, 'root is required'));
      try {
        project = Project.open(root, (rel) => adapterFor(rel) != null);
      } on Exception catch (e) {
        throw RpcException(ErrorCodes.notFound, '$e');
      }
      loaded.clear();
      for (final id in project!.config.toolkits) {
        await _load(id);
      }
      return {'name': project!.name, 'root': root, 'kind': project!.kind, 'config': _configJson(), 'pages': await _pages()};
    });

    on(Methods.projectPages, (p) async => await _pages());
    on(Methods.projectConfig, (p) => _configJson());
    on(Methods.projectSetConfig, (p) {
      final c = _proj.config;
      if (p['toolkits'] is List) c.toolkits = [for (final x in p['toolkits'] as List) '$x'];
      if (p['device'] is String) c.device = p['device'] as String;
      if (p['seedColor'] is int) c.seedColor = p['seedColor'] as int;
      if (p['dark'] is bool) c.dark = p['dark'] as bool;
      if (p['fontPreference'] is String) c.fontPreference = p['fontPreference'] as String;
      if (p.containsKey('uiSansFace')) {
        final v = p['uiSansFace'] as String?;
        c.uiSansFace = (v == null || v.isEmpty) ? null : v;
      }
      if (p.containsKey('uiMonoFace')) {
        final v = p['uiMonoFace'] as String?;
        c.uiMonoFace = (v == null || v.isEmpty) ? null : v;
      }
      _proj.saveConfig();
      return _configJson();
    });
    on(Methods.projectAddPage, (p) {
      try {
        return {'file': _proj.addFlutterPage(p['className'] as String)};
      } on Exception catch (e) {
        throw RpcException(ErrorCodes.editRejected, '$e');
      }
    });

    on(Methods.documentSource, (p) {
      final f = _file(p);
      return {'file': f, 'source': _proj.sources[f], 'dirty': _proj.dirty.contains(f)};
    });

    on(Methods.documentTree, (p) async {
      final f = _file(p);
      final pages = await adapterFor(f)!.pages(f, _proj.sources[f]!);
      final name = p['page'] as String?;
      final pg = name == null ? pages.firstOrNull : pages.where((x) => x.name == name).firstOrNull;
      if (pg == null) throw RpcException(ErrorCodes.notFound, 'No page $name in $f');
      return pg.toJson();
    });

    on(Methods.documentEdit, (p) async {
      final f = _file(p);
      final page = p['page'] as String? ?? '';
      final op = EditOp.fromJson((p['op'] as Map).cast());
      final a = adapterFor(f)!;
      try {
        final next = await a.applyEdit(f, _proj.sources[f]!, page, op);
        _proj.sources[f] = next;
        _proj.dirty.add(f);
      } on SourceEditException catch (e) {
        throw RpcException(ErrorCodes.editRejected, e.message);
      } on ArgumentError catch (e) {
        throw RpcException(ErrorCodes.invalidParams, '$e');
      }
      peer.notify(Methods.documentChanged, {'file': f});
      final pages = await a.pages(f, _proj.sources[f]!);
      return {
        'source': _proj.sources[f],
        'page': pages.where((x) => x.name == page).firstOrNull?.toJson(),
      };
    });

    on(Methods.documentSync, (p) async {
      final f = p['file'] as String? ?? (throw RpcException(ErrorCodes.invalidParams, 'file is required'));
      final src = p['source'] as String? ?? (throw RpcException(ErrorCodes.invalidParams, 'source is required'));
      if (f.startsWith('/') || f.contains('..') || f.contains(':')) throw RpcException(ErrorCodes.invalidParams, 'file must be project-relative');
      final a = adapterFor(f) ?? (throw RpcException(ErrorCodes.notFound, 'No adapter for $f'));
      final changed = _proj.sources[f] != src;
      _proj.sources[f] = src;
      // The client owns the buffer and saving, so a synced file is not dirty here.
      _proj.dirty.remove(f);
      final pages = await a.pages(f, src);
      return {'file': f, 'changed': changed, 'pages': [for (final pg in pages) if (pg.root != null) pg.toJson(withTree: false)]};
    });

    on(Methods.documentSave, (p) {
      final files = p['files'] is List ? [for (final x in p['files'] as List) '$x'] : _proj.dirty.toList();
      for (final f in files) {
        _proj.save(f);
      }
      return {'saved': files};
    });

    on(Methods.toolkitRegister, (p) {
      _addManifests(p['sdl'] as String);
      return {'ids': manifests.keys.toList()};
    });
    on(Methods.toolkitList, (p) => [
          for (final m in manifests.values)
            {...m.toJson(), 'loaded': loaded.containsKey(m.id), 'count': loaded[m.id]?.widgets.length ?? 0},
        ]);
    on(Methods.toolkitLoad, (p) async {
      final ok = await _load(p['id'] as String);
      if (!ok) throw RpcException(ErrorCodes.notFound, log.last);
      _proj.config.toolkits = loaded.keys.toList();
      _proj.saveConfig();
      return {'id': p['id'], 'count': loaded[p['id']]!.widgets.length};
    });
    on(Methods.toolkitUnload, (p) {
      loaded.remove(p['id']);
      _proj.config.toolkits = loaded.keys.toList();
      _proj.saveConfig();
      return null;
    });
    on(Methods.toolkitPalette, (p) {
      final only = p['toolkit'] as String?;
      return [
        for (final t in loaded.values)
          if (only == null || t.manifest.id == only)
            for (final w in t.widgets) w.toJson(),
      ];
    });

    on(Methods.devicePresets, (p) => [for (final d in DevicePresets.all) d.toJson()], needsInit: false);
  }

  Map<String, Object?> _configJson() {
    final c = _proj.config;
    return {
      'toolkits': c.toolkits,
      'device': c.device,
      'seedColor': c.seedColor,
      'dark': c.dark,
      'fontPreference': c.fontPreference,
      'uiSansFace': c.uiSansFace,
      'uiMonoFace': c.uiMonoFace,
    };
  }

  /// Adapter process failures are reported to the client, never swallowed.
  Future<Object?> _guard(FutureOr<Object?> Function() f) async {
    try {
      return await f();
    } on AdapterProcessException catch (e) {
      log.add(e.message);
      peer.notify(Methods.logMessage, {'message': e.message, 'type': 'error'});
      throw RpcException(ErrorCodes.adapterFailed, e.message);
    }
  }

  Future<List<Map<String, Object?>>> _pages() async {
    final out = <Map<String, Object?>>[];
    for (final e in _proj.sources.entries) {
      try {
        for (final pg in await adapterFor(e.key)!.pages(e.key, e.value)) {
          if (pg.root != null) out.add(pg.toJson(withTree: false));
        }
      } on AdapterProcessException {
        rethrow;
      } catch (err) {
        log.add('Could not read ${e.key}: $err');
      }
    }
    out.sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    return out;
  }

  Future<bool> _load(String id) async {
    final m = manifests[id];
    if (m == null) {
      log.add('Unknown toolkit $id');
      return false;
    }
    final a = adapterById(m.adapter);
    if (a == null) {
      log.add('Toolkit ${m.name}: adapter ${m.adapter} not available');
      return false;
    }
    final t = await a.loadToolkit(m, _proj.root);
    if (t == null) {
      log.add('Toolkit ${m.name}: package "${m.package}" not found. Add it to the project and install dependencies.');
      return false;
    }
    loaded[id] = t;
    log.add('Toolkit ${m.name}: ${t.widgets.length} constructors');
    peer.notify(Methods.logMessage, {'message': log.last});
    return true;
  }
}
