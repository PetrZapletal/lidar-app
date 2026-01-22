"""
LiDAR 3D Scanner Backend API

FastAPI server for processing 3D scans using:
- 3D Gaussian Splatting
- SuGaR mesh extraction
- Texture baking
"""

import os
import uuid
from datetime import datetime, timedelta
from typing import Optional
from pathlib import Path

from fastapi import FastAPI, UploadFile, File, HTTPException, BackgroundTasks, WebSocket, WebSocketDisconnect, Request, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from services.scan_processor import ScanProcessor
from services.storage import StorageService
from services.websocket_manager import WebSocketManager
from utils.logger import get_logger
from api.admin import router as admin_router
from api.auth import router as auth_router
from api.debug import router as debug_router
from api.ios_auth import router as ios_auth_router

# Initialize logger
logger = get_logger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="LiDAR 3D Scanner API",
    description="Backend API for AI-powered 3D reconstruction",
    version="1.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize services
storage = StorageService()
processor = ScanProcessor()
ws_manager = WebSocketManager()

# Mount static files
BASE_DIR = Path(__file__).resolve().parent.parent
static_dir = BASE_DIR / "static"
if static_dir.exists():
    app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")
else:
    logger.warning(f"Static directory not found: {static_dir}")

# Include routers
app.include_router(auth_router)
app.include_router(admin_router)
app.include_router(debug_router)
app.include_router(ios_auth_router)  # iOS app authentication


# ============================================================================
# Data Models
# ============================================================================

class ScanCreate(BaseModel):
    """Request model for creating a new scan"""
    name: str = Field(..., min_length=1, max_length=100)
    description: Optional[str] = None
    device_info: Optional[dict] = None


class ScanResponse(BaseModel):
    """Response model for scan operations"""
    id: str
    name: str
    status: str
    created_at: datetime
    updated_at: datetime
    progress: float = 0.0
    stage: Optional[str] = None
    result_urls: Optional[dict] = None
    error: Optional[str] = None


class ProcessingOptions(BaseModel):
    """Options for 3D processing"""
    enable_gaussian_splatting: bool = True
    enable_mesh_extraction: bool = True
    enable_texture_baking: bool = True
    mesh_resolution: str = "high"  # low, medium, high
    texture_resolution: int = 4096
    output_formats: list[str] = ["usdz", "gltf", "obj"]


# ============================================================================
# API Routes
# ============================================================================

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "status": "healthy",
        "service": "LiDAR 3D Scanner API",
        "version": "1.0.0"
    }


@app.get("/health")
async def health_check():
    """Health check endpoint for connectivity testing"""
    return {
        "status": "healthy",
        "service": "LiDAR 3D Scanner API",
        "version": "1.0.0"
    }


@app.post("/api/v1/scans", response_model=ScanResponse)
async def create_scan(scan: ScanCreate):
    """Create a new scan session"""
    scan_id = str(uuid.uuid4())

    scan_data = {
        "id": scan_id,
        "name": scan.name,
        "description": scan.description,
        "device_info": scan.device_info,
        "status": "created",
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow(),
        "progress": 0.0
    }

    # Store scan metadata
    await storage.save_scan_metadata(scan_id, scan_data)

    logger.info(f"Created scan: {scan_id}")

    return ScanResponse(**scan_data)


