/**
 * PiPiBot — Clean-room MIT implementation.
 * Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
 *
 * @pipibot/relay - landing-page.ts
 * Brand website (`https://pipibot.jimizhou.com`):
 *   - `/`         Apple-style sticky scroll-driven showcase with real macOS screenshots
 *   - `/features` Clean C-end feature walkthrough with scroll-reveal animations
 *   - `/download` Simple Mac, Mobile, and Linux download page
 *
 * Design principles:
 * - Scroll-driven product storytelling: pinned full-viewport stage smoothly scales and
 *   crossfades through 4 real SwiftUI macOS screenshots as the user scrolls.
 * - Ultra-clean C-end copy: short, plain, human language, zero technical jargon.
 * - Exact desktop AppIcon (`/assets/app-icon.png`) enlarged and centered in the Hero.
 * - Comfortable mobile margins and fluid 60fps GPU-composited animations (`transform`/`opacity`).
 */

export type BrandPageId = 'home' | 'features' | 'download';

const GITHUB_REPO_URL = 'https://github.com/JimiZhou/pipibot';
const GITHUB_RELEASES_URL = 'https://github.com/JimiZhou/pipibot/releases';
const ASSET_VER = 'v=6';

function renderBrandLayout(page: BrandPageId, title: string, description: string, bodyHtml: string): string {
  const navClass = (id: BrandPageId) => (page === id ? 'nav-link active' : 'nav-link');

  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover" />
  <meta name="theme-color" media="(prefers-color-scheme: light)" content="#FDFCF9" />
  <meta name="theme-color" media="(prefers-color-scheme: dark)" content="#08090B" />
  <meta name="description" content="${description}" />
  <title>${title}</title>
  <link rel="icon" type="image/png" href="/assets/app-icon.png?${ASSET_VER}" />
  <link rel="apple-touch-icon" href="/apple-touch-icon.png?${ASSET_VER}" />
  <style>
    :root {
      --bg: #FDFCF9;
      --bg-soft: #F4F3EE;
      --surface: #FFFFFF;
      --surface-hover: #F5F4F0;
      --border: rgba(23, 22, 20, 0.08);
      --border-strong: rgba(23, 22, 20, 0.14);
      --text: #171614;
      --text-2: #63605A;
      --text-3: #959088;
      --accent: #0A84FF;
      --btn-bg: #171614;
      --btn-fg: #FFFFFF;
      --glass: rgba(253, 252, 249, 0.80);
      --halo: radial-gradient(circle, rgba(10, 132, 255, 0.14) 0%, rgba(10, 132, 255, 0) 68%);
      --icon-shadow: 0 26px 54px -14px rgba(18, 30, 58, 0.30), 0 8px 18px -6px rgba(18, 30, 58, 0.14);
      --shot-shadow: 0 34px 80px -24px rgba(16, 20, 30, 0.24), 0 6px 18px -6px rgba(16, 20, 30, 0.08);
      --ease-out: cubic-bezier(0.22, 1, 0.36, 1);
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #08090B;
        --bg-soft: #111318;
        --surface: #13161C;
        --surface-hover: #1A1E26;
        --border: rgba(255, 255, 255, 0.09);
        --border-strong: rgba(255, 255, 255, 0.16);
        --text: #F5F5F7;
        --text-2: #A1A1AA;
        --text-3: #71717A;
        --accent: #4DA3FF;
        --btn-bg: #F5F5F7;
        --btn-fg: #08090B;
        --glass: rgba(8, 9, 11, 0.80);
        --halo: radial-gradient(circle, rgba(77, 163, 255, 0.18) 0%, rgba(77, 163, 255, 0) 68%);
        --icon-shadow: 0 28px 60px -12px rgba(0, 0, 0, 0.78), 0 0 0 1px rgba(255, 255, 255, 0.12);
        --shot-shadow: 0 40px 92px -22px rgba(0, 0, 0, 0.82), 0 0 0 1px rgba(255, 255, 255, 0.09);
      }
    }

    * { box-sizing: border-box; }
    html { scroll-behavior: smooth; overflow-x: clip; }
    body {
      margin: 0;
      overflow-x: clip;
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif;
      -webkit-font-smoothing: antialiased;
      text-rendering: optimizeLegibility;
      line-height: 1.5;
    }
    a { color: inherit; text-decoration: none; }
    button { font-family: inherit; }
    img { display: block; max-width: 100%; }

    /* Minimal Sticky Top Bar */
    .topbar {
      position: sticky;
      top: 0;
      z-index: 50;
      background: var(--glass);
      backdrop-filter: saturate(180%) blur(20px);
      -webkit-backdrop-filter: saturate(180%) blur(20px);
      border-bottom: 1px solid var(--border);
    }
    .topbar-inner {
      max-width: 1040px;
      margin: 0 auto;
      padding: 0 24px;
      height: 52px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
    }
    .brand {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      font-size: 15px;
      font-weight: 600;
      letter-spacing: -0.02em;
      white-space: nowrap;
    }
    .brand img {
      width: 24px;
      height: 24px;
      border-radius: 6px;
      box-shadow: 0 1px 4px rgba(0, 0, 0, 0.15);
    }
    .nav {
      display: flex;
      align-items: center;
      gap: 26px;
    }
    .nav-link {
      font-size: 13px;
      color: var(--text-2);
      transition: color 0.16s ease;
      white-space: nowrap;
    }
    .nav-link:hover, .nav-link.active { color: var(--text); font-weight: 550; }
    .topbar-actions {
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .nav-ghost {
      font-size: 12.5px;
      color: var(--text-2);
      padding: 0 8px;
      transition: color 0.16s ease;
      white-space: nowrap;
    }
    .nav-ghost:hover { color: var(--text); }
    .nav-pill {
      display: inline-flex;
      align-items: center;
      height: 30px;
      padding: 0 13px;
      border-radius: 999px;
      font-size: 12.5px;
      font-weight: 500;
      background: var(--btn-bg);
      color: var(--btn-fg);
      transition: transform 0.16s var(--ease-out), opacity 0.16s ease;
      white-space: nowrap;
    }
    .nav-pill:hover { opacity: 0.88; }
    .nav-pill:active { transform: scale(0.95); }

    .container {
      max-width: 1040px;
      margin: 0 auto;
      padding: 0 28px;
    }

    /* Full-Screen Opening Hero */
    .hero-screen {
      min-height: calc(100svh - 52px);
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      text-align: center;
      padding: 44px 24px 32px;
      position: relative;
    }
    .hero-logo-stage {
      position: relative;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      margin-bottom: 28px;
    }
    .hero-logo-stage::before {
      content: "";
      position: absolute;
      width: 240px;
      height: 240px;
      background: var(--halo);
      pointer-events: none;
      z-index: 0;
    }
    .hero-icon {
      position: relative;
      z-index: 1;
      width: 124px;
      height: 124px;
      border-radius: 28px;
      box-shadow: var(--icon-shadow);
      will-change: transform, opacity;
      transition: transform 0.5s var(--ease-out);
    }
    .hero-icon:hover { transform: scale(1.035) translateY(-2px); }
    h1 {
      margin: 0;
      font-size: clamp(38px, 6.2vw, 66px);
      line-height: 1.06;
      letter-spacing: -0.045em;
      font-weight: 680;
    }
    .hero-sub {
      margin: 14px auto 0;
      max-width: 420px;
      font-size: clamp(18px, 2.4vw, 23px);
      line-height: 1.45;
      color: var(--text-2);
      font-weight: 400;
      letter-spacing: -0.015em;
    }
    .cta-row {
      margin-top: 32px;
      display: flex;
      justify-content: center;
      align-items: center;
      flex-wrap: wrap;
      gap: 12px;
    }
    .btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 7px;
      height: 46px;
      padding: 0 24px;
      border-radius: 999px;
      font-size: 15px;
      font-weight: 550;
      letter-spacing: -0.01em;
      border: 1px solid transparent;
      cursor: pointer;
      transition: transform 0.16s var(--ease-out), opacity 0.16s ease, background 0.16s ease;
    }
    .btn:active { transform: scale(0.96); }
    .btn-primary { background: var(--btn-bg); color: var(--btn-fg); }
    .btn-primary:hover { opacity: 0.88; }
    .btn-secondary {
      background: var(--surface);
      color: var(--text);
      border-color: var(--border-strong);
    }
    .btn-secondary:hover { background: var(--surface-hover); }

    .scroll-cue {
      position: absolute;
      bottom: 24px;
      left: 50%;
      transform: translateX(-50%);
      display: inline-flex;
      flex-direction: column;
      align-items: center;
      gap: 6px;
      font-size: 12px;
      color: var(--text-3);
      letter-spacing: 0.02em;
      opacity: 0.85;
      transition: opacity 0.3s ease;
    }
    .scroll-cue svg {
      animation: floatCue 2.2s ease-in-out infinite;
    }
    @keyframes floatCue {
      0%, 100% { transform: translateY(0); }
      50% { transform: translateY(5px); }
    }

    /* Apple-Style Sticky Scroll-Driven Showcase */
    .story-track {
      position: relative;
      height: 360vh;
    }
    .story-sticky {
      position: sticky;
      top: 52px;
      height: calc(100svh - 52px);
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 24px 28px 34px;
      overflow: hidden;
    }
    .story-caption-stage {
      position: relative;
      width: 100%;
      max-width: 680px;
      height: 82px;
      margin-bottom: 22px;
      text-align: center;
    }
    .story-caption {
      position: absolute;
      inset: 0;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 6px;
      opacity: 0;
      transform: translateY(18px);
      transition: opacity 0.45s var(--ease-out), transform 0.55s var(--ease-out);
      pointer-events: none;
    }
    .story-caption.active {
      opacity: 1;
      transform: translateY(0);
      pointer-events: auto;
    }
    .story-caption.past {
      opacity: 0;
      transform: translateY(-18px);
    }
    .story-caption h2 {
      margin: 0;
      font-size: clamp(24px, 3.6vw, 38px);
      line-height: 1.15;
      letter-spacing: -0.035em;
      font-weight: 650;
    }
    .story-caption p {
      margin: 0;
      font-size: clamp(14.5px, 1.8vw, 17px);
      color: var(--text-2);
    }

    .story-screen-wrap {
      position: relative;
      width: 100%;
      max-width: 900px;
      aspect-ratio: 16 / 10;
      max-height: 58svh;
      will-change: transform, opacity;
    }
    .story-frame {
      position: relative;
      width: 100%;
      height: 100%;
      border-radius: 18px;
      overflow: hidden;
      background: var(--surface);
      border: 1px solid var(--border);
      box-shadow: var(--shot-shadow);
    }
    .story-shot {
      position: absolute;
      inset: 0;
      width: 100%;
      height: 100%;
      object-fit: cover;
      object-position: top center;
      opacity: 0;
      transform: scale(1.035);
      transition: opacity 0.6s var(--ease-out), transform 0.75s var(--ease-out);
      will-change: opacity, transform;
    }
    .story-shot.active {
      opacity: 1;
      transform: scale(1);
    }

    /* Progress Bar + Chapter Dots */
    .story-hud {
      margin-top: 24px;
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .story-pill {
      position: relative;
      width: 34px;
      height: 5px;
      border-radius: 999px;
      border: 0;
      padding: 0;
      background: var(--border-strong);
      overflow: hidden;
      cursor: pointer;
      transition: width 0.35s var(--ease-out), background 0.2s ease;
    }
    .story-pill.active {
      width: 58px;
    }
    .story-pill-fill {
      position: absolute;
      inset: 0;
      width: 0%;
      border-radius: inherit;
      background: var(--text);
      transition: width 0.12s linear;
    }
    .story-pill.done .story-pill-fill { width: 100%; }

    /* Clean Scroll-Reveal Sections */
    .reveal {
      opacity: 0;
      transform: translateY(28px);
      transition: opacity 0.75s var(--ease-out), transform 0.85s var(--ease-out);
      will-change: opacity, transform;
    }
    .reveal.in {
      opacity: 1;
      transform: translateY(0);
    }

    .values-section {
      padding: 96px 0 64px;
      border-top: 1px solid var(--border);
    }
    .values-grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 24px;
    }
    .value-item {
      padding: 28px 26px;
      border-radius: 20px;
      background: var(--surface);
      border: 1px solid var(--border);
    }
    .value-item h3 {
      margin: 0;
      font-size: 19px;
      font-weight: 650;
      letter-spacing: -0.025em;
    }
    .value-item p {
      margin: 8px 0 0;
      font-size: 15px;
      color: var(--text-2);
      line-height: 1.6;
    }

    /* Closing CTA */
    .closing {
      padding: 72px 24px 104px;
      text-align: center;
    }
    .closing h2 {
      margin: 0;
      font-size: clamp(28px, 4.2vw, 44px);
      letter-spacing: -0.035em;
      font-weight: 680;
    }
    .closing p {
      margin: 10px auto 0;
      font-size: 16px;
      color: var(--text-2);
    }

    /* Subpages (/features & /download) */
    .page-head {
      padding: 72px 0 44px;
      text-align: center;
    }
    .page-head h1 {
      font-size: clamp(32px, 4.6vw, 48px);
    }
    .page-head p {
      margin: 12px auto 0;
      max-width: 400px;
      font-size: 17px;
      color: var(--text-2);
    }
    .feature-list {
      display: flex;
      flex-direction: column;
      gap: 72px;
      padding-bottom: 96px;
    }
    .feature-block {
      display: grid;
      grid-template-columns: 1.35fr 0.85fr;
      gap: 44px;
      align-items: center;
    }
    .feature-block.flip { grid-template-columns: 0.85fr 1.35fr; }
    .feature-block.flip .feature-shot { order: 2; }
    .feature-shot {
      border-radius: 16px;
      overflow: hidden;
      border: 1px solid var(--border);
      box-shadow: var(--shot-shadow);
      background: var(--surface);
      aspect-ratio: 16 / 10;
    }
    .feature-shot img { width: 100%; height: 100%; object-fit: cover; object-position: top center; }
    .feature-text h2 {
      margin: 0;
      font-size: clamp(24px, 3vw, 32px);
      letter-spacing: -0.03em;
      font-weight: 650;
      line-height: 1.18;
    }
    .feature-text p {
      margin: 12px 0 0;
      font-size: 16px;
      color: var(--text-2);
      line-height: 1.6;
    }

    .dl-grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 20px;
      padding-bottom: 96px;
    }
    .dl-card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 22px;
      padding: 30px 26px;
      display: flex;
      flex-direction: column;
      gap: 12px;
    }
    .dl-card h2 {
      margin: 0;
      font-size: 22px;
      font-weight: 650;
      letter-spacing: -0.025em;
    }
    .dl-card p {
      margin: 0;
      font-size: 15px;
      color: var(--text-2);
      line-height: 1.6;
      flex: 1;
    }
    .dl-card .btn { margin-top: 8px; }
    .code-line {
      margin-top: 8px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      padding: 10px 12px;
      border-radius: 12px;
      background: var(--bg-soft);
      border: 1px solid var(--border);
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 12px;
      overflow-x: auto;
    }
    .copy-btn {
      flex-shrink: 0;
      border: 1px solid var(--border-strong);
      background: var(--surface);
      color: var(--text);
      border-radius: 999px;
      padding: 4px 11px;
      font-size: 12px;
      cursor: pointer;
    }

    /* Footer */
    footer {
      border-top: 1px solid var(--border);
      padding: 28px 0 40px;
      font-size: 12.5px;
      color: var(--text-3);
    }
    .footer-inner {
      display: flex;
      align-items: center;
      justify-content: space-between;
      flex-wrap: wrap;
      gap: 14px;
    }
    .footer-links {
      display: flex;
      align-items: center;
      gap: 20px;
    }
    .footer-links a:hover { color: var(--text); }

    /* Mobile: Spacious Margins + Smooth Vertical Scroll Reveal */
    @media (max-width: 860px) {
      .topbar-inner { padding: 0 20px; }
      .nav { gap: 16px; }
      .nav-ghost { display: none; }
      .container { padding: 0 24px; }

      .hero-screen { padding: 36px 24px 28px; }
      .hero-icon { width: 104px; height: 104px; border-radius: 24px; }
      .hero-sub { font-size: 17px; max-width: 280px; }
      .cta-row { margin-top: 26px; gap: 10px; }
      .btn { height: 44px; padding: 0 20px; font-size: 14.5px; }

      .story-track { height: 320svh; }
      .story-sticky { padding: 20px 22px 28px; }
      .story-caption-stage { height: 76px; margin-bottom: 18px; }
      .story-caption h2 { font-size: 24px; }
      .story-caption p { font-size: 14.5px; max-width: 300px; }
      .story-screen-wrap { max-height: 46svh; }
      .story-frame { border-radius: 14px; }
      .story-hud { margin-top: 22px; }
      .story-pill { width: 26px; }
      .story-pill.active { width: 46px; }

      .values-section { padding: 64px 0 44px; }
      .values-grid { grid-template-columns: 1fr; gap: 14px; }
      .value-item { padding: 22px 22px; }

      .closing { padding: 56px 24px 76px; }

      .page-head { padding: 48px 0 32px; }
      .feature-list { gap: 48px; padding-bottom: 64px; }
      .feature-block,
      .feature-block.flip { grid-template-columns: 1fr; gap: 20px; }
      .feature-block.flip .feature-shot { order: 0; }
      .feature-text { text-align: center; padding: 0 6px; }

      .dl-grid { grid-template-columns: 1fr; gap: 16px; padding-bottom: 64px; }
      .footer-inner { justify-content: center; text-align: center; }
    }

    @media (prefers-reduced-motion: reduce) {
      .story-track { height: auto; }
      .story-sticky { position: static; height: auto; gap: 24px; padding: 40px 24px; }
      .story-caption-stage { height: auto; }
      .story-caption { position: static; opacity: 1; transform: none; margin-bottom: 12px; }
      .story-screen-wrap { max-height: none; }
      .story-shot { position: static; opacity: 1; transform: none; margin-bottom: 16px; }
      .story-hud, .scroll-cue { display: none; }
      .reveal { opacity: 1; transform: none; }
      *, *::before, *::after { transition: none !important; animation: none !important; }
    }
  </style>
