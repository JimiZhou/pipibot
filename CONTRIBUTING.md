# Contributing to PipiBot

Thank you for your interest in building **PipiBot** — an open-source, local-first, cross-device AI Manager built on the **Pi Core Harness**, **Universal Multi-Harness BYOK Routing**, a **120Hz Procedural SVG Avatar**, **4-Tier Self-Evolving Memory**, and **$0/month Cloudflare Free-Tier Edge Infrastructure**.

Whether you are adding a harness adapter, extending the 53-state procedural avatar, refining memory salience scoring, or implementing iOS / macOS / IoT nodes, this guide explains how the repository is organized and how to contribute cleanly.

---

## 1. Engineering Principles

1. **Outcomes Over Tasks**: Every runtime feature should serve continuous responsibility loops (Goal + Constraints + Success Metrics + Evidence) and clean human escalation ("Needs You"), not one-shot chat spam.
2. **Local-First Privacy**: Raw source code, local CLI credentials (`~/.claude`, `~/.codex`, etc.), and SQLite memory databases stay on the user's primary resident machine (`macOS` in V1). Cloud sync carries only authenticated tunnel traffic, encrypted state summaries, or TTL-bounded artifacts.
3. **$0/Month Cloud Ceiling**: Edge components in [`packages/cloudflare-edge/`](packages/cloudflare-edge/wrangler.toml) must strictly respect Cloudflare Free Tier quotas (Workers 100k req/day, D1 5GB, R2 10GB with zero egress, KV 100k reads/day, Access <= 50 users).
4. **Zero-Bloat Runtime**: Keep core protocol zero-dependency, core Node packages minimal (`node:*` built-ins + `@pipibot/protocol` where feasible), and the Design System workbench 100% build-free (`python3 -m http.server`).
5. **Honest Documentation & Verification**: Never mark tasks complete or publish benchmarks without reproducible commands and observed outputs.

---

## 2. Repository Layout

```text
pipibot/
├── README.md                                  # English flagship overview
├── README.zh-CN.md                            # 简体中文总览
├── CONTRIBUTING.md                            # This guide
├── LICENSE                                    # MIT License
├── package.json                               # Root npm workspace manifest
├── tsconfig.base.json                         # Shared TypeScript strict compiler options
├── design-system/                             # Zero-build interactive UI/UX & Avatar workbench
│   ├── index.html                             # Interactive simulator (Mac Cue, iOS, 53-state stage)
│   ├── pipibot-avatar.js                      # 192-ray 120Hz procedural SVG engine
│   └── tokens.css                             # Obsidian Dark / Warm Vellum Light design tokens
├── docs/
│   ├── architecture/
│   │   ├── 01-PRODUCT-VISION-AND-RESEARCH.md  # Devin, GrokBot, Pi, Manus Cue/Dots/Muse synthesis
│   │   ├── 02-SYSTEM-ARCHITECTURE-AND-HARNESS.md # PipiCore, PipiRouter, Routed MCP Bridge, Outcomes
│   │   ├── 03-CLOUDFLARE-AND-FLEET-INFRA.md   # $0 Cloudflare stack + Mac/iOS/VPS/Win/IoT fleet
│   │   └── 04-MEMORY-AND-SELF-EVOLUTION.md    # 4-Tier Memory + Nightly Dreaming & Skill Synthesis
│   ├── design-system/
│   │   └── 01-UIUX-DESIGN-SYSTEM.md           # Ambient Soul & Outcome Studio design specification
│   └── roadmap/
│       ├── 01-DEVELOPMENT-PLAN.md             # Phase 0-5 WBS, test suites, SLAs, risk matrix
│       └── 02-PROGRESS-TRACKER.md             # Live status dashboard, ADR-001~008, changelog
└── packages/
    ├── protocol/src/index.ts                  # @pipibot/protocol zero-dep shared contracts
    ├── core/src/harness-router.ts             # PipiHarnessRouter & RoutedMcpBridge
    ├── core/src/memory-engine.ts              # 4-tier PipiMemoryEngine & PipiEvolutionLoop
    └── cloudflare-edge/                       # Worker relay, D1 schema, R2 artifacts, wrangler.toml
```

---

## 3. Local Development Setup

### Prerequisites