@app.post("/api/v1/scans/{scan_id}/upload")
async def upload_scan_data(
    scan_id: str,
    pointcloud: UploadFile = File(...),
    metadata: UploadFile = File(None),
    textures: list[UploadFile] = File(None)
):
    """Upload scan data (point cloud, textures, metadata)"""

    # Verify scan exists
    scan_data = await storage.get_scan_metadata(scan_id)
    if not scan_data:
        raise HTTPException(status_code=404, detail="Scan not found")

    try:
        # Save point cloud
        pc_path = await storage.save_upload(scan_id, "pointcloud.ply", pointcloud)
        logger.info(f"Saved point cloud: {pc_path}")

        # Save metadata
        if metadata:
            meta_path = await storage.save_upload(scan_id, "metadata.json", metadata)
            logger.info(f"Saved metadata: {meta_path}")

        # Save textures
        texture_paths = []
        if textures:
            for i, tex in enumerate(textures):
                tex_path = await storage.save_upload(scan_id, f"textures/frame_{i:04d}.heic", tex)
                texture_paths.append(tex_path)
            logger.info(f"Saved {len(texture_paths)} textures")

        # Update scan status
        scan_data["status"] = "uploaded"
        scan_data["updated_at"] = datetime.utcnow()
        await storage.save_scan_metadata(scan_id, scan_data)

        return {
            "status": "success",
            "scan_id": scan_id,
            "files_uploaded": {
                "pointcloud": pc_path,
                "metadata": meta_path if metadata else None,
                "textures": len(texture_paths)
            }
        }

    except Exception as e:
        logger.error(f"Upload failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================================
# Chunked Upload Endpoints (for iOS app)
# ============================================================================

# In-memory storage for upload sessions (in production, use Redis)
_upload_sessions: dict = {}


class UploadInitRequest(BaseModel):
    fileSize: int
    chunkSize: int = 5242880  # 5MB default
    contentType: str = "application/octet-stream"


class UploadInitResponse(BaseModel):
    uploadId: str
    uploadedChunks: Optional[list[int]] = None
    expiresAt: Optional[str] = None


@app.post("/api/v1/scans/{scan_id}/upload/init", response_model=UploadInitResponse)
async def init_chunked_upload(scan_id: str, request: UploadInitRequest):
    """Initialize a chunked upload session"""
    # Verify scan exists
    scan_data = await storage.get_scan_metadata(scan_id)
    if not scan_data:
        raise HTTPException(status_code=404, detail="Scan not found")

    upload_id = str(uuid.uuid4())
    total_chunks = (request.fileSize + request.chunkSize - 1) // request.chunkSize

    # Store upload session
    _upload_sessions[upload_id] = {
        "scan_id": scan_id,
        "file_size": request.fileSize,
        "chunk_size": request.chunkSize,
        "total_chunks": total_chunks,
        "uploaded_chunks": [],
        "chunks_data": {},
        "created_at": datetime.utcnow(),
    }

    logger.info(f"Initialized chunked upload for scan {scan_id}: {upload_id}, {total_chunks} chunks")

    return UploadInitResponse(
        uploadId=upload_id,
        uploadedChunks=[],
        expiresAt=(datetime.utcnow() + timedelta(hours=24)).isoformat()
    )


@app.put("/api/v1/scans/{scan_id}/upload/chunk")
async def upload_chunk(
    scan_id: str,
    request: Request,
    x_chunk_index: int = Header(..., alias="X-Chunk-Index"),
    x_chunk_offset: int = Header(0, alias="X-Chunk-Offset"),
    x_chunk_size: int = Header(0, alias="X-Chunk-Size"),
    x_upload_id: str = Header(None, alias="X-Upload-Id")
):
    """Upload a single chunk"""
    # Find upload session
    session = None
    if x_upload_id and x_upload_id in _upload_sessions:
        session = _upload_sessions[x_upload_id]
    else:
        # Find session by scan_id
        for uid, s in _upload_sessions.items():
            if s["scan_id"] == scan_id:
                session = s
                x_upload_id = uid
                break

    if not session:
        raise HTTPException(status_code=400, detail="Upload session not found. Call /upload/init first.")

    # Read chunk data
    chunk_data = await request.body()

    # Store chunk
    session["chunks_data"][x_chunk_index] = chunk_data
    if x_chunk_index not in session["uploaded_chunks"]:
        session["uploaded_chunks"].append(x_chunk_index)

    logger.info(f"Received chunk {x_chunk_index} for scan {scan_id}: {len(chunk_data)} bytes")

    return {
        "status": "chunk_received",
        "chunkIndex": x_chunk_index,
        "bytesReceived": len(chunk_data),
        "totalChunksReceived": len(session["uploaded_chunks"]),
        "totalChunksExpected": session["total_chunks"]
    }


@app.post("/api/v1/scans/{scan_id}/upload/finalize")
async def finalize_chunked_upload(scan_id: str):
    """Finalize chunked upload and assemble the file"""
    # Find upload session
    session = None
    upload_id = None
    for uid, s in _upload_sessions.items():
        if s["scan_id"] == scan_id:
            session = s
            upload_id = uid
            break

    if not session:
        raise HTTPException(status_code=400, detail="Upload session not found")

    # Check all chunks received
    expected_chunks = set(range(session["total_chunks"]))
    received_chunks = set(session["uploaded_chunks"])

    if expected_chunks != received_chunks:
        missing = expected_chunks - received_chunks
        raise HTTPException(
            status_code=400,
            detail=f"Missing chunks: {sorted(missing)}"
        )

    # Assemble file
    try:
        assembled_data = b""
        for i in range(session["total_chunks"]):
            assembled_data += session["chunks_data"][i]

        # Save to storage
        scan_dir = storage.get_scan_directory(scan_id)
        scan_dir.mkdir(parents=True, exist_ok=True)
        file_path = scan_dir / "scan_data.bin"
        with open(file_path, "wb") as f:
            f.write(assembled_data)

        # Update scan status
        scan_data = await storage.get_scan_metadata(scan_id)
        scan_data["status"] = "uploaded"
        scan_data["updated_at"] = datetime.utcnow()
        await storage.save_scan_metadata(scan_id, scan_data)

        # Clean up session
        del _upload_sessions[upload_id]

        logger.info(f"Finalized chunked upload for scan {scan_id}: {len(assembled_data)} bytes")

        return {
            "status": "finalized",
            "scan_id": scan_id,
            "totalBytes": len(assembled_data)
        }

    except Exception as e:
        logger.error(f"Error finalizing upload for scan {scan_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/v1/scans/{scan_id}/upload/cancel")
async def cancel_chunked_upload(scan_id: str):
    """Cancel an ongoing chunked upload"""
    # Find and remove upload session
    upload_id = None
    for uid, s in _upload_sessions.items():
        if s["scan_id"] == scan_id:
            upload_id = uid
            break

    if upload_id:
        del _upload_sessions[upload_id]
        logger.info(f"Cancelled chunked upload for scan {scan_id}")
        return {"status": "cancelled", "scan_id": scan_id}

    return {"status": "not_found", "scan_id": scan_id}


@app.post("/api/v1/scans/{scan_id}/process")
async def start_processing(
    scan_id: str,
    options: ProcessingOptions,
    background_tasks: BackgroundTasks
):
    """Start AI processing pipeline"""

    # Verify scan exists and is uploaded
    scan_data = await storage.get_scan_metadata(scan_id)
    if not scan_data:
        raise HTTPException(status_code=404, detail="Scan not found")

    if scan_data["status"] not in ["uploaded", "failed"]:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot process scan in status: {scan_data['status']}"
        )

    # Update status
    scan_data["status"] = "processing"
    scan_data["stage"] = "initializing"
    scan_data["progress"] = 0.0
    scan_data["updated_at"] = datetime.utcnow()
    await storage.save_scan_metadata(scan_id, scan_data)

    # Start background processing
    background_tasks.add_task(
        process_scan_task,
        scan_id,
        options.model_dump()
    )

    return {
        "status": "processing_started",
        "scan_id": scan_id,
        "message": "Processing started. Connect to WebSocket for real-time updates."
    }


