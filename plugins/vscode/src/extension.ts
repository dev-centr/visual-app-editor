import * as vscode from 'vscode';
import { InspectorProvider } from './inspector';
import { findNode, type TreeNode } from './model';
import { ServiceManager } from './service';
import { WidgetTreeProvider } from './treeView';

export interface Api {
  service: ServiceManager;
}

export function activate(context: vscode.ExtensionContext): Api {
  const output = vscode.window.createOutputChannel('Visual App Editor');
  const svc = new ServiceManager(output);
  const treeProvider = new WidgetTreeProvider(svc);
  const tree = vscode.window.createTreeView('visualAppEditor.tree', { treeDataProvider: treeProvider, showCollapseAll: true });
  const updateMessage = () => (tree.message = svc.state.error ? `⚠ ${svc.state.error}` : svc.state.root ? undefined : svc.state.status);
  svc.onDidChange(updateMessage);
  updateMessage();
  tree.onDidChangeSelection((e) => e.selection[0] && svc.select(e.selection[0].path));

  const current = (n?: TreeNode) => n ?? findNode(svc.state.root, svc.state.selected ?? []);
  const reload = () => svc.load(vscode.window.activeTextEditor?.document.uri ?? svc.state.uri);

  context.subscriptions.push(
    output,
    svc,
    tree,
    vscode.window.registerWebviewViewProvider('visualAppEditor.inspector', new InspectorProvider(svc)),
    vscode.window.onDidChangeActiveTextEditor((ed) => ed && svc.load(ed.document.uri)),
    vscode.workspace.onDidSaveTextDocument((d) => d.uri.toString() === svc.state.uri?.toString() && svc.load(d.uri)),
    vscode.workspace.onDidChangeConfiguration((e) => e.affectsConfiguration('visualAppEditor') && svc.restart()),
    vscode.commands.registerCommand('visualAppEditor.select', (n: TreeNode) => svc.select(n.path)),
    vscode.commands.registerCommand('visualAppEditor.refresh', reload),
    vscode.commands.registerCommand('visualAppEditor.restartService', () => svc.restart()),
    vscode.commands.registerCommand('visualAppEditor.selectPage', async () => {
      const pick = await vscode.window.showQuickPick(svc.state.pages, { placeHolder: 'Page (widget / component) to edit' });
      if (pick && svc.state.uri) await svc.load(svc.state.uri, pick);
    }),
    vscode.commands.registerCommand('visualAppEditor.delete', (n?: TreeNode) => {
      const t = current(n);
      return t && svc.edit('Delete', { op: 'removeNode', path: t.path });
    }),
    vscode.commands.registerCommand('visualAppEditor.moveUp', (n?: TreeNode) => {
      const t = current(n);
      return t && svc.edit('Move up', { op: 'moveInList', path: t.path, delta: -1 });
    }),
    vscode.commands.registerCommand('visualAppEditor.moveDown', (n?: TreeNode) => {
      const t = current(n);
      return t && svc.edit('Move down', { op: 'moveInList', path: t.path, delta: 1 });
    }),
    vscode.commands.registerCommand('visualAppEditor.wrap', async (n?: TreeNode) => {
      const t = current(n);
      if (!t) return;
      const jsx = svc.state.jsx;
      const w = await vscode.window.showInputBox({ prompt: 'Wrap the selection with', value: jsx ? 'div' : 'Padding' });
      if (!w) return;
      const multi = jsx || ['Column', 'Row', 'Stack', 'ListView', 'Wrap'].includes(w);
      return svc.edit('Wrap', { op: 'wrapNode', path: t.path, wrapper: w, slot: multi ? 'children' : 'child', extraArgs: !jsx && w === 'Padding' ? 'padding: const EdgeInsets.all(8)' : '' });
    }),
    vscode.commands.registerCommand('visualAppEditor.reveal', async (n?: TreeNode) => {
      const t = current(n);
      if (!t || !svc.state.uri) return;
      const doc = await vscode.workspace.openTextDocument(svc.state.uri);
      const ed = await vscode.window.showTextDocument(doc);
      const p = doc.positionAt(t.offset);
      ed.selection = new vscode.Selection(p, p);
      ed.revealRange(new vscode.Range(p, p));
    }),
  );
  void reload();
  return { service: svc };
}

export function deactivate() {}
