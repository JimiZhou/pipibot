/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/daemon - bot-box.ts
 * Layered Bot Box OS-Level Sandbox (macOS Seatbelt `sandbox-exec` / Linux `bubblewrap`)
 * + live `runBotBoxSelfCheck()` probe (`box-check`).
 */

import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export interface BoxCheckItem {
  name: string;
  passed: boolean;
  detail: string;
}

export interface BoxSelfCheckReport {
  backend: 'seatbelt' | 'bwrap' | 'off';
  checkedAt: string;
  allPassed: boolean;
  passedCount: number;
  checks: BoxCheckItem[];
}

function escapeSeatbelt(p: string): string {
  return p.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

function hasExecutable(bin: string): boolean {
  try {
    execFileSync('which', [bin], { stdio: 'ignore', timeout: 1500 });
    return true;
  } catch {
    return false;
  }
}

export function detectBoxBackend(): 'seatbelt' | 'bwrap' | 'off' {
  if (process.platform === 'darwin' && existsSync('/usr/bin/sandbox-exec')) {
    return 'seatbelt';
  }
  if (process.platform === 'linux' && hasExecutable('bwrap')) {
    return 'bwrap';
  }
  return 'off';
}

export function runBotBoxSelfCheck(): BoxSelfCheckReport {
  const backend = detectBoxBackend();
  const checkedAt = new Date().toISOString();

  if (backend === 'off') {
    return {
      backend: 'off',
      checkedAt,
      allPassed: false,
      passedCount: 0,
      checks: [
        {
          name: 'backend_available',
          passed: false,
          detail: 'Neither macOS sandbox-exec nor Linux bwrap is available on this host',
        },
      ],
    };
  }

  const root = realpathSync(mkdtempSync(join(tmpdir(), 'pipibot-boxcheck-')));
  const allowedDir = join(root, 'workspace');
  const deniedDir = join(root, 'decoy-secrets');
  const outsideDir = join(root, 'outside-write');
  mkdirSync(allowedDir, { recursive: true });
  mkdirSync(deniedDir, { recursive: true });
  mkdirSync(outsideDir, { recursive: true });
  const decoyFile = join(deniedDir, 'vault.enc');
  writeFileSync(decoyFile, 'TOP_SECRET_CANARY_999', 'utf8');

  const checks: BoxCheckItem[] = [];
  try {
    if (backend === 'seatbelt') {
      const profilePath = join(root, 'probe.sb');
      const profile = [
        '(version 1)',
        '(allow default)',
        '(deny file-write*)',
        `(allow file-write* (subpath "${escapeSeatbelt(allowedDir)}"))`,
        `(deny file-read* (subpath "${escapeSeatbelt(deniedDir)}"))`,
        '(deny network*)',
      ].join('\n');
      writeFileSync(profilePath, profile, 'utf8');

      const runBox = (cmd: string): { ok: boolean; out: string } => {
        try {
          const out = execFileSync('/usr/bin/sandbox-exec', ['-f', profilePath, '/bin/sh', '-c', cmd], {
            encoding: 'utf8',
            stdio: ['ignore', 'pipe', 'pipe'],
            timeout: 4000,
          });
          return { ok: true, out };
        } catch (err) {
          return { ok: false, out: String(err) };
        }
      };

      const readTry = runBox(`cat '${decoyFile}'`);
      const readBlocked = !readTry.ok && !readTry.out.includes('TOP_SECRET_CANARY_999');
      checks.push({
        name: 'block_secret_read',
        passed: readBlocked,
        detail: readBlocked ? 'Seatbelt blocked decoy secret read' : 'WARNING: decoy secret readable',
      });

      const outWrite = runBox(`echo pwn > '${join(outsideDir, 'escape.txt')}'`);
      const writeBlocked = !outWrite.ok && !existsSync(join(outsideDir, 'escape.txt'));
      checks.push({
        name: 'block_outside_write',
        passed: writeBlocked,
        detail: writeBlocked ? 'Seatbelt blocked outside write' : 'WARNING: outside write succeeded',
      });

      const inWrite = runBox(`echo ok > '${join(allowedDir, 'ok.txt')}'`);
      const insideOk = inWrite.ok && existsSync(join(allowedDir, 'ok.txt'));
      checks.push({
        name: 'allow_workspace_write',
        passed: insideOk,
        detail: insideOk ? 'Workspace write allowed' : 'Workspace write unexpectedly blocked',
      });
    } else {
      // Linux bubblewrap probe
      const runBwrap = (cmd: string): { ok: boolean; out: string } => {
        try {
          const out = execFileSync(
            'bwrap',
            [
              '--ro-bind', '/usr', '/usr',
              '--ro-bind', '/bin', '/bin',
              '--ro-bind', '/lib', '/lib',
              '--proc', '/proc',
              '--dev', '/dev',
              '--tmpfs', '/tmp',
              '--bind', allowedDir, allowedDir,
              '--unshare-net',
              '/bin/sh', '-c', cmd,
            ],
            { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 4000 },
          );
          return { ok: true, out };
        } catch (err) {
          return { ok: false, out: String(err) };
        }
      };

      const readTry = runBwrap(`cat '${decoyFile}'`);
      checks.push({
        name: 'block_secret_read',
        passed: !readTry.ok && !readTry.out.includes('TOP_SECRET_CANARY_999'),
        detail: !readTry.ok ? 'bwrap isolated decoy secrets' : 'WARNING: decoy visible',
      });

      const inWrite = runBwrap(`echo ok > '${join(allowedDir, 'ok.txt')}'`);
      checks.push({
        name: 'allow_workspace_write',
        passed: inWrite.ok && existsSync(join(allowedDir, 'ok.txt')),
        detail: inWrite.ok ? 'bwrap workspace write allowed' : 'bwrap workspace write failed',
      });
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }

  const passedCount = checks.filter((c) => c.passed).length;
  return {
    backend,
    checkedAt,
    allPassed: checks.length > 0 && passedCount === checks.length,
    passedCount,
    checks,
  };
}
