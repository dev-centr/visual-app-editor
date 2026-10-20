// JSON-RPC 2.0 client with LSP-style Content-Length framing (the vae_service wire format).
import type { Readable, Writable } from 'node:stream';

export class RpcError extends Error {
  constructor(public code: number, message: string) {
    super(message);
  }
}

export function encode(msg: unknown): Buffer {
  const body = Buffer.from(JSON.stringify(msg), 'utf8');
  return Buffer.concat([Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, 'ascii'), body]);
}

export class Decoder {
  private buf = Buffer.alloc(0);
  push(chunk: Buffer): unknown[] {
    this.buf = Buffer.concat([this.buf, chunk]);
    const out: unknown[] = [];
    for (;;) {
      const sep = this.buf.indexOf('\r\n\r\n');
      if (sep < 0) break;
      const m = /Content-Length:\s*(\d+)/i.exec(this.buf.subarray(0, sep).toString('ascii'));
      if (!m) throw new Error('Missing Content-Length');
      const len = Number(m[1]);
      if (this.buf.length < sep + 4 + len) break;
      out.push(JSON.parse(this.buf.subarray(sep + 4, sep + 4 + len).toString('utf8')));
      this.buf = this.buf.subarray(sep + 4 + len);
    }
    return out;
  }
}

type Pending = { resolve: (v: unknown) => void; reject: (e: Error) => void };

export class RpcClient {
  private nextId = 1;
  private pending = new Map<number, Pending>();
  private decoder = new Decoder();
  private closedReason: string | undefined;

  constructor(
    input: Readable,
    private output: Writable,
    private onNotification: (method: string, params: Record<string, unknown>) => void = () => {},
  ) {
    input.on('data', (c: Buffer) => {
      for (const m of this.decoder.push(c)) this.dispatch(m as Record<string, unknown>);
    });
    input.on('close', () => this.fail('Service closed the connection'));
    input.on('error', (e) => this.fail(`Service connection failed: ${e.message}`));
  }

  get closed(): boolean {
    return this.closedReason !== undefined;
  }

  request<T = unknown>(method: string, params: Record<string, unknown> = {}): Promise<T> {
    if (this.closedReason) return Promise.reject(new RpcError(-32603, this.closedReason));
    const id = this.nextId++;
    return new Promise<T>((resolve, reject) => {
      this.pending.set(id, { resolve: resolve as (v: unknown) => void, reject });
      this.output.write(encode({ jsonrpc: '2.0', id, method, params }));
    });
  }

  private dispatch(m: Record<string, unknown>) {
    const id = m.id as number | undefined;
    const method = m.method as string | undefined;
    if (method && id === undefined) return this.onNotification(method, (m.params ?? {}) as Record<string, unknown>);
    if (method) {
      this.output.write(encode({ jsonrpc: '2.0', id, error: { code: -32601, message: 'Not supported' } }));
      return;
    }
    const p = id === undefined ? undefined : this.pending.get(id);
    if (!p) return;
    this.pending.delete(id!);
    const err = m.error as { code: number; message: string } | undefined;
    if (err) p.reject(new RpcError(err.code, err.message));
    else p.resolve(m.result);
  }

  fail(reason: string) {
    this.closedReason ??= reason;
    for (const p of this.pending.values()) p.reject(new RpcError(-32603, this.closedReason));
    this.pending.clear();
  }
}
