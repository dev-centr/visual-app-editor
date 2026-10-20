# Visual App Editor - agent notes

Org rules: `dev-centr/agent-rules` `AGENTS.md` (org layer wins). Facts for this repo:

- Monorepo (formerly `widget-bench`): Dart pub workspace at the root (`packages/core`, `packages/protocol`, `packages/service`, `adapters/dart`, `apps/desktop`); `adapters/react` is Node/TS with pnpm; `plugins/intellij` (Kotlin, Gradle wrapper, Java 25, IntelliJ Platform Gradle Plugin 2.19, platform 262+) and `plugins/vscode` (TypeScript, pnpm, esbuild, vsce) are real front ends; build/test commands are in their READMEs. Never publish them (guide: docs `publishing-ide-plugins.adoc`).
- Run `flutter pub get` at the root (not `dart pub get`: the workspace has a Flutter member). Tests: `dart test` in each pure-Dart package, `flutter analyze && flutter test` in `apps/desktop`, `pnpm test` in `adapters/react` (builds `dist/`, which `packages/service` tests use; they skip without it).
- `package:analyzer` is pinned to `^9.0.0`: analyzer 10+ reshaped the AST (`NamedArgument`, `ClassBody`, `namePart`). Port `adapters/dart/lib/src` before raising it.
- `typescript` stays on 5.x: the adapter uses the JS compiler API; TS 7 is the native port.
- Editing toolkit manifests in `adapters/dart/toolkits/`: rerun `dart run tool/gen_bundled.dart` in `adapters/dart` (a test fails if out of sync).
- The desktop app is a protocol client; new editing behaviour goes in the service/adapters, not `apps/desktop`.
- README screenshot: in `apps/desktop`, `flutter test tool/screenshot/readme_screenshot_test.dart` (needs `FLUTTER_ROOT` or flutter on PATH; Windows for Consolas) writes `docs/modules/ROOT/images/screenshot.png`.
- Config files are SDL (`visual_app_editor.sdl`; `widget_bench.sdl` is still read).
- Installers: `apps/desktop/packaging/` scripts; CI uploads `visual-app-editor-<triplet>` artifacts. Do not create releases or tags unless asked. Do not publish packages (intent is documented in the spec).
- Changelog: `docs/modules/ROOT/pages/changelog.adoc` + `changelog-details/`, mirrored in `CHANGELOG.adoc`.
