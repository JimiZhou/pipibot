import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

export type DaemonWorktreeStatus =
  | 'active'
  | 'ready_for_review'
  | 'changes_requested'
  | 'merged'
  | 'discarded';

export type DaemonWorktreeMergeStrategy = 'squash' | 'merge_commit' | 'keep_branch_for_pr';

export interface DaemonWorktreeFileChange {
  path: string;
  status: string;
  additions: number;
  deletions: number;
}

export interface DaemonWorktreeSession {
  id: string;
  repoPath: string;
  worktreePath: string;
  branchName: string;
  baseBranch: string;
  taskTitle: string;
  botId: string;
  status: DaemonWorktreeStatus;
  files: DaemonWorktreeFileChange[];
  unifiedDiff: string;
  diffSummary: string;
  comments: Array<{ id: string; filePath?: string; lineNumber?: number; comment: string; createdAt: string }>;
  createdAt: string;
  updatedAt: string;
}

async function runGit(args: string[], cwd: string): Promise<string> {
  const { stdout } = await execFileAsync('git', args, {
    cwd,
    env: { ...process.env, GIT_TERMINAL_PROMPT: '0' },
    maxBuffer: 8 * 1024 * 1024,
  });
  return stdout.trim();
}

export function sanitizeWorktreeSlug(input: string): string {
  const cleaned = input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 28);
  return cleaned || 'task';
}

export class DaemonWorktreeManager {
  private readonly sessions = new Map<string, DaemonWorktreeSession>();

  listSessions(): DaemonWorktreeSession[] {
    return Array.from(this.sessions.values()).sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  }

  getSession(id: string): DaemonWorktreeSession | undefined {
    return this.sessions.get(id);
  }

  shouldIsolate(opts: {
    repoPath?: string;
    isGroupParallel?: boolean;
    projectAlwaysUseWorktree?: boolean;
  }): boolean {
    if (!opts.repoPath || !opts.repoPath.trim()) return false;
    if (opts.projectAlwaysUseWorktree || opts.isGroupParallel) return true;
    const resolved = resolve(opts.repoPath);
    const activeSameRepo = Array.from(this.sessions.values()).filter(
      (s) => s.repoPath === resolved && (s.status === 'active' || s.status === 'changes_requested'),
    ).length;
    return activeSameRepo > 0;
  }

  async createWorktree(input: {
    repoPath: string;
    taskTitle: string;
    botId: string;
  }): Promise<DaemonWorktreeSession> {
    const repoRoot = await runGit(['rev-parse', '--show-toplevel'], resolve(input.repoPath));
    const baseBranch =
      (await runGit(['rev-parse', '--abbrev-ref', 'HEAD'], repoRoot).catch(() => '')) || 'main';

    // Ensure .pipibot-worktrees/ is excluded locally without touching .gitignore
    const gitCommonDir = await runGit(['rev-parse', '--git-common-dir'], repoRoot);
    const excludePath = join(resolve(repoRoot, gitCommonDir), 'info', 'exclude');
    await mkdir(join(resolve(repoRoot, gitCommonDir), 'info'), { recursive: true });
    const existingExclude = await readFile(excludePath, 'utf8').catch(() => '');
    if (!existingExclude.includes('.pipibot-worktrees/')) {
      const next = existingExclude.endsWith('\n') || !existingExclude
        ? `${existingExclude}.pipibot-worktrees/\n`
        : `${existingExclude}\n.pipibot-worktrees/\n`;
      await writeFile(excludePath, next, 'utf8');
    }

    const shortId = randomUUID().slice(0, 6).toLowerCase();
    const slug = sanitizeWorktreeSlug(input.taskTitle);
    const branchName = `pipi/${slug}-${shortId}`;
    const container = join(repoRoot, '.pipibot-worktrees');
    await mkdir(container, { recursive: true });
    const worktreePath = join(container, `${slug}-${shortId}`);

    await runGit(['worktree', 'add', '-b', branchName, worktreePath, 'HEAD'], repoRoot);

    const now = new Date().toISOString();
    const session: DaemonWorktreeSession = {
      id: `wt_${shortId}`,
      repoPath: repoRoot,
      worktreePath,
      branchName,
      baseBranch,
      taskTitle: input.taskTitle,
      botId: input.botId,
      status: 'active',
      files: [],
      unifiedDiff: '',
      diffSummary: 'No file changes detected yet.',
      comments: [],
      createdAt: now,
      updatedAt: now,
    };
    this.sessions.set(session.id, session);
    return session;
  }

