import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { runTests } from '@vscode/test-electron';

async function main() {
  const ext = path.resolve(__dirname, '../../..');
  const repo = path.resolve(ext, '../..');
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'vae-vscode-'));
  fs.cpSync(path.join(repo, 'packages/service/test/sample_app'), work, { recursive: true });
  await runTests({
    extensionDevelopmentPath: ext,
    extensionTestsPath: path.resolve(__dirname, 'suite.js'),
    launchArgs: [work, '--disable-extensions', '--disable-workspace-trust'],
    extensionTestsEnv: { VAE_TEST_WORKSPACE: work, VAE_REPO_ROOT: repo, VAE_SERVICE_TEST_CMD: process.env.VAE_SERVICE_TEST_CMD ?? '' },
    version: process.env.VSCODE_TEST_VERSION ?? 'stable',
  });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
