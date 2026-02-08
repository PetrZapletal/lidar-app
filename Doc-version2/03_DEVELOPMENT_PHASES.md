# Vyvojove faze - Opraveny stav (Audit 2026-02-08)

## Prehled

Tento dokument opravuje `docs/DEVELOPMENT_PHASES.md`, ktery obsahoval vyrazne nadhodnoceny postup.
Pro kazdou fazi je uvedeno: co dokumentace tvrdi, co skutecne existuje v kodu,
co je realna implementace vs. stub/placeholder, a realisticky odhad dokonceni.

---

## Faze 1: Core LiDAR Infrastructure

### Dokumentovano: 85% hotovo
### Skutecny stav: ~55%

### Co dokumentace tvrdi vs. co existuje

| Dokumentovano | Skutecny stav |
|--------------|---------------|
| `LiDARService.swift` - Session management | **NEEXISTUJE.** Jmenuje se `ARSessionManager.swift` |
| `LiDARSessionManager.swift` - State machine | **NEEXISTUJE** jako samostatny soubor. Stavovy automat je primo v `ARSessionManager` |
| `PointCloudProcessor.swift` - Raw data processing | **NEEXISTUJE.** Jmenuje se `PointCloudExtractor.swift` |
| `PointCloud.swift` - Data model | **EXISTUJE** a je funkcni |
| `MeshGenerator.swift` - Real-time mesh | **NEEXISTUJE.** Jmenuje se `MeshAnchorProcessor.swift` |
| `MeshOptimizer.swift` - Mesh cleanup | **NEEXISTUJE** vubec |

### Soubory, ktere skutecne implementuji Fazi 1

| Soubor | Cesta | Stav |
|--------|-------|------|
| `ARSessionManager.swift` | `Services/ARKit/ARSessionManager.swift` | **REALNA implementace** (~530 radku). Kompletni ARSession lifecycle (start, pause, resume, stop), konfigurace scan modu (exterior/interior/object), ARSessionDelegate, world map persistence, high-res capture. Toto je hlavni soubor cele faze. |
| `PointCloudExtractor.swift` | `Services/ARKit/PointCloudExtractor.swift` | **REALNA implementace** (~395 radku). Extrakce z depth map i mesh anchors, confidence filtering, voxel downsampling, depth statistiky, barevna extrakce z kameroveho obrazu. Funkcni. |
| `MeshAnchorProcessor.swift` | `Services/ARKit/MeshAnchorProcessor.swift` | **REALNA implementace** (~258 radku). Extrakce vertexu, normal, facu a klasifikaci z ARMeshAnchor. Batch processing, kombinace meshu. Funkcni. |
| `DepthMapProcessor.swift` | `Services/ARKit/DepthMapProcessor.swift` | Existuje, ale nebyl podrobne auditovan. |
| `CoverageAnalyzer.swift` | `Services/ARKit/CoverageAnalyzer.swift` | Existuje, pouzivan v ScanningViewModel pro analyzu pokryti skenovaneho prostoru. |
| `PointCloud.swift` | `Domain/Entities/PointCloud.swift` | **REALNA implementace**. Data model s body, barvami, normalami, konfidenci. |
| `MeshData.swift` | `Domain/Entities/MeshData.swift` | **REALNA implementace**. Vertexy, normaly, face, klasifikace, transformace, bounding box, surface area. |

### Co je realne vs. co chybi

**Funkcni (realne implementace):**
- ARSession lifecycle (start, pause, resume, stop) - plne funkcni
- Konfigurace pro ruzne scan mody (exterior s GPS/heading, interior)
- Extrakce point cloudu z depth map i mesh anchors
- Confidence filtering a voxel downsampling
- Zpracovani ARMeshAnchor (vertexy, normaly, face, klasifikace)
- World map persistence (save/load pro resume session)
- High-resolution frame capture
- Error handling a recovery (fallback z gravityAndHeading na gravity)

**Chybi / Neimplementovano:**
- `MeshOptimizer` (hole filling, decimation, smoothing) - zcela chybi
- Memory management pod 500MB neni prokazany - neni mereni
- Performance monitoring behem skenovani je zakladni (framove pocitadlo)
- Neni zadny realni test, ze point cloud dosahuje 30+ FPS

### Realisticky odhad: **55%**

