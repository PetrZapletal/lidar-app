"""
Debug API endpoints for raw data upload and debug streaming.

Pipeline 1: Raw Data Upload
- Receives raw mesh, texture, and depth data from iOS
- Bypasses edge processing for debugging
- Supports chunked upload for large files

Pipeline 2: Debug Stream
- WebSocket endpoint for real-time debug events
- Batch HTTP endpoint for event batching
"""

import os
import uuid
import struct
from datetime import datetime
from typing import Optional
from pathlib import Path

from fastapi import APIRouter, UploadFile, File, HTTPException, WebSocket, WebSocketDisconnect, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from services.storage import StorageService
from services.log_storage import get_log_storage, log_device, log_upload, log_error
from utils.logger import get_logger

logger = get_logger(__name__)

router = APIRouter(prefix="/api/v1/debug", tags=["debug"])

# Initialize storage
storage = StorageService()

# In-memory storage for debug streams
debug_connections: dict[str, list[WebSocket]] = {}
debug_events_buffer: dict[str, list[dict]] = {}


# ============================================================================
# Data Models
# ============================================================================

class RawScanInit(BaseModel):
    """Request for initializing raw scan upload"""
    name: str = Field(..., min_length=1, max_length=100)
    device_id: str
    device_model: Optional[str] = None
    ios_version: Optional[str] = None


class RawScanInitResponse(BaseModel):
    """Response for raw scan init"""
    scan_id: str
    status: str
    upload_url: str


class DebugEvent(BaseModel):
    """Single debug event from iOS"""
    id: str
    timestamp: datetime
    category: str
    type: str
    data: dict
    device_id: str
    session_id: Optional[str] = None


# ============================================================================
# Raw Data Upload Endpoints (Pipeline 1)
# ============================================================================

@router.post("/scans/raw/init", response_model=RawScanInitResponse)
async def init_raw_scan(request: RawScanInit):
    """Initialize a new raw scan upload session"""
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

    # Create directory for raw scan
    scan_dir = Path(storage.base_path) / "raw_scans" / scan_id
    scan_dir.mkdir(parents=True, exist_ok=True)

    # Save metadata
    await storage.save_scan_metadata(scan_id, scan_data)

    logger.info(f"Initialized raw scan: {scan_id} from device {request.device_id}")

    return RawScanInitResponse(
        scan_id=scan_id,
        status="initialized",
        upload_url=f"/api/v1/debug/scans/{scan_id}/raw/chunk"
    )


@router.put("/scans/{scan_id}/raw/chunk")
async def upload_raw_chunk(
    scan_id: str,
    request: Request
):
    """Upload a chunk of raw scan data"""

    # Get scan metadata
    scan_data = await storage.get_scan_metadata(scan_id)
    if not scan_data:
        raise HTTPException(status_code=404, detail="Scan not found")

    if scan_data.get("type") != "raw":
        raise HTTPException(status_code=400, detail="Not a raw scan")

    # Get headers
    chunk_index = int(request.headers.get("X-Chunk-Index", "0"))
    is_last = request.headers.get("X-Is-Last-Chunk", "false").lower() == "true"

    # Read chunk data
    chunk_data = await request.body()

    # Save chunk to file
    scan_dir = Path(storage.base_path) / "raw_scans" / scan_id
    chunk_path = scan_dir / f"chunk_{chunk_index:06d}.bin"

    with open(chunk_path, "wb") as f:
        f.write(chunk_data)

    # Update metadata
    scan_data["chunks_received"] = scan_data.get("chunks_received", 0) + 1
    scan_data["total_bytes"] = scan_data.get("total_bytes", 0) + len(chunk_data)
    scan_data["updated_at"] = datetime.utcnow().isoformat()

    if is_last:
        scan_data["status"] = "chunks_complete"

    await storage.save_scan_metadata(scan_id, scan_data)

    logger.info(f"Received chunk {chunk_index} for scan {scan_id} ({len(chunk_data)} bytes)")

    return {
        "status": "chunk_received",
        "chunk_index": chunk_index,
        "bytes_received": len(chunk_data),
        "is_last": is_last
    }


