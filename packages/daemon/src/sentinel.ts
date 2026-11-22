/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/daemon - sentinel.ts
 * Zero-LLM Out-of-Process Read-Only Health Scanner (`pipibot-daemon sentinel`).
 * Normalizes paths/numbers/UUIDs/URLs/emails/quotes before SHA-256 hashing so recurring errors
 * collapse into one sanitized signature and feed approval-gated Self-Evolution proposals.
 */

import { createHash } from 'node:crypto';
import { chmodSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export type SentinelIssueKind =
  | 'tool_error'
  | 'shell_error'
  | 'queue_stall'
  | 'high_cost_turn'
  | 'routine_failure';

export interface SentinelSample {
  id: string;
  kind: SentinelIssueKind;
  toolName?: string;
  botId?: string;
  rawMessage: string;
  exitCode?: number;
  costUSD?: number;
  queueWaitSeconds?: number;
  timestamp?: string;
}

export interface SentinelIssue {
  signature: string;
  kind: SentinelIssueKind;
  severity: 'low' | 'medium' | 'high';
  normalizedTitle: string;
  toolName?: string;
  botId?: string;
  count: number;
  wastedTurns: number;
  firstSeenAt: string;
  lastSeenAt: string;
  evidenceRefIds: string[];
  evolutionProposal?: {
    id: string;
    proposedRule: string;
    rationale: string;
  };
}

export function normalizeSentinelErrorLine(raw: string, opts?: { isShell?: boolean; exitCode?: number }): string {
  const lower = raw.toLowerCase();
  if (opts?.isShell) {
    if (lower.includes('timed out') || lower.includes('timeout')) return 'shell: timed out';
    let cls = 'execution failed';
    if (lower.includes('command not found')) cls = 'command not found';
    else if (lower.includes('permission denied')) cls = 'permission denied';
    else if (lower.includes('no such file')) cls = 'no such file';
    else if (lower.includes('syntax error')) cls = 'syntax error';
    return `exit ${opts.exitCode ?? 1}: ${cls}`;
  }
  const firstLine = (raw.split(/\r?\n/)[0] ?? raw)
    .replace(/https?:\/\/[^\s"']+/g, '<url>')
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, '<email>')
    .replace(/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/g, '<uuid>')
    .replace(/(?:\/[A-Za-z0-9._-]+){2,}/g, '<path>')
    .replace(/"[^"]{1,120}"/g, '<str>')
    .replace(/'[^']{1,120}'/g, '<str>')
    .replace(/0x[0-9a-fA-F]{4,}/g, '<hex>')
    .replace(/\b[0-9a-fA-F]{16,}\b/g, '<hex>')
    .replace(/\b\d+\b/g, '<n>')
    .replace(/\s+/g, ' ')
    .trim();
  return firstLine.slice(0, 160);
}

export function computeSentinelSignature(kind: SentinelIssueKind, toolName: string | undefined, normalizedTitle: string): string {
  const hash = createHash('sha256')
    .update(`${kind}|${toolName ?? '-'}|${normalizedTitle}`)
    .digest('hex')
    .slice(0, 16);
  return `${kind}:${hash}`;
}

export function scanSentinelSamples(
  samples: SentinelSample[],
  options?: { queueWaitSeconds?: number; highCostUSD?: number; recurrenceThreshold?: number },
): SentinelIssue[] {
  const queueThreshold = options?.queueWaitSeconds ?? 120;
  const costThreshold = options?.highCostUSD ?? 2.0;
  const recurrenceThreshold = options?.recurrenceThreshold ?? 3;
  const bySig = new Map<string, SentinelIssue>();

  for (const s of samples) {
    const ts = s.timestamp ?? new Date().toISOString();
    let kind: SentinelIssueKind = s.kind;
    let normalizedTitle = '';
    let severity: 'low' | 'medium' | 'high' = 'medium';

    if ((s.queueWaitSeconds ?? 0) >= queueThreshold) {
      kind = 'queue_stall';
      normalizedTitle = `queue wait exceeded ${queueThreshold}s threshold`;
      severity = 'high';
    } else if ((s.costUSD ?? 0) >= costThreshold) {
      kind = 'high_cost_turn';
      normalizedTitle = `single turn cost exceeded $${costThreshold.toFixed(2)}`;
      severity = 'medium';
    } else {
      normalizedTitle = normalizeSentinelErrorLine(s.rawMessage, {
        isShell: s.kind === 'shell_error',
        exitCode: s.exitCode,
      });
      severity = s.kind === 'shell_error' || s.kind === 'routine_failure' ? 'high' : 'medium';
    }

    const sig = computeSentinelSignature(kind, s.toolName, normalizedTitle);
    const prev = bySig.get(sig);
    if (prev) {
      if (!prev.evidenceRefIds.includes(s.id)) {
        prev.count += 1;
        prev.wastedTurns += 1;
        if (ts > prev.lastSeenAt) prev.lastSeenAt = ts;
        prev.evidenceRefIds.push(s.id);
      }
    } else {
      bySig.set(sig, {
        signature: sig,
        kind,
        severity,
        normalizedTitle,
        toolName: s.toolName,
        botId: s.botId,
        count: 1,
        wastedTurns: 1,
        firstSeenAt: ts,
        lastSeenAt: ts,
        evidenceRefIds: [s.id],
      });
    }
  }

  const list = [...bySig.values()].sort((a, b) => b.count - a.count);
  for (const issue of list) {
    if (issue.count >= recurrenceThreshold) {
      issue.evolutionProposal = {
        id: `evo_sent_${issue.signature.split(':')[1]?.slice(0, 8) ?? 'guard'}`,
        proposedRule: `Sentinel Guard (${issue.signature}): Pre-check inputs before ${issue.toolName ?? 'tool'} to prevent recurring "${issue.normalizedTitle}".`,
        rationale: `Detected ${issue.count} identical failures across ${issue.wastedTurns} turns.`,
      };
    }
  }
  return list;
}

export function writeSentinelIssuesJSONL(outDir: string, issues: SentinelIssue[]): string {
  if (!existsSync(outDir)) {
    mkdirSync(outDir, { recursive: true, mode: 0o700 });
  }
  const filePath = join(outDir, 'issues.jsonl');
  const lines = issues.map((it) => JSON.stringify(it)).join('\n') + (issues.length ? '\n' : '');
  writeFileSync(filePath, lines, { encoding: 'utf8', mode: 0o600 });
  try {
    chmodSync(filePath, 0o600);
  } catch {
    // ignore on platforms without POSIX chmod
  }
  return filePath;
}
