# Visual App Editor for VS Code (planned)

**Status: planned, skeleton only. Nothing here builds or ships yet.**

This is our own VS Code extension, a standalone front end for the Visual App
Editor service. It does not extend or depend on any other vendor's language
extension.

Planned shape:

- Spawns `vae_service` over stdio with `vscode-jsonrpc`, using the same
  Content-Length framing as LSP.
- A webview panel with the tree, palette and properties. Edits use
  `document/edit`, and the returned source is applied as a `WorkspaceEdit`, so
  undo, dirty state and formatting stay native.
- Live preview uses the device_preview approach described in the spec.