### Co je treba udelat dal
1. Implementovat `MeshOptimizer.swift` (hole filling, decimation, smoothing)
2. Pridat mereni pameti behem skenovani a progressive loading
3. Profilovat FPS extrakce point cloudu
4. Pridat unit testy pro ARSessionManager a PointCloudExtractor

---

## Faze 2: Camera & Texture Pipeline

### Dokumentovano: 60% hotovo
### Skutecny stav: ~40%

### Co dokumentace tvrdi vs. co existuje

| Dokumentovano | Skutecny stav |
|--------------|---------------|
| `CameraService.swift` - Frame capture | **NEEXISTUJE.** Jmenuje se `CameraFrameCapture.swift` |
| `FrameSynchronizer.swift` - LiDAR/Camera sync | **EXISTUJE** |
| `TextureMapper.swift` - UV mapping | **NEEXISTUJE** pod timto jmenem. Existuje `TextureMappingService.swift` |
| `TextureOptimizer.swift` - Quality enhancement | **NEEXISTUJE** vubec |

### Soubory, ktere skutecne implementuji Fazi 2

| Soubor | Cesta | Stav |
|--------|-------|------|
| `CameraFrameCapture.swift` | `Services/Camera/CameraFrameCapture.swift` | Existuje. Zakladni frame capture. |
| `FrameSynchronizer.swift` | `Services/Camera/FrameSynchronizer.swift` | Existuje. Synchronizace LiDAR/Camera framu. |
| `TextureMappingService.swift` | `Services/Rendering/TextureMappingService.swift` | **CASTECNA implementace** (~430 radku). UV generovani (multi-view projection, box, spherical, planar), texture atlas z kamerovych framu, odhad materialu. Ale: `calculateImageVariance()` vraci hardcoded `25.0`, material estimation je velmi zjednodusena. |
| `ScanningViewModel.swift` | Scanning ViewModels | Texture frame capture je implementovano primo v `ScanningViewModel.captureTextureFrame()` - kazdy 10. frame se ulozi jako JPEG. |

### Co je realne vs. co chybi

**Funkcni:**
- Zakladni frame capture integrovany do ScanningViewModel
- FrameSynchronizer pro casovou synchronizaci
- Multi-view UV projekce v TextureMappingService - matematicky korektni
- Texture atlas generovani (grid layout z vicerozkladovych framu)
- Box/spherical/planar UV projekce

**Castecne / Stub:**
- Material estimation: `calculateImageVariance()` vraci konstantu `25.0`
- Texture atlas je naivni grid layout bez optimalizace
- HDR capture support chybi

**Chybi:**
- `TextureOptimizer.swift` (deblurring, color correction) - neexistuje
- Texture resolution >= 2048x2048 neni zarucena
- Seamless texture atlas (bez viditelnych svu) - nereseno
- Real-time texture preview

### Realisticky odhad: **40%**

### Co je treba udelat dal
1. Implementovat `TextureOptimizer.swift` (deblurring, color correction, white balance)
2. Vylepsit texture atlas - pouzit proper UV unwrapping misto naivniho gridu
3. Implementovat realni material estimation (ne hardcoded variance)
4. HDR capture support
5. Seam blending v texture atlasu

---

## Faze 3: UI Layer

### Dokumentovano: 75% hotovo
### Skutecny stav: ~80%

### Co dokumentace tvrdi vs. co existuje

| Dokumentovano | Skutecny stav |
|--------------|---------------|
| `ScanningView.swift` | **EXISTUJE** a je rozsahla |
| `ScanningViewModel.swift` | **EXISTUJE** (~860 radku, velmi robustni) |
| `ModelPreviewView.swift` | **EXISTUJE** s SceneKit/RealityKit |
| `ARQuickLookView.swift` | **NEEXISTUJE** pod timto jmenem, ale existuje `ARPlacementView.swift` |
| `MeasurementView.swift` | **EXISTUJE** jako `InteractiveMeasurementView.swift` |
| `MeasurementService.swift` | **EXISTUJE** a je kompletni |

### Soubory, ktere skutecne implementuji Fazi 3

