import fs from 'node:fs';
import path from 'node:path';
import ts from 'typescript';
import type { ToolkitManifest, WidgetParam, WidgetSpec } from './model.js';

const p = (name: string, type = 'string', required = false): WidgetParam => ({ name, type, named: true, required });

/** Intrinsic DOM elements: no package to introspect, so the catalog is fixed. */
const DOM: [string, string, WidgetParam[]][] = [
  ['div', 'Layout', [p('className'), p('style', 'CSSProperties')]],
  ['section', 'Layout', [p('className')]],
  ['header', 'Layout', [p('className')]],
  ['footer', 'Layout', [p('className')]],
  ['main', 'Layout', [p('className')]],
  ['nav', 'Layout', [p('className')]],
  ['h1', 'Text', [p('className')]],
  ['h2', 'Text', [p('className')]],
  ['p', 'Text', [p('className')]],
  ['span', 'Text', [p('className')]],
  ['a', 'Text', [p('href'), p('target')]],
  ['img', 'Display', [p('src', 'string', true), p('alt', 'string', true), p('width', 'number'), p('height', 'number')]],
  ['ul', 'Lists', [p('className')]],
  ['li', 'Lists', [p('className')]],
  ['button', 'Inputs', [p('type'), p('onClick', '() => void'), p('disabled', 'boolean')]],
  ['input', 'Inputs', [p('type'), p('value'), p('placeholder'), p('onChange', '(e) => void')]],
  ['label', 'Inputs', [p('htmlFor')]],
  ['form', 'Inputs', [p('onSubmit', '(e) => void')]],
];

const DOM_SNIPPETS: Record<string, string> = {
  img: '<img src="" alt="" />',
  input: '<input type="text" />',
};

/** react-native core components (used when the project has no node_modules yet). */
const RN: [string, string, WidgetParam[]][] = [
  ['View', 'Layout', [p('style', 'StyleProp<ViewStyle>'), p('testID')]],
  ['SafeAreaView', 'Layout', [p('style', 'StyleProp<ViewStyle>')]],
  ['ScrollView', 'Layout', [p('horizontal', 'boolean'), p('contentContainerStyle', 'StyleProp<ViewStyle>')]],
  ['Text', 'Text', [p('style', 'StyleProp<TextStyle>'), p('numberOfLines', 'number')]],
  ['Image', 'Display', [p('source', 'ImageSourcePropType', true), p('style', 'StyleProp<ImageStyle>')]],
  ['ActivityIndicator', 'Display', [p('size'), p('color')]],
  ['Button', 'Inputs', [p('title', 'string', true), p('onPress', '() => void', true), p('color')]],
  ['Pressable', 'Inputs', [p('onPress', '() => void')]],
  ['TextInput', 'Inputs', [p('value'), p('placeholder'), p('onChangeText', '(text: string) => void')]],
  ['Switch', 'Inputs', [p('value', 'boolean'), p('onValueChange', '(v: boolean) => void')]],
  ['FlatList', 'Lists', [p('data', 'ArrayLike<T>', true), p('renderItem', 'ListRenderItem<T>', true)]],
];

const RN_SNIPPETS: Record<string, string> = {
  Text: '<Text>Text</Text>',
  Button: '<Button title="Button" onPress={() => {}} />',
  Image: '<Image source={{ uri: "" }} style={{ width: 64, height: 64 }} />',
};

function fixed(id: string, rows: [string, string, WidgetParam[]][], snippets: Record<string, string>): WidgetSpec[] {
  return rows.map(([c, category, params]) => ({ class: c, toolkit: id, params, category, snippet: snippets[c] }));
}

function typesEntry(pkgDir: string): string | undefined {
  try {
    const pj = JSON.parse(fs.readFileSync(path.join(pkgDir, 'package.json'), 'utf8'));
    for (const k of [pj.types, pj.typings, 'index.d.ts', 'lib/typescript/index.d.ts']) {
      if (k && fs.existsSync(path.join(pkgDir, k))) return path.join(pkgDir, k);
    }
  } catch { /* no package */ }
  return undefined;
}

/**
 * Real introspection: load the package's declaration entry with the TypeScript
 * checker and list capitalised exports that are callable / constructible with
 * a props object, reading prop names, types and optionality.
 */
export function introspectPackage(projectRoot: string, manifest: ToolkitManifest, limitProps = 40): WidgetSpec[] | undefined {
  const pkgDir = path.join(projectRoot, 'node_modules', manifest.package);
  const entry = typesEntry(pkgDir) ?? typesEntry(path.join(projectRoot, 'node_modules', '@types', manifest.package.replace(/^@/, '').replace('/', '__')));
  if (!entry) return undefined;
  const program = ts.createProgram([entry], { jsx: ts.JsxEmit.ReactJSX, skipLibCheck: true, noEmit: true, types: [] });
  const checker = program.getTypeChecker();
  const sf = program.getSourceFile(entry);
  const mod = sf && checker.getSymbolAtLocation(sf);
  if (!mod) return undefined;
  const out: WidgetSpec[] = [];
  for (const ex of checker.getExportsOfModule(mod)) {
    if (!/^[A-Z]/.test(ex.name)) continue;
    const sym = ex.flags & ts.SymbolFlags.Alias ? checker.getAliasedSymbol(ex) : ex;
    if (!(sym.flags & (ts.SymbolFlags.Value))) continue;
    const decl = sym.valueDeclaration ?? sym.declarations?.[0];
    if (!decl) continue;
    const t = checker.getTypeOfSymbolAtLocation(sym, decl);
    const sig = t.getCallSignatures()[0] ?? t.getConstructSignatures()[0];
    if (!sig || sig.parameters.length === 0) continue;
    const propsSym = sig.parameters[0];
    const propsType = checker.getTypeOfSymbolAtLocation(propsSym, decl);
    const props = propsType.getProperties();
    if (!props.length && !(propsType.flags & ts.TypeFlags.Object)) continue;
    const params: WidgetParam[] = [];
    for (const pr of props.slice(0, limitProps)) {
      if (pr.name === 'children' || pr.name === 'key' || pr.name === 'ref') continue;
      const pd = pr.valueDeclaration ?? pr.declarations?.[0];
      const pt = pd ? checker.typeToString(checker.getTypeOfSymbolAtLocation(pr, pd)) : 'unknown';
      params.push({ name: pr.name, type: pt, named: true, required: !(pr.flags & ts.SymbolFlags.Optional) });
    }
    out.push({ class: ex.name, toolkit: manifest.id, params, category: 'Components', doc: ts.displayPartsToString(sym.getDocumentationComment(checker)) || undefined });
  }
  return out.sort((a, b) => a.class.localeCompare(b.class));
}

export function loadToolkit(manifest: ToolkitManifest, projectRoot?: string): { widgets: WidgetSpec[]; source: string } {
  if (manifest.package === 'react-dom' || manifest.id === 'html') return { widgets: fixed(manifest.id, DOM, DOM_SNIPPETS), source: 'builtin' };
  if (projectRoot) {
    const w = introspectPackage(projectRoot, manifest);
    if (w && w.length) return { widgets: w, source: 'introspected' };
  }
  if (manifest.package === 'react-native') return { widgets: fixed(manifest.id, RN, RN_SNIPPETS), source: 'builtin' };
  return { widgets: [], source: 'missing' };
}
