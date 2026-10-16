# Visual App Editor for IntelliJ / Android Studio (planned)

**Status: planned, skeleton only. Nothing here builds or ships yet.**

This is our own IntelliJ Platform plugin, a standalone front end for the
Visual App Editor service. It does not extend or depend on any other vendor's
language plugin.

Planned shape:

- Starts `vae_service` (or the bundled native build) as a child process and
  talks JSON-RPC over stdio (see `docs/modules/ROOT/pages/protocol.adoc`).
- Tool window with a widget tree, palette and properties, rendered with
  Swing/Compose against `document/tree` and `toolkit/palette`.
- Edits go through `document/edit`. The IDE document is updated from the
  returned source, so undo and VCS work as usual.
- Live preview: launches the user's app with the device_preview wrapper (see
  the spec) and does not draw widgets itself.

Files: `build.gradle.kts` (IntelliJ Platform Gradle plugin 2.x, to be wired
up), `src/main/resources/META-INF/plugin.xml`, and a placeholder service class.
