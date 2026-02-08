import SwiftUI

/// Scan mode selection per LUMISCAN specification
enum ScanMode: String, CaseIterable {
    case exterior   // Buildings, facades, outdoor - ARKit with gravityAndHeading
    case interior   // Rooms - RoomPlan API
    case object     // Standalone objects - ObjectCaptureSession

    var displayName: String {
        switch self {
        case .exterior: return "Exteriér"
        case .interior: return "Interiér"
        case .object: return "Objekt"
        }
    }

    var icon: String {
        switch self {
        case .exterior: return "building.2"
        case .interior: return "house.fill"
        case .object: return "cube.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .exterior: return "Budovy a fasády"
        case .interior: return "Místnosti (RoomPlan)"
        case .object: return "Samostatné předměty"
        }
    }

    var description: String {
        switch self {
        case .exterior:
            return "Skenování exteriérů, budov a fasád. Využívá GPS pro přesné umístění."
        case .interior:
            return "Automatická detekce stěn, dveří a oken. Optimalizované pro interiéry."
        case .object:
            return "Skenování objektů na stole nebo vozu. Chodíte kolem objektu dokola."
        }
    }

    var color: Color {
        switch self {
        case .exterior: return .green
        case .interior: return .blue
        case .object: return .orange
        }
    }
}
