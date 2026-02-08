# 08 - Coding Conventions (Skutecny stav)

> Dokument popisuje **skutecne pouzivane** konvence v codebase LidarAPP na zaklade auditu 91 Swift souboru.
> Posledni aktualizace: 2026-02-08

---

## 1. Pojmenovaci konvence

### 1.1 Views (`*View.swift`)

Vsechny View soubory dodrzuji sufix `*View.swift`. Celkem 17 View souboru.

| Soubor | Umisteni |
|--------|----------|
| `ScanningView.swift` | Presentation/Scanning/Views/ |
| `UnifiedScanningView.swift` | Presentation/Scanning/Views/ |
| `GalleryView.swift` | Presentation/Gallery/ |
| `ModelDetailView.swift` | Presentation/Gallery/ |
| `ARPlacementView.swift` | Presentation/Gallery/ |
| `AuthView.swift` | Presentation/Auth/Views/ |
| `ProfileView.swift` | Presentation/Auth/Views/ |
| `ExportView.swift` | Presentation/Export/ |
| `SettingsView.swift` | Presentation/Settings/ |
| `MainTabView.swift` | Presentation/Navigation/ |
| `ModelPreviewView.swift` | Presentation/Preview/Views/ |
| `ProcessingProgressView.swift` | Presentation/Processing/ |
| `InteractiveMeasurementView.swift` | Presentation/Measurement/ |
| `ObjectCaptureScanningView.swift` | Presentation/ObjectCapture/ |
| `RoomPlanScanningView.swift` | Presentation/RoomPlan/ |
| `ProfileTabView.swift` | Presentation/Profile/ |
| `MockDataPreviewView.swift` | Core/Mock/ |

**Poznamka:** Views jsou `struct` implementujici `View` protokol. Zadny View nepouziva `class`.

### 1.2 ViewModels (`*ViewModel.swift` vs `*Adapter.swift`)

V codebase existuji **dva vzory** pro ViewModels:

**Klasicke ViewModely (3 soubory):**
- `ScanningViewModel.swift` - hlavni skenovaci logika
- `AuthViewModel.swift` - autentizace
- `PreviewViewModel.swift` - nahled 3D modelu

**Adapter pattern (3 soubory):**
- `LiDARScanningModeAdapter.swift` - obaluje `ScanningViewModel`
- `ObjectCaptureScanningModeAdapter.swift` - obaluje `ObjectCaptureService`
- `RoomPlanScanningModeAdapter.swift` - obaluje `RoomPlanService`

Adaptery implementuji `ScanningModeProtocol` a slouzi jako bridge mezi ruznymu scanning mody a sdilenym `UnifiedScanningView`. Jsou to plnohodnotne ViewModely oznacene `@Observable`, jen pojmenovane jako Adapter kvuli jejich uloze.

### 1.3 Services - Rozmanite suffixy

Pouze **~28% servisnich trid** pouziva suffix `*Service.swift`. Zbytek pouziva nazvy odraze jejich funkcni roli:

**`*Service.swift` (12 souboru):**
| Soubor | Popis |
|--------|-------|
| `AuthService` | Autentizace a session management |
| `MeasurementService` | Orchestrace mereni |
| `ExportService` | Export 3D modelu do ruznych formatu |
| `WebSocketService` | Real-time WebSocket komunikace |
| `KeychainService` | Bezpecne uloziste (actor) |
| `DebugStreamService` | Streamovani debug eventu |
| `ScanProcessingService` | Orchestrace zpracovani skenu |
| `ObjectCaptureService` | Apple ObjectCapture wrapper |
| `RoomPlanService` | Apple RoomPlan wrapper |
| `TextureMappingService` | Mapovani textur na mesh |
| `EdgeMLGeometryService` | On-device ML zpracovani geometrie |
| `AIGeometryGenerationService` | AI generovani geometrie |