| Soubor | Cesta | Stav |
|--------|-------|------|
| **Scanning UI** | | |
| `ScanningView.swift` | `Presentation/Scanning/Views/ScanningView.swift` | **REALNA implementace**. AR preview, coverage overlay, guidance indicators, debug overlay, scan controls. |
| `UnifiedScanningView.swift` | `Presentation/Scanning/Views/UnifiedScanningView.swift` | Alternativni scanning view. |
| `ScanningViewModel.swift` | `Presentation/Scanning/ViewModels/ScanningViewModel.swift` | **REALNA implementace** (~860 radku). Kompletni scan state management, mock mode, depth fusion, auto-save, session persistence, raw data upload, memory monitoring. |
| `CoverageOverlay.swift` | `Presentation/Scanning/Views/CoverageOverlay.swift` | Coverage vizualizace. |
| `GuidanceIndicator.swift` | `Presentation/Scanning/Views/GuidanceIndicator.swift` | Navadeni uzivatele. |
| `DebugLogOverlay.swift` | `Presentation/Scanning/Views/DebugLogOverlay.swift` | Debug informace. |
| `ResumeSessionSheet.swift` | `Presentation/Scanning/Views/ResumeSessionSheet.swift` | Obnoveni session. |
| `SharedControlBar.swift` | `Presentation/Scanning/Views/Shared/SharedControlBar.swift` | Sdileny control bar. |
| `SharedTopBar.swift` | `Presentation/Scanning/Views/Shared/SharedTopBar.swift` | Sdileny top bar. |
| `StatisticsGrid.swift` | `Presentation/Scanning/Views/Shared/StatisticsGrid.swift` | Statistiky skenu. |
| `StatusIndicator.swift` | `Presentation/Scanning/Views/Shared/StatusIndicator.swift` | Stavovy indikator. |
| `CaptureButton.swift` | `Presentation/Scanning/Views/Shared/CaptureButton.swift` | Capture tlacitko. |
| **Preview UI** | | |
| `ModelPreviewView.swift` | `Presentation/Preview/Views/ModelPreviewView.swift` | **REALNA implementace**. SceneKit/RealityKit 3D viewer, session preview. |
| `Enhanced3DViewer.swift` | `Presentation/Preview/Views/Enhanced3DViewer.swift` | Vylepseny 3D viewer. |
| `PreviewViewModel.swift` | `Presentation/Preview/ViewModels/PreviewViewModel.swift` | ViewModel pro preview. |
| **Measurement UI** | | |
| `InteractiveMeasurementView.swift` | `Presentation/Measurement/InteractiveMeasurementView.swift` | **EXISTUJE**. |
| `MeasurementService.swift` | `Services/Measurement/MeasurementService.swift` | **REALNA implementace** (~460 radku). Distance, area, volume, angle mereni. Unit conversion (metric/imperial). Raycast to mesh. Export measurements. |
| `DistanceCalculator.swift` | `Services/Measurement/DistanceCalculator.swift` | Kalkulace vzdalenosti. |
| `AreaCalculator.swift` | `Services/Measurement/AreaCalculator.swift` | Kalkulace plochy. |
| `VolumeCalculator.swift` | `Services/Measurement/VolumeCalculator.swift` | Kalkulace objemu. |
| **Navigace & Ostatni** | | |
| `MainTabView.swift` | `Presentation/Navigation/MainTabView.swift` | Hlavni tab navigace. |
| `GalleryView.swift` | `Presentation/Gallery/GalleryView.swift` | Galerie skenu. |
| `ModelDetailView.swift` | `Presentation/Gallery/ModelDetailView.swift` | Detail modelu. |
| `GalleryExportSheet.swift` | `Presentation/Gallery/GalleryExportSheet.swift` | Export z galerie. |
| `ARPlacementView.swift` | `Presentation/Gallery/ARPlacementView.swift` | AR umisteni modelu (nahrada za `ARQuickLookView`). |
| `SettingsView.swift` | `Presentation/Settings/SettingsView.swift` | Nastaveni. |
| `AuthView.swift` | `Presentation/Auth/Views/AuthView.swift` | Prihlaseni. |
| `ProfileView.swift` | `Presentation/Auth/Views/ProfileView.swift` | Profil. |
| `ProcessingProgressView.swift` | `Presentation/Processing/ProcessingProgressView.swift` | Progress zpracovani. |
| `ObjectCaptureScanningView.swift` | `Presentation/ObjectCapture/ObjectCaptureScanningView.swift` | Object capture. |
| `RoomPlanScanningView.swift` | `Presentation/RoomPlan/RoomPlanScanningView.swift` | RoomPlan skenovani. |