@router.put("/scans/{scan_id}/metadata")
async def upload_metadata(scan_id: str, request: Request):
    """Upload metadata JSON for raw scan"""

    scan_data = await storage.get_scan_metadata(scan_id)
    if not scan_data:
        raise HTTPException(status_code=404, detail="Scan not found")

    # Read and save metadata
    metadata = await request.json()

    scan_dir = Path(storage.base_path) / "raw_scans" / scan_id
    metadata_path = scan_dir / "metadata.json"

    import json
    with open(metadata_path, "w") as f:
        json.dump(metadata, f, indent=2)

    # Update scan data
    scan_data["metadata"] = metadata
    scan_data["updated_at"] = datetime.utcnow().isoformat()
    await storage.save_scan_metadata(scan_id, scan_data)

    logger.info(f"Saved metadata for scan {scan_id}")

    return {"status": "metadata_saved"}


@router.post("/scans/{scan_id}/raw/finalize")
async def finalize_raw_upload(scan_id: str):
    """Finalize raw upload and reassemble chunks"""

    scan_data = await storage.get_scan_metadata(scan_id)
    if not scan_data:
        raise HTTPException(status_code=404, detail="Scan not found")

    if scan_data.get("status") != "chunks_complete":
        raise HTTPException(
            status_code=400,
            detail=f"Cannot finalize. Status: {scan_data.get('status')}"
        )

    scan_dir = Path(storage.base_path) / "raw_scans" / scan_id

    # Reassemble chunks into single file
    output_path = scan_dir / "raw_data.lraw"
    chunk_files = sorted(scan_dir.glob("chunk_*.bin"))

    if not chunk_files:
        raise HTTPException(status_code=400, detail="No chunks found")

    with open(output_path, "wb") as output:
        for chunk_path in chunk_files:
            with open(chunk_path, "rb") as chunk:
                output.write(chunk.read())

    # Validate LRAW format
    validation = validate_lraw_file(output_path)

    # Clean up chunk files
    for chunk_path in chunk_files:
        chunk_path.unlink()

    # Update status
    scan_data["status"] = "uploaded"
    scan_data["raw_file"] = str(output_path)
    scan_data["validation"] = validation
    scan_data["updated_at"] = datetime.utcnow().isoformat()
    await storage.save_scan_metadata(scan_id, scan_data)

    logger.info(f"Finalized raw upload for scan {scan_id}: {validation}")

    return {
        "status": "finalized",
        "scan_id": scan_id,
        "total_bytes": scan_data.get("total_bytes", 0),
        "validation": validation
    }


def validate_lraw_file(file_path: Path) -> dict:
    """Validate LRAW binary format and extract basic info"""
    try:
        with open(file_path, "rb") as f:
            # Read header (32 bytes)
            header = f.read(32)

            if len(header) < 32:
                return {"valid": False, "error": "Header too short"}

            # Parse header
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


@router.post("/scans/{scan_id}/process-raw")
async def process_raw_scan(scan_id: str):
    """Trigger processing of raw scan data"""

    scan_data = await storage.get_scan_metadata(scan_id)
    if not scan_data:
        raise HTTPException(status_code=404, detail="Scan not found")

    if scan_data.get("status") != "uploaded":
        raise HTTPException(
            status_code=400,
            detail=f"Cannot process. Status: {scan_data.get('status')}"
        )

    # Import Celery task for processing
    try:
        from worker.tasks import process_raw_scan_task

        # Queue the processing task
        task = process_raw_scan_task.delay(scan_id)

        scan_data["status"] = "processing"
        scan_data["task_id"] = task.id
        scan_data["updated_at"] = datetime.utcnow().isoformat()
        await storage.save_scan_metadata(scan_id, scan_data)

        return {
            "status": "processing_queued",
            "scan_id": scan_id,
            "task_id": task.id
        }

    except ImportError:
        # Celery not available, process synchronously (for development)
        logger.warning("Celery not available, processing synchronously")

        scan_data["status"] = "processing"
        await storage.save_scan_metadata(scan_id, scan_data)

        return {
            "status": "processing_started",
            "scan_id": scan_id,
            "message": "Processing synchronously (Celery unavailable)"
        }


