# Widget Bench - agent notes

Org rules: `dev-centr/agent-rules` `AGENTS.md` (org layer wins). Facts for this repo:

- Flutter desktop app. `flutter analyze` and `flutter test` must pass before push.
- `package:analyzer` is pinned to `^9.0.0`: analyzer 10+ reshaped the AST (`NamedArgument`, `ClassBody`, `namePart`). Port `lib/src/source` and `lib/src/toolkit/introspector.dart` before raising it.
- README screenshot: `flutter test tool/screenshot/readme_screenshot_test.dart` (needs `FLUTTER_ROOT` or flutter on PATH; Windows for Consolas) writes `docs/modules/ROOT/images/screenshot.png`.
- Config files are SDL (`widget_bench.sdl`, `toolkits/*.sdl`).
- Installers: `packaging/` scripts; CI uploads them as artifacts. Do not create releases or tags unless asked.
- Changelog: `docs/modules/ROOT/pages/changelog.adoc` + `changelog-details/`, mirrored in `CHANGELOG.adoc`.