### Co je realne vs. co chybi

**Funkcni (realne implementace):**
- Kompletni scanning UI s coverage overlay, guidance, debug overlay
- ScanningViewModel je nejrobustnejsi soubor v projektu (860 radku) - mock mode, auto-save, memory monitoring, scene phase handling
- 3D preview s SceneKit/RealityKit
- Measurement UI s distance/area/volume/angle
- Gallery, settings, auth, profile views
- AR placement view
- RoomPlan a ObjectCapture scanning views
- Tab navigace

**Castecne:**
- Lighting controls v preview - neni jasne, zda implementovano
- Scale adjustment v AR placement - zakladni

**Chybi:**
- Pokrocile lighting controls v ModelPreviewView

### Realisticky odhad: **80%**

Tato faze je ve skutecnosti LEPSI nez dokumentace uvadi (75%). UI vrstva je pomerne kompletni s rozsahlym systemem views, sdilenych komponent, a coverage vizualizaci. ScanningViewModel je mimoradne robustni.

### Co je treba udelat dal
1. Pridat lighting controls do ModelPreviewView
2. Vylepsit AR placement (scale adjustment, surface detection feedback)
3. Pridat onboarding flow pro nove uzivatele

---

## Faze 4: Export Pipeline

### Dokumentovano: 70% hotovo
### Skutecny stav: ~35%

### Co dokumentace tvrdi vs. co existuje

| Dokumentovano | Skutecny stav |
|--------------|---------------|
| `USDZExporter.swift` - [x] hotovo | **FAKE.** USDZ export pouze prejmenuje OBJ soubor (viz nize) |
| `GLTFExporter.swift` - [x] hotovo | **NEKOMPLETNI.** Zapise jen JSON bez binary bufferu |
| `OBJExporter.swift` - [x] hotovo | **FUNKCNI.** Realna implementace |
| `STLExporter.swift` - [x] hotovo | **FUNKCNI.** Realna implementace |
| `PLYExporter.swift` - [x] hotovo | **FUNKCNI.** Realna implementace |
| `ExportManager.swift` - [x] hotovo | **NEEXISTUJE.** Je to `ExportService.swift` |
| `ExportView.swift` - [ ] neni | **EXISTUJE** v `Presentation/Export/ExportView.swift` |

### Soubory, ktere skutecne implementuji Fazi 4

| Soubor | Cesta | Stav |
|--------|-------|------|
| `ExportService.swift` | `Presentation/Export/ExportService.swift` | **CASTECNA implementace** (~465 radku). Viz detailni analyza nize. |
| `ExportView.swift` | `Presentation/Export/ExportView.swift` | **EXISTUJE**. UI pro vyber formatu a export. |

### Detailni analyza ExportService

**OBJ export** (`exportToOBJ`): **FUNKCNI**
- Spravne zapisuje vertexy, normaly, face
- Podpora Y-up/Z-up coordinate system
- Spravny format `f v//vn`

**PLY export** (`exportToPLY`): **FUNKCNI**
- ASCII format s vertexy, normalami, face
- Spravny PLY header

**STL export** (`exportToSTL`): **FUNKCNI**
- ASCII STL format
- Korektni face normaly pres cross product

**glTF export** (`exportToGLTF`): **NEKOMPLETNI - NEFUNKCNI**
- Zapise pouze JSON metadata (accessors, bufferViews, meshes)
- **CHYBI binary buffer (.bin)** - glTF bez bufferu je nevalidni
- Soubor nebude otevritelny v zadnem 3D softwaru
- Radek 316: `let data = try JSONSerialization.data(withJSONObject: gltf)` - zapise jen JSON

**USDZ export** (`exportToUSDZ`): **FAKE IMPLEMENTACE**
- Radek 327-338: Exportuje jako OBJ a pak OBJ **PREJMENUJE** na .usdz
- Komentar v kodu: `// For now, export as OBJ and note that USDZ requires conversion`
- `try fileManager.moveItem(at: objURL, to: url)` - doslova moveItem z .obj na .usdz
- Vysledny soubor neni validni USDZ (je to OBJ s jinou priponou)
- V produkci by mel pouzit `MDLAsset` pro konverzi

