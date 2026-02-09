import Foundation
import ARKit
import simd

/// Analyzes scan coverage and identifies gaps for user guidance
@MainActor
@Observable
final class CoverageAnalyzer {

    // MARK: - Configuration

    struct Configuration {
        var gridResolution: Float = 0.1
        var minimumViewsForGood: Int = 3
        var minimumViewsForExcellent: Int = 5
        var angleThresholdDegrees: Float = 30
        var maxUpdateDistance: Float = 5.0
        var maxGapsToShow: Int = 5
        var minGapSizeCells: Int = 3

        static let `default` = Configuration()
    }

    // MARK: - Coverage Data Structures

    struct CoverageCell: Identifiable, Sendable {
        let id: Int
        let gridPosition: SIMD3<Int>
        let worldPosition: simd_float3
        var coverage: Float
        var quality: QualityLevel
        var viewCount: Int
        var viewDirections: [simd_float3]
        var lastUpdated: Date

        init(id: Int, gridPosition: SIMD3<Int>, worldPosition: simd_float3) {
            self.id = id
            self.gridPosition = gridPosition
            self.worldPosition = worldPosition
            self.coverage = 0
            self.quality = .none
            self.viewCount = 0
            self.viewDirections = []
            self.lastUpdated = Date()
        }
    }

    enum QualityLevel: Int, Comparable, Sendable {
        case none = 0
        case poor = 1
        case fair = 2
        case good = 3
        case excellent = 4

        var displayName: String {
            switch self {
            case .none: return "Not scanned"
            case .poor: return "Poor"
            case .fair: return "Fair"
            case .good: return "Good"
            case .excellent: return "Excellent"
            }
        }

        var color: simd_float4 {
            switch self {
            case .none: return simd_float4(1, 0, 0, 0.5)
            case .poor: return simd_float4(1, 0.5, 0, 0.5)
            case .fair: return simd_float4(1, 1, 0, 0.5)
            case .good: return simd_float4(0, 1, 0, 0.5)
            case .excellent: return simd_float4(0, 0.5, 1, 0.5)
            }
        }

