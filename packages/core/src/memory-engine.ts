/**
 * @pipibot/core - memory-engine.ts
 *
 * 4-Tier Cognitive Memory (`PipiMemoryEngine`) & Self-Evolution Loop (`PipiEvolutionLoop`):
 * - L0 Working & Sensory Memory (active turn, Manus Cue window/app context, fleet telemetry)
 * - L1 Episodic Memory (append-only journal, FTS5 + sqlite-vec RRF SQL builders + zero-dep local store)
 * - L2 Semantic Persona & Bi-Temporal Knowledge Graph (`SOUL.md`, `USER.md`, `MEMORY.md`)
 * - L3 Procedural Memory & Auto-Synthesized Pi Skills (`skills/*.md` & TS hook stubs)
 * - 4D Salience Scoring (Recency * Importance * Relevance * Confidence) + MMR deduplication
 * - Micro-Reflection + Nightly Dreaming Consolidation + Evolution Diff & Understanding Score
 *
 * Runtime dependencies: strictly Node built-ins (`node:*`) only.
 */

import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';

import type {
  CueSuggestion,
  EvolutionDiffItem,
  EvolutionSummary,
  FleetNodeTelemetry,
  HarnessProvider,
  MemoryDomain,
  MemoryEntry,
  MemorySourceKind,
  MemoryTrustLevel,
  SalienceBreakdown,
  SynthesizedSkillCandidate,
  UnderstandingScoreBreakdown,
  UserPersonaFact,
} from '@pipibot/protocol';

// ---------------------------------------------------------------------------
// 1. Constants & Scoring Parameters (Aligned with 04-MEMORY-AND-SELF-EVOLUTION.md)
// ---------------------------------------------------------------------------

export const DOMAIN_DECAY_RATES_PER_HOUR: Record<MemoryDomain, number> = {
  coding_convention: 0.0005,
  communication_pref: 0.0008,
  infra_topology: 0.0012,
  work_context: 0.004,
  daily_life: 0.008,
};

export const RRF_SMOOTHING_K = 60;
export const RRF_WEIGHT_FTS = 1.15;
export const RRF_WEIGHT_VEC = 1.0;
export const IMPLICIT_CONFIDENCE_CAP = 0.62;
export const ACTIVE_PROMOTION_CONFIDENCE_THRESHOLD = 0.78;
export const DEFAULT_EMBEDDING_DIM = 384;

// ---------------------------------------------------------------------------
// 2. Privacy & Secret Scrubbing Filter
// ---------------------------------------------------------------------------

export interface RedactionResult {
  sanitized: string;
  redactedCount: number;
  categories: string[];
}

const SECRET_PATTERNS: ReadonlyArray<{ category: string; regex: RegExp }> = [
  { category: 'PEM_PRIVATE_KEY', regex: /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----/g },
  { category: 'OPENAI_OR_SK_KEY', regex: /\bsk-(?:proj-|ant-|live-|test-)?[A-Za-z0-9_-]{20,}\b/g },
  { category: 'GITHUB_TOKEN', regex: /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\b|\bgithub_pat_[A-Za-z0-9_]{22,}\b/g },
  { category: 'AWS_ACCESS_KEY', regex: /\bAKIA[0-9A-Z]{16}\b/g },
  { category: 'JWT_TOKEN', regex: /\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/g },
  { category: 'BEARER_SECRET', regex: /\bBearer\s+[A-Za-z0-9._~+/=-]{24,}\b/gi },
];

export function scrubSensitiveContent(input: string): RedactionResult {
  let sanitized = input;
  let redactedCount = 0;
  const categories = new Set<string>();

  for (const { category, regex } of SECRET_PATTERNS) {
    sanitized = sanitized.replace(regex, (match) => {
      redactedCount += 1;
      categories.add(category);
      const shortHash = createHash('sha256').update(match).digest('hex').slice(0, 8);
      return `[REDACTED:${category}:${shortHash}]`;
    });
  }

  return {
    sanitized,
    redactedCount,
    categories: Array.from(categories),
  };
}

// ---------------------------------------------------------------------------
// 3. Zero-Dependency Deterministic Vectorization & Lexical Scoring + SQL Builders
// ---------------------------------------------------------------------------

export type EmbeddingProvider = (text: string) => Promise<number[]> | number[];

/**
 * Deterministic 384-dim feature-hashed trigram+word embedding for offline usage
 * when no CoreML / Ollama / BYOK embedding endpoint is attached.
 */
