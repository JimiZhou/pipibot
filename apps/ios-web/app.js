/**
 * PipiBot Companion PWA & Stageshow Live Controller
 * Connects to @pipibot/daemon (/api/v1/* + SSE /api/v1/events) with automatic
 * offline fallback so every view works both live and in static preview.
 */

const avatarModuleUrl =
  typeof window !== 'undefined' && window.location.pathname.startsWith('/ios')
    ? '/design-system/pipibot-avatar.js'
    : '../../design-system/pipibot-avatar.js';

function createSeedState() {
  return {
    liveDaemon: false,
    apiBase: '',
    theme: 'dark',
    activeTab: 'outcomes',
    selectedHarness: 'pi',
    avatarState: 'ambient-breathe',
    avatarExpression: 'happy',
    voiceListening: false,
    cloudflare: {
      tunnelConnected: true,
      tunnelRttMs: 18,
      tunnelUrl: 'https://pipibot-mac.trycloudflare.com',
      freeTierCostUsd: 0,
    },
    understandingScore: {
      overall: 94.2,
      deltaFromPrevious: 1.4,
    },
    outcomes: [
      {
        id: 'out-layout',
        title: 'Layout Guardian Bot',
        domain: 'dev',
        goal: 'Keep checkout CLS <= 0.02 across mobile & desktop via 3h Playwright audits.',
        preferredHarness: 'claude-code',
        status: 'needs_you',
        dailyBudgetUsd: 3.0,
        spentTodayUsd: 0.48,
      },
      {
        id: 'out-vps',
        title: 'HK VPS Zero-Downtime Watch',
        domain: 'infra',
        goal: 'Monitor nginx upstream 502 rate, TLS expiry, and Docker container memory.',
        preferredHarness: 'codex',
        status: 'active',
        dailyBudgetUsd: 2.0,
        spentTodayUsd: 0.14,
      },
      {
        id: 'out-travel',
        title: 'Tokyo NH962 Travel & Calendar Sync',
        domain: 'daily_life',
        goal: 'Extract boarding passes, calendar holds, and evening gym blocks automatically.',
        preferredHarness: 'pi',
        status: 'active',
        dailyBudgetUsd: 1.0,
        spentTodayUsd: 0.05,
      },
    ],
    decisions: [
      {
        id: 'dec-pr42',
        severity: 'warning',
        category: 'code_merge_or_push',
        title: 'Approve PR #42 — Checkout CLS Regression Fix',
        summary: 'Child session patched skeleton container height and verified 14/14 assertions.',
        recommendedOptionId: 'approve',
        options: [
          { id: 'approve', label: 'Approve & Merge', style: 'primary' },
          { id: 'steer', label: 'Steer', style: 'secondary' },
          { id: 'reject', label: 'Defer', style: 'destructive' },
        ],
        evidence: [
          {
            artifactId: 'art-cls-42',
            r2Key: 'r2://pipibot-artifacts/pr-42-diff.mp4',
            kind: 'video',
            caption: 'Before CLS 0.34 -> After CLS 0.01 (1080p Playwright capture)',
          },
        ],
        status: 'pending',
      },
      {
        id: 'dec-nginx',
        severity: 'critical',
        category: 'infra_mutation',
        title: 'Reload HK VPS Nginx Keepalive Pool',
        summary: 'Codex isolated 1.8% 502 spikes to upstream keepalive=15s timeout.',
        recommendedOptionId: 'approve',
        options: [
          { id: 'approve', label: 'Reload Safely', style: 'primary' },
          { id: 'reject', label: 'Hold', style: 'destructive' },
        ],
        evidence: [
          {
            artifactId: 'art-vps-trace',
            r2Key: 'r2://pipibot-artifacts/nginx-diff.patch',
            kind: 'diff_patch',
            caption: 'keepalive_timeout 15s -> 65s · nginx -t passed',
          },
        ],
        status: 'pending',
      },
      {
        id: 'dec-dream',
        severity: 'info',
        category: 'memory_evolution_review',
        title: 'Merge Nightly Dream Diff (+2 Facts, +1 Skill)',
        summary: 'Learned strict zero-runtime-dep TypeScript preference and cf-tunnel-heal skill.',
        recommendedOptionId: 'approve',
        options: [
          { id: 'approve', label: 'Merge Diff', style: 'primary' },
          { id: 'reject', label: 'Discard', style: 'destructive' },
        ],
        evidence: [
          {
            artifactId: 'art-mem-diff',
            r2Key: 'local://~/.pipibot/evolution/nightly.diff',
            kind: 'log_excerpt',
            caption: 'Understanding Score 92.8% -> 94.2%',
          },
        ],
        status: 'pending',
      },
    ],
    cue: {
      id: 'cue-demo-1',
      activeAppName: 'Xcode',
      windowTitle: 'PipiHost.swift',
      detectedIntent: 'SwiftUI snapshot tests untouched since last edit; run Pi + Xcode MCP suite.',
      actions: [
        { id: 'run-tests', label: 'Run Tests', harness: 'pi', promptTemplate: 'Run SwiftUI regression suite' },
      ],
    },
    nodes: [
      { nodeId: 'mac-resident', displayName: 'Mac Studio Host', kind: 'mac', vitality: 'alive', cpuLoadPct: 14, memoryUsedPct: 46, tunnelRttMs: 2 },
      { nodeId: 'ios-companion', displayName: 'iPhone 16 Pro', kind: 'ios', vitality: 'alive', cpuLoadPct: 8, memoryUsedPct: 38, tunnelRttMs: 18 },
      { nodeId: 'vps-hk-01', displayName: 'HK Edge VPS', kind: 'vps', vitality: 'busy', cpuLoadPct: 42, memoryUsedPct: 54, tunnelRttMs: 34 },
      { nodeId: 'win-wsl2', displayName: 'Win11 WSL2 Box', kind: 'windows', vitality: 'alive', cpuLoadPct: 19, memoryUsedPct: 51, tunnelRttMs: 14 },
      { nodeId: 'esp32-home', displayName: 'Home ESP32 MQTT', kind: 'embedded', vitality: 'alive', cpuLoadPct: 6, memoryUsedPct: 29, tunnelRttMs: 9 },
    ],
    chatMessages: [
      { role: 'assistant', provider: 'pi', text: 'PipiCore ready with 4 core tools + 4-Tier Memory recall. Switch harnesses anytime via the header or sheet.' },
    ],
    memory: {
      facts: [
        { id: 'fact-1', subject: 'user', predicate: 'prefers_runtime', objectValue: 'Zero external deps in TypeScript core & protocol', confidence: 0.96 },
        { id: 'fact-2', subject: 'user', predicate: 'gym_schedule', objectValue: 'Tue/Thu 19:30-21:00 DND for non-urgent alerts', confidence: 0.91 },
      ],
      skills: [
        { slug: 'cf-tunnel-heal', name: 'Cloudflare Tunnel Auto-Heal', successRate: 0.98, occurrences: 6 },
      ],
      lastDigest: {
        digestId: 'dig-demo',
        diffs: [
          {
            diffId: 'diff-1',
            operation: 'add',
            targetFile: 'USER.md',
            title: 'Zero raw hex in UI components',
            proposedValue: 'Always bind CSS/SwiftUI views to 3-tier design tokens.',
            reviewStatus: 'pending',
          },
        ],
      },
      soulPreview: '# SOUL.md\nAmbient Soul & Outcome Studio: calm until decisive, evidence over raw logs.',
    },
  };
}

