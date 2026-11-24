/**
 * @pipibot/protocol
 *
 * Zero-external-dependency shared types and constants for PipiBot across:
 * - Universal Harness Router (Pi, Claude Code, Codex, OpenCode, BYOK pi-ai)
 * - Devin-style Outcome Responsibilities, Sub-Sessions & Needs-You Escalation
 * - Manus Cue Ambient Context & Dots Fleet Telemetry (Mac, iOS, VPS, Windows, Embedded)
 * - 53-State Procedural Avatar Engine & 9 Core Expressions
 * - 4-Tier Cognitive Memory & Self-Evolution Diffs
 * - Cloudflare Edge Tunnel Relay, R2 Artifacts & Offline Webhook Queue
 */

// ---------------------------------------------------------------------------
// 1. Harness & Inference Routing (Pi + Local CLIs + BYOK)
// ---------------------------------------------------------------------------

export type HarnessProvider = 'pi' | 'claude-code' | 'codex' | 'opencode' | 'byok';

export type ByokApiProtocol =
  | 'openai-completions'
  | 'openai-responses'
  | 'anthropic-messages'
  | 'google-generative-ai'
  | 'openrouter'
  | 'ollama';

export type ByokVendorId =
  | 'openai'
  | 'anthropic'
  | 'google'
  | 'deepseek'
  | 'xai'
  | 'openrouter'
  | 'ollama'
  | 'vllm'
  | 'custom';

export interface ByokProviderConfig {
  id: string;
  vendor: ByokVendorId;
  /** Compatible with @mariozechner/pi-ai provider API taxonomy */
  api: ByokApiProtocol;
  modelId: string;
  baseUrl: string;
  /** Reference key name in macOS Keychain or env var (never serialized raw secret) */
  apiKeyEnvVar?: string;
  keychainService?: string;
  /** Optional direct runtime key (in-memory only; must never be persisted to L1/L2) */
  apiKey?: string;
  headers?: Record<string, string>;
  contextWindow: number;
  maxOutputTokens: number;
  supportsTools: boolean;
  supportsReasoning: boolean;
  supportsVision: boolean;
  costPerMillionInputUsd?: number;
  costPerMillionOutputUsd?: number;
}

export type HarnessExecutionPhase =
  | 'initializing'
  | 'recalling_memory'
  | 'streaming_model'
  | 'executing_tool'
  | 'awaiting_mcp_relay'
  | 'awaiting_human'
  | 'reflecting'
  | 'completed'
  | 'failed'
  | 'aborted';

export interface HarnessActivityPulse {
  sessionId: string;
  subSessionId?: string;
  provider: HarnessProvider;
  modelId?: string;
  phase: HarnessExecutionPhase;
  /** Standard 250ms activity pulse interval inspired by Grok Bot 0.18 */
  pulseIntervalMs: 250;
  seq: number;
  elapsedMs: number;
  activeToolName?: string;
  tokensEstimated: number;
  suggestedAvatarState: AvatarState53;
  timestamp: string;
}

export interface RoutedMcpToolDefinition {
  name: string;
  description: string;
  inputSchema: {
    type: 'object';
    properties: Record<string, {
      type: string;
      description?: string;
      enum?: readonly string[];
      items?: { type: string };
    }>;
    required?: readonly string[];
    additionalProperties?: boolean;
  };
  readOnlyHint?: boolean;
  requiresApproval?: boolean;
}

export interface HarnessProbeResult {
  provider: HarnessProvider;
  installed: boolean;
  authenticated: boolean;
  binaryPath?: string;
  version?: string;
  authSource?: string;
  supportsMcp: boolean;
  checkedAt: string;
}

// ---------------------------------------------------------------------------
// 2. Devin-Style Outcome Ownership, Sub-Sessions & Needs-You Escalation
// ---------------------------------------------------------------------------

export type OutcomeDomain = 'dev' | 'work' | 'daily_life' | 'infra';

export type OutcomeTriggerKind =
  | 'cron'
  | 'webhook'
  | 'filesystem_watch'
  | 'telemetry_threshold'
  | 'cue_action'
  | 'manual';

export interface OutcomeTriggerSpec {
  id: string;
  kind: OutcomeTriggerKind;
  // e.g. "0 */3 * * *" for cron, "github:pull_request" for webhook, "cpu>90%" for threshold
  expression: string;
  nodeTarget?: FleetNodeKind | string;
  enabled: boolean;
}

export type OutcomeStatus =
  | 'active'
  | 'evaluating'
  | 'delegating'
  | 'needs_you'
  | 'paused'
  | 'achieved'
  | 'failed';

