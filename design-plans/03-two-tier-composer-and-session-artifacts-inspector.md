# Two-Tier Devin/Codex Composer, Session Artifacts Inspector & Timeline Polish

Written against: `57e822a7b89ab3a7dbbbf2c5305d0d29fee34848` (+ uncommitted S0–S2 Mac shell working tree)

## Evidence chain

- Surface:
  - Composer: `apps/apple/Sources/PipiBotMacApp/PipiWorkspaceView.swift:2041-2423` and `PipiGroupChatView.swift:602-683`
  - Top toolbar & message stream: `PipiWorkspaceView.swift:383-513`, `:1637-2037`
  - Timeline & error cards: `apps/apple/Sources/PipiBotMacApp/PipiSessionTimelineCards.swift:546-662`
  - Right inspector: `apps/apple/Sources/PipiBotMacApp/PipiBotInspectorView.swift:34-354`
- Problem:
  1. **Composer layout defects & missing agent controls** (verified in rendered screenshot + source):
     - `composerEnginePicker` (`PipiWorkspaceView.swift:2371-2383`) manually embeds `Image(systemName: "chevron.down")` inside a macOS SwiftUI `.borderlessButton` `Menu`, which renders a **double chevron** (`⌄ Claude Code ⌄`).
     - The workspace folder button (`PipiWorkspaceView.swift:2220-2244`) overflows in a 960pt 3-column window and renders as an empty folder icon with clipped/invisible directory name.
     - Low-signal controls (`/` button duplicating typing `/`, vertical `|` divider, and generic chatbot style `均衡` `PipiReplyMode`) occupy prime composer width, while the two core Devin/Codex controls—**Permission/Execution Tier (`只读规划 / 询问执行 / 自动编辑`)** and **Bot Selector**—are absent. In the live screenshot, Claude Code literally failed waiting for approval because permission mode could not be seen or toggled from the composer.
     - Text in the transcript scrolls semi-transparently behind the composer's translucent gradient backdrop (`PipiWorkspaceView.swift:1683-1695`).
  2. **Right Inspector scope confusion & identity repetition** (`PipiBotInspectorView.swift:34-354`):
     - Titled `Bot 详情` yet combines Session artifacts (`计划`, `改动`) with static Bot profile (`编辑 Bot 人设`, `例行任务`, raw English `人设指令`), repeating the Bot name/avatar for a 4th time on the same screen and burning 308pt on empty chat sessions.
  3. **Toolbar alignment & Error Card truncation**:
     - `toolbarContent` (`PipiWorkspaceView.swift:384-513`) bunches `.primaryAction` buttons right next to `.navigation` title in the middle of the window instead of pushing actions to the trailing edge.
     - `PipiActionableErrorCard` (`PipiSessionTimelineCards.swift:580-652`) truncates `打开 AI 引擎设置` to `打开...` in a 3-column window and uses an aggressive bright blue primary button inside a warm peach block.
     - User message cards (`PipiWorkspaceView.swift:1753-1829`) add a redundant `"我"` pill header row above every prompt.
- Design evidence:
  - Live capture & user screenshot showing double chevron on `Claude Code`, empty `📁` icon, truncated `打开...` error CTA, bunched toolbar buttons, text bleeding behind composer, and static English system prompt in right panel.
  - `docs/architecture/08-BOT-RUNTIME-AND-EXPERIENCE-BLUEPRINT.md` §7.1–7.2 (composer `[Bot▾][引擎▾][权限▾]`, inspector strictly for Session `计划 / 改动 / 上下文`).
  - `apps/apple/Sources/PipiBotKit/State/PipiAppStore.swift:528-535`, `:1760`, `:1883-1884` (`effectivePermissionTier` and critical `isApprovalResume` invariant).
- Owner: `PipiWorkspaceView.swift`, `PipiBotInspectorView.swift`, `PipiSessionTimelineCards.swift`, `PipiGroupChatView.swift`, and a clean helper on `PipiAppStore.swift` for composer permission updates.
- Scope and affected surfaces: 1:1 Session stage, Group Chat composer, Right `.inspector`, Top toolbar, and timeline cards.
- Uncertainty: None; all backing models (`PipiPermissionTier`, `PipiExecutionTarget`, `PipiPlanItem`, `PipiFileChange`, `PipiRunRecord`) already exist in `PipiBotKit`.

