#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCS_DIR="${REPO_ROOT}/docs"

ADDONS=(
    "plugin.video.amazon-waipu"
    "repository.amazon-waipu"
    "script.module.amazoncaptcha"
    "script.module.mechanicalsoup"
    "script.module.pyautogui"
)

rm -rf "${DOCS_DIR}"
mkdir -p "${DOCS_DIR}"
touch "${DOCS_DIR}/.nojekyll"

DOWNLOAD_LINKS=""

for addon in "${ADDONS[@]}"; do
    addon_dir="${REPO_ROOT}/${addon}"
    [[ -d "${addon_dir}" ]] || { echo "SKIP: ${addon} nicht gefunden"; continue; }

    version=$(python3 -c "
import xml.etree.ElementTree as ET
print(ET.parse('${addon_dir}/addon.xml').getroot().attrib['version'])")
    zip_name="${addon}-${version}.zip"
    target_dir="${DOCS_DIR}/${addon}"
    mkdir -p "${target_dir}"

    echo "ZIP: ${addon} v${version}"
    (cd "${REPO_ROOT}" && zip -r "${target_dir}/${zip_name}" "${addon}/" \
        -x "${addon}/.git/*" -x "${addon}/__pycache__/*" -x "${addon}/*.pyc")

    # Kodi laedt icon.png/fanart.png aus datadir/{addon_id}/ (nicht nur aus ZIP).
    for asset in icon.png fanart.png clearlogo.png; do
        [[ -f "${addon_dir}/${asset}" ]] && cp "${addon_dir}/${asset}" "${target_dir}/"
    done

    # Kodi CHTTPDirectory: Anzeige-Text muss mit href uebereinstimmen (nach Slash-Strip).
    # Verzeichnis-Links (href=addon/), nicht ZIP mit anderem Link-Text.
    DOWNLOAD_LINKS="${DOWNLOAD_LINKS}        <li><a href=\"${addon}/\">${addon}</a></li>\n"

    cat > "${target_dir}/index.html" <<SUBDIREOF
<!DOCTYPE html>
<html><head><title>${addon}</title></head>
<body>
<h1>${addon}</h1>
<a href="${zip_name}">${zip_name}</a>
</body>
</html>
SUBDIREOF
done

cat > "${DOCS_DIR}/index.html" <<INDEXEOF
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <title>Amazon VOD Enhanced - Kodi Repository</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 700px; margin: 60px auto; padding: 0 20px; color: #e0e0e0; background: #1a1a2e; }
        h1 { color: #00a8e0; } h2 { color: #ccc; border-bottom: 1px solid #333; padding-bottom: 6px; }
        a { color: #ff8c00; } code { background: #16213e; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
        .box { background: #16213e; border-left: 4px solid #00a8e0; padding: 16px; margin: 20px 0; border-radius: 4px; }
        ol li { margin-bottom: 8px; }
    </style>
</head>
<body>
    <h1>Amazon VOD Enhanced</h1>
    <p>Fork des <a href="https://github.com/Sandmann79/xbmc">Sandmann79 Amazon VOD Plugins</a> mit verbesserter Bezahlartikel-Darstellung.</p>
    <div class="box"><strong>Kodi Repository URL:</strong><br><code>https://grenzenloseSchublade.github.io/xbmc/</code></div>
    <h2>Installation in Kodi</h2>
    <ol>
        <li>Dateimanager &rarr; Quelle hinzuf&uuml;gen &rarr; URL eingeben (siehe oben)</li>
        <li>Add-ons &rarr; Aus ZIP-Datei installieren &rarr; Quelle w&auml;hlen &rarr; Ordner <code>repository.amazon-waipu</code> &rarr; <code>repository.amazon-waipu-*.zip</code></li>
        <li>Add-ons &rarr; Aus Repository installieren &rarr; Amazon VOD Enhanced Repository &rarr; Video-Add-ons &rarr; Amazon VOD (Enhanced)</li>
    </ol>
    <h2>Downloads</h2>
    <ul>
$(echo -e "${DOWNLOAD_LINKS}")
    </ul>
    <h2>Verbesserungen</h2>
    <ul>
        <li>Fettes Euro-Zeichen (<strong>&euro;</strong>) als Prefix vor Kaufartikeln</li>
        <li>Label2 &bdquo;Kauf&ldquo; als zweite Textzeile in Listen-Views</li>
        <li>Zuverl&auml;ssigeres View-Setting (Kodi Bug #18576 Workaround)</li>
        <li>Auff&auml;lligere Default-Farbe f&uuml;r Bezahlartikel</li>
    </ul>
    <p><a href="https://github.com/grenzenloseSchublade/xbmc">Quellcode auf GitHub</a></p>
</body>
</html>
INDEXEOF

echo "Generiere addons.xml ..."
python3 - "${REPO_ROOT}" "${DOCS_DIR}" <<'PYEOF'
import sys, os, hashlib, xml.etree.ElementTree as ET

repo_root = sys.argv[1]
docs_dir = sys.argv[2]

addons_el = ET.Element('addons')
addon_dirs = [
    'plugin.video.amazon-waipu',
    'repository.amazon-waipu',
    'script.module.amazoncaptcha',
    'script.module.mechanicalsoup',
    'script.module.pyautogui',
]

for addon_id in addon_dirs:
    addon_xml = os.path.join(repo_root, addon_id, 'addon.xml')
    if not os.path.isfile(addon_xml):
        continue
    tree = ET.parse(addon_xml)
    addons_el.append(tree.getroot())

ET.indent(addons_el, space='  ')
addons_xml_path = os.path.join(docs_dir, 'addons.xml')
tree = ET.ElementTree(addons_el)
tree.write(addons_xml_path, encoding='UTF-8', xml_declaration=True)

with open(addons_xml_path, 'rb') as f:
    md5 = hashlib.md5(f.read()).hexdigest()
with open(addons_xml_path + '.md5', 'w') as f:
    f.write(md5)

print(f"addons.xml + addons.xml.md5 geschrieben (MD5: {md5})")
PYEOF

echo "Build abgeschlossen. Dateien in ${DOCS_DIR}:"
find "${DOCS_DIR}" -type f | sort
