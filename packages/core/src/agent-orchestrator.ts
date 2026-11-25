/**
 * @pipibot/core - agent-orchestrator.ts
 *
 * PiPiBot — Clean-room MIT implementation.
 * Multi-Agent DAG Orchestrator V2 (T3 Code + OMP `task` Subagents + Claude Agent Teams parity).
 *
 * Capabilities:
 * - Structured DAG task graph with Kahn topological wave scheduling & cycle detection.
 * - Cross-provider / cross-harness delegation with automatic fallback chain (e.g. Claude -> Codex -> Pi).
 * - Automatic Git Worktree isolation tagging when >= 2 writable workers share a parallel wave.
 * - Selective Shared Blackboard context bus (downstream tasks only receive declared `dependsOn` outputs).
 * - Built-in OMP-style subagent role presets (`scout`, `coder`, `reviewer`, `researcher`, `architect`, `verifier`).
 * - Per-node bounded retry + optional adversarial verifier gate + Supervisor final synthesis.
 * - Real structured verdict extraction (`APPROVE`/`REVISE`, `DONE`/`CONTINUE`, `SELECT: <actor>`).
 *
 * Runtime dependencies: strictly Node built-ins (`node:*`) only.
 */

import { randomUUID } from 'node:crypto';

export type SubagentRolePreset =
  | 'scout'
  | 'coder'
  | 'reviewer'
  | 'researcher'
  | 'architect'
  | 'verifier'
  | 'general';

export type OrchestrationNodeStatus =
  | 'queued'
  | 'blocked'
  | 'running'
  | 'reviewing'
  | 'retrying'
  | 'done'
  | 'failed'
  | 'skipped';

export interface OrchestrationTaskNode {
  id: string;
  title: string;
  prompt: string;
  rolePreset: SubagentRolePreset;
  actorId?: string;
  harness?: string;
  modelId?: string;
  dependsOn: string[];
  isolateWorktree?: boolean;
  readOnly?: boolean;
  maxRetries?: number;
  fallbackHarnesses?: string[];
  verifyWithActorId?: string;
}

export interface OrchestrationPlan {
  planId: string;
  goal: string;
  supervisorId: string;
  nodes: OrchestrationTaskNode[];
  synthesizeFinal: boolean;
  maxConcurrency: number;
  autoWorktreeOnParallelWrite: boolean;
}

export interface OrchestrationValidationIssue {
  path: string;
  code: string;
  message: string;
}

export interface OrchestrationValidationResult {
  valid: boolean;
  issues: OrchestrationValidationIssue[];
  waves: string[][];
  autoIsolatedNodeIds: string[];
}

export interface BlackboardArtifact {
  id: string;
  fromNodeId: string;
  actorId: string;
  kind: 'summary' | 'diff' | 'diagram' | 'finding' | 'verdict';
  title: string;
  content: string;
  worktreeBranch?: string;
  createdAt: string;
}

export interface OrchestrationNodeRequest {
  planId: string;
  node: OrchestrationTaskNode;
  waveIndex: number;
  attempt: number;
  effectiveHarness?: string;
  effectiveWorktreeIsolation: boolean;
  upstreamContext: BlackboardArtifact[];
  revisionFeedback?: string;
}

export interface OrchestrationNodeResponse {
  output: string;
  succeeded: boolean;
  harnessUsed?: string;
  worktreeBranch?: string;
  diffSummary?: string;
  artifacts?: Array<{ kind: BlackboardArtifact['kind']; title: string; content: string }>;
  errorMessage?: string;
}

export interface OrchestrationSynthesisRequest {
  planId: string;
  goal: string;
  supervisorId: string;
  nodeResults: OrchestrationNodeOutcome[];
  blackboard: BlackboardArtifact[];
}

export interface OrchestrationNodeOutcome {
  nodeId: string;
  title: string;
  actorId: string;
  rolePreset: SubagentRolePreset;
  waveIndex: number;
  status: OrchestrationNodeStatus;
  attempts: number;
  harnessUsed?: string;
  worktreeIsolated: boolean;
  worktreeBranch?: string;
  diffSummary?: string;
  output: string;
  verifiedApproved?: boolean;
  durationMs: number;
}

