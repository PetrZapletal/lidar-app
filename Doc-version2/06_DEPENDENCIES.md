# 06 - Zavislosti projektu

> Aktualni stav zavislosti iOS aplikace a Python backendu. Overeno primo ze zdrojovych souboru (`project.pbxproj`, `requirements.txt`).

---

## iOS aplikace

### Systemove frameworky Apple

Pouzite frameworky zjisteny analyzi `import` deklaraci v celem projektu:

| Framework | Pouziti |
|-----------|---------|
| **ARKit** | LiDAR skenovani, depth mapy, mesh anchory, AR sessions |
| **RealityKit** | 3D renderovani, Object Capture, AR vizualizace |
| **Metal** | GPU rendering, point cloud vizualizace, compute shadery |
| **MetalKit** | Metal view integrace, render pipeline |
| **CoreML** | On-device ML modely (Depth Anything, mesh korekce) |
| **Vision** | Vizualni analyza, integrace s CoreML |
| **RoomPlan** | Skenovani mistnosti (RoomPlanService) |
| **SceneKit** | 3D preview, mereni, galerie modelu |
| **AVFoundation** | Kamera, frame capture, audio/video |
| **CoreImage** | Zpracovani obrazu, depth map filtrovani |
| **Accelerate** | Vektorove/matricove operace, optimalizace vypoctu |
| **Combine** | Reaktivni programovani, data binding |
| **SwiftUI** | UI framework, vsechny views |
| **UIKit** | Systemova integrace, device info, sdileni |
| **Foundation** | Zakladni typy, networking, file system |
| **os.log** | Strukturovane logovani (DebugLogger) |

### Treti strany (Swift Package Manager)

Definovano v `LidarAPP.xcodeproj/project.pbxproj`:

| Balicek | Repository | Verze | Strategie aktualizace | Pouziti |
|---------|-----------|-------|----------------------|---------|
| **MetalSplatter** | `github.com/scier/MetalSplatter` | >= 0.1.0 | Up to Next Minor | Renderovani 3D Gaussian Splatting modelu |
| **sentry-cocoa** | `github.com/getsentry/sentry-cocoa` | >= 8.0.0 | Up to Next Major | Crash reporting, error tracking, performance monitoring |

Produkty z SPM balicku:
- `MetalSplatter` - hlavni renderovaci knihovna
- `Sentry` - core SDK pro crash reporting
- `SentrySwiftUI` - SwiftUI integrace pro Sentry

> **Poznamka:** Stare dokumenty (`CLAUDE.md`) uvadeji Alamofire, Realm, Lottie a RevenueCat jako zavislosti. Tyto balicky v projektu **nejsou** a nikdy nebyly v `project.pbxproj` definovany. Networking je resen nativne pres `URLSession` (`APIClient.swift`), lokalni uloziste pres `FileManager` (`ScanStore.swift`), animace pres SwiftUI.

---

## Python backend

### Zavislosti (requirements.txt)

#### Webovy framework a server

| Balicek | Verze | Popis |
|---------|-------|-------|
| `fastapi` | >= 0.109.0 | Hlavni webovy framework (REST API + WebSocket) |
| `uvicorn[standard]` | >= 0.27.0 | ASGI server (HTTP + HTTPS) |
| `python-multipart` | >= 0.0.6 | Zpracovani multipart/form-data uploadu |
| `websockets` | >= 12.0 | WebSocket podpora |
| `jinja2` | >= 3.1.0 | Template engine (debug UI) |

#### AWS / Uloziste

| Balicek | Verze | Popis |
|---------|-------|-------|
| `boto3` | >= 1.34.0 | AWS SDK (S3 kompatibilni uloziste) |
| `aiofiles` | >= 23.2.0 | Asynchronni operace se soubory |

#### Fronta uloh

| Balicek | Verze | Popis |
|---------|-------|-------|
| `celery[redis]` | >= 5.3.0 | Distribuovana fronta uloh pro AI zpracovani |
| `redis` | >= 5.0.0 | Redis klient (cache + message broker) |

#### 3D zpracovani

