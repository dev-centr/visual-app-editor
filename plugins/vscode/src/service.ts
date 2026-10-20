import { spawn, type ChildProcess } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import * as vscode from 'vscode';
import { argvFor, autodetectService } from './command';
import { minimalChange, type DevicePreset, type TreeNode, type WidgetSpec } from './model';
import { RpcClient, RpcError } from './rpc';

export interface ViewState {
  uri?: vscode.Uri;
  rel?: string;
  jsx: boolean;
  pages: string[];
  page?: string;
  root?: TreeNode;
  palette: WidgetSpec[];
  presets: DevicePreset[];
  device?: string;
  selected?: number[];
  status: string;
  error?: string;
}

const SUPPORTED = /\.(dart|tsx|jsx)$/i;

/** Owns the vae_service child process and keeps it in sync with VS Code documents. */
export class ServiceManager implements vscode.Disposable {
  private proc?: ChildProcess;
  private rpc?: RpcClient;
  private openRoot?: string;
  private stderr = '';
  private starting?: Promise<void>;
  private readonly emitter = new vscode.EventEmitter<ViewState>();
  readonly onDidChange = this.emitter.event;
  state: ViewState = { jsx: false, pages: [], palette: [], presets: [], status: 'Open a .dart, .tsx or .jsx file' };

  constructor(private readonly output: vscode.OutputChannel) {}

  private publish(patch: Partial<ViewState>) {
    this.state = { ...this.state, ...patch };
    this.emitter.fire(this.state);
  }

  private errorText(e: unknown): string {
    const msg = e instanceof Error ? e.message : String(e);
    return this.rpc?.closed && this.stderr.trim() ? `${msg}\n${this.stderr.trim().slice(-800)}` : msg;
  }

  private async call<T = unknown>(method: string, params: Record<string, unknown> = {}): Promise<T> {
    if (!this.rpc) throw new Error('Service not running');
    return this.rpc.request<T>(method, params);
  }

  private async ensureService(cwd: string) {
    if (this.rpc && !this.rpc.closed && this.proc && this.proc.exitCode === null) return;
    if (this.starting) return this.starting;
    this.starting = this.start(cwd).finally(() => (this.starting = undefined));
    return this.starting;
  }

