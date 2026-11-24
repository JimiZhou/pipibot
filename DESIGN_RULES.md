# PiPiBot Design Rules (`DESIGN_RULES.md`)

> Read this file before touching any UI in `apps/apple/`, `apps/ios-web/`, or `design-system/`.
> Inspired by Elia Kuratli's *Unslop your UI* discipline and Vercel Board's calm coordination surfaces.
> Every line below is a concrete decision — not a vibe word.

---

## Never

- **No sparkle or magic-wand icons** (`sparkles`, `sparkles.*`, `wand.and.stars`) anywhere in buttons, tabs, cards, or empty states.
- **No icons inside tinted rounded boxes** (e.g. `24×24` / `28×28` colored rounded squares wrapping SF Symbols or checkmarks in circles). Use bare monochrome glyphs or a single `6px` semantic status dot.
- **No nested cards (box-in-box)**: never wrap bordered cards inside another bordered rounded container (e.g. bordered Kanban column wrapping bordered task cards, or outer card wrapping inner card).
- **No decorative pills or pill spam**: never put 3+ metadata pills on one card or wrap static status text in colored capsules. Use quiet inline `·` separated metadata text and plain `6px` status dots.
- **No bold (`700`) or semibold (`600`) spam**: Regular (`400`) and Medium (`500`) weights only across UI chrome, headings, cards, labels, and CSS. Build hierarchy through size, spacing, and `textPrimary` vs `textSecondary` contrast.
- **No all-caps labels or eyebrow headers** (no `.textCase(.uppercase)`, no `.uppercased()` on UI copy, no `text-transform: uppercase`). Sentence case everywhere.
- **No gradients or glow** on UI surfaces, buttons, cards, or backgrounds (exempt strictly: procedural hardware robot mark/avatar lenses and 3D SceneKit room).
- **No shadows on grounded surfaces** (cards, buttons, sidebar rows, inline banners). Shadows are reserved strictly for floating overlays (popovers, command palette, quick bar, modal sheets).
- **No bounce or slow transitions**: never use under-damped overshoot curves (`cubic-bezier(0.34, 1.56, ...)` or spring `dampingFraction < 1.0` on standard UI) or transitions `> 300ms`.
- **No raw hex or rgb/rgba color literals** outside `DesignTokens.swift` and `design-system/tokens.css`.
- **No duplicate summary chrome**: never repeat the same count or entity list in 2+ places on the same screen (e.g. header subtitle + KPI strip + column badge, or main Bot grid + duplicate sidebar Bot list).

---

## Always

- **Sentence case everywhere** across Chinese and English labels.
- **Semantic tokens only** (`bgCanvas`, `bgSidebar`, `bgSurface`, `bgSurfaceHover`, `bgInset`, `bgElevated`, `textPrimary`, `textSecondary`, `textMuted`, `borderSubtle`, `borderStrong`, `soulPrimary`, plus `stateSuccess` / `stateWarning` / `stateError` strictly for live status).
- **Monochrome neutral surfaces**: Light `#FFFFFF` canvas / `#F7F7F8` rail / `#F8F8F9` subtle surface / `#171717` ink; Dark `#0F1012` canvas / `#141518` rail / `#181A1E` surface / `#F4F4F5` ink. Color appears only on status dots, diffs, and Bot identity glyphs.
- **One type scale, two weights (`Regular` / `Medium`)**:
  - `fontHero`: `28pt` Medium
  - `fontTitle`: `20pt` Medium
  - `fontHeadline`: `15pt` Medium
  - `fontBody`: `14pt` Regular
  - `fontSubheadline`: `13.5pt` Medium
  - `fontCaption`: `13pt` Regular
  - `fontMicro`: `12pt` Medium
- **Explicit motion budget (all `< 300ms`, exits faster than entries, zero bounce)**:
  - Keyboard highlight / selection: **instant (`0ms`)**
  - Button press (`scale 0.97`): **`100ms`**
  - Close / exit / collapse: **`140ms`**
  - Hover tint: **`150ms`**
  - Open / enter / popover: **`200ms`**
  - Panel / drawer / height change: **`260ms`, no bounce**
- **Canonical geometry**: Mobile buttons `44px` (`18px` icon, `8px` gap); macOS desktop buttons `32px` (`16px` icon, `6px` gap); Sheets anchored at `topEdge` `54px` or `102px`.
- **Board-first navigation restraint**: keep sidebar primary destinations to 4 calm items (`Board / 任务板`, `Threads / 频道与对话`, `Bots / 智能体`, `Knowledge / 知识与简报`); keep device nodes, mobile pairing, and host diagnostics inside the Host popover and Settings.
- **Visual verification before declaring done**: inspect rendered Light, Dark, and `390px` mobile screenshots against these rules after UI changes, and run `npm run audit:design`.
