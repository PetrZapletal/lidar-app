"""
Admin Dashboard Routes

Web UI for monitoring and managing 3D scan processing.
"""

import os
from datetime import datetime, timedelta
from typing import Optional
from pathlib import Path

from fastapi import APIRouter, Request, HTTPException, Depends
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from services.storage import StorageService
from utils.logger import get_logger

logger = get_logger(__name__)

# Initialize router
router = APIRouter(prefix="/admin", tags=["admin"])

# Templates directory
BASE_DIR = Path(__file__).resolve().parent.parent
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))

# Storage service
storage = StorageService()


# ============================================================================
# Helper Functions
# ============================================================================

def get_mock_gpu_data():
    """Get GPU data (mock for demo, replace with nvidia-smi in production)"""
    return [
        {
            "name": "NVIDIA RTX 4090",
            "status": "active",
            "utilization": 78,
            "memory_used": 18.2,
            "memory_total": 24,
            "memory_percent": 76,
            "temp": 72,
            "power": 320,
            "power_limit": 450,
            "current_job": {
                "name": "Office Scan",
                "stage": "3D Gaussian Splatting"
            }
        }
    ]


def get_mock_system_data():
    """Get system data (mock for demo)"""
    return {
        "cpu": 45,
        "memory_used": 28,
        "memory_total": 64,
        "memory_percent": 44,
        "disk_used": 450,
        "disk_total": 2000,
        "disk_percent": 23,
        "uptime": "5d 12h 34m",
        "started_at": "13.01.2026"
    }


def get_mock_services():
    """Get services status (mock for demo)"""
    return [
        {
            "name": "FastAPI Server",
            "description": "REST API & WebSocket",
            "status": "running",
            "icon": "fas fa-server"
        },
        {
            "name": "Redis",
            "description": "Task Queue",
            "status": "running",
            "icon": "fas fa-database"
        },
        {
            "name": "Celery Workers",
            "description": "Background Processing",
            "status": "running",
            "icon": "fas fa-cogs"
        },
        {
            "name": "Storage (MinIO)",
            "description": "Object Storage",
            "status": "running",
            "icon": "fas fa-hdd"
        }
    ]


async def get_dashboard_stats():
    """Get dashboard statistics"""
    all_scans = await storage.list_scans()

    total = len(all_scans)
    processing = len([s for s in all_scans if s.get("status") == "processing"])
    completed = len([s for s in all_scans if s.get("status") == "completed"])
    failed = len([s for s in all_scans if s.get("status") == "failed"])

    # Calculate today's scans
    today = datetime.utcnow().date()
    scans_today = len([
        s for s in all_scans
        if s.get("created_at") and s["created_at"].date() == today
    ])

    # Success rate
    total_finished = completed + failed
    success_rate = round((completed / total_finished * 100) if total_finished > 0 else 100, 1)

    return {
        "total_scans": total,
        "processing": processing,
        "completed": completed,
        "failed": failed,
        "scans_today": scans_today,
        "queued": 0,  # TODO: Get from Redis queue
        "success_rate": success_rate,
        "storage_used": "45.2 GB",
        "storage_percent": 23
    }


# ============================================================================
# Dashboard Routes
# ============================================================================

