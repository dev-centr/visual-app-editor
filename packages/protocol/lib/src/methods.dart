/// Method names of the editor protocol. See docs: protocol.adoc.
abstract final class Methods {
  // lifecycle
  static const initialize = 'initialize';
  static const shutdown = 'shutdown';
  static const exit = 'exit';

  // project
  static const projectOpen = 'project/open';
  static const projectPages = 'project/pages';
  static const projectConfig = 'project/config';
  static const projectSetConfig = 'project/setConfig';
  static const projectAddPage = 'project/addPage';

  // documents
  static const documentSource = 'document/source';
  static const documentTree = 'document/tree';
  static const documentEdit = 'document/edit';
  static const documentSave = 'document/save';

  // toolkits
  static const toolkitRegister = 'toolkit/register';
  static const toolkitList = 'toolkit/list';
  static const toolkitLoad = 'toolkit/load';
  static const toolkitUnload = 'toolkit/unload';
  static const toolkitPalette = 'toolkit/palette';

  // devices
  static const devicePresets = 'device/presets';

  // server -> client notifications
  static const documentChanged = 'document/changed';
  static const logMessage = 'window/logMessage';
}

/// JSON-RPC error codes (standard + editor range -32000..-32099).
abstract final class ErrorCodes {
  static const parseError = -32700;
  static const invalidRequest = -32600;
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
  static const internalError = -32603;
  static const notInitialized = -32002;
  static const noProject = -32010;
  static const editRejected = -32020;
  static const notFound = -32030;
  static const adapterFailed = -32040;
}
