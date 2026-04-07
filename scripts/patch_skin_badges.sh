#!/usr/bin/env bash
#
# patch_skin_badges.sh  –  Standalone idempotent ADB skin patch for Amazon Waipu pay badges
#
# Patches Arctic Zephyr Reloaded view XML files to show a 64x64 Euro badge
# overlay on paid content posters (via ListItem.Property(IsPaid)).
#
# Usage:
#   ./scripts/patch_skin_badges.sh                   # Patch views from addon settings + SidePoster
#   ./scripts/patch_skin_badges.sh 527 522 550       # Patch specific view IDs
#   ./scripts/patch_skin_badges.sh --all             # Patch ALL known video views
#   ./scripts/patch_skin_badges.sh --remove          # Remove patches from all views
#   ./scripts/patch_skin_badges.sh --remove 527 522  # Remove patches from specific views
#   ./scripts/patch_skin_badges.sh --list            # Show patched/unpatched status per view
#
# Requires: adb (connected device), sed
#
# Note: waipu-setup provides an enhanced version at scripts/kodi_patch_skin_badges.sh
#       with config.json integration and full logging.

set -euo pipefail

###############################################################################
# Configuration
###############################################################################

KODI_DATA="/sdcard/kodi_data/.kodi"
SKIN_ID="skin.arctic.zephyr.mod"
SKIN_RES_DIR=""
ADDON_ID="plugin.video.amazon-waipu"
BADGE_TEXTURE="special://home/addons/${ADDON_ID}/resources/media/badge_paid.png"
TMP_DIR=$(mktemp -d)
MARKER_PREFIX="Amazon Waipu Pay Badge"

SPINNER_VIEWS=(50 51 52 53 54 55 500 501 502)

declare -A VIEW_FILES=(
    [50]="View_50_List.xml"
    [51]="View_51_BigWide.xml"
    [52]="View_52_BigList.xml"
    [53]="View_53_Poster.xml"
    [54]="View_54_Banner.xml"
    [55]="View_55_Wall.xml"
    [56]="View_56_Fanart_V2.xml"
    [57]="View_57_Poster_V2.xml"
    [58]="View_58_Cards.xml"
    [59]="View_59_BannerWall.xml"
    [500]="View_500_Thumbnails.xml"
    [501]="View_501_Fanart.xml"
    [504]="View_504_Netflix.xml"
    [507]="View_507_Fanart.xml"
    [509]="View_509_Shifted.xml"
    [510]="View_510_Minimal.xml"
    [511]="View_511_DoubleFlix.xml"
    [512]="View_512_DoubleFlixBanner.xml"
    [513]="View_513_VerticalShifted.xml"
    [514]="View_514_SquareLight.xml"
    [515]="View_515_SideCards.xml"
    [516]="View_516_SeasonsInfo.xml"
    [517]="View_517_PosterWallSmall.xml"
    [519]="View_519_ShiftedClearArt.xml"
    [520]="View_520_FanartFlix.xml"
    [521]="View_521_Minimal_V2.xml"
    [522]="View_522_Minimal_V2_Episodes.xml"
    [524]="View_524_PosterFlixV2Seasons.xml"
    [526]="View_526_SeasonsInfoV2.xml"
    [527]="View_527_List_V2.xml"
    [550]="View_550_SidePoster.xml"
    [555]="View_555_FanartThumbs.xml"
)

ALL_VIEW_IDS=(50 51 52 53 54 55 56 57 58 59 500 501 504 507 509 510 511 512 513 514 515 516 517 519 520 521 522 524 526 527 550 555)

declare -A VIEW_NAMES=(
    [50]="List"                 [51]="BigWide"
    [52]="BigList"              [53]="BigPoster"
    [54]="Banner"               [55]="PosterWall"
    [56]="MediaInfo"            [57]="ExtraInfo"
    [58]="Cards"                [59]="BannerWall"
    [500]="Thumbnails"          [501]="ModernFanart"
    [504]="Netflix"             [507]="Fanart"
    [509]="Shifted"             [510]="PosterFlix"
    [511]="DoubleFlix"          [512]="DoubleFlixBanner"
    [513]="VerticalShifted"     [514]="SquareLight"
    [515]="SideCards"           [516]="SeasonsInfo"
    [517]="PosterWallSmall"     [519]="ShiftedClearArt"
    [520]="FanartFlix"          [521]="PosterFlixV2"
    [522]="FanartFlixV2"        [524]="PosterFlixV2Seasons"
    [526]="SeasonsInfoV2"       [527]="ListV2"
    [550]="SidePoster"          [555]="FanartThumbs"
)

###############################################################################
# Functions
###############################################################################

log() { echo "[patch] $*"; }
err() { echo "[ERROR] $*" >&2; }

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

detect_skin_res_dir() {
    local skin_base="${KODI_DATA}/addons/${SKIN_ID}"
    for res_dir in 1080i 720p xml; do
        if adb shell "test -d '${skin_base}/${res_dir}'" 2>/dev/null; then
            SKIN_RES_DIR="${skin_base}/${res_dir}"
            log "Skin-Verzeichnis: ${SKIN_RES_DIR}"
            return 0
        fi
    done
    err "Skin-Verzeichnis nicht gefunden: ${skin_base}/{1080i,720p,xml}"
    return 1
}

