/**
 * @pipibot/core - pocket-notes.ts
 *
 * PiPiBot — Clean-room MIT implementation.
 * Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
 * Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.
 *
 * Wave 3 (#11): Daily Pocket Notes (5-minute silence Tracking Item extraction & reconciliation)
 * + Editable Artifact Documents (revision tracking, SHA-256 digest & optional Personal Wiki sync).
 */

import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';

import type { ArtifactDocumentKind, TrackingItemStatus } from '@pipibot/protocol';
import { scrubSensitiveContent } from './memory-engine.ts';
import type { PipiPersonalWikiStore } from './personal-wiki.ts';

// ---------------------------------------------------------------------------
// 1. Public Contracts & Constants
// ---------------------------------------------------------------------------

export const DEFAULT_POCKET_NOTE_SILENCE_SECONDS = 300; // 5 minutes

export interface DailyPocketNote {
  dateYmd: string; // YYYY-MM-DD
  content: string;
  contentSha256: string;
  lastEditedAtMs: number;
  lastExtractedAtMs?: number;
  lastExtractedHash?: string;
}

export interface TrackingItem {
  id: string;
  sourceDateYmd: string;
  title: string;
  dueDateYmd?: string;
  status: TrackingItemStatus;
  fingerprint: string;
  createdAt: string;
  updatedAt: string;
}

export interface PocketNoteReconcileResult {
  dateYmd: string;
  extracted: boolean;
  reason: 'reconciled' | 'waiting_silence_window' | 'unchanged' | 'note_not_found';
  added: TrackingItem[];
  keptCount: number;
  removedOpenIds: string[];
  openItems: TrackingItem[];
}

export interface ArtifactDocument {
  id: string;
  title: string;
  kind: ArtifactDocumentKind;
  markdown: string;
  revision: number;
  contentSha256: string;
  sessionId?: string;
  groupId?: string;
  tags: string[];
  createdAt: string;
  updatedAt: string;
}

interface PersistedPocketNotesState {
  version: 1;
  notes: Record<string, DailyPocketNote>;
  trackingItems: TrackingItem[];
  documents: ArtifactDocument[];
}

// ---------------------------------------------------------------------------
// 2. Helpers
// ---------------------------------------------------------------------------

function sha256Hex(text: string): string {
  return createHash('sha256').update(text, 'utf8').digest('hex');
}

function normalizeTodoFingerprint(title: string): string {
  return sha256Hex(title.toLowerCase().replace(/\s+/g, ' ').trim()).slice(0, 16);
}

async function atomicWrite(filePath: string, content: string): Promise<void> {
  await mkdir(dirname(filePath), { recursive: true });
  const tmpPath = `${filePath}.tmp.${process.pid}.${randomBytes(6).toString('hex')}`;
  await writeFile(tmpPath, content, 'utf8');
  await rename(tmpPath, filePath);
}

const DATE_SUFFIX_RE = /\b(20\d{2}-\d{2}-\d{2})\b/;

export function extractTodosFromPocketNote(markdown: string): Array<{ title: string; dueDateYmd?: string; completed: boolean }> {
  const results: Array<{ title: string; dueDateYmd?: string; completed: boolean }> = [];
  const lines = markdown.replace(/\r\n/g, '\n').split('\n');

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) continue;

    let completed = false;
    let body: string | null = null;

    const checkboxMatch = line.match(/^[-*]\s+\[([ xX])\]\s+(.+)$/);
    if (checkboxMatch) {
      completed = checkboxMatch[1]?.toLowerCase() === 'x';
      body = checkboxMatch[2]?.trim() ?? null;
    } else {
      const prefixMatch = line.match(/^(?:[-*]\s+)?(?:TODO|待办|跟进)\s*[:：]\s*(.+)$/i);
      if (prefixMatch) {
        body = prefixMatch[1]?.trim() ?? null;
      }
    }

    if (!body) continue;
    const cleanBody = scrubSensitiveContent(body).sanitized;
    const dueMatch = cleanBody.match(DATE_SUFFIX_RE);
    results.push({
      title: cleanBody,
      dueDateYmd: dueMatch?.[1],
      completed,
    });
  }

  return results;
}

// ---------------------------------------------------------------------------
// 3. PipiPocketNotesEngine
// ---------------------------------------------------------------------------

export class PipiPocketNotesEngine {
  readonly rootDir: string;
  readonly silenceSeconds: number;
  private readonly statePath: string;
  private state: PersistedPocketNotesState = {
    version: 1,
    notes: {},
    trackingItems: [],
    documents: [],
  };
  private loaded = false;

