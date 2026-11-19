# Devin Task-First Sidebar, Single-Row Footer & Unified Bots Hub

Written against: `57e822a7b89ab3a7dbbbf2c5305d0d29fee34848` (+ uncommitted S0–S2 Mac shell working tree)

## Evidence chain

- Surface: `apps/apple/Sources/PipiBotMacApp/PipiWorkspaceView.swift` (left sidebar & navigation destinations) and `apps/apple/Sources/PipiBotMacApp/PipiBotHomeSceneView.swift` (Bots hub).
- Problem:
  1. **Sidebar clutter & missing primary CTA** (`PipiWorkspaceView.swift:517-858`): A 268pt column stacks 8 competing blocks (inline search input + redundant `⌘K` pill, `Bot 主页`, `需要你`, `群聊协作` section + dashed empty card, `会话` list, `项目` section + dashed empty card, `BOT 人设` row, and 3 footer rows), while the primary Devin/Codex action (`+ 新建任务`) is absent from the sidebar and buried as a small toolbar icon.
  2. **Bottom-left logic collision & visual noise** (`PipiWorkspaceView.swift:859-943`, ~165pt tall):
     - Clicking a Bot avatar in `BOT 人设` simultaneously mutates `store.selectedBotFilterId` (filtering sessions) AND `store.activePersonaId` (switching the active persona), while editing or starting a chat with a Bot requires discovering a hidden right-click context menu.
     - Bot management is scattered across 4 competing surfaces: top `Bot 主页`, bottom-left `BOT 人设` row, Settings `Bot 人设` tab, and Right Inspector `Bot 详情`.
     - Host status renders a raw emoji (`Text("🖥")`, line 911) as a dead non-interactive row, stacked above standalone `快捷浮窗 ⌥Space` and `设置 ⌘,` rows.
  3. **Incomplete Bots hub** (`PipiBotHomeSceneView.swift`): Currently renders only a full-bleed SceneKit 3D room, lacking structured visibility into Bot permissions, routines, recent runs, or deletion—forcing users back into Right Inspector and Settings.
- Design evidence:
  - User screenshot & live capture of `dist/PipiBot.app` showing empty dashed `新建群聊` and `新建项目` boxes, bloated bottom-left cluster with emoji `🖥`, and 4-way split of Bot controls.
  - Accepted user design decisions aligned against Devin Bot / Codex Desktop: task-first sidebar (`+ 新建任务` + `⌘K` -> `需要你` & `Bots` -> unified task stream + compact `项目`), single-row ~44pt bottom-left footer (`● 本机` clickable popover + `⚙` Settings button), and unified `Bots` card workspace with `卡片 | 3D 空间` toggle.
  - `docs/architecture/08-BOT-RUNTIME-AND-EXPERIENCE-BLUEPRINT.md` §7.1 (global sessions, quiet host badge, unified inbox).
- Owner: `apps/apple/Sources/PipiBotMacApp/PipiWorkspaceView.swift` and `apps/apple/Sources/PipiBotMacApp/PipiBotHomeSceneView.swift` (plus extracted `PipiBotsHubView.swift` if warranted for file clarity inside `PipiBotMacApp`).
- Scope and affected surfaces: Left sidebar, `WorkspaceDestination`, `PipiCommandPaletteView` (`PipiShellSubViews.swift`), and `Bots` destination view.
- Uncertainty: None; all data models (`PipiConversation`, `PipiGroupChat`, `PipiProject`, `PipiBotPersona`, `PipiBotRoutine`, `PipiRunRecord`, `PipiHostDescriptor`) already exist on `PipiAppStore`.

## Design decision

Re-architect Mac navigation around a Devin task-first sidebar, collapse the bottom-left footer into one crisp bar, and consolidate all Bot/routine management into a single `Bots` hub:

