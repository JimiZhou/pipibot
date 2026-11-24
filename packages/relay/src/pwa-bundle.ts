/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/relay - pwa-bundle.ts
 * Dual-Perspective E2EE WebUI & Mobile PWA Companion served by:
 *   - https://pipibot.jimizhou.com/c/<hostId>, /pair, /app (Zero-Knowledge E2EE Relay)
 *   - PiPiBot Mac App local server & Linux/macOS Daemon Hub
 *
 * UX & Architecture Highlights:
 * 1. Default Primary Control Node Perspective (`主节点总控`):
 *    - Always connected to the Primary Control Node (macOS / master host) for global fleet orchestration,
 *      natural-language butler chat, approvals, unified diff review, and 1-click jump into any node.
 * 2. Native Ovis / Herdr-Style Node Harness TUI + Live Headless Browser (`节点 Harness TUI`):
 *    - Dedicated parallel E2EE connection to any selected node (never disconnects the primary node).
 *    - Native real-time streaming over E2EE `agent_stream` push envelopes (zero polling lag).
 *    - Full ANSI 16/256/24-bit color & `\r` overwrite terminal renderer, direct keyboard capture,
 *      1-tap TUI control keys (`Enter`, `Esc`, `Tab`, `↑`, `↓`, `Ctrl+C`, `Ctrl+D`), and interactive Shell.
 *    - Gemini Spark / Mariner-style Remote Headless Browser CDP Live Viewport (`browser_frame` JPEG stream)
 *      with direct click, scroll, type, URL navigation, and side-by-side Split TUI + Browser mode!
 */

export function renderUniversalManifest(): string {
  return JSON.stringify(
    {
      name: 'PiPiBot Companion',
      short_name: 'PiPiBot',
      description: '零知识端到端加密的个人 AI 管家团队与远程 Harness TUI 控制台',
      start_url: '/app',
      scope: '/',
      display: 'standalone',
      background_color: '#FFFFFF',
      theme_color: '#171717',
      orientation: 'portrait',
      icons: [
        {
          src: '/icon.svg?v=2',
          sizes: 'any',
          type: 'image/svg+xml',
          purpose: 'any maskable',
        },
      ],
    },
    null,
    2,
  );
}

/**
 * Official "PiPi Halo" Hardware-Robot SVG Icon — 1:1 vector match with `scripts/generate-app-icons.swift`
 * & `PipiBotMarkView.swift`.
 */