        static func < (lhs: QualityLevel, rhs: QualityLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct Gap: Identifiable, Sendable {
        let id: UUID
        let center: simd_float3
        let cellCount: Int
        let estimatedArea: Float
        let suggestedViewDirection: simd_float3
        let suggestedCameraPosition: simd_float3
        let priority: Int
        let cellIds: [Int]
    }

    struct CoverageStatistics: Sendable {
        let totalCells: Int
        let coveredCells: Int
        let coveragePercentage: Float
        let averageQuality: Float
        let gapCount: Int
        let estimatedCompletion: Float
        let scannedAreaM2: Float
    }

    // MARK: - Published State

    private(set) var coverageGrid: [Int: CoverageCell] = [:]
    private(set) var detectedGaps: [Gap] = []
    private(set) var statistics: CoverageStatistics?
    private(set) var suggestedDirection: simd_float3?
    private(set) var suggestedCameraPosition: simd_float3?

    // MARK: - Internal State

    private let configuration: Configuration
    private var gridBounds: (min: SIMD3<Int>, max: SIMD3<Int>)?
    private var cameraTrajectory: [simd_float4x4] = []
    private var lastUpdateTime: Date = Date.distantPast
    private let updateInterval: TimeInterval = 0.2

    private var processedAnchorIdentifiers: Set<UUID> = []
    private var newCellsSinceLastGapDetection: Int = 0
    private let minNewCellsForGapDetection: Int = 100
    private var lastGapDetectionTime: Date = Date.distantPast
    private let minGapDetectionInterval: TimeInterval = 1.0
    private var statisticsDirty: Bool = false

    // MARK: - Initialization

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Public Methods

    /// Update coverage based on current mesh anchors and camera position
    func updateCoverage(meshAnchors: [ARMeshAnchor], cameraTransform: simd_float4x4) {
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= updateInterval else { return }
        lastUpdateTime = now

        cameraTrajectory.append(cameraTransform)
        if cameraTrajectory.count > 1000 {
            cameraTrajectory = cameraTrajectory.enumerated()
                .filter { $0.offset % 2 == 0 }
                .map { $0.element }
        }

        let cameraPosition = simd_float3(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        let cameraForward = -simd_float3(
            cameraTransform.columns.2.x,
            cameraTransform.columns.2.y,
            cameraTransform.columns.2.z
        )

        let previousCellCount = coverageGrid.count
        for anchor in meshAnchors {
            if !processedAnchorIdentifiers.contains(anchor.identifier) {
                updateCoverageFromMeshAnchor(anchor, cameraPosition: cameraPosition, cameraForward: cameraForward)
                processedAnchorIdentifiers.insert(anchor.identifier)
            }
        }

        let newCellsThisUpdate = coverageGrid.count - previousCellCount
        newCellsSinceLastGapDetection += max(0, newCellsThisUpdate)
        statisticsDirty = statisticsDirty || newCellsThisUpdate > 0

        let timeSinceLastGapDetection = now.timeIntervalSince(lastGapDetectionTime)
        let shouldDetectGaps = (newCellsSinceLastGapDetection >= minNewCellsForGapDetection) ||
                               (timeSinceLastGapDetection >= minGapDetectionInterval && newCellsSinceLastGapDetection > 0)

        if shouldDetectGaps {
            detectGaps(cameraPosition: cameraPosition)
            lastGapDetectionTime = now
            newCellsSinceLastGapDetection = 0
        }

        if statisticsDirty {
            updateStatistics()
            statisticsDirty = false
        }

        updateSuggestedDirection(cameraPosition: cameraPosition, cameraForward: cameraForward)
    }

    /// Get gaps visible from current camera position
    func getGapsInView(camera: ARCamera, maxDistance: Float = 3.0) -> [Gap] {
        let cameraPosition = simd_float3(
            camera.transform.columns.3.x,
            camera.transform.columns.3.y,
            camera.transform.columns.3.z
        )

        let cameraForward = -simd_float3(
            camera.transform.columns.2.x,
            camera.transform.columns.2.y,
            camera.transform.columns.2.z
        )

        return detectedGaps.filter { gap in
            let toGap = gap.center - cameraPosition
            let distance = simd_length(toGap)
            guard distance < maxDistance else { return false }
            let dotProduct = simd_dot(simd_normalize(toGap), cameraForward)
            return dotProduct > 0
        }
    }

    /// Reset coverage data
    func reset() {
        coverageGrid.removeAll()
        detectedGaps.removeAll()
        cameraTrajectory.removeAll()
        statistics = nil
        suggestedDirection = nil
        suggestedCameraPosition = nil
        gridBounds = nil
        processedAnchorIdentifiers.removeAll()
        newCellsSinceLastGapDetection = 0
        lastGapDetectionTime = Date.distantPast
        statisticsDirty = false
        debugLog("Coverage analyzer reset", category: .logCategoryScanning)
    }

    // MARK: - Private Methods

    private func updateCoverageFromMeshAnchor(_ anchor: ARMeshAnchor, cameraPosition: simd_float3, cameraForward: simd_float3) {
        let geometry = anchor.geometry
        let transform = anchor.transform

        let vertexSource = geometry.vertices
        let vertexCount = vertexSource.count
        guard vertexCount > 0 else { return }

        let sampleStep = max(1, vertexCount / 1000)
        let vertexStride = vertexSource.stride
        let vertexOffset = vertexSource.offset
        let bufferContents = vertexSource.buffer.contents()

        let requiredSize = vertexOffset + (vertexCount - 1) * vertexStride + MemoryLayout<simd_float3>.size
        guard vertexSource.buffer.length >= requiredSize else {
            warningLog("Buffer too small for vertex data", category: .logCategoryAR)
            return
        }

        for i in Swift.stride(from: 0, to: vertexCount, by: sampleStep) {
            let byteOffset = vertexOffset + i * vertexStride
            let vertexPtr = bufferContents.advanced(by: byteOffset)
            let localPosition = vertexPtr.assumingMemoryBound(to: simd_float3.self).pointee

            let worldPosition4 = transform * simd_float4(localPosition, 1)
            let worldPosition = simd_float3(worldPosition4.x, worldPosition4.y, worldPosition4.z)

            let distance = simd_length(worldPosition - cameraPosition)
            if distance < configuration.maxUpdateDistance {
                updateCellFromPoint(worldPosition, cameraPosition: cameraPosition, cameraForward: cameraForward)
            }
        }
    }

    private func updateCellFromPoint(_ worldPoint: simd_float3, cameraPosition: simd_float3, cameraForward: simd_float3) {
        let gridPos = worldToGrid(worldPoint)
        let cellId = gridPositionToId(gridPos)

        if var cell = coverageGrid[cellId] {
            let viewDirection = simd_normalize(cameraPosition - worldPoint)

            var isNewView = true
            for existingDir in cell.viewDirections {
                let angle = acos(simd_clamp(simd_dot(viewDirection, existingDir), -1, 1))
                if angle < (configuration.angleThresholdDegrees * .pi / 180) {
                    isNewView = false
                    break
                }
            }

            if isNewView {
                cell.viewCount += 1
                cell.viewDirections.append(viewDirection)
                cell.quality = qualityForViewCount(cell.viewCount)
                cell.coverage = Float(cell.viewCount) / Float(configuration.minimumViewsForExcellent)
                cell.lastUpdated = Date()
            }

            coverageGrid[cellId] = cell
        } else {
            var newCell = CoverageCell(
                id: cellId,
                gridPosition: gridPos,
                worldPosition: worldPoint
            )
            let viewDirection = simd_normalize(cameraPosition - worldPoint)
            newCell.viewCount = 1
            newCell.viewDirections = [viewDirection]
            newCell.quality = .poor
            newCell.coverage = 0.2
            coverageGrid[cellId] = newCell
            updateGridBounds(gridPos)
        }
    }

    private func detectGaps(cameraPosition: simd_float3) {
        guard let bounds = gridBounds else {
            detectedGaps = []
            return
        }

        var lowCoverageCells: [Int: CoverageCell] = [:]
        for (id, cell) in coverageGrid {
            if cell.quality < .good {
                lowCoverageCells[id] = cell
            }
        }

        var missingCells: [Int] = []
        for x in bounds.min.x...bounds.max.x {
            for y in bounds.min.y...bounds.max.y {
                for z in bounds.min.z...bounds.max.z {
                    let gridPos = SIMD3<Int>(x, y, z)
                    let cellId = gridPositionToId(gridPos)

                    let neighbors = getNeighborIds(gridPos)
                    let hasScannedNeighbor = neighbors.contains { id in
                        if let cell = coverageGrid[id] {
                            return cell.quality >= .fair
                        }
                        return false
                    }

                    if hasScannedNeighbor && coverageGrid[cellId] == nil {
                        missingCells.append(cellId)
                    }
                }
            }
        }

        var visited = Set<Int>()
        var gaps: [Gap] = []

        func floodFill(startId: Int) -> [Int] {
            var cluster: [Int] = []
            var stack: [Int] = [startId]

            while !stack.isEmpty {
                let cellId = stack.removeLast()
                guard !visited.contains(cellId) else { continue }
                visited.insert(cellId)

                if lowCoverageCells[cellId] != nil || missingCells.contains(cellId) {
                    cluster.append(cellId)

                    if let cell = coverageGrid[cellId] {
                        let neighbors = getNeighborIds(cell.gridPosition)
                        for neighbor in neighbors {
                            if !visited.contains(neighbor) {
                                stack.append(neighbor)
                            }
                        }
                    }
                }
            }

            return cluster
        }

        for (cellId, _) in lowCoverageCells {
            if !visited.contains(cellId) {
                let cluster = floodFill(startId: cellId)
                if cluster.count >= configuration.minGapSizeCells {
                    if let gap = createGap(from: cluster, cameraPosition: cameraPosition) {
                        gaps.append(gap)
                    }
                }
            }
        }

        gaps.sort { $0.priority > $1.priority }
        detectedGaps = Array(gaps.prefix(configuration.maxGapsToShow))
    }

    private func createGap(from cellIds: [Int], cameraPosition: simd_float3) -> Gap? {
        guard !cellIds.isEmpty else { return nil }

        var sumPosition = simd_float3.zero
        var count = 0

        for cellId in cellIds {
            if let cell = coverageGrid[cellId] {
                sumPosition += cell.worldPosition
                count += 1
            }
        }

        guard count > 0 else { return nil }
        let center = sumPosition / Float(count)

        let suggestedDirection = simd_normalize(cameraPosition - center)

        let cellArea = configuration.gridResolution * configuration.gridResolution
        let estimatedArea = Float(cellIds.count) * cellArea

        let distanceToCamera = simd_length(center - cameraPosition)
        let sizeFactor = Float(cellIds.count)
        let distanceFactor = max(0, 5 - distanceToCamera)
        let priority = Int(sizeFactor * distanceFactor)

        let suggestedCameraPos = center + suggestedDirection * 1.5

        return Gap(
            id: UUID(),
            center: center,
            cellCount: cellIds.count,
            estimatedArea: estimatedArea,
            suggestedViewDirection: -suggestedDirection,
            suggestedCameraPosition: suggestedCameraPos,
            priority: priority,
            cellIds: cellIds
        )
    }

    private func updateStatistics() {
        let totalCells = coverageGrid.count
        guard totalCells > 0 else {
            statistics = nil
            return
        }

        let coveredCells = coverageGrid.values.filter { $0.quality >= .fair }.count
        let coveragePercentage = Float(coveredCells) / Float(totalCells) * 100

        let averageQuality = coverageGrid.values.reduce(0.0) { $0 + Float($1.quality.rawValue) } / Float(totalCells)

        let gapCount = detectedGaps.count
        let estimatedCompletion = min(100, coveragePercentage + (gapCount == 0 ? 0 : -Float(gapCount) * 2))

        let cellArea = configuration.gridResolution * configuration.gridResolution
        let scannedAreaM2 = Float(coveredCells) * cellArea

        statistics = CoverageStatistics(
            totalCells: totalCells,
            coveredCells: coveredCells,
            coveragePercentage: coveragePercentage,
            averageQuality: averageQuality,
            gapCount: gapCount,
            estimatedCompletion: estimatedCompletion,
            scannedAreaM2: scannedAreaM2
        )
    }

    private func updateSuggestedDirection(cameraPosition: simd_float3, cameraForward: simd_float3) {
        guard let topGap = detectedGaps.first else {
            suggestedDirection = nil
            suggestedCameraPosition = nil
            return
        }

        suggestedDirection = topGap.suggestedViewDirection
        suggestedCameraPosition = topGap.suggestedCameraPosition
    }

    // MARK: - Grid Helpers

    private func worldToGrid(_ position: simd_float3) -> SIMD3<Int> {
        SIMD3<Int>(
            Int(floor(position.x / configuration.gridResolution)),
            Int(floor(position.y / configuration.gridResolution)),
            Int(floor(position.z / configuration.gridResolution))
        )
    }

    private func gridPositionToId(_ pos: SIMD3<Int>) -> Int {
        let prime1 = 73856093
        let prime2 = 19349663
        let prime3 = 83492791
        return abs((pos.x * prime1) ^ (pos.y * prime2) ^ (pos.z * prime3))
    }

    private func updateGridBounds(_ gridPos: SIMD3<Int>) {
        if var bounds = gridBounds {
            bounds.min = SIMD3<Int>(
                min(bounds.min.x, gridPos.x),
                min(bounds.min.y, gridPos.y),
                min(bounds.min.z, gridPos.z)
            )
            bounds.max = SIMD3<Int>(
                max(bounds.max.x, gridPos.x),
                max(bounds.max.y, gridPos.y),
                max(bounds.max.z, gridPos.z)
            )
            gridBounds = bounds
        } else {
            gridBounds = (min: gridPos, max: gridPos)
        }
    }

    private func getNeighborIds(_ gridPos: SIMD3<Int>) -> [Int] {
        var neighbors: [Int] = []
        for dx in -1...1 {
            for dy in -1...1 {
                for dz in -1...1 {
                    if dx == 0 && dy == 0 && dz == 0 { continue }
                    let neighborPos = SIMD3<Int>(gridPos.x + dx, gridPos.y + dy, gridPos.z + dz)
                    neighbors.append(gridPositionToId(neighborPos))
                }
            }
        }
        return neighbors
    }

    private func qualityForViewCount(_ count: Int) -> QualityLevel {
        switch count {
        case 0: return .none
        case 1: return .poor
        case 2: return .fair
        case 3..<configuration.minimumViewsForExcellent: return .good
        default: return .excellent
        }
    }
}
