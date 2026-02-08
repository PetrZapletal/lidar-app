# 02 - Adresarova struktura

> Kompletni prehled vsech adresaru a zdrojovych souboru projektu LidarApp.
> Stav k: 2026-02-08

---

## Legenda

- **[IMPL]** = Realna implementace s funkcni logikou
- **[STUB]** = Placeholder / zakladni kostra bez plne implementace
- **[CONFIG]** = Konfiguracni soubor
- **[TEST]** = Testovaci soubor
- **[ASSET]** = Staticke assety (obrazky, modely, sablony)
- **[SCRIPT]** = Pomocny skript / nastroj
- **[DOC]** = Dokumentace

---

## Korenovy adresar (`/home/user/lidar-app/`)

```
lidar-app/
├── .claude/                          # Claude Code konfigurace a agenti
├── .github/                          # GitHub Actions CI/CD
├── Doc-version2/                     # Dokumentace projektu v2
├── LidarAPP/                         # iOS aplikace (Swift/SwiftUI)
├── backend/                          # Python backend (FastAPI)
├── docs/                             # Projektova dokumentace v1
├── scripts/                          # Pomocne skripty
│
├── .gitignore                        # [CONFIG] Git ignore pravidla
├── CLAUDE.md                         # [DOC] Instrukce pro Claude Code
└── README.md                         # [DOC] Hlavni README projektu
```

---

## 1. `.claude/` - Claude Code konfigurace

```
.claude/
├── agents/
│   ├── arkit-specialist.md           # [CONFIG] Agent pro ARKit a LiDAR specialista
│   ├── code-quality.md               # [CONFIG] Agent pro kontrolu kvality kodu
│   └── ios-architect.md              # [CONFIG] Agent pro iOS architekturu
├── commands/
│   └── lidar-dev.md                  # [CONFIG] Vlastni prikazy pro vyvoj
└── settings.json                     # [CONFIG] Hlavni nastaveni Claude Code projektu
                                      #          (pluginy, LSP, hooks, cesty)
```

---

## 2. `.github/` - CI/CD Workflows

```
.github/
└── workflows/
    ├── build.yml                     # [CONFIG] GitHub Actions - build a testy
    │                                 #          Spousti se na push do main/develop
    └── testflight.yml                # [CONFIG] GitHub Actions - deploy na TestFlight
                                      #          Spousti se na version tagy (v*)
```

---

## 3. `Doc-version2/` - Dokumentace projektu v2

```
Doc-version2/
├── 00_INDEX.md                       # [DOC] Index dokumentace
├── 01_PROJECT_OVERVIEW.md            # [DOC] Prehled projektu
├── 02_DIRECTORY_STRUCTURE.md         # [DOC] Tento soubor - adresarova struktura
└── 05_AUTONOMOUS_DEBUG.md            # [DOC] Autonomni debugovani
```

---

## 4. `LidarAPP/` - iOS aplikace

### 4.1 Korenovy adresar iOS projektu

```
LidarAPP/
├── LidarAPP.xcodeproj/              # Xcode projekt
│   ├── project.pbxproj              # [CONFIG] Hlavni projektovy soubor Xcode
│   ├── project.xcworkspace/
│   │   ├── contents.xcworkspacedata # [CONFIG] Workspace data
│   │   └── xcshareddata/
│   │       ├── IDEWorkspaceChecks.plist  # [CONFIG] IDE kontroly
│   │       └── swiftpm/
│   │           └── Package.resolved      # [CONFIG] Zamcene verze SPM zavislosti
│   └── xcshareddata/
│       └── xcschemes/
│           └── LidarAPP.xcscheme    # [CONFIG] Build scheme
│
├── LidarAPP/                        # Hlavni zdrojovy kod aplikace (viz nize)
├── LidarAPPTests/                   # Unit testy (viz nize)
├── LidarAPPUITests/                 # UI testy (viz nize)
│
├── Test feedback/
│   ├── crashlog.crash               # [DOC] Crash log z testovani
│   └── feedback.json                # [DOC] Zpetna vazba z testovani
│
├── fastlane/                        # Fastlane konfigurace
│   ├── Appfile                      # [CONFIG] App identifikator, Team ID (placeholder)
│   ├── Fastfile                     # [CONFIG] Fastlane lanes (build, test, deploy)
│   ├── Matchfile                    # [CONFIG] Certifikat management (placeholder)
│   └── README.md                    # [DOC] Fastlane dokumentace
│
├── ExportOptions.plist              # [CONFIG] Export nastaveni pro archiv
├── UI_TESTING_SCENARIOS.md          # [DOC] Scenare pro UI testovani
│
│ # Ruby skripty pro modifikaci Xcode projektu:
├── add_crash_reporter.rb            # [SCRIPT] Pridani CrashReporter do projektu
├── add_debug_files.rb               # [SCRIPT] Pridani debug souboru do projektu
├── add_debug_log_overlay.rb         # [SCRIPT] Pridani debug log overlay
├── add_diagnostics.rb               # [SCRIPT] Pridani diagnostiky
├── add_gaussian_renderer.rb         # [SCRIPT] Pridani Gaussian renderer
├── add_metalsplatter.rb             # [SCRIPT] Pridani MetalSplatter zavislosti
├── add_ml_model.rb                  # [SCRIPT] Pridani ML modelu do projektu
├── add_mock_files.rb                # [SCRIPT] Pridani mock souboru
├── add_object_capture_files.rb      # [SCRIPT] Pridani Object Capture souboru
├── add_test_target.rb               # [SCRIPT] Pridani test targetu
├── add_uitest_target.rb             # [SCRIPT] Pridani UI test targetu
├── fix_metalsplatter_version.rb     # [SCRIPT] Oprava verze MetalSplatter
├── fix_test_target.rb               # [SCRIPT] Oprava test targetu
└── update_scheme.rb                 # [SCRIPT] Aktualizace build scheme
```

