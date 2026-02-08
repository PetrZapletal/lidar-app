# Lumiscan - Doc-version2

Opravená a kompletní projektová dokumentace (stav k 2026-02-08).

## Dokumenty

| # | Soubor | Popis |
|---|--------|-------|
| 01 | [PROJECT_OVERVIEW.md](./01_PROJECT_OVERVIEW.md) | Vize, architektura, stack, pipeline |
| 02 | [DIRECTORY_STRUCTURE.md](./02_DIRECTORY_STRUCTURE.md) | Kompletní adresářová struktura |
| 03 | [DEVELOPMENT_PHASES.md](./03_DEVELOPMENT_PHASES.md) | Fáze vývoje s reálným stavem |
| 04 | [API_REFERENCE.md](./04_API_REFERENCE.md) | Kompletní backend API reference |
| 05 | [AUTONOMOUS_DEBUG.md](./05_AUTONOMOUS_DEBUG.md) | Autonomní debug s real-time iOS log streamem |
| 06 | [DEPENDENCIES.md](./06_DEPENDENCIES.md) | Skutečné iOS a backend závislosti |
| 07 | [BUILD_AND_DEPLOY.md](./07_BUILD_AND_DEPLOY.md) | Build příkazy, konfigurace, TestFlight |
| 08 | [CODING_CONVENTIONS.md](./08_CODING_CONVENTIONS.md) | Skutečné konvence z kódu |
| 09 | [3D_PIPELINE.md](./09_3D_PIPELINE.md) | CAPTURE → PROCESS → REFINE → OUTPUT pipeline |
| 10 | [KNOWN_ISSUES.md](./10_KNOWN_ISSUES.md) | Známé problémy a technický dluh |

## Klíčový rozdíl oproti Doc-version1

Doc-version1 (`docs/`) obsahuje **idealizovanou specifikaci** - co má být. Doc-version2 obsahuje **skutečný stav** - co reálně existuje v kódu, co funguje a co ne.

## Pro Claude Code

Tento adresář slouží jako **ground truth** pro AI agenty pracující na projektu. Každý dokument odráží skutečný stav implementace ověřený analýzou zdrojového kódu.