**Point cloud export**: **FUNKCNI**
- PLY export s RGB barvami
- OBJ export (pouze body bez face)

**Measurement export**: **FUNKCNI**
- JSON a CSV export mereni

### Realisticky odhad: **35%**

Z 5 deklarovanych formatu jsou realne funkcni pouze 3 (OBJ, PLY, STL). glTF je nefunkcni a USDZ je fake. Pritom USDZ je nejdulezitejsi format pro iOS ekosystem (AR Quick Look).

### Co je treba udelat dal
1. **KRITICKE:** Implementovat realni USDZ export pres `MDLAsset` (ModelIO framework)
2. **KRITICKE:** Dokoncit glTF export - pridat binary buffer (.bin nebo embedded base64)
3. Pridat progress tracking do exportu
4. Otestovat, ze OBJ/PLY/STL soubory se skutecne daji otevrit v MeshLab, Blender, atd.
5. Pridat binary PLY format (misto ASCII) pro vetsi soubory
6. Optimalizovat export pro velke meshe (streaming write misto string concatenation)

---

## Faze 5: Cloud Integration

### Dokumentovano: 80% hotovo
### Skutecny stav: ~25%

### Co dokumentace tvrdi vs. co existuje

| Dokumentovano | Skutecny stav |
|--------------|---------------|
| `CloudUploadService.swift` - [x] hotovo | **NEEXISTUJE.** Toto jmeno nikde v kodu neni |
| `ScanSyncManager.swift` - [x] offline queue | **NEEXISTUJE.** Toto jmeno nikde v kodu neni |
| `CloudProcessingService.swift` - [x] AI pipeline | **NEEXISTUJE.** Toto jmeno nikde v kodu neni |
| `WebSocketService.swift` - [x] real-time updates | **EXISTUJE** a je funkcni |

### Soubory, ktere skutecne implementuji Fazi 5

| Soubor | Cesta | Stav |
|--------|-------|------|
| `APIClient.swift` | `Services/Network/APIClient.swift` | **REALNA implementace** (~445 radku). REST API klient s retry logiku, auth tokens, CRUD pro skeny, processing status. Kompletni endpoint definice. Ale: nikde neni pouzit v hlavnim flow - `ScanProcessingService` ma vlastni upload logiku. |
| `ChunkedUploader.swift` | `Services/Network/ChunkedUploader.swift` | **REALNA implementace** (~530 radku). Chunked upload s resume, pause, cancel. Progress tracking. Ale: `prepareScanData` konci s `// TODO: Create ZIP archive of all files`. |
| `WebSocketService.swift` | `Services/Network/WebSocketService.swift` | **REALNA implementace** (~445 radku). WebSocket s reconnect, ping/pong, subscription management, processing updates. Kompletni. |
| `RawDataUploader.swift` | `Services/Debug/RawDataUploader.swift` | Debug upload raw dat na backend. |
| `DebugStreamService.swift` | `Services/Debug/DebugStreamService.swift` | Debug WebSocket streaming. |

### Co je realne vs. co chybi

**Funkcni:**
- `APIClient` - kompletni REST klient s retry, auth, error handling
- `ChunkedUploader` - chunked upload s resume capability
- `WebSocketService` - real-time updates s reconnect

**KRITICKE co chybi:**
- **`CloudUploadService`** - neexistuje. Upload je rozdeleny mezi APIClient, ChunkedUploader, a ScanProcessingService, ale chybi orchestracni vrstva
- **`ScanSyncManager`** - neexistuje. Zadna offline queue, zadna sync logika
- **`CloudProcessingService`** - neexistuje. ScanProcessingService ma metody `uploadToBackend()` a `startServerProcessing()`, ale ty jsou pravdepodobne stuby (odkazuji na APIClient, ktery neni nikde propojen s realnim backendem v hlavnim flow)
- Offline queue neexistuje
- Conflict resolution neexistuje
- Upload resume po network interruption neni otestovany

**Problemy:**
- `ChunkedUploader.prepareScanData()` ma TODO: `// TODO: Create ZIP archive of all files` - data se nepripravuji spravne
- Backend URL je `https://100.96.188.18:8444` (Tailscale) - funguje jen pro development
- Produkci URL `https://api.lidarapp.com` pravdepodobne neexistuje
- Self-signed certificate handling je v debug rezimu - v produkci by nefungovalo
- Neni integrace s realnim backendem - vsechno je pripraveno, ale nic neni propojeno end-to-end

