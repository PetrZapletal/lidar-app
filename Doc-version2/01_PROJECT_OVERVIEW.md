# 01 - Project Overview

## Vize

Lumiscan je iOS aplikace, která využívá LiDAR senzor v iPhonu/iPadu k profesionálnímu 3D skenování prostorů a objektů. Surová data z ARKitu jsou zpracována AI - jak na zařízení (CoreML/EdgeML), tak na backendu (Gaussian Splatting, neuronové sítě) - a výsledný 3D model lze exportovat v různých formátech.

## Core Pipeline

```
LiDAR + Kamera  →  Point Cloud + Mesh  →  AI Enhancement  →  Export
   (CAPTURE)          (PROCESS)            (REFINE)          (OUTPUT)
     Edge               Edge              Backend/Edge         Edge
```

### Detailně

1. **CAPTURE** (iPhone) - LiDAR senzor (256x192 @ 60Hz, dTOF) + RGB kamera, ARKit mesh reconstruction (TSDF + Marching Cubes)
2. **PROCESS** (iPhone) - Point cloud extraction, depth map fusion, mesh anchor processing
3. **REFINE** (Backend) - Depth Anything V2, Poisson reconstruction, Gaussian Splatting, texture baking
4. **OUTPUT** (iPhone) - Export do OBJ, GLB, PLY (USDZ zatím nefunkční)

## Architektura

```
┌─────────────────────────────────────────────────────┐
│                    iOS App (SwiftUI)                  │
├─────────────────────────────────────────────────────┤
│  Presentation Layer                                  │
│  ├── Views (SwiftUI)                                │
│  ├── ViewModels (@Observable)                       │
│  └── Adapters (ScanningModeProtocol)                │
├─────────────────────────────────────────────────────┤
│  Service Layer                                       │
│  ├── ARKit (ARSessionManager, MeshAnchorProcessor)  │
│  ├── Camera (CameraFrameCapture, FrameSynchronizer) │
│  ├── EdgeML (DepthAnything, MeshCorrection)         │
│  ├── Rendering (Metal shaders, PointCloud, Mesh)    │
│  ├── Debug (DebugStreamService, PerformanceMonitor) │
│  ├── Measurement (Distance, Area, Volume)           │
│  ├── Network (APIClient, WebSocket, ChunkedUpload)  │
│  └── Persistence (ScanStore, ScanSessionPersistence)│
├─────────────────────────────────────────────────────┤
│  Domain Layer                                        │
│  └── Entities (ScanSession, MeshData, PointCloud)   │
└─────────────────────────────────────────────────────┘
          │                              │
          ▼                              ▼
┌──────────────────┐        ┌──────────────────────┐
│   Debug Server   │        │   Backend (FastAPI)   │
│  (debug_server.py│        │  ├── REST API         │
│   lightweight)   │        │  ├── WebSocket        │
│                  │        │  ├── Celery workers    │
│  - Raw data recv │        │  ├── AI pipeline       │
│  - Debug stream  │        │  └── Storage           │
│  - Dashboard WS  │        │                        │
└──────────────────┘        └──────────────────────┘
```

## Tech Stack

### iOS (skutečný stav)
| Technologie | Použití |
|-------------|---------|
| Swift 5.0 (projekt), SwiftUI | UI framework, veškeré views |
| ARKit 6 | LiDAR scanning, mesh reconstruction, world tracking |
| Metal | GPU rendering - point cloud, mesh, Gaussian splat |
| RealityKit | 3D preview, AR placement |
| CoreML | On-device ML inference (depth, mesh correction) |
| AVFoundation | Camera frame capture |
| Combine | Reactive streams (Publishers v services) |
| @Observable | State management (iOS 17+) |

### Backend (skutečný stav)
| Technologie | Použití |
|-------------|---------|
| Python 3.11, FastAPI | REST API + WebSocket server |
| Celery + Redis | Background task processing |
| PyTorch | Neural network inference |
| Depth Anything V2 | AI depth enhancement |
| Open3D | Point cloud processing, Poisson reconstruction |
| trimesh | Mesh processing, export |
| Jinja2 | Debug dashboard templates |

### Komunikace
| Kanál | Protokol | Účel |
|-------|----------|------|
| REST API | HTTPS (port 8444) | Scan CRUD, upload, processing |
| WebSocket | WSS (port 8444) | Real-time debug stream |
| Tailscale | VPN mesh | Dev konektivita iPhone ↔ Mac/Server |
| LRAW | Custom binary | Raw scan data transfer |

## Tři skenovací režimy

1. **LiDAR Scanning** - ARWorldTrackingConfiguration + scene reconstruction, primární režim
2. **Object Capture** - Apple ObjectCaptureSession pro izolované objekty
3. **RoomPlan** - Apple RoomCaptureSession pro interiéry s výstupem CapturedRoom

Každý režim implementuje `ScanningModeProtocol` přes Adapter pattern:
- `LiDARScanningModeAdapter`
- `ObjectCaptureScanningModeAdapter`
- `RoomPlanScanningModeAdapter`

## Klíčové entity

| Entita | Soubor | Popis |
|--------|--------|-------|
| `ScanSession` | Domain/Entities/ | Skenovací relace - stav, metadata, konfigurace |
| `ScanModel` | Domain/Entities/ | Uložený 3D model - název, cesta, formát, thumbnail |
| `MeshData` | Domain/Entities/ | Vertices, normals, faces, classifications |
| `PointCloud` | Domain/Entities/ | 3D body s barvami a normálami |
| `ScanMode` | Domain/Entities/ | Enum: lidar, objectCapture, roomPlan |
