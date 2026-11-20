/**
 * @pipibot/core - personal-wiki.ts
 *
 * Wave 2 (#01): Personal Entity Wiki + Dual-Channel Zero-Embedding Search + SQLite WAL.
 * - Personal-oriented taxonomy: `people`, `projects`, `topics`, `life`, `repos` (no CRM/business bias)
 * - Native SQLite WAL (`node:sqlite` DatabaseSync) with automatic FTS5 detection and
 *   SQLite-backed BM25 postings fallback when the Node binary omits ENABLE_FTS5
 * - CJK bigram + ASCII tokenization, up to 6 alternate wordings, independent Chunks & Facts channels,
 *   soft time-window RRF boost, optional cosine vector boost (disabled by default: 0 embedding calls)
 * - Atomic Markdown projection with YAML frontmatter & secret scrubbing
 *
 * PiPiBot — Clean-room MIT implementation.
 * Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
 * Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.
 */

import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { mkdir, rename, rm, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

import type { WikiEntityCategory, WikiSearchScope } from '@pipibot/protocol';
import { cosineSimilarity, scrubSensitiveContent } from './memory-engine.ts';

// ---------------------------------------------------------------------------
// 1. Public Models & Constants
// ---------------------------------------------------------------------------

export const MAX_WIKI_ALTERNATES = 6;
export const WIKI_RRF_K = 60;
export const WIKI_SOFT_WINDOW_BONUS_WEIGHT = 0.85;

export interface PersonalWikiPageInput {
  id?: string;
  slug?: string;
  category: WikiEntityCategory;
  title: string;
  aliases?: string[];
  summary: string;
  bodyMarkdown: string;
  tags?: string[];
  sourceRefs?: string[];
  eventDate?: string; // YYYY-MM-DD
  status?: 'draft' | 'stable' | 'deprecated';
  facts?: Array<{
    factText: string;
    entities?: string[];
    eventDate?: string;
    confidence?: number;
  }>;
  optionalEmbedding?: number[];
}

export interface PersonalWikiPage {
  id: string;
  slug: string;
  category: WikiEntityCategory;
  title: string;
  aliases: string[];
  summary: string;
  bodyMarkdown: string;
  tags: string[];
  sourceRefs: string[];
  eventDate?: string;
  status: 'draft' | 'stable' | 'deprecated';
  contentHash: string;
  createdAt: string;
  updatedAt: string;
}

export interface PersonalWikiChunkHit {
  chunkId: string;
  pageId: string;
  category: WikiEntityCategory;
  title: string;
  sectionHeading: string;
  content: string;
  eventDate?: string;
  inTimeWindow: boolean;
  score: number;
  matchedTerms: string[];
}

export interface PersonalWikiFactHit {
  factId: string;
  pageId: string;
  chunkId?: string;
  category: WikiEntityCategory;
  pageTitle: string;
  factText: string;
  entities: string[];
  eventDate?: string;
  confidence: number;
  inTimeWindow: boolean;
  score: number;
}

export interface PersonalWikiSummaryHit {
  pageId: string;
  slug: string;
  category: WikiEntityCategory;
  title: string;
  aliases: string[];
  summary: string;
  eventDate?: string;
  score: number;
  matchedAlias?: string;
}

export interface PersonalWikiSearchOptions {
  query: string;
  alternates?: string[];
  startDate?: string; // YYYY-MM-DD (soft time window start)
  endDate?: string; // YYYY-MM-DD (soft time window end)
  category?: WikiEntityCategory;
  scope?: WikiSearchScope;
  limit?: number;
  factLimit?: number;
  optionalQueryEmbedding?: number[];
}

export interface PersonalWikiSearchResult {
  query: string;
  effectiveQueries: string[];
  scope: WikiSearchScope;
  usedFts5: boolean;
  usedVectorChannel: boolean;
  chunks: PersonalWikiChunkHit[];
  facts: PersonalWikiFactHit[];
  summaries: PersonalWikiSummaryHit[];
}

// ---------------------------------------------------------------------------
// 2. Tokenization & CJK Bigram Expansion (Zero-Embedding Lexical Core)
// ---------------------------------------------------------------------------

const CJK_RUN_RE = /[\u3400-\u4dbf\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]+/gu;
const ASCII_TOKEN_RE = /[a-z0-9][a-z0-9_.-]{1,}/g;

export function expandTokensWithCjkBigrams(input: string): string[] {
  const lower = input.toLowerCase();
  const tokens: string[] = [];

  const asciiMatches = lower.match(ASCII_TOKEN_RE) ?? [];
  for (const tok of asciiMatches) {
    tokens.push(tok);
  }

  const cjkRuns = lower.match(CJK_RUN_RE) ?? [];
  for (const run of cjkRuns) {
    const chars = Array.from(run);
    if (chars.length === 1) {
      if (chars[0]) tokens.push(chars[0]);
      continue;
    }
    for (let i = 0; i < chars.length - 1; i += 1) {
      const a = chars[i];
      const b = chars[i + 1];
      if (a && b) tokens.push(a + b);
    }
    if (chars.length <= 4) {
      tokens.push(run);
    }
  }

  return tokens;
}

export function buildFtsTokenString(input: string): string {
  return expandTokensWithCjkBigrams(input).join(' ');
}

function slugifyTitle(title: string, fallbackId: string): string {
  const cleaned = title
    .toLowerCase()
    .trim()
    .replace(/[^\p{L}\p{N}\s_-]+/gu, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 64);
  return cleaned || fallbackId;
}

function sha256Hex(text: string): string {
  return createHash('sha256').update(text).digest('hex');
}

function splitMarkdownIntoChunks(bodyMarkdown: string, maxChars = 900): Array<{ heading: string; content: string }> {
  const lines = bodyMarkdown.replace(/\r\n/g, '\n').split('\n');
  const sections: Array<{ heading: string; content: string }> = [];
  let currentHeading = 'Overview';
  let buffer: string[] = [];

  const flush = (): void => {
    const raw = buffer.join('\n').trim();
    buffer = [];
    if (!raw) return;
    if (raw.length <= maxChars) {
      sections.push({ heading: currentHeading, content: raw });
      return;
    }
    // Split oversized section on paragraph boundaries
    const paragraphs = raw.split(/\n{2,}/);
    let acc = '';
    for (const para of paragraphs) {
      if (acc && acc.length + para.length + 2 > maxChars) {
        sections.push({ heading: currentHeading, content: acc.trim() });
        acc = para;
      } else {
        acc = acc ? `${acc}\n\n${para}` : para;
      }
    }
    if (acc.trim()) {
      sections.push({ heading: currentHeading, content: acc.trim() });
    }
  };

  for (const line of lines) {
    const headingMatch = line.match(/^#{1,3}\s+(.+)$/);
    if (headingMatch?.[1]) {
      flush();
      currentHeading = headingMatch[1].trim();
    } else {
      buffer.push(line);
    }
  }
  flush();

  if (sections.length === 0 && bodyMarkdown.trim()) {
    sections.push({ heading: 'Overview', content: bodyMarkdown.trim() });
  }
  return sections;
}

function isDateWithinWindow(eventDate: string | undefined, startDate?: string, endDate?: string): boolean {
  if (!eventDate || (!startDate && !endDate)) return false;
  if (startDate && eventDate < startDate) return false;
  if (endDate && eventDate > endDate) return false;
  return true;
}

async function atomicWriteFile(filePath: string, content: string): Promise<void> {
  await mkdir(dirname(filePath), { recursive: true });
  const tmpPath = `${filePath}.tmp.${process.pid}.${randomBytes(6).toString('hex')}`;
  await writeFile(tmpPath, content, 'utf8');
  await rename(tmpPath, filePath);
}

// ---------------------------------------------------------------------------
// 3. PipiPersonalWikiStore (SQLite WAL + FTS5 / Postings BM25 + Markdown)
// ---------------------------------------------------------------------------

export interface PersonalWikiStoreOptions {
  dbPath: string; // file path or ':memory:'
  markdownRootDir?: string;
}

export class PipiPersonalWikiStore {
  readonly dbPath: string;
  readonly markdownRootDir?: string;
  readonly supportsFts5: boolean;
  private readonly db: DatabaseSync;

  constructor(options: PersonalWikiStoreOptions) {
    this.dbPath = options.dbPath;
    this.markdownRootDir = options.markdownRootDir;
    this.db = new DatabaseSync(options.dbPath);
    if (options.dbPath !== ':memory:') {
      this.db.exec('PRAGMA journal_mode = WAL;');
    }
    this.db.exec('PRAGMA synchronous = NORMAL;');
    this.db.exec('PRAGMA busy_timeout = 5000;');
    this.db.exec('PRAGMA foreign_keys = ON;');

    this.initCoreSchema();
    this.supportsFts5 = this.initSearchIndexes();
  }

  close(): void {
    this.db.close();
  }

  getJournalMode(): string {
    const row = this.db.prepare('PRAGMA journal_mode;').get() as Record<string, unknown> | undefined;
    const firstVal = row ? Object.values(row)[0] : undefined;
    return typeof firstVal === 'string' ? firstVal.toLowerCase() : 'unknown';
  }

  private initCoreSchema(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS wiki_pages (
        id               TEXT PRIMARY KEY,
        slug             TEXT NOT NULL,
        category         TEXT NOT NULL,
        title            TEXT NOT NULL,
        aliases_json     TEXT NOT NULL DEFAULT '[]',
        summary          TEXT NOT NULL,
        body_markdown    TEXT NOT NULL,
        tags_json        TEXT NOT NULL DEFAULT '[]',
        source_refs_json TEXT NOT NULL DEFAULT '[]',
        event_date       TEXT,
        status           TEXT NOT NULL DEFAULT 'stable',
        content_hash     TEXT NOT NULL,
        created_at       TEXT NOT NULL,
        updated_at       TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_wiki_pages_category ON wiki_pages(category);
      CREATE INDEX IF NOT EXISTS idx_wiki_pages_event_date ON wiki_pages(event_date);

      CREATE TABLE IF NOT EXISTS wiki_chunks (
        id               TEXT PRIMARY KEY,
        page_id          TEXT NOT NULL REFERENCES wiki_pages(id) ON DELETE CASCADE,
        section_heading  TEXT NOT NULL,
        content          TEXT NOT NULL,
        token_count      INTEGER NOT NULL DEFAULT 0,
        event_date       TEXT,
        content_hash     TEXT NOT NULL,
        embedding_json   TEXT
      );

      CREATE INDEX IF NOT EXISTS idx_wiki_chunks_page ON wiki_chunks(page_id);
      CREATE INDEX IF NOT EXISTS idx_wiki_chunks_date ON wiki_chunks(event_date);

      CREATE TABLE IF NOT EXISTS wiki_facts (
        id               TEXT PRIMARY KEY,
        page_id          TEXT NOT NULL REFERENCES wiki_pages(id) ON DELETE CASCADE,
        chunk_id         TEXT,
        fact_text        TEXT NOT NULL,
        entities_json    TEXT NOT NULL DEFAULT '[]',
        token_count      INTEGER NOT NULL DEFAULT 0,
        event_date       TEXT,
        confidence       REAL NOT NULL DEFAULT 0.85,
        created_at       TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_wiki_facts_page ON wiki_facts(page_id);
      CREATE INDEX IF NOT EXISTS idx_wiki_facts_date ON wiki_facts(event_date);

      -- Fallback SQLite WAL inverted postings tables for Node builds without ENABLE_FTS5
      CREATE TABLE IF NOT EXISTS wiki_chunk_postings (
        term      TEXT NOT NULL,
        chunk_id  TEXT NOT NULL REFERENCES wiki_chunks(id) ON DELETE CASCADE,
        tf        INTEGER NOT NULL,
        in_title  INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (term, chunk_id)
      );
      CREATE INDEX IF NOT EXISTS idx_chunk_postings_term ON wiki_chunk_postings(term);

      CREATE TABLE IF NOT EXISTS wiki_fact_postings (
        term     TEXT NOT NULL,
        fact_id  TEXT NOT NULL REFERENCES wiki_facts(id) ON DELETE CASCADE,
        tf       INTEGER NOT NULL,
        PRIMARY KEY (term, fact_id)
      );
      CREATE INDEX IF NOT EXISTS idx_fact_postings_term ON wiki_fact_postings(term);
    `);
  }

  private initSearchIndexes(): boolean {
    try {
      this.db.exec(`
        CREATE VIRTUAL TABLE IF NOT EXISTS fts_wiki_chunks USING fts5(
          chunk_id UNINDEXED,
          page_id UNINDEXED,
          title_tokens,
          body_tokens,
          tokenize='unicode61'
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS fts_wiki_facts USING fts5(
          fact_id UNINDEXED,
          page_id UNINDEXED,
          fact_tokens,
          tokenize='unicode61'
        );
      `);
      return true;
    } catch {
      return false;
    }
  }

  // ---- Write / Upsert / Projection ----

  async upsertPage(input: PersonalWikiPageInput): Promise<PersonalWikiPage> {
    const nowIso = new Date().toISOString();
    const id = input.id?.trim() || `wiki_${Date.now().toString(36)}_${randomUUID().slice(0, 8)}`;
    const cleanTitle = scrubSensitiveContent(input.title.trim()).sanitized;
    const cleanSummary = scrubSensitiveContent(input.summary.trim()).sanitized;
    const cleanBody = scrubSensitiveContent(input.bodyMarkdown.trim()).sanitized;
    const aliases = (input.aliases ?? []).map((a) => scrubSensitiveContent(a.trim()).sanitized).filter(Boolean);
    const tags = (input.tags ?? []).map((t) => t.trim()).filter(Boolean);
    const sourceRefs = (input.sourceRefs ?? []).map((r) => r.trim()).filter(Boolean);
    const slug = input.slug?.trim() || slugifyTitle(cleanTitle, id);
    const status = input.status ?? 'stable';
    const contentHash = sha256Hex(
      JSON.stringify({ category: input.category, title: cleanTitle, aliases, summary: cleanSummary, body: cleanBody, eventDate: input.eventDate ?? null }),
    );

    const existing = this.db.prepare('SELECT created_at FROM wiki_pages WHERE id = ?').get(id) as
      | { created_at: string }
      | undefined;
    const createdAt = existing?.created_at ?? nowIso;

    this.db.exec('BEGIN IMMEDIATE');
    try {
      // Remove previous index entries for this page
      this.deleteIndexRowsForPage(id);
      this.db.prepare('DELETE FROM wiki_chunks WHERE page_id = ?').run(id);
      this.db.prepare('DELETE FROM wiki_facts WHERE page_id = ?').run(id);

      this.db
        .prepare(
          `INSERT INTO wiki_pages (
            id, slug, category, title, aliases_json, summary, body_markdown,
            tags_json, source_refs_json, event_date, status, content_hash, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            slug = excluded.slug,
            category = excluded.category,
            title = excluded.title,
            aliases_json = excluded.aliases_json,
            summary = excluded.summary,
            body_markdown = excluded.body_markdown,
            tags_json = excluded.tags_json,
            source_refs_json = excluded.source_refs_json,
            event_date = excluded.event_date,
            status = excluded.status,
            content_hash = excluded.content_hash,
            updated_at = excluded.updated_at`,
        )
        .run(
          id,
          slug,
          input.category,
          cleanTitle,
          JSON.stringify(aliases),
          cleanSummary,
          cleanBody,
          JSON.stringify(tags),
          JSON.stringify(sourceRefs),
          input.eventDate ?? null,
          status,
          contentHash,
          createdAt,
          nowIso,
        );

      const sections = splitMarkdownIntoChunks(cleanBody || cleanSummary);
      const titleHeaderText = [cleanTitle, ...aliases, ...tags].join(' ');
      const titleTokens = expandTokensWithCjkBigrams(titleHeaderText);
      const titleTokenSet = new Set(titleTokens);
      const embeddingJson = input.optionalEmbedding ? JSON.stringify(input.optionalEmbedding) : null;

      let firstChunkId: string | undefined;
      const insertChunk = this.db.prepare(
        `INSERT INTO wiki_chunks (id, page_id, section_heading, content, token_count, event_date, content_hash, embedding_json)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      );
      const insertChunkPosting = this.db.prepare(
        `INSERT INTO wiki_chunk_postings (term, chunk_id, tf, in_title) VALUES (?, ?, ?, ?)`,
      );
      const insertFtsChunk = this.supportsFts5
        ? this.db.prepare(
            `INSERT INTO fts_wiki_chunks (chunk_id, page_id, title_tokens, body_tokens) VALUES (?, ?, ?, ?)`,
          )
        : null;

      for (let i = 0; i < sections.length; i += 1) {
        const sec = sections[i];
        if (!sec) continue;
        const chunkId = `${id}_c${i}`;
        if (!firstChunkId) firstChunkId = chunkId;
        const bodyText = `${sec.heading}\n${sec.content}`;
        const bodyTokens = expandTokensWithCjkBigrams(`${cleanSummary} ${bodyText}`);
        const combinedTokens = [...titleTokens, ...bodyTokens];

        insertChunk.run(
          chunkId,
          id,
          sec.heading,
          sec.content,
          Math.max(1, combinedTokens.length),
          input.eventDate ?? null,
          sha256Hex(bodyText),
          embeddingJson,
        );

        if (insertFtsChunk) {
          insertFtsChunk.run(chunkId, id, titleTokens.join(' '), bodyTokens.join(' '));
        } else {
          const tfMap = new Map<string, number>();
          for (const t of combinedTokens) {
            tfMap.set(t, (tfMap.get(t) ?? 0) + 1);
          }
          for (const [term, tf] of tfMap.entries()) {
            insertChunkPosting.run(term, chunkId, tf, titleTokenSet.has(term) ? 1 : 0);
          }
        }
      }

      // Insert explicit facts + auto-derive a baseline summary fact if none given
      const factsToStore =
        input.facts && input.facts.length > 0
          ? input.facts
          : cleanSummary
            ? [{ factText: `${cleanTitle}: ${cleanSummary}`, entities: [cleanTitle, ...aliases], eventDate: input.eventDate, confidence: 0.85 }]
            : [];

      const insertFact = this.db.prepare(
        `INSERT INTO wiki_facts (id, page_id, chunk_id, fact_text, entities_json, token_count, event_date, confidence, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      );
      const insertFactPosting = this.db.prepare(
        `INSERT INTO wiki_fact_postings (term, fact_id, tf) VALUES (?, ?, ?)`,
      );
      const insertFtsFact = this.supportsFts5
        ? this.db.prepare(`INSERT INTO fts_wiki_facts (fact_id, page_id, fact_tokens) VALUES (?, ?, ?)`)
        : null;

      for (let i = 0; i < factsToStore.length; i += 1) {
        const f = factsToStore[i];
        if (!f) continue;
        const cleanFact = scrubSensitiveContent(f.factText.trim()).sanitized;
        if (!cleanFact) continue;
        const factId = `${id}_f${i}`;
        const entities = (f.entities ?? [cleanTitle]).map((e) => e.trim()).filter(Boolean);
        const factTokens = expandTokensWithCjkBigrams(`${cleanFact} ${entities.join(' ')}`);
        insertFact.run(
          factId,
          id,
          firstChunkId ?? null,
          cleanFact,
          JSON.stringify(entities),
          Math.max(1, factTokens.length),
          f.eventDate ?? input.eventDate ?? null,
          Math.min(1, Math.max(0.1, f.confidence ?? 0.85)),
          nowIso,
        );
        if (insertFtsFact) {
          insertFtsFact.run(factId, id, factTokens.join(' '));
        } else {
          const tfMap = new Map<string, number>();
          for (const t of factTokens) {
            tfMap.set(t, (tfMap.get(t) ?? 0) + 1);
          }
          for (const [term, tf] of tfMap.entries()) {
            insertFactPosting.run(term, factId, tf);
          }
        }
      }

      this.db.exec('COMMIT');
    } catch (err) {
      this.db.exec('ROLLBACK');
      throw err;
    }

    const page: PersonalWikiPage = {
      id,
      slug,
      category: input.category,
      title: cleanTitle,
      aliases,
      summary: cleanSummary,
      bodyMarkdown: cleanBody,
      tags,
      sourceRefs,
      eventDate: input.eventDate,
      status,
      contentHash,
      createdAt,
      updatedAt: nowIso,
    };

    if (this.markdownRootDir) {
      await this.projectPageMarkdown(page);
    }
    return page;
  }

  private deleteIndexRowsForPage(pageId: string): void {
    if (this.supportsFts5) {
      this.db.prepare('DELETE FROM fts_wiki_chunks WHERE page_id = ?').run(pageId);
      this.db.prepare('DELETE FROM fts_wiki_facts WHERE page_id = ?').run(pageId);
    }
  }

  async deletePage(id: string): Promise<boolean> {
    const existing = this.getPage(id);
    if (!existing) return false;
    this.db.exec('BEGIN IMMEDIATE');
    try {
      this.deleteIndexRowsForPage(id);
      this.db.prepare('DELETE FROM wiki_pages WHERE id = ?').run(id);
      this.db.exec('COMMIT');
    } catch (err) {
      this.db.exec('ROLLBACK');
      throw err;
    }
    if (this.markdownRootDir) {
      const mdPath = join(this.markdownRootDir, 'knowledge', existing.category, `${existing.slug}.md`);
      await rm(mdPath, { force: true });
    }
    return true;
  }

  getPage(id: string): PersonalWikiPage | null {
    const row = this.db.prepare('SELECT * FROM wiki_pages WHERE id = ?').get(id) as Record<string, unknown> | undefined;
    return row ? this.mapRowToPage(row) : null;
  }

  listPages(category?: WikiEntityCategory): PersonalWikiPage[] {
    const rows = category
      ? (this.db.prepare('SELECT * FROM wiki_pages WHERE category = ? ORDER BY updated_at DESC').all(category) as Record<
          string,
          unknown
        >[])
      : (this.db.prepare('SELECT * FROM wiki_pages ORDER BY updated_at DESC').all() as Record<string, unknown>[]);
    return rows.map((r) => this.mapRowToPage(r));
  }

  private mapRowToPage(row: Record<string, unknown>): PersonalWikiPage {
    return {
      id: String(row.id),
      slug: String(row.slug),
      category: String(row.category) as WikiEntityCategory,
      title: String(row.title),
      aliases: JSON.parse(String(row.aliases_json ?? '[]')) as string[],
      summary: String(row.summary ?? ''),
      bodyMarkdown: String(row.body_markdown ?? ''),
      tags: JSON.parse(String(row.tags_json ?? '[]')) as string[],
      sourceRefs: JSON.parse(String(row.source_refs_json ?? '[]')) as string[],
      eventDate: row.event_date ? String(row.event_date) : undefined,
      status: (String(row.status ?? 'stable') as PersonalWikiPage['status']),
      contentHash: String(row.content_hash ?? ''),
      createdAt: String(row.created_at ?? ''),
      updatedAt: String(row.updated_at ?? ''),
    };
  }

  renderPageMarkdown(page: PersonalWikiPage): string {
    const yamlQuote = (v: string): string => JSON.stringify(v);
    const fmLines = [
      '---',
      'pipibot_wiki_version: "1.0"',
      `id: ${yamlQuote(page.id)}`,
      `category: ${page.category}`,
      `title: ${yamlQuote(page.title)}`,
      `status: ${page.status}`,
      `updated_at: ${yamlQuote(page.updatedAt)}`,
    ];
    if (page.eventDate) fmLines.push(`event_date: ${yamlQuote(page.eventDate)}`);
    if (page.aliases.length > 0) fmLines.push(`aliases: [${page.aliases.map(yamlQuote).join(', ')}]`);
    if (page.tags.length > 0) fmLines.push(`tags: [${page.tags.map(yamlQuote).join(', ')}]`);
    if (page.sourceRefs.length > 0) fmLines.push(`sources: [${page.sourceRefs.map(yamlQuote).join(', ')}]`);
    fmLines.push('---', '', `# ${page.title}`, '', page.summary, '', page.bodyMarkdown, '');
    return fmLines.join('\n');
  }

  async projectPageMarkdown(page: PersonalWikiPage): Promise<string | null> {
    if (!this.markdownRootDir) return null;
    const filePath = join(this.markdownRootDir, 'knowledge', page.category, `${page.slug}.md`);
    await atomicWriteFile(filePath, this.renderPageMarkdown(page));
    return filePath;
  }

  // ---- Dual-Channel Zero-Embedding Search + Soft Time-Window RRF ----

  search(options: PersonalWikiSearchOptions): PersonalWikiSearchResult {
    const scope: WikiSearchScope = options.scope ?? 'all';
    const limit = Math.max(1, Math.min(30, options.limit ?? 10));
    const factLimit = Math.max(1, Math.min(30, options.factLimit ?? 12));

    const trimmedQuery = options.query.trim();
    const cleanedAlts = (options.alternates ?? [])
      .map((a) => a.trim())
      .filter((a) => a.length > 0 && a.toLowerCase() !== trimmedQuery.toLowerCase())
      .slice(0, MAX_WIKI_ALTERNATES);
    const effectiveQueries = trimmedQuery ? [trimmedQuery, ...cleanedAlts] : cleanedAlts;

    if (effectiveQueries.length === 0) {
      return {
        query: options.query,
        effectiveQueries: [],
        scope,
        usedFts5: this.supportsFts5,
        usedVectorChannel: false,
        chunks: [],
        facts: [],
        summaries: [],
      };
    }

    const hasWindow = Boolean(options.startDate || options.endDate);
    const chunks =
      scope === 'summaries'
        ? []
        : this.searchChunksChannel(effectiveQueries, options, limit, hasWindow);
    const facts =
      scope === 'summaries'
        ? []
        : this.searchFactsChannel(effectiveQueries, options, factLimit, hasWindow);
    const summaries =
      scope === 'originals'
        ? []
        : this.searchSummariesChannel(effectiveQueries, options, limit, hasWindow);

    return {
      query: options.query,
      effectiveQueries,
      scope,
      usedFts5: this.supportsFts5,
      usedVectorChannel: Boolean(options.optionalQueryEmbedding && options.optionalQueryEmbedding.length > 0),
      chunks,
      facts,
      summaries,
    };
  }

  private searchChunksChannel(
    queries: string[],
    options: PersonalWikiSearchOptions,
    limit: number,
    hasWindow: boolean,
  ): PersonalWikiChunkHit[] {
    const rrfScores = new Map<string, number>();
    const matchedTermsByChunk = new Map<string, Set<string>>();

    for (let qIdx = 0; qIdx < queries.length; qIdx += 1) {
      const q = queries[qIdx];
      if (!q) continue;
      const weight = qIdx === 0 ? 1.25 : 0.85;
      const ranked = this.rankChunksLexically(q, options.category);

      ranked.slice(0, 32).forEach((item, rankIdx) => {
        const vote = weight / (WIKI_RRF_K + rankIdx + 1);
        rrfScores.set(item.chunkId, (rrfScores.get(item.chunkId) ?? 0) + vote);
        const set = matchedTermsByChunk.get(item.chunkId) ?? new Set<string>();
        for (const t of item.matchedTerms) set.add(t);
        matchedTermsByChunk.set(item.chunkId, set);
      });

      if (hasWindow) {
        const inWindow = ranked.filter((item) =>
          isDateWithinWindow(item.eventDate, options.startDate, options.endDate),
        );
        inWindow.slice(0, 24).forEach((item, rankIdx) => {
          const bonus = (weight * WIKI_SOFT_WINDOW_BONUS_WEIGHT) / (WIKI_RRF_K + rankIdx + 1);
          rrfScores.set(item.chunkId, (rrfScores.get(item.chunkId) ?? 0) + bonus);
        });
      }
    }

    // Optional vector boost channel (disabled when no query embedding provided — 0 calls by default)
    if (options.optionalQueryEmbedding && options.optionalQueryEmbedding.length > 0) {
      const vecRows = (
        options.category
          ? this.db
              .prepare(
                `SELECT c.id AS chunk_id, c.embedding_json
                 FROM wiki_chunks c JOIN wiki_pages p ON p.id = c.page_id
                 WHERE c.embedding_json IS NOT NULL AND p.category = ?`,
              )
              .all(options.category)
          : this.db.prepare('SELECT id AS chunk_id, embedding_json FROM wiki_chunks WHERE embedding_json IS NOT NULL').all()
      ) as Array<{ chunk_id: string; embedding_json: string }>;

      const scoredVec = vecRows
        .map((r) => {
          const emb = JSON.parse(r.embedding_json) as number[];
          return { chunkId: r.chunk_id, sim: cosineSimilarity(options.optionalQueryEmbedding!, emb) };
        })
        .filter((x) => x.sim > 0.15)
        .sort((a, b) => b.sim - a.sim);

      scoredVec.slice(0, 24).forEach((item, rankIdx) => {
        const vote = 0.9 / (WIKI_RRF_K + rankIdx + 1);
        rrfScores.set(item.chunkId, (rrfScores.get(item.chunkId) ?? 0) + vote);
      });
    }

    if (rrfScores.size === 0) return [];

    const topIds = Array.from(rrfScores.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, limit);

    const fetchChunk = this.db.prepare(
      `SELECT c.id, c.page_id, c.section_heading, c.content, c.event_date, p.category, p.title
       FROM wiki_chunks c JOIN wiki_pages p ON p.id = c.page_id
       WHERE c.id = ?`,
    );

    const hits: PersonalWikiChunkHit[] = [];
    for (const [chunkId, score] of topIds) {
      const row = fetchChunk.get(chunkId) as Record<string, unknown> | undefined;
      if (!row) continue;
      const eventDate = row.event_date ? String(row.event_date) : undefined;
      hits.push({
        chunkId: String(row.id),
        pageId: String(row.page_id),
        category: String(row.category) as WikiEntityCategory,
        title: String(row.title),
        sectionHeading: String(row.section_heading),
        content: String(row.content),
        eventDate,
        inTimeWindow: isDateWithinWindow(eventDate, options.startDate, options.endDate),
        score,
        matchedTerms: Array.from(matchedTermsByChunk.get(chunkId) ?? []),
      });
    }
    return hits;
  }

  private rankChunksLexically(
    query: string,
    category?: WikiEntityCategory,
  ): Array<{ chunkId: string; eventDate?: string; score: number; matchedTerms: string[] }> {
    const terms = Array.from(new Set(expandTokensWithCjkBigrams(query)));
    if (terms.length === 0) return [];

    if (this.supportsFts5) {
      const matchExpr = terms.map((t) => `"${t.replace(/"/g, '""')}"`).join(' OR ');
      const sql = category
        ? `SELECT f.chunk_id, c.event_date, bm25(fts_wiki_chunks, 0, 0, 2.5, 1.0) AS rank_score
           FROM fts_wiki_chunks f
           JOIN wiki_chunks c ON c.id = f.chunk_id
           JOIN wiki_pages p ON p.id = f.page_id
           WHERE fts_wiki_chunks MATCH ? AND p.category = ?
           ORDER BY rank_score ASC LIMIT 40`
        : `SELECT f.chunk_id, c.event_date, bm25(fts_wiki_chunks, 0, 0, 2.5, 1.0) AS rank_score
           FROM fts_wiki_chunks f
           JOIN wiki_chunks c ON c.id = f.chunk_id
           WHERE fts_wiki_chunks MATCH ?
           ORDER BY rank_score ASC LIMIT 40`;
      const rows = (
        category ? this.db.prepare(sql).all(matchExpr, category) : this.db.prepare(sql).all(matchExpr)
      ) as Array<{ chunk_id: string; event_date: string | null; rank_score: number }>;
      return rows.map((r) => ({
        chunkId: r.chunk_id,
        eventDate: r.event_date ?? undefined,
        score: -r.rank_score,
        matchedTerms: terms,
      }));
    }

    // Real SQLite WAL BM25 postings fallback
    const totalRow = this.db.prepare('SELECT COUNT(*) AS cnt, AVG(token_count) AS avg_dl FROM wiki_chunks').get() as {
      cnt: number;
      avg_dl: number | null;
    };
    const totalDocs = Math.max(1, Number(totalRow?.cnt ?? 0));
    const avgDl = Math.max(1, Number(totalRow?.avg_dl ?? 30));

    const placeholders = terms.map(() => '?').join(', ');
    const dfRows = this.db
      .prepare(`SELECT term, COUNT(*) AS df FROM wiki_chunk_postings WHERE term IN (${placeholders}) GROUP BY term`)
      .all(...terms) as Array<{ term: string; df: number }>;
    const idfByTerm = new Map<string, number>();
    for (const r of dfRows) {
      idfByTerm.set(r.term, Math.log(1 + (totalDocs - r.df + 0.5) / (r.df + 0.5)));
    }

    const postingSql = category
      ? `SELECT cp.chunk_id, cp.term, cp.tf, cp.in_title, c.token_count, c.event_date
         FROM wiki_chunk_postings cp
         JOIN wiki_chunks c ON c.id = cp.chunk_id
         JOIN wiki_pages p ON p.id = c.page_id
         WHERE cp.term IN (${placeholders}) AND p.category = ?`
      : `SELECT cp.chunk_id, cp.term, cp.tf, cp.in_title, c.token_count, c.event_date
         FROM wiki_chunk_postings cp
         JOIN wiki_chunks c ON c.id = cp.chunk_id
         WHERE cp.term IN (${placeholders})`;

    const rows = (
      category
        ? this.db.prepare(postingSql).all(...terms, category)
        : this.db.prepare(postingSql).all(...terms)
    ) as Array<{
      chunk_id: string;
      term: string;
      tf: number;
      in_title: number;
      token_count: number;
      event_date: string | null;
    }>;

    const k1 = 1.5;
    const b = 0.75;
    const acc = new Map<string, { score: number; eventDate?: string; matchedTerms: Set<string> }>();
    for (const r of rows) {
      const idf = idfByTerm.get(r.term) ?? 0.5;
      const dl = Math.max(1, r.token_count);
      const tfNorm = (r.tf * (k1 + 1)) / (r.tf + k1 * (1 - b + b * (dl / avgDl)));
      const titleBoost = r.in_title ? 1.6 : 1.0;
      const entry = acc.get(r.chunk_id) ?? {
        score: 0,
        eventDate: r.event_date ?? undefined,
        matchedTerms: new Set<string>(),
      };
      entry.score += idf * tfNorm * titleBoost;
      entry.matchedTerms.add(r.term);
      acc.set(r.chunk_id, entry);
    }

    return Array.from(acc.entries())
      .map(([chunkId, v]) => ({
        chunkId,
        eventDate: v.eventDate,
        score: v.score,
        matchedTerms: Array.from(v.matchedTerms),
      }))
      .sort((a, b2) => b2.score - a.score);
  }

  private searchFactsChannel(
    queries: string[],
    options: PersonalWikiSearchOptions,
    limit: number,
    hasWindow: boolean,
  ): PersonalWikiFactHit[] {
    const rrfScores = new Map<string, number>();

    for (let qIdx = 0; qIdx < queries.length; qIdx += 1) {
      const q = queries[qIdx];
      if (!q) continue;
      const weight = qIdx === 0 ? 1.25 : 0.85;
      const ranked = this.rankFactsLexically(q, options.category);

      ranked.slice(0, 32).forEach((item, rankIdx) => {
        const vote = weight / (WIKI_RRF_K + rankIdx + 1);
        rrfScores.set(item.factId, (rrfScores.get(item.factId) ?? 0) + vote);
      });

      if (hasWindow) {
        const inWindow = ranked.filter((item) =>
          isDateWithinWindow(item.eventDate, options.startDate, options.endDate),
        );
        inWindow.slice(0, 24).forEach((item, rankIdx) => {
          const bonus = (weight * WIKI_SOFT_WINDOW_BONUS_WEIGHT) / (WIKI_RRF_K + rankIdx + 1);
          rrfScores.set(item.factId, (rrfScores.get(item.factId) ?? 0) + bonus);
        });
      }
    }

    if (rrfScores.size === 0) return [];

    const topIds = Array.from(rrfScores.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, limit);

    const fetchFact = this.db.prepare(
      `SELECT f.id, f.page_id, f.chunk_id, f.fact_text, f.entities_json, f.event_date, f.confidence, p.category, p.title
       FROM wiki_facts f JOIN wiki_pages p ON p.id = f.page_id
       WHERE f.id = ?`,
    );

    const hits: PersonalWikiFactHit[] = [];
    for (const [factId, score] of topIds) {
      const row = fetchFact.get(factId) as Record<string, unknown> | undefined;
      if (!row) continue;
      const eventDate = row.event_date ? String(row.event_date) : undefined;
      hits.push({
        factId: String(row.id),
        pageId: String(row.page_id),
        chunkId: row.chunk_id ? String(row.chunk_id) : undefined,
        category: String(row.category) as WikiEntityCategory,
        pageTitle: String(row.title),
        factText: String(row.fact_text),
        entities: JSON.parse(String(row.entities_json ?? '[]')) as string[],
        eventDate,
        confidence: Number(row.confidence ?? 0.85),
        inTimeWindow: isDateWithinWindow(eventDate, options.startDate, options.endDate),
        score,
      });
    }
    return hits;
  }

  private rankFactsLexically(
    query: string,
    category?: WikiEntityCategory,
  ): Array<{ factId: string; eventDate?: string; score: number }> {
    const terms = Array.from(new Set(expandTokensWithCjkBigrams(query)));
    if (terms.length === 0) return [];

    if (this.supportsFts5) {
      const matchExpr = terms.map((t) => `"${t.replace(/"/g, '""')}"`).join(' OR ');
      const sql = category
        ? `SELECT ff.fact_id, f.event_date, bm25(fts_wiki_facts) AS rank_score
           FROM fts_wiki_facts ff
           JOIN wiki_facts f ON f.id = ff.fact_id
           JOIN wiki_pages p ON p.id = ff.page_id
           WHERE fts_wiki_facts MATCH ? AND p.category = ?
           ORDER BY rank_score ASC LIMIT 40`
        : `SELECT ff.fact_id, f.event_date, bm25(fts_wiki_facts) AS rank_score
           FROM fts_wiki_facts ff
           JOIN wiki_facts f ON f.id = ff.fact_id
           WHERE fts_wiki_facts MATCH ?
           ORDER BY rank_score ASC LIMIT 40`;
      const rows = (
        category ? this.db.prepare(sql).all(matchExpr, category) : this.db.prepare(sql).all(matchExpr)
      ) as Array<{ fact_id: string; event_date: string | null; rank_score: number }>;
      return rows.map((r) => ({ factId: r.fact_id, eventDate: r.event_date ?? undefined, score: -r.rank_score }));
    }

    const totalRow = this.db.prepare('SELECT COUNT(*) AS cnt, AVG(token_count) AS avg_dl FROM wiki_facts').get() as {
      cnt: number;
      avg_dl: number | null;
    };
    const totalDocs = Math.max(1, Number(totalRow?.cnt ?? 0));
    const avgDl = Math.max(1, Number(totalRow?.avg_dl ?? 16));

    const placeholders = terms.map(() => '?').join(', ');
    const dfRows = this.db
      .prepare(`SELECT term, COUNT(*) AS df FROM wiki_fact_postings WHERE term IN (${placeholders}) GROUP BY term`)
      .all(...terms) as Array<{ term: string; df: number }>;
    const idfByTerm = new Map<string, number>();
    for (const r of dfRows) {
      idfByTerm.set(r.term, Math.log(1 + (totalDocs - r.df + 0.5) / (r.df + 0.5)));
    }

    const postingSql = category
      ? `SELECT fp.fact_id, fp.term, fp.tf, f.token_count, f.event_date
         FROM wiki_fact_postings fp
         JOIN wiki_facts f ON f.id = fp.fact_id
         JOIN wiki_pages p ON p.id = f.page_id
         WHERE fp.term IN (${placeholders}) AND p.category = ?`
      : `SELECT fp.fact_id, fp.term, fp.tf, f.token_count, f.event_date
         FROM wiki_fact_postings fp
         JOIN wiki_facts f ON f.id = fp.fact_id
         WHERE fp.term IN (${placeholders})`;

    const rows = (
      category
        ? this.db.prepare(postingSql).all(...terms, category)
        : this.db.prepare(postingSql).all(...terms)
    ) as Array<{ fact_id: string; term: string; tf: number; token_count: number; event_date: string | null }>;

    const k1 = 1.5;
    const b = 0.75;
    const acc = new Map<string, { score: number; eventDate?: string }>();
    for (const r of rows) {
      const idf = idfByTerm.get(r.term) ?? 0.5;
      const dl = Math.max(1, r.token_count);
      const tfNorm = (r.tf * (k1 + 1)) / (r.tf + k1 * (1 - b + b * (dl / avgDl)));
      const entry = acc.get(r.fact_id) ?? { score: 0, eventDate: r.event_date ?? undefined };
      entry.score += idf * tfNorm;
      acc.set(r.fact_id, entry);
    }

    return Array.from(acc.entries())
      .map(([factId, v]) => ({ factId, eventDate: v.eventDate, score: v.score }))
      .sort((a, b2) => b2.score - a.score);
  }

  private searchSummariesChannel(
    queries: string[],
    options: PersonalWikiSearchOptions,
    limit: number,
    hasWindow: boolean,
  ): PersonalWikiSummaryHit[] {
    const pages = this.listPages(options.category);
    const queryTermSets = queries.map((q) => ({
      rawLower: q.toLowerCase(),
      terms: new Set(expandTokensWithCjkBigrams(q)),
    }));

    const hits: PersonalWikiSummaryHit[] = [];
    for (const page of pages) {
      const titleLower = page.title.toLowerCase();
      const aliasLowers = page.aliases.map((a) => a.toLowerCase());
      const docTerms = new Set(
        expandTokensWithCjkBigrams(`${page.title} ${page.aliases.join(' ')} ${page.summary} ${page.tags.join(' ')}`),
      );

      let score = 0;
      let matchedAlias: string | undefined;

      for (let i = 0; i < queryTermSets.length; i += 1) {
        const qs = queryTermSets[i];
        if (!qs) continue;
        const w = i === 0 ? 1.25 : 0.85;
        if (titleLower === qs.rawLower || titleLower.includes(qs.rawLower)) {
          score += 3.0 * w;
        }
        for (let aIdx = 0; aIdx < aliasLowers.length; aIdx += 1) {
          const al = aliasLowers[aIdx];
          if (al && (al === qs.rawLower || al.includes(qs.rawLower) || qs.rawLower.includes(al))) {
            score += 2.6 * w;
            matchedAlias = page.aliases[aIdx];
          }
        }
        let overlap = 0;
        for (const t of qs.terms) {
          if (docTerms.has(t)) overlap += 1;
        }
        if (overlap > 0 && qs.terms.size > 0) {
          score += (overlap / qs.terms.size) * 1.8 * w;
        }
      }

      if (score <= 0) continue;
      if (hasWindow && isDateWithinWindow(page.eventDate, options.startDate, options.endDate)) {
        score *= 1.35;
      }

      hits.push({
        pageId: page.id,
        slug: page.slug,
        category: page.category,
        title: page.title,
        aliases: page.aliases,
        summary: page.summary,
        eventDate: page.eventDate,
        score,
        matchedAlias,
      });
    }

    return hits.sort((a, b) => b.score - a.score).slice(0, limit);
  }
}
