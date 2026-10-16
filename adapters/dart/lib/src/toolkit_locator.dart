import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vae_core/vae_core.dart';

import 'introspector.dart';

/// Resolves a toolkit manifest's package to a `lib/` folder on disk.
class ToolkitLocator {
  static String? locate(ToolkitManifest m, String? projectRoot) {
    if (projectRoot != null) {
      final r = ToolkitIntrospector.resolvePackageLib(projectRoot, m.package);
      if (r != null && Directory(r).existsSync()) return r;
    }
    if (m.package == 'flutter') {
      final sdk = flutterSdkRoot();
      if (sdk != null) {
        final lib = p.join(sdk, 'packages', 'flutter', 'lib');
        if (Directory(lib).existsSync()) return lib;
      }
    }
    return null;
  }

  /// `FLUTTER_ROOT`, else the folder above `flutter` on `PATH`.
  static String? flutterSdkRoot() {
    final env = Platform.environment['FLUTTER_ROOT'];
    if (env != null && env.isNotEmpty) return env;
    final pathVar = Platform.environment['PATH'] ?? '';
    for (final dir in pathVar.split(Platform.isWindows ? ';' : ':')) {
      final exe = File(p.join(dir, Platform.isWindows ? 'flutter.bat' : 'flutter'));
      if (exe.existsSync()) return p.dirname(p.dirname(exe.path));
    }
    return null;
  }
}
