import SwiftUI

/// Floating HUD shown while a meeting records: live level meters for BOTH sources (proof that
/// your mic AND the meeting's system audio are being heard), elapsed time, and stop/discard.
/// Collapsible to a compact pill (● time + micro meters) so it can stay on screen for a whole
/// meeting without covering the call.
struct MeetingHUDView: View {
    @ObservedObject var recorder: MeetingRecorder
    var onStop: () -> Void
    var onDiscard: () -> Void
    /// Asks the panel to resize for the compact/expanded layout.
    var onToggleCompact: (Bool) -> Void

    @State private var compact = false
    @State private var pulse = false
    /// Last time the system side showed real signal — drives the "no meeting audio yet" hint.
    @State private var lastSystemSignal = Date()

    private var mmss: String {
        let s = Int(recorder.elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var body: some View {
        Group {
            if compact { pill } else { card }
        }
        .onAppear { pulse = true; lastSystemSignal = Date() }
        // The hosting view is reused across meetings (the panel is only ordered out), so @State
        // survives: a new meeting must start expanded with fresh pulse/hint state.
        .onChange(of: recorder.isRecording) { _, rec in
            guard rec else { return }
            pulse = true
            lastSystemSignal = Date()
            if compact { setCompact(false) }
        }
        .onChange(of: recorder.systemLevel) { _, lvl in
            if lvl > 0.06 { lastSystemSignal = Date() }
        }
    }

    // MARK: - Compact pill (click to expand)

    private var pill: some View {
        HStack(spacing: 8) {
            recordDot
            Text(mmss).font(.system(size: 12, weight: .semibold).monospacedDigit())
            // Micro meters: still proof-of-life for both sources, just tiny.
            VStack(spacing: 2.5) {
                microMeter(level: recorder.micLevel, tint: .accentColor)
                microMeter(level: recorder.systemLevel, tint: .teal)
            }
            .frame(width: 34)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { setCompact(false) }
        .help(L10n.t("meeting.recording"))
    }

    private func microMeter(level: Float, tint: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule().fill(tint)
                    .frame(width: max(2, geo.size.width * CGFloat(min(1, level))))
                    .animation(.linear(duration: 0.1), value: level)
            }
        }
        .frame(height: 3)
    }

    // MARK: - Expanded card

    private var card: some View {
        VStack(spacing: 12) {
            if recorder.finishing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("meeting.finishing")).font(.system(size: 12, weight: .medium))
                }
                .padding(.vertical, 6)
                .transition(.opacity)
            } else {
                HStack(spacing: 8) {
                    recordDot
                    Text(L10n.t("meeting.recording")).font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(mmss).font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help(L10n.t("meeting.autostop.tip"))
                    Button { setCompact(true) } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("meeting.recording"))
                }

                meter(label: L10n.t("meeting.me"), icon: "mic.fill", level: recorder.micLevel, tint: .accentColor)
                meter(label: L10n.t("meeting.them"), icon: "speaker.wave.2.fill", level: recorder.systemLevel, tint: .teal)

                // One-line legend: first-time users shouldn't have to guess what the two bars are.
                Text(L10n.t("meeting.sources.hint"))
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // The system side heard nothing for a while: surface it — this is exactly the doubt
                // ("is it capturing them at all?") this HUD exists to answer.
                if Date().timeIntervalSince(lastSystemSignal) > 10, recorder.elapsed > 8 {
                    Label(L10n.t("meeting.nosystem"), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    Button(role: .destructive) { onDiscard() } label: {
                        Text(L10n.t("editor.discard.confirm")).font(.system(size: 11.5))
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Spacer(minLength: 8)
                    Button { onStop() } label: {
                        Label(L10n.t("rec.stop"), systemImage: "stop.fill").font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(14)
        .frame(width: 264)
        // Cross-fade into the finishing state instead of jumping.
        .animation(.easeOut(duration: 0.13), value: recorder.finishing)
    }

    private var recordDot: some View {
        Circle().fill(.red).frame(width: 9, height: 9)
            .opacity(pulse ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
    }

    private func setCompact(_ value: Bool) {
        compact = value
        onToggleCompact(value)
    }

    private func meter(label: String, icon: String, level: Float, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(width: 14)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading).lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                        // Subtle rounded track highlight: gives the empty track a defined edge.
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
                    Capsule().fill(tint)
                        .frame(width: max(3, geo.size.width * CGFloat(min(1, level))))
                        .animation(.linear(duration: 0.1), value: level)
                }
            }
            .frame(height: 6)
        }
    }
}
