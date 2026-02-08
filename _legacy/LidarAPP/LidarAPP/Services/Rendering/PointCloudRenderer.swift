import Metal
import MetalKit
import simd

/// Metal-based real-time point cloud renderer
final class PointCloudRenderer {

    // MARK: - Configuration

    struct Configuration {
        var pointSize: Float = 4.0
        var maxPoints: Int = 1_000_000
        var colorMode: ColorMode = .confidence
        var enableDepthTest: Bool = true
        var backgroundColor: simd_float4 = simd_float4(0.1, 0.1, 0.1, 1.0)

        enum ColorMode: Int {
            case uniform = 0
            case confidence = 1
            case depth = 2
            case normal = 3
            case classification = 4
            case rgb = 5
        }
    }

    // MARK: - Vertex Data

    struct PointVertex {
        var position: simd_float3
        var color: simd_float4
        var size: Float

        init(position: simd_float3, color: simd_float4 = simd_float4(1, 1, 1, 1), size: Float = 1.0) {
            self.position = position
            self.color = color
            self.size = size
        }
    }

    struct Uniforms {
        var modelViewProjectionMatrix: simd_float4x4
        var modelViewMatrix: simd_float4x4
        var pointSize: Float
        var colorMode: Int32
        var padding: simd_float2 = .zero
    }

    // MARK: - Metal Objects

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?

    private var vertexBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?

    private var pointCount: Int = 0
    private var configuration: Configuration

    // MARK: - Initialization

    init?(configuration: Configuration = Configuration()) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue
        self.configuration = configuration

