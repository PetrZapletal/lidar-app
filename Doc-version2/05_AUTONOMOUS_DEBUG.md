# 05 - Autonomní Debug s Real-Time iOS Log Streamem

## Přehled

Projekt má **dvě debug pipeline** pro autonomní debugging bez Xcode GUI:

```
Pipeline 1: Debug Event Stream (real-time telemetrie)
  iOS App → WebSocket/HTTP → Backend → Dashboard/CLI → Claude Code

Pipeline 2: Raw Data Upload (binární data pro offline analýzu)
  iOS App → LRAW binary → Chunked Upload → Backend → Processing
```

Obě pipeline jsou již implementovány a propojeny přes Tailscale VPN.

---

## Pipeline 1: Debug Event Stream

### Architektura

```
┌─────────────────────────────────────────────────────────────┐
│                        iOS App                               │
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌───────────────┐  │
│  │ DebugLogger  │───→│DebugStream   │───→│  WebSocket    │  │
│  │ (OSLog +     │    │Service       │    │  / HTTP Batch │  │
│  │  buffer)     │    │ (singleton)  │    │               │  │
│  └──────────────┘    └──────────────┘    └───────┬───────┘  │
│         ↑                    ↑                    │          │
│  ┌──────────────┐    ┌──────────────┐            │          │
│  │ Performance  │───→│ DebugSettings│            │          │
│  │ Monitor      │    │ (@AppStorage)│            │          │
│  │ (FPS,CPU,RAM)│    └──────────────┘            │          │
│  └──────────────┘                                │          │
└──────────────────────────────────────────────────┼──────────┘
                                                   │
                        Tailscale VPN              │
                                                   │
┌──────────────────────────────────────────────────┼──────────┐
│                     Backend                       │          │
│                                                   ▼          │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              api/debug.py                                ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌────────────────┐  ││
│  │  │ WS endpoint │  │ Batch HTTP  │  │ Dashboard WS   │  ││
│  │  │ /stream/    │  │ /events/    │  │ /dashboard/ws/ │  ││
│  │  │ {device_id} │  │ {device_id} │  │ {device_id}    │  ││
│  │  └──────┬──────┘  └──────┬──────┘  └───────┬────────┘  ││
│  │         │                │                  │           ││
│  │         └────────┬───────┘                  │           ││
│  │                  ▼                          │           ││
│  │  ┌──────────────────────┐    ┌──────────────┘           ││
│  │  │ In-memory buffer     │───→│ broadcast_to_dashboard() ││
│  │  │ (10K events/device)  │    │                          ││
│  │  └──────────────────────┘    └──────────────────────────┘│
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Debug Dashboard (HTML/JS)                                ││
│  │ GET /api/v1/debug/dashboard                              ││
│  │ - Real-time event feed                                   ││
│  │ - Performance grafy                                      ││
│  │ - Device list                                            ││
│  └─────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────┘
```

### iOS komponenty

| Soubor | Třída | Účel |
|--------|-------|------|
| `Services/Debug/DebugLogger.swift` | `DebugLogger` | Centrální logger - OSLog + in-memory buffer (2000 entries) + forwarding |
| `Services/Debug/DebugStreamService.swift` | `DebugStreamService` | Singleton - streamuje eventy přes WS nebo HTTP batch |
| `Services/Debug/DebugSettings.swift` | `DebugSettings` | @AppStorage konfigurace - IP, port, mode, categories |
| `Services/Debug/PerformanceMonitor.swift` | `PerformanceMonitor` | Real-time FPS (CADisplayLink), CPU, RAM, thermal, battery |
| `Presentation/Scanning/Views/DebugLogOverlay.swift` | `DebugLogOverlay` | SwiftUI overlay - posledních 10 logů přímo na scanning view |

### Event kategorie

```swift
enum DebugCategory: String {
    case appState      // UI state, view transitions, button taps
    case performance   // FPS, CPU, RAM, thermal, battery
    case arSession     // Tracking state, mesh anchors, relocalization
    case processing    // Pipeline timing, frame processing
    case network       // API calls, WebSocket events
    case logs          // Application log entries
}
```

### Konfigurace (DebugSettings)

