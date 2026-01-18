"""
WebSocket Connection Manager

Manages WebSocket connections for real-time processing updates.
"""

from typing import Dict, List
from fastapi import WebSocket

from utils.logger import get_logger

logger = get_logger(__name__)


class WebSocketManager:
    """
    Manages WebSocket connections for real-time updates.

    Features:
    - Per-scan connection grouping
    - Broadcast to all connections for a scan
    - Automatic cleanup on disconnect
    """

    def __init__(self):
        # Map scan_id -> list of WebSocket connections
        self.connections: Dict[str, List[WebSocket]] = {}

    async def connect(self, scan_id: str, websocket: WebSocket):
        """Accept and register a WebSocket connection"""
        await websocket.accept()

        if scan_id not in self.connections:
            self.connections[scan_id] = []

        self.connections[scan_id].append(websocket)

        logger.info(f"WebSocket connected for scan: {scan_id}")

    def disconnect(self, scan_id: str, websocket: WebSocket):
        """Remove a WebSocket connection"""
        if scan_id in self.connections:
            if websocket in self.connections[scan_id]:
                self.connections[scan_id].remove(websocket)

            # Clean up empty lists
            if not self.connections[scan_id]:
                del self.connections[scan_id]

        logger.info(f"WebSocket disconnected for scan: {scan_id}")

    async def broadcast(self, scan_id: str, message: dict):
        """Broadcast message to all connections for a scan"""
        if scan_id not in self.connections:
            return

        disconnected = []

        for websocket in self.connections[scan_id]:
            try:
                await websocket.send_json(message)
            except Exception as e:
                logger.warning(f"Failed to send to WebSocket: {e}")
                disconnected.append(websocket)

        # Clean up disconnected
        for ws in disconnected:
            self.disconnect(scan_id, ws)

    async def send_to_connection(self, websocket: WebSocket, message: dict):
        """Send message to a specific connection"""
        try:
            await websocket.send_json(message)
        except Exception as e:
            logger.warning(f"Failed to send to WebSocket: {e}")

    def get_connection_count(self, scan_id: str) -> int:
        """Get number of active connections for a scan"""
        return len(self.connections.get(scan_id, []))

    def get_total_connections(self) -> int:
        """Get total number of active connections"""
        return sum(len(conns) for conns in self.connections.values())