  async captureDiff(sessionId: string): Promise<DaemonWorktreeSession> {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error(`Worktree session not found: ${sessionId}`);

    const statusText = await runGit(['status', '--porcelain'], session.worktreePath).catch(() => '');
    const statusMap = new Map<string, string>();
    const untracked: string[] = [];
    for (const rawLine of statusText.split('\n').filter(Boolean)) {
      const code = rawLine.slice(0, 2).trim();
      const filePath = rawLine.slice(3).trim();
      if (!filePath) continue;
      if (code === '??') {
        statusMap.set(filePath, 'A');
        untracked.push(filePath);
      } else {
        statusMap.set(filePath, code[0] || 'M');
      }
    }

    const numstat = await runGit(['diff', '--numstat', session.baseBranch], session.worktreePath)
      .catch(() => runGit(['diff', '--numstat', 'HEAD'], session.worktreePath).catch(() => ''));
    const fileMap = new Map<string, DaemonWorktreeFileChange>();
    for (const line of numstat.split('\n').filter(Boolean)) {
      const [addsRaw, delsRaw, filePath] = line.split('\t');
      if (!filePath) continue;
      fileMap.set(filePath, {
        path: filePath,
        status: statusMap.get(filePath) ?? 'M',
        additions: Number.parseInt(addsRaw, 10) || 0,
        deletions: Number.parseInt(delsRaw, 10) || 0,
      });
    }

    const untrackedChunks: string[] = [];
    for (const filePath of untracked) {
      if (fileMap.has(filePath)) continue;
      const content = await readFile(join(session.worktreePath, filePath), 'utf8').catch(() => '');
      const lines = content ? content.split('\n') : [];
      fileMap.set(filePath, { path: filePath, status: 'A', additions: lines.length, deletions: 0 });
      if (lines.length > 0) {
        untrackedChunks.push(
          `--- /dev/null\n+++ b/${filePath}\n@@ -0,0 +1,${lines.length} @@\n${lines
            .slice(0, 80)
            .map((l) => `+${l}`)
            .join('\n')}`,
        );
      }
    }

    const trackedDiff = await runGit(['diff', session.baseBranch], session.worktreePath)
      .catch(() => runGit(['diff', 'HEAD'], session.worktreePath).catch(() => ''));
    const combinedDiff = [trackedDiff, ...untrackedChunks].filter(Boolean).join('\n\n').slice(0, 80_000);
    const files = Array.from(fileMap.values()).sort((a, b) => a.path.localeCompare(b.path));
    const adds = files.reduce((s, f) => s + f.additions, 0);
    const dels = files.reduce((s, f) => s + f.deletions, 0);

    session.files = files;
    session.unifiedDiff = combinedDiff;
    session.diffSummary = files.length
      ? `${files.length} file(s) changed (+${adds} / -${dels})`
      : 'No file changes detected yet.';
    if (files.length > 0 && (session.status === 'active' || session.status === 'changes_requested')) {
      session.status = 'ready_for_review';
    }
    session.updatedAt = new Date().toISOString();
    return session;
  }

  addFeedback(sessionId: string, comment: string, filePath?: string, lineNumber?: number): DaemonWorktreeSession {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error(`Worktree session not found: ${sessionId}`);
    session.comments.push({
      id: `wcmt_${randomUUID().slice(0, 6)}`,
      filePath,
      lineNumber,
      comment,
      createdAt: new Date().toISOString(),
    });
    session.status = 'changes_requested';
    session.updatedAt = new Date().toISOString();
    return session;
  }

  async mergeAndCleanup(
    sessionId: string,
    strategy: DaemonWorktreeMergeStrategy = 'squash',
    commitMessage?: string,
  ): Promise<{ session: DaemonWorktreeSession; summary: string }> {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error(`Worktree session not found: ${sessionId}`);

    const msg = (commitMessage || '').trim() || `feat(pipi): ${session.taskTitle}`;
    const dirty = await runGit(['status', '--porcelain'], session.worktreePath).catch(() => '');
    if (dirty) {
      await runGit(['add', '-A'], session.worktreePath);
      await runGit(['commit', '-m', msg], session.worktreePath);
    }

    if (strategy === 'keep_branch_for_pr') {
      session.updatedAt = new Date().toISOString();
      return {
        session,
        summary: `Committed changes on branch ${session.branchName} (preserved for PR).`,
      };
    }

    const activeBranch = await runGit(['rev-parse', '--abbrev-ref', 'HEAD'], session.repoPath);
    if (activeBranch !== session.baseBranch) {
      await runGit(['checkout', session.baseBranch], session.repoPath);
    }

    try {
      if (strategy === 'squash') {
        await runGit(['merge', '--squash', session.branchName], session.repoPath);
        const staged = await runGit(['status', '--porcelain'], session.repoPath);
        if (staged) {
          await runGit(['commit', '-m', msg], session.repoPath);
        }
      } else {
        await runGit(['merge', '--no-ff', '-m', msg, session.branchName], session.repoPath);
      }
    } catch (err) {
      await runGit(['merge', '--abort'], session.repoPath).catch(() => {});
      await runGit(['reset', '--merge'], session.repoPath).catch(() => {});
      throw err;
    }

    await runGit(['worktree', 'remove', '--force', session.worktreePath], session.repoPath).catch(() => {});
    await runGit(['branch', '-D', session.branchName], session.repoPath).catch(() => {});
    session.status = 'merged';
    session.updatedAt = new Date().toISOString();
    return {
      session,
      summary: `Merged ${session.branchName} into ${session.baseBranch} (${strategy}) and cleaned up worktree.`,
    };
  }

  async discardAndCleanup(sessionId: string): Promise<DaemonWorktreeSession> {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error(`Worktree session not found: ${sessionId}`);
    await runGit(['worktree', 'remove', '--force', session.worktreePath], session.repoPath).catch(() => {});
    await runGit(['branch', '-D', session.branchName], session.repoPath).catch(() => {});
    await rm(session.worktreePath, { recursive: true, force: true }).catch(() => {});
    session.status = 'discarded';
    session.updatedAt = new Date().toISOString();
    return session;
  }
}