| Setting | Default | Popis |
|---------|---------|-------|
| `debugStreamEnabled` | `true` | Master switch |
| `debugStreamServerIP` | `100.96.188.18` | Tailscale IP backendu |
| `debugStreamPort` | `8444` | HTTPS port (Docker mapuje na 8443) |
| `debugStreamMode` | `"batch"` | `"realtime"` (WebSocket) nebo `"batch"` (HTTP) |
| `batchInterval` | `5.0` | Sekundy mezi batch uploady |
| `enabledCategoriesString` | `"appState,performance,arSession,processing,logs"` | Aktivní kategorie |

### Dva režimy streamování

**Realtime (WebSocket):**
```
iOS → WSS://100.96.188.18:8444/api/v1/debug/stream/{device_id}
```
- Každý event odeslán ihned
- Server potvrdí ACK
- Auto-reconnect po 5s při výpadku

**Batch (HTTP):**
```
iOS → POST https://100.96.188.18:8444/api/v1/debug/events/{device_id}
```
- Buffer na iOS (max 500 events)
- Flush každých 5 sekund
- Re-buffer při selhání

### Jak číst debug stream z CLI (pro Claude Code)

```bash
# 1. Získat seznam aktivních zařízení
curl -k https://100.96.188.18:8444/api/v1/debug/devices

# 2. Číst posledních 100 eventů ze zařízení
curl -k https://100.96.188.18:8444/api/v1/debug/events/{device_id}?limit=100

# 3. Filtrovat podle kategorie
curl -k https://100.96.188.18:8444/api/v1/debug/events/{device_id}?category=performance&limit=50

# 4. Filtrovat od času
curl -k https://100.96.188.18:8444/api/v1/debug/events/{device_id}?since=2026-02-08T12:00:00

# 5. Real-time stream přes websocat (CLI WebSocket klient)
websocat -k wss://100.96.188.18:8444/api/v1/debug/dashboard/ws/{device_id}

# 6. Health check debug systému
curl -k https://100.96.188.18:8444/api/v1/debug/health

# 7. Smazat buffer (reset)
curl -k -X DELETE https://100.96.188.18:8444/api/v1/debug/events/{device_id}
```

### Formát debug eventu (JSON)

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2026-02-08T12:30:00Z",
  "category": "performance",
  "type": "metrics",
  "data": {
    "fps": 58.5,
    "memoryUsageMB": 245,
    "availableMemoryMB": 3755,
    "cpuUsage": 42.3,
    "threadCount": 28,
    "thermalState": "nominal",
    "batteryLevel": 0.85,
    "isLowPowerMode": false
  },
  "device_id": "A1B2C3D4-...",
  "session_id": "scan_session_001",
  "received_at": "2026-02-08T12:30:00.123Z"
}
```

---

## Pipeline 2: Raw Data Upload

### LRAW binární formát

Vlastní binární formát pro přenos surových skenovacích dat:

```
Header (32 bytes):
  [0:4]   Magic: "LRAW" (4 bytes)
  [4:6]   Version: UInt16 (currently 1)
  [6:8]   Flags: UInt16 (bitfield)
  [8:12]  Mesh anchor count: UInt32
  [12:16] Texture frame count: UInt32
  [16:20] Depth frame count: UInt32
  [20:32] Reserved: 12 bytes

Mesh Anchors Section:
  Per anchor:
    UUID (16B) + Transform (64B) + Vertex count (4B) + Face count (4B)
    + Classification flag (1B)
    + Vertices [simd_float3] + Normals [simd_float3] + Faces [simd_uint3]
    + Classifications [UInt8] (optional)

Texture Frames Section:
  Per frame:
    UUID (16B) + Timestamp (8B) + Transform (64B) + Intrinsics (36B)
    + Resolution (8B) + Image data length (4B) + JPEG data

Depth Frames Section:
  Per frame:
    UUID (16B) + Timestamp (8B) + Transform (64B) + Intrinsics (36B)
    + Width/Height (8B) + Float32 depth values + UInt8 confidence (optional)
