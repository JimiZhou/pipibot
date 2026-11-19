# Settings Information Architecture & Codex Compact List Card Redesign

Written against: `57e822a7b89ab3a7dbbbf2c5305d0d29fee34848` (+ uncommitted S0–S2 Mac shell working tree)

## Evidence chain

- Surface: `apps/apple/Sources/PipiBotMacApp/PipiSettingsView.swift` (all 1,151 lines) and entrypoints in `PipiBotMacApp.swift:53`, `:111-117`, `:236-245`, `PipiWorkspaceView.swift:2359-2361`, `PipiSessionTimelineCards.swift:588`, `:647`.
- Problem:
  1. **Tangled 4-tab Information Architecture** (`PipiSettingsView.swift:8-33`, `:218-741`):
     - `通用` mixes appearance/language/zoom with Host power management (`保持 Mac 唤醒`), global hotkey (`快捷浮窗 ⌥Space`), and onboarding replay (`重新打开初始化引导`).
     - `Bot 人设` duplicates the Bot management now consolidated in the top-level `Bots` hub (Plan 02), and the file still carries an orphaned 220-line duplicate struct `PipiPersonaEditorSheet` (`lines 931-1151`) superseded by `PipiBotCreatorSheet.swift`.
     - `记忆与隐私` embeds `手机端同步 / Daemon Endpoint` (`lines 666-708`), which is a Host/Runtime connectivity setting unrelated to memory or privacy.
     - `AI 引擎` tacks `默认工作目录` at the bottom and omits an explicit default routing preference (`store.defaultExecutionTarget`).
  2. **Puffy cards & button-crowded engine rows** (`PipiSettingsView.swift:421-524`, `:564-587`, `:854-866`):
     - Both `settingsCard` and `PipiListCard` use `radiusLG = 20pt`, looking bloated and mobile-like.
     - Each LLM provider card renders 4 full icon+text `PipiActionButton`s across its footer (`设为默认`, `测试连接`, `编辑`, red `删除`), creating heavy visual clutter.
     - Each Local CLI Agent uses a tall card with multi-line description + separate footer path.
  3. **Heavy modal presentation** (`PipiSettingsView.swift:81-196`):
     - Uses `.pipiStructuralMaterial()` (`.thickMaterial`) + cobalt-bordered `matchedGeometryEffect` pill in the left rail, clashing with the neutral `#F7F7F8` sidebar + `#FFFFFF` content plane established in Plan 01.
- Design evidence:
  - Direct line-by-line source audit of `PipiSettingsView.swift:1-1151`.
  - User feedback specifically calling out Settings (`侧边栏和设置里面我觉得问题比较多`) and accepting the 4-group IA reorganization (`通用 / 模型与引擎 / 运行环境与同步 / 记忆与数据`), removal of duplicate `Bot 人设` tab, compact grouped list cards (`10pt` radius, `1px` hairlines), and `···` overflow menus for secondary engine actions.
- Owner: `apps/apple/Sources/PipiBotMacApp/PipiSettingsView.swift` (and callers referencing `PipiSettingsTab` in `PipiBotMacApp.swift`, `PipiWorkspaceView.swift`, `PipiSessionTimelineCards.swift`, `PipiShellSubViews.swift`).
- Scope and affected surfaces: Settings modal/view, `PipiSettingsTab` enum, `modelEditorSheet`, and every caller passing a `PipiSettingsTab` case.
- Uncertainty: None; all backing `PipiAppStore` settings state already exists.

## Design decision

Reorganize Settings into 4 crisp, non-overlapping sections presented in a clean neutral light-gray (`#F7F7F8`) rail + pure-white (`#FFFFFF`) grouped-list pane:

