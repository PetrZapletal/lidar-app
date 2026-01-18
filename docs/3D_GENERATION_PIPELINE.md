# Generování 3D prostoru - Technický popis

## Přehled pipeline

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         3D GENERATION PIPELINE                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │   CAPTURE   │ →  │  PROCESS    │ →  │   REFINE    │ →  │   OUTPUT    │  │
│  │   (Edge)    │    │   (Edge)    │    │  (Backend)  │    │   (Edge)    │  │
│  └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘  │
│                                                                             │
│   LiDAR + Camera     Point Cloud        3D Gaussian       Clean Mesh       │
│   Raw Data           + Initial Mesh     Splatting         + Textures       │
│                                         + AI Refinement                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Fáze 1: CAPTURE - Sběr dat na iPhone

### 1.1 LiDAR Scanning (ARKit)

iPhone LiDAR senzor (dTOF - direct Time of Flight) emituje infračervené pulzy a měří čas návratu:

```
┌─────────────────────────────────────────────────────────────┐
│                    LiDAR Sensor Array                        │
│                                                             │
│    IR Emitter ─────────────────────────────→ IR Detector    │
│         │                                          ↑        │
│         │     ┌─────────────┐                      │        │
│         └────→│   Object    │──────────────────────┘        │
│               └─────────────┘                               │
│                                                             │
│    Vzdálenost = (čas letu × rychlost světla) / 2           │
│    Přesnost: ±1cm na 5m                                     │
│    Rozlišení: 256 × 192 bodů @ 60Hz                         │
│    Dosah: 0.1m - 5m                                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**ARKit konfigurace:**
```swift
let config = ARWorldTrackingConfiguration()
config.sceneReconstruction = .meshWithClassification
config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
config.planeDetection = [.horizontal, .vertical]
```

### 1.2 Mesh Reconstruction (ARKit native)

ARKit automaticky vytváří mesh z LiDAR dat pomocí TSDF (Truncated Signed Distance Function):

```
┌─────────────────────────────────────────────────────────────┐
│                    ARKit Mesh Pipeline                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Depth Frame (256×192)                                      │
│       ↓                                                     │
│  Camera Intrinsics (fx, fy, cx, cy)                         │
│       ↓                                                     │
│  Back-projection do 3D                                      │
│       xi = (u - cx) × di / fx                               │
│       yi = (v - cy) × di / fy                               │
│       zi = di                                               │
│       ↓                                                     │
│  TSDF Volume Fusion                                         │
│       Pro každý voxel: akumulace signed distance            │
│       ↓                                                     │
│  Marching Cubes                                             │
│       Iso-surface extraction při SDF = 0                    │
│       ↓                                                     │
│  ARMeshAnchor                                               │
│       vertices[], normals[], faces[], classifications[]     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Mesh Anchor Data:**
```swift
struct ARMeshGeometry {
    var vertices: ARGeometrySource      // simd_float3[]
    var normals: ARGeometrySource       // simd_float3[]
    var faces: ARGeometryElement        // simd_uint3[] (triangle indices)
    var classification: ARGeometrySource // UInt8[] (wall, floor, ceiling...)
}
```

### 1.3 RGB Camera Capture

Synchronizovaný snímek z kamery pro textury:

