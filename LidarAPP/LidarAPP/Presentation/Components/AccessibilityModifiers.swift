import SwiftUI

// MARK: - Accessibility Modifiers

/// SwiftUI view extensions for common accessibility patterns
/// used throughout the LiDAR scanning app.
extension View {

    /// Add standard accessibility for a scan mode button.
    /// - Parameters:
    ///   - mode: The scan mode this button represents.
    ///   - isSelected: Whether this mode is currently selected.
    /// - Returns: A view with appropriate accessibility traits and labels.
    func scanModeAccessibility(mode: ScanMode, isSelected: Bool) -> some View {
        self
            .accessibilityLabel("\(mode.displayName), \(mode.subtitle)")
            .accessibilityValue(isSelected ? "Vybrano" : "Nevybrano")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint("Dvojitym klepnutim vyberte rezim \(mode.displayName)")
            .accessibilityIdentifier("scanMode.\(mode.rawValue)")
    }

    /// Add accessibility for a measurement result display.
    /// - Parameters:
    ///   - value: The measurement value string (e.g., "2.35 m").
    ///   - type: The measurement type string (e.g., "Vzdalenost").
    /// - Returns: A view with appropriate accessibility labels.
    func measurementAccessibility(value: String, type: String) -> some View {
        self
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(type): \(value)")
            .accessibilityIdentifier("measurement.\(type.lowercased())")
    }

    /// Add accessibility for a scan statistics display.
    /// - Parameters:
    ///   - label: The statistic label (e.g., "Body").
    ///   - value: The statistic value (e.g., "1.2M").
    /// - Returns: A view with appropriate accessibility labels.
    func scanStatAccessibility(label: String, value: String) -> some View {
        self
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label): \(value)")
            .accessibilityIdentifier("scanStat.\(label.lowercased())")
    }
}