resolve_view_file() {
    local view_id="$1"
    local known="${VIEW_FILES[$view_id]:-}"
    if [[ -n "$known" ]]; then
        echo "$known"
        return
    fi
    local found
    found=$(adb shell "ls '${SKIN_RES_DIR}/View_${view_id}_'*.xml 2>/dev/null" | tr -d '\r' | head -1)
    if [[ -n "$found" ]]; then
        echo "$(basename "$found")"
    fi
}

get_addon_views() {
    local settings_remote="${KODI_DATA}/userdata/addon_data/${ADDON_ID}/settings.xml"
    local settings_file="$TMP_DIR/addon_settings.xml"

    if ! adb pull "$settings_remote" "$settings_file" 2>/dev/null; then
        log "Addon-Settings nicht lesbar, verwende Defaults (527 + 550)"
        echo "527"
        echo "550"
        return
    fi

    _read_setting() {
        grep -oP "id=\"${1}\"[^>]*>\\K[^<]+" "$settings_file" 2>/dev/null || true
    }

    local views=()
    local pairs=("movieview:movieid" "showview:showid" "seasonview:seasonid" "episodeview:episodeid")

    for pair in "${pairs[@]}"; do
        local spinner_key="${pair%%:*}"
        local id_key="${pair##*:}"
        local spinner_val
        spinner_val=$(_read_setting "$spinner_key")

        if [[ "$spinner_val" == "9" ]]; then
            local custom_id
            custom_id=$(_read_setting "$id_key")
            if [[ -n "$custom_id" && "$custom_id" =~ ^[0-9]+$ && "$custom_id" -gt 0 ]]; then
                views+=("$custom_id")
            fi
        elif [[ -n "$spinner_val" && "$spinner_val" =~ ^[0-9]+$ ]]; then
            local idx="$spinner_val"
            if (( idx >= 0 && idx < ${#SPINNER_VIEWS[@]} )); then
                views+=("${SPINNER_VIEWS[$idx]}")
            fi
        fi
    done

    if [[ ${#views[@]} -eq 0 ]]; then
        views=(527)
    fi

    printf '%s\n' "${views[@]}" 550 | sort -un
    unset -f _read_setting
}

generate_badge_xml() {
    local view_id="$1"
    cat <<XMLEOF
<!-- ${MARKER_PREFIX} - VIEW_${view_id} - START -->
<control type="image">
    <left>0</left>
    <top>0</top>
    <width>64</width>
    <height>64</height>
    <texture>${BADGE_TEXTURE}</texture>
    <visible>String.IsEqual(ListItem.Property(IsPaid),true)</visible>
</control>
<!-- ${MARKER_PREFIX} - VIEW_${view_id} - END -->
XMLEOF
}

has_marker() {
    local file="$1" view_id="$2"
    grep -q "${MARKER_PREFIX} - VIEW_${view_id} - START" "$file" 2>/dev/null
}

find_insertion_point() {
    local file="$1" layout_tag="$2"
    local layout_line
    layout_line=$(grep -n "<${layout_tag}" "$file" | head -1 | cut -d: -f1)
    [[ -z "$layout_line" ]] && return

    local include_end
    include_end=$(tail -n +"$layout_line" "$file" | grep -n '</include>' | head -1 | cut -d: -f1)
    if [[ -n "$include_end" ]]; then
        echo $((layout_line + include_end - 1))
        return
    fi

    local poster_line
    poster_line=$(tail -n +"$layout_line" "$file" | grep -n 'PosterImage\|ListItem\.Art(poster)' | head -1 | cut -d: -f1)
    if [[ -n "$poster_line" ]]; then
        local abs_poster=$((layout_line + poster_line - 1))
        local control_end
        control_end=$(tail -n +"$abs_poster" "$file" | grep -n '</control>' | head -1 | cut -d: -f1)
        if [[ -n "$control_end" ]]; then
            echo $((abs_poster + control_end - 1))
            return
        fi
    fi
}

patch_file() {
    local view_id="$1" file="$2"

    if has_marker "$file" "$view_id"; then
        log "View ${view_id}: bereits gepatcht, ueberspringe"
        return 1
    fi

    local badge_xml
    badge_xml=$(generate_badge_xml "$view_id")
    local patched=false

    local focused_line
    focused_line=$(find_insertion_point "$file" "focusedlayout")
    if [[ -n "$focused_line" ]]; then
        local tmp_file="$file.tmp"
        head -n "$focused_line" "$file" > "$tmp_file"
        echo "$badge_xml" >> "$tmp_file"
        tail -n +"$((focused_line + 1))" "$file" >> "$tmp_file"
        mv "$tmp_file" "$file"
        log "  View ${view_id}: focusedlayout gepatcht"
        patched=true
    fi

    # Recalculate from modified file
    local insert_line
    insert_line=$(find_insertion_point "$file" "itemlayout")
    if [[ -n "$insert_line" ]]; then
        local tmp_file="$file.tmp"
        head -n "$insert_line" "$file" > "$tmp_file"
        echo "$badge_xml" >> "$tmp_file"
        tail -n +"$((insert_line + 1))" "$file" >> "$tmp_file"
        mv "$tmp_file" "$file"
        log "  View ${view_id}: itemlayout gepatcht"
        patched=true
    fi

    if [[ "$patched" == "false" ]]; then
        err "View ${view_id}: kein Einfuegepunkt gefunden"
        return 1
    fi
    return 0
}

remove_patch() {
    local view_id="$1" file="$2"
    if ! has_marker "$file" "$view_id"; then
        log "View ${view_id}: kein Patch vorhanden"
        return 1
    fi
    local start_marker="${MARKER_PREFIX} - VIEW_${view_id} - START"
    local end_marker="${MARKER_PREFIX} - VIEW_${view_id} - END"
    sed -i "/${start_marker}/,/${end_marker}/d" "$file"
    log "View ${view_id}: Patch entfernt"
    return 0
}

list_views() {
    echo ""
    printf "  %-6s %-22s %-30s %s\n" "ID" "Name" "Datei" "Status"
    echo "  $(printf '─%.0s' {1..80})"
    for view_id in "${ALL_VIEW_IDS[@]}"; do
        local name="${VIEW_NAMES[$view_id]:-?}"
        local filename
        filename=$(resolve_view_file "$view_id")
        if [[ -z "$filename" ]]; then
            printf "  %-6s %-22s %-30s %s\n" "$view_id" "$name" "-" "Unbekannt"
            continue
        fi
        local remote_path="${SKIN_RES_DIR}/${filename}"
        local local_path="${TMP_DIR}/${filename}"
        if adb pull "$remote_path" "$local_path" 2>/dev/null; then
            if has_marker "$local_path" "$view_id"; then
                printf "  %-6s %-22s %-30s \033[0;32m%s\033[0m\n" "$view_id" "$name" "$filename" "GEPATCHT"
            else
                printf "  %-6s %-22s %-30s %s\n" "$view_id" "$name" "$filename" "-"
            fi
        else
            printf "  %-6s %-22s %-30s %s\n" "$view_id" "$name" "$filename" "Nicht auf Geraet"
        fi
    done
    echo ""
}

###############################################################################
# Main
###############################################################################

REMOVE_MODE=false
LIST_MODE=false
NO_RESTART=false
EXPLICIT_VIEWS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --remove)    REMOVE_MODE=true; shift ;;
        --all)       EXPLICIT_VIEWS=("${ALL_VIEW_IDS[@]}"); shift ;;
        --list)      LIST_MODE=true; shift ;;
        --no-restart) NO_RESTART=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--all|--remove|--list|--no-restart] [VIEW_IDs...]"
            exit 0 ;;
        *)
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                EXPLICIT_VIEWS+=("$1")
            else
                err "Unknown argument: $1"
                exit 1
            fi
            shift ;;
    esac
