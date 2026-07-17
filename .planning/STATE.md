# Project State

## Project Reference

See: .planning/PROJECT.md · .planning/ROADMAP.md (both describe milestone v0.5, now closed)

**Core value:** Everything you copy (or capture) stays persistent and searchable, one shortcut away, without leaving your Mac.

## Current Position

**Milestone v0.5 — "Native capture + transcription control": CLOSED.** All 4 phases shipped and
deployed (Gemini model picker · region capture + TCC · annotation editor · history/OCR integration).
ROADMAP.md is kept as the historical record of that milestone.

**Current work: v0.6 — Apple design rebrand.** Not phase-planned; driven directly from the
conversation, one surface at a time, each verified against a real screen capture before moving on.

Shipped in v0.6 so far:
- Real behind-window vibrancy on every floating surface (E panel, R recording popup, toasts).
  Root cause of the long-standing "not glass" bug: `layer.cornerRadius + masksToBounds` on an
  `NSVisualEffectView` silently kills `.behindWindow` blending. Corners now come from `maskImage`.
  See `Sources/Klip/Glass.swift` — the recipe is documented at the top of the file.
- Two-stroke rim (contour + specular), shared sheen layer, Reduce-Transparency fallback.
- Aux windows (Preferences/Welcome/Guide/Upload) moved onto the same glass path.
- History list: text-forward, date-grouped, no text animation.
- Direct-to-Downloads saves (image/text/PDF/ZIP) — no name dialog, numeric names.
- Editor: tooltips + hints on every tool, blur slider retunes existing blurs, tighter window fit.

## Accumulated Context

### Decisions

Logged in PROJECT.md's Key Decisions table. Still governing current work:

- [v0.5 Phase 2]: ScreenCaptureKit (`SCScreenshotManager`) over deprecated `CGDisplayCreateImage`; freeze-frame model
- [v0.5 Phase 3]: Editor is a custom AppKit `NSView` + a temporary `NSTextView` for in-place text (accents)
- [v0.6]: No private API — the Mac App Store is a goal, so `NSGlassEffectView`-era tricks stay out
- [v0.6]: Never round an `NSVisualEffectView` via its layer; use `GlassMask.rounded()`

### Blockers/Concerns

- Screen-recording TCC is the fragile permission — always install to `/Applications` via `install.sh`, never run from `.build/`
- Retina/multi-monitor crop scale is worth re-checking after any capture change
- Recurring failure mode, seen 4× in v0.6: our own decoration breaking native behavior — a view above
  the content swallowing clicks, an unclipped `NSHostingView` showing square corners, or
  `trackingAreas.forEach(removeTrackingArea)` destroying AppKit's own tooltip area. All four are fixed;
  the pattern is what to watch for.

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Share/Upload | SHR-01..04 (public URL, social, Google Images, print) | Deferred to v2 | 2026-06-17 |
| App Store | Sandbox, privacy manifest, Team ID | Open — scoped when publishing starts | 2026-07-17 |

## Session Continuity

Last session: 2026-07-17
Stopped at: v0.6 plan executed (overlay audit, 4 frictions, glass consistency, editor polish,
first tests). Built, deployed to `/Applications/Klip.app`.

### Deploy note (signing)
Signing with the stable `Klip Code Signing` identity can hang on a background Keychain prompt.
Run `install.sh` **interactively** and click "Allow", or run `security set-key-partition-list` once
to let codesign use the key without prompting. The ad-hoc fallback works but makes macOS re-ask for
permissions on every reinstall.
