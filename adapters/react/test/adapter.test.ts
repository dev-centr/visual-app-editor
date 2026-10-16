import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { describe, expect, it } from 'vitest';
import { applyEdit, Decoder, encode, handle, loadToolkit, pagesOf } from '../src/index.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const file = 'Home.tsx';
const src = fs.readFileSync(path.join(here, 'fixtures', file), 'utf8').replace(/\r\n/g, '\n');

describe('parse', () => {
  it('finds components and builds the tree', () => {
    const pages = pagesOf(file, src);
    expect(pages.map((p) => p.name)).toEqual(['Home', 'Card']);
    const root = pages[0].root!;
    expect(root.type).toBe('View');
    expect(root.args[0]).toEqual({ name: 'style', source: '{{ padding: 16 }}' });
    expect(root.children.map((c) => c.type)).toEqual(['Text', 'Button']);
    expect(root.children[0].text).toBe('Hello');
    expect(src.slice(root.children[1].offset, root.children[1].end)).toBe('<Button title="Go" onPress={() => {}} />');
  });
});

describe('edits round-trip', () => {
  const tree = (s: string, page = 'Home') => pagesOf(file, s).find((p) => p.name === page)!.root!;

  it('sets an existing and a new prop', () => {
    let s = applyEdit(file, src, 'Home', { op: 'setArgument', path: [1], name: 'title', value: "'Next'" });
    expect(s).toContain('<Button title="Next" onPress={() => {}} />');
    s = applyEdit(file, s, 'Home', { op: 'setArgument', path: [1], name: 'color', value: '"red"' });
    expect(tree(s).children[1].args.map((a) => a.name)).toEqual(['title', 'onPress', 'color']);
    s = applyEdit(file, s, 'Home', { op: 'setArgument', path: [0], name: 'numberOfLines', value: '2' });
    expect(s).toContain('<Text numberOfLines={2}>Hello</Text>');
    s = applyEdit(file, s, 'Home', { op: 'removeArgument', path: [1], name: 'color' });
    expect(s).not.toContain('color');
  });

  it('sets text', () => {
    const s = applyEdit(file, src, 'Home', { op: 'setText', path: [0], value: "'Hi there'" });
    expect(tree(s).children[0].text).toBe('Hi there');
  });

  it('inserts, moves and removes children', () => {
    let s = applyEdit(file, src, 'Home', { op: 'insertChild', path: [], snippet: '<Text>Added</Text>' });
    expect(tree(s).children.map((c) => c.text ?? c.type)).toEqual(['Hello', 'Button', 'Added']);
    expect(s).toContain('      <Text>Added</Text>\n    </View>');
    s = applyEdit(file, s, 'Home', { op: 'moveInList', path: [2], delta: -1 });
    s = applyEdit(file, s, 'Home', { op: 'moveInList', path: [1], delta: -1 });
    expect(tree(s).children.map((c) => c.text ?? c.type)).toEqual(['Added', 'Hello', 'Button']);
    s = applyEdit(file, s, 'Home', { op: 'removeNode', path: [0] });
    expect(s).toBe(src);
  });

  it('inserts into a self-closing element and wraps', () => {
    let s = applyEdit(file, src, 'Home', { op: 'wrapNode', path: [0], wrapper: 'Pressable', slot: 'children' });
    expect(tree(s).children[0].type).toBe('Pressable');
    expect(tree(s).children[0].children[0].text).toBe('Hello');
    s = applyEdit(file, src, 'Card', { op: 'insertChild', path: [], snippet: '<p>Body</p>' });
    expect(tree(s, 'Card').children.map((c) => c.type)).toEqual(['h2', 'p']);
  });

  it('rejects edits that break the file', () => {
    expect(() => applyEdit(file, src, 'Home', { op: 'insertChild', path: [], snippet: '<Text>' })).toThrow(/break/);
  });
});

describe('line endings', () => {
  it('keeps CRLF files CRLF', () => {
    const crlf = src.replace(/\r?\n/g, '\r\n');
    const s = applyEdit(file, crlf, 'Home', { op: 'insertChild', path: [], snippet: '<Text>Added</Text>' });
    expect(s.replace(/\r\n/g, '')).not.toContain('\n');
    expect(pagesOf(file, s)[0].root!.children.length).toBe(3);
  });
});

describe('toolkits', () => {
  it('serves builtin catalogs', () => {
    const rn = loadToolkit({ id: 'react-native', name: 'RN', package: 'react-native', import: 'react-native', adapter: 'react' });
    expect(rn.widgets.map((w) => w.class)).toContain('View');
    const dom = loadToolkit({ id: 'html', name: 'HTML', package: 'react-dom', import: 'react-dom', adapter: 'react' });
    expect(dom.widgets.find((w) => w.class === 'img')!.params.filter((p) => p.required).map((p) => p.name)).toEqual(['src', 'alt']);
  });

  it('introspects a package with the type checker', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'vae-react-'));
    const pkg = path.join(root, 'node_modules', 'demo-ui');
    fs.mkdirSync(pkg, { recursive: true });
    fs.writeFileSync(path.join(pkg, 'package.json'), JSON.stringify({ name: 'demo-ui', types: 'index.d.ts' }));
    fs.writeFileSync(path.join(pkg, 'index.d.ts'), '/** A badge. */\nexport declare function Badge(props: { label: string; tone?: "info" | "warn"; children?: unknown }): unknown;\nexport declare const helper: number;\n');
    const r = loadToolkit({ id: 'demo', name: 'Demo', package: 'demo-ui', import: 'demo-ui', adapter: 'react' }, root);
    expect(r.source).toBe('introspected');
    expect(r.widgets).toEqual([{ class: 'Badge', toolkit: 'demo', category: 'Components', doc: 'A badge.', params: [
      { name: 'label', type: 'string', named: true, required: true },
      { name: 'tone', type: '"info" | "warn"', named: true, required: false },
    ] }]);
  });
});

describe('rpc', () => {
  it('handles adapter methods in process', () => {
    const r = handle({ jsonrpc: '2.0', id: 1, method: 'adapter/applyEdit', params: { path: file, source: src, page: 'Nope', op: { op: 'removeNode', path: [0] } } }) as { error: { code: number } };
    expect(r.error.code).toBe(-32020);
  });

  it('speaks framed JSON-RPC over stdio', async () => {
    const child = spawn(process.execPath, [path.join(here, '..', 'dist', 'cli.js')], { stdio: ['pipe', 'pipe', 'inherit'] });
    const dec = new Decoder();
    const got = new Promise<any>((resolve) => child.stdout.on('data', (c: Buffer) => { const m = dec.push(c); if (m.length) resolve(m[0]); }));
    child.stdin.write(encode({ jsonrpc: '2.0', id: 7, method: 'adapter/pages', params: { path: file, source: src } }));
    const res = await got;
    child.kill();
    expect(res.id).toBe(7);
    expect(res.result.map((p: any) => p.name)).toEqual(['Home', 'Card']);
  });
});
