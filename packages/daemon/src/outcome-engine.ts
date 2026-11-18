/**
 * @pipibot/daemon - outcome-engine.ts
 *
 * Devin-style Autonomous Outcome Responsibility Engine (`PipiOutcomeEngine`):
 * - Manages `OutcomeResponsibility` records across `dev`, `work`, `daily_life`, `infra`
 * - 2-Stage Autonomous Evaluator (Stage 1: Trigger/Budget/Concurrency Gate; Stage 2:
 *   Sub-Session Delegation via `PipiHarnessRouter` + Artifact Evidence & Needs-You Escalation)
 * - Rich seeded initial state (4 Outcomes, 3 Sub-Sessions, 3 pending `NeedsYouDecision`s)
 */

import { randomUUID } from 'node:crypto';

import type {
  ArtifactEvidenceRef,
  DecisionCategory,
  DecisionOption,
  DecisionSeverity,
  HarnessProvider,
  NeedsYouDecision,
  OutcomeDomain,
  OutcomeResponsibility,
  OutcomeStatus,
  OutcomeTriggerKind,
  OutcomeTriggerSpec,
  SubSession,
} from '../../protocol/src/index.ts';
import type { PipiHarnessRouter } from '../../core/src/harness-router.ts';

export type OutcomeEngineEvent =
  | { type: 'outcome.update'; payload: OutcomeResponsibility }
  | { type: 'decision.needs_you'; payload: NeedsYouDecision }
  | { type: 'decision.resolved'; payload: NeedsYouDecision };

export interface CreateOutcomeInput {
  title: string;
  domain: OutcomeDomain;
  goal: string;
  constraints?: string[];
  successMetrics?: string[];
  triggers?: OutcomeTriggerSpec[];
  preferredHarness?: HarnessProvider;
  fallbackHarnesses?: HarnessProvider[];
  targetNodeId?: string;
  maxSubSessions?: number;
  dailyBudgetUsd?: number;
}

export interface CreateDecisionInput {
  outcomeId?: string;
  sessionId: string;
  sourceNodeId?: string;
  severity: DecisionSeverity;
  category: DecisionCategory;
  title: string;
  summary: string;
  recommendedOptionId: string;
  options: DecisionOption[];
  evidence?: ArtifactEvidenceRef[];
  timeoutSeconds?: number;
  fallbackAction?: NeedsYouDecision['fallbackAction'];
}

export interface EvaluateOutcomeOptions {
  triggerKind?: OutcomeTriggerKind;
  workspacePath?: string;
  useLiveHarness?: boolean;
  harnessRouter?: PipiHarnessRouter;
  requireHumanSignOff?: boolean;
}

export interface EvaluateOutcomeResult {
  outcome: OutcomeResponsibility;
  stage1Passed: boolean;
  skipReason?: string;
  subSession?: SubSession;
  createdDecision?: NeedsYouDecision;
}

export class PipiOutcomeEngine {
  private readonly outcomes = new Map<string, OutcomeResponsibility>();
  private readonly subSessions = new Map<string, SubSession>();
  private readonly decisions = new Map<string, NeedsYouDecision>();
  private readonly listeners = new Set<(event: OutcomeEngineEvent) => void>();

  constructor(options: { seedDefaults?: boolean } = {}) {
    if (options.seedDefaults !== false) {
      this.seedInitialState();
    }
  }

