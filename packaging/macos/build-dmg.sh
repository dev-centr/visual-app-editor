#!/usr/bin/env bash
# Builds the macOS release app and wraps it in a .dmg (unsigned).
# Usage: packaging/macos/build-dmg.sh [version]
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
version="${1:-$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)}"
build_id="${GITHUB_RUN_NUMBER:+ci.$GITHUB_RUN_NUMBER}"
if [ "${SKIP_BUILD:-0}" != 1 ]; then
  flutter build macos --release --dart-define=WB_VERSION="$version" --dart-define=WB_BUILD="${build_id:-local}"
fi
app="build/macos/Build/Products/Release/widget_bench.app"
test -d "$app"
dist="$root/dist"; mkdir -p "$dist"
stage="$(mktemp -d)"
cp -R "$app" "$stage/Widget Bench.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Widget Bench" -srcfolder "$stage" -ov -format UDZO "$dist/WidgetBench-${version}-macos-arm64.dmg"
ls -la "$dist"