### 4.2 `LidarAPP/LidarAPP/` - Hlavni zdrojovy kod

#### 4.2.1 `App/` - Vstupni bod aplikace

```
App/
└── LidarAPPApp.swift                 # [IMPL] struct LidarAPPApp: App
                                      #        @main vstupni bod, inicializace Sentry,
                                      #        CrashReporter, DebugStream.
                                      #        Hlavni Scene s MainTabView.
```

#### 4.2.2 `Core/` - Zakladni utility a rozsireni

```
Core/
├── Extensions/
│   └── simd+Extensions.swift         # [IMPL] Rozsireni pro simd_float3, simd_float4,
│                                     #        simd_float4x4, simd_float3x3.
│                                     #        Vektory, matice, transformace, rotace.
│
├── Mock/
│   ├── MockARSessionManager.swift    # [IMPL] class MockARSessionManager
│   │                                 #        Simulace AR session pro simulator.
│   │                                 #        Generuje mock framy, point cloudy, meshe.
│   │
│   ├── MockDataPreviewView.swift     # [IMPL] struct MockDataPreviewView: View
│   │                                 #        SwiftUI nahledy mock dat (point cloud,
│   │                                 #        mesh, mereni, session). Obsahuje take
│   │                                 #        MockSceneView (SceneKit UIViewRepresentable).
│   │
│   └── MockDataProvider.swift        # [IMPL] class MockDataProvider (singleton)
│                                     #        Generuje vzorova data: point cloudy
│                                     #        (krychle, koule, mistnost), meshe,
│                                     #        mereni, kompletni scan sessions.
│
├── Security/
│   └── KeychainService.swift         # [IMPL] actor KeychainService
│                                     #        Bezpecne uloziste pres iOS Keychain.
│                                     #        Save/load/delete pro Data, Codable, String.
│                                     #        Obsahuje enum KeychainError, KeychainKey.
│
└── Utilities/
    ├── AccessibilityIdentifiers.swift # [IMPL] enum AccessibilityIdentifiers
    │                                  #        Centralizovane identifikatory pro UI testy.
    │                                  #        Pokryva TabBar, Gallery, Scanning, ModelDetail,
    │                                  #        Profile, Settings, Auth, Export, Measurement.
    │
    └── DeviceCapabilities.swift       # [IMPL] enum DeviceCapabilities
                                       #        Kontrola LiDAR, depth capture, 4K, Neural Engine.
                                       #        Monitoring pameti (availableMemoryMB, pressure level).
                                       #        CapabilityCheckResult, CapabilityIssue, MemoryPressureLevel.
```

#### 4.2.3 `Domain/Entities/` - Domenove entity

```
Domain/
└── Entities/
    ├── MeshData.swift                # [IMPL] struct MeshData: Identifiable, Sendable
    │                                 #        3D mesh data z LiDAR skenovani.
    │                                 #        Vertices, normals, faces, classifications.
    │                                 #        Vypocty: surfaceArea, volume, boundingBox.
    │                                 #        class CombinedMesh (@Observable) - slucovani meshu.
    │                                 #        enum MeshClassification (wall, floor, ceiling...).
    │
    ├── PointCloud.swift              # [IMPL] struct PointCloud: Identifiable, Sendable
    │                                 #        3D point cloud z LiDAR. Body, barvy, normaly,
    │                                 #        confidence. Transformace, merge, filtrovani.
    │                                 #        struct PointCloudMetadata, BoundingBox.
    │
    ├── ScanMode.swift                # [IMPL] enum ScanMode: String, CaseIterable
    │                                 #        Rezimy skenovani: .exterior (budovy),
    │                                 #        .interior (RoomPlan), .object (ObjectCapture).
    │                                 #        Ceske nazvy (Exterier, Interier, Objekt).
    │
    ├── ScanModel.swift               # [IMPL] struct ScanModel: Identifiable, Hashable
    │                                 #        Model pro galerii skenu. ID, nazev, thumbnail,
    │                                 #        pointCount, faceCount, fileSize, isProcessed.
    │                                 #        enum ScanSortOrder (razeni skenu).
    │
    ├── ScanSession.swift             # [IMPL] class ScanSession (@Observable, Identifiable)
    │                                 #        Kompletni skenovaci session. Stav, point cloud,
    │                                 #        CombinedMesh, TextureFrame, DepthFrame, Measurement.
    │                                 #        Memory management (max frames v pameti).
    │                                 #        enum ScanState (idle/scanning/paused/processing/
    │                                 #        completed/failed).
    │                                 #        struct TextureFrame, Measurement, MeasurementType,
    │                                 #        MeasurementUnit. Extensions UIDevice, Bundle.
    │
    └── User.swift                    # [IMPL] struct User: Identifiable, Codable, Sendable
                                      #        Uzivatelsky model. Email, displayName, avatar,
                                      #        subscription, scanCredits, preferences.
                                      #        enum SubscriptionTier (free/pro/enterprise).
                                      #        struct UserPreferences, AuthTokens,
                                      #        LoginCredentials, RegisterCredentials,
                                      #        AuthResponse, TokenRefreshResponse.
```

#### 4.2.4 `ML/` - Machine Learning modely

```
ML/
└── DepthAnythingV2SmallF16.mlpackage/    # [ASSET] CoreML model Depth Anything V2
    ├── Manifest.json                      #        Manifest ML balicku
    └── Data/
        └── com.apple.CoreML/
            ├── model.mlmodel              #        Definice modelu
            └── weights/
                └── weight.bin             #        Vahy modelu (binarni)
```

#### 4.2.5 `Presentation/` - SwiftUI Views a ViewModels

