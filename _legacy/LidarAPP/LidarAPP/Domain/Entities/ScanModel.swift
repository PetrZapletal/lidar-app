import Foundation
import UIKit

struct ScanModel: Identifiable, Hashable {
    let id: String
    var name: String
    let createdAt: Date
    var thumbnail: UIImage?
    let pointCount: Int
    let faceCount: Int
    let fileSize: Int64
    let isProcessed: Bool
    let localURL: URL?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ScanModel, rhs: ScanModel) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Sorting

enum ScanSortOrder: String, CaseIterable {
    case dateDescending = "Nejnovější"
    case dateAscending = "Nejstarší"
    case nameAscending = "Název A-Z"
    case sizeDescending = "Největší"
}

extension [ScanModel] {
    func sorted(by order: ScanSortOrder) -> [ScanModel] {
        switch order {
        case .dateDescending:
            return sorted { $0.createdAt > $1.createdAt }
        case .dateAscending:
            return sorted { $0.createdAt < $1.createdAt }
        case .nameAscending:
            return sorted { $0.name < $1.name }
        case .sizeDescending:
            return sorted { $0.fileSize > $1.fileSize }
        }
    }
}
