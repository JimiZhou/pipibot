#!/usr/bin/env node
/**
 * @pipibot/core - pipibot-cli.ts
 *
 * PiPiBot — Clean-room MIT implementation.
 * Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
 * Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.
 *
 * Wave 3 (#11): Unified `pipibot` Local CLI.
 * - Single-source-of-truth command registry (`PIPIBOT_CLI_COMMANDS`):
 *   `--help`, `--schema` (JSON Schema), and `--permissions` (Guardrail ActionKind manifest)
 *   are generated deterministically from the exact same command definitions.
 * - Every write command supports `--operation-id` idempotency backed by `PipiOperationLedger`.
 */

import { realpathSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

import type { ActionKind, ArtifactDocumentKind, TeamCollaborationPattern, WikiEntityCategory } from '@pipibot/protocol';
import {
  BUILTIN_SKILL_PACKS,
  projectBuiltinSkillsReadOnly,
  verifyProjectedSkillsIntegrity,
} from './builtin-skills.ts';
import { PipiComputerUseCoordinator } from './computer-use.ts';
import { prepareIsolatedCliOverlay, type ReverseInjectedCliTarget } from './local-llm-gateway.ts';
import {
  detectLocalHardwareProfile,
  planLocalModelSetup,
  probeLocalInferenceEngines,
} from './model-autopilot.ts';
import { PipiOperationLedger } from './permission-guardrail.ts';
import { PipiPersonalWikiStore } from './personal-wiki.ts';
import { PipiPocketNotesEngine } from './pocket-notes.ts';
import { parseAndValidateTeamMd, renderTeamMdTemplate } from './team-protocol.ts';
import { defaultDailyVoiceConfig } from './voice-engine.ts';

// ---------------------------------------------------------------------------
// 1. Single-Source-of-Truth Command Definition Registry
// ---------------------------------------------------------------------------

export interface CliFlagSchema {
  name: string;
  type: 'string' | 'boolean' | 'number';
  required?: boolean;
  description: string;
  enum?: readonly string[];
}

export interface CliCommandDefinition {
  id: string; // e.g. "wiki.search"
  group: string;
  subcommand: string;
  summary: string;
  actionKind: ActionKind;
  requiresOperationId: boolean;
  flags: readonly CliFlagSchema[];
}

export const PIPIBOT_CLI_COMMANDS: readonly CliCommandDefinition[] = [
  {
    id: 'wiki.search',
    group: 'wiki',
    subcommand: 'search',
    summary: 'Zero-embedding dual-channel search across Personal Wiki pages, chunks, and facts.',
    actionKind: 'read_only',
    requiresOperationId: false,
    flags: [
      { name: 'query', type: 'string', required: true, description: 'Search query (supports CJK & English)' },
      { name: 'alternates', type: 'string', description: 'Comma-separated alternate wordings (max 6)' },
      { name: 'category', type: 'string', description: 'Filter by personal category', enum: ['people', 'projects', 'topics', 'life', 'repos'] },
      { name: 'start-date', type: 'string', description: 'Soft time-window start (YYYY-MM-DD)' },
      { name: 'end-date', type: 'string', description: 'Soft time-window end (YYYY-MM-DD)' },
    ],
  },
  {
    id: 'wiki.upsert',
    group: 'wiki',
    subcommand: 'upsert',
    summary: 'Create or update a Personal Wiki entity page with SQLite WAL indexing and Markdown projection.',
    actionKind: 'local_write',
    requiresOperationId: true,
    flags: [
      { name: 'category', type: 'string', required: true, description: 'Personal entity category', enum: ['people', 'projects', 'topics', 'life', 'repos'] },
      { name: 'title', type: 'string', required: true, description: 'Page title' },
      { name: 'summary', type: 'string', required: true, description: 'Concise summary' },
      { name: 'body', type: 'string', description: 'Markdown body content' },
      { name: 'aliases', type: 'string', description: 'Comma-separated aliases' },
      { name: 'event-date', type: 'string', description: 'Associated date (YYYY-MM-DD)' },
      { name: 'operation-id', type: 'string', description: 'Idempotency key for safe retries' },
    ],
  },
  {
    id: 'notes.save',
    group: 'notes',
    subcommand: 'save',
    summary: 'Save today’s (or specified YYYY-MM-DD) daily Pocket Note.',
    actionKind: 'local_write',
    requiresOperationId: true,
    flags: [
      { name: 'date', type: 'string', required: true, description: 'Calendar date (YYYY-MM-DD)' },
      { name: 'content', type: 'string', required: true, description: 'Markdown note content' },
      { name: 'operation-id', type: 'string', description: 'Idempotency key for safe retries' },
    ],
  },
  {
    id: 'notes.extract',
    group: 'notes',
    subcommand: 'extract',
    summary: 'Reconcile Tracking Items from a daily Pocket Note (5m silence or --force).',
    actionKind: 'local_write',
    requiresOperationId: false,
    flags: [
      { name: 'date', type: 'string', required: true, description: 'Calendar date (YYYY-MM-DD)' },
      { name: 'force', type: 'boolean', description: 'Bypass 5-minute silence window and reconcile immediately' },
    ],
  },
  {
    id: 'docs.upsert',
    group: 'docs',
    subcommand: 'upsert',
    summary: 'Create or revise an editable Artifact Document with SHA-256 tracking.',
    actionKind: 'local_write',
    requiresOperationId: true,
    flags: [
      { name: 'id', type: 'string', description: 'Existing document ID to revise' },
      { name: 'title', type: 'string', required: true, description: 'Document title' },
      { name: 'kind', type: 'string', description: 'Document kind', enum: ['note', 'report', 'spec', 'plan', 'draft'] },
      { name: 'markdown', type: 'string', required: true, description: 'Markdown body' },
      { name: 'operation-id', type: 'string', description: 'Idempotency key for safe retries' },
    ],
  },
  {
    id: 'docs.list',
    group: 'docs',
    subcommand: 'list',
    summary: 'List all editable Artifact Documents and their revision metadata.',
    actionKind: 'read_only',
    requiresOperationId: false,
    flags: [],
  },
  {
    id: 'skills.list',
    group: 'skills',
    subcommand: 'list',
    summary: 'List all versioned builtin office & personal skills with SHA-256 digests.',
    actionKind: 'read_only',
    requiresOperationId: false,
    flags: [],
  },
  {
    id: 'skills.project',
    group: 'skills',
    subcommand: 'project',
    summary: 'Project builtin versioned skills read-only (0444) into the local data root with SHA-256 verification.',
    actionKind: 'local_write',
    requiresOperationId: false,
    flags: [
      { name: 'slugs', type: 'string', description: 'Optional comma-separated skill slugs to project' },
    ],
  },
  {
    id: 'skills.verify',
    group: 'skills',
    subcommand: 'verify',
    summary: 'Verify SHA-256 integrity of projected read-only builtin skills.',
    actionKind: 'read_only',
    requiresOperationId: false,
    flags: [],
  },
  {
    id: 'team.validate',
    group: 'team',
    subcommand: 'validate',
    summary: 'Parse and validate a team.md multi-bot collaboration protocol file including DAG cycle checks.',
    actionKind: 'read_only',
    requiresOperationId: false,
    flags: [
      { name: 'file', type: 'string', required: true, description: 'Path to team.md file' },
      { name: 'room-members', type: 'string', description: 'Optional comma-separated Actor IDs in room' },
    ],
  },
  {
    id: 'team.template',
    group: 'team',
    subcommand: 'template',
    summary: 'Generate a canonical team.md template for any of the 5 collaboration patterns.',
    actionKind: 'read_only',
    requiresOperationId: false,
    flags: [
      {
        name: 'pattern',
        type: 'string',
        required: true,
        description: 'Collaboration topology pattern',
        enum: ['classify-and-act', 'fan-out-and-synthesize', 'adversarial-verification', 'tournament', 'loop-until-done'],
      },
      { name: 'goal', type: 'string', required: true, description: 'Collaboration task goal' },
    ],
  },
  {
    id: 'model.plan',
    group: 'model',
    subcommand: 'plan',
    summary: 'Inspect host hardware and generate a 5-layer local Model Autopilot & PolyStrata (MIT) plan.',
    actionKind: 'read_only',
    requiresOperationId: false,
    flags: [
      { name: 'ram-gb', type: 'number', description: 'Optional simulated system/unified RAM in GB' },
      { name: 'vram-gb', type: 'number', description: 'Optional simulated discrete GPU VRAM in GB' },
    ],
  },
  {
    id: 'model.gateway-env',
    group: 'model',
    subcommand: 'gateway-env',
    summary: 'Materialize an isolated CLI agent environment overlay (CLAUDE_CONFIG_DIR/CODEX_HOME/PI_CODING_AGENT_DIR) pointing to the loopback Gateway.',
    actionKind: 'local_write',
    requiresOperationId: false,
    flags: [
      { name: 'cli', type: 'string', required: true, description: 'Target CLI agent', enum: ['claude-code', 'codex', 'pi', 'opencode'] },
      { name: 'gateway-origin', type: 'string', required: true, description: 'Loopback gateway origin (e.g. http://127.0.0.1:18432)' },
      { name: 'token', type: 'string', required: true, description: 'Local gateway bearer token' },
      { name: 'model', type: 'string', required: true, description: 'Model ID routed through gateway' },
    ],
  },
  {
    id: 'voice.status',
    group: 'voice',
    subcommand: 'status',
    summary: 'Show personal daily voice defaults (on-device-first STT/TTS, echo-gated VAD, and privacy policy).',
    actionKind: 'read_only',
    requiresOperationId: false,
    flags: [],
  },
  {
    id: 'computer.journal',
    group: 'computer',
    subcommand: 'journal',
    summary: 'Inspect the Computer Use Write-Ahead Journal (WAL) and active/locked lanes.',
    actionKind: 'read_only',
    requiresOperationId: false,
    flags: [],
  },
  {
    id: 'computer.unlock-lane',
    group: 'computer',
    subcommand: 'unlock-lane',
    summary: 'Acknowledge an unknown_outcome WAL entry and unlock a blocked Computer Use lane after human inspection.',
    actionKind: 'local_write',
    requiresOperationId: false,
    flags: [
      { name: 'lane', type: 'string', required: true, description: 'Lane ID (e.g. screen:global or browser:bot_coder)' },
      { name: 'note', type: 'string', description: 'Optional human review note' },
    ],
  },
];

// ---------------------------------------------------------------------------
// 2. Single-Source Generators: --help, --schema, --permissions
// ---------------------------------------------------------------------------

export function generateCliHelpText(commandId?: string): string {
  if (commandId) {
    const cmd = PIPIBOT_CLI_COMMANDS.find((c) => c.id === commandId);
    if (!cmd) return `Unknown command: ${commandId}`;
    const flagLines = cmd.flags.map(
      (f) =>
        `  --${f.name}${f.type === 'boolean' ? '' : ` <${f.type}>`}${f.required ? ' (required)' : ''}\t${f.description}`,
    );
    return [
      `pipibot ${cmd.group} ${cmd.subcommand} — ${cmd.summary}`,
      `Permission ActionKind: ${cmd.actionKind}${cmd.requiresOperationId ? ' (supports --operation-id idempotency)' : ''}`,
      flagLines.length > 0 ? '\nFlags:\n' + flagLines.join('\n') : '\nNo flags.',
    ].join('\n');
  }

  const lines = [
    'pipibot — Unified Local Agent CLI (single-source-of-truth help, --schema, --permissions)',
    'Usage: pipibot <group> <subcommand> [flags]',
    'Global inspection flags: --help | --schema | --permissions | --root <dir>',
    '',
    'Commands:',
  ];
  for (const cmd of PIPIBOT_CLI_COMMANDS) {
    lines.push(`  ${cmd.group} ${cmd.subcommand.padEnd(10)} [${cmd.actionKind}] ${cmd.summary}`);
  }
  return lines.join('\n');
}

export function generateCliJsonSchema(commandId?: string): Record<string, unknown> {
  const list = commandId
    ? PIPIBOT_CLI_COMMANDS.filter((c) => c.id === commandId)
    : [...PIPIBOT_CLI_COMMANDS];
  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    title: 'PiPiBot Unified CLI Contract',
    commands: list.map((cmd) => ({
      id: cmd.id,
      usage: `pipibot ${cmd.group} ${cmd.subcommand}`,
      summary: cmd.summary,
      actionKind: cmd.actionKind,
      requiresOperationId: cmd.requiresOperationId,
      parameters: {
        type: 'object',
        additionalProperties: false,
        required: cmd.flags.filter((f) => f.required).map((f) => f.name),
        properties: Object.fromEntries(
          cmd.flags.map((f) => [
            f.name,
            {
              type: f.type,
              description: f.description,
              ...(f.enum ? { enum: [...f.enum] } : {}),
            },
          ]),
        ),
      },
    })),
  };
}

