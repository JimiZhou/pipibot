/**
 * PipiBot Companion Web App Controller
 * Connects to @pipibot/daemon (/api/v1/* + SSE /api/v1/events) with automatic
 * offline fallback and system-language adaptation.
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
    activeDecisionId: null,
    boardChannelFilter: 'all',
    board: {
      channels: [
        { slug: 'inbox', title: 'Inbox' },
        { slug: 'dev', title: 'Dev' },
        { slug: 'ops', title: 'Ops' },
      ],
      threads: [
        {
          id: 'bth-seed-1',
          channelSlug: 'dev',
          kind: 'task',
          title: '补齐 Jarvis 早停自动续跑与并发只读单测',
          status: 'claimed',
          priority: 'high',
          blockedBy: [],
          claim: { actor: { id: 'bot:coder', name: 'Coder · 编程搭档', kind: 'bot' }, expiresAt: new Date(Date.now() + 14 * 60_000).toISOString(), leaseToken: 'seed_lease_1' },
          messages: [{ id: 'bm-1', body: '已将 maxSteps 提升至 20 并添加早停守卫。' }],
        },
        {
          id: 'bth-seed-2',
          channelSlug: 'ops',
          kind: 'task',
          title: '云主机节点巡检与 omp CLI 验证',
          status: 'open',
          priority: 'normal',
          blockedBy: [],
          messages: [{ id: 'bm-2', body: '核验三台在线节点内存与 harness 可用性。' }],
        },
      ],
      events: [],
    },
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
        title: '布局守护 Bot',
        domain: 'dev',
        goal: '通过每 3 小时 Playwright 审计，将移动端与桌面端结账页 CLS 保持在 0.02 以下。',
        preferredHarness: 'claude-code',
        status: 'needs_you',
        dailyBudgetUsd: 3.0,
        spentTodayUsd: 0.48,
      },
      {
        id: 'out-vps',
        title: '香港 VPS 零停机监控',
        domain: 'infra',
        goal: '监控 nginx 上游 502 率、TLS 到期时间与 Docker 容器内存。',
        preferredHarness: 'codex',
        status: 'active',
        dailyBudgetUsd: 2.0,
        spentTodayUsd: 0.14,
      },
      {
        id: 'out-travel',
        title: '东京 NH962 行程与日历同步',
        domain: 'daily_life',
        goal: '自动提取登机牌、日历占位与晚间健身安排。',
        preferredHarness: 'pi',
        status: 'active',
        dailyBudgetUsd: 1.0,
        spentTodayUsd: 0.05,
      },
      {
        id: 'out-digest',
        title: '每周研究摘要',
        domain: 'research',
        goal: '汇总收藏论文，并在周一生成带引用的简报。',
        preferredHarness: 'pi',
        status: 'active',
        dailyBudgetUsd: 1.5,
        spentTodayUsd: 0.12,
      },
    ],
    decisions: [
      {
        id: 'dec-pr42',
        severity: 'warning',
        category: 'code_merge_or_push',
        title: '批准 PR #42 — 结账页 CLS 回归修复',
        summary: '子会话修复了骨架屏容器高度，并验证 14/14 条断言通过。',
        recommendedOptionId: 'approve',
        options: [
          { id: 'approve', label: '批准并合并', style: 'primary' },
          { id: 'steer', label: '调整', style: 'secondary' },
          { id: 'reject', label: '稍后', style: 'destructive' },
        ],
        evidence: [
          {
            artifactId: 'art-cls-42',
            r2Key: 'r2://pipibot-artifacts/pr-42-diff.mp4',
            kind: 'video',
            caption: 'CLS 0.34 -> 0.01（1080p Playwright 录屏）',
          },
        ],
        status: 'pending',
      },
      {
        id: 'dec-nginx',
        severity: 'critical',
        category: 'infra_mutation',
        title: '重载香港 VPS Nginx Keepalive 池',
        summary: 'Codex 将 1.8% 的 502 峰值定位到上游 keepalive=15s 超时。',
        recommendedOptionId: 'approve',
        options: [
          { id: 'approve', label: '安全重载', style: 'primary' },
          { id: 'reject', label: '暂缓', style: 'destructive' },
        ],
        evidence: [
          {
            artifactId: 'art-vps-trace',
            r2Key: 'r2://pipibot-artifacts/nginx-diff.patch',
            kind: 'diff_patch',
            caption: 'keepalive_timeout 15s -> 65s · nginx -t 通过',
          },
        ],
        status: 'pending',
      },
      {
        id: 'dec-dream',
        severity: 'info',
        category: 'memory_evolution_review',
        title: '合并夜间记忆整理 (+2 条事实, +1 个技能)',
        summary: '学习到 TypeScript 零运行时依赖偏好，以及 cf-tunnel-heal 技能。',
        recommendedOptionId: 'approve',
        options: [
          { id: 'approve', label: '合并变更', style: 'primary' },
          { id: 'reject', label: '丢弃', style: 'destructive' },
        ],
        evidence: [
          {
            artifactId: 'art-mem-diff',
            r2Key: 'local://~/.pipibot/evolution/nightly.diff',
            kind: 'log_excerpt',
            caption: '理解度 92.8% -> 94.2%',
          },
        ],
        status: 'pending',
      },
    ],
    cue: {
      id: 'cue-demo-1',
      activeAppName: 'Xcode',
      windowTitle: 'PipiHost.swift',
      detectedIntent: 'SwiftUI 快照测试待运行',
      actions: [
        { id: 'run-tests', label: '运行测试', harness: 'pi', promptTemplate: 'Run SwiftUI regression suite' },
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
      { role: 'assistant', provider: 'pi', text: 'PipiCore 已就绪，内置 4 个核心工具与四层记忆召回。可随时在顶部或面板切换引擎。' },
    ],
    memory: {
      facts: [
        { id: 'fact-1', subject: 'user', predicate: 'prefers_runtime', objectValue: 'TypeScript 核心与协议零外部依赖', confidence: 0.96 },
        { id: 'fact-2', subject: 'user', predicate: 'gym_schedule', objectValue: '周二/周四 19:30-21:00 非紧急提醒免打扰', confidence: 0.91 },
      ],
      skills: [
        { slug: 'cf-tunnel-heal', name: 'Cloudflare Tunnel 自动修复', successRate: 0.98, occurrences: 6 },
      ],
      lastDigest: {
        digestId: 'dig-demo',
        diffs: [
          {
            diffId: 'diff-1',
            operation: 'add',
            targetFile: 'USER.md',
            title: 'UI 组件零裸色值',
            proposedValue: 'CSS/SwiftUI 视图始终绑定三层设计令牌。',
            reviewStatus: 'pending',
          },
        ],
      },
      soulPreview: '# SOUL.md\n环境灵魂与任务工作室：平时安静，关键时刻果断，以证据代替原始日志。',
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

function sanitizeInlineSvg(raw) {
  return String(raw ?? '')
    .replace(/<script\b[\s\S]*?<\/script>/gi, '')
    .replace(/<foreignObject\b[\s\S]*?<\/foreignObject>/gi, '')
    .replace(/<iframe\b[\s\S]*?<\/iframe>/gi, '')
    .replace(/\s+on[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/gi, '')
    .replace(/(xlink:href|href|src)\s*=\s*["']\s*(?:javascript:|data:text\/html)[^"']*["']/gi, '$1="#"');
}

function renderMermaidInlineSvg(src) {
  const lines = String(src ?? '').replace(/\r\n/g, '\n').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('%%'));
  const nodes = new Map();
  const edges = [];
  const ensure = (tok) => {
    const clean = tok.trim().replace(/:::[a-zA-Z0-9_-]+$/, '');
    const m = clean.match(/^([A-Za-z0-9_.-]+)\s*[\[\(\{]([\s\S]+?)[\]\)\}]$/);
    const id = m ? m[1] : clean;
    const label = m ? m[2].replace(/^["']|["']$/g, '').split(/<br\s*\/?>|\\n/i)[0] : id;
    if (!nodes.has(id)) nodes.set(id, { id, label, rank: 0 });
    return id;
  };
  for (let i = 1; i < lines.length; i += 1) {
    const em = lines[i].match(/^(.+?)\s*(-->|-.->|==>)\s*(?:\|([^|]+)\|\s*)?(.+)$/);
    if (em) {
      const from = ensure(em[1]);
      const to = ensure(em[4]);
      edges.push({ from, to, label: (em[3] || '').trim(), dashed: em[2].includes('-.') });
    }
  }
  const list = Array.from(nodes.values());
  if (!list.length) return `<pre class="pipi-diagram-src">${escapeHtml(src)}</pre>`;
  edges.forEach((e) => {
    const a = nodes.get(e.from);
    const b = nodes.get(e.to);
    if (a && b && b.rank <= a.rank) b.rank = a.rank + 1;
  });
  const nW = 136;
  const nH = 44;
  const gX = 42;
  const gY = 26;
  const pad = 16;
  const byRank = new Map();
  let maxR = 0;
  let maxB = 1;
  list.forEach((n) => {
    maxR = Math.max(maxR, n.rank);
    if (!byRank.has(n.rank)) byRank.set(n.rank, []);
    byRank.get(n.rank).push(n);
  });
  byRank.forEach((arr) => { maxB = Math.max(maxB, arr.length); });
  const W = pad * 2 + (maxR + 1) * nW + maxR * gX;
  const H = pad * 2 + maxB * nH + (maxB - 1) * gY;
  const pos = new Map();
  byRank.forEach((arr, r) => {
    const colH = arr.length * nH + (arr.length - 1) * gY;
    arr.forEach((n, idx) => {
      pos.set(n.id, { x: pad + r * (nW + gX), y: (H - colH) / 2 + idx * (nH + gY) });
    });
  });
  const parts = [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}">`,
    `<defs><marker id="pwa-arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M 0 1.5 L 10 5 L 0 8.5 z" fill="currentColor"/></marker></defs>`,
  ];
  edges.forEach((e) => {
    const a = pos.get(e.from);
    const b = pos.get(e.to);
    if (!a || !b) return;
    const x1 = a.x + nW;
    const y1 = a.y + nH / 2;
    const x2 = b.x;
    const y2 = b.y + nH / 2;
    const mx = (x1 + x2) / 2;
    parts.push(`<path d="M ${x1} ${y1} C ${mx} ${y1}, ${mx} ${y2}, ${x2} ${y2}" fill="none" stroke="var(--pipi-border-strong)" stroke-width="1.4" ${e.dashed ? 'stroke-dasharray="4 3"' : ''} marker-end="url(#pwa-arr)"/>`);
    if (e.label) parts.push(`<text x="${mx}" y="${(y1 + y2) / 2 - 6}" text-anchor="middle" font-size="10" fill="var(--pipi-text-secondary)">${escapeHtml(e.label)}</text>`);
  });
  list.forEach((n) => {
    const p = pos.get(n.id);
    if (!p) return;
    parts.push(`<rect x="${p.x}" y="${p.y}" width="${nW}" height="${nH}" rx="8" fill="var(--pipi-bg-surface)" stroke="var(--pipi-border-strong)" stroke-width="1.2"/>`);
    parts.push(`<text x="${p.x + nW / 2}" y="${p.y + 26}" text-anchor="middle" font-size="11.5" fill="var(--pipi-text-primary)">${escapeHtml(n.label)}</text>`);
  });
  parts.push('</svg>');
  return parts.join('');
}

function renderRichChatContent(rawText) {
  const text = String(rawText ?? '');
  const parts = [];
  const fenceRe = /```([^\n]*)\n([\s\S]*?)```/g;
  let lastIdx = 0;
  let m;
  while ((m = fenceRe.exec(text)) !== null) {
    if (m.index > lastIdx) {
      parts.push(renderInlineProseAndSvg(text.slice(lastIdx, m.index)));
    }
    const info = (m[1] || '').trim();
    const lang = (info.split(/\s+/)[0] || '').toLowerCase();
    const body = (m[2] || '').trim();
    const titleMatch = info.match(/title\s*=\s*["']([^"']+)["']/i);
    const title = titleMatch ? titleMatch[1] : '';
    if (lang === 'svg' || (lang === 'xml' && body.startsWith('<svg'))) {
      parts.push(renderDiagramCardHtml('SVG', title, sanitizeInlineSvg(body), body));
    } else if (lang === 'mermaid' || lang === 'mmd') {
      parts.push(renderDiagramCardHtml('Mermaid', title, renderMermaidInlineSvg(body), body));
    } else if (lang === 'canvas' || lang === 'diagram' || lang === 'html-diagram') {
      parts.push(renderDiagramCardHtml('Canvas', title, sanitizeInlineSvg(body), body));
    } else {
      parts.push(`<pre class="pipi-diagram-src">${escapeHtml(body)}</pre>`);
    }
    lastIdx = m.index + m[0].length;
  }
  if (lastIdx < text.length) {
    parts.push(renderInlineProseAndSvg(text.slice(lastIdx)));
  }
  return parts.join('');
}

function renderInlineProseAndSvg(chunk) {
  const svgRe = /<svg\b[\s\S]*?<\/svg>/gi;
  let last = 0;
  let m;
  const out = [];
  while ((m = svgRe.exec(chunk)) !== null) {
    if (m.index > last) {
      out.push(`<div style="white-space:pre-wrap;">${escapeHtml(chunk.slice(last, m.index))}</div>`);
    }
    out.push(renderDiagramCardHtml('SVG', '', sanitizeInlineSvg(m[0]), m[0]));
    last = m.index + m[0].length;
  }
  if (last < chunk.length) {
    out.push(`<div style="white-space:pre-wrap;">${escapeHtml(chunk.slice(last))}</div>`);
  }
  return out.join('');
}

function renderDiagramCardHtml(kindLabel, title, renderedHtml, rawSource) {
  const heading = title ? `${escapeHtml(title)} · ${escapeHtml(kindLabel)}` : escapeHtml(kindLabel);
  return `
    <div class="pipi-diagram-card" data-diagram-card="1">
      <div class="pipi-diagram-head">
        <span>${heading}</span>
        <button class="pipi-diagram-toggle" type="button" data-diagram-toggle="1">源码</button>
      </div>
      <div class="pipi-diagram-body" data-diagram-preview="1">${renderedHtml}</div>
      <pre class="pipi-diagram-src" data-diagram-source="1" hidden>${escapeHtml(rawSource)}</pre>
    </div>
  `;
}

const HARNESS_META = [
  { id: 'pi', label: 'Pi Core Native', desc: '4 工具极简 SDK + RPC 流' },
  { id: 'claude-code', label: 'Claude Code CLI', desc: '本地已登录 claude + --mcp-config' },
  { id: 'codex', label: 'Codex Harness', desc: '本地 ~/.codex + 路由 MCP 桥' },
  { id: 'opencode', label: 'OpenCode ACP', desc: 'OpenCode ACP / HTTP 服务桥' },
  { id: 'byok', label: 'BYOK pi-ai Router', desc: '直连 OpenAI / Anthropic / Gemini / OpenRouter' },
];

export async function initApp() {
  if (typeof document === 'undefined') return;

  const { PipiAvatar } = await import(avatarModuleUrl);
  const state = createSeedState();
  const $ = (sel) => document.querySelector(sel);
  const params = new URLSearchParams(window.location.search);
  const tabParam = params.get('tab');
  if (['outcomes', 'needs-you', 'muse', 'fleet', 'soul'].includes(tabParam)) {
    state.activeTab = tabParam;
  }
  const themeParam = params.get('theme');
  if (themeParam === 'light' || themeParam === 'dark') {
    state.theme = themeParam;
    document.documentElement.setAttribute('data-theme', themeParam);
  }
  if (params.get('pwa') === '1') {
    document.body.classList.add('is-pwa-only');
  }

  const copy = {
    brandTitle: 'PipiBot · 个人 AI 助手',
    quickAction: '运行',
    tabTasks: '任务',
    tabApprovals: '待确认',
    tabChat: '对话',
    tabDevices: '设备',
    tabMemory: '记忆',
    themeObsidian: '主题：黑曜石',
    themeVellum: '主题：羊皮纸',
    pwaFocus: '手机视图',
    harness: '引擎',
    connecting: '正在连接 PipiBot ...',
    offlineDemo: '离线演示 · 使用示例数据',
    offlineDemoTitle: '运行 npm run start:daemon 连接本地 Daemon',
    liveConnected: (version) => `已连接 · pipibot-daemon v${version}`,
    offlineMode: '离线演示',
    liveMode: '实时连接',
    demoData: '演示数据',
    local: '本地',
    sampleData: '示例数据',
    outcomes: (count) => `任务 (${count})`,
    new: '新建',
    evaluateNeedsYou: '处理',
    evaluateActive: '查看',
    statusNeedsYou: '待确认',
    statusActive: '运行中',
    statusDone: '已完成',
    statusFailed: '失败',
    statusPaused: '已暂停',
    domainDev: '开发',
    domainInfra: '基础设施',
    domainDailyLife: '生活',
    domainResearch: '研究',
    harnessPi: 'Pi',
    harnessClaudeCode: 'Claude Code',
    harnessCodex: 'Codex',
    harnessOpenCode: 'OpenCode',
    harnessByok: 'BYOK',
    cue: '提示',
    needsYou: (count) => `待确认 (${count})`,
    steerNote: '补充说明（可选）',
    steerPlaceholder: '在批准前补充说明...',
    defer: '稍后',
    approve: '批准',
    r2Evidence: 'R2 证据',
    chatTitle: 'PipiBot 对话',
    voice: '语音输入',
    stopVoice: '停止语音',
    send: '发送',
    life: '生活',
    work: '工作',
    messageVia: (harness) => `通过 ${harness} 发送消息...`,
    connectedDevices: (count) => `已连接设备 (${count})`,
    soulMemory: (score) => `灵魂与记忆 (${score}%)`,
    dream: '整理记忆',
    learnedFacts: '已学习的事实与技能',
    factsSkills: (facts, skills) => `${facts} 条事实 · ${skills} 个技能`,
    revert: '撤销',
    adopt: '采纳',
    selectHarness: '选择引擎',
    close: '关闭',
    current: '当前',
    newOutcome: '新建任务',
    cancel: '取消',
    outcomeTitle: '任务名称',
    outcomeTitlePlaceholder: '例如：夜间 E2E 结账守护',
    domain: '领域',
    goal: '目标与验收标准',
    goalPlaceholder: '验证零视觉回归，并上传 R2 视频证据。',
    launchOutcome: '创建任务',
    allCaughtUp: '全部处理完了',
    allCaughtUpDesc: 'Mac 主机与 VPS 正在自动运行，没有待确认事项。',
    assignOutcome: '新建任务',
    allClear: '全部完成',
    pending: '待处理',
    nodesOnline: (count) => `${count} 台设备在线`,
    activeOutcomes: (count) => `${count} 个任务运行中`,
    reviewNeedsYou: '查看待确认',
    openOutcomes: '查看任务',
    avatarStates: {
      'ambient-breathe': '待命',
      thinking: '思考中',
      'plan-structuring': '规划中',
      synthesizing: '整理中',
      'evolution-proud': '已完成',
      'dreaming-consolidating': '整理记忆中',
      'persona-updating': '更新中',
      'manus-cue': '提示中',
      'voice-interrupted': '聆听中',
      idle: '空闲',
      'pi-coding': '编码中',
      'claude-routing': '路由中',
      'codex-routing': '路由中',
      'opencode-routing': '路由中',
      'byok-streaming': '流式生成中',
      'memory-pruning': '清理记忆中',
    },
    expressions: {
      happy: '愉快',
      focused: '专注',
      curious: '好奇',
      proud: '自豪',
      neutral: '平静',
      listening: '聆听',
      sleepy: '困倦',
      evolving: '进化中',
    },
  };

  const statusLabel = (status) => ({
    needs_you: copy.statusNeedsYou,
    active: copy.statusActive,
    done: copy.statusDone,
    failed: copy.statusFailed,
    paused: copy.statusPaused,
  }[status] || status);

  const statusPillClass = (status) => {
    if (status === 'needs_you' || status === 'failed') return 'is-warn';
    if (status === 'paused') return 'is-soul';
    return 'is-ok';
  };

  const severityLabel = (severity) => ({
    warning: '警告',
    critical: '严重',
    info: '提示',
  }[severity] || severity);

  const categoryLabel = (category) => ({
    code_merge_or_push: '代码合并 / 推送',
    infra_mutation: '基础设施变更',
    memory_evolution_review: '记忆更新',
  }[category] || category);

  const domainLabel = (domain) => ({
    dev: copy.domainDev,
    infra: copy.domainInfra,
    daily_life: copy.domainDailyLife,
    research: copy.domainResearch,
  }[domain] || domain);

  const harnessLabel = (harness) => ({
    pi: copy.harnessPi,
    'claude-code': copy.harnessClaudeCode,
    codex: copy.harnessCodex,
    opencode: copy.harnessOpenCode,
    byok: copy.harnessByok,
  }[harness] || harness);

  const nodeKindLabel = (kind) => ({
    mac: 'Mac',
    ios: 'iPhone',
    vps: 'VPS',
    windows: 'Windows',
    embedded: '嵌入式',
  }[kind] || kind);

  const operationLabel = (operation) => ({
    add: '新增',
    update: '更新',
    remove: '删除',
  }[operation] || operation);

  const reviewStatusLabel = (status) => ({
    pending: '待审阅',
    approved: '已采纳',
    reverted: '已撤销',
  }[status] || status);

  const evidenceKindLabel = (kind) => ({
    video: '视频',
    diff_patch: '补丁',
    log_excerpt: '日志',
  }[kind] || kind);

  const avatarStateLabel = (state) => copy.avatarStates[state] || state;
  const expressionLabel = (expression) => copy.expressions[expression] || expression;

  document.documentElement.lang = 'zh-CN';
  document.querySelectorAll('[data-i18n]').forEach((el) => {
    const key = el.getAttribute('data-i18n');
    if (key && copy[key]) el.textContent = copy[key];
  });
  $('#btn-toggle-theme span').textContent = state.theme === 'light' ? copy.themeVellum : copy.themeObsidian;

  // Mount live 120Hz PipiAvatars
  const toolbarAvatar = new PipiAvatar($('#toolbar-avatar-mount'), { size: 32, initialState: state.avatarState, interactive: false, cursorTrack: false });
  const islandAvatar = new PipiAvatar($('#island-avatar-mount'), { size: 22, initialState: state.avatarState, interactive: false, cursorTrack: false });
  const dockAvatar = new PipiAvatar($('#dock-avatar-mount'), { size: 34, initialState: 'manus-cue', interactive: true, cursorTrack: false });

  function syncAvatarState(nextState, nextExpr) {
    state.avatarState = nextState || 'ambient-breathe';
    if (nextExpr) state.avatarExpression = nextExpr;
    toolbarAvatar.setState(state.avatarState);
    islandAvatar.setState(state.avatarState);
    $('#mac-avatar-state-label').textContent = avatarStateLabel(state.avatarState);
    $('#mac-avatar-expr-label').textContent = expressionLabel(state.avatarExpression || islandAvatar.expressionId);
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
    $('#daemon-conn-banner').textContent = copy.offlineDemo;
    $('#daemon-conn-banner').title = copy.offlineDemoTitle;
    $('#ios-mode-chip').textContent = copy.offlineMode;
    $('#mac-sse-pill').textContent = copy.demoData;
    $('#mac-sse-pill').classList.remove('is-ok');
    $('#mac-sse-pill').classList.add('is-warn');
    renderAll();
  }

  function applyStatusPayload(data) {
    if (!data) return;
    if (data.cloudflare) state.cloudflare = data.cloudflare;
    if (data.understandingScore) state.understandingScore = data.understandingScore;
    if (data.avatarState) syncAvatarState(data.avatarState, data.avatarExpression);
    $('#daemon-conn-banner').textContent = copy.liveConnected(data.version || '0.2.0-beta');
    $('#daemon-conn-banner').title = '';
    $('#ios-mode-chip').textContent = copy.liveMode;
    $('#mac-sse-pill').textContent = copy.liveMode;
    $('#mac-sse-pill').classList.add('is-ok');
    $('#mac-sse-pill').classList.remove('is-warn');
  }

  async function refreshAllDaemonData() {
    if (!state.liveDaemon) return;
    const [outRes, decRes, cueRes, fleetRes, memRes, chatRes, boardRes] = await Promise.allSettled([
      apiFetch('/api/v1/outcomes'),
      apiFetch('/api/v1/decisions?status=pending'),
      apiFetch('/api/v1/cue'),
      apiFetch('/api/v1/fleet'),
      apiFetch('/api/v1/memory'),
      apiFetch('/api/v1/chat/transcript'),
      apiFetch('/api/v1/board'),
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
    if (boardRes.status === 'fulfilled' && boardRes.value) {
      const snap = boardRes.value.board || boardRes.value;
      if (Array.isArray(snap.threads)) {
        state.board = {
          channels: Array.isArray(snap.channels) && snap.channels.length ? snap.channels : state.board.channels,
          threads: snap.threads,
          events: Array.isArray(snap.events) ? snap.events : [],
        };
      }
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

    const reloadEvents = ['outcome.update', 'decision.needs_you', 'decision.resolved', 'cue.suggestion', 'node.heartbeat', 'evolution.digest_ready', 'board.event'];
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
    const shortTitle = pending[0]?.title?.split('—')[0].trim();
    const firstOutcome = state.outcomes[0];

    $('#badge-needs-you').textContent = String(pending.length);
    $('#badge-needs-you').style.display = pending.length > 0 ? 'grid' : 'none';
    const focalStatus = $('#mac-focal-status');
    focalStatus.textContent = firstOutcome ? statusLabel(firstOutcome.status) : copy.local;
    focalStatus.className = `pipi-pill ${firstOutcome ? statusPillClass(firstOutcome.status) : 'is-ok'} mono`;
    $('#ios-tunnel-chip').textContent = state.liveDaemon ? `CF 隧道 · ${rtt}ms` : copy.sampleData;
    $('#mac-understanding-score').textContent = `${score}%`;
    $('#toolbar-harness-label').textContent = `${copy.harness}：${harnessLabel(state.selectedHarness)}`;

    if (pending.length > 0) {
      $('#di-compact-title').textContent = shortTitle;
      $('#di-compact-title').title = pending[0].title;
      $('#di-compact-badge').textContent = `${pending.length} 项${copy.statusNeedsYou}`;
      $('#di-expanded-subtitle').textContent = `${pending.length} 项${copy.pending} · ${copy.nodesOnline(state.nodes.length)}`;
      $('#di-quick-action-label').textContent = copy.reviewNeedsYou;
      $('#mac-needs-you-title').textContent = pending[0].title;
      $('#mac-needs-you-count').textContent = `${pending.length} 项`;
    } else {
      $('#di-compact-title').textContent = `PipiBot · ${copy.allClear}`;
      $('#di-compact-title').title = '';
      $('#di-compact-badge').textContent = harnessLabel(state.selectedHarness);
      $('#di-expanded-subtitle').textContent = `${copy.activeOutcomes(state.outcomes.length)} · ${state.liveDaemon ? '$0/mo CF' : copy.local}`;
      $('#di-quick-action-label').textContent = copy.openOutcomes;
      $('#mac-needs-you-title').textContent = '没有待确认事项';
      $('#mac-needs-you-count').textContent = '0 项';
    }
    $('#di-expanded-metric').textContent = state.liveDaemon ? `${rtt}ms` : copy.local;

    if (firstOutcome) {
      $('#mac-focal-outcome').textContent = firstOutcome.title;
      $('#mac-focal-outcome-sub').textContent = firstOutcome.goal;
    }

    if (state.cue) {
      $('#dock-cue-title').textContent = `${copy.cue} · ${state.cue.activeAppName || 'Workspace'}`;
      $('#dock-cue-sub').textContent = state.cue.detectedIntent || state.cue.windowTitle || '上下文已就绪';
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

  function boardStatusLabel(status) {
    const zh = { open: '待认领', claimed: '进行中', blocked: '已阻塞', needs_you: '待确认', done: '已完成', cancelled: '已取消' };
    const en = { open: 'Open', claimed: 'Claimed', blocked: 'Blocked', needs_you: 'Needs you', done: 'Done', cancelled: 'Cancelled' };
    return (isZh ? zh[status] : en[status]) || status;
  }

  function boardStatusPillClass(status) {
    if (status === 'claimed') return 'is-ok';
    if (status === 'needs_you' || status === 'blocked') return 'is-warn';
    if (status === 'done') return 'is-ok';
    return '';
  }

  function formatLeaseCountdown(claim) {
    if (!claim || !claim.expiresAt) return '';
    const diffMs = Date.parse(claim.expiresAt) - Date.now();
    if (!Number.isFinite(diffMs) || diffMs <= 0) return isZh ? '租约到期' : 'Expired';
    const mins = Math.max(1, Math.ceil(diffMs / 60000));
    return isZh ? `剩余 ${mins}m` : `${mins}m left`;
  }

  async function handleBoardAction(action, threadId) {
    const actor = { id: 'human:mobile', name: isZh ? '手机端主人' : 'Owner (Mobile)', kind: 'human' };
    const thread = (state.board.threads || []).find((t) => t.id === threadId);
    if (!thread) return;
    if (state.liveDaemon) {
      try {
        if (action === 'claim') {
          await apiFetch(`/api/v1/board/threads/${encodeURIComponent(threadId)}/claim`, {
            method: 'POST',
            body: JSON.stringify({ actor, leaseSeconds: 900 }),
          });
        } else if (action === 'complete') {
          await apiFetch(`/api/v1/board/threads/${encodeURIComponent(threadId)}/complete`, {
            method: 'POST',
            body: JSON.stringify({
              actor: thread.claim?.actor || actor,
              leaseToken: thread.claim?.leaseToken,
              summary: isZh ? '已在移动端确认完成。' : 'Completed from mobile companion.',
            }),
          });
        }
        await refreshAllDaemonData();
        return;
      } catch {
        // fall through to optimistic local update
      }
    }
    if (action === 'claim') {
      thread.status = 'claimed';
      thread.claim = { actor, expiresAt: new Date(Date.now() + 15 * 60_000).toISOString(), leaseToken: 'local_lease' };
    } else if (action === 'complete') {
      thread.status = 'done';
      thread.claim = undefined;
    }
    renderAll();
  }

  async function handleQuickBoardPost(title, channelSlug) {
    const clean = (title || '').trim();
    if (!clean) return;
    const slug = channelSlug && channelSlug !== 'all' ? channelSlug : 'inbox';
    const actor = { id: 'human:mobile', name: isZh ? '手机端主人' : 'Owner (Mobile)', kind: 'human' };
    if (state.liveDaemon) {
      try {
        await apiFetch('/api/v1/board/threads', {
          method: 'POST',
          body: JSON.stringify({ channelSlug: slug, title: clean, kind: 'task', priority: 'normal', author: actor }),
        });
        await refreshAllDaemonData();
        return;
      } catch {
        // fall through to local optimistic create
      }
    }
    state.board.threads.unshift({
      id: `bth-local-${Date.now()}`,
      channelSlug: slug,
      kind: 'task',
      title: clean,
      status: 'open',
      priority: 'normal',
      blockedBy: [],
      messages: [],
    });
    renderAll();
  }

  function renderOutcomesTab(container) {
    const channels = state.board?.channels || [];
    const allThreads = state.board?.threads || [];
    const filter = state.boardChannelFilter || 'all';
    const visibleThreads = filter === 'all' ? allThreads : allThreads.filter((t) => t.channelSlug === filter);

    container.innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <span style="font-size:16px;font-weight:500;">${isZh ? `协同任务板 (${visibleThreads.length})` : `Board (${visibleThreads.length})`}</span>
        <span class="mono" style="font-size:11px;color:var(--pipi-text-muted);">${state.liveDaemon ? (isZh ? '实时同步' : 'Live') : (isZh ? '本地预览' : 'Preview')}</span>
      </div>
      <div style="display:flex;gap:6px;overflow-x:auto;padding-bottom:2px;">
        <button class="pipi-btn pipi-btn-desktop ${filter === 'all' ? 'pipi-btn-primary' : ''}" data-board-ch="all" type="button">${isZh ? '全部' : 'All'}</button>
        ${channels.map((c) => `<button class="pipi-btn pipi-btn-desktop ${filter === c.slug ? 'pipi-btn-primary' : ''}" data-board-ch="${escapeHtml(c.slug)}" type="button">#${escapeHtml(c.slug)}</button>`).join('')}
      </div>
      <form id="board-quick-form" style="display:flex;gap:8px;align-items:center;">
        <input id="board-quick-input" type="text" placeholder="${isZh ? '发布一条新任务到当前频道…' : 'Post a task to this channel…'}" style="flex:1;min-width:0;padding:8px 10px;border-radius:10px;border:1px solid var(--pipi-border-subtle);background:var(--pipi-bg-elevated);color:var(--pipi-text-primary);font-size:13px;" />
        <button class="pipi-btn pipi-btn-desktop pipi-btn-primary" type="submit">${isZh ? '发布' : 'Post'}</button>
      </form>
      ${visibleThreads.length === 0 ? `
        <div style="font-size:13px;color:var(--pipi-text-muted);padding:8px 0;">${isZh ? '该频道暂无任务。' : 'No tasks in this channel.'}</div>
      ` : visibleThreads.slice(0, 8).map((th) => {
        const leaseStr = th.status === 'claimed' ? formatLeaseCountdown(th.claim) : '';
        const holder = th.claim?.actor?.name || '';
        const meta = [`#${th.channelSlug}`, holder, leaseStr].filter(Boolean).join(' · ');
        return `
        <article class="pipi-list-card">
          <div class="pipi-list-card-head">
            <div>
              <div class="pipi-list-card-title">${escapeHtml(th.title)}</div>
              <div class="pipi-list-card-sub mono" style="font-size:11px;">${escapeHtml(meta)}</div>
            </div>
            <span class="pipi-pill ${boardStatusPillClass(th.status)} mono">${escapeHtml(boardStatusLabel(th.status))}</span>
          </div>
          <div style="display:flex;justify-content:flex-end;align-items:center;gap:8px;">
            ${th.status === 'open' ? `<button class="pipi-btn pipi-btn-desktop" data-board-act="claim" data-tid="${escapeHtml(th.id)}" type="button">${isZh ? '认领' : 'Claim'}</button>` : ''}
            ${th.status !== 'done' && th.status !== 'cancelled' && th.status !== 'blocked' ? `<button class="pipi-btn pipi-btn-desktop pipi-btn-primary" data-board-act="complete" data-tid="${escapeHtml(th.id)}" type="button">${isZh ? '完成' : 'Complete'}</button>` : ''}
          </div>
        </article>`;
      }).join('')}

      <div style="display:flex;justify-content:space-between;align-items:center;margin-top:8px;">
        <span style="font-size:15px;font-weight:500;">${copy.outcomes(state.outcomes.length)}</span>
        <button class="pipi-btn pipi-btn-desktop" id="btn-new-outcome" type="button">
          <svg class="pipi-icon-mobile" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <line x1="12" y1="5" x2="12" y2="19"></line>
            <line x1="5" y1="12" x2="19" y2="12"></line>
          </svg>
          <span>${copy.new}</span>
        </button>
      </div>
      ${state.outcomes.map((out) => `
        <article class="pipi-list-card">
          <div class="pipi-list-card-head">
            <div>
              <div class="pipi-list-card-title">${escapeHtml(out.title)}</div>
              <div class="pipi-list-card-sub">${escapeHtml(out.goal)}</div>
            </div>
            <span class="pipi-pill ${statusPillClass(out.status)} mono">${escapeHtml(statusLabel(out.status))}</span>
          </div>
          <div style="display:flex;justify-content:space-between;align-items:center;gap:8px;">
            <span class="mono" style="font-size:11px;color:var(--pipi-text-muted);">
              ${escapeHtml(domainLabel(out.domain))} · ${escapeHtml(harnessLabel(out.preferredHarness))} · $${Number(out.spentTodayUsd || 0).toFixed(2)}/$${Number(out.dailyBudgetUsd || 2).toFixed(0)}
            </span>
            <button class="pipi-btn pipi-btn-desktop ${out.status === 'needs_you' ? 'pipi-btn-primary' : ''}" data-eval-id="${escapeHtml(out.id)}" type="button">${out.status === 'needs_you' ? copy.evaluateNeedsYou : copy.evaluateActive}</button>
          </div>
        </article>
      `).join('')}
    `;

    container.querySelectorAll('[data-board-ch]').forEach((btn) => {
      btn.addEventListener('click', () => {
        state.boardChannelFilter = btn.dataset.boardCh || 'all';
        renderAll();
      });
    });
    container.querySelectorAll('[data-board-act]').forEach((btn) => {
      btn.addEventListener('click', () => handleBoardAction(btn.dataset.boardAct, btn.dataset.tid));
    });
    $('#board-quick-form')?.addEventListener('submit', (e) => {
      e.preventDefault();
      const input = $('#board-quick-input');
      if (input && input.value.trim()) {
        const val = input.value;
        input.value = '';
        handleQuickBoardPost(val, state.boardChannelFilter);
      }
    });
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
          <h3 class="pipi-empty-title">${copy.allCaughtUp}</h3>
          <p class="pipi-empty-desc">${copy.allCaughtUpDesc}</p>
          <button class="pipi-btn pipi-btn-primary" id="btn-empty-new-outcome" type="button">
            <svg class="pipi-icon-mobile" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <line x1="12" y1="5" x2="12" y2="19"></line>
              <line x1="5" y1="12" x2="19" y2="12"></line>
            </svg>
            <span>${copy.assignOutcome}</span>
          </button>
        </div>
      `;
      $('#btn-empty-new-outcome')?.addEventListener('click', openCreateOutcomeFormSheet);
      return;
    }

    const card = pending.find((d) => d.id === state.activeDecisionId) || pending[0];
    const rest = pending.filter((d) => d.id !== card.id);
    const ev = card.evidence?.[0];
    container.innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <strong style="font-size:16px;">${copy.needsYou(pending.length)}</strong>
        <span class="pipi-pill is-warn mono">${escapeHtml(severityLabel(card.severity))}</span>
      </div>
      <article class="pipi-list-card swipe-card-anim" id="needs-you-active-card">
        <div class="pipi-list-card-head">
          <div class="pipi-list-card-title">${escapeHtml(card.title)}</div>
          <span class="pipi-pill mono">${escapeHtml(categoryLabel(card.category))}</span>
        </div>
        <div class="pipi-list-card-sub">${escapeHtml(card.summary)}</div>
        ${ev ? `
          <div class="pipi-evidence-box">
            <span class="mono" style="font-size:11px;color:var(--pipi-soul-secondary);">${copy.r2Evidence} · ${escapeHtml(evidenceKindLabel(ev.kind))}</span>
            <div style="font-size:12px;font-weight:600;">${escapeHtml(ev.caption)}</div>
            <div class="mono" style="font-size:10px;color:var(--pipi-text-muted);word-break:break-all;">${escapeHtml(ev.r2Key)}</div>
          </div>
        ` : ''}
        <div class="pipi-field-group">
          <label class="pipi-field-label" for="ny-steer-note">${copy.steerNote}</label>
          <input class="pipi-input" id="ny-steer-note" placeholder="${copy.steerPlaceholder}" />
        </div>
        <div class="pipi-btn-row">
          <button class="pipi-btn pipi-btn-danger" id="btn-ny-reject" type="button">
            <svg class="pipi-icon-mobile" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <line x1="18" y1="6" x2="6" y2="18"></line>
              <line x1="6" y1="6" x2="18" y2="18"></line>
            </svg>
            <span>${copy.defer}</span>
          </button>
          <button class="pipi-btn pipi-btn-primary" id="btn-ny-approve" type="button">
            <svg class="pipi-icon-mobile" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <polyline points="20 6 9 17 4 12"></polyline>
            </svg>
            <span>${copy.approve}</span>
          </button>
        </div>
      </article>
      ${rest.length > 0 ? `
        <div class="pipi-section-label">接下来</div>
        ${rest.map((d) => `
          <button class="pipi-list-card pipi-decision-row" data-decision-id="${escapeHtml(d.id)}" type="button">
            <div class="pipi-list-card-head">
              <div>
                <div class="pipi-list-card-title">${escapeHtml(d.title)}</div>
                <div class="pipi-list-card-sub">${escapeHtml(d.summary)}</div>
              </div>
              <span class="pipi-pill ${d.severity === 'critical' ? 'is-warn' : 'is-soul'} mono">${escapeHtml(severityLabel(d.severity))}</span>
            </div>
          </button>
        `).join('')}
      ` : ''}
    `;

    $('#btn-ny-approve')?.addEventListener('click', () => handleResolveDecision(card, true));
    $('#btn-ny-reject')?.addEventListener('click', () => handleResolveDecision(card, false));
    container.querySelectorAll('[data-decision-id]').forEach((btn) => {
      btn.addEventListener('click', () => {
        state.activeDecisionId = btn.dataset.decisionId;
        renderActiveTab();
      });
    });
  }

  function renderMuseTab(container) {
    container.innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <strong style="font-size:16px;">${copy.chatTitle}</strong>
        <button class="pipi-btn pipi-btn-desktop" id="btn-voice-toggle" type="button">
          <span>${state.voiceListening ? copy.stopVoice : copy.voice}</span>
        </button>
      </div>
      <div class="muse-grid">
        <div class="pipi-list-card">
          <span class="mono" style="font-size:10px;color:var(--pipi-status-ok);">${copy.life}</span>
          <div class="pipi-list-card-title">NH962 值机</div>
          <div class="pipi-list-card-sub">已同步到 Apple 日历</div>
        </div>
        <div class="pipi-list-card">
          <span class="mono" style="font-size:10px;color:var(--pipi-soul-secondary);">${copy.work}</span>
          <div class="pipi-list-card-title">PR #42 CLS 修复</div>
          <div class="pipi-list-card-sub">R2 录屏已验证</div>
        </div>
      </div>
      <div style="display:flex;flex-direction:column;gap:8px;">
        ${state.chatMessages.slice(-4).map((m) => `
          <div class="chat-bubble ${m.role === 'user' ? 'is-user' : ''}">
            <div class="mono" style="font-size:10px;color:var(--pipi-text-muted);margin-bottom:3px;">${m.role === 'user' ? '你' : '助手'} · ${escapeHtml(harnessLabel(m.provider || state.selectedHarness))}</div>
            <div>${m.role === 'user' ? `<div style="white-space:pre-wrap;">${escapeHtml(m.text)}</div>` : renderRichChatContent(m.text)}</div>
          </div>
        `).join('')}
      </div>
      <form id="muse-chat-form" class="pipi-field-group">
        <div style="display:flex;gap:8px;">
          <input class="pipi-input" id="muse-chat-input" placeholder="${copy.messageVia(harnessLabel(state.selectedHarness))}" required />
          <button class="pipi-btn pipi-btn-primary" type="submit">
            <svg class="pipi-icon-mobile" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <line x1="22" y1="2" x2="11" y2="13"></line>
              <polygon points="22 2 15 22 11 13 2 9 22 2"></polygon>
            </svg>
            <span>${copy.send}</span>
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

    container.querySelectorAll('[data-diagram-toggle="1"]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const card = btn.closest('[data-diagram-card="1"]');
        if (!card) return;
        const preview = card.querySelector('[data-diagram-preview="1"]');
        const source = card.querySelector('[data-diagram-source="1"]');
        if (!preview || !source) return;
        const showingSource = !source.hidden;
        source.hidden = showingSource;
        preview.hidden = !showingSource;
        btn.textContent = showingSource ? '源码' : '预览';
      });
    });
  }

  function renderFleetTab(container) {
    const rtt = state.cloudflare?.tunnelRttMs ?? 18;
    container.innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <strong style="font-size:16px;">${copy.connectedDevices(state.nodes.length)}</strong>
        <span class="pipi-pill is-ok mono">${state.liveDaemon ? `${rtt}ms` : copy.local}</span>
      </div>
      ${state.nodes.map((node) => `
        <article class="pipi-list-card">
          <div class="pipi-list-card-head">
            <div style="display:flex;align-items:center;gap:10px;">
              <span class="dot-pulse is-${escapeHtml(node.vitality || 'alive')}"></span>
              <div>
                <div class="pipi-list-card-title">${escapeHtml(node.displayName)}</div>
                <div class="pipi-list-card-sub mono">${escapeHtml(nodeKindLabel(node.kind))} · CPU ${Math.round(node.cpuLoadPct || 0)}% · RAM ${Math.round(node.memoryUsedPct || 0)}%</div>
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
        <strong style="font-size:16px;">${copy.soulMemory(score)}</strong>
        <button class="pipi-btn pipi-btn-primary" id="btn-run-dream" type="button">
          <svg class="pipi-icon-mobile" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"></path>
          </svg>
          <span>${copy.dream}</span>
        </button>
      </div>
      ${diffs.map((d) => `
        <article class="pipi-list-card">
          <div class="pipi-list-card-head">
            <div>
              <div class="pipi-list-card-title">${escapeHtml(d.title)}</div>
              <div class="pipi-list-card-sub mono">${escapeHtml(d.targetFile)} · ${escapeHtml(operationLabel(d.operation))}</div>
            </div>
            <span class="pipi-pill ${d.reviewStatus === 'approved' ? 'is-ok' : 'is-soul'} mono">${escapeHtml(reviewStatusLabel(d.reviewStatus))}</span>
          </div>
          <div class="pipi-list-card-sub">${escapeHtml(d.proposedValue)}</div>
          ${d.reviewStatus === 'pending' ? `
            <div class="pipi-btn-row">
              <button class="pipi-btn" data-diff-revert="${escapeHtml(d.diffId)}" type="button">${copy.revert}</button>
              <button class="pipi-btn pipi-btn-primary" data-diff-approve="${escapeHtml(d.diffId)}" type="button">${copy.adopt}</button>
            </div>
          ` : ''}
        </article>
      `).join('')}
      <article class="pipi-list-card">
        <div class="pipi-list-card-title">${copy.learnedFacts}</div>
        <div class="pipi-list-card-sub mono">${copy.factsSkills(state.memory.facts.length, state.memory.skills.length)}</div>
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
        <strong style="font-size:17px;">${copy.selectHarness}</strong>
        <button class="pipi-btn pipi-btn-desktop" id="sheet-close-btn" type="button">${copy.close}</button>
      </div>
      ${HARNESS_META.map((h) => `
        <button class="pipi-list-card" data-pick-harness="${h.id}" type="button" style="text-align:left;cursor:pointer;">
          <div class="pipi-list-card-head">
            <div class="pipi-list-card-title">${escapeHtml(h.label)}</div>
            ${state.selectedHarness === h.id ? `<span class="pipi-pill is-ok mono">${copy.current}</span>` : ''}
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
        <strong style="font-size:17px;">${copy.newOutcome}</strong>
        <button class="pipi-btn pipi-btn-desktop" id="sheet-close-btn" type="button">${copy.cancel}</button>
      </div>
      <form id="create-outcome-form" style="display:flex;flex-direction:column;gap:12px;">
        <div class="pipi-field-group">
          <label class="pipi-field-label" for="out-title">${copy.outcomeTitle}</label>
          <input class="pipi-input" id="out-title" placeholder="${copy.outcomeTitlePlaceholder}" required />
        </div>
        <div class="pipi-field-group">
          <label class="pipi-field-label" for="out-domain">${copy.domain}</label>
          <select class="pipi-select" id="out-domain">
            <option value="dev">${copy.domainDev}</option>
            <option value="work">${copy.work}</option>
            <option value="daily_life">${copy.domainDailyLife}</option>
            <option value="infra">${copy.domainInfra}</option>
          </select>
        </div>
        <div class="pipi-field-group">
          <label class="pipi-field-label" for="out-goal">${copy.goal}</label>
          <textarea class="pipi-textarea" id="out-goal" rows="3" placeholder="${copy.goalPlaceholder}" required></textarea>
        </div>
        <button class="pipi-btn pipi-btn-primary pipi-btn-full" type="submit">
          <svg class="pipi-icon-mobile" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <polyline points="20 6 9 17 4 12"></polyline>
          </svg>
          <span>${copy.launchOutcome}</span>
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
    $('#btn-toggle-theme span').textContent = isLight ? copy.themeObsidian : copy.themeVellum;
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