export function computeLocalEmbedding384(text: string, dim = DEFAULT_EMBEDDING_DIM): number[] {
  const vec = new Float64Array(dim);
  const normalized = text.toLowerCase().trim();
  if (!normalized) return Array.from(vec);

  const tokens = normalized.split(/[\s,.;:!?/\\()[\]{}"'`]+/).filter(Boolean);
  const features: string[] = [...tokens];

  // Character trigrams support CJK and subword code identifiers simultaneously
  const compact = normalized.replace(/\s+/g, ' ');
  for (let i = 0; i <= compact.length - 3; i += 1) {
    features.push(compact.slice(i, i + 3));
  }

  for (const feat of features) {
    const digest = createHash('sha256').update(feat).digest();
    const bucket = digest.readUInt16BE(0) % dim;
    const sign = ((digest[2] ?? 0) & 1) === 0 ? 1 : -1;
    vec[bucket] = (vec[bucket] ?? 0) + sign;
  }

  let norm = 0;
  for (let i = 0; i < dim; i += 1) {
    const val = vec[i] ?? 0;
    norm += val * val;
  }
  norm = Math.sqrt(norm);
  if (norm > 0) {
    for (let i = 0; i < dim; i += 1) {
      vec[i] = (vec[i] ?? 0) / norm;
    }
  }
  return Array.from(vec);
}

export function cosineSimilarity(a: readonly number[], b: readonly number[]): number {
  const len = Math.min(a.length, b.length);
  if (len === 0) return 0;
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < len; i += 1) {
    const av = a[i] ?? 0;
    const bv = b[i] ?? 0;
    dot += av * bv;
    normA += av * av;
    normB += bv * bv;
  }
  const denom = Math.sqrt(normA) * Math.sqrt(normB);
  return denom > 0 ? dot / denom : 0;
}

export function tokenizeForLexicalMatch(text: string): string[] {
  const lower = text.toLowerCase();
  const asciiTokens = lower.match(/[a-z0-9_-]{2,}/g) ?? [];
  const cjkChars = lower.match(/[\u4e00-\u9fff]/g) ?? [];
  const cjkBigrams: string[] = [];
  for (let i = 0; i < cjkChars.length - 1; i += 1) {
    const first = cjkChars[i];
    const second = cjkChars[i + 1];
    if (first && second) cjkBigrams.push(first + second);
  }
  return [...asciiTokens, ...cjkChars, ...cjkBigrams];
}

/**
 * Generates exact SQLite + FTS5 + sqlite-vec (`vec0`) DDL matching doc 04.
 */
export function buildEpisodicSchemaSql(embeddingDim = DEFAULT_EMBEDDING_DIM): string {
  return `
CREATE TABLE IF NOT EXISTS episodic_events (
  id                TEXT PRIMARY KEY,
  seq               INTEGER NOT NULL,
  tier              TEXT NOT NULL DEFAULT 'L1_EPISODIC',
  domain            TEXT NOT NULL,
  source_kind       TEXT NOT NULL,
  session_id        TEXT,
  harness_provider  TEXT,
  node_id           TEXT,
  title             TEXT NOT NULL,
  content           TEXT NOT NULL,
  tool_signature    TEXT,
  outcome_success   INTEGER,
  importance_base   REAL NOT NULL DEFAULT 0.5,
  confidence        REAL NOT NULL DEFAULT 0.85,
  explicit_signal   INTEGER NOT NULL DEFAULT 0,
  trust_level       TEXT NOT NULL DEFAULT 'user_verified',
  redacted_count    INTEGER NOT NULL DEFAULT 0,
  access_count      INTEGER NOT NULL DEFAULT 0,
  last_accessed_at  INTEGER,
  created_at        INTEGER NOT NULL,
  consolidated_at   INTEGER,
  metadata_json     TEXT NOT NULL DEFAULT '{}'
);

CREATE VIRTUAL TABLE IF NOT EXISTS fts_episodic USING fts5(
  title,
  content,
  tool_signature,
  content='episodic_events',
  content_rowid='seq',
  tokenize='trigram'
);

CREATE VIRTUAL TABLE IF NOT EXISTS vec_episodic USING vec0(
  event_seq INTEGER PRIMARY KEY,
  embedding float[${embeddingDim}] distance_metric=cosine
);`.trim();
}

/**
 * Generates production Reciprocal Rank Fusion (RRF) query uniting FTS5 + sqlite-vec.
 */
export function buildHybridRrfSql(kRrf = RRF_SMOOTHING_K, topKPerBranch = 24): string {
  return `
WITH vec_matches AS (
  SELECT event_seq AS seq, row_number() OVER (ORDER BY distance ASC) AS vec_rank, (1.0 - distance) AS cosine_sim
  FROM vec_episodic
  WHERE embedding MATCH :query_embedding AND k = ${topKPerBranch}
),
fts_matches AS (
  SELECT rowid AS seq, row_number() OVER (ORDER BY rank ASC) AS fts_rank
  FROM fts_episodic
  WHERE fts_episodic MATCH :fts_query
  LIMIT ${topKPerBranch}
),
fused AS (
  SELECT
    COALESCE(f.seq, v.seq) AS seq,
    v.vec_rank,
    f.fts_rank,
    COALESCE(v.cosine_sim, 0.0) AS cosine_sim,
    (COALESCE(${RRF_WEIGHT_FTS} / (${kRrf}.0 + f.fts_rank), 0.0) + COALESCE(${RRF_WEIGHT_VEC} / (${kRrf}.0 + v.vec_rank), 0.0)) AS rrf_score
  FROM fts_matches f
  FULL OUTER JOIN vec_matches v ON v.seq = f.seq
)
SELECT e.*, fused.vec_rank, fused.fts_rank, fused.cosine_sim, fused.rrf_score
FROM fused
JOIN episodic_events e ON e.seq = fused.seq
WHERE e.trust_level != 'untrusted_external' OR :include_untrusted = 1
ORDER BY fused.rrf_score DESC
LIMIT 40;`.trim();
}

// ---------------------------------------------------------------------------
// 4. Storage Persistence Snapshot (Zero-Dep Atomic JSON + Markdown Files)
// ---------------------------------------------------------------------------

interface PersistedMemoryDatabase {
  version: 1;
  nextSeq: number;
  episodicEvents: MemoryEntry[];
  personaFacts: UserPersonaFact[];
  synthesizedSkills: SynthesizedSkillCandidate[];
  revertedCooldowns: Record<string, number>;
  lastEvolutionSummary?: EvolutionSummary;
}

async function atomicWrite(filePath: string, content: string): Promise<void> {
  await mkdir(dirname(filePath), { recursive: true });
  const tmpPath = `${filePath}.tmp.${process.pid}.${randomBytes(6).toString('hex')}`;
  await writeFile(tmpPath, content, 'utf8');
  await rename(tmpPath, filePath);
}

function clamp(val: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, val));
}

function generateId(prefix: string): string {
  return `${prefix}_${Date.now().toString(36)}_${randomUUID().slice(0, 8)}`;
}

// ---------------------------------------------------------------------------
// 5. PipiMemoryEngine (L0 Working -> L1 Episodic -> L2 Semantic -> L3 Skills)
// ---------------------------------------------------------------------------

export interface L0WorkingTurnEntry {
  role: 'user' | 'assistant' | 'tool';
  summary: string;
  timestamp: number;
}

export interface L0WorkingSnapshot {
  recentTurns: L0WorkingTurnEntry[];
  activeCue?: CueSuggestion;
  fleetNodes: FleetNodeTelemetry[];
}

export interface AppendEpisodicInput {
  domain: MemoryDomain;
  sourceKind: MemorySourceKind;
  title: string;
  content: string;
  sessionId?: string;
  harnessProvider?: HarnessProvider;
  nodeId?: string;
  toolSignature?: string;
  outcomeSuccess?: boolean;
  importanceBase?: number;
  confidence?: number;
  explicitSignal?: boolean;
  trustLevel?: MemoryTrustLevel;
  metadata?: Record<string, unknown>;
}

export interface RecallQueryOptions {
  query: string;
  domain?: MemoryDomain;
  limit?: number;
  tokenBudget?: number;
  includeUntrusted?: boolean;
  nowMs?: number;
  cueContext?: CueSuggestion;
}

export interface RecallResult {
  episodic: MemoryEntry[];
  facts: UserPersonaFact[];
  skills: SynthesizedSkillCandidate[];
  l0Snapshot: L0WorkingSnapshot;
  promptContextBlock: string;
  estimatedTokens: number;
}

export interface FactUpsertResult {
  action: 'reinforced' | 'inserted_active' | 'inserted_candidate' | 'superseded' | 'skipped_cooldown' | 'blocked_untrusted';
  fact: UserPersonaFact;
  supersededFactId?: string;
}

export class PipiMemoryEngine {
  readonly rootDir: string;
  private readonly dbFilePath: string;
  private readonly embedder: EmbeddingProvider;

  private db: PersistedMemoryDatabase = {
    version: 1,
    nextSeq: 1,
    episodicEvents: [],
    personaFacts: [],
    synthesizedSkills: [],
    revertedCooldowns: {},
  };

  private loaded = false;
  private readonly l0Turns: L0WorkingTurnEntry[] = [];
  private l0Cue?: CueSuggestion;
  private readonly l0Fleet = new Map<string, FleetNodeTelemetry>();

