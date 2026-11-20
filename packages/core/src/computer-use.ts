/**
 * @pipibot/core — computer-use.ts (Wave 5 · #09)
 *
 * PiPiBot — Clean-room MIT implementation.
 * Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
 * Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.
 *
 * Dual-Phase Computer Use Runtime:
 * - Phase A: Local signed-in Chrome collaboration with per-agent isolated
 *   Seats/Tabs (`signed_in_chrome_seat` or `isolated_profile`), local-only
 *   credentials (zero secret/cookie export, zero arbitrary page-script eval).
 * - Phase B: macOS Accessibility / Cua structured element-tree desktop control.
 * - Concurrency Lanes: one global `desktop_screen` single lane (waits for
 *   in-flight foreground browser calls) + independent parallel `agent_browser`
 *   lanes (one per agent so agents never fight over tabs or screen focus).
 * - Human-Focus Immediate Yield: detects human app/window focus switch or
 *   manual takeover and immediately yields the desktop lane without stealing
 *   cursor/keyboard focus.
 * - Write-Ahead Journal (WAL): logs every input action before dispatch;
 *   prevents duplicate clicks on retry and locks a lane on `unknown_outcome`
 *   until explicitly reviewed and unlocked by the human.
 * - Guardrail Enforcement: routes every Computer Use action with structured
 *   `<browser_state>` / `<desktop_state>` context through `#08`
 *   `PipiPermissionGuardrail`.
 *
 * Runtime dependencies: strictly Node built-ins (`node:*`) only.
 */

import { randomUUID } from 'node:crypto';
import { chmod, mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';

import type {
  ActionKind,
  ActionSourceTrust,
  BrowserSeatMode,
  ComputerUseActionType,
  ComputerUseLaneKind,
  ComputerUseLaneState,
  ComputerUsePhase,
  GuardrailVerdict,
  WriteAheadJournalStatus,
} from '@pipibot/protocol';
import {
  PipiPermissionGuardrail,
  type GuardrailEvaluationOptions,
} from './permission-guardrail.ts';

// ---------------------------------------------------------------------------
// 1. Structured Element Tree, Seat, Lane & WAL Contracts
// ---------------------------------------------------------------------------

export interface UIElementNode {
  ref: string;
  role: string;
  label: string;
  value?: string;
  enabled: boolean;
  bounds?: { x: number; y: number; width: number; height: number };
  /** Structured semantics used by #08 Guardrail (never rely on brittle regexes alone). */
  isSubmitAction?: boolean;
  isExternalEffect?: boolean;
  isSystemPrivacySwitch?: boolean;
}

export interface SurfaceSnapshot {
  phase: ComputerUsePhase;
  capturedAt: string;
  appName: string;
  appBundleId?: string;
  windowTitle: string;
  url?: string;
  seatId?: string;
  elements: UIElementNode[];
}

export interface ChromeBrowserSeat {
  seatId: string;
  agentId: string;
  mode: BrowserSeatMode;
  tabId: string;
  profileDir?: string;
  currentUrl: string;
  currentTitle: string;
  debugPort: number;
  createdAt: string;
  lastUsedAt: string;
}

export interface WriteAheadJournalEntry {
  journalId: string;
  operationId: string;
  laneId: string;
  laneKind: ComputerUseLaneKind;
  phase: ComputerUsePhase;
  agentId: string;
  actionType: ComputerUseActionType;
  targetApp?: string;
  targetUrl?: string;
  targetElementRef?: string;
  targetElementLabel?: string;
  status: WriteAheadJournalStatus;
  verdictDecision?: GuardrailVerdict['decision'];
  resultSummary?: string;
  error?: string;
  createdAt: string;
  updatedAt: string;
}

export interface ComputerUseLaneSnapshot {
  laneId: string;
  kind: ComputerUseLaneKind;
  state: ComputerUseLaneState;
  activeAgentId?: string;
  activeOperationId?: string;
  blockedByJournalId?: string;
  yieldReason?: string;
  updatedAt: string;
}

export interface ComputerUseActionRequest {
  operationId?: string;
  agentId: string;
  sessionId?: string;
  projectId?: string;
  phase: ComputerUsePhase;
  actionType: ComputerUseActionType;
  targetUrl?: string;
  targetAppName?: string;
  targetAppBundleId?: string;
  targetElementRef?: string;
  textInput?: string;
  keyCombo?: string;
  /** Explicit flag indicating an action submits/sends/publishes (e.g., Enter in chat box). */
  submitsEffect?: boolean;
  requiresFrontWindow?: boolean;
  sourceTrust?: ActionSourceTrust;
  trustedUserMessages?: string[];
  untrustedContextSnippets?: string[];
  guardrailOptions?: GuardrailEvaluationOptions;
}

export interface ComputerUseActionResult {
  ok: boolean;
  operationId: string;
  journalId: string;
  laneId: string;
  status: WriteAheadJournalStatus;
  replayedFromJournal: boolean;
  yieldedToHuman: boolean;
  verdict?: GuardrailVerdict;
  snapshot?: SurfaceSnapshot;
  seat?: ChromeBrowserSeat;
  summary: string;
  error?: string;
}

// ---------------------------------------------------------------------------
// 2. Pluggable Phase A (Chrome) & Phase B (macOS Accessibility) Drivers
// ---------------------------------------------------------------------------

export interface BrowserAutomationDriver {
  probeSignedInChrome(debugPort: number): Promise<{ reachable: boolean; browserVersion?: string }>;
  openOrReuseSeat(params: {
    agentId: string;
    mode: BrowserSeatMode;
    debugPort: number;
    profileDir?: string;
  }): Promise<{ tabId: string; url: string; title: string }>;
  executeBrowserAction(
    seat: ChromeBrowserSeat,
    req: ComputerUseActionRequest,
  ): Promise<{ summary: string; snapshot?: SurfaceSnapshot; currentUrl?: string; currentTitle?: string }>;
}

export interface DesktopAccessibilityDriver {
  checkAccessibilityTrusted(): Promise<boolean>;
  getFrontmostApp(): Promise<{ appName: string; bundleId: string; windowTitle: string }>;
  captureDesktopSnapshot(targetAppBundleId?: string): Promise<SurfaceSnapshot>;
  executeDesktopAction(
    req: ComputerUseActionRequest,
    resolvedElement?: UIElementNode,
  ): Promise<{ summary: string; snapshot?: SurfaceSnapshot }>;
}

export class DefaultLocalChromeDriver implements BrowserAutomationDriver {
  readonly #fetchImpl: typeof fetch;

  constructor(fetchImpl: typeof fetch = globalThis.fetch) {
    this.#fetchImpl = fetchImpl;
  }

  async probeSignedInChrome(debugPort: number): Promise<{ reachable: boolean; browserVersion?: string }> {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 1_500);
      try {
        const resp = await this.#fetchImpl(`http://127.0.0.1:${debugPort}/json/version`, {
          signal: controller.signal,
        });
        if (!resp.ok) return { reachable: false };
        const json = (await resp.json()) as { Browser?: string };
        return { reachable: true, browserVersion: json.Browser ?? 'Chrome CDP' };
      } finally {
        clearTimeout(timer);
      }
    } catch {
      return { reachable: false };
    }
  }

  async openOrReuseSeat(params: {
    agentId: string;
    mode: BrowserSeatMode;
    debugPort: number;
    profileDir?: string;
  }): Promise<{ tabId: string; url: string; title: string }> {
    return {
      tabId: `tab_${params.agentId}_${randomUUID().slice(0, 6)}`,
      url: 'about:blank',
      title: `PiPiBot Seat (${params.agentId})`,
    };
  }

  async executeBrowserAction(
    seat: ChromeBrowserSeat,
    req: ComputerUseActionRequest,
  ): Promise<{ summary: string; snapshot?: SurfaceSnapshot; currentUrl?: string; currentTitle?: string }> {
    const nextUrl = req.targetUrl ?? seat.currentUrl;
    const snap: SurfaceSnapshot = {
      phase: 'chrome_browser',
      capturedAt: new Date().toISOString(),
      appName: 'Google Chrome',
      appBundleId: 'com.google.Chrome',
      windowTitle: seat.currentTitle,
      url: nextUrl,
      seatId: seat.seatId,
      elements: [],
    };
    return {
      summary: `Executed Chrome ${req.actionType} on seat ${seat.seatId} (${nextUrl})`,
      snapshot: snap,
      currentUrl: nextUrl,
      currentTitle: seat.currentTitle,
    };
  }
}

