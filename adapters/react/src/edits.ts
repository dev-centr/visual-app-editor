import ts from 'typescript';
import { SourceEditError, type EditOp } from './model.js';
import { attributesOf, findComponents, isJsxNode, jsxChildren, nodeAt, parseSource, tagName, type JsxNode } from './parse.js';

interface Patch { start: number; end: number; text: string }

const apply = (src: string, p: Patch) => src.slice(0, p.start) + p.text + src.slice(p.end);

function indentAt(src: string, pos: number): string {
  const ls = src.lastIndexOf('\n', pos - 1) + 1;
  return /^[ \t]*/.exec(src.slice(ls))![0];
}

/** A prop value as JSX: string literals stay `"x"`, anything else becomes `{expr}`. */
export function jsxValue(v: string): string {
  const t = v.trim();
  if (t.startsWith('{') && t.endsWith('}')) return t;
  if (/^"[^"\\]*"$/.test(t)) return t;
  if (/^'[^'\\]*'$/.test(t)) return `"${t.slice(1, -1)}"`;
  return `{${t}}`;
}

function setAttr(n: JsxNode, sf: ts.SourceFile, name: string, value: string): Patch {
  const attrs = attributesOf(n);
  if (!attrs) throw new SourceEditError('Fragments take no props');
  const ex = attrs.properties.find((a): a is ts.JsxAttribute => ts.isJsxAttribute(a) && a.name.getText(sf) === name);
  const v = jsxValue(value);
  if (ex) return { start: ex.getStart(sf), end: ex.getEnd(), text: `${name}=${v}` };
  const tag = ts.isJsxElement(n) ? n.openingElement.tagName : (n as ts.JsxSelfClosingElement).tagName;
  const at = attrs.properties.length ? attrs.properties[attrs.properties.length - 1].getEnd() : tag.getEnd();
  return { start: at, end: at, text: ` ${name}=${v}` };
}

function removeAttr(n: JsxNode, sf: ts.SourceFile, name: string): Patch {
  const ex = attributesOf(n)?.properties.find((a): a is ts.JsxAttribute => ts.isJsxAttribute(a) && a.name.getText(sf) === name);
  if (!ex) throw new SourceEditError(`No prop ${name}`);
  let start = ex.getFullStart();
  return { start, end: ex.getEnd(), text: '' };
}

function escapeText(v: string): string {
  return /[{}<>]/.test(v) ? `{${JSON.stringify(v)}}` : v;
}

