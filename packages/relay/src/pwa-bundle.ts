/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/relay - pwa-bundle.ts
 * Consumer-grade, Apple Fluid Interface 5-Tab Mobile PWA Companion served by:
 *   - https://pipibot.jimizhou.com/c/<hostId>, /pair, /app (Oracle VPS Zero-Knowledge E2EE Relay)
 *   - PiPiBot Mac App local server
 *   - PiPiBot Linux/macOS Daemon Hub (/mobile)
 *
 * UX & Security Highlights:
 * - Vellum Light / Obsidian Dark native PiPiBot Design Tokens + frosted glass navigation & floating dock
 * - Pointer-down tactile micro-feedback, spring-feel bottom sheet for E2EE link diagnostics & theme switch
 * - Built-in lightweight Markdown renderer (code blocks, inline code, bold, lists) & syntax-colored Unified Diff viewer
 * - Starter prompt cards, Bot switcher strip, draft "Edit + Add Harness Rule", toast notifications
 * - WebCrypto P-256 ECDH + HKDF-SHA256 + AES-256-GCM E2EE + 3-tier transport (LAN -> WebRTC P2P -> WSS E2EE)
 */

export function renderUniversalManifest(): string {
  return JSON.stringify(
    {
      name: 'PiPiBot Companion',
      short_name: 'PiPiBot',
      description: '零知识端到端加密的个人 AI 管家团队随身控制台',
      start_url: '/app',
      scope: '/',
      display: 'standalone',
      background_color: '#FDFCF9',
      theme_color: '#5B4CE4',
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
 * & `PipiBotMarkView.swift` (Porcelain Ceramic chassis with concave crown notch, Sapphire-Indigo visor,
 * twin Arctic-Cyan optical lenses & crown telemetry pip).
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
      --canvas: #FDFCF9;
      --surface: #FFFFFF;
      --surface-soft: #F7F5F0;
      --surface-hover: #F1EDE4;
      --glass: rgba(253, 252, 249, 0.82);
      --border: rgba(23, 22, 20, 0.09);
      --border-strong: rgba(23, 22, 20, 0.16);
      --ink: #171614;
      --ink-2: #5E5B55;
      --ink-3: #8B867D;
      --soul: #5B4CE4;
      --soul-soft: rgba(91, 76, 228, 0.11);
      --soul-glow: rgba(91, 76, 228, 0.22);
      --ok: #047857;
      --ok-soft: rgba(4, 120, 87, 0.12);
      --warn: #B45309;
      --warn-soft: rgba(180, 83, 9, 0.12);
      --err: #B91C1C;
      --err-soft: rgba(185, 28, 28, 0.11);
      --diff-add: rgba(4, 120, 87, 0.11);
      --diff-del: rgba(185, 28, 28, 0.10);
      --shadow-sm: 0 2px 10px rgba(23, 22, 20, 0.04);
      --shadow-md: 0 12px 32px rgba(23, 22, 20, 0.10);
      --radius: 18px;
    }
    [data-theme="dark"] {
      --canvas: #08090B;
      --surface: #121418;
      --surface-soft: #171A20;
      --surface-hover: #1E222B;
      --glass: rgba(14, 16, 20, 0.82);
      --border: rgba(244, 245, 247, 0.09);
      --border-strong: rgba(244, 245, 247, 0.18);
      --ink: #F4F5F7;
      --ink-2: #A1A7B3;
      --ink-3: #6C7382;
      --soul: #7C6CF6;
      --soul-soft: rgba(124, 108, 246, 0.16);
      --soul-glow: rgba(124, 108, 246, 0.30);
      --ok: #10B981;
      --ok-soft: rgba(16, 185, 129, 0.16);
      --warn: #F59E0B;
      --warn-soft: rgba(245, 158, 11, 0.16);
      --err: #F87171;
      --err-soft: rgba(248, 113, 113, 0.16);
      --diff-add: rgba(16, 185, 129, 0.16);
      --diff-del: rgba(248, 113, 113, 0.15);
      --shadow-sm: 0 2px 12px rgba(0, 0, 0, 0.3);
      --shadow-md: 0 16px 40px rgba(0, 0, 0, 0.55);
    }
    @media (prefers-color-scheme: dark) {
      :root:not([data-theme="light"]) {
        --canvas: #08090B;
        --surface: #121418;
        --surface-soft: #171A20;
        --surface-hover: #1E222B;
        --glass: rgba(14, 16, 20, 0.82);
        --border: rgba(244, 245, 247, 0.09);
        --border-strong: rgba(244, 245, 247, 0.18);
        --ink: #F4F5F7;
        --ink-2: #A1A7B3;
        --ink-3: #6C7382;
        --soul: #7C6CF6;
        --soul-soft: rgba(124, 108, 246, 0.16);
        --soul-glow: rgba(124, 108, 246, 0.30);
        --ok: #10B981;
        --ok-soft: rgba(16, 185, 129, 0.16);
        --warn: #F59E0B;
        --warn-soft: rgba(245, 158, 11, 0.16);
        --err: #F87171;
        --err-soft: rgba(248, 113, 113, 0.16);
        --diff-add: rgba(16, 185, 129, 0.16);
        --diff-del: rgba(248, 113, 113, 0.15);
        --shadow-sm: 0 2px 12px rgba(0, 0, 0, 0.3);
        --shadow-md: 0 16px 40px rgba(0, 0, 0, 0.55);
      }
    }

    * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
    html, body {
      margin: 0; padding: 0; height: 100%; background: var(--canvas); color: var(--ink);
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", sans-serif;
      -webkit-font-smoothing: antialiased;
    }
    .app {
      position: relative; display: flex; flex-direction: column; height: 100dvh; max-width: 920px; margin: 0 auto;
    }

    /* Frosted Top Navigation */
    .topbar {
      position: sticky; top: 0; z-index: 20;
      display: flex; align-items: center; justify-content: space-between; gap: 10px;
      padding: calc(env(safe-area-inset-top) + 10px) 16px 11px;
      background: var(--glass);
      backdrop-filter: saturate(180%) blur(22px);
      -webkit-backdrop-filter: saturate(180%) blur(22px);
      border-bottom: 1px solid var(--border);
    }
    .brand { display: flex; align-items: center; gap: 10px; min-width: 0; }
    .avatar-orb {
      width: 36px; height: 36px; border-radius: 10px; flex-shrink: 0;
      display: grid; place-items: center; overflow: hidden;
    }
    .avatar-orb.pulse { animation: orbBreathe 2.6s ease-in-out infinite; }
    @keyframes orbBreathe { 0%,100% { transform: scale(1); } 50% { transform: scale(1.06); } }
    .brand-title { font-size: 15.5px; font-weight: 700; letter-spacing: -0.02em; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .brand-sub { font-size: 11.5px; color: var(--ink-2); display: flex; align-items: center; gap: 5px; margin-top: 1px; }
    .dot { width: 7px; height: 7px; border-radius: 50%; background: var(--warn); }
    .dot.ok { background: var(--ok); box-shadow: 0 0 0 3px var(--ok-soft); }
    .dot.err { background: var(--err); }

    .status-pill {
      border: 1px solid var(--border); background: var(--surface); color: var(--ink);
      padding: 6px 11px; border-radius: 999px; font-size: 11.5px; font-weight: 650;
      display: inline-flex; align-items: center; gap: 6px; cursor: pointer;
      box-shadow: var(--shadow-sm); transition: transform 100ms ease-out;
    }
    .status-pill:active { transform: scale(0.95); }
    .status-pill.ok { color: var(--ok); border-color: var(--ok-soft); background: var(--ok-soft); }

    /* Install Banner */
    .pwa-banner {
      display: none; align-items: center; justify-content: space-between; gap: 10px;
      padding: 9px 16px; font-size: 12px; color: var(--ink); background: var(--soul-soft);
      border-bottom: 1px solid var(--border);
    }
    .pwa-banner.show { display: flex; }

    /* Bot Switcher Strip */
    .bot-strip {
      display: none; gap: 7px; overflow-x: auto; padding: 9px 16px 4px; scrollbar-width: none;
    }
    .bot-strip::-webkit-scrollbar { display: none; }
    .bot-strip.show { display: flex; }
    .bot-chip {
      border: 1px solid var(--border); background: var(--surface); color: var(--ink-2);
      padding: 6px 12px; border-radius: 999px; font-size: 12px; font-weight: 600;
      white-space: nowrap; cursor: pointer; transition: transform 100ms ease-out, background 140ms ease;
    }
    .bot-chip:active { transform: scale(0.95); }
    .bot-chip.active { background: var(--ink); color: var(--canvas); border-color: transparent; }

    /* Main Scroll Canvas */
    .main {
      flex: 1; overflow-y: auto; -webkit-overflow-scrolling: touch;
      padding: 14px 16px 24px; display: flex; flex-direction: column; gap: 12px;
    }

    /* Cards & Typography */
    .card {
      background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius);
      padding: 15px 16px; display: flex; flex-direction: column; gap: 10px; box-shadow: var(--shadow-sm);
    }
    .row { display: flex; align-items: center; justify-content: space-between; gap: 8px; flex-wrap: wrap; }
    .card-title { font-size: 14.5px; font-weight: 700; letter-spacing: -0.015em; }
    .sub { font-size: 12.5px; color: var(--ink-2); line-height: 1.5; }
    .badge {
      font-size: 11px; font-weight: 650; padding: 3px 9px; border-radius: 999px;
      background: var(--soul-soft); color: var(--soul);
    }
    .badge.ok { background: var(--ok-soft); color: var(--ok); }
    .badge.warn { background: var(--warn-soft); color: var(--warn); }
    .badge.err { background: var(--err-soft); color: var(--err); }

    /* KPI 2x2 Grid */
    .kpi-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; }
    .kpi {
      background: var(--surface); border: 1px solid var(--border); border-radius: 16px;
      padding: 13px 14px; display: flex; flex-direction: column; gap: 4px; box-shadow: var(--shadow-sm);
    }
    .kpi-val { font-size: 22px; font-weight: 760; letter-spacing: -0.03em; }
    .kpi-label { font-size: 11.5px; color: var(--ink-2); font-weight: 500; }

    /* Chat Messages + Rich Markdown */
    .msg-wrap { display: flex; flex-direction: column; gap: 3px; }
    .msg-wrap.user { align-items: flex-end; }
    .msg-wrap.assistant { align-items: flex-start; }
    .msg-author { font-size: 11px; font-weight: 600; color: var(--ink-3); padding: 0 6px; }
    .msg {
      max-width: 88%; padding: 11px 14px; border-radius: 18px; font-size: 14.5px; line-height: 1.55;
      word-break: break-word;
    }
    .msg.user {
      background: var(--soul); color: #FFFFFF; border-bottom-right-radius: 5px;
      box-shadow: 0 6px 18px var(--soul-glow);
    }
    .msg.assistant {
      background: var(--surface); border: 1px solid var(--border); color: var(--ink);
      border-bottom-left-radius: 5px; box-shadow: var(--shadow-sm);
    }
    .msg pre {
      margin: 8px 0; padding: 10px 12px; border-radius: 10px; background: var(--surface-soft);
      border: 1px solid var(--border); overflow-x: auto; font-size: 12px; line-height: 1.45;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace; color: var(--ink);
    }
    .msg code {
      padding: 1px 5px; border-radius: 5px; background: var(--surface-soft);
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.9em;
    }
    .msg.user code { background: rgba(255,255,255,0.2); }

    /* Starter Prompts */
    .welcome-hero { text-align: center; padding: 24px 8px 10px; display: flex; flex-direction: column; align-items: center; gap: 10px; }
    .starter-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 9px; width: 100%; margin-top: 8px; }
    .starter-btn {
      text-align: left; padding: 12px 13px; border-radius: 15px; border: 1px solid var(--border);
      background: var(--surface); color: var(--ink); cursor: pointer; box-shadow: var(--shadow-sm);
      display: flex; flex-direction: column; gap: 4px; transition: transform 100ms ease-out;
    }
    .starter-btn:active { transform: scale(0.96); }
    .starter-btn strong { font-size: 13px; }
    .starter-btn span { font-size: 11.5px; color: var(--ink-2); }

    /* Syntax-Colored Unified Diff */
    .diff-box {
      border-radius: 12px; overflow: hidden; border: 1px solid var(--border); background: var(--surface-soft);
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 11.5px; max-height: 240px; overflow: auto;
    }
    .diff-line { padding: 2px 10px; white-space: pre; }
    .diff-line.add { background: var(--diff-add); color: var(--ok); }
    .diff-line.del { background: var(--diff-del); color: var(--err); }
    .diff-line.hunk { color: var(--soul); font-weight: 600; background: var(--soul-soft); }
    .proof-bar { height: 6px; border-radius: 999px; background: var(--surface-hover); overflow: hidden; }
    .proof-fill { height: 100%; background: linear-gradient(90deg, var(--soul), var(--ok)); border-radius: 999px; }

    /* Buttons & Inputs */
    .btn {
      border: 1px solid var(--border); background: var(--surface-soft); color: var(--ink);
      padding: 8px 14px; border-radius: 11px; font-size: 13px; font-weight: 650; cursor: pointer;
      display: inline-flex; align-items: center; justify-content: center; gap: 6px;
      transition: transform 100ms ease-out, opacity 120ms ease;
    }
    .btn:active { transform: scale(0.95); }
    .btn.primary { background: var(--ink); color: var(--canvas); border-color: transparent; }
    .btn.soul { background: var(--soul); color: #FFFFFF; border-color: transparent; box-shadow: 0 5px 16px var(--soul-glow); }
    .btn.ok { background: var(--ok); color: #FFFFFF; border-color: transparent; }
    .btn.danger { background: var(--err-soft); color: var(--err); border-color: transparent; }
    .btn:disabled { opacity: 0.45; }
    input.field {
      width: 100%; border: 1px solid var(--border-strong); border-radius: 12px; padding: 11px 13px;
      background: var(--canvas); color: var(--ink); font-size: 14px; outline: none; font-family: inherit;
    }
    input.field:focus { border-color: var(--soul); box-shadow: 0 0 0 3px var(--soul-soft); }

    /* Cloud Codex Composer */
    .composer-wrap {
      padding: 10px 16px 12px; background: var(--glass);
      backdrop-filter: saturate(180%) blur(22px); -webkit-backdrop-filter: saturate(180%) blur(22px);
      border-top: 1px solid var(--border);
    }
    .composer-box {
      display: flex; flex-direction: column; gap: 8px; padding: 11px 12px 9px 14px;
      background: var(--surface); border: 1px solid var(--border-strong); border-radius: 18px;
      box-shadow: 0 4px 20px rgba(0, 0, 0, 0.05);
      transition: border-color 140ms ease, box-shadow 140ms ease;
    }
    .composer-box:focus-within {
      border-color: var(--ink);
      box-shadow: 0 6px 24px rgba(0, 0, 0, 0.08);
    }
    .composer-box textarea {
      width: 100%; resize: none; min-height: 36px; max-height: 180px; overflow-y: auto; border: 0;
      padding: 2px 0; font-size: 14.5px; line-height: 1.5; background: transparent; color: var(--ink);
      outline: none; font-family: inherit;
    }
    .composer-toolbar {
      display: flex; align-items: center; justify-content: space-between; gap: 8px; flex-wrap: wrap;
      padding-top: 4px; border-top: 1px solid var(--border);
    }
    .composer-pickers {
      display: flex; align-items: center; gap: 6px; flex-wrap: wrap; min-width: 0; flex: 1;
    }
    .codex-select {
      appearance: none; -webkit-appearance: none; -moz-appearance: none;
      height: 28px; max-width: 240px; padding: 0 26px 0 11px; border-radius: 999px;
      border: 1px solid var(--border-strong); background-color: var(--surface-soft);
      color: var(--ink); font-size: 12px; font-weight: 600; font-family: inherit;
      line-height: 26px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
      cursor: pointer; outline: none; vertical-align: middle;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 24 24' fill='none' stroke='%23777' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpolyline points='6 9 12 15 18 9'/%3E%3C/svg%3E");
      background-repeat: no-repeat; background-position: right 9px center;
      transition: background-color 120ms ease, border-color 120ms ease;
    }
    .codex-select::picker-icon { display: none; }
    .codex-select:hover { border-color: var(--ink-3); background-color: var(--surface-hover); }
    .codex-select.mono { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 11.5px; font-weight: 500; }
    .composer-actions { display: flex; align-items: center; gap: 6px; flex-shrink: 0; }
    .shell-toggle {
      height: 28px; padding: 0 10px; border-radius: 999px; border: 1px solid var(--border-strong);
      background: transparent; color: var(--ink-2); font-size: 11.5px; font-weight: 650;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace; cursor: pointer;
      transition: all 120ms ease;
    }
    .shell-toggle.active { background: var(--ink); color: var(--canvas); border-color: var(--ink); }
    .send-btn {
      width: 30px; height: 30px; border-radius: 50%; border: 0; flex-shrink: 0;
      background: var(--ink); color: var(--canvas); font-size: 15px; font-weight: 700; cursor: pointer;
      display: grid; place-items: center; transition: transform 100ms ease-out, opacity 140ms ease;
    }
    .send-btn:active { transform: scale(0.90); }
    .send-btn:disabled { opacity: 0.35; }

    /* Frosted Bottom Tab Bar */
    .tabbar {
      display: grid; grid-template-columns: repeat(5, 1fr); gap: 4px;
      padding: 7px 10px calc(env(safe-area-inset-bottom) + 8px);
      background: var(--glass);
      backdrop-filter: saturate(180%) blur(24px); -webkit-backdrop-filter: saturate(180%) blur(24px);
      border-top: 1px solid var(--border);
    }
    .tab {
      position: relative; border: 0; background: transparent; color: var(--ink-3);
      font-size: 10.5px; font-weight: 600; padding: 6px 2px; border-radius: 12px; cursor: pointer;
      display: flex; flex-direction: column; align-items: center; gap: 3px;
      transition: transform 100ms ease-out, color 140ms ease, background 140ms ease;
    }
    .tab:active { transform: scale(0.93); }
    .tab.active { color: var(--soul); background: var(--soul-soft); }
    .tab svg { width: 20px; height: 20px; stroke: currentColor; fill: none; stroke-width: 1.9; stroke-linecap: round; stroke-linejoin: round; }
    .tab-dot {
      position: absolute; top: 4px; right: 16px; min-width: 16px; height: 16px; padding: 0 4px;
      border-radius: 999px; background: var(--err); color: #FFF; font-size: 10px; font-weight: 700;
      display: none; align-items: center; justify-content: center;
    }
    .tab-dot.show { display: inline-flex; }

    /* Bottom Sheet Modal */
    .sheet-backdrop {
      position: fixed; inset: 0; z-index: 50; background: rgba(0,0,0,0.42);
      display: none; align-items: flex-end; justify-content: center;
    }
    .sheet-backdrop.show { display: flex; }
    .sheet {
      width: 100%; max-width: 540px; background: var(--surface); border-radius: 26px 26px 0 0;
      padding: 12px 20px calc(env(safe-area-inset-bottom) + 22px);
      border-top: 1px solid var(--border); box-shadow: var(--shadow-md);
      display: flex; flex-direction: column; gap: 14px;
    }
    .sheet-handle { width: 40px; height: 4.5px; border-radius: 999px; background: var(--border-strong); margin: 0 auto 2px; }

    /* Toast */
    .toast {
      position: fixed; top: calc(env(safe-area-inset-top) + 64px); left: 50%; transform: translateX(-50%) translateY(-10px);
      z-index: 60; padding: 9px 16px; border-radius: 999px; background: var(--ink); color: var(--canvas);
      font-size: 12.5px; font-weight: 600; opacity: 0; pointer-events: none; transition: all 180ms ease;
      box-shadow: var(--shadow-md);
    }
    .toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }

    .empty { text-align: center; color: var(--ink-2); font-size: 13.5px; padding: 36px 18px; line-height: 1.6; }

    /* Desktop 3-Column Cloud Codex Layout (> 900px); Mobile PWA (<= 900px) stays untouched */
    .codex-sidebar, .codex-inspector { display: none; }
    .codex-center { display: flex; flex-direction: column; min-width: 0; height: 100%; overflow: hidden; }
    .nav-item {
      display: flex; align-items: center; justify-content: space-between; gap: 8px;
      width: 100%; padding: 8px 10px; border-radius: 10px; border: 0; background: transparent;
      color: var(--ink-2); font-size: 13px; font-weight: 550; text-align: left; cursor: pointer;
      transition: background 120ms ease, color 120ms ease;
    }
    .nav-item:hover { background: var(--surface-hover); color: var(--ink); }
    .nav-item.active { background: var(--surface); color: var(--ink); font-weight: 650; box-shadow: 0 1px 2px rgba(0,0,0,0.05); }
    .nav-section-title {
      font-size: 11px; font-weight: 650; color: var(--ink-3); text-transform: uppercase;
      letter-spacing: 0.04em; padding: 12px 10px 6px;
    }
    .node-item {
      display: flex; align-items: center; gap: 8px; width: 100%; padding: 8px 10px;
      border-radius: 10px; border: 1px solid transparent; background: transparent;
      color: var(--ink); font-size: 12.5px; text-align: left; cursor: pointer;
      transition: all 120ms ease;
    }
    .node-item:hover { background: var(--surface-hover); }
    .node-item.active { background: var(--surface); border-color: var(--border-strong); box-shadow: 0 1px 3px rgba(0,0,0,0.04); }
    .node-meta { font-size: 11px; color: var(--ink-3); margin-top: 1px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .node-pill {
      font-size: 10px; font-weight: 650; padding: 2px 6px; border-radius: 999px;
      background: var(--surface-soft); color: var(--ink-2); border: 1px solid var(--border); flex-shrink: 0;
    }
    .seg-group {
      display: inline-flex; gap: 2px; padding: 3px; border-radius: 10px;
      background: var(--surface-soft); border: 1px solid var(--border);
    }
    .seg-btn {
      border: 0; background: transparent; color: var(--ink-2); font-size: 12px; font-weight: 600;
      padding: 5px 10px; border-radius: 7px; cursor: pointer; transition: all 120ms ease;
    }
    .seg-btn.active { background: var(--surface); color: var(--ink); box-shadow: 0 1px 3px rgba(0,0,0,0.07); }
    .inspector-box {
      background: var(--surface); border: 1px solid var(--border); border-radius: 14px;
      padding: 13px; display: flex; flex-direction: column; gap: 10px;
      box-shadow: 0 1px 2px rgba(0,0,0,0.025);
    }
    .inspector-term {
      background: var(--canvas); color: var(--ink); border: 1px solid var(--border); border-radius: 10px;
      padding: 10px 11px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 11.5px; line-height: 1.55; max-height: 220px; overflow: auto;
      white-space: pre-wrap; word-break: break-word;
    }
    .quick-cmd-row { display: flex; flex-wrap: wrap; gap: 6px; }
    .quick-cmd-btn {
      border: 1px solid var(--border); background: var(--canvas); color: var(--ink-2);
      font-size: 11.5px; font-weight: 550; padding: 5px 9px; border-radius: 8px; cursor: pointer;
      transition: all 120ms ease;
    }
    .quick-cmd-btn:hover { color: var(--ink); border-color: var(--border-strong); background: var(--surface-hover); }
    .node-dropdown {
      background: var(--surface); border: 1px solid var(--border); border-radius: 12px;
      padding: 4px; margin: 6px 0 4px;
    }
    .node-dropdown > summary {
      list-style: none; display: flex; align-items: center; gap: 8px; padding: 7px 8px;
      cursor: pointer; border-radius: 8px; font-size: 12.5px; font-weight: 600; color: var(--ink);
      user-select: none; transition: background 120ms ease;
    }
    .node-dropdown > summary::-webkit-details-marker { display: none; }
    .node-dropdown > summary:hover { background: var(--surface-hover); }
    .node-dropdown-chevron { margin-left: auto; font-size: 10px; color: var(--ink-3); transition: transform 160ms ease; }
    .node-dropdown[open] .node-dropdown-chevron { transform: rotate(180deg); }
    .node-dropdown-body {
      display: flex; flex-direction: column; gap: 3px; padding: 6px 2px 2px;
      margin-top: 4px; border-top: 1px solid var(--border);
    }

    @media (min-width: 901px) {
      .app {
        max-width: 100%; width: 100%; display: grid;
        grid-template-columns: 264px minmax(0, 1fr) 316px;
        height: 100dvh; overflow: hidden;
      }
      .codex-sidebar {
        display: flex; flex-direction: column; height: 100dvh; overflow-y: auto;
        background: var(--surface-soft); border-right: 1px solid var(--border);
        padding: 14px 12px; gap: 4px;
      }
      .codex-inspector {
        display: flex; flex-direction: column; height: 100dvh; overflow-y: auto;
        background: var(--surface-soft); border-left: 1px solid var(--border);
        padding: 14px 12px; gap: 12px;
      }
      .tabbar, #device-strip, #pwa-banner { display: none !important; }
      .topbar { padding: 12px 22px; }
      .main { padding: 18px 26px; max-width: 900px; width: 100%; margin: 0 auto; }
      .composer-wrap { padding: 12px 26px 18px; max-width: 900px; width: 100%; margin: 0 auto; border-top: 0; background: transparent; backdrop-filter: none; }
    }
  </style>
</head>
<body>
<div class="app">
  <!-- Desktop Left Sidebar (3-Column Cloud Codex) -->
  <aside class="codex-sidebar" id="codex-sidebar">
    <div style="display:flex;align-items:center;gap:10px;padding:4px 8px 10px;border-bottom:1px solid var(--border);">
      <img src="/icon.svg?v=2" alt="PiPiBot" width="28" height="28" style="border-radius:8px;flex-shrink:0;" />
      <div style="min-width:0;flex:1;">
        <div style="font-size:14px;font-weight:720;letter-spacing:-0.02em;">PiPiBot Cloud</div>
        <div id="sidebar-user-email" style="font-size:11px;color:var(--ink-3);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">统一主控工作台</div>
      </div>
    </div>

    <details class="node-dropdown" id="sidebar-node-dropdown">
      <summary>
        <span class="dot ok" id="sidebar-active-node-dot" style="flex-shrink:0;"></span>
        <span id="sidebar-active-node-name" style="min-width:0;flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">切换执行节点</span>
        <span class="node-pill" id="sidebar-active-node-role">主控</span>
        <span class="node-dropdown-chevron">▾</span>
      </summary>
      <div class="node-dropdown-body">
        <div id="sidebar-node-list" style="display:flex;flex-direction:column;gap:3px;"></div>
        <a class="node-item" href="/login" style="text-decoration:none;color:var(--ink-2);font-size:12px;padding:6px 8px;margin-top:2px;border-top:1px solid var(--border);border-radius:0 0 8px 8px;">+ 纳管新设备</a>
      </div>
    </details>

    <div class="nav-section-title">工作模式</div>
    <button class="nav-item active" data-nav="chat" type="button"><span>💬 对话编排</span></button>
    <button class="nav-item" data-nav="harness" type="button"><span>⚡ Harness 控制台</span><span class="node-pill">独立</span></button>
    <button class="nav-item" data-nav="mission" type="button"><span>📋 任务台</span></button>
    <button class="nav-item" data-nav="approvals" type="button"><span>🛡️ 审批中心</span><span class="node-pill" id="nav-badge-approvals" style="display:none">0</span></button>
    <button class="nav-item" data-nav="diff" type="button"><span>🌿 Diff 审阅</span><span class="node-pill" id="nav-badge-diff" style="display:none">0</span></button>
    <button class="nav-item" data-nav="bots" type="button"><span>🤖 智能体与触发器</span></button>

    <div style="margin-top:auto;padding-top:12px;border-top:1px solid var(--border);display:flex;gap:6px;">
      <a class="btn" href="/login" style="flex:1;text-align:center;text-decoration:none;font-size:12px;padding:7px 8px;">设备管理</a>
      <button class="btn" id="btn-sidebar-theme" type="button" style="font-size:12px;padding:7px 10px;">🌗</button>
    </div>
  </aside>

  <!-- Center Main Workspace (Shared by Mobile PWA & Desktop 3-Column) -->
  <div class="codex-center">
    <header class="topbar">
      <div class="brand">
        <div class="avatar-orb pulse" id="avatar-orb">
          <img src="/icon.svg?v=2" alt="PiPiBot" width="36" height="36" style="display:block;width:100%;height:100%" />
        </div>
        <div style="min-width:0">
          <div class="brand-title" id="host-title">${hostTitle}</div>
          <div class="brand-sub"><span class="dot" id="conn-dot"></span><span id="conn-text">初始化中…</span></div>
        </div>
      </div>
      <button class="status-pill" id="btn-status-sheet" type="button">
        <span id="transport-badge">E2EE</span>
      </button>
    </header>

    <div class="pwa-banner" id="pwa-banner">
      <span>点击 Safari 分享 →「添加到主屏幕」，即可作为全屏 iOS App 长期使用。</span>
      <button class="btn" id="btn-dismiss-pwa" type="button" style="padding:5px 10px;font-size:11.5px">知道了</button>
    </div>

    <div class="bot-strip" id="device-strip" style="display:none;border-bottom:1px solid var(--border);padding-bottom:8px;"></div>

    <main class="main" id="main-view"></main>

    <div class="composer-wrap" id="composer-bar" style="display:none">
      <div class="composer-box">
        <textarea id="chat-input" rows="2" placeholder="发消息给主控管家（可直接自然语言指派去哪台 Linux 执行任务）…"></textarea>
        <div class="composer-toolbar">
          <div class="composer-pickers">
            <select id="picker-agent" class="codex-select" title="选择智能体或纯外接 CLI Harness"></select>
            <select id="picker-model" class="codex-select mono" title="读取自该 Harness 本地配置的模型" style="display:none"></select>
            <select id="picker-mode" class="codex-select" title="外接 Harness 执行模式（优先 ACP，其次 TUI PTY，CLI 无头用于自动编排）" style="display:none">
              <option value="acp">ACP 协议（推荐）</option>
              <option value="tui">TUI 终端 PTY</option>
              <option value="cli">CLI 无头</option>
            </select>
          </div>
          <div class="composer-actions">
            <button class="shell-toggle" id="btn-shell-mode" type="button" title="切换直接通过守护进程执行远程排查命令">&gt;_ 排查</button>
            <button class="send-btn" id="btn-send" type="button" aria-label="发送">↑</button>
          </div>
        </div>
      </div>
    </div>

    <nav class="tabbar">
      <button class="tab active" data-tab="chat" type="button">
        <svg viewBox="0 0 24 24"><path d="M21 12a8.5 8.5 0 0 1-12.6 7.4L3 21l1.6-5.4A8.5 8.5 0 1 1 21 12Z"/></svg>
        <span>对话</span>
      </button>
      <button class="tab" data-tab="harness" type="button">
        <svg viewBox="0 0 24 24"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>
        <span>Harness</span>
      </button>
      <button class="tab" data-tab="approvals" type="button">
        <span class="tab-dot" id="badge-approvals"></span>
        <svg viewBox="0 0 24 24"><path d="M12 3 4 7v6c0 5 3.5 7.5 8 8 4.5-.5 8-3 8-8V7l-8-4Z"/><path d="m9 12 2 2 4-4"/></svg>
        <span>审批</span>
      </button>
      <button class="tab" data-tab="diff" type="button">
        <span class="tab-dot" id="badge-diff"></span>
        <svg viewBox="0 0 24 24"><circle cx="6" cy="6" r="2.5"/><circle cx="18" cy="18" r="2.5"/><circle cx="18" cy="6" r="2.5"/><path d="M6 8.5v7A2.5 2.5 0 0 0 8.5 18H15.5"/><path d="M18 8.5V15.5"/></svg>
        <span>Diff</span>
      </button>
      <button class="tab" data-tab="bots" type="button">
        <svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="4"/><path d="M4 20a8 8 0 0 1 16 0"/></svg>
        <span>智能体</span>
      </button>
    </nav>
  </div>

  <!-- Desktop Right Inspector (Node Telemetry + Harnesses + Quick Remote Diagnostics) -->
  <aside class="codex-inspector" id="codex-inspector">
    <div class="inspector-box">
      <div class="row">
        <div style="font-size:12.5px;font-weight:700;">当前连接节点</div>
        <span class="badge ok" id="insp-conn-badge">E2EE</span>
      </div>
      <div id="insp-node-detail" style="font-size:12px;color:var(--ink-2);line-height:1.55;">加载节点上下文…</div>
    </div>

    <div class="inspector-box">
      <div class="row">
        <div style="font-size:12.5px;font-weight:700;">本机已上报 Harness</div>
        <button class="quick-cmd-btn" id="btn-open-harness-console" type="button">控制台 →</button>
      </div>
      <div id="insp-harness-list" style="display:flex;flex-direction:column;gap:6px;"></div>
    </div>

    <div class="inspector-box">
      <div class="row">
        <div style="font-size:12.5px;font-weight:700;">远程守护进程排查</div>
        <span style="font-size:11px;color:var(--ink-3);font-family:monospace;">daemon exec</span>
      </div>
      <div class="quick-cmd-row">
        <button class="quick-cmd-btn" data-qcmd="git status -sb" type="button">Git 状态</button>
        <button class="quick-cmd-btn" data-qcmd="df -h | head -n 8" type="button">磁盘</button>
        <button class="quick-cmd-btn" data-qcmd="uptime && free -h 2>/dev/null || vm_stat | head -n 5" type="button">负载/内存</button>
      </div>
      <div style="display:flex;gap:6px;align-items:center;">
        <input class="field" id="insp-cmd-input" style="padding:7px 10px;font-size:12px;font-family:monospace;border-radius:9px;" placeholder="输入远程排查命令…" />
        <button id="btn-insp-run" type="button" style="height:32px;padding:0 12px;border-radius:9px;border:0;background:var(--ink);color:var(--canvas);font-size:12px;font-weight:600;cursor:pointer;flex-shrink:0;">执行</button>
      </div>
      <div class="inspector-term" id="insp-term-out">点击上方快捷巡检或输入命令，经 E2EE 直连当前节点执行。</div>
    </div>
  </aside>
</div>

<div class="sheet-backdrop" id="status-sheet">
  <div class="sheet">
    <div class="sheet-handle"></div>
    <div class="row">
      <div class="card-title">端到端加密连接详情</div>
      <span class="badge ok">P-256 · AES-256-GCM</span>
    </div>
    <div class="sub" id="sheet-detail"></div>
    <div class="row">
      <button class="btn" id="btn-toggle-theme" type="button">切换亮/暗主题</button>
      <a class="btn" href="/">访问官网</a>
      <button class="btn danger" id="btn-disconnect" type="button">解除本机配对</button>
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

  function showToast(msg) {
    const el = document.getElementById('toast');
    el.textContent = msg;
    el.classList.add('show');
    clearTimeout(el._t);
    el._t = setTimeout(() => el.classList.remove('show'), 2200);
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
        dc.onopen = () => { clearTimeout(p2pTimer); this.mode = 'p2p'; this.onStatus('ok', 'P2P 打洞'); showToast('已升级为 WebRTC P2P 直连 ⚡'); };
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
  }

  const state = {
    tab: 'chat',
    selectedBotId: '',
    selectedModel: '',
    selectedMode: 'acp',
    shellExecMode: false,
    transport: null,
    statusLabel: '等待配对',
    snapshot: {
      hostName: 'PiPiBot',
      messages: [],
      bots: [],
      approvals: [],
      draftGates: [],
      evolutions: [],
      worktrees: [],
      sentinelIssues: [],
      triggers: [],
      usageSummary: null,
    },
  };

  const mainEl = document.getElementById('main-view');
  const composerEl = document.getElementById('composer-bar');
  const pickerAgentEl = document.getElementById('picker-agent');
  const pickerModelEl = document.getElementById('picker-model');
  const pickerModeEl = document.getElementById('picker-mode');
  const shellToggleBtn = document.getElementById('btn-shell-mode');
  const inputEl = document.getElementById('chat-input');

  pickerAgentEl.addEventListener('change', () => {
    state.selectedBotId = pickerAgentEl.value;
    state.selectedModel = '';
    syncComposerPickers();
  });
  pickerModelEl.addEventListener('change', () => {
    state.selectedModel = pickerModelEl.value;
  });
  pickerModeEl.addEventListener('change', () => {
    state.selectedMode = pickerModeEl.value;
  });
  shellToggleBtn.addEventListener('click', () => {
    state.shellExecMode = !state.shellExecMode;
    shellToggleBtn.classList.toggle('active', state.shellExecMode);
    inputEl.placeholder = state.shellExecMode
      ? '输入要在当前节点守护进程执行的 Shell 排查命令（如 git status / df -h / journalctl）…'
      : '向所选智能体或外接 Harness 派发任务…（Enter 发送，Shift+Enter 换行）';
  });

  function syncComposerPickers() {
    const bots = state.snapshot.bots || [];
    const harnesses = state.snapshot.harnesses || [];
    const items = [];
    if (bots.length === 0 && harnesses.length === 0) {
      items.push({ id: '', label: '✨ 当前管家', models: [], isHarness: false });
    } else {
      const hasNonHarness = bots.some((b) => b.kind !== 'harness');
      if (hasNonHarness) {
        items.push({ id: '', label: '✨ 当前管家', models: [], isHarness: false });
      }
      for (const b of bots) {
        items.push({
          id: b.id,
          label: (b.kind === 'harness' ? '⚡ ' : '🤖 ') + b.name,
          models: Array.isArray(b.models) ? b.models : [],
          defaultModel: b.defaultModel || '',
          configSource: b.configSource || '',
          isHarness: b.kind === 'harness',
        });
      }
      for (const h of harnesses) {
        if (!items.some((it) => it.id === h.id)) {
          items.push({
            id: h.id,
            label: '⚡ ' + h.name,
            models: Array.isArray(h.models) ? h.models : [],
            defaultModel: h.defaultModel || '',
            configSource: h.configSource || '',
            isHarness: true,
          });
        }
      }
    }

    if (!items.some((it) => it.id === state.selectedBotId)) {
      state.selectedBotId = items[0]?.id || '';
    }
    pickerAgentEl.innerHTML = items
      .map((it) => '<option value="' + esc(it.id) + '">' + esc(it.label) + '</option>')
      .join('');
    pickerAgentEl.value = state.selectedBotId;

    const current = items.find((it) => it.id === state.selectedBotId);
    if (current && current.models && current.models.length > 0) {
      pickerModelEl.style.display = 'inline-block';
      pickerModelEl.title = current.configSource ? ('模型配置来源：' + current.configSource) : '当前 Harness 可选模型';
      pickerModelEl.innerHTML = current.models
        .map((m) => '<option value="' + esc(m) + '">' + esc(m) + '</option>')
        .join('');
      if (!state.selectedModel || !current.models.includes(state.selectedModel)) {
        state.selectedModel = current.defaultModel || current.models[0];
      }
      pickerModelEl.value = state.selectedModel;
    } else {
      pickerModelEl.style.display = 'none';
    }

    pickerModeEl.style.display = current && current.isHarness ? 'inline-block' : 'none';
    pickerModeEl.value = state.selectedMode || 'acp';
  }
  const connDot = document.getElementById('conn-dot');
  const connText = document.getElementById('conn-text');
  const badgeEl = document.getElementById('transport-badge');
  const statusPill = document.getElementById('btn-status-sheet');

  inputEl.addEventListener('input', () => {
    inputEl.style.height = 'auto';
    inputEl.style.height = Math.min(150, Math.max(28, inputEl.scrollHeight)) + 'px';
  });

  const isStandalone = window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
  if (!isStandalone && !localStorage.getItem('pipibot_pwa_hint_dismissed')) {
    document.getElementById('pwa-banner').classList.add('show');
  }
  document.getElementById('btn-dismiss-pwa').onclick = () => {
    document.getElementById('pwa-banner').classList.remove('show');
    localStorage.setItem('pipibot_pwa_hint_dismissed', '1');
  };

  function setStatus(level, label) {
    state.statusLabel = label;
    connDot.className = 'dot ' + (level === 'ok' ? 'ok' : level === 'err' ? 'err' : '');
    connText.textContent = label;
    badgeEl.textContent = label;
    statusPill.className = 'status-pill ' + (level === 'ok' ? 'ok' : '');
  }

  function esc(str) {
    return String(str ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
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
    const lines = String(diffText || '').slice(0, 3200).split('\\n');
    return '<div class="diff-box">' + lines.map((line) => {
      let cls = 'diff-line';
      if (line.startsWith('+') && !line.startsWith('+++')) cls += ' add';
      else if (line.startsWith('-') && !line.startsWith('---')) cls += ' del';
      else if (line.startsWith('@@')) cls += ' hunk';
      return '<div class="' + cls + '">' + esc(line) + '</div>';
    }).join('') + '</div>';
  }

  async function refreshSnapshot() {
    if (!state.transport) return;
    try {
      const data = await state.transport.request('GET', '/api/v1/mobile/snapshot');
      if (data && !data.error) {
        state.snapshot = Object.assign(state.snapshot, data);
        if (data.hostName) document.getElementById('host-title').textContent = data.hostName;
        const pend = (state.snapshot.approvals?.length || 0) + (state.snapshot.draftGates?.length || 0) + (state.snapshot.evolutions?.length || 0);
        const appBadge = document.getElementById('badge-approvals');
        appBadge.textContent = pend > 9 ? '9+' : String(pend);
        appBadge.classList.toggle('show', pend > 0);
        const diffs = state.snapshot.worktrees?.length || 0;
        const diffBadge = document.getElementById('badge-diff');
        diffBadge.textContent = String(diffs);
        diffBadge.classList.toggle('show', diffs > 0);
        render();
      }
    } catch {}
  }

  function renderConnectPrompt() {
    composerEl.style.display = 'none';
    mainEl.innerHTML = \`
      <div class="welcome-hero">
        <div class="avatar-orb pulse" style="width:68px;height:68px;border-radius:18px">
          <img src="/icon.svg?v=2" alt="PiPiBot" width="68" height="68" style="display:block;width:100%;height:100%" />
        </div>
        <div style="font-size:20px;font-weight:760;letter-spacing:-0.025em">连接你的 PiPiBot 主机</div>
        <div class="sub" style="max-width:340px">在 Mac 任务台点击「开启中继并生成链接」，用手机相机扫二维码或粘贴统一链接，即刻建立零知识端到端加密通道。</div>
      </div>
      <div class="card">
        <div class="card-title">粘贴统一配对链接</div>
        <input class="field" id="pair-url-input" placeholder="https://pipibot.jimizhou.com/c/xxxx#t=...&k=..." />
        <button class="btn soul" id="btn-pair-connect" type="button" style="width:100%;padding:11px">建立端到端加密连接</button>
      </div>
      <div class="card">
        <div class="card-title">还没有安装 Mac / Linux 端？</div>
        <div class="sub">PiPiBot 100% 开源免费（MIT），支持原生 macOS 应用与 Linux 无界面多机集群。</div>
        <div class="row">
          <a class="btn primary" href="/">查看品牌官网</a>
          <a class="btn" href="https://github.com/JimiZhou/pipibot" target="_blank" rel="noopener">GitHub 源码</a>
        </div>
      </div>
    \`;
    document.getElementById('btn-pair-connect').onclick = () => {
      const raw = document.getElementById('pair-url-input').value.trim();
      if (raw) location.href = raw;
      else showToast('请先粘贴完整的配对链接');
    };
  }

  async function sendChatText(text) {
    const clean = text.trim();
    if (!clean || !state.transport) return;
    inputEl.value = '';
    inputEl.style.height = '36px';
    if (state.shellExecMode) {
      state.snapshot.messages.push({ role: 'user', content: '\`\`\`bash\\n$ ' + clean + '\\n\`\`\`' });
      render();
      try {
        const res = await state.transport.request('POST', '/api/shell/exec', { command: clean, timeoutMs: 20000 });
        const out = [res.stdout || '', res.stderr ? ('stderr:\\n' + res.stderr) : ''].filter(Boolean).join('\\n') || '(无输出)';
        state.snapshot.messages.push({
          role: 'assistant',
          author: '远程守护进程 · exit=' + (res.exitCode ?? 0),
          content: '\`\`\`\\n' + out + '\\n\`\`\`',
        });
        render();
      } catch (e) {
        state.snapshot.messages.push({ role: 'assistant', author: '系统', content: '远程命令执行失败：' + e.message });
        render();
      }
      return;
    }
    state.snapshot.messages.push({ role: 'user', content: clean });
    render();
    try {
      await state.transport.request('POST', '/api/v1/mobile/chat', {
        text: clean,
        botId: state.selectedBotId || undefined,
        model: state.selectedModel || undefined,
        mode: state.selectedMode || 'acp',
      });
      showToast('已加密送达主机');
      setTimeout(refreshSnapshot, 1200);
      setTimeout(refreshSnapshot, 3500);
    } catch (e) {
      state.snapshot.messages.push({ role: 'assistant', author: '系统', content: '发送失败：' + e.message });
      render();
    }
  }

  function render() {
    if (!state.transport) { renderConnectPrompt(); return; }
    const s = state.snapshot;
    composerEl.style.display = (state.tab === 'chat' || state.tab === 'harness') ? 'block' : 'none';
    if (state.tab === 'chat' || state.tab === 'harness') {
      syncComposerPickers();
    }
    syncSidebarAndInspector();

    if (state.tab === 'harness') {
      const harnesses = (s.harnesses && s.harnesses.length ? s.harnesses : (s.bots || []).filter((b) => b.kind === 'harness'));
      const sessions = s.sessions || [];
      const activeH = harnesses.find((h) => h.id === state.selectedBotId) || harnesses[0];
      if (activeH && state.selectedBotId !== activeH.id) {
        state.selectedBotId = activeH.id;
        syncComposerPickers();
      }
      const modeBar = \`
        <div class="card" style="gap:12px;">
          <div class="row">
            <div>
              <div class="card-title">⚡ Agent Harness 独立控制台</div>
              <div class="sub">直连当前节点上的外接 CLI Harness，独立于普通对话；自动读取本机 Config 模型。</div>
            </div>
            <div class="seg-group">
              <button class="seg-btn \${state.selectedMode === 'acp' ? 'active' : ''}" data-hmode="acp" type="button">ACP 协议</button>
              <button class="seg-btn \${state.selectedMode === 'tui' ? 'active' : ''}" data-hmode="tui" type="button">TUI PTY</button>
              <button class="seg-btn \${state.selectedMode === 'cli' ? 'active' : ''}" data-hmode="cli" type="button">CLI 无头</button>
            </div>
          </div>
          \${harnesses.length === 0
            ? '<div class="sub">当前节点未上报纯外接 CLI Harness。可在左侧切换到已接入的 Linux 节点（如 lenovo-amd-workstation），或在本机安装 claude / codex / pi / agy / omp。</div>'
            : '<div style="display:flex;flex-wrap:wrap;gap:8px;">' + harnesses.map((h) => {
                const isAct = activeH && h.id === activeH.id;
                return '<button class="btn ' + (isAct ? 'primary' : '') + '" data-pick-harness="' + esc(h.id) + '" type="button" style="font-size:12.5px;padding:7px 12px;">⚡ ' + esc(h.name) + (h.defaultModel ? ' <span style="opacity:0.7;font-family:monospace;font-size:11px;">(' + esc(h.defaultModel) + ')</span>' : '') + '</button>';
              }).join('') + '</div>'}
          \${activeH && activeH.configSource ? '<div class="sub" style="font-family:monospace;font-size:11px;">配置来源：' + esc(activeH.configSource) + '</div>' : ''}
        </div>
      \`;

      const sessionCards = sessions.length === 0
        ? '<div class="empty">⚡ 暂无运行中的 Harness 会话。<br/>在下方输入框选择模型并直接下发开发或排查任务，即可启动 ' + esc(state.selectedMode.toUpperCase()) + ' 会话。</div>'
        : sessions.slice().reverse().map((rs) => {
            const isRun = rs.status === 'running';
            const outText = (rs.outputLines || []).slice(-60).join('\\n') || '等待输出…';
            return \`
              <div class="card" style="gap:10px;">
                <div class="row">
                  <div style="display:flex;align-items:center;gap:8px;">
                    <span class="badge \${isRun ? 'ok' : ''}">\${isRun ? '● 运行中' : ('已结束 · exit=' + (rs.exitCode ?? 0))}</span>
                    <strong style="font-size:13px;">\${esc(rs.agent)}</strong>
                  </div>
                  <div style="display:flex;gap:6px;">
                    \${isRun ? '<button class="btn" style="padding:4px 9px;font-size:11.5px" data-sess-takeover="' + esc(rs.id) + '">接管</button>' : ''}
                    \${isRun ? '<button class="btn danger" style="padding:4px 9px;font-size:11.5px" data-sess-stop="' + esc(rs.id) + '">停止</button>' : ''}
                  </div>
                </div>
                <div class="inspector-term" style="max-height:320px;">\${esc(outText)}</div>
                \${isRun && rs.mode === 'tui' ? '<div style="display:flex;gap:6px;"><input class="field" style="padding:7px 10px;font-size:12.5px;font-family:monospace;" data-sess-input-box="' + esc(rs.id) + '" placeholder="向 TUI PTY 发送交互输入…" /><button class="btn primary" style="padding:6px 12px;font-size:12px" data-sess-send="' + esc(rs.id) + '">发送</button></div>' : ''}
              </div>
            \`;
          }).join('');

      mainEl.innerHTML = modeBar + sessionCards;
      mainEl.querySelectorAll('[data-hmode]').forEach((b) => {
        b.onclick = () => {
          state.selectedMode = b.dataset.hmode;
          pickerModeEl.value = state.selectedMode;
          render();
        };
      });
      mainEl.querySelectorAll('[data-pick-harness]').forEach((b) => {
        b.onclick = () => {
          state.selectedBotId = b.dataset.pickHarness;
          state.selectedModel = '';
          render();
        };
      });
      bindSessionControls(mainEl);
      return;
    }

    if (state.tab === 'chat') {
      const msgs = s.messages || [];
      if (msgs.length === 0) {
        mainEl.innerHTML = \`
          <div class="welcome-hero">
            <div style="font-size:18px;font-weight:720;letter-spacing:-0.02em">随时派活给你的数字团队</div>
            <div class="sub">端到端加密通道已就绪，选一张卡片或直接发消息：</div>
            <div class="starter-grid">
              <button class="starter-btn" data-prompt="帮我整理今天最重要的 3 件事和待处理项目状态"><strong>📋 今日待办巡检</strong><span>汇总进展与优先事项</span></button>
              <button class="starter-btn" data-prompt="帮我检查当前项目的 Git 状态和最近变更"><strong>🌿 检查代码状态</strong><span>快速扫描工作区变更</span></button>
              <button class="starter-btn" data-prompt="帮我新建一个自动化定时巡检 Bot"><strong>🥚 访谈建新 Bot</strong><span>召唤蛋宝生成蓝图</span></button>
              <button class="starter-btn" data-prompt="列出当前在线的多机节点和运行中的触发器"><strong>🖥️ 集群状态总览</strong><span>查看多机与触发器</span></button>
            </div>
          </div>
        \`;
        mainEl.querySelectorAll('.starter-btn').forEach((b) => {
          b.onclick = () => sendChatText(b.dataset.prompt);
        });
        return;
      }
      const runningSessions = (s.sessions || []).filter((ss) => ss.status === 'running');
      const liveBanner = runningSessions.length > 0 ? runningSessions.map((rs) => \`
        <div class="card" style="padding:11px 14px;gap:8px;border-color:var(--border-strong);">
          <div class="row">
            <span class="badge ok">● 运行中 · \${esc(rs.agent)}</span>
            <div style="display:flex;gap:6px">
              <button class="btn" style="padding:4px 9px;font-size:11.5px" data-sess-takeover="\${esc(rs.id)}">接管</button>
              <button class="btn danger" style="padding:4px 9px;font-size:11.5px" data-sess-stop="\${esc(rs.id)}">停止</button>
            </div>
          </div>
          \${rs.mode === 'tui' ? '<div style="display:flex;gap:6px"><input class="field" style="padding:7px 10px;font-size:12.5px" data-sess-input-box="' + esc(rs.id) + '" placeholder="向 TUI PTY 发送交互输入（回车发送）…" /><button class="btn primary" style="padding:6px 12px;font-size:12px" data-sess-send="' + esc(rs.id) + '">输入</button></div>' : ''}
        </div>
      \`).join('') : '';

      mainEl.innerHTML = liveBanner + msgs.map((m) => \`
        <div class="msg-wrap \${m.role === 'user' ? 'user' : 'assistant'}">
          \${m.role !== 'user' && m.author ? '<div class="msg-author">' + esc(m.author) + '</div>' : ''}
          <div class="msg \${m.role === 'user' ? 'user' : 'assistant'}">\${renderMarkdown(m.content)}</div>
        </div>
      \`).join('');
      mainEl.querySelectorAll('[data-sess-takeover]').forEach((b) => {
        b.onclick = async () => {
          await state.transport.request('POST', '/api/agents/' + b.dataset.sessTakeover + '/takeover', {});
          showToast('已接管当前会话控制权 ✓');
        };
      });
      mainEl.querySelectorAll('[data-sess-stop]').forEach((b) => {
        b.onclick = async () => {
          await state.transport.request('POST', '/api/agents/' + b.dataset.sessStop + '/stop', {});
          showToast('已发送停止信号');
          setTimeout(refreshSnapshot, 600);
        };
      });
      mainEl.querySelectorAll('[data-sess-send]').forEach((b) => {
        b.onclick = async () => {
          const sid = b.dataset.sessSend;
          const box = mainEl.querySelector('[data-sess-input-box="' + sid + '"]');
          const val = box ? box.value : '';
          if (!val) return;
          box.value = '';
          await state.transport.request('POST', '/api/agents/' + sid + '/input', { text: val, forceTakeover: true });
          showToast('已发送到 TUI PTY');
          setTimeout(refreshSnapshot, 800);
        };
      });
      mainEl.scrollTop = mainEl.scrollHeight;
      return;
    }

    if (state.tab === 'mission') {
      const issues = s.sentinelIssues || [];
      const u = s.usageSummary;
      const pend = (s.approvals?.length || 0) + (s.draftGates?.length || 0) + (s.evolutions?.length || 0);
      mainEl.innerHTML = \`
        <div class="kpi-grid">
          <div class="kpi"><div class="kpi-val">\${(s.bots || []).length}</div><div class="kpi-label">活跃智能体</div></div>
          <div class="kpi"><div class="kpi-val">\${pend}</div><div class="kpi-label">待你确认项</div></div>
          <div class="kpi"><div class="kpi-val">\${(s.worktrees || []).length}</div><div class="kpi-label">待审阅 Diff</div></div>
          <div class="kpi"><div class="kpi-val">$\${Number(u?.todayCostUSD || 0).toFixed(2)}</div><div class="kpi-label">今日估算消耗（仅提醒）</div></div>
        </div>
        <div class="card">
          <div class="row"><div class="card-title">Sentinel 零 LLM 健康哨兵</div><span class="badge \${issues.length ? 'warn' : 'ok'}">\${issues.length ? (issues.length + ' 项聚类') : '健康'}</span></div>
          \${issues.length === 0
            ? '<div class="sub">零重复工具报错或队列阻塞。Credential Broker 与 Bot Box 隔离运行中。</div>'
            : issues.map((it) => '<div class="row"><span class="sub">[' + it.count + 'x] ' + esc(it.normalizedTitle) + '</span><span class="badge ' + (it.severity === 'high' ? 'err' : 'warn') + '">' + esc(it.severity) + '</span></div>').join('')}
        </div>
      \`;
      return;
    }

    if (state.tab === 'approvals') {
      const blocks = [];
      for (const a of (s.approvals || [])) {
        blocks.push(\`<div class="card">
          <div class="row"><div class="card-title">\${esc(a.title)}</div><span class="badge warn">高危工具审批</span></div>
          <div class="sub">\${esc(a.summary || '')}</div>
          <div class="row"><button class="btn ok" data-act="approve" data-id="\${esc(a.id)}">允许执行</button><button class="btn danger" data-act="deny" data-id="\${esc(a.id)}">拒绝</button></div>
        </div>\`);
      }
      for (const d of (s.draftGates || [])) {
        blocks.push(\`<div class="card">
          <div class="row"><div class="card-title">Day-Shift 外发草稿门控</div><span class="badge">Draft Gate</span></div>
          <div class="sub">\${esc(d.draftContent || '')}</div>
          <div class="row"><button class="btn ok" data-act="draft-approve" data-id="\${esc(d.id)}">批准发送</button><button class="btn danger" data-act="draft-reject" data-id="\${esc(d.id)}">驳回</button></div>
        </div>\`);
      }
      for (const e of (s.evolutions || [])) {
        blocks.push(\`<div class="card">
          <div class="row"><div class="card-title">Blueprint 自进化提案</div><span class="badge ok">EvolutionDiff</span></div>
          <div class="sub">\${esc(e.rationale || e.proposedRule || '')}</div>
          <div class="row"><button class="btn ok" data-act="evo-approve" data-id="\${esc(e.id)}">采纳规则</button><button class="btn danger" data-act="evo-reject" data-id="\${esc(e.id)}">忽略</button></div>
        </div>\`);
      }
      mainEl.innerHTML = blocks.length ? blocks.join('') : '<div class="empty">✨ 当前没有任何待审批操作或进化提案，一切井井有条。</div>';
      mainEl.querySelectorAll('button[data-act]').forEach((btn) => {
        btn.onclick = async () => {
          btn.disabled = true;
          await state.transport.request('POST', '/api/v1/mobile/action', { action: btn.dataset.act, id: btn.dataset.id });
          showToast('已提交决策 ✓');
          await refreshSnapshot();
        };
      });
      return;
    }

    if (state.tab === 'diff') {
      const wts = s.worktrees || [];
      if (!wts.length) {
        mainEl.innerHTML = '<div class="empty">🌿 当前没有待审阅的隔离 Worktree 分支。<br/>当智能体在独立分支完成代码修改与验证后会出现在这里。</div>';
        return;
      }
      mainEl.innerHTML = wts.map((w) => {
        const score = Number(w.proofScore ?? 0);
        return \`<div class="card">
          <div class="row"><div class="card-title">\${esc(w.branchName)}</div><span class="badge \${score >= 80 ? 'ok' : 'warn'}">Proof \${score}%</span></div>
          <div class="proof-bar"><div class="proof-fill" style="width:\${Math.min(100, Math.max(8, score))}%"></div></div>
          <div class="sub">\${esc(w.summary || '')}</div>
          \${renderColoredDiff(w.diffText)}
          <div class="row">
            <button class="btn ok" data-wt="merge" data-id="\${esc(w.id)}">Squash 合入并清理</button>
            <button class="btn danger" data-wt="discard" data-id="\${esc(w.id)}">放弃分支</button>
          </div>
        </div>\`;
      }).join('');
      mainEl.querySelectorAll('button[data-wt]').forEach((btn) => {
        btn.onclick = async () => {
          btn.disabled = true;
          await state.transport.request('POST', '/api/v1/mobile/action', { action: 'worktree-' + btn.dataset.wt, id: btn.dataset.id });
          showToast(btn.dataset.wt === 'merge' ? '已合入并清理 Worktree ✓' : '已放弃该隔离分支');
          await refreshSnapshot();
        };
      });
      return;
    }

    if (state.tab === 'bots') {
      const bots = s.bots || [];
      const triggers = s.triggers || [];
      mainEl.innerHTML = \`
        <div class="card">
          <div class="row"><div class="card-title">智能体团队</div><span class="badge">\${bots.length} 位</span></div>
          \${bots.map((b) => '<div class="row" style="padding:6px 0;border-top:1px solid var(--border)"><div><div style="font-size:13.5px;font-weight:650">' + esc(b.name) + '</div><div class="sub">' + esc(b.role || '') + '</div></div><span class="badge ' + (b.isolation === 'sandbox_box' ? 'ok' : '') + '">' + (b.isolation === 'sandbox_box' ? 'Bot Box' : 'Host') + '</span></div>').join('') || '<div class="sub">等待主机同步…</div>'}
        </div>
        <div class="card">
          <div class="row"><div class="card-title">自动化触发器</div><span class="badge">\${triggers.length} 条</span></div>
          \${triggers.map((t) => '<div class="row" style="padding:5px 0;border-top:1px solid var(--border)"><span style="font-size:13px;font-weight:500">' + esc(t.title) + '</span><span class="badge ' + (t.enabled ? 'ok' : 'warn') + '">' + (t.enabled ? '运行中' : '已暂停') + '</span></div>').join('') || '<div class="sub">暂无自动化触发器</div>'}
        </div>
      \`;
    }
  }

  function bindSessionControls(rootEl) {
    rootEl.querySelectorAll('[data-sess-takeover]').forEach((b) => {
      b.onclick = async () => {
        await state.transport.request('POST', '/api/agents/' + b.dataset.sessTakeover + '/takeover', {});
        showToast('已接管当前会话控制权 ✓');
      };
    });
    rootEl.querySelectorAll('[data-sess-stop]').forEach((b) => {
      b.onclick = async () => {
        await state.transport.request('POST', '/api/agents/' + b.dataset.sessStop + '/stop', {});
        showToast('已发送停止信号');
        setTimeout(refreshSnapshot, 600);
      };
    });
    rootEl.querySelectorAll('[data-sess-send]').forEach((b) => {
      b.onclick = async () => {
        const sid = b.dataset.sessSend;
        const box = rootEl.querySelector('[data-sess-input-box="' + sid + '"]');
        const val = box ? box.value : '';
        if (!val) return;
        box.value = '';
        await state.transport.request('POST', '/api/agents/' + sid + '/input', { text: val, forceTakeover: true });
        showToast('已发送到 TUI PTY');
        setTimeout(refreshSnapshot, 800);
      };
    });
  }

  function syncSidebarAndInspector() {
    document.querySelectorAll('.nav-item[data-nav]').forEach((el) => {
      el.classList.toggle('active', el.dataset.nav === state.tab);
    });
    const s = state.snapshot;
    const pend = (s.approvals?.length || 0) + (s.draftGates?.length || 0) + (s.evolutions?.length || 0);
    const navApp = document.getElementById('nav-badge-approvals');
    if (navApp) { navApp.textContent = String(pend); navApp.style.display = pend > 0 ? 'inline-block' : 'none'; }
    const navDiff = document.getElementById('nav-badge-diff');
    const wtCount = (s.worktrees || []).length;
    if (navDiff) { navDiff.textContent = String(wtCount); navDiff.style.display = wtCount > 0 ? 'inline-block' : 'none'; }

    const inspBadge = document.getElementById('insp-conn-badge');
    if (inspBadge) inspBadge.textContent = state.statusLabel || 'E2EE';

    const inspDetail = document.getElementById('insp-node-detail');
    if (inspDetail) {
      const curDev = accountDevices.find((d) => d.hostId === state.transport?.hostId);
      const plat = curDev?.platform || s.platform || 'macos';
      const ws = curDev?.workspacePath || s.workspacePath || '—';
      inspDetail.innerHTML =
        '<div><strong>' + esc(curDev?.name || s.hostName || 'PiPiBot') + '</strong> · ' + esc(plat) + '</div>' +
        '<div style="font-family:monospace;font-size:11px;margin-top:4px;word-break:break-all;">工作区：' + esc(ws) + '</div>' +
        '<div style="font-family:monospace;font-size:11px;margin-top:2px;">指纹：' + esc(state.transport?.hostId || 'local') + '</div>';
    }

    const inspHarnesses = document.getElementById('insp-harness-list');
    if (inspHarnesses) {
      const hs = (s.harnesses && s.harnesses.length ? s.harnesses : (s.bots || []).filter((b) => b.kind === 'harness'));
      if (!hs.length) {
        inspHarnesses.innerHTML = '<div style="font-size:12px;color:var(--ink-3);">当前节点为主控/管家模式，或尚未检测到外接 CLI Harness。</div>';
      } else {
        inspHarnesses.innerHTML = hs.map((h) =>
          '<button class="node-item" data-jump-harness="' + esc(h.id) + '" type="button" style="padding:6px 8px;">' +
          '<div style="min-width:0;flex:1;"><div style="font-weight:650;font-size:12px;">⚡ ' + esc(h.name) + '</div>' +
          '<div class="node-meta" style="font-family:monospace;">' + esc(h.defaultModel || 'default') + '</div></div>' +
          '<span class="node-pill">进入</span></button>'
        ).join('');
        inspHarnesses.querySelectorAll('[data-jump-harness]').forEach((btn) => {
          btn.onclick = () => {
            state.selectedBotId = btn.dataset.jumpHarness;
            state.selectedModel = '';
            setActiveTab('harness');
          };
        });
      }
    }
  }

  function setActiveTab(tabName) {
    state.tab = tabName;
    document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === tabName));
    document.querySelectorAll('.nav-item[data-nav]').forEach((n) => n.classList.toggle('active', n.dataset.nav === tabName));
    render();
  }

  document.querySelectorAll('.tab').forEach((el) => {
    el.onclick = () => setActiveTab(el.dataset.tab);
  });
  document.querySelectorAll('.nav-item[data-nav]').forEach((el) => {
    el.onclick = () => setActiveTab(el.dataset.nav);
  });
  const btnOpenHarness = document.getElementById('btn-open-harness-console');
  if (btnOpenHarness) btnOpenHarness.onclick = () => setActiveTab('harness');
  const btnSidebarTheme = document.getElementById('btn-sidebar-theme');
  if (btnSidebarTheme) {
    btnSidebarTheme.onclick = () => {
      const cur = document.documentElement.getAttribute('data-theme');
      const next = cur === 'dark' ? 'light' : 'dark';
      document.documentElement.setAttribute('data-theme', next);
      localStorage.setItem('pipibot_theme', next);
    };
  }

  async function runInspectorCommand(cmd) {
    const clean = (cmd || '').trim();
    const outEl = document.getElementById('insp-term-out');
    if (!clean || !state.transport || !outEl) return;
    outEl.textContent = '$ ' + clean + '\\n⏳ 正在通过 E2EE 执行…';
    try {
      const res = await state.transport.request('POST', '/api/shell/exec', { command: clean, timeoutMs: 20000 });
      const text = [res.stdout || '', res.stderr ? ('stderr:\\n' + res.stderr) : ''].filter(Boolean).join('\\n') || '(无输出)';
      outEl.textContent = '$ ' + clean + ' (exit=' + (res.exitCode ?? 0) + ')\\n' + text;
    } catch (e) {
      outEl.textContent = '$ ' + clean + '\\n❌ ' + (e.message || '执行失败（Mac 主控请通过对话自然语言调度）');
    }
  }
  document.querySelectorAll('[data-qcmd]').forEach((b) => {
    b.onclick = () => runInspectorCommand(b.dataset.qcmd);
  });
  const inspCmdInput = document.getElementById('insp-cmd-input');
  const inspRunBtn = document.getElementById('btn-insp-run');
  if (inspRunBtn && inspCmdInput) {
    inspRunBtn.onclick = () => { runInspectorCommand(inspCmdInput.value); inspCmdInput.value = ''; };
    inspCmdInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') { e.preventDefault(); runInspectorCommand(inspCmdInput.value); inspCmdInput.value = ''; }
    });
  }

  document.getElementById('btn-send').onclick = () => sendChatText(inputEl.value);
  inputEl.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      sendChatText(inputEl.value);
    }
  });

  // Bottom sheet interactions
  const sheetBackdrop = document.getElementById('status-sheet');
  statusPill.onclick = () => {
    const t = state.transport;
    const liveLabel = t && t.ws && t.ws.readyState === 1
      ? (t.mode === 'p2p' ? 'WebRTC P2P 直连（已加密）' : 'E2EE 加密中继已连接')
      : state.statusLabel;
    document.getElementById('sheet-detail').innerHTML = t
      ? ('当前传输通道：<strong>' + esc(liveLabel) + '</strong><br/>主机指纹：<code>' + esc(t.hostId || 'local') + '</code><br/>所有业务载荷与 WebRTC 信令均经端到端 AES-256-GCM 加密，中继节点全程零明文可见。')
      : '当前尚未绑定任何 PiPiBot 主机。';
    sheetBackdrop.classList.add('show');
  };
  sheetBackdrop.onclick = (e) => { if (e.target === sheetBackdrop) sheetBackdrop.classList.remove('show'); };
  document.getElementById('btn-toggle-theme').onclick = () => {
    const cur = document.documentElement.getAttribute('data-theme');
    const next = cur === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', next);
    localStorage.setItem('pipibot_theme', next);
    sheetBackdrop.classList.remove('show');
  };
  document.getElementById('btn-disconnect').onclick = () => {
    localStorage.removeItem(STORAGE_KEY);
    location.href = '/login';
  };

  let accountDevices = [];
  let accountAccessToken = localStorage.getItem('pipibot_access_token') || '';
  let refreshTimer = null;

  function renderDeviceStrip(activeHostId) {
    // 1. Mobile compact strip
    const strip = document.getElementById('device-strip');
    if (strip && accountDevices.length) {
      strip.style.display = 'flex';
      strip.innerHTML = accountDevices.map((d) => {
        const isAct = d.hostId === activeHostId;
        const dot = d.isOnline ? '🟢 ' : '⚪ ';
        return '<button class="bot-chip ' + (isAct ? 'active' : '') + '" data-host="' + esc(d.hostId) + '" type="button">' + dot + esc(d.name) + '</button>';
      }).join('') + '<a class="bot-chip" href="/devices" style="text-decoration:none">+ 纳管设备</a>';
      strip.querySelectorAll('button[data-host]').forEach((btn) => {
        btn.onclick = () => {
          const target = accountDevices.find((d) => d.hostId === btn.dataset.host);
          if (target) connectToTargetDevice(target.hostId, target.hostPubKey || '', '', accountAccessToken, '');
        };
      });
    }

    // 2. Desktop collapsible node switcher (Primary Control Node pinned first!)
    const activeDev = accountDevices.find((d) => d.hostId === activeHostId);
    const activeNameEl = document.getElementById('sidebar-active-node-name');
    const activeRoleEl = document.getElementById('sidebar-active-node-role');
    const activeDotEl = document.getElementById('sidebar-active-node-dot');
    if (activeNameEl && activeDev) activeNameEl.textContent = activeDev.name;
    if (activeRoleEl && activeDev) activeRoleEl.textContent = activeDev.platform === 'macos' ? '主控' : (activeDev.platform || 'node');
    if (activeDotEl && activeDev) activeDotEl.className = 'dot ' + (activeDev.isOnline ? 'ok' : '');

    const listEl = document.getElementById('sidebar-node-list');
    if (listEl) {
      const sorted = accountDevices.slice().sort((a, b) => {
        const aScore = (a.platform === 'macos' ? 4 : 0) + (a.isOnline ? 2 : 0);
        const bScore = (b.platform === 'macos' ? 4 : 0) + (b.isOnline ? 2 : 0);
        return bScore - aScore;
      });
      listEl.innerHTML = sorted.map((d) => {
        const isAct = d.hostId === activeHostId;
        const isPrimary = d.platform === 'macos';
        const caps = (d.capabilities || []).slice(0, 3).join(' · ') || d.platform;
        return '<button class="node-item ' + (isAct ? 'active' : '') + '" data-snode="' + esc(d.hostId) + '" type="button" style="padding:6px 8px;">' +
          '<span class="dot ' + (d.isOnline ? 'ok' : '') + '" style="flex-shrink:0;"></span>' +
          '<div style="min-width:0;flex:1;">' +
            '<div style="font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">' + esc(d.name) + '</div>' +
            '<div class="node-meta">' + esc(caps) + '</div>' +
          '</div>' +
          '<span class="node-pill">' + (isPrimary ? '主控' : (d.platform || 'node')) + '</span>' +
        '</button>';
      }).join('') || '<div style="font-size:12px;color:var(--ink-3);padding:8px 10px;">暂无已纳管设备</div>';
      listEl.querySelectorAll('[data-snode]').forEach((btn) => {
        btn.onclick = () => {
          const dd = document.getElementById('sidebar-node-dropdown');
          if (dd) dd.open = false;
          const target = accountDevices.find((d) => d.hostId === btn.dataset.snode);
          if (target) connectToTargetDevice(target.hostId, target.hostPubKey || '', '', accountAccessToken, '');
        };
      });
    }
  }

  async function connectToTargetDevice(hostId, hostPubKey, lanHint, deviceToken, oneTimeToken) {
    if (refreshTimer) { clearInterval(refreshTimer); refreshTimer = null; }
    if (state.transport && state.transport.ws) {
      try { state.transport.ws.close(); } catch {}
    }
    if (hostId && hostPubKey) {
      saveSession({ hostId, hostPubKey, lanHint, deviceToken });
    }
    renderDeviceStrip(hostId);
    const transport = new E2EERelayTransport({ hostId, hostPubKey, lanHint, deviceToken, oneTimeToken });
    transport.onStatus = setStatus;
    state.transport = transport;
    render();
    try {
      await transport.connect();
      await refreshSnapshot();
      refreshTimer = setInterval(refreshSnapshot, 5000);
    } catch (e) {
      setStatus('err', e.message || '连接失败');
    }
  }

  async function boot() {
    const link = parseCurrentLink();
    const saved = loadSavedSession(link.pathHostId);

    // Load unified account session & all enrolled devices so one WebUI operates every machine
    if (IS_RELAY_MODE) {
      try {
        const meRes = await fetch('/api/auth/me', {
          headers: accountAccessToken ? { Authorization: 'Bearer ' + accountAccessToken } : {}
        });
        if (meRes.ok) {
          const me = await meRes.json();
          if (me.accessToken) {
            accountAccessToken = me.accessToken;
            localStorage.setItem('pipibot_access_token', me.accessToken);
          }
          if (me.user) {
            const emailEl = document.getElementById('sidebar-user-email');
            if (emailEl) emailEl.textContent = me.user.email || me.user.displayName || '已登录';
          }
          accountDevices = Array.isArray(me.devices) ? me.devices : [];
        }
      } catch {}
    }

    const matchedDev = accountDevices.find((d) => d.hostId === link.pathHostId)
      || accountDevices.find((d) => d.isOnline && d.platform === 'macos')
      || accountDevices.find((d) => d.isOnline)
      || accountDevices[0];

    const hostId = link.pathHostId || matchedDev?.hostId || saved?.hostId || '';
    const hostPubKey = link.hostPubKey || matchedDev?.hostPubKey || saved?.hostPubKey || '';
    const lanHint = link.lanHint || saved?.lanHint || '';
    const deviceToken = saved?.deviceToken || accountAccessToken || '';

    if (IS_RELAY_MODE && (!hostId || !hostPubKey)) {
      setStatus('warn', '请先登录');
      location.href = '/login';
      return;
    }

    await connectToTargetDevice(hostId, hostPubKey, lanHint, deviceToken, link.oneTimeToken);
  }

  boot();
})();
</script>
</body>
</html>`;
}
