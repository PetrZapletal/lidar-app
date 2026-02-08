# 09 - 3D Pipeline (skutecny stav)

> Posledni aktualizace: 2026-02-08
> Zdroj: audit kodu + srovnani s `docs/3D_GENERATION_PIPELINE.md`

## Prehled

Originalni spec (`docs/3D_GENERATION_PIPELINE.md`) popisuje ambiciozni pipeline
zahrnujici 3D Gaussian Splatting, SuGaR surface extraction, texture baking atd.
Skutecna implementace je vyrazne jednodussi -- pouziva ARKit nativni mesh,
on-device zpracovani a backendovy Poisson reconstruction.

```
SKUTECNY PIPELINE:

  iPhone (Edge)                          Backend (Apple Silicon)
  ──────────────                         ──────────────────────
  CAPTURE          PROCESS               REFINE              OUTPUT
  ┌──────────┐    ┌──────────────┐      ┌──────────────┐    ┌──────────┐
  │ARSession │ -> │MeshAnchor    │ ---> │SimplePipeline│ -> │ExportSvc │
  │Manager   │    │Processor     │ LRAW │              │    │(iOS)     │
  │          │    │              │      │Depth Any. V2 │    │          │
  │CameraFrm │    │PointCloud   │      │Poisson Recon │    │OBJ [OK]  │
  │Capture   │    │Extractor    │      │Export (trimesh│    │PLY [OK]  │
  │          │    │              │      │              │    │STL [OK]  │
  │DepthMap  │    │Coverage     │      └──────────────┘    │GLB [cast]│
  │Processor │    │Analyzer     │                          │USDZ[fake]│
  └──────────┘    └──────────────┘                          └──────────┘
```

---

## Faze 1: CAPTURE (Edge / iPhone)

### ARSessionManager
- **Soubor:** `LidarAPP/Services/ARKit/ARSessionManager.swift`
- **Stav:** IMPLEMENTOVANO a funkcni
- **Co dela:**
  - Spravuje zivotni cyklus ARKit session (start/pause/resume/stop)
  - Konfigurace: `sceneReconstruction = .meshWithClassification`
  - Frame semantics: `.sceneDepth` + `.smoothedSceneDepth`
  - Podpora 4K video formatu (`recommendedVideoFormatFor4KResolution`)
  - Dva rezimy: exterior (`gravityAndHeading`) a interior (`gravity`)
  - Delegat pro `didAdd/didUpdate/didRemove` ARMeshAnchor
  - Fallback z `gravityAndHeading` na `gravity` pri selhani senzoru
  - Podpora ARWorldMap persistence (ulozeni/nacteni mapy)
- **Co chybi oproti spec:**
  - Zadne -- ARKit capture je kompletni

### CameraFrameCapture
- **Soubor:** `LidarAPP/Services/Camera/CameraFrameCapture.swift`
- **Stav:** IMPLEMENTOVANO
- **Co dela:**
  - Zachytava RGB framy z ARFrame synchronizovane s LiDAR daty
  - Podporuje HEIC, JPEG, PNG vystupy
  - Generuje FrameMetadata (timestamp, transform, intrinsics, exposure)
  - Batch export framu s metadaty do JSON
  - Color sampling, brightness analyza
- **Omezeni:**
  - Resizing "for now returns original" (komentar v kodu)
  - ISO je hardcoded na 100 (ARKit nema primo ISO)

### DepthMapProcessor
- **Soubor:** `LidarAPP/Services/ARKit/DepthMapProcessor.swift`
- **Stav:** IMPLEMENTOVANO (algoritmicky, bez ML)
- **Co dela:**
  - Bilateralni filtr pro smoothing hloubkove mapy
  - Hole filling (iterativni, 4-sousedi, max 10px)
  - Sobel edge detection na hloubkove mape
  - Statistiky hloubky (min/max/mean/median, histogram)
  - Vizualizace hloubky (turbo/viridis/jet/grayscale colormapy)
  - Confidence map analyza (low/medium/high)
- **Co chybi oproti spec:**
  - Depth Anything V2 integrace na zarizeni (je jen na backendu)
  - Hole filling je zakladni placeholder (ne AI inpainting)

---

## Faze 2: PROCESS (Edge / iPhone)

### MeshAnchorProcessor
- **Soubor:** `LidarAPP/Services/ARKit/MeshAnchorProcessor.swift`
- **Stav:** IMPLEMENTOVANO a funkcni
- **Co dela:**
  - Extrahuje vertices, normals, faces, classifications z ARMeshAnchor
  - Podpora local-space i world-space transformace
  - Batch processing (parallelni s TaskGroup)
  - Kombinovani vice meshu do jednoho (s offsetem indexu)
  - Mesh statistiky (vertex/face count, surface area, bounding box, klasifikace)
