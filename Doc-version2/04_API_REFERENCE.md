# 04 - API Reference

Complete API reference for the LiDAR 3D Scanner backend. The backend is built with **FastAPI** (Python 3.11) and serves both the iOS application and the admin web dashboard.

**Base URL (Development):** `https://100.96.188.18:8444`

---

## Table of Contents

1. [Root & Health](#1-root--health-mainpy)
2. [Scan CRUD](#2-scan-crud-mainpy)
3. [Standard Upload](#3-standard-upload-mainpy)
4. [Chunked Upload](#4-chunked-upload-mainpy)
5. [Processing](#5-processing-mainpy)
6. [Download](#6-download-mainpy)
7. [WebSocket - Real-time Updates](#7-websocket---real-time-updates-mainpy)
8. [iOS Authentication](#8-ios-authentication-ios_authpy)
9. [iOS User Management](#9-ios-user-management-ios_authpy)
10. [Admin Dashboard Auth](#10-admin-dashboard-auth-authpy)
11. [Admin Dashboard Pages](#11-admin-dashboard-pages-adminpy)
12. [Admin Dashboard API](#12-admin-dashboard-api-adminpy)
13. [Debug - Raw Data Upload](#13-debug---raw-data-upload-pipeline-1-debugpy)
14. [Debug - Event Streaming](#14-debug---event-streaming-pipeline-2-debugpy)
15. [Debug - Device Logs](#15-debug---device-logs-debugpy)
16. [Debug - Visualization](#16-debug---visualization-debugpy)
17. [Debug - Simple Pipeline Processing](#17-debug---simple-pipeline-processing-debugpy)
18. [Debug - Model Downloads](#18-debug---model-downloads-debugpy)
19. [Debug - Dashboard & Health](#19-debug---dashboard--health-debugpy)

---

## 1. Root & Health (`main.py`)

These endpoints are unauthenticated and used for connectivity checks.

| Method | Path | Description | Request Body | Response |
|--------|------|-------------|-------------|----------|
| GET | `/` | Root endpoint. Returns service name and version. | None | `{ "status": "healthy", "service": "LiDAR 3D Scanner API", "version": "1.0.0" }` |
| GET | `/health` | Health check endpoint for connectivity testing. | None | `{ "status": "healthy", "service": "LiDAR 3D Scanner API", "version": "1.0.0" }` |

---

## 2. Scan CRUD (`main.py`)

Core scan management endpoints. No authentication required in current implementation.

| Method | Path | Description | Request Body | Response |
|--------|------|-------------|-------------|----------|
| POST | `/api/v1/scans` | Create a new scan session. | `ScanCreate` (see below) | `ScanResponse` |
| GET | `/api/v1/scans` | List all scans. | None | `ScanResponse[]` |
| GET | `/api/v1/scans/{scan_id}` | Get scan details by ID. | None | `ScanResponse` |
| GET | `/api/v1/scans/{scan_id}/status` | Get current scan status. | None | `ScanResponse` |
| DELETE | `/api/v1/scans/{scan_id}` | Delete a scan and its data. | None | `{ "status": "deleted", "scan_id": "<id>" }` |

### Request Model: `ScanCreate`

```json
{
  "name": "string (required, 1-100 chars)",
  "description": "string (optional)",
  "device_info": { } // optional dict
}
```

### Response Model: `ScanResponse`

```json
{
  "id": "string (UUID)",
  "name": "string",
  "status": "created | uploaded | processing | completed | failed | cancelled",
  "created_at": "datetime",
  "updated_at": "datetime",
  "progress": 0.0,
  "stage": "string | null",
  "result_urls": { } // or null
  "error": "string | null"
}
```

---

## 3. Standard Upload (`main.py`)

Single-request upload for scan data files.

| Method | Path | Description | Request Body | Response |
|--------|------|-------------|-------------|----------|
| POST | `/api/v1/scans/{scan_id}/upload` | Upload scan data (point cloud, textures, metadata). | `multipart/form-data` (see below) | Upload result |

### Multipart Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `pointcloud` | File | Yes | Point cloud file (PLY format) |
| `metadata` | File | No | Metadata JSON file |
| `textures` | File[] | No | List of texture frame files |

### Response

```json
{
  "status": "success",
  "scan_id": "<id>",
  "files_uploaded": {
    "pointcloud": "<path>",
    "metadata": "<path> | null",
    "textures": 0
  }
}
```

---

## 4. Chunked Upload (`main.py`)

Multi-request chunked upload for large files, designed for the iOS app.

| Method | Path | Description | Request Body | Response |
|--------|------|-------------|-------------|----------|
| POST | `/api/v1/scans/{scan_id}/upload/init` | Initialize a chunked upload session. | `UploadInitRequest` | `UploadInitResponse` |
| PUT | `/api/v1/scans/{scan_id}/upload/chunk` | Upload a single chunk. | Raw binary body | Chunk receipt confirmation |
| POST | `/api/v1/scans/{scan_id}/upload/finalize` | Finalize chunked upload and assemble the file. | None | Finalization result |
| DELETE | `/api/v1/scans/{scan_id}/upload/cancel` | Cancel an ongoing chunked upload. | None | `{ "status": "cancelled" | "not_found", "scan_id": "<id>" }` |

### `UploadInitRequest`

```json
{
  "fileSize": 123456789,
  "chunkSize": 5242880,       // default: 5MB
  "contentType": "application/octet-stream"
}
```

### `UploadInitResponse`

```json
{
  "uploadId": "string (UUID)",
  "uploadedChunks": [],
  "expiresAt": "ISO datetime string"
}
```

### Chunk Upload Headers

| Header | Type | Required | Description |
|--------|------|----------|-------------|
| `X-Chunk-Index` | int | Yes | Zero-based chunk index |
| `X-Chunk-Offset` | int | No | Byte offset within the file (default: 0) |
| `X-Chunk-Size` | int | No | Size of this chunk in bytes (default: 0) |
| `X-Upload-Id` | string | No | Upload session ID (falls back to scan_id lookup) |

### Chunk Upload Response

```json
{
  "status": "chunk_received",
  "chunkIndex": 0,
  "bytesReceived": 5242880,
  "totalChunksReceived": 1,
  "totalChunksExpected": 10
}
```

### Finalize Response

```json
{
  "status": "finalized",
  "scan_id": "<id>",
  "totalBytes": 52428800
}
```

---

## 5. Processing (`main.py`)

| Method | Path | Description | Request Body | Response |
|--------|------|-------------|-------------|----------|
| POST | `/api/v1/scans/{scan_id}/process` | Start the AI processing pipeline. Scan must be in `uploaded` or `failed` status. | `ProcessingOptions` | Processing started confirmation |

### `ProcessingOptions`

```json
{
  "enable_gaussian_splatting": true,
  "enable_mesh_extraction": true,
  "enable_texture_baking": true,
  "mesh_resolution": "high",         // "low" | "medium" | "high"
  "texture_resolution": 4096,
  "output_formats": ["usdz", "gltf", "obj"]
}
```

### Response

```json
{
  "status": "processing_started",
  "scan_id": "<id>",
  "message": "Processing started. Connect to WebSocket for real-time updates."
}
```

---

## 6. Download (`main.py`)

| Method | Path | Description | Request Body | Response |
|--------|------|-------------|-------------|----------|
| GET | `/api/v1/scans/{scan_id}/download` | Download processed 3D model. Scan must be in `completed` status. | None | File download (`application/octet-stream`) |

### Query Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `format` | string | `"usdz"` | Output format. Must be one of the formats available in `result_urls`. |

---

## 7. WebSocket - Real-time Updates (`main.py`)

### General WebSocket

| Protocol | Path | Description |
|----------|------|-------------|
| WS | `/ws` | General WebSocket endpoint with subscription mechanism for the iOS app. |

**Message Types (Client -> Server):**

| Message | Description |
|---------|-------------|
| `"ping"` | Keepalive ping. Server responds with `"pong"`. |
| `{ "type": "subscribe", "scanId": "<id>" }` | Subscribe to updates for a scan. Server sends current status immediately. |
| `{ "type": "unsubscribe", "scanId": "<id>" }` | Unsubscribe from a scan's updates. |

**Message Types (Server -> Client):**

```json
{
  "type": "processing_update",
  "data": {
    "scan_id": "<id>",
    "progress": 0.5,
    "stage": "gaussian_splatting",
    "status": "processing"
  }
}
```

### Scan-specific WebSocket

| Protocol | Path | Description |
|----------|------|-------------|
| WS | `/ws/scans/{scan_id}` | WebSocket endpoint for real-time processing updates for a specific scan. Sends current status on connect. Supports `"ping"` / `"pong"` keepalive. |

**Message Types (Server -> Client):**

- `processing_update` -- progress, stage, and status updates during processing.
- `error` -- error notification with code and message when processing fails.

```json
{
  "type": "processing_update",
  "data": {
    "scan_id": "<id>",
    "progress": 1.0,
    "stage": "completed",
    "status": "completed",
    "result_urls": { "usdz": "...", "gltf": "...", "obj": "..." }
  }
}
```

```json
{
  "type": "error",
  "data": {
    "scan_id": "<id>",
    "code": "processing_failed",
    "message": "Error description"
  }
}
```

---

## 8. iOS Authentication (`ios_auth.py`)

JWT-based authentication for the iOS app. Uses `Authorization: Bearer <token>` header. All endpoints are prefixed with `/api/v1`.

> **Note:** In the current development build, login and register accept any credentials and return a mock user.

| Method | Path | Description | Auth Required | Request Body | Response |
|--------|------|-------------|:---:|-------------|----------|
| POST | `/api/v1/auth/login` | Login with email and password. | No | `LoginRequest` | `AuthResponse` |
| POST | `/api/v1/auth/register` | Register a new user. | No | `RegisterRequest` | `AuthResponse` |
| POST | `/api/v1/auth/refresh` | Refresh access token using refresh token. | No | `RefreshTokenRequest` | `TokensResponse` |
| POST | `/api/v1/auth/logout` | Logout and invalidate token (mock). | No | None | `{ "status": "success", "message": "Logged out successfully" }` |
| POST | `/api/v1/auth/forgot-password` | Request password reset (mock). | No | Query: `email` (string) | `{ "status": "success", "message": "Password reset email sent" }` |
| POST | `/api/v1/auth/apple` | Sign in with Apple (mock). | No | Query: `identityToken` (string), `authorizationCode` (string) | `AuthResponse` |

### `LoginRequest`

```json
{
  "email": "user@example.com",
  "password": "password123"
}
```

### `RegisterRequest`

```json
{
  "email": "user@example.com",
  "password": "password123",
  "displayName": "John Doe"   // optional
}
```

### `RefreshTokenRequest`

```json
{
  "refreshToken": "refresh_<base64>.<signature>"
}
```

### `AuthResponse`

```json
{
  "user": {
    "id": "test-user-1",
    "email": "user@example.com",
    "displayName": "Test User",
    "avatarURL": null,
    "createdAt": "ISO datetime",
    "subscription": "pro",
    "scanCredits": 999,
    "preferences": {
      "measurementUnit": "meters",
      "autoUpload": true,
      "hapticFeedback": true,
      "showTutorials": false,
      "defaultExportFormat": "usdz",
      "scanQuality": "balanced"
    }
  },
  "tokens": {
    "accessToken": "<base64>.<signature>",
    "refreshToken": "refresh_<base64>.<signature>",
    "expiresAt": "ISO datetime"
  }
}
```

### `TokensResponse`

```json
{
  "accessToken": "<base64>.<signature>",
  "refreshToken": "refresh_<base64>.<signature>",
  "expiresAt": "ISO datetime"
}
```

---

## 9. iOS User Management (`ios_auth.py`)

All endpoints require `Authorization: Bearer <access_token>` header. Returns HTTP 401 if unauthorized.

| Method | Path | Description | Auth Required | Request Body | Response |
|--------|------|-------------|:---:|-------------|----------|
| GET | `/api/v1/users/me` | Get current user profile. | Yes | None | `UserResponse` |
| PUT | `/api/v1/users/me/preferences` | Update user preferences. | Yes | `UpdatePreferencesRequest` | `{ "status": "success", "message": "Preferences updated" }` |
| GET | `/api/v1/users/me/scans` | Get scans for current user. | Yes | None | `ScanResponse[]` |

### `UpdatePreferencesRequest`

All fields are optional; only provided fields are updated.

```json
{
  "measurementUnit": "meters",
  "autoUpload": true,
  "hapticFeedback": true,
  "showTutorials": false,
  "defaultExportFormat": "usdz",
  "scanQuality": "balanced"
}
```

---

## 10. Admin Dashboard Auth (`auth.py`)

Cookie-based session authentication for the admin web dashboard. Uses an `admin_session` HTTP-only cookie.

| Method | Path | Description | Auth Required | Request Body | Response |
|--------|------|-------------|:---:|-------------|----------|
| GET | `/login` | Serve the login page (HTML). | No | None | HTML page |
| POST | `/login` | Process login form submission. | No | Form: `username`, `password`, `next` (redirect path) | Redirect (303) with session cookie |
| GET | `/logout` | Logout and clear session cookie. | No | None | Redirect to `/login` |
| GET | `/api/auth/check` | Check if user is authenticated (AJAX). | No | None | `{ "authenticated": true, "username": "admin" }` or `{ "authenticated": false }` |

### Login Query Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `next` | string | `"/admin"` | URL to redirect to after successful login |
| `error` | string | None | Error type to display (e.g., `"invalid"`) |

---

## 11. Admin Dashboard Pages (`admin.py`)

All dashboard pages require admin session authentication (cookie-based). Unauthenticated requests are redirected to `/login`. All responses are HTML pages.

| Method | Path | Description | Auth Required | Query Parameters |
|--------|------|-------------|:---:|------------------|
| GET | `/admin/` | Main dashboard page with stats, active scans, GPU info, chart. | Yes | None |
| GET | `/admin/scans` | Scans list page with filtering and pagination. | Yes | `page` (int, default 1), `per_page` (int, default 20), `status` (string, optional), `search` (string, optional) |
| GET | `/admin/scans/{scan_id}` | Scan detail page with files, logs, and metadata. | Yes | None |
| GET | `/admin/processing` | Processing queue page with active and pending jobs. | Yes | None |
| GET | `/admin/logs` | Logs viewer page with error statistics. | Yes | None |
| GET | `/admin/system` | System status page with GPU, services, configuration. | Yes | None |

### Scans List Query Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `page` | int | 1 | Page number (1-based) |
| `per_page` | int | 20 | Items per page |
| `status` | string | None | Filter by scan status (e.g., `"completed"`, `"processing"`, `"failed"`) |
| `search` | string | None | Search by scan name or ID (case-insensitive) |

---

## 12. Admin Dashboard API (`admin.py`)

JSON API endpoints for dashboard AJAX refresh and scan management. All endpoints are prefixed with `/admin/api`. Authentication is **not enforced** on these endpoints in the current implementation (they rely on the browser session cookie from the dashboard).

| Method | Path | Description | Request Body | Response |
|--------|------|-------------|-------------|----------|
| GET | `/admin/api/active-processing` | Get count of active processing jobs. | None | `{ "processing_count": 0, "timestamp": "..." }` |
| GET | `/admin/api/processing-status` | Get detailed list of active processing jobs. | None | `{ "active_jobs": [...], "timestamp": "..." }` |
| GET | `/admin/api/system-status` | Get system and GPU status for dashboard refresh. | None | `{ "system": {...}, "gpus": [...], "timestamp": "..." }` |
| DELETE | `/admin/api/scans/{scan_id}` | Delete a scan. | None | `{ "status": "deleted", "scan_id": "<id>" }` |
| POST | `/admin/api/scans/{scan_id}/cancel` | Cancel processing for a scan (must be in `processing` status). | None | `{ "status": "cancelled", "scan_id": "<id>" }` |
| GET | `/admin/api/scans/{scan_id}/logs` | Get processing logs for a specific scan. | None | Log entries array |
| GET | `/admin/api/logs/recent` | Get recent logs with optional filtering. | None | `{ "logs": [...], "stats": {...} }` |
| GET | `/admin/api/logs/errors` | Get recent errors. | None | `{ "errors": [...], "stats": {...} }` |
| GET | `/admin/api/devices/{device_id}/logs` | Get logs for a specific device. | None | Device log entries |
| DELETE | `/admin/api/queue/{scan_id}` | Remove a scan from the processing queue (must be in `uploaded` status). | None | `{ "status": "removed", "scan_id": "<id>" }` |

### Query Parameters for Log Endpoints

**`/admin/api/scans/{scan_id}/logs`:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `limit` | int | 100 | Maximum number of log entries to return |

**`/admin/api/logs/recent`:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `limit` | int | 100 | Maximum number of log entries to return |
| `level` | string | None | Filter by log level (e.g., `"error"`, `"warning"`, `"info"`) |
| `category` | string | None | Filter by log category |

**`/admin/api/logs/errors`:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `limit` | int | 50 | Maximum number of error entries to return |

**`/admin/api/devices/{device_id}/logs`:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `limit` | int | 200 | Maximum number of log entries to return |

---

## 13. Debug - Raw Data Upload, Pipeline 1 (`debug.py`)

Endpoints for raw data upload from the iOS app, bypassing edge processing. All endpoints are prefixed with `/api/v1/debug`. No authentication required.

| Method | Path | Description | Request Body | Response |
|--------|------|-------------|-------------|----------|
| POST | `/api/v1/debug/scans/raw/init` | Initialize a new raw scan upload session. | `RawScanInit` | `RawScanInitResponse` |
| PUT | `/api/v1/debug/scans/{scan_id}/raw/chunk` | Upload a chunk of raw scan data. | Raw binary body | Chunk receipt confirmation |
| PUT | `/api/v1/debug/scans/{scan_id}/metadata` | Upload metadata JSON for a raw scan. | JSON body | `{ "status": "metadata_saved" }` |
| POST | `/api/v1/debug/scans/{scan_id}/raw/finalize` | Finalize raw upload, reassemble chunks, and validate LRAW format. | None | Finalization result with validation |
| POST | `/api/v1/debug/scans/{scan_id}/process-raw` | Trigger processing of raw scan data (Celery or synchronous fallback). Status must be `uploaded`. | None | Processing status |
| GET | `/api/v1/debug/scans/{scan_id}/raw/status` | Get status of raw scan upload/processing. | None | Status object |
| GET | `/api/v1/debug/scans/{scan_id}/raw/download` | Download the original LRAW file for offline analysis. | None | File download (`application/octet-stream`) |
| GET | `/api/v1/debug/scans` | List all scans (both raw uploads and processed). | None | `{ "scans": [...], "total": N }` |

### `RawScanInit`

```json
{
  "name": "string (required, 1-100 chars)",
  "device_id": "string (required)",
  "device_model": "string (optional)",
  "ios_version": "string (optional)"
}
```

### `RawScanInitResponse`

```json
{
  "scan_id": "UUID",
  "status": "initialized",
  "upload_url": "/api/v1/debug/scans/<id>/raw/chunk"
}
```

### Raw Chunk Upload Headers

| Header | Type | Required | Description |
|--------|------|----------|-------------|
| `X-Chunk-Index` | int | No (default: 0) | Zero-based chunk index |
| `X-Is-Last-Chunk` | string | No (default: `"false"`) | Set to `"true"` for the final chunk |

### Raw Chunk Upload Response

```json
{
  "status": "chunk_received",
  "chunk_index": 0,
  "bytes_received": 5242880,
  "is_last": false
}
```

### Finalize Response

```json
{
  "status": "finalized",
  "scan_id": "<id>",
  "total_bytes": 52428800,
  "validation": {
    "valid": true,
    "version": 1,
    "flags": 0,
    "mesh_anchor_count": 12,
    "texture_frame_count": 60,
    "depth_frame_count": 60,
    "file_size": 52428800
  }
}
```

### Raw Scan Status Response

```json
{
  "scan_id": "<id>",
  "status": "initialized | chunks_complete | uploaded | processing | completed | failed",
  "chunks_received": 10,
  "total_bytes": 52428800,
  "validation": { ... },
  "created_at": "ISO datetime",
  "updated_at": "ISO datetime"
}
```

### List Scans Query Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `limit` | int | 50 | Maximum number of scans to return |

---

## 14. Debug - Event Streaming, Pipeline 2 (`debug.py`)

Real-time debug event streaming from iOS devices. All endpoints are prefixed with `/api/v1/debug`. No authentication required.

### WebSocket Endpoints

| Protocol | Path | Description |
|----------|------|-------------|
| WS | `/api/v1/debug/stream/{device_id}` | Real-time debug event stream from iOS device. Receives JSON events, stores them in memory buffer, forwards to dashboard clients, and sends acknowledgment. |
| WS | `/api/v1/debug/dashboard/ws/{device_id}` | WebSocket relay for dashboard clients. Sends buffered recent events (last 200) on connect, then relays live events in real-time. Supports `"ping"` / `"pong"` keepalive. |

**Device Stream WebSocket (Client -> Server):**

```json
{
  "id": "event-uuid",
  "timestamp": "ISO datetime",
  "category": "scan | upload | error | device",
  "type": "scan_started | error | ...",
  "data": { },
  "device_id": "device-uuid",
  "session_id": "optional-session-id"
}
```

**Device Stream WebSocket (Server -> Client):**

```json
{ "ack": "<event_id>" }
```

**Dashboard WebSocket (Server -> Client):**

```json
{
  "type": "buffered_events",
  "events": [ ... ]
}
```

```json
{
  "type": "event",
  "data": { ... }
}
```

### HTTP Endpoints

| Method | Path | Description | Request Body | Response |
|--------|------|-------------|-------------|----------|
| POST | `/api/v1/debug/events/{device_id}` | Batch endpoint for debug events (HTTP mode). Accepts array of events. Forwards to dashboard and persists important events. | JSON array of event objects | `{ "status": "received", "count": N }` |
| GET | `/api/v1/debug/events/{device_id}` | Get buffered debug events for a device. | None | `{ "device_id": "...", "events": [...], "total_buffered": N }` |
| DELETE | `/api/v1/debug/events/{device_id}` | Clear debug events buffer for a device. | None | `{ "status": "cleared", "count": N }` or `{ "status": "not_found" }` |

### Event Query Parameters (`GET /api/v1/debug/events/{device_id}`)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `category` | string | None | Filter events by category |
| `since` | string | None | ISO datetime; return events received after this timestamp |
| `limit` | int | 100 | Maximum number of events to return (taken from the end of the buffer) |

---

## 15. Debug - Device Logs (`debug.py`)

Persistent device log management. Prefixed with `/api/v1/debug`. No authentication required.

| Method | Path | Description | Request Body | Response |
|--------|------|-------------|-------------|----------|
| GET | `/api/v1/debug/devices` | List all devices with buffered events. | None | `{ "devices": [...], "total_buffered_events": N, "log_stats": {...} }` |
| GET | `/api/v1/debug/devices/{device_id}/logs` | Get persistent logs for a specific device (uses persistent log storage, not in-memory buffer). | None | `{ "device_id": "...", "logs": [...], "stats": {...} }` |
| POST | `/api/v1/debug/devices/{device_id}/log` | Add a single log entry for a device. | JSON (see below) | `{ "status": "logged", "level": "info" }` |

### Device Log Request Body

```json
{
  "level": "info | warning | error | debug",
  "message": "Log message",
  "details": { }   // optional
}
```

### Device Logs Query Parameters (`GET /api/v1/debug/devices/{device_id}/logs`)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `limit` | int | 200 | Maximum number of log entries to return |

### List Devices Response

```json
{
  "devices": [
    {
      "device_id": "device-uuid",
      "buffered_events": 1234,
      "last_event_at": "ISO datetime",
      "last_event_type": "scan_completed"
    }
  ],
  "total_buffered_events": 5000,
  "log_stats": { ... }
}
```

---

## 16. Debug - Visualization (`debug.py`)

Endpoints for visual inspection and analysis of scan data. Prefixed with `/api/v1/debug`. No authentication required.

| Method | Path | Description | Request Body | Response |
|--------|------|-------------|-------------|----------|
| GET | `/api/v1/debug/scans/{scan_id}/viewer` | Return HTML page with embedded 3D viewer (Google model-viewer web component). | None | HTML page |
| GET | `/api/v1/debug/scans/{scan_id}/depth/{frame_id}/heatmap` | Return depth frame as colored heatmap image (PNG, TURBO colormap: blue=close, red=far). Requires OpenCV. | None | `image/png` |
| GET | `/api/v1/debug/scans/{scan_id}/pointcloud/preview` | Return downsampled point cloud as JSON for web visualization (Three.js). | None | Point cloud JSON |
| GET | `/api/v1/debug/scans/{scan_id}/compare` | Compare iOS edge processing vs backend processing results. | None | Comparison JSON |
| GET | `/api/v1/debug/scans/{scan_id}/intermediate/{stage}` | Get intermediate processing outputs for a given stage. | None | Stage-specific JSON |

### Point Cloud Preview Query Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `max_points` | int | 50000 | Maximum number of points to return (downsampled if exceeded) |

### Point Cloud Preview Response

```json
{
  "point_count": 50000,
  "points": [[x, y, z], ...],
  "colors": [[r, g, b], ...],    // optional, 0-255 per channel
  "bounds": {
    "min": [x_min, y_min, z_min],
    "max": [x_max, y_max, z_max]
  }
}
```

### Compare Response

```json
{
  "scan_id": "<id>",
  "ios_result": {
    "point_count": 0,
    "mesh_faces": 0,
    "vertex_count": 0,
    "processing_time_ms": null,
    "device": null
  },
  "backend_result": {
    "point_count": 125000,
    "mesh_format": ".glb",
    "mesh_size_bytes": 4567890
  },
  "differences": {
    "point_count_diff": 125000
  }
}
```

### Intermediate Stage Values

| Stage | Description |
|-------|-------------|
| `parsed` | After LRAW parsing -- mesh + point cloud stats from validation |
| `depth` | Depth processing results -- frame count and heatmap URLs |
| `gaussians` | Gaussian splat parameters (file size, download URL) |
| `mesh_raw` | Raw mesh before texture baking (file size) |

---

## 17. Debug - Simple Pipeline Processing (`debug.py`)

Simplified processing pipeline for Apple Silicon (MPS/CPU). Prefixed with `/api/v1/debug`. No authentication required.

| Method | Path | Description | Request Body | Response |
|--------|------|-------------|-------------|----------|
| POST | `/api/v1/debug/scans/{scan_id}/process` | Start SimplePipeline processing. Uses Celery if available, otherwise falls back to synchronous processing. LRAW file must exist. | None | Processing status |

### Pipeline Steps

1. Parse LRAW
2. AI Depth Enhancement (Depth Anything V2)
3. Point Cloud Extraction
4. Poisson Reconstruction (Open3D)
5. Export (PLY, GLB, OBJ)

### Response (Celery available)

```json
{
  "status": "processing_started",
  "scan_id": "<id>",
  "task_id": "<celery_task_id>",
  "message": "SimplePipeline processing queued"
}
```

### Response (Synchronous fallback, success)

```json
{
  "status": "completed",
  "scan_id": "<id>",
  "result": {
    "pointcloud_path": "/path/to/pointcloud.ply",
    "mesh_path": "/path/to/mesh.ply",
    "exports": { "ply": "...", "glb": "...", "obj": "..." }
  },
  "error": null
}
```

---

## 18. Debug - Model Downloads (`debug.py`)

Direct model file download endpoints. Prefixed with `/api/v1/debug`. No authentication required.

| Method | Path | Description | Request Body | Response |
|--------|------|-------------|-------------|----------|
| GET | `/api/v1/debug/scans/{scan_id}/model.glb` | Download GLB (binary glTF) model for Three.js/WebGL viewing. | None | File download (`model/gltf-binary`) |
| GET | `/api/v1/debug/scans/{scan_id}/model.obj` | Download OBJ model for 3D software. | None | File download (`application/x-obj`) |
| GET | `/api/v1/debug/scans/{scan_id}/mesh.ply` | Download reconstructed mesh in PLY format. | None | File download (`application/x-ply`) |

---

## 19. Debug - Dashboard & Health (`debug.py`)

| Method | Path | Description | Auth Required | Request Body | Response |
|--------|------|-------------|:---:|-------------|----------|
| GET | `/api/v1/debug/health` | Health check for debug endpoints. Returns active stream counts and log statistics. | No | None | See below |
| GET | `/api/v1/debug/dashboard` | Serve the real-time debug dashboard web UI (HTML page rendered from `templates/debug_dashboard.html`). | No | None | HTML page |

### Debug Health Response

```json
{
  "status": "healthy",
  "active_streams": 2,
  "buffered_devices": 3,
  "total_events": 4567,
  "log_stats": { ... }
}
```

---

## Error Responses

All endpoints use standard HTTP status codes with JSON error bodies:

```json
{
  "detail": "Error message describing what went wrong"
}
```

| Status Code | Description |
|-------------|-------------|
| 400 | Bad request (invalid input, wrong scan status, missing chunks, etc.) |
| 401 | Unauthorized (missing or invalid Bearer token, iOS auth endpoints) |
| 303 | Redirect to login (admin dashboard, via `Location` header) |
| 404 | Resource not found (scan, file, format) |
| 500 | Internal server error |

---

## Authentication Summary

| Module | Mechanism | Where Used |
|--------|-----------|------------|
| iOS Auth (`ios_auth.py`) | JWT Bearer token (`Authorization: Bearer <token>`) | `/api/v1/users/me`, `/api/v1/users/me/preferences`, `/api/v1/users/me/scans` |
| Admin Auth (`auth.py`) | Session cookie (`admin_session`) | All `/admin/*` HTML pages |
| No Auth | None | Root, health, scan CRUD, upload, processing, download, all debug endpoints, admin API endpoints |
