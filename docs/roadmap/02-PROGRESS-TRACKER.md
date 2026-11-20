# PipiBot 工程进度看板与架构决策记录 (Progress Tracker & ADRs)

> **当前基线版本**: `v0.2.0-beta` (+ Linger 对标升级 Wave 1 / Wave 2 / Wave 3 `100% Verified`)
> **最近更新**: `2026-11-20`
> **开源仓库**: `https://github.com/JimiZhou/pipibot` (`main`)
> **关联计划**: [全阶段工程开发计划 (`01-DEVELOPMENT-PLAN.md`)](./01-DEVELOPMENT-PLAN.md) · [Linger 对标提升主计划 (`03-LINGER-UPGRADE-PLAN.md`)](./03-LINGER-UPGRADE-PLAN.md) · [Mac/iOS V1 实现规范 (`05-MAC-AND-IOS-V1-IMPLEMENTATION.md`)](../architecture/05-MAC-AND-IOS-V1-IMPLEMENTATION.md) · [Mac 原生应用指南 (`06-MAC-NATIVE-APP-GUIDE.md`)](../architecture/06-MAC-NATIVE-APP-GUIDE.md) · [iOS 原生与 PWA 指南 (`07-IOS-APP-AND-PWA-GUIDE.md`)](../architecture/07-IOS-APP-AND-PWA-GUIDE.md)

---

## 1. 实时工程进度总览 (Live Progress Dashboard)

| 阶段 (Phase) | 史诗主题 (Epic Theme) | 目标版本 | 周期 | 进度 (Progress) | 状态 (Status) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Phase 0** | 深度研究、系统架构、设计系统与核心脚手架 | `v0.1.0-alpha` | Baseline | `██████████` **100%** | ✅ 100% Verified (GitHub Initial Release) |
| **Phase 1** | macOS 常驻守护进程、Pi SDK、多 Harness 适配器与 4 层 SQLite 记忆 | `v0.2.0-beta` | Weeks 1–2 | `███████░░░` **75%** | 🚧 Wave 2 Core Daemon Shipped (`@pipibot/daemon`) |
| **Phase 2** | $0/月 Cloudflare 边缘隧道、Workers Relay、D1/R2 与 Zero Trust | `v0.3.0-beta` | Week 3 | `██░░░░░░░░` **20%** | 🚧 Edge Worker/D1 Schema Ready · Tunnel Wiring Next |
| **Phase 3** | OpenPencil 5-Rule + All-in-One `PipiBot.app` + Native `PipiBotIOS.app` & PWA | `v0.2.0-beta` | Weeks 4–5 | `█████████░` **95%** | 🚧 Wave 3 Mac App & Wave 4 Native iOS App (`npm run app:ios`) Complete |
| **Phase 4** | Devin Outcome Manager、自动评估循环与夜间自我进化/技能合成 | `v0.5.0-rc` | Week 6 | `███░░░░░░░` **30%** | 🚧 Evaluator & Dreaming APIs Live in Daemon |
| **Phase 5** | `PipiFleet` 多节点扩展 (Linux VPS / Windows WSL2 / ESP32 & RPi IoT) | `v1.0.0` | Weeks 7–8 | `█░░░░░░░░░` **10%** | 📋 Protocol & Telemetry Matrix Defined |

---

## 2. 分阶段交付物追踪 (Deliverables Checklist)

### Phase 0: `v0.1.0-alpha` — Open-Source Architecture, Design System & Core Scaffolding (`100% Verified · 25/25 Files`)

- **Epic 0.1 — 架构与领域研究文档**
  - [x] [`docs/architecture/01-PRODUCT-VISION-AND-RESEARCH.md`](../architecture/01-PRODUCT-VISION-AND-RESEARCH.md) — Devin Bots、GrokBot 0.18、GrokBot Animation Anatomy、Pi Harness 与 Manus Cue/Dots/Muse 深度拆解与融合矩阵
  - [x] [`docs/architecture/02-SYSTEM-ARCHITECTURE-AND-HARNESS.md`](../architecture/02-SYSTEM-ARCHITECTURE-AND-HARNESS.md) — `PipiCore`、`PipiRouter` (`pi`, `claude-code`, `codex`, `opencode`, `byok`)、`RoutedMcpBridge` 与 `PipiOutcomeEngine` 完整设计
  - [x] [`docs/architecture/03-CLOUDFLARE-AND-FLEET-INFRA.md`](../architecture/03-CLOUDFLARE-AND-FLEET-INFRA.md) — $0/月 Cloudflare 免费层基础设施配额账本与 `PipiFleet` 跨端节点安全拓扑
  - [x] [`docs/architecture/04-MEMORY-AND-SELF-EVOLUTION.md`](../architecture/04-MEMORY-AND-SELF-EVOLUTION.md) — L0–L3 四层认知记忆架构、显著性评分公式与夜间自我进化循环
- **Epic 0.2 — UI/UX 设计系统与零依赖交互工作台**
  - [x] [`docs/design-system/01-UIUX-DESIGN-SYSTEM.md`](../design-system/01-UIUX-DESIGN-SYSTEM.md) — "Ambient Soul & Outcome Studio" 设计语言、53 状态机与双端交互规范
  - [x] [`design-system/tokens.css`](../../design-system/tokens.css) — Obsidian Dark & Warm Vellum Light 双主题语义 Token
  - [x] [`design-system/pipibot-avatar.js`](../../design-system/pipibot-avatar.js) — 192 射线轮廓插值 + 120Hz Euler 弹簧 + Rodrigues 3D 眼球程序化头像引擎
  - [x] [`design-system/index.html`](../../design-system/index.html) — 零构建交互式设计系统、Mac Manus Cue & iOS Needs You 模拟器
- **Epic 0.3 — Monorepo 协议、核心逻辑与边缘脚手架**
  - [x] [`packages/protocol/src/index.ts`](../../packages/protocol/src/index.ts) — `@pipibot/protocol` 全链路类型契约
  - [x] [`packages/core/src/harness-router.ts`](../../packages/core/src/harness-router.ts) — `PipiHarnessRouter` 与 `RoutedMcpBridge` 核心实现骨架
  - [x] [`packages/core/src/memory-engine.ts`](../../packages/core/src/memory-engine.ts) — 四层 `PipiMemoryEngine` 与 `PipiEvolutionLoop` 骨架
  - [x] [`packages/cloudflare-edge/wrangler.toml`](../../packages/cloudflare-edge/wrangler.toml), [`schema.sql`](../../packages/cloudflare-edge/schema.sql), [`src/worker.ts`](../../packages/cloudflare-edge/src/worker.ts) — Cloudflare Worker/D1/R2 边缘中继
- **Epic 0.4 — 工程规划与开源工程基建**
  - [x] [`docs/roadmap/01-DEVELOPMENT-PLAN.md`](./01-DEVELOPMENT-PLAN.md) & [`docs/roadmap/02-PROGRESS-TRACKER.md`](./02-PROGRESS-TRACKER.md)
  - [x] [`README.md`](../../README.md), [`README.zh-CN.md`](../../README.zh-CN.md), [`CONTRIBUTING.md`](../../CONTRIBUTING.md), [`LICENSE`](../../LICENSE)
  - [x] [`package.json`](../../package.json), [`tsconfig.base.json`](../../tsconfig.base.json), [`.gitignore`](../../.gitignore)
- **Phase 0 质量门禁验证记录 (Verification Gate — 2026-11-19)**:
  - [x] 全量 25/25 交付文件完整存在，文档与代码占位符扫描命中 0 处。
  - [x] 全部 147 处跨文档相对 Markdown 链接与内部 TOC 锚点 100% 可达；`design-system/index.html` 引用与 `design-system/pipibot-avatar.js` 导出完全匹配且静态 HTTP 服务返回 `200 OK`。
  - [x] `npm run verify`（`node --check design-system/pipibot-avatar.js` + `@pipibot/protocol` / `@pipibot/core` Node 22 `--experimental-strip-types`）、`bun build`（全部 4 个 `.ts` 入口）、`sqlite3 :memory:` (`schema.sql` 8 张表) 与 `Bun.TOML.parse` (`wrangler.toml`) 全部通过。
  - [x] 跨包契约校验：`@pipibot/protocol` `AVATAR_STATES_53`（53 状态）/ `AVATAR_EXPRESSIONS_9`（9 表情）与 `design-system/pipibot-avatar.js` 实现 1:1 精确对齐，5/5 跨包端到端烟雾断言通过。

### Wave 2 (`v0.2.0-beta` — ✅ 100% Verified): V1 Mac 常驻守护进程、Native Swift 6 Mac/iOS、Live iOS PWA 与 OpenPencil 设计治理

- **Epic W2.1 — OpenPencil 5-Rule 设计治理与 Stageshow 集成**
  - [x] [`design-system/design-system.md`](../../design-system/design-system.md) — 单文件持久化 AI 设计记忆（Rule + Reason + `2026-11-19`）
  - [x] [`design-system/pipibot.pen`](../../design-system/pipibot.pen) & [`design-system/tokens.dtcg.json`](../../design-system/tokens.dtcg.json) — 3 层 Token、6 大规范积木 (`list-card`, `sheet`, `form-sheet`, `dock`, `bottom-bar`, `empty-state`) 与 12 屏 OpenPencil JSON
  - [x] [`scripts/audit-design-system.mjs`](../../scripts/audit-design-system.mjs) — 跨 `.pen`、`design-system.md`、`apps/ios-web/styles.css` 与 `apps/apple/Sources/` 自动化五规则审计脚本
  - [x] `.agents/skills/stageshow` & [`docs/design-system/01-UIUX-DESIGN-SYSTEM.md`](../design-system/01-UIUX-DESIGN-SYSTEM.md) — Stageshow `device-pair` / `dynamic-island` 展示工艺与五规则文档补全
