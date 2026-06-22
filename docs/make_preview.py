#!/usr/bin/env python3
"""Generate docs/klip-preview.gif — an illustrative motion graphic of Klip's vibe-coder flow.

This is a stylized mockup (not a screen recording): it shows the core loop —
copy code / snip + annotate / OCR / dictate → paste into your AI. Replace with a
real screen capture when available.
"""
import io, math
import cairosvg
from PIL import Image

W, H = 720, 420
FRAMES = 48
ACCENT = "#2F6BFF"
BG = "#0E1525"
CARD = "#171F2E"
ROW = "#1F2A3D"
ROW_HI = "#26365A"
TXT = "#E7ECF5"
SUB = "#8A97AD"
GREEN = "#34C759"

ROWS = [
    ("</>", "func handleError(_ e: Error) { … }", "Copy as code block", ACCENT),
    ("IMG", "Screenshot  +  annotation",           "Extract text (OCR)", "#FF9F0A"),
    ("mic", "“refactor this function”",            "Voice → text",       "#FF375F"),
]

def esc(s): return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

def row_icon(kind, x, y, color):
    if kind == "</>":
        return (f'<text x="{x+18}" y="{y+22}" font-family="SF Mono, Menlo, monospace" '
                f'font-size="14" font-weight="700" fill="{color}" text-anchor="middle">&lt;/&gt;</text>')
    if kind == "IMG":
        return (f'<rect x="{x+6}" y="{y+8}" width="24" height="18" rx="3" fill="none" stroke="{color}" stroke-width="2"/>'
                f'<circle cx="{x+13}" cy="{y+14}" r="2.5" fill="{color}"/>'
                f'<path d="M{x+9} {y+24} l6 -6 l5 4 l5 -7 l4 9 z" fill="{color}" opacity="0.85"/>')
    # mic
    return (f'<rect x="{x+13}" y="{y+6}" width="10" height="15" rx="5" fill="{color}"/>'
            f'<path d="M{x+10} {y+18} a8 8 0 0 0 16 0" fill="none" stroke="{color}" stroke-width="2"/>'
            f'<line x1="{x+18}" y1="{y+26} " x2="{x+18}" y2="{y+30}" stroke="{color}" stroke-width="2"/>')

def frame_svg(i):
    t = i / FRAMES
    active = int((i // (FRAMES // 3)) % 3)        # which row is highlighted
    local = (i % (FRAMES // 3)) / (FRAMES // 3)   # 0..1 progress within this row
    # flying dot from the active row toward the AI node
    panel_x, panel_y, panel_w = 40, 70, 420
    row_h, row_gap, row_y0 = 56, 14, 150
    ry = row_y0 + active * (row_h + row_gap) + row_h / 2
    ai_x, ai_y = 640, 210
    sx = panel_x + panel_w - 30
    # dot appears in second half of the row's time
    dotp = max(0.0, (local - 0.45) / 0.55)
    dx = sx + (ai_x - sx) * dotp
    dy = ry + (ai_y - ry) * dotp
    pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 3)

    rows_svg = ""
    for idx, (kind, text, chip, color) in enumerate(ROWS):
        y = row_y0 + idx * (row_h + row_gap)
        hi = (idx == active)
        fill = ROW_HI if hi else ROW
        stroke = f'stroke="{ACCENT}" stroke-width="1.5"' if hi else 'stroke="none"'
        rows_svg += f'<rect x="{panel_x+16}" y="{y}" width="{panel_w-32}" height="{row_h}" rx="10" fill="{fill}" {stroke}/>'
        rows_svg += f'<rect x="{panel_x+28}" y="{y+row_h/2-16}" width="32" height="32" rx="7" fill="#0E1525"/>'
        rows_svg += row_icon(kind, panel_x+28, int(y+row_h/2-16), color)
        rows_svg += (f'<text x="{panel_x+72}" y="{y+24}" font-family="SF Mono, Menlo, monospace" '
                     f'font-size="13" fill="{TXT}">{esc(text)}</text>')
        if hi:
            cw = 8 * len(chip) + 24
            rows_svg += (f'<rect x="{panel_x+72}" y="{y+32}" width="{cw}" height="18" rx="9" fill="{color}" opacity="0.18"/>'
                         f'<text x="{panel_x+84}" y="{y+45}" font-family="-apple-system, Helvetica, sans-serif" '
                         f'font-size="11" font-weight="600" fill="{color}">{esc(chip)}</text>')

    dot = ""
    if dotp > 0:
        dot = f'<circle cx="{dx:.1f}" cy="{dy:.1f}" r="6" fill="{ROWS[active][3]}"/>'

    ai_glow = 0.25 + 0.55 * (dotp if dotp > 0 else 0)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
  <rect width="{W}" height="{H}" rx="20" fill="{BG}"/>
  <!-- Klip panel -->
  <rect x="{panel_x}" y="{panel_y}" width="{panel_w}" height="300" rx="16" fill="{CARD}" stroke="#26324A" stroke-width="1"/>
  <circle cx="{panel_x+22}" cy="{panel_y+22}" r="5" fill="#FF5F57"/>
  <circle cx="{panel_x+40}" cy="{panel_y+22}" r="5" fill="#FEBC2E"/>
  <circle cx="{panel_x+58}" cy="{panel_y+22}" r="5" fill="#28C840"/>
  <text x="{panel_x+panel_w-20}" y="{panel_y+27}" text-anchor="end" font-family="-apple-system, Helvetica, sans-serif" font-size="14" font-weight="700" fill="{TXT}">Klip</text>
  <rect x="{panel_x+16}" y="{panel_y+44}" width="{panel_w-32}" height="34" rx="9" fill="#0E1525"/>
  <text x="{panel_x+32}" y="{panel_y+66}" font-family="-apple-system, Helvetica, sans-serif" font-size="13" fill="{SUB}">Search…</text>
  {rows_svg}
  <!-- AI target -->
  <circle cx="{ai_x}" cy="{ai_y}" r="34" fill="{ACCENT}" opacity="{ai_glow:.2f}"/>
  <circle cx="{ai_x}" cy="{ai_y}" r="24" fill="{CARD}" stroke="{ACCENT}" stroke-width="2"/>
  <text x="{ai_x}" y="{ai_y+7}" text-anchor="middle" font-family="-apple-system, Helvetica, sans-serif" font-size="18" font-weight="800" fill="{ACCENT}">AI</text>
  <text x="{ai_x}" y="{ai_y+52}" text-anchor="middle" font-family="-apple-system, Helvetica, sans-serif" font-size="11" fill="{SUB}">paste</text>
  {dot}
  <!-- caption -->
  <text x="{W/2}" y="{H-26}" text-anchor="middle" font-family="-apple-system, Helvetica, sans-serif" font-size="15" font-weight="600" fill="{TXT}">Copy code · snip + annotate · OCR · dictate — then paste into your AI</text>
  <circle cx="{panel_x+10}" cy="{H-31}" r="0" fill="{GREEN}" opacity="{pulse:.2f}"/>
</svg>'''

def main():
    imgs = []
    for i in range(FRAMES):
        png = cairosvg.svg2png(bytestring=frame_svg(i).encode("utf-8"), output_width=W, output_height=H)
        imgs.append(Image.open(io.BytesIO(png)).convert("RGB"))
    out = "docs/klip-preview.gif"
    imgs[0].save(out, save_all=True, append_images=imgs[1:], duration=90, loop=0, optimize=True)
    print("wrote", out, "frames:", len(imgs))

if __name__ == "__main__":
    main()
