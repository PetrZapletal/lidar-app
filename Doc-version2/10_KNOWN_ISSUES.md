# 10 - Zname problemy a technicky dluh

> Posledni aktualizace: 2026-02-08
> Zdroj: audit celeho codebase

---

## Kriticke problemy

### 1. USDZ export je fake
- **Soubor:** `LidarAPP/Presentation/Export/ExportService.swift` (radky 322-339)
- **Problem:** Funkce `exportToUSDZ()` exportuje OBJ soubor a pouze ho prejmenovava
  na `.usdz`. Vysledny soubor NENI validni USDZ a nepujde otevrit v AR Quick Look,
  Reality Composer, ani v zadnem USDZ readeru.
- **Dopad:** Uzivatel dostane nefunkcni soubor oznaceny jako USDZ.
- **Reseni:** Pouzit `MDLAsset` (ModelIO framework) nebo `SCNScene` (SceneKit) pro
  skutecnou konverzi do USDZ formatu. Apple ma nativni API pro tuto konverzi.

### 2. MeshCorrectionModel nema zadny .mlmodel soubor
- **Soubor:** `LidarAPP/Services/EdgeML/MeshCorrectionModel.swift`
- **Problem:** Trida se tvari jako CoreML wrapper, ale:
  - `loadModel()` nastavuje `.ready` stav bez nacteni jakehokoliv modelu
  - Zakomentovany radek: `// model = try await MeshCorrector.load(configuration: config)`
  - Komentar: "For MVP: Use algorithmic corrections instead of ML model"
  - Pouzite algoritmy maji O(n^2) slozitost (brute-force hledani sousedu)
- **Dopad:** "ML korekce" je jen marketing -- skutecne provadi zakladni filtrovani.
  Na meshich s 100K+ vertexy bude extremne pomale.
- **Reseni:** Bud dodat skutecny .mlmodel soubor, nebo predelat na efektivni
  algoritmy s KD-tree (O(n log n)).

### 3. Hole filling je placeholder
- **Soubor:** `LidarAPP/Services/ARKit/DepthMapProcessor.swift` (metoda `fillHoles`)
- **Problem:** Pouziva jednoduchy iterativni 4-sousedni prumer. Vyplni jen male
  diry (max 10px) a vysledek je rozmazany. Spec slibuje "AI inpainting".
- **Dopad:** Velke diry v hloubkove mape zustanou nevyplnene.
- **Reseni:** Integrace Depth Anything V2 na zarizeni (CoreML) pro kvalitni doplneni.

---

## Chybejici komponenty

### 4. OnboardingView chybi
- **Problem:** V navigaci/flow aplikace se odkazuje na onboarding, ale zadny
  `OnboardingView.swift` v projektu neexistuje.
- **Dopad:** Novy uzivatel nema zadne uvitani, tutorial ani vysvetleni jak skenovat.

### 5. CloudProcessingService neexistuje
- **Problem:** Dokumentace (`CLAUDE.md`) a architektura odkazuji na cloud processing
  service pro backend komunikaci. Soubor `CloudProcessingService.swift` neexistuje.
- **Dopad:** Zadna oficialni service vrstva pro komunikaci s backendem
  (existuje jen `RawDataUploader` v Debug slozce).

### 6. ScanSyncManager neexistuje
- **Problem:** Odkazovany manazer pro synchronizaci skenu mezi zarizenim a backendem
  neexistuje.
- **Dopad:** Chybi logika pro sledovani stavu uploadu, retry, offline fronta.

### 7. docs/CURRENT_SPRINT.md neexistuje
- **Problem:** `CLAUDE.md` v TODO sekci odkazuje na `docs/CURRENT_SPRINT.md` pro
  aktualizaci podle skutecneho stavu. Soubor ale neexistuje.
- **Dopad:** Zadny tracking aktualniho sprintu.

### 8. .swiftlint.yml neexistuje
- **Problem:** `CLAUDE.md` uvadi build command `swiftlint lint --strict`, ale
  konfiguracni soubor `.swiftlint.yml` v projektu chybi.
- **Dopad:** SwiftLint pouzije vychozi pravidla (pokud je vubec nainstalovan),
  coz muze byt prilis striktni nebo naopak prilis benevolentni.

---

## Problemy s logovanim a error handling

### 9. Vetsina services pouziva print() misto DebugLogger
- **Soubory:** Prakticky vsechny Services soubory
- **Problem:** Projekt ma vlastni `DebugLogger` utilitu, ale vetsina kodu pouziva
  holou funkci `print()`. Priklady:
  - `ARSessionManager.swift`: `print("High-res capture error: ...")`
  - `ARSessionManager.swift`: `print("ARSession: gravityAndHeading failed...")`
  - `CoverageAnalyzer.swift`: `print("CoverageAnalyzer: Buffer too small...")`
  - Backend pouziva spravne `logger` z `utils.logger`
- **Dopad:** Logy nejsou strukturovane, nelze filtrovat podle urovne, v release
  buildu zustanou viditelne.
- **Reseni:** Nahradit vsechny `print()` volanim `DebugLogger` nebo `os.Logger`
  (Apple OSLog framework).

### 10. Chybi jednotny error type
- **Problem:** `CLAUDE.md` uvadi: "Wrap ARKit errors in `LiDARError`" -- ale typ
  `LiDARError` v projektu neexistuje.