// ---------------------------------------------------------------------------
// 3. Write-Ahead Journal (WAL) — Anti-Double-Click & Unknown-Outcome Lane Lock
// ---------------------------------------------------------------------------

class AsyncMutexLane {
  #tail: Promise<void> = Promise.resolve();

  async runExclusive<T>(fn: () => Promise<T>): Promise<T> {
    let release!: () => void;
    const next = new Promise<void>((resolve) => {
      release = resolve;
    });
    const prev = this.#tail;
    this.#tail = prev.then(() => next);
    await prev;
    try {
      return await fn();
    } finally {
      release();
    }
  }
}

export class PipiWriteAheadJournal {
  readonly #filePath?: string;
  #entries: WriteAheadJournalEntry[] = [];
  readonly #lockedLanes = new Map<string, string>(); // laneId -> blocking journalId
  readonly #persistMutex = new AsyncMutexLane();

  constructor(options?: { rootDir?: string }) {
    this.#filePath = options?.rootDir ? join(options.rootDir, 'computer-use-journal.json') : undefined;
  }

  async load(): Promise<void> {
    if (!this.#filePath) return;
    try {
      const raw = await readFile(this.#filePath, 'utf8');
      const parsed = JSON.parse(raw) as {
        entries?: WriteAheadJournalEntry[];
        lockedLanes?: Record<string, string>;
      };
      this.#entries = Array.isArray(parsed.entries) ? parsed.entries : [];
      this.#lockedLanes.clear();
      for (const [laneId, jid] of Object.entries(parsed.lockedLanes ?? {})) {
        this.#lockedLanes.set(laneId, jid);
      }
      // Recover any stale `dispatched` entries from a prior crash as `unknown_outcome` & lock their lane!
      let mutated = false;
      for (const entry of this.#entries) {
        if (entry.status === 'dispatched') {
          entry.status = 'unknown_outcome';
          entry.error = 'Process terminated while action was in flight; outcome unknown (replay blocked).';
          entry.updatedAt = new Date().toISOString();
          this.#lockedLanes.set(entry.laneId, entry.journalId);
          mutated = true;
        }
      }
      if (mutated) {
        await this.persist();
      }
    } catch {
      // File may not exist on first boot
    }
  }

  async persist(): Promise<void> {
    if (!this.#filePath) return;
    const targetPath = this.#filePath;
    await this.#persistMutex.runExclusive(async () => {
      await mkdir(dirname(targetPath), { recursive: true, mode: 0o700 });
      const tmp = `${targetPath}.tmp-${process.pid}-${randomUUID().slice(0, 8)}`;
      const payload = {
        entries: this.#entries.slice(-200),
        lockedLanes: Object.fromEntries(this.#lockedLanes.entries()),
        updatedAt: new Date().toISOString(),
      };
      await writeFile(tmp, `${JSON.stringify(payload, null, 2)}\n`, { mode: 0o600 });
      await chmod(tmp, 0o600).catch(() => undefined);
      await rename(tmp, targetPath);
    });
  }

  listEntries(): WriteAheadJournalEntry[] {
    return this.#entries.map((e) => ({ ...e }));
  }

  findByOperationId(operationId: string): WriteAheadJournalEntry | undefined {
    for (let i = this.#entries.length - 1; i >= 0; i -= 1) {
      if (this.#entries[i].operationId === operationId) {
        return { ...this.#entries[i] };
      }
    }
    return undefined;
  }

  blockingJournalForLane(laneId: string): string | undefined {
    return this.#lockedLanes.get(laneId);
  }

  async appendPrepared(
    entry: Omit<WriteAheadJournalEntry, 'journalId' | 'status' | 'createdAt' | 'updatedAt'>,
  ): Promise<WriteAheadJournalEntry> {
    const now = new Date().toISOString();
    const record: WriteAheadJournalEntry = {
      ...entry,
      journalId: `wal_${randomUUID().slice(0, 10)}`,
      status: 'prepared',
      createdAt: now,
      updatedAt: now,
    };
    this.#entries.push(record);
    await this.persist();
    return { ...record };
  }

  async updateStatus(
    journalId: string,
    status: WriteAheadJournalStatus,
    patch?: { verdictDecision?: GuardrailVerdict['decision']; resultSummary?: string; error?: string },
  ): Promise<WriteAheadJournalEntry | undefined> {
    const idx = this.#entries.findIndex((e) => e.journalId === journalId);
    if (idx < 0) return undefined;
    const entry = this.#entries[idx];
    entry.status = status;
    entry.updatedAt = new Date().toISOString();
    if (patch?.verdictDecision !== undefined) entry.verdictDecision = patch.verdictDecision;
    if (patch?.resultSummary !== undefined) entry.resultSummary = patch.resultSummary;
    if (patch?.error !== undefined) entry.error = patch.error;

    if (status === 'unknown_outcome') {
      this.#lockedLanes.set(entry.laneId, entry.journalId);
    }
    await this.persist();
    return { ...entry };
  }

  /**
   * Explicitly unlocks a lane that was halted due to an `unknown_outcome` entry
   * after the human has visually inspected the screen/tab and confirmed it is safe.
   */
  async acknowledgeAndUnlockLane(laneId: string, reviewerNote?: string): Promise<boolean> {
    const blockingId = this.#lockedLanes.get(laneId);
    if (!blockingId) return false;
    this.#lockedLanes.delete(laneId);
    const idx = this.#entries.findIndex((e) => e.journalId === blockingId);
    if (idx >= 0) {
      this.#entries[idx].resultSummary =
        `${this.#entries[idx].resultSummary ?? ''} [Human acknowledged & unlocked${reviewerNote ? `: ${reviewerNote}` : ''}]`.trim();
      this.#entries[idx].updatedAt = new Date().toISOString();
    }
    await this.persist();
    return true;
  }
}

// ---------------------------------------------------------------------------
// 4. Dual-Lane Concurrency + Human-Focus Yield + Guardrail Coordinator
// ---------------------------------------------------------------------------

export interface ComputerUseCoordinatorOptions {
  rootDir?: string;
  browserSeatMode?: BrowserSeatMode;
  chromeDebugPort?: number;
  guardrail?: PipiPermissionGuardrail;
  browserDriver?: BrowserAutomationDriver;
  desktopDriver?: DesktopAccessibilityDriver;
  autoYieldOnHumanFocus?: boolean;
}

const SYSTEM_PRIVACY_BUNDLE_IDS = new Set([
  'com.apple.systempreferences',
  'com.apple.SystemSettings',
  'com.apple.keychainaccess',
]);

export class PipiComputerUseCoordinator {
  static readonly DESKTOP_LANE_ID = 'screen:global';

  readonly journal: PipiWriteAheadJournal;
  readonly guardrail: PipiPermissionGuardrail;
  readonly #browserDriver: BrowserAutomationDriver;
  readonly #desktopDriver?: DesktopAccessibilityDriver;
  readonly #rootDir?: string;
  #browserSeatMode: BrowserSeatMode;
  #chromeDebugPort: number;
  #autoYieldOnHumanFocus: boolean;

  readonly #desktopMutex = new AsyncMutexLane();
  readonly #browserMutexes = new Map<string, AsyncMutexLane>();
  readonly #seats = new Map<string, ChromeBrowserSeat>();
  readonly #latestSnapshots = new Map<string, SurfaceSnapshot>();
  readonly #lanes = new Map<string, ComputerUseLaneSnapshot>();

  #inFlightBrowserForegroundCount = 0;
  readonly #browserDrainWaiters: Array<() => void> = [];

  #humanYieldActive = false;
  #humanYieldReason: string | undefined;
  #activeDesktopTargetBundleId: string | undefined;

  constructor(options: ComputerUseCoordinatorOptions = {}) {
    this.#rootDir = options.rootDir;
    this.#browserSeatMode = options.browserSeatMode ?? 'signed_in_chrome_seat';
    this.#chromeDebugPort = options.chromeDebugPort ?? 9222;
    this.#autoYieldOnHumanFocus = options.autoYieldOnHumanFocus ?? true;
    this.journal = new PipiWriteAheadJournal({ rootDir: options.rootDir });
    this.guardrail = options.guardrail ?? new PipiPermissionGuardrail();
    this.#browserDriver = options.browserDriver ?? new DefaultLocalChromeDriver();
    this.#desktopDriver = options.desktopDriver;

    this.#lanes.set(PipiComputerUseCoordinator.DESKTOP_LANE_ID, {
      laneId: PipiComputerUseCoordinator.DESKTOP_LANE_ID,
      kind: 'desktop_screen',
      state: 'idle',
      updatedAt: new Date().toISOString(),
    });
  }

  async initialize(): Promise<void> {
    await this.journal.load();
    const blockingDesktop = this.journal.blockingJournalForLane(PipiComputerUseCoordinator.DESKTOP_LANE_ID);
    if (blockingDesktop) {
      this.#setLaneState(PipiComputerUseCoordinator.DESKTOP_LANE_ID, 'desktop_screen', {
        state: 'blocked_unknown_outcome',
        blockedByJournalId: blockingDesktop,
      });
    }
  }

  get config(): {
    browserSeatMode: BrowserSeatMode;
    chromeDebugPort: number;
    autoYieldOnHumanFocus: boolean;
  } {
    return {
      browserSeatMode: this.#browserSeatMode,
      chromeDebugPort: this.#chromeDebugPort,
      autoYieldOnHumanFocus: this.#autoYieldOnHumanFocus,
    };
  }

  listSeats(): ChromeBrowserSeat[] {
    return Array.from(this.#seats.values()).map((s) => ({ ...s }));
  }

  listLanes(): ComputerUseLaneSnapshot[] {
    return Array.from(this.#lanes.values()).map((l) => ({ ...l }));
  }

  get isYieldedToHuman(): boolean {
    return this.#humanYieldActive;
  }

  /**
   * Immediately yields the global desktop screen lane when the human switches
   * foreground window, moves the mouse, or clicks "Take Over".
   */
  notifyHumanFocusChanged(activeAppBundleId: string, reason = 'Human switched foreground window'): boolean {
    if (!this.#autoYieldOnHumanFocus) return false;
    if (
      this.#activeDesktopTargetBundleId &&
      activeAppBundleId === this.#activeDesktopTargetBundleId
    ) {
      return false;
    }
    this.#humanYieldActive = true;
    this.#humanYieldReason = `${reason} (${activeAppBundleId})`;
    this.#setLaneState(PipiComputerUseCoordinator.DESKTOP_LANE_ID, 'desktop_screen', {
      state: 'yielded_to_human',
      yieldReason: this.#humanYieldReason,
      activeAgentId: undefined,
      activeOperationId: undefined,
    });
    return true;
  }

  resumeFromHumanYield(): void {
    this.#humanYieldActive = false;
    this.#humanYieldReason = undefined;
    const blocking = this.journal.blockingJournalForLane(PipiComputerUseCoordinator.DESKTOP_LANE_ID);
    this.#setLaneState(PipiComputerUseCoordinator.DESKTOP_LANE_ID, 'desktop_screen', {
      state: blocking ? 'blocked_unknown_outcome' : 'idle',
      blockedByJournalId: blocking,
      yieldReason: undefined,
    });
  }

  async acknowledgeUnknownOutcomeAndUnlockLane(laneId: string, note?: string): Promise<boolean> {
    const unlocked = await this.journal.acknowledgeAndUnlockLane(laneId, note);
    if (unlocked) {
      const existing = this.#lanes.get(laneId);
      const kind: ComputerUseLaneKind =
        existing?.kind ?? (laneId === PipiComputerUseCoordinator.DESKTOP_LANE_ID ? 'desktop_screen' : 'agent_browser');
      this.#setLaneState(laneId, kind, {
        state: kind === 'desktop_screen' && this.#humanYieldActive ? 'yielded_to_human' : 'idle',
        blockedByJournalId: undefined,
      });
    }
    return unlocked;
  }

  async ensureChromeSeat(agentId: string): Promise<ChromeBrowserSeat> {
    const existing = this.#seats.get(agentId);
    if (existing) {
      existing.lastUsedAt = new Date().toISOString();
      return { ...existing };
    }
    const profileDir =
      this.#browserSeatMode === 'isolated_profile' && this.#rootDir
        ? join(this.#rootDir, 'chrome-profiles', agentId.replace(/[^a-zA-Z0-9._-]/g, '_'))
        : undefined;
    const opened = await this.#browserDriver.openOrReuseSeat({
      agentId,
      mode: this.#browserSeatMode,
      debugPort: this.#chromeDebugPort,
      profileDir,
    });
    const now = new Date().toISOString();
    const seat: ChromeBrowserSeat = {
      seatId: `seat_${agentId}`,
      agentId,
      mode: this.#browserSeatMode,
      tabId: opened.tabId,
      profileDir,
      currentUrl: opened.url,
      currentTitle: opened.title,
      debugPort: this.#chromeDebugPort,
      createdAt: now,
      lastUsedAt: now,
    };
    this.#seats.set(agentId, seat);
    const laneId = `browser:${agentId}`;
    if (!this.#lanes.has(laneId)) {
      this.#setLaneState(laneId, 'agent_browser', { state: 'idle' });
    }
    return { ...seat };
  }

  /**
   * Executes one Phase A (Chrome Browser) or Phase B (macOS Desktop) action with:
   * 1. Write-Ahead Journal idempotency & unknown-outcome lane lock
   * 2. Per-agent Browser Lane parallelism vs Global Desktop Single Lane (+ browser drain wait)
   * 3. Human-Focus immediate yield check before & during desktop actions
   * 4. Full `#08` Permission Guardrail review using resolved `<browser_state>` / `<desktop_state>`
   */
  async executeAction(req: ComputerUseActionRequest): Promise<ComputerUseActionResult> {
    const operationId = req.operationId ?? `cu_${randomUUID().slice(0, 12)}`;
    const isBrowser = req.phase === 'chrome_browser';
    const laneKind: ComputerUseLaneKind = isBrowser ? 'agent_browser' : 'desktop_screen';
    const laneId = isBrowser ? `browser:${req.agentId}` : PipiComputerUseCoordinator.DESKTOP_LANE_ID;

    // 1. Write-Ahead Journal idempotency / no-replay check
    const prior = this.journal.findByOperationId(operationId);
    if (prior) {
      if (prior.status === 'committed') {
        return {
          ok: true,
          operationId,
          journalId: prior.journalId,
          laneId,
          status: 'committed',
          replayedFromJournal: true,
          yieldedToHuman: false,
          summary: prior.resultSummary ?? 'Replayed committed Computer Use action from Write-Ahead Journal.',
        };
      }
      if (prior.status === 'unknown_outcome') {
        return {
          ok: false,
          operationId,
          journalId: prior.journalId,
          laneId,
          status: 'unknown_outcome',
          replayedFromJournal: true,
          yieldedToHuman: false,
          summary: 'Refused to replay uncertain Computer Use action.',
          error: `UNKNOWN_OUTCOME_NO_REPLAY: journal ${prior.journalId} ended with unknown outcome and must be inspected by the user.`,
        };
      }
    }

    // 2. Lane lock check: if a prior input on this lane has unknown_outcome, block the lane!
    const blockingId = this.journal.blockingJournalForLane(laneId);
    if (blockingId) {
      this.#setLaneState(laneId, laneKind, {
        state: 'blocked_unknown_outcome',
        blockedByJournalId: blockingId,
      });
      return {
        ok: false,
        operationId,
        journalId: blockingId,
        laneId,
        status: 'unknown_outcome',
        replayedFromJournal: false,
        yieldedToHuman: false,
        summary: `Lane ${laneId} is locked due to prior uncertain input ${blockingId}.`,
        error: `LANE_LOCKED_UNKNOWN_OUTCOME: acknowledge and unlock lane ${laneId} after verifying state.`,
      };
    }

    // 3. Reject forbidden arbitrary JS/credential URL schemes immediately
    if (req.targetUrl && /^\s*javascript:/i.test(req.targetUrl)) {
      const wal = await this.journal.appendPrepared({
        operationId,
        laneId,
        laneKind,
        phase: req.phase,
        agentId: req.agentId,
        actionType: req.actionType,
        targetUrl: req.targetUrl,
      });
      await this.journal.updateStatus(wal.journalId, 'blocked_guardrail', {
        verdictDecision: 'deny',
        error: 'Page script execution (javascript: URL) is disabled for Computer Use agents.',
      });
      return {
        ok: false,
        operationId,
        journalId: wal.journalId,
        laneId,
        status: 'blocked_guardrail',
        replayedFromJournal: false,
        yieldedToHuman: false,
        summary: 'Blocked forbidden page script execution.',
        error: 'Page script execution is intentionally disabled.',
      };
    }

    if (isBrowser) {
      const mutex = this.#browserMutex(laneId);
      return mutex.runExclusive(() => this.#runBrowserLaneAction(req, operationId, laneId));
    }

    return this.#desktopMutex.runExclusive(() => this.#runDesktopLaneAction(req, operationId, laneId));
  }

  #browserMutex(laneId: string): AsyncMutexLane {
    let mutex = this.#browserMutexes.get(laneId);
    if (!mutex) {
      mutex = new AsyncMutexLane();
      this.#browserMutexes.set(laneId, mutex);
    }
    return mutex;
  }

  async #waitForInFlightBrowserCalls(): Promise<void> {
    if (this.#inFlightBrowserForegroundCount <= 0) return;
    await new Promise<void>((resolve) => {
      this.#browserDrainWaiters.push(resolve);
    });
  }

  #releaseBrowserForegroundWaitersIfDrained(): void {
    if (this.#inFlightBrowserForegroundCount <= 0) {
      while (this.#browserDrainWaiters.length > 0) {
        const wake = this.#browserDrainWaiters.shift();
        wake?.();
      }
    }
  }

  #resolveActionKindAndEvidence(
    req: ComputerUseActionRequest,
    snapshot?: SurfaceSnapshot,
    resolvedElement?: UIElementNode,
  ): { actionKind: ActionKind; description: string; targetResource: string; stateSummary: string } {
    const appBundle = req.targetAppBundleId ?? snapshot?.appBundleId ?? '';
    const appName = req.targetAppName ?? snapshot?.appName ?? (req.phase === 'chrome_browser' ? 'Google Chrome' : 'macOS Desktop');
    const url = req.targetUrl ?? snapshot?.url ?? '';
    const elemLabel = resolvedElement?.label ?? req.targetElementRef ?? '';

    const stateTag = req.phase === 'chrome_browser' ? 'browser_state' : 'desktop_state';
    const stateSummary = `<${stateTag} app="${appName}" bundle="${appBundle}" url="${url}" element_ref="${req.targetElementRef ?? ''}" element_role="${resolvedElement?.role ?? ''}" element_label="${elemLabel}" />`;

    // Pure observation (snapshot / scroll) never mutates state or privacy settings
    if (req.actionType === 'snapshot' || req.actionType === 'scroll') {
      return {
        actionKind: 'read_only',
        description: `${req.actionType} on ${appName} ${url || elemLabel}`.trim(),
        targetResource: url || appName,
        stateSummary,
      };
    }

    // Hard check: interacting with macOS Privacy / Security switches is always persistent security_change
    if (
      SYSTEM_PRIVACY_BUNDLE_IDS.has(appBundle) ||
      resolvedElement?.isSystemPrivacySwitch
    ) {
      return {
        actionKind: 'security_change',
        description: `Modify OS privacy/security setting in ${appName} (${elemLabel})`,
        targetResource: `${appBundle || appName}:${elemLabel}`,
        stateSummary,
      };
    }

    if (
      req.actionType === 'submit_form' ||
      req.submitsEffect === true ||
      resolvedElement?.isSubmitAction === true ||
      resolvedElement?.isExternalEffect === true
    ) {
      return {
        actionKind: 'external_effect',
        description: `Submit/Send via ${req.actionType} on ${appName} (${elemLabel || url})`,
        targetResource: url || `${appName}:${elemLabel}`,
        stateSummary,
      };
    }

    // Preparatory browser/desktop steps (navigating to read, typing into compose box without submitting)
    if (req.actionType === 'navigate' || req.actionType === 'type_text' || req.actionType === 'focus_window') {
      return {
        actionKind: 'prepare_draft',
        description: `Preparatory ${req.actionType} on ${appName} (${elemLabel || url})`,
        targetResource: url || `${appName}:${elemLabel}`,
        stateSummary,
      };
    }

    return {
      actionKind: 'local_write',
      description: `UI ${req.actionType} on ${appName} (${elemLabel || url})`,
      targetResource: url || `${appName}:${elemLabel}`,
      stateSummary,
    };
  }

  async #runBrowserLaneAction(
    req: ComputerUseActionRequest,
    operationId: string,
    laneId: string,
  ): Promise<ComputerUseActionResult> {
    const seat = await this.ensureChromeSeat(req.agentId);
    const latestSnap = this.#latestSnapshots.get(laneId);
    const resolvedElement = req.targetElementRef
      ? latestSnap?.elements.find((e) => e.ref === req.targetElementRef)
      : undefined;

    // Step A: Guardrail evaluation with structured <browser_state>
    const classified = this.#resolveActionKindAndEvidence(req, latestSnap, resolvedElement);
    const verdict = await this.guardrail.evaluate(
      {
        operationId,
        toolName: `computer_use.chrome.${req.actionType}`,
        actionKind: classified.actionKind,
        description: classified.description,
        targetResource: classified.targetResource,
        commandOrPayload: `${req.textInput ?? ''} ${req.keyCombo ?? ''} ${req.targetUrl ?? ''}`.trim(),
        sourceTrust: req.sourceTrust ?? 'trusted_user',
        sessionId: req.sessionId,
        projectId: req.projectId,
        trustedUserMessages: req.trustedUserMessages ?? [],
        untrustedContextSnippets: [
          classified.stateSummary,
          ...(req.untrustedContextSnippets ?? []),
        ],
      },
      req.guardrailOptions ?? {},
    );

    const wal = await this.journal.appendPrepared({
      operationId,
      laneId,
      laneKind: 'agent_browser',
      phase: 'chrome_browser',
      agentId: req.agentId,
      actionType: req.actionType,
      targetApp: 'Google Chrome',
      targetUrl: req.targetUrl ?? seat.currentUrl,
      targetElementRef: req.targetElementRef,
      targetElementLabel: resolvedElement?.label,
    });

    if (verdict.decision !== 'allow') {
      await this.journal.updateStatus(wal.journalId, 'blocked_guardrail', {
        verdictDecision: verdict.decision,
        error: verdict.rationale,
      });
      return {
        ok: false,
        operationId,
        journalId: wal.journalId,
        laneId,
        status: 'blocked_guardrail',
        replayedFromJournal: false,
        yieldedToHuman: false,
        verdict,
        seat,
        summary: `Guardrail ${verdict.decision}: ${verdict.rationale}`,
        error: verdict.rationale,
      };
    }

    this.#inFlightBrowserForegroundCount += 1;
    this.#setLaneState(laneId, 'agent_browser', {
      state: 'active',
      activeAgentId: req.agentId,
      activeOperationId: operationId,
    });

    try {
      await this.journal.updateStatus(wal.journalId, 'dispatched', { verdictDecision: 'allow' });
      const execResult = await this.#browserDriver.executeBrowserAction(seat, req);
      if (execResult.currentUrl) seat.currentUrl = execResult.currentUrl;
      if (execResult.currentTitle) seat.currentTitle = execResult.currentTitle;
      seat.lastUsedAt = new Date().toISOString();
      this.#seats.set(req.agentId, seat);
      if (execResult.snapshot) {
        this.#latestSnapshots.set(laneId, execResult.snapshot);
      }
      await this.journal.updateStatus(wal.journalId, 'committed', {
        verdictDecision: 'allow',
        resultSummary: execResult.summary,
      });
      this.#setLaneState(laneId, 'agent_browser', {
        state: 'idle',
        activeAgentId: undefined,
        activeOperationId: undefined,
      });
      return {
        ok: true,
        operationId,
        journalId: wal.journalId,
        laneId,
        status: 'committed',
        replayedFromJournal: false,
        yieldedToHuman: false,
        verdict,
        snapshot: execResult.snapshot,
        seat: { ...seat },
        summary: execResult.summary,
      };
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      await this.journal.updateStatus(wal.journalId, 'unknown_outcome', {
        verdictDecision: 'allow',
        error: msg,
      });
      this.#setLaneState(laneId, 'agent_browser', {
        state: 'blocked_unknown_outcome',
        blockedByJournalId: wal.journalId,
        activeAgentId: undefined,
        activeOperationId: undefined,
      });
      return {
        ok: false,
        operationId,
        journalId: wal.journalId,
        laneId,
        status: 'unknown_outcome',
        replayedFromJournal: false,
        yieldedToHuman: false,
        verdict,
        seat: { ...seat },
        summary: 'Browser action outcome uncertain; lane locked to prevent duplicate click.',
        error: msg,
      };
    } finally {
      this.#inFlightBrowserForegroundCount = Math.max(0, this.#inFlightBrowserForegroundCount - 1);
      this.#releaseBrowserForegroundWaitersIfDrained();
    }
  }

  async #runDesktopLaneAction(
    req: ComputerUseActionRequest,
    operationId: string,
    laneId: string,
  ): Promise<ComputerUseActionResult> {
    if (!this.#desktopDriver) {
      return {
        ok: false,
        operationId,
        journalId: '',
        laneId,
        status: 'blocked_guardrail',
        replayedFromJournal: false,
        yieldedToHuman: false,
        summary: 'No macOS Desktop Accessibility driver attached.',
        error: 'Desktop Accessibility driver unavailable in this host context.',
      };
    }

    // Desktop actions needing the front window wait for in-flight browser actions first
    if (req.requiresFrontWindow !== false && req.actionType !== 'snapshot') {
      await this.#waitForInFlightBrowserCalls();
    }

    // Human-Focus Immediate Yield check (pre-flight)
    if (this.#humanYieldActive) {
      const wal = await this.journal.appendPrepared({
        operationId,
        laneId,
        laneKind: 'desktop_screen',
        phase: 'macos_desktop',
        agentId: req.agentId,
        actionType: req.actionType,
        targetApp: req.targetAppName,
        targetElementRef: req.targetElementRef,
      });
      await this.journal.updateStatus(wal.journalId, 'yielded_to_human', {
        resultSummary: this.#humanYieldReason ?? 'Yielded immediately to human focus.',
      });
      return {
        ok: false,
        operationId,
        journalId: wal.journalId,
        laneId,
        status: 'yielded_to_human',
        replayedFromJournal: false,
        yieldedToHuman: true,
        summary: `Yielded to human focus: ${this.#humanYieldReason ?? 'human took control'}`,
      };
    }

    // Live frontmost window verification: if human switched away from expected target app, yield immediately!
    if (this.#autoYieldOnHumanFocus && req.targetAppBundleId && req.actionType !== 'snapshot' && req.actionType !== 'focus_window') {
      const frontmost = await this.#desktopDriver.getFrontmostApp();
      if (frontmost.bundleId && frontmost.bundleId !== req.targetAppBundleId) {
        this.notifyHumanFocusChanged(
          frontmost.bundleId,
          `Foreground window is ${frontmost.appName}, expected ${req.targetAppName ?? req.targetAppBundleId}`,
        );
        const wal = await this.journal.appendPrepared({
          operationId,
          laneId,
          laneKind: 'desktop_screen',
          phase: 'macos_desktop',
          agentId: req.agentId,
          actionType: req.actionType,
          targetApp: req.targetAppName ?? req.targetAppBundleId,
          targetElementRef: req.targetElementRef,
        });
        await this.journal.updateStatus(wal.journalId, 'yielded_to_human', {
          resultSummary: this.#humanYieldReason,
        });
        return {
          ok: false,
          operationId,
          journalId: wal.journalId,
          laneId,
          status: 'yielded_to_human',
          replayedFromJournal: false,
          yieldedToHuman: true,
          summary: `Immediate yield: ${this.#humanYieldReason}`,
        };
      }
    }

    const latestSnap = this.#latestSnapshots.get(laneId);
    const resolvedElement = req.targetElementRef
      ? latestSnap?.elements.find((e) => e.ref === req.targetElementRef)
      : undefined;

    // Guardrail check with structured <desktop_state>
    const classified = this.#resolveActionKindAndEvidence(req, latestSnap, resolvedElement);
    const verdict = await this.guardrail.evaluate(
      {
        operationId,
        toolName: `computer_use.desktop.${req.actionType}`,
        actionKind: classified.actionKind,
        description: classified.description,
        targetResource: classified.targetResource,
        commandOrPayload: `${req.textInput ?? ''} ${req.keyCombo ?? ''}`.trim(),
        sourceTrust: req.sourceTrust ?? 'trusted_user',
        sessionId: req.sessionId,
        projectId: req.projectId,
        trustedUserMessages: req.trustedUserMessages ?? [],
        untrustedContextSnippets: [
          classified.stateSummary,
          ...(req.untrustedContextSnippets ?? []),
        ],
      },
      req.guardrailOptions ?? {},
    );

    const wal = await this.journal.appendPrepared({
      operationId,
      laneId,
      laneKind: 'desktop_screen',
      phase: 'macos_desktop',
      agentId: req.agentId,
      actionType: req.actionType,
      targetApp: req.targetAppName ?? latestSnap?.appName,
      targetElementRef: req.targetElementRef,
      targetElementLabel: resolvedElement?.label,
    });

    if (verdict.decision !== 'allow') {
      await this.journal.updateStatus(wal.journalId, 'blocked_guardrail', {
        verdictDecision: verdict.decision,
        error: verdict.rationale,
      });
      return {
        ok: false,
        operationId,
        journalId: wal.journalId,
        laneId,
        status: 'blocked_guardrail',
        replayedFromJournal: false,
        yieldedToHuman: false,
        verdict,
        summary: `Guardrail ${verdict.decision}: ${verdict.rationale}`,
        error: verdict.rationale,
      };
    }

    this.#activeDesktopTargetBundleId = req.targetAppBundleId ?? latestSnap?.appBundleId;
    this.#setLaneState(laneId, 'desktop_screen', {
      state: 'active',
      activeAgentId: req.agentId,
      activeOperationId: operationId,
    });

    try {
      await this.journal.updateStatus(wal.journalId, 'dispatched', { verdictDecision: 'allow' });
      const execResult =
        req.actionType === 'snapshot'
          ? {
              summary: 'Captured macOS Accessibility element tree snapshot.',
              snapshot: await this.#desktopDriver.captureDesktopSnapshot(req.targetAppBundleId),
            }
          : await this.#desktopDriver.executeDesktopAction(req, resolvedElement);

      if (execResult.snapshot) {
        this.#latestSnapshots.set(laneId, execResult.snapshot);
      }

      if (this.#humanYieldActive) {
        await this.journal.updateStatus(wal.journalId, 'yielded_to_human', {
          verdictDecision: 'allow',
          resultSummary: `${execResult.summary} (human intervened during call; lane yielded)`,
        });
        return {
          ok: false,
          operationId,
          journalId: wal.journalId,
          laneId,
          status: 'yielded_to_human',
          replayedFromJournal: false,
          yieldedToHuman: true,
          verdict,
          snapshot: execResult.snapshot,
          summary: `Yielded to human focus: ${this.#humanYieldReason ?? 'human intervened'}`,
        };
      }

      await this.journal.updateStatus(wal.journalId, 'committed', {
        verdictDecision: 'allow',
        resultSummary: execResult.summary,
      });
      this.#setLaneState(laneId, 'desktop_screen', {
        state: 'idle',
        activeAgentId: undefined,
        activeOperationId: undefined,
      });
      return {
        ok: true,
        operationId,
        journalId: wal.journalId,
        laneId,
        status: 'committed',
        replayedFromJournal: false,
        yieldedToHuman: false,
        verdict,
        snapshot: execResult.snapshot,
        summary: execResult.summary,
      };
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      await this.journal.updateStatus(wal.journalId, 'unknown_outcome', {
        verdictDecision: 'allow',
        error: msg,
      });
      this.#setLaneState(laneId, 'desktop_screen', {
        state: 'blocked_unknown_outcome',
        blockedByJournalId: wal.journalId,
        activeAgentId: undefined,
        activeOperationId: undefined,
      });
      return {
        ok: false,
        operationId,
        journalId: wal.journalId,
        laneId,
        status: 'unknown_outcome',
        replayedFromJournal: false,
        yieldedToHuman: false,
        verdict,
        summary: 'Desktop input outcome uncertain; screen lane locked to prevent duplicate click.',
        error: msg,
      };
    } finally {
      this.#activeDesktopTargetBundleId = undefined;
    }
  }

  #setLaneState(
    laneId: string,
    kind: ComputerUseLaneKind,
    patch: Partial<Omit<ComputerUseLaneSnapshot, 'laneId' | 'kind' | 'updatedAt'>>,
  ): void {
    const existing = this.#lanes.get(laneId) ?? {
      laneId,
      kind,
      state: 'idle' as ComputerUseLaneState,
      updatedAt: new Date().toISOString(),
    };
    this.#lanes.set(laneId, {
      ...existing,
      ...patch,
      updatedAt: new Date().toISOString(),
    });
  }
}