```
┌─────────────────────────────────────────────────────────────┐
│                 Frame Synchronization                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  LiDAR Frame (t₀)          Camera Frame (t₀ ± 8ms)          │
│       ↓                           ↓                         │
│  ARFrame.capturedDepthData   ARFrame.capturedImage          │
│       ↓                           ↓                         │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              FrameSynchronizer                       │    │
│  │                                                     │    │
│  │  • Timestamp alignment (interpolace pokud nutné)    │    │
│  │  • Camera intrinsics extraction                     │    │
│  │  • Transform matrix (camera → world)                │    │
│  │  • Depth → UV projection                            │    │
│  │                                                     │    │
│  └─────────────────────────────────────────────────────┘    │
│       ↓                                                     │
│  SynchronizedFrame {                                        │
│      depthMap: CVPixelBuffer                                │
│      colorImage: CVPixelBuffer                              │
│      cameraIntrinsics: simd_float3x3                        │
│      transform: simd_float4x4                               │
│  }                                                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.4 Device Trajectory

SLAM (Simultaneous Localization and Mapping) pro tracking pozice:

```
┌─────────────────────────────────────────────────────────────┐
│                    Visual-Inertial SLAM                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐    │
│  │    IMU       │   │   Camera     │   │   LiDAR      │    │
│  │ (gyro+accel) │   │   Features   │   │   Depth      │    │
│  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘    │
│         │                  │                  │             │
│         └──────────────────┼──────────────────┘             │
│                            ↓                                │
│                   ┌────────────────┐                        │
│                   │  Pose Fusion   │                        │
│                   │                │                        │
│                   │  Extended      │                        │
│                   │  Kalman Filter │                        │
│                   └────────┬───────┘                        │
│                            ↓                                │
│                   Camera Pose (6-DoF)                       │
│                   [tx, ty, tz, rx, ry, rz]                  │
│                                                             │
│  Přesnost: <1% drift na 10m trajektorie                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Fáze 2: PROCESS - Edge Processing na iPhone

### 2.1 Point Cloud Extraction

```
┌─────────────────────────────────────────────────────────────┐
│                Point Cloud Generation                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Input: Depth Map (256×192) + Camera Matrix                 │
│                                                             │
│  for each pixel (u, v) with depth d:                        │
│                                                             │
│      // Back-projection                                     │
│      x_cam = (u - cx) * d / fx                              │
│      y_cam = (v - cy) * d / fy                              │
│      z_cam = d                                              │
│                                                             │
│      // Transform to world                                  │
│      P_world = camera_transform × [x_cam, y_cam, z_cam, 1]  │
│                                                             │
│      // Confidence filtering                                │
│      if confidence[u,v] >= 0.5:                             │
│          points.append(P_world.xyz)                         │
│                                                             │
│  // Voxel Downsampling (1cm grid)                           │
│  voxel_hash = floor(point / voxel_size)                     │
│  voxel_map[hash] = centroid(points_in_voxel)                │
│                                                             │
│  Output: ~50,000-200,000 bodů per frame                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Depth Enhancement (AI)

```
┌─────────────────────────────────────────────────────────────┐
│           Depth Anything V2 Enhancement                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐                   ┌──────────────┐        │
│  │  RGB Image   │                   │  LiDAR Depth │        │
│  │  (1920×1440) │                   │  (256×192)   │        │
│  └──────┬───────┘                   └──────┬───────┘        │
│         │                                  │                │
│         ↓                                  │                │
│  ┌──────────────────────┐                  │                │
│  │   Depth Anything V2  │                  │                │
│  │   (CoreML, 25MB)     │                  │                │
│  │                      │                  │                │
│  │   Vision Transformer │                  │                │
│  │   + DPT Decoder      │                  │                │
│  └──────────┬───────────┘                  │                │
│             │                              │                │
│             ↓                              ↓                │
│  ┌──────────────────────────────────────────────────┐       │
│  │              Prompt Fusion Module                 │       │
│  │                                                  │       │
│  │  AI Depth (relative)  +  LiDAR Depth (metric)   │       │
│  │       ↓                        ↓                │       │
│  │  Scale alignment: AI_metric = AI × (LiDAR_mean) │       │
│  │       ↓                                         │       │
│  │  Confidence weighting:                          │       │
│  │    fused = w_lidar × lidar + w_ai × ai_metric   │       │
│  │    w_lidar = lidar_confidence                   │       │
│  │    w_ai = 1 - lidar_confidence                  │       │
│  │       ↓                                         │       │
│  │  Edge-aware blending                            │       │
│  │                                                  │       │
│  └──────────────────────────────────────────────────┘       │
│             ↓                                               │
│  Enhanced Depth (1920×1440) s metrickou přesností           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 Initial Mesh Cleanup