  constructor(options: { rootDir?: string; embedder?: EmbeddingProvider } = {}) {
    this.rootDir = options.rootDir ?? join(homedir(), '.pipibot');
    this.dbFilePath = join(this.rootDir, 'memory', 'pipibot-memory-store.json');
    this.embedder = options.embedder ?? computeLocalEmbedding384;
  }

  async init(): Promise<void> {
    if (this.loaded) return;
    try {
      const raw = await readFile(this.dbFilePath, 'utf8');
      const parsed = JSON.parse(raw) as PersistedMemoryDatabase;
      if (parsed && parsed.version === 1) {
        this.db = parsed;
      }
    } catch {
      await this.flush();
    }
    this.loaded = true;
  }

  private async flush(): Promise<void> {
    await atomicWrite(this.dbFilePath, JSON.stringify(this.db, null, 2));
  }

  // ---- L0 Working & Sensory Memory ----

  pushWorkingTurn(entry: L0WorkingTurnEntry, maxEntries = 12): void {
    const clean = scrubSensitiveContent(entry.summary).sanitized;
    this.l0Turns.push({ ...entry, summary: clean });
    while (this.l0Turns.length > maxEntries) {
      this.l0Turns.shift();
    }
  }

  updateCueContext(cue: CueSuggestion): void {
    this.l0Cue = cue;
  }

  updateFleetTelemetry(telemetry: FleetNodeTelemetry): void {
    this.l0Fleet.set(telemetry.nodeId, telemetry);
  }

  getL0Snapshot(): L0WorkingSnapshot {
    return {
      recentTurns: [...this.l0Turns],
      activeCue: this.l0Cue,
      fleetNodes: Array.from(this.l0Fleet.values()),
    };
  }

  // ---- L1 Episodic Memory ----

  async appendEpisodic(input: AppendEpisodicInput): Promise<MemoryEntry> {
    await this.init();
    const titleClean = scrubSensitiveContent(input.title);
    const bodyClean = scrubSensitiveContent(input.content);
    const embedding = await this.embedder(`${titleClean.sanitized}\n${bodyClean.sanitized}`);

    const entry: MemoryEntry = {
      id: generateId('evt'),
      seq: this.db.nextSeq,
      tier: 'L1_EPISODIC',
      domain: input.domain,
      sourceKind: input.sourceKind,
      sessionId: input.sessionId,
      harnessProvider: input.harnessProvider,
      nodeId: input.nodeId,
      title: titleClean.sanitized,
      content: bodyClean.sanitized,
      toolSignature: input.toolSignature,
      outcomeSuccess: input.outcomeSuccess,
      importanceBase: clamp(input.importanceBase ?? 0.5, 0.1, 1.0),
      confidence: clamp(input.confidence ?? (input.explicitSignal ? 0.92 : 0.75), 0.1, 1.0),
      explicitSignal: Boolean(input.explicitSignal),
      trustLevel: input.trustLevel ?? 'user_verified',
      redactedCount: titleClean.redactedCount + bodyClean.redactedCount,
      accessCount: 0,
      createdAt: Date.now(),
      embedding,
      metadata: input.metadata,
    };

    this.db.nextSeq += 1;
    this.db.episodicEvents.push(entry);
    await this.flush();
    return entry;
  }

  // ---- Hybrid Retrieval (RRF + 4D Salience Scoring + MMR) ----

  async recall(options: RecallQueryOptions): Promise<RecallResult> {
    await this.init();
    const nowMs = options.nowMs ?? Date.now();
    const limit = options.limit ?? 8;
    const tokenBudget = options.tokenBudget ?? 3200;
    const activeCue = options.cueContext ?? this.l0Cue;

    const queryEmbedding = await this.embedder(options.query);
    const queryTokens = new Set(tokenizeForLexicalMatch(options.query));

    const pool = this.db.episodicEvents.filter((evt) => {
      if (!options.includeUntrusted && evt.trustLevel === 'untrusted_external') return false;
      if (options.domain && evt.domain !== options.domain) return false;
      return true;
    });

    // Compute lexical & vector ranks separately for RRF
    const scoredVectors = pool
      .map((evt) => ({
        evt,
        cos: evt.embedding ? cosineSimilarity(queryEmbedding, evt.embedding) : 0,
      }))
      .sort((a, b) => b.cos - a.cos);

    const scoredLexical = pool
      .map((evt) => {
        const docTokens = tokenizeForLexicalMatch(`${evt.title} ${evt.content} ${evt.toolSignature ?? ''}`);
        let overlap = 0;
        for (const t of docTokens) {
          if (queryTokens.has(t)) overlap += 1;
        }
        const score = docTokens.length > 0 ? overlap / Math.sqrt(docTokens.length) : 0;
        return { evt, lex: score };
      })
      .sort((a, b) => b.lex - a.lex);

    const vecRankMap = new Map<string, { rank: number; cos: number }>();
    scoredVectors.slice(0, 24).forEach((item, idx) => {
      vecRankMap.set(item.evt.id, { rank: idx + 1, cos: item.cos });
    });

    const ftsRankMap = new Map<string, { rank: number; lex: number }>();
    scoredLexical.slice(0, 24).forEach((item, idx) => {
      if (item.lex > 0) {
        ftsRankMap.set(item.evt.id, { rank: idx + 1, lex: item.lex });
      }
    });

    const candidateIds = new Set<string>([...vecRankMap.keys(), ...ftsRankMap.keys()]);
    const rrfRaw = new Map<string, number>();
    let maxRrf = 0;

    for (const id of candidateIds) {
      const v = vecRankMap.get(id);
      const f = ftsRankMap.get(id);
      const score =
        (v ? RRF_WEIGHT_VEC / (RRF_SMOOTHING_K + v.rank) : 0) +
        (f ? RRF_WEIGHT_FTS / (RRF_SMOOTHING_K + f.rank) : 0);
      rrfRaw.set(id, score);
      if (score > maxRrf) maxRrf = score;
    }

    const rankedWithSalience: MemoryEntry[] = [];
    for (const evt of pool) {
      if (!candidateIds.has(evt.id)) continue;
      const rrfScore = rrfRaw.get(evt.id) ?? 0;
      const normRrf = maxRrf > 0 ? rrfScore / maxRrf : 0;
      const cosSim = Math.max(0, vecRankMap.get(evt.id)?.cos ?? 0);
      const salience = this.computeSalienceScore(evt, {
        nowMs,
        normalizedRrf: normRrf,
        cosineSim: cosSim,
        rrfScore,
        cueContext: activeCue,
      });
      rankedWithSalience.push({ ...evt, salience });
    }

    rankedWithSalience.sort((a, b) => (b.salience?.finalSalience ?? 0) - (a.salience?.finalSalience ?? 0));

    // MMR diversification (lambda = 0.75)
    const selectedEpisodic = this.selectWithMmr(rankedWithSalience, limit, 0.75);

    // Reinforce Ebbinghaus access counter for recalled items
    const selectedIds = new Set(selectedEpisodic.map((e) => e.id));
    if (selectedIds.size > 0) {
      for (const evt of this.db.episodicEvents) {
        if (selectedIds.has(evt.id)) {
          evt.accessCount += 1;
          evt.lastAccessedAt = nowMs;
        }
      }
      await this.flush();
    }

    // Retrieve active L2 Persona Facts ranked by domain relevance & confidence
    const activeFacts = this.db.personaFacts
      .filter((f) => f.status === 'active' && (!options.domain || f.domain === options.domain))
      .sort((a, b) => b.confidence * b.importance - a.confidence * a.importance)
      .slice(0, 14);

    // Retrieve matching L3 Pi Skills
    const activeSkills = this.db.synthesizedSkills
      .filter((s) => s.status === 'active')
      .filter((s) => {
        if (queryTokens.size === 0) return true;
        const skillTokens = tokenizeForLexicalMatch(`${s.name} ${s.description}`);
        return skillTokens.some((t) => queryTokens.has(t));
      })
      .slice(0, 4);

    const l0Snapshot = this.getL0Snapshot();
    const promptContextBlock = this.assemblePromptContextBlock({
      l0Snapshot,
      facts: activeFacts,
      episodic: selectedEpisodic,
      skills: activeSkills,
      tokenBudget,
    });

    return {
      episodic: selectedEpisodic,
      facts: activeFacts,
      skills: activeSkills,
      l0Snapshot,
      promptContextBlock,
      estimatedTokens: Math.ceil(promptContextBlock.length / 4),
    };
  }

