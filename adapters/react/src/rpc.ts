// JSON-RPC 2.0 over Content-Length framing (same as packages/protocol).

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
