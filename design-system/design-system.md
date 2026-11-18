# PipiBot Persistent Design System Memory (`design-system.md`)

> Single source of truth for AI coding & UI agents across `.pen` (`pipibot.pen`), Web (`design-system/`, `apps/ios-web/`), and Native Apple (`apps/apple/`). Every rule below strictly records **one clear sentence + the reason + the date**.

---

## 1. 3-Tier Token Governance (`foundations -> theme -> tokens`)

- **Rule**: Organize all design tokens strictly into three layers: `foundations` (raw palette & primitives), `theme` (12-step `Obsidian Dark` and `Vellum Light` scales), and semantic `tokens` (`bgCanvas`, `bgSurface`, `textPrimary`, `soulPrimary`). **Reason**: Separating raw values from theme steps and semantic roles lets dark and light modes shift cleanly without rewriting view components. *(2026-11-19)*
- **Rule**: Never write raw `#RRGGBB`, `#RGB`, or `0xRRGGBB` color hex literals inside `.pen` component/screen nodes, `apps/ios-web/styles.css`, or SwiftUI views outside `DesignTokens.swift`. **Reason**: Hardcoded colors bypass theme switching and silently break dark/light parity across macOS and iOS. *(2026-11-19)*
- **Rule**: Every variable binding in `design-system/pipibot.pen` must specify a `fallbackColor` that equals the resolved hex value of that token in the active default mode, never `#000000` when the token resolves elsewhere. **Reason**: Mismatched or `#000000` fallback colors corrupt headless rendering and hide broken variable bindings during static audits. *(2026-11-19)*
- **Rule**: Every `TEXT` node in `design-system/pipibot.pen` must bind a registered `textStyleId` from the document's `textStyles` table. **Reason**: Ad-hoc font sizes and line heights cause vertical rhythm drift across the 12 desktop and mobile screens. *(2026-11-19)*

---

## 2. Geometry, Contrast & Vector Craft Rules

- **Rule**: Mobile interactive buttons must measure `44px` in height with `18px` icons and an `8px` internal gap, while macOS compact buttons must measure `32px` in height with `16px` icons and a `6px` internal gap. **Reason**: Touch targets below `44pt` fail Fitts's law ergonomics on iPhone, while `44pt` desktop controls waste macOS MenuBar popover real estate. *(2026-11-19)*
- **Rule**: Sheet overlays (`sheet` and `form-sheet`) must anchor their `topEdge` exclusively at `54px` (expanded top clearance) or `102px` (compact inspection clearance), never any value in between. **Reason**: Arbitrary intermediate sheet offsets collide with the Dynamic Island safe area or create awkward floating dead zones. *(2026-11-19)*
- **Rule**: All brand, harness, and semantic foreground colors on `Warm Vellum` light surfaces (`#F7F5F0`, `#FFFFFF`, `#FDFCF9`) must achieve at least a `4.5:1` WCAG AA contrast ratio. **Reason**: Glowing dark-mode neon hues wash out on warm paper backgrounds and become illegible outdoors on mobile. *(2026-11-19)*
- **Rule**: Vector icons sized `16-18px` must use a `1.5px` stroke weight, while icons sized `20-24px` must use a `1.75px` stroke weight. **Reason**: Scaling a single stroke weight linearly across sizes produces either hair-thin small glyphs or overly heavy toolbar marks. *(2026-11-19)*
- **Rule**: Set `clip: true` on `.pen` frames only when the frame carries visual `effects` (shadows/blur) or defines scrollable overflow (`overflowDirection !== "NONE"`). **Reason**: Unnecessary clipping masks flatten drop shadows, slice focus halos, and obscure subtle edge overflows during review. *(2026-11-19)*

---

## 3. The 6 Canonical Named Blocks

- **Rule**: Build all structured item lists, outcomes, fleet nodes, and memory diffs using the `list-card` block (`16px` outer radius, `12px` inner padding, consistent leading avatar/dot + title/subtitle + trailing telemetry). **Reason**: Hand-rolled row containers drift in padding and vertical alignment across iOS and macOS tabs. *(2026-11-19)*
- **Rule**: Present secondary detail drawers and harness selectors inside the `sheet` block anchored at `topEdge` `54px` or `102px` with a grounded drag indicator. **Reason**: Standardized modal sheets preserve spatial context and prevent jarring full-screen context switches. *(2026-11-19)*
- **Rule**: Capture user inputs such as creating a new Outcome or editing a rule inside the `form-sheet` block pairing labeled inputs with one full-width `44px` primary action button (`32px` on macOS). **Reason**: Grouping fields above one anchored primary CTA eliminates floating submit buttons and ambiguous form exits. *(2026-11-19)*
- **Rule**: Render persistent voice, cue, or live agent state summaries in the `dock` block placing the live `PipiAvatar` and concise status on the left and the single primary action on the right. **Reason**: A consistent left-soul/right-action polarity lets users check agent status and act in one glance without scanning. *(2026-11-19)*
- **Rule**: Anchor top-level mobile navigation and primary view switchers in a grounded full-bleed `bottom-bar` flush to the viewport bottom instead of a floating box-in-box pill card. **Reason**: Grounded bars reclaim vertical viewport space on iOS and avoid awkward double-bordered shadows over scrolling cards. *(2026-11-19)*
- **Rule**: Render empty queues (`Needs You` zero-inbox, empty search) with the `empty-state` block containing strictly one icon, one title, one concise sentence, and at most one primary button. **Reason**: Multi-paragraph empty states with secondary links clutter calm recovery screens and dilute the next step. *(2026-11-19)*

---

## 4. Stageshow Framing & Motion Craft Rules

- **Rule**: Compose cross-device showcase shots using the `device-pair` pattern where the macOS host window fills the upper-left stage and the companion iPhone straddles the right margin over quiet filler rows, never occluding focal metrics. **Reason**: Straddling empty margin links the Mac resident and iOS companion visually while keeping telemetry and diffs unobstructed. *(2026-11-19)*
- **Rule**: Render the `dynamic-island` as a single black pill container whose morphing box geometry animates independently from a separate foreground content layer. **Reason**: Animating container size and foreground labels on separate layers prevents text stretching and jitter during spring expansion. *(2026-11-19)*
- **Rule**: Limit each product frame or stage still to `3-7` focal real text strings (e.g., active outcome, delta metric, decision CTA) while substituting surrounding secondary rows with quiet structural `Bar` placeholders. **Reason**: Filling every row with synthetic lorem text creates visual noise and hides the one payoff the viewer should read first. *(2026-11-19)*
- **Rule**: Never decorate AI features with generic purple sparkle wands or cliché star icons; express intelligence through the living 120 Hz `PipiAvatar`, real R2 before/after evidence, and harness-colored activity pulses. **Reason**: Stock AI sparkles feel derivative and convey nothing about actual autonomous execution or evidence quality. *(2026-11-19)*