done

detect_skin_res_dir || exit 1

if [[ "$LIST_MODE" == true ]]; then
    list_views
    exit 0
fi

if [[ ${#EXPLICIT_VIEWS[@]} -eq 0 ]]; then
    log "Lese konfigurierte Views aus Addon-Settings ..."
    mapfile -t EXPLICIT_VIEWS < <(get_addon_views)
fi

log "Views: ${EXPLICIT_VIEWS[*]}"
log "Modus: $([ "$REMOVE_MODE" = true ] && echo 'ENTFERNEN' || echo 'PATCHEN')"

changed_files=()

for view_id in "${EXPLICIT_VIEWS[@]}"; do
    filename=$(resolve_view_file "$view_id")
    if [[ -z "$filename" ]]; then
        err "View ${view_id}: keine Datei-Zuordnung"
        continue
    fi
    remote_path="${SKIN_RES_DIR}/${filename}"
    local_path="${TMP_DIR}/${filename}"
    if ! adb pull "$remote_path" "$local_path" 2>/dev/null; then
        err "View ${view_id}: ${filename} nicht auf Geraet"
        continue
    fi
    if [[ "$REMOVE_MODE" = true ]]; then
        remove_patch "$view_id" "$local_path" && changed_files+=("$view_id")
    else
        patch_file "$view_id" "$local_path" && changed_files+=("$view_id")
    fi
done

if [[ ${#changed_files[@]} -gt 0 ]]; then
    log "Uebertrage ${#changed_files[@]} geaenderte Datei(en) ..."
    for view_id in "${changed_files[@]}"; do
        filename=$(resolve_view_file "$view_id")
        adb push "${TMP_DIR}/${filename}" "${SKIN_RES_DIR}/${filename}" 2>/dev/null
        log "  ${filename}"
    done
    if [[ "$NO_RESTART" == false ]]; then
        log "Starte Kodi neu ..."
        adb shell am force-stop org.xbmc.kodi 2>/dev/null || true
        sleep 2
        adb shell am start -n org.xbmc.kodi/.Splash 2>/dev/null || true
    fi
    log "Fertig: ${#changed_files[@]} View(s) aktualisiert"
else
    log "Keine Aenderungen noetig"
fi