export interface OutcomeResponsibility {
  id: string;
  title: string;
  domain: OutcomeDomain;
  goal: string;
  constraints: string[];
  successMetrics: string[];
  triggers: OutcomeTriggerSpec[];
  preferredHarness: HarnessProvider;
  fallbackHarnesses: HarnessProvider[];
  targetNodeId?: string;
  status: OutcomeStatus;
  maxSubSessions: number;
  dailyBudgetUsd: number;
  spentTodayUsd: number;
  lastEvaluatedAt?: string;
  lastEvidenceArtifactIds: string[];
  createdAt: string;
  updatedAt: string;
}

export type SubSessionStatus =
  | 'queued'
  | 'running'
  | 'waiting_tool'
  | 'needs_you'
  | 'succeeded'
  | 'failed'
  | 'cancelled';

export interface SubSession {
  id: string;
  parentOutcomeId?: string;
  parentSessionId?: string;
  role: string;
  objective: string;
  provider: HarnessProvider;
  modelId: string;
  nodeId: string;
  worktreePath?: string;
  branchName?: string;
  status: SubSessionStatus;
  lastPulseAt?: string;
  artifactIds: string[];
  summary?: string;
  startedAt: string;
  completedAt?: string;
}

export type DecisionSeverity = 'info' | 'warning' | 'critical';

export type DecisionCategory =
  | 'code_merge_or_push'
  | 'infra_mutation'
  | 'financial_or_purchase'
  | 'external_communication'
  | 'memory_evolution_review'
  | 'ambiguous_requirement';

export interface DecisionOption {
  id: string;
  label: string;
  style: 'primary' | 'secondary' | 'destructive';
  actionPayload?: Record<string, unknown>;
}

export interface ArtifactEvidenceRef {
  artifactId: string;
  r2Key: string;
  kind: 'screenshot' | 'video' | 'diff_patch' | 'html_preview' | 'log_excerpt';
  caption: string;
  signedUrl?: string;
  expiresAt?: string;
}

export interface NeedsYouDecision {
  id: string;
  outcomeId?: string;
  sessionId: string;
  sourceNodeId: string;
  severity: DecisionSeverity;
  category: DecisionCategory;
  title: string;
  summary: string;
  recommendedOptionId: string;
  options: DecisionOption[];
  evidence: ArtifactEvidenceRef[];
  timeoutSeconds?: number;
  fallbackAction?: 'pause' | 'abort' | 'auto_recommended';
  status: 'pending' | 'resolved' | 'expired';
  chosenOptionId?: string;
  userNote?: string;
  resolvedBy?: string;
  createdAt: string;
  resolvedAt?: string;
}

// ---------------------------------------------------------------------------
// 3. Manus Cue Ambient Context & PipiFleet Multi-Node Telemetry
// ---------------------------------------------------------------------------

export interface CueAction {
  id: string;
  label: string;
  hotkeyHint?: string;
  harness: HarnessProvider;
  promptTemplate: string;
  estimatedSeconds?: number;
  requiresConfirmation?: boolean;
}

export interface CueSuggestion {
  id: string;
  nodeId: string;
  activeAppName: string;
  activeAppBundleId: string;
  windowTitle: string;
  workspacePath?: string;
  gitBranch?: string;
  detectedIntent: string;
  confidence: number;
  actions: CueAction[];
  feedback?: 'accepted' | 'dismissed' | 'ignored';
  capturedAt: string;
  expiresAt: string;
}

export type FleetNodeKind = 'mac' | 'ios' | 'vps' | 'windows' | 'embedded';

export type DotsVitalityState = 'alive' | 'busy' | 'degraded' | 'sleeping' | 'offline';

export interface FleetNodeCapabilities {
  canRunPi: boolean;
  localHarnesses: HarnessProvider[];
  hasGpuOrNeuralEngine: boolean;
  canRunGuiCue: boolean;
  canActAsRelayHost: boolean;
  supportedTools: string[];
}

export interface FleetNodeTelemetry {
  nodeId: string;
  displayName: string;
  kind: FleetNodeKind;
  osVersion: string;
  arch: string;
  vitality: DotsVitalityState;
  cpuLoadPct: number;
  memoryUsedPct: number;
  diskUsedPct?: number;
  batteryPct?: number;
  isCharging?: boolean;
  tunnelRttMs?: number;
  activeSessionsCount: number;
  capabilities: FleetNodeCapabilities;
  tags: string[];
  lastSeenAt: string;
}

// ---------------------------------------------------------------------------
// 4. Procedural Avatar Engine: 53-State Machine & 9 Core Expressions
// ---------------------------------------------------------------------------

