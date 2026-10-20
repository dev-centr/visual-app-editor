import fs from 'node:fs';
import path from 'node:path';

/** Splits a command line honouring double quotes. */
export function splitCommand(cmd: string): string[] {
  const out: string[] = [];
  let cur = '';
  let has = false;
  let q = false;
  for (const c of cmd) {
    if (c === '"') { q = !q; has = true; }
    else if (/\s/.test(c) && !q) { if (has) out.push(cur); cur = ''; has = false; }
    else { cur += c; has = true; }
  }
  if (has) out.push(cur);
  return out;
}

export function resolveExecutable(name: string, windows: boolean, envPath = process.env.PATH ?? '', pathExt = process.env.PATHEXT ?? '.COM;.EXE;.BAT;.CMD'): string | undefined {
  const exts = windows ? ['', ...pathExt.split(';').filter(Boolean).map((e) => e.toLowerCase())] : [''];
  const isFile = (p: string) => { try { return fs.statSync(p).isFile(); } catch { return false; } };
  if (path.isAbsolute(name) || /[\\/]/.test(name)) {
    for (const e of exts) if (isFile(name + e)) return name + e;
    return undefined;
  }
  for (const dir of envPath.split(windows ? ';' : ':').filter(Boolean)) {
    for (const e of exts) {
      if (windows && e === '' && !name.includes('.')) continue;
      const p = path.join(dir, name + e);
      if (isFile(p)) return p;
    }
  }
  return undefined;
}

/** argv for child_process.spawn (no shell); Windows .bat/.cmd shims go through cmd.exe. */
export function argvFor(cmd: string, windows = process.platform === 'win32'): string[] {
  const parts = splitCommand(cmd);
  if (!parts.length) throw new Error('Empty service command');
  const exe = resolveExecutable(parts[0], windows) ?? parts[0];
  const rest = parts.slice(1);
  return windows && /\.(bat|cmd)$/i.test(exe) ? ['cmd.exe', '/d', '/s', '/c', exe, ...rest] : [exe, ...rest];
}

/** Default when unconfigured: $VAE_SERVICE, vae_service on PATH, then packages/service inside a workspace folder. */
export function autodetectService(folders: string[]): string | undefined {
  if (process.env.VAE_SERVICE?.trim()) return process.env.VAE_SERVICE;
  const exe = resolveExecutable('vae_service', process.platform === 'win32');
  if (exe) return `"${exe}"`;
  for (const f of folders) {
    let d = f;
    for (;;) {
      const bin = path.join(d, 'packages', 'service', 'bin', 'vae_service.dart');
      if (fs.existsSync(bin)) return `dart run "${bin}"`;
      const up = path.dirname(d);
      if (up === d) break;
      d = up;
    }
  }
  return undefined;
}
