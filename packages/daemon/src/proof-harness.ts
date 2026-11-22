import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { extname, join } from 'node:path';
import { promisify } from 'node:util';

import type { DaemonWorktreeSession } from './worktree.ts';

const execFileAsync = promisify(execFile);

export interface DaemonDeterministicCheck {
  id: string;
  name: string;
  kind: 'shell_command' | 'regex_ban';
  commandOrPattern: string;
  fileExtensions?: string[];
  enabled: boolean;
  graduatedFromRule?: string;
}

export interface DaemonProofCheckResult {
  checkId: string;
  name: string;
  passed: boolean;
  exitCode: number;
  durationMs: number;
  outputSnippet: string;
}

export interface DaemonProofBundle {
  id: string;
  worktreeSessionId: string;
  generatedAt: string;
  checkResults: DaemonProofCheckResult[];
  overallStatus: 'verified' | 'blocked';
  proofScore: number;
  summary: string;
}

export interface DaemonKnowledgeGap {
  id: string;
  botId: string;
  question: string;
  sourceChannel: string;
  occurrenceCount: number;
  status: 'open' | 'resolved';
  resolvedDocPath?: string;
  updatedAt: string;
}

export interface DaemonLoopDraft {
  id: string;
  loopName: string;
  botId: string;
  inputSummary: string;
  draftContent: string;
  citedSources: string[];
  status: 'pending_gate' | 'approved_and_sent' | 'edited_and_sent' | 'flagged_undrafted' | 'discarded';
  escalationReason?: string;
  addedHarnessRule?: string;
  createdAt: string;
  resolvedAt?: string;
}

const HARD_NO_DRAFT_TRIGGERS = ['refund', '退款', 'billing dispute', '账号安全', '投诉', 'angry'];

export class DaemonProofAndHarnessEngine {
  readonly checks: DaemonDeterministicCheck[] = [
    {
      id: 'chk_no_secret_leak',
      name: 'No Hardcoded Secrets',
      kind: 'regex_ban',
      commandOrPattern: '(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,})',
      fileExtensions: ['.ts', '.js', '.swift', '.py', '.json'],
      enabled: true,
      graduatedFromRule: 'Never commit hardcoded credentials',
    },
    {
      id: 'chk_no_excuse_comments',
      name: 'No Excuse Comments (pstack ratchet)',
      kind: 'regex_ban',
      commandOrPattern: '//\\s*(HACK|FIXME|XXX|TEMP)\\b',
      fileExtensions: ['.ts', '.js', '.swift', '.py'],
      enabled: true,
      graduatedFromRule: 'Replace excuse comments with tracked issues',
    },
  ];

  private readonly gaps: DaemonKnowledgeGap[] = [];
  private readonly drafts: DaemonLoopDraft[] = [];
  private readonly harnessRules: string[] = [];

  listGaps(): DaemonKnowledgeGap[] {
    return [...this.gaps];
  }

  recordGap(input: { botId: string; question: string; sourceChannel?: string }): DaemonKnowledgeGap {
    const q = input.question.trim();
    const now = new Date().toISOString();
    const existing = this.gaps.find((g) => g.status === 'open' && g.question.toLowerCase() === q.toLowerCase());
    if (existing) {
      existing.occurrenceCount += 1;
      existing.updatedAt = now;
      return existing;
    }
    const gap: DaemonKnowledgeGap = {
      id: `gap_${randomUUID().slice(0, 8)}`,
      botId: input.botId,
      question: q,
      sourceChannel: input.sourceChannel || 'support',
      occurrenceCount: 1,
      status: 'open',
      updatedAt: now,
    };
    this.gaps.unshift(gap);
    return gap;
  }

  resolveGap(id: string, docPath?: string): DaemonKnowledgeGap | undefined {
    const found = this.gaps.find((g) => g.id === id);
    if (!found) return undefined;
    found.status = 'resolved';
    found.resolvedDocPath = docPath;
    found.updatedAt = new Date().toISOString();
    return found;
  }

  listDrafts(): DaemonLoopDraft[] {
    return [...this.drafts];
  }

  listHarnessRules(): string[] {
    return [...this.harnessRules];
  }

