# LiDAR Backend - Development Guide

> **FINÁLNÍ KONFIGURACE** - Toto nastavení je ověřené a funkční. Neměnit bez důvodu.

## Quick Start (Apple Silicon M1/M2/M3)

```bash
cd backend
docker compose -f docker-compose.dev.yml up -d --build
```

**DŮLEŽITÉ:** Používat **vždy** `docker-compose.dev.yml` (bez CUDA). Nikdy `docker-compose.yml` na Apple Silicon!

## Architecture

```
┌────────────────────────┐          ┌─────────────────────────────────────┐
│   iPhone (iOS App)     │          │   Mac (Apple Silicon M1/M2)         │
│                        │          │                                     │
│  ┌──────────────────┐  │  HTTPS   │  ┌───────────────────────────────┐  │
│  │  APIClient       │──┼──────────┼─▶│  Docker (docker-compose.dev)  │  │
│  │  WebSocketService│  │  :8444   │  │                               │  │
│  └──────────────────┘  │          │  │  ┌─────────────────────────┐  │  │
│                        │          │  │  │  FastAPI + Uvicorn      │  │  │
│  Tailscale VPN         │          │  │  │  HTTP:8000 / HTTPS:8443 │  │  │
│  100.x.x.x             │          │  │  └───────────┬─────────────┘  │  │
└────────────────────────┘          │  │              │                │  │
                                    │  │              ▼                │  │
                                    │  │  ┌─────────────────────────┐  │  │
                                    │  │  │  Redis :6379            │  │  │
                                    │  │  └───────────┬─────────────┘  │  │
                                    │  │              │                │  │
                                    │  │              ▼                │  │
                                    │  │  ┌─────────────────────────┐  │  │
                                    │  │  │  Celery Worker          │  │  │
                                    │  │  └─────────────────────────┘  │  │
                                    │  └───────────────────────────────┘  │
                                    │                                     │
                                    │  Tailscale IP: 100.96.188.18        │
                                    └─────────────────────────────────────┘
```

## Ports

| Port | Protocol | Service | Description |
|------|----------|---------|-------------|
| 8080 | HTTP | API | REST API (local development) |
| 8444 | HTTPS | API | REST API + WebSocket (iOS via Tailscale) |
| 6379 | TCP | Redis | Message broker |

## Tailscale Configuration

iOS app connects via Tailscale network:

- **REST API:** `https://100.96.188.18:8444/api/v1`
- **WebSocket:** `wss://100.96.188.18:8444/ws`

### iOS App konfigurace (soubory s URL)

| Soubor | Účel |
|--------|------|
| `Services/Network/APIClient.swift` | REST API base URL |
| `Services/Auth/AuthService.swift` | Auth endpoints |
| `Services/Network/WebSocketService.swift` | WebSocket URL |
| `Services/Debug/DebugSettings.swift` | Debug/Raw data upload |

### Port Mapping

```
Tailscale IP:8444 → Docker Host:8444 → Container:8443
```

## Docker Files

| File | Purpose |
|------|---------|
| `docker-compose.dev.yml` | Development (Apple Silicon, no CUDA) |
| `docker-compose.yml` | Production (NVIDIA GPU required) |
| `Dockerfile.dev` | Dev image (python:3.11-slim) |
| `Dockerfile` | Prod image (nvidia/cuda) |

**Important:** Always use `docker-compose.dev.yml` on Apple Silicon!

## SSL Certificates

Located in `backend/certs/`:

```
certs/
├── cert.pem          # Server certificate
├── key.pem           # Private key
├── ca-cert.pem       # CA certificate
└── extfile.cnf       # SAN configuration
```

Subject Alternative Names (SAN):
- `IP:100.96.188.18` (Tailscale)
- `IP:127.0.0.1` (localhost)
- `DNS:localhost`

Valid until: January 2027

## API Endpoints

### Authentication (iOS)

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/auth/login` | Login (returns JWT) |
| POST | `/api/v1/auth/register` | Register new user |
| POST | `/api/v1/auth/refresh` | Refresh access token |
| POST | `/api/v1/auth/logout` | Logout |

### User

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/users/me` | Get current user |
| PUT | `/api/v1/users/me/preferences` | Update preferences |
| GET | `/api/v1/users/me/scans` | Get user's scans |

### Scans

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/scans` | Create new scan |
| GET | `/api/v1/scans` | List all scans |
| GET | `/api/v1/scans/{id}` | Get scan details |
| GET | `/api/v1/scans/{id}/status` | Get scan status |
| DELETE | `/api/v1/scans/{id}` | Delete scan |
| POST | `/api/v1/scans/{id}/process` | Start processing |
| GET | `/api/v1/scans/{id}/download` | Download result |

### Chunked Upload

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/scans/{id}/upload/init` | Initialize upload |
| PUT | `/api/v1/scans/{id}/upload/chunk` | Upload chunk |
| POST | `/api/v1/scans/{id}/upload/finalize` | Finalize upload |
| DELETE | `/api/v1/scans/{id}/upload/cancel` | Cancel upload |

### WebSocket

| Endpoint | Description |
|----------|-------------|
| `/ws` | General WebSocket (subscribe to scan updates) |
| `/ws/scans/{id}` | Scan-specific WebSocket |

## Testing

### API Test Script

```bash
# Local test
./scripts/test_api.sh

# Tailscale test
./scripts/test_api.sh 100.96.188.18 8444
```

### Manual curl tests

```bash
# Health check
curl -k https://127.0.0.1:8444/health

# Login
curl -k -X POST https://127.0.0.1:8444/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@test.com","password":"any"}'

# Create scan (with token)
curl -k -X POST https://127.0.0.1:8444/api/v1/scans \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{"name":"Test","device_info":{"model":"iPhone","os_version":"17","has_lidar":true}}'
```

## Logs

```bash
# All containers
docker compose -f docker-compose.dev.yml logs -f

# API only
docker logs -f backend-api-1

# Worker only
docker logs -f backend-worker-1
```

## Troubleshooting

### HTTPS not working

1. Check certificate mount: `docker exec backend-api-1 ls -la /app/certs/`
2. Check uvicorn logs: `docker logs backend-api-1`
3. Verify SAN includes your IP in `certs/extfile.cnf`

### Connection refused from iOS

1. Verify Tailscale is connected on both devices
2. Check port 8444 is exposed: `docker ps`
3. Test from Mac: `curl -k https://100.96.188.18:8444/health`

### 404 on auth endpoints

Ensure `ios_auth.py` router is registered in `main.py`:
```python
from api.ios_auth import router as ios_auth_router
app.include_router(ios_auth_router)
```

## Development Notes

- Auth is **mock-only** - accepts any credentials, returns test user
- JWT tokens are real but not persisted (in-memory)
- Chunked uploads stored in-memory (not Redis) - for testing only
