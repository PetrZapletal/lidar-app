"""
GPU Monitoring Module

Real-time GPU monitoring using nvidia-smi.
Provides memory usage, utilization, temperature, and power stats.
"""

import subprocess
import xml.etree.ElementTree as ET
from typing import List, Dict, Optional
from dataclasses import dataclass
import psutil
import os
from datetime import datetime

from utils.logger import get_logger

logger = get_logger(__name__)


@dataclass
class GPUInfo:
    """GPU information container"""
    index: int
    name: str
    uuid: str
    status: str
    utilization: int  # percentage
    memory_used: float  # GB
    memory_total: float  # GB
    memory_percent: int
    temp: int  # Celsius
    power: int  # Watts
    power_limit: int  # Watts
    current_job: Optional[Dict] = None


@dataclass
class SystemInfo:
    """System information container"""
    cpu: int  # percentage
    memory_used: float  # GB
    memory_total: float  # GB
    memory_percent: int
    disk_used: float  # GB
    disk_total: float  # GB
    disk_percent: int
    uptime: str
    started_at: str


class GPUMonitor:
    """Monitor for NVIDIA GPUs using nvidia-smi"""

    def __init__(self):
        self._nvidia_smi_available = self._check_nvidia_smi()
        self._start_time = datetime.utcnow()

    def _check_nvidia_smi(self) -> bool:
        """Check if nvidia-smi is available"""
        try:
            result = subprocess.run(
                ["nvidia-smi", "--version"],
                capture_output=True,
                text=True,
                timeout=5
            )
            return result.returncode == 0
        except (FileNotFoundError, subprocess.TimeoutExpired):
            logger.warning("nvidia-smi not available - GPU monitoring disabled")
            return False

    def get_gpu_info(self) -> List[GPUInfo]:
        """Get information for all GPUs"""
        if not self._nvidia_smi_available:
            return self._get_mock_gpu_info()

        try:
            result = subprocess.run(
                ["nvidia-smi", "-q", "-x"],
                capture_output=True,
                text=True,
                timeout=10
            )

            if result.returncode != 0:
                logger.error(f"nvidia-smi failed: {result.stderr}")
                return self._get_mock_gpu_info()

            return self._parse_nvidia_smi_xml(result.stdout)

        except subprocess.TimeoutExpired:
            logger.error("nvidia-smi timed out")
            return self._get_mock_gpu_info()
        except Exception as e:
            logger.error(f"GPU monitoring error: {e}")
            return self._get_mock_gpu_info()

    def _parse_nvidia_smi_xml(self, xml_output: str) -> List[GPUInfo]:
        """Parse nvidia-smi XML output"""
        gpus = []

        try:
            root = ET.fromstring(xml_output)

            for idx, gpu in enumerate(root.findall("gpu")):
                # GPU identification
                name = gpu.find("product_name").text or "Unknown GPU"
                uuid = gpu.find("uuid").text or ""

                # Utilization
                utilization = gpu.find("utilization")
                gpu_util = self._parse_percentage(
                    utilization.find("gpu_util").text if utilization is not None else "0 %"
                )

                # Memory
                memory = gpu.find("fb_memory_usage")
                if memory is not None:
                    mem_used = self._parse_memory(memory.find("used").text)
                    mem_total = self._parse_memory(memory.find("total").text)
                else:
                    mem_used = 0
                    mem_total = 0

                mem_percent = int((mem_used / mem_total * 100) if mem_total > 0 else 0)

                # Temperature
                temp_elem = gpu.find("temperature")
                temp = 0
                if temp_elem is not None:
                    gpu_temp = temp_elem.find("gpu_temp")
                    if gpu_temp is not None:
                        temp = self._parse_temperature(gpu_temp.text)

                # Power
                power_elem = gpu.find("gpu_power_readings")
                power = 0
                power_limit = 0
                if power_elem is not None:
                    power_draw = power_elem.find("power_draw")
                    if power_draw is not None:
                        power = self._parse_power(power_draw.text)
                    power_lim = power_elem.find("current_power_limit")
                    if power_lim is not None:
                        power_limit = self._parse_power(power_lim.text)

                # Determine status
                status = "idle"
                if gpu_util > 10:
                    status = "active"
                elif gpu_util > 0:
                    status = "low_usage"

                gpus.append(GPUInfo(
                    index=idx,
                    name=name,
                    uuid=uuid,
                    status=status,
                    utilization=gpu_util,
                    memory_used=round(mem_used, 1),
                    memory_total=round(mem_total, 1),
                    memory_percent=mem_percent,
                    temp=temp,
                    power=power,
                    power_limit=power_limit
                ))

        except ET.ParseError as e:
            logger.error(f"Failed to parse nvidia-smi XML: {e}")

        return gpus

    def _parse_percentage(self, value: str) -> int:
        """Parse percentage string like '78 %'"""
        try:
            return int(value.replace("%", "").strip())
        except (ValueError, AttributeError):
            return 0

    def _parse_memory(self, value: str) -> float:
        """Parse memory string like '8192 MiB' to GB"""
        try:
            value = value.strip()
            if "MiB" in value:
                return float(value.replace("MiB", "").strip()) / 1024
            elif "GiB" in value:
                return float(value.replace("GiB", "").strip())
            return float(value) / 1024
        except (ValueError, AttributeError):
            return 0

    def _parse_temperature(self, value: str) -> int:
        """Parse temperature string like '72 C'"""
        try:
            return int(value.replace("C", "").strip())
        except (ValueError, AttributeError):
            return 0

    def _parse_power(self, value: str) -> int:
        """Parse power string like '320.00 W'"""
        try:
            return int(float(value.replace("W", "").strip()))
        except (ValueError, AttributeError):
            return 0

    def _get_mock_gpu_info(self) -> List[GPUInfo]:
        """Return mock GPU data for development/testing"""
        return [
            GPUInfo(
                index=0,
                name="NVIDIA RTX 4090 (Mock)",
                uuid="GPU-mock-0000",
                status="active",
                utilization=78,
                memory_used=18.2,
                memory_total=24.0,
                memory_percent=76,
                temp=72,
                power=320,
                power_limit=450,
                current_job={
                    "name": "Office Scan",
                    "stage": "3D Gaussian Splatting"
                }
            )
        ]

    def get_system_info(self) -> SystemInfo:
        """Get system (CPU, RAM, disk) information"""
        try:
            # CPU
            cpu_percent = psutil.cpu_percent(interval=0.1)

            # Memory
            memory = psutil.virtual_memory()
            mem_used = memory.used / (1024**3)
            mem_total = memory.total / (1024**3)

            # Disk
            disk = psutil.disk_usage("/")
            disk_used = disk.used / (1024**3)
            disk_total = disk.total / (1024**3)

            # Uptime
            uptime_seconds = (datetime.utcnow() - self._start_time).total_seconds()
            uptime = self._format_uptime(uptime_seconds)

            return SystemInfo(
                cpu=int(cpu_percent),
                memory_used=round(mem_used, 1),
                memory_total=round(mem_total, 1),
                memory_percent=int(memory.percent),
                disk_used=round(disk_used, 1),
                disk_total=round(disk_total, 1),
                disk_percent=int(disk.percent),
                uptime=uptime,
                started_at=self._start_time.strftime("%d.%m.%Y")
            )

        except Exception as e:
            logger.error(f"System monitoring error: {e}")
            return SystemInfo(
                cpu=0,
                memory_used=0,
                memory_total=0,
                memory_percent=0,
                disk_used=0,
                disk_total=0,
                disk_percent=0,
                uptime="N/A",
                started_at="N/A"
            )

    def _format_uptime(self, seconds: float) -> str:
        """Format uptime seconds to human readable string"""
        days = int(seconds // 86400)
        hours = int((seconds % 86400) // 3600)
        minutes = int((seconds % 3600) // 60)

        if days > 0:
            return f"{days}d {hours}h {minutes}m"
        elif hours > 0:
            return f"{hours}h {minutes}m"
        else:
            return f"{minutes}m"


# Global monitor instance
_monitor: Optional[GPUMonitor] = None


def get_gpu_monitor() -> GPUMonitor:
    """Get the global GPU monitor instance"""
    global _monitor
    if _monitor is None:
        _monitor = GPUMonitor()
    return _monitor


def get_gpu_info() -> List[Dict]:
    """Get GPU info as list of dictionaries"""
    monitor = get_gpu_monitor()
    gpus = monitor.get_gpu_info()

    return [
        {
            "name": gpu.name,
            "status": gpu.status,
            "utilization": gpu.utilization,
            "memory_used": gpu.memory_used,
            "memory_total": gpu.memory_total,
            "memory_percent": gpu.memory_percent,
            "temp": gpu.temp,
            "power": gpu.power,
            "power_limit": gpu.power_limit,
            "current_job": gpu.current_job
        }
        for gpu in gpus
    ]


def get_system_info() -> Dict:
    """Get system info as dictionary"""
    monitor = get_gpu_monitor()
    info = monitor.get_system_info()

    return {
        "cpu": info.cpu,
        "memory_used": info.memory_used,
        "memory_total": info.memory_total,
        "memory_percent": info.memory_percent,
        "disk_used": info.disk_used,
        "disk_total": info.disk_total,
        "disk_percent": info.disk_percent,
        "uptime": info.uptime,
        "started_at": info.started_at
    }
