/// Build metadata. CI passes --dart-define=WB_VERSION / WB_BUILD.
const kVersion = String.fromEnvironment('WB_VERSION', defaultValue: '0.1.0-dev');
const kBuildId = String.fromEnvironment('WB_BUILD', defaultValue: 'local');
