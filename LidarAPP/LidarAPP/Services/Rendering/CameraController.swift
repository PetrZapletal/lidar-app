import Foundation
import simd
import UIKit

/// Controls 3D camera for orbit, pan, and zoom interactions
@MainActor
@Observable
final class CameraController {

    // MARK: - Configuration

    struct Configuration {
        var minDistance: Float = 0.5
        var maxDistance: Float = 20.0
        var panSpeed: Float = 0.005
        var rotateSpeed: Float = 0.005
        var zoomSpeed: Float = 0.1
        var momentumDecay: Float = 0.95
        var enableMomentum: Bool = true
        var invertY: Bool = false
        var constrainPitch: Bool = true
        var minPitch: Float = -.pi / 2 + 0.1
        var maxPitch: Float = .pi / 2 - 0.1
    }

    // MARK: - Camera State

    struct CameraState {
        var target: simd_float3 = .zero
        var distance: Float = 5.0
        var azimuth: Float = 0        // Horizontal rotation (radians)
        var elevation: Float = 0.3    // Vertical rotation (radians)

        var position: simd_float3 {
            let x = target.x + distance * cos(elevation) * sin(azimuth)
            let y = target.y + distance * sin(elevation)
            let z = target.z + distance * cos(elevation) * cos(azimuth)
            return simd_float3(x, y, z)
        }

        var viewMatrix: simd_float4x4 {
            simd_float4x4(lookAt: position, target: target, up: simd_float3(0, 1, 0))
        }
    }

    // MARK: - Properties

    private(set) var state: CameraState = CameraState()
    private var configuration: Configuration

    // Momentum
    private var velocity: simd_float3 = .zero
    private var angularVelocity: simd_float2 = .zero
    private var isAnimating: Bool = false
    private var displayLink: CADisplayLink?

    // Gesture state
    private var lastPanLocation: CGPoint = .zero
    private var lastPinchScale: CGFloat = 1.0
    private var isPanning: Bool = false
    private var isRotating: Bool = false

    // MARK: - Initialization

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    deinit {
        stopMomentum()
    }

    // MARK: - Camera Control

    func setTarget(_ target: simd_float3) {
        state.target = target
    }

    func setDistance(_ distance: Float) {
        state.distance = simd_clamp(distance, configuration.minDistance, configuration.maxDistance)
    }

    func setOrientation(azimuth: Float, elevation: Float) {
        state.azimuth = azimuth
        state.elevation = constrainElevation(elevation)
    }

    func reset() {
        state = CameraState()
        stopMomentum()
    }

    func fitToBounds(_ bounds: BoundingBox) {
        // Calculate center
        state.target = (bounds.min + bounds.max) / 2

        // Calculate distance to fit bounds in view
        let size = bounds.max - bounds.min
        let maxDimension = max(size.x, max(size.y, size.z))
        state.distance = maxDimension * 1.5

        // Reset orientation
        state.azimuth = 0
        state.elevation = 0.3
    }

    // MARK: - View & Projection Matrices

    var viewMatrix: simd_float4x4 {
        state.viewMatrix
    }

    func projectionMatrix(aspectRatio: Float, fov: Float = 60.0) -> simd_float4x4 {
        let fovRadians = fov * .pi / 180.0
        return simd_float4x4(
            perspectiveWithFOV: fovRadians,
            aspectRatio: aspectRatio,
            near: 0.01,
            far: 100.0
        )
    }

    // MARK: - Gesture Handling

    func handlePanGesture(_ gesture: UIPanGestureRecognizer, in view: UIView) {
        let location = gesture.location(in: view)
        let translation = gesture.translation(in: view)

        switch gesture.state {
        case .began:
            stopMomentum()
            lastPanLocation = location

            // Determine if this is rotation or pan based on finger count
            isRotating = gesture.numberOfTouches == 1
            isPanning = gesture.numberOfTouches == 2

        case .changed:
            if isRotating {
                // Orbit rotation
                let deltaX = Float(translation.x) * configuration.rotateSpeed
                let deltaY = Float(translation.y) * configuration.rotateSpeed * (configuration.invertY ? -1 : 1)

                state.azimuth -= deltaX
                state.elevation = constrainElevation(state.elevation + deltaY)

                // Store velocity for momentum
                angularVelocity = simd_float2(deltaX, deltaY)
            } else if isPanning {
                // Pan translation
                let deltaX = Float(translation.x) * configuration.panSpeed * state.distance
                let deltaY = Float(translation.y) * configuration.panSpeed * state.distance

                // Calculate pan vectors in camera space
                let right = simd_float3(
                    cos(state.azimuth),
                    0,
                    -sin(state.azimuth)
                )
                let up = simd_float3(0, 1, 0)

                state.target -= right * deltaX
                state.target += up * deltaY

                velocity = simd_float3(-deltaX, deltaY, 0)
            }

            gesture.setTranslation(.zero, in: view)

        case .ended, .cancelled:
            if configuration.enableMomentum {
                startMomentum()
            }
            isPanning = false
            isRotating = false

        default:
            break
        }
    }

    func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            stopMomentum()
            lastPinchScale = gesture.scale

