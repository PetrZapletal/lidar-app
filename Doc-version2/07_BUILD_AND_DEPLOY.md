# 07 - Build, Deploy a Konfigurace

> Kompletni prehled build procesu, deployment pipeline a konfigurace projektu. Overeno primo ze zdrojovych souboru.

---

## Zakladni konfigurace projektu

| Parametr | Hodnota | Zdroj |
|----------|---------|-------|
| **Bundle ID** | `com.petrzapletal.lidarscanner` | `project.pbxproj` |
| **Team ID** | `65HGP9PL6X` | `project.pbxproj`, `ExportOptions.plist` |
| **Swift verze** | 5.0 | `project.pbxproj` (`SWIFT_VERSION`) |
| **Minimalni iOS** | 17.0 | `project.pbxproj` (`IPHONEOS_DEPLOYMENT_TARGET`) |
| **Scheme** | `LidarAPP` | `project.pbxproj` |
| **Signing** | Automatic | `ExportOptions.plist` |
| **Xcodeproj** | `LidarAPP/LidarAPP.xcodeproj` | - |

> **Poznamka:** Stary `CLAUDE.md` uvadi Swift 5.9 a Bundle ID `com.lidarscanner.app` -- oboji je **chybne**. Skutecne hodnoty v `project.pbxproj` jsou Swift 5.0 a `com.petrzapletal.lidarscanner`.

---

## iOS Build

### Debug build

```bash
xcodebuild -scheme LidarAPP \
  -project LidarAPP/LidarAPP.xcodeproj \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  build
```

### Release build

```bash
xcodebuild -scheme LidarAPP \
  -project LidarAPP/LidarAPP.xcodeproj \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  build
```

### Resolve SPM zavislosti

```bash
xcodebuild -resolvePackageDependencies \
  -project LidarAPP/LidarAPP.xcodeproj \
  -scheme LidarAPP
```

---

## Testovani

### Unit testy

```bash
xcodebuild test \
  -scheme LidarAPP \
  -project LidarAPP/LidarAPP.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

### Fastlane testy (s code coverage)

```bash
cd LidarAPP
bundle exec fastlane test
```

Fastlane lane `test` spousti:
- Scheme: `LidarAPP`
- Device: iPhone 15 Pro
- Code coverage: zapnuto

---

## Linting

> **Pozor:** Soubor `.swiftlint.yml` v projektu **neexistuje**. SwiftLint neni aktualne nakonfigurovany.

Pokud se SwiftLint nainstaluje a nakonfiguruje:
```bash
swiftlint lint --path LidarAPP/LidarAPP
```

---

## TestFlight Deployment

### Manualni postup (xcodebuild)

```bash
cd LidarAPP

# 1. Zvysit build number
agvtool new-version -all $(( $(agvtool what-version -terse) + 1 ))

# 2. Archive
xcodebuild -scheme LidarAPP \
  -project LidarAPP.xcodeproj \
  -destination 'generic/platform=iOS' \
  -archivePath ./build/LidarAPP.xcarchive \
  archive \
  DEVELOPMENT_TEAM=65HGP9PL6X \
  CODE_SIGN_STYLE=Automatic

# 3. Export a upload do TestFlight
xcodebuild -exportArchive \
  -archivePath ./build/LidarAPP.xcarchive \
  -exportPath ./build/export \
  -exportOptionsPlist ExportOptions.plist
```

### ExportOptions.plist

Soubor `LidarAPP/ExportOptions.plist` obsahuje:

| Klic | Hodnota |
|------|---------|
| `method` | `app-store-connect` |
| `teamID` | `65HGP9PL6X` |
| `signingStyle` | `automatic` |
| `uploadBitcode` | `false` |
| `uploadSymbols` | `true` |
| `destination` | `upload` |

---

## Fastlane

Konfigurace v `LidarAPP/fastlane/`.

### Appfile

Soubor `LidarAPP/fastlane/Appfile`:
- `app_identifier`: `com.lidarscanner.app` (pozor -- toto je **zastarala** hodnota, v `project.pbxproj` je `com.petrzapletal.lidarscanner`)
- `team_id`: Nutno nastavit (`YOUR_TEAM_ID` placeholder)
- Podpora App Store Connect API Key autentifikace (zakomentovano)

### Dostupne lanes

| Lane | Prikaz | Popis |
|------|--------|-------|
| `beta` | `bundle exec fastlane beta` | Build + upload do TestFlight (interni testeri) |
| `beta_external` | `bundle exec fastlane beta_external` | Build + upload + distribuce externim testerum |
| `build` | `bundle exec fastlane build` | Pouze build bez uploadu |
| `test` | `bundle exec fastlane test` | Spusteni unit testu s code coverage |
| `sync_certs` | `bundle exec fastlane sync_certs` | Synchronizace certifikatu (match, readonly) |
| `create_certs` | `bundle exec fastlane create_certs` | Vytvoreni novych certifikatu (match) |
| `screenshots` | `bundle exec fastlane screenshots` | Screenshot pro App Store (scheme `LidarAPPUITests`) |
| `release` | `bundle exec fastlane release` | Build + upload do App Store (bez submit for review) |

### Typicky workflow pro TestFlight

```bash
cd LidarAPP