export type AvatarLifecycleGroup =
  | 'idle_ambient'
  | 'thinking_reasoning'
  | 'tool_harness_execution'
  | 'cue_needs_you_alert'
  | 'self_evolution_dreaming';

export type AvatarExpression9 =
  | 'neutral'
  | 'happy'
  | 'focused'
  | 'curious'
  | 'alert'
  | 'proud'
  | 'sleepy'
  | 'evolving'
  | 'listening';

export type AvatarShape =
  | 'orb'
  | 'squircle'
  | 'cloud'
  | 'spark'
  | 'bolt'
  | 'shield'
  | 'dream'
  | 'terminal';

export const AVATAR_EXPRESSIONS_9 = [
  'neutral',
  'happy',
  'focused',
  'curious',
  'alert',
  'proud',
  'sleepy',
  'evolving',
  'listening',
] as const satisfies readonly AvatarExpression9[];

/**
 * Complete canonical 53-state taxonomy grouped across the 5 lifecycle groups
 * (matching `design-system/pipibot-avatar.js` and `01-UIUX-DESIGN-SYSTEM.md`):
 * - idle_ambient (10)
 * - thinking_reasoning (11)
 * - tool_harness_execution (14)
 * - cue_needs_you_alert (10)
 * - self_evolution_dreaming (8)
 */
export const AVATAR_STATES_53 = [
  // Group 1: Idle & Ambient (10)
  'idle',
  'ambient-breathe',
  'ambient-wander',
  'ambient-curious-glance',
  'ambient-coffee-break',
  'ambient-night-watch',
  'ambient-battery-saver',
  'ambient-standby',
  'ambient-warm-welcome',
  'ambient-zen',

  // Group 2: Thinking & Reasoning (11)
  'thinking',
  'deep-reasoning',
  'memory-recall',
  'context-scanning',
  'plan-structuring',
  'hypothesis-branching',
  'cross-checking',
  'cost-routing',
  'diff-analyzing',
  'voice-transcribing',
  'synthesizing',

  // Group 3: Tool & Harness Execution (14)
  'pi-coding',
  'pi-bash-running',
  'pi-file-editing',
  'claude-routing',
  'codex-routing',
  'opencode-routing',
  'byok-streaming',
  'mcp-bridging',
  'subsession-spawning',
  'browser-evaluating',
  'vps-deploying',
  'mac-automating',
  'iot-signaling',
  'git-committing',

  // Group 4: Cue & Needs-You Alert (10)
  'manus-cue',
  'cue-whispering',
  'cue-window-matched',
  'needs-you',
  'needs-you-urgent',
  'needs-you-approval',
  'needs-you-diff-ready',
  'fleet-degraded',
  'tunnel-reconnecting',
  'voice-interrupted',

  // Group 5: Self-Evolution & Dreaming (8)
  'evolving',
  'sleeping',
  'dreaming-consolidating',
  'skill-synthesizing',
  'persona-updating',
  'memory-pruning',
  'r2-backing-up',
  'evolution-proud',
] as const;

export type AvatarState53 = (typeof AVATAR_STATES_53)[number];

export interface AvatarStateDescriptor {
  state: AvatarState53;
  group: AvatarLifecycleGroup;
  defaultExpression: AvatarExpression9;
  defaultShape: AvatarShape;
}