        case .changed:
            let scale = Float(gesture.scale / lastPinchScale)
            state.distance = simd_clamp(
                state.distance / scale,
                configuration.minDistance,
                configuration.maxDistance
            )
            lastPinchScale = gesture.scale

        case .ended, .cancelled:
            lastPinchScale = 1.0

        default:
            break
        }
    }

    func handleRotationGesture(_ gesture: UIRotationGestureRecognizer) {
        switch gesture.state {
        case .changed:
            state.azimuth += Float(gesture.rotation)
            gesture.rotation = 0

        default:
            break
        }
    }

    func handleDoubleTap(at location: CGPoint, in view: UIView) {
        // Reset camera to default view
        withAnimation {
            reset()
        }
    }

    // MARK: - Programmatic Animation

    func animateTo(
        target: simd_float3? = nil,
        distance: Float? = nil,
        azimuth: Float? = nil,
        elevation: Float? = nil,
        duration: TimeInterval = 0.5
    ) {
        let startState = state
        let endTarget = target ?? state.target
        let endDistance = distance ?? state.distance
        let endAzimuth = azimuth ?? state.azimuth
        let endElevation = elevation ?? state.elevation

        // Simple linear interpolation animation
        let startTime = CACurrentMediaTime()

        let animationLink = CADisplayLink(target: AnimationTarget { [weak self] in
            guard let self = self else { return false }

            let elapsed = CACurrentMediaTime() - startTime
            let t = min(Float(elapsed / duration), 1.0)

            // Ease out cubic
            let eased = 1 - pow(1 - t, 3)

            self.state.target = simd_mix(startState.target, endTarget, simd_float3(repeating: eased))
            self.state.distance = simd_mix(startState.distance, endDistance, eased)
            self.state.azimuth = simd_mix(startState.azimuth, endAzimuth, eased)
            self.state.elevation = simd_mix(startState.elevation, endElevation, eased)

            return t >= 1.0
        }, selector: #selector(AnimationTarget.tick))

        animationLink.add(to: .main, forMode: .common)
    }

    // MARK: - Momentum

    private func startMomentum() {
        guard simd_length(velocity) > 0.001 || simd_length(angularVelocity) > 0.001 else {
            return
        }

        isAnimating = true

        displayLink = CADisplayLink(target: MomentumTarget { [weak self] in
            self?.updateMomentum() ?? true
        }, selector: #selector(MomentumTarget.tick))

        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopMomentum() {
        isAnimating = false
        displayLink?.invalidate()
        displayLink = nil
        velocity = .zero
        angularVelocity = .zero
    }

    private func updateMomentum() -> Bool {
        // Apply momentum
        if simd_length(angularVelocity) > 0.0001 {
            state.azimuth -= angularVelocity.x
            state.elevation = constrainElevation(state.elevation + angularVelocity.y)
            angularVelocity *= configuration.momentumDecay
        }

        if simd_length(velocity) > 0.0001 {
            let right = simd_float3(cos(state.azimuth), 0, -sin(state.azimuth))
            let up = simd_float3(0, 1, 0)

            state.target -= right * velocity.x
            state.target += up * velocity.y
            velocity *= configuration.momentumDecay
        }

        // Stop when velocity is negligible
        let shouldStop = simd_length(velocity) < 0.0001 && simd_length(angularVelocity) < 0.0001

        if shouldStop {
            stopMomentum()
        }

        return shouldStop
    }

    // MARK: - Helpers

    private func constrainElevation(_ elevation: Float) -> Float {
        guard configuration.constrainPitch else { return elevation }
        return simd_clamp(elevation, configuration.minPitch, configuration.maxPitch)
    }

    private func withAnimation(_ block: () -> Void) {
        // Simple state change - could be enhanced with actual animation
        block()
    }
}

// MARK: - Display Link Targets

private class MomentumTarget: NSObject {
    let update: () -> Bool

    init(_ update: @escaping () -> Bool) {
        self.update = update
    }

    @objc func tick() {
        if update() {
            // Animation complete
        }
    }
}

private class AnimationTarget: NSObject {
    let update: () -> Bool

    init(_ update: @escaping () -> Bool) {
        self.update = update
    }

    @objc func tick() {
        if update() {
            // Animation complete
        }
    }
}

// MARK: - Matrix Extensions

extension simd_float4x4 {

    init(lookAt eye: simd_float3, target: simd_float3, up: simd_float3) {
        let z = simd_normalize(eye - target)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)

        self.init(columns: (
            simd_float4(x.x, y.x, z.x, 0),
            simd_float4(x.y, y.y, z.y, 0),
            simd_float4(x.z, y.z, z.z, 0),
            simd_float4(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
        ))
    }

    init(perspectiveWithFOV fov: Float, aspectRatio: Float, near: Float, far: Float) {
        let y = 1 / tan(fov * 0.5)
        let x = y / aspectRatio
        let z = far / (near - far)

        self.init(columns: (
            simd_float4(x, 0, 0, 0),
            simd_float4(0, y, 0, 0),
            simd_float4(0, 0, z, -1),
            simd_float4(0, 0, z * near, 0)
        ))
    }
}
