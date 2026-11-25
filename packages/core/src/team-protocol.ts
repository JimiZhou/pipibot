/**
 * @pipibot/core - team-protocol.ts
 *
 * PiPiBot — Clean-room MIT implementation.
 * Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
 * Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.
 *
 * Wave 3 (#06): Structured `team.md` Multi-Bot Collaboration Protocol.
 * - Full support for all 5 collaboration topologies:
 *   1. `classify-and-act`
 *   2. `fan-out-and-synthesize`
 *   3. `adversarial-verification`
 *   4. `tournament`
 *   5. `loop-until-done`
 * - Pure parser + multi-issue structured validator + DAG topological wave / cycle checker
 * - Dynamic Bot invite / create approval workflow (`DynamicBotProposal`) when `team.md`
 *   requests a role or Actor ID not yet in the group chat
 */

import { randomUUID } from 'node:crypto';

import type {
  DynamicBotProposalAction,
  DynamicBotProposalStatus,
  TeamCollaborationPattern,
} from '@pipibot/protocol';

const CANONICAL_TEAM_PATTERNS: readonly TeamCollaborationPattern[] = [
  'classify-and-act',
  'fan-out-and-synthesize',
  'adversarial-verification',
  'tournament',
  'loop-until-done',
];

// ---------------------------------------------------------------------------
// 1. Public Contracts & Validation Issue Codes
// ---------------------------------------------------------------------------

export const MAX_TEAM_MD_BYTES = 64 * 1024;
export const MAX_TEAM_MEMBERS = 50;
export const DEFAULT_MAX_LOOP_ROUNDS = 3;
export const MAX_ALLOWED_LOOP_ROUNDS = 6;

export interface TeamMdIssue {
  path: string;
  code: string;
  message: string;
}

export interface TeamParticipant {
  name: string;
  actorId: string;
  role: string;
  reportTo: string[];
  receiveFrom: string[];
  harness?: string;
  model?: string;
  worktree?: boolean;
}

export interface TeamMdDocument {
  pattern: TeamCollaborationPattern;
  maxRounds: number;
  taskGoal: string;
  orchestrator: TeamParticipant;
  members: TeamParticipant[];
}

export interface TeamMdValidationResult {
  valid: boolean;
  document: TeamMdDocument | null;
  issues: TeamMdIssue[];
  executionWaves: string[][];
  missingMemberActorIds: string[];
}

export interface DynamicBotProposal {
  id: string;
  groupId: string;
  action: DynamicBotProposalAction;
  status: DynamicBotProposalStatus;
  requestedActorId: string;
  existingBotId?: string;
  proposedName: string;
  proposedRole: string;
  proposedSystemPrompt: string;
  rationale: string;
  createdAt: string;
}

export interface TeamBotTurnRequest {
  actorId: string;
  memberName: string;
  role: string;
  pattern: TeamCollaborationPattern;
  phase: 'classify' | 'execute' | 'verify' | 'judge' | 'synthesize' | 'loop_step';
  round: number;
  prompt: string;
  upstreamOutputs: Array<{ actorId: string; memberName: string; output: string }>;
}

export interface TeamBotTurnResponse {
  output: string;
  selectedActorId?: string; // for classify-and-act / tournament winner
  approved?: boolean; // for adversarial-verification
  done?: boolean; // for loop-until-done
}

export type TeamBotExecutor = (req: TeamBotTurnRequest) => Promise<TeamBotTurnResponse>;

export interface TeamExecutionTraceEntry {
  phase: TeamBotTurnRequest['phase'];
  round: number;
  actorId: string;
  memberName: string;
  output: string;
}

export interface TeamExecutionResult {
  pattern: TeamCollaborationPattern;
  roundsExecuted: number;
  winnerActorId?: string;
  verifiedApproved?: boolean;
  completed?: boolean;
  finalOutput: string;
  trace: TeamExecutionTraceEntry[];
}

// ---------------------------------------------------------------------------
// 2. Pure `team.md` Parser, Validator & DAG Cycle Checker
// ---------------------------------------------------------------------------

function splitCsvList(raw: string): string[] {
  const cleaned = raw.trim();
  if (!cleaned || /^none$/i.test(cleaned) || cleaned === '-' || cleaned === '[]') {
    return [];
  }
  return cleaned
    .replace(/^\[|\]$/g, '')
    .split(/[,，]/)
    .map((s) => s.trim())
    .filter(Boolean);
}

