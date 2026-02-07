import Foundation

/// Centralized accessibility identifiers for UI testing.
/// These identifiers should be applied to SwiftUI views using `.accessibilityIdentifier()`.
///
/// Usage in SwiftUI:
/// ```swift
/// Button("Scan") { ... }
///     .accessibilityIdentifier(AccessibilityIdentifiers.TabBar.captureButton)
/// ```
///
/// Usage in tests:
/// ```swift
/// app.buttons[AccessibilityIdentifiers.TabBar.captureButton].tap()
/// ```
enum AccessibilityIdentifiers {

    // MARK: - Tab Bar

    enum TabBar {
        static let galleryTab = "tabBar.gallery"
        static let captureButton = "tabBar.capture"
        static let profileTab = "tabBar.profile"
    }

    // MARK: - Gallery View

    enum Gallery {
        static let view = "gallery.view"
        static let searchField = "gallery.searchField"
        static let sortButton = "gallery.sortButton"
        static let emptyStateView = "gallery.emptyState"
        static let scanGrid = "gallery.scanGrid"

        /// Dynamic identifier for scan card: "gallery.scanCard.\(scanId)"
        static func scanCard(_ id: String) -> String {
            "gallery.scanCard.\(id)"
        }
    }

    // MARK: - Scan Mode Selector

    enum ScanModeSelector {
        static let view = "scanModeSelector.view"
        static let exteriorCard = "scanModeSelector.exterior"
        static let interiorCard = "scanModeSelector.interior"
        static let objectCard = "scanModeSelector.object"
        static let cancelButton = "scanModeSelector.cancel"
    }

    // MARK: - Scanning View

    enum Scanning {
        static let view = "scanning.view"
        static let statusBar = "scanning.statusBar"
        static let captureButton = "scanning.captureButton"
        static let stopButton = "scanning.stopButton"
        static let closeButton = "scanning.closeButton"
        static let meshToggle = "scanning.meshToggle"
        static let settingsButton = "scanning.settingsButton"
        static let mockModeWarning = "scanning.mockModeWarning"

        // Statistics
        static let pointCountLabel = "scanning.pointCount"
        static let meshFaceCountLabel = "scanning.meshFaceCount"
        static let durationLabel = "scanning.duration"
    }

    // MARK: - Model Detail View

    enum ModelDetail {
        static let view = "modelDetail.view"
        static let titleLabel = "modelDetail.title"
        static let menuButton = "modelDetail.menu"
        static let shareButton = "modelDetail.share"
        static let exportButton = "modelDetail.export"
        static let renameButton = "modelDetail.rename"
        static let deleteButton = "modelDetail.delete"

        // Action Bar
        static let aiButton = "modelDetail.aiButton"
        static let measureButton = "modelDetail.measureButton"
        static let viewer3DButton = "modelDetail.viewer3DButton"
        static let arButton = "modelDetail.arButton"
        static let exportActionButton = "modelDetail.exportActionButton"

        // AI Processing
        static let aiProgressIndicator = "modelDetail.aiProgress"

        // Alerts
        static let renameAlert = "modelDetail.renameAlert"
        static let deleteAlert = "modelDetail.deleteAlert"
    }

    // MARK: - Profile View

    enum Profile {
        static let view = "profile.view"
        static let loginButton = "profile.loginButton"
        static let settingsButton = "profile.settingsButton"
        static let helpButton = "profile.helpButton"
        static let versionLabel = "profile.versionLabel"

        // Logged in state
        static let userAvatar = "profile.userAvatar"
        static let userNameLabel = "profile.userName"
        static let userEmailLabel = "profile.userEmail"
        static let subscriptionBadge = "profile.subscriptionBadge"
        static let logoutButton = "profile.logoutButton"
    }

    // MARK: - Settings View

    enum Settings {
        static let view = "settings.view"
        static let doneButton = "settings.doneButton"

        // Developer Section
        static let mockModeToggle = "settings.mockModeToggle"
        static let mockDataPreviewLink = "settings.mockDataPreview"

        // Debug Upload Section
        static let rawDataModeToggle = "settings.rawDataModeToggle"
        static let tailscaleIPField = "settings.tailscaleIP"
        static let testConnectionButton = "settings.testConnection"

        // Processing Section
        static let depthFusionToggle = "settings.depthFusionToggle"

        // Quality Section
        static let meshResolutionPicker = "settings.meshResolution"
        static let textureResolutionPicker = "settings.textureResolution"

        // Diagnostics
        static let exportDiagnosticsButton = "settings.exportDiagnostics"
        static let diagnosticsDetailLink = "settings.diagnosticsDetail"
    }

    // MARK: - Auth View

    enum Auth {
        static let view = "auth.view"
        static let loginTab = "auth.loginTab"
        static let registerTab = "auth.registerTab"
        static let emailField = "auth.emailField"
        static let passwordField = "auth.passwordField"
        static let confirmPasswordField = "auth.confirmPasswordField"
        static let nameField = "auth.nameField"
        static let submitButton = "auth.submitButton"
        static let forgotPasswordButton = "auth.forgotPasswordButton"
        static let signInWithAppleButton = "auth.signInWithApple"
        static let skipButton = "auth.skipButton"
        static let errorMessage = "auth.errorMessage"
    }

    // MARK: - Export View

    enum Export {
        static let view = "export.view"
        static let doneButton = "export.doneButton"

        // Format rows
        static let usdzFormat = "export.format.usdz"
        static let gltfFormat = "export.format.gltf"
        static let objFormat = "export.format.obj"
        static let stlFormat = "export.format.stl"
        static let plyFormat = "export.format.ply"
        static let pdfFormat = "export.format.pdf"
    }

    // MARK: - Measurement View

    enum Measurement {
        static let view = "measurement.view"
        static let closeButton = "measurement.closeButton"
        static let unitPicker = "measurement.unitPicker"
        static let distanceLabel = "measurement.distanceLabel"
    }

    // MARK: - Common / Shared

    enum Common {
        static let loadingIndicator = "common.loading"
        static let errorAlert = "common.errorAlert"
        static let confirmationAlert = "common.confirmationAlert"
        static let shareSheet = "common.shareSheet"
        static let navigationBackButton = "common.backButton"
    }
}
