# Action plan — getting Klip's glass right

Written after gathering real references (see `README.md`). **No code changes proposed for
execution yet — this is the plan to agree on first.**

## The core decision

The measurements say the Dock is *a darkened, desaturated blur of whatever is behind it*. It
looks glassy because what's behind it is a wallpaper. Klip floats over near-white app windows,
so true vibrancy there renders light grey — correctly.

So there are two mutually exclusive targets, and we must pick one:

**A. True Apple glass (honest vibrancy).**
Klip reflects whatever is behind it: colourful over the wallpaper, light grey over a white
editor — exactly like a real macOS menu behaves. Pro: genuinely native, zero fakery.
Con: over your usual (white) apps it will keep looking light grey, which is what you've been
rejecting for the last several rounds.

**B. Dock-like at all times (tinted glass).**
Impose the Dock's actual recipe — blur the backdrop, then *darken + desaturate* it toward a
fixed mid-tone — so it reads as glass over any background, white apps included. This is what
the Dock's private material effectively does. Pro: consistent, always visibly glass.
Con: not a stock material; we're approximating a private CoreUI recipe by hand.

**My recommendation: B**, because it's what you've actually been asking for every time
("gloss like the Dock", "I still don't see the glass"), and the measurements show the Dock is
tinted rather than neutral. A is the purist answer that keeps producing the result you dislike.

## Steps once a direction is chosen

### Step 0 — Verify the blending fix actually landed (blocking)
The `maskImage` fix (Finding 3) removed the bug that flattened *every* material, but we've never
confirmed it visually. Before tuning anything: open the panel **over the desktop wallpaper**
(not over an app) and check whether it now carries the wallpaper's colour.
- If yes → blending works; proceed to tune.
- If no → something still covers the vibrancy; hunt that before touching materials again.

This must be checked first because every tuning decision below is meaningless if blending is
still broken.

### If direction A (true vibrancy)
1. Keep `.menu` (or `.underWindowBackground` for a thinner look), `.behindWindow`, `.active`,
   `isEmphasized = false`, `maskImage` corners, `Color.clear` roots.
2. Accept and document the behaviour; stop chasing it over white apps.
3. Done — it's already implemented.

### If direction B (Dock-like tinted glass) — recommended
1. Keep the real vibrancy underneath (blur + backdrop colour).
2. Add a controlled tint layer over it approximating the Dock's measured recipe:
   target luminosity ≈ 145 and low saturation, i.e. a dark, slightly desaturating overlay
   rather than the white "gloss" I wrongly added before.
3. Add the top rim (measured lighter than the body: ~165 vs ~145) — 0.5pt light hairline along
   the top edge only, via the mask/border, not `layer.cornerRadius`.
4. Flip content to light-on-dark, since the surface becomes mid-dark (this is the part you
   rejected earlier as "too dark" — but that attempt was *without* working blending and with a
   flat 32% black scrim, which is not the same thing as a tinted blur).
5. Tune the tint against real captures: screenshot the panel over the wallpaper, sample it, and
   compare its numbers to the Dock's (145 / 9% sat) until they match.

### Step N — Verification loop (new capability)
`screencapture` works from the shell, which means I can finally **see** Klip's panel and measure
it — the thing that was missing for the last dozen rounds. The loop becomes:
capture → sample pixels → compare to the Dock's numbers → adjust → repeat.
Constraint: only capture with the panel over the **desktop wallpaper**, never over your work
windows (see the process lesson in `README.md`).

## What I need from you

1. **Direction A or B?** (I recommend B.)
2. For the verification loop: is it OK for me to capture the panel **when it's over the desktop
   wallpaper only**? That keeps your work windows out of every screenshot.

## Open questions / risks

- Direction B means the panel goes mid-dark. You rejected "too dark" once already — but that was
  a flat black scrim with broken blending. A tinted *blur* reads differently. If B still feels
  too dark once measured against the Dock, the fallback is to lighten the tint and accept a
  softer effect.
- The Dock's exact material is private (Finding 4). B is an approximation by construction.
- macOS 26 (Tahoe) ships `NSGlassEffectView` / `.glassEffect()` — the real Liquid Glass API with
  proper corner radius and content hosting. Klip targets macOS 14, so it's unavailable, but it's
  the eventual clean path and worth an availability-gated branch later.
