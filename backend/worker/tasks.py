"""
Celery Tasks

Background tasks for 3D scan processing pipeline.
"""

import os
import asyncio
from datetime import datetime, timedelta
from typing import Optional, Dict, Any

from celery import Task
from celery.utils.log import get_task_logger

from worker.celery_app import celery_app
from services.scan_processor import ScanProcessor
from services.storage import StorageService
from services.websocket_manager import WebSocketManager

logger = get_task_logger(__name__)

# Initialize services
storage = StorageService()
processor = ScanProcessor()
ws_manager = WebSocketManager()


class ScanProcessingTask(Task):
    """Base class for scan processing tasks with progress reporting"""

    _processor: Optional[ScanProcessor] = None

    @property
    def processor(self) -> ScanProcessor:
        if self._processor is None:
            self._processor = ScanProcessor()
        return self._processor


# ============================================================================
# Main Processing Tasks
# ============================================================================

@celery_app.task(
    bind=True,
    base=ScanProcessingTask,
    name="worker.tasks.process_scan",
    max_retries=3,
    default_retry_delay=60,
    time_limit=3600,  # 1 hour max
    soft_time_limit=3300  # 55 min soft limit
)
def process_scan(
    self,
    scan_id: str,
    options: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Main scan processing task.

    Pipeline:
    1. Preprocessing (10%)
    2. 3D Gaussian Splatting (40%)
    3. SuGaR Mesh Extraction (25%)
    4. Texture Baking (15%)
    5. Export (10%)
    """
    logger.info(f"Starting processing for scan: {scan_id}")

    try:
        # Run async processing in event loop
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

        try:
            result = loop.run_until_complete(
                _process_scan_async(self, scan_id, options)
            )
            return result
        finally:
            loop.close()

    except Exception as e:
        logger.error(f"Processing failed for {scan_id}: {e}")

        # Update scan status
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            loop.run_until_complete(
                _update_scan_status(scan_id, "failed", error=str(e))
            )
        finally:
            loop.close()

        raise self.retry(exc=e)


async def _process_scan_async(
    task: ScanProcessingTask,
    scan_id: str,
    options: Dict[str, Any]
) -> Dict[str, Any]:
    """Async implementation of scan processing"""

    async def on_progress(progress: float, stage: str, message: str = None):
        """Progress callback"""
        await _update_scan_status(scan_id, "processing", progress=progress, stage=stage)

        # Notify WebSocket clients
        try:
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
        except Exception as e:
            logger.warning(f"WebSocket broadcast failed: {e}")

        # Update Celery task state
        task.update_state(
            state="PROGRESS",
            meta={
                "progress": progress,
                "stage": stage,
                "scan_id": scan_id
            }
        )

    # Run processing pipeline
    result = await task.processor.process_scan(
        scan_id=scan_id,
        options=options,
        progress_callback=on_progress
    )

    # Update final status
    await _update_scan_status(
        scan_id,
        "completed",
        progress=1.0,
        stage="completed",
        result_urls=result.get("output_urls", {})
    )

    # Notify completion
    await ws_manager.broadcast(scan_id, {
        "type": "processing_update",
        "data": {
            "scan_id": scan_id,
            "progress": 1.0,
            "stage": "completed",
            "status": "completed",
            "result_urls": result.get("output_urls", {})
        }
    })

    logger.info(f"Processing completed for scan: {scan_id}")

    return {
        "scan_id": scan_id,
        "status": "completed",
        "output_urls": result.get("output_urls", {})
    }


async def _update_scan_status(
    scan_id: str,
    status: str,
    progress: float = None,
    stage: str = None,
    error: str = None,
    result_urls: Dict = None
):
    """Update scan metadata in storage"""
    scan_data = await storage.get_scan_metadata(scan_id)

    if scan_data:
        scan_data["status"] = status
        scan_data["updated_at"] = datetime.utcnow()

        if progress is not None:
            scan_data["progress"] = progress
        if stage is not None:
            scan_data["stage"] = stage
        if error is not None:
            scan_data["error"] = error
        if result_urls is not None:
            scan_data["result_urls"] = result_urls

        await storage.save_scan_metadata(scan_id, scan_data)


# ============================================================================
# Raw Data Processing Tasks
# ============================================================================

@celery_app.task(
    bind=True,
    base=ScanProcessingTask,
    name="worker.tasks.process_raw_scan",
    max_retries=3,
    default_retry_delay=60,
    time_limit=7200,  # 2 hours max for raw data
    soft_time_limit=6900
)
def process_raw_scan_task(
    self,
    scan_id: str,
    options: Dict[str, Any] = None
) -> Dict[str, Any]:
    """
    Process raw scan data uploaded via debug pipeline.

    Pipeline:
    1. Parse LRAW binary format
    2. Reconstruct mesh from anchors
    3. Extract point cloud
    4. Run standard processing pipeline
    """
    logger.info(f"Starting raw scan processing: {scan_id}")

    try:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

        try:
            result = loop.run_until_complete(
                _process_raw_scan_async(self, scan_id, options or {})
            )
            return result
        finally:
            loop.close()

    except Exception as e:
        logger.error(f"Raw scan processing failed for {scan_id}: {e}")

        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            loop.run_until_complete(
                _update_scan_status(scan_id, "failed", error=str(e))
            )
        finally:
            loop.close()

        raise self.retry(exc=e)


async def _process_raw_scan_async(
    task: ScanProcessingTask,
    scan_id: str,
    options: Dict[str, Any]
) -> Dict[str, Any]:
    """Process raw scan data asynchronously"""
    from pathlib import Path
    from services.raw_data_processor import RawDataProcessor

    async def on_progress(progress: float, stage: str, message: str = None):
        await _update_scan_status(scan_id, "processing", progress=progress, stage=stage)

        task.update_state(
            state="PROGRESS",
            meta={
                "progress": progress,
                "stage": stage,
                "scan_id": scan_id
            }
        )

    # Get raw file path
    scan_data = await storage.get_scan_metadata(scan_id)
    if not scan_data:
        raise ValueError(f"Scan not found: {scan_id}")

    raw_file = scan_data.get("raw_file")
    if not raw_file or not Path(raw_file).exists():
        raise ValueError(f"Raw data file not found: {raw_file}")

    # Process raw data
    raw_processor = RawDataProcessor()
    processed_data = await raw_processor.process(
        raw_file_path=raw_file,
        scan_id=scan_id,
        progress_callback=on_progress
    )

    # Continue with standard processing
    await on_progress(0.5, "gaussian_splatting", "Starting 3D reconstruction...")

    result = await task.processor.process_scan(
        scan_id=scan_id,
        options={**options, "preprocessed_data": processed_data},
        progress_callback=lambda p, s, m=None: on_progress(0.5 + p * 0.5, s, m)
    )

    # Update final status
    await _update_scan_status(
        scan_id,
        "completed",
        progress=1.0,
        stage="completed",
        result_urls=result.get("output_urls", {})
    )

    logger.info(f"Raw scan processing completed: {scan_id}")

    return {
        "scan_id": scan_id,
        "status": "completed",
        "output_urls": result.get("output_urls", {})
    }


# ============================================================================
# Simple Pipeline Tasks (Apple Silicon compatible)
# ============================================================================

@celery_app.task(
    bind=True,
    name="worker.tasks.process_scan_simple",
    max_retries=2,
    default_retry_delay=30,
    time_limit=3600,  # 1 hour max
    soft_time_limit=3300
)
def process_scan_simple(
    self,
    scan_id: str,
    lraw_path: str
) -> Dict[str, Any]:
    """
    Process raw scan using SimplePipeline (MPS/CPU compatible).

    This task bypasses Gaussian Splatting and uses:
    1. Parse LRAW
    2. AI Depth Enhancement (Depth Anything V2)
    3. Point Cloud Extraction
    4. Poisson Reconstruction (Open3D)
    5. Export (PLY, GLB, OBJ)

    Args:
        scan_id: Unique scan identifier
        lraw_path: Path to LRAW file

    Returns:
        Processing result with paths to generated files
    """
    logger.info(f"Starting simple pipeline processing: {scan_id}")

    try:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

        try:
            result = loop.run_until_complete(
                _process_scan_simple_async(self, scan_id, lraw_path)
            )
            return result
        finally:
            loop.close()

    except Exception as e:
        logger.error(f"Simple pipeline failed for {scan_id}: {e}")
        import traceback
        traceback.print_exc()

        # Update scan status
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            loop.run_until_complete(
                _update_scan_status(scan_id, "failed", error=str(e))
            )
        finally:
            loop.close()

        raise self.retry(exc=e)


async def _process_scan_simple_async(
    task,
    scan_id: str,
    lraw_path: str
) -> Dict[str, Any]:
    """Async implementation of simple pipeline processing"""
    from services.simple_pipeline import SimplePipeline

    async def on_progress(progress: float, stage: str, message: str = ""):
        """Progress callback"""
        await _update_scan_status(scan_id, "processing", progress=progress, stage=stage)

        # Update Celery task state
        task.update_state(
            state="PROGRESS",
            meta={
                "progress": progress,
                "stage": stage,
                "message": message,
                "scan_id": scan_id
            }
        )

        # Notify WebSocket clients
        try:
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
        except Exception as e:
            logger.debug(f"WebSocket broadcast failed: {e}")

    # Run simple pipeline
    pipeline = SimplePipeline()
    result = await pipeline.process(
        scan_id=scan_id,
        lraw_path=lraw_path,
        progress_callback=on_progress
    )

    if result.status == "error":
        raise Exception(result.error)

    # Update final status
    await _update_scan_status(
        scan_id,
        "completed",
        progress=1.0,
        stage="completed",
        result_urls=result.exports
    )

    # Notify completion
    await ws_manager.broadcast(scan_id, {
        "type": "processing_update",
        "data": {
            "scan_id": scan_id,
            "progress": 1.0,
            "stage": "completed",
            "status": "completed",
            "result_urls": result.exports
        }
    })

    logger.info(f"Simple pipeline completed: {scan_id}")

    return {
        "scan_id": scan_id,
        "status": "completed",
        "pointcloud_path": result.pointcloud_path,
        "mesh_path": result.mesh_path,
        "exports": result.exports,
        "stats": result.stats
    }


# ============================================================================
# Export Tasks
# ============================================================================

@celery_app.task(
    bind=True,
    name="worker.tasks.export_model",
    max_retries=3
)
def export_model(
    self,
    scan_id: str,
    output_format: str,
    options: Dict[str, Any] = None
) -> str:
    """Export processed model to specified format"""
    logger.info(f"Exporting scan {scan_id} to {output_format}")

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    try:
        from services.export_service import ExportService
        export_service = ExportService()

        output_path = loop.run_until_complete(
            export_service.export(scan_id, output_format, options or {})
        )

        logger.info(f"Export completed: {output_path}")
        return output_path

    finally:
        loop.close()


# ============================================================================
# Maintenance Tasks
# ============================================================================

@celery_app.task(name="worker.tasks.cleanup_old_scans")
def cleanup_old_scans(max_age_days: int = 30):
    """Clean up old scan data"""
    logger.info(f"Cleaning up scans older than {max_age_days} days")

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    try:
        cutoff = datetime.utcnow() - timedelta(days=max_age_days)
        all_scans = loop.run_until_complete(storage.list_scans())

        deleted_count = 0
        for scan in all_scans:
            if scan.get("created_at") and scan["created_at"] < cutoff:
                if scan.get("status") in ["completed", "failed"]:
                    loop.run_until_complete(storage.delete_scan(scan["id"]))
                    deleted_count += 1
                    logger.info(f"Deleted old scan: {scan['id']}")

        logger.info(f"Cleanup completed: {deleted_count} scans deleted")
        return {"deleted": deleted_count}

    finally:
        loop.close()


@celery_app.task(name="worker.tasks.update_gpu_stats")
def update_gpu_stats():
    """Update GPU statistics in Redis for dashboard"""
    from utils.gpu_monitor import get_gpu_info, get_system_info
    import redis
    import json

    try:
        redis_url = os.getenv("REDIS_URL", "redis://localhost:6379/0")
        r = redis.from_url(redis_url)

        # Store GPU info
        gpu_info = get_gpu_info()
        r.setex("gpu_stats", 60, json.dumps(gpu_info))

        # Store system info
        system_info = get_system_info()
        r.setex("system_stats", 60, json.dumps(system_info))

        return {"status": "updated"}

    except Exception as e:
        logger.warning(f"Failed to update GPU stats: {e}")
        return {"status": "error", "error": str(e)}


@celery_app.task(name="worker.tasks.health_check")
def health_check():
    """Worker health check task"""
    from utils.gpu_monitor import get_gpu_info

    gpu_info = get_gpu_info()

    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "gpu_count": len(gpu_info),
        "gpus": [
            {
                "name": g["name"],
                "utilization": g["utilization"],
                "memory_percent": g["memory_percent"]
            }
            for g in gpu_info
        ]
    }