1. **Top-to-Bottom Sidebar Hierarchy** (`idealWidth: 252`, `min: 220`, `max: 320`, flat `PipiTokens.bgSidebar` background):
   - **Header Action Row**: Full-width crisp `+ 新建任务` primary/elevated button (`⌘N` hint on right, clicking creates & focuses a new session; right-click or trailing chevron menu allows `+ 新建多 Bot 协作群`) paired with a compact `🔍` search trigger button (`⌘K`) that opens `PipiCommandPaletteView` (eliminating the bulky inline search box + duplicate `⌘K` pill).
   - **Primary Nav (strictly 2 items, 32pt height)**:
     - `需要你` (`tray`, monochrome icon, warning badge count only when `store.totalNeedsYouCount > 0`)
     - `Bots` (`cpu` or `square.grid.2x2`, subtle busy pulse dot when any Bot is running/collaborating) — replaces `Bot 主页` as the single home for all Bots, routines, and the optional 3D space.
   - **Unified Task / Session List (`任务`)**:
     - Section header: `任务` on left; quiet Bot/Type filter menu (`全部 ▾` / specific Bot / 群聊) on right — cleanly replacing the overloaded bottom-left avatar filter!
     - Merge active/recent multi-bot `PipiGroupChat` threads into the same unified task stream (visually distinguished by overlapping mini-avatars or `person.2` glyph + swarm badge) so empty group chats never waste 70pt on a dashed box.
     - Keep time/state grouping (`进行中 / 需要你`, `置顶`, `今天`, `昨天`, `前 7 天`, `更早`) and collapsible `已归档` footer toggle (hidden when 0 archived).
   - **Projects Section (`项目`)**:
     - Single quiet header row: `项目` + `+` ghost icon button (`folder.badge.plus` -> `plus`).
     - When `store.projects.isEmpty`, render **nothing below the header** (remove the 30pt dashed `新建项目` placeholder box completely). When projects exist, render clean collapsible folders with nested session rows.
2. **Single-Row Bottom-Left Footer (~44pt height, separated by 1px `borderSubtle` hairline)**:
   - Remove `BOT 人设` avatar strip, remove standalone `快捷浮窗` row, remove raw `🖥` emoji.
   - Single `HStack` row:
     - **Left**: Clickable **Host Status Button** — 6pt semantic dot (`stateSuccess` online / `stateWarning` degraded / `textMuted` offline) + `store.localHost.displayName(lang)` (`本机`) + muted `· 在线` / engine count. Clicking opens a clean **Host & Quick Actions Popover** showing:
       - Local Host link state (`PipiHostDescriptor`) & Keep-Awake status
       - Connected local CLI agents quick status (Claude Code / Codex / OpenCode ready indicators)
       - One-click `呼出快捷浮窗 (⌥Space)` action
       - Link to `运行环境与同步设置…` (`onOpenSettings(.runtimeSync)`)
     - **Right**: Single compact `PipiGhostIconButton(systemImage: "gearshape")` (`⌘,` tooltip, opens Settings).
3. **Unified `Bots` Hub (Card Workspace Default + `卡片 | 3D 空间` Switcher)**:
   - Clicking `Bots` in the sidebar opens the unified Bots hub (`PipiBotsHubView`, wrapping `PipiBotHomeSceneView` as its 3D mode):
     - **Top Bar**: Title `Bots` + live summary (`4 个 Bot · 1 运行中`), right side segmented switcher (`卡片` | `3D 空间`), `+ 群聊协作` secondary button, and `+ 新建 Bot` primary monochrome button (`#171717`).
     - **Default `卡片` View** (Devin Bot card grid on pure white `#FFFFFF` canvas, 2-column responsive `LazyVGrid`):
       - Each Bot card (`10pt` radius, `1px` `borderSubtle`, `bgSurface`/`#FFFFFF` hover) displays:
         - `PipiBotPersonaGlyph` (36pt) + Bot Name + Live State pill (`待命 / 运行中 / 需要你`)
         - Role 1–2 lines
         - Metadata pills: bound Engine (`Claude Code` / `自动路由`), Permission Tier (`只读 / 询问 / 自动编辑`), Routine count (`0 条例行任务`)
         - Footer actions: `开始任务` (creates/opens session with this Bot), `例行任务` (expands or opens Bot detail sheet/drawer), and `···` overflow menu (`编辑人设`, `拉入群聊`, `删除 Bot` with confirmation dialog).
       - Clicking a Bot card (or its `例行任务` button) opens a clean **Bot Detail & Routines Sheet/Drawer** hosting the Routine list + `addRoutineInlineForm` (migrated from `PipiBotInspectorView.swift:269-523`), recent runs for that Bot, permission tier quick picker, and `编辑 Bot 人设` button.
     - **`3D 空间` View**: Renders the existing `PipiBotHomeSceneView` cleanly inside the detail stage (omitting duplicate title HUD when hosted inside the unified top bar) so existing 3D SceneKit investment is preserved without imposing on daily Devin-style efficiency.

## Reuse

- Existing `PipiBotPersonaGlyph`, `PipiActionButton`, `PipiGhostIconButton`, `PipiSessionStateDot`, `PipiDotIndicator`, `PipiPressButtonStyle`.
- Existing sheets: `PipiBotCreatorSheet`, `PipiGroupCreatorSheet`, `PipiProjectEditorSheet`, `PipiCommandPaletteView`.
- Existing routine creation/list logic from `PipiBotInspectorView.swift:269-523` (relocate into the Bots hub detail drawer/sheet so nothing is duplicated or lost).
- Existing `PipiBotHomeSceneView.swift` as the `3D 空间` tab inside the unified Bots hub.
- Exemplar: `PipiWorkspaceView.swift:1252-1371` (`conversationSidebarRow` hover/context-menu/accessibility pattern).

## Changes

1. `apps/apple/Sources/PipiBotMacApp/PipiWorkspaceView.swift`
   - Change:
     - Rename `.home` destination label in sidebar & toolbar from `Bot 主页` to `Bots` (keep enum case `.home` or rename to `.bots` internally).
     - Replace lines 520–638 (top search box + nav) with:
       - Compact top bar: `+ 新建任务` primary action button (`height: 32`, `radiusSM`, `bgElevated` `#FFFFFF` with `1px` border + subtle shadow or monochrome `#171717` CTA) with trailing menu or split option for `+ 新建群聊`, plus a `32×32` `magnifyingglass` button (`⌘K`) that sets `store.isCommandPalettePresented = true`.
       - Two clean nav rows (`需要你` with badge, `Bots` with active dot).
     - Replace lines 643–698 (standalone `群聊协作` section with dashed empty box) by merging `store.sortedGroupChats` into the unified `任务` section (or showing a unified sorted feed / compact `群聊` subsection ONLY when `!store.groupChats.isEmpty`). Add a subtle filter `Menu` (`全部` / individual Bots / `仅群聊`) on the `任务` header trailing edge.
     - Replace lines 825–847 (`if store.projects.isEmpty` dashed box) with `EmptyView()` so an empty `项目` section occupies only its single 24pt header + `+` button.
     - Replace lines 859–943 (the entire 165pt bottom-left `BOT 人设` + `🖥` + `快捷浮窗` + `设置` block) with a single ~44pt footer row:
       - Leading: Host status pill button (`Circle` 6pt + `store.localHost.displayName(lang)` + muted link state) with `.popover(isPresented: $showHostPopover)` containing local Host/CLI status, `快捷浮窗 (⌥Space)` button (`onToggleQuickBar`), and `运行环境设置…` button.
       - Trailing: `PipiGhostIconButton(systemImage: "gearshape", accessibilityLabel: s.settings)` triggering `onOpenSettings(.general)`.
     - Remove `sidebarSearchQuery` inline TextField if search is unified into `⌘K` (or keep optional filter inside `⌘K` palette so sidebar stays clean and uncluttered).
     - Remove `botAvatarChip` and `sidebarFooterRow` helper methods once replaced.
   - Preserve:
     - Context menus (Pin / Rename / Move to Project / Archive / Delete with `⌘Z` undo toast) and VoiceOver `.accessibilityAction`s on all conversation, group chat, and project rows.
     - Confirmation dialog before deleting a Bot (`pendingDeletePersona`).
     - `NavigationSplitView` collapse/resize support (`⌃⌘S` via `SidebarCommands()`).
   - Verify: Sidebar bottom chrome is strictly 1 row (~44pt), zero emojis appear in sidebar chrome, empty Projects/Groups show zero dashed boxes, and `+ 新建任务` is immediately clickable at top-left.

2. `apps/apple/Sources/PipiBotMacApp/PipiBotsHubView.swift` (new view file inside `PipiBotMacApp`, paired with `PipiBotHomeSceneView.swift`)
   - Change:
     - Build `PipiBotsHubView` hosting a clean `#FFFFFF` top header (`Bots`, summary subtitle, segmented `卡片 | 3D 空间` picker, `+ 群聊协作`, `+ 新建 Bot`).
     - Implement the `卡片` mode as a clean 2-column grid of Bot cards (`radiusMD = 10`, `1px` `borderSubtle`) showing avatar, live state, role, engine label, permission tier badge, routine count, `开始任务` button, `例行任务` button, and `···` menu (`编辑人设`, `发起群聊`, `删除 Bot`).
     - Implement an inline side sheet / modal (`PipiBotDetailSheet` or collapsible right pane within `Bots`) that hosts that Bot's Routines (`addRoutineInlineForm` + `routineRow` migrated from `PipiBotInspectorView`), quick Permission Tier segmented picker, recent run history for that Bot, and `编辑人设` trigger.
     - In `3D 空间` mode, embed `PipiBotHomeSceneView` (pass a flag `showTopHUD: false` so its floating `Bot 主页` HUD doesn't duplicate `PipiBotsHubView`'s clean header).
   - Preserve: All `PipiBotHomeSceneView` 3D SceneKit interactions (orbit, zoom, click bot, quick prompt, reset camera) when switched to `3D 空间`.
   - Verify: Users can create, edit, delete, configure routines, inspect permissions, start 1:1 tasks, or start multi-bot groups from one single `Bots` hub.

3. `apps/apple/Sources/PipiBotMacApp/PipiShellSubViews.swift` (`PipiCommandPaletteView`)
   - Change:
     - Update the `"bot_home"` command title/subtitle from `Bot 主页 / 3D 温馨主页` to `Bots / 管理 Bot 团队、例行任务与 3D 空间`.
     - Ensure selecting a Bot in `⌘K` opens/filters cleanly without relying on the removed bottom-left avatar strip.
   - Preserve: Keyboard navigation (↑/↓/↩/Esc), full session/group/bot/command search.
   - Verify: Pressing `⌘K` or clicking the sidebar search button opens the palette and navigates cleanly to `Bots`, `需要你`, or any session.

## Scope

- Inherit: `PipiWorkspaceView.swift`, `PipiBotsHubView.swift`, `PipiBotHomeSceneView.swift`, `PipiShellSubViews.swift`.
- Verify: `PipiBotMacApp.swift` keyboard shortcuts (`⌘N` new task, `⌘K` command palette, `⌘,` settings, `⌘1..⌘4` persona switching — update `⌘1..⌘4` so switching persona selects/creates or updates the active Bot cleanly without conflicting with a hidden filter).
- Exclude: `PipiBotHome3DEngine.swift` internal SceneKit geometry/lighting (no 3D engine rewrite required); iOS app navigation (`PipiIOSCompanionRootView.swift`).

## Validation

- Product: Complete full workflows without touching Settings or right-clicking hidden controls: create a new task (`+ 新建任务`), switch to `Bots` and add a Routine to a Bot, toggle `卡片 | 3D 空间`, filter tasks by Bot in the `任务` header, open Host popover at bottom-left and summon Quick Bar (`⌥Space`), open Settings via bottom-left `⚙`.
- Interface: Verify at `960×660` (min window) and `1440×900` in Light & Dark modes, with 0 projects, 0 group chats, 10+ sessions, and 6+ Bots.
- System: Confirm no raw hex literals, no emoji icons (`🖥`) in navigation chrome, and every icon-only button (`+`, `🔍`, `⚙`, `···`) has `.accessibilityLabel` and `.help`.
- Repository:
  - `node scripts/audit-design-system.mjs` → exit 0
  - `cd apps/apple && swift build && swift test` → exit 0

## Stop conditions

- Stop if `PipiBotInspectorView.swift` still depends on routine state before Plan 03 runs; keep routine helper methods cleanly factored so Plan 02 and Plan 03 do not leave duplicate routine UIs.
- Stop if adding `PipiBotsHubView.swift` requires `Package.swift` source list edits (check `apps/apple/Package.swift` — SwiftPM auto-discovers files under `Sources/PipiBotMacApp/`).

## Design documentation

- After acceptance and validation: Update `docs/architecture/08-BOT-RUNTIME-AND-EXPERIENCE-BLUEPRINT.md` §7.1 ASCII layout to reflect `+ 新建任务`, `Bots` hub, unified `任务` stream, and single-row `● 本机 | ⚙` footer.