- **Epic W2.2 — V1 macOS 常驻宿主 Daemon (`packages/daemon`)**
  - [x] [`packages/daemon/package.json`](../../packages/daemon/package.json) & [`src/cli.ts`](../../packages/daemon/src/cli.ts) — `@pipibot/daemon` CLI 与 `npm run start:daemon`
  - [x] [`packages/daemon/src/outcome-engine.ts`](../../packages/daemon/src/outcome-engine.ts) — `PipiOutcomeEngine` 两阶段自主评估器、子会话调度与 Needs You R2 证据队列
  - [x] [`packages/daemon/src/cue-fleet-sensor.ts`](../../packages/daemon/src/cue-fleet-sensor.ts) — `PipiCueSensor` 工作区/Git 感知与 `PipiFleetManager` 实机指标 + Tunnel 状态
  - [x] [`packages/daemon/src/server.ts`](../../packages/daemon/src/server.ts) & [`test/daemon.test.ts`](../../packages/daemon/test/daemon.test.ts) — REST `/api/v1/*` + 250ms SSE + `launchd` plist 生成 + `/design-system/` & `/ios` 静态托管与全路由集成测试
- **Epic W2.3 — 原生 Apple Swift 6 工程 (`apps/apple`) & 实时 iOS PWA (`apps/ios-web`)**
  - [x] [`apps/apple/Package.swift`](../../apps/apple/Package.swift) — `PipiBotKit`（`ProtocolModels`、`DesignTokens`、`CanonicalBlocks`、120Hz `PipiProceduralAvatarEngine`、`PipiDaemonClient`）、`PipiBotIOSUI`（Swipe Deck / Muse / Dots）、`PipiBotMacApp`（`MenuBarExtra` / `ManusCueFloatingPanel` / `MacOutcomeStudioView`）与 `PipiBotKitTests`
  - [x] [`apps/ios-web/index.html`](../../apps/ios-web/index.html), [`styles.css`](../../apps/ios-web/styles.css), [`app.js`](../../apps/ios-web/app.js), [`manifest.json`](../../apps/ios-web/manifest.json) — 零 raw hex、6 积木复用、Live SSE + 离线降级 PWA
  - [x] [`docs/architecture/05-MAC-AND-IOS-V1-IMPLEMENTATION.md`](../architecture/05-MAC-AND-IOS-V1-IMPLEMENTATION.md) — V1 全栈实现规范文档
- **Wave 2 (`v0.2.0-beta`) 质量门禁验证记录 (Verification Gate — 2026-11-19)**:
  - [x] `node scripts/audit-design-system.mjs` 退出码 `0`：通过 `pipibot.pen`（6 个积木组件、12 个桌面/移动 Screen、99 处变量绑定精确 `fallbackColor`、44 个文本节点、16 个图标、8 个 `clip` 容器、11 个按钮、4 个 Sheet、13 项 Vellum Light `>= 4.5:1` 对比度校验）、`design-system.md`（19 条规则）、`tokens.dtcg.json`、`apps/ios-web/styles.css`（0 原始 hex/rgb）及 `apps/apple/Sources/`（`DesignTokens.swift` 之外 13 个 Swift 文件 0 原始 hex）。
  - [x] `npm run verify` 退出码 `0`：通过 `check:avatar`、`check:ios`、`audit:design`、`check:workspaces`（`@pipibot/core` / `@pipibot/daemon` / `@pipibot/protocol`）以及 `test:daemon`（`packages/daemon/test/daemon.test.ts` **10/10 通过**）。
  - [x] `cd apps/apple && swift build && swift test` 退出码 `0`：`PipiBotMacApp` 可执行目标构建成功，`PipiBotKitTests` **7/7 通过**；`xcodebuild -scheme PipiBotIOSUI -destination 'generic/platform=iOS Simulator' build` 输出 `** BUILD SUCCEEDED **`。
  - [x] 端到端链路与文档巡检：`PipiResidentServer` 15 个 REST 与 `/ios` / `/design-system/` 静态路由实测返回 `200 OK`；跨文档 214 处相对 Markdown 链接 0 断链，PipiBot 文档与源码占位符命中 0 处。

### Wave 3 (`v0.2.0-beta` · All-in-One Native `PipiBot.app`): 独立桌面打包与原生运行时融合

- **Epic W3.1 — App 内置原生运行时与托管桥接 (`PipiNativeMacRuntime`)**
  - [x] [`apps/apple/Sources/PipiBotKit/Runtime/PipiNativeMacRuntime.swift`](../../apps/apple/Sources/PipiBotKit/Runtime/PipiNativeMacRuntime.swift) — 本机 CLI 扫描 (`pi`/`claude`/`codex`/`opencode`/`byok`)、`ProcessInfo` 实机遥测、`NSWorkspace` + Git 前台感知、`resident-state.json` 持久化、`ProcessInfo.beginActivity` 防休眠锁与 `PipiEmbeddedBridgeSupervisor` 自动桥接托管
  - [x] [`apps/apple/Sources/PipiBotKit/State/PipiAppStore.swift`](../../apps/apple/Sources/PipiBotKit/State/PipiAppStore.swift), [`PipiBotMacApp.swift`](../../apps/apple/Sources/PipiBotMacApp/PipiBotMacApp.swift) & [`MacOutcomeStudioView.swift`](../../apps/apple/Sources/PipiBotMacApp/MacOutcomeStudioView.swift) — 开箱即运行 Native All-in-One 模式（无需手动开启终端守护进程）
  - [x] [`apps/apple/Tests/PipiBotKitTests/PipiBotKitTests.swift`](../../apps/apple/Tests/PipiBotKitTests/PipiBotKitTests.swift) — 原生探测器、遥测、Cue 感知与持久化单元测试
- **Epic W3.2 — 原生 `.app` Bundle 打包与架构文档**
  - [x] [`scripts/build-mac-app.sh`](../../scripts/build-mac-app.sh) & [`package.json`](../../package.json) — 新增 `npm run app:mac`，自动构建 Release `dist/PipiBot.app` 并执行签名
  - [x] [`docs/architecture/06-MAC-NATIVE-APP-GUIDE.md`](../architecture/06-MAC-NATIVE-APP-GUIDE.md) & [`05-MAC-AND-IOS-V1-IMPLEMENTATION.md`](../architecture/05-MAC-AND-IOS-V1-IMPLEMENTATION.md) — 详述 All-in-One `PipiBot.app` 架构、三大桌面入口、八大功能模块与打包运行指南

### Wave 4 (`v0.2.0-beta` · Dual-Mode iOS): 原生系统应用 (`PipiBotIOS.app`) + 零安装 PWA (`apps/ios-web`)

- **Epic W4.1 — iOS 系统级深度集成与独立原生 App (`PipiBotIOSApp`)**
  - [x] [`apps/apple/Sources/PipiBotIOSUI/PipiIOSSystemIntegration.swift`](../../apps/apple/Sources/PipiBotIOSUI/PipiIOSSystemIntegration.swift) — Action Button & Siri `AppIntents` (`PipiIOSShortcutsProvider`)、锁屏 `UNTextInputNotificationAction` Steer 通知 (`PipiIOSNotificationManager`)、灵动岛/小组件快照桥接 (`PipiIOSLiveActivitySnapshot` / `PipiIOSWidgetBridge`) 与 `pipibot://` Tunnel 配对路由 (`PipiIOSDeepLinkRouter`)
  - [x] [`apps/apple/Sources/PipiBotIOSUI/PipiIOSCompanionRootView.swift`](../../apps/apple/Sources/PipiBotIOSUI/PipiIOSCompanionRootView.swift) & [`apps/apple/Sources/PipiBotIOSApp/PipiBotIOSApp.swift`](../../apps/apple/Sources/PipiBotIOSApp/PipiBotIOSApp.swift) — 独立 `@main` 原生 iOS App，串联 `.onOpenURL`、`ScenePhase` 快照同步与 Native iOS System Integrations 检视抽屉
  - [x] [`apps/apple/Package.swift`](../../apps/apple/Package.swift) & [`apps/apple/Tests/PipiBotKitTests/PipiBotKitTests.swift`](../../apps/apple/Tests/PipiBotKitTests/PipiBotKitTests.swift) — 新增 `PipiBotIOSApp` 可执行目标与深链/灵动岛快照集成单测
- **Epic W4.2 — iOS `.app` Bundle 打包与双形态指南**
  - [x] [`scripts/build-ios-app.sh`](../../scripts/build-ios-app.sh) & [`package.json`](../../package.json) — 新增 `npm run app:ios`，经由 `xcodebuild` 编译 iOS Simulator `arm64` 二进制并生成 `dist/PipiBotIOS.app`（`NSSupportsLiveActivities`、`pipibot://` URL Scheme、`plutil` + `codesign` 校验）
  - [x] [`docs/architecture/07-IOS-APP-AND-PWA-GUIDE.md`](../architecture/07-IOS-APP-AND-PWA-GUIDE.md) & [`05-MAC-AND-IOS-V1-IMPLEMENTATION.md`](../architecture/05-MAC-AND-IOS-V1-IMPLEMENTATION.md) — 详述 Native `PipiBotIOS.app` 与 Zero-Install PWA 双形态架构、系统集成及运行指南