        setupPipeline()
        setupDepthState()
        setupBuffers()
    }

    // MARK: - Setup

    private func setupPipeline() {
        guard let library = device.makeDefaultLibrary() else {
            // Use runtime-compiled shaders if library not found
            setupPipelineWithSource()
            return
        }

        let vertexFunction = library.makeFunction(name: "pointCloudVertex")
        let fragmentFunction = library.makeFunction(name: "pointCloudFragment")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        // Enable blending for transparency
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        // Vertex descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = MemoryLayout<simd_float3>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0

        vertexDescriptor.attributes[2].format = .float
        vertexDescriptor.attributes[2].offset = MemoryLayout<simd_float3>.stride + MemoryLayout<simd_float4>.stride
        vertexDescriptor.attributes[2].bufferIndex = 0

        vertexDescriptor.layouts[0].stride = MemoryLayout<PointVertex>.stride
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }

    private func setupPipelineWithSource() {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct PointVertex {
            float3 position [[attribute(0)]];
            float4 color [[attribute(1)]];
            float size [[attribute(2)]];
        };

        struct Uniforms {
            float4x4 modelViewProjectionMatrix;
            float4x4 modelViewMatrix;
            float pointSize;
            int colorMode;
            float2 padding;
        };

        struct VertexOut {
            float4 position [[position]];
            float4 color;
            float pointSize [[point_size]];
        };

        vertex VertexOut pointCloudVertex(PointVertex in [[stage_in]],
                                          constant Uniforms &uniforms [[buffer(1)]]) {
            VertexOut out;
            out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
            out.color = in.color;
            out.pointSize = uniforms.pointSize * in.size;
            return out;
        }

        fragment float4 pointCloudFragment(VertexOut in [[stage_in]],
                                           float2 pointCoord [[point_coord]]) {
            // Circular point with soft edge
            float dist = length(pointCoord - float2(0.5));
            if (dist > 0.5) {
                discard_fragment();
            }

            float alpha = 1.0 - smoothstep(0.3, 0.5, dist);
            return float4(in.color.rgb, in.color.a * alpha);
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)

            let vertexFunction = library.makeFunction(name: "pointCloudVertex")
            let fragmentFunction = library.makeFunction(name: "pointCloudFragment")

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

            // Enable blending
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha

            // Vertex descriptor
            let vertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].format = .float3
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0

            vertexDescriptor.attributes[1].format = .float4
            vertexDescriptor.attributes[1].offset = MemoryLayout<simd_float3>.stride
            vertexDescriptor.attributes[1].bufferIndex = 0

            vertexDescriptor.attributes[2].format = .float
            vertexDescriptor.attributes[2].offset = MemoryLayout<simd_float3>.stride + MemoryLayout<simd_float4>.stride
            vertexDescriptor.attributes[2].bufferIndex = 0

            vertexDescriptor.layouts[0].stride = MemoryLayout<PointVertex>.stride

            pipelineDescriptor.vertexDescriptor = vertexDescriptor

            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline with source: \(error)")
        }
    }

    private func setupDepthState() {
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = configuration.enableDepthTest ? .less : .always
        depthDescriptor.isDepthWriteEnabled = configuration.enableDepthTest

        depthState = device.makeDepthStencilState(descriptor: depthDescriptor)
    }

    private func setupBuffers() {
        // Pre-allocate vertex buffer for max points
        let bufferSize = MemoryLayout<PointVertex>.stride * configuration.maxPoints
        vertexBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)

        // Uniform buffer
        uniformBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.stride, options: .storageModeShared)
    }

    // MARK: - Update Point Cloud

    func updatePointCloud(_ pointCloud: PointCloud) {
        let points = pointCloud.points
        pointCount = min(points.count, configuration.maxPoints)

        guard pointCount > 0, let buffer = vertexBuffer else { return }

        let vertices = buffer.contents().bindMemory(to: PointVertex.self, capacity: pointCount)

        for i in 0..<pointCount {
            let position = points[i]
            let color = colorForPoint(at: i, in: pointCloud)

            vertices[i] = PointVertex(
                position: position,
                color: color,
                size: 1.0
            )
        }
    }

    func updatePointCloud(points: [simd_float3], colors: [simd_float4]? = nil) {
        pointCount = min(points.count, configuration.maxPoints)

        guard pointCount > 0, let buffer = vertexBuffer else { return }

        let vertices = buffer.contents().bindMemory(to: PointVertex.self, capacity: pointCount)

        for i in 0..<pointCount {
            let color = colors?[safe: i] ?? simd_float4(1, 1, 1, 1)

            vertices[i] = PointVertex(
                position: points[i],
                color: color,
                size: 1.0
            )
        }
    }

    // MARK: - Color Modes

    private func colorForPoint(at index: Int, in pointCloud: PointCloud) -> simd_float4 {
        switch configuration.colorMode {
        case .uniform:
            return simd_float4(0.3, 0.7, 1.0, 1.0)  // Light blue

        case .confidence:
            if let confidences = pointCloud.confidences, index < confidences.count {
                let c = confidences[index]
                return simd_float4(1 - c, c, 0, 1)  // Red to green
            }
            return simd_float4(0.5, 0.5, 0.5, 1.0)

        case .depth:
            if let bbox = pointCloud.boundingBox {
                let point = pointCloud.points[index]
                let normalizedDepth = (point.z - bbox.min.z) / (bbox.max.z - bbox.min.z)
                return depthToColor(normalizedDepth)
            }
            return simd_float4(0.5, 0.5, 0.5, 1.0)

        case .normal:
            if let normals = pointCloud.normals, index < normals.count {
                let n = normals[index]
                return simd_float4(
                    (n.x + 1) / 2,
                    (n.y + 1) / 2,
                    (n.z + 1) / 2,
                    1.0
                )
            }
            return simd_float4(0.5, 0.5, 1.0, 1.0)

        case .classification:
            // TODO: Implement classification coloring
            return simd_float4(0.5, 0.5, 0.5, 1.0)

        case .rgb:
            if let colors = pointCloud.colors, index < colors.count {
                return colors[index]
            }
            return simd_float4(1, 1, 1, 1)
        }
    }

    private func depthToColor(_ depth: Float) -> simd_float4 {
        // Turbo colormap approximation
        let t = simd_clamp(depth, 0, 1)

        let r = simd_clamp(0.84 - 0.84 * cos(3.14159 * (t * 0.8 + 0.2)), 0, 1)
        let g = simd_clamp(sin(3.14159 * t), 0, 1)
        let b = simd_clamp(0.84 * cos(3.14159 * (t * 0.8)), 0, 1)

        return simd_float4(Float(r), Float(g), Float(b), 1.0)
    }

    // MARK: - Rendering

    func render(
        in view: MTKView,
        viewMatrix: simd_float4x4,
        projectionMatrix: simd_float4x4
    ) {
        guard pointCount > 0,
              let pipelineState = pipelineState,
              let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        // Update uniforms
        let modelViewProjection = projectionMatrix * viewMatrix
        var uniforms = Uniforms(
            modelViewProjectionMatrix: modelViewProjection,
            modelViewMatrix: viewMatrix,
            pointSize: configuration.pointSize,
            colorMode: Int32(configuration.colorMode.rawValue)
        )

        uniformBuffer?.contents().copyMemory(
            from: &uniforms,
            byteCount: MemoryLayout<Uniforms>.stride
        )

        // Render
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)

        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)

        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: pointCount)

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Configuration

    func setPointSize(_ size: Float) {
        configuration.pointSize = size
    }

    func setColorMode(_ mode: Configuration.ColorMode) {
        configuration.colorMode = mode
    }

    func setDepthTestEnabled(_ enabled: Bool) {
        configuration.enableDepthTest = enabled
        setupDepthState()
    }

    // MARK: - Statistics

    var currentPointCount: Int {
        pointCount
    }

    var maxPointCount: Int {
        configuration.maxPoints
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
