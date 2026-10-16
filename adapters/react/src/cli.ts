#!/usr/bin/env node
import { Decoder, encode } from './rpc.js';
import { handle } from './server.js';

const dec = new Decoder();
process.stdin.on('data', (chunk: Buffer) => {
  for (const msg of dec.push(chunk)) {
    const req = msg as { method: string };
    const res = handle(msg as Parameters<typeof handle>[0]);
    if (res) process.stdout.write(encode(res));
    if (req.method === 'exit' || req.method === 'shutdown') setTimeout(() => process.exit(0), 50);
  }
});
process.stdin.on('end', () => process.exit(0));
