import AppKit

// Genera Resources/AppIcon.png (1024×1024): squircle con degradado + portapapeles blanco.
let S = 1024
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("rep") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let canvas = CGFloat(S)
let inset: CGFloat = 76
let rect = NSRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
let squircle = NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200)

// Fondo degradado (índigo → violeta).
NSGraphicsContext.saveGraphicsState()
squircle.addClip()
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.40, green: 0.49, blue: 0.99, alpha: 1.0),
    NSColor(srgbRed: 0.52, green: 0.33, blue: 0.93, alpha: 1.0)
])!
gradient.draw(in: rect, angle: -90)
NSGraphicsContext.restoreGraphicsState()

// Glifo de portapapeles (SF Symbol) teñido de blanco.
let cfg = NSImage.SymbolConfiguration(pointSize: 470, weight: .semibold)
if let base = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let sz = base.size
    let tinted = NSImage(size: sz)
    tinted.lockFocus()
    base.draw(at: .zero, from: NSRect(origin: .zero, size: sz), operation: .sourceOver, fraction: 1)
    NSColor.white.set()
    NSRect(origin: .zero, size: sz).fill(using: .sourceAtop)
    tinted.unlockFocus()
    let drawRect = NSRect(x: (canvas - sz.width) / 2,
                          y: (canvas - sz.height) / 2 - 8,
                          width: sz.width, height: sz.height)
    tinted.draw(in: drawRect, from: NSRect(origin: .zero, size: sz), operation: .sourceOver, fraction: 1.0)
}

NSGraphicsContext.restoreGraphicsState()

let url = URL(fileURLWithPath: "Resources/AppIcon.png")
try! rep.representation(using: .png, properties: [:])!.write(to: url)
print("✓ Icono escrito en Resources/AppIcon.png (\(S)×\(S))")
