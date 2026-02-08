# 11 - Rewrite Plan (Přístup C: Čistý rewrite)

## Strategie

Stávající iOS kód přesunout do `_legacy/` jako referenci. Nový čistý Xcode projekt postavit od nuly podle Doc-version2 specifikace. Backend zachovat a rozšířit.

## Co zachovat 1:1

| Zdroj | Důvod |
|-------|-------|
| `Doc-version2/` | Specifikace = ground truth |
| `backend/` | Funguje, jen rozšířit |
| `.claude/` | Agent konfigurace |
| `Services/Debug/*` | Robustní, dobře napsané (DebugLogger, DebugStreamService, PerformanceMonitor, RawDataPackager, RawDataUploader, DebugSettings) |
| `Services/Diagnostics/*` | CrashReporter (MetricKit) funguje |
| `Domain/Entities/*` | Entity modely jsou čisté |
| `Core/Security/KeychainService.swift` | Keychain wrapper funguje |
| `Core/Extensions/simd+Extensions.swift` | Utility extension |
| `ML/DepthAnythingV2SmallF16.mlpackage/` | CoreML model (~100MB weights) |
| `Resources/Assets.xcassets` | App ikony, barvy, launch screen |
| Sentry SDK konfigurace | DSN, options - přenést |

## Co přepsat od nuly

| Oblast | Problém ve stávajícím kódu |
|--------|---------------------------|
| DI container | Žádný neexistuje, vše jsou singletons nebo přímé init |
| Protokoly | Jen 5% services má protokol |
| ARKit scanning | ARSessionManager je monolitický, bez protokolu |
| Camera | CameraFrameCapture bez protokolu |
| Export | USDZ je fake (přejmenuje OBJ), ExportService je v Presentation/ |
| Rendering | Rozptýlené mezi MetalSplatter, PointCloudRenderer, LiveMeshRenderer |
| Network | APIClient bez interceptoru, bez automatického logování |
| Persistence | ScanStore + ScanSessionPersistence bez jasné abstrakce |
| Measurement | Funguje, ale bez protokolů |
| ViewModels | Mix *ViewModel a *Adapter pojmenování |
| Views | Fungují, ale potřebují lepší DI |

## Xcode projekt konfigurace (nový)

```
Product Name:        LidarAPP
Bundle ID:           com.petrzapletal.lidarscanner
Team ID:             65HGP9PL6X
Swift Version:       5.0
iOS Deployment:      17.0
Code Sign:           Automatic
SPM Dependencies:    MetalSplatter (>=0.1.0), sentry-cocoa (>=8.0.0)
Capabilities:        Sign in with Apple, Keychain Sharing
```

### Info.plist klíče (zachovat)

```
NSCameraUsageDescription
NSPhotoLibraryUsageDescription
NSPhotoLibraryAddUsageDescription
NSLocationWhenInUseUsageDescription
NSAppTransportSecurity (allow 100.96.188.18)
UIFileSharingEnabled = true
LSSupportsOpeningDocumentsInPlace = true
UIRequiredDeviceCapabilities = [armv7, arkit, lidar]
```

---

## Sprint 0: Repo Setup + Skeleton

**Cíl:** Čistá kostra projektu, DI container, migrace debug infrastruktury, build prochází.

### Úkoly

```
0.1  Přesunout LidarAPP/ → _legacy/LidarAPP/
0.2  Vytvořit novou adresářovou strukturu
0.3  Přenést Xcode projekt soubory (project.pbxproj vytvořit nový)
0.4  Přenést Resources (Assets.xcassets, Info.plist, entitlements)
0.5  Vytvořit Core/DI/ServiceContainer.swift
0.6  Vytvořit Core/Protocols/ - všechny service protokoly
0.7  Vytvořit Core/Errors/ - sdílené error typy
0.8  Přenést Domain/Entities/ (1:1)
0.9  Přenést Services/Debug/ (1:1, funguje)
0.10 Přenést Services/Diagnostics/ (CrashReporter)
0.11 Přenést Core/Security/KeychainService.swift
0.12 Přenést Core/Extensions/
0.13 Přenést ML/DepthAnythingV2SmallF16.mlpackage/
0.14 Vytvořit App/LidarAPPApp.swift (Sentry init, DI setup)
0.15 Vytvořit minimální MainTabView (placeholder tabs)
0.16 Ověřit build (xcodebuild)
```

### Nová adresářová struktura

