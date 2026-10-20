import assert from 'node:assert/strict';
import path from 'node:path';
import Mocha from 'mocha';
import * as vscode from 'vscode';

export function run(): Promise<void> {
  const mocha = new Mocha({ ui: 'tdd', timeout: 180_000, color: true });
  mocha.suite.emit('pre-require', globalThis, 'suite', mocha);
  const g = globalThis as unknown as { suite: Mocha.SuiteFunction; test: Mocha.TestFunction };

  g.suite('Visual App Editor extension', () => {
    g.test('activates and contributes its commands', async () => {
      const ext = vscode.extensions.getExtension('devcentr.visual-app-editor');
      assert.ok(ext, 'extension present');
      await ext.activate();
      const cmds = await vscode.commands.getCommands(true);
      for (const c of ['visualAppEditor.refresh', 'visualAppEditor.delete', 'visualAppEditor.wrap', 'visualAppEditor.selectPage']) assert.ok(cmds.includes(c), c);
    });

    g.test('edits a Dart page through the service with one undo step', async function () {
      const cmd = process.env.VAE_SERVICE_TEST_CMD;
      if (!cmd) return this.skip();
      await vscode.workspace.getConfiguration('visualAppEditor').update('serviceCommand', cmd, vscode.ConfigurationTarget.Global);
      const ext = vscode.extensions.getExtension<{ service: import('../../src/service').ServiceManager }>('devcentr.visual-app-editor')!;
      const api = await ext.activate();
      const file = vscode.Uri.file(path.join(process.env.VAE_TEST_WORKSPACE!, 'lib/pages/home_page.dart'));
      const doc = await vscode.workspace.openTextDocument(file);
      await vscode.window.showTextDocument(doc);
      // Unsaved buffer change must reach the service before the edit.
      const ed = vscode.window.activeTextEditor!;
      const idx = doc.getText().indexOf('Good morning');
      await ed.edit((b) => b.replace(new vscode.Range(doc.positionAt(idx), doc.positionAt(idx + 12)), 'Good evening'));
      const before = doc.getText();
      await api.service.load(file, 'HomePage');
      assert.equal(api.service.state.error, undefined, api.service.state.error);
      const root = api.service.state.root!;
      assert.equal(root.type, 'Scaffold');
      assert.ok(api.service.state.presets.some((p) => p.mode === 'web'));
      assert.ok(await api.service.edit('Set backgroundColor', { op: 'setArgument', path: root.path, name: 'backgroundColor', value: 'Colors.amber' }), api.service.state.error);
      assert.ok(doc.getText().includes('backgroundColor: Colors.amber'));
      assert.ok(doc.getText().includes('Good evening'));
      await vscode.commands.executeCommand('undo');
      assert.equal(doc.getText(), before);
      assert.equal(await api.service.edit('Delete root', { op: 'removeNode', path: root.path }), false);
      assert.match(api.service.state.error ?? '', /rejected|root|Cannot/i);
    });
  });

  return new Promise((resolve, reject) => mocha.run((f) => (f ? reject(new Error(`${f} tests failed`)) : resolve())));
}