```
Presentation/
├── Auth/
│   ├── ViewModels/
│   │   └── AuthViewModel.swift           # [IMPL] class AuthViewModel (@Observable)
│   │                                     #        Login, register, Apple Sign In,
│   │                                     #        password reset. Validace formulare,
│   │                                     #        password strength. enum PasswordStrength.
│   │
│   └── Views/
│       ├── AuthView.swift                # [IMPL] struct AuthView: View
│       │                                 #        Login/Register tabs, Apple Sign In,
│       │                                 #        Forgot Password sheet.
│       │                                 #        enum AuthTab, struct ForgotPasswordView,
│       │                                 #        struct AuthTextFieldStyle.
│       │
│       └── ProfileView.swift             # [IMPL] struct ProfileView: View
│                                         #        Uzivatelsky profil, subscription info,
│                                         #        preferences, logout.
│                                         #        struct PreferencesView, SubscriptionInfoView,
│                                         #        SubscriptionCard, AboutView,
│                                         #        ScanHistoryPlaceholder [STUB],
│                                         #        ExportSettingsPlaceholder [STUB].
│
├── Components/
│   └── UserStatusBanner.swift            # [IMPL] struct UserStatusBanner: View
│                                         #        Banner zobrazujici jmeno uzivatele,
│                                         #        zbyvajici skeny, subscription badge.
│                                         #        struct FeatureRow: View.
│
├── Export/
│   ├── ExportService.swift               # [IMPL] actor ExportService
│   │                                     #        Export do OBJ, PLY, STL, glTF, USDZ.
│   │                                     #        Export point cloudu (PLY, OBJ).
│   │                                     #        Export mereni (JSON, CSV).
│   │                                     #        USDZ export = placeholder (exportuje OBJ).
│   │                                     #        enum ExportError.
│   │
│   └── ExportView.swift                  # [IMPL] struct ExportView: View
│                                         #        UI pro vyber formatu a moznosti exportu.
│                                         #        enum ExportFormat (obj/ply/stl/gltf/usdz/
│                                         #        json/csv/pdf), ExportCategory.
│                                         #        class ExportViewModel (@Observable).
│                                         #        struct ExportFormatRow, ShareSheet.
│
├── Gallery/
│   ├── ARPlacementView.swift             # [IMPL] struct ARPlacementView: View
│   │                                     #        Umisteni 3D modelu v AR prostoru.
│   │
│   ├── GalleryExportSheet.swift          # [IMPL] struct GalleryExportSheet: View
│   │                                     #        Export sheet pristupny z galerie.
│   │
│   ├── GalleryView.swift                 # [IMPL] struct GalleryView: View
│   │                                     #        Hlavni galerie skenu (grid/list).
│   │                                     #        Vyhledavani, razeni, prazdny stav.
│   │
│   └── ModelDetailView.swift             # [IMPL] struct ModelDetailView: View
│                                         #        Detail skenu s 3D nahledy.
│                                         #        AI processing, mereni, AR, export.
│
├── Measurement/
│   └── InteractiveMeasurementView.swift  # [IMPL] struct InteractiveMeasurementView: View
│                                         #        Interaktivni mereni nad 3D scn.
│                                         #        SceneKit vizualizace, dotykove ovladani.
│
├── Navigation/
│   └── MainTabView.swift                 # [IMPL] struct MainTabView: View
│                                         #        Hlavni tab bar: Gallery, Capture, Profile.
│                                         #        Vyber rezimu skenovani, sheet pro skenovani.
│
├── ObjectCapture/
│   ├── ObjectCaptureScanningView.swift   # [IMPL] struct ObjectCaptureScanningView: View
│   │                                     #        UI pro Object Capture (RealityKit).
│   │                                     #        Ovladani, progress, fotografie kolem objektu.
│   │
│   └── ViewModels/
│       └── ObjectCaptureScanningModeAdapter.swift
│                                         # [IMPL] class ObjectCaptureScanningModeAdapter
│                                         #        Adapter pro ScanningModeProtocol.
│                                         #        Obaluje ObjectCaptureViewModel.
│
├── Preview/
│   ├── ViewModels/
│   │   └── PreviewViewModel.swift        # [IMPL] class PreviewViewModel (@Observable)
│   │                                     #        ViewModel pro 3D nahled.
│   │                                     #        Rezimy: solid, wireframe, points.
│   │
│   └── Views/
│       ├── Enhanced3DViewer.swift         # [IMPL] struct Enhanced3DViewer: View
│       │                                 #        Pokrocily 3D prohledac se SceneKit.
│       │                                 #        Point cloud, mesh, grid, bounding box,
│       │                                 #        normaly, osvetleni, barevne rezimy.
│       │
│       └── ModelPreviewView.swift        # [IMPL] struct ModelPreviewView: View
│                                         #        3D nahled modelu s SceneKit/RealityKit.
│                                         #        QuickLook integrace.
│
├── Processing/
│   └── ProcessingProgressView.swift      # [IMPL] struct ProcessingProgressView: View
│                                         #        Zobrazeni prubehu zpracovani skenu.
│                                         #        Propojeni s ScanProcessingService.
│
├── Profile/
│   └── ProfileTabView.swift              # [IMPL] struct ProfileTabView: View
│                                         #        Tab profilu. Prihlaseny/neprihlaseny stav.
│                                         #        Nastaveni, mock data nahled, diagnostika.
│
├── RoomPlan/
│   ├── RoomPlanScanningView.swift        # [IMPL] struct RoomPlanScanningView: View
│   │                                     #        UI pro RoomPlan skenovani interieru.
│   │                                     #        RoomCaptureView integrace.
│   │
│   └── ViewModels/
│       └── RoomPlanScanningModeAdapter.swift
│                                         # [IMPL] class RoomPlanScanningModeAdapter
│                                         #        Adapter pro ScanningModeProtocol.
│                                         #        Obaluje RoomPlanViewModel.
│
├── Scanning/
│   ├── Protocols/
│   │   └── ScanningModeProtocol.swift    # [IMPL] protocol ScanningModeProtocol
│   │                                     #        Spolecne rozhrani pro vsechny skenovaci
│   │                                     #        rezimy (LiDAR, RoomPlan, ObjectCapture).
│   │                                     #        Status, ovladani, statistiky.
│   │                                     #        enum UnifiedScanStatus (v StatusIndicator).
│   │
│   ├── ViewModels/
│   │   ├── LiDARScanningModeAdapter.swift # [IMPL] class LiDARScanningModeAdapter
│   │   │                                  #        Adapter pro ScanningModeProtocol.
│   │   │                                  #        Obaluje puvodni ScanningViewModel.
│   │   │
│   │   └── ScanningViewModel.swift        # [IMPL] class ScanningViewModel (@Observable)
│   │                                      #        Hlavni ViewModel pro LiDAR skenovani.
│   │                                      #        Integrace ARSessionManager, PointCloudExtractor,
│   │                                      #        CameraFrameCapture, FrameSynchronizer,
│   │                                      #        DepthFusionProcessor, CoverageAnalyzer.
│   │
│   └── Views/
│       ├── CoverageOverlay.swift          # [IMPL] struct CoverageOverlay: View
│       │                                  #        AR overlay s mini-mapou pokryti
│       │                                  #        a statistikami skenovani.
│       │
│       ├── DebugLogOverlay.swift          # [IMPL] struct DebugLogOverlay: View
│       │                                  #        Overlay s debug logy behem skenovani.
│       │                                  #        struct DebugLog, enum DebugLogLevel.
│       │
│       ├── GuidanceIndicator.swift        # [IMPL] struct GuidanceIndicator: View
│       │                                  #        Vizualni navadeni kamery k nepokrytym
│       │                                  #        oblastem. Pulzujici animace.
│       │
│       ├── ResumeSessionSheet.swift       # [IMPL] struct ResumeSessionSheet: View
│       │                                  #        Sheet pro volbu: novy sken vs.
│       │                                  #        obnoveni ulozene session.
│       │
│       ├── ScanningView.swift             # [IMPL] struct ScanningView: View
│       │                                  #        Hlavni skenovaci UI (puvodni LiDAR verze).
│       │                                  #        RealityKit AR view, ovladaci prvky.
│       │
│       ├── UnifiedScanningView.swift      # [IMPL] struct UnifiedScanningView<Mode>: View
│       │                                  #        Genericke skenovaci UI pro libovolny
│       │                                  #        ScanningModeProtocol. Sdileny layout.
│       │
│       └── Shared/
│           ├── CaptureButton.swift        # [IMPL] enum CaptureButtonState
│           │                              #        Stavy: ready, recording, processing, paused.
│           │                              #        Vizualni capture tlacitko.
│           │
│           ├── SharedControlBar.swift     # [IMPL] struct SharedControlBar<L,R>: View
│           │                              #        Sdileny spodni ovladaci panel pro
│           │                              #        vsechny rezimy. Leve/prave prislusenstvi
│           │                              #        + centralni capture tlacitko.
│           │
│           ├── SharedTopBar.swift         # [IMPL] struct SharedTopBar<R>: View
│           │                              #        Sdileny horni panel. Zavrit,
│           │                              #        status, akce.
│           │
│           ├── StatisticsGrid.swift       # [IMPL] struct StatisticsGrid: View
│           │                              #        Grid se statistikami skenovani
│           │                              #        (body, plochy, cas, atd.).
│           │
│           └── StatusIndicator.swift      # [IMPL] enum UnifiedScanStatus
│                                          #        Unifikovany status vsech rezimu:
│                                          #        idle, preparing, scanning, processing,
│                                          #        completed, error.
│                                          #        struct StatusIndicator: View.
│
└── Settings/
    └── SettingsView.swift                 # [IMPL] struct SettingsView: View
                                           #        Nastaveni aplikace. Backend URL,
                                           #        depth fusion, rozliseni, mock mode,
                                           #        raw data upload, diagnostika.
```

