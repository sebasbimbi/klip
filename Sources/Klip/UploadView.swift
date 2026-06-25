import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Window to upload audio files and transcribe them: drop zone + file picker.
struct UploadView: View {
    @ObservedObject var recorder: Recorder
    @ObservedObject var settings = Settings.shared   // re-localize live when the UI language changes
    var onChoose: () -> Void
    var onFiles: ([URL]) -> Void
    var onClose: () -> Void
    var onOpenPreferences: () -> Void

    @State private var hovering = false

    // Formats the transcribers actually accept. (Dropped aac/aiff: OpenAI rejects them and they'd fail
    // silently; .m4b is treated as .m4a on upload.)
    private let exts = ["m4a", "m4b", "mp3", "wav", "mp4", "flac", "ogg", "oga", "opus",
                        "webm", "mpga", "mpeg"]

    var body: some View {
        VStack(spacing: 14) {
            switch recorder.state {
            case .missingAPIKey:
                Image(systemName: "key.slash").font(.system(size: 34)).foregroundStyle(.orange)
                Text(L10n.t("rec.nokey.title")).font(.headline)
                HStack {
                    Button(L10n.t("common.close")) { onClose() }
                    Button(L10n.t("rec.openprefs")) { onOpenPreferences(); onClose() }.buttonStyle(.borderedProminent)
                }
            case .error(let m):
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 34)).foregroundStyle(.orange)
                Text(m).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(L10n.t("common.close")) { recorder.reset(); onClose() }
            default:
                Text(L10n.t("upload.title")).font(.headline)
                dropZone
                Text(L10n.t("upload.info"))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if recorder.transcribingCount > 0 {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text(recorder.preparingModel
                             ? L10n.t("upload.preparing")
                             : String(format: L10n.t(recorder.transcribingCount == 1 ? "upload.transcribing.one" : "upload.transcribing.many"), recorder.transcribingCount))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                }
                if !recorder.uploadResults.isEmpty { resultsSection }
                Button(L10n.t("common.close")) { onClose() }
            }
        }
        .frame(minWidth: 400, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity, alignment: .top)
        .padding()
    }

    /// The transcriptions of the just-uploaded files, filled in live as each one finishes.
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("upload.results")).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(recorder.uploadResults) { resultRow($0) }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private func resultRow(_ r: UploadTranscription) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "waveform").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(r.name).font(.system(size: 11, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if r.text == nil && !r.failed {
                    ProgressView().controlSize(.small)
                } else if r.failed {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange)
                } else {
                    Button { copyText(r.text ?? "") } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 11))
                    }
                    .buttonStyle(.borderless).help(L10n.t("row.copy"))
                }
            }
            if let t = r.text {
                Text(t).font(.system(size: 12)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).lineLimit(8)
            } else if r.failed {
                Text(L10n.t("upload.failed")).font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private func copyText(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc.fill").font(.system(size: 38))
                .foregroundStyle(hovering ? Color.accentColor : .secondary)
            Text(L10n.t("upload.drop")).font(.system(size: 14, weight: .medium))
            Text(L10n.t("upload.or")).font(.caption).foregroundStyle(.secondary)
            Button(L10n.t("upload.choose")) { onChoose() }
        }
        .frame(maxWidth: .infinity).frame(height: 150)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(hovering ? 0.12 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .foregroundStyle(hovering ? Color.accentColor : Color.secondary.opacity(0.5)))
        .onDrop(of: [UTType.fileURL], isTargeted: $hovering) { providers in
            handleDrop(providers); return true
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                // loadItem delivers its callback on an arbitrary internal queue and the providers run in
                // parallel: accumulating on main serializes the appends (Array is not thread-safe).
                let resolved: URL? = (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                    ?? (item as? URL)
                DispatchQueue.main.async {
                    if let resolved { urls.append(resolved) }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            let audio = urls.filter { exts.contains($0.pathExtension.lowercased()) }
            if !audio.isEmpty { onFiles(audio) }
        }
    }
}
