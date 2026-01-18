# LiDAR 3D Scanner

**Ultra-přesné řešení pro 3D mapování prostoru** s offline měřením. iOS aplikace pro AI-powered 3D skenování s LiDAR a fotoaparátem.

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-17.0+-blue.svg)](https://apple.com/ios)
[![Python](https://img.shields.io/badge/Python-3.11-blue.svg)](https://python.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Klíčové vlastnosti

- 🎯 **Přesné 3D mapování** prostředí v reálném čase (±1cm přesnost)
- 📏 **Offline měření** - vzdálenosti, plochy, objemy bez připojení
- 🤖 **AI zpracování** - neuronové sítě pro kvalitní mesh a textury
- 📤 **Export** - profesionální 3D formáty (USDZ, glTF, OBJ, STL, PLY)
- 📱 **AR Preview** - umístění modelu do reálného prostředí

## Architektura

```
┌─────────────────────────────────────────────────────────────────────┐
│                        iPhone (Edge Device)                          │
├─────────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────────────┐    │
│  │   LiDAR      │   │   Camera     │   │   Edge ML Model      │    │
│  │   Scanner    │──▶│   Capture    │──▶│   (CoreML)           │    │
│  │   (ARKit)    │   │   (RGB)      │   │   - Depth fusion     │    │
│  └──────────────┘   └──────────────┘   │   - Mesh cleanup     │    │
│                                         │   - Point cloud      │    │
│                                         └──────────────────────┘    │
│                                                    │                 │
│                                                    ▼                 │
│                              ┌──────────────────────────────────┐   │
│                              │  Upload: Point Cloud + Textures  │   │
│                              └──────────────────────────────────┘   │
└─────────────────────────────────────────┬───────────────────────────┘
                                          │
                                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        Backend (Cloud GPU)                           │
├─────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    AI Processing Pipeline                     │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────────────────┐  │   │
│  │  │ 3D Gaussian│  │ SuGaR Mesh │  │ Texture Baking         │  │   │
│  │  │ Splatting  │──▶│ Extraction │──▶│ + UV Mapping          │  │   │
│  │  └────────────┘  └────────────┘  └────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                    │                                 │
│                                    ▼                                 │
│              ┌──────────────────────────────────────────┐           │
│              │  Output: Clean Mesh + PBR Textures       │           │
│              │  (USDZ, glTF, OBJ, STL, PLY)             │           │
│              └──────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────────────┘
```

## Struktura projektu

```
lidar-app/
├── LidarAPP/                          # iOS aplikace
│   ├── LidarAPP.xcodeproj/            # Xcode projekt
│   └── LidarAPP/
│       ├── App/                       # Entry point, konfigurace
│       ├── Core/                      # Utility, extensions, DI
│       ├── Domain/                    # Entity modely
│       ├── Presentation/              # SwiftUI views + ViewModels
│       │   ├── Scanning/              # Skenovací obrazovka
│       │   ├── Preview/               # 3D náhled
│       │   ├── Export/                # Export služby
│       │   └── Auth/                  # Autentizace
│       ├── Services/
│       │   ├── ARKit/                 # LiDAR, mesh, point cloud
│       │   ├── Camera/                # Frame capture, synchronizace
│       │   ├── EdgeML/                # Depth Anything, fusion
│       │   ├── Measurement/           # Vzdálenosti, plochy, objemy
│       │   ├── Rendering/             # Metal, RealityKit
│       │   └── Network/               # API, WebSocket, upload
│       └── Resources/                 # Assets, Info.plist
│
├── backend/                           # Python backend
│   ├── api/                           # FastAPI server
│   ├── services/                      # Processing pipeline
│   │   ├── gaussian_splatting.py      # 3DGS training
│   │   ├── sugar_mesh.py              # Mesh extraction
│   │   ├── texture_baker.py           # UV + textures
│   │   └── export_service.py          # Multi-format export
│   ├── Dockerfile
│   └── docker-compose.yml
│
└── docs/                              # Dokumentace
    ├── 3D_GENERATION_PIPELINE.md      # Technický popis pipeline
    └── ML_IMPROVEMENTS_PROPOSAL.md    # AI/ML vylepšení
```

## Požadavky

### iOS aplikace
- **Zařízení**: iPhone 12 Pro / iPad Pro 2020 nebo novější (s LiDAR)
- **iOS**: 17.0+
- **Xcode**: 15.0+

### Backend
- **Python**: 3.11+
- **GPU**: NVIDIA s CUDA 12.1+ (doporučeno A100/RTX 4090)
- **RAM**: 16GB+ (32GB doporučeno)
- **Storage**: 100GB+ pro scan data

## Instalace

### iOS aplikace

```bash
# Klonovat repozitář
git clone https://github.com/PetrZapletal/lidar-app.git
cd lidar-app

# Otevřít v Xcode
open LidarAPP/LidarAPP.xcodeproj

# Stáhnout Depth Anything V2 model
# https://huggingface.co/apple/coreml-depth-anything-v2-small
# Přidat do projektu jako DepthAnythingV2Small.mlmodelc
```

### Backend

```bash
cd backend

# Docker deployment
docker-compose up -d

# Nebo lokální instalace
pip install -r requirements.txt
uvicorn api.main:app --host 0.0.0.0 --port 8000
```

## API Reference

### Endpoints

| Method | Endpoint | Popis |
|--------|----------|-------|
| `POST` | `/api/v1/scans` | Vytvořit nový scan |
| `POST` | `/api/v1/scans/{id}/upload` | Upload point cloud + textures |
| `POST` | `/api/v1/scans/{id}/process` | Spustit AI processing |
| `GET` | `/api/v1/scans/{id}/status` | Stav zpracování |
| `GET` | `/api/v1/scans/{id}/download` | Stáhnout výsledek |
| `WS` | `/ws/scans/{id}` | Real-time status updates |

### Processing Options

```json
{
  "enable_gaussian_splatting": true,
  "enable_mesh_extraction": true,
  "enable_texture_baking": true,
  "mesh_resolution": "high",
  "texture_resolution": 4096,
  "output_formats": ["usdz", "gltf", "obj"]
}
```

## ML Modely

### Edge (iPhone)

| Model | Velikost | Inference | Účel |
|-------|----------|-----------|------|
| Depth Anything V2 | 25MB | <50ms | Depth enhancement |
| Custom MeshGPT-lite | 50MB | <200ms | Mesh refinement |

### Backend (GPU)

| Model | VRAM | Čas | Účel |
|-------|------|-----|------|
| 3D Gaussian Splatting | 8-24GB | 5-15 min | Scene reconstruction |
| SuGaR | 8GB | 2-5 min | Mesh extraction |
| Texture Baker | 4GB | 1-2 min | UV + textures |

## Měření (Offline)

Aplikace podporuje přesné měření bez připojení k internetu:

- **Vzdálenosti**: Point-to-point, polyline (±1cm na 5m)
- **Plochy**: Polygon area, mesh surface
- **Objemy**: Bounding box, mesh volume
- **Úhly**: Mezi plochami

## Export formáty

| Formát | Popis | Použití |
|--------|-------|---------|
| USDZ | Apple AR | AR Quick Look, Reality Composer |
| glTF | Cross-platform | Web, Unity, Unreal |
| OBJ | Universal | CAD software, Blender |
| STL | 3D Print | Slicery, 3D tisk |
| PLY | Point Cloud | CloudCompare, MeshLab |

## Vývoj

### Spuštění testů

```bash
# iOS testy
xcodebuild test -scheme LidarAPP -destination 'platform=iOS Simulator,name=iPhone 15 Pro'

# Backend testy
cd backend
pytest tests/
```

### Kódové konvence

- **Swift**: SwiftLint, SwiftFormat
- **Python**: Black, isort, mypy

## Roadmap

- [x] ARKit LiDAR integrace
- [x] Základní mesh processing
- [x] Offline měření
- [x] Depth Anything V2 integrace
- [x] Backend 3DGS pipeline
- [ ] Uživatelské účty a předplatné
- [ ] Cloudové úložiště skenů
- [ ] Kolaborativní editace
- [ ] AR anotace

## Licence

MIT License - viz [LICENSE](LICENSE)

## Autoři

- Petr Zapletal
- Claude AI (Anthropic)

---

**Poznámka**: Pro testování je vyžadováno fyzické zařízení s LiDAR senzorem. ARKit s LiDAR nelze simulovat v iOS Simulátoru.