  computeSalienceScore(
    entry: MemoryEntry,
    ctx: {
      nowMs: number;
      normalizedRrf: number;
      cosineSim: number;
      rrfScore: number;
      cueContext?: CueSuggestion;
    },
  ): SalienceBreakdown {
    const lambda = DOMAIN_DECAY_RATES_PER_HOUR[entry.domain];
    const refTime = Math.max(entry.createdAt, entry.lastAccessedAt ?? 0);
    const deltaHours = Math.max(0, (ctx.nowMs - refTime) / 3_600_000);
    const spacedReinforcement = 1 + 0.45 * Math.log(1 + entry.accessCount);
    const recency = clamp(Math.exp((-lambda * deltaHours) / spacedReinforcement), 0.05, 1.0);

    const outcomeImpact = entry.sourceKind === 'outcome_result' ? 1.5 : entry.sourceKind === 'cue_feedback' ? 1.0 : 0.3;
    const importance = clamp(
      0.55 * entry.importanceBase +
        0.3 * (entry.explicitSignal ? 1 : 0) +
        0.15 * Math.min(1, Math.log2(1 + outcomeImpact) / 3),
      0.1,
      1.0,
    );

    let cueAffinity = 0;
    if (ctx.cueContext) {
      const appLower = `${ctx.cueContext.activeAppName} ${ctx.cueContext.workspacePath ?? ''}`.toLowerCase();
      if (
        (appLower.includes('code') || appLower.includes('xcode') || appLower.includes('terminal')) &&
        entry.domain === 'coding_convention'
      ) {
        cueAffinity = 1.0;
      } else if (
        ctx.cueContext.workspacePath &&
        entry.content.toLowerCase().includes(ctx.cueContext.workspacePath.toLowerCase())
      ) {
        cueAffinity = 1.0;
      }
    }

    const relevance = clamp(
      0.55 * ctx.normalizedRrf + 0.3 * ctx.cosineSim + 0.15 * cueAffinity,
      0.05,
      1.0,
    );

    const confidence = clamp(entry.confidence, 0.1, 1.0);
    const finalSalience = recency * importance * relevance * confidence;

    return {
      recency,
      importance,
      relevance,
      confidence,
      rrfScore: ctx.rrfScore,
      finalSalience,
    };
  }

  private selectWithMmr(candidates: MemoryEntry[], limit: number, lambdaMmr: number): MemoryEntry[] {
    if (candidates.length <= limit) return candidates;
    const remaining = [...candidates];
    const selected: MemoryEntry[] = [];

    while (selected.length < limit && remaining.length > 0) {
      let bestIdx = 0;
      let bestMmr = -Infinity;

      for (let i = 0; i < remaining.length; i += 1) {
        const cand = remaining[i];
        if (!cand) continue;
        const sal = cand.salience?.finalSalience ?? 0;
        let maxSim = 0;
        if (cand.embedding && selected.length > 0) {
          for (const chosen of selected) {
            if (chosen.embedding) {
              maxSim = Math.max(maxSim, cosineSimilarity(cand.embedding, chosen.embedding));
            }
          }
        }
        const mmr = lambdaMmr * sal - (1 - lambdaMmr) * maxSim;
        if (mmr > bestMmr) {
          bestMmr = mmr;
          bestIdx = i;
        }
      }

      const picked = remaining.splice(bestIdx, 1)[0];
      if (picked) selected.push(picked);
    }
    return selected;
  }

  private assemblePromptContextBlock(params: {
    l0Snapshot: L0WorkingSnapshot;
    facts: UserPersonaFact[];
    episodic: MemoryEntry[];
    skills: SynthesizedSkillCandidate[];
    tokenBudget: number;
  }): string {
    const budgetChars = params.tokenBudget * 4;
    const l0Budget = Math.floor(budgetChars * 0.35);
    const l2Budget = Math.floor(budgetChars * 0.25);
    const l1Budget = Math.floor(budgetChars * 0.25);
    const l3Budget = Math.floor(budgetChars * 0.15);

    const truncate = (str: string, maxChars: number): string =>
      str.length <= maxChars ? str : `${str.slice(0, Math.max(0, maxChars - 16))}\n...[truncated]`;

    const l0Lines: string[] = [];
    if (params.l0Snapshot.activeCue) {
      const cue = params.l0Snapshot.activeCue;
      l0Lines.push(
        `- Active App: ${cue.activeAppName} (${cue.windowTitle})${cue.workspacePath ? ` | Repo: ${cue.workspacePath}` : ''}${cue.gitBranch ? ` [${cue.gitBranch}]` : ''}`,
      );
    }
    for (const node of params.l0Snapshot.fleetNodes) {
      l0Lines.push(`- Node ${node.displayName} (${node.kind}): ${node.vitality}, cpu=${node.cpuLoadPct}%`);
    }
    for (const turn of params.l0Snapshot.recentTurns.slice(-4)) {
      l0Lines.push(`- [${turn.role}] ${turn.summary}`);
    }

    const l2Lines = params.facts.map(
      (f) => `- [${f.domain}|${f.scope}|conf=${f.confidence.toFixed(2)}] ${f.subject} ${f.predicate}: ${f.objectValue}`,
    );
    const l1Lines = params.episodic.map(
      (e) => `- (${e.domain}, sal=${(e.salience?.finalSalience ?? 0).toFixed(2)}) ${e.title}: ${e.content}`,
    );
    const l3Lines = params.skills.map((s) => `- Skill \`${s.slug}\`: ${s.description}`);

    return [
      '<pipibot_cognitive_memory>',
      `<l0_working>\n${truncate(l0Lines.join('\n') || 'None', l0Budget)}\n</l0_working>`,
      `<l2_user_persona>\n${truncate(l2Lines.join('\n') || 'None', l2Budget)}\n</l2_user_persona>`,
      `<l1_episodic_recall>\n${truncate(l1Lines.join('\n') || 'None', l1Budget)}\n</l1_episodic_recall>`,
      `<l3_procedural_skills>\n${truncate(l3Lines.join('\n') || 'None', l3Budget)}\n</l3_procedural_skills>`,
      '</pipibot_cognitive_memory>',
    ].join('\n');
  }