**`*Processor.swift` (4 soubory):**
| Soubor | Popis |
|--------|-------|
| `DepthMapProcessor` | Zpracovani hloubkovych map |
| `MeshAnchorProcessor` | Extrakce mesh dat z ARMeshAnchor |
| `DepthFusionProcessor` | Fuze hloubkovych dat z vice zdroju |
| `OnDeviceProcessor` | Orchestrace on-device ML pipeline |

**`*Extractor.swift` (2 soubory):**
| Soubor | Popis |
|--------|-------|
| `PointCloudExtractor` | Extrakce point cloudu z depth/mesh |
| `HighResPointCloudExtractor` | Vysoko-rozlisena extrakce s ML |

**`*Analyzer.swift` (1 soubor):**
| Soubor | Popis |
|--------|-------|
| `CoverageAnalyzer` | Analyza pokryti skenu s detekcí mezer |

**`*Calculator.swift` (3 soubory):**
| Soubor | Popis |
|--------|-------|
| `DistanceCalculator` | Vypocty vzdalenosti v 3D prostoru |
| `AreaCalculator` | Vypocty ploch |
| `VolumeCalculator` | Vypocty objemu |

**`*Model.swift` (2 soubory - ML modely, nikoliv domain entity):**
| Soubor | Popis |
|--------|-------|
| `DepthAnythingModel` | CoreML wrapper pro Depth Anything V2 |
| `MeshCorrectionModel` | CoreML wrapper pro korekci meshe |

**Dalsi nazvy:**
- `APIClient` - REST API klient (actor)
- `ChunkedUploader` - Upload po castech (actor)
- `ChunkManager` - Sprava chunk souboru (actor)
- `FrameSynchronizer` - Synchronizace kamery a hloubky |
- `CameraFrameCapture` - Zachytavani snimku z kamery |
- `ScanStore` - Lokalni uloziste skenu |
- `ARSessionManager` - Sprava AR session |
- Renderery: `PointCloudRenderer`, `LiveMeshRenderer`, `GaussianSplatRenderer`, `CameraController` |

### 1.4 Protokoly - Minimalni pouziti (~5%)

V codebase existuje pouze **1 dedikovan soubor s protokolem**:

```
Presentation/Scanning/Protocols/ScanningModeProtocol.swift
```

Protokol `ScanningModeProtocol` definuje spolecne rozhrani pro vsechny skenovaci mody. Obsahuje asociovane typy pro ViewBuilder a type-erased wrapper `AnyScanningMode`.

Dalsi protokoly (definovane inline v souborech servis):
- `ObjectCaptureServiceProtocol` (v `ObjectCaptureService.swift`)
- `RoomPlanServiceProtocol` (v `RoomPlanService.swift`)

**Codebase nepouziva** rozsirenemu protocol-oriented designu. Misto toho preferuje konkretni tridy s constructor injection.

### 1.5 Domain Entity

Domain entity pouzivaji jednoduche nazvy bez sufixu:
- `ScanModel.swift` - metadata o skenu (struct)
- `ScanSession.swift` - aktivni session se 3D daty (class)
- `PointCloud.swift` - point cloud data (struct)
- `MeshData.swift` - mesh data (struct)
- `User.swift` - uzivatelsky profil (struct)
- `ScanMode.swift` - enum skenovacich modu

---

## 2. Architektura a strukturovani kodu

### 2.1 MVVM vzor

Pouzivana varianta MVVM:
```
View (struct) -> ViewModel (@Observable class) -> Service/Processor/etc.
```

**View** pristupuje k ViewModelu primarne pres:
- `@Bindable private var viewModel` (pro two-way binding, 4 vyskyty)
- Primo predane instance (napr. `let scanStore: ScanStore`)
- `@State private var` pro lokalni UI stav