  private async start(cwd: string) {
    this.stop();
    const cfg = vscode.workspace.getConfiguration('visualAppEditor');
    const folders = (vscode.workspace.workspaceFolders ?? []).map((f) => f.uri.fsPath);
    const cmd = (cfg.get<string>('serviceCommand') ?? '').trim() || autodetectService(folders);
    if (!cmd) throw new Error('No Visual App Editor service configured. Set "visualAppEditor.serviceCommand" (a vae_service executable or `dart run <repo>/packages/service/bin/vae_service.dart`).');
    const argv = argvFor(cmd);
    this.output.appendLine(`Starting ${argv.join(' ')}`);
    this.publish({ status: `Starting service…`, error: undefined });
    const p = spawn(argv[0], argv.slice(1), { cwd, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
    this.proc = p;
    this.stderr = '';
    p.stderr!.on('data', (d: Buffer) => {
      const s = d.toString('utf8');
      this.stderr = (this.stderr + s).slice(-4000);
      this.output.append(s);
    });
    const spawnError = new Promise<never>((_, reject) => p.on('error', (e) => reject(new Error(`Could not start the service (${argv.join(' ')}): ${e.message}`))));
    this.rpc = new RpcClient(p.stdout!, p.stdin!, (m, params) => this.onNotification(m, params));
    p.on('exit', (code) => this.rpc?.fail(`Service exited with code ${code}`));
    await Promise.race([this.call('initialize', this.initializeParams()), spawnError]);
    this.openRoot = undefined;
  }

  private initializeParams(): Record<string, unknown> {
    const react = (vscode.workspace.getConfiguration('visualAppEditor').get<string>('reactAdapterCommand') ?? '').trim();
    const out: Record<string, unknown> = { clientName: 'vscode' };
    if (react) {
      const argv = argvFor(react);
      out.externalAdapters = [{ id: 'react', extensions: ['.tsx', '.jsx'], command: argv }];
      const cli = [...argv].reverse().find((a) => a.endsWith('.js'));
      const kits = cli && path.join(path.dirname(path.dirname(cli)), 'toolkits');
      if (kits && fs.existsSync(kits)) out.manifests = fs.readdirSync(kits).filter((f) => f.endsWith('.sdl')).map((f) => fs.readFileSync(path.join(kits, f), 'utf8'));
    }
    return out;
  }

  private onNotification(method: string, params: Record<string, unknown>) {
    if (method === 'window/logMessage') {
      this.output.appendLine(String(params.message));
      if (params.type === 'error') void vscode.window.showErrorMessage(`Visual App Editor: ${params.message}`);
    }
  }

  stop() {
    const rpc = this.rpc;
    const p = this.proc;
    this.rpc = undefined;
    this.proc = undefined;
    this.openRoot = undefined;
    if (rpc && !rpc.closed) {
      rpc.request('shutdown').catch(() => {});
      setTimeout(() => p?.kill(), 1500);
    } else p?.kill();
  }

  async restart() {
    this.stop();
    if (this.state.uri) await this.load(this.state.uri);
  }

  dispose() {
    this.stop();
    this.emitter.dispose();
  }

  private projectRoot(file: string): string | undefined {
    let d = path.dirname(file);
    for (;;) {
      if (fs.existsSync(path.join(d, 'pubspec.yaml')) || fs.existsSync(path.join(d, 'package.json'))) return d;
      const up = path.dirname(d);
      if (up === d) return undefined;
      d = up;
    }
  }

  private async text(uri: vscode.Uri): Promise<{ doc: vscode.TextDocument; text: string }> {
    const doc = await vscode.workspace.openTextDocument(uri);
    return { doc, text: doc.getText() };
  }

  /** Loads (or reloads) the tree for a file. Errors are shown in the views, not thrown. */
  async load(uri: vscode.Uri | undefined, page?: string): Promise<void> {
    if (!uri || uri.scheme !== 'file' || !SUPPORTED.test(uri.fsPath)) {
      if (!this.state.uri) this.publish({ status: 'Open a .dart, .tsx or .jsx file' });
      return;
    }
    try {
      const root = this.projectRoot(uri.fsPath);
      if (!root) return this.publish({ uri, root: undefined, pages: [], status: 'No pubspec.yaml or package.json above this file', error: undefined });
      await this.ensureService(root);
      let { palette, presets, device } = this.state;
      if (this.openRoot !== root) {
        const open = await this.call<{ config?: { device?: string } }>('project/open', { root });
        this.openRoot = root;
        palette = await this.call<WidgetSpec[]>('toolkit/palette');
        presets = await this.call<DevicePreset[]>('device/presets');
        device = open.config?.device ?? device;
      }
      const rel = path.relative(root, uri.fsPath).split(path.sep).join('/');
      const { text } = await this.text(uri);
      const synced = await this.call<{ pages: { name: string }[] }>('document/sync', { file: rel, source: text });
      const pages = synced.pages.map((p) => p.name);
      const sameFile = this.state.uri?.toString() === uri.toString();
      const pg = (page && pages.includes(page) ? page : undefined) ?? (sameFile && this.state.page && pages.includes(this.state.page) ? this.state.page : undefined) ?? pages[0];
      const tree = pg ? (await this.call<{ root?: TreeNode }>('document/tree', { file: rel, page: pg })).root : undefined;
      this.publish({
        uri, rel, jsx: /\.(tsx|jsx)$/i.test(rel), pages, page: pg, root: tree, palette, presets, device,
        selected: sameFile ? this.state.selected : tree?.path,
        status: pg ? `${pg} · ${path.basename(rel)}` : `No pages in ${path.basename(rel)}`, error: undefined,
      });
    } catch (e) {
      this.publish({ uri, error: this.errorText(e), status: 'Error' });
    }
  }

  select(path: number[] | undefined) {
    this.publish({ selected: path });
  }

  /** Runs one edit op for the current page and applies the result as a WorkspaceEdit (one undo step). */
  async edit(label: string, op: Record<string, unknown>): Promise<boolean> {
    const { uri, rel, page } = this.state;
    if (!uri || !rel || !page) return false;
    try {
      const { doc, text } = await this.text(uri);
      await this.call('document/sync', { file: rel, source: text });
      const r = await this.call<{ source: string; page?: { root?: TreeNode } }>('document/edit', { file: rel, page, op });
      const c = minimalChange(text, r.source);
      if (c) {
        if (doc.getText() !== text) throw new Error(`${path.basename(rel)} changed while editing; try again`);
        const we = new vscode.WorkspaceEdit();
        we.replace(uri, new vscode.Range(doc.positionAt(c.start), doc.positionAt(c.end)), c.text, { label: `Visual App Editor: ${label}`, needsConfirmation: false });
        if (!(await vscode.workspace.applyEdit(we))) throw new Error('VS Code refused the edit');
      }
      this.publish({ root: r.page?.root ?? this.state.root, status: `${label} · ${path.basename(rel)}`, error: undefined });
      return true;
    } catch (e) {
      const msg = e instanceof RpcError && e.code === -32020 ? `Edit rejected: ${e.message}` : this.errorText(e);
      this.publish({ error: msg });
      return false;
    }
  }

  async setDevice(id: string) {
    this.publish({ device: id });
    // Persisted in the project's visual_app_editor.sdl so the desktop app agrees.
    if (this.openRoot) await this.call('project/setConfig', { device: id }).catch(() => {});
  }
}
