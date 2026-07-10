# ReadAloud — Design Guidelines

Ruby's visual standards. **All agents follow these; compose the tokens in
`Shared/DesignSystem.swift` + `Shared/Styles/` — never hardcode raw numbers in a
view.** They sit on top of the "paper & ink" identity (DECISIONS #36) and the
semantic palette (DECISIONS #39).

## 1. Type — ≤2 families per screen
- Two families only: **system sans** (SF / PingFang) for UI chrome and native-
  language text; **serif** (New York, `Theme.sentenceDesign`) for source-language
  "book voice" content. Never introduce a third.
- **Even font sizes only** (odd px blurs on device). Fixed sizes go through
  `DesignSystem.IconSize` for symbols; body text uses the semantic `Font` styles
  (Dynamic Type) so it scales.
- Line height: body **1.5–1.6×**, headings **1.2–1.3×**.

## 2. Spacing & grid — 8-pt system
- Every gap/padding is a **multiple of 8** (4 is the only allowed half-step).
  No 10, 15, 22… Use `DesignSystem.Spacing` (xs 4 · sm 8 · md 16 · lg 24 · xl 32).
- **Screen side margins are unified: 16** (`DesignSystem.Spacing.screenMargin`).
  Use 20 only where a screen deliberately needs more air.

## 3. Corner radius — one global ladder
- `DesignSystem.CornerRadius`: **icon/small module 8** (`small`) · **button 10**
  (`button`) · **card 12** (`medium`, range 12–16) · **hero container 20**
  (`large`). One page should not mix arbitrary radii — pick the ladder rung.

## 4. Tap targets — ≥44 pt (hard rule)
- Every interactive control's hit area is **≥ `DesignSystem.minTapTarget` (44)**.
  Small-looking icon buttons still need a 44×44 frame.

## 5. Color — restrained + accessible
- **One primary** (ink blue `Theme.accent`); the 5-hue `Palette` is **semantic
  accent** (source kinds / annotation types / grades), not decoration. Functional
  colors are global and semantic (`ReviewGrade.tint`, confused → marigold).
- **Contrast ≥ 4.5:1** for body text (WCAG 2.1). White-on-tint surfaces (book
  covers, filled buttons) must clear 4.5:1 — add a scrim if unsure. Marigold's
  light variant is deliberately dark (#A9740E) for this reason.

## 6. Icons — uniform
- SF Symbols only; **consistent weight** (default `.semibold` for accents) and
  **consistent size** via `DesignSystem.IconSize` (sm 16 · md 24 · lg 28 · hero 48).
  Symbols stay crisp at any scale (no raster assets).

---
*When a value doesn't fit a token, the token set is wrong — extend
`DesignSystem`/`Theme`, don't sprinkle literals in views.*
