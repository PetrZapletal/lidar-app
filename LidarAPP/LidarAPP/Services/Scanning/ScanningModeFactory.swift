import Foundation

/// Factory pro vytváření správného skenovacího adaptéru podle zvoleného režimu
///
/// Centralizuje vytváření adaptérů a poskytuje informace o dostupných režimech
/// na aktuálním zařízení.
@MainActor
final class ScanningModeFactory {

    // MARK: - Properties

    private let services: ServiceContainer

    // MARK: - Initialization

    init(services: ServiceContainer) {
        self.services = services
        debugLog("ScanningModeFactory inicializován", category: .logCategoryScanning)
    }

    // MARK: - Factory Methods

    /// Vytvoří adaptér pro daný skenovací režim
    ///
    /// - Parameter mode: Požadovaný režim skenování
    /// - Returns: Adaptér implementující `ScanningModeProtocol`
    func createAdapter(for mode: ScanMode) -> any ScanningModeProtocol {
        let adapter: any ScanningModeProtocol

        switch mode {
        case .exterior:
            adapter = LiDARScanningModeAdapter(services: services)
        case .interior:
            adapter = RoomPlanScanningModeAdapter(services: services)
        case .object:
            adapter = ObjectCaptureScanningModeAdapter(services: services)
        }

        debugLog(
            "Vytvořen adaptér pro režim \(mode.displayName), dostupný: \(adapter.isAvailable)",
            category: .logCategoryScanning
        )

        return adapter
    }

    /// Vrátí seznam režimů dostupných na aktuálním zařízení
    ///
    /// - Returns: Pole dostupných skenovacích režimů
    func availableModes() -> [ScanMode] {
        let available = ScanMode.allCases.filter { mode in
            createAdapter(for: mode).isAvailable
        }

        debugLog(
            "Dostupné skenovací režimy: \(available.map(\.displayName).joined(separator: ", "))",
            category: .logCategoryScanning
        )

        return available
    }

    /// Zkontroluje, zda je daný režim na zařízení dostupný
    ///
    /// - Parameter mode: Režim k ověření
    /// - Returns: `true` pokud je režim dostupný
    func isModeAvailable(_ mode: ScanMode) -> Bool {
        createAdapter(for: mode).isAvailable
    }
}