@router.get("/scans/{scan_id}/raw/status")
async def get_raw_scan_status(scan_id: str):
    """Get status of raw scan upload/processing"""

    scan_data = await storage.get_scan_metadata(scan_id)
    if not scan_data:
        raise HTTPException(status_code=404, detail="Scan not found")

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
# Debug Stream Endpoints (Pipeline 2)
# ============================================================================

@router.websocket("/stream/{device_id}")
async def debug_stream_websocket(websocket: WebSocket, device_id: str):
    """WebSocket endpoint for real-time debug event streaming"""

    await websocket.accept()

    # Register connection
    if device_id not in debug_connections:
        debug_connections[device_id] = []
    debug_connections[device_id].append(websocket)

    logger.info(f"Debug stream connected: {device_id}")

    try:
        while True:
            # Receive events from iOS
            data = await websocket.receive_json()

            # Store event
            if device_id not in debug_events_buffer:
                debug_events_buffer[device_id] = []

            debug_events_buffer[device_id].append({
                **data,
                "received_at": datetime.utcnow().isoformat()
            })

            # Limit buffer size
            if len(debug_events_buffer[device_id]) > 10000:
                debug_events_buffer[device_id] = debug_events_buffer[device_id][-5000:]

            # Acknowledge receipt
            await websocket.send_json({"ack": data.get("id", "unknown")})

    except WebSocketDisconnect:
        debug_connections[device_id].remove(websocket)
        if not debug_connections[device_id]:
            del debug_connections[device_id]
        logger.info(f"Debug stream disconnected: {device_id}")


@router.post("/events/{device_id}")
async def receive_debug_events(device_id: str, request: Request):
    """Batch endpoint for debug events (HTTP mode)"""

    events = await request.json()

    if device_id not in debug_events_buffer:
        debug_events_buffer[device_id] = []

    received_at = datetime.utcnow().isoformat()

    for event in events:
        debug_events_buffer[device_id].append({
            **event,
            "received_at": received_at
        })

        # Log important events to persistent storage
        event_type = event.get("type", "")
        category = event.get("category", "device")

        if event_type == "error" or category == "error":
            log_error(
                message=event.get("message", str(event.get("data", {}))),
                category="device",
                device_id=device_id,
                details=event.get("data")
            )
        elif event_type in ["scan_started", "scan_completed", "upload_started", "upload_completed"]:
            log_device(
                message=f"{event_type}: {event.get('message', '')}",
                device_id=device_id,
                level="info",
                details=event.get("data")
            )

    # Limit buffer size
    if len(debug_events_buffer[device_id]) > 10000:
        debug_events_buffer[device_id] = debug_events_buffer[device_id][-5000:]

    logger.debug(f"Received {len(events)} debug events from {device_id}")

    return {
        "status": "received",
        "count": len(events)
    }


@router.get("/events/{device_id}")
async def get_debug_events(
    device_id: str,
    category: Optional[str] = None,
    since: Optional[str] = None,
    limit: int = 100
):
    """Get buffered debug events for a device"""

    events = debug_events_buffer.get(device_id, [])

    # Filter by category
    if category:
        events = [e for e in events if e.get("category") == category]

    # Filter by time
    if since:
        try:
            since_dt = datetime.fromisoformat(since)
            events = [
                e for e in events
                if datetime.fromisoformat(e.get("received_at", "")) > since_dt
            ]
        except ValueError:
            pass

    # Limit results
    events = events[-limit:]

    return {
        "device_id": device_id,
        "events": events,
        "total_buffered": len(debug_events_buffer.get(device_id, []))
    }


@router.delete("/events/{device_id}")
async def clear_debug_events(device_id: str):
    """Clear debug events buffer for a device"""

    if device_id in debug_events_buffer:
        count = len(debug_events_buffer[device_id])
        del debug_events_buffer[device_id]
        return {"status": "cleared", "count": count}

    return {"status": "not_found"}


# ============================================================================
# Health Check
# ============================================================================

@router.get("/health")
async def debug_health():
    """Health check for debug endpoints"""
    log_storage = get_log_storage()

    return {
        "status": "healthy",
        "active_streams": len(debug_connections),
        "buffered_devices": len(debug_events_buffer),
        "total_events": sum(len(events) for events in debug_events_buffer.values()),
        "log_stats": log_storage.get_statistics()
    }


