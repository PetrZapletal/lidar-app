"""
Log Storage Service

Stores and retrieves processing logs and errors for debugging.
Uses file-based storage with JSON format.
"""

import json
import os
from datetime import datetime
from pathlib import Path
from typing import Optional, List
from dataclasses import dataclass, asdict
from collections import deque
import threading

from utils.logger import get_logger

logger = get_logger(__name__)


@dataclass
class LogEntry:
    """Single log entry"""
    timestamp: str
    level: str  # debug, info, warning, error
    category: str  # processing, upload, system, device
    message: str
    scan_id: Optional[str] = None
    device_id: Optional[str] = None
    details: Optional[dict] = None

    def to_dict(self) -> dict:
        return asdict(self)


class LogStorageService:
    """
    Manages log storage for scans and devices.

    Features:
    - In-memory ring buffer for recent logs (fast access)
    - File-based persistence per scan
    - Error aggregation and statistics
    """

    MAX_MEMORY_LOGS = 1000  # Per category
    MAX_FILE_LOGS = 10000   # Per scan

    def __init__(self, base_path: str = "./data/logs"):
        self.base_path = Path(base_path)
        self.base_path.mkdir(parents=True, exist_ok=True)

        # In-memory buffers (thread-safe)
        self._lock = threading.Lock()
        self._recent_logs: deque = deque(maxlen=self.MAX_MEMORY_LOGS)
        self._recent_errors: deque = deque(maxlen=500)
        self._scan_logs: dict[str, deque] = {}
        self._device_logs: dict[str, deque] = {}

        # Statistics
        self._stats = {
            "total_logs": 0,
            "total_errors": 0,
            "errors_by_category": {}
        }

    def add_log(
        self,
        level: str,
        category: str,
        message: str,
        scan_id: Optional[str] = None,
        device_id: Optional[str] = None,
        details: Optional[dict] = None
    ) -> LogEntry:
        """Add a log entry"""
        entry = LogEntry(
            timestamp=datetime.utcnow().isoformat(),
            level=level,
            category=category,
            message=message,
            scan_id=scan_id,
            device_id=device_id,
            details=details
        )

        with self._lock:
            # Add to recent logs
            self._recent_logs.append(entry)
            self._stats["total_logs"] += 1

            # Track errors separately
            if level == "error":
                self._recent_errors.append(entry)
                self._stats["total_errors"] += 1
                self._stats["errors_by_category"][category] = \
                    self._stats["errors_by_category"].get(category, 0) + 1

            # Add to scan-specific buffer
            if scan_id:
                if scan_id not in self._scan_logs:
                    self._scan_logs[scan_id] = deque(maxlen=self.MAX_MEMORY_LOGS)
                self._scan_logs[scan_id].append(entry)

            # Add to device-specific buffer
            if device_id:
                if device_id not in self._device_logs:
                    self._device_logs[device_id] = deque(maxlen=self.MAX_MEMORY_LOGS)
                self._device_logs[device_id].append(entry)

        # Persist to file (async would be better but keeping it simple)
        if scan_id:
            self._persist_scan_log(scan_id, entry)

        return entry

    def get_recent_logs(
        self,
        limit: int = 100,
        level: Optional[str] = None,
        category: Optional[str] = None
    ) -> List[dict]:
        """Get recent logs with optional filtering"""
        with self._lock:
            logs = list(self._recent_logs)

        # Filter
        if level:
            logs = [l for l in logs if l.level == level]
        if category:
            logs = [l for l in logs if l.category == category]

        # Return newest first, limited
        logs = sorted(logs, key=lambda x: x.timestamp, reverse=True)
        return [l.to_dict() for l in logs[:limit]]

    def get_recent_errors(self, limit: int = 50) -> List[dict]:
        """Get recent errors"""
        with self._lock:
            errors = list(self._recent_errors)

        errors = sorted(errors, key=lambda x: x.timestamp, reverse=True)
        return [e.to_dict() for e in errors[:limit]]

    def get_scan_logs(self, scan_id: str, limit: int = 200) -> List[dict]:
        """Get logs for a specific scan"""
        # First check memory
        with self._lock:
            if scan_id in self._scan_logs:
                logs = list(self._scan_logs[scan_id])
                logs = sorted(logs, key=lambda x: x.timestamp, reverse=True)
                return [l.to_dict() for l in logs[:limit]]

        # Fall back to file
        return self._load_scan_logs(scan_id, limit)

    def get_device_logs(self, device_id: str, limit: int = 200) -> List[dict]:
        """Get logs for a specific device"""
        with self._lock:
            if device_id in self._device_logs:
                logs = list(self._device_logs[device_id])
                logs = sorted(logs, key=lambda x: x.timestamp, reverse=True)
                return [l.to_dict() for l in logs[:limit]]
        return []

    def get_statistics(self) -> dict:
        """Get log statistics"""
        with self._lock:
            return {
                **self._stats,
                "memory_logs": len(self._recent_logs),
                "memory_errors": len(self._recent_errors),
                "tracked_scans": len(self._scan_logs),
                "tracked_devices": len(self._device_logs)
            }

    def _persist_scan_log(self, scan_id: str, entry: LogEntry):
        """Persist log entry to file"""
        try:
            log_dir = self.base_path / "scans"
            log_dir.mkdir(exist_ok=True)
            log_file = log_dir / f"{scan_id}.jsonl"

            with open(log_file, "a") as f:
                f.write(json.dumps(entry.to_dict()) + "\n")

        except Exception as e:
            logger.warning(f"Failed to persist log: {e}")

    def _load_scan_logs(self, scan_id: str, limit: int) -> List[dict]:
        """Load scan logs from file"""
        log_file = self.base_path / "scans" / f"{scan_id}.jsonl"

        if not log_file.exists():
            return []

        try:
            logs = []
            with open(log_file, "r") as f:
                for line in f:
                    if line.strip():
                        logs.append(json.loads(line))

            # Return newest first
            logs = sorted(logs, key=lambda x: x.get("timestamp", ""), reverse=True)
            return logs[:limit]

        except Exception as e:
            logger.error(f"Failed to load scan logs: {e}")
            return []

    def clear_scan_logs(self, scan_id: str):
        """Clear logs for a scan"""
        with self._lock:
            if scan_id in self._scan_logs:
                del self._scan_logs[scan_id]

        log_file = self.base_path / "scans" / f"{scan_id}.jsonl"
        if log_file.exists():
            log_file.unlink()

    def clear_device_logs(self, device_id: str):
        """Clear logs for a device"""
        with self._lock:
            if device_id in self._device_logs:
                del self._device_logs[device_id]