**ViewModel** drzi stav a zavislosti:
```swift
@MainActor
@Observable
final class ScanningViewModel {
    // State
    var isScanning: Bool = false
    var showError: Bool = false

    // Dependencies (constructor injection)
    private let arSessionManager: ARSessionManager
    private let meshProcessor = MeshAnchorProcessor()
    private let processingService: ScanProcessingService

    init(session: ScanSession = ScanSession(), mode: ScanMode = .exterior) {
        self.arSessionManager = ARSessionManager()
        self.processingService = ScanProcessingService()
    }
}
```

### 2.2 Dependency Injection

**Pouzity vzor: Constructor injection** (nikoliv `@EnvironmentObject`).

`@EnvironmentObject` se v codebase **nepouziva vubec** (0 vyskytu). Misto toho:

- ViewModely dostávají zavislosti pres `init()`
- Views dostavaji data jako parametry (`let scanStore: ScanStore`)
- `@Environment(\.dismiss)` a `@Environment(\.scenePhase)` se pouzivaji pouze pro systemove hodnoty (28 vyskytu)

Priklad typickeho predavani zavislosti:
```swift
// View dostava data jako parametr
struct GalleryView: View {
    let scanStore: ScanStore
    ...
}

// ViewModel dostava service pres init
init(authService: AuthService) {
    self.authService = authService
}
```

### 2.3 Singleton pattern

Nekteré servisy pouzivaji `static let shared` (10 instanci):

| Trida | Duvod |
|-------|-------|
| `DebugLogger.shared` | Centralni logging |
| `DebugStreamService.shared` | Debug streaming |
| `DebugSettings.shared` | Debug nastaveni |
| `PerformanceMonitor.shared` | Monitoring vykonu |
| `PerformanceHistory.shared` | Historie vykonu |
| `MockDataProvider.shared` | Mock data pro simulator |
| `ObjectCaptureService.shared` | Apple ObjectCapture |
| `RoomPlanService.shared` | Apple RoomPlan |
| `CrashReporter.shared` | Reportovani padu |
| `AppDiagnostics.shared` | Diagnostika |
| `SelfSignedCertDelegate.shared` | SSL delegate |

Singletony se pouzivaji pro infrastrukturni a debug servisy. Business-logic servisy (`AuthService`, `ScanProcessingService`) singletony **nepouzivaji**.

---

## 3. State Management

### 3.1 `@Observable` (iOS 17+)

Codebase pouziva vyhradne **`@Observable` makro** z iOS 17 Observation frameworku. Celkem 38 vyskytu ve 29 souborech.

```swift
@MainActor
@Observable
final class ScanningViewModel { ... }
```

**`@ObservableObject` + `@Published` se temer nepouziva** - pouze 9 vyskytu ve 4 souborech (legacy kod v `EdgeMLGeometryService`, `GaussianSplatRenderer`, `ObjectCaptureScanningView`, `RoomPlanScanningView`). Tyto soubory pravdepodobne pouzivaji `@Published` kvuli integraci s Apple frameworky, ktere to vyzaduji.

### 3.2 View state dekoratory

| Dekorator | Pouziti |
|-----------|---------|
| `@State private var` | Lokalni UI stav ve Views (vsude) |
| `@Bindable private var` | Two-way binding s @Observable VM (4 soubory) |
| `@Environment(\.dismiss)` | Dismissovani sheetu/navigation (bezne) |
| `@Environment(\.scenePhase)` | Lifecycle handling (scanning views) |
| `@EnvironmentObject` | **NEPOUZIVA SE** (0 vyskytu) |

---

## 4. Concurrency

### 4.1 async/await

Dominantni concurrency model. Pouziva se ve **20+ souborech** se stovkami vyskytu.

Typicky vzor:
```swift
func login() async {
    isLoading = true
    defer { isLoading = false }

    do {
        try await authService.login(email: email, password: password)
        isSuccess = true
    } catch let error as AuthError {
        errorMessage = error.localizedDescription
    }
}
```

### 4.2 `@MainActor`

Masivni pouziti - **88 vyskytu ve 39 souborech**. Temer vsechny ViewModely a servisy s UI statem jsou oznaceny `@MainActor`.

