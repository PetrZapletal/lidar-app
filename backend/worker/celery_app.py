"""
Celery Application Configuration

Background task processing for 3D scan pipeline.
"""

import os
from celery import Celery

# Redis URL from environment
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")

# Initialize Celery
celery_app = Celery(
    "lidar_scanner",
    broker=REDIS_URL,
    backend=REDIS_URL,
    include=["worker.tasks"]
)

# Configuration
celery_app.conf.update(
    # Task settings
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,

    # Task execution
    task_acks_late=True,
    task_reject_on_worker_lost=True,
    task_track_started=True,

    # Retry settings
    task_default_retry_delay=60,
    task_max_retries=3,

    # Result expiration (24 hours)
    result_expires=86400,

    # Concurrency (1 worker per GPU typically)
    worker_concurrency=int(os.getenv("CELERY_CONCURRENCY", "1")),

    # Prefetch (for GPU tasks, prefetch 1 at a time)
    worker_prefetch_multiplier=1,

    # Queue routing
    task_routes={
        "worker.tasks.process_scan": {"queue": "gpu"},
        "worker.tasks.export_model": {"queue": "cpu"},
        "worker.tasks.cleanup": {"queue": "cpu"},
    },

    # Default queue
    task_default_queue="cpu",

    # Beat schedule (periodic tasks)
    beat_schedule={
        "cleanup-old-scans": {
            "task": "worker.tasks.cleanup_old_scans",
            "schedule": 3600.0,  # Every hour
        },
        "update-gpu-stats": {
            "task": "worker.tasks.update_gpu_stats",
            "schedule": 30.0,  # Every 30 seconds
        },
    },
)

# Task priority
celery_app.conf.task_queue_max_priority = 10
celery_app.conf.task_default_priority = 5

if __name__ == "__main__":
    celery_app.start()
