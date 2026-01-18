"""
Storage Service

Handles file storage and scan metadata persistence.
Supports local filesystem and S3-compatible storage.
"""

import os
import json
import aiofiles
from pathlib import Path
from typing import Optional
from datetime import datetime

from fastapi import UploadFile
from utils.logger import get_logger

logger = get_logger(__name__)


class StorageService:
    """
    Storage service for scan data and metadata.

    Supports:
    - Local filesystem storage
    - S3-compatible object storage (optional)
    """

    def __init__(
        self,
        base_path: str = "/data/scans",
        use_s3: bool = False,
        s3_bucket: Optional[str] = None
    ):
        self.base_path = Path(base_path)
        self.base_path.mkdir(parents=True, exist_ok=True)

        self.use_s3 = use_s3
        self.s3_bucket = s3_bucket
        self.s3_client = None

        if use_s3:
            self._init_s3()

    def _init_s3(self):
        """Initialize S3 client"""
        try:
            import boto3
            self.s3_client = boto3.client('s3')
            logger.info(f"S3 storage initialized with bucket: {self.s3_bucket}")
        except ImportError:
            logger.warning("boto3 not installed, falling back to local storage")
            self.use_s3 = False

    # ========================================================================
    # Scan Metadata
    # ========================================================================

    async def save_scan_metadata(self, scan_id: str, metadata: dict):
        """Save scan metadata to JSON file"""
        scan_dir = self.base_path / scan_id
        scan_dir.mkdir(parents=True, exist_ok=True)

        metadata_path = scan_dir / "scan_metadata.json"

        # Convert datetime objects to ISO format
        serializable = self._make_serializable(metadata)

        async with aiofiles.open(metadata_path, 'w') as f:
            await f.write(json.dumps(serializable, indent=2))

        logger.debug(f"Saved metadata for scan: {scan_id}")

    async def get_scan_metadata(self, scan_id: str) -> Optional[dict]:
        """Load scan metadata from JSON file"""
        metadata_path = self.base_path / scan_id / "scan_metadata.json"

        if not metadata_path.exists():
            return None

        async with aiofiles.open(metadata_path, 'r') as f:
            content = await f.read()
            metadata = json.loads(content)

        # Convert ISO strings back to datetime
        if 'created_at' in metadata:
            metadata['created_at'] = datetime.fromisoformat(metadata['created_at'])
        if 'updated_at' in metadata:
            metadata['updated_at'] = datetime.fromisoformat(metadata['updated_at'])

        return metadata

    async def list_scans(self, limit: int = 100, offset: int = 0) -> list:
        """List all scans"""
        scans = []

        for scan_dir in sorted(self.base_path.iterdir(), reverse=True):
            if scan_dir.is_dir():
                metadata = await self.get_scan_metadata(scan_dir.name)
                if metadata:
                    scans.append(metadata)

        return scans[offset:offset + limit]

    async def delete_scan(self, scan_id: str) -> bool:
        """Delete a scan and all its files"""
        scan_dir = self.base_path / scan_id

        if not scan_dir.exists():
            return False

        import shutil
        shutil.rmtree(scan_dir)

        logger.info(f"Deleted scan: {scan_id}")
        return True

    def get_scan_directory(self, scan_id: str) -> Path:
        """Get the directory path for a scan"""
        return self.base_path / scan_id

    # ========================================================================
    # File Upload
    # ========================================================================

    async def save_upload(
        self,
        scan_id: str,
        filename: str,
        file: UploadFile
    ) -> str:
        """Save uploaded file to scan directory"""
        scan_dir = self.base_path / scan_id
        file_path = scan_dir / filename

        # Create subdirectories if needed
        file_path.parent.mkdir(parents=True, exist_ok=True)

        # Save file
        async with aiofiles.open(file_path, 'wb') as f:
            while chunk := await file.read(1024 * 1024):  # 1MB chunks
                await f.write(chunk)

        logger.debug(f"Saved file: {file_path}")

        return str(file_path)

    async def get_file_path(self, scan_id: str, filename: str) -> Optional[Path]:
        """Get full path for a scan file"""
        file_path = self.base_path / scan_id / filename

        if file_path.exists():
            return file_path
        return None

    # ========================================================================
    # Chunked Upload Support
    # ========================================================================

    async def init_chunked_upload(
        self,
        scan_id: str,
        filename: str,
        total_size: int,
        chunk_size: int
    ) -> str:
        """Initialize a chunked upload session"""
        upload_id = f"{scan_id}_{filename}_{datetime.utcnow().timestamp()}"

        upload_info = {
            "upload_id": upload_id,
            "scan_id": scan_id,
            "filename": filename,
            "total_size": total_size,
            "chunk_size": chunk_size,
            "chunks_received": [],
            "status": "in_progress"
        }

        # Save upload info
        uploads_dir = self.base_path / ".uploads"
        uploads_dir.mkdir(exist_ok=True)

        async with aiofiles.open(uploads_dir / f"{upload_id}.json", 'w') as f:
            await f.write(json.dumps(upload_info))

        return upload_id

    async def save_chunk(
        self,
        upload_id: str,
        chunk_index: int,
        chunk_data: bytes
    ) -> dict:
        """Save a chunk of a chunked upload"""
        uploads_dir = self.base_path / ".uploads"
        info_path = uploads_dir / f"{upload_id}.json"

        if not info_path.exists():
            raise ValueError(f"Upload not found: {upload_id}")

        # Load upload info
        async with aiofiles.open(info_path, 'r') as f:
            upload_info = json.loads(await f.read())

        # Save chunk
        chunk_path = uploads_dir / f"{upload_id}_chunk_{chunk_index:06d}"
        async with aiofiles.open(chunk_path, 'wb') as f:
            await f.write(chunk_data)

        # Update info
        upload_info["chunks_received"].append(chunk_index)
        upload_info["chunks_received"].sort()

        async with aiofiles.open(info_path, 'w') as f:
            await f.write(json.dumps(upload_info))

        # Check if complete
        expected_chunks = -(-upload_info["total_size"] // upload_info["chunk_size"])
        is_complete = len(upload_info["chunks_received"]) == expected_chunks

        return {
            "chunks_received": len(upload_info["chunks_received"]),
            "total_chunks": expected_chunks,
            "is_complete": is_complete
        }

    async def finalize_chunked_upload(self, upload_id: str) -> str:
        """Combine chunks into final file"""
        uploads_dir = self.base_path / ".uploads"
        info_path = uploads_dir / f"{upload_id}.json"

        async with aiofiles.open(info_path, 'r') as f:
            upload_info = json.loads(await f.read())

        # Create output path
        scan_dir = self.base_path / upload_info["scan_id"]
        scan_dir.mkdir(parents=True, exist_ok=True)
        output_path = scan_dir / upload_info["filename"]

        # Combine chunks
        async with aiofiles.open(output_path, 'wb') as out_file:
            for chunk_idx in sorted(upload_info["chunks_received"]):
                chunk_path = uploads_dir / f"{upload_id}_chunk_{chunk_idx:06d}"
                async with aiofiles.open(chunk_path, 'rb') as chunk_file:
                    await out_file.write(await chunk_file.read())
                # Delete chunk
                chunk_path.unlink()

        # Delete upload info
        info_path.unlink()

        logger.info(f"Finalized chunked upload: {output_path}")

        return str(output_path)

    # ========================================================================
    # Utilities
    # ========================================================================

    def _make_serializable(self, obj):
        """Convert object to JSON-serializable format"""
        if isinstance(obj, datetime):
            return obj.isoformat()
        elif isinstance(obj, dict):
            return {k: self._make_serializable(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [self._make_serializable(v) for v in obj]
        return obj
