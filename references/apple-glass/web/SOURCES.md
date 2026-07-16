# Reference images — sources & licensing

Downloaded for **study only**. These are third-party/Apple copyrighted images: they are
**git-ignored and never published** with Klip. Use them to compare against, not to ship.

| Folder | Source | What it teaches |
|---|---|---|
| `01-apple-hig/` | [Apple HIG — Materials](https://developer.apple.com/design/human-interface-guidelines/materials) | Apple's own material scale (ultrathin→thick), Liquid Glass over light vs dark, and the ✅/❌ legibility pair (vibrant vs non-vibrant label) |
| `02-apple-newsroom/` | [Apple Newsroom, June 2025](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/) | Official Liquid Glass hero + macOS Tahoe Control Center |
| `03-macos-14-baseline/` | [512pixels Aqua Screenshot Library — Sonoma](https://512pixels.net/projects/aqua-screenshot-library/macos-14-sonoma/) | **Our actual floor.** Real Spotlight / Control Center / Notification Center on macOS 14 — this is what Klip can genuinely match |
| `04-macos-26-tahoe/` | [512pixels — Tahoe](https://512pixels.net/projects/aqua-screenshot-library/macos-26-tahoe/) | Where Apple went next (Liquid Glass) — aspirational, not reachable on 14 |
| `05-reverse-engineering/` | [Oskar Groth — Reverse-engineering NSVisualEffectView](https://oskargroth.com/blog/reverse-engineering-nsvisualeffectview) | The material breakdown behind the real recipe |

## Measured from these (proof of the model)

macOS 26 Tahoe Control Center, panel vs the wallpaper around it:

| | Luminosity | Saturation |
|---|---|---|
| Wallpaper | 138.2 | 42.1% |
| Apple's panel | 136.1 | **55.8%** |

Luminance essentially flat, **saturation HIGHER than the backdrop**. That is the
`saturate → blur → brightness` pipeline: crush the luminance range, boost the chroma so the
backdrop's *hue* still reads. Exactly what the brief predicts — and the opposite of a white wash,
which raises luminance and kills chroma.
