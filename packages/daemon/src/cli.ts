/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/daemon - cli.ts
 * Unified Linux & macOS Headless CLI + Mesh Hub + Mesh Node Daemon (`pipibot-daemon`).
 * Supports:
 * - `hub start`        : Run a free self-hosted Multi-Machine Mesh Hub
 * - `node join`        : Join a Linux/macOS/GPU machine to any Hub via outbound SSE
 * - `daemon install`   : Generate Linux systemd unit or macOS launchd plist
 * - `nodes list`       : List all online/offline machines & Agents in the cluster
 * - `run --node <n>`   : Dispatch a live task to any remote machine from terminal
 * - `skills list|install`: Manage community SKILL.md & MCP packs
 */

import { readFileSync } from 'node:fs';
import { realpathSync } from 'node:fs';
import { hostname as osHostname, platform as osPlatform } from 'node:os';
import { pathToFileURL } from 'node:url';

import { runBotBoxSelfCheck } from './bot-box.ts';
import { runBoundedMCPStdioLoop } from './mcp-server.ts';
import { buildLinuxSystemdService, type MeshNodeRecord, type MeshTaskRecord } from './mesh-hub.ts';
import { PipiMeshNodeAgent } from './mesh-node.ts';
import { parsePortableTemplate } from './portable-template.ts';
import { scanSentinelSamples } from './sentinel.ts';
import { DAEMON_VERSION, DEFAULT_DAEMON_PORT, PipiResidentServer } from './server.ts';

export type DaemonCliMode =
  | 'hub_start'
  | 'node_join'
  | 'daemon_install'
  | 'nodes_list'
  | 'run_remote'
  | 'skills_list'
  | 'skills_install'
  | 'mcp_stdio'
  | 'team_apply'
  | 'sentinel_scan'
  | 'box_check';

export interface ParsedCliArgs {
  mode: DaemonCliMode;
  port: number;
  host: string;
  hubUrl: string;
  token?: string;
  nodeName: string;
  targetNode?: string;
  promptText?: string;
  skillSource?: string;
  role: 'hub' | 'node';
  serviceFormat: 'auto' | 'systemd' | 'launchd';
  workspacePath?: string;
  printPlistOnly: boolean;
  clean: boolean;
  help: boolean;
}

