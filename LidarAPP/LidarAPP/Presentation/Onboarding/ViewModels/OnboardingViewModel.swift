import Foundation
import AVFoundation
import ARKit

/// ViewModel pro onboarding flow - kontrola LiDAR, oprávnění kamery, tutorial
@MainActor
@Observable
final class OnboardingViewModel {

    // MARK: - Constants

    let totalPages = 5

    // MARK: - State

    var currentPage: Int = 0
    var hasLiDAR: Bool = false
    var cameraPermissionGranted: Bool = false
    var isRequestingPermission: Bool = false

    // MARK: - Persistence

    @ObservationIgnored
    private let onboardingCompletedKey = "onboarding_completed"

    var onboardingCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: onboardingCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardingCompletedKey) }
    }

    // MARK: - Dependencies

    private let services: ServiceContainer

    // MARK: - Init

    init(services: ServiceContainer) {
        self.services = services
        checkLiDARSupport()
        checkCameraPermission()
        infoLog("OnboardingViewModel initialized", category: .logCategoryUI)
    }

    // MARK: - LiDAR Check

    func checkLiDARSupport() {
        hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        debugLog("LiDAR support: \(hasLiDAR)", category: .logCategoryUI)
    }

    // MARK: - Camera Permission

    func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraPermissionGranted = (status == .authorized)
        debugLog("Camera permission status: \(status.rawValue)", category: .logCategoryUI)
    }

    func requestCameraPermission() async {
        isRequestingPermission = true
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraPermissionGranted = granted
        isRequestingPermission = false

        if granted {
            infoLog("Camera permission granted", category: .logCategoryUI)
        } else {
            warningLog("Camera permission denied", category: .logCategoryUI)
        }
    }

    // MARK: - Navigation

    var canGoNext: Bool {
        currentPage < totalPages - 1
    }

    var isLastPage: Bool {
        currentPage == totalPages - 1
    }

    func nextPage() {
        guard canGoNext else { return }
        currentPage += 1
        debugLog("Onboarding moved to page \(currentPage)", category: .logCategoryUI)
    }

    func previousPage() {
        guard currentPage > 0 else { return }
        currentPage -= 1
    }

    // MARK: - Completion

    func completeOnboarding() {
        onboardingCompleted = true
        infoLog("Onboarding completed normally", category: .logCategoryUI)
        services.debugStream.trackViewAppeared("OnboardingCompleted", details: [
            "skipped": false,
            "hasLiDAR": hasLiDAR,
            "cameraGranted": cameraPermissionGranted
        ])
    }

    func skipOnboarding() {
        onboardingCompleted = true
        warningLog("Onboarding skipped by user", category: .logCategoryUI)
        services.debugStream.trackViewAppeared("OnboardingSkipped", details: [
            "skippedAtPage": currentPage,
            "hasLiDAR": hasLiDAR,
            "cameraGranted": cameraPermissionGranted
        ])
    }
}