  constructor(options: { rootDir: string; silenceSeconds?: number }) {
    this.rootDir = options.rootDir;
    this.silenceSeconds = Math.max(0, options.silenceSeconds ?? DEFAULT_POCKET_NOTE_SILENCE_SECONDS);
    this.statePath = join(this.rootDir, 'pocket-notes', 'state.json');
  }

  async init(): Promise<void> {
    if (this.loaded) return;
    try {
      const raw = await readFile(this.statePath, 'utf8');
      const parsed = JSON.parse(raw) as PersistedPocketNotesState;
      if (parsed && parsed.version === 1) {
        this.state = parsed;
      }
    } catch {
      // Fresh state
    }
    this.loaded = true;
  }

  private async persist(): Promise<void> {
    await atomicWrite(this.statePath, JSON.stringify(this.state, null, 2));
  }

  // ---- Daily Pocket Notes ----

  async saveDailyNote(dateYmd: string, content: string, nowMs = Date.now()): Promise<DailyPocketNote> {
    await this.init();
    const clean = scrubSensitiveContent(content).sanitized;
    const existing = this.state.notes[dateYmd];
    const hash = sha256Hex(clean);
    const note: DailyPocketNote = {
      dateYmd,
      content: clean,
      contentSha256: hash,
      lastEditedAtMs: nowMs,
      lastExtractedAtMs: existing?.lastExtractedAtMs,
      lastExtractedHash: existing?.lastExtractedHash,
    };
    this.state.notes[dateYmd] = note;
    await atomicWrite(join(this.rootDir, 'pocket-notes', `${dateYmd}.md`), clean);
    await this.persist();
    return note;
  }

  async getDailyNote(dateYmd: string): Promise<DailyPocketNote | null> {
    await this.init();
    return this.state.notes[dateYmd] ?? null;
  }

  async listTrackingItems(status?: TrackingItemStatus): Promise<TrackingItem[]> {
    await this.init();
    const items = status
      ? this.state.trackingItems.filter((i) => i.status === status)
      : [...this.state.trackingItems];
    return items.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  }

  async setTrackingItemStatus(id: string, status: TrackingItemStatus): Promise<TrackingItem | null> {
    await this.init();
    const item = this.state.trackingItems.find((t) => t.id === id);
    if (!item) return null;
    item.status = status;
    item.updatedAt = new Date().toISOString();
    await this.persist();
    return item;
  }

  /**
   * Reconciles today's Pocket Note into Tracking Items once the user has been silent
   * for `silenceSeconds` (default 5 minutes), or immediately when `force: true`.
   * Open items originating from this date that are no longer mentioned in the note are removed.
   */
  async reconcileDailyNoteIfQuiet(
    dateYmd: string,
    options: { nowMs?: number; force?: boolean } = {},
  ): Promise<PocketNoteReconcileResult> {
    await this.init();
    const nowMs = options.nowMs ?? Date.now();
    const note = this.state.notes[dateYmd];
    if (!note) {
      return {
        dateYmd,
        extracted: false,
        reason: 'note_not_found',
        added: [],
        keptCount: 0,
        removedOpenIds: [],
        openItems: this.state.trackingItems.filter((i) => i.status === 'open'),
      };
    }

    if (!options.force && note.lastExtractedHash === note.contentSha256) {
      return {
        dateYmd,
        extracted: false,
        reason: 'unchanged',
        added: [],
        keptCount: 0,
        removedOpenIds: [],
        openItems: this.state.trackingItems.filter((i) => i.status === 'open'),
      };
    }

    const elapsedSec = (nowMs - note.lastEditedAtMs) / 1000;
    if (!options.force && elapsedSec < this.silenceSeconds) {
      return {
        dateYmd,
        extracted: false,
        reason: 'waiting_silence_window',
        added: [],
        keptCount: 0,
        removedOpenIds: [],
        openItems: this.state.trackingItems.filter((i) => i.status === 'open'),
      };
    }

    const parsedTodos = extractTodosFromPocketNote(note.content);
    const activeFingerprints = new Set(parsedTodos.map((t) => normalizeTodoFingerprint(t.title)));
    const nowIso = new Date(nowMs).toISOString();

    const removedOpenIds: string[] = [];
    this.state.trackingItems = this.state.trackingItems.filter((existing) => {
      if (existing.sourceDateYmd === dateYmd && existing.status === 'open' && !activeFingerprints.has(existing.fingerprint)) {
        removedOpenIds.push(existing.id);
        return false;
      }
      return true;
    });

    const added: TrackingItem[] = [];
    let keptCount = 0;

    for (const todo of parsedTodos) {
      const fp = normalizeTodoFingerprint(todo.title);
      const existing = this.state.trackingItems.find(
        (t) => t.sourceDateYmd === dateYmd && t.fingerprint === fp,
      );
      if (existing) {
        existing.title = todo.title;
        existing.dueDateYmd = todo.dueDateYmd;
        if (todo.completed && existing.status === 'open') {
          existing.status = 'done';
        }
        existing.updatedAt = nowIso;
        keptCount += 1;
      } else {
        const created: TrackingItem = {
          id: `trk_${Date.now().toString(36)}_${randomUUID().slice(0, 6)}`,
          sourceDateYmd: dateYmd,
          title: todo.title,
          dueDateYmd: todo.dueDateYmd,
          status: todo.completed ? 'done' : 'open',
          fingerprint: fp,
          createdAt: nowIso,
          updatedAt: nowIso,
        };
        this.state.trackingItems.unshift(created);
        added.push(created);
      }
    }

    note.lastExtractedAtMs = nowMs;
    note.lastExtractedHash = note.contentSha256;
    await this.persist();

    return {
      dateYmd,
      extracted: true,
      reason: 'reconciled',
      added,
      keptCount,
      removedOpenIds,
      openItems: this.state.trackingItems.filter((i) => i.status === 'open'),
    };
  }