```
┌─────────────────────────────────────────────────────────────┐
│              On-Device Mesh Processing                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Input: ARMeshAnchor (raw mesh)                             │
│                                                             │
│  1. STATISTICAL OUTLIER REMOVAL                             │
│     ┌─────────────────────────────────────────────────┐     │
│     │  Pro každý vertex:                               │     │
│     │    1. Najdi k nejbližších sousedů (k=20)        │     │
│     │    2. Spočítej mean distance                    │     │
│     │    3. Spočítej std deviation všech distances    │     │
│     │    4. Odstraň pokud distance > mean + 2×std     │     │
│     └─────────────────────────────────────────────────┘     │
│                                                             │
│  2. LAPLACIAN SMOOTHING                                     │
│     ┌─────────────────────────────────────────────────┐     │
│     │  Pro každý vertex (2 iterace):                   │     │
│     │    1. Najdi všechny sousedy (connected faces)   │     │
│     │    2. Spočítej centroid sousedů                 │     │
│     │    3. Nová pozice = lerp(vertex, centroid, 0.5) │     │
│     └─────────────────────────────────────────────────┘     │
│                                                             │
│  3. DEGENERATE TRIANGLE REMOVAL                             │
│     ┌─────────────────────────────────────────────────┐     │
│     │  Odstraň trojúhelníky kde:                       │     │
│     │    • Area < 1e-8 (nulová plocha)                │     │
│     │    • Kolineární vertices                        │     │
│     │    • Duplicitní vertices                        │     │
│     └─────────────────────────────────────────────────┘     │
│                                                             │
│  4. NORMAL RECOMPUTATION                                    │
│     ┌─────────────────────────────────────────────────┐     │
│     │  Pro každý vertex:                               │     │
│     │    1. Najdi všechny přilehlé faces              │     │
│     │    2. Spočítej face normal = cross(e1, e2)      │     │
│     │    3. Akumuluj normály (area-weighted)          │     │
│     │    4. Normalizuj výsledek                       │     │
│     └─────────────────────────────────────────────────┘     │
│                                                             │
│  Output: Cleaned mesh (ready for upload)                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Fáze 3: REFINE - Backend AI Processing

### 3.1 Data Upload

```
┌─────────────────────────────────────────────────────────────┐
│                    Chunked Upload                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Upload Package:                                            │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  scan_data/                                          │    │
│  │  ├── pointcloud.ply      (binary, ~50-200MB)        │    │
│  │  ├── mesh_anchors/                                  │    │
│  │  │   ├── anchor_0.bin    (vertices, faces, normals) │    │
│  │  │   └── anchor_N.bin                               │    │
│  │  ├── textures/                                      │    │
│  │  │   ├── frame_0000.heic (camera intrinsics json)   │    │
│  │  │   └── frame_NNNN.heic                            │    │
│  │  ├── trajectory.json     (camera poses timeline)    │    │
│  │  └── metadata.json       (device, settings, bbox)   │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  Chunked transfer:                                          │
│    • 5MB chunks                                            │
│    • Resumable upload                                      │
│    • SHA256 verification                                   │
│    • Progress: 0-100%                                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 3D Gaussian Splatting Training