```
LidarAPP/
├── LidarAPP.xcodeproj/
├── LidarAPP/
│   ├── App/
│   │   └── LidarAPPApp.swift
│   ├── Core/
│   │   ├── DI/
│   │   │   └── ServiceContainer.swift      # NOVÉ - centrální DI
│   │   ├── Protocols/
│   │   │   ├── ARSessionServiceProtocol.swift
│   │   │   ├── CameraServiceProtocol.swift
│   │   │   ├── ExportServiceProtocol.swift
│   │   │   ├── NetworkServiceProtocol.swift
│   │   │   ├── PersistenceServiceProtocol.swift
│   │   │   ├── ScanningModeProtocol.swift
│   │   │   ├── MeasurementServiceProtocol.swift
│   │   │   └── RenderingServiceProtocol.swift
│   │   ├── Errors/
│   │   │   ├── ScanError.swift
│   │   │   ├── ExportError.swift
│   │   │   ├── NetworkError.swift
│   │   │   └── AuthError.swift
│   │   ├── Extensions/
│   │   │   └── simd+Extensions.swift       # Z legacy
│   │   └── Security/
│   │       └── KeychainService.swift       # Z legacy
│   ├── Domain/
│   │   └── Entities/
│   │       ├── ScanSession.swift           # Z legacy
│   │       ├── ScanModel.swift             # Z legacy
│   │       ├── ScanMode.swift              # Z legacy
│   │       ├── MeshData.swift              # Z legacy
│   │       ├── PointCloud.swift            # Z legacy
│   │       └── User.swift                  # Z legacy
│   ├── Services/
│   │   ├── Debug/                          # Z legacy (celý, 1:1)
│   │   │   ├── DebugLogger.swift
│   │   │   ├── DebugStreamService.swift
│   │   │   ├── DebugSettings.swift
│   │   │   ├── PerformanceMonitor.swift
│   │   │   ├── RawDataPackager.swift
│   │   │   ├── RawDataUploader.swift
│   │   │   └── DepthFrame.swift
│   │   └── Diagnostics/                    # Z legacy
│   │       ├── CrashReporter.swift
│   │       └── AppDiagnostics.swift
│   ├── Presentation/
│   │   ├── Navigation/
│   │   │   └── MainTabView.swift           # NOVÉ - placeholder
│   │   └── Components/                     # NOVÉ - shared UI
│   ├── ML/
│   │   └── DepthAnythingV2SmallF16.mlpackage/  # Z legacy
│   └── Resources/
│       ├── Assets.xcassets                 # Z legacy
│       ├── Info.plist                      # Z legacy (upravit)
│       └── LidarAPP.entitlements           # Z legacy
├── LidarAPPTests/
│   └── ServiceContainerTests.swift         # NOVÉ
└── LidarAPPUITests/
```

### ServiceContainer design

```swift
/// Centrální DI container - constructor injection
@MainActor
@Observable
final class ServiceContainer {
    // MARK: - Core Services
    let debugLogger: DebugLogger
    let debugStream: DebugStreamService
    let performanceMonitor: PerformanceMonitor
    let crashReporter: CrashReporter

    // MARK: - Feature Services (lazy, protocol-backed)
    private(set) lazy var arSession: any ARSessionServiceProtocol = ARSessionService(logger: debugLogger)
    private(set) lazy var camera: any CameraServiceProtocol = CameraService(logger: debugLogger)
    private(set) lazy var export: any ExportServiceProtocol = ExportService(logger: debugLogger)
    private(set) lazy var network: any NetworkServiceProtocol = NetworkService(logger: debugLogger)
    private(set) lazy var persistence: any PersistenceServiceProtocol = PersistenceService(logger: debugLogger)
    private(set) lazy var measurement: any MeasurementServiceProtocol = MeasurementService(logger: debugLogger)

    // MARK: - Init
    init() {
        self.debugLogger = DebugLogger.shared
        self.debugStream = DebugStreamService.shared
        self.performanceMonitor = PerformanceMonitor.shared
        self.crashReporter = CrashReporter.shared
    }

    // MARK: - Testing
    /// Pro unit testy - injektuj mock implementace
    init(
        arSession: any ARSessionServiceProtocol,
        camera: any CameraServiceProtocol,
        // ...
    ) {
        // ...
    }
}
```

### Pravidla pro nový kód

