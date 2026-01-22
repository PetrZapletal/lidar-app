# Verzování iOS aplikace

## Semantic Versioning (SemVer)

Používáme standardní **Semantic Versioning** formát: `MAJOR.MINOR.PATCH`

### Version (CFBundleShortVersionString)

Marketingová verze zobrazená uživatelům v App Store.

| Změna | Příklad | Kdy použít |
|-------|---------|------------|
| **MAJOR** | `1.0.0` → `2.0.0` | Breaking changes, velké přepracování UI, nekompatibilní API změny |
| **MINOR** | `1.0.0` → `1.1.0` | Nové funkce, vylepšení, zpětně kompatibilní změny |
| **PATCH** | `1.0.0` → `1.0.1` | Bugfixy, drobné opravy, bezpečnostní záplaty |

### Build Number (CFBundleVersion)

Interní číslo buildu - **musí být unikátní pro každý upload na App Store Connect**.

**Možné formáty:**
- Inkrementální: `1`, `2`, `3`, `4`...
- S verzí: `1.0.1`, `1.0.2`, `1.1.1`...
- Datum-based: `20260119.1`, `20260119.2`...

**Doporučení:** Používáme jednoduché inkrementální číslo (`1`, `2`, `3`...).

## Příklady verzování

```
1.0.0 (1)  - První release
1.0.1 (2)  - Bugfix release
1.1.0 (3)  - Nové funkce (např. Object mode)
1.1.1 (4)  - Bugfix pro 1.1.0
1.2.0 (5)  - Další nové funkce
2.0.0 (6)  - Velké přepracování
```

## Aktualizace verze

### 1. Ruční úprava v Info.plist

```xml
<key>CFBundleShortVersionString</key>
<string>1.1.0</string>
<key>CFBundleVersion</key>
<string>2</string>
```

### 2. Pomocí agvtool (doporučeno)

```bash
# Nastavit marketing version
agvtool new-marketing-version 1.1.0

# Inkrementovat build number
agvtool next-version -all

# Nebo nastavit konkrétní build
agvtool new-version -all 2
```

### 3. Pomocí Fastlane

```bash
# Automaticky inkrementuje build number
fastlane beta
```

## Release workflow

1. **Před release:**
   - Zkontrolovat CHANGELOG
   - Rozhodnout o typu verze (major/minor/patch)
   - Aktualizovat version a build number

2. **Release:**
   ```bash
   # Nastavit verzi
   agvtool new-marketing-version 1.1.0
   agvtool new-version -all 2

   # Archivovat a uploadovat
   xcodebuild archive ...
   xcodebuild -exportArchive ...
   xcrun altool --upload-app ...
   ```

3. **Po release:**
   - Commit změn do git
   - Vytvořit git tag: `git tag v1.1.0`
   - Push tag: `git push origin v1.1.0`

## Historie verzí

| Verze | Build | Datum | Popis |
|-------|-------|-------|-------|
| 1.0.0 | 1 | 2026-01-18 | První TestFlight build |
| 1.1.0 | 2 | 2026-01-19 | Přidány 3 režimy skenování (Exteriér, Interiér, Objekt) |
| 1.1.0 | 3 | 2026-01-19 | Fix: CIContext memory leak, fallback pro gravityAndHeading |
| 1.1.0 | 4 | 2026-01-19 | Přidán MetricKit crash reporting, diagnostika v Settings |
| 1.1.0 | 5 | 2026-01-19 | Fix: CoverageAnalyzer buffer access crash (stride/offset) |

## Poznámky

- Build number musí být **vždy vyšší** než předchozí upload
- Stejnou version můžete uploadovat vícekrát s různými build numbers
- Pro TestFlight stačí inkrementovat build number
- Pro App Store release je obvykle nová version