### Linger 对标提升 Wave 1（`2026-11-20` — ✅ 100% Verified）：调度、双层风控与跨端契约地基（`#04` + `#08` + `#12`）

- **Epic L1.1 — 洁净室开源合规与跨端契约单源校验 (`#12`)**
  - [x] [`NOTICE`](../../NOTICE) & [`docs/roadmap/03-LINGER-UPGRADE-PLAN.md`](./03-LINGER-UPGRADE-PLAN.md) — 明确 MIT 协议边界与 `simplexai-labs/linger` / `PolyStrata` 洁净室架构灵感署名（零源码/素材复制）
  - [x] [`packages/protocol/schema/host-v2.schema.json`](../../packages/protocol/schema/host-v2.schema.json) & [`scripts/audit-protocol-parity.mjs`](../../scripts/audit-protocol-parity.mjs) — 11 项 Host v2 规范枚举实现 JSON Schema ↔ TypeScript ↔ Swift 1:1 自动校验并纳入 `npm run verify`
- **Epic L1.2 — 优先级可抢占模型调度器与 AIMD 自适应并发 (`#04`)**
  - [x] [`packages/core/src/model-scheduler.ts`](../../packages/core/src/model-scheduler.ts) & [`apps/apple/Sources/PipiBotKit/Runtime/PipiModelScheduler.swift`](../../apps/apple/Sources/PipiBotKit/Runtime/PipiModelScheduler.swift) — 7 级优先级排队、交互保留槽位 `soft = max(1, hard - 1)`、AIMD 429/延迟退避、统一 JSON Schema 自纠重试与可恢复 CLI Session 抢占自动 `--resume` 续跑
  - [x] [`apps/apple/Sources/PipiBotKit/State/PipiAppStore.swift`](../../apps/apple/Sources/PipiBotKit/State/PipiAppStore.swift) — 替换旧 FIFO 队列接入 `PipiModelScheduler`，后台 Routine 支持让渡给前台交互并无缝续跑
- **Epic L1.3 — 规则 + 独立 LLM 双层风控裁判、多粒度审批与写幂等 (`#08`)**
  - [x] [`packages/core/src/permission-guardrail.ts`](../../packages/core/src/permission-guardrail.ts) & [`apps/apple/Sources/PipiBotKit/Runtime/PipiPermissionGuardrail.swift`](../../apps/apple/Sources/PipiBotKit/Runtime/PipiPermissionGuardrail.swift) — 静态规则 + `critical` 硬熔断（密钥外发、破坏审批规则、毁灭性删除强制 `deny`）+ Prompt Injection 可信/不可信隔离 + 独立 LLM Risk×Authorization 裁判（故障默认安全阻断）+ `operation_id` 写幂等账本
  - [x] [`packages/core/src/harness-router.ts`](../../packages/core/src/harness-router.ts), [`apps/apple/Sources/PipiBotMacApp/PipiSessionTimelineCards.swift`](../../apps/apple/Sources/PipiBotMacApp/PipiSessionTimelineCards.swift) & [`PipiSettingsView.swift`](../../apps/apple/Sources/PipiBotMacApp/PipiSettingsView.swift) — 接入 `RoutedMcpBridge`、时间线多粒度审批卡（本次/本会话/本项目或长期/拒绝 + 风险徽章与理由）及设置页白名单审计撤销
- **Wave 1 质量门禁验证记录 (`2026-11-20`)**:
  - [x] `npm run verify` 退出码 `0`：`audit:design`（39 个 Swift 文件 0 原始 hex）、`audit:protocol`（11/11 枚举三端精确一致 + `NOTICE` + 4/4 模块洁净室署名头）、`test:core` **8/8 通过**、`test:daemon` **11/11 通过**。
  - [x] `cd apps/apple && swift build && swift test` 退出码 `0`：**53/53 通过**（含 `PipiBotWave1Tests` 6/6 全绿，零编译警告）；`xcodebuild -scheme PipiBotIOSUI -destination 'generic/platform=iOS Simulator' build` 输出 `** BUILD SUCCEEDED **`。

### Linger 对标提升 Wave 2（`2026-11-20` — ✅ 100% Verified）：个人知识 Wiki、Per-Bot 独立记忆与 macOS 原生主动性（`#01` + `#02` + `#03`）

- **Epic L2.1 — 个人向实体 Wiki + SQLite WAL/FTS5 双通道零向量检索 (`#01`)**
  - [x] [`packages/protocol/schema/host-v2.schema.json`](../../packages/protocol/schema/host-v2.schema.json) & [`scripts/audit-protocol-parity.mjs`](../../scripts/audit-protocol-parity.mjs) — Host v2 跨端单一事实来源枚举扩展至 **17/17**（新增 `WikiEntityCategory`、`WikiSearchScope`、`BotMemoryLifecycleStage`、`ProactiveSourceKind`、`ProactiveActionDecision`、`ProactiveFeedbackSignal`）并校验 12/12 Wave 1+2 模块洁净室 MIT 署名头
  - [x] [`apps/apple/Sources/PipiBotKit/Runtime/PipiPersonalWikiStore.swift`](../../apps/apple/Sources/PipiBotKit/Runtime/PipiPersonalWikiStore.swift) & [`packages/core/src/personal-wiki.ts`](../../packages/core/src/personal-wiki.ts) — 原生 SQLite3 WAL + FTS5（Node 端支持 `node:sqlite` WAL 自动探测 FTS5 / SQLite BM25 倒排兜底）、个人向分类（`people/projects/topics/life/repos`）、CJK bigram、最多 6 改写词、独立 `chunks`/`facts`/`summaries` 通道、软时间窗 RRF 与脱敏原子 Markdown 投影
- **Epic L2.2 — Per-Bot 独立经验记忆与 Prompt-Cache 安全召回 (`#02`)**
  - [x] [`apps/apple/Sources/PipiBotKit/Runtime/PipiBotMemoryEngine.swift`](../../apps/apple/Sources/PipiBotKit/Runtime/PipiBotMemoryEngine.swift) & [`packages/core/src/bot-memory.ts`](../../packages/core/src/bot-memory.ts) — 严格按 Bot 目录隔离、每 5 次成功运行提炼候选、空闲 6 小时/会话压缩/>64KB/>=30 会话自动去重合并；首条或压缩后通过出站隐藏附注注入，**零改动 System Prompt**
  - [x] [`apps/apple/Sources/PipiBotKit/State/PipiAppStore.swift`](../../apps/apple/Sources/PipiBotKit/State/PipiAppStore.swift) & [`PersonalBotModels.swift`](../../apps/apple/Sources/PipiBotKit/Models/PersonalBotModels.swift) — 接入 `compactionGeneration`、`compactConversation(id:)`、后台 6h 空闲自动合并与 Prompt-Cache 安全注入链路
- **Epic L2.3 — macOS 原生主动感知、Prepare 备料与 `Clue → Rule` 夜间自学习 (`#03`)**
  - [x] [`apps/apple/Sources/PipiBotKit/Runtime/PipiProactiveEngine.swift`](../../apps/apple/Sources/PipiBotKit/Runtime/PipiProactiveEngine.swift), [`PipiMacNativeSignalCollector.swift`](../../apps/apple/Sources/PipiBotKit/Runtime/PipiMacNativeSignalCollector.swift) & [`packages/core/src/proactive-engine.ts`](../../packages/core/src/proactive-engine.ts) — 首批 macOS 原生事件源（`EventKit` 日历/提醒事项、本地 Git/FS、Mac 遥测、笔记）+ 22:00–08:00 静音窗/每日限额/3 分钟对话退让/SHA-256 日级去重 + 只读 `Prepare` Wiki 关联备料 + 14 天 `seen>=2` 升格规则（上限 20 条、快照一键回滚）
  - [x] [`apps/apple/Sources/PipiBotMacApp/PipiKnowledgeHubView.swift`](../../apps/apple/Sources/PipiBotMacApp/PipiKnowledgeHubView.swift), [`PipiWorkspaceView.swift`](../../apps/apple/Sources/PipiBotMacApp/PipiWorkspaceView.swift), [`PipiBotInspectorView.swift`](../../apps/apple/Sources/PipiBotMacApp/PipiBotInspectorView.swift) & [`PipiSettingsView.swift`](../../apps/apple/Sources/PipiBotMacApp/PipiSettingsView.swift) — 新增「知识与简报」三合一原生界面（个人 Wiki / 主动简报 / Bot 记忆）、`/wiki` 与 `/compact` 斜杠命令、右侧 Inspector 压缩入口及设置页自学习规则审计回滚面板（100% `PipiTokens`，0 原始色值）
