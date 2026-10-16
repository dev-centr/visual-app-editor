import ts from 'typescript';
import type { ArgInfo, PageInfo, TreeNode } from './model.js';

export type JsxNode = ts.JsxElement | ts.JsxSelfClosingElement | ts.JsxFragment;

export function parseSource(file: string, source: string): ts.SourceFile {
  const kind = /\.tsx$/.test(file) ? ts.ScriptKind.TSX : /\.ts$/.test(file) ? ts.ScriptKind.TS : ts.ScriptKind.JSX;
  return ts.createSourceFile(file, source, ts.ScriptTarget.Latest, true, kind);
}

export function isJsxNode(n: ts.Node): n is JsxNode {
  return ts.isJsxElement(n) || ts.isJsxSelfClosingElement(n) || ts.isJsxFragment(n);
}

function unwrap(e: ts.Expression): ts.Expression {
  while (ts.isParenthesizedExpression(e) || ts.isAsExpression(e) || ts.isSatisfiesExpression(e)) e = e.expression;
  return e;
}

/** The first JSX returned by a component body (block `return` or concise arrow). */
function returnedJsx(body: ts.Node | undefined): JsxNode | undefined {
  if (!body) return undefined;
  if (!ts.isBlock(body)) {
    const e = unwrap(body as ts.Expression);
    return isJsxNode(e) ? e : undefined;
  }
  let found: JsxNode | undefined;
  const visit = (n: ts.Node): void => {
    if (found) return;
    if (ts.isFunctionLike(n)) return; // nested callbacks are not the component's return
    if (ts.isReturnStatement(n) && n.expression) {
      const e = unwrap(n.expression);
      if (isJsxNode(e)) { found = e; return; }
    }
    ts.forEachChild(n, visit);
  };
  ts.forEachChild(body, visit);
  return found;
}

const isComponentName = (s: string) => /^[A-Z]/.test(s);

/** Components: capitalised function declarations / const arrows / function expressions returning JSX. */
export function findComponents(sf: ts.SourceFile): { name: string; root: JsxNode }[] {
  const out: { name: string; root: JsxNode }[] = [];
  const consider = (name: string | undefined, fn: ts.Node | undefined) => {
    if (!name || !fn || !isComponentName(name)) return;
    let f = fn;
    // memo(...) / forwardRef(...) wrappers
    while (ts.isCallExpression(f) && f.arguments.length > 0) f = f.arguments[0];
    if (ts.isArrowFunction(f) || ts.isFunctionExpression(f) || ts.isFunctionDeclaration(f)) {
      const root = returnedJsx(f.body);
      if (root) out.push({ name, root });
    }
  };
  for (const st of sf.statements) {
    if (ts.isFunctionDeclaration(st)) consider(st.name?.text ?? (hasDefault(st) ? 'Default' : undefined), st);
    else if (ts.isVariableStatement(st)) {
      for (const d of st.declarationList.declarations) {
        if (ts.isIdentifier(d.name)) consider(d.name.text, d.initializer);
      }
    } else if (ts.isClassDeclaration(st) && st.name) {
      const render = st.members.find((m): m is ts.MethodDeclaration => ts.isMethodDeclaration(m) && m.name.getText(sf) === 'render');
      const root = returnedJsx(render?.body);
      if (root && isComponentName(st.name.text)) out.push({ name: st.name.text, root });
    }
  }
  return out;
}

function hasDefault(n: ts.FunctionDeclaration): boolean {
  return !!n.modifiers?.some((m) => m.kind === ts.SyntaxKind.DefaultKeyword);
}

export function tagName(n: JsxNode, sf: ts.SourceFile): string {
  if (ts.isJsxFragment(n)) return 'Fragment';
  const tag = ts.isJsxElement(n) ? n.openingElement.tagName : n.tagName;
  return tag.getText(sf);
}

export function attributesOf(n: JsxNode): ts.JsxAttributes | undefined {
  if (ts.isJsxFragment(n)) return undefined;
  return ts.isJsxElement(n) ? n.openingElement.attributes : n.attributes;
}

/** Element children only (text and `{expr}` children are folded into `text`). */
export function jsxChildren(n: JsxNode): JsxNode[] {
  if (ts.isJsxSelfClosingElement(n)) return [];
  const out: JsxNode[] = [];
  for (const c of n.children) {
    if (isJsxNode(c)) out.push(c);
    else if (ts.isJsxExpression(c) && c.expression) {
      // {cond && <X/>} and {list.map(() => <X/>)} surface their JSX for selection
      const inner = firstJsxIn(c.expression);
      if (inner) out.push(inner);
    }
  }
  return out;
}

function firstJsxIn(e: ts.Node): JsxNode | undefined {
  let found: JsxNode | undefined;
  const visit = (n: ts.Node): void => {
    if (found) return;
    if (isJsxNode(n)) { found = n; return; }
    ts.forEachChild(n, visit);
  };
  visit(e);
  return found;
}

function textOf(n: JsxNode, sf: ts.SourceFile): string | undefined {
  if (ts.isJsxSelfClosingElement(n)) return undefined;
  const parts: string[] = [];
  for (const c of n.children) {
    if (ts.isJsxText(c)) { const t = c.getText(sf).replace(/\s+/g, ' ').trim(); if (t) parts.push(t); }
    else if (ts.isJsxExpression(c) && c.expression && (ts.isStringLiteral(c.expression) || ts.isNoSubstitutionTemplateLiteral(c.expression))) parts.push(c.expression.text);
  }
  return parts.length ? parts.join(' ') : undefined;
}

export function toTree(n: JsxNode, sf: ts.SourceFile, path: number[] = []): TreeNode {
  const args: ArgInfo[] = [];
  for (const a of attributesOf(n)?.properties ?? []) {
    if (ts.isJsxAttribute(a)) args.push({ name: a.name.getText(sf), source: a.initializer ? a.initializer.getText(sf) : 'true' });
    else args.push({ source: a.getText(sf) }); // {...spread}
  }
  const kids = jsxChildren(n);
  return {
    type: tagName(n, sf),
    path,
    slot: path.length ? 'children' : undefined,
    args,
    children: kids.map((c, i) => toTree(c, sf, [...path, i])),
    offset: n.getStart(sf),
    end: n.getEnd(),
    text: textOf(n, sf),
  };
}

export function pagesOf(file: string, source: string): PageInfo[] {
  const sf = parseSource(file, source);
  return findComponents(sf).map((c) => ({ name: c.name, file, kind: 'component', root: toTree(c.root, sf) }));
}

export function nodeAt(root: JsxNode, path: number[]): JsxNode {
  let n = root;
  for (const i of path) {
    const k = jsxChildren(n);
    if (i < 0 || i >= k.length) throw new RangeError(`No child ${i} at ${path.join('.')}`);
    n = k[i];
  }
  return n;
}