export const AVATAR_STATE_GROUP_MAP: Record<AvatarState53, AvatarLifecycleGroup> = {
  idle: 'idle_ambient',
  'ambient-breathe': 'idle_ambient',
  'ambient-wander': 'idle_ambient',
  'ambient-curious-glance': 'idle_ambient',
  'ambient-coffee-break': 'idle_ambient',
  'ambient-night-watch': 'idle_ambient',
  'ambient-battery-saver': 'idle_ambient',
  'ambient-standby': 'idle_ambient',
  'ambient-warm-welcome': 'idle_ambient',
  'ambient-zen': 'idle_ambient',

  thinking: 'thinking_reasoning',
  'deep-reasoning': 'thinking_reasoning',
  'memory-recall': 'thinking_reasoning',
  'context-scanning': 'thinking_reasoning',
  'plan-structuring': 'thinking_reasoning',
  'hypothesis-branching': 'thinking_reasoning',
  'cross-checking': 'thinking_reasoning',
  'cost-routing': 'thinking_reasoning',
  'diff-analyzing': 'thinking_reasoning',
  'voice-transcribing': 'thinking_reasoning',
  synthesizing: 'thinking_reasoning',

  'pi-coding': 'tool_harness_execution',
  'pi-bash-running': 'tool_harness_execution',
  'pi-file-editing': 'tool_harness_execution',
  'claude-routing': 'tool_harness_execution',
  'codex-routing': 'tool_harness_execution',
  'opencode-routing': 'tool_harness_execution',
  'byok-streaming': 'tool_harness_execution',
  'mcp-bridging': 'tool_harness_execution',
  'subsession-spawning': 'tool_harness_execution',
  'browser-evaluating': 'tool_harness_execution',
  'vps-deploying': 'tool_harness_execution',
  'mac-automating': 'tool_harness_execution',
  'iot-signaling': 'tool_harness_execution',
  'git-committing': 'tool_harness_execution',

  'manus-cue': 'cue_needs_you_alert',
  'cue-whispering': 'cue_needs_you_alert',
  'cue-window-matched': 'cue_needs_you_alert',
  'needs-you': 'cue_needs_you_alert',
  'needs-you-urgent': 'cue_needs_you_alert',
  'needs-you-approval': 'cue_needs_you_alert',
  'needs-you-diff-ready': 'cue_needs_you_alert',
  'fleet-degraded': 'cue_needs_you_alert',
  'tunnel-reconnecting': 'cue_needs_you_alert',
  'voice-interrupted': 'cue_needs_you_alert',

  evolving: 'self_evolution_dreaming',
  sleeping: 'self_evolution_dreaming',
  'dreaming-consolidating': 'self_evolution_dreaming',
  'skill-synthesizing': 'self_evolution_dreaming',
  'persona-updating': 'self_evolution_dreaming',
  'memory-pruning': 'self_evolution_dreaming',
  'r2-backing-up': 'self_evolution_dreaming',
  'evolution-proud': 'self_evolution_dreaming',
};

// ---------------------------------------------------------------------------
// 5. 4-Tier Cognitive Memory & Self-Evolution Contracts
// ---------------------------------------------------------------------------

export type MemoryTier = 'L0_WORKING' | 'L1_EPISODIC' | 'L2_SEMANTIC' | 'L3_PROCEDURAL';

export type MemoryDomain =
  | 'coding_convention'
  | 'communication_pref'
  | 'daily_life'
  | 'work_context'
  | 'infra_topology';

export type MemorySourceKind =
  | 'conversation_turn'
  | 'tool_trace'
  | 'outcome_result'
  | 'git_commit'
  | 'life_log'
  | 'cue_feedback'
  | 'infra_event';

export type MemoryTrustLevel = 'user_verified' | 'local_tool' | 'untrusted_external';

export interface SalienceBreakdown {
  recency: number;
  importance: number;
  relevance: number;
  confidence: number;
  rrfScore?: number;
  finalSalience: number;
}

export interface MemoryEntry {
  id: string;
  seq: number;
  tier: MemoryTier;
  domain: MemoryDomain;
  sourceKind: MemorySourceKind;
  sessionId?: string;
  harnessProvider?: HarnessProvider;
  nodeId?: string;
  title: string;
  content: string;
  toolSignature?: string;
  outcomeSuccess?: boolean;
  importanceBase: number;
  confidence: number;
  explicitSignal: boolean;
  trustLevel: MemoryTrustLevel;
  redactedCount: number;
  accessCount: number;
  lastAccessedAt?: number;
  createdAt: number;
  consolidatedAt?: number;
  embedding?: number[];
  salience?: SalienceBreakdown;
  metadata?: Record<string, unknown>;
}

export type PersonaFactStatus = 'candidate' | 'active' | 'superseded' | 'reverted';

export interface UserPersonaFact {
  id: string;
  subject: string;
  predicate: string;
  objectValue: string;
  domain: MemoryDomain;
  scope: string;
  status: PersonaFactStatus;
  confidence: number;
  importance: number;
  evidenceCount: number;
  evidenceEventIds: string[];
  validFrom: number;
  validTo?: number;
  supersededBy?: string;
  createdAt: number;
  updatedAt: number;
}

export interface UnderstandingScoreBreakdown {
  overall: number;
  deltaFromPrevious: number;
  breakdown: Record<MemoryDomain, number>;
  metrics: {
    coverage: number;
    cueAcceptanceRate: number;
    memoryRetention: number;
    correctionRate: number;
  };
}

export type EvolutionDiffOperation = 'add' | 'supersede' | 'add_skill' | 'update_soul' | 'archive';

export type EvolutionReviewStatus = 'pending' | 'approved' | 'edited' | 'reverted';