async def process_scan_task(scan_id: str, options: dict):
    """Background task for processing scan"""
    try:
        # Progress callback
        async def on_progress(progress: float, stage: str, message: str = None):
            scan_data = await storage.get_scan_metadata(scan_id)
            scan_data["progress"] = progress
            scan_data["stage"] = stage
            scan_data["updated_at"] = datetime.utcnow()
            await storage.save_scan_metadata(scan_id, scan_data)

            # Notify WebSocket clients
            await ws_manager.broadcast(scan_id, {
                "type": "processing_update",
                "data": {
                    "scan_id": scan_id,
                    "progress": progress,
                    "stage": stage,
                    "message": message,
                    "status": "processing"
                }
            })

        # Run processing pipeline
        result = await processor.process_scan(
            scan_id=scan_id,
            options=options,
            progress_callback=on_progress
        )

        # Update final status
        scan_data = await storage.get_scan_metadata(scan_id)
        scan_data["status"] = "completed"
        scan_data["progress"] = 1.0
        scan_data["stage"] = "completed"
        scan_data["result_urls"] = result["output_urls"]
        scan_data["updated_at"] = datetime.utcnow()
        await storage.save_scan_metadata(scan_id, scan_data)

        # Notify completion
        await ws_manager.broadcast(scan_id, {
            "type": "processing_update",
            "data": {
                "scan_id": scan_id,
                "progress": 1.0,
                "stage": "completed",
                "status": "completed",
                "result_urls": result["output_urls"]
            }
        })

        logger.info(f"Processing completed for scan: {scan_id}")

    except Exception as e:
        logger.error(f"Processing failed for scan {scan_id}: {e}")

        # Update error status
        scan_data = await storage.get_scan_metadata(scan_id)
        scan_data["status"] = "failed"
        scan_data["error"] = str(e)
        scan_data["updated_at"] = datetime.utcnow()
        await storage.save_scan_metadata(scan_id, scan_data)

        # Notify error
        await ws_manager.broadcast(scan_id, {
            "type": "error",
            "data": {
                "scan_id": scan_id,
                "code": "processing_failed",
                "message": str(e)
            }
        })