  // ---- L2 Semantic Bi-Temporal Facts & Superseding ----

  async upsertPersonaFact(input: {
    subject: string;
    predicate: string;
    objectValue: string;
    domain: MemoryDomain;
    scope?: string;
    confidence: number;
    importance: number;
    evidenceEventIds: string[];
    explicitSignal?: boolean;
    trustLevel?: MemoryTrustLevel;
  }): Promise<FactUpsertResult> {
    await this.init();
    const now = Date.now();
    const scope = input.scope ?? 'global';
    const cooldownKey = `${input.subject}::${input.predicate}::${input.objectValue}::${scope}`;

    if (input.trustLevel === 'untrusted_external') {
      const blocked: UserPersonaFact = {
        id: generateId('fact'),
        subject: input.subject,
        predicate: input.predicate,
        objectValue: input.objectValue,
        domain: input.domain,
        scope,
        status: 'reverted',
        confidence: 0,
        importance: input.importance,
        evidenceCount: 0,
        evidenceEventIds: [],
        validFrom: now,
        createdAt: now,
        updatedAt: now,
      };
      return { action: 'blocked_untrusted', fact: blocked };
    }

    const cooldownUntil = this.db.revertedCooldowns[cooldownKey];
    if (cooldownUntil && cooldownUntil > now && !input.explicitSignal) {
      const skipped: UserPersonaFact = {
        id: generateId('fact'),
        subject: input.subject,
        predicate: input.predicate,
        objectValue: input.objectValue,
        domain: input.domain,
        scope,
        status: 'reverted',
        confidence: 0.1,
        importance: input.importance,
        evidenceCount: input.evidenceEventIds.length,
        evidenceEventIds: input.evidenceEventIds,
        validFrom: now,
        createdAt: now,
        updatedAt: now,
      };
      return { action: 'skipped_cooldown', fact: skipped };
    }

    const sanitizedValue = scrubSensitiveContent(input.objectValue).sanitized;
    const effectiveConfidence = input.explicitSignal
      ? clamp(input.confidence, 0.85, 1.0)
      : clamp(input.confidence, 0.1, IMPLICIT_CONFIDENCE_CAP);

    const existingSameSlot = this.db.personaFacts.find(
      (f) =>
        f.status === 'active' &&
        f.subject === input.subject &&
        f.predicate === input.predicate &&
        f.scope === scope,
    );

    if (existingSameSlot && existingSameSlot.objectValue === sanitizedValue) {
      const mergedIds = Array.from(new Set([...existingSameSlot.evidenceEventIds, ...input.evidenceEventIds]));
      existingSameSlot.evidenceEventIds = mergedIds;
      existingSameSlot.evidenceCount = mergedIds.length;
      existingSameSlot.confidence = clamp(1 - (1 - existingSameSlot.confidence) * (1 - 0.35), 0.1, 1.0);
      existingSameSlot.importance = Math.max(existingSameSlot.importance, input.importance);
      existingSameSlot.updatedAt = now;
      await this.flush();
      return { action: 'reinforced', fact: existingSameSlot };
    }

    if (existingSameSlot && existingSameSlot.objectValue !== sanitizedValue) {
      // Conflict resolution: supersede if explicit or >= existing confidence; otherwise hold as candidate
      const shouldSupersede = input.explicitSignal || effectiveConfidence >= existingSameSlot.confidence;
      if (shouldSupersede) {
        const newFact: UserPersonaFact = {
          id: generateId('fact'),
          subject: input.subject,
          predicate: input.predicate,
          objectValue: sanitizedValue,
          domain: input.domain,
          scope,
          status: effectiveConfidence >= ACTIVE_PROMOTION_CONFIDENCE_THRESHOLD ? 'active' : 'candidate',
          confidence: effectiveConfidence,
          importance: clamp(input.importance, 0.1, 1.0),
          evidenceCount: input.evidenceEventIds.length,
          evidenceEventIds: input.evidenceEventIds,
          validFrom: now,
          createdAt: now,
          updatedAt: now,
        };
        existingSameSlot.status = 'superseded';
        existingSameSlot.validTo = now;
        existingSameSlot.supersededBy = newFact.id;
        existingSameSlot.updatedAt = now;
        this.db.personaFacts.push(newFact);
        await this.flush();
        return { action: 'superseded', fact: newFact, supersededFactId: existingSameSlot.id };
      }

      const candidateFact: UserPersonaFact = {
        id: generateId('fact'),
        subject: input.subject,
        predicate: input.predicate,
        objectValue: sanitizedValue,
        domain: input.domain,
        scope,
        status: 'candidate',
        confidence: effectiveConfidence,
        importance: clamp(input.importance, 0.1, 1.0),
        evidenceCount: input.evidenceEventIds.length,
        evidenceEventIds: input.evidenceEventIds,
        validFrom: now,
        createdAt: now,
        updatedAt: now,
      };
      this.db.personaFacts.push(candidateFact);
      await this.flush();
      return { action: 'inserted_candidate', fact: candidateFact };
    }

    const newFact: UserPersonaFact = {
      id: generateId('fact'),
      subject: input.subject,
      predicate: input.predicate,
      objectValue: sanitizedValue,
      domain: input.domain,
      scope,
      status: effectiveConfidence >= ACTIVE_PROMOTION_CONFIDENCE_THRESHOLD ? 'active' : 'candidate',
      confidence: effectiveConfidence,
      importance: clamp(input.importance, 0.1, 1.0),
      evidenceCount: input.evidenceEventIds.length,
      evidenceEventIds: input.evidenceEventIds,
      validFrom: now,
      createdAt: now,
      updatedAt: now,
    };
    this.db.personaFacts.push(newFact);
    await this.flush();
    return {
      action: newFact.status === 'active' ? 'inserted_active' : 'inserted_candidate',
      fact: newFact,
    };
  }

  getPersonaFacts(status?: UserPersonaFact['status']): UserPersonaFact[] {
    return status ? this.db.personaFacts.filter((f) => f.status === status) : [...this.db.personaFacts];
  }

  getEpisodicEvents(): MemoryEntry[] {
    return [...this.db.episodicEvents];
  }

  getSynthesizedSkills(): SynthesizedSkillCandidate[] {
    return [...this.db.synthesizedSkills];
  }

