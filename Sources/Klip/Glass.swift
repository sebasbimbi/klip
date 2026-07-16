import AppKit
import SwiftUI

/// Press feedback for custom (`.plain`/`.borderless`) buttons that don't get AppKit's native
/// press dip. Apple's first fluid-interface principle: respond on press-DOWN, instantly. The dip
/// rides a critically-damped spring (no overshoot) so it feels physical, not scripted. Respects
/// Reduce Motion (the spring degrades to an instant state change there automatically).
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.snappy(duration: 0.18, extraBounce: 0), value: configuration.isPressed)
    }
}

/// Shared helpers for real behind-window vibrancy ("glass").
@MainActor
enum GlassMask {
    /// Rounded-corner mask for an NSVisualEffectView.
    ///
    /// CRITICAL: never round a visual-effect view with `wantsLayer` + `layer.cornerRadius` +
    /// `masksToBounds`. `.behindWindow` blending works by the window server compositing the material
    /// through the view's `maskImage`; forcing the view into its own clipped backing layer composites
    /// it off-screen instead and collapses the glass to flat opaque gray — regardless of the material.
    /// A resizable rounded-rect `maskImage` gives the same corners while keeping the blur alive.
    static func rounded(_ radius: CGFloat) -> NSImage {
        let d = radius * 2 + 1
        let img = NSImage(size: NSSize(width: d, height: d), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }
}

/// A floating glass surface implementing Apple's real material recipe (references/apple-glass):
///
///   backdrop  — NSVisualEffectView (.popover, .behindWindow, .active) rounded via maskImage
///   tint      — the luminance CEILING: near-white grey composited with darkenBlendMode in light
///               (min(backdrop, tint) clamps highlights), near-black with lightenBlendMode in dark.
///               Apple's light materials always darken, never whiten — a white wash has no ceiling
///               and blows out over bright content.
///   content   — hosted above the tint (fills + vibrancy only; never a second effect view)
///   rim       — where glass is actually defined: concentric strokes, light-catching edge.
///
/// Adapts to the effective appearance (light/dark) and goes fully opaque under Reduce
/// Transparency / Increase Contrast, mirroring the system materials' fallback.
final class GlassPanelView: NSView {
    /// Decoration that must never intercept clicks: the sheen and rim sit ABOVE the hosted content,
    /// so without this they'd swallow every press (a dead Cancel button).
    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private let fx = NSVisualEffectView()
    private let tintView = PassthroughView()
    private let sheen = CAGradientLayer()
    private let rimView = PassthroughView()
    private let rimOuter = CALayer()
    private let rimInner = CALayer()
    private let radius: CGFloat
    private weak var content: NSView?

