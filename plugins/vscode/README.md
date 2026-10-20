# Visual App Editor for VS Code

Our own VS Code extension (TypeScript, esbuild, pnpm). It is a front end for the Visual App Editor service and does not extend or depend on any other vendor's extension.

- **Widget Tree** view (Visual App Editor activity bar icon): the tree of the current `.dart` / `.tsx` / `.jsx` file. It has a page picker, inline move up/down, wrap and delete, and a context menu entry to reveal the source.
- **Inspector** webview:
  - a device mode switcher (phone / tablet / desktop / web) with presets, saved in `visual_app_editor.sdl`;
  - properties of the selected widget (unset values stay blank, with the default as placeholder);
  - a searchable toolbox (double-click to insert into the selection).
- Edits are applied as a `WorkspaceEdit`: one minimal replacement, one undo step. Unsaved changes are synced to the service before each edit.

## Settings

- `visualAppEditor.serviceCommand`: a compiled `vae_service` executable or `dart run <repo>/packages/service/bin/vae_service.dart`. Leave it empty to use `$VAE_SERVICE`, then `vae_service` on PATH, then `packages/service` in the workspace.
- `visualAppEditor.reactAdapterCommand` (optional): `node <repo>/adapters/react/dist/cli.js`. This enables `.tsx`/`.jsx` files.

## Build

```sh
cd plugins/vscode
pnpm install
pnpm test             # typecheck + unit tests
pnpm package          # visual-app-editor-<version>.vsix
VAE_SERVICE_TEST_CMD="$(command -v dart) run $PWD/../../packages/service/bin/vae_service.dart" pnpm test:integration
```

Install from file: `code --install-extension visual-app-editor-<version>.vsix`, or **Extensions view | ··· | Install from VSIX…**. Publishing: see the docs page *Publishing the IDE plugins*.

The `publisher` in `package.json` is `devcentr`, for the Marketplace publisher *DevCentr*. Confirm the exact publisher ID at https://marketplace.visualstudio.com/manage before the first publish.