1. **4-Tab Clean Information Architecture (`PipiSettingsTab`)**:
   - **`.general` (`通用`)**:
     - Group 1 — **外观与语言**: 语言 (`Picker`), 外观 (`跟随系统 / 浅色 / 深色` segmented), 界面字号 (`− 100% +`).
     - Group 2 — **快捷键**: 全局快捷浮窗 (`⌥Space` + compact `打开浮窗` secondary button), 全局命令面板 (`⌘K` readonly hint), 新建任务 (`⌘N` readonly hint).
     - Quiet bottom action row — `重新打开初始化引导` (ghost button, de-emphasized instead of a full standalone card).
   - **`.aiEngine` (`模型与引擎`)**:
     - Group 1 — **默认策略**: 默认执行路由 (`自动 / 指定模型 / 指定 CLI Agent` compact Picker bound to `store.defaultExecutionTarget`) + 默认工作目录 (compact single row with truncated path + `更改` secondary button).
     - Group 2 — **本地 CLI Agent** (section header + compact `重新探测` ghost button):
       - Single grouped white card with `1px` internal hairline dividers; each row (height ~52pt) shows Agent Name + concise status dot/label (`就绪 / 需登录 / 未安装`) + monospaced binary path on line 2 + trailing `.toggleStyle(.switch)`.
     - Group 3 — **云端与本地模型 API** (section header + compact `+ 添加模型` monochrome primary button):
       - Single grouped white card with `1px` internal dividers; each row shows Provider · Model + subtle `默认` badge (when default) + trailing inline `测试` ghost icon/label button + **`···` overflow `Menu`** containing `设为默认`, `编辑`, Divider, and destructive `删除`. Inline test result feedback appears cleanly beneath the row only when present.
   - **`.runtimeSync` (`运行环境与同步`)** *(replaces the duplicate `.personas` tab)*:
     - Group 1 — **本机大本营 (`This Mac`)**: Host live status (`● 本机 · 在线`), `保持 Mac 唤醒` (`store.bridgeSupervisor.keepAwakeEnabled` switch).
     - Group 2 — **移动端伴侣同步**: `开启手机端同步` (`store.companionSyncEnabled` switch); when enabled, reveals compact Daemon Endpoint field + `刷新` button inside the same grouped card.
   - **`.memoryPrivacy` (`记忆与数据`)**:
     - Group 1 — **个人记忆**: `启用个人记忆` switch + compact `个人背景与偏好` `TextEditor` (`height: 96`, `bgInset`, `radiusSM = 8`).
     - Group 2 — **数据管理**: `清空所有对话` row with destructive `清空` button + existing `confirmationDialog`.

2. **Codex-Grade Visual & Card Discipline**:
   - Left nav rail (`width: 192`, `PipiTokens.bgSidebar` `#F7F7F8`, 1px right `borderSubtle` hairline): compact 32pt nav items using monochrome active fill (`PipiTokens.bgSurfaceHover` `#EFEFF1`, no cobalt border, no drop shadow) + subtle app version footer.
   - Right content plane (`PipiTokens.bgCanvas` `#FFFFFF`, max content width `600pt` centered/left-aligned with generous 24pt padding):
     - Section headers in quiet uppercase/caption `textSecondary` above grouped cards (`radiusMD = 10`, `bgElevated` `#FFFFFF` or subtle `bgSurface` `#F8F8F9` with `1px` `borderSubtle` border, `12–14pt` row padding, `1px` internal `borderSubtle` dividers).
     - Remove `PipiListCard` usage inside Settings where compact grouped rows are clearer (preserving `PipiListCard` in `CanonicalBlocks.swift` for `audit-design-system.mjs` and its other consumers).
   - Delete dead `PipiPersonaEditorSheet` (`PipiSettingsView.swift:931-1151`) after verifying zero remaining references.

## Reuse

- Existing `PipiTokens` (`bgSidebar`, `bgCanvas`, `bgSurface`, `bgSurfaceHover`, `bgInset`, `borderSubtle`, `radiusSM = 8`, `radiusMD = 10`).
- Existing `PipiActionButton`, `PipiGhostIconButton`, `PipiPressButtonStyle`.
- Existing `modelEditorSheet` inside `PipiSettingsView.swift` (updated to `radiusMD = 10` inputs, `bgCanvas` `#FFFFFF` surface, and neutral styling).
- **Local helper inside `PipiSettingsView.swift`**: `settingsGroup(title:trailing:content:)` + `settingsRowDivider` — strictly local to Settings, composing existing `PipiTokens` without adding unnecessary global primitives.

## Changes