export function parseCliArgs(argv: readonly string[]): ParsedCliArgs {
  let mode: DaemonCliMode = 'hub_start';
  let port = Number(process.env.PIPIBOT_PORT ?? DEFAULT_DAEMON_PORT);
  let host = process.env.PIPIBOT_HOST ?? '127.0.0.1';
  let hubUrl = process.env.PIPIBOT_HUB_URL ?? `http://127.0.0.1:${DEFAULT_DAEMON_PORT}`;
  let token = process.env.PIPIBOT_HUB_TOKEN;
  let nodeName = osHostname();
  let targetNode: string | undefined;
  let promptText: string | undefined;
  let skillSource: string | undefined;
  let role: 'hub' | 'node' = 'hub';
  let serviceFormat: 'auto' | 'systemd' | 'launchd' = 'auto';
  let workspacePath: string | undefined;
  let printPlistOnly = false;
  let clean = false;
  let help = false;

  const positional: string[] = [];
  let idx = 0;

  if (argv[0] === 'hub' && argv[1] === 'start') {
    mode = 'hub_start';
    idx = 2;
  } else if (argv[0] === 'node' && argv[1] === 'join') {
    mode = 'node_join';
    role = 'node';
    idx = 2;
  } else if (argv[0] === 'daemon' && argv[1] === 'install') {
    mode = 'daemon_install';
    idx = 2;
  } else if (argv[0] === 'nodes' && (argv[1] === 'list' || !argv[1] || argv[1].startsWith('-'))) {
    mode = 'nodes_list';
    idx = argv[1] === 'list' ? 2 : 1;
  } else if (argv[0] === 'run') {
    mode = 'run_remote';
    idx = 1;
  } else if (argv[0] === 'skills' && argv[1] === 'install') {
    mode = 'skills_install';
    idx = 2;
  } else if (argv[0] === 'skills') {
    mode = 'skills_list';
    idx = argv[1] === 'list' ? 2 : 1;
  } else if (argv[0] === 'mcp') {
    mode = 'mcp_stdio';
    idx = 1;
  } else if (argv[0] === 'team' && argv[1] === 'apply') {
    mode = 'team_apply';
    idx = 2;
  } else if (argv[0] === 'sentinel') {
    mode = 'sentinel_scan';
    idx = 1;
  } else if (argv[0] === 'box-check') {
    mode = 'box_check';
    idx = 1;
  }

  for (let i = idx; i < argv.length; i += 1) {
    const arg = argv[i] ?? '';
    if (arg === '--help' || arg === '-h') {
      help = true;
    } else if (arg === '--print-plist') {
      printPlistOnly = true;
    } else if (arg === '--clean') {
      clean = true;
    } else if (arg === '--systemd') {
      serviceFormat = 'systemd';
    } else if (arg === '--launchd') {
      serviceFormat = 'launchd';
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
    } else if (arg === '--hub') {
      const next = argv[i + 1];
      if (next) {
        hubUrl = next.replace(/\/+$/, '');
        i += 1;
      }
    } else if (arg === '--token') {
      const next = argv[i + 1];
      if (next) {
        token = next;
        i += 1;
      }
    } else if (arg === '--name') {
      const next = argv[i + 1];
      if (next) {
        nodeName = next;
        i += 1;
      }
    } else if (arg === '--node') {
      const next = argv[i + 1];
      if (next) {
        targetNode = next;
        i += 1;
      }
    } else if (arg === '--role') {
      const next = argv[i + 1];
      if (next === 'node' || next === 'hub') {
        role = next;
        i += 1;
      }
    } else if (arg === '--workspace') {
      const next = argv[i + 1];
      if (next) {
        workspacePath = next;
        i += 1;
      }
    } else if (!arg.startsWith('-')) {
      positional.push(arg);
    }
  }

  if (mode === 'run_remote' && positional.length > 0) {
    promptText = positional.join(' ');
  }
  if (mode === 'skills_install' && positional.length > 0) {
    skillSource = positional[0];
  }

  return {
    mode,
    port,
    host,
    hubUrl,
    token,
    nodeName,
    targetNode,
    promptText,
    skillSource,
    role,
    serviceFormat,
    workspacePath,
    printPlistOnly,
    clean,
    help,
  };
}