- **Node.js `>= 22.6.0`** (native ESM, `--check`, and `--experimental-strip-types` support)
- **npm `>= 10`** (workspace management)
- **Python 3** (for zero-build static preview of [`design-system/index.html`](design-system/index.html))
- **Git**

### Quick Verification Commands

```bash
# 1. Preview the Interactive Design System & 120Hz Avatar Workbench
npm run preview:design
# Open http://127.0.0.1:8080/design-system/ in your browser

# 2. Syntax-check the procedural avatar engine
npm run check:avatar

# 3. Run workspace verification & typechecks (when TypeScript / workspace scripts are installed)
npm run verify
```

---

## 4. Common Contribution Workflows

### A. Adding or Updating a Harness Adapter

1. Read [`docs/architecture/02-SYSTEM-ARCHITECTURE-AND-HARNESS.md`](docs/architecture/02-SYSTEM-ARCHITECTURE-AND-HARNESS.md) first.
2. Add or extend provider metadata in [`packages/protocol/src/index.ts`](packages/protocol/src/index.ts) (`HarnessProvider`, capabilities, auth discovery schema).
3. Implement detection, spawning/RPC transport, and **Routed MCP Bridge** registration in [`packages/core/src/harness-router.ts`](packages/core/src/harness-router.ts).
4. Ensure `250ms` activity pulse emissions and normalized event envelopes match the `Pi` core stream contract so the UI avatar and iOS Live Activity reflect state transitions uniformly.

### B. Extending the Procedural Avatar or Design System

1. Review [`docs/design-system/01-UIUX-DESIGN-SYSTEM.md`](docs/design-system/01-UIUX-DESIGN-SYSTEM.md).
2. Keep [`design-system/pipibot-avatar.js`](design-system/pipibot-avatar.js) zero-dependency and modular so `node --check design-system/pipibot-avatar.js` always passes without a DOM runtime.
3. Preserve the 6-track animation structure (`x`, `y`, `rot`, `squash`, `scale`, `lids`), 120Hz semi-implicit Euler springs, Rodrigues 3D sphere eye projection, and `0.26s` blink curve (peak closure at 45%).
4. Update tokens in [`design-system/tokens.css`](design-system/tokens.css) for both **Obsidian Dark** and **Warm Vellum Light** themes.

### C. Evolving Memory, Outcomes, or Cloudflare Edge

1. Check [`docs/architecture/04-MEMORY-AND-SELF-EVOLUTION.md`](docs/architecture/04-MEMORY-AND-SELF-EVOLUTION.md) before altering salience weights or `SOUL.md` / `USER.md` / `MEMORY.md` synthesis rules in [`packages/core/src/memory-engine.ts`](packages/core/src/memory-engine.ts).
2. For any schema or endpoint change in [`packages/cloudflare-edge/schema.sql`](packages/cloudflare-edge/schema.sql) or [`packages/cloudflare-edge/src/worker.ts`](packages/cloudflare-edge/src/worker.ts), verify projected daily Worker invocations, D1 row reads, and R2 retention against the $0/mo budget table in [`docs/architecture/03-CLOUDFLARE-AND-FLEET-INFRA.md`](docs/architecture/03-CLOUDFLARE-AND-FLEET-INFRA.md).

### D. Proposing Major Architectural Changes (ADRs)

Significant cross-package changes require an **Architectural Decision Record (ADR)** appended to [`docs/roadmap/02-PROGRESS-TRACKER.md`](docs/roadmap/02-PROGRESS-TRACKER.md) covering: Context, Decision, Alternatives Considered, Free-Tier/Performance Impact, and Rollback Plan.

---

## 5. Pull Request Checklist

- [ ] Branch created from `main` with a clear scope (`feat/...`, `fix/...`, `docs/...`).
- [ ] Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat(core): ...`, `docs(roadmap): ...`, `fix(avatar): ...`).
- [ ] Relative markdown links verified against actual workspace paths.
- [ ] No API keys, OAuth tokens, `.env` files, or local `.sqlite` databases staged.
- [ ] [`docs/roadmap/02-PROGRESS-TRACKER.md`](docs/roadmap/02-PROGRESS-TRACKER.md) updated if a milestone deliverable or ADR changed.
- [ ] Exact verification commands and results included in the PR description.

---

## 6. Code of Conduct

Be direct, constructive, evidence-driven, and respectful. PipiBot aims to elevate human agency — treat fellow contributors with the same clarity and care.