function parseParticipantBlock(
  blockLines: string[],
  defaultName: string,
  pathPrefix: string,
  issues: TeamMdIssue[],
): TeamParticipant {
  let name = defaultName;
  let actorId = '';
  let role = '';
  let reportTo: string[] = [];
  let receiveFrom: string[] = [];
  let harness: string | undefined;
  let model: string | undefined;
  let worktree: boolean | undefined;
  const seenAttrs = new Set<string>();

  for (const rawLine of blockLines) {
    const line = rawLine.trim();
    if (!line) continue;
    if (line.startsWith('## ')) {
      name = line.slice(3).trim();
      continue;
    }
    const attrMatch = line.match(/^[-*]\s+([^:]+):\s*(.*)$/);
    if (!attrMatch) continue;
    const keyRaw = (attrMatch[1] ?? '').trim().toLowerCase().replace(/\s+/g, '_');
    const val = (attrMatch[2] ?? '').trim();

    if (seenAttrs.has(keyRaw)) {
      issues.push({
        path: `${pathPrefix}.${keyRaw}`,
        code: 'team_md_attribute_duplicated',
        message: `Duplicate attribute "${attrMatch[1]}" for participant "${name}".`,
      });
      continue;
    }
    seenAttrs.add(keyRaw);

    switch (keyRaw) {
      case 'name':
        name = val;
        break;
      case 'actor_id':
        actorId = val;
        break;
      case 'role':
        role = val;
        break;
      case 'report_to':
        reportTo = splitCsvList(val);
        break;
      case 'receive_from':
        receiveFrom = splitCsvList(val);
        break;
      case 'harness':
        harness = val || undefined;
        break;
      case 'model':
        model = val || undefined;
        break;
      case 'worktree':
        worktree = /^(true|yes|1|isolated|auto)$/i.test(val);
        break;
      default:
        issues.push({
          path: `${pathPrefix}.${keyRaw}`,
          code: 'team_md_attribute_unknown',
          message: `Unknown participant attribute "${attrMatch[1]}".`,
        });
    }
  }

  if (!name) {
    issues.push({ path: `${pathPrefix}.name`, code: 'team_md_name_invalid', message: 'Participant name is required.' });
  }
  if (!actorId) {
    issues.push({
      path: `${pathPrefix}.actor_id`,
      code: 'team_md_actor_id_missing',
      message: `Participant "${name || pathPrefix}" is missing Actor ID.`,
    });
  }

  return {
    name,
    actorId,
    role,
    reportTo,
    receiveFrom,
    ...(harness ? { harness } : {}),
    ...(model ? { model } : {}),
    ...(worktree !== undefined ? { worktree } : {}),
  };
}

