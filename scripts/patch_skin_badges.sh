#!/usr/bin/env bash
#
# patch_skin_badges.sh  –  Idempotent ADB skin patch for Amazon Waipu pay badges
#
# Usage:
#   ./patch_skin_badges.sh                   # Patch views configured in addon settings + SidePoster
#   ./patch_skin_badges.sh 527 522 50        # Patch specific view IDs
#   ./patch_skin_badges.sh --all             # Patch ALL known video views
#   ./patch_skin_badges.sh --remove          # Remove patches from all views
#   ./patch_skin_badges.sh --remove 527 522  # Remove patches from specific views
#
# Requires: adb (connected device), sed, python3 (optional, for JSON-RPC reload)

set -euo pipefail

###############################################################################
# Configuration
###############################################################################

SKIN_PATH="/sdcard/kodi_data/.kodi/addons/skin.arctic.zephyr.mod/1080i"
ADDON_SETTINGS="/sdcard/kodi_data/.kodi/userdata/addon_data/plugin.video.amazon-waipu/settings.xml"
KODI_JSONRPC_PORT=9090
BADGE_TEXTURE="special://home/addons/plugin.video.amazon-waipu/resources/media/badge_paid.png"
TMP_DIR=$(mktemp -d)
MARKER_PREFIX="Amazon Waipu Pay Badge"

# View-ID -> Filename mapping
declare -A VIEW_FILES=(
    [50]="View_50_List.xml"
    [53]="View_53_Poster.xml"
    [55]="View_55_Wall.xml"
    [500]="View_500_Thumbnails.xml"
    [510]="View_510_Minimal.xml"
    [521]="View_521_Minimal_V2.xml"
    [522]="View_522_Minimal_V2_Episodes.xml"
    [527]="View_527_List_V2.xml"
    [550]="View_550_SidePoster.xml"
    [56]="View_56_Fanart_V2.xml"
    [57]="View_57_Poster_V2.xml"
    [501]="View_501_Fanart.xml"
    [502]="View_502_Shift.xml"
)

ALL_VIEW_IDS=(50 53 55 56 57 500 501 502 510 521 522 527 550)

###############################################################################
# Functions
###############################################################################

log() { echo "[patch] $*"; }
err() { echo "[ERROR] $*" >&2; }

adb_pull() {
    adb pull "$1" "$2" 2>/dev/null
}

adb_push() {
    adb push "$1" "$2" 2>/dev/null
}

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

get_addon_views() {
    local settings_file="$TMP_DIR/addon_settings.xml"
    if ! adb_pull "$ADDON_SETTINGS" "$settings_file"; then
        log "Could not pull addon settings, using defaults (527)"
        echo "527"
        return
    fi

    local views=()
    for key in movieview showview seasonview episodeview; do
        local val
        val=$(grep -oP "id=\"${key}\"[^>]*>\\K[^<]+" "$settings_file" 2>/dev/null || true)
        if [[ -n "$val" && "$val" =~ ^[0-9]+$ ]]; then
            views+=("$val")
        fi
    done

    # Deduplicate and always include 50 (SidePoster covers this)
    local unique_views
    unique_views=$(printf '%s\n' "${views[@]}" 50 | sort -un)
    echo "$unique_views"
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
    local file="$1"
    # Strategy 1: Find closing </include> of the poster include inside <itemlayout>
    #   Arctic Zephyr uses <include content="include.widget.poster"> inside <itemlayout>
    local itemlayout_line
    itemlayout_line=$(grep -n '<itemlayout' "$file" | head -1 | cut -d: -f1)
    if [[ -n "$itemlayout_line" ]]; then
        local include_end
        include_end=$(tail -n +"$itemlayout_line" "$file" | grep -n '</include>' | head -1 | cut -d: -f1)
        if [[ -n "$include_end" ]]; then
            echo $((itemlayout_line + include_end - 1))
            return
        fi
    fi
    # Strategy 2: Look for PosterImage or ListItem.Art(poster) texture
    local poster_line
    poster_line=$(grep -n 'PosterImage\|ListItem\.Art(poster)' "$file" | head -1 | cut -d: -f1)
    if [[ -n "$poster_line" ]]; then
        local control_end
        control_end=$(tail -n +"$poster_line" "$file" | grep -n '</control>' | head -1 | cut -d: -f1)
        if [[ -n "$control_end" ]]; then
            echo $((poster_line + control_end - 1))
            return
        fi
    fi
}

find_focused_insertion_point() {
    local file="$1"
    # Find closing </include> of the poster include inside <focusedlayout>
    local focusedlayout_line
    focusedlayout_line=$(grep -n '<focusedlayout' "$file" | head -1 | cut -d: -f1)
    if [[ -n "$focusedlayout_line" ]]; then
        local include_end
        include_end=$(tail -n +"$focusedlayout_line" "$file" | grep -n '</include>' | head -1 | cut -d: -f1)
        if [[ -n "$include_end" ]]; then
            echo $((focusedlayout_line + include_end - 1))
            return
        fi
    fi
}