export interface EvolutionDiffItem {
  diffId: string;
  operation: EvolutionDiffOperation;
  targetFile: string;
  domain: MemoryDomain;
  title: string;
  factId?: string;
  skillSlug?: string;
  previousValue?: string;
  proposedValue: string;
  confidence: number;
  evidenceEventIds: string[];
  evidenceSummary: string;
  reviewStatus: EvolutionReviewStatus;
}

export interface SynthesizedSkillCandidate {
  slug: string;
  name: string;
  description: string;
  domain: MemoryDomain;
  toolSequence: string[];
  occurrences: number;
  successRate: number;
  skillMarkdown: string;
  extensionHookTs?: string;
  status: 'candidate' | 'active' | 'reverted';
}

export interface EvolutionSummary {
  digestId: string;
  cycle: 'micro_reflection' | 'nightly_dreaming' | 'weekly_meta';
  generatedAt: string;
  windowStart: string;
  windowEnd: string;
  episodicEventsProcessed: number;
  understandingScore: UnderstandingScoreBreakdown;
  diffs: EvolutionDiffItem[];
  candidateSkills: SynthesizedSkillCandidate[];
  requiresUserReviewCount: number;
}

// ---------------------------------------------------------------------------
// 6. Cloudflare Edge Tunnel Relay, Presence, Queue & R2 Artifact Envelopes
// ---------------------------------------------------------------------------

export type RelayMessageType =
  | 'node.heartbeat'
  | 'harness.pulse'
  | 'harness.stream_chunk'
  | 'outcome.update'
  | 'decision.needs_you'
  | 'decision.resolved'
  | 'cue.suggestion'
  | 'evolution.digest_ready'
  | 'evolution.diff_action'
  | 'queue.command'
  | 'relay.ping'
  | 'relay.pong';

export interface CloudflareRelayEnvelope<TPayload = unknown> {
  version: '1.0';
  messageId: string;
  type: RelayMessageType;
  sourceNodeId: string;
  targetNodeId?: string;
  sessionId?: string;
  correlationId?: string;
  timestamp: string;
  payload: TPayload;
}

export interface AccessIdentityContext {
  authenticated: boolean;
  authKind: 'cf_access_jwt' | 'cf_service_token' | 'node_hmac' | 'dev_bypass';
  email?: string;
  subject?: string;
  clientId?: string;
  issuer?: string;
}

export interface TunnelPresenceRecord {
  nodeId: string;
  kind: FleetNodeKind;
  displayName: string;
  vitality: DotsVitalityState;
  tunnelUrl?: string;
  activeSessionsCount: number;
  tunnelRttMs?: number;
  batteryPct?: number;
  lastSeenAt: string;
}

export interface OfflineWebhookItem {
  id: string;
  idempotencyKey: string;
  targetNodeId: string;
  source: 'ios_client' | 'github_webhook' | 'linear_webhook' | 'cron_trigger' | 'iot_mqtt';
  eventType: string;
  payload: Record<string, unknown>;
  status: 'pending' | 'delivered' | 'acked' | 'expired';
  retryCount: number;
  createdAt: string;
  expiresAt: string;
}

export interface ArtifactPresignRequest {
  r2Key: string;
  contentType: string;
  sizeBytes: number;
  kind: 'screenshot' | 'video' | 'encrypted_memory_backup' | 'html_preview' | 'log';
  sha256Hex: string;
  ttlSeconds?: number;
}

export interface ArtifactPresignResponse {
  artifactId: string;
  r2Key: string;
  signedDownloadUrl: string;
  expiresAt: string;
}

export interface ApnsPushPayload {
  title: string;
  subtitle?: string;
  body: string;
  category: 'NEEDS_YOU_DECISION' | 'EVOLUTION_DIGEST' | 'FLEET_ALERT' | 'OUTCOME_DONE';
  decisionId?: string;
  digestId?: string;
  badgeCount?: number;
  threadId?: string;
}

// ---------------------------------------------------------------------------
// 7. Host Protocol v2: Priority Model Scheduling, Two-Tier Guardrail & Team Topologies
//
// Clean-room MIT implementation matching `packages/protocol/schema/host-v2.schema.json`.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.
// ---------------------------------------------------------------------------

export const SESSION_STATES_V2 = [
  'idle',
  'queued',
  'running',
  'needsYou',
  'done',
  'failed',
  'cancelled',
] as const;

export type SessionStateV2 = (typeof SESSION_STATES_V2)[number];

export const PERMISSION_TIERS_V2 = ['readOnly', 'ask', 'autoEdit'] as const;

export type PermissionTierV2 = (typeof PERMISSION_TIERS_V2)[number];