export interface OrchestrationEvent {
  type:
    | 'plan_validated'
    | 'wave_started'
    | 'node_started'
    | 'node_retrying'
    | 'node_reviewing'
    | 'node_completed'
    | 'node_failed'
    | 'synthesis_started'
    | 'completed';
  planId: string;
  waveIndex?: number;
  nodeId?: string;
  actorId?: string;
  detail?: string;
  timestamp: string;
}

export interface OrchestrationExecutionResult {
  planId: string;
  goal: string;
  completed: boolean;
  wavesExecuted: number;
  nodeOutcomes: OrchestrationNodeOutcome[];
  blackboard: BlackboardArtifact[];
  finalOutput: string;
  durationMs: number;
}

export interface OrchestrationExecutor {
  runNode: (req: OrchestrationNodeRequest) => Promise<OrchestrationNodeResponse>;
  runSynthesis?: (req: OrchestrationSynthesisRequest) => Promise<string>;
  onEvent?: (event: OrchestrationEvent) => void;
}

export interface StructuredTurnVerdict {
  approved?: boolean;
  done?: boolean;
  selectedActorId?: string;
  reason?: string;
}

export const SUBAGENT_ROLE_PRESETS: Record<
  SubagentRolePreset,
  { readOnlyDefault: boolean; systemGuidance: string }
> = {
  scout: {
    readOnlyDefault: true,
    systemGuidance:
      'You are a fast read-only Scout subagent. Inspect files, symbols, and call graphs concisely; return exact file paths, line numbers, and key invariants without editing files.',
  },
  researcher: {
    readOnlyDefault: true,
    systemGuidance:
      'You are a Research subagent. Gather authoritative evidence, compare trade-offs in structured tables, and cite concrete sources.',
  },
  architect: {
    readOnlyDefault: true,
    systemGuidance:
      'You are an Architect subagent. Produce concrete interfaces, invariants, and clear inline SVG/Mermaid diagrams illustrating dataflow and module boundaries.',
  },
  coder: {
    readOnlyDefault: false,
    systemGuidance:
      'You are a Coder subagent working in a scoped workspace (or isolated Git worktree). Implement clean, tested changes and verify with build/tests before reporting.',
  },
  reviewer: {
    readOnlyDefault: true,
    systemGuidance:
      'You are an Adversarial Code Reviewer subagent. Audit diffs for regressions, edge cases, contract drift, and missing tests. End with VERDICT: APPROVE or VERDICT: REVISE.',
  },
  verifier: {
    readOnlyDefault: true,
    systemGuidance:
      'You are a Verification Gate subagent. Validate outputs against the task goal and concrete acceptance checks. End with VERDICT: APPROVE or VERDICT: REVISE.',
  },
  general: {
    readOnlyDefault: false,
    systemGuidance:
      'You are a focused Specialist subagent. Complete your assigned subtask end-to-end and return a crisp structured summary.',
  },
};

// ---------------------------------------------------------------------------
// 1. Plan Validation, Kahn DAG Wave Scheduling & Auto Worktree Isolation
// ---------------------------------------------------------------------------