  // ---- Editable Artifact Documents ----

  async upsertDocument(input: {
    id?: string;
    title: string;
    kind: ArtifactDocumentKind;
    markdown: string;
    sessionId?: string;
    groupId?: string;
    tags?: string[];
  }): Promise<ArtifactDocument> {
    await this.init();
    const nowIso = new Date().toISOString();
    const cleanTitle = scrubSensitiveContent(input.title.trim()).sanitized;
    const cleanBody = scrubSensitiveContent(input.markdown).sanitized;
    const hash = sha256Hex(`${cleanTitle}\n${cleanBody}`);
    const existing = input.id ? this.state.documents.find((d) => d.id === input.id) : undefined;

    let doc: ArtifactDocument;
    if (existing) {
      existing.title = cleanTitle;
      existing.kind = input.kind;
      existing.markdown = cleanBody;
      existing.revision += 1;
      existing.contentSha256 = hash;
      existing.sessionId = input.sessionId ?? existing.sessionId;
      existing.groupId = input.groupId ?? existing.groupId;
      existing.tags = input.tags ?? existing.tags;
      existing.updatedAt = nowIso;
      doc = existing;
    } else {
      doc = {
        id: input.id?.trim() || `doc_${Date.now().toString(36)}_${randomUUID().slice(0, 6)}`,
        title: cleanTitle,
        kind: input.kind,
        markdown: cleanBody,
        revision: 1,
        contentSha256: hash,
        sessionId: input.sessionId,
        groupId: input.groupId,
        tags: input.tags ?? [],
        createdAt: nowIso,
        updatedAt: nowIso,
      };
      this.state.documents.unshift(doc);
    }

    await atomicWrite(join(this.rootDir, 'documents', `${doc.id}.md`), doc.markdown);
    await this.persist();
    return { ...doc, tags: [...doc.tags] };
  }

  async listDocuments(): Promise<ArtifactDocument[]> {
    await this.init();
    return [...this.state.documents].sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  }

  async syncDocumentToPersonalWiki(docId: string, wiki: PipiPersonalWikiStore): Promise<string | null> {
    await this.init();
    const doc = this.state.documents.find((d) => d.id === docId);
    if (!doc) return null;
    const firstNonEmpty = doc.markdown
      .split('\n')
      .map((l) => l.replace(/^#+\s*/, '').trim())
      .find((l) => l.length > 0);
    const page = await wiki.upsertPage({
      id: `wiki_doc_${doc.id}`,
      category: doc.kind === 'note' ? 'life' : 'projects',
      title: doc.title,
      summary: (firstNonEmpty ?? doc.title).slice(0, 180),
      bodyMarkdown: doc.markdown,
      tags: [...doc.tags, doc.kind],
      sourceRefs: [`pipibot://documents/${doc.id}@rev${doc.revision}`],
    });
    return page.id;
  }
}