export const SCHEDULER_PRIORITIES = [
  'approval_review',
  'voice_interactive',
  'chat_interactive',
  'delegated_task',
  'proactive_routine',
  'compaction',
  'background_memory',
] as const;

export type SchedulerPriority = (typeof SCHEDULER_PRIORITIES)[number];

export const RISK_LEVELS = ['low', 'medium', 'high', 'critical'] as const;

export type RiskLevel = (typeof RISK_LEVELS)[number];

export const USER_AUTHORIZATION_LEVELS = ['high', 'medium', 'low', 'unknown'] as const;

export type UserAuthorizationLevel = (typeof USER_AUTHORIZATION_LEVELS)[number];

export const GUARDRAIL_DECISIONS = ['allow', 'needs_approval', 'deny'] as const;

export type GuardrailDecision = (typeof GUARDRAIL_DECISIONS)[number];

export const APPROVAL_GRANULARITIES = [
  'allow_once',
  'allow_session',
  'allow_project',
  'allow_always',
  'deny',
] as const;

export type ApprovalGranularity = (typeof APPROVAL_GRANULARITIES)[number];

export const ACTION_KINDS = [
  'read_only',
  'prepare_draft',
  'local_write',
  'shell_command',
  'external_effect',
  'credential_access',
  'security_change',
  'destructive',
] as const;

export type ActionKind = (typeof ACTION_KINDS)[number];

export const ACTION_SOURCE_TRUSTS = [
  'trusted_user',
  'trusted_user_routine',
  'agent_generated_routine',
  'untrusted_external',
] as const;

export type ActionSourceTrust = (typeof ACTION_SOURCE_TRUSTS)[number];

export const OPERATION_LEDGER_STATUSES = [
  'in_flight',
  'completed',
  'denied',
  'unknown_outcome',
] as const;

export type OperationLedgerStatus = (typeof OPERATION_LEDGER_STATUSES)[number];

export const TEAM_COLLABORATION_PATTERNS = [
  'classify-and-act',
  'fan-out-and-synthesize',
  'adversarial-verification',
  'tournament',
  'loop-until-done',
] as const;

export type TeamCollaborationPattern = (typeof TEAM_COLLABORATION_PATTERNS)[number];

export interface GuardrailActionInput {
  operationId: string;
  toolName: string;
  actionKind: ActionKind;
  target: string;
  payloadSummary: string;
  isPreparatoryOnly?: boolean;
  sessionId?: string;
  projectId?: string;
  sourceTrust: ActionSourceTrust;
  trustedUserMessages: string[];
  untrustedContextSnippets?: string[];
  hasRecentRevocation?: boolean;
}

export interface GuardrailVerdict {
  riskLevel: RiskLevel;
  userAuthorization: UserAuthorizationLevel;
  decision: GuardrailDecision;
  rationale: string;
  operationId: string;
  ruleId?: string;
  usedLLMJudge?: boolean;
  matchedWhitelistRuleId?: string;
}

export interface ApprovalWhitelistRule {
  id: string;
  granularity: 'allow_session' | 'allow_project' | 'allow_always';
  toolName: string;
  actionKind: ActionKind;
  targetPattern?: string;
  sessionId?: string;
  projectId?: string;
  note?: string;
  createdAt: string;
}

// ---------------------------------------------------------------------------
// 8. Wave 2 Canonical Host v2 Contracts (#01 Personal Wiki, #02 Bot Memory, #03 Proactive)
// ---------------------------------------------------------------------------

export const WIKI_ENTITY_CATEGORIES = [
  'people',
  'projects',
  'topics',
  'life',
  'repos',
] as const;

export type WikiEntityCategory = (typeof WIKI_ENTITY_CATEGORIES)[number];

export const WIKI_SEARCH_SCOPES = ['all', 'originals', 'summaries'] as const;

export type WikiSearchScope = (typeof WIKI_SEARCH_SCOPES)[number];

export const BOT_MEMORY_LIFECYCLE_STAGES = [
  'candidate',
  'consolidated',
  'archived',
] as const;

export type BotMemoryLifecycleStage = (typeof BOT_MEMORY_LIFECYCLE_STAGES)[number];

export const PROACTIVE_SOURCE_KINDS = [
  'calendar_eventkit',
  'reminders_eventkit',
  'git_workspace',
  'device_telemetry',
  'chat_pocket_note',
] as const;

export type ProactiveSourceKind = (typeof PROACTIVE_SOURCE_KINDS)[number];

export const PROACTIVE_ACTION_DECISIONS = [
  'remind_directly',
  'prepare_briefing',
  'track_for_follow_up',
  'stay_silent',
] as const;

