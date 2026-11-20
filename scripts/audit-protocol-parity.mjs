#!/usr/bin/env node
/**
 * scripts/audit-protocol-parity.mjs
 *
 * Wave 1 (#12) Cross-Platform Contract & Attribution Auditor:
 * - Verifies 1:1 exact enum parity between `packages/protocol/schema/host-v2.schema.json`
 *   (canonical single source of truth), TypeScript (`packages/protocol/src/index.ts`),
 *   and Swift (`apps/apple/Sources/PipiBotKit/Models/SessionHostModels.swift`).
 * - Verifies clean-room MIT upstream attribution headers and root `NOTICE` file.
 *
 * Clean-room MIT implementation inspired by the contract-verification discipline of
 * simplexai-labs/linger (see root NOTICE and LICENSE). Zero external dependencies.
 */

import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, '..');

function fail(msg) {
  console.error(`FAIL: ${msg}`);
  process.exitCode = 1;
}

function pass(msg) {
  console.log(`PASS: ${msg}`);
}

const schemaPath = resolve(repoRoot, 'packages/protocol/schema/host-v2.schema.json');
const tsProtocolPath = resolve(repoRoot, 'packages/protocol/src/index.ts');
const swiftModelsPath = resolve(repoRoot, 'apps/apple/Sources/PipiBotKit/Models/SessionHostModels.swift');
const noticePath = resolve(repoRoot, 'NOTICE');

if (!existsSync(schemaPath)) {
  fail(`Missing canonical schema: ${schemaPath}`);
  process.exit(1);
}

const schema = JSON.parse(readFileSync(schemaPath, 'utf8'));
const tsSource = readFileSync(tsProtocolPath, 'utf8');
const swiftSource = readFileSync(swiftModelsPath, 'utf8');

function extractTsConstArray(source, constName) {
  const re = new RegExp(`export const ${constName}\\s*=\\s*\\[([\\s\\S]*?)\\]\\s*as const`, 'm');
  const match = source.match(re);
  if (!match) return null;
  const items = [];
  const itemRe = /'([^']+)'/g;
  let m;
  while ((m = itemRe.exec(match[1])) !== null) {
    items.push(m[1]);
  }
  return items;
}

function extractSwiftStringEnumCases(source, enumName) {
  const startRe = new RegExp(`public enum ${enumName}\\s*:\\s*String[^{]*\\{`, 'm');
  const startMatch = startRe.exec(source);
  if (!startMatch) return null;
  let depth = 1;
  let idx = startMatch.index + startMatch[0].length;
  while (idx < source.length && depth > 0) {
    if (source[idx] === '{') depth += 1;
    else if (source[idx] === '}') depth -= 1;
    idx += 1;
  }
  const body = source.slice(startMatch.index + startMatch[0].length, idx - 1);
  const values = [];
  // Match top-level `case foo` or `case foo = "bar"` inside the enum (before any nested switch)
  for (const rawLine of body.split('\n')) {
    const line = rawLine.trim();
    if (line.startsWith('public func') || line.startsWith('public var') || line.startsWith('public static')) {
      break;
    }
    const explicit = line.match(/^case\s+([A-Za-z0-9_]+)\s*=\s*"([^"]+)"/);
    if (explicit) {
      values.push(explicit[2]);
      continue;
    }
    const implicit = line.match(/^case\s+([A-Za-z0-9_]+)\s*$/);
    if (implicit) {
      values.push(implicit[1]);
    }
  }
  return values;
}