# Singleton instance
_log_storage: Optional[LogStorageService] = None


def get_log_storage() -> LogStorageService:
    """Get or create log storage singleton"""
    global _log_storage
    if _log_storage is None:
        data_dir = os.getenv("DATA_DIR", "./data")
        _log_storage = LogStorageService(base_path=f"{data_dir}/logs")
    return _log_storage


# Convenience functions
def log_processing(
    message: str,
    scan_id: str,
    level: str = "info",
    details: Optional[dict] = None
):
    """Log a processing event"""
    get_log_storage().add_log(
        level=level,
        category="processing",
        message=message,
        scan_id=scan_id,
        details=details
    )


def log_upload(
    message: str,
    scan_id: Optional[str] = None,
    device_id: Optional[str] = None,
    level: str = "info",
    details: Optional[dict] = None
):
    """Log an upload event"""
    get_log_storage().add_log(
        level=level,
        category="upload",
        message=message,
        scan_id=scan_id,
        device_id=device_id,
        details=details
    )


def log_device(
    message: str,
    device_id: str,
    level: str = "info",
    details: Optional[dict] = None
):
    """Log a device event"""
    get_log_storage().add_log(
        level=level,
        category="device",
        message=message,
        device_id=device_id,
        details=details
    )


def log_error(
    message: str,
    category: str = "system",
    scan_id: Optional[str] = None,
    device_id: Optional[str] = None,
    details: Optional[dict] = None
):
    """Log an error"""
    get_log_storage().add_log(
        level="error",
        category=category,
        message=message,
        scan_id=scan_id,
        device_id=device_id,
        details=details
    )