export type ProactiveActionDecision = (typeof PROACTIVE_ACTION_DECISIONS)[number];

export const PROACTIVE_FEEDBACK_SIGNALS = [
  'acted',
  'thanked',
  'dismissed',
  'snoozed',
  'muted_topic',
  'ignored',
] as const;

export type ProactiveFeedbackSignal = (typeof PROACTIVE_FEEDBACK_SIGNALS)[number];

// ---------------------------------------------------------------------------
// 9. Wave 3 Canonical Host v2 Contracts (#05 AlterEgo, #06 team.md, #11 CLI/Skills/Notes)
// ---------------------------------------------------------------------------

export const DELEGATION_TASK_STATUSES = [
  'queued',
  'running',
  'paused',
  'completed',
  'failed',
  'cancelled',
] as const;

export type DelegationTaskStatus = (typeof DELEGATION_TASK_STATUSES)[number];

export const DYNAMIC_BOT_PROPOSAL_ACTIONS = [
  'invite_existing',
  'create_and_invite',
] as const;

export type DynamicBotProposalAction = (typeof DYNAMIC_BOT_PROPOSAL_ACTIONS)[number];

export const DYNAMIC_BOT_PROPOSAL_STATUSES = [
  'pending',
  'approved',
  'rejected',
] as const;

export type DynamicBotProposalStatus = (typeof DYNAMIC_BOT_PROPOSAL_STATUSES)[number];

export const TRACKING_ITEM_STATUSES = [
  'open',
  'done',
  'archived',
] as const;

export type TrackingItemStatus = (typeof TRACKING_ITEM_STATUSES)[number];

export const ARTIFACT_DOCUMENT_KINDS = [
  'note',
  'report',
  'spec',
  'plan',
  'draft',
] as const;

export type ArtifactDocumentKind = (typeof ARTIFACT_DOCUMENT_KINDS)[number];

// ---------------------------------------------------------------------------
// 10. Wave 4 Canonical Host v2 Contracts (#07 Local Model Stack & #10 Daily Voice)
// ---------------------------------------------------------------------------

export const MODEL_SOURCE_MODES = [
  'local_model',
  'subscription',
  'byok',
] as const;

export type ModelSourceMode = (typeof MODEL_SOURCE_MODES)[number];

export const LOCAL_INFERENCE_ENGINE_KINDS = [
  'polystrata',
  'llama_cpp',
  'ollama',
  'mlx',
] as const;

export type LocalInferenceEngineKind = (typeof LOCAL_INFERENCE_ENGINE_KINDS)[number];

export const MODEL_SELF_TEST_STATUSES = [
  'untested',
  'running',
  'verified',
  'failed',
] as const;

export type ModelSelfTestStatus = (typeof MODEL_SELF_TEST_STATUSES)[number];

export const VOICE_INTERACTION_MODES = [
  'dictation',
  'muse_hands_free',
  'voice_to_task',
] as const;

export type VoiceInteractionMode = (typeof VOICE_INTERACTION_MODES)[number];

export const VOICE_SESSION_STATES = [
  'idle',
  'listening',
  'transcribing',
  'thinking',
  'speaking',
  'interrupted',
  'error',
] as const;

export type VoiceSessionState = (typeof VOICE_SESSION_STATES)[number];

export const VOICE_ENGINE_PROVIDERS = [
  'apple_on_device',
  'whisper_kit',
  'mlx_audio',
  'openai_byok',
  'deepgram_byok',
  'elevenlabs_byok',
  'custom_byok',
] as const;

export type VoiceEngineProvider = (typeof VOICE_ENGINE_PROVIDERS)[number];

export const VOICE_PRIVACY_POLICIES = [
  'on_device_only',
  'on_device_first',
  'cloud_preferred',
] as const;

export type VoicePrivacyPolicy = (typeof VOICE_PRIVACY_POLICIES)[number];

// ---------------------------------------------------------------------------
// 11. Wave 5 Canonical Host v2 Contracts (#09 Computer Use: Phase A Chrome & Phase B macOS Cua)
// ---------------------------------------------------------------------------

export const COMPUTER_USE_PHASES = [
  'chrome_browser',
  'macos_desktop',
] as const;

export type ComputerUsePhase = (typeof COMPUTER_USE_PHASES)[number];

export const BROWSER_SEAT_MODES = [
  'signed_in_chrome_seat',
  'isolated_profile',
] as const;

export type BrowserSeatMode = (typeof BROWSER_SEAT_MODES)[number];

