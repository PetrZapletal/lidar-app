import Foundation
import Metal
import MetalKit
import simd
import SwiftUI

// MARK: - Gaussian Splat Data Structures

/// Represents a single 3D Gaussian splat
struct GaussianSplat {
    var position: simd_float3
    var scale: simd_float3
    var rotation: simd_float4 // Quaternion
    var color: simd_float4 // RGBA with opacity
    var sphericalHarmonics: [Float]? // Optional SH coefficients for view-dependent color
}

/// Container for Gaussian splat scene data
struct GaussianSplatScene {
    var splats: [GaussianSplat]
    var boundingBox: BoundingBox
    var metadata: GaussianSplatMetadata

    var splatCount: Int { splats.count }

    init(splats: [GaussianSplat] = []) {
        self.splats = splats
        self.boundingBox = Self.calculateBoundingBox(from: splats)
        self.metadata = GaussianSplatMetadata()
    }

    private static func calculateBoundingBox(from splats: [GaussianSplat]) -> BoundingBox {
        guard !splats.isEmpty else {
            return BoundingBox(min: .zero, max: .zero)
        }

        var minPoint = simd_float3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxPoint = simd_float3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)

        for splat in splats {
            minPoint = simd_min(minPoint, splat.position - splat.scale)
            maxPoint = simd_max(maxPoint, splat.position + splat.scale)
        }

        return BoundingBox(min: minPoint, max: maxPoint)
    }
}

struct GaussianSplatMetadata {
    var sourceFormat: String = "PLY"
    var createdAt: Date = Date()
    var processingTime: TimeInterval = 0
    var originalImageCount: Int = 0
}

// MARK: - PLY Parser for Gaussian Splats

/// Parser for PLY files containing Gaussian splat data
class GaussianSplatPLYParser {

    enum ParseError: LocalizedError {
        case invalidHeader
        case invalidFormat
        case missingProperties
        case readError
        case unsupportedFormat(String)

        var errorDescription: String? {
            switch self {
            case .invalidHeader:
                return "Invalid PLY header"
            case .invalidFormat:
                return "Invalid PLY format"
            case .missingProperties:
                return "Missing required Gaussian splat properties"
            case .readError:
                return "Failed to read PLY data"
            case .unsupportedFormat(let format):
                return "Unsupported PLY format: \(format)"
            }
        }
    }

    /// Parse a PLY file containing Gaussian splat data
    static func parse(from url: URL) throws -> GaussianSplatScene {
        let data = try Data(contentsOf: url)
        return try parse(from: data)
    }

    /// Parse PLY data from memory
    static func parse(from data: Data) throws -> GaussianSplatScene {
        guard let content = String(data: data, encoding: .utf8) else {
            throw ParseError.readError
        }

        let lines = content.components(separatedBy: .newlines)
        var lineIndex = 0

        // Parse header
        guard lines[lineIndex] == "ply" else {
            throw ParseError.invalidHeader
        }
        lineIndex += 1

        var format: String = ""
        var vertexCount = 0
        var properties: [String] = []

        while lineIndex < lines.count {
            let line = lines[lineIndex].trimmingCharacters(in: .whitespaces)
            lineIndex += 1

            if line == "end_header" {
                break
            }

            let parts = line.components(separatedBy: " ")
            if parts.first == "format" {
                format = parts.dropFirst().joined(separator: " ")
            } else if parts.first == "element" && parts.count >= 3 && parts[1] == "vertex" {
                vertexCount = Int(parts[2]) ?? 0
            } else if parts.first == "property" && parts.count >= 3 {
                properties.append(parts.last ?? "")
            }
        }

        guard format.hasPrefix("ascii") || format.hasPrefix("binary_little_endian") else {
            throw ParseError.unsupportedFormat(format)
        }

        // Parse vertex data
        var splats: [GaussianSplat] = []
        splats.reserveCapacity(vertexCount)

        // For ASCII format
        if format.hasPrefix("ascii") {
            for _ in 0..<vertexCount {
                guard lineIndex < lines.count else { break }
                let line = lines[lineIndex].trimmingCharacters(in: .whitespaces)
                lineIndex += 1

                if line.isEmpty { continue }

                let values = line.components(separatedBy: .whitespaces).compactMap { Float($0) }
                if let splat = createSplat(from: values, properties: properties) {
                    splats.append(splat)
                }
            }
        }

        // Note: Binary format parsing would need additional implementation

        return GaussianSplatScene(splats: splats)
    }

    private static func createSplat(from values: [Float], properties: [String]) -> GaussianSplat? {
        guard values.count >= 3 else { return nil }

        // Standard Gaussian splat properties
        // x, y, z, nx, ny, nz, f_dc_0, f_dc_1, f_dc_2, opacity, scale_0, scale_1, scale_2, rot_0, rot_1, rot_2, rot_3

        var position = simd_float3(values[0], values[1], values[2])
        var scale = simd_float3(0.01, 0.01, 0.01) // Default scale
        var rotation = simd_float4(0, 0, 0, 1) // Identity quaternion
        var color = simd_float4(0.5, 0.5, 0.5, 1.0) // Default gray

        // Map properties to values
        for (idx, prop) in properties.enumerated() {
            guard idx < values.count else { break }
            let val = values[idx]

            switch prop {
            case "x": position.x = val
            case "y": position.y = val
            case "z": position.z = val
            case "scale_0": scale.x = exp(val) // Gaussian splats often use log scale
            case "scale_1": scale.y = exp(val)
            case "scale_2": scale.z = exp(val)
            case "rot_0": rotation.x = val
            case "rot_1": rotation.y = val
            case "rot_2": rotation.z = val
            case "rot_3": rotation.w = val
            case "f_dc_0": color.x = sigmoid(val) // DC component of spherical harmonics
            case "f_dc_1": color.y = sigmoid(val)
            case "f_dc_2": color.z = sigmoid(val)
            case "opacity": color.w = sigmoid(val)
            case "red": color.x = val / 255.0
            case "green": color.y = val / 255.0
            case "blue": color.z = val / 255.0
            case "alpha": color.w = val / 255.0
            default: break
            }
        }

        return GaussianSplat(
            position: position,
            scale: scale,
            rotation: rotation,
            color: color,
            sphericalHarmonics: nil
        )
    }

