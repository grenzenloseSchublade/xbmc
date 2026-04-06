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

## Gepatchte Dateien

| Datei | Aenderung |
|-------|-----------|
| `plugin.video.amazon-waipu/addon.xml` | Neue Addon-ID, Version, Provider |
| `plugin.video.amazon-waipu/resources/lib/android_api.py` | Euro-Prefix in `formatTitle()`, Facetten-Prefix |
| `plugin.video.amazon-waipu/resources/lib/web_api.py` | Euro-Prefix fuer Kategorien |
| `plugin.video.amazon-waipu/resources/lib/itemlisting.py` | `setLabel2`, `IsPaid` Property, `addSortMethod` |
| `plugin.video.amazon-waipu/resources/settings.xml` | `paycol` Default geaendert |

## Sichtbarkeit nach View

| View | Titel-Farbe | Euro-Prefix | Label2 "Kauf" |
|------|-------------|-------------|---------------|
| ListV2 / WideList | Gut sichtbar | Gut sichtbar | Sichtbar |
| Poster / Wall | Klein, unter Poster | Sichtbar wenn Titel sichtbar | Nicht sichtbar |
| Netflix (504) | Nur bei Fokus | Nur bei Fokus | Nicht sichtbar |

**Empfehlung:** Fuer Amazon VOD Listen-Views verwenden (z.B. ListV2 = ID 527).

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

Das Repository-Addon (`repository.amazon-waipu`) laedt Index und ZIPs von **GitHub Pages** (`info` / `checksum` / `datadir` in `repository.amazon-waipu/addon.xml`).

## Kodi Repository (Self-Hosted)

Das Plugin wird ueber GitHub Pages bereitgestellt:
- URL: `https://grenzenloseSchublade.github.io/xbmc/`
- Build: `scripts/build_repo.sh` generiert ZIPs + `addons.xml` in `docs/`
- CI: GitHub Action (`.github/workflows/build-repo.yml`) baut automatisch bei Push

## Struktur

```
xbmc/  (Fork von Sandmann79/xbmc)
├── plugin.video.amazon-test/            # Original (unveraendert)
├── plugin.video.amazon-waipu/           # Fork mit Patches
│   ├── addon.xml                        # ID: plugin.video.amazon-waipu
│   ├── resources/lib/android_api.py     # Patch: formatTitle, Facetten
│   ├── resources/lib/web_api.py         # Patch: Kategorien-Farben
│   ├── resources/lib/itemlisting.py     # Patch: Label2, IsPaid, SortMethod
│   └── resources/settings.xml           # paycol Default
├── repository.amazon-waipu/             # Kodi-Repository-Addon
├── docs/                                # GitHub Pages (addons.xml, ZIPs)
├── scripts/build_repo.sh               # ZIP + addons.xml Builder
└── .github/workflows/build-repo.yml    # CI Pipeline
```

## Zusammenspiel mit waipu-setup

Dieser Fork wird in [waipu-setup](https://github.com/grenzenloseSchublade/waipu-setup) als Git-Submodule unter `vendor/xbmc-amazon-fork/` referenziert. Die Integration ist in `config.json` (`amazon_plugin` Key) konfigurierbar.
