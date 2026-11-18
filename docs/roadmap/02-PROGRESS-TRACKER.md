# PipiBot 工程进度看板与架构决策记录 (Progress Tracker & ADRs)

> **当前基线版本**: `v0.1.0-alpha` (Initial Open-Source Foundation · 100% Verified)
> **最近更新**: `2026-11-19`
> **开源仓库**: `https://github.com/JimiZhou/pipibot` (`main`)
> **关联计划**: [全阶段工程开发计划 (`01-DEVELOPMENT-PLAN.md`)](./01-DEVELOPMENT-PLAN.md)

---

## 1. 实时工程进度总览 (Live Progress Dashboard)

| 阶段 (Phase) | 史诗主题 (Epic Theme) | 目标版本 | 周期 | 进度 (Progress) | 状态 (Status) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Phase 0** | 深度研究、系统架构、设计系统与核心脚手架 | `v0.1.0-alpha` | Baseline | `██████████` **100%** | ✅ 100% Verified (GitHub Initial Release) |
| **Phase 1** | macOS 常驻守护进程、Pi SDK、多 Harness 适配器与 4 层 SQLite 记忆 | `v0.2.0-alpha` | Weeks 1–2 | `░░░░░░░░░░` **0%** | 🗓️ Next Up |
| **Phase 2** | $0/月 Cloudflare 边缘隧道、Workers Relay、D1/R2 与 Zero Trust | `v0.3.0-beta` | Week 3 | `░░░░░░░░░░` **0%** | 📋 Planned |
| **Phase 3** | macOS MenuBar & Manus Cue (`⌥Space`) + iOS 原生伴侣端 (`pipibot-ios`) | `v0.4.0-beta` | Weeks 4–5 | `░░░░░░░░░░` **0%** | 📋 Planned |
| **Phase 4** | Devin Outcome Manager、自动评估循环与夜间自我进化/技能合成 | `v0.5.0-rc` | Week 6 | `░░░░░░░░░░` **0%** | 📋 Planned |
| **Phase 5** | `PipiFleet` 多节点扩展 (Linux VPS / Windows WSL2 / ESP32 & RPi IoT) | `v1.0.0` | Weeks 7–8 | `░░░░░░░░░░` **0%** | 📋 Planned |

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

### Phase 1–5: Runtime Implementation Backlog (`0%`)

| Epic ID | 所属阶段 | 关键交付项 (Planned Deliverables) | 状态 |
| :--- | :--- | :--- | :--- |
| **E1.1** | Phase 1 | `pipibot-daemon` macOS `launchd` 服务、Unix Socket IPC、250ms 脉冲广播 | 📋 Planned |
| **E1.2** | Phase 1 | `@mariozechner/pi-coding-agent` SDK 嵌入式集成与扩展安全钩子 | 📋 Planned |
| **E1.3** | Phase 1 | `claude-code` / `codex` / `opencode` 本地 CLI 探测器、适配器与 Routed MCP Bridge | 📋 Planned |
| **E1.4** | Phase 1 | SQLite WAL + FTS5 + `sqlite-vec` 四层记忆持久化及 `SOUL.md`/`USER.md` 同步器 | 📋 Planned |
| **E2.1** | Phase 2 | `cloudflared` 休眠唤醒自愈隧道与 Worker WebSocket/SSE + APNs 中继上线 | 📋 Planned |
| **E2.2** | Phase 2 | D1 Fleet Registry、R2 7 天 TTL 制品上传器与 Cloudflare Access Service Token 鉴权 | 📋 Planned |
| **E3.1** | Phase 3 | macOS MenuBar Popover Studio & Manus Cue (`⌥Space`) 悬浮感知胶囊 | 📋 Planned |
| **E3.2** | Phase 3 | `pipibot-ios` SwiftUI 原生客户端 (120Hz Metal/Canvas Avatar, Dynamic Island, Needs You 滑动卡片, Muse 画布) | 📋 Planned |
| **E4.1** | Phase 4 | `PipiOutcomeEngine` 责任循环引擎、Autonomous Evaluator 与 Sub-Session DAG | 📋 Planned |
| **E4.2** | Phase 4 | `PipiEvolve` 夜间做梦反思、L3 Pi Skill 自动合成与 Evolution Diff 审计卡 | 📋 Planned |
| **E5.1** | Phase 5 | `pipibot-node-linux` (`<15MB` VPS `systemd` 代理) | 📋 Planned |
| **E5.2** | Phase 5 | `pipibot-node-win` (Windows Service + WSL2 双通道) & `pipibot-edge-iot` (RPi / ESP32 MQTT / Home Assistant) | 📋 Planned |

---

## 3. 架构决策记录 (Architectural Decision Records, ADR-001 ~ ADR-008)

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

---

## 4. 变更日志 (Changelog)

### `v0.1.0-alpha` (2026-11-18 ~ 2026-11-19) — Initial Open-Source Foundation & GitHub Release Milestone
- **Release Milestone**: 完成 Phase 0 全量 25 个开源基线文件的跨包契约统一与自动化质量门禁验收（100% Verified），初始化 `main` 分支并发布公开 GitHub 仓库 [`JimiZhou/pipibot`](https://github.com/JimiZhou/pipibot)。
- **Architecture**: 发布 4 份深度架构规范文档（产品愿景与竞品拆解、Pi Core 与多 Harness 路由、$0 Cloudflare 边缘与多端 Fleet、4 层记忆与自我进化引擎）。
- **Design System**: 发布 *"Ambient Soul & Outcome Studio"* 设计规范与零依赖可交互工作台（[`design-system/index.html`](../../design-system/index.html)），完整落地 192 射线轮廓、120Hz 弹簧与 Rodrigues 3D 眼球程序化头像及 Mac/iOS 模拟器。
- **Core & Edge Scaffolding**: 发布 `@pipibot/protocol` 共享类型契约（53 个规范化状态 ID 与 9 表情 1:1 对齐头像引擎）、`@pipibot/core` 路由器/记忆骨架及 `@pipibot/cloudflare-edge` Worker/D1/R2 模板。
- **Roadmap & Governance**: 建立 Phase 0–5 全量开发计划、进度看板、ADR-001~008 架构决策记录、中英文旗舰 README、MIT 协议与贡献指南。