- **Poznamka:** Toto je zakladni stavebni kamen -- ARKit dela tezkou praci (TSDF + Marching Cubes)

### PointCloudExtractor
- **Soubor:** `LidarAPP/Services/ARKit/PointCloudExtractor.swift`
- **Stav:** IMPLEMENTOVANO
- **Co dela:**
  - Extrakce point cloudu z ARFrame depth dat (back-projection)
  - Extrakce point cloudu z mesh anchor vertexu
  - Confidence filtering (min 0.5)
  - Voxel downsampling (1cm grid, max 500K bodu)
  - Barevny point cloud (sampling barvy z kameroveho obrazu)
  - "Safe" varianta s validaci bufferu
- **Omezeni:**
  - Downsample stride = 2 (kazdy 2. pixel)
  - Color sampling predpoklada BGRA format (ne vzdy spravne pro YCbCr z ARKit)

### CoverageAnalyzer
- **Soubor:** `LidarAPP/Services/ARKit/CoverageAnalyzer.swift`
- **Stav:** IMPLEMENTOVANO (robustni)
- **Co dela:**
  - 3D grid (10cm bunky) s poctem pohledu a uhlem
  - Quality levels: none/poor/fair/good/excellent
  - Detekce mezer (flood fill clustering, prioritizace)
  - Navrh smeru kamery pro uzivatelsky guidance
  - Serializace/deserializace coverage gridu
  - Performance optimalizace: rate limiting, lazy gap detection, dirty flag pro statistiky
- **Poznamka:** Jeden z nejkvalitnejsich souboru v projektu -- dobry stav

### MeshCorrectionModel
- **Soubor:** `LidarAPP/Services/EdgeML/MeshCorrectionModel.swift`
- **Stav:** STUB / PLACEHOLDER
- **Co dela ve skutecnosti:**
  - `loadModel()` nastavuje stav na `.ready` ale NENACITA zadny .mlmodel soubor
  - Korekce jsou ciste algoritmicke (ne ML):
    - Statistical outlier removal (O(n^2) bez KD-tree!)
    - Laplacian smoothing (O(n^2) hledani sousedu!)
    - Normal re-estimation z face dat
  - Komentare v kodu: "For MVP: Use algorithmic corrections instead of ML model"
- **Problem:** Quadraticka slozitost -- nepouzitelne pro velke meshe (100K+ vertexu)

---

## Faze 3: REFINE (Backend / Apple Silicon)

### SimplePipeline
- **Soubor:** `backend/services/simple_pipeline.py`
- **Stav:** IMPLEMENTOVANO (nahrazuje puvodni GS pipeline)
- **Co dela:**
  1. **Parse LRAW** (10%) -- RawDataProcessor parsuje binarni LRAW format
  2. **AI Depth Enhancement** (30%) -- Depth Anything V2 (pokud dostupne)
  3. **Point Cloud Extraction** (20%) -- z mesh dat nebo AI-enhanced hloubek
  4. **Poisson Reconstruction** (30%) -- Open3D, depth=9, outlier removal
  5. **Export** (10%) -- PLY, GLB (trimesh), OBJ (trimesh)
- **Poznamka:** Gaussian Splatting a SuGaR ze spec NEJSOU implementovane.
  Backend bezi na Apple Silicon (MPS/CPU), ne na CUDA GPU.

### Poisson Reconstruction (detail)
- Open3D `create_from_point_cloud_poisson(depth=9)`
- Fallback na depth=7 pri selhani
- Orezani low-density vertexu (1% kvantil)
- Cisteni: degenerate triangles, duplicity, non-manifold edges
- Filtrovani neplatnych souradnic (> 1000m)

---

## Datovy transport: LRAW format

Binarni format pro prenos raw scan dat z iPhonu na backend.

