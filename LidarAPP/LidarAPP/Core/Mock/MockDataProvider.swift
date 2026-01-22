import Foundation
import simd

/// Provides mock data for simulator testing
final class MockDataProvider {

    // MARK: - Singleton

    static let shared = MockDataProvider()

    private init() {}

    // MARK: - Mock Mode Configuration

    /// Enable/disable mock mode globally
    static var isMockModeEnabled: Bool {
        get {
            #if targetEnvironment(simulator)
            return UserDefaults.standard.bool(forKey: "MockModeEnabled", defaultValue: true)
            #else
            return UserDefaults.standard.bool(forKey: "MockModeEnabled", defaultValue: false)
            #endif
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "MockModeEnabled")
        }
    }

    /// Check if running on simulator
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Sample Point Cloud

    /// Generate a sample point cloud (cube shape)
    func generateSamplePointCloud(pointCount: Int = 10000) -> PointCloud {
        var points: [simd_float3] = []
        var colors: [simd_float4] = []
        var confidences: [Float] = []

        // Generate points on cube surface
        let size: Float = 1.0
        let pointsPerFace = pointCount / 6

        for face in 0..<6 {
            for _ in 0..<pointsPerFace {
                let u = Float.random(in: -size/2...size/2)
                let v = Float.random(in: -size/2...size/2)

                var point: simd_float3
                var color: simd_float4

                switch face {
                case 0: // Front
                    point = simd_float3(u, v, size/2)
                    color = simd_float4(1, 0, 0, 1) // Red
                case 1: // Back
                    point = simd_float3(u, v, -size/2)
                    color = simd_float4(0, 1, 0, 1) // Green
                case 2: // Left
                    point = simd_float3(-size/2, u, v)
                    color = simd_float4(0, 0, 1, 1) // Blue
                case 3: // Right
                    point = simd_float3(size/2, u, v)
                    color = simd_float4(1, 1, 0, 1) // Yellow
                case 4: // Top
                    point = simd_float3(u, size/2, v)
                    color = simd_float4(1, 0, 1, 1) // Magenta
                default: // Bottom
                    point = simd_float3(u, -size/2, v)
                    color = simd_float4(0, 1, 1, 1) // Cyan
                }

                // Add some noise
                point += simd_float3(
                    Float.random(in: -0.01...0.01),
                    Float.random(in: -0.01...0.01),
                    Float.random(in: -0.01...0.01)
                )

                points.append(point)
                colors.append(color)
                confidences.append(Float.random(in: 0.7...1.0))
            }
        }

        return PointCloud(
            points: points,
            colors: colors,
            confidences: confidences
        )
    }

    /// Generate an object point cloud (sphere-like shape for object scanning)
    func generateObjectPointCloud(
        radius: Float = 0.3,
        pointCount: Int = 5000
    ) -> PointCloud {
        var points: [simd_float3] = []
        var colors: [simd_float4] = []

        // Generate points on a sphere surface
        for _ in 0..<pointCount {
            // Random spherical coordinates
            let theta = Float.random(in: 0...(2 * .pi))
            let phi = Float.random(in: 0...Float.pi)

            // Convert to Cartesian
            let x = radius * sin(phi) * cos(theta)
            let y = radius * sin(phi) * sin(theta)
            let z = radius * cos(phi)

            // Add some noise for realism
            let noise = simd_float3(
                Float.random(in: -0.005...0.005),
                Float.random(in: -0.005...0.005),
                Float.random(in: -0.005...0.005)
            )

            points.append(simd_float3(x, y, z) + noise)

            // Color based on position (gradient effect)
            let r = (x / radius + 1) / 2
            let g = (y / radius + 1) / 2
            let b = (z / radius + 1) / 2
            colors.append(simd_float4(r, g, b, 1))
        }

        return PointCloud(
            points: points,
            colors: colors,
            confidences: nil
        )
    }

    /// Generate a room-like point cloud
    func generateRoomPointCloud(
        width: Float = 4.0,
        height: Float = 2.5,
        depth: Float = 5.0,
        pointDensity: Int = 5000
    ) -> PointCloud {
        var points: [simd_float3] = []
        var colors: [simd_float4] = []

        // Floor
        let floorPoints = pointDensity
        for _ in 0..<floorPoints {
            let x = Float.random(in: -width/2...width/2)
            let z = Float.random(in: -depth/2...depth/2)
            points.append(simd_float3(x, 0, z))
            colors.append(simd_float4(0.6, 0.4, 0.2, 1)) // Brown floor
        }

        // Walls
        let wallPoints = pointDensity / 2
        for _ in 0..<wallPoints {
            // Back wall
            let x = Float.random(in: -width/2...width/2)
            let y = Float.random(in: 0...height)
            points.append(simd_float3(x, y, -depth/2))
            colors.append(simd_float4(0.9, 0.9, 0.85, 1)) // Light wall
        }

        for _ in 0..<wallPoints {
            // Left wall
            let y = Float.random(in: 0...height)
            let z = Float.random(in: -depth/2...depth/2)
            points.append(simd_float3(-width/2, y, z))
            colors.append(simd_float4(0.85, 0.85, 0.9, 1))
        }

        for _ in 0..<wallPoints {
            // Right wall
            let y = Float.random(in: 0...height)
            let z = Float.random(in: -depth/2...depth/2)
            points.append(simd_float3(width/2, y, z))
            colors.append(simd_float4(0.85, 0.9, 0.85, 1))
        }

        // Ceiling
        let ceilingPoints = pointDensity / 2
        for _ in 0..<ceilingPoints {
            let x = Float.random(in: -width/2...width/2)
            let z = Float.random(in: -depth/2...depth/2)
            points.append(simd_float3(x, height, z))
            colors.append(simd_float4(0.95, 0.95, 0.95, 1)) // White ceiling
        }

        return PointCloud(
            points: points,
            colors: colors,
            confidences: nil
        )
    }

    // MARK: - Sample Mesh

    /// Generate a sample cube mesh
    func generateSampleMesh() -> MeshData {
        let size: Float = 0.5

        let vertices: [simd_float3] = [
            // Front face
            simd_float3(-size, -size,  size),
            simd_float3( size, -size,  size),
            simd_float3( size,  size,  size),
            simd_float3(-size,  size,  size),
            // Back face
            simd_float3(-size, -size, -size),
            simd_float3(-size,  size, -size),
            simd_float3( size,  size, -size),
            simd_float3( size, -size, -size),
        ]

        let normals: [simd_float3] = [
            simd_float3(0, 0, 1),
            simd_float3(0, 0, 1),
            simd_float3(0, 0, 1),
            simd_float3(0, 0, 1),
            simd_float3(0, 0, -1),
            simd_float3(0, 0, -1),
            simd_float3(0, 0, -1),
            simd_float3(0, 0, -1),
        ]

        let faces: [simd_uint3] = [
            // Front
            simd_uint3(0, 1, 2),
            simd_uint3(2, 3, 0),
            // Back
            simd_uint3(4, 5, 6),
            simd_uint3(6, 7, 4),
            // Top
            simd_uint3(3, 2, 6),
            simd_uint3(6, 5, 3),
            // Bottom
            simd_uint3(4, 7, 1),
            simd_uint3(1, 0, 4),
            // Right
            simd_uint3(1, 7, 6),
            simd_uint3(6, 2, 1),
            // Left
            simd_uint3(4, 0, 3),
            simd_uint3(3, 5, 4),
        ]

        return MeshData(
            anchorIdentifier: UUID(),
            vertices: vertices,
            normals: normals,
            faces: faces
        )
    }

    /// Generate a floor plane mesh
    func generateFloorMesh(width: Float = 4.0, depth: Float = 5.0, subdivisions: Int = 10) -> MeshData {
        var vertices: [simd_float3] = []
        var normals: [simd_float3] = []
        var faces: [simd_uint3] = []

        let stepX = width / Float(subdivisions)
        let stepZ = depth / Float(subdivisions)

        // Generate vertices
        for z in 0...subdivisions {
            for x in 0...subdivisions {
                let posX = -width/2 + Float(x) * stepX
                let posZ = -depth/2 + Float(z) * stepZ
                vertices.append(simd_float3(posX, 0, posZ))
                normals.append(simd_float3(0, 1, 0))
            }
        }

        // Generate faces
        for z in 0..<subdivisions {
            for x in 0..<subdivisions {
                let topLeft = UInt32(z * (subdivisions + 1) + x)
                let topRight = topLeft + 1
                let bottomLeft = topLeft + UInt32(subdivisions + 1)
                let bottomRight = bottomLeft + 1

                faces.append(simd_uint3(topLeft, bottomLeft, topRight))
                faces.append(simd_uint3(topRight, bottomLeft, bottomRight))
            }
        }

        return MeshData(
            anchorIdentifier: UUID(),
            vertices: vertices,
            normals: normals,
            faces: faces
        )
    }

    // MARK: - Sample Measurements

    /// Generate sample measurements
    func generateSampleMeasurements() -> [Measurement] {
        [
            Measurement(
                type: .distance,
                points: [simd_float3(0, 0, 0), simd_float3(2.5, 0, 0)],
                value: 2.5,
                unit: .meters,
                label: "Wall width"
            ),
            Measurement(
                type: .distance,
                points: [simd_float3(0, 0, 0), simd_float3(0, 2.4, 0)],
                value: 2.4,
                unit: .meters,
                label: "Room height"
            ),
            Measurement(
                type: .area,
                points: [
                    simd_float3(-2, 0, -2.5),
                    simd_float3(2, 0, -2.5),
                    simd_float3(2, 0, 2.5),
                    simd_float3(-2, 0, 2.5)
                ],
                value: 20.0,
                unit: .meters,
                label: "Floor area"
            ),
            Measurement(
                type: .volume,
                points: [simd_float3(0, 0, 0)],
                value: 48.0,
                unit: .meters,
                label: "Room volume"
            )
        ]
    }

    // MARK: - Sample Scan Session

    /// Create a complete mock scan session
    func createMockScanSession(name: String = "Mock Scan") -> ScanSession {
        let session = ScanSession(name: name)

        // Add point cloud
        session.pointCloud = generateRoomPointCloud()

        // Add meshes
        let floorMesh = generateFloorMesh()
        session.addMesh(floorMesh)

        let cubeMesh = generateSampleMesh()
        session.addMesh(cubeMesh)

        // Add measurements
        for measurement in generateSampleMeasurements() {
            session.addMeasurement(measurement)
        }

        // Simulate completed scan
        session.startScanning()
        session.stopScanning()

        return session
    }
}

// MARK: - UserDefaults Extension

private extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if object(forKey: key) == nil {
            return defaultValue
        }
        return bool(forKey: key)
    }
}
