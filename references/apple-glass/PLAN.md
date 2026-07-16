# Action plan — Klip's glass (rewritten after the deep research)

The earlier version of this plan framed the decision as "honest vibrancy vs a tinted fake".
**The research killed that framing.** Apple's own materials *are* tinted — the tint is not a
cheat, it's the mechanism. So there is no purist/pragmatist fork. There's just the recipe.

Read `DESIGN-BRIEF.md` first. This is the execution order.

## What was actually wrong (all of it, in order)

1. **`layer.cornerRadius` + `masksToBounds` on the effect view** broke `.behindWindow` blending →
   every material rendered flat grey. Fixed (`GlassMask.rounded`), never visually confirmed.
2. **The white "gloss" overlay was backwards.** A white wash only raises the luminance floor. It
   has **no ceiling**, so over bright content the panel blows out toward white. Apple does the
   opposite: a near-white tint with **`darkenBlendMode`** = `min(backdrop, tint)`, which *lowers
   the ceiling* and leaves darks untouched. Light materials darken; dark materials lighten. No
   exceptions in anything Apple ships.
3. **No rim.** Apple's glass is defined at the **edge**, not the middle. Two concentric strokes,
   not one border. This is the single highest-leverage missing piece.
4. **Chasing materials.** Semantic choice only; the material was never the problem.

## The recipe to implement (macOS 14, public API only)

Numbers from the reverse-engineered CoreUI `panelLight` recipe (see brief §3.2):

| Layer | Value |
|---|---|
| Backdrop | `NSVisualEffectView`, `.popover`, `.behindWindow`, `.active`, `maskImage` corners |
| Background fill | grey `0.9647` @ α`0.45` — normal composite (raises the floor) |
| **Tint** | grey `0.9333` @ α`0.50`, `compositingFilter = "darkenBlendMode"` (**lowers the ceiling** — this is the glass) |
| Rim outer | 0.5pt contour, white α`0.5`, radius `r + borderWidth` |
| Rim inner | 1pt specular edge, radius `r` |
| Corners | `cornerCurve = .continuous`, both strokes concentric |
| Labels | `labelColor` / `secondaryLabelColor` only — never `systemGray*` |
| Rows | fills + vibrancy. **Never a second effect view** (no glass-on-glass) |
| Row radius | `panelRadius − padding` (concentric) |
| a11y | `reduceTransparency`/`increaseContrast` → go fully opaque (light `0.8784`/`0.8235` @ α1.0), rim to 1pt α1.0 |

## Order of work

0. **Confirm the blending fix landed.** Panel over the desktop wallpaper — does it carry the
   wallpaper's colour? If no, nothing below matters; hunt the blocker first.
1. **Add the darken tint layer.** The one change that turns "grey box" into glass.
2. **Build the two-stroke concentric rim.** Where the glass actually lives.
3. **Verify by measurement, not opinion** (see below).
4. Concentric row radii; scroll-edge gradient instead of dividers.
5. Accessibility fallback (opaque) — not optional.
6. Later: availability-gate `.glassEffect()` for macOS 26.

## Verification loop (the thing that was missing all along)

`screencapture` works from the shell, so the loop is now objective:

1. Panel over the **desktop wallpaper only** (never over work windows — see README's process lesson).
2. Capture → sample panel vs surrounding wallpaper.
3. Target, from Apple's own Tahoe Control Center measured in `web/SOURCES.md`:
   **luminance ≈ flat vs backdrop, saturation HIGHER than backdrop** (they measured 136 vs 138 lum,
   55.8% vs 42.1% sat).
4. If the panel is *brighter* than the backdrop → the tint is wrong (white wash again).
5. Iterate on numbers, not vibes.

## Judge with the brief's checklist

`DESIGN-BRIEF.md` §5 has 13 tells for real glass vs fake glassmorphism. The three that carry it:
darken tint (#3), two-stroke concentric rim (#4), opaque a11y fallback (#10).

## Still open for you

- The panel will end up **slightly darker than the backdrop, not brighter**. That's what Apple does
  and what makes it read as glass. Earlier you rejected "too dark" — but that was a flat 32% black
  scrim with broken blending, which is a different thing from a `min()` ceiling on a live blur.
- OK for me to capture the panel **only when it's over the desktop wallpaper**, for the measurement
  loop?