  enqueueDraft(input: {
    loopName: string;
    botId: string;
    inputSummary: string;
    draftContent: string;
    citedSources?: string[];
  }): DaemonLoopDraft {
    const matched = HARD_NO_DRAFT_TRIGGERS.find((t) =>
      input.inputSummary.toLowerCase().includes(t.toLowerCase()),
    );
    const now = new Date().toISOString();
    if (matched) {
      const flagged: DaemonLoopDraft = {
        id: `drf_${randomUUID().slice(0, 8)}`,
        loopName: input.loopName,
        botId: input.botId,
        inputSummary: input.inputSummary,
        draftContent: '',
        citedSources: [],
        status: 'flagged_undrafted',
        escalationReason: `Matched hard no-draft trigger "${matched}"; flagged straight to owner.`,
        createdAt: now,
      };
      this.drafts.unshift(flagged);
      return flagged;
    }
    const item: DaemonLoopDraft = {
      id: `drf_${randomUUID().slice(0, 8)}`,
      loopName: input.loopName,
      botId: input.botId,
      inputSummary: input.inputSummary,
      draftContent: input.draftContent,
      citedSources: input.citedSources ?? [],
      status: 'pending_gate',
      createdAt: now,
    };
    this.drafts.unshift(item);
    return item;
  }

  resolveDraft(id: string, opts: { action: 'approve' | 'edit_and_add_rule' | 'discard'; editedDraft?: string; newRule?: string }): DaemonLoopDraft | undefined {
    const item = this.drafts.find((d) => d.id === id);
    if (!item) return undefined;
    item.resolvedAt = new Date().toISOString();
    if (opts.action === 'approve') {
      item.status = 'approved_and_sent';
    } else if (opts.action === 'edit_and_add_rule') {
      if (opts.editedDraft) item.draftContent = opts.editedDraft;
      const rule = (opts.newRule || '').trim() || 'Match revised owner phrasing';
      item.addedHarnessRule = rule;
      if (!this.harnessRules.includes(rule)) this.harnessRules.push(rule);
      item.status = 'edited_and_sent';
    } else {
      item.status = 'discarded';
    }
    return item;
  }

  async verifyWorktree(session: DaemonWorktreeSession): Promise<DaemonProofBundle> {
    const results: DaemonProofCheckResult[] = [];
    for (const chk of this.checks.filter((c) => c.enabled)) {
      const started = Date.now();
      if (chk.kind === 'regex_ban') {
        const rx = new RegExp(chk.commandOrPattern);
        const hits: string[] = [];
        let scanned = 0;
        for (const f of session.files) {
          if (f.status === 'D') continue;
          const ext = extname(f.path).toLowerCase();
          if (chk.fileExtensions && chk.fileExtensions.length > 0 && !chk.fileExtensions.includes(ext)) {
            continue;
          }
          const content = await readFile(join(session.worktreePath, f.path), 'utf8').catch(() => '');
          if (!content) continue;
          scanned += 1;
          const lines = content.split('\n');
          for (let i = 0; i < lines.length; i += 1) {
            if (rx.test(lines[i])) {
              hits.push(`${f.path}:L${i + 1}`);
              if (hits.length >= 6) break;
            }
          }
        }
        const passed = hits.length === 0;
        results.push({
          checkId: chk.id,
          name: chk.name,
          passed,
          exitCode: passed ? 0 : 1,
          durationMs: Math.max(1, Date.now() - started),
          outputSnippet: passed ? `0 violations across ${scanned} file(s).` : `Violations: ${hits.join(', ')}`,
        });
      } else {
        try {
          const { stdout } = await execFileAsync('sh', ['-lc', chk.commandOrPattern], {
            cwd: session.worktreePath,
            timeout: 30_000,
          });
          results.push({
            checkId: chk.id,
            name: chk.name,
            passed: true,
            exitCode: 0,
            durationMs: Math.max(1, Date.now() - started),
            outputSnippet: stdout.trim().slice(-240) || 'Passed (exit 0)',
          });
        } catch (err) {
          results.push({
            checkId: chk.id,
            name: chk.name,
            passed: false,
            exitCode: 1,
            durationMs: Math.max(1, Date.now() - started),
            outputSnippet: err instanceof Error ? err.message.slice(-240) : String(err),
          });
        }
      }
    }

    const passedCount = results.filter((r) => r.passed).length;
    const score = results.length ? Math.round((passedCount / results.length) * 100) : 100;
    const overallStatus = passedCount === results.length ? 'verified' : 'blocked';
    return {
      id: `proof_${randomUUID().slice(0, 8)}`,
      worktreeSessionId: session.id,
      generatedAt: new Date().toISOString(),
      checkResults: results,
      overallStatus,
      proofScore: score,
      summary: `Deterministic checks ${passedCount}/${results.length} passed · Proof score ${score}/100`,
    };
  }
}
