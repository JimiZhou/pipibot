# 03 · PiPiBot 对标 `simplexai-labs/linger` 能力提升主执行计划（Wave 1 – Wave 5）

> **状态**：`✅ 12/12 全部定稿 · Wave 1 – Wave 5 全部完成并全量验收 (100% Verified)`
> **基准日期**：`2026-11-20`
> **参考上游项目**：[`simplexai-labs/linger`](https://github.com/simplexai-labs/linger) · [`simplexai-labs/PolyStrata`](https://github.com/simplexai-labs/PolyStrata)
> **关联蓝图**：[`08-BOT-RUNTIME-AND-EXPERIENCE-BLUEPRINT.md`](../architecture/08-BOT-RUNTIME-AND-EXPERIENCE-BLUEPRINT.md) · [`02-PROGRESS-TRACKER.md`](./02-PROGRESS-TRACKER.md) · [`NOTICE`](../../NOTICE)

---

## 1. 开源协议与洁净室实现规范（License & Clean-Room Policy）

在借鉴吸收上游优秀开源项目能力时，PiPiBot 严格执行以下开源合规与署名铁律（完整声明见根目录 [`NOTICE`](../../NOTICE)）：

1. **保持 PiPiBot 100% MIT 协议纯净**：`simplexai-labs/linger` 使用 *Linger Open Source License*（基于 Apache 2.0 并附带托管服务及前端 Logo 保留条款），而 PiPiBot 使用 [MIT License](../../LICENSE)。
2. **严格洁净室实现（Zero Verbatim Copy）**：绝不直接复制粘贴 Linger 的源代码、Prompt 原文、前端组件、图标或素材；所有吸收项均基于其公开架构理念，面向 PiPiBot 的 **原生 Swift 6 + 轻量 TypeScript + \$0/月 Cloudflare 架构** 从零独立设计与实现。
3. **透明上游署名**：在 [`NOTICE`](../../NOTICE)、[`README.md`](../../README.md)、[`README.zh-CN.md`](../../README.zh-CN.md)、本路线图以及每个受启发模块的文件头注释中明确标注架构灵感来源与协议边界。
4. **外部可选 MIT 后端兼容**：Wave 4 集成的 [`simplexai-labs/PolyStrata`](https://github.com/simplexai-labs/PolyStrata) 为标准 **MIT License**，采用外部运行时适配接入并保留其 MIT 版权声明。

---

## 2. 12 项定稿能力矩阵（已逐项讨论确认）

| 编号 | 能力项 | 状态 | 定制化落地约束 | 归属波次 |
| :--- | :--- | :---: | :--- | :---: |
| **`#01`** | 个人实体 Wiki + 双通道零向量检索 + SQLite WAL | ✅ Verified | **个人向 Wiki**（`People / Projects / Topics / Life / Repos`，非商务向）；SQLite WAL + FTS5 + CJK bigram + 最多 6 改写词 + 软时间窗 RRF（`sqlite-vec` 可选增强） | **Wave 2** |
| **`#02`** | Per-Bot 独立经验记忆 + Prompt Cache 友好注入 | ✅ Verified | **完整采用 Linger 节奏**：每 5 次成功运行提炼候选 → 空闲 6 小时或压缩时合并去重（>64KB/30会话提前合并）；`summary.md` 仅作首条/压缩后消息隐藏附注，绝不修改 System Prompt | **Wave 2** |
| **`#03`** | 主动智能体防打扰护栏 + Clue→Rule 夜间自学习 | ✅ Verified | **第一批仅接 macOS 原生源**（`EventKit` 日历/提醒事项、本地 Git/FS、设备状态、聊天/随手记）；**支持 `Prepare` 提前备料**；静音窗 22:00–08:00、每日限额、静默 3 分钟推送、14 天 `seen>=2` 升格规则（上限 20 条可回滚） | **Wave 2** |
| **`#04`** | 优先级模型调度器 + 交互保留槽位 + 可抢占续跑 + AIMD | ✅ Verified | 7 级优先级队列 + 交互保留槽位 `soft = max(1, hard - 1)` + AIMD 延迟/429 退避 + 统一重试纠错；**启用可恢复 CLI Session 抢占后自动 `--resume` 续跑** | **Wave 1** |
| **`#05`** | Meta / AlterEgo 会话内后台分身委派 | ✅ Verified | **自主委派为主**（Meta 通过工具判断耗时任务派生 AlterEgo 后台并行）；独立 `playground/<task-id>/` 且同会话只读互通；支持中途追加指令、实时步骤展开、单独取消/恢复 | **Wave 3** |
| **`#06`** | 结构化 `team.md` 多 Bot 协作协议 | ✅ Verified | **全量支持 5 种拓扑**（`classify-and-act`、`fan-out-and-synthesize`、`adversarial-verification`、`tournament`、`loop-until-done`）+ DAG 依赖校验 + **支持动态发起拉入/新建角色 Bot 审批** | **Wave 3** |
| **`#07`** | 硬件 Model Autopilot + PolyStrata 集成 + 本地统一 Gateway | ✅ Verified | Apple Silicon 硬件/内存 64K+ 规划与真实问答自测；**集成 `PolyStrata`**（Mac 支持 Metal+SSD 预取 beta 并搭配 `llama.cpp` Metal/Ollama/MLX 全模型兜底，Linux/Win `PipiFleet` 解锁全量 12 模型）；**本地 Gateway 通过隔离配置环境反向注入 CLI Agent**（不污染个人 `~/.claude`/`~/.codex` 配置） | **Wave 4** |
| **`#08`** | 规则 + 独立 LLM 双层风控裁判 + 写操作幂等 | ✅ Verified | 静态规则 + 高危动作独立 LLM `Risk × Authorization` 裁判（严格隔离可信/不可信防 Prompt Injection，`critical` 硬熔断 `deny`，外部写带 `operation_id` 幂等）；**支持多粒度审批**（本次允许 / 本会话同类允许 / 加入项目或长期白名单 / 拒绝并附注） | **Wave 1** |
| **`#09`** | Computer Use（已登录 Chrome + macOS 桌面操控） | ✅ Verified | **双阶段全部支持**：Phase A 本机已登录 Chrome 协同（独立 Seat/Tab、密钥仅留本机）；Phase B macOS Accessibility/Cua 元素树操控；屏幕单车道 + 浏览器独立车道 + **人类切窗立即停手礼让** + Write-Ahead Journal 防重复点击 | **Wave 5** |
| **`#10`** | 个人日常语音交互（非会议场景，赋能 Muse & QuickBar） | ✅ Verified | **面向个人日常语音交互**（口述输入 Dictation + Muse 免提对话/随时打断 + 一句话语音派活，不做重型会议纪要套件）；**端侧优先**（Apple Speech / WhisperKit / MLX + 本地 VAD 播音防回声打断门控），**同时支持配置云端语音 API**（BYOK） | **Wave 4** |
| **`#11`** | 统一 `pipibot` CLI + 内置版本化办公技能 + 每日随手记 | ✅ Verified | **三项全部纳入**：① 单点定义同源生成 `--help`/`--schema`/权限清单的 `pipibot` CLI；② 内置版本化只读投影办公/日常技能包（SHA-256 校验）；③ 每日随手记（静默 5 分钟提炼待办）+ 可编辑产物文档 | **Wave 3** |
| **`#12`** | 跨端 Schema 单一事实来源 + 结构化输出铁律 + 离线确定性验收 | ✅ Verified | Host Protocol v2 共享 JSON Schema 校验（TS ↔ Swift 零漂移）；核心逻辑严禁靠自然语言正则驱动（Structured Output 优先、多语言无关）；本地确定性 Fixture 测试替身与旅程验收门禁 | **Wave 1** |

---

## 3. 五波次工程拆解与验收标准

### Wave 1：调度、安全与契约地基（`#12` + `#04` + `#08`）
- **`#12` 跨端契约与确定性测试**：
  - `packages/protocol/schema/host-v2.schema.json` 作为 TS/Swift 共享枚举与数据结构事实来源。
  - `scripts/audit-protocol-parity.mjs` 纳入 `npm run verify`，自动校验 TS (`packages/protocol/src/index.ts`) 与 Swift (`apps/apple/Sources/PipiBotKit/`) 1:1 精确对齐及洁净室署名头完整性。
- **`#04` 优先级模型调度器 (`PipiModelScheduler`)**：
  - 落地于 `apps/apple/Sources/PipiBotKit/Runtime/PipiModelScheduler.swift` 与 `packages/core/src/model-scheduler.ts`。
  - 7 级优先级（`approvalReview` > `voiceInteractive` > `chatInteractive` > `delegatedTask` > `proactiveRoutine` > `compaction` > `backgroundMemory`）+ 交互保留槽位 `soft = max(1, hard - 1)` + AIMD 延迟/429 退避 + 统一重试/Schema 纠错 + 可恢复 CLI Session 抢占让渡与自动 `--resume` 续跑。
- **`#08` 双层风控裁判与多粒度审批 (`PipiPermissionGuardrail`)**：
  - 落地于 `apps/apple/Sources/PipiBotKit/Runtime/PipiPermissionGuardrail.swift` 与 `packages/core/src/permission-guardrail.ts`，并接入 `PipiAppStore`、`PipiInlineApprovalCard`、`PipiSettingsView` 与 `RoutedMcpBridge`。
  - Layer 1 静态规则 + `critical` 硬熔断（密钥外发、破坏审批规则、毁灭性删除强制 `deny`）+ `operation_id` 写幂等账本；Layer 2 高危动作独立 LLM `Risk × Authorization` 裁判（严格隔离可信/不可信防 Prompt Injection，失败默认安全阻断为 `needs_approval`）；审批卡支持多粒度授权（本次允许 / 本会话同类允许 / 加入项目或长期白名单 / 保持只读拒绝）并在设置页支持审计与一键撤销。

### Wave 2：个人知识 Wiki、Per-Bot 独立记忆与原生主动性（`#01` + `#02` + `#03`，✅ Verified）
- **`#01` 个人向实体 Wiki + 双通道零向量检索 (`PipiPersonalWikiStore`)**：
  - 落地于 `apps/apple/Sources/PipiBotKit/Runtime/PipiPersonalWikiStore.swift`（原生 Apple `SQLite3` WAL + `FTS5` `bm25()`）与 `packages/core/src/personal-wiki.ts`（Node `node:sqlite` WAL + 自动 FTS5 探测与 SQLite BM25 倒排兜底）。
  - 严格个人向分类（`people` / `projects` / `topics` / `life` / `repos`）、原子 Markdown 磁盘投影（YAML Frontmatter + 密钥脱敏）、CJK bigram 扩展、最多 6 个同义改写词、独立 `chunks` / `facts` / `summaries` 通道与软时间窗 RRF（零向量调用默认开启）。
- **`#02` Per-Bot 独立经验记忆与 Prompt Cache 安全召回 (`PipiBotMemoryEngine`)**：
  - 落地于 `apps/apple/Sources/PipiBotKit/Runtime/PipiBotMemoryEngine.swift` 与 `packages/core/src/bot-memory.ts`，并接入 `PipiAppStore`（含 `compactConversation` 与 `/compact`）。
  - 严格按 Bot 隔离 `bots/<botId>/memory/{summary.md, candidates.json, state.json}`；每 5 次成功运行提炼候选 → 6h 空闲 / 会话压缩 / >64KB / >=30 会话自动合并去重；`summary.md` 仅在会话首条或压缩后作为出站用户消息隐藏附注注入，**绝不改动 System Prompt，保护 KV Prompt Cache**。
- **`#03` macOS 原生主动感知、防打扰护栏、Prepare 备料与 `Clue → Rule` 夜间自学习 (`PipiProactiveEngine` + `PipiMacNativeSignalCollector`)**：
  - 落地于 `apps/apple/Sources/PipiBotKit/Runtime/PipiProactiveEngine.swift`、`PipiMacNativeSignalCollector.swift`、`packages/core/src/proactive-engine.ts` 与原生桌面端 `PipiKnowledgeHubView.swift` / `PipiSettingsView.swift` / `PipiBotInspectorView.swift`。
  - 首批接入 macOS 原生源（`EventKit` 日历/提醒事项、本地 Git/FS、Mac 设备遥测、对话/笔记）；强制夜间静音窗（22:00–08:00）、每日提醒上限、对话静默 3 分钟退让与日级 SHA-256 去重；支持只读 `Prepare` 提前备料（自动关联个人 Wiki 上下文）；反馈累计 14 天内 `seen >= 2` 自动升格规则（上限 20 条，支持版本快照一键回滚）。

### Wave 3：高阶协同与工具生态（`#05` + `#06` + `#11`，✅ Verified）
- **`#05` Meta / AlterEgo 会话内自主后台分身委派 (`PipiAlterEgoCoordinator`)**：
  - 落地于 `apps/apple/Sources/PipiBotKit/Runtime/PipiAlterEgoCoordinator.swift`、`packages/core/src/alter-ego.ts` 与桌面端 `PipiAlterEgoBarView.swift`。
  - 支持 Meta 回复内嵌 `<pipibot_delegate>` 自主派生与 `/delegate` 手动触发；独立可写 `sessions/<sessionId>/playground/<taskId>/` + 同会话兄弟任务只读互通（跨会话与路径穿越严格阻断）；支持中途追加 Steer 指令、实时步骤展开、单独取消与保留产物恢复，走 `PipiModelScheduler`（`.delegatedTask` 优先级）。
- **`#06` 结构化 `team.md` 全量 5 模式多 Bot 协作协议与动态拉人/建 Bot 审批 (`PipiTeamProtocol`)**：
  - 落地于 `apps/apple/Sources/PipiBotKit/Runtime/PipiTeamProtocol.swift`、`packages/core/src/team-protocol.ts`、`PipiGroupInspectorView.swift` 与 `PipiNeedsYouInboxView`。
  - 纯函数多错误一次性校验器 + Kahn DAG 拓扑波次/环路校验；完整执行 5 种拓扑（`classify-and-act`、`fan-out-and-synthesize`、`adversarial-verification`、`tournament`、`loop-until-done`）；当协议引用缺失角色/Bot 时自动生成 `PipiDynamicBotProposal`（`invite_existing` / `create_and_invite`）审批卡，批准后自动拉入或新建角色 Bot 入群。
- **`#11` 统一 `pipibot` CLI + 内置版本化办公技能包 + 每日随手记与可编辑文档**：
  - 落地于 `packages/core/src/pipibot-cli.ts`（`npm run pipibot` 单点注册表同源生成 `--help` / `--schema` / `--permissions` + `--operation-id` 写幂等）、`builtin-skills.ts` & `PipiBuiltinSkillsRegistry.swift`（8 套内置技能 `0444` 只读投影 + SHA-256 完整性防篡改自愈）、`pocket-notes.ts` & `PipiPocketNotesEngine.swift`（每日随手记静默 5 分钟提炼/对账 Tracking Items + 带修订号/SHA-256 的可编辑产物文档与一键同步 Wiki）。

### Wave 4：本地模型栈（PolyStrata + Gateway）与个人日常语音（`#07` + `#10`，✅ Verified）
- **`#07` 硬件 Model Autopilot + `PolyStrata` (MIT) 集成 + 本地统一 LLM Gateway & CLI 隔离反向注入**：
  - 落地于 `packages/core/src/model-autopilot.ts`、`packages/core/src/local-llm-gateway.ts`、`apps/apple/Sources/PipiBotKit/Runtime/PipiModelAutopilot.swift`、`PipiLocalLLMGateway.swift`、`PipiInferenceEngine.swift` 与 `PipiSettingsView.swift`。
  - 5 层硬件自适应规划器（探测 Apple Silicon / 内存 / 剩余磁盘 / 64K–128K KV 池与伴随模型余量）、16 模型目录（含 12+ `PolyStrata` MIT MoE 模型，覆盖 Mac Metal+SSD 预取 beta 与 Linux/Win `PipiFleet` GPU+RAM/SSD 分页 + `llama.cpp`/Ollama/MLX 兜底）、强制真实问答自测门禁（仅通过确定性问答与 tok/s 检测后标为 `verified`）。
  - 仅监听 `127.0.0.1` 回环地址的统一 HTTP Gateway（Node `http.Server` & Swift `Network.framework` `NWListener`），支持 Bearer/`x-api-key` 鉴权与 OpenAI `/v1/chat/completions` ↔ Anthropic `/anthropic/v1/messages` 双向 JSON/SSE 协议互转；通过 `0700`/`0600` 独立目录生成 `CLAUDE_CONFIG_DIR` / `CODEX_HOME` / `PI_CODING_AGENT_DIR` / `OPENCODE_CONFIG_DIR` 隔离环境叠加层反向注入 CLI Agent，零污染 `~/.claude` 与 `~/.codex`。
- **`#10` 个人日常语音交互（端侧优先 + BYOK 云端语音 API + 本地 VAD 防回声打断）**：
  - 落地于 `packages/core/src/voice-engine.ts`、`apps/apple/Sources/PipiBotKit/Runtime/PipiDailyVoiceEngine.swift`、`PipiMuseVoiceBarView.swift`、`PipiWorkspaceView.swift`、`PipiQuickBarPanel.swift` 与设置页独立 `Daily Voice` Tab。
  - 聚焦个人日常三大场景（口述输入 Dictation、Muse 免提对话、一句话派活 Voice-to-Task，接入 `.voiceInteractive` 高优先级槽位）；支持本地 RMS+ZCR 动态底噪与播音期回声门控打断（`PipiEchoGatedVAD`）；默认端侧优先（Apple `SFSpeechRecognizer(onDevice)` / `AVSpeechSynthesizer` / WhisperKit / MLX Audio），同时支持配置 OpenAI / Deepgram / ElevenLabs / 自定义 BYOK 云端语音 API（密钥仅存 macOS Keychain），`on_device_only` 模式下硬阻断一切云端外发。

### Wave 5：Computer Use 双阶段能力（`#09`，✅ Verified）
- **Phase A（已登录 Chrome 协同）**：落地于 `packages/core/src/computer-use.ts` 与 `apps/apple/Sources/PipiBotKit/Runtime/PipiComputerUseEngine.swift`；支持 `signed_in_chrome_seat`（每 Agent 独立 Seat/Tab 复用本机登录态，密钥仅留本机）与 `isolated_profile`；禁止任意页面脚本注入（`javascript:`）；只读快照与草稿输入顺滑放行，提交/发送/外发按钮经 `#08` 双层风控审批。
- **Phase B（macOS Accessibility / Cua 元素树 + 双车道 + 礼让 + WAL）**：原生 `AXIsProcessTrusted()` / `AXUIElement` 元素树探测与 `NSWorkspace.didActivateApplicationNotification` 焦点监听；桌面全局单车道（等待在途前景浏览器调用落定）+ 每 Agent 独立并行浏览器车道；人类切窗或点击「人工接管」毫秒级触发 `yielded_to_human` 停手礼让；Write-Ahead Journal 写前日志防止重试重复点击，不确定结果（`unknown_outcome`）立即锁车道直至人类核查解锁；同步落地 `PipiComputerUseBarView.swift`、`/computer` 命令与设置页 `runtimeSync` 控制面板，并扩展 `pipibot computer journal / unlock-lane` CLI。