export function validateOrchestrationPlan(plan: OrchestrationPlan): OrchestrationValidationResult {
  const issues: OrchestrationValidationIssue[] = [];
  if (!plan.goal.trim()) {
    issues.push({ path: 'goal', code: 'orch_goal_empty', message: 'Orchestration goal must not be empty.' });
  }
  if (plan.nodes.length === 0) {
    issues.push({ path: 'nodes', code: 'orch_nodes_empty', message: 'At least one task node is required.' });
    return { valid: false, issues, waves: [], autoIsolatedNodeIds: [] };
  }

  const nodeById = new Map<string, OrchestrationTaskNode>();
  for (const [idx, node] of plan.nodes.entries()) {
    if (!node.id.trim()) {
      issues.push({ path: `nodes[${idx}].id`, code: 'orch_node_id_missing', message: 'Task node ID is required.' });
      continue;
    }
    if (nodeById.has(node.id)) {
      issues.push({
        path: `nodes[${idx}].id`,
        code: 'orch_node_id_duplicated',
        message: `Duplicate task node ID "${node.id}".`,
      });
      continue;
    }
    nodeById.set(node.id, node);
  }

  const deps = new Map<string, Set<string>>();
  for (const node of plan.nodes) {
    if (!node.id) continue;
    const set = new Set<string>();
    for (const depId of node.dependsOn) {
      if (depId === node.id) {
        issues.push({
          path: `nodes.${node.id}.dependsOn`,
          code: 'orch_self_dependency',
          message: `Node "${node.id}" cannot depend on itself.`,
        });
      } else if (!nodeById.has(depId)) {
        issues.push({
          path: `nodes.${node.id}.dependsOn`,
          code: 'orch_unknown_dependency',
          message: `Node "${node.id}" references unknown dependency "${depId}".`,
        });
      } else {
        set.add(depId);
      }
    }
    deps.set(node.id, set);
  }

  // Kahn's topological layering
  const waves: string[][] = [];
  const remaining = new Map<string, Set<string>>();
  for (const [id, set] of deps.entries()) {
    remaining.set(id, new Set(set));
  }
  const orderedIds = plan.nodes.map((n) => n.id).filter(Boolean);

  while (remaining.size > 0) {
    const ready = orderedIds.filter((id) => remaining.has(id) && (remaining.get(id)?.size ?? 0) === 0);
    if (ready.length === 0) {
      issues.push({
        path: 'dag',
        code: 'orch_cycle_detected',
        message: `Circular dependency detected among nodes: ${Array.from(remaining.keys()).join(', ')}.`,
      });
      break;
    }
    waves.push(ready);
    for (const id of ready) remaining.delete(id);
    for (const set of remaining.values()) {
      for (const id of ready) set.delete(id);
    }
  }

  // Auto-isolation policy (T3 Code / OMP parity): if >= 2 writable nodes run in the same wave,
  // automatically mark them for isolated Git Worktrees so they never clobber each other.
  const autoIsolatedNodeIds: string[] = [];
  for (const wave of waves) {
    const writableInWave = wave.filter((id) => {
      const node = nodeById.get(id);
      if (!node) return false;
      const isReadOnly = node.readOnly ?? SUBAGENT_ROLE_PRESETS[node.rolePreset].readOnlyDefault;
      return !isReadOnly;
    });
    for (const id of wave) {
      const node = nodeById.get(id);
      if (!node) continue;
      const explicitlyRequested = node.isolateWorktree === true;
      const autoParallelWrite = plan.autoWorktreeOnParallelWrite && writableInWave.length >= 2 && writableInWave.includes(id);
      if (explicitlyRequested || autoParallelWrite) {
        autoIsolatedNodeIds.push(id);
      }
    }
  }

  return {
    valid: issues.length === 0,
    issues,
    waves,
    autoIsolatedNodeIds,
  };
}

// ---------------------------------------------------------------------------
// 2. Structured Plan & Verdict Parsers (Zero Hardcoded Stubs)
// ---------------------------------------------------------------------------