@router.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Main dashboard page"""
    stats = await get_dashboard_stats()
    all_scans = await storage.list_scans()

    # Active scans (processing)
    active_scans = [
        {
            **s,
            "eta": "~5 min"  # TODO: Calculate real ETA
        }
        for s in all_scans if s.get("status") == "processing"
    ][:5]

    # Recent scans
    recent_scans = sorted(
        all_scans,
        key=lambda x: x.get("created_at", datetime.min),
        reverse=True
    )[:10]

    # Format dates
    for scan in recent_scans:
        if scan.get("created_at"):
            scan["created_at"] = scan["created_at"].strftime("%d.%m. %H:%M")

    # Chart data (last 7 days)
    chart_labels = [(datetime.utcnow() - timedelta(days=i)).strftime("%d.%m.") for i in range(6, -1, -1)]
    chart_data = [3, 5, 2, 8, 4, 6, 7]  # TODO: Get real data

    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "active_page": "dashboard",
        "stats": stats,
        "active_scans": active_scans,
        "recent_scans": recent_scans,
        "gpus": get_mock_gpu_data(),
        "chart_labels": chart_labels,
        "chart_data": chart_data
    })


@router.get("/scans", response_class=HTMLResponse)
async def scans_list(
    request: Request,
    page: int = 1,
    per_page: int = 20,
    status: Optional[str] = None,
    search: Optional[str] = None
):
    """Scans list page"""
    all_scans = await storage.list_scans()

    # Filter by status
    if status:
        all_scans = [s for s in all_scans if s.get("status") == status]

    # Filter by search
    if search:
        search_lower = search.lower()
        all_scans = [
            s for s in all_scans
            if search_lower in s.get("name", "").lower() or
               search_lower in s.get("id", "").lower()
        ]

    # Sort by date (newest first)
    all_scans = sorted(
        all_scans,
        key=lambda x: x.get("created_at", datetime.min),
        reverse=True
    )

    # Pagination
    total = len(all_scans)
    total_pages = (total + per_page - 1) // per_page
    start = (page - 1) * per_page
    end = start + per_page
    scans = all_scans[start:end]

    # Stats
    stats = {
        "total": total,
        "created": len([s for s in all_scans if s.get("status") == "created"]),
        "processing": len([s for s in all_scans if s.get("status") == "processing"]),
        "completed": len([s for s in all_scans if s.get("status") == "completed"]),
        "failed": len([s for s in all_scans if s.get("status") == "failed"])
    }

    return templates.TemplateResponse("scans.html", {
        "request": request,
        "active_page": "scans",
        "scans": scans,
        "stats": stats,
        "page": page,
        "per_page": per_page,
        "total": total,
        "total_pages": total_pages
    })


@router.get("/scans/{scan_id}", response_class=HTMLResponse)
async def scan_detail(request: Request, scan_id: str):
    """Scan detail page"""
    scan = await storage.get_scan_metadata(scan_id)

    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found")

    # Get files info
    scan_dir = storage.get_scan_directory(scan_id)
    files = []

    if scan_dir.exists():
        # Point cloud
        pc_path = scan_dir / "pointcloud.ply"
        if pc_path.exists():
            files.append({
                "type": "pointcloud",
                "name": "pointcloud.ply",
                "size": f"{pc_path.stat().st_size / 1024 / 1024:.1f} MB",
                "url": f"/api/v1/scans/{scan_id}/files/pointcloud.ply"
            })

        # Textures
        tex_dir = scan_dir / "textures"
        if tex_dir.exists():
            tex_count = len(list(tex_dir.glob("*.heic")))
            if tex_count > 0:
                files.append({
                    "type": "texture",
                    "name": f"textures ({tex_count} frames)",
                    "size": "N/A",
                    "url": None
                })

    scan["files"] = files
    scan["logs"] = []  # TODO: Get real logs

    return templates.TemplateResponse("scan_detail.html", {
        "request": request,
        "active_page": "scans",
        "scan": scan
    })


@router.get("/processing", response_class=HTMLResponse)
async def processing_queue(request: Request):
    """Processing queue page"""
    all_scans = await storage.list_scans()

    # Queue stats
    queue = {
        "pending": len([s for s in all_scans if s.get("status") == "uploaded"]),
        "preprocessing": len([s for s in all_scans if s.get("stage") == "preprocessing"]),
        "gaussian_splatting": len([s for s in all_scans if s.get("stage") == "gaussian_splatting"]),
        "mesh_extraction": len([s for s in all_scans if s.get("stage") == "mesh_extraction"]),
        "texture_baking": len([s for s in all_scans if s.get("stage") == "texture_baking"])
    }

    # Active jobs
    active_jobs = [
        {
            **s,
            "elapsed": "2:34",  # TODO: Calculate real elapsed time
            "eta": "~8 min",
            "gpu_usage": 78,
            "completed_stages": []  # TODO: Track completed stages
        }
        for s in all_scans if s.get("status") == "processing"
    ]

    # Pending jobs
    pending_jobs = [
        {
            **s,
            "queued_at": s.get("updated_at", datetime.utcnow()).strftime("%d.%m. %H:%M"),
            "estimated_time": "~15 min"
        }
        for s in all_scans if s.get("status") == "uploaded"
    ]

    return templates.TemplateResponse("processing.html", {
        "request": request,
        "active_page": "processing",
        "queue": queue,
        "active_jobs": active_jobs,
        "pending_jobs": pending_jobs
    })


@router.get("/system", response_class=HTMLResponse)
async def system_status(request: Request):
    """System status page"""
    return templates.TemplateResponse("system.html", {
        "request": request,
        "active_page": "system",
        "system": get_mock_system_data(),
        "gpus": get_mock_gpu_data(),
        "services": get_mock_services(),
        "recent_errors": [],  # TODO: Get from logs
        "config": {
            "ENVIRONMENT": os.getenv("ENVIRONMENT", "development"),
            "DATA_DIR": os.getenv("DATA_DIR", "/data/scans"),
            "REDIS_URL": os.getenv("REDIS_URL", "redis://localhost:6379"),
            "MAX_WORKERS": os.getenv("MAX_WORKERS", "4"),
            "GPU_MEMORY_FRACTION": os.getenv("GPU_MEMORY_FRACTION", "0.9"),
            "DEFAULT_MESH_RESOLUTION": os.getenv("DEFAULT_MESH_RESOLUTION", "high"),
            "DEFAULT_TEXTURE_RESOLUTION": os.getenv("DEFAULT_TEXTURE_RESOLUTION", "4096")
        }
    })


# ============================================================================
# API Endpoints for Dashboard
# ============================================================================

@router.get("/api/active-processing")
async def get_active_processing():
    """Get active processing stats for dashboard refresh"""
    all_scans = await storage.list_scans()
    processing_count = len([s for s in all_scans if s.get("status") == "processing"])

    return {
        "processing_count": processing_count,
        "timestamp": datetime.utcnow().isoformat()
    }


@router.get("/api/processing-status")
async def get_processing_status():
    """Get detailed processing status"""
    all_scans = await storage.list_scans()

    active_jobs = [
        {
            "id": s["id"],
            "name": s["name"],
            "progress": s.get("progress", 0),
            "stage": s.get("stage", "unknown")
        }
        for s in all_scans if s.get("status") == "processing"
    ]

    return {
        "active_jobs": active_jobs,
        "timestamp": datetime.utcnow().isoformat()
    }


@router.get("/api/system-status")
async def get_system_status_api():
    """Get system status for dashboard refresh"""
    return {
        "system": get_mock_system_data(),
        "gpus": get_mock_gpu_data(),
        "timestamp": datetime.utcnow().isoformat()
    }


@router.delete("/api/scans/{scan_id}")
async def delete_scan(scan_id: str):
    """Delete a scan"""
    scan = await storage.get_scan_metadata(scan_id)
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found")

    await storage.delete_scan(scan_id)
    logger.info(f"Deleted scan: {scan_id}")

    return {"status": "deleted", "scan_id": scan_id}


@router.post("/api/scans/{scan_id}/cancel")
async def cancel_processing(scan_id: str):
    """Cancel processing for a scan"""
    scan = await storage.get_scan_metadata(scan_id)
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found")

    if scan.get("status") != "processing":
        raise HTTPException(status_code=400, detail="Scan is not processing")

    # TODO: Actually cancel the background task
    scan["status"] = "cancelled"
    scan["updated_at"] = datetime.utcnow()
    await storage.save_scan_metadata(scan_id, scan)

    logger.info(f"Cancelled processing for scan: {scan_id}")

    return {"status": "cancelled", "scan_id": scan_id}


@router.get("/api/scans/{scan_id}/logs")
async def get_scan_logs(scan_id: str):
    """Get processing logs for a scan"""
    # TODO: Implement real log retrieval
    return [
        {"timestamp": "10:34:56", "level": "info", "message": "Started preprocessing"},
        {"timestamp": "10:35:12", "level": "info", "message": "Point cloud loaded: 1,234,567 points"},
        {"timestamp": "10:35:18", "level": "info", "message": "Outlier removal: removed 12,345 points"},
        {"timestamp": "10:35:45", "level": "info", "message": "Starting 3D Gaussian Splatting training"}
    ]


@router.delete("/api/queue/{scan_id}")
async def remove_from_queue(scan_id: str):
    """Remove a scan from the processing queue"""
    scan = await storage.get_scan_metadata(scan_id)
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found")

    if scan.get("status") != "uploaded":
        raise HTTPException(status_code=400, detail="Scan is not in queue")

    scan["status"] = "created"
    scan["updated_at"] = datetime.utcnow()
    await storage.save_scan_metadata(scan_id, scan)

    return {"status": "removed", "scan_id": scan_id}
