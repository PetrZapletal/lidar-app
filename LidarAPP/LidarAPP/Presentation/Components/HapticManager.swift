import UIKit

// MARK: - Haptic Manager

/// Centralized haptic feedback manager.
/// Provides both raw haptic styles and semantic haptic methods
/// for consistent tactile feedback throughout the app.
@MainActor
final class HapticManager {
    static let shared = HapticManager()

    // MARK: - Generators

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()

    // MARK: - Initialization

    private init() {
        prepareAll()
        debugLog("HapticManager initialized", category: .logCategoryUI)
    }

    // MARK: - Preparation

    /// Prepare all generators for low-latency feedback.
    /// Call before anticipated haptic events.
    func prepareAll() {
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }

    // MARK: - Raw Haptics

    /// Trigger an impact haptic with the given style.
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        switch style {
        case .light:
            impactLight.impactOccurred()
            impactLight.prepare()
        case .medium:
            impactMedium.impactOccurred()
            impactMedium.prepare()
        case .heavy:
            impactHeavy.impactOccurred()
            impactHeavy.prepare()
        case .rigid:
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.impactOccurred()
        case .soft:
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.impactOccurred()
        @unknown default:
            impactMedium.impactOccurred()
            impactMedium.prepare()
        }
    }

    /// Trigger a notification haptic with the given type.
    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
    }

    /// Trigger a selection haptic.
    func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    // MARK: - Semantic Haptics

    /// Heavy impact when scanning begins.
    func scanStarted() {
        impact(.heavy)
        debugLog("Haptic: scanStarted", category: .logCategoryUI)
    }

    /// Medium impact when scanning is paused.
    func scanPaused() {
        impact(.medium)
        debugLog("Haptic: scanPaused", category: .logCategoryUI)
    }

    /// Success notification when scanning completes.
    func scanCompleted() {
        notification(.success)
        debugLog("Haptic: scanCompleted", category: .logCategoryUI)
    }

    /// Error notification when scanning fails.
    func scanFailed() {
        notification(.error)
        debugLog("Haptic: scanFailed", category: .logCategoryUI)
    }

    /// Light impact when a measurement point is placed.
    func measurementPlaced() {
        impact(.light)
        debugLog("Haptic: measurementPlaced", category: .logCategoryUI)
    }

    /// Selection feedback for general button taps.
    func buttonTapped() {
        selection()
    }

    /// Success notification when export finishes.
    func exportCompleted() {
        notification(.success)
        debugLog("Haptic: exportCompleted", category: .logCategoryUI)
    }
}