- **Skutecny stav:**
  - `ARSessionError` -- pro AR session chyby (existuje, funkcni)
  - `ExportError` -- pro export chyby (existuje, funkcni)
  - `ARWorldMapError` -- pro world map chyby (existuje, funkcni)
  - Zadny zastresujici `LiDARError` ani `AppError` pro celou aplikaci
- **Dopad:** Error handling je fragmentovany. Kazdy modul si definuje vlastni
  error typy, chybi jednotna vrstva pro zobrazeni chyb uzivateli.

---

## Problemy v dokumentaci (CLAUDE.md)

### 11. Spatna verze Swift
- **CLAUDE.md uvadi:** Swift 5.9
- **Skutecnost:** Projekt pouziva Swift 5.0 (overeno v project settings)
- **Dopad:** Claude Code muze generovat kod s features z novejsiho Swiftu.

### 12. Spatny Bundle ID
- **CLAUDE.md uvadi:** `com.lidarscanner.app`
- **Skutecnost:** Skutecny Bundle ID se lisi (overeno v Xcode projektu)
- **Dopad:** Navody pro build/deploy mohou byt zavadejici.

### 13. Spatne iOS dependencies
- **CLAUDE.md uvadi:** Alamofire, Realm, Lottie, RevenueCat
- **Skutecnost:** Zadna z techto knihoven neni v projektu pouzita.
  Projekt pouziva nativni frameworky (URLSession, SwiftData/UserDefaults,
  SwiftUI animace). Neni definovany Package.swift ani Podfile s temito
  zavislostmi.
- **Dopad:** CLAUDE.md zavadejicim zpusobem popisuje technologicky stack.
  Novy vyvojar bude zmaten.

---

## Architektonicke problemy

### 14. ExportService je v Presentation/ misto Services/
- **Soubor:** `LidarAPP/Presentation/Export/ExportService.swift`
- **Problem:** Podle MVVM + Clean Architecture by services nemely byt
  v Presentation vrstve. ExportService je business logika, ne UI.
- **Dopad:** Poruseni architektonickych pravidel, horsci testovatelnost.
- **Reseni:** Presunout do `LidarAPP/Services/Export/ExportService.swift`.

### 15. Adopce protokolu je minimalni (~5%)
- **Problem:** `CLAUDE.md` uvadi "Protocol-oriented design", ale:
  - Vetsina services nema definovany protokol/interface
  - `ARSessionManager` -- zadny protokol
  - `CameraFrameCapture` -- zadny protokol
  - `DepthMapProcessor` -- zadny protokol
  - `ExportService` -- zadny protokol
  - `CoverageAnalyzer` -- zadny protokol
- **Dopad:**
  - Nelze jednoduse mockovat pro unit testy
  - Nelze menit implementace za behu (napr. pro preview vs produkci)
  - Dependency injection je obtizny
- **Reseni:** Pro kazdou service definovat protokol (napr. `ExportServiceProtocol`,
  `DepthProcessable`, atd.) a pouzivat pro DI.

### 16. glTF export je nefunkcni
- **Soubor:** `LidarAPP/Presentation/Export/ExportService.swift` (metoda `exportToGLTF`)
- **Problem:** Zapisuje pouze JSON metadata bez binarniho bufferu (.bin).
  Vysledny soubor neni validni glTF -- accessory odkazuji na buffer ktery neexistuje.
- **Dopad:** Export do glTF format produkuje nefunkcni soubor.
- **Reseni:** Implementovat zapis binarniho bufferu s vertex a index daty,
  nebo pouzit knihovnu treti strany.

---

## Souhrn podle priority

| Priorita | Issue | Typ |
|----------|-------|-----|
| KRITICKA | #1 USDZ fake export | Bug |
| KRITICKA | #11-13 CLAUDE.md nepresnosti | Dokumentace |
| VYSOKA | #2 MeshCorrectionModel je stub | Technicky dluh |
| VYSOKA | #5-6 Chybejici services | Chybejici funkce |
| VYSOKA | #10 Chybi jednotny error type | Architektura |
| VYSOKA | #15 Minimalni adopce protokolu | Architektura |
| VYSOKA | #16 glTF export nefunkcni | Bug |
| STREDNI | #3 Hole filling je placeholder | Technicky dluh |
| STREDNI | #9 print() misto DebugLogger | Kvalita kodu |
| STREDNI | #14 ExportService spatne umisteni | Architektura |
| NIZKA | #4 Chybejici OnboardingView | Chybejici funkce |
| NIZKA | #7 CURRENT_SPRINT.md neexistuje | Dokumentace |
| NIZKA | #8 .swiftlint.yml neexistuje | Nastroje |

---

## Co funguje dobre

Pro uplnost -- nasledujici casti jsou kvalitni a funkcni:

- **ARSessionManager** -- robustni, dobre osetrene chybove stavy, fallback logika
- **CoverageAnalyzer** -- sofistikovany, s performance optimalizacemi
- **MeshAnchorProcessor** -- spolehliva extrakce dat z ARKit
- **PointCloudExtractor** -- funkcni, s voxel downsamplingem
- **Backend SimplePipeline** -- pragmaticky pristup, Poisson reconstruction funguje
- **LRAW format** -- dobre navrzeny binarni format s debug nastrojem
- **OBJ/PLY/STL export** -- jednoduche ale funkcni
