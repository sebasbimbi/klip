# Apple glass — references & findings

Reference material gathered to understand how Apple's "glass" (vibrancy) actually works,
before changing any more code. **Nothing here is generated art — the PNGs are real captures
of this Mac's system UI.**

## Captures (real, extracted)

| File | What it is |
|---|---|
| `01-dock.png` | The macOS Dock strip — the user's stated reference for "glass" |
| `02-dock-zoom.png` | Dock close-up — shows the glass texture and the top rim |
| `03-menubar.png` | The menu bar — the other system glass surface |

> A Spotlight capture was attempted and **deleted immediately**: the region grabbed a chat
> window with real names and phone numbers instead. Lesson recorded below.

## Finding 1 — The Dock's glass is DARK, not a bright white panel

Measured from `01-dock.png` (sampling glass areas between icons vs. the content above):

| Sample | RGB | Luminosity | Saturation |
|---|---|---|---|
| White app window just above the Dock | (248, 248, 247) | **248** | 0% |
| **Dock glass** (between icons) | (139, 153, 144) | **145** | 9% |
| Dock glass just under the top edge | (113, 127, 119) | 120 | — |
| Top rim (light catching the edge) | (155, 178, 163) | 165 | — |

**The Dock takes the wallpaper, blurs it heavily, desaturates it slightly, and DARKENS it**
(248 → 145). It is a mid-tone material that carries the backdrop's hue (green here, from the
wallpaper), plus a brighter rim along the top edge.

This kills the assumption we were designing against. "Dock glass" ≠ bright white frosted panel.

## Finding 2 — Why the Dock looks glassy and Klip doesn't

The Dock sits at the bottom of the screen **over the desktop wallpaper**. Behind-window
vibrancy samples what is *behind the window* — for the Dock that's a colourful photo, so the
glass visibly carries colour and reads as glass.

Klip's panel floats **over the user's app windows** (editor, chat, Notion — all near-white).
Same material, but it samples white → renders light grey. That is correct macOS behaviour, not
a bug: an Apple menu opened over a white document also renders light grey.

**Implication:** matching "the Dock look" over arbitrary app backgrounds is not a material
choice — it requires deciding whether we accept the backdrop (true glass, varies) or impose a
tint (consistent, less "true" glass).

## Finding 3 — The real code bug (from research, already fixed)

Rounding an `NSVisualEffectView` with `wantsLayer` + `layer.cornerRadius` + `masksToBounds`
**breaks `.behindWindow` blending** and collapses the material to flat opaque grey — for every
material. `.behindWindow` works by the window server compositing the material through the
view's `maskImage`; forcing the view into its own clipped backing layer composites it
off-screen instead.

Klip did exactly this on all four glass surfaces, which is why `.menu`, `.popover`, `.sidebar`,
`.hudWindow` and `.underWindowBackground` all looked identical.

Second cause: `NSVisualEffectView` does not affect content drawn **over** it. The white "gloss"
fills added as SwiftUI backgrounds were covering the vibrancy.

Both are fixed in `GlassMask.rounded(_:)` + `Color.clear` roots (commit `fix(glass)`), but the
result has not been visually confirmed yet.

Sources: [onmyway133/blog#1025](https://github.com/onmyway133/blog/issues/1025),
[Apple Dev Forums 125183](https://developer.apple.com/forums/thread/125183),
[philz.blog vibrancy](https://philz.blog/vibrancy-nsappearance-and-visual-effects-in-modern-appkit-apps/),
[Oskar Groth — reverse-engineering NSVisualEffectView](https://oskargroth.com/blog/reverse-engineering-nsvisualeffectview).

## Finding 4 — The Dock's exact material is private

Apple's system surfaces (Dock, Control Center, menus) load private CoreUI `.car` recipes:
a `CABackdropLayer` sampling the backdrop + `CAFilter` blur/saturation/brightness + a tint
layer using darken/lighten blend modes. The public `NSVisualEffectView.Material` enum only
exposes a fixed set of baked recipes — any public material is an approximation. We cannot
reproduce the Dock exactly with public API.

## Verified non-causes

- **Reduce Transparency** (System Settings → Accessibility → Display): **OFF** on this Mac, so
  it is not forcing materials to flat grey.
- Material choice: not the cause (see Finding 3).
- SwiftUI `.ultraThinMaterial`: cannot help — on macOS it blends against the *window's own*
  backdrop (within-window), never the desktop/other apps behind it.

## Process lesson

Never blind-capture arbitrary screen regions on the user's machine — the Spotlight attempt
grabbed real personal data (names, phone numbers) and had to be destroyed. Only capture known
system-UI zones (Dock strip at the bottom, menu bar at the top), or have the user place the
window over the desktop first.
