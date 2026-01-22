# LiDAR 3D Scanner - UI Testovaci Scenare

## Prehled

Tento dokument obsahuje testovaci scenare pro manualni testovani aplikace v iOS Simulatoru s mock daty.

---

## 1. Spusteni aplikace

### Scenar 1.1: Prvni spusteni
- **Kroky:**
  1. Spustit aplikaci
  2. Pockat na nacteni
- **Ocekavany vysledek:**
  - Zobrazi se galerie s textem "Zadne modely"
  - Dole je modre tlacitko pro skenovani

### Scenar 1.2: Mock mode aktivni (Simulator)
- **Kroky:**
  1. Overit, ze aplikace bezi na simulatoru
- **Ocekavany vysledek:**
  - Mock mode je automaticky povolen
  - Lze pouzivat skenovaci funkce bez LiDAR

---

## 2. Skenovani (Mock Mode)

### Scenar 2.1: Spusteni mock skenovani
- **Kroky:**
  1. Kliknout na modre tlacitko sken
  2. Vybrat "LiDAR sken" nebo "RoomPlan"
- **Ocekavany vysledek:**
  - Otevre se skenovaci obrazovka
  - Zobrazi se mock vizualizace

### Scenar 2.2: Ulozeni mock skenu
- **Kroky:**
  1. Spustit skenovani
  2. Kliknout na "Stop" / "Ulozit"
  3. Zadat nazev
- **Ocekavany vysledek:**
  - Sken se ulozi do galerie
  - Zobrazi se v seznamu modelu

---

## 3. Galerie modelu

### Scenar 3.1: Zobrazeni prazdne galerie
- **Kroky:**
  1. Spustit aplikaci bez zadnych skenu
- **Ocekavany vysledek:**
  - Zobrazi se "Zadne modely"
  - Informace o pouziti tlacitka skenovani

### Scenar 3.2: Razeni modelu
- **Kroky:**
  1. Mit alespon 2 modely v galerii
  2. Kliknout na ikonu razeni (vpravo nahore)
  3. Vybrat ruzne typy razeni
- **Ocekavany vysledek:**
  - Modely se preradi podle vybraneho kriteria
  - Dostupne: Nejnovejsi, Nejstarsi, Nazev A-Z, Nejvetsi

### Scenar 3.3: Vyhledavani
- **Kroky:**
  1. Mit alespon 2 modely s ruznymi nazvy
  2. Kliknout do vyhledavaciho pole
  3. Zadat cast nazvu
- **Ocekavany vysledek:**
  - Filtruje se seznam podle zadaneho textu

---

## 4. Detail modelu

### Scenar 4.1: Otevreni detailu
- **Kroky:**
  1. Kliknout na model v galerii
- **Ocekavany vysledek:**
  - Otevre se detail modelu
  - Zobrazi se 3D nahled (nebo placeholder)
  - Dole jsou akcni tlacitka

### Scenar 4.2: Prejmenovat model ✅ OPRAVENO
- **Kroky:**
  1. Otevrit detail modelu
  2. Kliknout na menu (tri tecky vpravo nahore)
  3. Vybrat "Prejmenovat"
  4. Zadat novy nazev
  5. Potvrdit "Ulozit"
- **Ocekavany vysledek:**
  - Zobrazi se alert s textovym polem
  - Po ulozeni se nazev zmeni v titulku
  - Zmena se projevit i v galerii

### Scenar 4.3: Smazat model ✅ OPRAVENO
- **Kroky:**
  1. Otevrit detail modelu
  2. Kliknout na menu (tri tecky)
  3. Vybrat "Smazat"
  4. Potvrdit smazani
- **Ocekavany vysledek:**
  - Zobrazi se potvrzovaci dialog
  - Po potvrzeni se model smaze
  - Navrat do galerie

---

## 5. AI Zpracovani

### Scenar 5.1: Spustit AI zpracovani ✅ OPRAVENO
- **Kroky:**
  1. Otevrit detail modelu
  2. Kliknout na tlacitko "AI" (hulka s hvezdickou)
- **Ocekavany vysledek:**
  - Zobrazi se progress bar
  - Faze zpracovani: Analyzing, Processing, Completing...
  - Po dokonceni se aktualizuje mesh

### Scenar 5.2: AI zpracovani s mock daty
- **Kroky:**
  1. Vytvorit novy mock sken
  2. Otevrit detail
  3. Spustit AI zpracovani
- **Ocekavany vysledek:**
  - Automaticky se vytvori mock session
  - AI zpracovani probehne na mock datech
  - Pri chybe se zobrazi error alert

