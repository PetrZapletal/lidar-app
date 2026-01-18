# LiDAR 3D Scanner - Backend

Backend služba pro AI-powered zpracování 3D skenů.

## Architektura

```
┌─────────────────────────────────────────────────────────────────┐
│                         FastAPI Server                           │
├─────────────────────────────────────────────────────────────────┤
│  REST API          WebSocket           Background Tasks          │
│  /api/v1/*         /ws/scans/*         Celery Workers           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Processing Pipeline                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Preprocessing (10%)                                         │
│     └── Point cloud cleanup, normalization, outlier removal     │
│                                                                 │
│  2. 3D Gaussian Splatting (40%)                                 │
│     └── Initialize → Train → Densify → Prune                   │
│                                                                 │
│  3. SuGaR Mesh Extraction (25%)                                 │
│     └── Surface alignment → Poisson reconstruction              │
│                                                                 │
│  4. Texture Baking (15%)                                        │
│     └── UV unwrap → View selection → Projection → Blending     │
│                                                                 │
│  5. Export (10%)                                                │
│     └── USDZ, glTF, OBJ, STL, PLY                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Rychlý start

### Docker (doporučeno)

```bash
# Spustit všechny služby
docker-compose up -d

# Zobrazit logy
docker-compose logs -f api

# Zastavit
docker-compose down
```

### Lokální instalace

```bash
# Vytvořit virtuální prostředí
python -m venv venv
source venv/bin/activate  # Linux/Mac
# nebo: venv\Scripts\activate  # Windows

# Nainstalovat závislosti
pip install -r requirements.txt

# Spustit server
uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
```

## API Dokumentace

Po spuštění serveru je dostupná na:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

### Příklady

#### Vytvořit scan
```bash
curl -X POST http://localhost:8000/api/v1/scans \
  -H "Content-Type: application/json" \
  -d '{"name": "Můj scan", "description": "Test scan"}'
```

#### Upload dat
```bash
curl -X POST http://localhost:8000/api/v1/scans/{scan_id}/upload \
  -F "pointcloud=@scan.ply" \
  -F "metadata=@metadata.json"
```

#### Spustit zpracování
```bash
curl -X POST http://localhost:8000/api/v1/scans/{scan_id}/process \
  -H "Content-Type: application/json" \
  -d '{
    "enable_gaussian_splatting": true,
    "enable_mesh_extraction": true,
    "mesh_resolution": "high",
    "output_formats": ["usdz", "gltf", "obj"]
  }'
```

#### WebSocket pro real-time status
```javascript
const ws = new WebSocket('ws://localhost:8000/ws/scans/{scan_id}');
ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log(`Progress: ${data.data.progress * 100}%`);
  console.log(`Stage: ${data.data.stage}`);
};
```

## Konfigurace

### Environment proměnné

| Proměnná | Popis | Default |
|----------|-------|---------|
| `ENVIRONMENT` | development/production | development |
| `LOG_LEVEL` | DEBUG/INFO/WARNING/ERROR | INFO |
| `REDIS_URL` | Redis connection URL | redis://localhost:6379 |
| `DATA_DIR` | Adresář pro scan data | /data/scans |
| `S3_BUCKET` | S3 bucket pro storage | - |
| `S3_ENDPOINT` | S3 endpoint URL | - |

### GPU Requirements

Pro 3D Gaussian Splatting je vyžadována NVIDIA GPU s CUDA:

```bash
# Ověřit CUDA
nvidia-smi

# Nainstalovat PyTorch s CUDA
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
```

## Struktura

```
backend/
├── api/
│   ├── __init__.py
│   └── main.py                 # FastAPI app, routes
│
├── services/
│   ├── __init__.py
│   ├── scan_processor.py       # Main processing orchestrator
│   ├── gaussian_splatting.py   # 3DGS training
│   ├── sugar_mesh.py           # Mesh extraction
│   ├── texture_baker.py        # UV + textures
│   ├── export_service.py       # Multi-format export
│   ├── storage.py              # File storage
│   └── websocket_manager.py    # WS connections
│
├── utils/
│   ├── __init__.py
│   └── logger.py               # Structured logging
│
├── models/
│   └── __init__.py
│
├── requirements.txt
├── Dockerfile
└── docker-compose.yml
```

## Testování

```bash
# Spustit testy
pytest tests/ -v

# S coverage
pytest tests/ --cov=services --cov-report=html
```

## Monitoring

### Health check
```bash
curl http://localhost:8000/
# {"status": "healthy", "service": "LiDAR 3D Scanner API", "version": "1.0.0"}
```

### Prometheus metrics
```bash
curl http://localhost:8000/metrics
```

## Troubleshooting

### CUDA out of memory
- Snížit `mesh_resolution` na "medium" nebo "low"
- Snížit `texture_resolution` na 2048

### Slow processing
- Ověřit, že GPU je dostupná: `nvidia-smi`
- Zkontrolovat Docker GPU support: `docker run --gpus all nvidia/cuda:12.1.1-base nvidia-smi`

### Upload fails
- Zkontrolovat dostupné místo na disku
- Ověřit permissions na DATA_DIR