```
1. Žádný print()              → vždy debugLog() / errorLog()
2. Žádný singleton přístup     → vždy přes ServiceContainer
3. Každý service má protokol   → protocol *ServiceProtocol
4. Každý service má error enum → enum *Error: Error, LocalizedError
5. @Observable                 → žádný @Published / ObservableObject
6. Constructor injection       → žádný @EnvironmentObject
7. async/await                 → žádné callback hell
8. Unit test pro každý service → mock přes protokol
```

---

## Sprint 1: Scan Pipeline (End-to-End)

**Cíl:** Jedna funkční cesta: LiDAR scan → LRAW → Backend → GLB

### Úkoly

```
1.1  ARSessionService + ARSessionServiceProtocol
     - startSession(mode: ScanMode)
     - pauseSession() / resumeSession()
     - delegate callbacks (tracking state, mesh anchors)
     - Integrovat DebugStreamService (AR events)

1.2  MeshProcessor
     - MeshAnchorProcessor (z legacy, refactor s protokolem)
     - PointCloudExtractor (z legacy, refactor)
     - DepthMapProcessor (z legacy, refactor)
     - CoverageAnalyzer (z legacy, refactor)

1.3  ScanningView + ScanningViewModel
     - AR view s live mesh rendering
     - Start/stop/pause ovládání
     - DebugLogOverlay (z legacy)
     - Performance stats overlay
     - Coverage overlay

1.4  LRAW Export + Upload
     - RawDataPackager (už přenesený)
     - RawDataUploader (už přenesený)
     - Upload progress UI

1.5  Backend Processing
     - Ověřit SimplePipeline end-to-end
     - LRAW → Depth Enhancement → Poisson → GLB
     - Stáhnout výsledný GLB

1.6  Výsledek ke stažení
     - API endpoint pro GLB download
     - Uložení do lokálního storage
```

### Soubory k vytvoření

```
Services/ARKit/ARSessionService.swift
Services/ARKit/MeshAnchorProcessor.swift      (refactor z legacy)
Services/ARKit/PointCloudExtractor.swift       (refactor z legacy)
Services/ARKit/DepthMapProcessor.swift         (refactor z legacy)
Services/ARKit/CoverageAnalyzer.swift          (refactor z legacy)
Services/Camera/CameraService.swift
Services/Camera/FrameSynchronizer.swift        (refactor z legacy)
Presentation/Scanning/Views/ScanningView.swift
Presentation/Scanning/Views/DebugLogOverlay.swift  (z legacy)
Presentation/Scanning/ViewModels/ScanningViewModel.swift
Core/Protocols/ARSessionServiceProtocol.swift
Core/Protocols/CameraServiceProtocol.swift
Core/Errors/ScanError.swift
```

---

## Sprint 2: Preview + Export

**Cíl:** 3D náhled naskenovaného modelu, reálný export do OBJ/GLB/USDZ.

### Úkoly

```
2.1  ExportService + ExportServiceProtocol
     - exportOBJ(meshData:) → URL       ← funguje v legacy
     - exportGLB(meshData:) → URL       ← dodělat (trimesh na backendu)
     - exportUSDZ(meshData:) → URL      ← REÁLNÝ (ModelIO framework)
     - exportPLY(pointCloud:) → URL

2.2  ModelPreviewView
     - SceneKit/RealityKit 3D viewer
     - Orbit, zoom, pan ovládání
     - Wireframe/solid/textured mody
     - Light/dark prostředí

2.3  GalleryView + GalleryViewModel
     - Grid s thumbnaily naskenovaných modelů
     - Detail view s metadaty
     - Swipe to delete
     - Share sheet pro export

2.4  PersistenceService + PersistenceServiceProtocol
     - saveScan(session:meshData:) → ScanModel
     - loadScans() → [ScanModel]
     - deleteScan(id:)
     - File management (OBJ/GLB soubory na disku)
```

### Soubory k vytvoření

```
Services/Export/ExportService.swift            (NOVÝ - reálný USDZ)
Presentation/Preview/Views/ModelPreviewView.swift
Presentation/Preview/ViewModels/PreviewViewModel.swift
Presentation/Gallery/Views/GalleryView.swift
Presentation/Gallery/ViewModels/GalleryViewModel.swift
Presentation/Gallery/Views/ModelDetailView.swift
Services/Persistence/PersistenceService.swift
Core/Protocols/ExportServiceProtocol.swift
Core/Protocols/PersistenceServiceProtocol.swift
Core/Errors/ExportError.swift
```

---

## Sprint 3: Alternativní skenovací režimy + ML

**Cíl:** ObjectCapture, RoomPlan, a reálné CoreML inference.