  // ---- Markdown Synchronization (`USER.md`, `SOUL.md`, `MEMORY.md`) ----

  async syncPersonaMarkdownFiles(): Promise<{ userMdPath: string; soulMdPath: string; memoryMdPath: string }> {
    await this.init();
    const personaDir = join(this.rootDir, 'persona');
    const userMdPath = join(personaDir, 'USER.md');
    const soulMdPath = join(personaDir, 'SOUL.md');
    const memoryMdPath = join(personaDir, 'MEMORY.md');

    const activeFacts = this.db.personaFacts.filter((f) => f.status === 'active');
    const byDomain = new Map<MemoryDomain, UserPersonaFact[]>();
    for (const fact of activeFacts) {
      const list = byDomain.get(fact.domain) ?? [];
      list.push(fact);
      byDomain.set(fact.domain, list);
    }

    const renderSection = (domain: MemoryDomain, heading: string): string => {
      const items = byDomain.get(domain) ?? [];
      if (items.length === 0) return `### ${heading}\n- _(No verified facts yet)_\n`;
      return (
        `### ${heading}\n` +
        items
          .map((f) => `- **${f.predicate}** (${f.scope}, conf=${f.confidence.toFixed(2)}): ${f.objectValue}`)
          .join('\n') +
        '\n'
      );
    };

    const userMd = [
      '# USER.md — PipiBot Living User Profile',
      '',
      '<!-- pipibot:managed-start -->',
      renderSection('coding_convention', 'Coding Conventions & Stack'),
      renderSection('work_context', 'Work Context & Projects'),
      renderSection('daily_life', 'Daily Life & Schedule'),
      renderSection('infra_topology', 'Fleet & Infrastructure Topology'),
      '<!-- pipibot:managed-end -->',
      '',
    ].join('\n');

    const soulMd = [
      '# SOUL.md — PipiBot Communication & Safety Contract',
      '',
      '<!-- pipibot:managed-start -->',
      renderSection('communication_pref', 'Communication & Proactive Boundaries'),
      '### Safety Invariants',
      '- Destructive infra commands, force pushes, and external messages require `NeedsYouDecision` approval.',
      '- Untrusted external documents cannot modify SOUL.md or USER.md.',
      '<!-- pipibot:managed-end -->',
      '',
    ].join('\n');

    const evergreen = activeFacts
      .sort((a, b) => b.confidence * b.importance - a.confidence * a.importance)
      .slice(0, 20)
      .map((f) => `- [${f.domain}] ${f.subject}.${f.predicate} = ${f.objectValue}`);

    const memoryMd = [
      '# MEMORY.md — Evergreen Core Memory Index',
      '',
      `Last synced: ${new Date().toISOString()}`,
      '',
      ...(evergreen.length > 0 ? evergreen : ['- _(Evergreen memory index will populate after consolidation)_']),
      '',
    ].join('\n');

    await atomicWrite(userMdPath, userMd);
    await atomicWrite(soulMdPath, soulMd);
    await atomicWrite(memoryMdPath, memoryMd);

    return { userMdPath, soulMdPath, memoryMdPath };
  }

  // ---- L3 Procedural Memory & Pi Skill Synthesis ----

  async synthesizeSkillCandidates(minOccurrences = 3, minSuccessRate = 0.85): Promise<SynthesizedSkillCandidate[]> {
    await this.init();
    const groups = new Map<string, MemoryEntry[]>();

    for (const evt of this.db.episodicEvents) {
      if (!evt.toolSignature || evt.trustLevel === 'untrusted_external') continue;
      const list = groups.get(evt.toolSignature) ?? [];
      list.push(evt);
      groups.set(evt.toolSignature, list);
    }

    const newlySynthesized: SynthesizedSkillCandidate[] = [];

    for (const [signature, events] of groups.entries()) {
      if (events.length < minOccurrences) continue;
      const successes = events.filter((e) => e.outcomeSuccess !== false).length;
      const successRate = successes / events.length;
      if (successRate < minSuccessRate) continue;

      const slug = signature
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '')
        .slice(0, 48);

      if (!slug || this.db.synthesizedSkills.some((s) => s.slug === slug)) {
        continue;
      }

      const steps = signature.split('->').map((s) => s.trim()).filter(Boolean);
      const primaryDomain = events[0]?.domain ?? 'work_context';

      const skillMarkdown = [
        '---',
        `name: ${slug}`,
        `description: Auto-synthesized workflow from ${events.length} successful executions (${(successRate * 100).toFixed(0)}% success).`,
        'status: candidate',
        '---',
        '',
        `# ${slug}`,
        '',
        '## Repeated Successful Tool Sequence',
        ...steps.map((step, i) => `${i + 1}. Execute \`${step}\``),
        '',
        '## Evidence Event IDs',
        ...events.slice(0, 6).map((e) => `- \`${e.id}\`: ${e.title}`),
        '',
      ].join('\n');

      const extensionHookTs = [
        `// Auto-synthesized Pi extension guard for ${slug}`,
        `export const skillSlug = '${slug}';`,
        `export function shouldActivate(promptText: string): boolean {`,
        `  return promptText.toLowerCase().includes('${steps[0]?.split(':')[0] ?? slug}');`,
        `}`,
        '',
      ].join('\n');

      const candidate: SynthesizedSkillCandidate = {
        slug,
        name: slug,
        description: `Synthesized from ${events.length} successful trajectories (${signature})`,
        domain: primaryDomain,
        toolSequence: steps,
        occurrences: events.length,
        successRate,
        skillMarkdown,
        extensionHookTs,
        status: 'candidate',
      };

      this.db.synthesizedSkills.push(candidate);
      newlySynthesized.push(candidate);
    }