export function parseStructuredTurnVerdict(
  text: string,
  candidateActorIds: readonly string[] = [],
): StructuredTurnVerdict {
  const verdict: StructuredTurnVerdict = {};
  const trimmed = text.trim();

  // Check JSON directive block first if present
  const jsonMatch = trimmed.match(/\{[\s\S]*?"(?:approved|done|selectedActorId|verdict)"[\s\S]*?\}/i);
  if (jsonMatch?.[0]) {
    try {
      const parsed = JSON.parse(jsonMatch[0]) as Record<string, unknown>;
      if (typeof parsed.approved === 'boolean') verdict.approved = parsed.approved;
      if (typeof parsed.done === 'boolean') verdict.done = parsed.done;
      if (typeof parsed.selectedActorId === 'string') verdict.selectedActorId = parsed.selectedActorId;
      if (typeof parsed.reason === 'string') verdict.reason = parsed.reason;
    } catch {
      // Fall through to text markers
    }
  }

  // VERDICT: APPROVE | REVISE / REJECT
  if (verdict.approved === undefined) {
    if (/\b(?:VERDICT|REVIEW)\s*[:：]\s*(?:APPROVE|APPROVED|PASS|LGTM)\b/i.test(trimmed)) {
      verdict.approved = true;
    } else if (/\b(?:VERDICT|REVIEW)\s*[:：]\s*(?:REVISE|REJECT|CHANGES_REQUESTED|FAIL)\b/i.test(trimmed)) {
      verdict.approved = false;
    } else if (/【(?:通过|批准)】/.test(trimmed)) {
      verdict.approved = true;
    } else if (/【(?:打回|需修改|拒绝)】/.test(trimmed)) {
      verdict.approved = false;
    }
  }

  // STATUS: DONE | CONTINUE
  if (verdict.done === undefined) {
    if (/\b(?:STATUS|LOOP)\s*[:：]\s*(?:DONE|COMPLETE|COMPLETED|FINISHED)\b/i.test(trimmed)) {
      verdict.done = true;
    } else if (/\b(?:STATUS|LOOP)\s*[:：]\s*(?:CONTINUE|RETRY|IN_PROGRESS|MORE)\b/i.test(trimmed)) {
      verdict.done = false;
    }
  }

  // SELECT: actor_id or WINNER: actor_id
  if (!verdict.selectedActorId && candidateActorIds.length > 0) {
    const selMatch = trimmed.match(/\b(?:SELECT|WINNER|ASSIGN)\s*[:：]\s*([A-Za-z0-9_.:-]+)/i);
    if (selMatch?.[1]) {
      const rawPick = selMatch[1].trim().toLowerCase();
      const hit = candidateActorIds.find((id) => id.toLowerCase() === rawPick);
      if (hit) verdict.selectedActorId = hit;
    }
    if (!verdict.selectedActorId) {
      const lower = trimmed.toLowerCase();
      const firstMentioned = candidateActorIds.find((id) => lower.includes(id.toLowerCase()));
      if (firstMentioned) verdict.selectedActorId = firstMentioned;
    }
  }

  return verdict;
}