    init(frame: NSRect, radius: CGFloat, material: NSVisualEffectView.Material = .popover) {
        self.radius = radius
        super.init(frame: frame)

        fx.material = material
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.isEmphasized = false
        fx.maskImage = GlassMask.rounded(radius)
        fx.frame = bounds
        fx.autoresizingMask = [.width, .height]
        addSubview(fx)

        tintView.wantsLayer = true
        tintView.frame = bounds
        tintView.autoresizingMask = [.width, .height]
        tintView.layer?.cornerRadius = radius
        tintView.layer?.cornerCurve = .continuous
        // Specular sheen — the "mirror" band: a soft diagonal highlight from the top-left, like
        // light reflecting off the glass (Liquid Glass's Highlight layer). This is what makes the
        // surface read as glass even over plain white content, where blur alone shows nothing.
        // Directional and edge-weighted — NOT a flat white veil (which would just raise the floor).
        sheen.type = .axial
        sheen.startPoint = CGPoint(x: 0, y: 1)      // top-left (macOS layer coords: y-up)
        sheen.endPoint = CGPoint(x: 0.65, y: 0.1)   // fades out ~2/3 across, light at ≈ -60°
        sheen.cornerRadius = radius
        sheen.cornerCurve = .continuous
        sheen.masksToBounds = true
        tintView.layer?.addSublayer(sheen)
        addSubview(tintView)

        rimView.wantsLayer = true
        rimView.frame = bounds
        rimView.autoresizingMask = [.width, .height]
        rimOuter.borderWidth = 0.5
        rimInner.borderWidth = 1
        rimOuter.cornerCurve = .continuous
        rimInner.cornerCurve = .continuous
        rimView.layer?.addSublayer(rimOuter)
        rimView.layer?.addSublayer(rimInner)
        addSubview(rimView)

        applyRecipe()

        NotificationCenter.default.addObserver(
            self, selector: #selector(accessibilityChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Installs the hosted content between the tint and the rim.
    ///
    /// The content is clipped to the panel's rounded shape: an NSHostingView is a plain rectangle,
    /// so without this its square backing shows past the glass corners as a white box. Clipping the
    /// CONTENT is safe — unlike clipping the effect view, which would break behind-window blending.
    func setContent(_ view: NSView) {
        content?.removeFromSuperview()
        content = view
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = radius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        addSubview(view, positioned: .below, relativeTo: rimView)
    }

    override func layout() {
        super.layout()
        // Concentric rim: outer contour hugs the panel edge at r + its own width; inner specular
        // stroke sits just inside at r (inner_radius = outer_radius − stroke, Apple's concentricity).
        rimOuter.frame = rimView.bounds
        rimOuter.cornerRadius = radius
        rimInner.frame = rimView.bounds.insetBy(dx: 0.5, dy: 0.5)
        rimInner.cornerRadius = max(0, radius - 0.5)
        sheen.frame = tintView.bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyRecipe()
    }
    @objc private func accessibilityChanged() { applyRecipe() }

    /// The measured CoreUI panel recipe (see references/apple-glass/DESIGN-BRIEF.md §3.2).
    private func applyRecipe() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

        if reduce {
            // System materials go fully opaque here; so do we (the accessibility floor).
            fx.isHidden = true
            sheen.isHidden = true
            tintView.layer?.compositingFilter = nil
            tintView.layer?.backgroundColor = NSColor(white: dark ? 0.12 : 0.8784, alpha: 1).cgColor
            rimOuter.borderColor = NSColor(white: dark ? 1 : 0, alpha: 1).cgColor
            rimOuter.borderWidth = 1
            rimInner.isHidden = true
            return
        }

        fx.isHidden = false
        // NO extra tint: the system material already applies Apple's full recipe (floor + darken
        // ceiling + saturation) internally. Measured in the glass lab: raw .popover+mask converges
        // to the same value as a REAL Finder menu over the same backdrop (Δ≈-9 vs +15, both toward
        // ~188); adding the CoreUI tint on top double-applies it and lands ~20 too dark.
        tintView.layer?.compositingFilter = nil
        tintView.layer?.backgroundColor = NSColor.clear.cgColor
        sheen.isHidden = false
        rimOuter.borderWidth = 0.5
        if dark {
            sheen.colors = [NSColor(white: 1, alpha: 0.10).cgColor,
                            NSColor(white: 1, alpha: 0.03).cgColor,
                            NSColor.clear.cgColor]
            sheen.locations = [0, 0.3, 0.6]
            rimOuter.borderColor = NSColor(white: 0, alpha: 0.8).cgColor
            rimInner.isHidden = false
            rimInner.borderColor = NSColor(white: 1, alpha: 0.2).cgColor
        } else {
            sheen.colors = [NSColor(white: 1, alpha: 0.28).cgColor,
                            NSColor(white: 1, alpha: 0.08).cgColor,
                            NSColor.clear.cgColor]
            sheen.locations = [0, 0.3, 0.6]
            rimOuter.borderColor = NSColor(white: 0, alpha: 0.10).cgColor   // faint contour so the edge reads over white content
            rimInner.isHidden = false
            rimInner.borderColor = NSColor(white: 1, alpha: 0.5).cgColor    // specular inner edge (light catching the glass)
        }
    }
}

/// Native macOS "glass" chrome for auxiliary windows (Welcome, Guide, Upload, Preferences):
/// a behind-window translucent material running edge to edge under a transparent titlebar,
/// so they match the history panel / HUD look instead of a flat opaque window.
@MainActor
enum Glass {
    /// Replaces the window's content view with a glass background hosting `root`, and makes
    /// the titlebar transparent over it. SwiftUI content keeps respecting the titlebar via
    /// the hosting view's safe area.
    static func install<V: View>(_ root: V, in window: NSWindow,
                                 material: NSVisualEffectView.Material = .underWindowBackground) {
        let fx = NSVisualEffectView()
        fx.material = material
        fx.blendingMode = .behindWindow
        fx.state = .followsWindowActiveState
        let host = NSHostingView(rootView: root)
        host.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            host.topAnchor.constraint(equalTo: fx.topAnchor),
            host.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
        ])
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.contentView = fx
    }
}