- **Wave 2 质量门禁验证记录 (`2026-11-20`)**:
  - [x] `npm run verify` 退出码 `0`：`audit:design`（44 个 Swift 文件 0 原始 hex）、`audit:protocol`（17/17 枚举三端精确一致 + `NOTICE` + 12/12 模块洁净室署名头）、`test:core` **11/11 通过**（含 `wave2.test.ts`）、`test:daemon` **11/11 通过**、`typecheck` 通过。
  - [x] `cd apps/apple && swift build && swift test` 退出码 `0`：**57/57 通过**（含 `PipiBotWave2Tests` 4/4 全绿，零编译警告）；`xcodebuild -scheme PipiBotIOSUI -destination 'generic/platform=iOS Simulator' build` 输出 `** BUILD SUCCEEDED **`。

### Linger 对标提升 Wave 3（`2026-11-20` — ✅ 100% Verified）：高阶协同（AlterEgo + `team.md`）与工具生态（CLI / 技能 / 随手记）（`#05` + `#06` + `#11`）

- **Epic L3.1 — Meta / AlterEgo 会话内自主后台分身委派 (`#05`)**
  - [x] [`packages/core/src/alter-ego.ts`](../../packages/core/src/alter-ego.ts) & [`apps/apple/Sources/PipiBotKit/Runtime/PipiAlterEgoCoordinator.swift`](../../apps/apple/Sources/PipiBotKit/Runtime/PipiAlterEgoCoordinator.swift) — 自主 `<pipibot_delegate>` 指令解析 + `/delegate` 命令、独立可写 `playground/<taskId>/` + 同会话兄弟只读共享（严格拒绝跨会话读取与路径穿越）、中途 Steer、实时步骤展开、取消与保留产物恢复，走 `PipiModelScheduler`（`.delegatedTask`）
  - [x] [`apps/apple/Sources/PipiBotMacApp/PipiAlterEgoBarView.swift`](../../apps/apple/Sources/PipiBotMacApp/PipiAlterEgoBarView.swift) & [`PipiWorkspaceView.swift`](../../apps/apple/Sources/PipiBotMacApp/PipiWorkspaceView.swift) — 会话顶部按需展示分身进度条（零空闲占位）
- **Epic L3.2 — 结构化 `team.md` 全量 5 模式多 Bot 协作与动态成员审批 (`#06`)**
  - [x] [`packages/core/src/team-protocol.ts`](../../packages/core/src/team-protocol.ts) & [`apps/apple/Sources/PipiBotKit/Runtime/PipiTeamProtocol.swift`](../../apps/apple/Sources/PipiBotKit/Runtime/PipiTeamProtocol.swift) — 纯函数解析与多问题报告、Kahn DAG 环路与并行波次校验、全量 5 种协作拓扑（`classify-and-act` / `fan-out-and-synthesize` / `adversarial-verification` / `tournament` / `loop-until-done`）及动态拉入/新建角色 Bot 审批（`PipiDynamicBotProposal`）
  - [x] [`apps/apple/Sources/PipiBotMacApp/PipiGroupInspectorView.swift`](../../apps/apple/Sources/PipiBotMacApp/PipiGroupInspectorView.swift) & [`PipiShellSubViews.swift`](../../apps/apple/Sources/PipiBotMacApp/PipiShellSubViews.swift) — 群工作区集成 `team.md` 5 模式模板生成/DAG 校验编辑器/一键执行，并在群面板与 `Needs You` 收件箱同步承载动态成员审批卡
- **Epic L3.3 — 统一 `pipibot` CLI + 版本化只读技能包 + 每日随手记与可编辑文档 (`#11`)**
  - [x] [`packages/core/src/pipibot-cli.ts`](../../packages/core/src/pipibot-cli.ts) & [`package.json`](../../package.json) — 新增 `npm run pipibot`，单点注册表同源生成 `--help` / `--schema` / `--permissions` 并支持 `--operation-id` 幂等回放
  - [x] [`packages/core/src/builtin-skills.ts`](../../packages/core/src/builtin-skills.ts) & [`apps/apple/Sources/PipiBotKit/Runtime/PipiBuiltinSkillsRegistry.swift`](../../apps/apple/Sources/PipiBotKit/Runtime/PipiBuiltinSkillsRegistry.swift) — 8 套内置办公/日常技能（`docx`/`pdf`/`pptx`/`xlsx`/`slide-deck`/`humanlike-browse`/`personal-profile`/`proactive-response`）`0444` 只读投影 + SHA-256 校验防篡改自愈
  - [x] [`packages/core/src/pocket-notes.ts`](../../packages/core/src/pocket-notes.ts), [`apps/apple/Sources/PipiBotKit/Runtime/PipiPocketNotesEngine.swift`](../../apps/apple/Sources/PipiBotKit/Runtime/PipiPocketNotesEngine.swift) & [`PipiKnowledgeHubView.swift`](../../apps/apple/Sources/PipiBotMacApp/PipiKnowledgeHubView.swift) — 每日随手记静默 5 分钟自动提炼/对账 Tracking Items + 可编辑产物文档（修订号/SHA-256/一键同步 Wiki）与内置技能检视 Tab
- **Wave 3 质量门禁验证记录 (`2026-11-20`)**:
  - [x] `npm run verify` 退出码 `0`：`audit:design`（49 个 Swift 文件 0 原始 hex）、`audit:protocol`（22/22 枚举三端精确一致 + `NOTICE` + 22/22 Wave 1–3 模块洁净室署名头）、`test:core` **14/14 通过**（含 `wave3.test.ts`）、`test:daemon` **11/11 通过**、`typecheck` 通过。
  - [x] `cd apps/apple && swift build && swift test` 退出码 `0`：**60/60 通过**（含 `PipiBotWave3Tests` 3/3 全绿，零编译警告）；`xcodebuild -scheme PipiBotIOSUI -destination 'generic/platform=iOS Simulator' build` 输出 `** BUILD SUCCEEDED **`。

### Linger 对标提升 Wave 4（`2026-11-20` — ✅ 100% Verified）：本地模型栈（PolyStrata + Gateway）与个人日常语音（`#07` + `#10`）

- **Epic L4.1 — 硬件 Model Autopilot、PolyStrata (MIT) 集成与真实问答自测 (`#07`)**
  - [x] [`packages/core/src/model-autopilot.ts`](../../packages/core/src/model-autopilot.ts) & [`apps/apple/Sources/PipiBotKit/Runtime/PipiModelAutopilot.swift`](../../apps/apple/Sources/PipiBotKit/Runtime/PipiModelAutopilot.swift) — 真实本机硬件探测 + 5 层确定性规划器（64K/128K KV 池、16 模型含 12+ `PolyStrata` MIT MoE 目录、Apple Silicon Metal+SSD beta 与 `PipiFleet` Linux/Win CUDA+RAM/SSD 分页、`llama.cpp`/Ollama/MLX 兜底）+ 强制真实问答自测门禁（`PIPI_QA_42` 校验 + TTFT/tok/s 统计）
- **Epic L4.2 — 本地统一回环 LLM Gateway 与 CLI 隔离环境反向注入 (`#07`)**
  - [x] [`packages/core/src/local-llm-gateway.ts`](../../packages/core/src/local-llm-gateway.ts), [`apps/apple/Sources/PipiBotKit/Runtime/PipiLocalLLMGateway.swift`](../../apps/apple/Sources/PipiBotKit/Runtime/PipiLocalLLMGateway.swift) & [`PipiInferenceEngine.swift`](../../apps/apple/Sources/PipiBotKit/Runtime/PipiInferenceEngine.swift) — 仅监听 `127.0.0.1` 的双协议本地 Gateway（OpenAI `/v1/chat/completions` ↔ Anthropic `/anthropic/v1/messages` JSON/SSE 互转 + 常量时间 Token 鉴权），并生成 `0700`/`0600` 隔离环境叠加层（`CLAUDE_CONFIG_DIR` / `CODEX_HOME` / `PI_CODING_AGENT_DIR` / `OPENCODE_CONFIG_DIR`）透传给 CLI 子进程，绝不污染 `~/.claude` 或 `~/.codex`
- **Epic L4.3 — 个人日常语音交互（端侧优先 + BYOK 云端语音 + 本地 VAD 防回声打断）(`#10`)**
  - [x] [`packages/core/src/voice-engine.ts`](../../packages/core/src/voice-engine.ts), [`apps/apple/Sources/PipiBotKit/Runtime/PipiDailyVoiceEngine.swift`](../../apps/apple/Sources/PipiBotKit/Runtime/PipiDailyVoiceEngine.swift), [`PipiMuseVoiceBarView.swift`](../../apps/apple/Sources/PipiBotMacApp/PipiMuseVoiceBarView.swift), [`PipiQuickBarPanel.swift`](../../apps/apple/Sources/PipiBotMacApp/PipiQuickBarPanel.swift) & [`PipiSettingsView.swift`](../../apps/apple/Sources/PipiBotMacApp/PipiSettingsView.swift) — 聚焦个人日常（口述 Dictation、Muse 免提对话、一句话派活 Voice-to-Task，走 `.voiceInteractive` 优先级）；实现本地 RMS+ZCR 回声门控打断（`PipiEchoGatedVAD`）、`on_device_only` 零外发硬隐私墙及 Keychain 托管的 BYOK 云端语音 API（OpenAI/Deepgram/ElevenLabs/Custom）