#### 4.2.6 `Services/` - Business logika a sluzby

```
Services/
├── AIGeometry/
│   └── AIGeometryGenerationService.swift  # [IMPL] class AIGeometryGenerationService (@Observable)
│                                          #        AI generovani 3D geometrie.
│                                          #        On-device + cloud procesing.
│                                          #        Doplneni a vylepseni geometrie.
│
├── ARKit/
│   ├── ARSessionManager.swift             # [IMPL] class ARSessionManager: NSObject (@Observable)
│   │                                      #        Sprava ARKit session. LiDAR konfigurace,
│   │                                      #        tracking state, mesh anchors,
│   │                                      #        world mapping status.
│   │
│   ├── CoverageAnalyzer.swift             # [IMPL] class CoverageAnalyzer (@Observable)
│   │                                      #        Analyza pokryti skenu. Grid bunek,
│   │                                      #        detekce mezer, navadeni uzivatele.
│   │
│   ├── DepthMapProcessor.swift            # [IMPL] class DepthMapProcessor (Sendable)
│   │                                      #        Zpracovani a vylepseni LiDAR depth map.
│   │                                      #        Bilateralni filtr, detekce hran,
│   │                                      #        validace hloubky.
│   │
│   ├── MeshAnchorProcessor.swift          # [IMPL] class MeshAnchorProcessor (Sendable)
│   │                                      #        Extrakce mesh dat z ARMeshAnchor.
│   │                                      #        Vertices, normals, faces, classifications.
│   │
│   └── PointCloudExtractor.swift          # [IMPL] class PointCloudExtractor (Sendable)
│                                          #        Extrakce point cloudu z ARKit depth.
│                                          #        Voxel downsampling, confidence filtrovani.
│
├── Auth/
│   └── AuthService.swift                  # [IMPL] class AuthService (@Observable)
│                                          #        Sprava autentizace. Login, register,
│                                          #        Apple Sign In, token refresh, logout.
│                                          #        Keychain persistence.
│
├── Camera/
│   ├── CameraFrameCapture.swift           # [IMPL] class CameraFrameCapture (Sendable)
│   │                                      #        Zachytavani high-res kamerovych snimku.
│   │                                      #        HEIC/JPEG komprese, synchronizace s LiDAR.
│   │
│   └── FrameSynchronizer.swift            # [IMPL] class FrameSynchronizer (@Observable)
│                                          #        Synchronizace RGB a depth dat.
│                                          #        SynchronizedFrame s casovou znackou.
│
├── Debug/
│   ├── DebugLogger.swift                  # [IMPL] enum LogLevel + logging funkce
│   │                                      #        Strukturovane logovani s OSLog.
│   │                                      #        Urovne: debug, info, warning, error.
│   │
│   ├── DebugSettings.swift                # [IMPL] class DebugSettings (@Observable, singleton)
│   │                                      #        Centralizovane debug nastaveni.
│   │                                      #        Raw data pipeline, debug stream,
│   │                                      #        @AppStorage perzistence.
│   │
│   ├── DebugStreamService.swift           # [IMPL] struct DebugEvent + service
│   │                                      #        Real-time streaming debug udalosti
│   │                                      #        na backend. WebSocket + HTTP batch.
│   │                                      #        struct AnyCodableValue.
│   │
│   ├── DepthFrame.swift                   # [IMPL] struct DepthFrame: Identifiable, Sendable
│   │                                      #        Zachyceny depth frame s metadaty.
│   │                                      #        Camera transform, intrinsics, depth data.
│   │
│   ├── PerformanceMonitor.swift           # [IMPL] struct PerformanceSnapshot + monitor
│   │                                      #        Monitorovani vykonu: FPS, pamet,
│   │                                      #        CPU, teplota, baterie.
│   │
│   ├── RawDataPackager.swift              # [IMPL] Binarni format LRAW pro raw data.
│   │                                      #        Balovani mesh anchors, texture frames,
│   │                                      #        depth frames do jednoho souboru.
│   │
│   └── RawDataUploader.swift              # [IMPL] actor RawDataUploader
│                                          #        Upload raw dat na debug backend.
│                                          #        Chunked upload, resume, progress.
│
├── Diagnostics/
│   ├── AppDiagnostics.swift               # [IMPL] class AppDiagnostics (@Observable, singleton)
│   │                                      #        In-app diagnostika a testovani.
│   │                                      #        Kontrola ARKit, LiDAR, pameti, site.
│   │
│   └── CrashReporter.swift               # [IMPL] class CrashReporter (singleton)
│                                          #        Sber crash reportu pres MetricKit.
│                                          #        MXDiagnosticPayload, MXMetricPayload.
│
├── EdgeML/
│   ├── DepthAnythingModel.swift           # [IMPL] class DepthAnythingModel
│   │                                      #        CoreML wrapper pro Depth Anything V2.
│   │                                      #        Monokulerni odhad hloubky 518x518.
│   │
│   ├── DepthFusionProcessor.swift         # [IMPL] class DepthFusionProcessor
│   │                                      #        Fuze LiDAR depth s AI depth.
│   │                                      #        Resolution multiplier 4x (256x192 -> 1024x768).
│   │
│   ├── EdgeMLGeometryService.swift        # [IMPL] Edge ML service pro instant 3D.
│   │                                      #        Depth enhancement, segmentace,
│   │                                      #        detekce primitiv, neuronni rekonstrukce.
│   │
│   ├── HighResPointCloudExtractor.swift   # [IMPL] class HighResPointCloudExtractor
│   │                                      #        Extrakce high-res point cloudu z
│   │                                      #        fuze depth. Max 2M bodu, 5mm voxely.
│   │
│   ├── MeshCorrectionModel.swift          # [IMPL] class MeshCorrectionModel
│   │                                      #        CoreML model pro korekci meshe.
│   │                                      #        Batch processing, Neural Engine.
│   │
│   └── OnDeviceProcessor.swift            # [IMPL] class OnDeviceProcessor (@Observable)
│                                          #        Orchestrace on-device AI pipeline.
│                                          #        Faze: inicializace, korekce, export.
│
├── Measurement/
│   ├── AreaCalculator.swift               # [IMPL] class AreaCalculator (Sendable)
│   │                                      #        Vypocet ploch 3D polygonu.
│   │                                      #        Shoelace formula, best-fit roviny.
│   │
│   ├── DistanceCalculator.swift           # [IMPL] class DistanceCalculator (Sendable)
│   │                                      #        Euklidovske vzdalenosti, bod-usecka,
│   │                                      #        bod-rovina, prumerna vzdalenost.
│   │
│   ├── MeasurementService.swift           # [IMPL] class MeasurementService (@Observable)
│   │                                      #        Orchestrace mereni. Rezimy:
│   │                                      #        distance, area, volume, angle.
│   │
│   └── VolumeCalculator.swift             # [IMPL] class VolumeCalculator (Sendable)
│                                          #        Vypocet objemu z bounding box,
│                                          #        tetraedru, convex hull.
│
├── Network/
│   ├── APIClient.swift                    # [IMPL] actor APIClient
│   │                                      #        HTTP klient pro backend API.
│   │                                      #        Retry, timeout, autentizace.
│   │
│   ├── ChunkedUploader.swift              # [IMPL] actor ChunkedUploader
│   │                                      #        Chunked upload velkych souboru.
│   │                                      #        5MB chunky, resume, 3 retries.
│   │
│   └── WebSocketService.swift             # [IMPL] class WebSocketService (@Observable)
│                                          #        WebSocket pro real-time aktualizace.
│                                          #        Reconnect, heartbeat, state management.
│
├── ObjectCapture/
│   └── ObjectCaptureService.swift         # [IMPL] protocol ObjectCaptureServiceProtocol
│                                          #        + implementace. RealityKit ObjectCapture.
│                                          #        Fotografie kolem objektu, progress,
│                                          #        rekonstrukce.
│
├── Persistence/
│   ├── ChunkManager.swift                 # [IMPL] actor ChunkManager
│   │                                      #        Streaming mesh/point cloud dat na disk.
│   │                                      #        50k vertices/chunk, komprese.
│   │
│   ├── ScanSessionPersistence.swift       # [IMPL] actor ScanSessionPersistence
│   │                                      #        Ukladani/nacitani scan sessions.
│   │                                      #        ARWorldMap pro obnovitelne skenovani.
│   │
│   └── ScanStore.swift                    # [IMPL] class ScanStore (@Observable)
│                                          #        Centralni uloziste vsech skenu.
│                                          #        Seznam ScanModel, prave ScanSession data.
│
├── Processing/
│   └── ScanProcessingService.swift        # [IMPL] enum ScanProcessingState + service
│                                          #        Orchestrace zpracovani skenu.
│                                          #        Faze: scanning, processing, uploading,
│                                          #        server processing, downloading, completed.
│
├── Rendering/
│   ├── CameraController.swift             # [IMPL] class CameraController (@Observable)
│   │                                      #        3D kamera: orbit, pan, zoom.
│   │                                      #        Dotykove gesta, inertia.
│   │
│   ├── GaussianSplatRenderer.swift        # [IMPL] struct GaussianSplat + renderer
│   │                                      #        Metal-based 3D Gaussian Splatting renderer.
│   │                                      #        Sorting, tiling, alpha blending.
│   │
│   ├── LiveMeshRenderer.swift             # [IMPL] class LiveMeshRenderer
│   │                                      #        RealityKit live mesh vizualizace.
│   │                                      #        Wireframe, opacity, barvy.
│   │
│   ├── PointCloudRenderer.swift           # [IMPL] class PointCloudRenderer
│   │                                      #        Metal real-time point cloud renderer.
│   │                                      #        Az 1M bodu, barevne rezimy.
│   │
│   └── TextureMappingService.swift        # [IMPL] class TextureMappingService
│                                          #        Projekce textur na mesh.
│                                          #        UV mapovani, best-view vyber.
│
└── RoomPlan/
    └── RoomPlanService.swift              # [IMPL] protocol RoomPlanServiceProtocol
                                           #        + implementace. Apple RoomPlan API.
                                           #        Automaticka detekce sten, dveri, oken.
```