---

## 6. Mereni

### Scenar 6.1: Otevrit merici nastroj
- **Kroky:**
  1. Otevrit detail modelu s validni session
  2. Kliknout na "Merit" (pravitko)
- **Ocekavany vysledek:**
  - Otevre se interaktivni merici view
  - Moznost merit vzdalenosti, plochy, objemy

### Scenar 6.2: Prepinani jednotek
- **Kroky:**
  1. Otevrit merici nastroj
  2. Zmenit jednotky (m/cm/ft/in)
- **Ocekavany vysledek:**
  - Hodnoty se prepocitaji na nove jednotky

---

## 7. Enhanced 3D Viewer

### Scenar 7.1: Otevrit 3D+ prohlizec
- **Kroky:**
  1. Otevrit detail modelu
  2. Kliknout na "3D+" (kostka)
- **Ocekavany vysledek:**
  - Otevre se rozsireny 3D prohlizec
  - Moznost rotace, zoom, pan

---

## 8. Export

### Scenar 8.1: Otevrit export
- **Kroky:**
  1. Otevrit detail modelu
  2. Kliknout na "Export"
- **Ocekavany vysledek:**
  - Zobrazi se moznosti exportu
  - Formaty: USDZ, OBJ, PLY, STL

### Scenar 8.2: Export do USDZ
- **Kroky:**
  1. Vybrat USDZ format
  2. Potvrdit export
- **Ocekavany vysledek:**
  - Soubor se vytvori
  - Otevre se share sheet nebo AR Quick Look

---

## 9. Chybove stavy

### Scenar 9.1: Prazdny mesh pri AI zpracovani
- **Kroky:**
  1. Pokusit se zpracovat model bez platnych dat
- **Ocekavany vysledek:**
  - ✅ Aplikace nespadne (opraveno)
  - Zobrazi se chybova hlaska

### Scenar 9.2: Neplatne indexy v mesh
- **Kroky:**
  1. (Interni test) - vytvorit mesh s neplatnymi face indexy
- **Ocekavany vysledek:**
  - ✅ Aplikace nespadne (opraveno)
  - Neplatne faces se preskoci

---

## 10. Nastaveni

### Scenar 10.1: Otevrit nastaveni
- **Kroky:**
  1. Najit pristup k nastaveni (pokud existuje)
- **Ocekavany vysledek:**
  - Zobrazeni nastaveni aplikace

### Scenar 10.2: Prepnout mock mode
- **Kroky:**
  1. Otevrit nastaveni
  2. Prepnout mock mode on/off
- **Ocekavany vysledek:**
  - Zmeni se chovani aplikace

---

## Checklist pro testovani

### Zakladni funkcionalita
- [ ] Aplikace se spusti bez padu
- [ ] Galerie se zobrazi spravne
- [ ] Lze vytvorit mock sken
- [ ] Lze prejmenovat model
- [ ] Lze smazat model
- [ ] AI tlacitko reaguje
- [ ] Mereni funguje
- [ ] Export funguje

### Stabilita
- [ ] Zadne pady pri beznem pouzivani
- [ ] Spravne zpracovani prazdnych dat
- [ ] Spravne zpracovani chyb

### UI/UX
- [ ] Vsechny tlacitka reagují
- [ ] Texty jsou citelne
- [ ] Navigace funguje spravne
- [ ] Alerty se zobrazuji spravne

---

## Poznamky z testovani

| Datum | Scenar | Vysledek | Poznamka |
|-------|--------|----------|----------|
| 2026-01-18 | 4.2 | ✅ Opraveno | Implementovano prejmenovat |
| 2026-01-18 | 4.3 | ✅ Opraveno | Implementovano smazat |
| 2026-01-18 | 5.1 | ✅ Opraveno | AI button nyni funguje |
| 2026-01-18 | 9.1 | ✅ Opraveno | Crash fix v AIGeometryGenerationService |

---

## Spusteni testu

```bash
# Build a instalace
cd /Users/petrzapletal/Documents/GitHub/lidar-app/LidarAPP
xcodebuild -scheme LidarAPP -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Instalace do simulatoru
xcrun simctl install "iPhone 17 Pro" ~/Library/Developer/Xcode/DerivedData/LidarAPP-*/Build/Products/Debug-iphonesimulator/LidarAPP.app

# Spusteni
xcrun simctl launch "iPhone 17 Pro" com.lidarscanner.app

# Unit testy
xcodebuild test -scheme LidarAPP -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LidarAPPTests
```