Typicky vzor pro callback z non-main threadu:
```swift
arSessionManager.onMeshUpdate = { [weak self] meshAnchor in
    Task { @MainActor in
        self?.handleMeshUpdate(meshAnchor)
    }
}
```

### 4.3 Swift Actors

**9 trid** je definovano jako `actor` pro thread-safe pristup:

| Actor | Ucel |
|-------|------|
| `APIClient` | REST API volani |
| `ChunkedUploader` | Upload po castech |
| `ChunkManager` | Sprava chunk souboru |
| `ExportService` | Export operace |
| `KeychainService` | Pristup ke Keychain |
| `RawDataUploader` | Upload raw dat |
| `ScanSessionPersistence` | Persistence session |
| `DepthFrameBuffer` | Buffer pro depth frames |
| `TextureFrameBuffer` | Buffer pro texture frames |

Actors se pouzivaji predevsim pro I/O operace (sit, disk, keychain) a data buffery.

### 4.4 `Sendable`

**68 vyskytu ve 25 souborech.** Pouziva se pro:
- Domain entity structs (`PointCloud`, `MeshData`, `User`)
- Configuration structs
- Nested types v actors
- Utility tridy oznacene `final class: Sendable` (napr. `DistanceCalculator`, `PointCloudExtractor`)

### 4.5 `nonisolated(unsafe)`

**29 vyskytu v 7 souborech.** Pouziva se pro:
- WebSocket properties v `WebSocketService` (protoze URLSessionDelegate je nonisolated)
- Staticke property s lazy inicializaci (napr. `sharedCIContext` v `ScanningViewModel`)
- Delegate metody v `ARSessionManager`, `RoomPlanService`

### 4.6 Combine

Combine se pouziva **omezeně** - pouze v souborech, ktere to vyzaduje architektura:
- `AnyPublisher` / `CurrentValueSubject` / `PassthroughSubject` se vyskytuje pouze ve **2 souborech** (`ObjectCaptureService`, `RoomPlanService`)
- Importuje se v dalsich souborech, ale primarne pro `import Combine` bez realneho pouziti Publishers

Combine je nahrazen `@Observable` + async/await pro vetsinu reactive patternu.

### 4.7 `Task` pattern

Pro asynchronni operace z synchronniho kontextu se bezne pouziva:
```swift
Task {
    await saveCurrentProgress()
}

// S cancellation:
private var autoSaveTask: Task<Void, Never>?

autoSaveTask = Task {
    while !Task.isCancelled && isScanning {
        try? await Task.sleep(for: .seconds(autoSaveInterval))
        await saveCurrentProgress()
    }
}
```

---

## 5. Error Handling

### 5.1 Servisne-specificke error enumy

Codebase **nepouziva** jednotny `LiDARError`. Misto toho kazdy service/modul definuje vlastni error enum:

| Error enum | Definovan v |
|------------|-------------|
| `AuthError` | `AuthService.swift` |
| `ProcessingError` | `ScanProcessingService.swift` |
| `WebSocketError` | `WebSocketService.swift` |
| `DepthAnythingError` | `DepthAnythingModel.swift` |

Vsechny implementuji `LocalizedError` s property `errorDescription`:
```swift
enum AuthError: LocalizedError {
    case invalidCredentials
    case emailAlreadyExists
    case networkError(Error)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        ...
        }
    }
}
```

### 5.2 Error handling vzor

Typicky pattern ve ViewModelech:
```swift
do {
    try await authService.login(email: email, password: password)
} catch let error as AuthError {
    errorMessage = error.localizedDescription
} catch {
    errorMessage = "An unexpected error occurred"
}
```

Pro non-critical errory se pouziva tichy catch:
```swift
} catch {
    print("Auto-save failed: \(error.localizedDescription)")
}
```

### 5.3 UI zobrazeni chyb

Views pouzivaji `.alert()` modifier s bindingem na ViewModel stav:
```swift
.alert("Scanning Error", isPresented: $viewModel.showError) {
    Button("OK") { viewModel.dismissError() }
} message: {
    Text(viewModel.errorMessage ?? "Unknown error")
}
```