#### 4.2.7 `Resources/` - Assety a konfigurace

```
Resources/
├── Assets.xcassets/
│   ├── Contents.json                     # [CONFIG] Asset catalog root
│   ├── AccentColor.colorset/
│   │   └── Contents.json                 # [CONFIG] Akcentova barva aplikace
│   └── AppIcon.appiconset/
│       ├── Contents.json                 # [CONFIG] Konfigurace app ikon
│       ├── AppIcon-1024.png              # [ASSET] App ikona 1024x1024 (App Store)
│       ├── AppIcon-180.png               # [ASSET] App ikona 180x180 (iPhone @3x)
│       ├── AppIcon-167.png               # [ASSET] App ikona 167x167 (iPad Pro)
│       ├── AppIcon-152.png               # [ASSET] App ikona 152x152 (iPad)
│       ├── AppIcon-120.png               # [ASSET] App ikona 120x120 (iPhone @2x)
│       └── AppIcon-76.png               # [ASSET] App ikona 76x76 (iPad @1x)
│
├── Info.plist                            # [CONFIG] Dalsi Info.plist (Resources slozka)
└── LidarAPP.entitlements                 # [CONFIG] App entitlements (opravneni)
```

#### 4.2.8 Hlavni `Info.plist`

```
LidarAPP/
└── Info.plist                            # [CONFIG] Hlavni Info.plist aplikace
                                          #        Opravneni kamery, ARKit, atd.
```