- **Wave 4 质量门禁验证记录 (`2026-11-20`)**:
  - [x] `npm run verify` 退出码 `0`：`audit:design`（53 个 Swift 文件 0 原始 hex）、`audit:protocol`（29/29 枚举三端精确一致 + `NOTICE` + 29/29 Wave 1–4 模块洁净室署名头）、`test:core` **17/17 通过**（含 `wave4.test.ts`）、`test:daemon` **11/11 通过**、`typecheck` 通过。
  - [x] `cd apps/apple && swift build && swift test` 退出码 `0`：**63/63 通过**（60 XCTest + `PipiBotWave4Tests` 3/3 Swift Testing 全绿，零编译警告）；`xcodebuild -scheme PipiBotIOSUI -destination 'generic/platform=iOS Simulator' build` 输出 `** BUILD SUCCEEDED **`。

### Linger 对标提升 Wave 5（`2026-11-20` — ✅ 100% Verified · 12/12 全部收官）：双阶段 Computer Use（`#09`）

- **Epic L5.1 — Phase A 本机已登录 Chrome 协同与 Phase B macOS Accessibility / Cua 双车道运行底座 (`#09`)**
  - [x] [`packages/core/src/computer-use.ts`](../../packages/core/src/computer-use.ts) & [`apps/apple/Sources/PipiBotKit/Runtime/PipiComputerUseEngine.swift`](../../apps/apple/Sources/PipiBotKit/Runtime/PipiComputerUseEngine.swift) — Phase A 每 Agent 独立 Chrome Seat/Tab（`signed_in_chrome_seat` / `isolated_profile`，密钥仅留本机、禁止 `javascript:` 页面脚本注入）+ Phase B 原生 `AXUIElement` 元素树与 `NSWorkspace` 焦点监控；实现桌面全局单车道（自动等待在途浏览器调用）+ 每 Agent 并行浏览器车道、人类切窗即时礼让（`yielded_to_human`）、Write-Ahead Journal（`0600` 原子落盘防重复点击 + `unknown_outcome` 自动锁车道直至人工核查解锁）及与 `#08` `PipiPermissionGuardrail` 的 `<browser_state>` / `<desktop_state>` 深度联动
- **Epic L5.2 — 原生桌面监控条、设置面板与 CLI 工具集成 (`#09`)**
  - [x] [`apps/apple/Sources/PipiBotMacApp/PipiComputerUseBarView.swift`](../../apps/apple/Sources/PipiBotMacApp/PipiComputerUseBarView.swift), [`PipiWorkspaceView.swift`](../../apps/apple/Sources/PipiBotMacApp/PipiWorkspaceView.swift), [`PipiSettingsView.swift`](../../apps/apple/Sources/PipiBotMacApp/PipiSettingsView.swift) & [`packages/core/src/pipibot-cli.ts`](../../packages/core/src/pipibot-cli.ts) — 工作区按需展示 Computer Use 状态条（一键「人工接管 / 恢复 / 解锁车道」与 WAL 展开审计）、`/computer` 斜杠命令、设置页 Chrome Seat & macOS 辅助功能权限直达面板，以及 `pipibot computer journal / unlock-lane` CLI 子命令
- **Wave 5 质量门禁验证记录 (`2026-11-20`)**:
  - [x] `npm run verify` 退出码 `0`：`audit:design`（55 个 Swift 文件 0 原始 hex）、`audit:protocol`（35/35 枚举三端精确一致 + `NOTICE` + 32/32 Wave 1–5 模块洁净室署名头）、`test:core` **20/20 通过**（含 `wave5.test.ts`）、`test:daemon` **11/11 通过**、`typecheck` 通过。
  - [x] `cd apps/apple && swift build && swift test` 退出码 `0`：**66/66 通过**（60 XCTest + Wave 4/5 共 6/6 Swift Testing 全绿，零编译警告）；`xcodebuild -scheme PipiBotIOSUI -destination 'generic/platform=iOS Simulator' build` 输出 `** BUILD SUCCEEDED **`。

### Phase 1–5: Remaining Backlog

| Epic ID | 所属阶段 | 关键交付项 (Planned / Remaining Deliverables) | 状态 |
| :--- | :--- | :--- | :--- |
| **E1.1** | Phase 1 | `pipibot-daemon` HTTP REST + 250ms SSE + `launchd` plist 生成器上线；Unix Socket IPC 与睡眠锁增量补齐 | 🚧 80% |
| **E1.2** | Phase 1 | `@mariozechner/pi-coding-agent` SDK 真实子进程嵌入式挂载与扩展安全钩子落盘 | 🚧 60% |
| **E1.3** | Phase 1 | `claude-code` / `codex` / `opencode` 探测 + `PipiHarnessRouter` 框架完成；真机 CLI 流式联调待补 | 🚧 70% |
| **E1.4** | Phase 1 | `PipiMemoryEngine` 引擎骨架就绪；真实 SQLite WAL + FTS5 + `sqlite-vec` 持久化驱动接入 | 🚧 50% |
| **E2.1** | Phase 2 | `cloudflared` 休眠唤醒自愈隧道与 Worker WebSocket/SSE + APNs 线上部署与实测 | 🚧 25% |
| **E2.2** | Phase 2 | D1 Fleet Registry、R2 7 天 TTL 制品上传器与 Cloudflare Access Service Token 端到端联调 | 🚧 20% |
| **E3.1** | Phase 3 | macOS `MenuBarExtra`、`ManusCueFloatingPanel` (`⌥Space`) 与 `MacOutcomeStudioView` 落地；系统级全局热键权限完善 | 🚧 85% |
| **E3.2** | Phase 3 | Swift 6 `PipiBotIOSUI` + Live `apps/ios-web` PWA 落地；真机 `ActivityKit` 灵动岛签名打包待补 | 🚧 80% |
| **E4.1** | Phase 4 | `PipiOutcomeEngine` 两阶段评估原型上线；Cron/Webhook/FS Watch 守护触发器完善 | 🚧 35% |
| **E4.2** | Phase 4 | `PipiEvolve` 做梦 Diff API 上线；夜间空闲自动聚类与 Pi Skill 自动写入磁盘待补 | 🚧 25% |
| **E5.1** | Phase 5 | `pipibot-node-linux` (`<15MB` VPS `systemd` 代理) | 📋 Planned |
| **E5.2** | Phase 5 | `pipibot-node-win` (Windows Service + WSL2) & `pipibot-edge-iot` (RPi / ESP32 MQTT / Home Assistant) | 📋 Planned |

---

## 3. 架构决策记录 (Architectural Decision Records, ADR-001 ~ ADR-009)

### ADR-001: 采用 Pi (`@mariozechner/pi-coding-agent` / `pi-ai`) 作为极简核心 Harness 内核
- **Status**: `Accepted` (2026-11-18)
- **Context**: 传统 AI Agent 框架往往内置数十个耦合工具、复杂 Prompt 黑盒与重型依赖，难以跨模型复用且常驻内存开销大，不适合作为常驻个人设备的多端总管底座。
- **Decision**: 选用 `Pi` 的 4 工具极简内核（`read`, `write`, `edit`, `bash`）与模型无关的 `pi-ai` 路由层作为 `PipiCore` 嵌入式内核，并借助其 25+ TypeScript Extension Hooks 与 Skills 系统扩展安全护栏与能力。
- **Consequences**:
  - (+) 内核极度轻量可控，支持以 SDK/RPC/JSON 事件流方式原生嵌入 macOS Daemon。
  - (+) 天然兼容各类 BYOK API（OpenAI、Anthropic、Gemini、DeepSeek、Grok、Ollama/vLLM）。
  - (-) 复杂交互（如 MCP、记忆图谱、多端调度）需通过 PipiBot 自研扩展与协议层显式装配，增加了核心契约的设计责任。

### ADR-002: 采用 GrokBot 风格零依赖程序化 SVG 引擎替代 Lottie / GIF / WebGL
- **Status**: `Accepted` (2026-11-18)
- **Context**: Lottie 与视频序列帧无法根据光标位置实时 3D 眼球追踪、无法动态对物理打断做出连续弹簧回弹，且多状态导出文件体积膨胀迅速；WebGL 在菜单栏小图标与轻量弹窗中显存开销过高。
- **Decision**: 基于 `grokbot-animation-anatomy` 的核心数学原理构建零依赖程序化 SVG 引擎（Web 端为 [`design-system/pipibot-avatar.js`](../../design-system/pipibot-avatar.js)，iOS 端移植至 SwiftUI `Canvas`/Metal）：192 射线极坐标轮廓插值、6 轨道 cubic-Bézier 关键帧、120Hz 半隐式 Euler 弹簧、Rodrigues 3D 球面眼球投影与 `0.26s` 眨眼曲线，支持 53 状态机与 9 种表情。
- **Consequences**:
  - (+) 体积仅数 KB、任意 DPI 无损缩放、CPU 占用 `< 1%`，且拥有“活着”的物理质感。
  - (-) 需在 Web (JS) 与 iOS (Swift) 两侧保持数学公式与关键帧配方同步。

