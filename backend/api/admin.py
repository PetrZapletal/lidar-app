"""
Admin Dashboard Routes

Web UI for monitoring and managing 3D scan processing.
"""

import os
from datetime import datetime, timedelta
from typing import Optional
from pathlib import Path

from fastapi import APIRouter, Request, HTTPException, Depends
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from services.storage import StorageService
from services.log_storage import get_log_storage
from utils.logger import get_logger
from utils.gpu_monitor import get_gpu_info as get_real_gpu_info, get_system_info as get_real_system_info
from api.auth import get_current_user

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

def get_gpu_data():
    """Get GPU data from nvidia-smi or mock if unavailable"""
    return get_real_gpu_info()


def get_system_data():
    """Get real system data using psutil"""
    return get_real_system_info()


def get_services_status():
    """Get real services status"""
    import redis

    services = [
        {
            "name": "FastAPI Server",
            "description": "REST API & WebSocket",
            "status": "running",  # Always running if we're here
            "icon": "fas fa-server"
        }
    ]

    # Check Redis
    redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
    try:
        r = redis.from_url(redis_url, socket_timeout=2)
        r.ping()
        redis_status = "running"
    except Exception:
        redis_status = "stopped"

    services.append({
        "name": "Redis",
        "description": "Task Queue",
        "status": redis_status,
        "icon": "fas fa-database"
    })

    # Check Celery (via Redis)
    try:
        if redis_status == "running":
            r = redis.from_url(redis_url, socket_timeout=2)
            # Check if any celery workers registered
            workers = r.smembers("_kombu.binding.celery")
            celery_status = "running" if workers else "idle"
        else:
            celery_status = "stopped"
    except Exception:
        celery_status = "unknown"

    services.append({
        "name": "Celery Workers",
        "description": "Background Processing",
        "status": celery_status,
        "icon": "fas fa-cogs"
    })

    # Storage (local filesystem)
    storage_status = "running" if storage.base_path.exists() else "stopped"
    services.append({
        "name": "Local Storage",
        "description": f"{storage.base_path}",
        "status": storage_status,
        "icon": "fas fa-hdd"
    })

    return services


def get_directory_size(path: Path) -> int:
    """Calculate total size of directory in bytes"""
    total = 0
    try:
        for entry in path.rglob("*"):
            if entry.is_file():
                total += entry.stat().st_size
    except (PermissionError, OSError):
        pass
    return total


def format_size(bytes_size: int) -> str:
    """Format bytes to human readable string"""
    if bytes_size < 1024:
        return f"{bytes_size} B"
    elif bytes_size < 1024 ** 2:
        return f"{bytes_size / 1024:.1f} KB"
    elif bytes_size < 1024 ** 3:
        return f"{bytes_size / (1024 ** 2):.1f} MB"
    else:
        return f"{bytes_size / (1024 ** 3):.2f} GB"


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

    # Calculate real storage usage
    storage_bytes = get_directory_size(storage.base_path)
    storage_used = format_size(storage_bytes)

    # Get disk info for percentage (use DATA_DIR mount point)
    import psutil
    try:
        disk = psutil.disk_usage(str(storage.base_path))
        storage_percent = int((storage_bytes / disk.total) * 100) if disk.total > 0 else 0
    except (OSError, Exception):
        storage_percent = 0

    return {
        "total_scans": total,
        "processing": processing,
        "completed": completed,
        "failed": failed,
        "scans_today": scans_today,
        "queued": 0,  # TODO: Get from Redis queue
        "success_rate": success_rate,
        "storage_used": storage_used,
        "storage_percent": storage_percent
    }


# ============================================================================
# Authentication Helper
# ============================================================================

async def check_auth(request: Request):
    """Check if user is authenticated, redirect to login if not"""
    user = await get_current_user(request)
    if not user:
        return None
    return user


# ============================================================================
# Dashboard Routes
# ============================================================================

@router.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Main dashboard page"""
    user = await check_auth(request)
    if not user:
        return RedirectResponse(url="/login?next=/admin", status_code=303)

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
        "gpus": get_gpu_data(),
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
    user = await check_auth(request)
    if not user:
        return RedirectResponse(url="/login?next=/admin/scans", status_code=303)

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
    user = await check_auth(request)
    if not user:
        return RedirectResponse(url=f"/login?next=/admin/scans/{scan_id}", status_code=303)

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

    # Get real logs from storage
    log_storage = get_log_storage()
    scan["logs"] = log_storage.get_scan_logs(scan_id, limit=50)

    return templates.TemplateResponse("scan_detail.html", {
        "request": request,
        "active_page": "scans",
        "scan": scan
    })


@router.get("/processing", response_class=HTMLResponse)
async def processing_queue(request: Request):
    """Processing queue page"""
    user = await check_auth(request)
    if not user:
        return RedirectResponse(url="/login?next=/admin/processing", status_code=303)

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


@router.get("/logs", response_class=HTMLResponse)
async def logs_page(request: Request):
    """Logs viewer page"""
    user = await check_auth(request)
    if not user:
        return RedirectResponse(url="/login?next=/admin/logs", status_code=303)

    log_storage = get_log_storage()

    return templates.TemplateResponse("logs.html", {
        "request": request,
        "active_page": "logs",
        "stats": log_storage.get_statistics(),
        "recent_errors": log_storage.get_recent_errors(limit=20)
    })


@router.get("/system", response_class=HTMLResponse)
async def system_status(request: Request):
    """System status page"""
    user = await check_auth(request)
    if not user:
        return RedirectResponse(url="/login?next=/admin/system", status_code=303)

    # Get real errors from log storage
    log_storage = get_log_storage()
    recent_errors = log_storage.get_recent_errors(limit=20)

    return templates.TemplateResponse("system.html", {
        "request": request,
        "active_page": "system",
        "system": get_system_data(),
        "gpus": get_gpu_data(),
        "services": get_services_status(),
        "recent_errors": recent_errors,
        "log_stats": log_storage.get_statistics(),
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
        "system": get_system_data(),
        "gpus": get_gpu_data(),
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
async def get_scan_logs(scan_id: str, limit: int = 100):
    """Get processing logs for a scan"""
    log_storage = get_log_storage()
    return log_storage.get_scan_logs(scan_id, limit=limit)


@router.get("/api/logs/recent")
async def get_recent_logs(
    limit: int = 100,
    level: Optional[str] = None,
    category: Optional[str] = None
):
    """Get recent logs with optional filtering"""
    log_storage = get_log_storage()
    return {
        "logs": log_storage.get_recent_logs(limit=limit, level=level, category=category),
        "stats": log_storage.get_statistics()
    }


@router.get("/api/logs/errors")
async def get_recent_errors(limit: int = 50):
    """Get recent errors"""
    log_storage = get_log_storage()
    return {
        "errors": log_storage.get_recent_errors(limit=limit),
        "stats": log_storage.get_statistics()
    }


@router.get("/api/devices/{device_id}/logs")
async def get_device_logs(device_id: str, limit: int = 200):
    """Get logs for a specific device"""
    log_storage = get_log_storage()
    return log_storage.get_device_logs(device_id, limit=limit)


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
