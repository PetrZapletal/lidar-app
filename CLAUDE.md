# LidarApp - Project Context for Claude Code

## TODO (po restartu Claude Code)
- [ ] Spustit `@spec-manager` pro analýzu aktuálního stavu projektu a aktualizaci dokumentace
- [ ] Aktualizovat `docs/CURRENT_SPRINT.md` podle skutečného stavu

## Project Overview
iOS LiDAR 3D Scanner app with backend AI processing. Ultra-precise 3D space mapping using ARKit, Metal rendering, and neural network mesh processing.

## Quick Facts
- **Stack**: Swift 5.9, SwiftUI, ARKit 6, Metal, RealityKit, Python 3.11, FastAPI
- **Architecture**: MVVM + Clean Architecture
- **Minimum iOS**: 17.0+
- **Devices**: iPhone 12 Pro+ / iPad Pro 2020+ (LiDAR required)

## Key Directories
```
LidarAPP/                    # iOS aplikace
├── App/                     # Entry point, App Delegate
├── Core/                    # DI container, Extensions, Utilities
├── Domain/                  # Entity models, Use Cases
├── Presentation/            # SwiftUI Views + ViewModels
│   ├── Scanning/            # LiDAR scanning UI
│   ├── Preview/             # 3D model preview
│   ├── Export/              # Export options
│   └── Auth/                # Authentication
└── Services/                # Business logic services
    ├── ARKit/               # LiDAR, mesh, point cloud
    ├── Camera/              # Frame capture
    ├── EdgeML/              # CoreML models
    ├── Measurement/         # Offline measurements
    ├── Rendering/           # Metal, RealityKit
    └── Network/             # API, WebSocket

backend/                     # Python backend
├── api/                     # FastAPI endpoints
└── services/                # AI processing
    ├── gaussian_splatting.py
    ├── sugar_mesh.py
    └── texture_baker.py
```

## Code Style & Conventions

### Swift
- Use SwiftUI for all new views
- MVVM pattern: View -> ViewModel -> Service
- Combine for reactive programming
- async/await for concurrency
- Protocol-oriented design
- Dependency injection via environment

### Naming Conventions
- Views: `*View.swift` (e.g., `ScanningView.swift`)
- ViewModels: `*ViewModel.swift` (e.g., `ScanningViewModel.swift`)
- Services: `*Service.swift` (e.g., `LiDARService.swift`)
- Protocols: `*Protocol.swift` or `*able` suffix

### Error Handling
- Always use custom error types
- Wrap ARKit errors in `LiDARError`
- Log errors with OSLog
- Show user-friendly error messages

## Testing Requirements
- Unit tests for all ViewModels
- Integration tests for Services
- UI tests for critical flows
- Test command: `xcodebuild test -scheme LidarAPP -destination 'platform=iOS Simulator,name=iPhone 15 Pro'`

## Build Commands
```bash
# iOS build
xcodebuild -scheme LidarAPP -configuration Debug -destination 'generic/platform=iOS'

# Backend (Apple Silicon - development)
cd backend && docker compose -f docker-compose.dev.yml up -d --build

# Lint
swiftlint lint --strict
```

## Backend Connection (Development)

| Endpoint | Value |
|----------|-------|
| **Tailscale IP** | `100.96.188.18` |
| **Port** | `8444` (HTTPS) |
| **REST API** | `https://100.96.188.18:8444/api/v1` |
| **WebSocket** | `wss://100.96.188.18:8444/ws` |

### Test API
```bash
./scripts/test_api.sh 100.96.188.18 8444
```

## API Reference

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/scans` | POST | Create new scan |
| `/api/v1/scans/{id}/upload` | POST | Upload point cloud |
| `/api/v1/scans/{id}/process` | POST | Start AI processing |
| `/api/v1/scans/{id}/status` | GET | Processing status |
| `/ws/scans/{id}` | WS | Real-time updates |

## Current Development Phase
See `docs/DEVELOPMENT_PHASES.md` for detailed breakdown.

## Known Issues
- ARSession crashes on background -> always pause session in `scenePhase` change
- Metal shader compilation slow on first run -> precompile in app launch
- Memory pressure with large point clouds -> implement progressive loading

## Dependencies

### iOS (Swift Package Manager)
- Alamofire (networking)
- Realm (local storage)
- Lottie (animations)
- RevenueCat (subscriptions)

### Backend (pip)
- FastAPI, uvicorn
- PyTorch, torchvision
- Open3D (point cloud)
- trimesh (mesh processing)

## Security Notes
- Never commit API keys
- Use Keychain for sensitive data
- Certificate pinning for API calls
- Sanitize all user inputs

## Performance Guidelines
- Target 60 FPS during scanning
- Metal compute for point cloud processing
- Lazy loading for 3D previews
- Background processing for exports

## iOS Build & TestFlight

```bash
cd LidarAPP

# 1. Increment build number
agvtool new-version -all $(( $(agvtool what-version -terse) + 1 ))

# 2. Archive
xcodebuild -scheme LidarAPP -project LidarAPP.xcodeproj \
  -destination 'generic/platform=iOS' \
  -archivePath ./build/LidarAPP.xcarchive \
  archive \
  DEVELOPMENT_TEAM=65HGP9PL6X \
  CODE_SIGN_STYLE=Automatic

# 3. Export and upload to TestFlight
xcodebuild -exportArchive \
  -archivePath ./build/LidarAPP.xcarchive \
  -exportPath ./build/export \
  -exportOptionsPlist ExportOptions.plist
```

### Team ID
- **Development Team:** `65HGP9PL6X`
- **Bundle ID:** `com.lidarscanner.app`
