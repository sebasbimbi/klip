import Foundation
import Combine

/// Fuente de verdad para la navegación por teclado, compartida entre el monitor
/// AppKit (PanelController) y la vista SwiftUI (HistoryView).
final class SelectionModel: ObservableObject {
    /// IDs en el MISMO orden en que la lista filtrada de la vista los muestra.
    @Published var visibleIDs: [UUID] = []
    /// Índice seleccionado dentro de visibleIDs (-1 = nada).
    @Published var selectedIndex: Int = 0
    /// Se incrementa cada vez que el panel se abre para que la vista reinicie búsqueda y foco.
    @Published var openToken: Int = 0
    /// Se incrementa para devolver el foco al campo de búsqueda SIN limpiar búsqueda/filtro (p. ej. tras renombrar).
    @Published var focusToken: Int = 0
    /// true mientras el panel está en modo multi-selección por lotes: el teclado (Return / ⌘1-9) NO debe
    /// pegar ni cerrar el panel (rompería el lote que el usuario está armando). Sincronizado por HistoryView.
    @Published var selecting: Bool = false

    var selectedID: UUID? {
        guard visibleIDs.indices.contains(selectedIndex) else { return nil }
        return visibleIDs[selectedIndex]
    }

    /// La vista llama a esto cuando la lista filtrada cambia.
    func updateVisible(_ ids: [UUID]) {
        // Re-anclar por ID: si el ítem seleccionado sigue visible, mantener su selección
        // (evita que la selección "salte" cuando entran capturas nuevas); si no, ir al primero.
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

    func reset() {
        selectedIndex = visibleIDs.isEmpty ? -1 : 0
    }
}
