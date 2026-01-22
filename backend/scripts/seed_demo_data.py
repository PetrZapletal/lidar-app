#!/usr/bin/env python3
"""
Seed demo data for testing the admin dashboard.
"""

import os
import sys
import json
import asyncio
from datetime import datetime, timedelta
from pathlib import Path
import random
import uuid

# Add parent to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from services.storage import StorageService
from services.log_storage import get_log_storage

# Demo scan data
DEMO_SCANS = [
    {
        "name": "Obývací pokoj",
        "device_model": "iPhone 15 Pro",
        "status": "completed",
        "progress": 100,
        "stage": "export",
        "point_count": 2450000,
        "days_ago": 0
    },
    {
        "name": "Kuchyně",
        "device_model": "iPhone 14 Pro Max",
        "status": "completed",
        "progress": 100,
        "stage": "export",
        "point_count": 1890000,
        "days_ago": 1
    },
    {
        "name": "Ložnice",
        "device_model": "iPhone 15 Pro",
        "status": "processing",
        "progress": 65,
        "stage": "mesh_extraction",
        "point_count": 2100000,
        "days_ago": 0
    },
    {
        "name": "Garáž",
        "device_model": "iPad Pro 12.9",
        "status": "processing",
        "progress": 23,
        "stage": "gaussian_splatting",
        "point_count": 3200000,
        "days_ago": 0
    },
    {
        "name": "Zahrada - terasa",
        "device_model": "iPhone 15 Pro Max",
        "status": "uploaded",
        "progress": 0,
        "stage": "pending",
        "point_count": 4500000,
        "days_ago": 0
    },
    {
        "name": "Kancelář",
        "device_model": "iPhone 14 Pro",
        "status": "completed",
        "progress": 100,
        "stage": "export",
        "point_count": 1650000,
        "days_ago": 2
    },
    {
        "name": "Dětský pokoj",
        "device_model": "iPhone 15",
        "status": "failed",
        "progress": 45,
        "stage": "gaussian_splatting",
        "point_count": 980000,
        "error": "Insufficient points for reconstruction",
        "days_ago": 1
    },
    {
        "name": "Koupelna",
        "device_model": "iPhone 15 Pro",
        "status": "completed",
        "progress": 100,
        "stage": "export",
        "point_count": 890000,
        "days_ago": 3
    },
    {
        "name": "Sklep",
        "device_model": "iPad Pro 11",
        "status": "completed",
        "progress": 100,
        "stage": "export",
        "point_count": 1200000,
        "days_ago": 4
    },
    {
        "name": "Půda",
        "device_model": "iPhone 14",
        "status": "failed",
        "progress": 12,
        "stage": "preprocessing",
        "point_count": 450000,
        "error": "Low light conditions - poor point cloud quality",
        "days_ago": 2
    }
]


async def seed_data():
    """Create demo scan data"""
    storage = StorageService()
    log_storage = get_log_storage()

    print("Seeding demo data...")

    for scan_info in DEMO_SCANS:
        scan_id = str(uuid.uuid4())[:8]
        created_at = datetime.utcnow() - timedelta(days=scan_info["days_ago"], hours=random.randint(0, 12))

        metadata = {
            "id": scan_id,
            "name": scan_info["name"],
            "device_id": f"device_{random.randint(1000, 9999)}",
            "device_model": scan_info["device_model"],
            "status": scan_info["status"],
            "progress": scan_info["progress"],
            "stage": scan_info["stage"],
            "point_count": scan_info["point_count"],
            "created_at": created_at,
            "updated_at": created_at + timedelta(minutes=random.randint(5, 60)),
            "scan_duration": random.randint(60, 300),
            "settings": {
                "mode": random.choice(["interior", "exterior", "object"]),
                "quality": random.choice(["high", "medium"]),
                "texture_enabled": True
            }
        }

        if "error" in scan_info:
            metadata["error"] = scan_info["error"]

        # Save metadata
        await storage.save_scan_metadata(scan_id, metadata)

        # Add some logs
        log_storage.add_log(
            level="info",
            message=f"Scan '{scan_info['name']}' created",
            category="scan",
            scan_id=scan_id
        )

        if scan_info["status"] == "completed":
            log_storage.add_log(
                level="info",
                message=f"Processing completed successfully",
                category="processing",
                scan_id=scan_id
            )
        elif scan_info["status"] == "failed":
            log_storage.add_log(
                level="error",
                message=scan_info.get("error", "Unknown error"),
                category="processing",
                scan_id=scan_id
            )

        print(f"  Created: {scan_info['name']} ({scan_id}) - {scan_info['status']}")

    # Add some general system logs
    log_storage.add_log(
        level="info",
        message="Backend server started",
        category="system"
    )
    log_storage.add_log(
        level="info",
        message="Connected to Redis",
        category="system"
    )
    log_storage.add_log(
        level="warning",
        message="GPU not detected, using CPU fallback",
        category="system"
    )

    print(f"\nCreated {len(DEMO_SCANS)} demo scans")
    print("Dashboard should now show real data!")


if __name__ == "__main__":
    asyncio.run(seed_data())
