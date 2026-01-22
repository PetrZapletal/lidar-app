"""
Minimal Debug Server

Lightweight server for testing debug pipeline without heavy 3D dependencies.
Run with: python debug_server.py
"""

import os
import json
import uuid
import struct
from datetime import datetime
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

# Initialize FastAPI
app = FastAPI(
    title="LiDAR Debug Server",
    description="Minimal debug server for raw data upload testing",
    version="1.0.0"
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Storage
DATA_DIR = Path("./debug_data")
DATA_DIR.mkdir(parents=True, exist_ok=True)

SCANS_METADATA = {}
DEBUG_EVENTS = {}
DEBUG_CONNECTIONS = {}


# ============================================================================
# Data Models
# ============================================================================

class RawScanInit(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    device_id: str
    device_model: Optional[str] = None
    ios_version: Optional[str] = None


# ============================================================================
# Health Endpoints
# ============================================================================

@app.get("/")
async def root():
    return {"status": "healthy", "service": "LiDAR Debug Server", "version": "1.0.0"}


@app.get("/health")
async def health():
    return {"status": "healthy", "service": "LiDAR Debug Server", "version": "1.0.0"}


# ============================================================================
# Raw Data Upload Endpoints
# ============================================================================

@app.post("/api/v1/debug/scans/raw/init")
async def init_raw_scan(request: RawScanInit):
    """Initialize raw scan upload"""
    scan_id = str(uuid.uuid4())

    scan_data = {
        "id": scan_id,
        "name": request.name,
        "device_id": request.device_id,
        "device_model": request.device_model,
        "ios_version": request.ios_version,
        "type": "raw",
        "status": "initialized",
        "created_at": datetime.utcnow().isoformat(),
        "updated_at": datetime.utcnow().isoformat(),
        "chunks_received": 0,
        "total_bytes": 0
    }

    # Create directory
    scan_dir = DATA_DIR / "raw_scans" / scan_id
    scan_dir.mkdir(parents=True, exist_ok=True)

    SCANS_METADATA[scan_id] = scan_data

    print(f"[INIT] Raw scan: {scan_id} from {request.device_id}")

    return {
        "scan_id": scan_id,
        "status": "initialized",
        "upload_url": f"/api/v1/debug/scans/{scan_id}/raw/chunk"
    }


@app.put("/api/v1/debug/scans/{scan_id}/raw/chunk")
async def upload_chunk(scan_id: str, request: Request):
    """Upload chunk of raw data"""
    if scan_id not in SCANS_METADATA:
        raise HTTPException(status_code=404, detail="Scan not found")

    chunk_index = int(request.headers.get("X-Chunk-Index", "0"))
    is_last = request.headers.get("X-Is-Last-Chunk", "false").lower() == "true"

    chunk_data = await request.body()

    # Save chunk
    scan_dir = DATA_DIR / "raw_scans" / scan_id
    chunk_path = scan_dir / f"chunk_{chunk_index:06d}.bin"

    with open(chunk_path, "wb") as f:
        f.write(chunk_data)

    # Update metadata
    scan_data = SCANS_METADATA[scan_id]
    scan_data["chunks_received"] = scan_data.get("chunks_received", 0) + 1
    scan_data["total_bytes"] = scan_data.get("total_bytes", 0) + len(chunk_data)
    scan_data["updated_at"] = datetime.utcnow().isoformat()

    if is_last:
        scan_data["status"] = "chunks_complete"

    print(f"[CHUNK] Scan {scan_id}: chunk {chunk_index}, {len(chunk_data)} bytes, last={is_last}")

    return {
        "status": "chunk_received",
        "chunk_index": chunk_index,
        "bytes_received": len(chunk_data),
        "is_last": is_last
    }


@app.put("/api/v1/debug/scans/{scan_id}/metadata")
async def upload_metadata(scan_id: str, request: Request):
    """Upload metadata"""
    if scan_id not in SCANS_METADATA:
        raise HTTPException(status_code=404, detail="Scan not found")

    metadata = await request.json()

    scan_dir = DATA_DIR / "raw_scans" / scan_id
    with open(scan_dir / "metadata.json", "w") as f:
        json.dump(metadata, f, indent=2)

    SCANS_METADATA[scan_id]["metadata"] = metadata

    print(f"[META] Scan {scan_id}: metadata saved")

    return {"status": "metadata_saved"}


@app.post("/api/v1/debug/scans/{scan_id}/raw/finalize")
async def finalize_upload(scan_id: str):
    """Finalize and validate upload"""
    if scan_id not in SCANS_METADATA:
        raise HTTPException(status_code=404, detail="Scan not found")

    scan_data = SCANS_METADATA[scan_id]
    scan_dir = DATA_DIR / "raw_scans" / scan_id

    # Reassemble chunks
    output_path = scan_dir / "raw_data.lraw"
    chunk_files = sorted(scan_dir.glob("chunk_*.bin"))

    total_size = 0
    with open(output_path, "wb") as output:
        for chunk_path in chunk_files:
            with open(chunk_path, "rb") as chunk:
                data = chunk.read()
                output.write(data)
                total_size += len(data)

    # Validate LRAW
    validation = validate_lraw(output_path)

    # Clean up chunks
    for chunk_path in chunk_files:
        chunk_path.unlink()

    scan_data["status"] = "uploaded"
    scan_data["raw_file"] = str(output_path)
    scan_data["validation"] = validation

    print(f"[FINAL] Scan {scan_id}: {total_size} bytes, validation={validation}")

    return {
        "status": "finalized",
        "scan_id": scan_id,
        "total_bytes": total_size,
        "validation": validation
    }


def validate_lraw(file_path: Path) -> dict:
    """Validate LRAW format"""
    try:
        with open(file_path, "rb") as f:
            header = f.read(32)

            if len(header) < 32:
                return {"valid": False, "error": "Header too short"}

            magic = header[0:4]
            if magic != b"LRAW":
                return {"valid": False, "error": f"Invalid magic: {magic}"}

            version = struct.unpack("<H", header[4:6])[0]
            flags = struct.unpack("<H", header[6:8])[0]
            mesh_count = struct.unpack("<I", header[8:12])[0]
            texture_count = struct.unpack("<I", header[12:16])[0]
            depth_count = struct.unpack("<I", header[16:20])[0]

            return {
                "valid": True,
                "version": version,
                "flags": flags,
                "mesh_anchor_count": mesh_count,
                "texture_frame_count": texture_count,
                "depth_frame_count": depth_count,
                "file_size": file_path.stat().st_size
            }
    except Exception as e:
        return {"valid": False, "error": str(e)}


@app.get("/api/v1/debug/scans/{scan_id}/raw/status")
async def get_scan_status(scan_id: str):
    """Get scan status"""
    if scan_id not in SCANS_METADATA:
        raise HTTPException(status_code=404, detail="Scan not found")

    scan_data = SCANS_METADATA[scan_id]
    return {
        "scan_id": scan_id,
        "status": scan_data.get("status"),
        "chunks_received": scan_data.get("chunks_received", 0),
        "total_bytes": scan_data.get("total_bytes", 0),
        "validation": scan_data.get("validation"),
        "created_at": scan_data.get("created_at"),
        "updated_at": scan_data.get("updated_at")
    }


# ============================================================================
# Debug Stream Endpoints
# ============================================================================

@app.websocket("/api/v1/debug/stream/{device_id}")
async def debug_stream(websocket: WebSocket, device_id: str):
    """WebSocket for debug streaming"""
    await websocket.accept()

    if device_id not in DEBUG_CONNECTIONS:
        DEBUG_CONNECTIONS[device_id] = []
    DEBUG_CONNECTIONS[device_id].append(websocket)

    print(f"[WS] Connected: {device_id}")

    try:
        while True:
            data = await websocket.receive_json()

            if device_id not in DEBUG_EVENTS:
                DEBUG_EVENTS[device_id] = []

            DEBUG_EVENTS[device_id].append({
                **data,
                "received_at": datetime.utcnow().isoformat()
            })

            # Limit buffer
            if len(DEBUG_EVENTS[device_id]) > 10000:
                DEBUG_EVENTS[device_id] = DEBUG_EVENTS[device_id][-5000:]

            await websocket.send_json({"ack": data.get("id", "unknown")})

    except WebSocketDisconnect:
        DEBUG_CONNECTIONS[device_id].remove(websocket)
        print(f"[WS] Disconnected: {device_id}")


@app.post("/api/v1/debug/events/{device_id}")
async def receive_events(device_id: str, request: Request):
    """Batch receive debug events"""
    events = await request.json()

    if device_id not in DEBUG_EVENTS:
        DEBUG_EVENTS[device_id] = []

    for event in events:
        DEBUG_EVENTS[device_id].append({
            **event,
            "received_at": datetime.utcnow().isoformat()
        })

    if len(DEBUG_EVENTS[device_id]) > 10000:
        DEBUG_EVENTS[device_id] = DEBUG_EVENTS[device_id][-5000:]

    print(f"[BATCH] {device_id}: {len(events)} events")

    return {"status": "received", "count": len(events)}


@app.get("/api/v1/debug/events/{device_id}")
async def get_events(device_id: str, limit: int = 100):
    """Get buffered events"""
    events = DEBUG_EVENTS.get(device_id, [])
    return {
        "device_id": device_id,
        "events": events[-limit:],
        "total_buffered": len(events)
    }


@app.get("/api/v1/debug/health")
async def debug_health():
    """Debug health check"""
    return {
        "status": "healthy",
        "active_streams": len(DEBUG_CONNECTIONS),
        "buffered_devices": len(DEBUG_EVENTS),
        "scans": len(SCANS_METADATA)
    }


# ============================================================================
# Crash Reports
# ============================================================================

CRASH_REPORTS = []
CRASH_REPORTS_DIR = DATA_DIR / "crashes"
CRASH_REPORTS_DIR.mkdir(parents=True, exist_ok=True)


class CrashReport(BaseModel):
    device_id: str
    app_version: str
    build_number: str
    ios_version: str
    device_model: str
    crash_type: str
    error_message: str
    stack_trace: Optional[str] = None
    user_info: Optional[dict] = None
    timestamp: str


@app.post("/api/v1/debug/crashes")
async def receive_crash_report(report: CrashReport):
    """Receive crash report from iOS app"""
    crash_id = str(uuid.uuid4())[:8]

    crash_data = {
        "id": crash_id,
        **report.dict(),
        "received_at": datetime.utcnow().isoformat()
    }

    CRASH_REPORTS.append(crash_data)

    # Save to file
    crash_file = CRASH_REPORTS_DIR / f"crash_{crash_id}_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.json"
    with open(crash_file, "w") as f:
        json.dump(crash_data, f, indent=2)

    print(f"\n{'='*60}")
    print(f"🚨 CRASH REPORT RECEIVED - {crash_id}")
    print(f"{'='*60}")
    print(f"Device: {report.device_model} ({report.device_id[:8]}...)")
    print(f"App: {report.app_version} ({report.build_number})")
    print(f"iOS: {report.ios_version}")
    print(f"Type: {report.crash_type}")
    print(f"Error: {report.error_message}")
    if report.stack_trace:
        print(f"\nStack Trace:")
        print(report.stack_trace[:500])
        if len(report.stack_trace) > 500:
            print(f"... ({len(report.stack_trace)} chars total)")
    print(f"{'='*60}\n")

    return {"status": "received", "crash_id": crash_id}


@app.get("/api/v1/debug/crashes")
async def list_crashes(limit: int = 50):
    """List recent crash reports"""
    return {
        "crashes": CRASH_REPORTS[-limit:],
        "total": len(CRASH_REPORTS)
    }


@app.get("/api/v1/debug/crashes/{crash_id}")
async def get_crash(crash_id: str):
    """Get specific crash report"""
    for crash in CRASH_REPORTS:
        if crash["id"] == crash_id:
            return crash
    raise HTTPException(status_code=404, detail="Crash report not found")


# ============================================================================
# Admin Endpoints
# ============================================================================

@app.get("/api/v1/debug/scans")
async def list_scans():
    """List all scans"""
    return {
        "scans": list(SCANS_METADATA.values()),
        "count": len(SCANS_METADATA)
    }


if __name__ == "__main__":
    import uvicorn
    import sys

    # Check for HTTPS mode
    use_https = "--https" in sys.argv or "-s" in sys.argv
    port = 8443 if use_https else 8002

    print("=" * 60)
    print("LiDAR Debug Server")
    print("=" * 60)
    print(f"Mode: {'HTTPS' if use_https else 'HTTP'}")
    print(f"Port: {port}")
    print(f"Data directory: {DATA_DIR.absolute()}")
    print()
    print("Endpoints:")
    print("  GET  /health                              - Health check")
    print("  POST /api/v1/debug/scans/raw/init         - Init upload")
    print("  PUT  /api/v1/debug/scans/{id}/raw/chunk   - Upload chunk")
    print("  POST /api/v1/debug/scans/{id}/raw/finalize- Finalize")
    print("  WS   /api/v1/debug/stream/{device_id}     - Debug stream")
    print("  POST /api/v1/debug/events/{device_id}     - Batch events")
    print("=" * 60)

    if use_https:
        uvicorn.run(
            app,
            host="0.0.0.0",
            port=port,
            log_level="info",
            ssl_keyfile="certs/key.pem",
            ssl_certfile="certs/cert.pem"
        )
    else:
        uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")