patch_file() {
    local view_id="$1" file="$2"

    if has_marker "$file" "$view_id"; then
        log "View ${view_id}: already patched, skipping"
        return 1
    fi

    local insert_line
    insert_line=$(find_insertion_point "$file")
    if [[ -z "$insert_line" ]]; then
        log "View ${view_id}: no insertion point found in itemlayout, skipping"
        return 1
    fi

    local badge_xml
    badge_xml=$(generate_badge_xml "$view_id")

    # Also patch focusedlayout if present
    local focused_line
    focused_line=$(find_focused_insertion_point "$file")

    if [[ -n "$focused_line" ]]; then
        # Patch focusedlayout first (higher line number) to avoid offset issues
        local tmp_file="$file.tmp"
        head -n "$focused_line" "$file" > "$tmp_file"
        echo "$badge_xml" >> "$tmp_file"
        tail -n +"$((focused_line + 1))" "$file" >> "$tmp_file"
        mv "$tmp_file" "$file"
        log "View ${view_id}: focusedlayout patched"

        # Recalculate itemlayout insertion (still at same line since it's before focusedlayout)
    fi

    local tmp_file="$file.tmp"
    head -n "$insert_line" "$file" > "$tmp_file"
    echo "$badge_xml" >> "$tmp_file"
    tail -n +"$((insert_line + 1))" "$file" >> "$tmp_file"
    mv "$tmp_file" "$file"

    log "View ${view_id}: itemlayout patched"
    return 0
}

remove_patch() {
    local view_id="$1" file="$2"

    if ! has_marker "$file" "$view_id"; then
        log "View ${view_id}: no patch found, nothing to remove"
        return 1
    fi

    local start_marker="${MARKER_PREFIX} - VIEW_${view_id} - START"
    local end_marker="${MARKER_PREFIX} - VIEW_${view_id} - END"

    sed -i "/${start_marker}/,/${end_marker}/d" "$file"
    log "View ${view_id}: patch removed"
    return 0
}

reload_skin() {
    log "Reloading Kodi skin..."
    local payload='{"jsonrpc":"2.0","method":"Addons.ExecuteAddon","params":{"addonid":"xbmc.python","params":["import xbmc; xbmc.executebuiltin(\"ReloadSkin()\")"]},"id":1}'

    # Try simple builtin execution via JSON-RPC
    (echo '{"jsonrpc":"2.0","method":"GUI.ActivateWindow","params":{"window":"home"},"id":1}' | \
        nc -w 2 localhost "$KODI_JSONRPC_PORT" 2>/dev/null) || true

    # Direct skin reload
    python3 -c "
import socket, json, time
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    s.connect(('localhost', $KODI_JSONRPC_PORT))
    req = json.dumps({'jsonrpc':'2.0','method':'Addons.ExecuteAddon','params':{'addonid':'script.toolbox','params':['ReloadSkin()']},'id':1})
    s.send(req.encode() + b'\n')
    time.sleep(1)
    s.close()
except Exception as e:
    print(f'Skin reload via JSON-RPC failed: {e}')
    print('Please restart Kodi manually or navigate to Settings > Appearance > Skin.')
" 2>/dev/null || log "Auto-reload not available, please restart Kodi to apply skin changes"
}

###############################################################################
# Main
###############################################################################

REMOVE_MODE=false
EXPLICIT_VIEWS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remove)
            REMOVE_MODE=true
            shift
            ;;
        --all)
            EXPLICIT_VIEWS=("${ALL_VIEW_IDS[@]}")
            shift
            ;;
        *)
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                EXPLICIT_VIEWS+=("$1")
            else
                err "Unknown argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Determine views to process
if [[ ${#EXPLICIT_VIEWS[@]} -eq 0 ]]; then
    log "Reading configured views from addon settings..."
    mapfile -t EXPLICIT_VIEWS < <(get_addon_views)
fi

log "Views to process: ${EXPLICIT_VIEWS[*]}"
log "Mode: $([ "$REMOVE_MODE" = true ] && echo 'REMOVE' || echo 'PATCH')"

changed_files=()

for view_id in "${EXPLICIT_VIEWS[@]}"; do
    filename="${VIEW_FILES[$view_id]:-}"
    if [[ -z "$filename" ]]; then
        err "View ${view_id}: no known filename mapping, skipping"
        continue
    fi

    remote_path="${SKIN_PATH}/${filename}"
    local_path="${TMP_DIR}/${filename}"

    if ! adb_pull "$remote_path" "$local_path"; then
        err "View ${view_id}: could not pull ${filename}"
        continue
    fi

    if [[ "$REMOVE_MODE" = true ]]; then
        if remove_patch "$view_id" "$local_path"; then
            changed_files+=("$view_id")
        fi
    else
        if patch_file "$view_id" "$local_path"; then
            changed_files+=("$view_id")
        fi
    fi
done

# Push changed files back
if [[ ${#changed_files[@]} -gt 0 ]]; then
    log "Pushing ${#changed_files[@]} changed file(s)..."
    for view_id in "${changed_files[@]}"; do
        filename="${VIEW_FILES[$view_id]}"
        local_path="${TMP_DIR}/${filename}"
        remote_path="${SKIN_PATH}/${filename}"
        adb_push "$local_path" "$remote_path"
        log "Pushed: ${filename}"
    done

    reload_skin
    log "Done! ${#changed_files[@]} view(s) updated."
else
    log "No changes needed."
fi