1. `apps/apple/Sources/PipiBotMacApp/PipiSettingsView.swift`
   - Change:
     - Replace `PipiSettingsTab.personas` with `PipiSettingsTab.runtimeSync` (`iconName: "desktopcomputer"`, title `运行环境与同步` / `Runtime & Sync`). Keep `.general`, `.aiEngine`, `.memoryPrivacy` raw values intact.
     - Restyle left settings rail (`lines 82-144`) to `width: 192`, flat `PipiTokens.bgSidebar`, compact 32pt rows with monochrome `bgSurfaceHover` active state (removing cobalt stroke & shadow on selected pill).
     - Refactor `generalTab` (`lines 218-385`) into Appearance/Language group, Shortcuts group, and quiet bottom Onboarding reset row (moving `keepAwake` out to `runtimeSyncTab`).
     - Refactor `aiEngineTab` (`lines 389-548`) into 3 clean compact grouped lists: Default Strategy (routing target + workspace folder), Local CLI Agents (compact single-card rows with toggle), and Cloud/Local LLM APIs (compact single-card rows with inline `测试` + `···` overflow menu for Set Default / Edit / Delete).
     - Implement `runtimeSyncTab` combining Local Host summary + `keepAwake` toggle + Mobile Companion Sync (`companionSyncEnabled` + Daemon endpoint moved out of `memoryPrivacyTab`).
     - Trim `memoryPrivacyTab` (`lines 612-741`) to Memory toggle + profile note + Clear All Chats destructive group.
     - Remove unused `editingPersona`, `showNewPersonaSheet`, `pendingDeletePersona` state + sheets from `PipiSettingsView`, and delete dead `PipiPersonaEditorSheet` (`lines 931-1151`).
     - Tighten `settingsCard` to `radiusMD = 10`, `spacing12`, crisp `1px` `borderSubtle`.
   - Preserve:
     - Keychain-backed `PipiLLMProviderConfig` editor (`modelEditorSheet`), live connection test feedback, debounced `personalProfileNote` flush on disappear, `confirmationDialog` for clearing all conversations, and `pipiTextScale` invalidation.
   - Verify: Every tab has strictly cohesive responsibilities, 0 cards have 4-button footers, and `PipiPersonaEditorSheet` is gone with 0 broken references.

2. Callsites referencing `PipiSettingsTab` (verify via repo-wide grep before editing):
   - `apps/apple/Sources/PipiBotMacApp/PipiBotMacApp.swift` (`settingsInitialTab = .general`)
   - `apps/apple/Sources/PipiBotMacApp/PipiWorkspaceView.swift` (Host popover link -> `onOpenSettings(.runtimeSync)`; engine picker `管理 AI 引擎...` -> `onOpenSettings(.aiEngine)`)
   - `apps/apple/Sources/PipiBotMacApp/PipiSessionTimelineCards.swift` (`onOpenSettings(.aiEngine)`)
   - `apps/apple/Sources/PipiBotMacApp/PipiShellSubViews.swift` (`onOpenSettings(.general)`)
   - Change: Ensure no callsite passes removed `.personas` case, and wire the new Host popover link (from Plan 02) directly to `.runtimeSync`.
   - Preserve: `⌘,` shortcut and Settings sheet/view dismissal flow.
   - Verify: Clean compilation across all targets.

## Scope

- Inherit: `PipiSettingsView.swift` and all `PipiSettingsTab` callers in `PipiBotMacApp`.
- Verify: `PipiOnboardingView.swift` (ensure any shared wording or LLM/Local Agent setup patterns remain consistent).
- Exclude: `PipiBotCreatorSheet.swift` (still owned by `Bots` hub and Onboarding); iOS settings views (`PipiIOSCompanionRootView.swift`).

## Validation

- Product: Open Settings via `⌘,` and bottom-left `⚙`; step through all 4 tabs (`通用`, `模型与引擎`, `运行环境与同步`, `记忆与数据`); add/test/set-default/edit/delete an LLM provider via `···` menu; toggle a Local CLI Agent; toggle Keep-Awake and Companion Sync; verify Clear History still asks confirmation.
- Interface: Inspect at `800×560` (min sheet size) in Light & Dark modes, with 0 LLM providers, 3+ LLM providers (long URLs/model IDs), and all 3 Local CLI Agents; verify no button wrapping or truncation.
- System: Confirm 0 raw hex literals in `PipiSettingsView.swift`, 0 references to deleted `PipiPersonaEditorSheet`, and `audit-design-system.mjs` passes.
- Repository:
  - `grep -rn "PipiPersonaEditorSheet\|\.personas" apps/apple/Sources/PipiBotMacApp/` → 0 stale `.personas` settings tab or dead editor references
  - `node scripts/audit-design-system.mjs` → exit 0
  - `cd apps/apple && swift build && swift test` → exit 0

## Stop conditions

- Stop if any test or external module imports `PipiPersonaEditorSheet` or `PipiSettingsTab.personas` (verified via grep: none found in `PipiBotKitTests`, re-verify before deletion).
- Stop if opening Settings from `PipiWorkspaceView` is later migrated to a native macOS `Settings` scene (`Settings { ... }`); keep `PipiSettingsView` independent of sheet presentation chrome (via optional `onClose`) so it works identically in either sheet or standalone window.

## Design documentation

- After acceptance and validation: Update `docs/architecture/06-MAC-NATIVE-APP-GUIDE.md` Settings section to reflect the 4-tab structure (`通用 / 模型与引擎 / 运行环境与同步 / 记忆与数据`) and removal of the redundant `Bot 人设` Settings tab.