### 4.3 `LidarAPPTests/` - Unit testy

```
LidarAPPTests/
├── Info.plist                            # [CONFIG] Test target Info.plist
├── MeshDataTests.swift                   # [TEST] class MeshDataTests: XCTestCase
│                                         #        Testy MeshData entity (inicializace,
│                                         #        plocha, objem, bounding box).
│
├── PointCloudTests.swift                 # [TEST] class PointCloudTests: XCTestCase
│                                         #        Testy PointCloud entity (inicializace,
│                                         #        transformace, merge, filtrovani).
│
├── ScanSessionTests.swift                # [TEST] class ScanSessionTests: XCTestCase
│                                         #        Testy ScanSession (stavy, data management,
│                                         #        memory limits).
│
├── MockDataProviderTests.swift           # [TEST] class MockDataProviderTests: XCTestCase
│                                         #        Testy MockDataProvider (generovani dat,
│                                         #        point cloudu, meshu, session).
│
└── IntegrationTests.swift                # [TEST] class IntegrationTests: XCTestCase
                                          #        Integracni testy (kompletni scan workflow,
                                          #        export pipeline).
```

### 4.4 `LidarAPPUITests/` - UI testy

```
LidarAPPUITests/
├── Info.plist                            # [CONFIG] UI test target Info.plist
│
├── Pages/                                # Page Object pattern
│   ├── BasePage.swift                    # [TEST] Zakladni trida pro vsechny Pages
│   ├── AuthPage.swift                    # [TEST] Page Object pro autentizaci
│   ├── ExportPage.swift                  # [TEST] Page Object pro export
│   ├── GalleryPage.swift                 # [TEST] Page Object pro galerii
│   ├── ModelDetailPage.swift             # [TEST] Page Object pro detail modelu
│   ├── ProfilePage.swift                 # [TEST] Page Object pro profil
│   ├── ScanModeSelectorPage.swift        # [TEST] Page Object pro vyber rezimu
│   ├── ScanningPage.swift                # [TEST] Page Object pro skenovani
│   ├── SettingsPage.swift                # [TEST] Page Object pro nastaveni
│   └── TabBarPage.swift                  # [TEST] Page Object pro tab bar
│
├── TestCases/
│   ├── AppLaunchTests.swift              # [TEST] class AppLaunchTests: BaseUITestCase
│   │                                     #        Testy spusteni aplikace.
│   │
│   ├── AuthenticationTests.swift         # [TEST] Testy prihlaseni/registrace
│   ├── GalleryTests.swift                # [TEST] Testy galerie
│   ├── NavigationTests.swift             # [TEST] Testy navigace
│   ├── ProfileTests.swift                # [TEST] Testy profilu
│   ├── ScanningModeTests.swift           # [TEST] Testy skenovacich rezimu
│   └── SettingsTests.swift               # [TEST] Testy nastaveni
│
└── Utilities/
    ├── AccessibilityIdentifiers.swift    # [TEST] Kopie identifikatoru pro UI testy
    ├── BaseUITestCase.swift              # [TEST] class BaseUITestCase: XCTestCase
    │                                     #        Zakladni trida pro vsechny UI testy.
    │                                     #        Setup, teardown, utility metody.
    │
    └── XCTestExtensions.swift            # [TEST] Rozsireni XCTest pro pohodlnejsi testovani
```

