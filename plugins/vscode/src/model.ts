// Mirrors vae_core JSON (TreeNode, WidgetSpec, DevicePreset) and pure helpers shared by the views.

export interface Arg { name?: string; source: string }
export interface TreeNode {
  type: string;
  path: number[];
  slot?: string;
  args: Arg[];
  children: TreeNode[];
  offset: number;
  end: number;
  text?: string;
}
export interface Param { name: string; type: string; named?: boolean; required?: boolean; default?: string }
export interface WidgetSpec { class: string; toolkit: string; category?: string; params: Param[]; snippet?: string; doc?: string }
export interface DevicePreset { id: string; label: string; mode: 'phone' | 'tablet' | 'desktop' | 'web'; width: number; height: number }

export interface PropRow { name: string; type: string; required: boolean; default?: string; value: string; content?: boolean }

export const CONTENT = '(content)';

export function samePath(a: number[], b: number[]): boolean {
  return a.length === b.length && a.every((x, i) => x === b[i]);
}

/** Finds a node by its own path (adapters number the root differently: [] for JSX, [0] for Dart). */
export function findNode(root: TreeNode | undefined, path: number[]): TreeNode | undefined {
  if (!root) return undefined;
  if (samePath(root.path, path)) return root;
  for (const c of root.children) {
    const f = findNode(c, path);
    if (f) return f;
  }
  return undefined;
}

export function parentOf(root: TreeNode | undefined, n: TreeNode): TreeNode | undefined {
  if (!root) return undefined;
  for (const c of root.children) {
    if (c === n || samePath(c.path, n.path)) return root;
    const p = parentOf(c, n);
    if (p) return p;
  }
  return undefined;
}

export function label(n: TreeNode): string {
  const head = n.slot && n.slot !== 'children' ? `${n.slot}: ${n.type}` : n.type;
  const t = n.text?.trim();
  if (t) return `${head} "${t.slice(0, 40)}"`;
  const first = n.args.find((a) => a.name === undefined || a.name === null)?.source;
  if (first && first.length >= 2 && /^['"]/.test(first)) return `${head} "${first.slice(1, -1).slice(0, 40)}"`;
  return head;
}

/** Property rows: every named parameter of the spec (blank value when unset, never the type name) plus extra args. */
export function propRows(n: TreeNode, spec: WidgetSpec | undefined, jsx: boolean): PropRow[] {
  const rows: PropRow[] = [];
  const content = n.text ?? n.args.find((a) => a.name == null)?.source;
  if (content !== undefined || n.type === 'Text') rows.push({ name: CONTENT, type: jsx ? 'text' : 'positional 0', required: false, value: content ?? '', content: true });
  const seen = new Set<string>();
  for (const p of spec?.params ?? []) {
    if (p.named === false) continue;
    rows.push({ name: p.name, type: p.type, required: !!p.required, default: p.default ?? undefined, value: n.args.find((a) => a.name === p.name)?.source ?? '' });
    seen.add(p.name);
  }
  for (const a of n.args) if (a.name != null && !seen.has(a.name)) rows.push({ name: a.name, type: '', required: false, value: a.source });
  return rows;
}

/** The edit op for a property change; undefined when nothing changes. */
export function propEdit(row: PropRow, value: string, path: number[], jsx: boolean): Record<string, unknown> | undefined {
  const v = value.trim();
  if (row.content) return jsx ? { op: 'setText', path, value: v } : { op: 'setPositional', path, index: 0, value: v };
  if (v === row.value) return undefined;
  if (v === '') return row.value ? { op: 'removeArgument', path, name: row.name } : undefined;
  return { op: 'setArgument', path, name: row.name, value: v };
}

export function snippetFor(spec: WidgetSpec, jsx: boolean): string {
  return spec.snippet ?? (jsx ? `<${spec.class} />` : `${spec.class}()`);
}

/** Smallest single replacement turning `a` into `b`. */
export function minimalChange(a: string, b: string): { start: number; end: number; text: string } | undefined {
  if (a === b) return undefined;
  let p = 0;
  const max = Math.min(a.length, b.length);
  while (p < max && a.charCodeAt(p) === b.charCodeAt(p)) p++;
  let ea = a.length;
  let eb = b.length;
  while (ea > p && eb > p && a.charCodeAt(ea - 1) === b.charCodeAt(eb - 1)) {
    ea--;
    eb--;
  }
  return { start: p, end: ea, text: b.slice(p, eb) };
}
