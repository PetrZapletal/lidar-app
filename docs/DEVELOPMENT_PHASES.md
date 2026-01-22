# LidarApp Development Phases

## Overview
Projekt je rozdělen do 6 hlavních fází. Každá fáze má jasně definované deliverables a acceptance criteria.

---

## Phase 1: Core LiDAR Infrastructure - IN PROGRESS

### 1.1 LiDAR Service Foundation
- [x] `LiDARService.swift` - Session management
  - [x] ARSession lifecycle (start, pause, resume, stop)
  - [x] Configuration for different scan modes
  - [x] Error handling and recovery
- [x] `LiDARSessionManager.swift` - State machine
  - [x] State transitions (idle, scanning, paused, processing)
  - [x] Combine publishers for state changes

### 1.2 Point Cloud Processing
- [x] `PointCloudProcessor.swift` - Raw data processing
  - [x] Depth frame extraction
  - [x] Confidence filtering
  - [x] Point cloud generation
- [x] `PointCloud.swift` - Data model
  - [x] Points, normals, colors, confidence
  - [x] Serialization for upload

### 1.3 Mesh Generation
- [x] `MeshGenerator.swift` - Real-time mesh
  - [x] ARMeshAnchor processing
  - [x] Mesh classification (floor, wall, ceiling)
- [ ] `MeshOptimizer.swift` - Mesh cleanup
  - [ ] Hole filling
  - [ ] Decimation
  - [ ] Smoothing

**Acceptance Criteria:**
- [x] LiDAR scanning starts/stops without crashes
- [x] Point cloud captures at 30+ FPS
- [x] Mesh updates in real-time
- [ ] Memory usage < 500MB during scanning

---

## Phase 2: Camera & Texture Pipeline - IN PROGRESS

### 2.1 Camera Integration
- [x] `CameraService.swift` - Frame capture
  - [x] Synchronized RGB frames
  - [ ] HDR capture support
  - [x] Frame rate management
- [x] `FrameSynchronizer.swift` - LiDAR/Camera sync
  - [x] Timestamp alignment
  - [x] Pose estimation

### 2.2 Texture Processing
- [ ] `TextureMapper.swift` - UV mapping
  - [ ] Projective texturing
  - [ ] Texture atlas generation
- [ ] `TextureOptimizer.swift` - Quality enhancement
  - [ ] Deblurring
  - [ ] Color correction

**Acceptance Criteria:**
- [x] RGB frames synced with depth within 10ms
- [ ] Texture resolution >= 2048x2048
- [ ] No visible seams in texture atlas

---

## Phase 3: UI Layer - IN PROGRESS

### 3.1 Scanning Interface
- [x] `ScanningView.swift` - Main scanning UI
  - [x] AR preview overlay
  - [x] Scan progress indicator
  - [x] Quality feedback
- [x] `ScanningViewModel.swift` - Business logic
  - [x] Scan state management
  - [x] User guidance

### 3.2 Preview Interface
- [x] `ModelPreviewView.swift` - 3D preview
  - [x] SceneKit/RealityKit renderer
  - [x] Pan, zoom, rotate gestures
  - [ ] Lighting controls
- [ ] `ARQuickLookView.swift` - AR placement
  - [ ] Real-world placement
  - [ ] Scale adjustment

### 3.3 Measurement Tools
- [x] `MeasurementView.swift` - Measurement UI
  - [x] Point-to-point distance
  - [x] Area calculation
  - [x] Volume estimation
- [x] `MeasurementService.swift` - Calculations
  - [x] Hit testing
  - [x] Geometry calculations

**Acceptance Criteria:**
- [x] UI responds within 100ms
- [x] Smooth 60 FPS rendering
- [x] Measurement accuracy +/-1cm

---

## Phase 4: Export Pipeline - PLANNED

### 4.1 Format Exporters
- [x] `USDZExporter.swift` - Apple AR format
- [x] `GLTFExporter.swift` - Cross-platform
- [x] `OBJExporter.swift` - Universal
- [x] `STLExporter.swift` - 3D printing
- [x] `PLYExporter.swift` - Point cloud

### 4.2 Export Manager
- [x] `ExportManager.swift` - Orchestration
  - [x] Format selection
  - [x] Quality options
  - [ ] Progress tracking
- [ ] `ExportView.swift` - Export UI
  - [ ] Format picker
  - [ ] Share sheet integration

**Acceptance Criteria:**
- [x] All 5 formats export correctly
- [ ] Export completes in < 30s for typical scan
- [ ] Files open in standard software

---

## Phase 5: Cloud Integration - IN PROGRESS

### 5.1 Upload Service
- [x] `CloudUploadService.swift` - File upload
  - [x] Chunked upload
  - [x] Resume support
  - [x] Progress tracking
- [x] `ScanSyncManager.swift` - Sync logic
  - [x] Offline queue
  - [ ] Conflict resolution

### 5.2 Processing Integration
- [x] `CloudProcessingService.swift` - AI pipeline
  - [x] Job submission
  - [x] Status polling
  - [x] Result download
- [x] `WebSocketService.swift` - Real-time updates
  - [x] Progress notifications
  - [x] Completion events

**Acceptance Criteria:**
- [x] Upload resumes after network interruption
- [x] Real-time progress updates
- [ ] < 5 min processing for standard scan

---

## Phase 6: EdgeML Integration - PLANNED

### 6.1 Depth Enhancement
- [x] `DepthAnythingService.swift` - Depth refinement
  - [x] CoreML model integration
  - [ ] Real-time inference
  - [ ] Depth fusion

### 6.2 On-device Processing
- [ ] `EdgeMeshProcessor.swift` - Local mesh cleanup
  - [ ] Lightweight neural network
  - [ ] < 200ms inference

**Acceptance Criteria:**
- [ ] Depth enhancement < 50ms per frame
- [ ] Mesh cleanup < 200ms
- [ ] Battery impact < 20% over 10 min scan

---

## Progress Tracking

| Phase | Status | Progress | Target Date |
|-------|--------|----------|-------------|
| Phase 1: Core LiDAR | In Progress | 85% | Q1 2026 |
| Phase 2: Camera | In Progress | 60% | Q1 2026 |
| Phase 3: UI | In Progress | 75% | Q2 2026 |
| Phase 4: Export | In Progress | 70% | Q2 2026 |
| Phase 5: Cloud | In Progress | 80% | Q3 2026 |
| Phase 6: EdgeML | Planned | 20% | Q3 2026 |

---

## How to Use This Document

### Starting a new feature:
```bash
# 1. Check current phase
cat docs/DEVELOPMENT_PHASES.md | grep "IN PROGRESS"

# 2. Use feature-dev plugin
/feature-dev explore "LiDARService session management"

# 3. Architect the solution
/feature-dev architect "ARSession lifecycle"

# 4. Implement with ralph-loop for iteration
# Claude will work iteratively until code is complete

# 5. Review before commit
/code-review
```

### Marking progress:
Replace `[ ]` with `[x]` when completing items.
Update status: Planned -> In Progress -> Complete