---

## 5. `backend/` - Python backend

```
backend/
├── api/                                  # FastAPI endpointy
│   ├── __init__.py                       # [CONFIG] Python package init (prazdny)
│   ├── main.py                           # [IMPL] FastAPI aplikace, CORS, routy
│   │                                     #        Hlavni server pro 3D zpracovani.
│   │                                     #        REST API + WebSocket endpointy.
│   │
│   ├── auth.py                           # [IMPL] JWT autentizace pro admin dashboard
│   │                                     #        Cookie-based sessions, login/logout.
│   │
│   ├── admin.py                          # [IMPL] Admin dashboard webove routy
│   │                                     #        Monitoring, sprava zpracovani skenu.
│   │
│   ├── debug.py                          # [IMPL] Debug API endpointy
│   │                                     #        Raw data upload, debug stream WebSocket,
│   │                                     #        chunked upload, batch HTTP.
│   │
│   └── ios_auth.py                       # [IMPL] JWT autentizace pro iOS aplikaci
│                                         #        Oddelena od admin auth.
│                                         #        V test modu prijima libovolne udaje.
│
├── services/                             # Business logika
│   ├── __init__.py                       # [CONFIG] Python package init (prazdny)
│   ├── scan_processor.py                 # [IMPL] class ScanProcessor
│   │                                     #        Orchestrace pipeline: preprocessing,
│   │                                     #        Gaussian Splatting, SuGaR, texture baking,
│   │                                     #        export.
│   │
│   ├── gaussian_splatting.py             # [IMPL] 3D Gaussian Splatting trenink
│   │                                     #        Neuronni radiance field.
│   │                                     #        Vyzaduje CUDA GPU.
│   │
│   ├── sugar_mesh.py                     # [IMPL] SuGaR mesh extrakce
│   │                                     #        Ciste trojuhelnikove meshe z Gaussian Splatting.
│   │
│   ├── texture_baker.py                  # [IMPL] Texture baking service
│   │                                     #        UV unwrapping (xatlas), projekce textur,
│   │                                     #        seam blending, PBR materialy.
│   │
│   ├── simple_pipeline.py               # [IMPL] Jednoduchy pipeline pro Apple Silicon
│   │                                     #        Bez CUDA: LRAW parse, Depth Anything V2,
│   │                                     #        Poisson rekonstrukce (Open3D), export.
│   │
│   ├── depth_anything.py                 # [IMPL] Depth Anything V2 (PyTorch)
│   │                                     #        Serverova verze stejneho modelu jako iOS.
│   │                                     #        HuggingFace transformers.
│   │
│   ├── depth_fusion.py                   # [IMPL] Fuze LiDAR + AI depth (serverova)
│   │                                     #        Stejny algoritmus jako iOS DepthFusionProcessor.
│   │
│   ├── export_service.py                 # [IMPL] Export modelu do USDZ, glTF, OBJ, STL, PLY
│   │
│   ├── storage.py                        # [IMPL] class StorageService
│   │                                     #        Ukladani souboru (local FS + S3 kompatibilni).
│   │                                     #        Metadata perzistence JSON.
│   │
│   ├── websocket_manager.py              # [IMPL] class WebSocketManager
│   │                                     #        Sprava WebSocket spojeni.
│   │                                     #        Real-time processing updates.
│   │
│   ├── log_storage.py                    # [IMPL] Ukladani a nacitani procesing logu
│   │                                     #        JSON format, file-based storage.
│   │
│   └── raw_data_processor.py             # [IMPL] Parser LRAW binarniho formatu
│                                         #        Konverze iOS raw dat na standardni vstupy.
│
├── models/
│   └── __init__.py                       # [CONFIG] Python package init (prazdny)
│                                         #        Pripraveno pro Pydantic/SQLAlchemy modely.
│
├── utils/
│   ├── __init__.py                       # [CONFIG] Python package init (prazdny)
│   ├── logger.py                         # [IMPL] Konfigurace logovani (structlog)
│   │                                     #        JSON pro produkci, barevny konzolovy vystup
│   │                                     #        pro vyvoj.
│   │
│   └── gpu_monitor.py                    # [IMPL] Monitoring GPU pres nvidia-smi
│                                         #        Pamet, vyuziti, teplota, prikon.
│                                         #        Podpora i pro systemy bez GPU (psutil).
│
├── worker/                               # Celery background tasks
│   ├── __init__.py                       # [CONFIG] Python package init (prazdny)
│   ├── celery_app.py                     # [IMPL] Celery konfigurace s Redis
│   │                                     #        Nastaveni fronty uloh.
│   │
│   └── tasks.py                          # [IMPL] Celery tasky pro zpracovani skenu
│                                         #        Background processing pipeline.
│
├── scripts/
│   ├── seed_demo_data.py                 # [SCRIPT] Seedovani demo dat pro testovani
│   │                                     #          Generuje vzorove skeny a metadata.
│   │
│   └── test_api.sh                       # [SCRIPT] Bash skript pro testovani API
│                                         #          Kontrola endpointu, upload, status.
│
├── static/
│   └── js/
│       ├── dashboard.js                  # [ASSET] JavaScript pro admin dashboard
│       └── pointcloud-viewer.js          # [ASSET] JavaScript 3D point cloud viewer
│
├── templates/                            # Jinja2 HTML sablony
│   ├── base.html                         # [ASSET] Zakladni layout sablona
│   ├── login.html                        # [ASSET] Prihlasovaci stranka
│   ├── dashboard.html                    # [ASSET] Hlavni dashboard
│   ├── debug_dashboard.html              # [ASSET] Debug dashboard
│   ├── scans.html                        # [ASSET] Seznam skenu
│   ├── scan_detail.html                  # [ASSET] Detail skenu
│   ├── processing.html                   # [ASSET] Stav zpracovani
│   ├── logs.html                         # [ASSET] Zobrazeni logu
│   └── system.html                       # [ASSET] Systemove informace
│
├── certs/                                # SSL certifikaty
│   ├── LiDAR_Debug_CA.crt               # [CONFIG] Debug CA certifikat
│   ├── ca-cert.srl                       # [CONFIG] CA serial number
│   ├── extfile.cnf                       # [CONFIG] OpenSSL extension konfigurace
│   └── server.csr                        # [CONFIG] Server certificate signing request
│
├── debug_server.py                       # [IMPL] Minimalni debug server
│                                         #        Lehky server pro testovani debug pipeline
│                                         #        bez tezkych 3D zavislosti.
│
├── debug_lraw.py                         # [SCRIPT] Debug skript pro LRAW parsing
│                                         #          Detailni analyza binarniho formatu.
│
├── Dockerfile                            # [CONFIG] Produkci Docker image (multi-stage)
├── Dockerfile.dev                        # [CONFIG] Vyvojovy Docker image (bez CUDA)
├── docker-compose.yml                    # [CONFIG] Docker Compose - produkce (API + Worker + Redis)
├── docker-compose.dev.yml                # [CONFIG] Docker Compose - vyvoj (Apple Silicon)
│                                         #          HTTP:8080, HTTPS:8444 (Tailscale)
│
├── requirements.txt                      # [CONFIG] Python zavislosti
│                                         #          FastAPI, PyTorch, Open3D, trimesh, atd.
│
├── server.log                            # Server log soubor (runtime)
├── DEVELOPMENT.md                        # [DOC] Vyvojova dokumentace backendu
└── README.md                             # [DOC] README backendu
```

