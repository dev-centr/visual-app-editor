#!/usr/bin/env bash
# Builds the Linux release bundle and packages it as an AppImage and a .deb.
# Usage: packaging/linux/build-packages.sh [version]   (needs flutter, dpkg-deb, curl)
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
version="${1:-$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)}"
case "$(uname -m)" in
  x86_64) arch=x64; deb_arch=amd64; ai_arch=x86_64 ;;
  aarch64|arm64) arch=arm64; deb_arch=arm64; ai_arch=aarch64 ;;
  *) echo "unsupported arch $(uname -m)"; exit 1 ;;
esac
build_id="${GITHUB_RUN_NUMBER:+ci.$GITHUB_RUN_NUMBER}"
if [ "${SKIP_BUILD:-0}" != 1 ]; then
  flutter build linux --release --dart-define=VAE_VERSION="$version" --dart-define=VAE_BUILD="${build_id:-local}"
fi
bundle="build/linux/$arch/release/bundle"
test -x "$bundle/visual_app_editor"
dist="$root/dist"; mkdir -p "$dist"
icon="packaging/icons/visual_app_editor-256.png"

# .deb -------------------------------------------------------------------
deb="$(mktemp -d)"
mkdir -p "$deb/DEBIAN" "$deb/opt/visual-app-editor" "$deb/usr/bin" "$deb/usr/share/applications" "$deb/usr/share/icons/hicolor/256x256/apps"
cp -r "$bundle/." "$deb/opt/visual-app-editor/"
ln -s /opt/visual-app-editor/visual_app_editor "$deb/usr/bin/visual-app-editor"
cp "$icon" "$deb/usr/share/icons/hicolor/256x256/apps/visual-app-editor.png"
cp packaging/linux/visual-app-editor.desktop "$deb/usr/share/applications/"
cat > "$deb/DEBIAN/control" <<CONTROL
Package: visual-app-editor
Version: $version
Section: devel
Priority: optional
Architecture: $deb_arch
Depends: libgtk-3-0
Maintainer: Dev-Centr <https://github.com/dev-centr>
Homepage: https://github.com/dev-centr/visual-app-editor
Description: Offline visual UI builder for Flutter apps
 Edits Flutter page source visually with toolkits introspected from packages.
CONTROL
dpkg-deb --build --root-owner-group "$deb" "$dist/visual-app-editor_${version}_${deb_arch}.deb"

# AppImage ---------------------------------------------------------------
appdir="$(mktemp -d)/VisualAppEditor.AppDir"
mkdir -p "$appdir/usr/bin"
cp -r "$bundle/." "$appdir/usr/bin/"
cp "$icon" "$appdir/visual-app-editor.png"
cp packaging/linux/visual-app-editor.desktop "$appdir/"
cat > "$appdir/AppRun" <<'RUN'
#!/bin/sh
here="$(dirname "$(readlink -f "$0")")"
exec "$here/usr/bin/visual_app_editor" "$@"
RUN
chmod +x "$appdir/AppRun"
tool="$(mktemp -d)/appimagetool"
curl -fsSL -o "$tool" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${ai_arch}.AppImage"
chmod +x "$tool"
ARCH="$ai_arch" "$tool" --appimage-extract-and-run "$appdir" "$dist/VisualAppEditor-${version}-${arch}.AppImage"
ls -la "$dist"