### ADR-003: 采用 Routed MCP Bridge 统一复用本地已认证 CLI (`claude-code`, `codex`, `opencode`) 与 BYOK
- **Status**: `Accepted` (2026-11-18)
- **Context**: 开发者电脑上往往已经登录了 Claude Code、Codex CLI、OpenCode 等高阶订阅工具。若要求用户重复申请并付费 API Key，不仅体验割裂，还会导致各 CLI 无法访问 PipiBot 的个人记忆与跨设备工具。
- **Decision**: 借鉴 `grok-bot-0.18-reconstructed` 架构，实现 `PipiHarnessRouter` 与 `RoutedMcpBridge`：自动探测本地已认证的 `claude`、`codex`、`opencode` CLI，并在拉起子进程时动态注入 `--mcp-config`（stdio/SSE），将 `PipiMemory`、`NeedsYou` 与 `PipiFleet` 工具安全暴露给外部 CLI；同时保留 `pi-ai` BYOK 直连路径。
- **Consequences**:
  - (+) 零重复 API 费用，既能享受顶尖专有 CLI 的代码推理力，又能沉淀统一记忆与结果证据。
  - (-) 需为各 CLI 维护轻量级输出流解析适配器以防范上游 CLI 升级变动。

### ADR-004: 采用 Devin-Style "Outcome-over-Task" 责任模型与统一 "Needs You" 收件箱
- **Status**: `Accepted` (2026-11-18)
- **Context**: 纯对话式 Chatbot 要求人类充当微管理经理（不断追问进度、复制报错、手动验证），无法实现“一人管理十个持续运转的 Bot 舰队”。
- **Decision**: 引入 Devin Bots 的 **Outcome Ownership** 原语：用户定义长期 **Responsibility（目标 + 约束 + 成功指标 + 触发器）**，后台自主触发并借助独立 Evaluator 验证交付物（附带 R2 截图/视频/日志证据），仅当遇到边界歧义、高危操作或策略决策时才汇总进入统一的 **"Needs You" 人类决策收件箱**。
- **Consequences**:
  - (+) 极大降低人类注意力碎片化，支持 iOS 端单手 3 秒批阅驱动研发、工作与生活流。
  - (-) 必须设计严格的成本与权限 Guardrails（见 `01-DEVELOPMENT-PLAN.md` 风险矩阵 R-04），防止后台死循环。

### ADR-005: 采用 100% Cloudflare 免费层基础设施实现零公网端口跨端互联
- **Status**: `Accepted` (2026-11-18)
- **Context**: 自建公网服务器或购买中继 VPS 会增加每月固定财务成本与公网端口暴露攻击面，且家庭宽带通常无固定公网 IP。
- **Decision**: 全栈使用 Cloudflare Free Tier 组合：`cloudflared` 出站加密隧道（0 开放端口）+ Workers（WebSocket/SSE 中继与 APNs 唤醒）+ D1（Fleet 注册表与离线队列表）+ KV（Presence 缓存）+ R2（10GB 零出站费视觉证据与加密备份）+ Access Zero Trust（OIDC + Service Token）。
- **Consequences**:
  - (+) 真正实现 **$0/月** 运维成本，且具备全球 Anycast 就近接入与零公网暴露安全性。
  - (-) 需严格遵守免费配额（如 Worker 100k req/day、R2 10GB 上限），通过边缘脉冲合并与 7 天临时制品 TTL 守卫配额红线。

### ADR-006: 采用 4 层混合认知记忆 (L0–L3) 与夜间透明进化机制
- **Status**: `Accepted` (2026-11-18)
- **Context**: 单纯把历史塞入向量库（RAG）容易检索出互相矛盾的过期偏好，也无法将“反复成功的步骤”固化为可复用技能；而暗箱更新用户画像又会带来不可控的幻觉风险。
- **Decision**: 设计 L0（瞬时工作上下文）-> L1（SQLite FTS5 + `sqlite-vec` 情景日志）-> L2（人类可读可改的 `SOUL.md` / `USER.md` / `MEMORY.md` 语义图谱 + 时间线覆盖）-> L3（夜间做梦自动合成的 Pi `skills/*.md`），并强制展示每日 **Evolution Diff** 供审计回滚。
- **Consequences**:
  - (+) “越用越懂用户”，且用户随时可用普通文本编辑器查看或修正 PipiBot 对自己的认知。
  - (-) 夜间汇总消耗少量本地/BYOK 推理 Token，需限定仅在电源接入及低费率模型下运行。

### ADR-007: V1 客户端形态收敛为 “macOS 常驻宿主 + iOS 原生伴侣端” 分离架构
- **Status**: `Accepted` (2026-11-18)
- **Context**: 若在 V1 同时开发 macOS、iOS、Android、Web Dashboard、Windows 桌面 GUI，会分散战线导致体验平庸。
- **Decision**: V1 专注打磨 **macOS Always-On Resident Host**（`launchd` 守护 + MenuBar + Manus Cue `⌥Space` 负责所有重型计算、CLI 托管与本地记忆存储）与 **iOS Native Companion App**（SwiftUI + Dynamic Island + 120Hz Avatar + Needs You 滑动审批 + Muse 语音打断），Linux/Windows/IoT 则作为无头执行节点纳入 `PipiFleet`。
- **Consequences**:
  - (+) 聚焦苹果生态开发者与核心效率人群的最强日常闭环，避免跨端 UI 妥协。
  - (-) 非 macOS 宿主的纯 Linux/Windows 桌面用户需待 Phase 5 节点与通用管理界面完善。

### ADR-008: Local-First 数据主权与端到端局部载荷加密
- **Status**: `Accepted` (2026-11-18)
- **Context**: AI 个人管家掌握着用户的代码仓库、家庭日常、服务器权限与个人偏好，任何云端明文留存都会构成不可接受的隐私风险。
- **Decision**: 坚持 macOS 本地作为唯一权威数据主节点（Single Source of Truth）：源代码、API Key（Keychain）、原始 SQLite 记忆库绝不上云；通过 Cloudflare Tunnel/Workers/R2 流转的 Prompt、终端摘要与备份快照全部附加基于设备公钥/对称密钥的端到端加密（E2EE），Cloudflare 仅路由密文与不可敏感元数据。
- **Consequences**:
  - (+) 即便云账号或边缘节点日志发生极端泄露，核心代码与个人隐私仍不可读取。
  - (-) 跨端配对阶段需要一次优雅的二维码 / Passkey 密钥交换引导流程。

### ADR-009: 采用 OpenPencil 五规则设计治理、6 大规范积木与 Stageshow 约束 AI 生成界面
- **Status**: `Accepted` (2026-11-19)
- **Context**: 当同一产品横跨 Web 工作台、iOS PWA (`apps/ios-web`) 与原生 Swift 6 (`apps/apple`) 时，AI Coding Agent 极易在各文件散落硬编码色值、不一致的卡片/抽屉几何尺寸以及低级特效（如紫色闪烁星星），破坏产品一致性。
- **Decision**: 引入三件套作为唯一视觉契约——[`design-system/design-system.md`](../../design-system/design-system.md)（一句规则 + 原因 + 日期）、[`design-system/tokens.dtcg.json`](../../design-system/tokens.dtcg.json) / [`tokens.css`](../../design-system/tokens.css)（3 层 Token 体系）、[`design-system/pipibot.pen`](../../design-system/pipibot.pen)（6 个规范命名积木 `list-card`, `sheet`, `form-sheet`, `dock`, `bottom-bar`, `empty-state` + 12 屏 Frame），集成 `.agents/skills/stageshow` 展示工艺，并用 [`scripts/audit-design-system.mjs`](../../scripts/audit-design-system.mjs) 自动审计 `.pen`、CSS 与 Swift 源码（仅 `DesignTokens.swift` 允许字面量色值）。
- **Consequences**:
  - (+) 彻底消灭 Web/Swift 双端样式漂移与 `#000000` 变量回退色错配，每次提交均可机审。
  - (-) 新增视觉元素时需先注册至 Token 与规范积木，不可即兴硬编码样式。

### ADR-010: 借鉴上游开源项目的洁净室 MIT 实现与透明署名规范
- **Status**: `Accepted` (2026-11-20)
- **Context**: 对标学习 `simplexai-labs/linger`（Linger Open Source License：Apache 2.0 附加托管服务与前端 Logo 条款）等优秀项目时，必须确保 PiPiBot 保持 100% MIT 协议纯净，避免任何许可证传染或版权争议。
- **Decision**: 严格遵守洁净室原则——零复制上游源码、Prompt、前端组件与素材，全部在 Swift 6 / TypeScript 中独立从零实现；并在根目录 `NOTICE`、中英文 `README`、`03-LINGER-UPGRADE-PLAN.md` 及对应源文件头部透明标注架构灵感来源，同时将合规检查纳入 `scripts/audit-protocol-parity.mjs`。
- **Consequences**:
  - (+) 兼具开源透明署名与 MIT 协议法律纯净度，对社区用户与商业自用零额外限制。
  - (-) 需在每次新增受启发模块时保持署名头与 `NOTICE` 同步。

### ADR-011: 采用 7 级优先级可抢占模型调度器与 AIMD 自适应并发替代静态 FIFO 队列
- **Status**: `Accepted` (2026-11-20)
- **Context**: 随着定时 Routine、夜间记忆/Wiki 刷新与本地模型单并发场景引入，原有静态 FIFO 队列会导致后台任务阻塞用户前台对话，且对云端 429 限流无自适应退避能力。
- **Decision**: 构建跨端一致的 `PipiModelScheduler`（7 级优先级、交互保留槽位 `soft = max(1, hard - 1)`、AIMD 429/延迟退避、统一 JSON Schema 纠错重试），并为支持 `cliSessionId` 的后台 CLI 会话提供安全让渡与自动 `--resume` 续跑闭环。
- **Consequences**:
  - (+) 前台交互与高危审批永远优先响应，本地单卡/单并发模型体验不卡顿。
  - (-) 后台可抢占任务需严格校验可恢复会话条件（如 Codex 确认已落盘输出/工具事件且无待决审批卡）后方可让渡。

