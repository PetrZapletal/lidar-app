import Foundation

/// Chyby při skenování
enum ScanError: Error, LocalizedError {
    case lidarNotAvailable
    case sessionFailed(String)
    case trackingLost(reason: String)
    case meshExtractionFailed
    case depthMapUnavailable
    case insufficientData(String)
    case memoryPressure
    case thermalThrottling

    var errorDescription: String? {
        switch self {
        case .lidarNotAvailable:
            return "LiDAR senzor není na tomto zařízení dostupný"
        case .sessionFailed(let reason):
            return "AR session selhala: \(reason)"
        case .trackingLost(let reason):
            return "Tracking ztracen: \(reason)"
        case .meshExtractionFailed:
            return "Nepodařilo se extrahovat mesh data"
        case .depthMapUnavailable:
            return "Depth mapa není dostupná"
        case .insufficientData(let detail):
            return "Nedostatečná data: \(detail)"
        case .memoryPressure:
            return "Nedostatek paměti pro pokračování skenování"
        case .thermalThrottling:
            return "Zařízení se přehřívá, skenování pozastaveno"
        }
    }
}
