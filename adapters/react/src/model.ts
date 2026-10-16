// Wire shapes shared with vae_core (packages/core/lib/src/tree.dart, edits.dart, catalog.dart).

export interface ArgInfo { name?: string; source: string }

export interface TreeNode {
  type: string;
  path: number[];
  slot?: string;
  args: ArgInfo[];
  children: TreeNode[];
  offset: number;
  end: number;
  text?: string;
}

export interface PageInfo { name: string; file: string; kind: string; root?: TreeNode }

export type EditOp =
  | { op: 'setArgument'; path: number[]; name: string; value: string }
  | { op: 'removeArgument'; path: number[]; name: string }
  | { op: 'setPositional'; path: number[]; index: number; value: string }
  | { op: 'setText'; path: number[]; value: string }
  | { op: 'insertChild'; path: number[]; snippet: string; index?: number | null }
  | { op: 'removeNode'; path: number[] }
  | { op: 'wrapNode'; path: number[]; wrapper: string; slot?: string; extraArgs?: string }
  | { op: 'moveInList'; path: number[]; delta: number }
  | { op: 'replaceSource'; text: string };

export interface WidgetParam { name: string; type: string; named?: boolean; required?: boolean; default?: string }

export interface WidgetSpec {
  class: string;
  // 'constructor' (named Dart constructors) has no JSX equivalent and is omitted.
  toolkit: string;
  params: WidgetParam[];
  doc?: string;
  category?: string;
  snippet?: string;
}

export interface ToolkitManifest { id: string; name: string; package: string; import: string; adapter: string }

export class SourceEditError extends Error {}
