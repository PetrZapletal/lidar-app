# ML/AI Vylepšení pro čisté 3D geometrie

## Analýza současného stavu

### Aktuální implementace v projektu

Projekt má připravenou ML infrastrukturu v `Services/EdgeML/`:

1. **MeshCorrectionModel.swift** - CoreML wrapper s algoritmickými korekcemi:
   - Statistical Outlier Removal (k-NN analýza)
   - Laplacian Smoothing (iterativní vyhlazování)
   - Normal Re-estimation (výpočet normál z faces)
   - Confidence scoring (placeholder)

2. **OnDeviceProcessor.swift** - 7-fázový pipeline:
   - Data Preparation → Noise Removal → Hole Filling → Mesh Smoothing →
   - Topology Optimization → Normal Recomputation → Decimation

**Současné limitace:**
- Hole filling není implementován (placeholder)
- Žádný skutečný ML model (.mlmodel)
- KD-tree prostorové indexování chybí
- Texture mapping není integrován s mesh korekcemi

---

## 4 Návrhy vylepšení

---

## 1. Depth Fusion s Prompt Depth Anything

### Koncept
Kombinace LiDAR depth dat s AI-enhanced monokulárním depth estimation pro vyšší rozlišení a vyplnění děr.

### Edge Model (iPhone)
**Model:** [Depth Anything V2 Small](https://huggingface.co/apple/coreml-depth-anything-v2-small)
- **Velikost:** ~25MB (FP16)
- **Inference:** <50ms na Neural Engine
- **Rozlišení:** 518x518 → upscale na 4K

**Implementace:**
```
LiDAR Depth (sparse, 256x192) + RGB Frame
            ↓
    Depth Anything V2 (dense, 518x518)
            ↓
    Prompt Fusion Module
            ↓
    High-res Metric Depth (4K)
```

### Backend Model
**Model:** [Prompt Depth Anything](https://arxiv.org/abs/2412.14015)
- Využívá LiDAR jako "prompt" pro depth foundation model
- 4K rozlišení s metrickou přesností
- State-of-the-art na ARKitScenes a ScanNet++

### Benefity
- **8x vyšší rozlišení** depth map oproti raw LiDAR
- **Vyplnění děr** v oblastech kde LiDAR selhává (sklo, černé povrchy)
- **Lepší hrany** díky edge-aware fusion
- **Přesnější metriky** pro měření vzdáleností

### Nové soubory
```
Services/EdgeML/
├── DepthFusionModel.swift      # CoreML Depth Anything wrapper
├── PromptFusionProcessor.swift # LiDAR + AI depth fusion
└── HighResDepthExtractor.swift # 4K depth extraction
```

---

## 2. Neural Mesh Refinement s MeshGPT-lite

### Koncept
Transformer-based mesh generation pro čisté, artist-like geometrie místo noisy iso-surface extraction.

### Edge Model (iPhone)
**Custom model** inspirovaný [MeshGPT](https://nihalsid.github.io/mesh-gpt/) architekturou:
- **Velikost:** ~50MB (INT8 quantized)
- **Inference:** 100-200ms na Neural Engine
- **Kapacita:** max 10K faces per inference

**Architektura:**
```
Input: Noisy mesh vertices + normals
    ↓
Geometric Vocabulary Encoder (VQ-VAE)
    ↓
Lightweight Transformer (4 layers)
    ↓
Output: Refined vertex positions + topology
```

### Backend Model
**Model:** [Meshtron](https://developer.nvidia.com/blog/high-fidelity-3d-mesh-generation-at-scale-with-meshtron/)
- **64K faces** s 1024-level coordinate resolution
- **Hourglass Transformer** s sliding window attention
- **2.5x rychlejší** a 50% úspora paměti vs MeshGPT

**Alternativa:** [MeshAnything V2](https://openreview.net/forum?id=KGZAs8VcOM)
- Konvertuje libovolnou 3D reprezentaci na Artist-Created Mesh
- Integruje se s NeRF/3DGS výstupy

### Benefity
- **Čisté topologie** bez degenerovaných trojúhelníků
- **Sharp edges** zachovány
- **Manifold meshes** připravené pro 3D tisk
- **Nižší polygon count** při zachování detailů

### Nové soubory
```
Services/EdgeML/
├── MeshVocabularyEncoder.swift  # Geometric tokenizer
├── MeshTransformerLite.swift    # Lightweight transformer
└── TopologyOptimizer.swift      # Quad/triangle remeshing
```

---

## 3. 3D Gaussian Splatting → Mesh Pipeline

### Koncept
Využití 3D Gaussian Splatting pro fotorealistickou rekonstrukci s následnou extrakcí čistého meshe pomocí SuGaR.

### Edge Model (iPhone)
**Příprava dat na zařízení:**
- Point cloud + camera poses → komprimovaný upload
- Lightweight Gaussian initialization
- **Žádný těžký ML** na edge - pouze data collection

### Backend Pipeline
```
┌─────────────────────────────────────────────────────────────┐
│                    GPU Backend (A100/RTX 4090)              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. 3D Gaussian Splatting Training                          │
│     Model: github.com/graphdeco-inria/gaussian-splatting    │
│     Čas: 5-15 minut na scénu                                │
│                                                             │
│  2. Surface-Aligned Optimization (SuGaR)                    │
│     Model: github.com/Anttwo/SuGaR                          │
│     Regularizace Gaussianů k povrchu                        │
│                                                             │
│  3. Mesh Extraction (Poisson Reconstruction)                │
│     Rychlé, škálovatelné, zachovává detaily                 │
│                                                             │
│  4. Texture Baking                                          │
│     UV unwrapping + PBR material generation                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Alternativní modely:**
- [2DGS](https://surfsplatting.github.io/) - 2D Gaussian Splatting pro surface reconstruction
- [GS2Mesh](https://github.com/yanivw12/gs2mesh) - Novel stereo views pro mesh extraction
- [Gaussian Frosting](https://anttwo.github.io/frosting/) - Mesh + Gaussian hybrid

### Benefity
- **Fotorealistické textury** z novel view synthesis
- **Kompletní scény** ne jen jednotlivé objekty
- **Real-time preview** díky Gaussian rendering
- **Profesionální kvalita** srovnatelná s photogrammetry

### Nové soubory
```
Services/Network/
├── GaussianSplatUploader.swift   # Optimized data upload
└── SplatProcessingService.swift  # Backend job management

Backend (Python):
├── gaussian_training.py          # 3DGS training pipeline
├── sugar_optimization.py         # Surface alignment
└── mesh_extraction.py            # Poisson + texture baking
```

---

## 4. Single-Image Enhancement s TripoSR/SPAR3D

### Koncept
Pro objekty skenované z jednoho úhlu - AI doplní chybějící geometrii a textury.

### Edge Model (iPhone)
**Pre-processing:**
- Segmentace objektu (SAM/SegmentAnything CoreML)
- Background removal
- Image enhancement

**Model:** Lightweight feature encoder
- **Velikost:** ~30MB
- Extrakce DINOv2 features pro backend

### Backend Models

**Option A: [TripoSR](https://github.com/VAST-AI-Research/TripoSR)**
- Single image → 3D mesh za **<0.5s**
- MIT licence (open source)
- Založeno na LRM (Large Reconstruction Model)

**Option B: [SPAR3D](https://github.com/Stability-AI/stable-point-aware-3d)**
- Point cloud diffusion + triplane transformer
- **<0.7s** celková inference
- Triangle + quad remeshing included

**Pipeline:**
```
iPhone: Segmented object image + LiDAR partial scan
            ↓
Backend: TripoSR/SPAR3D inference
            ↓
Merge: AI-generated backside + LiDAR frontside
            ↓
Output: Complete 3D mesh with textures
```

### Benefity
- **Kompletní objekty** i z částečného skenu
- **Rychlé zpracování** (<1 sekunda)
- **Symetrické doplnění** chybějících částí
- **Textura generování** pro neviditelné strany

### Nové soubory
```
Services/EdgeML/
├── ObjectSegmentation.swift      # SAM-based segmentation
└── FeatureExtractor.swift        # DINOv2 feature encoding

Services/Network/
└── SingleImageReconstructor.swift # TripoSR/SPAR3D API

Backend (Python):
├── triposr_inference.py          # TripoSR pipeline
├── spar3d_inference.py           # SPAR3D pipeline
└── mesh_fusion.py                # LiDAR + AI mesh merging
```

---

## Přehled modelů

### Edge (iPhone) - CoreML kompatibilní

| Model | Velikost | Inference | Účel |
|-------|----------|-----------|------|
| [Depth Anything V2 Small](https://huggingface.co/apple/coreml-depth-anything-v2-small) | 25MB | <50ms | Depth enhancement |
| [FastViT](https://developer.apple.com/machine-learning/models/) | 15MB | <30ms | Feature extraction |
| SAM (Mobile) | 40MB | <100ms | Object segmentation |
| Custom MeshGPT-lite | 50MB | <200ms | Mesh refinement |
| DINOv2 ViT-S | 80MB | <100ms | Image features |

### Backend (Cloud GPU)

| Model | GPU Memory | Inference | Účel |
|-------|------------|-----------|------|
| [3D Gaussian Splatting](https://github.com/graphdeco-inria/gaussian-splatting) | 8-24GB | 5-15 min | Scene reconstruction |
| [SuGaR](https://github.com/Anttwo/SuGaR) | 8GB | 2-5 min | Mesh extraction |
| [NeuS2](https://github.com/19reborn/NeuS2) | 8GB | 5 min | Neural surface |
| [TripoSR](https://github.com/VAST-AI-Research/TripoSR) | 8GB | <0.5s | Single-image 3D |
| [SPAR3D](https://github.com/Stability-AI/stable-point-aware-3d) | 16GB | <0.7s | Point-aware 3D |
| [Meshtron](https://developer.nvidia.com/blog/high-fidelity-3d-mesh-generation-at-scale-with-meshtron/) | 24GB | Variable | High-fidelity mesh |
| [Prompt Depth Anything](https://arxiv.org/abs/2412.14015) | 8GB | <1s | 4K metric depth |

---

## Doporučená implementační strategie

### Fáze 1: Depth Fusion (2-3 týdny)
1. Integrace Depth Anything V2 CoreML
2. LiDAR + AI depth fusion
3. Vylepšené hole filling

### Fáze 2: Backend 3DGS Pipeline (3-4 týdny)
1. 3D Gaussian Splatting training
2. SuGaR mesh extraction
3. Texture baking pipeline

### Fáze 3: Single-Image Enhancement (2 týdny)
1. TripoSR backend integration
2. Mesh fusion s LiDAR daty
3. UI pro partial scan completion

### Fáze 4: Edge Mesh Refinement (3-4 týdny)
1. Custom MeshGPT-lite training
2. CoreML conversion + quantization
3. Real-time mesh cleanup

---

## Zdroje

### Dokumentace
- [Apple CoreML Models](https://developer.apple.com/machine-learning/models/)
- [Hugging Face CoreML Examples](https://github.com/huggingface/coreml-examples)
- [3D Gaussian Splatting Paper](https://repo-sam.inria.fr/fungraph/3d-gaussian-splatting/)

### Repozitáře
- [Depth Anything V2](https://github.com/DepthAnything/Depth-Anything-V2)
- [SuGaR](https://github.com/Anttwo/SuGaR)
- [TripoSR](https://github.com/VAST-AI-Research/TripoSR)
- [SPAR3D](https://github.com/Stability-AI/stable-point-aware-3d)
- [MeshGPT PyTorch](https://github.com/lucidrains/meshgpt-pytorch)

### Výzkum
- [Radiance Fields](https://radiancefields.com/)
- [Surface Reconstruction Survey](https://pmc.ncbi.nlm.nih.gov/articles/PMC12453780/)
- [Point Cloud Denoising Survey](https://arxiv.org/html/2508.17011v1)
