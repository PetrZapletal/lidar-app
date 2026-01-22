# Fastlane Setup for LiDAR 3D Scanner

## Prerequisites

1. **Install Fastlane**
   ```bash
   brew install fastlane
   ```

2. **Apple Developer Program membership** ($99/year)
   - Register at https://developer.apple.com/programs/

3. **App Store Connect API Key** (recommended)
   - Go to App Store Connect → Users and Access → Keys
   - Create a new key with "App Manager" role
   - Download the .p8 file and save it securely

## Initial Setup

### 1. Configure Appfile

Edit `Appfile` and replace placeholders:
- `YOUR_APPLE_ID@email.com` - Your Apple Developer email
- `YOUR_TEAM_ID` - Find at developer.apple.com/account → Membership

### 2. Create App in App Store Connect

1. Go to https://appstoreconnect.apple.com
2. My Apps → + → New App
3. Fill in:
   - Platform: iOS
   - Name: LiDAR 3D Scanner
   - Bundle ID: com.lidarscanner.app
   - SKU: lidar-scanner-001

### 3. Setup Certificates (First Time Only)

Create a PRIVATE git repository for certificates:
```bash
# Edit Matchfile with your git URL
# Then run:
fastlane create_certs
```

## Usage

### Upload to TestFlight (Internal)
```bash
cd LidarAPP
fastlane beta
```

### Upload to TestFlight (External)
```bash
fastlane beta_external
```

### Build Only (No Upload)
```bash
fastlane build
```

### Run Tests
```bash
fastlane test
```

### Sync Certificates
```bash
fastlane sync_certs
```

## Environment Variables

For CI/CD, set these secrets:

```
MATCH_PASSWORD          # Password for certificates repo encryption
MATCH_GIT_URL           # Git URL for certificates repo
ASC_KEY_ID              # App Store Connect API Key ID
ASC_ISSUER_ID           # App Store Connect Issuer ID
ASC_PRIVATE_KEY         # Contents of .p8 file (base64 encoded)
```

## Troubleshooting

### "No signing certificate found"
Run `fastlane sync_certs` or create new ones with `fastlane create_certs`

### "Bundle ID not registered"
Register it at developer.apple.com → Identifiers → +

### "App not found in App Store Connect"
Create the app first in App Store Connect

## Lanes Reference

| Lane | Description |
|------|-------------|
| `beta` | Build and upload to TestFlight (internal) |
| `beta_external` | Build and distribute to external testers |
| `build` | Build only, no upload |
| `test` | Run unit tests |
| `sync_certs` | Sync certificates from git repo |
| `create_certs` | Create new certificates (first time) |
| `release` | Submit to App Store for review |