export function parseOrchestrationPlanFromText(input: {
  text: string;
  goal: string;
  supervisorId: string;
  candidates: Array<{ id: string; name: string; aliases?: string[] }>;
}): OrchestrationPlan | null {
  const { text, goal, supervisorId, candidates } = input;

  // Format 1: Structured `<pipibot_plan>{...}</pipibot_plan>` JSON block
  const tagMatch = text.match(/<pipibot_plan>([\s\S]*?)<\/pipibot_plan>/i);
  if (tagMatch?.[1]) {
    try {
      const raw = JSON.parse(tagMatch[1].trim()) as {
        nodes?: Array<{
          id?: string;
          title?: string;
          prompt?: string;
          rolePreset?: SubagentRolePreset;
          actorId?: string;
          harness?: string;
          modelId?: string;
          dependsOn?: string[];
          isolateWorktree?: boolean;
          readOnly?: boolean;
          maxRetries?: number;
        }>;
        synthesizeFinal?: boolean;
        maxConcurrency?: number;
      };
      if (Array.isArray(raw.nodes) && raw.nodes.length > 0) {
        const nodes: OrchestrationTaskNode[] = raw.nodes.map((n, idx) => ({
          id: (n.id ?? `task_${idx + 1}`).trim(),
          title: (n.title ?? n.prompt ?? `Subtask ${idx + 1}`).slice(0, 80),
          prompt: (n.prompt ?? n.title ?? goal).trim(),
          rolePreset: n.rolePreset && n.rolePreset in SUBAGENT_ROLE_PRESETS ? n.rolePreset : 'general',
          actorId: n.actorId,
          harness: n.harness,
          modelId: n.modelId,
          dependsOn: Array.isArray(n.dependsOn) ? n.dependsOn.filter(Boolean) : [],
          isolateWorktree: n.isolateWorktree,
          readOnly: n.readOnly,
          maxRetries: n.maxRetries,
        }));
        return {
          planId: `plan_${randomUUID().slice(0, 8)}`,
          goal,
          supervisorId,
          nodes,
          synthesizeFinal: raw.synthesizeFinal ?? true,
          maxConcurrency: Math.max(1, Math.min(6, raw.maxConcurrency ?? 3)),
          autoWorktreeOnParallelWrite: true,
        };
      }
    } catch {
      // Fall through to @Member line parser
    }
  }

  // Format 2: Enhanced `@MemberName: subtask [id: t1] [depends: t0] [worktree] [harness: codex] [role: coder]`
  const nodes: OrchestrationTaskNode[] = [];
  const lines = text.split(/\r?\n/);
  for (const rawLine of lines) {
    const line = rawLine.trim().replace(/^[-*•]\s*/, '');
    const m = line.match(/^@([^\s:：]+)\s*[:：]\s*(.+)$/);
    if (!m?.[1] || !m[2]) continue;
    const mentionName = m[1].trim().toLowerCase();
    const matchedCand = candidates.find(
      (c) =>
        c.id.toLowerCase() === mentionName ||
        c.name.toLowerCase() === mentionName ||
        (c.aliases ?? []).some((a) => a.toLowerCase() === mentionName),
    );
    if (!matchedCand) continue;

    let body = m[2].trim();
    const idTag = body.match(/\[id\s*:\s*([A-Za-z0-9_-]+)\]/i);
    const depsTag = body.match(/\[depends\s*:\s*([^\]]+)\]/i);
    const harnessTag = body.match(/\[harness\s*:\s*([A-Za-z0-9_-]+)\]/i);
    const roleTag = body.match(/\[role\s*:\s*([A-Za-z0-9_-]+)\]/i);
    const hasWorktree = /\[worktree\]/i.test(body);

    body = body
      .replace(/\[(?:id|depends|harness|role)\s*:[^\]]+\]/gi, '')
      .replace(/\[worktree\]/gi, '')
      .trim();
    if (!body) continue;

    const rawRole = (roleTag?.[1]?.toLowerCase() ?? 'general') as SubagentRolePreset;
    const rolePreset: SubagentRolePreset = rawRole in SUBAGENT_ROLE_PRESETS ? rawRole : 'general';
    const dependsOn = depsTag?.[1]
      ? depsTag[1]
          .split(/[,，]/)
          .map((s) => s.trim())
          .filter(Boolean)
      : [];

    nodes.push({
      id: idTag?.[1]?.trim() || `t${nodes.length + 1}`,
      title: body.slice(0, 72),
      prompt: body,
      rolePreset,
      actorId: matchedCand.id,
      harness: harnessTag?.[1]?.trim(),
      dependsOn,
      isolateWorktree: hasWorktree ? true : undefined,
    });
  }

  if (nodes.length === 0) return null;
  return {
    planId: `plan_${randomUUID().slice(0, 8)}`,
    goal,
    supervisorId,
    nodes,
    synthesizeFinal: true,
    maxConcurrency: 3,
    autoWorktreeOnParallelWrite: true,
  };
}

// ---------------------------------------------------------------------------
// 3. Wave-Based DAG Execution Engine with Blackboard, Retries & Synthesis
// ---------------------------------------------------------------------------

async function runWithConcurrency<T, R>(
  items: readonly T[],
  limit: number,
  worker: (item: T) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(items.length);
  let cursor = 0;
  const laneCount = Math.min(Math.max(1, limit), items.length);

  await Promise.all(
    Array.from({ length: laneCount }, async () => {
      while (true) {
        const idx = cursor;
        cursor += 1;
        if (idx >= items.length) break;
        results[idx] = await worker(items[idx]!);
      }
    }),
  );

  return results;
}

