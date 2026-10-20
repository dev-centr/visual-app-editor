import { PassThrough } from 'node:stream';
import { describe, expect, it } from 'vitest';
import { argvFor, splitCommand } from '../../src/command';
import { CONTENT, findNode, label, minimalChange, propEdit, propRows, snippetFor, type TreeNode, type WidgetSpec } from '../../src/model';
import { Decoder, encode, RpcClient, RpcError } from '../../src/rpc';

const node: TreeNode = {
  type: 'Container', path: [0], args: [{ name: 'color', source: 'Colors.red' }, { name: 'extra', source: '1' }],
  children: [{ type: 'Text', path: [0, 0], slot: 'child', args: [{ source: "'Hi'" }], children: [], offset: 0, end: 0 }], offset: 0, end: 10,
};
const spec: WidgetSpec = { class: 'Container', toolkit: 'widgets', params: [{ name: 'color', type: 'Color?' }, { name: 'padding', type: 'EdgeInsetsGeometry?', default: 'null' }] };

describe('model', () => {
  it('finds nodes by their own path and labels them', () => {
    expect(findNode(node, [0, 0])?.type).toBe('Text');
    expect(findNode(node, [])).toBeUndefined();
    expect(label(node.children[0])).toBe('child: Text "Hi"');
  });

  it('leaves unset properties blank (never the type name)', () => {
    const rows = propRows(node, spec, false);
    expect(rows.map((r) => [r.name, r.value])).toEqual([['color', 'Colors.red'], ['padding', ''], ['extra', '1']]);
    const text = propRows(node.children[0], undefined, false);
    expect(text[0]).toMatchObject({ name: CONTENT, value: "'Hi'", content: true });
  });

  it('maps property edits to ops', () => {
    const [color, padding] = propRows(node, spec, false);
    expect(propEdit(color, 'Colors.blue', [0], false)).toEqual({ op: 'setArgument', path: [0], name: 'color', value: 'Colors.blue' });
    expect(propEdit(color, '', [0], false)).toEqual({ op: 'removeArgument', path: [0], name: 'color' });
    expect(propEdit(padding, '', [0], false)).toBeUndefined();
    const [content] = propRows(node.children[0], undefined, true);
    expect(propEdit(content, 'Yo', [0, 0], true)).toEqual({ op: 'setText', path: [0, 0], value: 'Yo' });
    expect(snippetFor({ class: 'View', toolkit: 'rn', params: [] }, true)).toBe('<View />');
  });

  it('computes minimal changes', () => {
    const a = "Text('a'),\nText('b'),\n";
    const b = "Text('a'),\nText('B'),\n";
    expect(minimalChange(a, b)).toEqual({ start: 17, end: 18, text: 'B' });
    expect(minimalChange(a, a)).toBeUndefined();
    for (const [x, y] of [['', 'abc'], ['abc', ''], ['aaa', 'aaaa']]) {
      const c = minimalChange(x, y)!;
      expect(x.slice(0, c.start) + c.text + x.slice(c.end)).toBe(y);
    }
  });
});

describe('command', () => {
  it('splits quoted commands', () => {
    expect(splitCommand('"C:\\Program Files\\dart.exe" run "a b.dart"')).toEqual(['C:\\Program Files\\dart.exe', 'run', 'a b.dart']);
    expect(argvFor('node cli.js', false)[1]).toBe('cli.js');
  });
});

describe('rpc', () => {
  it('frames requests and resolves responses, errors and notifications', async () => {
    const fromServer = new PassThrough();
    const toServer = new PassThrough();
    const notes: string[] = [];
    const c = new RpcClient(fromServer, toServer, (m) => notes.push(m));
    const sent: unknown[] = [];
    const dec = new Decoder();
    toServer.on('data', (d: Buffer) => sent.push(...dec.push(d)));
    const a = c.request('initialize');
    const b = c.request('document/edit');
    fromServer.write(encode({ jsonrpc: '2.0', method: 'document/changed', params: { file: 'x' } }));
    fromServer.write(encode({ jsonrpc: '2.0', id: 2, error: { code: -32020, message: 'no' } }));
    fromServer.write(encode({ jsonrpc: '2.0', id: 1, result: { ok: 'ü' } }));
    await expect(a).resolves.toEqual({ ok: 'ü' });
    await expect(b).rejects.toMatchObject({ code: -32020 });
    expect(notes).toEqual(['document/changed']);
    expect(sent[0]).toMatchObject({ method: 'initialize', id: 1 });
    const pending = c.request('project/pages');
    fromServer.destroy();
    await expect(pending).rejects.toBeInstanceOf(RpcError);
  });
});
