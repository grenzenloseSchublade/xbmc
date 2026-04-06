# Amazon VOD Enhanced (Fork)

Fork des [Sandmann79 Amazon VOD Plugins](https://github.com/Sandmann79/xbmc) (`plugin.video.amazon-test`) mit verbesserter Bezahlartikel-Darstellung.

**Lizenz:** GPL-3.0-or-later (wie das Original)

## Warum dieser Fork?

Das Original-Plugin kennzeichnet Kaufartikel nur durch gelben Text (`[COLOR]`-Tags auf dem Titel). In Poster-, Wall- oder Netflix-Views ist dieser Text winzig oder nur bei Fokus sichtbar -- die Kennzeichnung wirkt dort kaum.

Dieser Fork verbessert die Sichtbarkeit durch:

- **Fettes Euro-Zeichen** (`€`) als Prefix vor Kaufartikeln im Titel
- **Label2 "Kauf"** als zweite Textzeile (in Listen-Views sichtbar)
- **Property `IsPaid`** fuer Skin-Anpassungen (z.B. Overlays)
- **Auffaelligere Default-Farbe** (`FFFF4400` Orange statt `FFE95E01` Gelb)
- **Zuverlaessiges View-Setting** (Kodi Bug #18576 Workaround)

## Installation

### 1. Kodi Repository hinzufuegen

Repository-URL: `https://grenzenloseSchublade.github.io/xbmc/`

In Kodi:
1. Dateimanager → Quelle hinzufuegen → URL eingeben (siehe oben)
2. Add-ons → Aus ZIP-Datei installieren → Quelle waehlen → Ordner **`repository.amazon-waipu`** oeffnen → **`repository.amazon-waipu-*.zip`** installieren (Kodi listet nur Links, bei denen Anzeige-Text und href uebereinstimmen; im Wurzelverzeichnis sind das Ordner-Links)
3. Add-ons → Aus Repository installieren → Amazon VOD Enhanced Repository → Video-Add-ons → Amazon VOD (Enhanced)

### 2. Original-Plugin deinstallieren

**Wichtig:** Original und Fork koennen nicht gleichzeitig installiert sein.

In Kodi: Add-ons → Meine Add-ons → Video → Amazon Prime Video → Deinstallieren

### 3. Amazon-Login

Nach Installation des Fork-Plugins muss einmalig neu eingeloggt werden (Tokens sind addon-spezifisch).

## View-Handling (Kodi Bug #18576 Fix)

Das Original-Plugin hat einen kritischen Bug: `Container.SetViewMode()` wird **vor** `endOfDirectory()` aufgerufen. Kodi ignoriert den Aufruf, weil das Directory noch nicht fertig geladen ist ([Bug #18576](https://github.com/xbmc/xbmc/issues/18576)). Dadurch greifen die View-Einstellungen des Plugins nicht zuverlaessig.

**Unser Fix in `itemlisting.py` (`setContentAndView()`):**

1. `endOfDirectory()` wird zuerst aufgerufen (Directory vollstaendig registriert)
2. `xbmc.sleep(100)` gibt Kodi Zeit, das Directory zu verarbeiten
3. Erst dann wird `Container.SetViewMode(viewid)` ausgefuehrt
4. `addSortMethod` mit `label2Mask='%h'` ermoeglicht die Label2-Anzeige ("Kauf")
5. Fallback fuer `videos`/`files`-Content-Typen (Kategorien, Suche) ueber `movieid`

**Auswirkung auf `kodi_set_views.sh` (waipu-setup):**

Das Setup-Skript setzt im `all`-Modus Views ueber 4 Methoden. Die **`plugin`-Methode** (Custom-View-IDs in den Plugin-Settings) funktioniert erst durch unseren Fix zuverlaessig, weil das Plugin die Settings nun korrekt anwendet. Damit greifen die konfigurierten Views auf **allen Verschachtelungsebenen**:

| Ebene | Content-Type | View (Beispiel Arctic Zephyr) |
|-------|-------------|-------------------------------|
| Filmliste | `movies` | `movieview` → 527 (ListV2) |
| Serienliste | `tvshows` | `showview` → 527 (ListV2) |
| Staffeluebersicht | `seasons` | `seasonview` → 524 (PosterFlixV2Seasons) |
| Episodenliste | `episodes` | `episodeview` → 521 (PosterFlixV2) |
| Kategorien/Suche | `videos`/`files` | Fallback → `movieid`, Skin-Default oder DB |

## Gepatchte Dateien

| Datei | Aenderung |
|-------|-----------|
| `plugin.video.amazon-waipu/addon.xml` | Neue Addon-ID, Version, Provider |
| `plugin.video.amazon-waipu/resources/lib/android_api.py` | Euro-Prefix in `formatTitle()`, Facetten-Prefix, `offerType`-Erkennung |
| `plugin.video.amazon-waipu/resources/lib/web_api.py` | Euro-Prefix fuer Kategorien |
| `plugin.video.amazon-waipu/resources/lib/itemlisting.py` | View-Bug-Fix (#18576), `setLabel2`, `IsPaid`/`OfferType` Properties, Badge-Steuerung |
| `plugin.video.amazon-waipu/resources/lib/badge_overlay.py` | PIL-Badge-Erzeugung, Hintergrund-Verarbeitung, Container.Refresh |
| `plugin.video.amazon-waipu/resources/lib/common.py` | Settings fuer `badge_display`, `badge_auto_refresh`, `badge_mode`, `badge_color` |
| `plugin.video.amazon-waipu/resources/settings.xml` | Bezahlinhalt-Einstellungen (Badge-Modus, Auto-Refresh, Farben) |
| `plugin.video.amazon-waipu/resources/media/badge_paid.png` | 64x64 Badge-Grafik fuer Skin-Overlay |
| `scripts/patch_skin_badges.sh` | ADB-Skript fuer idempotenten Skin-Patch |

## Sichtbarkeit nach View

| View | Titel-Farbe | Euro-Prefix | Label2 "Kauf" |
|------|-------------|-------------|---------------|
| ListV2 / WideList | Gut sichtbar | Gut sichtbar | Sichtbar |
| Poster / Wall | Klein, unter Poster | Sichtbar wenn Titel sichtbar | Nicht sichtbar |
| Netflix (504) | Nur bei Fokus | Nur bei Fokus | Nicht sichtbar |

**Empfehlung:** Fuer Amazon VOD Listen-Views verwenden (z.B. ListV2 = ID 527).

## Badge-Darstellung fuer Bezahlinhalte

Bezahlinhalte (Kauf, Miete, Abo) werden durch verschiedene Strategien visuell hervorgehoben. Die Strategie ist in den Addon-Einstellungen unter **Bezahlinhalte** konfigurierbar.

### Badge-Modi (Einstellung: "Badge-Darstellung")

| Modus | Beschreibung |
|-------|-------------|
| **Automatisch** (Standard) | Text-Farbe + PIL-Bild-Badge + Container.Refresh |
| **Nur Text-Farbe** | Orangefarbener Titel + Euro-Prefix, kein Poster-Badge |
| **Bild-Badge (PIL)** | Text-Farbe + PIL-generierter Rahmen/Badge auf dem Poster |
| **Skin-Overlay** | Text-Farbe + Skin zeigt Badge per `IsPaid`-Property (kein PIL) |

### Strategie A: PIL-Bild-Badge mit Container.Refresh

- Poster/Thumbnails werden im Hintergrund per PIL (Pillow) mit einem orangen Rahmen und/oder Euro-Badge versehen
- Bilder werden auf max. 600px Hoehe skaliert und als JPEG (85% Qualitaet) im Cache gespeichert (`special://temp/pay_badges/`)
- Nach Abschluss der Hintergrund-Verarbeitung wird automatisch `Container.Refresh` ausgefuehrt (abschaltbar ueber "Auto-Refresh nach Badge-Erzeugung")
- Beim zweiten Besuch der Seite werden gecachte Bilder sofort angezeigt

### Strategie B: Skin-Overlay (Arctic Zephyr Reloaded)

Fuer Arctic Zephyr Reloaded kann ein Skin-Overlay aktiviert werden, das ein 64x64-Euro-Badge direkt ueber dem Poster anzeigt -- ohne PIL, ohne Verzoegerung.

**Voraussetzungen:** Das Skript `scripts/patch_skin_badges.sh` muss einmalig (und nach jedem Skin-Update erneut) ausgefuehrt werden.

**Aufruf:**

```bash
# Standard: Views aus Addon-Einstellungen + SidePoster
./scripts/patch_skin_badges.sh

# Bestimmte Views patchen
./scripts/patch_skin_badges.sh 527 522 50

# Alle bekannten Video-Views patchen
./scripts/patch_skin_badges.sh --all

# Patch entfernen
./scripts/patch_skin_badges.sh --remove
```

Das Skript ist **idempotent pro View** -- wiederholtes Ausfuehren patcht keine Datei doppelt. Es nutzt Marker-Kommentare (`<!-- Amazon Waipu Pay Badge - VIEW_xxx -->`) zur Erkennung.

**Bekannte View-IDs:**

| ID | Datei |
|----|-------|
| 50 | `View_50_List.xml` |
| 53 | `View_53_Poster.xml` |
| 55 | `View_55_Wall.xml` |
| 500 | `View_500_Thumbnails.xml` |
| 510 | `View_510_Minimal.xml` |
| 521 | `View_521_Minimal_V2.xml` |
| 522 | `View_522_Minimal_V2_Episodes.xml` |
| 527 | `View_527_List_V2.xml` |
| 550 | `View_550_SidePoster.xml` |

### Technische Details

- **Properties:** `IsPaid` (true/false), `OfferType` (buy/rent/channel) werden auf jedem `ListItem` gesetzt
- **Cache:** `special://temp/pay_badges/` (JPEG, ~30-80KB pro Bild)
- **PIL-Abhaengigkeit:** Nur fuer Strategie A noetig; PIL/Pillow muss im Python-Pfad verfuegbar sein
- **Skin-Badge-Textur:** `resources/media/badge_paid.png` (64x64 PNG, orangenes Rechteck mit weissem Euro-Zeichen)

## Upstream-Sync

Das Original-Plugin (`plugin.video.amazon-test/`) bleibt unveraendert im Fork erhalten. Bei Bedarf:

```bash
git remote add upstream https://github.com/Sandmann79/xbmc.git  # einmalig
git fetch upstream
git merge upstream/master
# Konflikte loesen (unsere Patches sind isoliert), testen, pushen
```

## Abhaengigkeiten (Plugin-Installation)

`plugin.video.amazon-waipu` benoetigt u.a. `beautifulsoup4`, `pyxbmct`, `inputstreamhelper` -- diese liegen **nicht** in diesem Repository, sondern im **offiziellen Kodi-Repository** (`repository.xbmc.org`). Kodi loest sie beim Installieren des Plugins automatisch auf, **sofern** das offizielle Repo in Kodi installiert und erreichbar ist.

Aus diesem Repo kommen u.a.: `script.module.mechanicalsoup`, `script.module.pyautogui`, `script.module.amazoncaptcha` (siehe `docs/addons.xml`).

Das Repository-Addon (`repository.amazon-waipu`) laedt Index und ZIPs von **raw.githubusercontent.com** (`info` / `checksum` / `datadir` in `repository.amazon-waipu/addon.xml`). GitHub Pages dient als Browse-URL fuer die initiale Repository-Installation in Kodi.

**Warum raw.githubusercontent.com statt GitHub Pages?** GitHub Pages liefert `.md5`-Dateien als `Content-Type: application/octet-stream`, was Kodis HTTP-Client ablehnt (`CRepository: failed read`). raw.githubusercontent.com liefert `text/plain` -- kompatibel mit allen Kodi-Versionen.

## Kodi Repository (Self-Hosted)

Das Plugin wird ueber GitHub bereitgestellt:
- Browse-URL: `https://grenzenloseSchublade.github.io/xbmc/` (GitHub Pages, fuer Kodi-Dateimanager)
- Repo-URLs: `https://raw.githubusercontent.com/grenzenloseSchublade/xbmc/master/docs/` (addons.xml, ZIPs)
- Build: `scripts/build_repo.sh` generiert ZIPs + `addons.xml` in `docs/`
- CI: GitHub Action (`.github/workflows/build-repo.yml`) baut automatisch bei Push

## Struktur

```
xbmc/  (Fork von Sandmann79/xbmc)
├── plugin.video.amazon-test/            # Original (unveraendert)
├── plugin.video.amazon-waipu/           # Fork mit Patches
│   ├── addon.xml                        # ID: plugin.video.amazon-waipu
│   ├── resources/lib/android_api.py     # Patch: formatTitle, Facetten, offerType
│   ├── resources/lib/web_api.py         # Patch: Kategorien-Farben
│   ├── resources/lib/itemlisting.py     # Patch: View-Fix #18576, Label2, IsPaid, Badge-Steuerung
│   ├── resources/lib/badge_overlay.py   # PIL-Badge + Container.Refresh
│   ├── resources/lib/common.py          # Badge-Einstellungen
│   ├── resources/media/badge_paid.png   # Skin-Overlay-Badge (64x64)
│   └── resources/settings.xml           # Bezahlinhalt-Einstellungen
├── repository.amazon-waipu/             # Kodi-Repository-Addon
├── docs/                                # GitHub Pages (addons.xml, ZIPs)
├── scripts/build_repo.sh               # ZIP + addons.xml Builder
├── scripts/patch_skin_badges.sh         # ADB Skin-Patch fuer Badge-Overlay
└── .github/workflows/build-repo.yml    # CI Pipeline
```

## Zusammenspiel mit waipu-setup

Dieser Fork wird in [waipu-setup](https://github.com/grenzenloseSchublade/waipu-setup) als Git-Submodule unter `vendor/xbmc-amazon-fork/` referenziert. Die Integration ist in `config.json` (`amazon_plugin` Key) konfigurierbar.
