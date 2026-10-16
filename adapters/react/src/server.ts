import { loadToolkit } from './catalog.js';
import { applyEdit } from './edits.js';
import { SourceEditError, type EditOp, type ToolkitManifest } from './model.js';
import { pagesOf } from './parse.js';

export const ADAPTER_ID = 'react';
export const EXTENSIONS = ['.jsx', '.tsx'];

interface Req { jsonrpc: '2.0'; id?: number | string; method: string; params?: Record<string, unknown> }

/** Handles one `adapter/*` request; returns the JSON-RPC response (or undefined for notifications). */
export function handle(req: Req): object | undefined {
  const reply = (result: unknown) => (req.id === undefined ? undefined : { jsonrpc: '2.0', id: req.id, result });
  const fail = (code: number, message: string) => (req.id === undefined ? undefined : { jsonrpc: '2.0', id: req.id, error: { code, message } });
  const p = req.params ?? {};
  try {
    switch (req.method) {
      case 'adapter/info':
        return reply({ id: ADAPTER_ID, extensions: EXTENSIONS, frameworks: ['react', 'react-native'] });
      case 'adapter/pages':
        return reply(pagesOf(String(p.path), String(p.source)));
      case 'adapter/applyEdit':
        return reply({ source: applyEdit(String(p.path), String(p.source), String(p.page), p.op as EditOp) });
      case 'adapter/loadToolkit':
        return reply(loadToolkit(p.manifest as ToolkitManifest, p.projectRoot as string | undefined));
      case 'shutdown':
        return reply(null);
      default:
        return fail(-32601, `Unknown method ${req.method}`);
    }
  } catch (e) {
    return fail(e instanceof SourceEditError ? -32020 : -32603, (e as Error).message);
  }
}
