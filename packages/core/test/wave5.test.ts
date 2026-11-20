/**
 * packages/core/test/wave5.test.ts
 *
 * Deterministic offline verification suite for Wave 5 (#09 Dual-Phase Computer Use):
 * - Phase A: Signed-in Chrome per-agent Seats/Tabs, parallel browser lanes,
 *   preparatory draft allow vs external submit guardrail approval, forbidden page-script block.
 * - Phase B: macOS Accessibility/Cua single global desktop lane, waiting for in-flight
 *   browser calls, OS privacy switch protection, and immediate Human-Focus Yield.
 * - Write-Ahead Journal (WAL): anti-double-click idempotency, crash/error `unknown_outcome`
 *   lane lock (refuses duplicate clicks), and explicit human review/unlock (plus CLI exposure).
 */

import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import {
  PipiComputerUseCoordinator,
  type BrowserAutomationDriver,
  type ChromeBrowserSeat,
  type ComputerUseActionRequest,
  type DesktopAccessibilityDriver,
  type SurfaceSnapshot,
  type UIElementNode,
} from '../src/computer-use.ts';
import { runPipiBotCli } from '../src/pipibot-cli.ts';

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

test('Wave 5 (#09a Phase A): Per-agent Chrome Seats run in parallel, preparatory draft passes & external submit requires #08 approval', async () => {
  const rootDir = await mkdtemp(join(tmpdir(), 'pipibot-wave5-a-'));
  let activeParallel = 0;
  let maxObservedParallel = 0;

  const mockChrome: BrowserAutomationDriver = {
    async probeSignedInChrome() {
      return { reachable: true, browserVersion: 'Chrome/142.0' };
    },
    async openOrReuseSeat({ agentId }) {
      return { tabId: `tab_${agentId}`, url: 'https://mail.example.com/compose', title: 'Compose Mail' };
    },
    async executeBrowserAction(seat: ChromeBrowserSeat, req: ComputerUseActionRequest) {
      activeParallel += 1;
      maxObservedParallel = Math.max(maxObservedParallel, activeParallel);
      await sleep(30);
      activeParallel -= 1;

      const snapshot: SurfaceSnapshot = {
        phase: 'chrome_browser',
        capturedAt: new Date().toISOString(),
        appName: 'Google Chrome',
        appBundleId: 'com.google.Chrome',
        windowTitle: 'Compose Mail',
        url: req.targetUrl ?? seat.currentUrl,
        seatId: seat.seatId,
        elements: [
          { ref: 'el_body', role: 'textbox', label: 'Message Body', enabled: true },
          { ref: 'el_send', role: 'button', label: 'Send Email', enabled: true, isSubmitAction: true, isExternalEffect: true },
        ],
      };
      return {
        summary: `Chrome ${req.actionType} ok on ${seat.seatId}`,
        snapshot,
        currentUrl: snapshot.url,
        currentTitle: snapshot.windowTitle,
      };
    },
  };

  try {
    const cu = new PipiComputerUseCoordinator({
      rootDir,
      browserSeatMode: 'signed_in_chrome_seat',
      browserDriver: mockChrome,
    });
    await cu.initialize();

    // 1. Two agents execute on separate per-agent browser lanes CONCURRENTLY!
    const [r1, r2] = await Promise.all([
      cu.executeAction({
        agentId: 'bot_coder',
        phase: 'chrome_browser',
        actionType: 'snapshot',
      }),
      cu.executeAction({
        agentId: 'bot_writer',
        phase: 'chrome_browser',
        actionType: 'snapshot',
      }),
    ]);
    assert.equal(r1.ok, true);
    assert.equal(r2.ok, true);
    assert.equal(maxObservedParallel, 2, 'Two agents must run concurrently in independent Chrome Seat lanes');
    assert.equal(cu.listSeats().length, 2);
    assert.notEqual(r1.seat?.tabId, r2.seat?.tabId);

    // 2. Preparatory typing into compose box (NOT submitting) is allowed smoothly
    const draftRes = await cu.executeAction({
      agentId: 'bot_coder',
      phase: 'chrome_browser',
      actionType: 'type_text',
      targetElementRef: 'el_body',
      textInput: 'Drafting update for tomorrow.',
    });
    assert.equal(draftRes.ok, true);
    assert.equal(draftRes.status, 'committed');

    // 3. Clicking the resolved `Send Email` button (isExternalEffect=true) triggers #08 Guardrail needs_approval!
    const sendRes = await cu.executeAction({
      agentId: 'bot_coder',
      phase: 'chrome_browser',
      actionType: 'click',
      targetElementRef: 'el_send',
      trustedUserMessages: ['Check my inbox and draft a reply'],
    });
    assert.equal(sendRes.ok, false);
    assert.equal(sendRes.status, 'blocked_guardrail');
    assert.equal(sendRes.verdict?.decision, 'needs_approval');

    // 4. Forbidden arbitrary page script (`javascript:` URL) is hard-blocked
    const jsRes = await cu.executeAction({
      agentId: 'bot_coder',
      phase: 'chrome_browser',
      actionType: 'navigate',
      targetUrl: 'javascript:alert(document.cookie)',
    });
    assert.equal(jsRes.ok, false);
    assert.equal(jsRes.status, 'blocked_guardrail');
  } finally {
    await rm(rootDir, { recursive: true, force: true });
  }
});

