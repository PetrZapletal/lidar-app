"""
LiDAR 3D Scanner Backend API

FastAPI server for processing 3D scans using:
- 3D Gaussian Splatting
- SuGaR mesh extraction
- Texture baking
"""

import os
import uuid
from datetime import datetime
from typing import Optional
from pathlib import Path

from fastapi import FastAPI, UploadFile, File, HTTPException, BackgroundTasks, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from services.scan_processor import ScanProcessor
from services.storage import StorageService
from services.websocket_manager import WebSocketManager
from utils.logger import get_logger
from api.admin import router as admin_router

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

# Include admin dashboard router
app.include_router(admin_router)


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
    """Health check endpoint"""
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
# WebSocket Endpoint
# ============================================================================

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
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )
