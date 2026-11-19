# Monochrome Neutral White-Gray Desktop Surface System

Written against: `57e822a7b89ab3a7dbbbf2c5305d0d29fee34848` (+ uncommitted S0–S2 Mac shell working tree)

## Evidence chain

- Surface: `apps/apple/Sources/PipiBotMacApp/` (main workspace window, sidebar, transcript canvas, inspector, sheets, quick bar, settings) backed by `apps/apple/Sources/PipiBotKit/DesignSystem/DesignTokens.swift` and `CanonicalBlocks.swift`.
- Problem:
  1. Light mode surfaces have a cool blue-slate cast (`vellum150 = #F6F7FA`, `vellum200 = #F1F3F8`, `vellum250 = #EBEEF5`, `inkLightSecondary = #556072`) instead of neutral white / pale gray (Codex / Antigravity / Linear desktop aesthetic).
  2. Pane luminance hierarchy is inverted in rendered screenshots: the left sidebar uses `.thickMaterial` (`CanonicalBlocks.swift:107`), rendering as muddy translucent mid-gray; the center reading canvas uses off-white `bgCanvas` (`#F6F7FA`); and the right inspector uses pure white `bgElevated` (`#FFFFFF`).
  3. Primary controls (`PipiActionButton.tone == .primary`, active tab highlights, send buttons, error retry CTA) use saturated Cobalt Blue (`#2563EB`), visually competing with semantic status colors, file diffs, and multi-persona Bot glyphs.
  4. Card and surface corner radii (`radiusLG = 20`, `radiusMD = 14`) read oversized/mobile-like on desktop surfaces compared to desktop-grade `8–12pt` geometry.
- Design evidence:
  - Live rendered capture of running `dist/PipiBot.app` (960×968 window) and user-provided screenshot showing muddy `.thickMaterial` sidebar, off-white chat canvas, saturated cobalt Retry button, and bluish-gray inset cards.
  - `apps/apple/Sources/PipiBotKit/DesignSystem/DesignTokens.swift:47-118`, `:236-341`, `:427-475`, `:673-679`.
  - `apps/apple/Sources/PipiBotKit/DesignSystem/CanonicalBlocks.swift:98-135`, `:171-271`, `:331-403`.
  - `design-system/design-system.md` (3-tier token governance: `foundations -> theme -> tokens`, zero raw hex outside `DesignTokens.swift`, `>= 4.5:1` light contrast, `32pt` macOS compact button height).
  - `apps/apple/Tests/PipiBotKitTests/PipiBotKitTests.swift:91-98` (unit-tested button & sheet geometry constants).
- Owner: `apps/apple/Sources/PipiBotKit/DesignSystem/DesignTokens.swift` and `apps/apple/Sources/PipiBotKit/DesignSystem/CanonicalBlocks.swift`.
- Scope and affected surfaces: All macOS views in `apps/apple/Sources/PipiBotMacApp/*.swift` and shared SwiftUI primitives in `PipiBotKit`; passively inherited by `apps/apple/Sources/PipiBotIOSUI/` via `PipiTokens`.
- Uncertainty: None for light-mode desktop neutral hierarchy; dark mode should retain crisp neutral graphite parity (`#0F1012` canvas / `#141518` sidebar / `#F3F4F6` primary controls) when system or user preference is `.dark`.

## Design decision

Establish a Codex / Linear-inspired neutral monochrome surface and control hierarchy in `DesignTokens.swift` and `CanonicalBlocks.swift`:

1. **Correct the pane luminance hierarchy (Light Mode)**:
   - Main reading/working canvas (`bgCanvas`) becomes pure white (`#FFFFFF`).
   - Navigation rails (`bgSidebar`, new semantic token used by `PipiStructuralMaterialModifier`) become flat ultra-light neutral gray (`#F7F7F8`) instead of macOS `.thickMaterial`, eliminating muddy wallpaper bleed.
   - Subtle cards on pure white canvas (`bgSurface`) become `#F8F8F9`, hover/active fills (`bgSurfaceHover`) become `#EFEFF1`, inset code/diff wells (`bgInset`) become `#F2F2F4`, and floating popovers/modals (`bgElevated`) become `#FFFFFF` with crisp 1px hairlines (`#171717` at 8% opacity for `borderSubtle`, 15% for `borderStrong`).
2. **Neutralize ink & primary controls**:
   - Replace blue-slate inks (`#11141B` / `#556072` / `#848FA3`) with true neutral graphite inks (`#171717` primary, `#52525B` secondary, `#71717A` muted).
   - Switch `soulPrimary` (primary CTA & active chrome token) to monochrome near-black (`#171717` Light / `#F3F4F6` Dark; `textInverse` `#FFFFFF` Light / `#111214` Dark). Reserve color strictly for semantic states (`stateSuccess`, `stateWarning`, `stateError`, `stateInfo`), diffs, and `PipiPersonaAccent` robot glyphs.
   - Replace Cobalt focus border (`borderFocus`) with restrained neutral graphite (`#171717` at 28% Light / `#FFFFFF` at 28% Dark).
3. **Tighten desktop geometry tokens without breaking tested constants**:
   - Add desktop-specific card radius token `PipiTokens.radiusCardDesktop: CGFloat = 10` and composer radius `PipiTokens.radiusComposer: CGFloat = 14`, and tighten `radiusSM = 8`, `radiusMD = 10`, `radiusLG = 12` for desktop cards while preserving all unit-tested constants (`buttonHeightMobile = 44`, `buttonHeightDesktop = 32`, `sheetTopEdgeCompact = 54`, `sheetTopEdgeExpanded = 102`).
4. **Restrain shadows & specular gloss**:
   - Remove the glossy white top bevel highlight on `PipiActionButton` (`.primary` / `.secondary`) and composer dock in favor of flat 1px architectural borders and minimal soft elevation shadows (`composerShadow` at 5% opacity).

## Reuse

- Existing 3-tier token architecture: `PipiFoundations` -> `PipiThemePalette` -> `PipiTokens` in `apps/apple/Sources/PipiBotKit/DesignSystem/DesignTokens.swift`.
- Existing modifiers and canonical blocks: `PipiStructuralMaterialModifier`, `PipiLiquidGlassModifier`, `PipiActionButton`, `PipiGhostIconButton`, `PipiListCard`, `PipiPressButtonStyle` in `apps/apple/Sources/PipiBotKit/DesignSystem/CanonicalBlocks.swift`.
- **New semantic token justified**: Add `PipiTokens.bgSidebar` (adaptive: Dark `#141518`, Light `#F7F7F8`) because `bgCanvas` (`#FFFFFF`), `bgElevated` (`#FFFFFF` modals), and `bgSurface` (`#F8F8F9` cards) cannot independently distinguish the structural sidebar/inspector rail from cards or pure-white modals. Consumers sharing `bgSidebar`: `PipiStructuralMaterialModifier`, `PipiWorkspaceView.sidebar`, `PipiBotInspectorView`, `PipiSettingsView` left nav, `PipiBotCreatorSheet.templateGalleryPane`.

## Changes

1. `apps/apple/Sources/PipiBotKit/DesignSystem/DesignTokens.swift`
   - Change:
     - Update `PipiFoundations` neutral light scale (`vellum50 = "#FFFFFF"`, `vellum100 = "#F8F8F9"`, `vellum150 = "#F7F7F8"`, `vellum200 = "#EFEFF1"`, `vellum250 = "#F2F2F4"`) and neutral dark scale (`obsidian950 = "#0B0C0E"`, `obsidian900 = "#0F1012"`, `obsidian850 = "#141518"`, `obsidian800 = "#181A1E"`, `obsidian750 = "#22242A"`, `obsidian650 = "#2C2F36"`, `obsidian550 = "#3B3F48"`).
     - Update neutral inks (`inkLightPrimary = "#171717"`, `inkLightSecondary = "#52525B"`, `inkLightMuted = "#71717A"`; `inkDarkPrimary = "#F4F4F5"`, `inkDarkSecondary = "#A1A1AA"`, `inkDarkMuted = "#71717A"`).
     - Add monochrome primary control foundations (`controlLightPrimary = "#171717"`, `controlLightHover = "#27272A"`, `controlDarkPrimary = "#F4F4F5"`, `controlDarkHover = "#E4E4E7"`).
     - Map `PipiTokens.bgCanvas` to `vellum50` (`#FFFFFF`) in Light / `obsidian900` (`#0F1012`) in Dark.
     - Add `PipiTokens.bgSidebar` mapped to `vellum150` (`#F7F7F8`) in Light / `obsidian850` (`#141518`) in Dark.
     - Map `PipiTokens.bgElevated` to `vellum50` (`#FFFFFF`) in Light / `obsidian800` (`#181A1E`) in Dark.
     - Map `PipiTokens.bgSurface` to `vellum100` (`#F8F8F9`) in Light / `obsidian800` (`#181A1E`) in Dark.
     - Map `PipiTokens.bgSurfaceHover` to `vellum200` (`#EFEFF1`) in Light / `obsidian750` (`#22242A`) in Dark.
     - Map `PipiTokens.bgInset` to `vellum250` (`#F2F2F4`) in Light / `obsidian950` (`#0B0C0E`) in Dark.
     - Map `PipiTokens.soulPrimary` to `controlDarkPrimary` (`#F4F4F5`) in Dark / `controlLightPrimary` (`#171717`) in Light, and `PipiTokens.textInverse` to `obsidian900` in Dark / `pureWhite` in Light.
     - Update `borderSubtle` (Light `#171717` @ 0.08, Dark `#FFFFFF` @ 0.08), `borderStrong` (Light `#171717` @ 0.16, Dark `#FFFFFF` @ 0.16), `borderFocus` (Light `#171717` @ 0.28, Dark `#FFFFFF` @ 0.28).
     - Tune composer tokens: `composerSurface` = `#FFFFFF` (Light) / `#181A1E` (Dark), `composerBorder` = `#171717` @ 0.11 (Light), `composerBorderFocused` = `#171717` @ 0.26 (Light), `composerShadow` = `#171717` @ 0.05 (Light).
     - Update `buttonSecondaryBg` = `#FFFFFF` (Light) / `#181A1E` (Dark), `buttonSecondaryHoverBg` = `#F4F4F5` (Light) / `#22242A` (Dark), `buttonGhostHoverBg` = `#171717` @ 0.055 (Light).
     - Tighten radii: `radiusSM = 8`, `radiusMD = 10`, `radiusLG = 12`, `radiusXL = 16` (and add `radiusComposer = 14`).
     - Update `PipiThemePalette.obsidianDark` and `PipiThemePalette.warmVellumLight` to mirror the exact same neutral values.
   - Preserve:
     - All `PipiTokens.buttonHeight*`, `buttonIcon*`, `buttonGap*`, `sheetTopEdge*`, `iconStroke*`, `spacing*`, `textScale` / `scaledFont` APIs, `PipiMotion`, `PipiPersonaAccent` colors, `HarnessProvider` colors, `PipiFoundations` robot hardware palette (`robotLight*` / `robotDark*`), and semantic status colors (`stateSuccess`, `stateWarning`, `stateError`, `stateInfo`, ensuring `>= 4.5:1` WCAG AA contrast on `#FFFFFF`).
   - Verify: Zero raw hex literals outside `DesignTokens.swift`; `PipiTokens.soulPrimary` on `bgCanvas` achieves >17:1 contrast in Light mode and >15:1 in Dark mode.

2. `apps/apple/Sources/PipiBotKit/DesignSystem/CanonicalBlocks.swift`
   - Change:
     - Update `PipiStructuralMaterialModifier` (`CanonicalBlocks.swift:98-110`) to render solid `PipiTokens.bgSidebar` (removing `.thickMaterial` so macOS desktop wallpaper never muddies the sidebar or settings rail).
     - Update `PipiActionButton` (`CanonicalBlocks.swift:216-270`):
       - Remove the glossy top-edge `.overlay(alignment: .top)` white bevel stroke (lines 221–228) and tighten shadow (`radius: isHovered ? 3 : 1, y: 1`, `opacity: tone == .ghost ? 0 : 0.45`).
       - For `.primary`, use `PipiTokens.soulPrimary` (`#171717` Light / `#F4F4F5` Dark) with `PipiTokens.textInverse` text, and subtle hover shift (`opacity(isHovered ? 0.88 : 1.0)` instead of `.brightness(0.04)` which washes out near-black).
       - For `.secondary`, use crisp `buttonSecondaryBg` (`#FFFFFF` Light) + `1px` `borderSubtle`.
     - Update `PipiListCard` (`CanonicalBlocks.swift:395-402`) to use `PipiTokens.radiusMD` (`10pt`) and `PipiTokens.bgElevated` (`#FFFFFF` Light) on `bgSidebar`/`bgCanvas` or `bgSurface` with `1px` `borderSubtle` border (eliminating puffy `20pt` corners).
     - Update `PipiLiquidGlassModifier` (`CanonicalBlocks.swift:70-96`) for floating overlays (`PipiQuickBarPanel`, `PipiCommandPaletteView`, undo toast): keep refined `.ultraThinMaterial` / `bgElevated` (Light `#FFFFFF` @ 0.94 overlay) with crisp `1px` `borderSubtle` border and restrained neutral shadow (`radius: 16, y: 6`).
   - Preserve:
     - All 6 canonical block type names (`PipiListCard`, `PipiSheet`, `PipiFormSheet`, `PipiDock`, `PipiBottomBar`, `PipiEmptyState`) required by `scripts/audit-design-system.mjs`.
     - `PipiButtonDensity.desktopCompact` (`32pt` height, `16pt` icon, `6pt` gap) and `.mobile` (`44pt`).
     - `PipiPressButtonStyle`, `accessibilityReduceMotion`, `accessibilityReduceTransparency`, and `pipiTextScale` invalidation.
   - Verify: Sidebar renders flat neutral `#F7F7F8`, main canvas renders `#FFFFFF`, primary buttons render `#171717` with crisp white text, cards have crisp `10–12pt` corners and 1px hairlines.

3. `apps/apple/Sources/PipiBotMacApp/PipiWorkspaceView.swift` & `PipiBotMacApp.swift` (window/surface alignment)
   - Change:
     - Remove the colored `RadialGradient` wash on `chatStage` empty state (`PipiWorkspaceView.swift:1435-1444`) so the empty canvas remains crisp pure `#FFFFFF` (Light) / `#0F1012` (Dark).
     - In `PipiMacAppDelegate.configureNativeWindowChrome` (`PipiBotMacApp.swift:38-44`), ensure `window.backgroundColor = .clear` is NOT introducing dark tinting behind the toolbar, and keep `.windowToolbarStyle(.unified(showsTitle: false))` cleanly blending with `#FFFFFF` detail / `#F7F7F8` sidebar.
     - Keep `PipiAppStore.themeMode` defaulting to `.system` (or allow clean Light/Dark switching in Settings) with both Light and Dark verified.
   - Preserve: Native `NavigationSplitView`, window minimum size (`960×660`), keyboard shortcuts, and `preferredColorScheme(store.themeMode.colorSchemeOverride)`.
   - Verify: Opening the Mac app in Light mode displays a calm, uniform `#F7F7F8` left sidebar separated by a 1px divider from a crisp `#FFFFFF` center workspace.

## Scope

- Inherit: All views in `apps/apple/Sources/PipiBotMacApp/` (`PipiWorkspaceView`, `PipiBotInspectorView`, `PipiSettingsView`, `PipiShellSubViews`, `PipiSessionTimelineCards`, `PipiGroupChatView`, `PipiMarkdownView`, `PipiBotCreatorSheet`, `PipiProjectEditorSheet`, `PipiQuickBarPanel`, `PipiOnboardingView`, `PipiBotMacApp`) and `apps/apple/Sources/PipiBotIOSUI/`.
- Verify: `PipiBotMarkView.swift` and `PipiAvatarView.swift` (confirm robot chassis/lenses stay crisp on `#FFFFFF` and `#F7F7F8`); `PipiMarkdownView.swift` (confirm code/diff/table `bgInset` `#F2F2F4` contrasts cleanly on `#FFFFFF`).
- Exclude: `apps/ios-web/`, `design-system/pipibot.pen`, `design-system/tokens.css`, `design-system/tokens.dtcg.json` (do not break existing `audit-design-system.mjs` web/pen checks during the Mac-only Swift pass; sync web/pen tokens in a follow-up if desired).

## Validation

- Product: Launch `dist/PipiBot.app` in macOS Light Mode and Dark Mode; confirm every pane, card, button, and code block is immediately legible with Codex / Linear-level calm contrast.
- Interface: Inspect Light Mode, Dark Mode, High Contrast, and Reduce Transparency across empty session, active conversation, error card, inspector, command palette (`⌘K`), quick bar (`⌥Space`), and settings.
- System: Confirm 0 raw hex literals in any Swift file outside `DesignTokens.swift`, and confirm `PipiStructuralMaterialModifier` uses `PipiTokens.bgSidebar` with no `.thickMaterial` wallpaper bleed.
- Repository:
  - `node scripts/audit-design-system.mjs` → exit 0 (`ALL DESIGN SYSTEM GOVERNANCE CHECKS PASSED.`)
  - `cd apps/apple && swift build && swift test` → exit 0 (all `PipiBotKitTests` including geometry assertions pass)

## Stop conditions

- Stop if changing `PipiTokens.soulPrimary` to `#171717` / `#F4F4F5` causes any iOS view in `PipiBotIOSUI` to lose button/icon visibility (if so, verify `textInverse` pairing at that callsite instead of adding hardcoded colors).
- Stop if macOS `NavigationSplitView` overrides the SwiftUI sidebar background with an opaque system tint; if so, apply `.scrollContentBackground(.hidden)` / `.background(PipiTokens.bgSidebar)` at the sidebar container level rather than introducing AppKit private APIs.

## Design documentation

- After acceptance and validation: Update `design-system/design-system.md` (add dated rule recording neutral white `#FFFFFF` canvas + `#F7F7F8` flat sidebar + monochrome `#171717` primary controls for macOS desktop) and update `docs/architecture/08-BOT-RUNTIME-AND-EXPERIENCE-BLUEPRINT.md` §7.4 Material rule (replacing heavy sidebar translucency with flat neutral structural surface `#F7F7F8`).
