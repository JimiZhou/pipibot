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