```

### Upload flow

```
1. POST /api/v1/debug/scans/raw/init          → scan_id
2. PUT  /api/v1/debug/scans/{id}/raw/chunk     → (5MB chunks, retry 3x)
3. PUT  /api/v1/debug/scans/{id}/metadata      → JSON metadata
4. POST /api/v1/debug/scans/{id}/raw/finalize  → LRAW validation
5. POST /api/v1/debug/scans/{id}/process       → trigger SimplePipeline
```

### iOS komponenty

| Soubor | Třída | Účel |
|--------|-------|------|
| `Services/Debug/RawDataPackager.swift` | `RawDataPackager` | Balí ARMeshAnchor + TextureFrame + DepthFrame do LRAW |
| `Services/Debug/RawDataUploader.swift` | `RawDataUploader` (actor) | Chunked upload s retry, exponential backoff |
| `Services/Debug/DepthFrame.swift` | `DepthFrame` | Depth frame entita s binary serializací |

---

## Autonomní Debug Workflow pro Claude Code

### Scénář: Debug scanning problému

```bash
# 1. Ověř konektivitu
curl -k https://100.96.188.18:8444/health

# 2. Zjisti připojená zařízení
curl -k https://100.96.188.18:8444/api/v1/debug/devices

# 3. Spusť polling loop pro performance metriky
while true; do
  curl -sk "https://100.96.188.18:8444/api/v1/debug/events/{device_id}?category=performance&limit=5" \
    | python3 -m json.tool
  sleep 3
done

# 4. Sleduj AR session eventy
curl -sk "https://100.96.188.18:8444/api/v1/debug/events/{device_id}?category=arSession&limit=20" \
  | python3 -m json.tool

# 5. Zkontroluj logy (errors)
curl -sk "https://100.96.188.18:8444/api/v1/debug/events/{device_id}?category=logs&limit=50" \
  | python3 -c "