@app.get("/api/v1/scans/{scan_id}/status", response_model=ScanResponse)
async def get_scan_status(scan_id: str):
    """Get current scan status"""
    scan_data = await storage.get_scan_metadata(scan_id)
    if not scan_data:
        raise HTTPException(status_code=404, detail="Scan not found")

    return ScanResponse(**scan_data)


@app.get("/api/v1/scans", response_model=list[ScanResponse])
async def list_scans():
    """List all scans"""
    try:
        scans = await storage.list_scans()
        return [ScanResponse(**scan) for scan in scans]
    except Exception as e:
        logger.error(f"Error listing scans: {e}")
        return []


@app.get("/api/v1/scans/{scan_id}", response_model=ScanResponse)
async def get_scan(scan_id: str):
    """Get scan details"""
    scan_data = await storage.get_scan_metadata(scan_id)
    if not scan_data:
        raise HTTPException(status_code=404, detail="Scan not found")

    return ScanResponse(**scan_data)


@app.delete("/api/v1/scans/{scan_id}")
async def delete_scan(scan_id: str):
    """Delete a scan"""
    scan_data = await storage.get_scan_metadata(scan_id)
    if not scan_data:
        raise HTTPException(status_code=404, detail="Scan not found")

    try:
        await storage.delete_scan(scan_id)
        logger.info(f"Deleted scan: {scan_id}")
        return {"status": "deleted", "scan_id": scan_id}
    except Exception as e:
        logger.error(f"Error deleting scan {scan_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/v1/scans/{scan_id}/download")