## Design decision

1. **Codex + Devin Two-Tier Composer** (`PipiWorkspaceView.swift`):
   - **Tier 1 — Inside the crisp white composer box** (`PipiTokens.composerSurface`, `radiusComposer = 14`, `1px` `composerBorder`, solid `#FFFFFF` dock backing so transcript text never bleeds behind it):
     - Attachment chips strip (shown only when attachments exist or drag-targeted).
     - Multi-line input field (`输入任务或消息，Enter 发送，/ 调出命令…`).
     - Bottom action bar — **strictly 4 items** (zero horizontal overflow even at 960pt):
       1. **`+` Unified Menu** (`PipiGhostIconButton` / `Menu` with `.menuIndicator(.hidden)`): `添加文件/图片…` + Divider + slash shortcuts (`/plan 先规划再执行`, `/review 代码审查`, `/summarize 提炼要点`). Removes standalone `/` button and `|` vertical divider (typing `/` in the input still pops up `slashCommandPopover`).
       2. **Permission / Execution Mode Picker** (`只读规划 / 询问执行 / 自动编辑` mapped to `PipiPermissionTier` with clean icon + concise label, replacing `PipiReplyMode` `均衡` from the composer). Uses `.menuIndicator(.hidden)` + single custom `chevron.down` (9pt) so macOS NEVER renders double chevrons.
       3. **Engine Picker** (compact dot + active engine name, `.menuIndicator(.hidden)` + single `chevron.down` — eliminates the double-chevron bug!).
       4. **Send / Stop Circle** (trailing, `30×30`, monochrome `#171717` when `canSend`, `stateError` stop button when running).
   - **Tier 2 — Quiet Codex Metadata Strip directly below the composer box** (`height: 24`, muted 11–12pt text, zero borders/boxes):
     - **Left**: Compact **Bot Picker** (16pt `PipiBotPersonaGlyph` + short Bot name + subtle `chevron.down`). On an empty/new session, switches `store.activePersonaId` (and rebinds the empty draft conversation's `personaId`); inside an active session, allows switching Bot for a new task or viewing the current Bot cleanly.
     - **Right (or adjacent with `·`)**: **Workspace Folder Picker** (`folder` SF Symbol + full last path component, clickable to invoke `chooseWorkspaceFolderInPlace()`, shown whenever a local CLI agent is active or a project folder is bound — never truncated!).
   - **Critical Store Safety Rule (`PipiAppStore.swift:1760`)**:
     - Do **NOT** pass `input.permissionOverride = .autoEdit` directly on normal sends, because `performLocalHostSend` line 1760 currently infers `let isApprovalResume = input.permissionOverride == .autoEdit && explicitConversationId != nil` and skips appending the user message!
     - Instead, expose a clean method `store.setEffectivePermissionTier(_ tier: PipiPermissionTier)` that updates `activeProject.permissionTierOverride` (if the session belongs to a project) or `activePersona.permissionTier` and persists via `saveResidentState()`. (And optionally add an explicit `isApprovalResume: Bool = false` field on `PipiUserInput` in `SessionHostModels.swift` so approval continuation is never inferred ambiguously.)
   - **Group Chat Composer Alignment (`PipiGroupChatView.swift:602-683`)**:
     - Restyle `composerArea` to share the exact same `PipiTokens.composerSurface`, `radiusComposer = 14`, crisp border, and monochrome `#171717` circular send button (while keeping its `@` mention trigger).

2. **Pure Devin Session Artifacts Inspector** (`PipiBotInspectorView.swift`):
   - Rename header from `Bot 详情` to **`任务详情`** (`Session Artifacts` / `任务详情`).
   - Strictly session-scoped 3 tabs: **`计划`** (`Plan`) · **`改动`** (`Changes`) · **`上下文`** (`Context`):
     - `计划`: Session plan checklist + collapsed tool step timeline.
     - `改动`: Session modified files list + inline monospaced Diff viewer.
     - `上下文`: Strictly session runtime context — **Work Directory** (with reveal-in-Finder / change), **Active Engine & Permission Tier** (single compact summary row), **Session Run History** (filtered to current conversation, not all Bot runs), and **Memory Active Status** (`已启用个人记忆` summary).
   - **Remove** from Inspector: static Bot profile card, `编辑 Bot 人设` CTA, `例行任务` CRUD section (migrated to `Bots` hub in Plan 02), and raw English `人设指令` (`systemPrompt`) box.
   - **Default closed on empty/clean sessions**: Keep `store.isInspectorPresented = false` by default (`PipiAppStore.swift:183`); when `planItems` or `fileChanges` are non-empty, display a subtle artifact count badge on the top-right inspector toggle button so users open it on demand (and auto-open when clicking a file row in `PipiFileChangesCard`, which already calls `store.openInspectorForChange`).
   - Background uses `PipiTokens.bgSidebar` (`#F7F7F8` Light) separated from the pure white `#FFFFFF` transcript by a 1px divider.

3. **Toolbar Alignment & Center Transcript Card Polish**:
   - **Toolbar (`PipiWorkspaceView.swift:384-513`)**:
     - Remove the duplicate `square.and.pencil` new-chat button from the top toolbar (now owned by sidebar top `+ 新建任务`).
     - Place session title + optional project chip + running status pill in `.navigation` (leading), and place `停止` (when running) + `任务详情` inspector toggle (with artifact count badge when `planCount + changeCount > 0`) cleanly on the trailing edge using `.automatic` / `.primaryAction` with proper macOS `NavigationSplitView` spacing (verify trailing alignment in SwiftUI `ToolbarItem(placement: .primaryAction)` vs `ToolbarItem(placement: .automatic)` + `Spacer()` inside detail header if macOS unified toolbar groups `.navigation` and `.primaryAction` together).
   - **User Message Turn (`PipiWorkspaceView.swift:1753-1829`)**:
     - Remove the redundant `"我"` capsule row. Render a clean flat light-gray card (`PipiTokens.bgSurface` `#F8F8F9`, `radiusMD = 10`, `1px` `borderSubtle`), with attachment chips only when present and a quiet top-right hover copy button.
   - **Assistant Message Turn (`PipiWorkspaceView.swift:1831-2035`)**:
     - Keep compact Bot glyph + Bot name + muted inline engine text (plain `textMuted` rather than a noisy capsule on every message); keep last-turn Copy/Regenerate actions quiet and monochrome.
   - **Actionable Error Card (`PipiSessionTimelineCards.swift:546-662`)**:
     - Tone down surface to subtle neutral/soft-error tint (`bgSurface` with `stateWarning.opacity(0.35)` border and warning icon header) instead of saturated peach fill.
     - Keep buttons compact and never-truncating: monochrome primary `重试`, secondary `换引擎` (`Menu` with `.menuIndicator(.hidden)` + single chevron), and concise ghost `引擎设置` (shortened from `打开 AI 引擎设置` so it never clips to `打开...`).
   - **Prevent Scroll Bleed Behind Composer (`PipiWorkspaceView.swift:1637-1696`)**:
     - Switch `activeTranscriptStage` from `ZStack` overlay to a clean `VStack(spacing: 0)` where the `ScrollView` sits cleanly above a grounded `#FFFFFF` (`PipiTokens.bgCanvas`) composer footer region (with subtle 12pt top fade mask or clean 1px separator), eliminating semi-transparent text peeking behind the input box.

## Reuse

- `PipiPermissionTier` (`SessionHostModels.swift:5-44` — already has `label(_:)`, `description(_:)`, `iconName`).
- `PipiAppStore.effectivePermissionTier(for:project:)` (`PipiAppStore.swift:528-535`).
- `PipiPlanChecklistCard`, `PipiCollapsedStepsCard`, `PipiFileChangesCard`, `PipiInlineApprovalCard`, `PipiSummaryEvidenceCard` (`PipiSessionTimelineCards.swift`).
- `PipiActionButton`, `PipiGhostIconButton`, `PipiPressButtonStyle` (`CanonicalBlocks.swift`).
- Exemplar for macOS borderless menu without double chevron: SwiftUI `Menu { ... } label: { ... }.menuStyle(.borderlessButton).menuIndicator(.hidden)`.

## Changes

1. `apps/apple/Sources/PipiBotKit/State/PipiAppStore.swift`
   - Change:
     - Add `public func setEffectivePermissionTier(_ tier: PipiPermissionTier)` that updates `activeProject`'s `permissionTierOverride` (if in a project) or `activePersona`'s `permissionTier`, and calls `saveResidentState()`.
     - Add `public func assignActiveConversationPersona(_ personaId: String)` for safely switching the Bot on an empty draft conversation from the composer's bottom metadata strip.
   - Preserve: `performLocalHostResolveApproval` (`line 1672`) approval continuation flow and all existing S0/S1/S2 tests.
   - Verify: Changing permission tier in the composer immediately takes effect on the next `sendPersonalMessage` call AND appends the user message normally (never triggering the `isApprovalResume` branch).

2. `apps/apple/Sources/PipiBotMacApp/PipiWorkspaceView.swift`
   - Change:
     - Refactor `composerDock` (`lines 2101-2423`) into the two-tier layout:
       - Inner dock bottom bar: `+` menu (attachments + `/plan`, `/review`, `/summarize`) -> `permissionTierPicker` -> `composerEnginePicker` (both with `.menuIndicator(.hidden)` and one crisp `chevron.down`) -> `Spacer` -> monochrome Send / Stop circle.
       - Remove `replyModePicker` (`均衡`) and standalone `/` button and vertical divider from `composerDock`.
       - Directly below `composerDock`: quiet 24pt metadata bar showing `composerBotPicker` (left) and workspace folder button (`folder` + full folder name, right/adjacent).
     - Refactor `activeTranscriptStage` (`lines 1637-1697`) from `ZStack` overlapping composer to `VStack(spacing: 0)` (`ScrollView` on top, grounded `composerStack` dock below on solid `PipiTokens.bgCanvas`) so messages never bleed behind the composer.
     - Simplify user `messageRow` (`lines 1753-1829`) by removing the `"我"` pill badge row.
     - Refine `toolbarContent` (`lines 384-513`): remove redundant `square.and.pencil` button; ensure trailing controls (`停止` when active + `sidebar.right` inspector button with artifact badge dot/count) sit cleanly on the trailing edge of the detail pane.
   - Preserve: Drag-and-drop file attachment (`.onDrop`), `/` keyboard typing trigger for `slashCommandPopover`, `Enter` submit, `⌘Z` undo deletion toast, and VoiceOver labels/actions.
   - Verify: Zero double chevrons on any `Menu`; folder name is fully legible at 960pt width; switching `询问后执行` -> `自动编辑` works cleanly in-place without leaving the chat.

3. `apps/apple/Sources/PipiBotMacApp/PipiBotInspectorView.swift`
   - Change:
     - Update header title to `任务详情` (`Session Artifacts`).
     - Set panel background to `PipiTokens.bgSidebar` with crisp segmented control and `10pt` cards.
     - Refactor `contextTabContent` (`lines 225-354`) to show strictly session-scoped context (Workspace folder, Engine + Permission Tier summary, Session Run records for `store.activeConversationId`, Memory status).
     - Remove Bot profile card, `编辑 Bot 人设` button, Routines UI (`addRoutineInlineForm`, `routineRow`, `@State` routine fields), and raw `systemPrompt` box (all now owned by `Bots` hub in Plan 02).
   - Preserve: `planTabContent` and `changesTabContent` (including inline diff viewer and `selectedFileChangeId` selection).
   - Verify: Right panel shows zero Bot bio duplication and closes cleanly by default on new chats.

4. `apps/apple/Sources/PipiBotMacApp/PipiSessionTimelineCards.swift`
   - Change:
     - Update `PipiActionableErrorCard` (`lines 546-662`): restyle card background to calm neutral `PipiTokens.bgSurface` with subtle warning border, keep monochrome primary `重试`, add `.menuIndicator(.hidden)` to `换引擎` menu (fixing double chevron), and shorten the third button label to `引擎设置` (`Engine Settings`) so it never truncates to `打开...`.
     - Align `PipiPlanChecklistCard`, `PipiCollapsedStepsCard`, `PipiFileChangesCard`, and `PipiSummaryEvidenceCard` to `radiusMD = 10`, flat `PipiTokens.bgSurface`, and `1px` `borderSubtle`.
   - Preserve: All interactive actions (`onRetry`, `onSwitchEngine`, `onOpenSettings`, `onSelectChange`, `onResolve`).
   - Verify: Error card renders all 3 action buttons cleanly without ellipsis at 960pt window width (even with Inspector open).

5. `apps/apple/Sources/PipiBotMacApp/PipiGroupChatView.swift`
   - Change:
     - Align `composerArea` (`lines 602-683`) visual surface (`PipiTokens.composerSurface`, `radiusComposer`, crisp border, monochrome `#171717` circular send button) with the 1:1 session composer.
   - Preserve: `@` mention trigger, `mentionAutocompleteStrip`, Swarm mode picker, and task assignment board.
   - Verify: Switching between 1:1 Session and Group Chat feels like one unified desktop app.

## Scope

- Inherit: `PipiWorkspaceView.swift`, `PipiBotInspectorView.swift`, `PipiSessionTimelineCards.swift`, `PipiGroupChatView.swift`, `PipiAppStore.swift`.
- Verify: `PipiQuickBarPanel.swift` (confirm quick bar inline approval/error/send button matches monochrome `#171717` styling from Plan 01).
- Exclude: `PipiCLIAgentParser.swift` and `PipiInferenceEngine.swift` CLI process spawning internals (note: the underlying permission tier already maps to CLI flags via `effectivePermission`).

## Validation

- Product:
  1. Start a new session with Claude Code, toggle Permission Mode directly inside the composer (`只读` -> `询问后执行` -> `自动编辑`), switch workspace folder in the bottom strip, attach a file via `+`, and type `/` to verify slash popover still triggers.
  2. Trigger an error state and verify `重试` / `换引擎` / `引擎设置` all fit cleanly with zero truncation.
  3. Open Inspector (`sidebar.right`) and verify `计划 / 改动 / 上下文` contain only session-scoped artifacts.
- Interface: Inspect at `960×660` (both Inspector closed and Inspector open) and `1440×900` in Light & Dark modes. Confirm 0 double chevrons, 0 clipped labels, and 0 text bleeding behind the composer while scrolling long replies.
- System: Confirm 0 raw hex literals outside `DesignTokens.swift`, and confirm `PipiAppStore.setEffectivePermissionTier` is unit-tested in `PipiBotKitTests`.
- Repository:
  - `node scripts/audit-design-system.mjs` → exit 0
  - `cd apps/apple && swift build && swift test` → exit 0

## Stop conditions

- Stop if macOS `NavigationSplitView` unified toolbar forces `.primaryAction` adjacent to `.navigation` even after adjusting placements; if so, render the session header bar cleanly inside `chatStage` (with `.toolbar(.hidden)` or minimal sidebar toggle only) so leading title and trailing actions align reliably at all widths.
- Stop if `.menuIndicator(.hidden)` is unavailable on the deployment macOS target in `Package.swift`; check `platforms: [.macOS(.v14)]` (`.menuIndicator(.hidden)` is native since macOS 12).

## Design documentation

- After acceptance and validation: Update `docs/architecture/08-BOT-RUNTIME-AND-EXPERIENCE-BLUEPRINT.md` §7.1 to document the two-tier composer (`[+][权限▾][引擎▾] [↑]` + bottom `Bot ▾ · 📁 目录` rail) and pure Session Artifacts inspector.