```
┌─────────────────────────────────────────────────────────────┐
│              3D Gaussian Splatting Pipeline                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  INITIALIZATION                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Point Cloud → Initial Gaussians                    │    │
│  │                                                     │    │
│  │  Pro každý bod:                                     │    │
│  │    position: μ = [x, y, z]                          │    │
│  │    covariance: Σ = R × S × S^T × R^T                │    │
│  │      S = diag(sx, sy, sz)  (scale)                  │    │
│  │      R = quaternion → matrix (rotation)             │    │
│  │    opacity: α ∈ [0, 1]                              │    │
│  │    color: spherical harmonics (SH) coefficients     │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  DIFFERENTIABLE RASTERIZATION                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                                                     │    │
│  │  Pro každý pixel:                                   │    │
│  │    1. Najdi Gaussians které přispívají              │    │
│  │    2. Seřaď podle depth (front-to-back)             │    │
│  │    3. Alpha compositing:                            │    │
│  │                                                     │    │
│  │       C_pixel = Σᵢ cᵢ × αᵢ × Π_{j<i}(1 - αⱼ)        │    │
│  │                                                     │    │
│  │    4. Compute loss vs ground truth image            │    │
│  │       L = L₁ + λ × D-SSIM                           │    │
│  │                                                     │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  ADAPTIVE DENSITY CONTROL                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Každých 100 iterací:                               │    │
│  │                                                     │    │
│  │  • Densification (gradient > threshold):           │    │
│  │    - Clone: malé Gaussians → 2×                    │    │
│  │    - Split: velké Gaussians → 2× menší             │    │
│  │                                                     │    │
│  │  • Pruning:                                         │    │
│  │    - Opacity < 0.01 → remove                       │    │
│  │    - Too large → remove                            │    │
│  │                                                     │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  Training time: 5-15 minut (30K iterací)                    │
│  Output: ~500K-2M optimized Gaussians                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 Surface Extraction (SuGaR)

```
┌─────────────────────────────────────────────────────────────┐
│            SuGaR: Surface-Aligned Gaussians                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  REGULARIZATION                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Přidej regularizační loss pro alignment:           │    │
│  │                                                     │    │
│  │  L_reg = Σᵢ ||sᵢ_min||²                             │    │
│  │                                                     │    │
│  │  Minimalizuje nejmenší scale každého Gaussianu      │    │
│  │  → Gaussians se "zploští" na surface                │    │
│  │                                                     │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  DENSITY FIELD EXTRACTION                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Pro každý bod v prostoru x:                        │    │
│  │                                                     │    │
│  │  density(x) = Σᵢ αᵢ × exp(-0.5 × (x-μᵢ)^T Σᵢ⁻¹ (x-μᵢ)) │
│  │                                                     │    │
│  │  Vysoká density = blízko povrchu                    │    │
│  │                                                     │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  POISSON SURFACE RECONSTRUCTION                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  1. Sample points na iso-surface (density = τ)      │    │
│  │  2. Estimate normals z Gaussian orientací           │    │
│  │  3. Poisson reconstruction:                         │    │
│  │     - Řeší ∇²χ = ∇·V (V = oriented points)          │    │
│  │     - χ = indicator function                        │    │
│  │  4. Marching Cubes pro finální mesh                 │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  MESH REFINEMENT                                            │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  1. Bind Gaussians k mesh vertices                  │    │
│  │  2. Joint optimization:                             │    │
│  │     - Render loss (image quality)                   │    │
│  │     - Mesh regularization (smoothness)              │    │
│  │  3. Laplacian smoothing                             │    │
│  │  4. Quadric error decimation (optional)             │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  Output: Clean triangle mesh (50K-500K faces)               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 3.4 Texture Generation

```
┌─────────────────────────────────────────────────────────────┐
│                 Texture Baking Pipeline                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  UV UNWRAPPING                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Algorithm: xatlas (automatic UV atlas generation)  │    │
│  │                                                     │    │
│  │  1. Seam detection (high curvature edges)           │    │
│  │  2. Chart creation (connected face groups)          │    │
│  │  3. Parameterization (minimize distortion)          │    │
│  │  4. Atlas packing (maximize texture utilization)    │    │
│  │                                                     │    │
│  │  Output: UV coordinates pro každý vertex            │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  VIEW SELECTION                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Pro každý face:                                    │    │
│  │    1. Najdi všechny views které ho vidí             │    │
│  │    2. Score = visibility × angle × resolution       │    │
│  │    3. Vyber top-K views pro blending                │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  TEXTURE PROJECTION                                         │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Pro každý texel v atlas:                           │    │
│  │    1. Najdi odpovídající 3D point na mesh           │    │
│  │    2. Project do všech vybraných views              │    │
│  │    3. Sample barvu z každého view                   │    │
│  │    4. Blend s váhami (view-dependent)               │    │
│  │    5. Color correction (exposure matching)          │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  SEAM BLENDING                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  • Poisson blending na chart boundaries             │    │
│  │  • Multi-band blending (frequency domain)           │    │
│  │  • Optional: AI inpainting pro díry                 │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  Output: Diffuse texture (4K), Normal map, Roughness map    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Fáze 4: OUTPUT - Finální výstup

### 4.1 Mesh Post-processing

```
┌─────────────────────────────────────────────────────────────┐
│                Final Mesh Optimization                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  TOPOLOGY CLEANUP                                           │
│  • Remove non-manifold edges                               │
│  • Fill small holes (< 10 edges)                           │
│  • Remove isolated components (< 100 faces)                │
│                                                             │
│  SIMPLIFICATION (optional)                                  │
│  • Quadric Error Metrics decimation                        │
│  • Target: 50% reduction s < 0.1% error                    │
│  • Preserve UV seams a sharp edges                         │
│                                                             │
│  COORDINATE SYSTEM                                          │
│  • ARKit: Y-up, right-handed                               │
│  • Export option: Z-up pro CAD software                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Export Formáty