    private static func sigmoid(_ x: Float) -> Float {
        return 1.0 / (1.0 + exp(-x))
    }
}

// MARK: - Gaussian Splat Renderer

/// Metal-based renderer for 3D Gaussian splats
@MainActor
class GaussianSplatRenderer: ObservableObject {

    // MARK: - Configuration

    struct Configuration {
        var maxSplats: Int = 1_000_000
        var sortingEnabled: Bool = true
        var lodEnabled: Bool = true
        var lodDistanceThreshold: Float = 5.0
        var backgroundColor: simd_float4 = simd_float4(0.1, 0.1, 0.1, 1.0)
    }

    // MARK: - Properties

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?

    private var splatBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?

    @Published private(set) var isLoaded: Bool = false
    @Published private(set) var splatCount: Int = 0
    @Published private(set) var fps: Double = 0

    private var scene: GaussianSplatScene?
    private let configuration: Configuration

    private var lastFrameTime: CFTimeInterval = 0
    private var frameCount: Int = 0

    // MARK: - Initialization

    init(configuration: Configuration = Configuration()) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RendererError.metalNotAvailable
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.commandQueueCreationFailed
        }

        self.device = device
        self.commandQueue = commandQueue
        self.configuration = configuration

        try setupPipeline()
    }

    // MARK: - Setup

    private func setupPipeline() throws {
        // Create depth stencil state
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depthDescriptor)

        // Note: Full shader pipeline would be implemented here
        // For now, we rely on MetalSplatter library for actual rendering
        print("GaussianSplatRenderer initialized with Metal device: \(device.name)")
    }

    // MARK: - Loading

    /// Load Gaussian splat scene from PLY file
    func loadScene(from url: URL) async throws {
        let scene = try GaussianSplatPLYParser.parse(from: url)
        self.scene = scene
        self.splatCount = scene.splatCount
        self.isLoaded = true

        print("Loaded \(splatCount) Gaussian splats from \(url.lastPathComponent)")
    }

    /// Load Gaussian splat scene from data
    func loadScene(from data: Data) async throws {
        let scene = try GaussianSplatPLYParser.parse(from: data)
        self.scene = scene
        self.splatCount = scene.splatCount
        self.isLoaded = true

        print("Loaded \(splatCount) Gaussian splats from memory")
    }

    // MARK: - Rendering

    /// Render the scene to a Metal drawable
    func render(
        to drawable: CAMetalDrawable,
        viewMatrix: simd_float4x4,
        projectionMatrix: simd_float4x4,
        viewport: MTLViewport
    ) {
        guard isLoaded, let scene = scene else { return }

        let currentTime = CACurrentMediaTime()
        if lastFrameTime > 0 {
            frameCount += 1
            if currentTime - lastFrameTime >= 1.0 {
                fps = Double(frameCount)
                frameCount = 0
                lastFrameTime = currentTime
            }
        } else {
            lastFrameTime = currentTime
        }

        // Note: Actual rendering would use MetalSplatter or custom shaders
        // This is a placeholder for the rendering interface
    }

    // MARK: - Errors

    enum RendererError: LocalizedError {
        case metalNotAvailable
        case commandQueueCreationFailed
        case shaderCompilationFailed
        case bufferCreationFailed

        var errorDescription: String? {
            switch self {
            case .metalNotAvailable:
                return "Metal is not available on this device"
            case .commandQueueCreationFailed:
                return "Failed to create Metal command queue"
            case .shaderCompilationFailed:
                return "Failed to compile Metal shaders"
            case .bufferCreationFailed:
                return "Failed to create Metal buffer"
            }
        }
    }
}

// MARK: - SwiftUI View

/// SwiftUI view for displaying Gaussian splat scenes
struct GaussianSplatView: UIViewRepresentable {
    let scene: GaussianSplatScene?
    let cameraPosition: simd_float3
    let cameraRotation: simd_float4x4

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        mtkView.delegate = context.coordinator
        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.scene = scene
        context.coordinator.cameraPosition = cameraPosition
        context.coordinator.cameraRotation = cameraRotation
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, MTKViewDelegate {
        var scene: GaussianSplatScene?
        var cameraPosition: simd_float3 = simd_float3(0, 0, 2)
        var cameraRotation: simd_float4x4 = matrix_identity_float4x4

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Handle resize
        }

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor else {
                return
            }

            // Placeholder: Actual rendering would happen here
            // Using MetalSplatter or custom Gaussian splatting shader

            guard let commandBuffer = view.device?.makeCommandQueue()?.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                return
            }

            // Draw background
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct GaussianSplatView_Previews: PreviewProvider {
    static var previews: some View {
        GaussianSplatView(
            scene: nil,
            cameraPosition: simd_float3(0, 0, 2),
            cameraRotation: matrix_identity_float4x4
        )
    }
}
#endif