---

## 6. Loggovani

### 6.1 Tri urovne loggovani (nekonzistentni)

Codebase pouziva **tri ruzne logovaci metody** soucasne:

**1. `print()` - nejcastejsi (56 vyskytu ve 14 souborech)**
```swift
print("RawDataUploader: Upload completed!")
print("Auto-save failed: \(error.localizedDescription)")
print("[Debug] ScanningViewModel cleanup called")
```

**2. `DebugLogger` / globalni funkce `debugLog()` (6 souboru)**
```swift
debugLog("Debug stream started", category: .logCategoryNetwork)
DebugLogger.shared.error("Something failed", category: .logCategoryAR)
```
`DebugLogger` pouziva interně `os.log` + `print()` + buffer v pameti + forwarding do `DebugStreamService`.

**3. `DebugStreamService` tracking metody (rozsirene pouziti)**
```swift
DebugStreamService.shared.trackError("Failed to resume session: \(error)", screen: "Scanning")
DebugStreamService.shared.trackViewAppeared("ScanningView", details: ["mode": mode.rawValue])
```

**4. OSLog primo (1 soubor)**
Pouze `DebugLogger.swift` pouziva `os.log` primo - a to jako backend pro `DebugLogger` tridu.

**Zaver:** Loggovani neni konzistentni. `print()` dominuje pro rychle debug logy. `DebugLogger`/`debugLog()` se pouziva v novejsim kodu. `DebugStreamService` se pouziva pro strukturovane eventy posílané na backend.

---

## 7. Strukturovani souboru

### 7.1 MARK sekce

`// MARK: -` se pouziva **masivne** - 725 vyskytu v 85 souborech. Prakticky kazdy soubor je organizovan pomoci MARK.

Typicka struktura:
```swift
// MARK: - Configuration
// MARK: - Published State
// MARK: - Dependencies
// MARK: - Initialization
// MARK: - Public Methods
// MARK: - Private Methods
// MARK: - Error Handling
```

### 7.2 Modifikatory pristupu

- `final class` - pouziva se na vsech konkretních tridach (ViewModely, Services, Analyzery)
- `private` a `private(set)` - bezne pouzivane pro encapsulaci
- `internal` (default) - implicitni, explicitne se nepise
- `public` - nepouziva se (single-module aplikace)

### 7.3 Dokumentacni komentare

Soubory pouzivaji `///` doc komentare pred tridami a klicovymi metodami:
```swift
/// ViewModel for the scanning interface
@MainActor
@Observable
final class ScanningViewModel { ... }

/// Calculate Euclidean distance between two points
func pointToPointDistance(from p1: simd_float3, to p2: simd_float3) -> Float { ... }
```

### 7.4 Nested types

Bezne pouzivane pro Configuration, Error enumy a helper typy:
```swift
final class CoverageAnalyzer {
    struct Configuration { ... }
    struct CoverageCell { ... }
    enum QualityLevel { ... }
    struct Gap { ... }
    struct CoverageStatistics { ... }
}
```

### 7.5 Extensions

Extensions se pouzivaji pro:
- Conformance k protokolum (napr. `extension WebSocketService: URLSessionWebSocketDelegate`)
- Organizaci kodu v ramci souboru (s MARK)
- Pridani helper metod (`extension JSONDecoder`, `extension [ScanModel]`)

### 7.6 #Preview

SwiftUI `#Preview` makro se pouziva ve **20 souborech** (vsechny View soubory).

---

## 8. UI konvence

### 8.1 SwiftUI moderni pristup

- `.foregroundStyle()` misto `.foregroundColor()` (bezne)
- `.clipShape()` s konkretnim shape (napr. `Capsule()`, `RoundedRectangle(cornerRadius: 12)`)
- `.background(.ultraThinMaterial, in: Shape())` pro glassmorphism efekty
- `NavigationStack` misto `NavigationView`
- `.navigationDestination(item:)` pro navigaci