</head>
<body>
  <header class="topbar">
    <div class="topbar-inner">
      <a class="brand" href="/">
        <img src="/assets/app-icon.png?${ASSET_VER}" alt="PiPiBot" width="24" height="24" />
        <span>PiPiBot</span>
      </a>
      <nav class="nav" aria-label="主导航">
        <a class="${navClass('home')}" href="/">概览</a>
        <a class="${navClass('features')}" href="/features">功能</a>
        <a class="${navClass('download')}" href="/download">下载</a>
      </nav>
      <div class="topbar-actions">
        <a class="nav-ghost" href="${GITHUB_REPO_URL}" target="_blank" rel="noopener">GitHub</a>
        <a class="nav-pill" href="/pair">手机端</a>
      </div>
    </div>
  </header>

  <main>
    ${bodyHtml}
  </main>

  <footer>
    <div class="container footer-inner">
      <span>PiPiBot</span>
      <div class="footer-links">
        <a href="/">概览</a>
        <a href="/features">功能</a>
        <a href="/download">下载</a>
        <a href="/pair">手机端</a>
        <a href="${GITHUB_REPO_URL}" target="_blank" rel="noopener">GitHub</a>
      </div>
    </div>
  </footer>

  <script>
    (function () {
      var prefersReduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

      // 1. Apple-style Sticky Scroll-Driven Showcase
      var heroEl = document.querySelector('.hero-screen');
      var track = document.getElementById('story-track');
      var screenWrap = document.getElementById('story-screen');
      var scrollCue = document.getElementById('scroll-cue');
      if (track && screenWrap && !prefersReduced) {
        var captions = Array.prototype.slice.call(track.querySelectorAll('.story-caption'));
        var shots = Array.prototype.slice.call(track.querySelectorAll('.story-shot'));
        var pills = Array.prototype.slice.call(track.querySelectorAll('.story-pill'));
        var fills = pills.map(function (p) { return p.querySelector('.story-pill-fill'); });
        var total = shots.length;
        var ticking = false;
        var navOffset = 52;

        function clamp(v, min, max) { return Math.max(min, Math.min(max, v)); }

        function renderScroll() {
          ticking = false;
          var vh = window.innerHeight || 800;
          var rect = track.getBoundingClientRect();
          var scrollable = Math.max(1, track.offsetHeight - vh + navOffset);
          var raw = (navOffset - rect.top) / scrollable;
          var progress = clamp(raw, 0, 1);

          if (heroEl) {
            var heroOut = clamp(window.scrollY / (vh * 0.72), 0, 1);
            heroEl.style.opacity = (1 - heroOut * 0.85).toFixed(3);
            heroEl.style.transform = 'translate3d(0,' + (-heroOut * 22).toFixed(1) + 'px,0) scale(' + (1 - heroOut * 0.04).toFixed(4) + ')';
          }
          if (scrollCue) {
            scrollCue.style.opacity = window.scrollY > 36 ? '0' : '0.85';
          }

          // Smooth entry lift & zoom as the showcase glides into view
          var enterP = clamp((vh - rect.top) / (vh * 0.82), 0, 1);
          var scale = 0.90 + 0.10 * enterP;
          var liftY = (1 - enterP) * 32;
          screenWrap.style.transform = 'translate3d(0,' + liftY.toFixed(1) + 'px,0) scale(' + scale.toFixed(4) + ')';
          screenWrap.style.opacity = (0.28 + 0.72 * enterP).toFixed(3);

          var scaled = progress * total;
          var activeIdx = Math.min(total - 1, Math.floor(scaled));
          var segProgress = clamp(scaled - activeIdx, 0, 1);

          for (var i = 0; i < total; i++) {
            captions[i].classList.toggle('active', i === activeIdx);
            captions[i].classList.toggle('past', i < activeIdx);
            shots[i].classList.toggle('active', i === activeIdx);
            pills[i].classList.toggle('active', i === activeIdx);
            pills[i].classList.toggle('done', i < activeIdx);
            if (fills[i]) {
              var w = i < activeIdx ? 100 : (i === activeIdx ? Math.max(12, Math.round(segProgress * 100)) : 0);
              fills[i].style.width = w + '%';
            }
          }
        }

        function onScroll() {
          if (!ticking) {
            ticking = true;
            requestAnimationFrame(renderScroll);
          }
        }

        pills.forEach(function (pill, idx) {
          pill.addEventListener('click', function () {
            var vh = window.innerHeight || 800;
            var scrollable = Math.max(1, track.offsetHeight - vh + navOffset);
            var targetY = track.offsetTop - navOffset + ((idx + 0.15) / total) * scrollable;
            window.scrollTo({ top: Math.max(0, targetY), behavior: 'smooth' });
          });
        });

        window.addEventListener('scroll', onScroll, { passive: true });
        window.addEventListener('resize', onScroll, { passive: true });
        renderScroll();
      }

      // 2. Smooth Scroll-Reveal for lower sections & subpages
      var reveals = Array.prototype.slice.call(document.querySelectorAll('.reveal'));
      if (reveals.length && !prefersReduced && 'IntersectionObserver' in window) {
        var io = new IntersectionObserver(function (entries) {
          entries.forEach(function (e) {
            if (e.isIntersecting) {
              e.target.classList.add('in');
              io.unobserve(e.target);
            }
          });
        }, { threshold: 0.14, rootMargin: '0px 0px -40px 0px' });
        reveals.forEach(function (el) { io.observe(el); });
      } else {
        reveals.forEach(function (el) { el.classList.add('in'); });
      }

      // 3. Copy button on /download
      document.querySelectorAll('[data-copy]').forEach(function (btn) {
        btn.addEventListener('click', function () {
          var text = btn.getAttribute('data-copy') || '';
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(function () {
              var old = btn.textContent;
              btn.textContent = '已复制';
              setTimeout(function () { btn.textContent = old; }, 1500);
            });
          }
        });
      });
    })();
  </script>