    if (newlySynthesized.length > 0) {
      await this.flush();
    }
    return newlySynthesized;
  }

  async materializeSkillFiles(skill: SynthesizedSkillCandidate): Promise<{ skillPath: string; hookPath?: string }> {
    const skillPath = join(this.rootDir, 'skills', skill.slug, 'SKILL.md');
    await atomicWrite(skillPath, skill.skillMarkdown);

    let hookPath: string | undefined;
    if (skill.extensionHookTs) {
      hookPath = join(this.rootDir, 'extensions', `${skill.slug}.ts`);
      await atomicWrite(hookPath, skill.extensionHookTs);
    }
    return { skillPath, hookPath };
  }

  // ---- Internal Helpers for EvolutionLoop ----

  async markEpisodicConsolidated(eventIds: string[], nowMs = Date.now()): Promise<void> {
    const idSet = new Set(eventIds);
    for (const evt of this.db.episodicEvents) {
      if (idSet.has(evt.id)) {
        evt.consolidatedAt = nowMs;
      }
    }
    await this.flush();
  }

  async saveEvolutionSummary(summary: EvolutionSummary): Promise<void> {
    this.db.lastEvolutionSummary = summary;
    await this.flush();
  }

  getLastEvolutionSummary(): EvolutionSummary | undefined {
    return this.db.lastEvolutionSummary;
  }

  async applyFactReviewDecision(
    factId: string,
    action: 'approve' | 'edit' | 'revert',
    editedValue?: string,
  ): Promise<UserPersonaFact | null> {
    await this.init();
    const fact = this.db.personaFacts.find((f) => f.id === factId);
    if (!fact) return null;

    const now = Date.now();
    if (action === 'approve') {
      fact.status = 'active';
      fact.confidence = Math.max(fact.confidence, ACTIVE_PROMOTION_CONFIDENCE_THRESHOLD);
      fact.updatedAt = now;
    } else if (action === 'edit') {
      fact.objectValue = scrubSensitiveContent(editedValue ?? fact.objectValue).sanitized;
      fact.status = 'active';
      fact.confidence = 1.0;
      fact.updatedAt = now;
    } else if (action === 'revert') {
      fact.status = 'reverted';
      fact.updatedAt = now;
      const cooldownKey = `${fact.subject}::${fact.predicate}::${fact.objectValue}::${fact.scope}`;
      this.db.revertedCooldowns[cooldownKey] = now + 14 * 24 * 3600 * 1000;

      // Restore any fact that this reverted fact had superseded
      const previouslySuperseded = this.db.personaFacts.find((f) => f.supersededBy === fact.id);
      if (previouslySuperseded) {
        previouslySuperseded.status = 'active';
        previouslySuperseded.validTo = undefined;
        previouslySuperseded.supersededBy = undefined;
        previouslySuperseded.updatedAt = now;
      }
    }

    await this.flush();
    await this.syncPersonaMarkdownFiles();
    return fact;
  }

  async applySkillReviewDecision(slug: string, action: 'approve' | 'revert'): Promise<SynthesizedSkillCandidate | null> {
    await this.init();
    const skill = this.db.synthesizedSkills.find((s) => s.slug === slug);
    if (!skill) return null;
    skill.status = action === 'approve' ? 'active' : 'reverted';
    await this.flush();
    if (action === 'approve') {
      await this.materializeSkillFiles(skill);
    }
    return skill;
  }
}

// ---------------------------------------------------------------------------
// 6. PipiEvolutionLoop (Micro-Reflection + Nightly Dreaming + Understanding Score)
// ---------------------------------------------------------------------------

export interface MicroReflectionInput {
  sessionId: string;
  userPrompt: string;
  assistantResponse: string;
  harnessProvider: HarnessProvider;
  nodeId?: string;
  domainHint?: MemoryDomain;
  toolSequence?: string[];
  outcomeSuccess?: boolean;
  cueFeedback?: { cueId: string; actionLabel: string; feedback: 'accepted' | 'dismissed' };
}

export interface MicroReflectionOutput {
  appendedEventId: string;
  explicitPreferenceDetected: boolean;
  extractedCandidateFact?: UserPersonaFact;
}