export function generateCliPermissionManifest(): Array<{
  commandId: string;
  actionKind: ActionKind;
  requiresOperationId: boolean;
}> {
  return PIPIBOT_CLI_COMMANDS.map((c) => ({
    commandId: c.id,
    actionKind: c.actionKind,
    requiresOperationId: c.requiresOperationId,
  }));
}

// ---------------------------------------------------------------------------
// 3. Arg Parser & Executor
// ---------------------------------------------------------------------------

export interface CliRunOutput {
  exitCode: number;
  stdout: string;
  stderr: string;
  replayedIdempotent?: boolean;
}

function parseFlags(argv: readonly string[]): { positional: string[]; flags: Record<string, string | boolean> } {
  const positional: string[] = [];
  const flags: Record<string, string | boolean> = {};
  for (let i = 0; i < argv.length; i += 1) {
    const tok = argv[i] ?? '';
    if (tok.startsWith('--')) {
      const eqIdx = tok.indexOf('=');
      if (eqIdx > 2) {
        flags[tok.slice(2, eqIdx)] = tok.slice(eqIdx + 1);
      } else {
        const key = tok.slice(2);
        const next = argv[i + 1];
        if (next && !next.startsWith('--')) {
          flags[key] = next;
          i += 1;
        } else {
          flags[key] = true;
        }
      }
    } else if (tok === '-h') {
      flags.help = true;
    } else {
      positional.push(tok);
    }
  }
  return { positional, flags };
}