</body>
</html>`;
}

export function renderBrandLandingHTML(): string {
  const body = `
    <section class="hero-screen">
      <div class="hero-logo-stage">
        <img class="hero-icon" src="/assets/app-icon.png?${ASSET_VER}" alt="PiPiBot" width="124" height="124" />
      </div>
      <h1>PiPiBot</h1>
      <p class="hero-sub">你的私人 AI 助手团队。</p>
      <div class="cta-row">
        <a class="btn btn-primary" href="/download">下载 Mac 版</a>
        <a class="btn btn-secondary" href="${GITHUB_REPO_URL}" target="_blank" rel="noopener">GitHub</a>
      </div>
      <a class="scroll-cue" id="scroll-cue" href="#story-track" aria-label="向下滑动了解产品">
        <span>向下滑动</span>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg>
      </a>
    </section>

    <section class="story-track" id="story-track" aria-label="产品界面展示">
      <div class="story-sticky">
        <div class="story-caption-stage">
          <div class="story-caption active">
            <h2>多位助手，各有所长</h2>
            <p>写代码、查资料、理日程，点一下就开工。</p>
          </div>
          <div class="story-caption">
            <h2>拉个群，一起干活</h2>
            <p>一句话说清目标，助手们自己分工配合。</p>
          </div>
          <div class="story-caption">
            <h2>任务一目了然，手机随时接续</h2>
            <p>所有进度集中呈现，扫码就能在手机上同步查看与确认。</p>
          </div>
          <div class="story-caption">
            <h2>日夜皆宜，安静陪伴</h2>
            <p>住在你的 Mac 里，随时待命，从不打扰。</p>
          </div>
        </div>

        <div class="story-screen-wrap" id="story-screen">
          <div class="story-frame">
            <img class="story-shot active" src="/assets/mac-workspace.png?${ASSET_VER}" alt="PiPiBot Mac 工作台" width="1800" height="1125" />
            <img class="story-shot" src="/assets/mac-group.png?${ASSET_VER}" alt="PiPiBot 多助手群聊" width="1800" height="1125" />
            <img class="story-shot" src="/assets/mac-mission.png?${ASSET_VER}" alt="PiPiBot 任务台与手机扫码" width="1800" height="1125" />
            <img class="story-shot" src="/assets/mac-workspace-dark.png?${ASSET_VER}" alt="PiPiBot 深色外观" width="1800" height="1125" />
          </div>
        </div>

        <div class="story-hud" role="tablist" aria-label="切换产品画面">
          <button class="story-pill active" type="button" aria-label="工作台"><span class="story-pill-fill"></span></button>
          <button class="story-pill" type="button" aria-label="多助手群聊"><span class="story-pill-fill"></span></button>
          <button class="story-pill" type="button" aria-label="手机远程管理"><span class="story-pill-fill"></span></button>
          <button class="story-pill" type="button" aria-label="深色外观"><span class="story-pill-fill"></span></button>
        </div>
      </div>
    </section>

    <section class="values-section">
      <div class="container">
        <div class="values-grid">
          <div class="value-item reveal">
            <h3>就在你电脑里</h3>
            <p>对话和文件只留在自己设备上，不经过第三方云端。</p>
          </div>
          <div class="value-item reveal" style="transition-delay: 80ms">
            <h3>手机扫码就用</h3>
            <p>不用安装额外应用，手机浏览器扫码直接连上电脑。</p>
          </div>
          <div class="value-item reveal" style="transition-delay: 160ms">
            <h3>完全免费开源</h3>
            <p>全部代码托管在 GitHub，透明可靠，自由使用。</p>
          </div>
        </div>
      </div>
    </section>

    <section class="closing reveal">
      <h2>现在就开始。</h2>
      <p>支持 macOS 与手机浏览器。</p>
      <div class="cta-row">
        <a class="btn btn-primary" href="/download">下载 Mac 版</a>
        <a class="btn btn-secondary" href="/pair">手机扫码连接</a>
      </div>
    </section>
  `;

  return renderBrandLayout(
    'home',
    'PiPiBot — 你的私人 AI 助手团队',
    'PiPiBot 是装在你自己电脑里的开源 AI 助手团队，手机扫码随时使用。',
    body
  );
}

export function renderBrandFeaturesHTML(): string {
  const body = `
    <section class="page-head">
      <div class="container">
        <h1>简单好用，一用就会。</h1>
        <p>把琐事交给助手，你只做决定。</p>
      </div>
    </section>

    <section class="container">
      <div class="feature-list">
        <article class="feature-block reveal">
          <div class="feature-shot">
            <img src="/assets/mac-workspace.png?${ASSET_VER}" alt="多位助手工作台" width="1800" height="1125" />
          </div>
          <div class="feature-text">
            <h2>多位助手，各有所长</h2>
            <p>全能助理、编程搭档、写作助手、任务管家随时待命，点一下就能开始新任务。</p>
          </div>
        </article>

        <article class="feature-block flip reveal">
          <div class="feature-shot">
            <img src="/assets/mac-group.png?${ASSET_VER}" alt="多助手群聊" width="1800" height="1125" loading="lazy" />
          </div>
          <div class="feature-text">
            <h2>拉个群，一起把事办完</h2>
            <p>像和同事建群一样，把几位助手拉在一起。交代好目标，大家按分工汇报结果。</p>
          </div>
        </article>

        <article class="feature-block reveal">
          <div class="feature-shot">
            <img src="/assets/mac-mission.png?${ASSET_VER}" alt="任务台与手机配对" width="1800" height="1125" loading="lazy" />
          </div>
          <div class="feature-text">
            <h2>电脑与手机，随时接续</h2>
            <p>所有任务进度集中展示，手机扫码即可加密连接，重要改动确认后再执行。</p>
          </div>
        </article>
      </div>
    </section>
  `;

  return renderBrandLayout(
    'features',
    '功能 — PiPiBot',
    '了解 PiPiBot 的工作台、多助手群聊与手机扫码远程管理。',
    body
  );
}

export function renderBrandDownloadHTML(): string {
  const linuxCmd = 'npm i -g @pipibot/daemon && pipibot-daemon start';
  const body = `
    <section class="page-head">
      <div class="container">
        <h1>下载 PiPiBot。</h1>
        <p>免费开源，几分钟即可上手。</p>
      </div>
    </section>

    <section class="container">
      <div class="dl-grid">
        <article class="dl-card reveal">
          <h2>Mac 版</h2>
          <p>专为 macOS 打造的原生桌面应用，打开就能用。</p>
          <a class="btn btn-primary" href="${GITHUB_RELEASES_URL}" target="_blank" rel="noopener">前往下载</a>
        </article>

        <article class="dl-card reveal" style="transition-delay: 80ms">
          <h2>手机端</h2>
          <p>无需下载 App。用手机扫一扫电脑二维码，随时随地继续对话。</p>
          <a class="btn btn-secondary" href="/pair">打开手机端</a>
        </article>

        <article class="dl-card reveal" style="transition-delay: 160ms">
          <h2>Linux 主机</h2>
          <p>适合放在服务器或闲置电脑上 24 小时运行。</p>
          <div class="code-line">
            <span>${linuxCmd}</span>
            <button class="copy-btn" type="button" data-copy="${linuxCmd}">复制</button>
          </div>
        </article>
      </div>
    </section>
  `;

  return renderBrandLayout(
    'download',
    '下载 — PiPiBot',
    '下载 PiPiBot Mac 版、打开手机端或部署 Linux 主机。',
    body
  );
}