const EXPLICIT_PREF_TRIGGERS = [
  /(?:以后|永远|记住|请不要|别再|我习惯|我更喜欢|不要用|请使用)/i,
  /\b(?:always use|never use|remember that|i prefer|please stop|don't use)\b/i,
];

export class PipiEvolutionLoop {
  private readonly memory: PipiMemoryEngine;

  constructor(memory: PipiMemoryEngine) {
    this.memory = memory;
  }

  /**
   * Stage A: Lightweight Turn-Level Micro-Reflection (runs asynchronously after turn response).
   */
  async runMicroReflection(input: MicroReflectionInput): Promise<MicroReflectionOutput> {
    const explicitPreferenceDetected = EXPLICIT_PREF_TRIGGERS.some((re) => re.test(input.userPrompt));
    const domain = input.domainHint ?? this.inferDomain(input.userPrompt, input.toolSequence);
    const toolSignature = input.toolSequence && input.toolSequence.length > 0 ? input.toolSequence.join('->') : undefined;

    this.memory.pushWorkingTurn({
      role: 'user',
      summary: input.userPrompt.slice(0, 220),
      timestamp: Date.now(),
    });
    this.memory.pushWorkingTurn({
      role: 'assistant',
      summary: input.assistantResponse.slice(0, 220),
      timestamp: Date.now(),
    });

    const event = await this.memory.appendEpisodic({
      domain,
      sourceKind: input.cueFeedback ? 'cue_feedback' : toolSignature ? 'tool_trace' : 'conversation_turn',
      sessionId: input.sessionId,
      harnessProvider: input.harnessProvider,
      nodeId: input.nodeId,
      title: input.userPrompt.trim().slice(0, 96) || 'Interaction turn',
      content: `User: ${input.userPrompt.trim()}\nAssistant: ${input.assistantResponse.trim().slice(0, 600)}`,
      toolSignature,
      outcomeSuccess: input.outcomeSuccess,
      importanceBase: explicitPreferenceDetected ? 0.92 : toolSignature ? 0.65 : 0.45,
      confidence: explicitPreferenceDetected ? 0.9 : 0.6,
      explicitSignal: explicitPreferenceDetected,
      trustLevel: 'user_verified',
      metadata: input.cueFeedback ? { cueFeedback: input.cueFeedback } : undefined,
    });

    let extractedCandidateFact: UserPersonaFact | undefined;
    if (explicitPreferenceDetected) {
      const upserted = await this.memory.upsertPersonaFact({
        subject: 'user',
        predicate: domain === 'communication_pref' ? 'communication_guideline' : 'explicit_preference',
        objectValue: input.userPrompt.trim().slice(0, 240),
        domain,
        scope: 'global',
        confidence: 0.9,
        importance: 0.9,
        evidenceEventIds: [event.id],
        explicitSignal: true,
        trustLevel: 'user_verified',
      });
      extractedCandidateFact = upserted.fact;
    }

    return {
      appendedEventId: event.id,
      explicitPreferenceDetected,
      extractedCandidateFact,
    };
  }

  /**
   * Stage B: Nightly Dreaming Consolidation Cycle.
   */
  async runNightlyDreamingCycle(options: {
    cycle?: EvolutionSummary['cycle'];
    windowHours?: number;
    nowMs?: number;
  } = {}): Promise<EvolutionSummary> {
    await this.memory.init();
    const nowMs = options.nowMs ?? Date.now();
    const windowMs = (options.windowHours ?? 24) * 3_600_000;
    const windowStartMs = nowMs - windowMs;

    const previousScore = this.memory.getLastEvolutionSummary()?.understandingScore.overall ?? 50;
    const allEvents = this.memory.getEpisodicEvents();
    const unconsolidated = allEvents.filter(
      (e) => !e.consolidatedAt && e.createdAt >= windowStartMs && e.trustLevel !== 'untrusted_external',
    );

    const diffs: EvolutionDiffItem[] = [];

    // 1. Consolidate candidate facts and recurring domain clusters
    const candidateFacts = this.memory.getPersonaFacts('candidate');
    for (const fact of candidateFacts) {
      diffs.push({
        diffId: generateId('diff'),
        operation: fact.supersededBy ? 'supersede' : 'add',
        targetFile: fact.domain === 'communication_pref' ? 'SOUL.md' : 'USER.md',
        domain: fact.domain,
        title: `Verify learned preference: ${fact.subject}.${fact.predicate}`,
        factId: fact.id,
        proposedValue: fact.objectValue,
        confidence: fact.confidence,
        evidenceEventIds: fact.evidenceEventIds,
        evidenceSummary: `Extracted from ${fact.evidenceCount} episodic event(s).`,
        reviewStatus: 'pending',
      });
    }

    // 2. Synthesize L3 Pi Skills from recurring successful tool trajectories
    const newSkills = await this.memory.synthesizeSkillCandidates(3, 0.85);
    for (const skill of newSkills) {
      diffs.push({
        diffId: generateId('diff'),
        operation: 'add_skill',
        targetFile: `skills/${skill.slug}/SKILL.md`,
        domain: skill.domain,
        title: `Auto-synthesized Pi Skill: ${skill.slug}`,
        skillSlug: skill.slug,
        proposedValue: skill.description,
        confidence: skill.successRate,
        evidenceEventIds: [],
        evidenceSummary: `Observed ${skill.occurrences} times with ${(skill.successRate * 100).toFixed(0)}% success rate.`,
        reviewStatus: 'pending',
      });
    }

    // 3. Mark processed episodic items and sync Markdown files
    if (unconsolidated.length > 0) {
      await this.memory.markEpisodicConsolidated(
        unconsolidated.map((e) => e.id),
        nowMs,
      );
    }
    await this.memory.syncPersonaMarkdownFiles();

    const understandingScore = this.computeUnderstandingScore(previousScore);

    const summary: EvolutionSummary = {
      digestId: generateId('evo'),
      cycle: options.cycle ?? 'nightly_dreaming',
      generatedAt: new Date(nowMs).toISOString(),
      windowStart: new Date(windowStartMs).toISOString(),
      windowEnd: new Date(nowMs).toISOString(),
      episodicEventsProcessed: unconsolidated.length,
      understandingScore,
      diffs,
      candidateSkills: newSkills,
      requiresUserReviewCount: diffs.filter((d) => d.reviewStatus === 'pending').length,
    };

    await this.memory.saveEvolutionSummary(summary);
    return summary;
  }

  async applyEvolutionDecision(
    summary: EvolutionSummary,
    diffId: string,
    action: 'approve' | 'edit' | 'revert',
    editedValue?: string,
  ): Promise<EvolutionSummary> {
    const diff = summary.diffs.find((d) => d.diffId === diffId);
    if (!diff) return summary;

    if (diff.factId) {
      await this.memory.applyFactReviewDecision(diff.factId, action, editedValue);
    } else if (diff.skillSlug && action !== 'edit') {
      await this.memory.applySkillReviewDecision(diff.skillSlug, action);
    }

    diff.reviewStatus = action === 'approve' ? 'approved' : action === 'edit' ? 'edited' : 'reverted';
    if (action === 'edit' && editedValue) {
      diff.proposedValue = editedValue;
    }

    const updated: EvolutionSummary = {
      ...summary,
      requiresUserReviewCount: summary.diffs.filter((d) => d.reviewStatus === 'pending').length,
    };
    await this.memory.saveEvolutionSummary(updated);
    return updated;
  }

  computeUnderstandingScore(previousOverall: number): UnderstandingScoreBreakdown {
    const activeFacts = this.memory.getPersonaFacts('active');
    const revertedFacts = this.memory.getPersonaFacts('reverted');
    const allEvents = this.memory.getEpisodicEvents();

    const domains: MemoryDomain[] = [
      'coding_convention',
      'communication_pref',
      'daily_life',
      'work_context',
      'infra_topology',
    ];

    const breakdown = {} as Record<MemoryDomain, number>;
    let coveredDomains = 0;

    for (const d of domains) {
      const domainFacts = activeFacts.filter((f) => f.domain === d);
      if (domainFacts.length > 0) coveredDomains += 1;
      const avgConf =
        domainFacts.length > 0
          ? domainFacts.reduce((acc, f) => acc + f.confidence, 0) / domainFacts.length
          : 0.45;
      const domainDensity = Math.min(1, domainFacts.length / 4);
      breakdown[d] = Number((100 * (0.55 * avgConf + 0.45 * domainDensity)).toFixed(1));
    }

    const coverage = clamp(coveredDomains / domains.length + Math.min(0.25, activeFacts.length / 40), 0, 1);

    const cueEvents = allEvents.filter((e) => e.sourceKind === 'cue_feedback');
    const acceptedCues = cueEvents.filter((e) => {
      const fb = (e.metadata?.cueFeedback as { feedback?: string } | undefined)?.feedback;
      return fb === 'accepted';
    }).length;
    const cueAcceptanceRate = cueEvents.length > 0 ? acceptedCues / cueEvents.length : 0.72;

    const accessedEvents = allEvents.filter((e) => e.accessCount > 0).length;
    const memoryRetention = allEvents.length > 0 ? clamp(accessedEvents / Math.min(allEvents.length, 20) + 0.35, 0.35, 1) : 0.65;

    const totalDecidedFacts = activeFacts.length + revertedFacts.length;
    const correctionRate = totalDecidedFacts > 0 ? revertedFacts.length / totalDecidedFacts : 0.05;

    const overall = Number(
      clamp(
        100 *
          (0.3 * coverage + 0.25 * cueAcceptanceRate + 0.25 * memoryRetention + 0.2 * (1 - correctionRate)),
        0,
        100,
      ).toFixed(1),
    );

    return {
      overall,
      deltaFromPrevious: Number((overall - previousOverall).toFixed(1)),
      breakdown,
      metrics: {
        coverage: Number(coverage.toFixed(3)),
        cueAcceptanceRate: Number(cueAcceptanceRate.toFixed(3)),
        memoryRetention: Number(memoryRetention.toFixed(3)),
        correctionRate: Number(correctionRate.toFixed(3)),
      },
    };
  }

  private inferDomain(prompt: string, toolSequence?: string[]): MemoryDomain {
    const joined = `${prompt} ${(toolSequence ?? []).join(' ')}`.toLowerCase();
    if (/(nginx|docker|vps|cloudflare|tunnel|ssh|systemd|d1|r2|mqtt|raspberry|esp32)/.test(joined)) {
      return 'infra_topology';
    }
    if (/(typescript|bun|pnpm|git|eslint|vitest|swift|xcode|refactor|bash|edit|write)/.test(joined)) {
      return 'coding_convention';
    }
    if (/(语气|简短|不要废话|format|reply|concise|tone|bullet)/.test(joined)) {
      return 'communication_pref';
    }
    if (/(健身|咖啡|晚安|提醒|买|超市|睡觉|起床|dinner|gym|sleep|flight|grocery)/.test(joined)) {
      return 'daily_life';
    }
    return 'work_context';
  }
}