# Rychly deploy do TestFlight
bundle exec fastlane beta

# S distribuce externim testerum
bundle exec fastlane beta_external
```

> **Upozorneni:** Fastlane `Appfile` ma placeholder hodnoty pro `team_id` a `apple_id`. Pred prvnim pouzitim je nutne nakonfigurovat.

---

## Backend - Docker

### Development (Apple Silicon / bez CUDA)

```bash
cd backend
docker compose -f docker-compose.dev.yml up -d --build
```

Sluzby v `docker-compose.dev.yml`:

| Sluzba | Port (host:container) | Popis |
|--------|-----------------------|-------|
| `api` | `8080:8000` (HTTP), `8444:8443` (HTTPS) | FastAPI server |
| `redis` | `6379:6379` | Redis (cache + message broker) |
| `worker` | - | Celery worker pro background ulohy |

Funkce dev prostredi:
- **Hot reload** -- slozky `api/`, `utils/`, `services/`, `static/`, `templates/` jsou mountovane jako readonly volumes
- **SSL certifikaty** -- z `backend/certs/` (mountovane jako readonly)
- **Dockerfile** -- `Dockerfile.dev` (python:3.11-slim, bez CUDA)
- **Healthcheck** -- `curl -f http://localhost:8000/health`

### Produkce (s NVIDIA CUDA)

```bash
cd backend
docker compose up -d --build
```

Sluzby v `docker-compose.yml`:

| Sluzba | Port (host:container) | Popis |
|--------|-----------------------|-------|
| `api` | `8000:8000` | FastAPI server |
| `redis` | `6379:6379` | Redis |
| `worker` | - | Celery worker s GPU pristupem |
| `minio` | `9000:9000`, `9001:9001` | S3 uloziste (profil `storage`, volitelne) |

Funkce produkcniho prostredi:
- **NVIDIA CUDA 12.1** -- GPU akcelerace pro PyTorch, 3DGS
- **Multi-stage build** -- mensi vysledny image
- **MinIO** -- volitelne S3 uloziste (aktivace: `docker compose --profile storage up`)

### Spusteni MinIO (volitelne)

```bash
cd backend
docker compose --profile storage up -d minio
```

MinIO konzole: `http://localhost:9001` (admin: `minioadmin` / `minioadmin`)

### Zastaveni sluzeb

```bash
# Development
cd backend && docker compose -f docker-compose.dev.yml down

# Produkce
cd backend && docker compose down

# Vcetne volumes (smazani dat!)
cd backend && docker compose down -v
```

---

## Backend - Pristup z iOS aplikace

### Tailscale (development)

| Parametr | Hodnota |
|----------|---------|
| **Tailscale IP** | `100.96.188.18` |
| **HTTPS port** | `8444` |
| **REST API** | `https://100.96.188.18:8444/api/v1` |
| **WebSocket** | `wss://100.96.188.18:8444/ws` |

### Test API

Testovaci skript: `backend/scripts/test_api.sh`

```bash
# Defaultni (localhost:8444)
cd backend && ./scripts/test_api.sh

# Pres Tailscale
cd backend && ./scripts/test_api.sh 100.96.188.18 8444
```

Skript testuje:
1. Health check (`/health`)
2. Login (`/api/v1/auth/login`)
3. User profil (`/api/v1/users/me`)
4. Vytvoreni skenu (`/api/v1/scans`)
5. Status skenu (`/api/v1/scans/{id}/status`)
6. Seznam skenu (`/api/v1/scans`)
7. Smazani skenu (`/api/v1/scans/{id}`)
8. WebSocket endpoint (`/ws`)

---

## Prehled souboru konfigurace

| Soubor | Cesta | Existuje | Popis |
|--------|-------|----------|-------|
| `project.pbxproj` | `LidarAPP/LidarAPP.xcodeproj/project.pbxproj` | Ano | Hlavni konfigurace Xcode projektu |
| `ExportOptions.plist` | `LidarAPP/ExportOptions.plist` | Ano | Nastaveni exportu pro TestFlight/App Store |
| `Fastfile` | `LidarAPP/fastlane/Fastfile` | Ano | Fastlane automatizace |
| `Appfile` | `LidarAPP/fastlane/Appfile` | Ano | Fastlane identifikace aplikace |
| `.swiftlint.yml` | - | **Ne** | SwiftLint konfigurace neexistuje |
| `docker-compose.dev.yml` | `backend/docker-compose.dev.yml` | Ano | Docker pro vyvoj (bez CUDA) |
| `docker-compose.yml` | `backend/docker-compose.yml` | Ano | Docker pro produkci (s CUDA) |
| `Dockerfile.dev` | `backend/Dockerfile.dev` | Ano | Dev Docker image (python:3.11-slim) |
| `Dockerfile` | `backend/Dockerfile` | Ano | Prod Docker image (nvidia/cuda) |
| `requirements.txt` | `backend/requirements.txt` | Ano | Python zavislosti |
| `test_api.sh` | `backend/scripts/test_api.sh` | Ano | Skript pro testovani API endpointu |