function escapeHtml(str) {
  return String(str ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

const HARNESS_META = [
  { id: 'pi', label: 'Pi Core Native', desc: '4-tool minimalist SDK + RPC stream' },
  { id: 'claude-code', label: 'Claude Code CLI', desc: 'Local authenticated claude + --mcp-config' },
  { id: 'codex', label: 'Codex Harness', desc: 'Local ~/.codex + Routed MCP Bridge' },
  { id: 'opencode', label: 'OpenCode ACP', desc: 'OpenCode ACP / HTTP server bridge' },
  { id: 'byok', label: 'BYOK pi-ai Router', desc: 'Direct OpenAI / Anthropic / Gemini / OpenRouter' },
];

export async function initApp() {
  if (typeof document === 'undefined') return;

  const { PipiAvatar } = await import(avatarModuleUrl);
  const state = createSeedState();
  const $ = (sel) => document.querySelector(sel);

  // Mount live 120Hz PipiAvatars
  const toolbarAvatar = new PipiAvatar($('#toolbar-avatar-mount'), { size: 32, initialState: state.avatarState, interactive: false, cursorTrack: false });
  const islandAvatar = new PipiAvatar($('#island-avatar-mount'), { size: 22, initialState: state.avatarState, interactive: false, cursorTrack: false });
  const dockAvatar = new PipiAvatar($('#dock-avatar-mount'), { size: 34, initialState: 'manus-cue', interactive: true, cursorTrack: false });

  function syncAvatarState(nextState, nextExpr) {
    state.avatarState = nextState || 'ambient-breathe';
    if (nextExpr) state.avatarExpression = nextExpr;
    toolbarAvatar.setState(state.avatarState);
    islandAvatar.setState(state.avatarState);
    $('#mac-avatar-state-label').textContent = state.avatarState;
    $('#mac-avatar-expr-label').textContent = state.avatarExpression || islandAvatar.expressionId;
  }

  async function apiFetch(path, options = {}) {
    const url = `${state.apiBase}${path}`;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), options.timeoutMs || 2500);
    try {
      const res = await fetch(url, {
        ...options,
        signal: controller.signal,
        headers: {
          'Content-Type': 'application/json',
          ...(options.headers || {}),
        },
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return await res.json();
    } finally {
      clearTimeout(timer);
    }
  }

  async function probeDaemonAndHydrate() {
    const candidates = window.location.pathname.startsWith('/ios')
      ? ['', 'http://127.0.0.1:4242']
      : ['http://127.0.0.1:4242'];

    for (const base of candidates) {
      try {
        const res = await fetch(`${base}/api/v1/status`, { signal: AbortSignal.timeout(950) });
        if (!res.ok) continue;
        const statusData = await res.json();
        state.liveDaemon = true;
        state.apiBase = base;
        applyStatusPayload(statusData);
        await refreshAllDaemonData();
        connectSse();
        return;
      } catch {
        // try next candidate
      }
    }

    state.liveDaemon = false;
    $('#daemon-conn-banner').textContent = 'Offline Demo Mode · Start daemon via npm run start:daemon';
    $('#ios-mode-chip').textContent = 'Offline Demo';
    $('#mac-sse-pill').textContent = 'Demo Fallback';
    $('#mac-sse-pill').classList.remove('is-ok');
    $('#mac-sse-pill').classList.add('is-warn');
    renderAll();
  }

  function applyStatusPayload(data) {
    if (!data) return;
    if (data.cloudflare) state.cloudflare = data.cloudflare;
    if (data.understandingScore) state.understandingScore = data.understandingScore;
    if (data.avatarState) syncAvatarState(data.avatarState, data.avatarExpression);
    $('#daemon-conn-banner').textContent = `Connected Live · pipibot-daemon v${data.version || '0.2.0-beta'}`;
    $('#ios-mode-chip').textContent = 'Live Daemon';
    $('#mac-sse-pill').textContent = 'SSE Live';
    $('#mac-sse-pill').classList.add('is-ok');
    $('#mac-sse-pill').classList.remove('is-warn');
  }

  async function refreshAllDaemonData() {
    if (!state.liveDaemon) return;
    const [outRes, decRes, cueRes, fleetRes, memRes, chatRes] = await Promise.allSettled([
      apiFetch('/api/v1/outcomes'),
      apiFetch('/api/v1/decisions?status=pending'),
      apiFetch('/api/v1/cue'),
      apiFetch('/api/v1/fleet'),
      apiFetch('/api/v1/memory'),
      apiFetch('/api/v1/chat/transcript'),
    ]);

    if (outRes.status === 'fulfilled' && Array.isArray(outRes.value.outcomes)) {
      state.outcomes = outRes.value.outcomes;
    }
    if (decRes.status === 'fulfilled' && Array.isArray(decRes.value.decisions)) {
      state.decisions = decRes.value.decisions;
    }
    if (cueRes.status === 'fulfilled' && cueRes.value.latest) {
      state.cue = cueRes.value.latest;
    }
    if (fleetRes.status === 'fulfilled' && Array.isArray(fleetRes.value.nodes)) {
      state.nodes = fleetRes.value.nodes;
      if (fleetRes.value.cloudflare) state.cloudflare = fleetRes.value.cloudflare;
    }
    if (memRes.status === 'fulfilled') {
      state.memory.facts = memRes.value.facts || state.memory.facts;
      state.memory.skills = memRes.value.skills || state.memory.skills;
      state.memory.lastDigest = memRes.value.lastDigest || state.memory.lastDigest;
      if (memRes.value.understandingScore) state.understandingScore = memRes.value.understandingScore;
    }
    if (chatRes.status === 'fulfilled' && Array.isArray(chatRes.value.entries) && chatRes.value.entries.length > 0) {
      state.chatMessages = chatRes.value.entries.slice(-10).map((e) => ({
        role: e.role || 'assistant',
        provider: e.provider || state.selectedHarness,
        text: e.text || e.content || '',
      }));
    }
    renderAll();
  }

  function connectSse() {
    if (!state.liveDaemon || typeof EventSource === 'undefined') return;
    const es = new EventSource(`${state.apiBase}/api/v1/events`);

    es.addEventListener('harness.pulse', (ev) => {
      try {
        const pulse = JSON.parse(ev.data);
        if (pulse.suggestedAvatarState) syncAvatarState(pulse.suggestedAvatarState);
      } catch {
        // ignore parse error
      }
    });

    const reloadEvents = ['outcome.update', 'decision.needs_you', 'decision.resolved', 'cue.suggestion', 'node.heartbeat', 'evolution.digest_ready'];
    for (const evtName of reloadEvents) {
      es.addEventListener(evtName, () => {
        void refreshAllDaemonData();
      });
    }
  }

  /* ----------------------------------------------------------------
   * Render Dynamic Island, Mac Focal Panel, Dock, and Active Tab
   * -------------------------------------------------------------- */
  function renderChromeSync() {
    const pending = state.decisions.filter((d) => d.status === 'pending');
    const rtt = state.cloudflare?.tunnelRttMs ?? 18;
    const score = Number(state.understandingScore?.overall ?? 94.2).toFixed(1);

    $('#badge-needs-you').textContent = String(pending.length);
    $('#badge-needs-you').style.display = pending.length > 0 ? 'grid' : 'none';
    $('#mac-tunnel-rtt').textContent = `CF ${rtt}ms`;
    $('#ios-tunnel-chip').textContent = `CF Tunnel · ${rtt}ms`;
    $('#mac-understanding-score').textContent = `${score}%`;
    $('#toolbar-harness-label').textContent = `Harness: ${state.selectedHarness}`;

    if (pending.length > 0) {
      $('#di-compact-title').textContent = pending[0].title.slice(0, 22);
      $('#di-compact-badge').textContent = `${pending.length} Needs You`;
      $('#di-expanded-subtitle').textContent = `${pending.length} pending · ${state.nodes.length} nodes online`;
      $('#di-quick-action-label').textContent = 'Review Needs You';
    } else {
      $('#di-compact-title').textContent = 'PipiBot · All Clear';
      $('#di-compact-badge').textContent = state.selectedHarness;
      $('#di-expanded-subtitle').textContent = `${state.outcomes.length} active outcomes · $0/mo CF`;
      $('#di-quick-action-label').textContent = 'Open Outcomes';
    }
    $('#di-expanded-metric').textContent = `${rtt}ms`;

    if (state.outcomes.length > 0) {
      const first = state.outcomes[0];
      $('#mac-focal-outcome').textContent = first.title;
      $('#mac-focal-outcome-sub').textContent = first.goal;
    }

    if (state.cue) {
      $('#dock-cue-title').textContent = `Cue · ${state.cue.activeAppName || 'Workspace'}`;
      $('#dock-cue-sub').textContent = state.cue.detectedIntent || state.cue.windowTitle || 'Context ready';
    }
  }

  function renderActiveTab() {
    const container = $('#ios-tab-content');
    document.querySelectorAll('.pipi-tab-item').forEach((btn) => {
      btn.classList.toggle('is-active', btn.dataset.tab === state.activeTab);
    });

    if (state.activeTab === 'outcomes') {
      renderOutcomesTab(container);
    } else if (state.activeTab === 'needs-you') {
      renderNeedsYouTab(container);
    } else if (state.activeTab === 'muse') {
      renderMuseTab(container);
    } else if (state.activeTab === 'fleet') {
      renderFleetTab(container);
    } else if (state.activeTab === 'soul') {
      renderSoulTab(container);
    }
  }

  function renderOutcomesTab(container) {
    container.innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <strong style="font-size:16px;">Outcomes (${state.outcomes.length})</strong>
        <button class="pipi-btn pipi-btn-primary" id="btn-new-outcome" type="button">
          <svg class="pipi-icon-mobile" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <line x1="12" y1="5" x2="12" y2="19"></line>
            <line x1="5" y1="12" x2="19" y2="12"></line>
          </svg>
          <span>New</span>
        </button>
      </div>
      ${state.outcomes.map((out) => `
        <article class="pipi-list-card">
          <div class="pipi-list-card-head">
            <div>
              <div class="pipi-list-card-title">${escapeHtml(out.title)}</div>
              <div class="pipi-list-card-sub">${escapeHtml(out.goal)}</div>
            </div>
            <span class="pipi-pill ${out.status === 'needs_you' ? 'is-warn' : 'is-ok'} mono">${escapeHtml(out.status)}</span>
          </div>
          <div style="display:flex;justify-content:space-between;align-items:center;gap:8px;">
            <span class="mono" style="font-size:11px;color:var(--pipi-text-muted);">
              ${escapeHtml(out.domain)} · ${escapeHtml(out.preferredHarness)} · $${Number(out.spentTodayUsd || 0).toFixed(2)}/$${Number(out.dailyBudgetUsd || 2).toFixed(0)}
            </span>
            <button class="pipi-btn pipi-btn-desktop" data-eval-id="${escapeHtml(out.id)}" type="button">Evaluate</button>
          </div>
        </article>
      `).join('')}
    `;

    $('#btn-new-outcome')?.addEventListener('click', openCreateOutcomeFormSheet);
    container.querySelectorAll('[data-eval-id]').forEach((btn) => {
      btn.addEventListener('click', () => handleEvaluateOutcome(btn.dataset.evalId));
    });
  }

  function renderNeedsYouTab(container) {
    const pending = state.decisions.filter((d) => d.status === 'pending');
    if (pending.length === 0) {
      // Canonical Block 6: empty-state (1 icon, 1 title, 1 sentence, 1 button max)
      container.innerHTML = `
        <div class="pipi-empty-state">
          <svg class="pipi-icon-md" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <polyline points="20 6 9 17 4 12"></polyline>
          </svg>
          <h3 class="pipi-empty-title">All Caught Up</h3>
          <p class="pipi-empty-desc">Your Mac resident and VPS fleet are running autonomously without pending sign-offs.</p>
          <button class="pipi-btn pipi-btn-primary" id="btn-empty-new-outcome" type="button">
            <svg class="pipi-icon-mobile" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <line x1="12" y1="5" x2="12" y2="19"></line>
              <line x1="5" y1="12" x2="19" y2="12"></line>
            </svg>
            <span>Assign Outcome</span>
          </button>
        </div>
      `;
      $('#btn-empty-new-outcome')?.addEventListener('click', openCreateOutcomeFormSheet);
      return;
    }

    const card = pending[0];
    const ev = card.evidence?.[0];
    container.innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <strong style="font-size:16px;">Needs You (${pending.length})</strong>
        <span class="pipi-pill is-warn mono">${escapeHtml(card.severity)}</span>
      </div>
      <article class="pipi-list-card swipe-card-anim" id="needs-you-active-card">
        <div class="pipi-list-card-head">
          <div class="pipi-list-card-title">${escapeHtml(card.title)}</div>
          <span class="pipi-pill mono">${escapeHtml(card.category)}</span>
        </div>
        <div class="pipi-list-card-sub">${escapeHtml(card.summary)}</div>
        ${ev ? `
          <div class="pipi-evidence-box">
            <span class="mono" style="font-size:11px;color:var(--pipi-soul-secondary);">R2 EVIDENCE · ${escapeHtml(ev.kind)}</span>
            <div style="font-size:12px;font-weight:600;">${escapeHtml(ev.caption)}</div>
            <div class="mono" style="font-size:10px;color:var(--pipi-text-muted);word-break:break-all;">${escapeHtml(ev.r2Key)}</div>
          </div>
        ` : ''}
        <div class="pipi-field-group">
          <label class="pipi-field-label" for="ny-steer-note">Steer Note (Optional)</label>
          <input class="pipi-input" id="ny-steer-note" placeholder="Add guidance before shipping..." />
        </div>
        <div class="pipi-btn-row">
          <button class="pipi-btn pipi-btn-danger" id="btn-ny-reject" type="button">
            <svg class="pipi-icon-mobile" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <line x1="18" y1="6" x2="6" y2="18"></line>
              <line x1="6" y1="6" x2="18" y2="18"></line>
            </svg>
            <span>Defer</span>
          </button>
          <button class="pipi-btn pipi-btn-primary" id="btn-ny-approve" type="button">
            <svg class="pipi-icon-mobile" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <polyline points="20 6 9 17 4 12"></polyline>
            </svg>
            <span>Approve</span>
          </button>
        </div>
      </article>
    `;

    $('#btn-ny-approve')?.addEventListener('click', () => handleResolveDecision(card, true));
    $('#btn-ny-reject')?.addEventListener('click', () => handleResolveDecision(card, false));
  }

  function renderMuseTab(container) {
    container.innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <strong style="font-size:16px;">Muse Canvas &amp; Chat</strong>
        <button class="pipi-btn pipi-btn-desktop" id="btn-voice-toggle" type="button">
          <span>${state.voiceListening ? 'Stop Voice' : 'Voice Interrupt'}</span>
        </button>
      </div>
      <div class="muse-grid">
        <div class="pipi-list-card">
          <span class="mono" style="font-size:10px;color:var(--pipi-status-ok);">LIFE</span>
          <div class="pipi-list-card-title">NH962 Check-in</div>
          <div class="pipi-list-card-sub">Synced to Apple Calendar</div>
        </div>
        <div class="pipi-list-card">
          <span class="mono" style="font-size:10px;color:var(--pipi-soul-secondary);">WORK</span>
          <div class="pipi-list-card-title">PR #42 CLS Fix</div>
          <div class="pipi-list-card-sub">R2 clip verified</div>
        </div>
      </div>
      <div style="display:flex;flex-direction:column;gap:8px;">
        ${state.chatMessages.slice(-4).map((m) => `
          <div class="chat-bubble ${m.role === 'user' ? 'is-user' : ''}">
            <div class="mono" style="font-size:10px;color:var(--pipi-text-muted);margin-bottom:3px;">${escapeHtml(m.role)} · ${escapeHtml(m.provider || state.selectedHarness)}</div>
            <div style="white-space:pre-wrap;">${escapeHtml(m.text)}</div>
          </div>
        `).join('')}
      </div>
      <form id="muse-chat-form" class="pipi-field-group">
        <div style="display:flex;gap:8px;">
          <input class="pipi-input" id="muse-chat-input" placeholder="Message via ${escapeHtml(state.selectedHarness)}..." required />
          <button class="pipi-btn pipi-btn-primary" type="submit">
            <svg class="pipi-icon-mobile" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <line x1="22" y1="2" x2="11" y2="13"></line>
              <polygon points="22 2 15 22 11 13 2 9 22 2"></polygon>
            </svg>
            <span>Send</span>
          </button>
        </div>
      </form>
    `;

    $('#btn-voice-toggle')?.addEventListener('click', () => {
      state.voiceListening = !state.voiceListening;
      syncAvatarState(state.voiceListening ? 'voice-interrupted' : 'ambient-breathe', state.voiceListening ? 'listening' : 'happy');
      renderActiveTab();
    });

    $('#muse-chat-form')?.addEventListener('submit', async (e) => {
      e.preventDefault();
      const input = $('#muse-chat-input');
      const prompt = input.value.trim();
      if (!prompt) return;
      input.value = '';
      await handleChatTurn(prompt);
    });
  }

  function renderFleetTab(container) {
    const rtt = state.cloudflare?.tunnelRttMs ?? 18;
    container.innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <strong style="font-size:16px;">Dots Fleet (${state.nodes.length})</strong>
        <span class="pipi-pill is-ok mono">$0/mo CF · ${rtt}ms</span>
      </div>
      ${state.nodes.map((node) => `
        <article class="pipi-list-card">
          <div class="pipi-list-card-head">
            <div style="display:flex;align-items:center;gap:10px;">
              <span class="dot-pulse is-${escapeHtml(node.vitality || 'alive')}"></span>
              <div>
                <div class="pipi-list-card-title">${escapeHtml(node.displayName)}</div>
                <div class="pipi-list-card-sub mono">${escapeHtml(node.kind)} · CPU ${Math.round(node.cpuLoadPct || 0)}% · RAM ${Math.round(node.memoryUsedPct || 0)}%</div>
              </div>
            </div>
            <span class="pipi-pill mono">${node.tunnelRttMs ?? 12}ms</span>
          </div>
        </article>
      `).join('')}
    `;
  }

  function renderSoulTab(container) {
    const score = Number(state.understandingScore?.overall ?? 94.2).toFixed(1);
    const diffs = state.memory?.lastDigest?.diffs || [];
    container.innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <strong style="font-size:16px;">Soul &amp; Memory (${score}%)</strong>
        <button class="pipi-btn pipi-btn-primary" id="btn-run-dream" type="button">
          <svg class="pipi-icon-mobile" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"></path>
          </svg>
          <span>Dream</span>
        </button>
      </div>
      ${diffs.map((d) => `
        <article class="pipi-list-card">
          <div class="pipi-list-card-head">
            <div>
              <div class="pipi-list-card-title">${escapeHtml(d.title)}</div>
              <div class="pipi-list-card-sub mono">${escapeHtml(d.targetFile)} · ${escapeHtml(d.operation)}</div>
            </div>
            <span class="pipi-pill ${d.reviewStatus === 'approved' ? 'is-ok' : 'is-soul'} mono">${escapeHtml(d.reviewStatus)}</span>
          </div>
          <div class="pipi-list-card-sub">${escapeHtml(d.proposedValue)}</div>
          ${d.reviewStatus === 'pending' ? `
            <div class="pipi-btn-row">
              <button class="pipi-btn" data-diff-revert="${escapeHtml(d.diffId)}" type="button">Revert</button>
              <button class="pipi-btn pipi-btn-primary" data-diff-approve="${escapeHtml(d.diffId)}" type="button">Approve</button>
            </div>
          ` : ''}
        </article>
      `).join('')}
      <article class="pipi-list-card">
        <div class="pipi-list-card-title">Learned Facts &amp; Skills</div>
        <div class="pipi-list-card-sub mono">${state.memory.facts.length} active facts · ${state.memory.skills.length} Pi skills</div>
        ${state.memory.facts.slice(0, 3).map((f) => `
          <div class="pipi-list-card-sub">• ${escapeHtml(f.objectValue)}</div>
        `).join('')}
      </article>
    `;

    $('#btn-run-dream')?.addEventListener('click', handleRunDream);
    container.querySelectorAll('[data-diff-approve]').forEach((b) => {
      b.addEventListener('click', () => handleDiffReview(b.dataset.diffApprove, 'approve'));
    });
    container.querySelectorAll('[data-diff-revert]').forEach((b) => {
      b.addEventListener('click', () => handleDiffReview(b.dataset.diffRevert, 'revert'));
    });
  }

  /* ----------------------------------------------------------------
   * Canonical Block 2 & 3: Sheet (102px) & Form-Sheet (54px)
   * -------------------------------------------------------------- */
  function closeSheet() {
    $('#sheet-backdrop').classList.remove('is-open');
  }

  function openHarnessSheet() {
    const sheet = $('#active-sheet');
    sheet.className = 'pipi-sheet';
    sheet.innerHTML = `
      <div class="pipi-sheet-grabber"></div>
      <div class="pipi-sheet-head">
        <strong style="font-size:17px;">Select Harness Route</strong>
        <button class="pipi-btn pipi-btn-desktop" id="sheet-close-btn" type="button">Close</button>
      </div>
      ${HARNESS_META.map((h) => `
        <button class="pipi-list-card" data-pick-harness="${h.id}" type="button" style="text-align:left;cursor:pointer;">
          <div class="pipi-list-card-head">
            <div class="pipi-list-card-title">${escapeHtml(h.label)}</div>
            ${state.selectedHarness === h.id ? '<span class="pipi-pill is-ok mono">active</span>' : ''}
          </div>
          <div class="pipi-list-card-sub">${escapeHtml(h.desc)}</div>
        </button>
      `).join('')}
    `;
    $('#sheet-backdrop').classList.add('is-open');
    $('#sheet-close-btn')?.addEventListener('click', closeSheet);
    sheet.querySelectorAll('[data-pick-harness]').forEach((btn) => {
      btn.addEventListener('click', () => {
        state.selectedHarness = btn.dataset.pickHarness;
        const map = { pi: 'pi-coding', 'claude-code': 'claude-routing', codex: 'codex-routing', opencode: 'opencode-routing', byok: 'byok-streaming' };
        syncAvatarState(map[state.selectedHarness] || 'pi-coding', 'focused');
        closeSheet();
        renderAll();
      });
    });
  }

  function openCreateOutcomeFormSheet() {
    const sheet = $('#active-sheet');
    sheet.className = 'pipi-form-sheet';
    sheet.innerHTML = `
      <div class="pipi-sheet-grabber"></div>
      <div class="pipi-sheet-head">
        <strong style="font-size:17px;">New Outcome Responsibility</strong>
        <button class="pipi-btn pipi-btn-desktop" id="sheet-close-btn" type="button">Cancel</button>
      </div>
      <form id="create-outcome-form" style="display:flex;flex-direction:column;gap:12px;">
        <div class="pipi-field-group">
          <label class="pipi-field-label" for="out-title">Outcome Title</label>
          <input class="pipi-input" id="out-title" placeholder="e.g. Nightly E2E Checkout Guard" required />
        </div>
        <div class="pipi-field-group">
          <label class="pipi-field-label" for="out-domain">Domain</label>
          <select class="pipi-select" id="out-domain">
            <option value="dev">dev</option>
            <option value="work">work</option>
            <option value="daily_life">daily_life</option>
            <option value="infra">infra</option>
          </select>
        </div>
        <div class="pipi-field-group">
          <label class="pipi-field-label" for="out-goal">Goal &amp; Success Metrics</label>
          <textarea class="pipi-textarea" id="out-goal" rows="3" placeholder="Verify zero visual regressions and upload R2 video evidence." required></textarea>
        </div>
        <button class="pipi-btn pipi-btn-primary pipi-btn-full" type="submit">
          <svg class="pipi-icon-mobile" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <polyline points="20 6 9 17 4 12"></polyline>
          </svg>
          <span>Launch Outcome</span>
        </button>
      </form>
    `;
    $('#sheet-backdrop').classList.add('is-open');
    $('#sheet-close-btn')?.addEventListener('click', closeSheet);
    $('#create-outcome-form')?.addEventListener('submit', async (e) => {
      e.preventDefault();
      const title = $('#out-title').value.trim();
      const domain = $('#out-domain').value;
      const goal = $('#out-goal').value.trim();
      if (!title || !goal) return;

      if (state.liveDaemon) {
        const res = await apiFetch('/api/v1/outcomes', {
          method: 'POST',
          body: JSON.stringify({ title, domain, goal, preferredHarness: state.selectedHarness }),
        });
        if (res.outcome) state.outcomes.unshift(res.outcome);
      } else {
        state.outcomes.unshift({
          id: `out-${Date.now()}`,
          title,
          domain,
          goal,
          preferredHarness: state.selectedHarness,
          status: 'active',
          dailyBudgetUsd: 2,
          spentTodayUsd: 0,
        });
      }
      state.activeTab = 'outcomes';
      syncAvatarState('plan-structuring', 'focused');
      closeSheet();
      renderAll();
    });
  }

  /* ----------------------------------------------------------------
   * Action Handlers
   * -------------------------------------------------------------- */
  async function handleEvaluateOutcome(outcomeId) {
    syncAvatarState('plan-structuring', 'focused');
    if (state.liveDaemon) {
      await apiFetch(`/api/v1/outcomes/${encodeURIComponent(outcomeId)}/evaluate`, {
        method: 'POST',
        body: JSON.stringify({ requireHumanSignOff: false, useLiveHarness: false }),
      });
      await refreshAllDaemonData();
      return;
    }
    const target = state.outcomes.find((o) => o.id === outcomeId);
    if (target) target.spentTodayUsd = Number(((target.spentTodayUsd || 0) + 0.08).toFixed(2));
    syncAvatarState('synthesizing', 'proud');
    renderAll();
  }

  async function handleResolveDecision(card, approve) {
    const note = $('#ny-steer-note')?.value.trim() || undefined;
    const cardEl = $('#needs-you-active-card');
    cardEl?.classList.add(approve ? 'is-approved' : 'is-rejected');

    const chosenOptionId = approve
      ? (card.recommendedOptionId || card.options?.[0]?.id || 'approve')
      : (card.options?.find((o) => o.style === 'destructive')?.id || 'reject');

    if (state.liveDaemon) {
      await apiFetch(`/api/v1/decisions/${encodeURIComponent(card.id)}/resolve`, {
        method: 'POST',
        body: JSON.stringify({ chosenOptionId, userNote: note, resolvedBy: 'ios-web' }),
      });
    }

    setTimeout(async () => {
      card.status = 'resolved';
      syncAvatarState(approve ? 'evolution-proud' : 'idle', approve ? 'proud' : 'neutral');
      if (state.liveDaemon) await refreshAllDaemonData();
      else renderAll();
    }, 260);
  }

  async function handleChatTurn(prompt) {
    state.chatMessages.push({ role: 'user', provider: state.selectedHarness, text: prompt });
    syncAvatarState('thinking', 'curious');
    renderActiveTab();

    if (state.liveDaemon) {
      const res = await apiFetch('/api/v1/chat/turn', {
        method: 'POST',
        body: JSON.stringify({ prompt, provider: state.selectedHarness, useLiveHarness: false }),
      });
      state.chatMessages.push({
        role: 'assistant',
        provider: res.providerUsed || state.selectedHarness,
        text: res.text || 'Turn completed.',
      });
      syncAvatarState('synthesizing', 'proud');
      renderAll();
      return;
    }

    state.chatMessages.push({
      role: 'assistant',
      provider: state.selectedHarness,
      text: `[${state.selectedHarness} · demo] Routed via PipiHarnessRouter + 4-Tier Memory recall for "${prompt.slice(0, 60)}".`,
    });
    syncAvatarState('synthesizing', 'proud');
    renderAll();
  }

  async function handleRunDream() {
    syncAvatarState('dreaming-consolidating', 'sleepy');
    if (state.liveDaemon) {
      const res = await apiFetch('/api/v1/memory/dream', { method: 'POST', body: '{}' });
      if (res.summary) state.memory.lastDigest = res.summary;
      await refreshAllDaemonData();
      return;
    }
    state.understandingScore.overall = Math.min(99.9, Number(state.understandingScore.overall) + 0.3);
    syncAvatarState('persona-updating', 'evolving');
    renderAll();
  }

  async function handleDiffReview(diffId, action) {
    if (state.liveDaemon) {
      const res = await apiFetch(`/api/v1/memory/diffs/${encodeURIComponent(diffId)}/review`, {
        method: 'POST',
        body: JSON.stringify({ action }),
      });
      if (res.summary) state.memory.lastDigest = res.summary;
      await refreshAllDaemonData();
      return;
    }
    const diff = state.memory?.lastDigest?.diffs?.find((d) => d.diffId === diffId);
    if (diff) diff.reviewStatus = action === 'approve' ? 'approved' : 'reverted';
    syncAvatarState(action === 'approve' ? 'evolution-proud' : 'memory-pruning');
    renderAll();
  }

  async function handleExecuteDockCue() {
    dockAvatar.poke();
    if (state.liveDaemon && state.cue?.id) {
      await apiFetch(`/api/v1/cue/${encodeURIComponent(state.cue.id)}/execute`, {
        method: 'POST',
        body: JSON.stringify({ actionId: state.cue.actions?.[0]?.id }),
      });
      await refreshAllDaemonData();
      return;
    }
    syncAvatarState('manus-cue', 'curious');
    state.activeTab = 'muse';
    await handleChatTurn(`Execute Cue: ${state.cue.detectedIntent}`);
  }

  function renderAll() {
    renderChromeSync();
    renderActiveTab();
  }

  /* ----------------------------------------------------------------
   * Event Listeners
   * -------------------------------------------------------------- */
  document.querySelectorAll('.pipi-tab-item').forEach((btn) => {
    btn.addEventListener('click', () => {
      state.activeTab = btn.dataset.tab;
      renderAll();
    });
  });

  $('#dynamic-island').addEventListener('click', (e) => {
    if (e.target.closest('#di-quick-action-btn')) {
      e.stopPropagation();
      const pending = state.decisions.filter((d) => d.status === 'pending');
      state.activeTab = pending.length > 0 ? 'needs-you' : 'outcomes';
      $('#dynamic-island').classList.remove('is-expanded');
      renderAll();
      return;
    }
    const el = $('#dynamic-island');
    const expanded = el.classList.toggle('is-expanded');
    el.setAttribute('aria-expanded', String(expanded));
    islandAvatar.poke();
  });

  $('#dock-cue-btn').addEventListener('click', () => { void handleExecuteDockCue(); });
  $('#btn-open-harness-sheet').addEventListener('click', openHarnessSheet);
  $('#sheet-backdrop').addEventListener('click', (e) => {
    if (e.target.id === 'sheet-backdrop') closeSheet();
  });

  $('#btn-toggle-theme').addEventListener('click', () => {
    const html = document.documentElement;
    const isLight = html.getAttribute('data-theme') === 'light';
    html.setAttribute('data-theme', isLight ? 'dark' : 'light');
    state.theme = isLight ? 'dark' : 'light';
    $('#btn-toggle-theme span').textContent = `Theme: ${isLight ? 'Obsidian' : 'Vellum'}`;
  });

  $('#btn-toggle-pwa').addEventListener('click', () => {
    document.body.classList.toggle('is-pwa-only');
  });

  renderAll();
  void probeDaemonAndHydrate();
}

if (typeof document !== 'undefined') {
  void initApp();
}