### Realisticky odhad: **25%**

Dokumentace tvrdila 80%, ale 3 ze 4 hlavnich souboru vubec neexistuji. Co existuje (APIClient, ChunkedUploader, WebSocketService) jsou solidni implementace, ale chybi orchestracni vrstva a neni zadna end-to-end integrace. Upload flow konci s TODO komentari.

### Co je treba udelat dal
1. **KRITICKE:** Vytvorit `CloudUploadService` jako orchestracni vrstvu nad APIClient a ChunkedUploader
2. **KRITICKE:** Vytvorit `ScanSyncManager` s offline queue (Core Data nebo Realm)
3. Implementovat `prepareScanData()` - ZIP archiv misto TODO
4. Propojit end-to-end: scan -> upload -> processing -> download
5. Otestovat s realnim backendem
6. Pridat retry logiku pro cely upload flow (ne jen jednotlive chunky)
7. Implementovat conflict resolution pro sync

---

## Faze 6: EdgeML Integration

### Dokumentovano: 20% hotovo
### Skutecny stav: ~45%

### Co dokumentace tvrdi vs. co existuje

| Dokumentovano | Skutecny stav |
|--------------|---------------|
| `DepthAnythingService.swift` - [x] CoreML integration | Jmenuje se `DepthAnythingModel.swift`. Existuje, ale model neni v bundle. |
| `EdgeMeshProcessor.swift` - [ ] neni | Existuje jako `OnDeviceProcessor.swift` + `MeshCorrectionModel.swift` |

### Soubory, ktere skutecne implementuji Fazi 6

| Soubor | Cesta | Stav |
|--------|-------|------|
| `DepthAnythingModel.swift` | `Services/EdgeML/DepthAnythingModel.swift` | **CASTECNA implementace**. CoreML wrapper pro Depth Anything V2. Load model logika existuje, ale `.mlmodelc` soubor neni v bundle. Fallback na error `modelNotFound`. Bez modelu je nepouzitelne. |
| `DepthFusionProcessor.swift` | `Services/EdgeML/DepthFusionProcessor.swift` | **REALNA implementace** (~rozsahla). Fuse LiDAR depth s AI-enhanced depth. Konfigurace resolution multiplier, edge-aware blending. Ale: zavisla na `DepthAnythingModel` ktery nema model. |
| `MeshCorrectionModel.swift` | `Services/EdgeML/MeshCorrectionModel.swift` | **ALGORITMICKA implementace** (~363 radku). Statistical outlier removal, Laplacian smoothing, normal re-estimation, confidence computation. Pouziva algoritmicke metody misto ML modelu (komentar: `// For MVP: Use algorithmic corrections instead of ML model`). Funkcni bez CoreML modelu. |
| `OnDeviceProcessor.swift` | `Services/EdgeML/OnDeviceProcessor.swift` | **REALNA implementace**. Orchestracni pipeline: noise removal, hole filling, smoothing, topology optimization, normal computation. Processing states, statistics, quality levels. |
| `EdgeMLGeometryService.swift` | `Services/EdgeML/EdgeMLGeometryService.swift` | **ROZSAHLA implementace** (~836 radku). Depth enhancement (bilateral filter, edge detection, hole filling), semantic segmentation (Vision framework), RANSAC plane detection, box detection, mesh generation z depth, TSDF volume. Ale: `TSDFVolume.integrate()` a `extractMesh()` jsou prazdne stuby. Segmentace pouziva VNClassifyImageRequest (ne spatialnou segmentaci). |
| `HighResPointCloudExtractor.swift` | `Services/EdgeML/HighResPointCloudExtractor.swift` | **REALNA implementace** (~496 radku). High-res point cloud extrakce z fused depth. Voxel downsampling, normal estimation, batch processing, color sampling. Funkcni. |

### Co je realne vs. co chybi

**Funkcni (realne implementace):**
- `MeshCorrectionModel` - algoritmicke mesh corrections (outlier removal, smoothing, normals) - funkcni bez ML modelu
- `OnDeviceProcessor` - kompletni pipeline orchestrace
- `HighResPointCloudExtractor` - high-res point cloud extrakce
- `EdgeMLGeometryService` - bilateral filter, edge detection, hole filling, RANSAC plane detection