---

## 6. `docs/` - Projektova dokumentace

```
docs/
├── 3D_GENERATION_PIPELINE.md             # [DOC] Popis 3D generacniho pipeline
│                                         #        Gaussian Splatting, SuGaR, texture baking.
│
├── DEVELOPMENT_PHASES.md                 # [DOC] Faze vyvoje projektu
│                                         #        Detailni rozdeleni na etapy.
│
├── LUMISCAN_MOCKUP.md                    # [DOC] LumiScan mockup specifikace
│                                         #        Navrh UI a UX.
│
├── Lumiscan_Product_Specification.docx   # [DOC] Produktova specifikace (Word)
│                                         #        Kompletni produktovy dokument.
│
├── ML_IMPROVEMENTS_PROPOSAL.md           # [DOC] Navrh na vylepseni ML modelu
│                                         #        Depth fusion, mesh korekce, segmentace.
│
└── VERSIONING.md                         # [DOC] Verzovaci strategie
                                          #        Semantic versioning, release proces.
```

---

## 7. `scripts/` - Pomocne skripty

```
scripts/
├── debug_ios.sh                          # [SCRIPT] iOS debug helper
│                                         #          Screenshot, logy, video, UI hierarchy.
│
└── maestro/
    └── scan_flow.yaml                    # [CONFIG] Maestro E2E test flow
                                          #          Automatizovany test skenovaciho procesu.
                                          #          AppId: com.petrzapletal.lidarscanner
```

---

## Souhrn statistik

| Kategorie | Pocet souboru |
|-----------|---------------|
| **Swift zdrojove soubory (.swift)** | 72 |
| -- Presentation (Views + ViewModels) | 32 |
| -- Services | 28 |
| -- Domain/Entities | 6 |
| -- Core (Extensions, Mock, Security, Utilities) | 6 |
| **Swift testy** | 17 |
| -- Unit testy | 5 |
| -- UI testy (Pages + TestCases + Utilities) | 12 |
| **Python zdrojove soubory (.py)** | 21 |
| -- API endpointy | 5 |
| -- Services | 12 |
| -- Utils + Worker | 4 |
| **Konfiguracni soubory** | ~25 |
| **HTML sablony** | 9 |
| **JavaScript soubory** | 2 |
| **Ruby skripty (.rb)** | 12 |
| **Shell skripty (.sh)** | 2 |
| **YAML soubory** | 3 |
| **Dokumentace (.md)** | ~15 |
| **ML model** | 1 balicek (DepthAnythingV2SmallF16) |

---

## Architektura - vizualni prehled

```
+-------------------+       HTTPS/WSS        +-------------------+
|                   | <--------------------> |                   |
|   iOS Aplikace    |    Tailscale VPN       |  Python Backend   |
|   (LidarAPP/)     |    Port 8444           |  (backend/)       |
|                   |                        |                   |
|  SwiftUI + MVVM   |                        |  FastAPI + Celery |
|  ARKit + Metal    |                        |  PyTorch + Open3D |
|  CoreML (Edge)    |                        |  3DGS + SuGaR     |
+-------------------+                        +-------------------+
        |                                            |
        v                                            v
  LiDAR senzor                                 CUDA/MPS GPU
  RGB kamera                                   Redis (fronta)
  Depth Anything V2                            S3 storage
```