const ENUM_PARITY_MAP = [
  { schemaDef: 'SessionState', tsConst: 'SESSION_STATES_V2', swiftEnum: 'PipiSessionState' },
  { schemaDef: 'PermissionTier', tsConst: 'PERMISSION_TIERS_V2', swiftEnum: 'PipiPermissionTier' },
  { schemaDef: 'SchedulerPriority', tsConst: 'SCHEDULER_PRIORITIES', swiftEnum: 'PipiSchedulerPriority' },
  { schemaDef: 'RiskLevel', tsConst: 'RISK_LEVELS', swiftEnum: 'PipiRiskLevel' },
  { schemaDef: 'UserAuthorizationLevel', tsConst: 'USER_AUTHORIZATION_LEVELS', swiftEnum: 'PipiUserAuthorizationLevel' },
  { schemaDef: 'GuardrailDecision', tsConst: 'GUARDRAIL_DECISIONS', swiftEnum: 'PipiGuardrailDecision' },
  { schemaDef: 'ApprovalGranularity', tsConst: 'APPROVAL_GRANULARITIES', swiftEnum: 'PipiApprovalGranularity' },
  { schemaDef: 'ActionKind', tsConst: 'ACTION_KINDS', swiftEnum: 'PipiActionKind' },
  { schemaDef: 'ActionSourceTrust', tsConst: 'ACTION_SOURCE_TRUSTS', swiftEnum: 'PipiActionSourceTrust' },
  { schemaDef: 'OperationLedgerStatus', tsConst: 'OPERATION_LEDGER_STATUSES', swiftEnum: 'PipiOperationLedgerStatus' },
  { schemaDef: 'TeamCollaborationPattern', tsConst: 'TEAM_COLLABORATION_PATTERNS', swiftEnum: 'PipiTeamCollaborationPattern' },
  { schemaDef: 'WikiEntityCategory', tsConst: 'WIKI_ENTITY_CATEGORIES', swiftEnum: 'PipiWikiEntityCategory' },
  { schemaDef: 'WikiSearchScope', tsConst: 'WIKI_SEARCH_SCOPES', swiftEnum: 'PipiWikiSearchScope' },
  { schemaDef: 'BotMemoryLifecycleStage', tsConst: 'BOT_MEMORY_LIFECYCLE_STAGES', swiftEnum: 'PipiBotMemoryLifecycleStage' },
  { schemaDef: 'ProactiveSourceKind', tsConst: 'PROACTIVE_SOURCE_KINDS', swiftEnum: 'PipiProactiveSourceKind' },
  { schemaDef: 'ProactiveActionDecision', tsConst: 'PROACTIVE_ACTION_DECISIONS', swiftEnum: 'PipiProactiveActionDecision' },
  { schemaDef: 'ProactiveFeedbackSignal', tsConst: 'PROACTIVE_FEEDBACK_SIGNALS', swiftEnum: 'PipiProactiveFeedbackSignal' },
  { schemaDef: 'DelegationTaskStatus', tsConst: 'DELEGATION_TASK_STATUSES', swiftEnum: 'PipiDelegationTaskStatus' },
  { schemaDef: 'DynamicBotProposalAction', tsConst: 'DYNAMIC_BOT_PROPOSAL_ACTIONS', swiftEnum: 'PipiDynamicBotProposalAction' },
  { schemaDef: 'DynamicBotProposalStatus', tsConst: 'DYNAMIC_BOT_PROPOSAL_STATUSES', swiftEnum: 'PipiDynamicBotProposalStatus' },
  { schemaDef: 'TrackingItemStatus', tsConst: 'TRACKING_ITEM_STATUSES', swiftEnum: 'PipiTrackingItemStatus' },
  { schemaDef: 'ArtifactDocumentKind', tsConst: 'ARTIFACT_DOCUMENT_KINDS', swiftEnum: 'PipiArtifactDocumentKind' },
  { schemaDef: 'ModelSourceMode', tsConst: 'MODEL_SOURCE_MODES', swiftEnum: 'PipiModelSourceMode' },
  { schemaDef: 'LocalInferenceEngineKind', tsConst: 'LOCAL_INFERENCE_ENGINE_KINDS', swiftEnum: 'PipiLocalInferenceEngineKind' },
  { schemaDef: 'ModelSelfTestStatus', tsConst: 'MODEL_SELF_TEST_STATUSES', swiftEnum: 'PipiModelSelfTestStatus' },
  { schemaDef: 'VoiceInteractionMode', tsConst: 'VOICE_INTERACTION_MODES', swiftEnum: 'PipiVoiceInteractionMode' },
  { schemaDef: 'VoiceSessionState', tsConst: 'VOICE_SESSION_STATES', swiftEnum: 'PipiVoiceSessionState' },
  { schemaDef: 'VoiceEngineProvider', tsConst: 'VOICE_ENGINE_PROVIDERS', swiftEnum: 'PipiVoiceEngineProvider' },
  { schemaDef: 'VoicePrivacyPolicy', tsConst: 'VOICE_PRIVACY_POLICIES', swiftEnum: 'PipiVoicePrivacyPolicy' },
  { schemaDef: 'ComputerUsePhase', tsConst: 'COMPUTER_USE_PHASES', swiftEnum: 'PipiComputerUsePhase' },
  { schemaDef: 'BrowserSeatMode', tsConst: 'BROWSER_SEAT_MODES', swiftEnum: 'PipiBrowserSeatMode' },
  { schemaDef: 'ComputerUseActionType', tsConst: 'COMPUTER_USE_ACTION_TYPES', swiftEnum: 'PipiComputerUseActionType' },
  { schemaDef: 'ComputerUseLaneKind', tsConst: 'COMPUTER_USE_LANE_KINDS', swiftEnum: 'PipiComputerUseLaneKind' },
  { schemaDef: 'ComputerUseLaneState', tsConst: 'COMPUTER_USE_LANE_STATES', swiftEnum: 'PipiComputerUseLaneState' },
  { schemaDef: 'WriteAheadJournalStatus', tsConst: 'WRITE_AHEAD_JOURNAL_STATUSES', swiftEnum: 'PipiWriteAheadJournalStatus' },
];

console.log('=== PiPiBot Cross-Platform Protocol Parity & Attribution Audit ===');