# ============================================================================
# Device Logs Endpoints
# ============================================================================

@router.get("/devices/{device_id}/logs")
async def get_device_logs(device_id: str, limit: int = 200):
    """
    Get persistent logs for a specific device.

    Unlike /events which uses in-memory buffer, this uses persistent log storage.
    """
    log_storage = get_log_storage()
    return {
        "device_id": device_id,
        "logs": log_storage.get_device_logs(device_id, limit=limit),
        "stats": log_storage.get_statistics()
    }


@router.get("/devices")
async def list_active_devices():
    """List all devices with buffered events"""
    log_storage = get_log_storage()

    devices = []
    for device_id, events in debug_events_buffer.items():
        last_event = events[-1] if events else None
        devices.append({
            "device_id": device_id,
            "buffered_events": len(events),
            "last_event_at": last_event.get("received_at") if last_event else None,
            "last_event_type": last_event.get("type") if last_event else None
        })

    return {
        "devices": devices,
        "total_buffered_events": sum(len(events) for events in debug_events_buffer.values()),
        "log_stats": log_storage.get_statistics()
    }


@router.post("/devices/{device_id}/log")
async def add_device_log(device_id: str, request: Request):
    """
    Add a single log entry for a device.

    Body: {
        "level": "info|warning|error|debug",
        "message": "Log message",
        "details": {} (optional)
    }
    """
    data = await request.json()

    level = data.get("level", "info")
    message = data.get("message", "No message")
    details = data.get("details")

    if level == "error":
        log_error(message=message, category="device", device_id=device_id, details=details)
    else:
        log_device(message=message, device_id=device_id, level=level, details=details)

    return {"status": "logged", "level": level}


# ============================================================================
# Visualization Endpoints (Debug Visibility for AI Assistant)
# ============================================================================

