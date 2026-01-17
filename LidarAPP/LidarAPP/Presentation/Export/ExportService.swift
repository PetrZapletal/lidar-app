import Foundation
import simd
import UIKit
import UniformTypeIdentifiers

/// Service for exporting scan data to various formats
actor ExportService {

    // MARK: - Export Result

    struct ExportResult {
        let url: URL
        let format: ExportFormat
        let fileSize: Int64
        let duration: TimeInterval
    }

    // MARK: - Export Options

    struct ExportOptions {
        var includeNormals: Bool = true
        var includeColors: Bool = true
        var includeTextures: Bool = true
        var simplifyMesh: Bool = false
        var simplificationRatio: Float = 0.5
        var coordinateSystem: CoordinateSystem = .yUp

        enum CoordinateSystem: String {
            case yUp = "Y-up"
            case zUp = "Z-up"
        }
    }

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let exportDirectory: URL

    init() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.exportDirectory = documentsURL.appendingPathComponent("Exports", isDirectory: true)

        try? fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Export Methods

    func exportMesh(
        _ meshData: MeshData,
        format: ExportFormat,
        name: String,
        options: ExportOptions = ExportOptions()
    ) async throws -> ExportResult {
        let startTime = CACurrentMediaTime()

        let fileName = "\(name)_\(Int(Date().timeIntervalSince1970)).\(format.rawValue)"
        let fileURL = exportDirectory.appendingPathComponent(fileName)

        switch format {
        case .obj:
            try await exportToOBJ(meshData, url: fileURL, options: options)
        case .ply:
            try await exportToPLY(meshData, url: fileURL, options: options)
        case .stl:
            try await exportToSTL(meshData, url: fileURL, options: options)
        case .gltf:
            try await exportToGLTF(meshData, url: fileURL, options: options)
        case .usdz:
            try await exportToUSDZ(meshData, url: fileURL, options: options)
        default:
            throw ExportError.unsupportedFormat(format)
        }

        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        return ExportResult(
            url: fileURL,
            format: format,
            fileSize: fileSize,
            duration: CACurrentMediaTime() - startTime
        )
    }

    func exportPointCloud(
        _ pointCloud: PointCloud,
        format: ExportFormat,
        name: String
    ) async throws -> ExportResult {
        let startTime = CACurrentMediaTime()

        let fileName = "\(name)_\(Int(Date().timeIntervalSince1970)).\(format.rawValue)"
        let fileURL = exportDirectory.appendingPathComponent(fileName)

        switch format {
        case .ply:
            try await exportPointCloudToPLY(pointCloud, url: fileURL)
        case .obj:
            try await exportPointCloudToOBJ(pointCloud, url: fileURL)
        default:
            throw ExportError.unsupportedFormat(format)
        }

        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        return ExportResult(
            url: fileURL,
            format: format,
            fileSize: fileSize,
            duration: CACurrentMediaTime() - startTime
        )
    }

    func exportMeasurements(
        _ measurements: [Measurement],
        format: ExportFormat,
        name: String
    ) async throws -> ExportResult {
        let startTime = CACurrentMediaTime()

        let fileName = "\(name)_measurements_\(Int(Date().timeIntervalSince1970)).\(format.rawValue)"
        let fileURL = exportDirectory.appendingPathComponent(fileName)

        switch format {
        case .json:
            try await exportMeasurementsToJSON(measurements, url: fileURL)
        case .csv:
            try await exportMeasurementsToCSV(measurements, url: fileURL)
        default:
            throw ExportError.unsupportedFormat(format)
        }

        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        return ExportResult(
            url: fileURL,
            format: format,
            fileSize: fileSize,
            duration: CACurrentMediaTime() - startTime
        )
    }

    // MARK: - OBJ Export

    private func exportToOBJ(_ mesh: MeshData, url: URL, options: ExportOptions) async throws {
        var content = "# Exported from LiDAR Scanner\n"
        content += "# Vertices: \(mesh.vertexCount)\n"
        content += "# Faces: \(mesh.faceCount)\n\n"

        // Write vertices
        for vertex in mesh.worldVertices {
            let v = options.coordinateSystem == .zUp ?
                simd_float3(vertex.x, -vertex.z, vertex.y) : vertex
            content += "v \(v.x) \(v.y) \(v.z)\n"
        }

        content += "\n"

        // Write normals
        if options.includeNormals {
            for normal in mesh.normals {
                let n = options.coordinateSystem == .zUp ?
                    simd_float3(normal.x, -normal.z, normal.y) : normal
                content += "vn \(n.x) \(n.y) \(n.z)\n"
            }
            content += "\n"
        }

        // Write faces
        for face in mesh.faces {
            if options.includeNormals {
                content += "f \(face.x + 1)//\(face.x + 1) \(face.y + 1)//\(face.y + 1) \(face.z + 1)//\(face.z + 1)\n"
            } else {
                content += "f \(face.x + 1) \(face.y + 1) \(face.z + 1)\n"
            }
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - PLY Export

    private func exportToPLY(_ mesh: MeshData, url: URL, options: ExportOptions) async throws {
        var header = "ply\n"
        header += "format ascii 1.0\n"
        header += "element vertex \(mesh.vertexCount)\n"
        header += "property float x\n"
        header += "property float y\n"
        header += "property float z\n"

        if options.includeNormals && !mesh.normals.isEmpty {
            header += "property float nx\n"
            header += "property float ny\n"
            header += "property float nz\n"
        }

        header += "element face \(mesh.faceCount)\n"
        header += "property list uchar int vertex_indices\n"
        header += "end_header\n"

        var content = header

        // Write vertices
        for (i, vertex) in mesh.worldVertices.enumerated() {
            var line = "\(vertex.x) \(vertex.y) \(vertex.z)"

            if options.includeNormals && i < mesh.normals.count {
                let n = mesh.normals[i]
                line += " \(n.x) \(n.y) \(n.z)"
            }

            content += line + "\n"
        }

        // Write faces
        for face in mesh.faces {
            content += "3 \(face.x) \(face.y) \(face.z)\n"
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - STL Export

    private func exportToSTL(_ mesh: MeshData, url: URL, options: ExportOptions) async throws {
        var content = "solid LiDARScan\n"

        for face in mesh.faces {
            let i0 = Int(face.x)
            let i1 = Int(face.y)
            let i2 = Int(face.z)

            guard i0 < mesh.vertices.count &&
                  i1 < mesh.vertices.count &&
                  i2 < mesh.vertices.count else {
                continue
            }

            let v0 = mesh.worldVertices[i0]
            let v1 = mesh.worldVertices[i1]
            let v2 = mesh.worldVertices[i2]

            // Calculate face normal
            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let normal = simd_normalize(simd_cross(edge1, edge2))

            content += "  facet normal \(normal.x) \(normal.y) \(normal.z)\n"
            content += "    outer loop\n"
            content += "      vertex \(v0.x) \(v0.y) \(v0.z)\n"
            content += "      vertex \(v1.x) \(v1.y) \(v1.z)\n"
            content += "      vertex \(v2.x) \(v2.y) \(v2.z)\n"
            content += "    endloop\n"
            content += "  endfacet\n"
        }

        content += "endsolid LiDARScan\n"

        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - glTF Export

    private func exportToGLTF(_ mesh: MeshData, url: URL, options: ExportOptions) async throws {
        // glTF is a JSON-based format with binary buffers
        // This is a simplified implementation

        let gltf: [String: Any] = [
            "asset": [
                "version": "2.0",
                "generator": "LiDAR Scanner"
            ],
            "scene": 0,
            "scenes": [
                ["nodes": [0]]
            ],
            "nodes": [
                ["mesh": 0, "name": "LiDARMesh"]
            ],
            "meshes": [
                [
                    "primitives": [
                        [
                            "attributes": ["POSITION": 0],
                            "indices": 1
                        ]
                    ]
                ]
            ],
            "buffers": [
                ["byteLength": mesh.vertexCount * 12 + mesh.faceCount * 12]
            ],
            "bufferViews": [
                ["buffer": 0, "byteOffset": 0, "byteLength": mesh.vertexCount * 12],
                ["buffer": 0, "byteOffset": mesh.vertexCount * 12, "byteLength": mesh.faceCount * 12]
            ],
            "accessors": [
                [
                    "bufferView": 0,
                    "componentType": 5126,  // FLOAT
                    "count": mesh.vertexCount,
                    "type": "VEC3"
                ],
                [
                    "bufferView": 1,
                    "componentType": 5125,  // UNSIGNED_INT
                    "count": mesh.faceCount * 3,
                    "type": "SCALAR"
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: gltf, options: .prettyPrinted)
        try data.write(to: url)
    }

    // MARK: - USDZ Export

    private func exportToUSDZ(_ mesh: MeshData, url: URL, options: ExportOptions) async throws {
        // USDZ export requires ModelIO or SceneKit
        // This is a placeholder - in production, use MDLAsset

        // For now, export as OBJ and note that USDZ requires conversion
        let objURL = url.deletingPathExtension().appendingPathExtension("obj")
        try await exportToOBJ(mesh, url: objURL, options: options)

        // In production, convert OBJ to USDZ using:
        // let asset = MDLAsset(url: objURL)
        // try asset.export(to: url)

        // Move OBJ to final URL for now
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: objURL, to: url)
    }

    // MARK: - Point Cloud Export

    private func exportPointCloudToPLY(_ pointCloud: PointCloud, url: URL) async throws {
        var header = "ply\n"
        header += "format ascii 1.0\n"
        header += "element vertex \(pointCloud.points.count)\n"
        header += "property float x\n"
        header += "property float y\n"
        header += "property float z\n"

        if let colors = pointCloud.colors {
            header += "property uchar red\n"
            header += "property uchar green\n"
            header += "property uchar blue\n"
        }

        header += "end_header\n"

        var content = header

        for (i, point) in pointCloud.points.enumerated() {
            var line = "\(point.x) \(point.y) \(point.z)"

            if let colors = pointCloud.colors, i < colors.count {
                let r = Int(colors[i].x * 255)
                let g = Int(colors[i].y * 255)
                let b = Int(colors[i].z * 255)
                line += " \(r) \(g) \(b)"
            }

            content += line + "\n"
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportPointCloudToOBJ(_ pointCloud: PointCloud, url: URL) async throws {
        var content = "# Point Cloud Export\n"
        content += "# Points: \(pointCloud.points.count)\n\n"

        for point in pointCloud.points {
            content += "v \(point.x) \(point.y) \(point.z)\n"
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Measurements Export

    private func exportMeasurementsToJSON(_ measurements: [Measurement], url: URL) async throws {
        let exportData = measurements.map { m -> [String: Any] in
            [
                "id": m.id.uuidString,
                "type": m.type.rawValue,
                "value": m.value,
                "unit": m.unit.rawValue,
                "label": m.label ?? "",
                "points": m.points.map { [$0.x, $0.y, $0.z] },
                "createdAt": ISO8601DateFormatter().string(from: m.createdAt)
            ]
        }

        let wrapper: [String: Any] = [
            "version": "1.0",
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "measurements": exportData
        ]

        let data = try JSONSerialization.data(withJSONObject: wrapper, options: .prettyPrinted)
        try data.write(to: url)
    }

    private func exportMeasurementsToCSV(_ measurements: [Measurement], url: URL) async throws {
        var csv = "ID,Type,Value,Unit,Label,Point1_X,Point1_Y,Point1_Z,Created\n"

        for m in measurements {
            let point = m.points.first ?? simd_float3.zero
            let line = "\(m.id.uuidString),\(m.type.rawValue),\(m.value),\(m.unit.rawValue),\(m.label ?? ""),\(point.x),\(point.y),\(point.z),\(ISO8601DateFormatter().string(from: m.createdAt))\n"
            csv += line
        }

        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Utilities

    func getExportedFiles() -> [URL] {
        (try? fileManager.contentsOfDirectory(at: exportDirectory, includingPropertiesForKeys: nil)) ?? []
    }

    func deleteExport(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func clearAllExports() throws {
        let files = getExportedFiles()
        for file in files {
            try fileManager.removeItem(at: file)
        }
    }

    func shareExport(_ url: URL) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
}

// MARK: - Errors

enum ExportError: LocalizedError {
    case unsupportedFormat(ExportFormat)
    case exportFailed(String)
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "Unsupported export format: \(format.rawValue)"
        case .exportFailed(let message):
            return "Export failed: \(message)"
        case .fileNotFound:
            return "File not found"
        }
    }
}
