/// Build metadata. CI passes --dart-define=VAE_VERSION / VAE_BUILD.
const kVersion = String.fromEnvironment('VAE_VERSION', defaultValue: '0.1.0-dev');
const kBuildId = String.fromEnvironment('VAE_BUILD', defaultValue: 'local');
