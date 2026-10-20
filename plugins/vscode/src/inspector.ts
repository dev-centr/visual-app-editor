import * as vscode from 'vscode';
import { findNode, propEdit, propRows, snippetFor } from './model';
import type { ServiceManager } from './service';

/** Webview with the device switcher, properties of the selected widget, and the toolbox. */
export class InspectorProvider implements vscode.WebviewViewProvider {
  private view?: vscode.WebviewView;

  constructor(private readonly svc: ServiceManager) {
    svc.onDidChange(() => this.post());
  }

  resolveWebviewView(view: vscode.WebviewView): void {
    this.view = view;
    view.webview.options = { enableScripts: true };
    view.webview.html = html(nonce());
    view.webview.onDidReceiveMessage((m) => this.onMessage(m));
    view.onDidChangeVisibility(() => this.post());
    this.post();
  }

  private selectedNode() {
    const s = this.svc.state;
    return findNode(s.root, s.selected ?? s.root?.path ?? []);
  }

  private post() {
    const s = this.svc.state;
    const n = this.selectedNode();
    const spec = n && s.palette.find((w) => w.class === n.type.split('.')[0]);
    void this.view?.webview.postMessage({
      type: 'state',
      status: s.status,
      error: s.error,
      device: s.device,
      presets: s.presets,
      node: n ? { type: n.type, path: n.path } : undefined,
      doc: spec?.doc,
      rows: n ? propRows(n, spec, s.jsx) : [],
      palette: s.palette.map((w) => ({ class: w.class, category: w.category ?? 'Other' })),
    });
  }

  private async onMessage(m: { type: string; [k: string]: unknown }) {
    const s = this.svc.state;
    const n = this.selectedNode();
    switch (m.type) {
      case 'ready':
        return this.post();
      case 'device':
        return this.svc.setDevice(String(m.id));
      case 'prop': {
        if (!n) return;
        const spec = s.palette.find((w) => w.class === n.type.split('.')[0]);
        const row = propRows(n, spec, s.jsx).find((r) => r.name === m.name);
        const op = row && propEdit(row, String(m.value), n.path, s.jsx);
        if (op) await this.svc.edit(`Set ${row!.name}`, op);
        return;
      }
      case 'insert': {
        const spec = s.palette.find((w) => w.class === m.class);
        const target = n ?? s.root;
        if (spec && target) await this.svc.edit(`Insert ${spec.class}`, { op: 'insertChild', path: target.path, snippet: snippetFor(spec, s.jsx) });
        return;
      }
    }
  }
}

function nonce() {
  let t = '';
  const c = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  for (let i = 0; i < 32; i++) t += c.charAt(Math.floor(Math.random() * c.length));
  return t;
}

function html(n: string): string {
  return `<!DOCTYPE html><html><head><meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${n}';">
<style>
 body{font-family:var(--vscode-font-family);font-size:var(--vscode-font-size);color:var(--vscode-foreground);padding:4px 8px}
 h3{font-size:11px;text-transform:uppercase;opacity:.75;margin:12px 0 4px}
 .modes button{background:none;border:1px solid var(--vscode-panel-border);color:inherit;padding:2px 8px;cursor:pointer}
 .modes button.on{background:var(--vscode-button-background);color:var(--vscode-button-foreground)}
 select,input{width:100%;box-sizing:border-box;background:var(--vscode-input-background);color:var(--vscode-input-foreground);border:1px solid var(--vscode-input-border,transparent);padding:2px 4px;font-family:var(--vscode-editor-font-family)}
 .row{margin:4px 0}.row label{display:flex;justify-content:space-between;font-size:11px}.row label span{opacity:.6;margin-left:6px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
 .req{color:var(--vscode-errorForeground)}
 .err{color:var(--vscode-errorForeground);white-space:pre-wrap}
 .kit div{cursor:pointer;padding:1px 4px}.kit div:hover{background:var(--vscode-list-hoverBackground)}.kit small{opacity:.6}
 .muted{opacity:.7}
</style></head><body>
<div id="status" class="muted"></div><div id="err" class="err"></div>
<h3>Device</h3>
<div class="modes" id="modes"></div><select id="preset"></select>
<h3 id="ptitle">Properties</h3><div id="doc" class="muted"></div><div id="props"></div>
<h3>Toolbox</h3><input id="q" placeholder="Search widgets"><div class="kit" id="kit"></div>
<script nonce="${n}">
const vs = acquireVsCodeApi();
let st = {presets:[],rows:[],palette:[]}; let mode = 'phone';
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
function render(){
  $('status').textContent = st.status || ''; $('err').textContent = st.error || '';
  const cur = st.presets.find(p => p.id === st.device); if (cur) mode = cur.mode;
  $('modes').innerHTML = ['phone','tablet','desktop','web'].map(m => '<button data-mode="'+m+'" class="'+(m===mode?'on':'')+'">'+m+'</button>').join(' ');
  const list = st.presets.filter(p => p.mode === mode);
  $('preset').innerHTML = list.map(p => '<option value="'+esc(p.id)+'"'+(p.id===st.device?' selected':'')+'>'+esc(p.label)+'  '+p.width+'x'+p.height+'</option>').join('');
  $('ptitle').textContent = st.node ? 'Properties · ' + st.node.type : 'Properties';
  $('doc').textContent = st.doc || '';
  $('props').innerHTML = st.rows.map((r,i) => '<div class="row"><label><b>'+esc(r.name)+(r.required?' <i class="req">*</i>':'')+'</b><span>'+esc(r.type)+'</span></label>'
    + '<input data-i="'+i+'" value="'+esc(r.value)+'" placeholder="'+esc(r.default != null ? 'default: '+r.default : '')+'"></div>').join('') || '<div class="muted">Select a widget in the tree</div>';
  kit();
}
function kit(){
  const q = $('q').value.trim().toLowerCase();
  $('kit').innerHTML = st.palette.filter(w => !q || w.class.toLowerCase().includes(q) || w.category.toLowerCase().includes(q)).slice(0,300)
    .map(w => '<div data-class="'+esc(w.class)+'" title="Insert into the selected widget">'+esc(w.class)+' <small>'+esc(w.category)+'</small></div>').join('');
}
$('modes').addEventListener('click', e => { const m = e.target.dataset && e.target.dataset.mode; if (!m) return; mode = m; const p = st.presets.find(x => x.mode === m); if (p) vs.postMessage({type:'device', id:p.id}); render(); });
$('preset').addEventListener('change', e => vs.postMessage({type:'device', id:e.target.value}));
$('props').addEventListener('change', e => { const i = e.target.dataset.i; if (i === undefined) return; vs.postMessage({type:'prop', name: st.rows[+i].name, value: e.target.value}); });
$('q').addEventListener('input', kit);
$('kit').addEventListener('dblclick', e => { const d = e.target.closest('[data-class]'); if (d) vs.postMessage({type:'insert', class: d.dataset.class}); });
window.addEventListener('message', e => { if (e.data.type === 'state') { st = e.data; render(); } });
vs.postMessage({type:'ready'});
</script></body></html>`;
}