```
┌─────────────────────────────────────────────────────────────┐
│                    Export Formats                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  USDZ (Apple AR)                                            │
│  ├── mesh.usdc (binary geometry)                           │
│  ├── diffuse.png (4K texture)                              │
│  ├── normal.png                                            │
│  └── roughness.png                                         │
│                                                             │
│  glTF 2.0 (Web/Cross-platform)                              │
│  ├── model.gltf (JSON metadata)                            │
│  └── model.bin (binary buffers)                            │
│                                                             │
│  OBJ (Universal)                                            │
│  ├── model.obj (geometry)                                  │
│  ├── model.mtl (materials)                                 │
│  └── texture.jpg                                           │
│                                                             │
│  STL (3D Print)                                             │
│  └── model.stl (triangles only, no texture)                │
│                                                             │
│  PLY (Point Cloud)                                          │
│  └── pointcloud.ply (vertices + colors)                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Kvalita výstupu

### Metriky

| Metrika | Edge Processing | Backend AI |
|---------|-----------------|------------|
| Vertex count | 50K-200K | 50K-500K (optimized) |
| Accuracy | ±1-2cm | ±0.5cm |
| Hole filling | Basic | Complete |
| Textures | Camera projection | Multi-view fusion |
| Processing time | Real-time | 5-20 min |
| Sharp edges | Preserved | Enhanced |

### Porovnání kvality

```
┌─────────────────────────────────────────────────────────────┐
│                    Quality Comparison                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  RAW LIDAR MESH (ARKit native)                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  • Noisy surface                                    │    │
│  │  • Holes in low-confidence areas                    │    │
│  │  • Jagged edges                                     │    │
│  │  • No textures                                      │    │
│  │  • 100K-500K unoptimized triangles                  │    │
│  └─────────────────────────────────────────────────────┘    │
│                         ↓                                   │
│  EDGE PROCESSED                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  • Smoothed surface (Laplacian)                     │    │
│  │  • Outliers removed                                 │    │
│  │  • Improved normals                                 │    │
│  │  • Basic hole filling                               │    │
│  │  • ~30% vertex reduction                            │    │
│  └─────────────────────────────────────────────────────┘    │
│                         ↓                                   │
│  BACKEND AI REFINED                                         │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  • Clean, manifold topology                         │    │
│  │  • Complete surface (no holes)                      │    │
│  │  • Sharp edges where appropriate                    │    │
│  │  • High-quality PBR textures                        │    │
│  │  • Optimized triangle count                         │    │
│  │  • Ready for professional use                       │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementační priorita

1. **Fáze 1** (Kritická): ARKit mesh capture + základní cleanup
2. **Fáze 2** (Vysoká): Depth Anything integration pro lepší rozlišení
3. **Fáze 3** (Vysoká): Backend 3DGS + SuGaR pipeline
4. **Fáze 4** (Střední): Texture baking pipeline
5. **Fáze 5** (Nízká): Advanced mesh refinement (MeshGPT-lite)
