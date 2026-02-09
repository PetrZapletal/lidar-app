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