export async function runPipiBotCli(
  argv: readonly string[],
  options: { rootDir?: string; ledger?: PipiOperationLedger } = {},
): Promise<CliRunOutput> {
  const { positional, flags } = parseFlags(argv);
  const rootDir =
    (typeof flags.root === 'string' && flags.root) ||
    (typeof flags['data-dir'] === 'string' && flags['data-dir']) ||
    options.rootDir ||
    join(homedir(), '.pipibot');
  const ledger = options.ledger ?? new PipiOperationLedger();

  const group = positional[0];
  const sub = positional[1];
  const cmdId = group && sub ? `${group}.${sub}` : undefined;

  if (flags.permissions) {
    return { exitCode: 0, stdout: JSON.stringify(generateCliPermissionManifest(), null, 2), stderr: '' };
  }
  if (flags.schema) {
    return { exitCode: 0, stdout: JSON.stringify(generateCliJsonSchema(cmdId), null, 2), stderr: '' };
  }
  if (flags.help || positional.length === 0) {
    return { exitCode: 0, stdout: generateCliHelpText(cmdId), stderr: '' };
  }

  const def = PIPIBOT_CLI_COMMANDS.find((c) => c.group === group && c.subcommand === sub);
  if (!def) {
    return {
      exitCode: 2,
      stdout: '',
      stderr: `Unknown command "${positional.join(' ')}". Run with --help to inspect available commands.`,
    };
  }

  for (const flagDef of def.flags) {
    if (flagDef.required && flags[flagDef.name] === undefined) {
      return { exitCode: 2, stdout: '', stderr: `Missing required flag --${flagDef.name} for ${def.id}.` };
    }
  }

  const opId = typeof flags['operation-id'] === 'string' ? flags['operation-id'].trim() : undefined;
  if (opId && def.requiresOperationId) {
    const prior = ledger.get(opId);
    if (prior?.status === 'completed' && prior.cachedResultSummary !== undefined) {
      let cachedParsed: unknown = prior.cachedResultSummary;
      try {
        cachedParsed = JSON.parse(prior.cachedResultSummary);
      } catch {
        // leave as string
      }
      return {
        exitCode: 0,
        stdout: JSON.stringify({ idempotentReplay: true, operationId: opId, result: cachedParsed }, null, 2),
        stderr: '',
        replayedIdempotent: true,
      };
    }
    if (prior?.status === 'unknown_outcome') {
      return {
        exitCode: 1,
        stdout: '',
        stderr: `Operation ${opId} previously finished with unknown_outcome; refusing unsafe blind replay.`,
      };
    }
    ledger.markInFlight(opId);
  }

  try {
    let payload: unknown;

    switch (def.id) {
      case 'wiki.search': {
        const wiki = new PipiPersonalWikiStore({ dbPath: join(rootDir, 'wiki.sqlite'), markdownRootDir: rootDir });
        try {
          payload = wiki.search({
            query: String(flags.query),
            alternates: typeof flags.alternates === 'string' ? flags.alternates.split(',').map((s) => s.trim()) : [],
            category: typeof flags.category === 'string' ? (flags.category as WikiEntityCategory) : undefined,
            startDate: typeof flags['start-date'] === 'string' ? flags['start-date'] : undefined,
            endDate: typeof flags['end-date'] === 'string' ? flags['end-date'] : undefined,
          });
        } finally {
          wiki.close();
        }
        break;
      }
      case 'wiki.upsert': {
        const wiki = new PipiPersonalWikiStore({ dbPath: join(rootDir, 'wiki.sqlite'), markdownRootDir: rootDir });
        try {
          payload = await wiki.upsertPage({
            category: String(flags.category) as WikiEntityCategory,
            title: String(flags.title),
            summary: String(flags.summary),
            bodyMarkdown: typeof flags.body === 'string' ? flags.body : String(flags.summary),
            aliases: typeof flags.aliases === 'string' ? flags.aliases.split(',').map((s) => s.trim()) : [],
            eventDate: typeof flags['event-date'] === 'string' ? flags['event-date'] : undefined,
          });
        } finally {
          wiki.close();
        }
        break;
      }
      case 'notes.save': {
        const engine = new PipiPocketNotesEngine({ rootDir });
        payload = await engine.saveDailyNote(String(flags.date), String(flags.content));
        break;
      }
      case 'notes.extract': {
        const engine = new PipiPocketNotesEngine({ rootDir });
        payload = await engine.reconcileDailyNoteIfQuiet(String(flags.date), { force: Boolean(flags.force) });
        break;
      }
      case 'docs.upsert': {
        const engine = new PipiPocketNotesEngine({ rootDir });
        payload = await engine.upsertDocument({
          id: typeof flags.id === 'string' ? flags.id : undefined,
          title: String(flags.title),
          kind: (typeof flags.kind === 'string' ? flags.kind : 'note') as ArtifactDocumentKind,
          markdown: String(flags.markdown),
        });
        break;
      }
      case 'docs.list': {
        const engine = new PipiPocketNotesEngine({ rootDir });
        payload = await engine.listDocuments();
        break;
      }
      case 'skills.list': {
        payload = BUILTIN_SKILL_PACKS.map((s) => ({
          slug: s.slug,
          version: s.version,
          category: s.category,
          titleEn: s.titleEn,
          titleZh: s.titleZh,
          sha256: s.sha256,
        }));
        break;
      }
      case 'skills.project': {
        const slugs = typeof flags.slugs === 'string' ? flags.slugs.split(',').map((s) => s.trim()).filter(Boolean) : undefined;
        payload = await projectBuiltinSkillsReadOnly(rootDir, slugs);
        break;
      }
      case 'skills.verify': {
        payload = await verifyProjectedSkillsIntegrity(rootDir);
        break;
      }
      case 'team.validate': {
        const content = await readFile(String(flags.file), 'utf8');
        const roomMemberActorIds =
          typeof flags['room-members'] === 'string'
            ? flags['room-members'].split(',').map((s) => s.trim()).filter(Boolean)
            : undefined;
        payload = parseAndValidateTeamMd(content, { roomMemberActorIds });
        break;
      }
      case 'team.template': {
        const rendered = renderTeamMdTemplate({
          pattern: String(flags.pattern) as TeamCollaborationPattern,
          taskGoal: String(flags.goal),
          orchestrator: { name: 'PiPi Lead', actorId: 'bot_pipi_general' },
          members: [
            { name: 'Coder', actorId: 'bot_coder', role: 'Implementation & architecture' },
            { name: 'Reviewer', actorId: 'bot_writer', role: 'Verification & clarity review' },
          ],
        });
        return { exitCode: 0, stdout: rendered, stderr: '' };
      }
      case 'model.plan': {
        const hw = await detectLocalHardwareProfile({
          ...(typeof flags['ram-gb'] === 'number' ? { totalRamGb: flags['ram-gb'] } : {}),
          ...(typeof flags['vram-gb'] === 'number'
            ? { gpuVramGb: flags['vram-gb'], unifiedMemory: false, isAppleSilicon: false, platformClass: 'linux_nvidia' }
            : {}),
        });
        const installedEngines = await probeLocalInferenceEngines();
        payload = {
          plan: planLocalModelSetup(hw, { installedEngines }),
          engines: installedEngines,
        };
        break;
      }
      case 'model.gateway-env': {
        payload = await prepareIsolatedCliOverlay({
          dataRootDir: rootDir,
          cli: String(flags.cli) as ReverseInjectedCliTarget,
          gatewayOrigin: String(flags['gateway-origin']),
          gatewayToken: String(flags.token),
          modelId: String(flags.model),
        });
        break;
      }
      case 'voice.status': {
        payload = {
          defaults: defaultDailyVoiceConfig(),
          supportedModes: ['dictation', 'muse_hands_free', 'voice_to_task'],
          privacyPolicies: ['on_device_only', 'on_device_first', 'cloud_preferred'],
        };
        break;
      }
      case 'computer.journal': {
        const cu = new PipiComputerUseCoordinator({ rootDir });
        await cu.initialize();
        payload = {
          config: cu.config,
          lanes: cu.listLanes(),
          entries: cu.journal.listEntries(),
        };
        break;
      }
      case 'computer.unlock-lane': {
        const cu = new PipiComputerUseCoordinator({ rootDir });
        await cu.initialize();
        const unlocked = await cu.acknowledgeUnknownOutcomeAndUnlockLane(
          String(flags.lane),
          typeof flags.note === 'string' ? flags.note : undefined,
        );
        payload = { lane: String(flags.lane), unlocked, lanes: cu.listLanes() };
        break;
      }
    }

    if (opId && def.requiresOperationId) {
      ledger.markCompleted(opId, JSON.stringify(payload));
    }

    return { exitCode: 0, stdout: JSON.stringify(payload, null, 2), stderr: '' };
  } catch (err) {
    if (opId && def.requiresOperationId) {
      ledger.markUnknownOutcome(opId);
    }
    return { exitCode: 1, stdout: '', stderr: err instanceof Error ? err.message : String(err) };
  }
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
  void runPipiBotCli(process.argv.slice(2)).then((res) => {
    if (res.stdout) process.stdout.write(res.stdout + '\n');
    if (res.stderr) process.stderr.write(res.stderr + '\n');
    process.exitCode = res.exitCode;
  });
}