function setText(n: JsxNode, sf: ts.SourceFile, value: string): Patch {
  const v = value.trim().replace(/^(['"])(.*)\1$/s, '$2');
  if (ts.isJsxSelfClosingElement(n)) {
    // <X/> -> <X>text</X>
    const name = n.tagName.getText(sf);
    const head = sf.text.slice(n.getStart(sf), n.getEnd()).replace(/\s*\/>$/, '>');
    return { start: n.getStart(sf), end: n.getEnd(), text: `${head}${escapeText(v)}</${name}>` };
  }
  const textual = n.children.filter((c) => ts.isJsxText(c) && c.getText(sf).trim() !== '' || (ts.isJsxExpression(c) && c.expression && ts.isStringLiteralLike(c.expression)));
  if (textual.length) {
    const first = textual[0];
    const raw = first.getText(sf);
    const lead = ts.isJsxText(first) ? /^\s*/.exec(raw)![0] : '';
    const trail = ts.isJsxText(first) ? /\s*$/.exec(raw)![0] : '';
    return { start: first.getStart(sf), end: first.getEnd(), text: lead + escapeText(v) + trail };
  }
  const at = ts.isJsxElement(n) ? n.openingElement.getEnd() : (n as ts.JsxFragment).openingFragment.getEnd();
  return { start: at, end: at, text: escapeText(v) };
}

function insertChild(n: JsxNode, sf: ts.SourceFile, snippet: string, index?: number | null): Patch {
  const src = sf.text;
  const kids = jsxChildren(n);
  const snip = snippet.trim();
  if (ts.isJsxSelfClosingElement(n)) {
    const name = n.tagName.getText(sf);
    const ind = indentAt(src, n.getStart(sf));
    const head = src.slice(n.getStart(sf), n.getEnd()).replace(/\s*\/>$/, '>');
    return { start: n.getStart(sf), end: n.getEnd(), text: `${head}\n${ind}  ${snip}\n${ind}</${name}>` };
  }
  const closing = ts.isJsxElement(n) ? n.closingElement : (n as ts.JsxFragment).closingFragment;
  if (index != null && index < kids.length) {
    const before = kids[Math.max(0, index)];
    const ind = indentAt(src, before.getStart(sf));
    return { start: before.getStart(sf), end: before.getStart(sf), text: `${snip}\n${ind}` };
  }
  if (kids.length) {
    const last = kids[kids.length - 1];
    const ind = indentAt(src, last.getStart(sf));
    // insert after the last child's enclosing JsxExpression, if any
    const anchor = ts.isJsxExpression(last.parent) ? last.parent : findChildContainer(n, last);
    return { start: anchor.getEnd(), end: anchor.getEnd(), text: `\n${ind}${snip}` };
  }
  const ind = indentAt(src, n.getStart(sf));
  const closeStart = closing.getStart(sf);
  const between = src.slice(ts.isJsxElement(n) ? n.openingElement.getEnd() : (n as ts.JsxFragment).openingFragment.getEnd(), closeStart);
  if (between.trim() === '') {
    const st = closeStart - between.length;
    return { start: st, end: closeStart, text: `\n${ind}  ${snip}\n${ind}` };
  }
  return { start: closeStart, end: closeStart, text: `${snip}` };
}

function findChildContainer(parent: JsxNode, kid: JsxNode): ts.Node {
  let n: ts.Node = kid;
  while (n.parent && n.parent !== parent) n = n.parent;
  return n;
}

function removeNode(n: JsxNode, sf: ts.SourceFile, root: JsxNode): Patch {
  if (n === root) throw new SourceEditError('Cannot remove the component root');
  let target: ts.Node = n;
  if (n.parent && ts.isJsxExpression(n.parent)) target = n.parent;
  else if (!isJsxNode(n.parent!)) throw new SourceEditError('Only direct JSX children can be removed');
  const src = sf.text;
  let start = target.getStart(sf);
  const ls = src.lastIndexOf('\n', start - 1);
  if (src.slice(ls + 1, start).trim() === '') start = ls; // drop the whole line
  return { start, end: target.getEnd(), text: '' };
}

function wrapNode(n: JsxNode, sf: ts.SourceFile, wrapper: string, extra: string): Patch {
  const inner = sf.text.slice(n.getStart(sf), n.getEnd());
  const ind = indentAt(sf.text, n.getStart(sf));
  const attrs = extra.trim() ? ' ' + extra.trim() : '';
  const name = wrapper.trim().replace(/^</, '').replace(/\/?>$/, '').split(/\s/)[0];
  const body = inner.split('\n').map((l, i) => (i === 0 ? l : '  ' + l)).join('\n');
  return { start: n.getStart(sf), end: n.getEnd(), text: `<${name}${attrs}>\n${ind}  ${body}\n${ind}</${name}>` };
}

function moveInList(n: JsxNode, sf: ts.SourceFile, root: JsxNode, path: number[], delta: number): Patch {
  if (!path.length) throw new SourceEditError('Cannot move the root');
  const parent = nodeAt(root, path.slice(0, -1));
  const kids = jsxChildren(parent);
  const i = path[path.length - 1];
  const j = i + delta;
  if (j < 0 || j >= kids.length) throw new SourceEditError('Already at the edge');
  const a = findChildContainer(parent, kids[Math.min(i, j)]);
  const b = findChildContainer(parent, kids[Math.max(i, j)]);
  const src = sf.text;
  const as = a.getStart(sf), ae = a.getEnd(), bs = b.getStart(sf), be = b.getEnd();
  return { start: as, end: be, text: src.slice(bs, be) + src.slice(ae, bs) + src.slice(as, ae) };
}

/** Apply one edit to `source` for component `page` and return the new source. */
export function applyEdit(file: string, source: string, page: string, op: EditOp): string {
  if (op.op === 'replaceSource') return op.text;
  const sf = parseSource(file, source);
  const comp = findComponents(sf).find((c) => c.name === page);
  if (!comp) throw new SourceEditError(`No component ${page} in ${file}`);
  let n: JsxNode;
  try { n = nodeAt(comp.root, op.path); } catch (e) { throw new SourceEditError((e as Error).message); }
  let p: Patch;
  switch (op.op) {
    case 'setArgument': p = setAttr(n, sf, op.name, op.value); break;
    case 'removeArgument': p = removeAttr(n, sf, op.name); break;
    case 'setPositional':
      if (op.index !== 0) throw new SourceEditError('JSX has a single positional slot (text)');
      p = setText(n, sf, op.value); break;
    case 'setText': p = setText(n, sf, op.value); break;
    case 'insertChild': p = insertChild(n, sf, op.snippet, op.index); break;
    case 'removeNode': p = removeNode(n, sf, comp.root); break;
    case 'wrapNode': p = wrapNode(n, sf, op.wrapper, op.extraArgs ?? ''); break;
    case 'moveInList': p = moveInList(n, sf, comp.root, op.path, op.delta); break;
  }
  const out = apply(source, p);
  const check = parseSource(file, out) as ts.SourceFile & { parseDiagnostics?: ts.Diagnostic[] };
  if (check.parseDiagnostics?.length) {
    throw new SourceEditError(`Edit would break ${file}: ${ts.flattenDiagnosticMessageText(check.parseDiagnostics[0].messageText, '\n')}`);
  }
  void tagName;
  return out;
}
