# Visual App Editor for IntelliJ IDEA / Android Studio

Our own IntelliJ Platform plugin (Kotlin, IntelliJ Platform Gradle Plugin 2.x). It is a front end for the Visual App Editor service and does not extend or depend on any other vendor's plugin.

- **Tool window** *Visual App Editor* (right side): the widget tree of the current `.dart` / `.tsx` / `.jsx` file, with page picker, move up/down, wrap with, delete, and double-click to jump to the source.
- **Properties** tab: every named parameter of the selected widget. Unset values stay blank (the type and default are in the third column). Editing a value sends `setArgument` / `removeArgument` / `setText`.
- **Toolbox** tab: searchable palette from the loaded toolkits. Double-click (or *Insert into selection*) sends `insertChild`.
- **Device** switcher: phone / tablet / desktop / web modes and their presets, persisted in `visual_app_editor.sdl`. The **Preview** tab draws the tree as a wireframe at that size.
- Every change is applied with `WriteCommandAction` as one minimal document replacement, so **Undo** and VCS work as usual. Unsaved buffer text is synced to the service before each edit (`document/sync`).

Targets IntelliJ Platform **2026.2 (build 262)** and later: IntelliJ IDEA 2026.2+ and Android Studio 2026.2+. It needs Java 25 to build.

## Setup

The plugin starts the headless service as a child process. Under **Settings | Tools | Visual App Editor**:

- **Service command**: a compiled `vae_service` executable, or `dart run <repo>/packages/service/bin/vae_service.dart` (run `flutter pub get` in the repo first). Leave it empty to use `$VAE_SERVICE`, then `vae_service` on `PATH`, then `packages/service` inside the open project.
- **React adapter command** (optional): `node <repo>/adapters/react/dist/cli.js` (after `pnpm install && pnpm build` in `adapters/react`). This enables `.tsx`/`.jsx` files.

## Build and test

```sh
cd plugins/intellij
./gradlew test buildPlugin verifyPlugin      # zip in build/distributions/
# Optional end-to-end test against the real service:
VAE_SERVICE_TEST_CMD="dart run packages/service/bin/vae_service.dart" VAE_REPO_ROOT=../.. ./gradlew test
# Build against an installed IDE instead of downloading IntelliJ IDEA:
./gradlew buildPlugin -PplatformLocalPath="C:/Program Files/Android/Android Studio"
```

Install from file: **Settings | Plugins | ⚙ | Install Plugin from Disk…** and pick `visual-app-editor-intellij-<version>.zip`. Publishing: see the docs page *Publishing the IDE plugins*.
