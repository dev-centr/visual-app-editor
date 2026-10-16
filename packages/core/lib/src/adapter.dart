import 'dart:async';

import 'catalog.dart';
import 'edits.dart';
import 'tree.dart';

/// A language / framework adapter. The headless service routes each source
/// file to the first adapter whose [handles] returns true.
abstract class LanguageAdapter {
  /// Stable id, e.g. `dart-flutter`, `react`.
  String get id;

  /// File extensions this adapter edits (`.dart`, `.tsx`, ...).
  List<String> get extensions;

  bool handles(String path) => extensions.any(path.endsWith);

  /// Pages / screens found in [source].
  FutureOr<List<PageInfo>> pages(String path, String source);

  /// Applies [op] to page [page] in [source] and returns the new source.
  /// Throws [SourceEditException] when the result would not parse.
  FutureOr<String> applyEdit(String path, String source, String page, EditOp op);

  /// Discovers widget/component constructors for [manifest] given a project.
  FutureOr<Toolkit?> loadToolkit(ToolkitManifest manifest, String projectRoot) => null;
}
