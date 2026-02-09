import Foundation

/// Formáty exportu 3D modelu
enum ExportFormat: String, CaseIterable, Identifiable {
    case obj = "OBJ"
    case glb = "GLB"
    case usdz = "USDZ"
    case ply = "PLY"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .obj: return "obj"
        case .glb: return "glb"
        case .usdz: return "usdz"
        case .ply: return "ply"
        }
    }

    var mimeType: String {
        switch self {
        case .obj: return "application/x-obj"
        case .glb: return "model/gltf-binary"
        case .usdz: return "model/vnd.usdz+zip"
        case .ply: return "application/x-ply"
        }
    }
}

/// Protokol pro export 3D modelů
@MainActor
protocol ExportServiceProtocol: AnyObject {
    /// Exportuj mesh data do zvoleného formátu
    func export(meshData: MeshData, format: ExportFormat, name: String) async throws -> URL

    /// Exportuj point cloud do PLY
    func exportPointCloud(_ pointCloud: PointCloud, name: String) async throws -> URL

    /// Podporované formáty
    var supportedFormats: [ExportFormat] { get }
}