### Struktura
```
Header (32 bytes):
  Magic:           "LRAW" (4 bytes)
  Version:         UInt16 (2 bytes) -- aktualne 1
  Flags:           UInt16 (2 bytes)
    bit 0: HAS_CLASSIFICATIONS
    bit 1: HAS_CONFIDENCE_MAPS
    bit 2: HAS_TEXTURE_FRAMES
    bit 3: HAS_DEPTH_FRAMES
    bit 4: COMPRESSED (nepouzivano)
  Mesh count:      UInt32 (4 bytes)
  Texture count:   UInt32 (4 bytes)
  Depth count:     UInt32 (4 bytes)
  Reserved:        12 bytes

Mesh Anchors Section:
  Pro kazdy anchor:
    UUID:          16 bytes
    Transform:     64 bytes (4x4 float matice)
    Vertex count:  UInt32
    Face count:    UInt32
    Class. flag:   UInt8
    Vertices:      vertex_count * 16 bytes (simd_float3, stride=16!)
    Normals:       vertex_count * 16 bytes
    Faces:         face_count * 16 bytes (simd_uint3, stride=16!)
    Classifications: face_count * 1 byte (volitelne)

Texture Frames Section:
  Pro kazdy frame:
    UUID:          16 bytes
    Timestamp:     Double (8 bytes)
    Transform:     64 bytes
    Intrinsics:    48 bytes (simd_float3x3)
    Width/Height:  8 bytes
    Image length:  UInt32
    Image data:    JPEG/HEIC bytes

Depth Frames Section:
  Pro kazdy frame:
    UUID:          16 bytes
    Timestamp:     Double (8 bytes)
    Transform:     64 bytes
    Intrinsics:    48 bytes
    Width/Height:  8 bytes
    Depth values:  width * height * 4 bytes (Float32)
    Confidence:    width * height bytes (volitelne)
```

### Encoder/Decoder
- **iOS (encoder):** `LidarAPP/Services/Debug/RawDataPackager.swift`
- **Backend (decoder):** `backend/services/raw_data_processor.py`
- **Debug nastroj:** `backend/debug_lraw.py`

**POZOR:** SIMD stride je 16 bytes (ne 12!) -- simd_float3 a simd_uint3 v iOS maji
alignment padding. Toto je dokumentovano v debug_lraw.py.

---

## Faze 4: OUTPUT (Edge / iPhone)

### ExportService
- **Soubor:** `LidarAPP/Presentation/Export/ExportService.swift`
  (POZOR: je v Presentation/, ne v Services/ -- chybne umisteni)
- **Stav:** Castecne implementovano

| Format | Stav | Poznamka |
|--------|------|----------|
| OBJ | FUNKCNI | ASCII export, Y-up/Z-up konverze, normals |
| PLY | FUNKCNI | ASCII format, vertices + normals + barvy |
| STL | FUNKCNI | ASCII STL, face normals |
| JSON | FUNKCNI | Export mereni (measurements) |
| CSV | FUNKCNI | Export mereni |
| glTF | CASTECNY | Pouze JSON metadata, BEZ binarniho bufferu -- nefunkcni |
| USDZ | FAKE | Exportuje OBJ a prejmenovava na .usdz! |

### USDZ "export" -- detail problemu
```swift
// ExportService.swift, radek 322-339
private func exportToUSDZ(...) async throws {
    let objURL = url.deletingPathExtension().appendingPathExtension("obj")
    try await exportToOBJ(mesh, url: objURL, options: options)
    // Move OBJ to final URL for now
    try fileManager.moveItem(at: objURL, to: url)
}
```
Vysledny .usdz soubor je ve skutecnosti OBJ s jinou priponou.
Nebude fungovat v AR Quick Look ani v zadnem USDZ readeru.

---

## Srovnani: Spec vs Realita

| Funkce | Spec | Realita |
|--------|------|---------|
| ARKit mesh capture | Ano | **Ano** |
| Depth Anything V2 (on-device) | Ano | **Ne** (jen backend) |
| 3D Gaussian Splatting | Ano | **Ne** (nahrazeno Poisson) |
| SuGaR surface extraction | Ano | **Ne** |
| Texture baking (UV unwrap) | Ano | **Ne** |
| PBR textury (diffuse, normal, roughness) | Ano | **Ne** |
| Poisson reconstruction | Ne (mel byt GS) | **Ano** (backend) |
| OBJ export | Ano | **Ano** |
| PLY export | Ano | **Ano** |
| STL export | Ano | **Ano** |
| glTF export | Ano | **Castecny** (nefunkcni) |
| USDZ export | Ano | **Fake** (prejmenovany OBJ) |
| ML mesh correction (on-device) | Ano | **Stub** (algoritmicke, O(n^2)) |
| Chunked upload | Ano | **Ne** (single LRAW upload) |
| Coverage analysis | Nespecifikovano | **Ano** (robustni) |
| LRAW binary format | Nespecifikovano | **Ano** (vlastni format) |

---

## Doporuceni pro dalsi vyvoj

1. **USDZ export** -- pouzit `MDLAsset` nebo `SceneKit` pro skutecnou konverzi
2. **glTF export** -- doplnit binarni buffer (.bin) k JSON metadatum
3. **MeshCorrectionModel** -- bud dodat .mlmodel nebo nahradit efektivnim algoritmem (KD-tree)
4. **Texture pipeline** -- zatim uplne chybi (zadne UV, zadne textury na meshu)
5. **Depth Anything on-device** -- CoreML konverze modelu pro offline pouziti