async def download_result(
    scan_id: str,
    format: str = "usdz"
):
    """Download processed model"""

    scan_data = await storage.get_scan_metadata(scan_id)
    if not scan_data:
        raise HTTPException(status_code=404, detail="Scan not found")

    if scan_data["status"] != "completed":
        raise HTTPException(
            status_code=400,
            detail=f"Scan not completed. Current status: {scan_data['status']}"
        )

    result_urls = scan_data.get("result_urls", {})
    if format not in result_urls:
        raise HTTPException(
            status_code=404,
            detail=f"Format {format} not available. Available: {list(result_urls.keys())}"
        )

    file_path = result_urls[format]

    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="File not found")

    return FileResponse(
        path=file_path,
        filename=f"{scan_data['name']}.{format}",
        media_type="application/octet-stream"
    )


# ============================================================================
# WebSocket Endpoints
# ============================================================================

@app.websocket("/ws")
async def general_websocket_endpoint(websocket: WebSocket):
    """General WebSocket endpoint with subscription mechanism for iOS app"""
    await websocket.accept()
    subscribed_scans: set = set()

    try:
        while True:
            data = await websocket.receive_text()

            # Handle ping
            if data == "ping":
                await websocket.send_text("pong")
                continue

            # Try to parse JSON message
            try:
                import json
                message = json.loads(data)
                msg_type = message.get("type")
                scan_id = message.get("scanId")

                if msg_type == "subscribe" and scan_id:
                    subscribed_scans.add(scan_id)
                    # Send current status
                    scan_data = await storage.get_scan_metadata(scan_id)
                    if scan_data:
                        await websocket.send_json({
                            "type": "processing_update",
                            "data": {
                                "scan_id": scan_id,
                                "progress": scan_data.get("progress", 0),
                                "stage": scan_data.get("stage", "unknown"),
                                "status": scan_data.get("status", "unknown")
                            }
                        })
                    logger.info(f"Client subscribed to scan: {scan_id}")

                elif msg_type == "unsubscribe" and scan_id:
                    subscribed_scans.discard(scan_id)
                    logger.info(f"Client unsubscribed from scan: {scan_id}")

                elif msg_type == "pong":
                    pass  # Pong response from client

            except json.JSONDecodeError:
                logger.warning(f"Invalid JSON message: {data}")

    except WebSocketDisconnect:
        logger.info("General WebSocket disconnected")


@app.websocket("/ws/scans/{scan_id}")
async def websocket_endpoint(websocket: WebSocket, scan_id: str):
    """WebSocket endpoint for real-time processing updates"""

    await ws_manager.connect(scan_id, websocket)

    try:
        # Send current status on connect
        scan_data = await storage.get_scan_metadata(scan_id)
        if scan_data:
            await websocket.send_json({
                "type": "processing_update",
                "data": {
                    "scan_id": scan_id,
                    "progress": scan_data.get("progress", 0),
                    "stage": scan_data.get("stage", "unknown"),
                    "status": scan_data.get("status", "unknown")
                }
            })

        # Keep connection alive
        while True:
            data = await websocket.receive_text()

            if data == "ping":
                await websocket.send_text("pong")

    except WebSocketDisconnect:
        ws_manager.disconnect(scan_id, websocket)
        logger.info(f"WebSocket disconnected for scan: {scan_id}")


# ============================================================================
# Entry Point
# ============================================================================

if __name__ == "__main__":
    import uvicorn
    import sys

    # Check for HTTPS mode
    use_https = "--https" in sys.argv or "-s" in sys.argv
    port = 8443 if use_https else 8000

    print("=" * 60)
    print("LiDAR 3D Scanner API")
    print("=" * 60)
    print(f"Mode: {'HTTPS' if use_https else 'HTTP'}")
    print(f"Port: {port}")
    print()

    if use_https:
        uvicorn.run(
            "main:app",
            host="0.0.0.0",
            port=port,
            log_level="info",
            ssl_keyfile="certs/key.pem",
            ssl_certfile="certs/cert.pem"
        )
    else:
        uvicorn.run(
            "main:app",
            host="0.0.0.0",
            port=port,
            reload=True,
            log_level="info"
        )