export function renderOfficialBrandMarkSVG(size = 28): string {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 1024 1024" aria-hidden="true">
  <defs>
    <linearGradient id="pipiField" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#FDFCF9"/>
      <stop offset="55%" stop-color="#F5F2EC"/>
      <stop offset="100%" stop-color="#E8E3D9"/>
    </linearGradient>
    <radialGradient id="pipiHalo" cx="50%" cy="49%" r="44%">
      <stop offset="0%" stop-color="#38BDF8" stop-opacity="0.16"/>
      <stop offset="52%" stop-color="#63F5E6" stop-opacity="0.07"/>
      <stop offset="100%" stop-color="#F5F2EC" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="pipiChassis" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#FFFFFF"/>
      <stop offset="56%" stop-color="#F4F1EA"/>
      <stop offset="100%" stop-color="#DCD6C9"/>
    </linearGradient>
    <linearGradient id="pipiRim" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.95"/>
      <stop offset="50%" stop-color="#C5BEB2" stop-opacity="0.88"/>
      <stop offset="100%" stop-color="#A79F93" stop-opacity="0.82"/>
    </linearGradient>
    <linearGradient id="pipiVisor" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#1E3A8A"/>
      <stop offset="55%" stop-color="#172554"/>
      <stop offset="100%" stop-color="#0F172A"/>
    </linearGradient>
    <radialGradient id="pipiLensAura" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#67E8F9" stop-opacity="0.52"/>
      <stop offset="55%" stop-color="#38BDF8" stop-opacity="0.16"/>
      <stop offset="100%" stop-color="#172554" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="pipiLensCore" cx="46%" cy="40%" r="58%">
      <stop offset="0%" stop-color="#F7FDFF"/>
      <stop offset="52%" stop-color="#67E8F9"/>
      <stop offset="100%" stop-color="#06B6D4"/>
    </radialGradient>
  </defs>
  <rect x="44" y="44" width="936" height="936" rx="212" fill="url(#pipiField)" stroke="#171717" stroke-opacity="0.10" stroke-width="8"/>
  <circle cx="512" cy="504" r="430" fill="url(#pipiHalo)"/>
  <path d="M365.04 160 L396.5 160 C448.48 160 468.11 185.34 512 185.34 C555.89 185.34 575.52 160 627.5 160 L658.96 160 C751.96 160 842 250.04 842 343.04 L842 680.96 C842 773.96 751.96 864 658.96 864 L365.04 864 C272.04 864 182 773.96 182 680.96 L182 343.04 C182 250.04 272.04 160 365.04 160 Z" fill="url(#pipiChassis)" stroke="url(#pipiRim)" stroke-width="14"/>
  <rect x="484" y="292" width="56" height="11" rx="5.5" fill="#B9B2A6" fill-opacity="0.82"/>
  <rect x="498" y="293.5" width="28" height="8" rx="4" fill="#0284C7"/>
  <rect x="244.7" y="394.8" width="534.6" height="260.5" rx="130.25" fill="url(#pipiVisor)" stroke="#3B4A7A" stroke-width="10"/>
  <line x1="369" y1="410" x2="655" y2="410" stroke="#FFFFFF" stroke-opacity="0.28" stroke-width="7" stroke-linecap="round"/>
  <ellipse cx="376.7" cy="525" rx="108" ry="116" fill="url(#pipiLensAura)"/>
  <ellipse cx="647.3" cy="525" rx="108" ry="116" fill="url(#pipiLensAura)"/>
  <ellipse cx="376.7" cy="525" rx="70.95" ry="84.15" fill="url(#pipiLensCore)"/>
  <ellipse cx="647.3" cy="525" rx="70.95" ry="84.15" fill="url(#pipiLensCore)"/>
  <ellipse cx="352" cy="488" rx="18" ry="12" fill="#FFFFFF" fill-opacity="0.88"/>
  <ellipse cx="622.6" cy="488" rx="18" ry="12" fill="#FFFFFF" fill-opacity="0.88"/>
</svg>`;
}

export function renderUniversalIconSVG(): string {
  return renderOfficialBrandMarkSVG(192);
}

export function renderUniversalPWAHTML(options?: {
  relayMode?: boolean;
  defaultHostTitle?: string;
  stunUrls?: string[];
}): string {
  const relayMode = options?.relayMode ?? true;
  const hostTitle = options?.defaultHostTitle ?? 'PiPiBot';
  const stunUrls = JSON.stringify(
    options?.stunUrls ?? ['stun:stun.l.google.com:19302', 'stun:stun.cloudflare.com:3478'],
  );

  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover" />
  <meta name="apple-mobile-web-app-capable" content="yes" />
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
  <meta name="apple-mobile-web-app-title" content="PiPiBot" />
  <link rel="manifest" href="/manifest.webmanifest" />
  <link rel="apple-touch-icon" href="/icon.svg?v=2" />
  <link rel="icon" type="image/svg+xml" href="/icon.svg?v=2" />
  <title>${hostTitle} · Companion</title>
  <style>
    :root {
      --canvas: #FFFFFF;
      --surface: #FFFFFF;
      --surface-soft: #F8F8F9;
      --surface-hover: #EFEFF1;
      --glass: rgba(255, 255, 255, 0.92);
      --border: rgba(23, 23, 23, 0.08);
      --border-strong: rgba(23, 23, 23, 0.16);
      --ink: #171717;
      --ink-2: #52525B;
      --ink-3: #71717A;
      --soul: #171717;
      --soul-ink: #FFFFFF;
      --soul-soft: rgba(23, 23, 23, 0.06);
      --soul-glow: rgba(23, 23, 23, 0.08);
      --ok: #047857;
      --ok-soft: rgba(4, 120, 87, 0.11);
      --warn: #B45309;
      --warn-soft: rgba(180, 83, 9, 0.11);
      --err: #B91C1C;
      --err-soft: rgba(185, 28, 28, 0.11);
      --diff-add: rgba(4, 120, 87, 0.11);
      --diff-del: rgba(185, 28, 28, 0.10);
      --shadow-sm: 0 1px 4px rgba(23, 23, 23, 0.04);
      --shadow-md: 0 12px 32px rgba(23, 23, 23, 0.08);
      --radius: 10px;
      --term-bg: #0B0C0E;
      --term-surface: #141518;
      --term-border: rgba(255, 255, 255, 0.08);
      --term-ink: #F4F4F5;
      --term-muted: #A1A1AA;
    }
    [data-theme="dark"] {
      --canvas: #0F1012;
      --surface: #141518;
      --surface-soft: #181A1E;
      --surface-hover: #22242A;
      --glass: rgba(15, 16, 18, 0.90);
      --border: rgba(255, 255, 255, 0.08);
      --border-strong: rgba(255, 255, 255, 0.16);
      --ink: #F4F4F5;
      --ink-2: #A1A1AA;
      --ink-3: #71717A;
      --soul: #F4F4F5;
      --soul-ink: #0F1012;
      --soul-soft: rgba(255, 255, 255, 0.08);
      --soul-glow: rgba(0, 0, 0, 0.20);
      --ok: #10B981;
      --ok-soft: rgba(16, 185, 129, 0.14);
      --warn: #F59E0B;
      --warn-soft: rgba(245, 158, 11, 0.14);
      --err: #EF4444;
      --err-soft: rgba(239, 68, 68, 0.14);
      --diff-add: rgba(16, 185, 129, 0.14);
      --diff-del: rgba(239, 68, 68, 0.14);
      --shadow-sm: 0 2px 10px rgba(0, 0, 0, 0.25);
      --shadow-md: 0 14px 36px rgba(0, 0, 0, 0.45);
    }
    @media (prefers-color-scheme: dark) {
      :root:not([data-theme="light"]) {
        --canvas: #0F1012;
        --surface: #141518;
        --surface-soft: #181A1E;
        --surface-hover: #22242A;
        --glass: rgba(15, 16, 18, 0.90);
        --border: rgba(255, 255, 255, 0.08);
        --border-strong: rgba(255, 255, 255, 0.16);
        --ink: #F4F4F5;
        --ink-2: #A1A1AA;
        --ink-3: #71717A;
        --soul: #F4F4F5;
        --soul-ink: #0F1012;
        --soul-soft: rgba(255, 255, 255, 0.08);
        --soul-glow: rgba(0, 0, 0, 0.20);
        --ok: #10B981;
        --ok-soft: rgba(16, 185, 129, 0.14);
        --warn: #F59E0B;
        --warn-soft: rgba(245, 158, 11, 0.14);
        --err: #EF4444;
        --err-soft: rgba(239, 68, 68, 0.14);
        --diff-add: rgba(16, 185, 129, 0.14);
        --diff-del: rgba(239, 68, 68, 0.14);
        --shadow-sm: 0 2px 10px rgba(0, 0, 0, 0.25);
        --shadow-md: 0 14px 36px rgba(0, 0, 0, 0.45);
      }
    }

    * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
    html, body {
      margin: 0; padding: 0; height: 100%; background: var(--canvas); color: var(--ink);
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", sans-serif;
      -webkit-font-smoothing: antialiased; overflow: hidden;
    }

    /* Root App Shell */
    .shell {
      display: flex; flex-direction: column; height: 100dvh; width: 100%; overflow: hidden;
    }

    /* Global Top Header with 2-Tab Perspective Switch */
    .global-header {
      flex-shrink: 0; z-index: 30;
      display: grid; grid-template-columns: 1fr auto 1fr; align-items: center; gap: 12px;
      padding: calc(env(safe-area-inset-top) + 8px) 16px 8px;
      background: var(--glass);
      backdrop-filter: saturate(180%) blur(22px);
      -webkit-backdrop-filter: saturate(180%) blur(22px);
      border-bottom: 1px solid var(--border);
    }
    .brand { display: flex; align-items: center; gap: 9px; min-width: 0; }
    .brand-logo { width: 28px; height: 28px; border-radius: 8px; flex-shrink: 0; }
    .brand-title { font-size: 14.5px; font-weight: 720; letter-spacing: -0.02em; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .brand-sub { font-size: 11px; color: var(--ink-3); display: flex; align-items: center; gap: 5px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

    .dot { width: 7px; height: 7px; border-radius: 50%; background: var(--warn); flex-shrink: 0; display: inline-block; }
    .dot.ok { background: var(--ok); box-shadow: 0 0 0 3px var(--ok-soft); }
    .dot.err { background: var(--err); }
    .dot.pulse { animation: dotPulse 1.5s ease-in-out infinite; }
    @keyframes dotPulse { 0%,100% { opacity: 1; transform: scale(1); } 50% { opacity: 0.45; transform: scale(0.82); } }

    /* Top-Level 2-Tab Segmented Switch */
    .root-tabs {
      display: inline-flex; align-items: center; gap: 3px; padding: 3px;
      background: var(--surface-soft); border: 1px solid var(--border); border-radius: 12px;
    }
    .root-tab {
      border: 0; background: transparent; color: var(--ink-2);
      padding: 6px 14px; border-radius: 9px; font-size: 12.5px; font-weight: 650;
      cursor: pointer; display: inline-flex; align-items: center; gap: 6px; white-space: nowrap;
      transition: all 140ms ease;
    }
    .root-tab:hover { color: var(--ink); }
    .root-tab.active {
      background: var(--surface); color: var(--ink);
      box-shadow: 0 1px 4px rgba(0,0,0,0.08), 0 0 0 1px var(--border);
    }
    .root-tab-badge {
      font-size: 10px; font-weight: 700; padding: 1px 6px; border-radius: 999px;
      background: var(--ok-soft); color: var(--ok);
    }

    .header-right {
      display: flex; align-items: center; justify-content: flex-end; gap: 7px; min-width: 0;
    }
    .pill-btn {
      border: 1px solid var(--border); background: var(--surface); color: var(--ink);
      padding: 5px 10px; border-radius: 999px; font-size: 11.5px; font-weight: 620;
      display: inline-flex; align-items: center; gap: 5px; cursor: pointer; text-decoration: none;
      white-space: nowrap; transition: background 120ms ease, transform 90ms ease;
    }
    .pill-btn:hover { background: var(--surface-hover); }
    .pill-btn:active { transform: scale(0.96); }
    .pill-btn.ok { color: var(--ok); border-color: var(--ok-soft); background: var(--ok-soft); }

    /* Workspace Container */
    .workspace {
      flex: 1; min-height: 0; display: flex; overflow: hidden; position: relative;
    }
    .view-pane {
      display: none; width: 100%; height: 100%; min-height: 0; overflow: hidden;
    }
    .view-pane.active { display: flex; }

    /* =========================================================================
       TAB 1: PRIMARY CONTROL NODE VIEW (主节点总控)
       ========================================================================= */
    .master-layout {
      display: grid; grid-template-columns: 276px minmax(0, 1fr); width: 100%; height: 100%; overflow: hidden;
    }
    .master-rail {
      display: flex; flex-direction: column; gap: 10px; padding: 14px 12px;
      background: var(--surface-soft); border-right: 1px solid var(--border);
      overflow-y: auto; min-height: 0;
    }
    .rail-label {
      font-size: 11px; font-weight: 500; color: var(--ink-3);
      padding: 4px 8px 2px;
    }
    .master-card {
      background: var(--surface); border: 1px solid var(--border); border-radius: 14px;
      padding: 11px 12px; display: flex; flex-direction: column; gap: 6px; box-shadow: var(--shadow-sm);
    }
    .subnav-list { display: flex; flex-direction: column; gap: 2px; }
    .subnav-btn {
      display: flex; align-items: center; justify-content: space-between; gap: 8px;
      width: 100%; padding: 8px 10px; border-radius: 10px; border: 0; background: transparent;
      color: var(--ink-2); font-size: 13px; font-weight: 560; text-align: left; cursor: pointer;
      transition: background 120ms ease, color 120ms ease;
    }
    .subnav-btn:hover { background: var(--surface-hover); color: var(--ink); }
    .subnav-btn.active { background: var(--surface); color: var(--ink); font-weight: 660; box-shadow: 0 1px 3px rgba(0,0,0,0.06); }

    .fleet-list { display: flex; flex-direction: column; gap: 6px; }
    .fleet-node-card {
      background: var(--surface); border: 1px solid var(--border); border-radius: 12px;
      padding: 9px 10px; display: flex; flex-direction: column; gap: 6px;
      transition: border-color 120ms ease, box-shadow 120ms ease;
    }
    .fleet-node-card:hover { border-color: var(--border-strong); box-shadow: var(--shadow-sm); }
    .fleet-node-head { display: flex; align-items: center; gap: 7px; min-width: 0; }
    .fleet-node-name { font-size: 12.5px; font-weight: 650; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; flex: 1; }
    .fleet-node-caps { font-size: 11px; color: var(--ink-3); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .fleet-node-actions { display: flex; align-items: center; justify-content: space-between; gap: 6px; }

    .master-main {
      display: flex; flex-direction: column; min-width: 0; height: 100%; overflow: hidden; background: var(--canvas);
    }
    .master-scroll {
      flex: 1; overflow-y: auto; -webkit-overflow-scrolling: touch;
      padding: 18px 24px 24px; display: flex; flex-direction: column; gap: 12px;
      max-width: 920px; width: 100%; margin: 0 auto;
    }
    .composer-wrap {
      flex-shrink: 0; padding: 10px 24px 16px; max-width: 920px; width: 100%; margin: 0 auto;
    }
    .composer-box {
      display: flex; flex-direction: column; gap: 8px; padding: 11px 12px 9px 14px;
      background: var(--surface); border: 1px solid var(--border-strong); border-radius: 16px;
      box-shadow: 0 4px 18px rgba(0, 0, 0, 0.05); transition: border-color 140ms ease;
    }
    .composer-box:focus-within { border-color: var(--soul); }
    .composer-box textarea {
      width: 100%; resize: none; min-height: 36px; max-height: 160px; overflow-y: auto; border: 0;
      padding: 2px 0; font-size: 14px; line-height: 1.5; background: transparent; color: var(--ink);
      outline: none; font-family: inherit;
    }
    .composer-toolbar {
      display: flex; align-items: center; justify-content: space-between; gap: 8px;
      padding-top: 6px; border-top: 1px solid var(--border);
    }
    .send-btn {
      width: 30px; height: 30px; border-radius: 50%; border: 0; flex-shrink: 0;
      background: var(--ink); color: var(--canvas); font-size: 15px; font-weight: 700; cursor: pointer;
      display: grid; place-items: center; transition: transform 100ms ease-out;
    }
    .send-btn:active { transform: scale(0.92); }

    /* =========================================================================
       TAB 2: OVIS / HERDR NATIVE AGENT HARNESS TUI + LIVE HEADLESS BROWSER
       ========================================================================= */
    .herdr-layout {
      display: grid; grid-template-columns: 288px minmax(0, 1fr); width: 100%; height: 100%; overflow: hidden;
      background: var(--term-bg); color: var(--term-ink);
    }
    .herdr-rail {
      display: flex; flex-direction: column; gap: 10px; padding: 12px;
      background: var(--term-surface); border-right: 1px solid var(--term-border);
      overflow-y: auto; min-height: 0;
    }
    .herdr-section {
      background: rgba(255,255,255,0.03); border: 1px solid var(--term-border);
      border-radius: 12px; padding: 10px; display: flex; flex-direction: column; gap: 8px;
    }
    .herdr-label {
      font-size: 11px; font-weight: 500; color: var(--term-muted);
      display: flex; align-items: center; justify-content: space-between;
    }
    .herdr-select, .herdr-input {
      width: 100%; border: 1px solid rgba(255,255,255,0.12); background: #0A0C10; color: var(--term-ink);
      border-radius: 8px; padding: 7px 9px; font-size: 12px; font-family: inherit; outline: none;
    }
    .herdr-select:focus, .herdr-input:focus { border-color: #7C6CF6; }
    .herdr-select.mono, .herdr-input.mono { font-family: "JetBrains Mono", "SF Mono", Menlo, monospace; font-size: 11.5px; }

    .mode-pills {
      display: grid; grid-template-columns: repeat(3, 1fr); gap: 3px; padding: 3px;
      background: #0A0C10; border: 1px solid var(--term-border); border-radius: 9px;
    }
    .mode-pill {
      border: 0; background: transparent; color: var(--term-muted); font-size: 11px; font-weight: 650;
      padding: 5px 4px; border-radius: 6px; cursor: pointer; transition: all 120ms ease;
    }
    .mode-pill.active { background: #222736; color: #FFF; }

    .herdr-btn {
      border: 1px solid rgba(255,255,255,0.13); background: rgba(255,255,255,0.06); color: var(--term-ink);
      padding: 6px 10px; border-radius: 8px; font-size: 12px; font-weight: 620; cursor: pointer;
      display: inline-flex; align-items: center; justify-content: center; gap: 5px; white-space: nowrap;
      transition: background 110ms ease, border-color 110ms ease;
    }
    .herdr-btn:hover { background: rgba(255,255,255,0.11); border-color: rgba(255,255,255,0.22); }
    .herdr-btn.primary { background: #5B4CE4; border-color: #7C6CF6; color: #FFF; }
    .herdr-btn.primary:hover { background: #6C5DF2; }
    .herdr-btn.ok { background: rgba(16,185,129,0.18); border-color: rgba(16,185,129,0.4); color: #34D399; }
    .herdr-btn.danger { background: rgba(248,113,113,0.14); border-color: rgba(248,113,113,0.35); color: #FCA5A5; }
    .herdr-btn.active { background: #7C6CF6; border-color: #A598FF; color: #FFF; }

    .session-list { display: flex; flex-direction: column; gap: 5px; }
    .session-item {
      width: 100%; text-align: left; border: 1px solid transparent; background: rgba(255,255,255,0.025);
      color: var(--term-ink); border-radius: 10px; padding: 8px 9px; cursor: pointer;
      display: flex; flex-direction: column; gap: 4px; transition: all 110ms ease;
    }
    .session-item:hover { background: rgba(255,255,255,0.06); }
    .session-item.active { background: rgba(124,108,246,0.16); border-color: rgba(124,108,246,0.5); }
    .session-item-top { display: flex; align-items: center; gap: 6px; font-size: 12px; font-weight: 640; }
    .session-item-meta { font-size: 10.5px; color: var(--term-muted); display: flex; align-items: center; gap: 6px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }

    /* Herdr Main Stage (TUI + Live Browser Split / Switch) */
    .herdr-stage {
      display: flex; flex-direction: column; min-width: 0; height: 100%; overflow: hidden;
    }
    .stage-bar {
      flex-shrink: 0; display: flex; align-items: center; justify-content: space-between; gap: 10px; flex-wrap: wrap;
      padding: 8px 14px; background: #0E1117; border-bottom: 1px solid var(--term-border);
    }
    .stage-title-group { display: flex; align-items: center; gap: 8px; min-width: 0; flex: 1; }
    .stage-name { font-size: 13px; font-weight: 680; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .live-pill {
      font-size: 10.5px; font-weight: 700; padding: 2px 8px; border-radius: 999px;
      background: rgba(16,185,129,0.16); color: #34D399; border: 1px solid rgba(16,185,129,0.32);
      display: inline-flex; align-items: center; gap: 5px; flex-shrink: 0;
    }
    .live-pill.idle { background: rgba(255,255,255,0.06); color: var(--term-muted); border-color: var(--term-border); }

    .stage-view-switch {
      display: inline-flex; gap: 2px; padding: 3px; border-radius: 9px;
      background: #080A0E; border: 1px solid var(--term-border);
    }
    .stage-view-btn {
      border: 0; background: transparent; color: var(--term-muted); font-size: 11.5px; font-weight: 640;
      padding: 4px 10px; border-radius: 6px; cursor: pointer; white-space: nowrap;
    }
    .stage-view-btn.active { background: #1F2433; color: #FFF; }

    .stage-body {
      flex: 1; min-height: 0; display: flex; overflow: hidden; position: relative;
    }
    .stage-body.mode-tui .pane-tui { display: flex; flex: 1; }
    .stage-body.mode-tui .pane-browser { display: none; }
    .stage-body.mode-browser .pane-tui { display: none; }
    .stage-body.mode-browser .pane-browser { display: flex; flex: 1; }
    .stage-body.mode-split .pane-tui { display: flex; flex: 1; border-right: 1px solid var(--term-border); }
    .stage-body.mode-split .pane-browser { display: flex; flex: 1; }

    /* Native ANSI Streaming Terminal Pane */
    .pane-tui {
      flex-direction: column; min-width: 0; min-height: 0; position: relative; background: #0A0C10;
    }
    .tui-viewport {
      flex: 1; min-height: 0; overflow-y: auto; padding: 14px 16px 24px;
      font-family: "JetBrains Mono", "SF Mono", "Fira Code", Menlo, Consolas, monospace;
      font-size: 12.5px; line-height: 1.55; color: var(--term-ink);
      white-space: pre-wrap; word-break: break-word; outline: none;
      tab-size: 4;
    }
    .tui-viewport.direct-kb { box-shadow: inset 0 0 0 1.5px rgba(124,108,246,0.65); }
    .tui-cursor {
      display: inline-block; width: 7.5px; height: 14px; background: #7C6CF6;
      vertical-align: text-bottom; margin-left: 2px; animation: blink 1s step-end infinite;
    }
    @keyframes blink { 0%, 49% { opacity: 1; } 50%, 100% { opacity: 0; } }

    .jump-bottom-btn {
      position: absolute; right: 16px; bottom: 96px; z-index: 5;
      display: none; border: 1px solid rgba(124,108,246,0.5); background: rgba(17,20,27,0.92);
      color: #E6EDF3; font-size: 11.5px; font-weight: 640; padding: 5px 11px; border-radius: 999px; cursor: pointer;
      box-shadow: 0 6px 20px rgba(0,0,0,0.45);
    }
    .jump-bottom-btn.show { display: inline-flex; align-items: center; gap: 5px; }

    .tui-controls {
      flex-shrink: 0; padding: 8px 12px 10px; background: #0E1117; border-top: 1px solid var(--term-border);
      display: flex; flex-direction: column; gap: 7px;
    }
    .key-strip {
      display: flex; align-items: center; gap: 5px; overflow-x: auto; scrollbar-width: none;
    }
    .key-strip::-webkit-scrollbar { display: none; }
    .key-chip {
      border: 1px solid rgba(255,255,255,0.12); background: #161B26; color: #C9D1D9;
      padding: 3px 8px; border-radius: 6px; font-size: 11px; font-weight: 620;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace; cursor: pointer; white-space: nowrap;
    }
    .key-chip:hover { background: #222938; color: #FFF; border-color: rgba(255,255,255,0.25); }
    .key-chip.danger { color: #FCA5A5; border-color: rgba(248,113,113,0.3); }

    .tui-input-row { display: flex; align-items: center; gap: 7px; }
    .tui-prompt-glyph { color: #7C6CF6; font-family: monospace; font-weight: 700; font-size: 13px; flex-shrink: 0; }

    /* Remote Headless Browser Live Viewport Pane (Gemini Spark / Mariner Style) */
    .pane-browser {
      flex-direction: column; min-width: 0; min-height: 0; background: #090B0F;
    }
    .browser-chrome {
      flex-shrink: 0; display: flex; align-items: center; gap: 6px; padding: 8px 10px;
      background: #11151E; border-bottom: 1px solid var(--term-border); flex-wrap: wrap;
    }
    .browser-url-input {
      flex: 1; min-width: 160px; border: 1px solid rgba(255,255,255,0.12); background: #0A0C10;
      color: #E6EDF3; border-radius: 8px; padding: 6px 10px; font-size: 12px;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace; outline: none;
    }
    .browser-url-input:focus { border-color: #38BDF8; }
    .browser-tabs-strip {
      display: none; gap: 5px; padding: 5px 10px; background: #0D1017; border-bottom: 1px solid var(--term-border);
      overflow-x: auto; scrollbar-width: none;
    }
    .browser-tabs-strip.show { display: flex; }
    .browser-tab-pill {
      border: 1px solid var(--term-border); background: rgba(255,255,255,0.04); color: var(--term-muted);
      padding: 3px 9px; border-radius: 6px; font-size: 11px; max-width: 180px;
      white-space: nowrap; overflow: hidden; text-overflow: ellipsis; cursor: pointer;
    }
    .browser-tab-pill.active { background: rgba(56,189,248,0.15); border-color: rgba(56,189,248,0.45); color: #E0F2FE; }

    .browser-canvas-wrap {
      flex: 1; min-height: 0; position: relative; display: flex; align-items: center; justify-content: center;
      overflow: auto; padding: 10px; background: radial-gradient(circle at 50% 0%, rgba(56,189,248,0.06), transparent 60%);
    }
    .browser-screen-box {
      position: relative; display: inline-flex; max-width: 100%; max-height: 100%;
      border-radius: 10px; overflow: hidden; border: 1px solid rgba(255,255,255,0.12);
      box-shadow: 0 12px 36px rgba(0,0,0,0.55); background: #000;
    }
    .browser-screen-img {
      display: block; max-width: 100%; max-height: 100%; width: auto; height: auto;
      cursor: crosshair; user-select: none; -webkit-user-drag: none;
    }
    .click-ripple {
      position: absolute; width: 18px; height: 18px; margin: -9px 0 0 -9px; border-radius: 50%;
      border: 2px solid #38BDF8; background: rgba(56,189,248,0.32); pointer-events: none;
      animation: rippleOut 420ms ease-out forwards;
    }
    @keyframes rippleOut { 0% { transform: scale(0.4); opacity: 1; } 100% { transform: scale(2.1); opacity: 0; } }

    .browser-empty {
      text-align: center; max-width: 360px; padding: 24px 16px; color: var(--term-muted);
      display: flex; flex-direction: column; align-items: center; gap: 10px; font-size: 12.5px; line-height: 1.6;
    }
    .browser-input-bar {
      flex-shrink: 0; display: flex; align-items: center; gap: 6px; padding: 8px 10px;
      background: #11151E; border-top: 1px solid var(--term-border);
    }

    /* Shared Cards, Chat Messages, Diff & Badges */
    .card {
      background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius);
      padding: 14px 16px; display: flex; flex-direction: column; gap: 10px; box-shadow: var(--shadow-sm);
    }
    .row { display: flex; align-items: center; justify-content: space-between; gap: 8px; flex-wrap: wrap; }
    .card-title { font-size: 14px; font-weight: 700; letter-spacing: -0.015em; }
    .sub { font-size: 12.5px; color: var(--ink-2); line-height: 1.5; }
    .badge {
      font-size: 10.5px; font-weight: 660; padding: 2px 8px; border-radius: 999px;
      background: var(--soul-soft); color: var(--soul); white-space: nowrap;
    }
    .badge.ok { background: var(--ok-soft); color: var(--ok); }
    .badge.warn { background: var(--warn-soft); color: var(--warn); }
    .badge.err { background: var(--err-soft); color: var(--err); }

    .kpi-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; }
    .kpi {
      background: var(--surface); border: 1px solid var(--border); border-radius: 14px;
      padding: 12px 14px; display: flex; flex-direction: column; gap: 3px;
    }
    .kpi-val { font-size: 20px; font-weight: 760; letter-spacing: -0.03em; }
    .kpi-label { font-size: 11px; color: var(--ink-2); }

    .msg-wrap { display: flex; flex-direction: column; gap: 3px; }
    .msg-wrap.user { align-items: flex-end; }
    .msg-wrap.assistant { align-items: flex-start; }
    .msg-author { font-size: 11px; font-weight: 600; color: var(--ink-3); padding: 0 6px; }
    .msg {
      max-width: 86%; padding: 10px 14px; border-radius: 16px; font-size: 14px; line-height: 1.55;
      word-break: break-word;
    }
    .msg.user { background: var(--surface-soft); color: var(--ink); border: 1px solid var(--border); border-bottom-right-radius: 4px; }
    .msg.assistant { background: var(--surface); border: 1px solid var(--border); color: var(--ink); border-bottom-left-radius: 4px; }
    .msg pre {
      margin: 8px 0; padding: 10px 12px; border-radius: 10px; background: var(--surface-soft);
      border: 1px solid var(--border); overflow-x: auto; font-size: 12px; line-height: 1.45;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    }
    .msg code { padding: 1px 5px; border-radius: 5px; background: var(--surface-soft); font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.9em; }
    .msg.user code { background: rgba(255,255,255,0.2); }

    .welcome-hero { text-align: center; padding: 20px 8px 8px; display: flex; flex-direction: column; align-items: center; gap: 10px; }
    .starter-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 9px; width: 100%; margin-top: 6px; }
    .starter-btn {
      text-align: left; padding: 12px 13px; border-radius: 14px; border: 1px solid var(--border);
      background: var(--surface); color: var(--ink); cursor: pointer; box-shadow: var(--shadow-sm);
      display: flex; flex-direction: column; gap: 3px; transition: border-color 120ms ease, transform 90ms ease;
    }
    .starter-btn:hover { border-color: var(--border-strong); }
    .starter-btn:active { transform: scale(0.98); }
    .starter-btn strong { font-size: 13px; }
    .starter-btn span { font-size: 11.5px; color: var(--ink-2); }

    .diff-box {
      border-radius: 10px; overflow: auto; border: 1px solid var(--border); background: var(--surface-soft);
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 11.5px; max-height: 240px;
    }
    .diff-line { padding: 2px 10px; white-space: pre; }
    .diff-line.add { background: var(--diff-add); color: var(--ok); }
    .diff-line.del { background: var(--diff-del); color: var(--err); }
    .diff-line.hunk { color: var(--ink); font-weight: 500; background: var(--soul-soft); }
    .proof-bar { height: 6px; border-radius: 999px; background: var(--surface-hover); overflow: hidden; }
    .proof-fill { height: 100%; background: var(--ok); border-radius: 999px; }

    .btn {
      border: 1px solid var(--border); background: var(--surface-soft); color: var(--ink);
      padding: 6px 12px; border-radius: 8px; font-size: 12.5px; font-weight: 500; cursor: pointer;
      display: inline-flex; align-items: center; justify-content: center; gap: 5px; text-decoration: none;
      transition: transform 100ms ease, background 150ms ease;
    }
    .btn:hover { background: var(--surface-hover); }
    .btn:active { transform: scale(0.96); }
    .btn.primary { background: var(--ink); color: var(--canvas); border-color: transparent; }
    .btn.soul { background: var(--soul); color: var(--soul-ink); border-color: transparent; }
    .btn.ok { background: var(--ok); color: #FFF; border-color: transparent; }
    .btn.danger { background: var(--err-soft); color: var(--err); border-color: transparent; }
    .btn.xs { padding: 4px 9px; font-size: 11.5px; border-radius: 8px; }

    .codex-select {
      appearance: none; -webkit-appearance: none; height: 28px; max-width: 220px; padding: 0 24px 0 10px;
      border-radius: 999px; border: 1px solid var(--border-strong); background-color: var(--surface-soft);
      color: var(--ink); font-size: 12px; font-weight: 600; cursor: pointer; outline: none;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 24 24' fill='none' stroke='%23777' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpolyline points='6 9 12 15 18 9'/%3E%3C/svg%3E");
      background-repeat: no-repeat; background-position: right 8px center;
    }

    .empty { text-align: center; color: var(--ink-2); font-size: 13px; padding: 36px 16px; line-height: 1.65; }

    /* Bottom Sheet Modal & Toast */
    .sheet-backdrop {
      position: fixed; inset: 0; z-index: 60; background: rgba(0,0,0,0.45);
      display: none; align-items: flex-end; justify-content: center;
    }
    .sheet-backdrop.show { display: flex; }
    .sheet {
      width: 100%; max-width: 520px; background: var(--surface); border-radius: 22px 22px 0 0;
      padding: 12px 20px calc(env(safe-area-inset-bottom) + 20px);
      border-top: 1px solid var(--border); box-shadow: var(--shadow-md);
      display: flex; flex-direction: column; gap: 12px;
    }
    .sheet-handle { width: 38px; height: 4px; border-radius: 999px; background: var(--border-strong); margin: 0 auto 2px; }
    .toast {
      position: fixed; top: calc(env(safe-area-inset-top) + 58px); left: 50%; transform: translateX(-50%) translateY(-10px);
      z-index: 70; padding: 8px 15px; border-radius: 999px; background: var(--ink); color: var(--canvas);
      font-size: 12px; font-weight: 620; opacity: 0; pointer-events: none; transition: all 160ms ease;
      box-shadow: var(--shadow-md);
    }
    .toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }

    /* Mobile Bottom Tab Bar */
    .mobile-bottom-bar {
      display: none; flex-shrink: 0; grid-template-columns: repeat(2, 1fr); gap: 6px;
      padding: 6px 12px calc(env(safe-area-inset-bottom) + 8px);
      background: var(--glass); border-top: 1px solid var(--border);
      backdrop-filter: saturate(180%) blur(20px);
    }
    .mobile-tab {
      border: 0; background: transparent; color: var(--ink-2); padding: 8px 6px; border-radius: 10px;
      font-size: 12px; font-weight: 650; cursor: pointer; display: flex; align-items: center; justify-content: center; gap: 6px;
    }
    .mobile-tab.active { background: var(--soul-soft); color: var(--soul); }

    @media (max-width: 860px) {
      .global-header { grid-template-columns: 1fr auto; }
      .root-tabs { display: none; }
      .mobile-bottom-bar { display: grid; }
      .master-layout { grid-template-columns: 1fr; }
      .master-rail {
        flex-direction: row; flex-wrap: nowrap; overflow-x: auto; padding: 8px 10px;
        border-right: 0; border-bottom: 1px solid var(--border); max-height: 112px; flex-shrink: 0;
      }
      .master-rail .rail-label, .master-rail .master-card { display: none; }
      .subnav-list { flex-direction: row; gap: 4px; flex-shrink: 0; }
      .subnav-btn { width: auto; white-space: nowrap; padding: 6px 10px; font-size: 12px; }
      .fleet-list { flex-direction: row; flex-shrink: 0; }
      .fleet-node-card { min-width: 170px; padding: 7px 9px; }
      .master-scroll { padding: 12px 14px 16px; }
      .composer-wrap { padding: 8px 12px 10px; }
      .kpi-grid { grid-template-columns: repeat(2, 1fr); }
      .starter-grid { grid-template-columns: 1fr; }

      .herdr-layout { grid-template-columns: 1fr; grid-template-rows: auto minmax(0, 1fr); }
      .herdr-rail { max-height: 220px; border-right: 0; border-bottom: 1px solid var(--term-border); padding: 8px 10px; }
      .stage-body.mode-split { flex-direction: column; }
      .stage-body.mode-split .pane-tui { border-right: 0; border-bottom: 1px solid var(--term-border); }
    }
  </style>
</head>
<body>
<div class="shell">
  <!-- Unified Global Header -->
  <header class="global-header">
    <div class="brand">
      <img class="brand-logo" src="/icon.svg?v=2" alt="PiPiBot" />
      <div style="min-width:0;">
        <div class="brand-title" id="header-title">${hostTitle}</div>
        <div class="brand-sub"><span class="dot" id="header-dot"></span><span id="header-sub">正在连接主节点…</span></div>
      </div>
    </div>

    <!-- Top-Level 2-Tab Perspective Switch -->
    <nav class="root-tabs" aria-label="主视角切换">
      <button class="root-tab active" data-root-tab="master" type="button">
        <span>🧭 主节点总控</span>
        <span class="root-tab-badge" id="badge-online-nodes" style="display:none;">0 在线</span>
      </button>
      <button class="root-tab" data-root-tab="herdr" type="button">
        <span>⚡ 节点 Harness TUI</span>
        <span class="root-tab-badge" id="badge-running-sessions" style="display:none;">0 运行</span>
      </button>
    </nav>

    <div class="header-right">
      <button class="pill-btn" id="btn-status-sheet" type="button">
        <span id="transport-badge">E2EE</span>
      </button>
      <a class="pill-btn" href="/login" title="管理已纳管设备">设备</a>
      <button class="pill-btn" id="btn-theme-toggle" type="button" title="切换明暗主题">🌗</button>
    </div>
  </header>

  <div class="workspace">
    <!-- =======================================================================
         TAB 1: PRIMARY CONTROL NODE (主节点总控 — 默认进入)
         ======================================================================= -->
    <section class="view-pane active" id="pane-master">
      <div class="master-layout">
        <aside class="master-rail">
          <div class="master-card">
            <div class="row">
              <div style="display:flex;align-items:center;gap:7px;min-width:0;">
                <span class="dot ok" id="master-node-dot"></span>
                <strong id="master-node-name" style="font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">主控节点</strong>
              </div>
              <span class="badge ok">主节点</span>
            </div>
            <div id="master-node-meta" style="font-size:11px;color:var(--ink-3);font-family:monospace;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">等待同步…</div>
          </div>

          <div class="rail-label">主节点视角</div>
          <div class="subnav-list">
            <button class="subnav-btn active" data-master-view="chat" type="button"><span>全局管家对话</span></button>
            <button class="subnav-btn" data-master-view="board" type="button"><span>协同任务板</span><span class="badge" id="sub-badge-board" style="display:none;">0</span></button>
            <button class="subnav-btn" data-master-view="approvals" type="button"><span>审批中心</span><span class="badge warn" id="sub-badge-approvals" style="display:none;">0</span></button>
            <button class="subnav-btn" data-master-view="diff" type="button"><span>Diff 审阅</span><span class="badge" id="sub-badge-diff" style="display:none;">0</span></button>
            <button class="subnav-btn" data-master-view="overview" type="button"><span>任务与智能体</span></button>
          </div>

          <div class="rail-label" style="display:flex;justify-content:space-between;align-items:center;">
            <span>纳管节点矩阵</span>
            <a href="/login" style="color:var(--soul);text-decoration:none;font-size:10.5px;">+ 纳管</a>
          </div>
          <div class="fleet-list" id="master-fleet-list"></div>
        </aside>

        <div class="master-main">
          <div class="master-scroll" id="master-content"></div>
          <div class="composer-wrap" id="master-composer">
            <div class="composer-box">
              <textarea id="master-chat-input" rows="2" placeholder="向主节点管家下发全局指令（可直接自然语言调度任意在线节点执行任务）…"></textarea>
              <div class="composer-toolbar">
                <div style="display:flex;align-items:center;gap:6px;">
                  <select id="master-agent-picker" class="codex-select" title="选择主节点智能体"></select>
                </div>
                <button class="send-btn" id="btn-master-send" type="button" aria-label="发送">↑</button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- =======================================================================
         TAB 2: OVIS / HERDR NATIVE AGENT HARNESS TUI + LIVE HEADLESS BROWSER
         ======================================================================= -->
    <section class="view-pane" id="pane-herdr">
      <div class="herdr-layout">
        <!-- Left Multiplexer Rail -->
        <aside class="herdr-rail">
          <div class="herdr-section">
            <div class="herdr-label">
              <span>目标节点</span>
              <span id="herdr-conn-badge" style="color:#34D399;">未连接</span>
            </div>
            <select id="herdr-node-select" class="herdr-select"></select>
            <div id="herdr-node-cwd" style="font-size:10.5px;color:var(--term-muted);font-family:monospace;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">—</div>
          </div>

          <div class="herdr-section">
            <div class="herdr-label"><span>新建 Harness 会话</span></div>
            <select id="herdr-harness-select" class="herdr-select"></select>
            <select id="herdr-model-select" class="herdr-select mono" style="display:none;"></select>
            <div class="mode-pills" id="herdr-mode-pills">
              <button class="mode-pill active" data-hmode="tui" type="button">TUI PTY</button>
              <button class="mode-pill" data-hmode="acp" type="button">ACP 流式</button>
              <button class="mode-pill" data-hmode="cli" type="button">CLI</button>
            </div>
            <input id="herdr-cwd-input" class="herdr-input mono" placeholder="工作目录（留空默认节点目录）" />
            <input id="herdr-prompt-input" class="herdr-input" placeholder="初始任务（TUI / Shell 可留空直接进入）" />
            <button class="herdr-btn primary" id="btn-herdr-launch" type="button" style="width:100%;">⚡ 启动原生会话</button>
          </div>

          <div class="herdr-section" style="flex:1;min-height:120px;">
            <div class="herdr-label">
              <span>节点会话窗格</span>
              <button class="herdr-btn" id="btn-herdr-refresh" type="button" style="padding:2px 7px;font-size:10.5px;">刷新</button>
            </div>
            <div class="session-list" id="herdr-session-list">
              <div style="font-size:11.5px;color:var(--term-muted);padding:8px 4px;">暂无会话，点击上方「启动原生会话」。</div>
            </div>
          </div>
        </aside>

        <!-- Right Main Stage: TUI + Live Headless Browser -->
        <div class="herdr-stage">
          <div class="stage-bar">
            <div class="stage-title-group">
              <span class="live-pill idle" id="stage-live-pill"><span class="dot"></span><span>待命</span></span>
              <div class="stage-name" id="stage-session-title">选择或启动一个 Agent Harness 会话</div>
            </div>

            <div class="stage-view-switch" id="stage-view-switch">
              <button class="stage-view-btn active" data-sview="tui" type="button">⚡ TUI 终端</button>
              <button class="stage-view-btn" data-sview="split" type="button">◫ 分屏</button>
              <button class="stage-view-btn" data-sview="browser" type="button">🌐 实时浏览器</button>
            </div>

            <div style="display:flex;align-items:center;gap:5px;">
              <button class="herdr-btn" id="btn-direct-kb" type="button" title="开启后点击终端可直接按键发送原始 PTY 键码">⌨️ 键盘直输</button>
              <button class="herdr-btn" id="btn-sess-takeover" type="button" title="接管当前会话输入控制权">接管</button>
              <button class="herdr-btn" id="btn-tui-clear" type="button">清屏</button>
              <button class="herdr-btn danger" id="btn-sess-stop" type="button">停止</button>
            </div>
          </div>

          <div class="stage-body mode-tui" id="herdr-stage-body">
            <!-- Native Streaming ANSI TUI Pane -->
            <div class="pane-tui">
              <div class="tui-viewport" id="tui-viewport" tabindex="0"></div>
              <button class="jump-bottom-btn" id="btn-jump-bottom" type="button">↓ 回到最新流</button>
              <div class="tui-controls">
                <div class="key-strip">
                  <button class="key-chip" data-rawkey="enter" type="button">↵ Enter</button>
                  <button class="key-chip" data-rawkey="esc" type="button">Esc</button>
                  <button class="key-chip" data-rawkey="tab" type="button">Tab</button>
                  <button class="key-chip" data-rawkey="up" type="button">↑</button>
                  <button class="key-chip" data-rawkey="down" type="button">↓</button>
                  <button class="key-chip" data-rawkey="y" type="button">y</button>
                  <button class="key-chip" data-rawkey="n" type="button">n</button>
                  <button class="key-chip danger" data-rawkey="ctrlc" type="button">Ctrl+C</button>
                  <button class="key-chip danger" data-rawkey="ctrld" type="button">Ctrl+D</button>
                </div>
                <div class="tui-input-row">
                  <span class="tui-prompt-glyph">❯</span>
                  <input id="tui-cmd-input" class="herdr-input mono" style="flex:1;" placeholder="向当前 TUI PTY 发送指令（或无会话时回车直接启动）…" />
                  <button class="herdr-btn primary" id="btn-tui-send" type="button">发送</button>
                </div>
              </div>
            </div>

            <!-- Live Remote Headless Browser Pane (Gemini Spark / Mariner Style) -->
            <div class="pane-browser">
              <div class="browser-chrome">
                <button class="herdr-btn" id="btn-br-back" type="button" title="后退">←</button>
                <button class="herdr-btn" id="btn-br-fwd" type="button" title="前进">→</button>
                <button class="herdr-btn" id="btn-br-reload" type="button" title="刷新">↻</button>
                <input id="br-url-input" class="browser-url-input" placeholder="https://example.com 或 http://127.0.0.1:3000" />
                <button class="herdr-btn ok" id="btn-br-launch" type="button">▶ 启动</button>
                <button class="herdr-btn" id="btn-br-attach" type="button" title="接入远端已运行的 Chrome CDP :9222">接入 :9222</button>
                <button class="herdr-btn danger" id="btn-br-stop" type="button" style="display:none;">停止</button>
              </div>
              <div class="browser-tabs-strip" id="br-tabs-strip"></div>
              <div class="browser-canvas-wrap" id="br-canvas-wrap">
                <div class="browser-empty" id="br-empty-state">
                  <div style="font-size:28px;">🌐</div>
                  <div style="font-size:14px;font-weight:700;color:#E6EDF3;">远端实时无头浏览器</div>
                  <div>直接拉起远端机器的 Headless Chrome，或一键接入 Agent 已打开的 CDP (:9222)，通过 E2EE 实时画面在网页上点击、滚动、输入与接管。</div>
                  <div style="display:flex;gap:8px;margin-top:4px;">
                    <button class="herdr-btn primary" id="btn-br-empty-launch" type="button">▶ 启动无头浏览器</button>
                    <button class="herdr-btn" id="btn-br-empty-attach" type="button">🔗 接入已有 CDP :9222</button>
                  </div>
                </div>
                <div class="browser-screen-box" id="br-screen-box" style="display:none;">
                  <img class="browser-screen-img" id="br-screen-img" alt="Remote Headless Browser Live Stream" />
                </div>
              </div>
              <div class="browser-input-bar">
                <input id="br-type-input" class="herdr-input" style="flex:1;" placeholder="向远端浏览器当前焦点输入文字（回车发送文本）…" />
                <button class="herdr-btn" id="btn-br-type-send" type="button">输入</button>
                <button class="key-chip" data-brkey="Enter" type="button">↵</button>
                <button class="key-chip" data-brkey="Tab" type="button">Tab</button>
                <button class="key-chip" data-brkey="Backspace" type="button">⌫</button>
                <button class="key-chip" data-brkey="Escape" type="button">Esc</button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  </div>

  <!-- Mobile Bottom 2-Tab Bar -->
  <nav class="mobile-bottom-bar" aria-label="移动端主视角">
    <button class="mobile-tab active" data-root-tab="master" type="button">🧭 主节点总控</button>
    <button class="mobile-tab" data-root-tab="herdr" type="button">⚡ Harness TUI</button>
  </nav>
</div>

<!-- E2EE Connection Details Sheet -->
<div class="sheet-backdrop" id="status-sheet">
  <div class="sheet">
    <div class="sheet-handle"></div>
    <div class="row">
      <div class="card-title">端到端加密通道</div>
      <span class="badge ok">P-256 · AES-256-GCM</span>
    </div>
    <div class="sub" id="sheet-detail"></div>
    <div class="row">
      <a class="btn" href="/login">管理设备</a>
      <a class="btn" href="/">品牌官网</a>
      <button class="btn danger" id="btn-disconnect" type="button">解除本地缓存</button>
    </div>
  </div>
</div>

<div class="toast" id="toast"></div>

<script>
(function () {
  const IS_RELAY_MODE = ${relayMode ? 'true' : 'false'};
  const STUN_URLS = ${stunUrls};
  const STORAGE_KEY = 'pipibot_universal_session_v1';

  const savedTheme = localStorage.getItem('pipibot_theme');
  if (savedTheme) document.documentElement.setAttribute('data-theme', savedTheme);

  const b64uEncode = (buf) => {
    const bytes = new Uint8Array(buf);
    let bin = '';
    for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin).replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/g, '');
  };
  const b64uDecode = (str) => {
    const norm = str.replace(/-/g, '+').replace(/_/g, '/');
    const pad = norm + '='.repeat((4 - (norm.length % 4)) % 4);
    const bin = atob(pad);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  };
  const randHex = (n) => {
    const b = new Uint8Array(n);
    crypto.getRandomValues(b);
    return Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
  };

  function esc(str) {
    return String(str ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  }

  function showToast(msg) {
    const el = document.getElementById('toast');
    el.textContent = msg;
    el.classList.add('show');
    clearTimeout(el._t);
    el._t = setTimeout(() => el.classList.remove('show'), 2200);
  }

  function renderMarkdown(raw) {
    let html = esc(raw);
    html = html.replace(/\`\`\`[a-zA-Z0-9_-]*\\n([\\s\\S]*?)\`\`\`/g, '<pre>$1</pre>');
    html = html.replace(/\`([^\`\\n]+)\`/g, '<code>$1</code>');
    html = html.replace(/\\*\\*([^\\*\\n]+)\\*\\*/g, '<strong>$1</strong>');
    html = html.replace(/\\n/g, '<br/>');
    return html;
  }

  function renderColoredDiff(diffText) {
    const lines = String(diffText || '').slice(0, 3600).split('\\n');
    return '<div class="diff-box">' + lines.map((line) => {
      let cls = 'diff-line';
      if (line.startsWith('+') && !line.startsWith('+++')) cls += ' add';
      else if (line.startsWith('-') && !line.startsWith('---')) cls += ' del';
      else if (line.startsWith('@@')) cls += ' hunk';
      return '<div class="' + cls + '">' + esc(line) + '</div>';
    }).join('') + '</div>';
  }

  // =========================================================================
  // Lightweight Native ANSI Terminal Renderer (16/256/24-bit SGR + \\r overwrite)
  // =========================================================================
  const ANSI_16 = [
    '#1C2128', '#F85149', '#3FB950', '#D29922', '#58A6FF', '#BC8CFF', '#39C5CF', '#B1BAC4',
    '#6E7681', '#FF7B72', '#56D364', '#E3B341', '#79C0FF', '#D2A8FF', '#56D4DD', '#F0F6FC',
  ];
  function ansi256Color(n) {
    if (n < 16) return ANSI_16[n] || '#E6EDF3';
    if (n >= 232) {
      const v = 8 + (n - 232) * 10;
      return 'rgb(' + v + ',' + v + ',' + v + ')';
    }
    const idx = n - 16;
    const r = Math.floor(idx / 36);
    const g = Math.floor((idx % 36) / 6);
    const b = idx % 6;
    const map = [0, 95, 135, 175, 215, 255];
    return 'rgb(' + map[r] + ',' + map[g] + ',' + map[b] + ')';
  }

  function applyCarriageReturns(raw) {
    // Normalize CRLF -> LF, then let lone CR overwrite current line (for spinners & progress bars)
    const normalized = raw.replace(/\\r\\n/g, '\\n');
    const lines = normalized.split('\\n');
    return lines.map((line) => {
      if (line.indexOf('\\r') === -1) return line;
      const segs = line.split('\\r');
      let out = '';
      for (const seg of segs) {
        if (!seg) continue;
        if (seg.length >= out.length) out = seg;
        else out = seg + out.slice(seg.length);
      }
      return out;
    }).join('\\n');
  }

  function renderAnsiHtml(rawInput) {
    // Strip OSC sequences & non-SGR CSI cursor controls, keep SGR (m)
    const cleaned = applyCarriageReturns(
      String(rawInput || '')
        .replace(/\\x1b\\][^\\x07\\x1b]*(?:\\x07|\\x1b\\\\)/g, '')
        .replace(/\\x1b\\[\\?[0-9;]*[a-zA-Z]/g, '')
        .replace(/\\x1b\\[[0-9;]*[A-LN-Za-ln-z]/g, '')
    );

    const sgrRe = /\\x1b\\[([0-9;]*)m/g;
    let fg = '', bg = '', bold = false, dim = false, italic = false, underline = false, inverse = false;
    let lastIdx = 0;
    let out = '';
    let match;

    const wrap = (text) => {
      if (!text) return '';
      const styles = [];
      const effFg = inverse ? (bg || '#0A0C10') : fg;
      const effBg = inverse ? (fg || '#E6EDF3') : bg;
      if (effFg) styles.push('color:' + effFg);
      if (effBg) styles.push('background:' + effBg);
      if (bold) styles.push('font-weight:700');
      if (dim) styles.push('opacity:0.65');
      if (italic) styles.push('font-style:italic');
      if (underline) styles.push('text-decoration:underline');
      const safe = esc(text);
      return styles.length ? ('<span style="' + styles.join(';') + '">' + safe + '</span>') : safe;
    };

    while ((match = sgrRe.exec(cleaned)) !== null) {
      if (match.index > lastIdx) out += wrap(cleaned.slice(lastIdx, match.index));
      lastIdx = sgrRe.lastIndex;
      const codes = (match[1] || '0').split(';').map((x) => parseInt(x || '0', 10));
      for (let i = 0; i < codes.length; i++) {
        const c = codes[i];
        if (c === 0) { fg = ''; bg = ''; bold = false; dim = false; italic = false; underline = false; inverse = false; }
        else if (c === 1) bold = true;
        else if (c === 2) dim = true;
        else if (c === 3) italic = true;
        else if (c === 4) underline = true;
        else if (c === 7) inverse = true;
        else if (c === 22) { bold = false; dim = false; }
        else if (c === 23) italic = false;
        else if (c === 24) underline = false;
        else if (c === 27) inverse = false;
        else if (c >= 30 && c <= 37) fg = ANSI_16[c - 30];
        else if (c === 39) fg = '';
        else if (c >= 40 && c <= 47) bg = ANSI_16[c - 40];
        else if (c === 49) bg = '';
        else if (c >= 90 && c <= 97) fg = ANSI_16[c - 90 + 8];
        else if (c >= 100 && c <= 107) bg = ANSI_16[c - 100 + 8];
        else if ((c === 38 || c === 48) && codes[i + 1] === 5 && codes[i + 2] !== undefined) {
          const col = ansi256Color(codes[i + 2]);
          if (c === 38) fg = col; else bg = col;
          i += 2;
        } else if ((c === 38 || c === 48) && codes[i + 1] === 2 && codes[i + 4] !== undefined) {
          const col = 'rgb(' + codes[i + 2] + ',' + codes[i + 3] + ',' + codes[i + 4] + ')';
          if (c === 38) fg = col; else bg = col;
          i += 4;
        }
      }
    }
    if (lastIdx < cleaned.length) out += wrap(cleaned.slice(lastIdx));
    return out;
  }

  // =========================================================================
  // E2EE Relay Transport (with Live Push Stream Support: agent_stream & browser_frame)
  // =========================================================================
  class E2EERelayTransport {
    constructor(cfg) {
      this.hostId = cfg.hostId;
      this.hostPubKey = cfg.hostPubKey;
      this.lanHint = cfg.lanHint || '';
      this.deviceToken = cfg.deviceToken || '';
      this.oneTimeToken = cfg.oneTimeToken || '';
      this.clientId = 'web_' + randHex(6);
      this.sid = 's_' + randHex(8);
      this.txSeq = 0;
      this.rxSeq = 0;
      this.mode = 'connecting';
      this.ws = null;
      this.pc = null;
      this.dc = null;
      this.pending = new Map();
      this.onStatus = () => {};
      this.onStream = () => {};
    }

    async initCrypto() {
      const kp = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
      this.clientPubKeyB64Url = b64uEncode(await crypto.subtle.exportKey('raw', kp.publicKey));
      const peerRaw = b64uDecode(this.hostPubKey);
      const peerKey = await crypto.subtle.importKey('raw', peerRaw, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
      const sharedBits = await crypto.subtle.deriveBits({ name: 'ECDH', public: peerKey }, kp.privateKey, 256);
      const baseKey = await crypto.subtle.importKey('raw', sharedBits, 'HKDF', false, ['deriveKey']);
      const enc = new TextEncoder();
      this.aesKey = await crypto.subtle.deriveKey(
        {
          name: 'HKDF',
          hash: 'SHA-256',
          salt: enc.encode('pipibot-e2ee-v1:' + this.hostId),
          info: enc.encode('pipibot-aes256gcm-session:' + this.sid),
        },
        baseKey,
        { name: 'AES-GCM', length: 256 },
        false,
        ['encrypt', 'decrypt']
      );
    }

    async seal(obj) {
      this.txSeq += 1;
      const nonce = new Uint8Array(12);
      crypto.getRandomValues(nonce);
      const enc = new TextEncoder();
      const aad = enc.encode('v1|' + this.sid + '|c2h|' + this.txSeq);
      const pt = enc.encode(JSON.stringify(obj));
      const ct = await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce, additionalData: aad }, this.aesKey, pt);
      const env = {
        type: 'envelope', v: 1, hostId: this.hostId, clientId: this.clientId, sid: this.sid,
        dir: 'c2h', seq: this.txSeq, nonce: b64uEncode(nonce), ct: b64uEncode(ct),
      };
      if (this.txSeq === 1) env.clientPubKey = this.clientPubKeyB64Url;
      return env;
    }

    async open(env) {
      if (env.seq <= this.rxSeq) throw new Error('Replay detected');
      const nonce = b64uDecode(env.nonce);
      const ct = b64uDecode(env.ct);
      const enc = new TextEncoder();
      const aad = enc.encode('v1|' + env.sid + '|' + env.dir + '|' + env.seq);
      const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: nonce, additionalData: aad }, this.aesKey, ct);
      this.rxSeq = env.seq;
      return JSON.parse(new TextDecoder().decode(pt));
    }

    async connect() {
      if (this.lanHint && !IS_RELAY_MODE) {
        try {
          const ctrl = new AbortController();
          setTimeout(() => ctrl.abort(), 800);
          const res = await fetch(this.lanHint + '/api/v1/health', { signal: ctrl.signal });
          if (res.ok) { this.mode = 'lan'; this.onStatus('ok', 'LAN 直连'); return; }
        } catch {}
      }
      if (!IS_RELAY_MODE && !this.hostPubKey) {
        this.mode = 'lan'; this.onStatus('ok', '本机直连'); return;
      }

      await this.initCrypto();
      const wsProto = location.protocol === 'https:' ? 'wss:' : 'ws:';
      const wsUrl = wsProto + '//' + location.host + '/ws';

      await new Promise((resolve, reject) => {
        const ws = new WebSocket(wsUrl);
        this.ws = ws;
        const timer = setTimeout(() => reject(new Error('中继连接超时')), 8000);
        ws.onopen = () => {
          ws.send(JSON.stringify({ type: 'client_join', hostId: this.hostId, clientId: this.clientId }));
        };
        ws.onmessage = async (ev) => {
          let msg;
          try { msg = JSON.parse(ev.data); } catch { return; }
          if (msg.type === 'joined') {
            clearTimeout(timer);
            this.mode = 'relay';
            this.onStatus(msg.hostOnline ? 'ok' : 'warn', msg.hostOnline ? 'E2EE 中继' : '主机离线');
            if (msg.hostOnline) this.tryUpgradeWebRTC();
            resolve();
            return;
          }
          if (msg.type === 'host_status') {
            this.onStatus(msg.online ? 'ok' : 'warn', msg.online ? (this.mode === 'p2p' ? 'P2P 打洞' : 'E2EE 中继') : '主机离线');
            return;
          }
          if (msg.type === 'envelope') {
            try { this.handleInnerMessage(await this.open(msg)); } catch {}
          }
        };
        ws.onerror = () => { clearTimeout(timer); reject(new Error('WSS 连接失败')); };
        ws.onclose = () => { this.onStatus('err', '已断开'); };
      });

      if (this.oneTimeToken && !this.deviceToken) {
        const pairRes = await this.request('POST', '/api/v1/auth/pair', {
          code: this.oneTimeToken,
          label: navigator.userAgent.includes('iPhone') ? 'iPhone Safari PWA' : 'Web Companion',
          clientPublicKey: this.clientPubKeyB64Url,
        });
        if (pairRes && pairRes.token) {
          this.deviceToken = pairRes.token;
          this.oneTimeToken = '';
          saveSession({ hostId: this.hostId, hostPubKey: this.hostPubKey, lanHint: this.lanHint, deviceToken: this.deviceToken });
          showToast('已建立端到端加密配对 ✓');
        }
      }
    }

    async tryUpgradeWebRTC() {
      if (typeof RTCPeerConnection === 'undefined') return;
      try {
        const pc = new RTCPeerConnection({ iceServers: [{ urls: STUN_URLS }] });
        this.pc = pc;
        const dc = pc.createDataChannel('pipibot-e2ee', { ordered: true });
        this.dc = dc;
        const p2pTimer = setTimeout(() => {
          if (this.mode !== 'p2p') { try { pc.close(); } catch {} this.pc = null; this.dc = null; }
        }, 2200);
        dc.onopen = () => { clearTimeout(p2pTimer); this.mode = 'p2p'; this.onStatus('ok', 'P2P 打洞'); };
        dc.onmessage = async (ev) => {
          try {
            const env = JSON.parse(ev.data);
            if (env.type === 'envelope') this.handleInnerMessage(await this.open(env));
          } catch {}
        };
        pc.onicecandidate = async (ev) => {
          if (ev.candidate && this.ws && this.ws.readyState === 1) {
            this.ws.send(JSON.stringify(await this.seal({ kind: 'rtc_ice', candidate: ev.candidate.toJSON() })));
          }
        };
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        if (this.ws && this.ws.readyState === 1) {
          this.ws.send(JSON.stringify(await this.seal({ kind: 'rtc_offer', sdp: offer.sdp })));
        }
      } catch {}
    }

    handleInnerMessage(inner) {
      if (inner.kind === 'rtc_answer' && this.pc && inner.sdp) { this.pc.setRemoteDescription({ type: 'answer', sdp: inner.sdp }).catch(() => {}); return; }
      if (inner.kind === 'rtc_ice' && this.pc && inner.candidate) { this.pc.addIceCandidate(inner.candidate).catch(() => {}); return; }
      if (inner.kind === 'agent_stream' || inner.kind === 'browser_frame') {
        this.onStream(inner);
        return;
      }
      if (inner.kind === 'http_res' && inner.reqId && this.pending.has(inner.reqId)) {
        const { resolve } = this.pending.get(inner.reqId);
        this.pending.delete(inner.reqId);
        resolve(inner.body);
      }
    }

    async request(method, path, body) {
      if (this.mode === 'lan') {
        const headers = { 'Content-Type': 'application/json' };
        if (this.deviceToken) headers['Authorization'] = 'Bearer ' + this.deviceToken;
        const base = this.lanHint && IS_RELAY_MODE ? this.lanHint : '';
        const res = await fetch(base + path, { method, headers, body: body !== undefined ? JSON.stringify(body) : undefined });
        return res.json();
      }
      const reqId = 'r_' + randHex(6);
      const env = await this.seal({ kind: 'http_req', reqId, method, path, token: this.deviceToken, body: body ?? null });
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => { this.pending.delete(reqId); reject(new Error('请求超时')); }, 25000);
        this.pending.set(reqId, { resolve: (val) => { clearTimeout(timer); resolve(val); } });
        const wire = JSON.stringify(env);
        if (this.mode === 'p2p' && this.dc && this.dc.readyState === 'open') this.dc.send(wire);
        else if (this.ws && this.ws.readyState === 1) this.ws.send(wire);
        else { clearTimeout(timer); this.pending.delete(reqId); reject(new Error('未连接到主机')); }
      });
    }

    close() {
      try { if (this.pc) this.pc.close(); } catch {}
      try { if (this.ws) this.ws.close(); } catch {}
    }
  }

  // Lightweight HTTPS Transport for Embedded / Low-Resource Edge Nodes (Python Lite & POSIX Shell)
  class EdgeHttpTransport {
    constructor(cfg) {
      this.hostId = cfg.hostId;
      this.deviceToken = cfg.deviceToken || '';
      this.mode = 'edge-https';
      this.onStatus = () => {};
      this.onStream = () => {};
    }

    async connect() {
      const snap = await this.request('GET', '/api/v1/mobile/snapshot');
      this.onStatus(snap && snap.online ? 'ok' : 'warn', snap && snap.online ? 'Edge HTTPS' : '嵌入式节点离线');
    }

    async request(method, path, body) {
      const headers = { 'Content-Type': 'application/json' };
      if (this.deviceToken) headers['Authorization'] = 'Bearer ' + this.deviceToken;
      if (path === '/api/v1/mobile/snapshot') {
        const res = await fetch('/api/edge/snapshot?hostId=' + encodeURIComponent(this.hostId), { headers });
        return res.json();
      }
      if (path.endsWith('/attach')) {
        return {
          ok: true,
          rawBuffer: '\\x1b[36m[PiPiBot Edge]\\x1b[0m 已挂载嵌入式节点终端，输入任意 Shell 命令并回车即可下发执行。\\r\\n',
        };
      }
      if (path === '/api/agents/run' || path.endsWith('/input') || path === '/api/shell/exec') {
        const cmd = String((body && (body.command || body.text || body.prompt)) || '').trim();
        const sid = 'edge_shell_' + this.hostId;
        if (!cmd) return { ok: true, session: { id: sid, agent: 'Edge Shell', mode: 'cli', status: 'running' }, rawBuffer: '' };
        this.onStream({ kind: 'agent_stream', sessionId: sid, chunk: '\\x1b[35m$ ' + cmd + '\\x1b[0m\\r\\n', status: 'running' });
        const res = await fetch('/api/edge/exec', {
          method: 'POST',
          headers,
          body: JSON.stringify({ hostId: this.hostId, command: cmd, timeoutMs: (body && body.timeoutMs) || 20000 }),
        });
        const data = await res.json();
        const out = [data.stdout || '', data.stderr ? ('\\x1b[31m' + data.stderr + '\\x1b[0m') : ''].filter(Boolean).join('\\n') || '(无输出)';
        this.onStream({ kind: 'agent_stream', sessionId: sid, chunk: out + '\\r\\n', status: 'running' });
        return { ok: Boolean(data.ok), session: { id: sid, agent: 'Edge Shell', mode: 'cli', status: 'running' }, rawBuffer: '$ ' + cmd + '\\n' + out + '\\n', ...data };
      }
      return { ok: true };
    }

    close() {}
  }

  function parseCurrentLink() {
    const segs = location.pathname.split('/').filter(Boolean);
    const pathHostId = (segs[0] === 'c' && segs[1]) ? decodeURIComponent(segs[1]) : '';
    const hash = new URLSearchParams(location.hash.replace(/^#/, ''));
    const oneTimeToken = hash.get('t') || '';
    const hostPubKey = hash.get('k') || '';
    const lanHint = hash.get('lan') || '';
    if (oneTimeToken || hostPubKey) {
      const cleanPath = pathHostId ? ('/c/' + encodeURIComponent(pathHostId)) : '/app';
      history.replaceState({}, '', cleanPath);
    }
    return { pathHostId, oneTimeToken, hostPubKey, lanHint };
  }

  function loadSavedSession(hostId) {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return null;
      const parsed = JSON.parse(raw);
      if (hostId && parsed.hostId && parsed.hostId !== hostId) return null;
      return parsed;
    } catch { return null; }
  }
  function saveSession(s) { localStorage.setItem(STORAGE_KEY, JSON.stringify(s)); }

  // =========================================================================
  // Dual-Perspective Application State
  // =========================================================================
  const app = {
    rootTab: 'master', // 'master' (default primary node) | 'herdr' (node harness TUI + browser)
    accountDevices: [],
    accountAccessToken: localStorage.getItem('pipibot_access_token') || '',
    // Tab 1: Primary Control Node
    primaryHostId: '',
    primaryTransport: null,
    primaryStatus: { level: 'warn', label: '连接中…' },
    masterView: 'chat', // 'chat' | 'approvals' | 'diff' | 'overview'
    masterSelectedBotId: '',
    masterSnapshot: {
      hostName: '主控节点', messages: [], bots: [], approvals: [], draftGates: [],
      evolutions: [], worktrees: [], sentinelIssues: [], triggers: [], usageSummary: null,
    },
    // Tab 2: Herdr / Ovis Node Harness TUI + Live Headless Browser
    herdrHostId: '',
    herdrTransport: null,
    herdrStatus: { level: 'warn', label: '未连接' },
    herdrSnapshot: { hostName: '', workspacePath: '', harnesses: [], sessions: [] },
    herdrMode: 'tui', // 'tui' | 'acp' | 'cli'
    herdrStageView: 'tui', // 'tui' | 'split' | 'browser'
    activeSessionId: '',
    sessionBuffers: new Map(), // sessionId -> raw ANSI text
    directKeyboard: false,
    autoScroll: true,
    // Remote Browser State
    browser: { running: false, url: '', title: '', width: 1280, height: 800, tabs: [], lastFrame: '' },
  };

  let masterPollTimer = null;
  let herdrPollTimer = null;

  // =========================================================================
  // Header & Root Tab Switching
  // =========================================================================
  function syncHeaderStatus() {
    const isMaster = app.rootTab === 'master';
    const st = isMaster ? app.primaryStatus : app.herdrStatus;
    const title = isMaster
      ? (app.masterSnapshot.hostName || 'PiPiBot 主节点')
      : ((app.herdrSnapshot.hostName || '节点') + ' · Harness TUI');
    document.getElementById('header-title').textContent = title;
    document.getElementById('header-dot').className = 'dot ' + (st.level === 'ok' ? 'ok' : st.level === 'err' ? 'err' : '');
    document.getElementById('header-sub').textContent = isMaster ? ('主节点全局总控 · ' + st.label) : ('Ovis/Herdr 原生流式 · ' + st.label);
    const badge = document.getElementById('transport-badge');
    badge.textContent = st.label;
    document.getElementById('btn-status-sheet').className = 'pill-btn ' + (st.level === 'ok' ? 'ok' : '');

    const onlineCount = app.accountDevices.filter((d) => d.isOnline).length;
    const onlineBadge = document.getElementById('badge-online-nodes');
    if (onlineBadge) {
      onlineBadge.textContent = onlineCount + ' 在线';
      onlineBadge.style.display = onlineCount > 0 ? 'inline-block' : 'none';
    }
    const runningCount = (app.herdrSnapshot.sessions || []).filter((s) => s.status === 'running').length;
    const runBadge = document.getElementById('badge-running-sessions');
    if (runBadge) {
      runBadge.textContent = runningCount + ' 运行';
      runBadge.style.display = runningCount > 0 ? 'inline-block' : 'none';
    }
  }

  function setRootTab(tab) {
    app.rootTab = tab;
    document.querySelectorAll('[data-root-tab]').forEach((el) => {
      el.classList.toggle('active', el.dataset.rootTab === tab);
    });
    document.getElementById('pane-master').classList.toggle('active', tab === 'master');
    document.getElementById('pane-herdr').classList.toggle('active', tab === 'herdr');
    syncHeaderStatus();
    if (tab === 'herdr') {
      ensureHerdrConnected();
    }
  }

  document.querySelectorAll('[data-root-tab]').forEach((el) => {
    el.onclick = () => setRootTab(el.dataset.rootTab);
  });

  document.getElementById('btn-theme-toggle').onclick = () => {
    const cur = document.documentElement.getAttribute('data-theme');
    const next = cur === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', next);
    localStorage.setItem('pipibot_theme', next);
  };

  // =========================================================================
  // TAB 1: PRIMARY CONTROL NODE (主节点总控)
  // =========================================================================
  function renderFleetList() {
    const listEl = document.getElementById('master-fleet-list');
    if (!listEl) return;
    const sorted = app.accountDevices.slice().sort((a, b) => {
      const aScore = (a.hostId === app.primaryHostId ? 8 : 0) + (a.isOnline ? 4 : 0) + (a.platform === 'linux' ? 2 : 0);
      const bScore = (b.hostId === app.primaryHostId ? 8 : 0) + (b.isOnline ? 4 : 0) + (b.platform === 'linux' ? 2 : 0);
      return bScore - aScore;
    });
    if (!sorted.length) {
      listEl.innerHTML = '<div style="font-size:12px;color:var(--ink-3);padding:8px;">暂无已纳管设备，点击右上角「+ 纳管」。</div>';
      return;
    }
    listEl.innerHTML = sorted.map((d) => {
      const isPrimary = d.hostId === app.primaryHostId;
      const caps = (d.capabilities || []).slice(0, 3).join(' · ') || d.platform;
      return \`
        <div class="fleet-node-card">
          <div class="fleet-node-head">
            <span class="dot \${d.isOnline ? 'ok' : ''}"></span>
            <div class="fleet-node-name">\${esc(d.name)}</div>
            <span class="badge \${isPrimary ? 'ok' : ''}">\${isPrimary ? '主控' : esc(d.platform || 'node')}</span>
          </div>
          <div class="fleet-node-caps">\${esc(caps)}</div>
          <div class="fleet-node-actions">
            <span style="font-size:10.5px;color:var(--ink-3);">\${d.isOnline ? '在线可直连' : '离线'}</span>
            <button class="btn xs \${d.isOnline ? 'soul' : ''}" data-open-tui="\${esc(d.hostId)}" type="button">⚡ Harness TUI →</button>
          </div>
        </div>
      \`;
    }).join('');
    listEl.querySelectorAll('[data-open-tui]').forEach((btn) => {
      btn.onclick = () => openNodeInHerdr(btn.dataset.openTui);
    });
  }

  function renderMasterView() {
    const s = app.masterSnapshot;
    const masterDev = app.accountDevices.find((d) => d.hostId === app.primaryHostId);
    document.getElementById('master-node-name').textContent = masterDev?.name || s.hostName || '主控节点';
    document.getElementById('master-node-dot').className = 'dot ' + (app.primaryStatus.level === 'ok' ? 'ok' : '');
    document.getElementById('master-node-meta').textContent = (masterDev?.platform || s.platform || 'macos') + ' · ' + (masterDev?.workspacePath || s.workspacePath || app.primaryHostId || 'local');

    const pend = (s.approvals?.length || 0) + (s.draftGates?.length || 0) + (s.evolutions?.length || 0);
    const appBadge = document.getElementById('sub-badge-approvals');
    appBadge.textContent = String(pend);
    appBadge.style.display = pend > 0 ? 'inline-block' : 'none';
    const boardThreads = (s.board && Array.isArray(s.board.threads)) ? s.board.threads : [];
    const activeBoardCount = boardThreads.filter((t) => t.status === 'open' || t.status === 'claimed' || t.status === 'needs_you').length;
    const boardBadge = document.getElementById('sub-badge-board');
    if (boardBadge) {
      boardBadge.textContent = String(activeBoardCount);
      boardBadge.style.display = activeBoardCount > 0 ? 'inline-block' : 'none';
    }
    const diffCount = (s.worktrees || []).length;
    const diffBadge = document.getElementById('sub-badge-diff');
    diffBadge.textContent = String(diffCount);
    diffBadge.style.display = diffCount > 0 ? 'inline-block' : 'none';

    document.querySelectorAll('[data-master-view]').forEach((b) => {
      b.classList.toggle('active', b.dataset.masterView === app.masterView);
    });

    const contentEl = document.getElementById('master-content');
    const composerEl = document.getElementById('master-composer');
    composerEl.style.display = app.masterView === 'chat' ? 'block' : 'none';

    // Sync primary node agent picker
    const picker = document.getElementById('master-agent-picker');
    const bots = s.bots || [];
    const options = [{ id: '', label: '主节点全局管家' }].concat(
      bots.map((b) => ({ id: b.id, label: b.name }))
    );
    picker.innerHTML = options.map((o) => '<option value="' + esc(o.id) + '">' + esc(o.label) + '</option>').join('');
    picker.value = app.masterSelectedBotId || '';

    if (app.masterView === 'chat') {
      const msgs = s.messages || [];
      if (!msgs.length) {
        contentEl.innerHTML = \`
          <div class="welcome-hero">
            <div style="font-size:19px;font-weight:760;letter-spacing:-0.025em;">主节点全局总控台</div>
            <div class="sub">在这里用自然语言掌管整个数字团队与所有在线机器；需要直接进某台机器操作原生 Agent Harness TUI 或无头浏览器时，点左侧节点的「⚡ Harness TUI →」或顶部切换标签即可。</div>
            <div class="starter-grid">
              <button class="starter-btn" data-mprompt="汇报所有在线节点状态、正在运行的任务和待处理审批"><strong>🧭 全局集群巡检</strong><span>汇总全部机器与任务进展</span></button>
              <button class="starter-btn" data-mprompt="帮我整理今天最重要的 3 件事和项目优先级"><strong>📋 今日行动简报</strong><span>主节点管家全局统筹</span></button>
              <button class="starter-btn" data-mprompt="检查当前工作区 Git 变更并总结风险点"><strong>🌿 代码状态扫描</strong><span>快速审阅近期改动</span></button>
              <button class="starter-btn" data-mprompt="帮我新建一个自动化定时巡检 Bot"><strong>🤖 编排新智能体</strong><span>按需委派专职数字员工</span></button>
            </div>
          </div>
        \`;
        contentEl.querySelectorAll('[data-mprompt]').forEach((b) => {
          b.onclick = () => sendMasterChat(b.dataset.mprompt);
        });
        return;
      }
      contentEl.innerHTML = msgs.map((m) => \`
        <div class="msg-wrap \${m.role === 'user' ? 'user' : 'assistant'}">
          \${m.role !== 'user' && m.author ? '<div class="msg-author">' + esc(m.author) + '</div>' : ''}
          <div class="msg \${m.role === 'user' ? 'user' : 'assistant'}">\${renderMarkdown(m.content)}</div>
        </div>
      \`).join('');
      contentEl.scrollTop = contentEl.scrollHeight;
      return;
    }

    if (app.masterView === 'board') {
      const boardData = s.board || { channels: [], threads: [], events: [] };
      const threads = Array.isArray(boardData.threads) ? boardData.threads : [];
      const events = Array.isArray(boardData.events) ? boardData.events : [];
      const statusText = { open: '待认领', claimed: '进行中', blocked: '已阻塞', needs_you: '待确认', done: '已完成', cancelled: '已取消' };
      const quickForm = \`
        <div class="card">
          <div class="row"><div class="card-title">协同任务板</div><span class="badge">\${threads.length} 项任务</span></div>
          <div style="display:flex;gap:8px;margin-top:8px;">
            <input id="relay-board-title" type="text" placeholder="输入任务标题，直接发布到 #inbox…" style="flex:1;min-width:0;padding:7px 10px;border-radius:8px;border:1px solid var(--border);background:var(--bg);color:var(--ink);font-size:13px;" />
            <button class="btn ok" id="relay-board-post" type="button">发布任务</button>
          </div>
        </div>
      \`;
      const threadCards = threads.length
        ? threads.slice(0, 20).map((t) => {
            const badgeClass = t.status === 'needs_you' || t.status === 'blocked' ? 'warn' : (t.status === 'claimed' || t.status === 'done' ? 'ok' : '');
            const holder = t.claim?.actor?.name ? (' · ' + t.claim.actor.name) : '';
            return \`<div class="card">
              <div class="row"><div class="card-title">\${esc(t.title)}</div><span class="badge \${badgeClass}">\${esc(statusText[t.status] || t.status)}</span></div>
              <div class="sub">#\${esc(t.channelSlug || 'inbox')}\${esc(holder)} · 优先级 \${esc(t.priority || 'normal')}</div>
              <div class="row">
                \${t.status === 'open' ? '<button class="btn" data-bact="claim" data-tid="' + esc(t.id) + '">认领</button>' : ''}
                \${t.status !== 'done' && t.status !== 'cancelled' && t.status !== 'blocked' ? '<button class="btn ok" data-bact="complete" data-tid="' + esc(t.id) + '">标记完成</button>' : ''}
              </div>
            </div>\`;
          }).join('')
        : '<div class="empty">当前任务板为空，可以在上方快速发布一条任务。</div>';
      const eventCard = events.length
        ? \`<div class="card"><div class="row"><div class="card-title">最近活动流</div><span class="badge">\${events.length}</span></div>\${events.slice(-8).reverse().map((ev) => '<div class="sub" style="padding:4px 0;border-top:1px solid var(--border)">#' + esc(ev.channelSlug || 'inbox') + ' · ' + esc(ev.summary || '') + '</div>').join('')}</div>\`
        : '';
      contentEl.innerHTML = quickForm + threadCards + eventCard;
      const postBtn = document.getElementById('relay-board-post');
      if (postBtn) {
        postBtn.onclick = async () => {
          const input = document.getElementById('relay-board-title');
          const title = (input?.value || '').trim();
          if (!title) return;
          postBtn.disabled = true;
          await app.primaryTransport.request('POST', '/api/v1/board/threads', {
            channelSlug: 'inbox',
            title,
            kind: 'task',
            priority: 'normal',
            author: { id: 'human:web', name: 'Web Owner', kind: 'human' },
          });
          showToast('已发布到任务板 ✓');
          await refreshMasterSnapshot();
        };
      }
      contentEl.querySelectorAll('[data-bact]').forEach((btn) => {
        btn.onclick = async () => {
          btn.disabled = true;
          const tid = btn.dataset.tid;
          const act = btn.dataset.bact;
          const actor = { id: 'human:web', name: 'Web Owner', kind: 'human' };
          if (act === 'claim') {
            await app.primaryTransport.request('POST', '/api/v1/board/threads/' + encodeURIComponent(tid) + '/claim', { actor, leaseSeconds: 900 });
            showToast('已认领任务 ✓');
          } else if (act === 'complete') {
            await app.primaryTransport.request('POST', '/api/v1/board/threads/' + encodeURIComponent(tid) + '/complete', { actor, summary: 'Completed from Web Console.' });
            showToast('任务已完成 ✓');
          }
          await refreshMasterSnapshot();
        };
      });
      return;
    }

    if (app.masterView === 'approvals') {
      const blocks = [];
      for (const a of (s.approvals || [])) {
        blocks.push(\`<div class="card">
          <div class="row"><div class="card-title">\${esc(a.title)}</div><span class="badge warn">高危工具审批</span></div>
          <div class="sub">\${esc(a.summary || '')}</div>
          <div class="row"><button class="btn ok" data-mact="approve" data-id="\${esc(a.id)}">允许执行</button><button class="btn danger" data-mact="deny" data-id="\${esc(a.id)}">拒绝</button></div>
        </div>\`);
      }
      for (const d of (s.draftGates || [])) {
        blocks.push(\`<div class="card">
          <div class="row"><div class="card-title">外发草稿门控</div><span class="badge">Draft Gate</span></div>
          <div class="sub">\${esc(d.draftContent || '')}</div>
          <div class="row"><button class="btn ok" data-mact="draft-approve" data-id="\${esc(d.id)}">批准发送</button><button class="btn danger" data-mact="draft-reject" data-id="\${esc(d.id)}">驳回</button></div>
        </div>\`);
      }
      for (const e of (s.evolutions || [])) {
        blocks.push(\`<div class="card">
          <div class="row"><div class="card-title">Blueprint 自进化提案</div><span class="badge ok">EvolutionDiff</span></div>
          <div class="sub">\${esc(e.rationale || e.proposedRule || '')}</div>
          <div class="row"><button class="btn ok" data-mact="evo-approve" data-id="\${esc(e.id)}">采纳规则</button><button class="btn danger" data-mact="evo-reject" data-id="\${esc(e.id)}">忽略</button></div>
        </div>\`);
      }
      contentEl.innerHTML = blocks.length ? blocks.join('') : '<div class="empty">当前没有任何待审批操作，全局运行正常。</div>';
      contentEl.querySelectorAll('[data-mact]').forEach((btn) => {
        btn.onclick = async () => {
          btn.disabled = true;
          await app.primaryTransport.request('POST', '/api/v1/mobile/action', { action: btn.dataset.mact, id: btn.dataset.id });
          showToast('已提交决策 ✓');
          await refreshMasterSnapshot();
        };
      });
      return;
    }

    if (app.masterView === 'diff') {
      const wts = s.worktrees || [];
      if (!wts.length) {
        contentEl.innerHTML = '<div class="empty">🌿 当前没有待审阅的 Worktree Diff 分支。</div>';
        return;
      }
      contentEl.innerHTML = wts.map((w) => {
        const score = Number(w.proofScore ?? 0);
        return \`<div class="card">
          <div class="row"><div class="card-title">\${esc(w.branchName)}</div><span class="badge \${score >= 80 ? 'ok' : 'warn'}">Proof \${score}%</span></div>
          <div class="proof-bar"><div class="proof-fill" style="width:\${Math.min(100, Math.max(8, score))}%"></div></div>
          <div class="sub">\${esc(w.summary || '')}</div>
          \${renderColoredDiff(w.diffText)}
          <div class="row">
            <button class="btn ok" data-mwt="merge" data-id="\${esc(w.id)}">Squash 合入</button>
            <button class="btn danger" data-mwt="discard" data-id="\${esc(w.id)}">放弃分支</button>
          </div>
        </div>\`;
      }).join('');
      contentEl.querySelectorAll('[data-mwt]').forEach((btn) => {
        btn.onclick = async () => {
          btn.disabled = true;
          await app.primaryTransport.request('POST', '/api/v1/mobile/action', { action: 'worktree-' + btn.dataset.mwt, id: btn.dataset.id });
          showToast(btn.dataset.mwt === 'merge' ? '已合入并清理 ✓' : '已放弃该分支');
          await refreshMasterSnapshot();
        };
      });
      return;
    }

    // overview: KPIs + Sentinel + Bots + Triggers
    const issues = s.sentinelIssues || [];
    const u = s.usageSummary;
    const triggers = s.triggers || [];
    contentEl.innerHTML = \`
      <div class="kpi-grid">
        <div class="kpi"><div class="kpi-val">\${app.accountDevices.filter((d) => d.isOnline).length}/\${app.accountDevices.length}</div><div class="kpi-label">在线节点</div></div>
        <div class="kpi"><div class="kpi-val">\${bots.length}</div><div class="kpi-label">活跃智能体</div></div>
        <div class="kpi"><div class="kpi-val">\${pend}</div><div class="kpi-label">待审批项</div></div>
        <div class="kpi"><div class="kpi-val">$\${Number(u?.todayCostUSD || 0).toFixed(2)}</div><div class="kpi-label">今日估算消耗</div></div>
      </div>
      <div class="card">
        <div class="row"><div class="card-title">Sentinel 健康哨兵</div><span class="badge \${issues.length ? 'warn' : 'ok'}">\${issues.length ? (issues.length + ' 项异常') : '健康'}</span></div>
        \${issues.length === 0 ? '<div class="sub">无重复报错或队列阻塞。</div>' : issues.map((it) => '<div class="row"><span class="sub">[' + it.count + 'x] ' + esc(it.normalizedTitle) + '</span><span class="badge warn">' + esc(it.severity) + '</span></div>').join('')}
      </div>
      <div class="card">
        <div class="row"><div class="card-title">智能体与自动化触发器</div><span class="badge">\${bots.length} 位 · \${triggers.length} 条</span></div>
        \${bots.map((b) => '<div class="row" style="padding:5px 0;border-top:1px solid var(--border)"><div><div style="font-size:13px;font-weight:640">' + esc(b.name) + '</div><div class="sub">' + esc(b.role || '') + '</div></div><span class="badge">' + esc(b.isolation === 'sandbox_box' ? 'Bot Box' : 'Host') + '</span></div>').join('') || '<div class="sub">等待主节点同步…</div>'}
      </div>
    \`;
  }

  async function refreshMasterSnapshot() {
    if (!app.primaryTransport) return;
    try {
      const [data, boardRes] = await Promise.all([
        app.primaryTransport.request('GET', '/api/v1/mobile/snapshot'),
        app.primaryTransport.request('GET', '/api/v1/board').catch(() => null),
      ]);
      if (data && !data.error) {
        app.masterSnapshot = Object.assign(app.masterSnapshot, data);
      }
      if (boardRes && !boardRes.error) {
        app.masterSnapshot.board = boardRes.board || boardRes;
      }
      renderMasterView();
      syncHeaderStatus();
    } catch {}
  }

  async function sendMasterChat(text) {
    const clean = (text || '').trim();
    if (!clean || !app.primaryTransport) return;
    const input = document.getElementById('master-chat-input');
    input.value = '';
    input.style.height = '36px';
    app.masterSnapshot.messages.push({ role: 'user', content: clean });
    renderMasterView();
    try {
      await app.primaryTransport.request('POST', '/api/v1/mobile/chat', {
        text: clean,
        botId: app.masterSelectedBotId || undefined,
      });
      showToast('已加密送达主节点 ✓');
      setTimeout(refreshMasterSnapshot, 1100);
      setTimeout(refreshMasterSnapshot, 3200);
    } catch (e) {
      app.masterSnapshot.messages.push({ role: 'assistant', author: '系统', content: '发送失败：' + e.message });
      renderMasterView();
    }
  }

  document.querySelectorAll('[data-master-view]').forEach((btn) => {
    btn.onclick = () => { app.masterView = btn.dataset.masterView; renderMasterView(); };
  });
  document.getElementById('master-agent-picker').onchange = (e) => { app.masterSelectedBotId = e.target.value; };
  document.getElementById('btn-master-send').onclick = () => sendMasterChat(document.getElementById('master-chat-input').value);
  const masterInput = document.getElementById('master-chat-input');
  masterInput.addEventListener('input', () => {
    masterInput.style.height = 'auto';
    masterInput.style.height = Math.min(150, Math.max(36, masterInput.scrollHeight)) + 'px';
  });
  masterInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      sendMasterChat(masterInput.value);
    }
  });

  // =========================================================================
  // TAB 2: OVIS / HERDR NATIVE AGENT HARNESS TUI + LIVE REMOTE BROWSER
  // =========================================================================
  function populateHerdrNodeSelect() {
    const sel = document.getElementById('herdr-node-select');
    if (!sel) return;
    const sorted = app.accountDevices.slice().sort((a, b) => {
      const aScore = (a.isOnline ? 4 : 0) + (a.platform === 'linux' ? 2 : 0);
      const bScore = (b.isOnline ? 4 : 0) + (b.platform === 'linux' ? 2 : 0);
      return bScore - aScore;
    });
    sel.innerHTML = sorted.map((d) => {
      const prefix = d.isOnline ? '🟢 ' : '⚪ ';
      const role = d.hostId === app.primaryHostId ? ' [主控]' : (' [' + (d.platform || 'node') + ']');
      return '<option value="' + esc(d.hostId) + '">' + prefix + esc(d.name) + role + '</option>';
    }).join('') || '<option value="">无可用节点</option>';
    if (app.herdrHostId) sel.value = app.herdrHostId;
  }

  function populateHerdrHarnessPickers() {
    const hSel = document.getElementById('herdr-harness-select');
    const mSel = document.getElementById('herdr-model-select');
    const harnesses = (app.herdrSnapshot.harnesses || []).slice();
    const list = harnesses.concat([{ id: 'shell', name: 'Interactive Shell (PTY)', models: [], defaultModel: '' }]);
    const prev = hSel.value;
    hSel.innerHTML = list.map((h) => '<option value="' + esc(h.id) + '">' + (h.id === 'shell' ? '💻 ' : '⚡ ') + esc(h.name) + '</option>').join('');
    if (prev && list.some((h) => h.id === prev)) hSel.value = prev;
    syncHerdrModelPicker();
  }

  function syncHerdrModelPicker() {
    const hSel = document.getElementById('herdr-harness-select');
    const mSel = document.getElementById('herdr-model-select');
    const found = (app.herdrSnapshot.harnesses || []).find((h) => h.id === hSel.value);
    if (found && Array.isArray(found.models) && found.models.length) {
      mSel.style.display = 'block';
      mSel.innerHTML = found.models.map((m) => '<option value="' + esc(m) + '">' + esc(m) + '</option>').join('');
      if (found.defaultModel && found.models.includes(found.defaultModel)) mSel.value = found.defaultModel;
    } else {
      mSel.style.display = 'none';
      mSel.innerHTML = '';
    }
  }
  document.getElementById('herdr-harness-select').onchange = syncHerdrModelPicker;

  document.querySelectorAll('#herdr-mode-pills [data-hmode]').forEach((btn) => {
    btn.onclick = () => {
      app.herdrMode = btn.dataset.hmode;
      document.querySelectorAll('#herdr-mode-pills [data-hmode]').forEach((b) => b.classList.toggle('active', b.dataset.hmode === app.herdrMode));
    };
  });

  function renderHerdrSessions() {
    const listEl = document.getElementById('herdr-session-list');
    const sessions = (app.herdrSnapshot.sessions || []).slice().reverse();
    document.getElementById('herdr-node-cwd').textContent = app.herdrSnapshot.workspacePath || '—';

    if (!sessions.length) {
      listEl.innerHTML = '<div style="font-size:11.5px;color:var(--term-muted);padding:8px 4px;">暂无运行中或历史会话。<br/>在上方选择 Harness 并点击「启动原生会话」。</div>';
      renderTuiStageHeader();
      return;
    }
    listEl.innerHTML = sessions.map((s) => {
      const isRun = s.status === 'running';
      const isAct = s.id === app.activeSessionId;
      return \`
        <button class="session-item \${isAct ? 'active' : ''}" data-pick-sess="\${esc(s.id)}" type="button">
          <div class="session-item-top">
            <span class="dot \${isRun ? 'ok pulse' : ''}"></span>
            <span style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis;flex:1;">\${esc(s.agent)}</span>
          </div>
          <div class="session-item-meta">
            <span>\${esc((s.mode || 'tui').toUpperCase())}</span>
            <span>·</span>
            <span>\${isRun ? 'LIVE' : ('exit ' + (s.exitCode ?? 0))}</span>
          </div>
        </button>
      \`;
    }).join('');
    listEl.querySelectorAll('[data-pick-sess]').forEach((btn) => {
      btn.onclick = () => attachHerdrSession(btn.dataset.pickSess);
    });
    renderTuiStageHeader();
    syncHeaderStatus();
  }

  function renderTuiStageHeader() {
    const sess = (app.herdrSnapshot.sessions || []).find((s) => s.id === app.activeSessionId);
    const pill = document.getElementById('stage-live-pill');
    const title = document.getElementById('stage-session-title');
    if (!sess) {
      pill.className = 'live-pill idle';
      pill.innerHTML = '<span class="dot"></span><span>待命</span>';
      title.textContent = (app.herdrSnapshot.hostName || '节点') + ' · 选择或启动一个 Agent Harness 会话';
      return;
    }
    const isRun = sess.status === 'running';
    pill.className = 'live-pill ' + (isRun ? '' : 'idle');
    pill.innerHTML = isRun
      ? '<span class="dot ok pulse"></span><span>LIVE · 流式</span>'
      : '<span class="dot"></span><span>已结束 · exit=' + esc(sess.exitCode ?? 0) + '</span>';
    title.textContent = sess.agent + (sess.cwd ? ('  —  ' + sess.cwd) : '');
  }

  let renderTuiRaf = 0;
  function scheduleRenderTuiViewport() {
    if (renderTuiRaf) return;
    renderTuiRaf = requestAnimationFrame(() => {
      renderTuiRaf = 0;
      const vp = document.getElementById('tui-viewport');
      const sess = (app.herdrSnapshot.sessions || []).find((s) => s.id === app.activeSessionId);
      const raw = app.activeSessionId ? (app.sessionBuffers.get(app.activeSessionId) || '') : '';
      if (!app.activeSessionId) {
        vp.innerHTML = '<div style="color:var(--term-muted);padding:20px 6px;line-height:1.8;">⚡ <strong>Ovis / Herdr 原生 Agent Harness TUI</strong><br/>1. 在左侧选择目标节点（Linux / Mac）与 Harness（Claude Code / Codex / Pi / OpenCode / Shell）。<br/>2. 点击「启动原生会话」，或直接在下方输入框回车即可立即拉起流式会话。<br/>3. 点击顶部「◫ 分屏」或「🌐 实时浏览器」可同步查看并操作远端无头浏览器画面。</div>';
        return;
      }
      const isRun = sess && sess.status === 'running';
      vp.innerHTML = renderAnsiHtml(raw) + (isRun ? '<span class="tui-cursor"></span>' : '');
      if (app.autoScroll) {
        vp.scrollTop = vp.scrollHeight;
      }
    });
  }

  const tuiViewport = document.getElementById('tui-viewport');
  const jumpBottomBtn = document.getElementById('btn-jump-bottom');
  tuiViewport.addEventListener('scroll', () => {
    const nearBottom = tuiViewport.scrollHeight - tuiViewport.scrollTop - tuiViewport.clientHeight < 48;
    app.autoScroll = nearBottom;
    jumpBottomBtn.classList.toggle('show', !nearBottom);
  });
  jumpBottomBtn.onclick = () => {
    app.autoScroll = true;
    tuiViewport.scrollTop = tuiViewport.scrollHeight;
    jumpBottomBtn.classList.remove('show');
  };

  async function attachHerdrSession(sessionId) {
    if (!sessionId || !app.herdrTransport) return;
    app.activeSessionId = sessionId;
    app.autoScroll = true;
    renderHerdrSessions();
    try {
      const res = await app.herdrTransport.request('POST', '/api/agents/' + sessionId + '/attach', {});
      if (res && res.ok) {
        app.sessionBuffers.set(sessionId, res.rawBuffer || (res.session?.outputLines || []).join('\\n'));
        if (res.session) {
          const idx = (app.herdrSnapshot.sessions || []).findIndex((s) => s.id === sessionId);
          if (idx >= 0) app.herdrSnapshot.sessions[idx] = res.session;
        }
        renderHerdrSessions();
        scheduleRenderTuiViewport();
      }
    } catch (e) {
      showToast('挂载会话流失败：' + e.message);
    }
  }

  async function launchHerdrSession(promptOverride) {
    if (!app.herdrTransport) { showToast('请先选择在线节点'); return; }
    const agent = document.getElementById('herdr-harness-select').value || 'shell';
    const model = document.getElementById('herdr-model-select').value || undefined;
    const cwd = document.getElementById('herdr-cwd-input').value.trim() || undefined;
    const promptInput = document.getElementById('herdr-prompt-input');
    const prompt = promptOverride !== undefined ? promptOverride : promptInput.value.trim();
    if (!prompt && app.herdrMode !== 'tui' && agent !== 'shell') {
      showToast('ACP / CLI 模式请输入初始任务，或切换至 TUI PTY 直接进入');
      promptInput.focus();
      return;
    }
    promptInput.value = '';
    try {
      const res = await app.herdrTransport.request('POST', '/api/agents/run', {
        agent,
        model,
        mode: agent === 'shell' ? 'tui' : app.herdrMode,
        cwd,
        prompt,
      });
      if (res && res.ok && res.session) {
        app.herdrSnapshot.sessions = (app.herdrSnapshot.sessions || []).filter((s) => s.id !== res.session.id);
        app.herdrSnapshot.sessions.push(res.session);
        app.activeSessionId = res.session.id;
        app.sessionBuffers.set(res.session.id, res.rawBuffer || '');
        app.autoScroll = true;
        renderHerdrSessions();
        scheduleRenderTuiViewport();
        showToast('已启动实时流式会话 ⚡');
      } else {
        showToast('启动失败：' + (res?.error || '未知错误'));
      }
    } catch (e) {
      showToast('启动失败：' + e.message);
    }
  }

  document.getElementById('btn-herdr-launch').onclick = () => launchHerdrSession();
  document.getElementById('herdr-prompt-input').addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); launchHerdrSession(); }
  });

  async function sendTuiRaw(rawStr) {
    if (!app.activeSessionId || !app.herdrTransport) return;
    try {
      await app.herdrTransport.request('POST', '/api/agents/' + app.activeSessionId + '/input', {
        raw: rawStr,
        forceTakeover: true,
      });
    } catch (e) {
      showToast('按键发送失败：' + e.message);
    }
  }

  async function sendTuiLine(text) {
    if (!app.herdrTransport) return;
    const sess = (app.herdrSnapshot.sessions || []).find((s) => s.id === app.activeSessionId);
    if (!sess || sess.status !== 'running') {
      if (text.trim()) await launchHerdrSession(text.trim());
      return;
    }
    try {
      await app.herdrTransport.request('POST', '/api/agents/' + app.activeSessionId + '/input', {
        text,
        forceTakeover: true,
      });
    } catch (e) {
      showToast('发送失败：' + e.message);
    }
  }

  const RAW_KEY_MAP = {
    enter: '\\r',
    esc: '\\x1b',
    tab: '\\t',
    up: '\\x1b[A',
    down: '\\x1b[B',
    y: 'y\\r',
    n: 'n\\r',
    ctrlc: '\\x03',
    ctrld: '\\x04',
  };
  document.querySelectorAll('[data-rawkey]').forEach((btn) => {
    btn.onclick = () => sendTuiRaw(RAW_KEY_MAP[btn.dataset.rawkey] || '');
  });

  const tuiCmdInput = document.getElementById('tui-cmd-input');
  document.getElementById('btn-tui-send').onclick = () => {
    const v = tuiCmdInput.value;
    tuiCmdInput.value = '';
    sendTuiLine(v);
  };
  tuiCmdInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.isComposing) {
      e.preventDefault();
      const v = tuiCmdInput.value;
      tuiCmdInput.value = '';
      sendTuiLine(v);
    }
  });

  // Direct Keyboard Capture for native terminal feel
  const btnDirectKb = document.getElementById('btn-direct-kb');
  btnDirectKb.onclick = () => {
    app.directKeyboard = !app.directKeyboard;
    btnDirectKb.classList.toggle('active', app.directKeyboard);
    tuiViewport.classList.toggle('direct-kb', app.directKeyboard);
    if (app.directKeyboard) {
      tuiViewport.focus();
      showToast('键盘直输已开启：在终端区域按键直接发送到远端 PTY');
    }
  };
  tuiViewport.addEventListener('keydown', (e) => {
    if (!app.directKeyboard || !app.activeSessionId) return;
    if (e.metaKey) return; // Keep browser Cmd+C / Cmd+R intact
    let seq = '';
    if (e.ctrlKey && e.key.length === 1) {
      const code = e.key.toUpperCase().charCodeAt(0) - 64;
      if (code >= 1 && code <= 26) seq = String.fromCharCode(code);
    } else if (e.key === 'Enter') seq = '\\r';
    else if (e.key === 'Backspace') seq = '\\x7f';
    else if (e.key === 'Tab') seq = '\\t';
    else if (e.key === 'Escape') seq = '\\x1b';
    else if (e.key === 'ArrowUp') seq = '\\x1b[A';
    else if (e.key === 'ArrowDown') seq = '\\x1b[B';
    else if (e.key === 'ArrowRight') seq = '\\x1b[C';
    else if (e.key === 'ArrowLeft') seq = '\\x1b[D';
    else if (e.key.length === 1 && !e.altKey) seq = e.key;
    if (seq) {
      e.preventDefault();
      sendTuiRaw(seq);
    }
  });

  document.getElementById('btn-sess-takeover').onclick = async () => {
    if (!app.activeSessionId || !app.herdrTransport) return;
    await app.herdrTransport.request('POST', '/api/agents/' + app.activeSessionId + '/takeover', {});
    showToast('已接管当前会话控制权 ✓');
  };
  document.getElementById('btn-tui-clear').onclick = () => {
    if (app.activeSessionId) {
      app.sessionBuffers.set(app.activeSessionId, '');
      scheduleRenderTuiViewport();
    }
  };
  document.getElementById('btn-sess-stop').onclick = async () => {
    if (!app.activeSessionId || !app.herdrTransport) return;
    await app.herdrTransport.request('POST', '/api/agents/' + app.activeSessionId + '/stop', {});
    showToast('已发送停止信号');
    setTimeout(refreshHerdrSnapshot, 400);
  };
  document.getElementById('btn-herdr-refresh').onclick = () => refreshHerdrSnapshot();

  // Stage View Mode Switch (TUI / Split / Live Browser)
  function setHerdrStageView(mode) {
    app.herdrStageView = mode;
    const body = document.getElementById('herdr-stage-body');
    body.className = 'stage-body mode-' + mode;
    document.querySelectorAll('#stage-view-switch [data-sview]').forEach((b) => {
      b.classList.toggle('active', b.dataset.sview === mode);
    });
    if (mode === 'browser' || mode === 'split') {
      attachRemoteBrowser();
    }
  }
  document.querySelectorAll('#stage-view-switch [data-sview]').forEach((btn) => {
    btn.onclick = () => setHerdrStageView(btn.dataset.sview);
  });

  // =========================================================================
  // Remote Headless Browser CDP Live Viewport Controls
  // =========================================================================
  function renderBrowserState() {
    const b = app.browser;
    const emptyEl = document.getElementById('br-empty-state');
    const boxEl = document.getElementById('br-screen-box');
    const imgEl = document.getElementById('br-screen-img');
    const stopBtn = document.getElementById('btn-br-stop');
    const urlInput = document.getElementById('br-url-input');
    const tabsEl = document.getElementById('br-tabs-strip');

    stopBtn.style.display = b.running ? 'inline-flex' : 'none';
    if (b.url && document.activeElement !== urlInput) urlInput.value = b.url;

    if (b.running && b.lastFrame) {
      emptyEl.style.display = 'none';
      boxEl.style.display = 'inline-flex';
      imgEl.src = 'data:image/jpeg;base64,' + b.lastFrame;
    } else if (b.running) {
      emptyEl.style.display = 'flex';
      emptyEl.querySelector('div:nth-child(2)').textContent = '无头浏览器已连接，等待画面帧…';
      boxEl.style.display = 'none';
    } else {
      emptyEl.style.display = 'flex';
      emptyEl.querySelector('div:nth-child(2)').textContent = '远端实时无头浏览器';
      boxEl.style.display = 'none';
    }

    if (Array.isArray(b.tabs) && b.tabs.length > 1) {
      tabsEl.classList.add('show');
      tabsEl.innerHTML = b.tabs.map((t) =>
        '<button class="browser-tab-pill ' + (t.url === b.url ? 'active' : '') + '" data-brtab="' + esc(t.id) + '" type="button">' + esc(t.title || t.url || 'Tab') + '</button>'
      ).join('');
      tabsEl.querySelectorAll('[data-brtab]').forEach((btn) => {
        btn.onclick = () => sendBrowserAction({ type: 'switch-tab', targetId: btn.dataset.brtab });
      });
    } else {
      tabsEl.classList.remove('show');
    }
  }

  async function attachRemoteBrowser() {
    if (!app.herdrTransport) return;
    try {
      const res = await app.herdrTransport.request('POST', '/api/browser/attach', {});
      if (res && res.ok) {
        Object.assign(app.browser, {
          running: Boolean(res.running),
          url: res.url || '',
          title: res.title || '',
          width: res.width || 1280,
          height: res.height || 800,
          tabs: res.tabs || [],
          lastFrame: res.lastFrame || app.browser.lastFrame,
        });
        renderBrowserState();
      }
    } catch {}
  }

  async function launchRemoteBrowser(attachOnly) {
    if (!app.herdrTransport) { showToast('请先连接目标节点'); return; }
    const url = document.getElementById('br-url-input').value.trim() || (attachOnly ? undefined : 'https://example.com');
    showToast(attachOnly ? '正在探测远端 Chrome CDP :9222…' : '正在拉起远端无头浏览器…');
    try {
      const res = await app.herdrTransport.request('POST', '/api/browser/launch', {
        url,
        width: 1280,
        height: 800,
        attachOnly: Boolean(attachOnly),
      });
      if (res && res.ok) {
        Object.assign(app.browser, {
          running: true,
          url: res.url || url || '',
          title: res.title || '',
          width: res.width || 1280,
          height: res.height || 800,
          tabs: res.tabs || [],
          lastFrame: res.lastFrame || '',
        });
        renderBrowserState();
        showToast('远端实时浏览器已就绪 🌐');
      } else {
        showToast(res?.error || '启动失败');
      }
    } catch (e) {
      showToast('浏览器连接失败：' + e.message);
    }
  }

  async function sendBrowserAction(payload) {
    if (!app.herdrTransport || !app.browser.running) return;
    try {
      await app.herdrTransport.request('POST', '/api/browser/action', payload);
    } catch {}
  }

  document.getElementById('btn-br-launch').onclick = () => launchRemoteBrowser(false);
  document.getElementById('btn-br-empty-launch').onclick = () => launchRemoteBrowser(false);
  document.getElementById('btn-br-attach').onclick = () => launchRemoteBrowser(true);
  document.getElementById('btn-br-empty-attach').onclick = () => launchRemoteBrowser(true);
  document.getElementById('btn-br-stop').onclick = async () => {
    if (!app.herdrTransport) return;
    await app.herdrTransport.request('POST', '/api/browser/stop', {});
    app.browser.running = false;
    app.browser.lastFrame = '';
    renderBrowserState();
    showToast('已停止远端无头浏览器');
  };
  document.getElementById('btn-br-back').onclick = () => sendBrowserAction({ type: 'back' });
  document.getElementById('btn-br-fwd').onclick = () => sendBrowserAction({ type: 'forward' });
  document.getElementById('btn-br-reload').onclick = () => sendBrowserAction({ type: 'reload' });
  document.getElementById('br-url-input').addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.isComposing) {
      e.preventDefault();
      const u = e.target.value.trim();
      if (!u) return;
      if (app.browser.running) sendBrowserAction({ type: 'navigate', url: u });
      else launchRemoteBrowser(false);
    }
  });

  // Click & Wheel directly on the live browser frame
  const brImg = document.getElementById('br-screen-img');
  const brBox = document.getElementById('br-screen-box');
  brImg.addEventListener('click', (e) => {
    if (!app.browser.running) return;
    const rect = brImg.getBoundingClientRect();
    const rx = Math.round(((e.clientX - rect.left) / rect.width) * (app.browser.width || 1280));
    const ry = Math.round(((e.clientY - rect.top) / rect.height) * (app.browser.height || 800));
    const ripple = document.createElement('div');
    ripple.className = 'click-ripple';
    ripple.style.left = (e.clientX - rect.left) + 'px';
    ripple.style.top = (e.clientY - rect.top) + 'px';
    brBox.appendChild(ripple);
    setTimeout(() => ripple.remove(), 440);
    sendBrowserAction({ type: 'click', x: rx, y: ry });
  });
  let wheelThrottle = 0;
  brImg.addEventListener('wheel', (e) => {
    if (!app.browser.running) return;
    e.preventDefault();
    const now = Date.now();
    if (now - wheelThrottle < 90) return;
    wheelThrottle = now;
    const rect = brImg.getBoundingClientRect();
    const rx = Math.round(((e.clientX - rect.left) / rect.width) * (app.browser.width || 1280));
    const ry = Math.round(((e.clientY - rect.top) / rect.height) * (app.browser.height || 800));
    sendBrowserAction({ type: 'wheel', x: rx, y: ry, deltaX: e.deltaX, deltaY: e.deltaY });
  }, { passive: false });

  const brTypeInput = document.getElementById('br-type-input');
  const sendBrType = () => {
    const val = brTypeInput.value;
    if (!val) return;
    brTypeInput.value = '';
    sendBrowserAction({ type: 'type', text: val });
  };
  document.getElementById('btn-br-type-send').onclick = sendBrType;
  brTypeInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); sendBrType(); }
  });
  document.querySelectorAll('[data-brkey]').forEach((btn) => {
    btn.onclick = () => sendBrowserAction({ type: 'key', key: btn.dataset.brkey });
  });

  // =========================================================================
  // Real-Time E2EE Stream Handler (agent_stream + browser_frame)
  // =========================================================================
  function handleHerdrStream(msg) {
    if (msg.kind === 'agent_stream' && msg.sessionId) {
      if (msg.chunk) {
        const prev = app.sessionBuffers.get(msg.sessionId) || '';
        let next = prev + msg.chunk;
        if (next.length > 160000) next = next.slice(next.length - 160000);
        app.sessionBuffers.set(msg.sessionId, next);
      }
      if (msg.status) {
        const sess = (app.herdrSnapshot.sessions || []).find((s) => s.id === msg.sessionId);
        if (sess) {
          sess.status = msg.status;
          if (msg.exitCode !== undefined) sess.exitCode = msg.exitCode;
        }
        renderHerdrSessions();
      }
      if (msg.sessionId === app.activeSessionId) {
        scheduleRenderTuiViewport();
      }
      return;
    }
    if (msg.kind === 'browser_frame' && msg.data) {
      app.browser.running = true;
      app.browser.lastFrame = msg.data;
      if (msg.url) app.browser.url = msg.url;
      if (msg.width) app.browser.width = msg.width;
      if (msg.height) app.browser.height = msg.height;
      renderBrowserState();
    }
  }

  async function refreshHerdrSnapshot() {
    if (!app.herdrTransport) return;
    try {
      const data = await app.herdrTransport.request('GET', '/api/v1/mobile/snapshot');
      if (data && !data.error) {
        app.herdrSnapshot = {
          hostName: data.hostName || app.herdrSnapshot.hostName,
          workspacePath: data.workspacePath || '',
          harnesses: data.harnesses || [],
          sessions: data.sessions || [],
        };
        if (data.browser) {
          app.browser.running = Boolean(data.browser.running);
          if (data.browser.url) app.browser.url = data.browser.url;
          renderBrowserState();
        }
        populateHerdrHarnessPickers();
        renderHerdrSessions();
        if (!app.activeSessionId && app.herdrSnapshot.sessions.length > 0) {
          const running = app.herdrSnapshot.sessions.find((s) => s.status === 'running') || app.herdrSnapshot.sessions[app.herdrSnapshot.sessions.length - 1];
          if (running) attachHerdrSession(running.id);
        } else {
          scheduleRenderTuiViewport();
        }
      }
    } catch {}
  }

  async function connectHerdrNode(hostId) {
    if (!hostId) return;
    const dev = app.accountDevices.find((d) => d.hostId === hostId);
    if (!dev) return;
    if (herdrPollTimer) { clearInterval(herdrPollTimer); herdrPollTimer = null; }
    if (app.herdrTransport && app.herdrTransport !== app.primaryTransport) {
      app.herdrTransport.close();
    }
    app.herdrHostId = hostId;
    app.activeSessionId = '';
    app.sessionBuffers.clear();
    app.browser = { running: false, url: '', title: '', width: 1280, height: 800, tabs: [], lastFrame: '' };
    renderBrowserState();
    populateHerdrNodeSelect();
    document.getElementById('herdr-conn-badge').textContent = '连接中…';

    if (hostId === app.primaryHostId && app.primaryTransport) {
      app.herdrTransport = app.primaryTransport;
      app.herdrTransport.onStream = handleHerdrStream;
      app.herdrStatus = { ...app.primaryStatus };
      document.getElementById('herdr-conn-badge').textContent = app.herdrStatus.label;
      await refreshHerdrSnapshot();
      herdrPollTimer = setInterval(refreshHerdrSnapshot, 8000);
      syncHeaderStatus();
      return;
    }

    const isEdge = dev.hostPubKey === 'edge-https';
    const t = isEdge
      ? new EdgeHttpTransport({ hostId: dev.hostId, deviceToken: app.accountAccessToken })
      : new E2EERelayTransport({
          hostId: dev.hostId,
          hostPubKey: dev.hostPubKey || '',
          deviceToken: app.accountAccessToken,
        });
    t.onStatus = (level, label) => {
      app.herdrStatus = { level, label };
      document.getElementById('herdr-conn-badge').textContent = label;
      syncHeaderStatus();
    };
    t.onStream = handleHerdrStream;
    app.herdrTransport = t;
    try {
      await t.connect();
      await refreshHerdrSnapshot();
      herdrPollTimer = setInterval(refreshHerdrSnapshot, 8000);
    } catch (e) {
      app.herdrStatus = { level: 'err', label: e.message || '连接失败' };
      document.getElementById('herdr-conn-badge').textContent = app.herdrStatus.label;
      syncHeaderStatus();
    }
  }

  function ensureHerdrConnected() {
    populateHerdrNodeSelect();
    if (app.herdrHostId && app.herdrTransport) {
      scheduleRenderTuiViewport();
      return;
    }
    // Prefer an online Linux worker node for Harness TUI, otherwise any online node
    const preferred = app.accountDevices.find((d) => d.isOnline && d.platform === 'linux')
      || app.accountDevices.find((d) => d.isOnline && d.hostId !== app.primaryHostId)
      || app.accountDevices.find((d) => d.isOnline)
      || app.accountDevices[0];
    if (preferred) connectHerdrNode(preferred.hostId);
  }

  function openNodeInHerdr(hostId) {
    setRootTab('herdr');
    if (hostId && hostId !== app.herdrHostId) {
      connectHerdrNode(hostId);
    }
  }

  document.getElementById('herdr-node-select').onchange = (e) => {
    if (e.target.value) connectHerdrNode(e.target.value);
  };

  // Bottom Status Sheet
  const sheetBackdrop = document.getElementById('status-sheet');
  document.getElementById('btn-status-sheet').onclick = () => {
    const t = app.rootTab === 'master' ? app.primaryTransport : app.herdrTransport;
    document.getElementById('sheet-detail').innerHTML = t
      ? ('主控节点指纹：<code>' + esc(app.primaryHostId || 'local') + '</code><br/>当前视角节点：<code>' + esc(t.hostId || 'local') + '</code><br/>所有对话、Harness PTY 实时流与无头浏览器画面均经 AES-256-GCM 端到端加密传输，中继节点零明文可见。')
      : '尚未连接到任何主机。';
    sheetBackdrop.classList.add('show');
  };
  sheetBackdrop.onclick = (e) => { if (e.target === sheetBackdrop) sheetBackdrop.classList.remove('show'); };
  document.getElementById('btn-disconnect').onclick = () => {
    localStorage.removeItem(STORAGE_KEY);
    location.href = '/login';
  };

  // =========================================================================
  // Boot: Always default to Primary Control Node (主节点视角)
  // =========================================================================
  async function boot() {
    const link = parseCurrentLink();
    const saved = loadSavedSession(link.pathHostId);

    if (IS_RELAY_MODE) {
      try {
        const meRes = await fetch('/api/auth/me', {
          headers: app.accountAccessToken ? { Authorization: 'Bearer ' + app.accountAccessToken } : {},
        });
        if (meRes.ok) {
          const me = await meRes.json();
          if (me.accessToken) {
            app.accountAccessToken = me.accessToken;
            localStorage.setItem('pipibot_access_token', me.accessToken);
          }
          app.accountDevices = Array.isArray(me.devices) ? me.devices : [];
        }
      } catch {}
    }

    // Select Primary Control Node (macOS primary first, then online node)
    const primaryDev = app.accountDevices.find((d) => d.isOnline && d.platform === 'macos')
      || app.accountDevices.find((d) => d.platform === 'macos')
      || app.accountDevices.find((d) => d.isOnline)
      || app.accountDevices[0];

    const hostId = primaryDev?.hostId || link.pathHostId || saved?.hostId || '';
    const hostPubKey = primaryDev?.hostPubKey || link.hostPubKey || saved?.hostPubKey || '';
    const lanHint = link.lanHint || saved?.lanHint || '';
    const deviceToken = saved?.deviceToken || app.accountAccessToken || '';

    if (IS_RELAY_MODE && (!hostId || !hostPubKey)) {
      location.href = '/login';
      return;
    }

    app.primaryHostId = hostId;
    renderFleetList();
    populateHerdrNodeSelect();

    const t = new E2EERelayTransport({
      hostId,
      hostPubKey,
      lanHint,
      deviceToken,
      oneTimeToken: link.oneTimeToken,
    });
    t.onStatus = (level, label) => {
      app.primaryStatus = { level, label };
      syncHeaderStatus();
      renderMasterView();
    };
    t.onStream = (msg) => {
      if (app.herdrTransport === t) handleHerdrStream(msg);
    };
    app.primaryTransport = t;
    renderMasterView();

    try {
      await t.connect();
      await refreshMasterSnapshot();
      masterPollTimer = setInterval(refreshMasterSnapshot, 5000);
    } catch (e) {
      app.primaryStatus = { level: 'err', label: e.message || '连接失败' };
      syncHeaderStatus();
    }

    // If user explicitly opened /c/<workerHostId> (non-primary), pre-select it in Harness TUI tab
    if (link.pathHostId && link.pathHostId !== hostId) {
      openNodeInHerdr(link.pathHostId);
    }
  }

  boot();
})();
</script>
</body>
</html>`;
}