| Balicek | Verze | Popis |
|---------|-------|-------|
| `numpy` | >= 1.26.0 | Numericke vypocty, pole, matice |
| `scipy` | >= 1.12.0 | Vedecke vypocty, optimalizace |
| `trimesh` | >= 4.0.0 | Zpracovani 3D meshi |
| `open3d` | >= 0.18.0 | Point cloud zpracovani, registrace |
| `plyfile` | >= 1.0.0 | Cteni/zapis PLY souboru |

#### PyTorch (3DGS a SuGaR)

| Balicek | Verze | Popis |
|---------|-------|-------|
| `torch` | >= 2.1.0 | PyTorch framework pro deep learning |
| `torchvision` | >= 0.16.0 | Modely a transformace pro pocitacove videni |

#### HuggingFace (Depth Anything V2)

| Balicek | Verze | Popis |
|---------|-------|-------|
| `transformers` | >= 4.35.0 | HuggingFace modely (Depth Anything V2) |
| `accelerate` | >= 0.24.0 | Optimalizace inference a trenink |

#### Zpracovani obrazu

| Balicek | Verze | Popis |
|---------|-------|-------|
| `Pillow` | >= 10.2.0 | Zpracovani obrazu |
| `opencv-python` | >= 4.9.0 | Pocitacove videni (OpenCV) |
| `imageio` | >= 2.33.0 | Cteni/zapis obrazovych formatu |

#### Zpracovani meshi

| Balicek | Verze | Popis |
|---------|-------|-------|
| `xatlas` | >= 0.0.8 | UV unwrapping pro textury |
| `pymeshlab` | >= 2023.12 | MeshLab operace (decimace, vycisteni) |

#### Monitoring

| Balicek | Verze | Popis |
|---------|-------|-------|
| `prometheus-client` | >= 0.19.0 | Prometheus metriky |
| `psutil` | >= 5.9.0 | Systemove metriky (CPU, RAM, disk) |

#### Utility

| Balicek | Verze | Popis |
|---------|-------|-------|
| `pydantic` | >= 2.5.0 | Validace dat, serialializace, API modely |
| `python-dotenv` | >= 1.0.0 | Nacitani .env promennych prostredi |
| `tqdm` | >= 4.66.0 | Progress bary pro CLI |
| `structlog` | >= 24.1.0 | Strukturovane logovani |

#### Specialni zavislosti (instalace z GitHubu)

Tyto balicky nejsou v `requirements.txt` primo, ale jsou pozadovany pro 3D Gaussian Splatting:

- `diff-gaussian-rasterization` - z `github.com/graphdeco-inria/gaussian-splatting`
- `simple-knn` - z `github.com/graphdeco-inria/gaussian-splatting`

> Instaluji se manualne z repozitare, protoze vyzaduji CUDA kompilaci.

---

## Infrastrukturni zavislosti

### Docker

| Sluzba | Image | Popis |
|--------|-------|-------|
| **API server (dev)** | `python:3.11-slim` | Development bez CUDA (Dockerfile.dev) |
| **API server (prod)** | `nvidia/cuda:12.1.1-runtime-ubuntu22.04` | Produkce s CUDA GPU (Dockerfile) |
| **Redis** | `redis:7-alpine` | Message broker + cache |
| **MinIO** | `minio/minio` | S3-kompatibilni uloziste (volitelne, profil `storage`) |
| **Celery Worker** | Sdileny s API serverem | Background zpracovani uloh |

### Systemove pozadavky backendu

- Python 3.11
- CUDA 12.1+ (pouze produkce, pro GPU akceleraci)
- Redis 7+
- SSL certifikaty v `backend/certs/` (pro HTTPS)

---

## Sprava zavislosti

### iOS - Swift Package Manager

Zavislosti jsou definovany v `LidarAPP.xcodeproj/project.pbxproj` v sekci `XCRemoteSwiftPackageReference`. Xcode je automaticky resolvuje pri otevreni projektu.

```bash
# Resolve SPM zavislosti
xcodebuild -resolvePackageDependencies \
  -project LidarAPP/LidarAPP.xcodeproj \
  -scheme LidarAPP
```

### Backend - pip

```bash
# Instalace zavislosti
cd backend
pip install -r requirements.txt

# Nebo v Docker kontejneru (doporuceno)
docker compose -f docker-compose.dev.yml up -d --build
```