export function parseAndValidateTeamMd(
  content: string,
  options: { roomMemberActorIds?: string[] } = {},
): TeamMdValidationResult {
  const issues: TeamMdIssue[] = [];

  if (!content || !content.trim()) {
    issues.push({ path: 'document', code: 'team_md_content_invalid', message: 'team.md content is empty.' });
    return { valid: false, document: null, issues, executionWaves: [], missingMemberActorIds: [] };
  }

  if (Buffer.byteLength(content, 'utf8') > MAX_TEAM_MD_BYTES) {
    issues.push({
      path: 'document',
      code: 'team_md_content_too_large',
      message: `team.md exceeds ${MAX_TEAM_MD_BYTES} bytes.`,
    });
    return { valid: false, document: null, issues, executionWaves: [], missingMemberActorIds: [] };
  }

  const normalized = content.replace(/\r\n/g, '\n');
  const fmMatch = normalized.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!fmMatch) {
    issues.push({
      path: 'frontmatter',
      code: 'team_md_frontmatter_missing',
      message: 'YAML frontmatter (--- ... ---) declaring collaborate_pattern is required.',
    });
    return { valid: false, document: null, issues, executionWaves: [], missingMemberActorIds: [] };
  }

  const fmText = fmMatch[1] ?? '';
  const bodyText = fmMatch[2] ?? '';

  let rawPattern = '';
  let maxRounds = DEFAULT_MAX_LOOP_ROUNDS;

  for (const rawLine of fmText.split('\n')) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const kv = line.match(/^([a-zA-Z0-9_-]+)\s*:\s*(.+)$/);
    if (!kv) {
      issues.push({
        path: 'frontmatter',
        code: 'team_md_frontmatter_invalid',
        message: `Malformed frontmatter line: "${line}".`,
      });
      continue;
    }
    const key = (kv[1] ?? '').trim();
    const val = (kv[2] ?? '').trim().replace(/^["']|["']$/g, '');
    if (key === 'collaborate_pattern') {
      rawPattern = val;
    } else if (key === 'max_rounds') {
      const n = Number(val);
      if (Number.isInteger(n) && n >= 1 && n <= MAX_ALLOWED_LOOP_ROUNDS) {
        maxRounds = n;
      } else {
        issues.push({
          path: 'frontmatter.max_rounds',
          code: 'team_md_frontmatter_invalid',
          message: `max_rounds must be an integer between 1 and ${MAX_ALLOWED_LOOP_ROUNDS}.`,
        });
      }
    }
  }

  if (!rawPattern) {
    issues.push({
      path: 'frontmatter.collaborate_pattern',
      code: 'team_md_pattern_missing',
      message: 'Frontmatter must declare collaborate_pattern.',
    });
  } else if (!(CANONICAL_TEAM_PATTERNS as readonly string[]).includes(rawPattern)) {
    issues.push({
      path: 'frontmatter.collaborate_pattern',
      code: 'team_md_pattern_invalid',
      message: `Unsupported collaborate_pattern "${rawPattern}". Allowed: ${CANONICAL_TEAM_PATTERNS.join(', ')}.`,
    });
  }

  // Split H1 sections (# Task Goal, # Orchestrator, # Team Members)
  const sections = new Map<string, string[]>();
  let currentSec: string | null = null;
  for (const line of bodyText.split('\n')) {
    const h1 = line.match(/^#\s+(.+)$/);
    if (h1?.[1]) {
      const secName = h1[1].trim().toLowerCase();
      if (!['task goal', 'orchestrator', 'team members'].includes(secName)) {
        issues.push({
          path: `sections.${secName}`,
          code: 'team_md_section_unknown',
          message: `Unknown top-level section "# ${h1[1].trim()}".`,
        });
        currentSec = null;
        continue;
      }
      if (sections.has(secName)) {
        issues.push({
          path: `sections.${secName}`,
          code: 'team_md_section_duplicated',
          message: `Duplicate top-level section "# ${h1[1].trim()}".`,
        });
        currentSec = null;
        continue;
      }
      sections.set(secName, []);
      currentSec = secName;
    } else if (currentSec) {
      sections.get(currentSec)?.push(line);
    }
  }

  for (const requiredSec of ['task goal', 'orchestrator', 'team members']) {
    if (!sections.has(requiredSec)) {
      issues.push({
        path: `sections.${requiredSec}`,
        code: 'team_md_section_missing',
        message: `Missing required section "# ${requiredSec}".`,
      });
    }
  }

  const taskGoal = (sections.get('task goal') ?? []).join('\n').trim();
  if (!taskGoal) {
    issues.push({
      path: 'task_goal',
      code: 'team_md_task_goal_missing',
      message: 'Task Goal section must describe the collaboration objective.',
    });
  }

  const orchestrator = parseParticipantBlock(
    sections.get('orchestrator') ?? [],
    'Orchestrator',
    'orchestrator',
    issues,
  );

  // Split Team Members by H2 (`## Name`)
  const memberLines = sections.get('team members') ?? [];
  const memberBlocks: Array<{ name: string; lines: string[] }> = [];
  let activeMember: { name: string; lines: string[] } | null = null;
  for (const line of memberLines) {
    const h2 = line.match(/^##\s+(.+)$/);
    if (h2?.[1]) {
      if (activeMember) memberBlocks.push(activeMember);
      activeMember = { name: h2[1].trim(), lines: [] };
    } else if (activeMember) {
      activeMember.lines.push(line);
    }
  }
  if (activeMember) memberBlocks.push(activeMember);

  if (memberBlocks.length === 0) {
    issues.push({
      path: 'members',
      code: 'team_md_member_missing',
      message: 'At least one Team Member (## <Name>) is required.',
    });
  } else if (memberBlocks.length > MAX_TEAM_MEMBERS) {
    issues.push({
      path: 'members',
      code: 'team_md_too_many_members',
      message: `Team members exceed maximum limit (${MAX_TEAM_MEMBERS}).`,
    });
  }

  const members: TeamParticipant[] = memberBlocks.map((blk, idx) =>
    parseParticipantBlock(blk.lines, blk.name, `members[${idx}]`, issues),
  );

  // Check duplicate names & actor IDs
  const allParticipants = [orchestrator, ...members];
  const seenNames = new Set<string>();
  const seenActorIds = new Set<string>();
  for (const p of allParticipants) {
    const nl = p.name.toLowerCase();
    if (nl && !seenNames.has(nl)) {
      seenNames.add(nl);
    } else if (nl) {
      issues.push({ path: `participant.${p.name}`, code: 'team_md_name_duplicated', message: `Duplicate name "${p.name}".` });
    }
    if (p.actorId && !seenActorIds.has(p.actorId)) {
      seenActorIds.add(p.actorId);
    } else if (p.actorId) {
      issues.push({
        path: `participant.${p.actorId}`,
        code: 'team_md_actor_id_duplicated',
        message: `Duplicate Actor ID "${p.actorId}".`,
      });
    }
  }

  // Reference resolution & DAG construction
  const nameToActorId = new Map<string, string>();
  for (const p of allParticipants) {
    if (p.actorId) {
      nameToActorId.set(p.actorId.toLowerCase(), p.actorId);
      if (p.name) nameToActorId.set(p.name.toLowerCase(), p.actorId);
    }
  }

  const memberIds = new Set(members.map((m) => m.actorId).filter(Boolean));
  const deps = new Map<string, Set<string>>();
  for (const m of members) {
    if (m.actorId) deps.set(m.actorId, new Set<string>());
  }

  for (const p of allParticipants) {
    for (const ref of [...p.receiveFrom, ...p.reportTo]) {
      if (!nameToActorId.has(ref.toLowerCase())) {
        issues.push({
          path: `participant.${p.name}.references`,
          code: 'team_md_reference_unknown',
          message: `Unknown participant reference "${ref}" in "${p.name}".`,
        });
      }
    }
    if (memberIds.has(p.actorId)) {
      for (const upstreamRef of p.receiveFrom) {
        const upId = nameToActorId.get(upstreamRef.toLowerCase());
        if (upId && memberIds.has(upId) && upId !== p.actorId) {
          deps.get(p.actorId)?.add(upId);
        }
      }
    }
  }

  // Room membership verification (non-members become candidates for Dynamic Bot Proposals!)
  const missingMemberActorIds: string[] = [];
  if (options.roomMemberActorIds) {
    const roomSet = new Set(options.roomMemberActorIds);
    for (const p of allParticipants) {
      if (p.actorId && !roomSet.has(p.actorId)) {
        missingMemberActorIds.push(p.actorId);
        issues.push({
          path: `participant.${p.actorId}`,
          code: 'team_md_actor_not_room_member',
          message: `Actor "${p.actorId}" (${p.name}) is not currently a member of this group chat.`,
        });
      }
    }
  }

  // DAG topological sort (Kahn's algorithm) over team members
  const pattern = ((CANONICAL_TEAM_PATTERNS as readonly string[]).includes(rawPattern)
    ? rawPattern
    : 'fan-out-and-synthesize') as TeamCollaborationPattern;
  const allowsBoundedCycle = pattern === 'adversarial-verification' || pattern === 'loop-until-done';

  const executionWaves: string[][] = [];
  const remaining = new Map<string, Set<string>>();
  for (const [id, d] of deps.entries()) {
    remaining.set(id, new Set(d));
  }

  while (remaining.size > 0) {
    const ready: string[] = [];
    for (const [id, d] of remaining.entries()) {
      if (d.size === 0) ready.push(id);
    }
    if (ready.length === 0) {
      if (!allowsBoundedCycle) {
        issues.push({
          path: 'dag',
          code: 'team_md_cycle_detected',
          message: `Circular dependency detected in pattern "${pattern}". Use adversarial-verification or loop-until-done for bounded cycles.`,
        });
      } else {
        // Bounded iterative pattern: emit remaining members as an ordered wave
        executionWaves.push(Array.from(remaining.keys()));
      }
      break;
    }
    executionWaves.push(ready);
    for (const id of ready) {
      remaining.delete(id);
    }
    for (const d of remaining.values()) {
      for (const id of ready) d.delete(id);
    }
  }

  const doc: TeamMdDocument | null =
    rawPattern && taskGoal && orchestrator.actorId && members.length > 0
      ? { pattern, maxRounds, taskGoal, orchestrator, members }
      : null;

  return {
    valid: issues.length === 0 && doc !== null,
    document: doc,
    issues,
    executionWaves,
    missingMemberActorIds,
  };
}

// ---------------------------------------------------------------------------
// 3. Template Renderer & Dynamic Bot Invite / Create Proposal Builder
// ---------------------------------------------------------------------------

export function renderTeamMdTemplate(input: {
  pattern: TeamCollaborationPattern;
  taskGoal: string;
  orchestrator: { name: string; actorId: string; role?: string };
  members: Array<{ name: string; actorId: string; role: string; receiveFrom?: string[]; reportTo?: string[] }>;
  maxRounds?: number;
}): string {
  const roundsLine =
    input.pattern === 'adversarial-verification' || input.pattern === 'loop-until-done'
      ? `max_rounds: ${input.maxRounds ?? DEFAULT_MAX_LOOP_ROUNDS}\n`
      : '';
  const memberBlocks = input.members.map((m) => {
    const recv = m.receiveFrom && m.receiveFrom.length > 0 ? m.receiveFrom.join(', ') : input.orchestrator.name;
    const rep = m.reportTo && m.reportTo.length > 0 ? m.reportTo.join(', ') : input.orchestrator.name;
    return [
      `## ${m.name}`,
      `- Actor ID: ${m.actorId}`,
      `- Role: ${m.role}`,
      `- Receive from: ${recv}`,
      `- Report to: ${rep}`,
    ].join('\n');
  });

  return [
    '---',
    `collaborate_pattern: ${input.pattern}`,
    roundsLine ? roundsLine.trimEnd() : null,
    '---',
    '',
    '# Task Goal',
    input.taskGoal.trim(),
    '',
    '# Orchestrator',
    `## ${input.orchestrator.name}`,
    `- Actor ID: ${input.orchestrator.actorId}`,
    `- Role: ${input.orchestrator.role ?? 'Lead coordinator & synthesizer'}`,
    `- Report to: none`,
    `- Receive from: ${input.members.map((m) => m.name).join(', ') || 'none'}`,
    '',
    '# Team Members',
    memberBlocks.join('\n\n'),
    '',
  ]
    .filter((line): line is string => line !== null)
    .join('\n');
}

export function buildDynamicBotProposals(input: {
  groupId: string;
  document: TeamMdDocument;
  groupMemberIds: string[];
  allKnownBots: Array<{ id: string; name: string; role: string }>;
}): DynamicBotProposal[] {
  const groupSet = new Set(input.groupMemberIds);
  const proposals: DynamicBotProposal[] = [];
  const allParticipants = [input.document.orchestrator, ...input.document.members];

  for (const p of allParticipants) {
    if (!p.actorId || groupSet.has(p.actorId)) continue;
    const existing = input.allKnownBots.find(
      (b) => b.id === p.actorId || b.name.toLowerCase() === p.name.toLowerCase(),
    );
    proposals.push({
      id: `dbp_${Date.now().toString(36)}_${randomUUID().slice(0, 6)}`,
      groupId: input.groupId,
      action: existing ? 'invite_existing' : 'create_and_invite',
      status: 'pending',
      requestedActorId: p.actorId,
      existingBotId: existing?.id,
      proposedName: existing?.name ?? p.name,
      proposedRole: p.role || existing?.role || 'Specialist Collaborator',
      proposedSystemPrompt: `You are ${p.name}, specialized in ${p.role || 'collaborative problem solving'}. Collaborate cleanly according to team.md.`,
      rationale: existing
        ? `team.md assigns "${p.role || p.name}" to existing Bot "${existing.name}", which is not yet in this group.`
        : `team.md requires role "${p.role || p.name}" (${p.actorId}), which does not exist yet. Approve to create and invite this Bot.`,
      createdAt: new Date().toISOString(),
    });
  }

  return proposals;
}

// ---------------------------------------------------------------------------
// 4. All 5 Collaboration Pattern Executor
// ---------------------------------------------------------------------------

export async function executeTeamProtocol(
  doc: TeamMdDocument,
  userPrompt: string,
  executor: TeamBotExecutor,
): Promise<TeamExecutionResult> {
  const trace: TeamExecutionTraceEntry[] = [];
  const validation = parseAndValidateTeamMd(
    renderTeamMdTemplate({
      pattern: doc.pattern,
      taskGoal: doc.taskGoal,
      orchestrator: doc.orchestrator,
      members: doc.members,
      maxRounds: doc.maxRounds,
    }),
  );

  const memberById = new Map<string, TeamParticipant>(doc.members.map((m) => [m.actorId, m]));

  switch (doc.pattern) {
    case 'classify-and-act': {
      const classifyResp = await executor({
        actorId: doc.orchestrator.actorId,
        memberName: doc.orchestrator.name,
        role: doc.orchestrator.role,
        pattern: doc.pattern,
        phase: 'classify',
        round: 1,
        prompt: `Goal: ${doc.taskGoal}\nRequest: ${userPrompt}\nSelect best specialist from: ${doc.members.map((m) => `${m.actorId}(${m.role})`).join(', ')}`,
        upstreamOutputs: [],
      });
      trace.push({
        phase: 'classify',
        round: 1,
        actorId: doc.orchestrator.actorId,
        memberName: doc.orchestrator.name,
        output: classifyResp.output,
      });

      const chosen =
        (classifyResp.selectedActorId && memberById.get(classifyResp.selectedActorId)) || doc.members[0]!;
      const actResp = await executor({
        actorId: chosen.actorId,
        memberName: chosen.name,
        role: chosen.role,
        pattern: doc.pattern,
        phase: 'execute',
        round: 1,
        prompt: userPrompt,
        upstreamOutputs: [{ actorId: doc.orchestrator.actorId, memberName: doc.orchestrator.name, output: classifyResp.output }],
      });
      trace.push({
        phase: 'execute',
        round: 1,
        actorId: chosen.actorId,
        memberName: chosen.name,
        output: actResp.output,
      });
      return {
        pattern: doc.pattern,
        roundsExecuted: 1,
        winnerActorId: chosen.actorId,
        completed: true,
        finalOutput: actResp.output,
        trace,
      };
    }

    case 'fan-out-and-synthesize': {
      const outputsByActor = new Map<string, { actorId: string; memberName: string; output: string }>();
      const waves = validation.executionWaves.length > 0 ? validation.executionWaves : [doc.members.map((m) => m.actorId)];

      for (let wIdx = 0; wIdx < waves.length; wIdx += 1) {
        const wave = waves[wIdx] ?? [];
        const waveResults = await Promise.all(
          wave.map(async (actorId) => {
            const member = memberById.get(actorId);
            if (!member) return null;
            const upstream = Array.from(outputsByActor.values());
            const resp = await executor({
              actorId: member.actorId,
              memberName: member.name,
              role: member.role,
              pattern: doc.pattern,
              phase: 'execute',
              round: wIdx + 1,
              prompt: userPrompt,
              upstreamOutputs: upstream,
            });
            return { member, output: resp.output };
          }),
        );
        for (const item of waveResults) {
          if (!item) continue;
          outputsByActor.set(item.member.actorId, {
            actorId: item.member.actorId,
            memberName: item.member.name,
            output: item.output,
          });
          trace.push({
            phase: 'execute',
            round: wIdx + 1,
            actorId: item.member.actorId,
            memberName: item.member.name,
            output: item.output,
          });
        }
      }

      const synthResp = await executor({
        actorId: doc.orchestrator.actorId,
        memberName: doc.orchestrator.name,
        role: doc.orchestrator.role,
        pattern: doc.pattern,
        phase: 'synthesize',
        round: waves.length + 1,
        prompt: `Synthesize all member outputs for: ${userPrompt}`,
        upstreamOutputs: Array.from(outputsByActor.values()),
      });
      trace.push({
        phase: 'synthesize',
        round: waves.length + 1,
        actorId: doc.orchestrator.actorId,
        memberName: doc.orchestrator.name,
        output: synthResp.output,
      });

      return {
        pattern: doc.pattern,
        roundsExecuted: waves.length,
        completed: true,
        finalOutput: synthResp.output,
        trace,
      };
    }

    case 'adversarial-verification': {
      const producer = doc.members[0]!;
      const verifier = doc.members[1] ?? doc.orchestrator;
      const maxRounds = Math.min(MAX_ALLOWED_LOOP_ROUNDS, Math.max(1, doc.maxRounds));
      let latestDraft = '';
      let latestCritique = '';
      let approved = false;
      let rounds = 0;

      for (let r = 1; r <= maxRounds; r += 1) {
        rounds = r;
        const prodResp = await executor({
          actorId: producer.actorId,
          memberName: producer.name,
          role: producer.role,
          pattern: doc.pattern,
          phase: 'execute',
          round: r,
          prompt: r === 1 ? userPrompt : `Revise draft addressing verifier feedback:\n${latestCritique}`,
          upstreamOutputs: latestCritique
            ? [{ actorId: verifier.actorId, memberName: verifier.name, output: latestCritique }]
            : [],
        });
        latestDraft = prodResp.output;
        trace.push({ phase: 'execute', round: r, actorId: producer.actorId, memberName: producer.name, output: latestDraft });

        const verResp = await executor({
          actorId: verifier.actorId,
          memberName: verifier.name,
          role: verifier.role,
          pattern: doc.pattern,
          phase: 'verify',
          round: r,
          prompt: `Adversarially verify draft against goal (${doc.taskGoal}):\n${latestDraft}`,
          upstreamOutputs: [{ actorId: producer.actorId, memberName: producer.name, output: latestDraft }],
        });
        latestCritique = verResp.output;
        trace.push({ phase: 'verify', round: r, actorId: verifier.actorId, memberName: verifier.name, output: latestCritique });

        if (verResp.approved === true) {
          approved = true;
          break;
        }
      }

      return {
        pattern: doc.pattern,
        roundsExecuted: rounds,
        verifiedApproved: approved,
        completed: approved,
        finalOutput: latestDraft,
        trace,
      };
    }

    case 'tournament': {
      const submissions = await Promise.all(
        doc.members.map(async (member) => {
          const resp = await executor({
            actorId: member.actorId,
            memberName: member.name,
            role: member.role,
            pattern: doc.pattern,
            phase: 'execute',
            round: 1,
            prompt: userPrompt,
            upstreamOutputs: [],
          });
          return { actorId: member.actorId, memberName: member.name, output: resp.output };
        }),
      );
      for (const sub of submissions) {
        trace.push({ phase: 'execute', round: 1, actorId: sub.actorId, memberName: sub.memberName, output: sub.output });
      }

      const judgeResp = await executor({
        actorId: doc.orchestrator.actorId,
        memberName: doc.orchestrator.name,
        role: doc.orchestrator.role,
        pattern: doc.pattern,
        phase: 'judge',
        round: 2,
        prompt: `Judge competing submissions for: ${userPrompt}`,
        upstreamOutputs: submissions,
      });
      trace.push({
        phase: 'judge',
        round: 2,
        actorId: doc.orchestrator.actorId,
        memberName: doc.orchestrator.name,
        output: judgeResp.output,
      });

      const winnerId =
        judgeResp.selectedActorId && submissions.some((s) => s.actorId === judgeResp.selectedActorId)
          ? judgeResp.selectedActorId
          : submissions[0]?.actorId;

      return {
        pattern: doc.pattern,
        roundsExecuted: 1,
        winnerActorId: winnerId,
        completed: true,
        finalOutput: judgeResp.output,
        trace,
      };
    }

    case 'loop-until-done': {
      const worker = doc.members[0]!;
      const maxRounds = Math.min(MAX_ALLOWED_LOOP_ROUNDS, Math.max(1, doc.maxRounds));
      let lastOutput = '';
      let done = false;
      let rounds = 0;

      for (let r = 1; r <= maxRounds; r += 1) {
        rounds = r;
        const stepResp = await executor({
          actorId: worker.actorId,
          memberName: worker.name,
          role: worker.role,
          pattern: doc.pattern,
          phase: 'loop_step',
          round: r,
          prompt: r === 1 ? userPrompt : `Continue toward completion (${doc.taskGoal}). Previous output:\n${lastOutput}`,
          upstreamOutputs: lastOutput ? [{ actorId: worker.actorId, memberName: worker.name, output: lastOutput }] : [],
        });
        lastOutput = stepResp.output;
        trace.push({ phase: 'loop_step', round: r, actorId: worker.actorId, memberName: worker.name, output: lastOutput });
        if (stepResp.done === true) {
          done = true;
          break;
        }
      }

      return {
        pattern: doc.pattern,
        roundsExecuted: rounds,
        completed: done,
        finalOutput: lastOutput,
        trace,
      };
    }
  }
}
