import Foundation
import Combine

/// Source of truth for keyboard navigation, shared between the AppKit
/// monitor (PanelController) and the SwiftUI view (HistoryView).
final class SelectionModel: ObservableObject {
    /// IDs in the SAME order the View's filtered list shows.
    @Published var visibleIDs: [UUID] = []
    /// Selected index within visibleIDs (-1 = nothing).
    @Published var selectedIndex: Int = 0
    /// Incremented each time the panel opens so the view resets search and focus.
    @Published var openToken: Int = 0
    /// Incremented to return focus to the search field WITHOUT clearing search/filter (e.g. after renaming).
    @Published var focusToken: Int = 0
    /// true while the panel is in batch multi-selection mode: the keyboard (Return / ⌘1-9) must NOT
    /// paste or close the panel (it would break the batch the user is assembling). Synced by HistoryView.
    @Published var selecting: Bool = false

    var visibleCount: Int { visibleIDs.count }

    var selectedID: UUID? {
        guard visibleIDs.indices.contains(selectedIndex) else { return nil }
        return visibleIDs[selectedIndex]
    }

    /// The View calls this when the filtered list changes.
    func updateVisible(_ ids: [UUID]) {
        // Re-anchor by ID: if the selected item is still visible, keep its selection
        // (prevents the selection from "jumping" when new captures come in); otherwise, go to the first.
        let prev = selectedID
        visibleIDs = ids
        if let prev, let i = ids.firstIndex(of: prev) { selectedIndex = i }
        else { selectedIndex = ids.isEmpty ? -1 : 0 }
    }

    func moveDown() {
        guard !visibleIDs.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, visibleIDs.count - 1)
    }

    func moveUp() {
        guard !visibleIDs.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    /// ⌘1..⌘9 → index 0..8 (if it exists).
    func selectQuick(_ n: Int) {
        let i = n - 1
        if visibleIDs.indices.contains(i) { selectedIndex = i }
    }

    func reset() {
        selectedIndex = visibleIDs.isEmpty ? -1 : 0
    }
}