test('Wave 5 (#09b Phase B): Desktop single lane waits for browser, yields immediately to human focus & blocks OS privacy switches', async () => {
  const rootDir = await mkdtemp(join(tmpdir(), 'pipibot-wave5-b-'));
  const timeline: string[] = [];
  let currentFrontmost = { appName: 'Notes', bundleId: 'com.apple.Notes', windowTitle: 'Daily Notes' };
  let activeDesktopCount = 0;
  let maxDesktopConcurrent = 0;

  const mockChrome: BrowserAutomationDriver = {
    async probeSignedInChrome() {
      return { reachable: true };
    },
    async openOrReuseSeat({ agentId }) {
      return { tabId: `tab_${agentId}`, url: 'https://docs.example.com', title: 'Docs' };
    },
    async executeBrowserAction(seat) {
      timeline.push('browser:start');
      await sleep(45);
      timeline.push('browser:end');
      return { summary: `ok ${seat.seatId}` };
    },
  };

  const mockDesktop: DesktopAccessibilityDriver = {
    async checkAccessibilityTrusted() {
      return true;
    },
    async getFrontmostApp() {
      return { ...currentFrontmost };
    },
    async captureDesktopSnapshot(targetAppBundleId?: string) {
      const isSysSettings = targetAppBundleId === 'com.apple.systempreferences';
      return {
        phase: 'macos_desktop',
        capturedAt: new Date().toISOString(),
        appName: isSysSettings ? 'System Settings' : 'Notes',
        appBundleId: isSysSettings ? 'com.apple.systempreferences' : 'com.apple.Notes',
        windowTitle: isSysSettings ? 'Privacy & Security' : 'Daily Notes',
        elements: isSysSettings
          ? [{ ref: 'ax_fda', role: 'AXCheckBox', label: 'Full Disk Access', enabled: true, isSystemPrivacySwitch: true }]
          : [{ ref: 'ax_note_area', role: 'AXTextArea', label: 'Note Body', enabled: true }],
      };
    },
    async executeDesktopAction(req: ComputerUseActionRequest, elem?: UIElementNode) {
      activeDesktopCount += 1;
      maxDesktopConcurrent = Math.max(maxDesktopConcurrent, activeDesktopCount);
      timeline.push(`desktop:start:${req.operationId ?? req.actionType}`);
      await sleep(20);
      timeline.push(`desktop:end:${req.operationId ?? req.actionType}`);
      activeDesktopCount -= 1;
      return { summary: `Desktop ${req.actionType} on ${elem?.label ?? req.targetAppName}` };
    },
  };

  try {
    const cu = new PipiComputerUseCoordinator({
      rootDir,
      browserDriver: mockChrome,
      desktopDriver: mockDesktop,
      autoYieldOnHumanFocus: true,
    });
    await cu.initialize();

    // 1. Start a browser call, then issue two desktop calls: desktop MUST wait for browser to finish AND serialize to 1 at a time!
    const browserPromise = cu.executeAction({
      agentId: 'bot_browser',
      phase: 'chrome_browser',
      actionType: 'click',
      operationId: 'op_browser_1',
    });
    await sleep(5);
    const desk1Promise = cu.executeAction({
      agentId: 'bot_desk_a',
      phase: 'macos_desktop',
      actionType: 'type_text',
      targetAppName: 'Notes',
      targetAppBundleId: 'com.apple.Notes',
      textInput: 'Line 1',
      operationId: 'op_desk_1',
    });
    const desk2Promise = cu.executeAction({
      agentId: 'bot_desk_b',
      phase: 'macos_desktop',
      actionType: 'type_text',
      targetAppName: 'Notes',
      targetAppBundleId: 'com.apple.Notes',
      textInput: 'Line 2',
      operationId: 'op_desk_2',
    });

    const [bRes, d1, d2] = await Promise.all([browserPromise, desk1Promise, desk2Promise]);
    assert.equal(bRes.ok, true);
    assert.equal(d1.ok, true);
    assert.equal(d2.ok, true);
    assert.equal(maxDesktopConcurrent, 1, 'Global desktop screen lane must strictly allow 1 action at a time');
    assert.ok(
      timeline.indexOf('browser:end') < timeline.indexOf('desktop:start:op_desk_1'),
      `Desktop action must wait for in-flight browser call; timeline=${JSON.stringify(timeline)}`,
    );

    // 2. Human switches foreground app to Safari -> desktop lane IMMEDIATELY yields without touching input!
    currentFrontmost = { appName: 'Safari', bundleId: 'com.apple.Safari', windowTitle: 'Banking' };
    const yieldedRes = await cu.executeAction({
      agentId: 'bot_desk_a',
      phase: 'macos_desktop',
      actionType: 'click',
      targetAppName: 'Notes',
      targetAppBundleId: 'com.apple.Notes',
    });
    assert.equal(yieldedRes.ok, false);
    assert.equal(yieldedRes.yieldedToHuman, true);
    assert.equal(yieldedRes.status, 'yielded_to_human');
    assert.equal(cu.isYieldedToHuman, true);

    // Resume after human hands control back
    currentFrontmost = { appName: 'System Settings', bundleId: 'com.apple.systempreferences', windowTitle: 'Privacy & Security' };
    cu.resumeFromHumanYield();
    assert.equal(cu.isYieldedToHuman, false);

    // 3. Attempting to click OS System Settings Privacy switch requires explicit guardrail protection!
    const snapSys = await cu.executeAction({
      agentId: 'bot_desk_a',
      phase: 'macos_desktop',
      actionType: 'snapshot',
      targetAppBundleId: 'com.apple.systempreferences',
    });
    assert.equal(snapSys.ok, true);
    const privacyClick = await cu.executeAction({
      agentId: 'bot_desk_a',
      phase: 'macos_desktop',
      actionType: 'click',
      targetAppName: 'System Settings',
      targetAppBundleId: 'com.apple.systempreferences',
      targetElementRef: 'ax_fda',
    });
    assert.equal(privacyClick.ok, false);
    assert.equal(privacyClick.status, 'blocked_guardrail');
    assert.equal(privacyClick.verdict?.decision, 'needs_approval');
  } finally {
    await rm(rootDir, { recursive: true, force: true });
  }
});