let checkedEnums = 0;
for (const spec of ENUM_PARITY_MAP) {
  const expected = schema.$defs?.[spec.schemaDef]?.enum;
  if (!Array.isArray(expected) || expected.length === 0) {
    fail(`Schema $defs.${spec.schemaDef}.enum is missing or empty`);
    continue;
  }

  const tsValues = extractTsConstArray(tsSource, spec.tsConst);
  if (!tsValues) {
    fail(`TypeScript constant ${spec.tsConst} not found in packages/protocol/src/index.ts`);
  } else if (JSON.stringify(tsValues) !== JSON.stringify(expected)) {
    fail(
      `TypeScript ${spec.tsConst} mismatch vs schema ${spec.schemaDef}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(tsValues)}`,
    );
  }

  const swiftValues = extractSwiftStringEnumCases(swiftSource, spec.swiftEnum);
  if (!swiftValues) {
    fail(`Swift enum ${spec.swiftEnum} not found in SessionHostModels.swift`);
  } else if (JSON.stringify(swiftValues) !== JSON.stringify(expected)) {
    fail(
      `Swift ${spec.swiftEnum} mismatch vs schema ${spec.schemaDef}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(swiftValues)}`,
    );
  }

  checkedEnums += 1;
}

if (!process.exitCode) {
  pass(`All ${checkedEnums}/${ENUM_PARITY_MAP.length} canonical Host v2 enums match 1:1 across JSON Schema, TypeScript, and Swift.`);
}

// Verify root NOTICE & clean-room attribution headers on Wave 1 files
if (!existsSync(noticePath)) {
  fail('Missing root NOTICE file for upstream attribution and license boundaries.');
} else {
  const noticeBody = readFileSync(noticePath, 'utf8');
  if (!noticeBody.includes('simplexai-labs/linger') || !noticeBody.includes('MIT License')) {
    fail('Root NOTICE must explicitly document simplexai-labs/linger attribution and MIT License boundary.');
  } else {
    pass('Root NOTICE verified with upstream attribution and clean-room MIT boundary.');
  }
}

const ATTRIBUTION_FILES = [
  // Wave 1
  'packages/core/src/model-scheduler.ts',
  'packages/core/src/permission-guardrail.ts',
  'apps/apple/Sources/PipiBotKit/Runtime/PipiModelScheduler.swift',
  'apps/apple/Sources/PipiBotKit/Runtime/PipiPermissionGuardrail.swift',
  // Wave 2
  'packages/core/src/personal-wiki.ts',
  'packages/core/src/bot-memory.ts',
  'packages/core/src/proactive-engine.ts',
  'apps/apple/Sources/PipiBotKit/Runtime/PipiPersonalWikiStore.swift',
  'apps/apple/Sources/PipiBotKit/Runtime/PipiBotMemoryEngine.swift',
  'apps/apple/Sources/PipiBotKit/Runtime/PipiProactiveEngine.swift',
  'apps/apple/Sources/PipiBotKit/Runtime/PipiMacNativeSignalCollector.swift',
  'apps/apple/Sources/PipiBotMacApp/PipiKnowledgeHubView.swift',
  // Wave 3
  'packages/core/src/alter-ego.ts',
  'packages/core/src/team-protocol.ts',
  'packages/core/src/builtin-skills.ts',
  'packages/core/src/pocket-notes.ts',
  'packages/core/src/pipibot-cli.ts',
  'apps/apple/Sources/PipiBotKit/Runtime/PipiAlterEgoCoordinator.swift',
  'apps/apple/Sources/PipiBotKit/Runtime/PipiTeamProtocol.swift',
  'apps/apple/Sources/PipiBotKit/Runtime/PipiBuiltinSkillsRegistry.swift',
  'apps/apple/Sources/PipiBotKit/Runtime/PipiPocketNotesEngine.swift',
  'apps/apple/Sources/PipiBotMacApp/PipiAlterEgoBarView.swift',
  // Wave 4
  'packages/core/src/model-autopilot.ts',
  'packages/core/src/local-llm-gateway.ts',
  'packages/core/src/voice-engine.ts',
  'apps/apple/Sources/PipiBotKit/Runtime/PipiModelAutopilot.swift',
  'apps/apple/Sources/PipiBotKit/Runtime/PipiLocalLLMGateway.swift',
  'apps/apple/Sources/PipiBotKit/Runtime/PipiDailyVoiceEngine.swift',
  'apps/apple/Sources/PipiBotMacApp/PipiMuseVoiceBarView.swift',
  // Wave 5
  'packages/core/src/computer-use.ts',
  'apps/apple/Sources/PipiBotKit/Runtime/PipiComputerUseEngine.swift',
  'apps/apple/Sources/PipiBotMacApp/PipiComputerUseBarView.swift',
];

let attributedCount = 0;
for (const rel of ATTRIBUTION_FILES) {
  const full = resolve(repoRoot, rel);
  if (!existsSync(full)) {
    fail(`Missing Wave 1-5 source file: ${rel}`);
    continue;
  }
  const head = readFileSync(full, 'utf8').slice(0, 1200);
  if (!head.includes('simplexai-labs/linger') || !head.includes('Clean-room MIT')) {
    fail(`${rel} is missing its clean-room MIT & upstream attribution header.`);
  } else {
    attributedCount += 1;
  }
}

if (!process.exitCode) {
  pass(`Verified clean-room MIT attribution headers on ${attributedCount}/${ATTRIBUTION_FILES.length} Wave 1–5 modules.`);
  console.log('\nALL PROTOCOL PARITY & ATTRIBUTION CHECKS PASSED.');
}