### ADR-012: 采用规则 + 独立 LLM 双层风控裁判、多粒度审批与写操作幂等账本
- **Status**: `Accepted` (2026-11-20)
- **Context**: 原有 `ask` 权限档位仅在整轮只读后弹出宽泛审批，缺少防 Prompt Injection 隔离、窃密硬熔断、细粒度范围授权以及重试防重复写保护。
- **Decision**: 引入 `PipiPermissionGuardrail`（Layer 1 静态策略 + `critical` 硬熔断 `deny` + `operation_id` 写幂等账本；Layer 2 高危动作独立 LLM Risk×Authorization 裁判，严格分离可信授权与不可信上下文并采用故障安全阻断）及多粒度审批选项（`allow_once` / `allow_session` / `allow_project` / `allow_always` / `deny`），白名单规则可在设置页透明审计与一键撤销。
- **Consequences**:
  - (+) 显著提升对 Prompt Injection、凭据外泄与重复副作用的防御力，同时减少重复审批疲劳。
  - (-) 规则匹配仍不可绕过 `critical` 熔断与最近的用户撤回信号。

### ADR-013: 采用原生 SQLite3 WAL + FTS5 CJK Bigram 双通道零向量个人实体 Wiki
- **Status**: `Accepted` (2026-11-20)
- **Context**: 个人日常知识库若强依赖外部向量模型或 Docker/PostgreSQL，会破坏 PiPiBot 的零配置本地体验并增加检索成本与延迟。
- **Decision**: 在 Swift 端直接复用系统 `SQLite3`（开启 WAL 与内置 FTS5 `bm25()`），在 Node 端复用 `node:sqlite` WAL（自动探测 FTS5 并在无 `ENABLE_FTS5` 的二进制上回退到 SQLite 倒排 BM25 表）；面向个人场景固定 5 大实体分类（`people` / `projects` / `topics` / `life` / `repos`），通过 CJK Bigram 扩展 + 最多 6 改写词 + 独立 `chunks`/`facts`/`summaries` 通道 + 软时间窗 RRF 实现零向量秒级召回，并同步投影脱敏 Markdown 文件。
- **Consequences**:
  - (+) 零外部依赖、零向量费用、双端行为一致，且支持人类直接用编辑器阅读个人知识文件。
  - (-) 可选本地/云端向量检索保留为扩展通道（默认关闭），避免额外推理开销。

### ADR-014: 采用 Per-Bot 严格隔离记忆与 Prompt-Cache 安全隐藏附注注入策略
- **Status**: `Accepted` (2026-11-20)
- **Context**: 若将动态演化的个人/Bot 记忆不断拼接到 System Prompt 中，会导致每轮 Prompt 前缀失效、Anthropic/OpenAI/本地 KV Cache 命中率骤降；同时不同角色 Bot 混用同一份经验记忆会引发角色串味。
- **Decision**: 为每个 Bot 分配独立隔离目录 `bots/<botId>/memory/{summary.md, candidates.json, state.json}`，按「每 5 次成功运行提炼候选 → 6h 空闲 / 会话压缩 / >64KB / >=30 会话自动合并去重」节奏维护；召回时**严禁修改 System Prompt**，仅在会话首条消息或会话压缩（`compactionGeneration` 递增）后的首条出站用户消息中注入隐藏 `<pipibot_bot_memory>` 附注，且不污染界面可见气泡。
- **Consequences**:
  - (+) 长会话期间 System Prompt 字节完全不变，最大化 KV Prompt Cache 命中率与响应速度；各 Bot 经验互不干扰。
  - (-) 需通过 `compactConversation` 或新开会话主动刷新长对话中更新的记忆版本。

### ADR-015: 采用 macOS 原生事件源优先的主动防打扰护栏、只读 Prepare 备料与可回滚 `Clue → Rule` 自学习
- **Status**: `Accepted` (2026-11-20)
- **Context**: 主动式 AI 若缺乏静音窗、每日限额与对话退让机制，极易沦为高频骚扰通知；而未经授权自动执行外部写操作则会带来安全风险。
- **Decision**: 第一批主动源严格聚焦 macOS 原生信号（`EventKit` 日历/提醒事项、本地 Git/FS、Mac 遥测、笔记），设置 22:00–08:00 静音窗、每日提醒上限、3 分钟活跃对话静默退让与日级 SHA-256 去重；对临近日程与活跃代码库提供只读 `Prepare` 提前备料（自动关联个人 Wiki 上下文，零外部副作用）；所有用户反馈进入 14 天滑动线索池，`seen >= 2` 自动升格为规则（上限 20 条）并保存版本快照支持一键回滚。
- **Consequences**:
  - (+) 主动性克制可信、越用越懂用户打扰边界，且无需额外第三方 SaaS 连接器即可发挥 Mac 本机优势。
  - (-) `EventKit` 日历/提醒事项需由用户在界面显式触发系统权限授权，后台扫描绝不静默弹窗阻塞。

### ADR-016: 采用 Meta / AlterEgo 会话内自主后台分身委派与同会话只读互通 `playground/`
- **Status**: `Accepted` (2026-11-20)
- **Context**: 当用户在单聊中抛出耗时调研或批量分析任务时，同步等待会阻塞对话；而允许后台任务肆意读写工作区又会导致并发冲突或跨会话数据串味。
- **Decision**: 实现 `PipiAlterEgoCoordinator`：支持 Meta 通过 `<pipibot_delegate>` 自主派生（或用户 `/delegate` 触发）后台分身，按 `sessions/<sessionId>/playground/<taskId>/` 分配独立可写目录并开放同会话兄弟任务只读互通，严格拦截路径穿越与跨会话读取；提供中途 Steer、取消与保留产物恢复，并经 `PipiModelScheduler`（`.delegatedTask`）礼让前台聊天。
- **Consequences**:
  - (+) 前台聊天零卡顿，多后台分身可流水线协作复用中间产物且互不覆盖。
  - (-) 分身产物默认留在 `playground/`，合入正式代码仓库仍受既有权限档位与 Guardrail 约束。

### ADR-017: 采用结构化 `team.md` 全量 5 模式协作协议与动态成员审批
- **Status**: `Accepted` (2026-11-20)
- **Context**: 自由群聊模式难以表达“对抗评审”“锦标赛择优”“有界循环迭代”或严格 DAG 依赖顺序，且当群内缺少特定专家角色时缺少安全受控的扩编机制。
- **Decision**: 引入纯函数 `PipiTeamProtocol` 解析校验器与执行引擎，支持全部 5 种协作拓扑（`classify-and-act`、`fan-out-and-synthesize`、`adversarial-verification`、`tournament`、`loop-until-done`）及 Kahn DAG 环路检测（仅对抗/循环模式允许有界 `max_rounds` 回环）；当协议指定了不在群内的角色/Bot 时自动生成 `PipiDynamicBotProposal` 审批卡，经用户批准后拉入现有 Bot 或动态新建角色 Bot 入群。
- **Consequences**:
  - (+) 多 Bot 协作可审计、可复现、不死循环，且支持按需动态扩展团队角色。
  - (-) 新建角色 Bot 需经人类显式审批，杜绝 Agent 擅自无界增殖。

### ADR-018: 采用单源 `pipibot` CLI、SHA-256 只读技能投影与静默 5 分钟每日随手记
- **Status**: `Accepted` (2026-11-20)
- **Context**: 工具说明、JSON Schema 与权限清单分处维护容易漂移；本地技能文件若可被 Agent 随手篡改则存在持久化投毒风险；个人灵感随手记需要无感沉淀为待办而不打断书写。
- **Decision**: 在 `packages/core/src/pipibot-cli.ts` 以单一 `PIPIBOT_CLI_COMMANDS` 注册表同源生成 `--help` / `--schema` / `--permissions` 并接入 `PipiOperationLedger`（`--operation-id`）；内置 8 套版本化办公/日常技能以 `0444` 只读权限投影并执行 SHA-256 完整性防篡改自愈；每日随手记编辑静默 5 分钟后自动提炼并对账 `TrackingItem`，配套可编辑产物文档支持修订号、SHA-256 与一键同步个人 Wiki。
- **Consequences**:
  - (+) CLI 文档/Schema/权限零漂移，内置技能防篡改，个人日常记录平滑闭环至 Wiki 与待办。
  - (-) 后续新增本地 CLI 命令均需在 `PIPIBOT_CLI_COMMANDS` 单点注册。

