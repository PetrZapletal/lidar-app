import Foundation
import simd

/// Výsledek měření
struct MeasurementResult: Sendable {
    let value: Float
    let unit: String
    let startPoint: simd_float3
    let endPoint: simd_float3
}

/// Protokol pro offline měření v 3D prostoru
@MainActor
protocol MeasurementServiceProtocol: AnyObject {
    /// Změř vzdálenost mezi dvěma body
    func measureDistance(from: simd_float3, to: simd_float3) -> MeasurementResult

    /// Vypočítej plochu z bodů polygonu
    func calculateArea(points: [simd_float3]) -> Float

    /// Vypočítej objem z mesh dat
    func calculateVolume(meshData: MeshData) -> Float
}

// MARK: - Placeholder (Sprint 0)

@MainActor
final class PlaceholderMeasurementService: MeasurementServiceProtocol {
    func measureDistance(from: simd_float3, to: simd_float3) -> MeasurementResult {
        let distance = simd_distance(from, to)
        return MeasurementResult(value: distance, unit: "m", startPoint: from, endPoint: to)
    }

    func calculateArea(points: [simd_float3]) -> Float { 0 }
    func calculateVolume(meshData: MeshData) -> Float { 0 }
}
