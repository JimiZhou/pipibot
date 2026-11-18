/**
 * @pipibot/daemon - cli.ts
 *
 * CLI entrypoint for the V1 macOS Always-On Resident Daemon (`pipibot-daemon`).
 * Guarded by `realpathSync` entrypoint check so importing or running type-strip
 * syntax checks (`node --experimental-strip-types cli.ts`) does NOT bind a socket.
 */

import { realpathSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

import { DAEMON_VERSION, DEFAULT_DAEMON_PORT, PipiResidentServer } from './server.ts';

export interface ParsedCliArgs {
  port: number;
  host: string;
  workspacePath?: string;
  printPlistOnly: boolean;
  help: boolean;
}

export function parseCliArgs(argv: readonly string[]): ParsedCliArgs {
  let port = Number(process.env.PIPIBOT_PORT ?? DEFAULT_DAEMON_PORT);
  let host = process.env.PIPIBOT_HOST ?? '127.0.0.1';
  let workspacePath: string | undefined;
  let printPlistOnly = false;
  let help = false;

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') {
      help = true;
    } else if (arg === '--print-plist') {
      printPlistOnly = true;
    } else if (arg === '--port' || arg === '-p') {
      const next = argv[i + 1];
      if (next) {
        const parsed = Number(next);
        if (Number.isFinite(parsed) && parsed >= 0) port = parsed;
        i += 1;
      }
    } else if (arg === '--host') {
      const next = argv[i + 1];
      if (next) {
        host = next;
        i += 1;
      }
    } else if (arg === '--workspace') {
      const next = argv[i + 1];
      if (next) {
        workspacePath = next;
        i += 1;
      }
    }
  }

  return { port, host, workspacePath, printPlistOnly, help };
}

export async function runDaemonCli(argv = process.argv.slice(2)): Promise<void> {
  const opts = parseCliArgs(argv);

  if (opts.help) {
    console.log(
      [
        `pipibot-daemon v${DAEMON_VERSION}`,
        'Usage: node --experimental-strip-types packages/daemon/src/cli.ts [options]',
        '',
        'Options:',
        `  -p, --port <port>       Listen port (default: ${DEFAULT_DAEMON_PORT} or PIPIBOT_PORT)`,
        '      --host <host>       Bind host (default: 127.0.0.1)',
        '      --workspace <dir>   Workspace root for Manus Cue & Outcomes',
        '      --print-plist       Print macOS launchd plist XML and exit',
        '  -h, --help              Show help',
      ].join('\n'),
    );
    return;
  }

  const server = new PipiResidentServer({
    port: opts.port,
    host: opts.host,
    workspacePath: opts.workspacePath,
  });

  if (opts.printPlistOnly) {
    console.log(server.buildLaunchdPlist(opts.port));
    return;
  }

  const baseUrl = await server.start();
  console.log(`[pipibot-daemon v${DAEMON_VERSION}] listening on ${baseUrl}`);
  console.log(`  - API Status      : ${baseUrl}/api/v1/status`);
  console.log(`  - SSE Events      : ${baseUrl}/api/v1/events`);
  console.log(`  - Design System   : ${baseUrl}/design-system/`);
  console.log(`  - iOS Companion   : ${baseUrl}/ios/`);

  const shutdown = async () => {
    await server.stop();
    process.exit(0);
  };
  process.once('SIGINT', () => void shutdown());
  process.once('SIGTERM', () => void shutdown());
}

function isDirectEntrypoint(): boolean {
  const entry = process.argv[1];
  if (!entry) return false;
  try {
    return import.meta.url === pathToFileURL(realpathSync(entry)).href;
  } catch {
    return false;
  }
}

if (isDirectEntrypoint()) {
  void runDaemonCli();
}