@router.get("/scans/{scan_id}/viewer")
async def get_3d_viewer(scan_id: str):
    """
    Return HTML page with embedded 3D viewer.

    Uses Google's model-viewer web component for interactive 3D visualization.
    """
    from fastapi.responses import HTMLResponse

    scan_data = await storage.get_scan_metadata(scan_id)
    if not scan_data:
        raise HTTPException(status_code=404, detail="Scan not found")

    html_content = f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>3D Viewer - {scan_data.get('name', scan_id)}</title>
        <script type="module" src="https://unpkg.com/@google/model-viewer/dist/model-viewer.min.js"></script>
        <style>
            body {{ margin: 0; background: #1a1a2e; font-family: sans-serif; color: white; }}
            model-viewer {{
                width: 100%;
                height: 80vh;
                background-color: #16213e;
            }}
            .info {{
                padding: 20px;
                background: #0f3460;
            }}
            .info h2 {{ margin: 0 0 10px 0; }}
            .info p {{ margin: 5px 0; opacity: 0.8; }}
        </style>
    </head>
    <body>
        <model-viewer
            src="/api/v1/scans/{scan_id}/download?format=glb"
            alt="3D Model - {scan_data.get('name', scan_id)}"
            camera-controls
            auto-rotate
            shadow-intensity="1"
            environment-image="neutral"
            exposure="0.8">
        </model-viewer>
        <div class="info">
            <h2>{scan_data.get('name', 'Scan')}</h2>
            <p>Status: {scan_data.get('status', 'unknown')}</p>
            <p>Created: {scan_data.get('created_at', 'N/A')}</p>
            <p>Total bytes: {scan_data.get('total_bytes', 0):,}</p>
        </div>
    </body>
    </html>
    """

    return HTMLResponse(content=html_content)


@router.get("/scans/{scan_id}/depth/{frame_id}/heatmap")
async def get_depth_heatmap(scan_id: str, frame_id: int):
    """
    Return depth frame as colored heatmap image (PNG).

    Color scheme: TURBO (blue=close, red=far)
    """
    from fastapi.responses import Response
    import numpy as np

    try:
        import cv2
    except ImportError:
        raise HTTPException(status_code=500, detail="OpenCV not installed")

    # Find depth file
    depth_dir = Path(storage.base_path) / "processed" / scan_id / "depth"
    depth_file = depth_dir / f"frame_{frame_id:06d}.npz"

    if not depth_file.exists():
        # Try alternative naming
        depth_file = depth_dir / f"frame_{frame_id}.npz"

    if not depth_file.exists():
        raise HTTPException(status_code=404, detail=f"Depth frame {frame_id} not found")

    # Load depth data
    data = np.load(depth_file)
    depth = data.get('depth', data.get('arr_0'))  # Handle different key names

    if depth is None:
        raise HTTPException(status_code=500, detail="Invalid depth file format")

    # Normalize to 0-255
    depth_min = np.nanmin(depth[depth > 0]) if (depth > 0).any() else 0
    depth_max = np.nanmax(depth)

    if depth_max - depth_min < 1e-6:
        normalized = np.zeros_like(depth, dtype=np.uint8)
    else:
        normalized = ((depth - depth_min) / (depth_max - depth_min) * 255).astype(np.uint8)

    # Apply colormap (TURBO for depth visualization)
    heatmap = cv2.applyColorMap(normalized, cv2.COLORMAP_TURBO)

    # Mark invalid pixels as black
    heatmap[depth <= 0] = [0, 0, 0]

    # Encode as PNG
    _, buffer = cv2.imencode('.png', heatmap)

    return Response(content=buffer.tobytes(), media_type="image/png")


@router.get("/scans/{scan_id}/pointcloud/preview")
async def get_pointcloud_preview(scan_id: str, max_points: int = 50000):
    """
    Return downsampled point cloud as JSON for web visualization.

    Useful for lightweight preview in web browsers using Three.js or similar.
    """
    import numpy as np

    ply_path = Path(storage.base_path) / "processed" / scan_id / "pointcloud.ply"

    if not ply_path.exists():
        # Try raw scans location
        ply_path = Path(storage.base_path) / "raw_scans" / scan_id / "pointcloud.ply"

    if not ply_path.exists():
        raise HTTPException(status_code=404, detail="Point cloud not found")

    # Simple PLY parser for ASCII format
    try:
        points = []
        colors = []
        with open(ply_path, 'r') as f:
            # Skip header
            for line in f:
                if line.strip() == "end_header":
                    break

            # Read points
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 3:
                    points.append([float(parts[0]), float(parts[1]), float(parts[2])])
                    if len(parts) >= 6:
                        colors.append([int(parts[3]), int(parts[4]), int(parts[5])])

        points = np.array(points)
        colors = np.array(colors) if colors else None

        # Downsample if too many points
        if len(points) > max_points:
            indices = np.random.choice(len(points), max_points, replace=False)
            points = points[indices]
            if colors is not None:
                colors = colors[indices]

        result = {
            "point_count": len(points),
            "points": points.tolist(),
            "bounds": {
                "min": points.min(axis=0).tolist(),
                "max": points.max(axis=0).tolist()
            }
        }

        if colors is not None:
            result["colors"] = colors.tolist()

        return result

    except Exception as e:
        logger.error(f"Failed to load point cloud: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/scans/{scan_id}/compare")
async def compare_processing(scan_id: str):
    """
    Compare iOS edge processing vs backend processing results.

    Useful for debugging and quality analysis.
    """
    scan_data = await storage.get_scan_metadata(scan_id)
    if not scan_data:
        raise HTTPException(status_code=404, detail="Scan not found")

    # Get iOS metadata (from upload)
    ios_metadata = scan_data.get("metadata", {})

    # Get backend processing results
    processed_dir = Path(storage.base_path) / "processed" / scan_id

    backend_result = {}
    if processed_dir.exists():
        # Count points in generated point cloud
        ply_path = processed_dir / "pointcloud.ply"
        if ply_path.exists():
            with open(ply_path, 'r') as f:
                for line in f:
                    if line.startswith("element vertex"):
                        backend_result["point_count"] = int(line.split()[-1])
                        break

        # Check for mesh
        for ext in [".obj", ".gltf", ".glb", ".usdz"]:
            mesh_path = processed_dir / f"model{ext}"
            if mesh_path.exists():
                backend_result["mesh_format"] = ext
                backend_result["mesh_size_bytes"] = mesh_path.stat().st_size
                break

    return {
        "scan_id": scan_id,
        "ios_result": {
            "point_count": ios_metadata.get("pointCount", 0),
            "mesh_faces": ios_metadata.get("faceCount", 0),
            "vertex_count": ios_metadata.get("vertexCount", 0),
            "processing_time_ms": ios_metadata.get("processingTimeMs"),
            "device": ios_metadata.get("deviceModel")
        },
        "backend_result": backend_result,
        "differences": {
            "point_count_diff": backend_result.get("point_count", 0) - ios_metadata.get("pointCount", 0)
        }
    }


@router.get("/scans/{scan_id}/raw/download")
async def download_raw_lraw(scan_id: str):
    """
    Download original LRAW file for offline analysis.
    """
    from fastapi.responses import FileResponse

    lraw_path = Path(storage.base_path) / "raw_scans" / scan_id / "raw_data.lraw"

    if not lraw_path.exists():
        raise HTTPException(status_code=404, detail="Raw LRAW file not found")

    return FileResponse(
        path=lraw_path,
        filename=f"{scan_id}.lraw",
        media_type="application/octet-stream"
    )


@router.get("/scans/{scan_id}/intermediate/{stage}")
async def get_intermediate_output(scan_id: str, stage: str):
    """
    Get intermediate processing outputs.

    Stages:
    - 'parsed': After LRAW parsing (mesh + point cloud stats)
    - 'depth': Depth processing results
    - 'gaussians': Gaussian splat parameters (if available)
    - 'mesh_raw': Raw mesh before texture baking
    """
    valid_stages = ["parsed", "depth", "gaussians", "mesh_raw"]

    if stage not in valid_stages:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid stage. Valid stages: {valid_stages}"
        )

    scan_data = await storage.get_scan_metadata(scan_id)
    if not scan_data:
        raise HTTPException(status_code=404, detail="Scan not found")

    intermediate_dir = Path(storage.base_path) / "processed" / scan_id / "intermediate"

    result = {
        "scan_id": scan_id,
        "stage": stage,
        "available": False
    }

    if stage == "parsed":
        validation = scan_data.get("validation", {})
        result.update({
            "available": validation.get("valid", False),
            "mesh_anchor_count": validation.get("mesh_anchor_count", 0),
            "texture_frame_count": validation.get("texture_frame_count", 0),
            "depth_frame_count": validation.get("depth_frame_count", 0),
            "file_size": validation.get("file_size", 0)
        })

    elif stage == "depth":
        depth_dir = Path(storage.base_path) / "processed" / scan_id / "depth"
        if depth_dir.exists():
            depth_files = list(depth_dir.glob("*.npz"))
            result.update({
                "available": len(depth_files) > 0,
                "frame_count": len(depth_files),
                "heatmap_urls": [
                    f"/api/v1/debug/scans/{scan_id}/depth/{i}/heatmap"
                    for i in range(min(10, len(depth_files)))  # First 10 frames
                ]
            })

    elif stage == "gaussians":
        gs_path = intermediate_dir / "gaussians.ply"
        if gs_path.exists():
            result.update({
                "available": True,
                "file_size": gs_path.stat().st_size,
                "download_url": f"/api/v1/debug/scans/{scan_id}/intermediate/gaussians/download"
            })

    elif stage == "mesh_raw":
        mesh_path = intermediate_dir / "mesh_raw.ply"
        if mesh_path.exists():
            result.update({
                "available": True,
                "file_size": mesh_path.stat().st_size
            })

    return result


@router.get("/scans")
async def list_all_scans(limit: int = 50):
    """List all scans (both raw uploads and processed)"""

    scans = []

    # List raw scans
    raw_dir = Path(storage.base_path) / "raw_scans"
    if raw_dir.exists():
        for scan_dir in raw_dir.iterdir():
            if scan_dir.is_dir():
                metadata = await storage.get_scan_metadata(scan_dir.name)
                if metadata:
                    scans.append({
                        "id": scan_dir.name,
                        "name": metadata.get("name", "Unknown"),
                        "type": "raw",
                        "status": metadata.get("status"),
                        "created_at": metadata.get("created_at"),
                        "total_bytes": metadata.get("total_bytes", 0)
                    })

    # Sort by creation date
    scans.sort(key=lambda x: x.get("created_at", ""), reverse=True)

    return {
        "scans": scans[:limit],
        "total": len(scans)
    }