### Úkoly

```
3.1  ScanningModeProtocol adapters
     - LiDARScanningModeAdapter (refactor z legacy)
     - ObjectCaptureScanningModeAdapter (refactor)
     - RoomPlanScanningModeAdapter (refactor)
     - UnifiedScanningView s mode picker

3.2  ObjectCaptureService + protokol
     - Apple ObjectCaptureSession wrapper
     - Feedback UI (coverage, angles)

3.3  RoomPlanService + protokol
     - Apple RoomCaptureSession wrapper
     - CapturedRoom → export

3.4  EdgeML Services
     - DepthAnythingModel (refactor - propojit s reálným .mlpackage)
     - MeshCorrectionModel (NOVÝ - reálný CoreML model nebo odstranit)
     - OnDeviceProcessor orchestrator
     - DepthFusionProcessor (refactor)

3.5  MeasurementService + protokol
     - DistanceCalculator (z legacy)
     - AreaCalculator (z legacy)
     - VolumeCalculator (z legacy)
     - InteractiveMeasurementView
```

---

## Sprint 4: Network + Cloud

**Cíl:** Cloud processing, sync, auth.

### Úkoly

```
4.1  NetworkService + NetworkServiceProtocol
     - APIClient (refactor - přidat request interceptor pro auto-logging)
     - WebSocketService (refactor)
     - ChunkedUploader (refactor)
     - Automatický retry s exponential backoff

4.2  CloudProcessingService (NOVÝ - neexistuje v legacy)
     - uploadScan(lrawData:) → scanId
     - startProcessing(scanId:) → taskId
     - pollStatus(taskId:) → ProcessingStatus
     - downloadResult(scanId:format:) → URL

4.3  ScanSyncManager (NOVÝ - neexistuje v legacy)
     - Lokální queue pro offline scany
     - Auto-sync při připojení
     - Conflict resolution

4.4  AuthService (refactor z legacy)
     - Sign in with Apple
     - Session management
     - Token refresh
```

---

## Sprint 5: Polish + Production

**Cíl:** Onboarding, settings, UI polish, TestFlight.

### Úkoly

```
5.1  OnboardingView (NOVÝ - chybí v legacy)
     - LiDAR capability check
     - Permission requests (camera, photo library)
     - Quick tutorial

5.2  SettingsView (refactor)
     - Debug settings panel
     - Export quality settings
     - Account management
     - About + version info

5.3  UI Polish
     - Loading states
     - Error states s recovery actions
     - Haptic feedback
     - Accessibility (VoiceOver labels)

5.4  Testing
     - Unit testy pro všechny ViewModels
     - Unit testy pro všechny Services (mock přes protokoly)
     - UI testy pro critical flows
     - Performance testy (scan duration, memory)

5.5  TestFlight
     - Fastlane pipeline
     - Build + archive
     - Upload to App Store Connect
```

---

## Metriky úspěchu

| Sprint | Metrika | Cíl |
|--------|---------|-----|
| 0 | Clean build | Xcode build bez warnings |
| 1 | E2E scan | LiDAR → LRAW → Backend → GLB (10 min) |
| 2 | Export test | OBJ + GLB + USDZ z jednoho scanu |
| 3 | 3 režimy | LiDAR + ObjectCapture + RoomPlan fungují |
| 4 | Cloud pipeline | Upload → process → download bez manuálních kroků |
| 5 | TestFlight | Funkční build na externím zařízení |

## Odhadovaný scope

| Sprint | Nových souborů | Migrovaných z legacy | Celkem |
|--------|---------------|---------------------|--------|
| 0 | ~12 | ~20 | ~32 |
| 1 | ~8 | ~6 | ~14 |
| 2 | ~8 | ~2 | ~10 |
| 3 | ~10 | ~8 | ~18 |
| 4 | ~8 | ~3 | ~11 |
| 5 | ~6 | ~2 | ~8 |
| **Celkem** | **~52** | **~41** | **~93** |

## Workflow pro každý sprint

```
1. Zkontroluj Doc-version2/ spec
2. Vytvoř protokol v Core/Protocols/
3. Vytvoř error enum v Core/Errors/
4. Implementuj service (conformance to protocol)
5. Zaregistruj v ServiceContainer
6. Implementuj ViewModel
7. Implementuj View
8. Napiš unit testy (mock service přes protokol)
9. Integruj DebugLogger (žádný print())
10. Ověř debug stream (curl backend events)
```