**Castecne (stuby v jinak realnem kodu):**
- `DepthAnythingModel` - wrapper existuje, ale CoreML model chybi v bundle
- `DepthFusionProcessor` - logika existuje, ale bez DepthAnything modelu nefunguje
- `EdgeMLGeometryService.TSDFVolume` - `integrate()` je prazdny stub, `extractMesh()` vraci prazdny mesh
- Segmentace je globalni (VNClassifyImageRequest) misto prostorove

**Chybi:**
- Skutecne ML modely (DepthAnythingV2SmallF16.mlmodelc neni v bundle)
- Real-time inference < 50ms per frame - netestovano
- Battery impact monitoring
- TSDF volume implementace (Marching Cubes)

### Realisticky odhad: **45%**

Dokumentace tvrdila 20%, ale ve skutecnosti je tu vic - algoritmicke mesh corrections, RANSAC plane detection, bilateral filtering, a kompletni pipeline orchestrace. Problem je, ze ML modely chybi a TSDF je stub. Algoritmicke alternativy fungujou, ale bez Neural Engine.

### Co je treba udelat dal
1. Pridat DepthAnythingV2SmallF16.mlmodelc do bundle
2. Implementovat TSDF volume (integrate + Marching Cubes)
3. Nahradit globalni segmentaci prostorovou (VNGeneratePersonSegmentationRequest nebo custom model)
4. Benchmarkovat inference time a battery impact
5. Profilovat memory usage pri depth fusion

---

## Souhrnna tabulka

| Faze | Dokumentovano | Skutecnost | Hlavni problem |
|------|--------------|------------|----------------|
| **Faze 1: Core LiDAR** | 85% | **~55%** | MeshOptimizer chybi, spatne nazvy v docs |
| **Faze 2: Camera & Texture** | 60% | **~40%** | TextureOptimizer chybi, material est. je stub |
| **Faze 3: UI Layer** | 75% | **~80%** | Lepsi nez dokumentovano, UI je robustni |
| **Faze 4: Export** | 70% | **~35%** | USDZ je fake (renamed OBJ), glTF nefunkcni |
| **Faze 5: Cloud** | 80% | **~25%** | 3/4 dokumentovanych souboru neexistuji |
| **Faze 6: EdgeML** | 20% | **~45%** | Lepsi nez dokumentovano, ale ML modely chybi |

### Celkovy postup projektu

- **Dokumentovany prumer:** ~65%
- **Skutecny prumer:** ~47%
- **Hlavni rizika:**
  1. Export pipeline - USDZ a glTF jsou nefunkcni (kriticke pro iOS app)
  2. Cloud integrace - orchestracni vrstva chybi, end-to-end flow neexistuje
  3. ML modely nejsou v bundle

### Systematicke problemy v dokumentaci

1. **Spatne nazvy souboru** - dokumentace pouziva nazvy, ktere neodpovidaji skutecnym souborum (`LiDARService` vs `ARSessionManager`, `CameraService` vs `CameraFrameCapture`, atd.)
2. **Nadhodnoceny postup** - checkboxy jsou oznaceny jako hotove, i kdyz implementace je stub nebo zcela chybi
3. **Phantom features** - `CloudUploadService`, `ScanSyncManager`, `CloudProcessingService` jsou dokumentovany jako existujici a funkci, ale vubec neexistuji
4. **Fake implementace** - USDZ "export" pouze prejmenuje OBJ soubor

---

## Doporucene priority

### P0 - Kriticke (blokuji release)
1. Implementovat realni USDZ export (`MDLAsset`)
2. Opravit glTF export (pridat binary buffer)
3. Vytvorit `CloudUploadService` orchestracni vrstvu
4. Pridat DepthAnything CoreML model do bundle

### P1 - Dulezite
5. Implementovat `MeshOptimizer` (hole filling, decimation)
6. Vytvorit `ScanSyncManager` s offline queue
7. Implementovat `TextureOptimizer`
8. End-to-end test scan -> upload -> processing -> download

### P2 - Vylepseni
9. TSDF volume implementace
10. Prostorova segmentace (nahradit globalnou)
11. Binary PLY export
12. Performance profiling (FPS, memory, battery)

---

*Posledni aktualizace: 2026-02-08*
*Zdroj: Audit codebase pomoci Claude Code*