### ADR-019: 采用本地回环双协议 LLM Gateway 与隔离环境叠加层反向注入 CLI Agent
- **Status**: `Accepted` (2026-11-20)
- **Context**: 用户希望将本机 PolyStrata / llama.cpp / Ollama / MLX 本地模型或 BYOK API 复用到已安装的 `claude` / `codex` / `pi` / `opencode` CLI Agent 上，但直接改写 `~/.claude` 或 `~/.codex` 会破坏用户原有的个人订阅登录与终端配置，且 Claude Code 仅讲 Anthropic Messages 协议而本地推理后端多提供 OpenAI Chat Completions 接口。
- **Decision**: 在 TypeScript Core (`PipiLocalLLMGateway`) 与 Swift 6 (`Network.framework` `NWListener`) 双端实现仅监听 `127.0.0.1` 的统一回环 Gateway，内置 OpenAI ↔ Anthropic 双向 JSON/SSE 协议互转与常量时间鉴权；启动 CLI 子进程时按会话在 PiPiBot 私有数据目录生成 `0700`/`0600` 隔离配置并通过 `CLAUDE_CONFIG_DIR` / `CODEX_HOME` / `PI_CODING_AGENT_DIR` / `OPENCODE_CONFIG_DIR` 环境变量反向注入。
- **Consequences**:
  - (+) 本地与 BYOK 模型可零修改无缝驱动任意 CLI Agent，用户个人 `~/.claude` 与 `~/.codex` 100% 洁净无污染。
  - (-) 本地模型必须先通过确定性真实问答自测门禁（`PipiModelAutopilot.verifyModelWithQA`）方可标记为 `verified`。

### ADR-020: 个人日常语音坚持端侧优先、回声门控打断与 `on_device_only` 零外发隐私墙
- **Status**: `Accepted` (2026-11-20)
- **Context**: 个人日常口述、Muse 免提对话与一句话派活高度敏感且高频，直接把全部麦克风音频上传云端既产生费用又泄露隐私；而在免提对话中若不做回声门控，Bot 自身的 TTS 播音会反复误触发自打断。
- **Decision**: 构建 `PipiDailyVoiceEngine` 与 `PipiEchoGatedVAD`：默认采用 Apple 原生端侧 `SFSpeechRecognizer(requiresOnDeviceRecognition)` + `AVSpeechSynthesizer`（并预留 WhisperKit / MLX Audio 端侧路由），同时支持 Keychain 托管的 BYOK 云端语音 API；在 `on_device_only` 策略下强制硬阻断任何云端传输；播音期间按 `echoGateMultiplier` 抬高能量门槛并要求连续人声帧后即时触发 Barge-In 打断，所有语音交互经 `.voiceInteractive` 高优先级调度。
- **Consequences**:
  - (+) 零门槛、零额外月费的个人日常语音闭环，同时允许高要求用户按需接入 OpenAI / Deepgram / ElevenLabs BYOK API。
  - (-) 聚焦个人日常轻量交互（口述 / Muse / 派活），刻意保持非会议录音定位以维持端侧轻量性。

### ADR-021: Computer Use 采用「桌面全局单车道 + 每 Agent 独立浏览器车道 + 人类切窗礼让 + 写前日志 (WAL)」安全模型
- **Status**: `Accepted` (2026-11-20)
- **Context**: 多 Agent 并发操作浏览器和桌面时极易争抢鼠键焦点、与人类正在使用的前景窗口打架，或在超时/崩溃重试时重复点击“发送/付款”等不可逆按钮；同时直接将浏览器 Cookie/密钥同步到云端或开放页面脚本注入会带来极大安全隐患。
- **Decision**: 在 TS Core (`PipiComputerUseCoordinator`) 与 Swift 6 (`PipiComputerUseEngine`) 双端实现 Phase A（本机已登录 Chrome 每 Agent 独立 Seat/Tab + 禁止 `javascript:` 页面脚本注入）与 Phase B（macOS Accessibility 元素树单车道）：桌面输入自动等待在途浏览器前景调用并串行执行，监听 `NSWorkspace` 前景切换一旦检测到人类切窗即刻进入 `yielded_to_human` 停手礼让；所有输入动作先写 `0600` Write-Ahead Journal 再派发，结果未知（`unknown_outcome`）立即锁定车道严禁自动重放，且全部提交/外发与系统隐私开关操作均经 `#08` `PipiPermissionGuardrail` 审查。
- **Consequences**:
  - (+) 多 Agent 浏览器并行高效、桌面不与人类抢焦点、杜绝误点/重放点击，且凭据始终留在本机。
  - (-) 当车道因崩溃/超时进入 `blocked_unknown_outcome` 时需人类核查画面后一键点击解锁，换取确定性安全。

---

## 4. 变更日志 (Changelog)

### `v0.2.0-beta` (2026-11-19) — V1 Mac Daemon, Native Swift 6 Mac/iOS, Live iOS PWA & OpenPencil Design Governance (Verified)
- **Dual-Mode Native iOS (`PipiBotIOS.app`) + Zero-Install PWA (Wave 4)**: 新增原生 iOS 可执行目标 `PipiBotIOSApp`、系统级集成 `PipiIOSSystemIntegration.swift`（Action Button/Siri `AppIntents`、锁屏 `UNTextInput` Steer 通知、灵动岛/小组件快照、`pipibot://` 深链）、`scripts/build-ios-app.sh` (`npm run app:ios` -> `dist/PipiBotIOS.app`) 与 [`07-IOS-APP-AND-PWA-GUIDE.md`](../architecture/07-IOS-APP-AND-PWA-GUIDE.md)。
- **All-in-One Native `PipiBot.app` (Wave 3)**: 升级 `PipiBotMacApp` 为完全独立的原生桌面应用（内置 `PipiNativeMacRuntime` 与按需自动托管的 `PipiEmbeddedBridgeSupervisor`），新增 `scripts/build-mac-app.sh`、`npm run app:mac` 及 [`06-MAC-NATIVE-APP-GUIDE.md`](../architecture/06-MAC-NATIVE-APP-GUIDE.md)。
- **OpenPencil v2.21 Scene-Graph**: 为 [`design-system/pipibot.pen`](../../design-system/pipibot.pen) 补齐 `@open-pencil/pen` v2.21 原生 `variables` 与 `children` 场景图并在 `audit-design-system.mjs` 纳入校验。
- **Wave 2 Release Gate**: 完成 OpenPencil 五规则审计 (`scripts/audit-design-system.mjs`)、`npm run verify`（含 `@pipibot/daemon` 10/10 测试）、Swift 6 macOS 构建与测试 (`swift test` 7/7) 及 `PipiBotIOSUI` iOS Simulator 构建全量通过。
- **Design Governance & Stageshow**: 落地 [`design-system/pipibot.pen`](../../design-system/pipibot.pen)、[`design-system.md`](../../design-system/design-system.md)、[`tokens.dtcg.json`](../../design-system/tokens.dtcg.json)、自动化五规则审计脚本 [`scripts/audit-design-system.mjs`](../../scripts/audit-design-system.mjs) 及 `.agents/skills/stageshow` 技能集成。
- **Mac Resident Daemon (`@pipibot/daemon`)**: 交付零外部运行时依赖的 HTTP REST + 250ms SSE 服务 (`packages/daemon`)，实现 `PipiOutcomeEngine` 两阶段评估、`PipiCueSensor` 工作区探测、`PipiFleetManager` 实机监控、`ai.pipibot.daemon.plist` 生成及全路由 `daemon.test.ts` 集成测试。
- **Native Apple Swift 6 (`apps/apple`)**: 交付 `PipiBotKit`（53 状态协议模型、3 层 `DesignTokens`、6 个 `CanonicalBlocks`、120Hz `PipiProceduralAvatarEngine`、`PipiDaemonClient`）、`PipiBotIOSUI`（Needs You 左滑/右滑栈、Muse 画布、Dots & Tunnel 视图）、`PipiBotMacApp`（`MenuBarExtra`、Manus Cue `NSPanel`、`MacOutcomeStudioView`）及 `PipiBotKitTests`。
- **Live iOS Companion PWA (`apps/ios-web`)**: 交付零构建、零原始 hex 的 iOS 伴侣网页应用（通过 Daemon `/ios` 直出），完整对接 `/api/v1/*` 与 SSE 实时脉动并支持离线演示降级。
- **Architecture & Tooling**: 新增 [`05-MAC-AND-IOS-V1-IMPLEMENTATION.md`](../architecture/05-MAC-AND-IOS-V1-IMPLEMENTATION.md) 与 `ADR-009`，升级根 [`package.json`](../../package.json) 脚本与全链路校验门禁。

### `v0.1.0-alpha` (2026-11-18 ~ 2026-11-19) — Initial Open-Source Foundation & GitHub Release Milestone
- **Release Milestone**: 完成 Phase 0 全量 25 个开源基线文件的跨包契约统一与自动化质量门禁验收（100% Verified），初始化 `main` 分支并发布公开 GitHub 仓库 [`JimiZhou/pipibot`](https://github.com/JimiZhou/pipibot)。
- **Architecture**: 发布 4 份深度架构规范文档（产品愿景与竞品拆解、Pi Core 与多 Harness 路由、$0 Cloudflare 边缘与多端 Fleet、4 层记忆与自我进化引擎）。
- **Design System**: 发布 *"Ambient Soul & Outcome Studio"* 设计规范与零依赖可交互工作台（[`design-system/index.html`](../../design-system/index.html)），完整落地 192 射线轮廓、120Hz 弹簧与 Rodrigues 3D 眼球程序化头像及 Mac/iOS 模拟器。
- **Core & Edge Scaffolding**: 发布 `@pipibot/protocol` 共享类型契约（53 个规范化状态 ID 与 9 表情 1:1 对齐头像引擎）、`@pipibot/core` 路由器/记忆骨架及 `@pipibot/cloudflare-edge` Worker/D1/R2 模板。
- **Roadmap & Governance**: 建立 Phase 0–5 全量开发计划、进度看板、ADR-001~008 架构决策记录、中英文旗舰 README、MIT 协议与贡献指南。
