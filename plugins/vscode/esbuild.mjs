import * as esbuild from 'esbuild';

const production = process.argv.includes('--production');
await esbuild.build({
  entryPoints: ['src/extension.ts'],
  bundle: true,
  format: 'cjs',
  platform: 'node',
  target: 'node20',
  external: ['vscode'],
  outfile: 'out/extension.js',
  sourcemap: !production,
  minify: production,
  logLevel: 'info',
});
