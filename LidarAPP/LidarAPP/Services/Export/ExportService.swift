import Foundation
import simd
import ModelIO

/// Service for exporting 3D mesh and point cloud data to various formats
@Observable
@MainActor
final class ExportService: ExportServiceProtocol {

    // MARK: - Properties

    var supportedFormats: [ExportFormat] { [.obj, .ply, .usdz] }

    private let fileManager = FileManager.default

    // MARK: - ExportServiceProtocol

    func export(meshData: MeshData, format: ExportFormat, name: String) async throws -> URL {
        guard !meshData.vertices.isEmpty else {
            throw ExportError.noData
        }

        let exportDir = fileManager.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let fileName = "\(name).\(format.fileExtension)"
        let fileURL = exportDir.appendingPathComponent(fileName)

        // Remove existing file if present
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }

        switch format {
        case .obj:
            try await exportOBJ(meshData, to: fileURL)
        case .ply:
            try await exportPLY(meshData, to: fileURL)
        case .usdz:
            try await exportUSDZ(meshData, to: fileURL)
        case .glb:
            throw ExportError.formatNotSupported(.glb)
        }

        debugLog("Exported \(format.rawValue): \(meshData.vertexCount) vertices, \(meshData.faceCount) faces -> \(fileName)", category: .logCategoryProcessing)
        return fileURL
    }

    func exportPointCloud(_ pointCloud: PointCloud, name: String) async throws -> URL {
        guard !pointCloud.points.isEmpty else {
            throw ExportError.noData
        }

        let exportDir = fileManager.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let fileName = "\(name).ply"
        let fileURL = exportDir.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }

        try await exportPointCloudPLY(pointCloud, to: fileURL)

        debugLog("Exported point cloud PLY: \(pointCloud.pointCount) points -> \(fileName)", category: .logCategoryProcessing)
        return fileURL
    }

    // MARK: - OBJ Export

    private func exportOBJ(_ mesh: MeshData, to url: URL) async throws {
        var content = "# LiDAR Scanner OBJ Export\n"
        content += "# Vertices: \(mesh.vertexCount)\n"
        content += "# Faces: \(mesh.faceCount)\n\n"

        // Vertices (world space)
        for vertex in mesh.worldVertices {
            content += "v \(vertex.x) \(vertex.y) \(vertex.z)\n"
        }
        content += "\n"

        // Normals
        if !mesh.normals.isEmpty {
            for normal in mesh.normals {
                content += "vn \(normal.x) \(normal.y) \(normal.z)\n"
            }
            content += "\n"
        }

        // Faces (1-indexed, with normals if available)
        let hasNormals = !mesh.normals.isEmpty
        for face in mesh.faces {
            if hasNormals {
                content += "f \(face.x + 1)//\(face.x + 1) \(face.y + 1)//\(face.y + 1) \(face.z + 1)//\(face.z + 1)\n"
            } else {
                content += "f \(face.x + 1) \(face.y + 1) \(face.z + 1)\n"
            }
        }

        guard let data = content.data(using: .utf8) else {
            throw ExportError.conversionFailed("Failed to encode OBJ data")
        }

        do {
            try data.write(to: url)
        } catch {
            throw ExportError.fileWriteFailed(url)
        }
    }

    // MARK: - PLY Export

    private func exportPLY(_ mesh: MeshData, to url: URL) async throws {
        let hasNormals = !mesh.normals.isEmpty

        var header = "ply\n"
        header += "format ascii 1.0\n"
        header += "comment LiDAR Scanner PLY Export\n"
        header += "element vertex \(mesh.vertexCount)\n"
        header += "property float x\n"
        header += "property float y\n"
        header += "property float z\n"

        if hasNormals {
            header += "property float nx\n"
            header += "property float ny\n"
            header += "property float nz\n"
        }

        // Add RGB from classification colors
        header += "property uchar red\n"
        header += "property uchar green\n"
        header += "property uchar blue\n"

        header += "element face \(mesh.faceCount)\n"
        header += "property list uchar int vertex_indices\n"
        header += "end_header\n"

        var content = header

        // Vertices with normals and colors
        let worldVerts = mesh.worldVertices
        for i in 0..<mesh.vertexCount {
            let v = worldVerts[i]
            var line = "\(v.x) \(v.y) \(v.z)"

            if hasNormals, i < mesh.normals.count {
                let n = mesh.normals[i]
                line += " \(n.x) \(n.y) \(n.z)"
            }

            // Default gray color; use classification if available
            var r: UInt8 = 180, g: UInt8 = 180, b: UInt8 = 180
            if let classifications = mesh.classifications, i < classifications.count {
                let cls = MeshClassification(rawValue: Int(classifications[i])) ?? .none
                let color = cls.color
                r = UInt8(min(max(color.x * 255, 0), 255))
                g = UInt8(min(max(color.y * 255, 0), 255))
                b = UInt8(min(max(color.z * 255, 0), 255))
            }
            line += " \(r) \(g) \(b)"

            content += line + "\n"
        }

        // Faces
        for face in mesh.faces {
            content += "3 \(face.x) \(face.y) \(face.z)\n"
        }

        guard let data = content.data(using: .utf8) else {
            throw ExportError.conversionFailed("Failed to encode PLY data")
        }

        do {
            try data.write(to: url)
        } catch {
            throw ExportError.fileWriteFailed(url)
        }
    }

    // MARK: - USDZ Export (ModelIO)

    private func exportUSDZ(_ mesh: MeshData, to url: URL) async throws {
        guard MDLAsset.canExportFileExtension("usdz") else {
            throw ExportError.modelIOError("USDZ export is not supported on this device")
        }

        let worldVertices = mesh.worldVertices
        let vertexCount = worldVertices.count
        let faceCount = mesh.faces.count

        guard vertexCount > 0, faceCount > 0 else {
            throw ExportError.noData
        }

        // Create allocator
        let allocator = MDLMeshBufferDataAllocator()

        // Vertex buffer: pack position + normal interleaved
        let hasNormals = !mesh.normals.isEmpty
        let vertexStride = hasNormals ? MemoryLayout<Float>.size * 6 : MemoryLayout<Float>.size * 3
        var vertexData = Data(count: vertexCount * vertexStride)

        vertexData.withUnsafeMutableBytes { ptr in
            let floats = ptr.bindMemory(to: Float.self)
            for i in 0..<vertexCount {
                let v = worldVertices[i]
                let base = hasNormals ? i * 6 : i * 3
                floats[base + 0] = v.x
                floats[base + 1] = v.y
                floats[base + 2] = v.z

                if hasNormals, i < mesh.normals.count {
                    let n = mesh.normals[i]
                    floats[base + 3] = n.x
                    floats[base + 4] = n.y
                    floats[base + 5] = n.z
                }
            }
        }

        let vertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)

        // Index buffer
        var indexData = Data(count: faceCount * 3 * MemoryLayout<UInt32>.size)
        indexData.withUnsafeMutableBytes { ptr in
            let indices = ptr.bindMemory(to: UInt32.self)
            for i in 0..<faceCount {
                let face = mesh.faces[i]
                indices[i * 3 + 0] = face.x
                indices[i * 3 + 1] = face.y
                indices[i * 3 + 2] = face.z
            }
        }

        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)

        // Vertex descriptor
        let descriptor = MDLVertexDescriptor()

        let positionAttr = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        descriptor.attributes[0] = positionAttr

        if hasNormals {
            let normalAttr = MDLVertexAttribute(
                name: MDLVertexAttributeNormal,
                format: .float3,
                offset: MemoryLayout<Float>.size * 3,
                bufferIndex: 0
            )
            descriptor.attributes[1] = normalAttr
        }

        let layout = MDLVertexBufferLayout(stride: vertexStride)
        descriptor.layouts[0] = layout

        // Create submesh
        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: faceCount * 3,
            indexType: .uInt32,
            geometryType: .triangles,
            material: nil
        )

        // Create MDLMesh
        let mdlMesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: vertexCount,
            descriptor: descriptor,
            submeshes: [submesh]
        )

        // Create asset and export
        let asset = MDLAsset()
        asset.add(mdlMesh)

        let usdzURL = url.deletingPathExtension().appendingPathExtension("usdz")

        do {
            try asset.export(to: usdzURL)
        } catch {
            errorLog("ModelIO USDZ export failed: \(error.localizedDescription)", category: .logCategoryProcessing)
            throw ExportError.modelIOError(error.localizedDescription)
        }

        // If the export wrote to a different path, move it
        if usdzURL != url && fileManager.fileExists(atPath: usdzURL.path) {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.moveItem(at: usdzURL, to: url)
        }

        guard fileManager.fileExists(atPath: url.path) else {
            throw ExportError.modelIOError("USDZ file was not created")
        }
    }

    // MARK: - Point Cloud PLY Export

    private func exportPointCloudPLY(_ pointCloud: PointCloud, to url: URL) async throws {
        let hasColors = pointCloud.colors != nil
        let hasNormals = pointCloud.normals != nil

        var header = "ply\n"
        header += "format ascii 1.0\n"
        header += "comment LiDAR Scanner Point Cloud Export\n"
        header += "element vertex \(pointCloud.pointCount)\n"
        header += "property float x\n"
        header += "property float y\n"
        header += "property float z\n"

        if hasNormals {
            header += "property float nx\n"
            header += "property float ny\n"
            header += "property float nz\n"
        }

        if hasColors {
            header += "property uchar red\n"
            header += "property uchar green\n"
            header += "property uchar blue\n"
        }

        header += "end_header\n"

        var content = header

        for i in 0..<pointCloud.pointCount {
            let p = pointCloud.points[i]
            var line = "\(p.x) \(p.y) \(p.z)"

            if let normals = pointCloud.normals, i < normals.count {
                let n = normals[i]
                line += " \(n.x) \(n.y) \(n.z)"
            }

            if let colors = pointCloud.colors, i < colors.count {
                let r = Int(min(max(colors[i].x * 255, 0), 255))
                let g = Int(min(max(colors[i].y * 255, 0), 255))
                let b = Int(min(max(colors[i].z * 255, 0), 255))
                line += " \(r) \(g) \(b)"
            }

            content += line + "\n"
        }

        guard let data = content.data(using: .utf8) else {
            throw ExportError.conversionFailed("Failed to encode point cloud PLY data")
        }

        do {
            try data.write(to: url)
        } catch {
            throw ExportError.fileWriteFailed(url)
        }
    }
}