export async function executeOrchestrationPlan(
  plan: OrchestrationPlan,
  executor: OrchestrationExecutor,
): Promise<OrchestrationExecutionResult> {
  const startedAt = Date.now();
  const validation = validateOrchestrationPlan(plan);
  const emit = (ev: Omit<OrchestrationEvent, 'planId' | 'timestamp'>) => {
    executor.onEvent?.({
      ...ev,
      planId: plan.planId,
      timestamp: new Date().toISOString(),
    });
  };

  if (!validation.valid) {
    const summary = validation.issues.map((i) => `${i.code}: ${i.message}`).join('; ');
    return {
      planId: plan.planId,
      goal: plan.goal,
      completed: false,
      wavesExecuted: 0,
      nodeOutcomes: [],
      blackboard: [],
      finalOutput: `Invalid orchestration plan: ${summary}`,
      durationMs: Date.now() - startedAt,
    };
  }

  emit({
    type: 'plan_validated',
    detail: `${plan.nodes.length} nodes across ${validation.waves.length} waves`,
  });

  const nodeById = new Map(plan.nodes.map((n) => [n.id, n]));
  const isolatedSet = new Set(validation.autoIsolatedNodeIds);
  const blackboard: BlackboardArtifact[] = [];
  const artifactsByNode = new Map<string, BlackboardArtifact[]>();
  const outcomesById = new Map<string, OrchestrationNodeOutcome>();

  for (let waveIndex = 0; waveIndex < validation.waves.length; waveIndex += 1) {
    const waveIds = validation.waves[waveIndex] ?? [];
    emit({ type: 'wave_started', waveIndex, detail: waveIds.join(', ') });

    await runWithConcurrency(waveIds, plan.maxConcurrency, async (nodeId) => {
      const node = nodeById.get(nodeId)!;
      const actorId = node.actorId ?? `${node.rolePreset}:${node.id}`;
      const nodeStarted = Date.now();

      // Check if any required upstream dependency failed
      const failedDep = node.dependsOn.find((dep) => outcomesById.get(dep)?.status === 'failed');
      if (failedDep) {
        const skippedOutcome: OrchestrationNodeOutcome = {
          nodeId: node.id,
          title: node.title,
          actorId,
          rolePreset: node.rolePreset,
          waveIndex,
          status: 'skipped',
          attempts: 0,
          worktreeIsolated: isolatedSet.has(node.id),
          output: `Skipped because upstream dependency "${failedDep}" failed.`,
          durationMs: 0,
        };
        outcomesById.set(node.id, skippedOutcome);
        return;
      }

      // Selective Blackboard injection: ONLY pass outputs from declared `dependsOn` ancestors
      const upstreamContext: BlackboardArtifact[] = [];
      for (const depId of node.dependsOn) {
        upstreamContext.push(...(artifactsByNode.get(depId) ?? []));
      }

      const harnessChain: Array<string | undefined> = [
        node.harness,
        ...(node.fallbackHarnesses ?? []),
      ];
      const maxAttempts = Math.max(1, (node.maxRetries ?? 1) + 1);
      let attempt = 0;
      let revisionFeedback: string | undefined;
      let finalResp: OrchestrationNodeResponse | null = null;
      let verifiedApproved: boolean | undefined;

      while (attempt < maxAttempts) {
        attempt += 1;
        const effectiveHarness = harnessChain[Math.min(attempt - 1, harnessChain.length - 1)];
        emit({
          type: attempt === 1 ? 'node_started' : 'node_retrying',
          waveIndex,
          nodeId: node.id,
          actorId,
          detail: effectiveHarness ? `attempt ${attempt} (${effectiveHarness})` : `attempt ${attempt}`,
        });

        try {
          const resp = await executor.runNode({
            planId: plan.planId,
            node,
            waveIndex,
            attempt,
            effectiveHarness,
            effectiveWorktreeIsolation: isolatedSet.has(node.id),
            upstreamContext,
            revisionFeedback,
          });
          finalResp = resp;

          if (!resp.succeeded) {
            revisionFeedback = resp.errorMessage || 'Previous attempt failed; try fallback approach.';
            continue;
          }

          // Optional adversarial verification gate
          if (node.verifyWithActorId) {
            emit({
              type: 'node_reviewing',
              waveIndex,
              nodeId: node.id,
              actorId: node.verifyWithActorId,
              detail: `Verifying ${node.id}`,
            });
            const verifyNode: OrchestrationTaskNode = {
              id: `${node.id}_verify_${attempt}`,
              title: `Verify ${node.title}`,
              prompt: `Review the output for "${node.title}" against goal "${plan.goal}".\n\nOutput:\n${resp.output}\n\nRespond with VERDICT: APPROVE or VERDICT: REVISE and concise feedback.`,
              rolePreset: 'verifier',
              actorId: node.verifyWithActorId,
              dependsOn: [node.id],
              readOnly: true,
            };
            const verResp = await executor.runNode({
              planId: plan.planId,
              node: verifyNode,
              waveIndex,
              attempt: 1,
              effectiveWorktreeIsolation: false,
              upstreamContext,
            });
            const parsedVerdict = parseStructuredTurnVerdict(verResp.output);
            verifiedApproved = parsedVerdict.approved ?? verResp.succeeded;
            if (!verifiedApproved && attempt < maxAttempts) {
              revisionFeedback = verResp.output;
              continue;
            }
          }

          break;
        } catch (err) {
          finalResp = {
            output: '',
            succeeded: false,
            errorMessage: err instanceof Error ? err.message : String(err),
          };
          revisionFeedback = finalResp.errorMessage;
        }
      }

      const succeeded = Boolean(finalResp?.succeeded) && verifiedApproved !== false;
      const outcome: OrchestrationNodeOutcome = {
        nodeId: node.id,
        title: node.title,
        actorId,
        rolePreset: node.rolePreset,
        waveIndex,
        status: succeeded ? 'done' : 'failed',
        attempts: attempt,
        harnessUsed: finalResp?.harnessUsed ?? node.harness,
        worktreeIsolated: isolatedSet.has(node.id),
        worktreeBranch: finalResp?.worktreeBranch,
        diffSummary: finalResp?.diffSummary,
        output: finalResp?.output || finalResp?.errorMessage || '',
        verifiedApproved,
        durationMs: Date.now() - nodeStarted,
      };
      outcomesById.set(node.id, outcome);

      if (succeeded) {
        const created: BlackboardArtifact[] = [
          {
            id: `bb_${node.id}_main`,
            fromNodeId: node.id,
            actorId,
            kind: finalResp?.diffSummary ? 'diff' : 'summary',
            title: node.title,
            content: outcome.output,
            worktreeBranch: outcome.worktreeBranch,
            createdAt: new Date().toISOString(),
          },
          ...(finalResp?.artifacts ?? []).map((a, idx) => ({
            id: `bb_${node.id}_${idx + 1}`,
            fromNodeId: node.id,
            actorId,
            kind: a.kind,
            title: a.title,
            content: a.content,
            worktreeBranch: outcome.worktreeBranch,
            createdAt: new Date().toISOString(),
          })),
        ];
        blackboard.push(...created);
        artifactsByNode.set(node.id, created);
        emit({ type: 'node_completed', waveIndex, nodeId: node.id, actorId });
      } else {
        emit({
          type: 'node_failed',
          waveIndex,
          nodeId: node.id,
          actorId,
          detail: finalResp?.errorMessage,
        });
      }
    });
  }

  const orderedOutcomes = plan.nodes
    .map((n) => outcomesById.get(n.id))
    .filter((o): o is OrchestrationNodeOutcome => Boolean(o));
  const allSucceeded = orderedOutcomes.length > 0 && orderedOutcomes.every((o) => o.status === 'done');

  let finalOutput: string;
  if (plan.synthesizeFinal && executor.runSynthesis) {
    emit({ type: 'synthesis_started', actorId: plan.supervisorId });
    finalOutput = await executor.runSynthesis({
      planId: plan.planId,
      goal: plan.goal,
      supervisorId: plan.supervisorId,
      nodeResults: orderedOutcomes,
      blackboard,
    });
  } else {
    finalOutput = orderedOutcomes
      .map((o) => `### ${o.title} (${o.actorId} · ${o.status})\n${o.output}`)
      .join('\n\n');
  }

  emit({ type: 'completed', detail: allSucceeded ? 'all_done' : 'partial' });

  return {
    planId: plan.planId,
    goal: plan.goal,
    completed: allSucceeded,
    wavesExecuted: validation.waves.length,
    nodeOutcomes: orderedOutcomes,
    blackboard,
    finalOutput,
    durationMs: Date.now() - startedAt,
  };
}