test('Wave 5 (#09c WAL): Anti-double-click idempotency, unknown_outcome lane lock & human unlock (with CLI)', async () => {
  const rootDir = await mkdtemp(join(tmpdir(), 'pipibot-wave5-wal-'));
  let actualClicks = 0;
  let shouldCrashNext = false;

  const mockDesktop: DesktopAccessibilityDriver = {
    async checkAccessibilityTrusted() {
      return true;
    },
    async getFrontmostApp() {
      return { appName: 'Notes', bundleId: 'com.apple.Notes', windowTitle: 'Draft' };
    },
    async captureDesktopSnapshot() {
      return {
        phase: 'macos_desktop',
        capturedAt: new Date().toISOString(),
        appName: 'Notes',
        appBundleId: 'com.apple.Notes',
        windowTitle: 'Draft',
        elements: [{ ref: 'ax_save', role: 'AXButton', label: 'Save Draft', enabled: true }],
      };
    },
    async executeDesktopAction() {
      if (shouldCrashNext) {
        throw new Error('AX bridge disconnected mid-click');
      }
      actualClicks += 1;
      return { summary: `Clicked #${actualClicks}` };
    },
  };

  try {
    const cu = new PipiComputerUseCoordinator({ rootDir, desktopDriver: mockDesktop });
    await cu.initialize();

    // 1. Committed action retried with same operationId MUST NOT click twice!
    const first = await cu.executeAction({
      operationId: 'op_save_once',
      agentId: 'bot_coder',
      phase: 'macos_desktop',
      actionType: 'click',
      targetAppName: 'Notes',
      targetAppBundleId: 'com.apple.Notes',
      targetElementRef: 'ax_save',
    });
    assert.equal(first.ok, true);
    assert.equal(first.replayedFromJournal, false);
    assert.equal(actualClicks, 1);

    const retry = await cu.executeAction({
      operationId: 'op_save_once',
      agentId: 'bot_coder',
      phase: 'macos_desktop',
      actionType: 'click',
      targetAppName: 'Notes',
      targetAppBundleId: 'com.apple.Notes',
      targetElementRef: 'ax_save',
    });
    assert.equal(retry.ok, true);
    assert.equal(retry.replayedFromJournal, true);
    assert.equal(actualClicks, 1, 'WAL must prevent duplicate physical clicks for same operationId');

    // 2. Crash mid-dispatch records `unknown_outcome` and LOCKS the entire screen lane!
    shouldCrashNext = true;
    const crashed = await cu.executeAction({
      operationId: 'op_uncertain_click',
      agentId: 'bot_coder',
      phase: 'macos_desktop',
      actionType: 'click',
      targetAppName: 'Notes',
      targetAppBundleId: 'com.apple.Notes',
      targetElementRef: 'ax_save',
    });
    assert.equal(crashed.ok, false);
    assert.equal(crashed.status, 'unknown_outcome');

    // Retrying the uncertain operationId is strictly refused (no replay!)
    shouldCrashNext = false;
    const refuseReplay = await cu.executeAction({
      operationId: 'op_uncertain_click',
      agentId: 'bot_coder',
      phase: 'macos_desktop',
      actionType: 'click',
      targetAppName: 'Notes',
      targetAppBundleId: 'com.apple.Notes',
      targetElementRef: 'ax_save',
    });
    assert.equal(refuseReplay.ok, false);
    assert.ok(refuseReplay.error?.includes('UNKNOWN_OUTCOME_NO_REPLAY'));

    // Even a brand new action on the locked lane is blocked until human acknowledges!
    const blockedNew = await cu.executeAction({
      operationId: 'op_next_after_crash',
      agentId: 'bot_coder',
      phase: 'macos_desktop',
      actionType: 'click',
      targetAppName: 'Notes',
      targetAppBundleId: 'com.apple.Notes',
      targetElementRef: 'ax_save',
    });
    assert.equal(blockedNew.ok, false);
    assert.ok(blockedNew.error?.includes('LANE_LOCKED_UNKNOWN_OUTCOME'));

    // 3. CLI `computer journal` inspects the locked lane and `computer unlock-lane` unlocks it!
    const cliJournal = await runPipiBotCli(['computer', 'journal', '--data-dir', rootDir]);
    assert.equal(cliJournal.exitCode, 0);
    assert.ok(cliJournal.stdout.includes('blocked_unknown_outcome'));

    const cliUnlock = await runPipiBotCli([
      'computer',
      'unlock-lane',
      '--lane',
      'screen:global',
      '--note',
      'Verified Notes window manually',
      '--data-dir',
      rootDir,
    ]);
    assert.equal(cliUnlock.exitCode, 0);
    assert.ok(cliUnlock.stdout.includes('"unlocked": true'));

    // Reload coordinator from disk and confirm lane is now unlocked and accepts new action!
    const cuReloaded = new PipiComputerUseCoordinator({ rootDir, desktopDriver: mockDesktop });
    await cuReloaded.initialize();
    const afterUnlock = await cuReloaded.executeAction({
      operationId: 'op_after_human_unlock',
      agentId: 'bot_coder',
      phase: 'macos_desktop',
      actionType: 'click',
      targetAppName: 'Notes',
      targetAppBundleId: 'com.apple.Notes',
      targetElementRef: 'ax_save',
    });
    assert.equal(afterUnlock.ok, true);
    assert.equal(actualClicks, 2);
  } finally {
    await rm(rootDir, { recursive: true, force: true });
  }
});