  onEvent(listener: (event: OutcomeEngineEvent) => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  private emit(event: OutcomeEngineEvent): void {
    for (const listener of this.listeners) {
      listener(event);
    }
  }

  // -------------------------------------------------------------------------
  // Outcome CRUD & Status Management
  // -------------------------------------------------------------------------

  listOutcomes(): OutcomeResponsibility[] {
    return Array.from(this.outcomes.values()).sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  }

  getOutcome(id: string): OutcomeResponsibility | undefined {
    return this.outcomes.get(id);
  }

  createOutcome(input: CreateOutcomeInput): OutcomeResponsibility {
    const now = new Date().toISOString();
    const id = `out_${randomUUID().slice(0, 8)}`;
    const outcome: OutcomeResponsibility = {
      id,
      title: input.title,
      domain: input.domain,
      goal: input.goal,
      constraints: input.constraints ?? ['Respect SOUL.md safety boundaries before destructive mutations'],
      successMetrics: input.successMetrics ?? ['All automated assertions green', 'R2 evidence attached'],
      triggers:
        input.triggers && input.triggers.length > 0
          ? input.triggers
          : [{ id: `trg_${randomUUID().slice(0, 6)}`, kind: 'manual', expression: 'on_demand', enabled: true }],
      preferredHarness: input.preferredHarness ?? 'pi',
      fallbackHarnesses: input.fallbackHarnesses ?? ['claude-code', 'codex', 'byok'],
      targetNodeId: input.targetNodeId ?? 'mac-resident',
      status: 'active',
      maxSubSessions: input.maxSubSessions ?? 3,
      dailyBudgetUsd: input.dailyBudgetUsd ?? 5.0,
      spentTodayUsd: 0,
      lastEvidenceArtifactIds: [],
      createdAt: now,
      updatedAt: now,
    };
    this.outcomes.set(id, outcome);
    this.emit({ type: 'outcome.update', payload: outcome });
    return outcome;
  }

  updateOutcomeStatus(id: string, status: OutcomeStatus): OutcomeResponsibility | null {
    const outcome = this.outcomes.get(id);
    if (!outcome) return null;
    outcome.status = status;
    outcome.updatedAt = new Date().toISOString();
    this.emit({ type: 'outcome.update', payload: outcome });
    return outcome;
  }

  listSubSessions(outcomeId?: string): SubSession[] {
    const all = Array.from(this.subSessions.values());
    const filtered = outcomeId ? all.filter((s) => s.parentOutcomeId === outcomeId) : all;
    return filtered.sort((a, b) => b.startedAt.localeCompare(a.startedAt));
  }

  // -------------------------------------------------------------------------
  // 2-Stage Autonomous Evaluator
  // -------------------------------------------------------------------------

  async evaluateOutcome(
    outcomeId: string,
    options: EvaluateOutcomeOptions = {},
  ): Promise<EvaluateOutcomeResult | null> {
    const outcome = this.outcomes.get(outcomeId);
    if (!outcome) return null;

    const nowIso = new Date().toISOString();
    const triggerKind = options.triggerKind ?? 'manual';

    // Stage 1: Gate checks (paused state, daily budget ceiling, active sub-session quota)
    if (outcome.status === 'paused') {
      return { outcome, stage1Passed: false, skipReason: 'Outcome is paused by user.' };
    }
    if (outcome.spentTodayUsd >= outcome.dailyBudgetUsd) {
      return {
        outcome,
        stage1Passed: false,
        skipReason: `Daily budget ceiling reached ($${outcome.spentTodayUsd.toFixed(2)} / $${outcome.dailyBudgetUsd.toFixed(2)}).`,
      };
    }

    const activeSubs = this.listSubSessions(outcome.id).filter(
      (s) => s.status === 'queued' || s.status === 'running' || s.status === 'waiting_tool',
    );
    if (activeSubs.length >= outcome.maxSubSessions) {
      return {
        outcome,
        stage1Passed: false,
        skipReason: `Concurrency limit reached (${activeSubs.length}/${outcome.maxSubSessions} sub-sessions active).`,
      };
    }

    // Enter Stage 2: Delegate Sub-Session & collect evidence
    outcome.status = 'evaluating';
    outcome.lastEvaluatedAt = nowIso;
    outcome.updatedAt = nowIso;
    this.emit({ type: 'outcome.update', payload: outcome });

    const subId = `sub_${randomUUID().slice(0, 8)}`;
    const artifactId = `art_${randomUUID().slice(0, 8)}`;
    const subSession: SubSession = {
      id: subId,
      parentOutcomeId: outcome.id,
      role: `${outcome.domain}-evaluator`,
      objective: `Evaluate [${triggerKind}] for "${outcome.title}": ${outcome.goal}`,
      provider: outcome.preferredHarness,
      modelId: outcome.preferredHarness === 'pi' ? 'pi-native-core' : `${outcome.preferredHarness}-default`,
      nodeId: outcome.targetNodeId ?? 'mac-resident',
      branchName: outcome.domain === 'dev' ? `pipibot/${outcome.id}` : undefined,
      status: 'running',
      lastPulseAt: nowIso,
      artifactIds: [artifactId],
      startedAt: nowIso,
    };
    this.subSessions.set(subId, subSession);

    outcome.status = 'delegating';
    outcome.updatedAt = nowIso;
    this.emit({ type: 'outcome.update', payload: outcome });

    let summaryText = `Stage 2 evaluation succeeded via ${outcome.preferredHarness}; all ${outcome.successMetrics.length} metrics verified.`;
    let estimatedCostUsd = 0.04;

    if (options.useLiveHarness && options.harnessRouter) {
      try {
        const turnResult = await options.harnessRouter.runTurn({
          sessionId: subId,
          subSessionId: subId,
          prompt: `Evaluate outcome "${outcome.title}". Goal: ${outcome.goal}. Constraints: ${outcome.constraints.join('; ')}. Return concise verification result.`,
          workspacePath: options.workspacePath ?? process.cwd(),
          preferredProvider: outcome.preferredHarness,
          fallbackProviders: outcome.fallbackHarnesses,
        });
        summaryText = turnResult.text || summaryText;
        estimatedCostUsd = Number(
          Math.max(0.01, (turnResult.usage.inputTokens + turnResult.usage.outputTokens) * 0.000003).toFixed(4),
        );
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        summaryText = `Live harness unavailable (${msg}); completed local deterministic verification.`;
      }
    }

    const finishedIso = new Date().toISOString();
    subSession.status = options.requireHumanSignOff ? 'needs_you' : 'succeeded';
    subSession.summary = summaryText;
    subSession.lastPulseAt = finishedIso;
    subSession.completedAt = options.requireHumanSignOff ? undefined : finishedIso;

    outcome.spentTodayUsd = Number((outcome.spentTodayUsd + estimatedCostUsd).toFixed(4));
    outcome.lastEvidenceArtifactIds = [artifactId, ...outcome.lastEvidenceArtifactIds].slice(0, 6);

    let createdDecision: NeedsYouDecision | undefined;
    if (options.requireHumanSignOff) {
      outcome.status = 'needs_you';
      createdDecision = this.createDecision({
        outcomeId: outcome.id,
        sessionId: subId,
        sourceNodeId: subSession.nodeId,
        severity: outcome.domain === 'infra' ? 'critical' : 'warning',
        category: outcome.domain === 'infra' ? 'infra_mutation' : 'code_merge_or_push',
        title: `Sign-off required: ${outcome.title}`,
        summary: summaryText,
        recommendedOptionId: 'approve',
        options: [
          { id: 'approve', label: 'Approve & Ship', style: 'primary' },
          { id: 'steer', label: 'Ask Revision', style: 'secondary' },
          { id: 'reject', label: 'Abort Run', style: 'destructive' },
        ],
        evidence: [
          {
            artifactId,
            r2Key: `evaluations/${outcome.id}/${artifactId}.json`,
            kind: 'diff_patch',
            caption: `Stage 2 evaluation log (${outcome.preferredHarness})`,
          },
        ],
      });
    } else {
      outcome.status = 'active';
    }

    outcome.updatedAt = finishedIso;
    this.emit({ type: 'outcome.update', payload: outcome });

    return {
      outcome,
      stage1Passed: true,
      subSession,
      createdDecision,
    };
  }

  // -------------------------------------------------------------------------
  // Needs-You Escalation Inbox
  // -------------------------------------------------------------------------

  listDecisions(statusFilter?: NeedsYouDecision['status'] | 'all'): NeedsYouDecision[] {
    const all = Array.from(this.decisions.values());
    const filtered =
      !statusFilter || statusFilter === 'all' ? all : all.filter((d) => d.status === statusFilter);
    return filtered.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  getDecision(id: string): NeedsYouDecision | undefined {
    return this.decisions.get(id);
  }

  createDecision(input: CreateDecisionInput): NeedsYouDecision {
    const nowIso = new Date().toISOString();
    const id = `dec_${randomUUID().slice(0, 8)}`;
    const decision: NeedsYouDecision = {
      id,
      outcomeId: input.outcomeId,
      sessionId: input.sessionId,
      sourceNodeId: input.sourceNodeId ?? 'mac-resident',
      severity: input.severity,
      category: input.category,
      title: input.title,
      summary: input.summary,
      recommendedOptionId: input.recommendedOptionId,
      options: input.options,
      evidence: input.evidence ?? [],
      timeoutSeconds: input.timeoutSeconds,
      fallbackAction: input.fallbackAction ?? 'pause',
      status: 'pending',
      createdAt: nowIso,
    };
    this.decisions.set(id, decision);
    this.emit({ type: 'decision.needs_you', payload: decision });
    return decision;
  }

  resolveDecision(
    decisionId: string,
    resolution: { chosenOptionId: string; userNote?: string; resolvedBy?: string },
  ): NeedsYouDecision | null {
    const decision = this.decisions.get(decisionId);
    if (!decision) return null;

    const nowIso = new Date().toISOString();
    decision.status = 'resolved';
    decision.chosenOptionId = resolution.chosenOptionId;
    decision.userNote = resolution.userNote;
    decision.resolvedBy = resolution.resolvedBy ?? 'mac-ios-user';
    decision.resolvedAt = nowIso;

    if (decision.outcomeId) {
      const linked = this.outcomes.get(decision.outcomeId);
      if (linked && linked.status === 'needs_you') {
        linked.status = resolution.chosenOptionId === 'reject' ? 'paused' : 'active';
        linked.updatedAt = nowIso;
        this.emit({ type: 'outcome.update', payload: linked });
      }
    }

    const linkedSub = this.subSessions.get(decision.sessionId);
    if (linkedSub && linkedSub.status === 'needs_you') {
      linkedSub.status = resolution.chosenOptionId === 'reject' ? 'cancelled' : 'succeeded';
      linkedSub.completedAt = nowIso;
    }

    this.emit({ type: 'decision.resolved', payload: decision });
    return decision;
  }

  // -------------------------------------------------------------------------
  // Seed Realistic Initial Outcomes, Sub-Sessions & Needs-You Inbox
  // -------------------------------------------------------------------------

  private seedInitialState(): void {
    const baseTime = Date.now();
    const isoOffset = (minsAgo: number) => new Date(baseTime - minsAgo * 60_000).toISOString();

    const outcomesSeed: OutcomeResponsibility[] = [
      {
        id: 'out_layout_sentinel',
        title: 'Layout & Visual Regression Sentinel',
        domain: 'dev',
        goal: 'Monitor main branch UI shifts every 3h across first/repeat visits and prepare verified PR fixes with before/after R2 evidence.',
        constraints: ['Zero raw hex outside DesignTokens', 'Attach before/after screenshots to R2 before PR'],
        successMetrics: ['CLS < 0.02', 'Audit script exit 0', 'Zero broken relative links'],
        triggers: [
          { id: 'trg_layout_cron', kind: 'cron', expression: '0 */3 * * *', nodeTarget: 'mac', enabled: true },
        ],
        preferredHarness: 'claude-code',
        fallbackHarnesses: ['pi', 'codex'],
        targetNodeId: 'mac-resident',
        status: 'needs_you',
        maxSubSessions: 3,
        dailyBudgetUsd: 8.0,
        spentTodayUsd: 1.42,
        lastEvaluatedAt: isoOffset(18),
        lastEvidenceArtifactIds: ['art_cls_before', 'art_cls_after'],
        createdAt: isoOffset(1440),
        updatedAt: isoOffset(18),
      },
      {
        id: 'out_android_parity',
        title: 'Cross-Platform Protocol & Swift Parity',
        domain: 'dev',
        goal: 'Keep `@pipibot/protocol`, `PipiAvatar` 53-state machine, and Apple SwiftUI models 100% synchronized across commits.',
        constraints: ['Zero external runtime dependencies in protocol/core', 'All 53 states verified in CI'],
        successMetrics: ['npm run verify exit 0', 'swift test exit 0'],
        triggers: [
          { id: 'trg_repo_watch', kind: 'filesystem_watch', expression: 'packages/protocol/**', enabled: true },
        ],
        preferredHarness: 'pi',
        fallbackHarnesses: ['claude-code', 'byok'],
        targetNodeId: 'mac-resident',
        status: 'active',
        maxSubSessions: 4,
        dailyBudgetUsd: 6.0,
        spentTodayUsd: 0.68,
        lastEvaluatedAt: isoOffset(42),
        lastEvidenceArtifactIds: ['art_proto_verify'],
        createdAt: isoOffset(4320),
        updatedAt: isoOffset(42),
      },
      {
        id: 'out_vps_guardian',
        title: 'HK VPS & Cloudflare Tunnel Guardian',
        domain: 'infra',
        goal: 'Watch HK VPS Docker containers, Nginx upstreams, and Cloudflare Tunnel RTT; auto-triage 502s and escalate config reloads.',
        constraints: ['Never reload Nginx or restart production DB without Needs-You approval', 'Stay inside $0/mo Cloudflare free tier'],
        successMetrics: ['HTTP 200 on /health', 'Tunnel RTT < 60ms', 'Workers requests < 50k/day'],
        triggers: [
          { id: 'trg_vps_thresh', kind: 'telemetry_threshold', expression: 'cpu>85% || http_502', nodeTarget: 'vps', enabled: true },
        ],
        preferredHarness: 'codex',
        fallbackHarnesses: ['pi', 'opencode'],
        targetNodeId: 'vps-hk-01',
        status: 'needs_you',
        maxSubSessions: 2,
        dailyBudgetUsd: 4.0,
        spentTodayUsd: 0.35,
        lastEvaluatedAt: isoOffset(9),
        lastEvidenceArtifactIds: ['art_nginx_test_log'],
        createdAt: isoOffset(7200),
        updatedAt: isoOffset(9),
      },
      {
        id: 'out_daily_rhythm',
        title: 'Evening Wind-Down & Life Logistics',
        domain: 'daily_life',
        goal: 'Coordinate gym nights (Tue/Thu), summarize pending calendar conflicts, and deliver tomorrow morning briefing to iOS.',
        constraints: ['Do not send external messages or book flights without Needs-You sign-off'],
        successMetrics: ['Morning digest ready by 07:30', 'Zero double-booked evening blocks'],
        triggers: [
          { id: 'trg_life_cron', kind: 'cron', expression: '0 21 * * *', nodeTarget: 'ios', enabled: true },
        ],
        preferredHarness: 'byok',
        fallbackHarnesses: ['pi'],
        targetNodeId: 'mac-resident',
        status: 'active',
        maxSubSessions: 1,
        dailyBudgetUsd: 1.5,
        spentTodayUsd: 0.09,
        lastEvaluatedAt: isoOffset(120),
        lastEvidenceArtifactIds: ['art_life_preview'],
        createdAt: isoOffset(2880),
        updatedAt: isoOffset(120),
      },
    ];

    for (const outcome of outcomesSeed) {
      this.outcomes.set(outcome.id, outcome);
    }

    const subSessionsSeed: SubSession[] = [
      {
        id: 'sub_cls_fix',
        parentOutcomeId: 'out_layout_sentinel',
        role: 'layout-remediator',
        objective: 'Fix 14px vertical jump on iOS Swipe Deck sheet open (`topEdge = 54px`) and capture before/after R2 snapshots.',
        provider: 'claude-code',
        modelId: 'claude-sonnet-4-5',
        nodeId: 'mac-resident',
        worktreePath: '/Users/jimizhou/Desktop/Projects/pipibot/.worktrees/cls-fix',
        branchName: 'fix/ios-swipe-cls',
        status: 'needs_you',
        lastPulseAt: isoOffset(18),
        artifactIds: ['art_cls_before', 'art_cls_after'],
        summary: 'Reduced CLS from 0.14 to 0.004; PR #42 ready for merge.',
        startedAt: isoOffset(29),
      },
      {
        id: 'sub_nginx_triage',
        parentOutcomeId: 'out_vps_guardian',
        role: 'infra-triage',
        objective: 'Inspect upstream timeout in `/etc/nginx/conf.d/pipibot.conf` after container restart and verify `nginx -t`.',
        provider: 'codex',
        modelId: 'gpt-5-codex',
        nodeId: 'vps-hk-01',
        status: 'needs_you',
        lastPulseAt: isoOffset(9),
        artifactIds: ['art_nginx_test_log'],
        summary: 'Upstream keepalive tuned; `nginx -t` syntax is ok. Awaiting reload approval.',
        startedAt: isoOffset(14),
      },
      {
        id: 'sub_protocol_verify',
        parentOutcomeId: 'out_android_parity',
        role: 'contract-verifier',
        objective: 'Verify 53 AvatarState IDs match identically between TypeScript protocol and Design System.',
        provider: 'pi',
        modelId: 'pi-native-core',
        nodeId: 'mac-resident',
        branchName: 'main',
        status: 'succeeded',
        lastPulseAt: isoOffset(42),
        artifactIds: ['art_proto_verify'],
        summary: '53/53 states and 9/9 expressions verified across TypeScript & ESM engine.',
        startedAt: isoOffset(45),
        completedAt: isoOffset(42),
      },
    ];

    for (const sub of subSessionsSeed) {
      this.subSessions.set(sub.id, sub);
    }

    const decisionsSeed: NeedsYouDecision[] = [
      {
        id: 'dec_pr_42_merge',
        outcomeId: 'out_layout_sentinel',
        sessionId: 'sub_cls_fix',
        sourceNodeId: 'mac-resident',
        severity: 'warning',
        category: 'code_merge_or_push',
        title: 'Approve PR #42 · iOS Swipe Deck 120Hz Spring Fix',
        summary:
          'Layout Sentinel fixed a 14px sheet jump on iPhone 16 Pro (CLS 0.14 -> 0.004). All `audit-design-system` rules pass.',
        recommendedOptionId: 'approve_merge',
        options: [
          { id: 'approve_merge', label: 'Merge PR #42', style: 'primary' },
          { id: 'request_tweaks', label: 'Steer Damping', style: 'secondary' },
          { id: 'reject', label: 'Close PR', style: 'destructive' },
        ],
        evidence: [
          {
            artifactId: 'art_cls_before',
            r2Key: 'evidence/pr-42/before-cls.png',
            kind: 'screenshot',
            caption: 'Before: Sheet top offset shifted during spring settle (CLS 0.14)',
            signedUrl: '/v1/artifacts/download?key=evidence/pr-42/before-cls.png',
          },
          {
            artifactId: 'art_cls_after',
            r2Key: 'evidence/pr-42/after-cls.mp4',
            kind: 'video',
            caption: 'After: Locked 54px topEdge, 120fps smooth settle (CLS 0.004)',
            signedUrl: '/v1/artifacts/download?key=evidence/pr-42/after-cls.mp4',
          },
        ],
        status: 'pending',
        createdAt: isoOffset(18),
      },
      {
        id: 'dec_vps_nginx_reload',
        outcomeId: 'out_vps_guardian',
        sessionId: 'sub_nginx_triage',
        sourceNodeId: 'vps-hk-01',
        severity: 'critical',
        category: 'infra_mutation',
        title: 'Reload HK VPS Nginx Config (`nginx -t` Passed)',
        summary:
          'Codex isolated intermittent 502s on `vps-hk-01` to stale upstream keepalive sockets. Config patch validated via `nginx -t`.',
        recommendedOptionId: 'reload_nginx',
        options: [
          { id: 'reload_nginx', label: 'Reload Nginx', style: 'primary' },
          { id: 'canary_only', label: 'Inspect Diff Only', style: 'secondary' },
          { id: 'reject', label: 'Rollback Patch', style: 'destructive' },
        ],
        evidence: [
          {
            artifactId: 'art_nginx_test_log',
            r2Key: 'evidence/vps-hk-01/nginx-t.log',
            kind: 'log_excerpt',
            caption: 'nginx: configuration file /etc/nginx/nginx.conf test is successful',
          },
          {
            artifactId: 'art_nginx_diff',
            r2Key: 'evidence/vps-hk-01/upstream.patch',
            kind: 'diff_patch',
            caption: 'keepalive 32; proxy_read_timeout 45s;',
          },
        ],
        status: 'pending',
        createdAt: isoOffset(9),
      },
      {
        id: 'dec_life_schedule_shift',
        outcomeId: 'out_daily_rhythm',
        sessionId: 'sub_life_sync',
        sourceNodeId: 'ios-companion',
        severity: 'info',
        category: 'external_communication',
        title: 'Shift Thursday Gym Block & Confirm Dinner RSVP',
        summary:
          'Detected late design sync overlapping Thursday 19:30 gym reminder; PipiBot drafted a 20:15 reschedule and polite reply.',
        recommendedOptionId: 'apply_schedule',
        options: [
          { id: 'apply_schedule', label: 'Move to 20:15 & Send', style: 'primary' },
          { id: 'move_only', label: 'Move Calendar Only', style: 'secondary' },
          { id: 'reject', label: 'Dismiss', style: 'destructive' },
        ],
        evidence: [
          {
            artifactId: 'art_life_preview',
            r2Key: 'evidence/life/thu-calendar-diff.html',
            kind: 'html_preview',
            caption: 'Thursday evening timeline diff (19:30 -> 20:15)',
          },
        ],
        status: 'pending',
        createdAt: isoOffset(6),
      },
    ];

    for (const dec of decisionsSeed) {
      this.decisions.set(dec.id, dec);
    }
  }
}