export async function runDaemonCli(argv = process.argv.slice(2)): Promise<void> {
  const opts = parseCliArgs(argv);

  if (opts.help) {
    console.log(
      [
        `pipibot v${DAEMON_VERSION} — Free Open-Source Multi-Machine Agent Hub & Linux/macOS Node Daemon`,
        '',
        'Commands:',
        '  hub start [--host 0.0.0.0 --port 4242 --token <tok>]       Start self-hosted Mesh Hub',
        '  node join --hub <url> --name <host> [--token <tok>]        Join this Linux/Mac machine to Hub',
        '  daemon install [--role hub|node] [--systemd|--launchd]     Print systemd/launchd service unit',
        '  nodes list [--hub <url>] [--token <tok>]                   List all connected machines & Agents',
        '  run --node <host> "<task>" [--hub <url>]                   Dispatch a live task to a remote host',
        '  skills list | skills install <github-url|path|id>          Manage SKILL.md & MCP packs',
        '',
        'Legacy Options (default: hub start):',
        `  -p, --port <port>       Listen port (default: ${DEFAULT_DAEMON_PORT})`,
        '      --host <host>       Bind host (default: 127.0.0.1)',
        '      --workspace <dir>   Workspace root',
        '      --clean             Start without demo seed data',
        '      --print-plist       Print macOS launchd plist XML and exit',
        '  -h, --help              Show help',
      ].join('\n'),
    );
    return;
  }

  const authHeaders = (): Record<string, string> =>
    opts.token ? { Authorization: `Bearer ${opts.token}` } : {};

  if (opts.mode === 'daemon_install') {
    const useSystemd = opts.serviceFormat === 'systemd' || (opts.serviceFormat === 'auto' && osPlatform() === 'linux');
    if (useSystemd) {
      console.log(
        buildLinuxSystemdService({
          role: opts.role,
          port: opts.port,
          hubUrl: opts.hubUrl,
          token: opts.token,
          nodeName: opts.nodeName,
          workspace: opts.workspacePath ?? process.cwd(),
        }),
      );
    } else {
      const server = new PipiResidentServer({ port: opts.port, host: opts.host, workspacePath: opts.workspacePath });
      console.log(server.buildLaunchdPlist(opts.port));
    }
    return;
  }

  if (opts.mode === 'nodes_list') {
    const resp = await fetch(`${opts.hubUrl}/api/v1/mesh/nodes`, { headers: authHeaders() });
    if (!resp.ok) {
      console.error(`Failed to list nodes from ${opts.hubUrl}: HTTP ${resp.status}`);
      process.exitCode = 1;
      return;
    }
    const json = (await resp.json()) as { nodes?: MeshNodeRecord[] };
    const nodes = json.nodes ?? [];
    if (nodes.length === 0) {
      console.log(`No nodes connected to ${opts.hubUrl} yet.`);
      return;
    }
    for (const n of nodes) {
      const gpu = n.telemetry.gpuSummary ? ` | GPU: ${n.telemetry.gpuSummary}` : '';
      const clis = n.cliAgents.length ? ` | CLIs: ${n.cliAgents.join(',')}` : '';
      console.log(`[${n.status.toUpperCase()}] ${n.name} (${n.nodeId}) — ${n.platform}/${n.arch}${clis}${gpu}`);
    }
    return;
  }

  if (opts.mode === 'run_remote') {
    if (!opts.targetNode || !opts.promptText) {
      console.error('Usage: pipibot run --node <nodeName> "<task>" [--hub <url>]');
      process.exitCode = 1;
      return;
    }
    const dispResp = await fetch(`${opts.hubUrl}/api/v1/mesh/dispatch`, {
      method: 'POST',
      headers: { ...authHeaders(), 'Content-Type': 'application/json' },
      body: JSON.stringify({ targetNodeId: opts.targetNode, prompt: opts.promptText }),
    });
    if (!dispResp.ok) {
      console.error(`Dispatch failed: HTTP ${dispResp.status} ${await dispResp.text()}`);
      process.exitCode = 1;
      return;
    }
    const { task } = (await dispResp.json()) as { task: MeshTaskRecord };
    console.log(`[pipibot] Dispatched ${task.taskId} -> ${opts.targetNode}`);
    // Poll until terminal state (keeps CLI simple & reliable)
    for (let attempt = 0; attempt < 180; attempt += 1) {
      await new Promise((r) => setTimeout(r, 500));
      const check = await fetch(`${opts.hubUrl}/api/v1/mesh/tasks/${encodeURIComponent(task.taskId)}`, {
        headers: authHeaders(),
      });
      if (!check.ok) continue;
      const body = (await check.json()) as { task: MeshTaskRecord };
      if (body.task.status === 'completed') {
        console.log(body.task.outputText);
        return;
      }
      if (body.task.status === 'failed') {
        console.error(`Remote task failed: ${body.task.error ?? 'unknown error'}`);
        process.exitCode = 1;
        return;
      }
    }
    console.error('Timed out waiting for remote node response.');
    process.exitCode = 1;
    return;
  }

  if (opts.mode === 'skills_list') {
    const resp = await fetch(`${opts.hubUrl}/api/v1/ecosystem`, { headers: authHeaders() });
    if (!resp.ok) {
      console.error(`Failed to query ecosystem from ${opts.hubUrl}: HTTP ${resp.status}`);
      process.exitCode = 1;
      return;
    }
    const json = (await resp.json()) as {
      skills?: Array<{ id: string; name: string; scope: string }>;
      mcpServers?: Array<{ id: string; name: string; transport: string }>;
    };
    console.log(`Installed Skills (${json.skills?.length ?? 0}):`);
    for (const s of json.skills ?? []) console.log(`  • ${s.name} (${s.id}) [${s.scope}]`);
    console.log(`Installed MCP Servers (${json.mcpServers?.length ?? 0}):`);
    for (const m of json.mcpServers ?? []) console.log(`  • ${m.name} (${m.id}) [${m.transport}]`);
    return;
  }

  if (opts.mode === 'skills_install') {
    if (!opts.skillSource) {
      console.error('Usage: pipibot skills install <github-url|local-path|catalog-id>');
      process.exitCode = 1;
      return;
    }
    const resp = await fetch(`${opts.hubUrl}/api/v1/ecosystem/skills`, {
      method: 'POST',
      headers: { ...authHeaders(), 'Content-Type': 'application/json' },
      body: JSON.stringify({ source: opts.skillSource }),
    });
    if (!resp.ok) {
      console.error(`Install failed: HTTP ${resp.status}`);
      process.exitCode = 1;
      return;
    }
    const json = (await resp.json()) as { skill?: { id: string; name: string } };
    console.log(`✅ Installed skill: ${json.skill?.name ?? opts.skillSource} (${json.skill?.id ?? ''})`);
    return;
  }

  if (opts.mode === 'mcp_stdio') {
    runBoundedMCPStdioLoop(opts.hubUrl, opts.token);
    return;
  }

  if (opts.mode === 'box_check') {
    const report = runBotBoxSelfCheck();
    console.log(JSON.stringify(report, null, 2));
    process.exitCode = report.allPassed ? 0 : 1;
    return;
  }

  if (opts.mode === 'sentinel_scan') {
    const issues = scanSentinelSamples([]);
    console.log(JSON.stringify({ scannedAt: new Date().toISOString(), issueCount: issues.length, issues }, null, 2));
    return;
  }

  if (opts.mode === 'team_apply') {
    const targetFile = opts.skillSource ?? opts.promptText;
    if (!targetFile) {
      console.error('Usage: pipibot team apply <team.md|team.yaml>');
      process.exitCode = 1;
      return;
    }
    const raw = readFileSync(targetFile, 'utf8');
    const parsed = parsePortableTemplate(raw);
    try {
      const resp = await fetch(`${opts.hubUrl}/api/v1/templates/apply`, {
        method: 'POST',
        headers: { ...authHeaders(), 'Content-Type': 'application/json' },
        body: JSON.stringify({ markdown: raw }),
      });
      if (resp.ok) {
        console.log(JSON.stringify(await resp.json(), null, 2));
        return;
      }
    } catch {
      // Offline preview output when Hub isn't running
    }
    console.log(JSON.stringify({ dryRun: true, template: parsed }, null, 2));
    return;
  }

  if (opts.mode === 'node_join') {
    const agent = new PipiMeshNodeAgent({
      hubUrl: opts.hubUrl,
      token: opts.token,
      name: opts.nodeName,
      workspacePath: opts.workspacePath,
    });
    const registered = await agent.start();
    console.log(`[pipibot-node v${DAEMON_VERSION}] joined Hub ${opts.hubUrl}`);
    console.log(`  - Node ID   : ${registered.nodeId}`);
    console.log(`  - Name      : ${registered.name} (${registered.platform}/${registered.arch})`);
    console.log(`  - Workspace : ${registered.workspacePath}`);
    console.log(`  - CLIs      : ${registered.cliAgents.join(', ') || 'none (native toolbox ready)'}`);
    const shutdown = () => {
      agent.stop();
      process.exit(0);
    };
    process.once('SIGINT', shutdown);
    process.once('SIGTERM', shutdown);
    return;
  }

  // Default: hub start
  const server = new PipiResidentServer({
    port: opts.port,
    host: opts.host,
    workspacePath: opts.workspacePath,
    hubToken: opts.token,
    seedDefaults: !opts.clean,
    seedFleet: !opts.clean,
    seedMemoryIfEmpty: !opts.clean,
  });

  if (opts.printPlistOnly) {
    console.log(server.buildLaunchdPlist(opts.port));
    return;
  }

  const baseUrl = await server.start();
  console.log(`[pipibot-hub v${DAEMON_VERSION}] listening on ${baseUrl}`);
  console.log(`  - Mesh Nodes      : ${baseUrl}/api/v1/mesh/nodes`);
  console.log(`  - Mesh Dispatch   : ${baseUrl}/api/v1/mesh/dispatch`);
  console.log(`  - Ecosystem API   : ${baseUrl}/api/v1/ecosystem`);
  console.log(`  - Systemd Unit    : ${baseUrl}/api/v1/systemd-service?role=node&name=linux-gpu`);
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