### 8.2 UIKit bridging

`UIViewRepresentable` se pouziva pro:
- `ARViewContainer` - ARKit ARView integrace do SwiftUI
- Dalsi specializovane views vyzadujici UIKit

### 8.3 Lokalizace

Codebase pouziva **primo cesky text** v UI bez NSLocalizedString:
```swift
Text("Moje 3D modely")
Text("Skenujte pomalu a systematicky")
Label("Mrizka", systemImage: "square.grid.2x2")
```

Nektere error messages a technicky text zustava v anglictine:
```swift
return "Invalid email or password"
return "An unexpected error occurred"
```

### 8.4 Accessibility

Pouziva se castecne:
- `.accessibilityLabel()` na interaktivnich prvcich (hlavne tlacitka)
- `.accessibilityIdentifier()` pro UI testy (`AccessibilityIdentifiers` struct)
- `.accessibilityHint()` pro slozitejsi interakce

---

## 9. Configuration patterns

### 9.1 Nested Configuration struct

Bezny vzor pro konfigurovatelne komponenty:
```swift
final class CoverageAnalyzer {
    struct Configuration {
        var gridResolution: Float = 0.1
        var minimumViewsForGood: Int = 3
        static let `default` = Configuration()
    }

    private let configuration: Configuration

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }
}
```

### 9.2 #if DEBUG

Pouziva se pro:
- Debug overlay UI (DebugLogOverlay)
- Debug stream tracking volani
- Ruzne API URL (Tailscale vs produkce)

```swift
#if DEBUG
DebugStreamService.shared.trackViewAppeared("ScanningView")
#endif
```

---

## 10. Souhrnna statistika codebase

| Metrika | Hodnota |
|---------|---------|
| Celkem Swift souboru | 91 |
| View soubory | 17 |
| ViewModel soubory | 3 + 3 adaptery |
| Service soubory | 12 |
| Actor tridy | 9 |
| `@Observable` tridy | 29 |
| `@ObservableObject` (legacy) | 4 soubory |
| `@MainActor` oznaceni | 88 vyskytu / 39 souboru |
| `// MARK: -` sekce | 725 |
| `#Preview` makra | 20 souboru |
| `Sendable` typy | 68 vyskytu / 25 souboru |
| Protokoly (dedicovane soubory) | 1 |
| `@EnvironmentObject` | 0 |
| `@Bindable` | 4 soubory |
| `print()` logy | 56 vyskytu / 14 souboru |
| `DebugLogger` pouziti | 6 souboru |
| Singleton pattern | 10 instanci |

---

## 11. Klicove odlisnosti od stare dokumentace (CLAUDE.md)

| Tema | CLAUDE.md tvrdi | Skutecnost |
|------|-----------------|------------|
| **Services naming** | `*Service.swift` | Pouze ~28%. Tez `*Processor`, `*Extractor`, `*Analyzer`, `*Calculator`, `*Model` |
| **Protocols** | Protocol-oriented design | Minimalni (~5%). Jen 1 dedicovany protokol soubor |
| **DI** | `@EnvironmentObject` | Constructor injection. 0 vyskytu `@EnvironmentObject` |
| **State** | `@Published` / `@ObservableObject` | `@Observable` (iOS 17+). Legacy `@Published` jen ve 4 souborech |
| **Logging** | OSLog | Mix `print()` (dominantni), `DebugLogger`, `DebugStreamService`. OSLog jen v DebugLogger backendu |
| **Errors** | Jednotny `LiDARError` | Servisne-specificke enumy (`AuthError`, `ProcessingError`, atd.) |
| **Combine** | Hlavni reactive framework | Omezene (2 soubory s Publishers). Nahrazeno `@Observable` + async/await |
| **Protocols naming** | `*Protocol.swift` nebo `*able` | Jediny `ScanningModeProtocol.swift`. Ostatni inline |