import json, sys
events = json.load(sys.stdin)['events']
errors = [e for e in events if e.get('data', {}).get('level') in ('error', 'warning')]
for e in errors:
    print(f\"[{e['data'].get('level','?').upper()}] {e['data'].get('message','')}\")
"

# 6. Pokud je raw scan uploadnutý, prozkoumej data
curl -sk "https://100.96.188.18:8444/api/v1/debug/scans" | python3 -m json.tool
curl -sk "https://100.96.188.18:8444/api/v1/debug/scans/{scan_id}/raw/status"

# 7. Spusť backend processing
curl -sk -X POST "https://100.96.188.18:8444/api/v1/debug/scans/{scan_id}/process"

# 8. Prohlédni výsledný point cloud (JSON pro analýzu)
curl -sk "https://100.96.188.18:8444/api/v1/debug/scans/{scan_id}/pointcloud/preview?max_points=1000"

# 9. Porovnej iOS vs backend výsledky
curl -sk "https://100.96.188.18:8444/api/v1/debug/scans/{scan_id}/compare"
```

### Scénář: Debug crash na zařízení

```bash
# CrashReporter na iOS odesílá automaticky
curl -sk "https://100.96.188.18:8444/api/v1/debug/crashes?limit=10" | python3 -m json.tool

# Detail konkrétního crashe
curl -sk "https://100.96.188.18:8444/api/v1/debug/crashes/{crash_id}" | python3 -m json.tool
```

---

## Alternativní debug metody (bez vlastní infrastruktury)

### 1. `log stream` přes USB (macOS → iPhone)

Přímý real-time log stream z připojeného iPhonu:

```bash
# Všechny logy z aplikace
log stream --device --predicate 'subsystem == "com.lidarscanner.app"' --level debug

# Jen ARKit logy
log stream --device --predicate 'subsystem == "com.apple.arkit"' --level info

# Jen errory
log stream --device --predicate 'subsystem == "com.lidarscanner.app" AND messageType == error'

# S JSON výstupem (parsovatelný)
log stream --device --predicate 'subsystem == "com.lidarscanner.app"' --style json
```

**Požadavky:** iPhone připojený USB, macOS s Xcode command line tools.
**Pro Claude Code:** Plně použitelné z terminálu. DebugLogger v aplikaci už loguje přes `os_log` se subsystem z Bundle ID.

### 2. pymobiledevice3 (Python, bez Xcode)

```bash
pip install pymobiledevice3

# List zařízení
pymobiledevice3 usbmux list

# Syslog stream
pymobiledevice3 syslog live

# S filtrem
pymobiledevice3 syslog live --match "LidarAPP"

# Crash logy
pymobiledevice3 crash list
pymobiledevice3 crash export --all ./crashes/
```

**Pro Claude Code:** Funguje čistě z CLI, nepotřebuje Xcode. Ideální pro Linux/CI.

### 3. ios-deploy (deploy + debug z CLI)

```bash
# Install na device
ios-deploy --bundle LidarAPP.app

# Install + sleduj logy
ios-deploy --bundle LidarAPP.app --debug --noninteractive

# Jen logy (bez instalace)
ios-deploy --bundle LidarAPP.app --justlaunch --noinstall
```

### 4. xcresult analýza (testy na device)

```bash
# Spusť testy na reálném zařízení
xcodebuild test \
  -scheme LidarAPP \
  -destination 'platform=iOS,id={device_udid}' \
  -resultBundlePath ./test_results.xcresult

# Parsuj výsledky
xcrun xcresulttool get --path ./test_results.xcresult --format json
```

### 5. Metal GPU Capture (CLI)

```bash
# Environment variable pro Metal validation
export METAL_DEVICE_WRAPPER_TYPE=1
export METAL_DEBUG_ERROR_MODE=0

# Metal system trace
xctrace record --template 'Metal System Trace' \
  --device {device_udid} \
  --attach {pid} \
  --output metal_trace.trace \
  --time-limit 10s

# Parsuj trace
xctrace export --input metal_trace.trace --output metal_data
```

### 6. Network proxy pro API debug

```bash
# mitmproxy pro zachycení API komunikace
mitmproxy --mode regular --listen-port 8080

# Charles Proxy CLI
charles-cli record --port 8888

# Na iOS: nastav HTTP proxy na Mac IP:port
```

---

## Co je implementováno vs co chybí

### Implementováno (funguje)
- [x] DebugLogger s OSLog + in-memory buffer
- [x] DebugStreamService (WebSocket + HTTP batch)
- [x] PerformanceMonitor (FPS, CPU, RAM, thermal, battery)
- [x] DebugSettings s @AppStorage
- [x] RawDataPackager (LRAW formát)
- [x] RawDataUploader (chunked, retry, exponential backoff)
- [x] Backend debug endpoints (WS stream, batch, events, devices)
- [x] Backend debug dashboard (HTML/WS)
- [x] CrashReporter → backend
- [x] DebugLogOverlay (on-screen logs)
- [x] SelfSignedCertDelegate (dev HTTPS)

### Chybí / nutno doladit
- [ ] Integrace DebugLogger do VŠECH services (většina stále používá `print()`)
- [ ] AR session event tracking v ARSessionManager (logMeshAnchorEvent, logARTrackingChange)
- [ ] Network request interceptor (automatický log všech API calls)
- [ ] WebSocket dashboard relay test s reálným zařízením
- [ ] Performance alerting (automatický warning při FPS < 30, RAM > 500MB)
- [ ] Log export/share z iOS UI
- [ ] Persistent log storage na backendu (log_storage.py existuje, ale není plně integrován)
- [ ] Depth heatmap vizualizace (endpoint existuje, ale závisí na OpenCV)

---

## Doporučený debug setup pro vývoj

```
Mac (Tailscale) ←──VPN──→ iPhone (Tailscale)
     │                          │
     ├── Backend Docker          ├── LidarAPP (Debug build)
     │   port 8444               │   DebugStreamService → WS
     │                          │   RawDataUploader → HTTP
     ├── Terminal 1              │
     │   log stream --device     │
     │                          │
     ├── Terminal 2              │
     │   curl polling loop       │
     │                          │
     └── Terminal 3 (Claude Code)│
         Reads debug events      │
         Analyzes logs           │
         Modifies code           │
         Triggers rebuild        │
```

### Minimální setup

1. iPhone + Mac na stejné Tailscale síti
2. Backend running: `cd backend && python debug_server.py --https`
3. iPhone: Settings → Debug → Stream Enabled → ON
4. Claude Code: `curl -k https://100.96.188.18:8444/api/v1/debug/health`
