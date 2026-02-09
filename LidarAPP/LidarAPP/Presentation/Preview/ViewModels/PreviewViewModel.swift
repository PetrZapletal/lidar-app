import SwiftUI
import SceneKit
import simd

/// Rezim zobrazeni 3D modelu
enum DisplayMode: String, CaseIterable, Identifiable {
    case solid = "Solid"
    case wireframe = "Wireframe"
    case points = "Body"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .solid: return "cube.fill"
        case .wireframe: return "cube"
        case .points: return "circle.grid.3x3"
        }
    }

    var scnFillMode: SCNFillMode {
        switch self {
        case .solid: return .fill
        case .wireframe: return .lines
        case .points: return .fill
        }
    }
}

/// ViewModel pro nahled 3D modelu
@MainActor
@Observable
final class PreviewViewModel {

    // MARK: - Dependencies

    private let services: ServiceContainer

    // MARK: - State

    var meshData: MeshData?
    var isLoading: Bool = false
    var errorMessage: String?
    var displayMode: DisplayMode = .solid

    // MARK: - Init

    init(services: ServiceContainer) {
        self.services = services
    }

    // MARK: - Methods

    func loadMesh(from scan: ScanModel) {
        isLoading = true
        errorMessage = nil

        // Try to find mesh file via persistence
        for format in ExportFormat.allCases {
            if let url = services.persistence.scanFileURL(id: UUID(uuidString: scan.id) ?? UUID(), format: format) {
                debugLog("Found mesh file at \(url.path)", category: .logCategoryUI)
                break
            }
        }

        // For now meshData is set externally (e.g. from ScanSession.combinedMesh)
        isLoading = false
    }

    func setDisplayMode(_ mode: DisplayMode) {
        displayMode = mode
        debugLog("Display mode changed to \(mode.rawValue)", category: .logCategoryUI)
    }
}