export const COMPUTER_USE_ACTION_TYPES = [
  'snapshot',
  'navigate',
  'click',
  'double_click',
  'type_text',
  'press_key',
  'scroll',
  'drag',
  'submit_form',
  'focus_window',
] as const;

export type ComputerUseActionType = (typeof COMPUTER_USE_ACTION_TYPES)[number];

export const COMPUTER_USE_LANE_KINDS = [
  'desktop_screen',
  'agent_browser',
] as const;

export type ComputerUseLaneKind = (typeof COMPUTER_USE_LANE_KINDS)[number];

export const COMPUTER_USE_LANE_STATES = [
  'idle',
  'active',
  'yielded_to_human',
  'blocked_unknown_outcome',
] as const;

export type ComputerUseLaneState = (typeof COMPUTER_USE_LANE_STATES)[number];

export const WRITE_AHEAD_JOURNAL_STATUSES = [
  'prepared',
  'dispatched',
  'committed',
  'yielded_to_human',
  'blocked_guardrail',
  'unknown_outcome',
] as const;

export type WriteAheadJournalStatus = (typeof WRITE_AHEAD_JOURNAL_STATUSES)[number];

// ---------------------------------------------------------------------------
// 12. Phase 2 Canonical Board Coordination Contracts (Channel -> Thread -> Task)
// ---------------------------------------------------------------------------

export const BOARD_THREAD_KINDS = [
  'discussion',
  'task',
  'review',
  'incident',
] as const;

export type BoardThreadKind = (typeof BOARD_THREAD_KINDS)[number];

export const BOARD_TASK_STATUSES = [
  'open',
  'blocked',
  'claimed',
  'needs_you',
  'done',
  'cancelled',
] as const;

export type BoardTaskStatus = (typeof BOARD_TASK_STATUSES)[number];

export const BOARD_ACTOR_KINDS = [
  'human',
  'bot',
  'harness',
  'system',
] as const;

export type BoardActorKind = (typeof BOARD_ACTOR_KINDS)[number];

export const BOARD_EVENT_KINDS = [
  'channel_created',
  'thread_created',
  'message_posted',
  'task_claimed',
  'lease_renewed',
  'claim_lost',
  'task_unblocked',
  'task_needs_you',
  'task_completed',
  'followup_scheduled',
  'followup_triggered',
] as const;

export type BoardEventKind = (typeof BOARD_EVENT_KINDS)[number];

export type BoardTaskPriority = 'urgent' | 'high' | 'normal' | 'low';

export interface BoardActorRef {
  id: string;
  name: string;
  kind: BoardActorKind;
  harness?: HarnessProvider;
  nodeId?: string;
}

export interface BoardChannel {
  id: string;
  slug: string; // e.g. "inbox", "dev", "dev/pipibot", "ops"
  title: string;
  description?: string;
  createdAt: string;
  updatedAt: string;
}

export interface BoardMessage {
  id: string;
  threadId: string;
  author: BoardActorRef;
  body: string;
  artifactRef?: string;
  metadata?: Record<string, string>;
  createdAt: string;
}

export interface BoardTaskClaim {
  actor: BoardActorRef;
  leaseToken: string;
  claimedAt: string;
  expiresAt: string;
  renewCount: number;
  note?: string;
}

export interface BoardScheduledFollowUp {
  id: string;
  threadId: string;
  actor: BoardActorRef;
  prompt: string;
  dueAt: string;
  status: 'pending' | 'triggered' | 'cancelled';
  createdAt: string;
  triggeredAt?: string;
}

export interface BoardThread {
  id: string;
  channelSlug: string;
  kind: BoardThreadKind;
  title: string;
  status: BoardTaskStatus;
  priority: BoardTaskPriority;
  labels: string[];
  blockedBy: string[];
  claim?: BoardTaskClaim;
  claimLostCount: number;
  maxClaimRetries: number;
  messages: BoardMessage[];
  followUps: BoardScheduledFollowUp[];
  deliverableRef?: string;
  linkedConversationId?: string;
  linkedWorktreeId?: string;
  linkedDecisionId?: string;
  createdBy: BoardActorRef;
  createdAt: string;
  updatedAt: string;
  completedAt?: string;
}

export interface BoardActivityEvent {
  id: string;
  kind: BoardEventKind;
  channelSlug: string;
  threadId?: string;
  actor: BoardActorRef;
  summary: string;
  detail?: Record<string, string>;
  createdAt: string;
}

export interface BoardSnapshot {
  channels: BoardChannel[];
  threads: BoardThread[];
  recentEvents: BoardActivityEvent[];
  counts: Record<BoardTaskStatus, number>;
  updatedAt: string;
}





