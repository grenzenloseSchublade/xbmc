#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCS_DIR="${REPO_ROOT}/docs"

ADDONS=(
    "plugin.video.amazon-waipu"
    "repository.amazon-waipu"
)

rm -rf "${DOCS_DIR}"
mkdir -p "${DOCS_DIR}"
touch "${DOCS_DIR}/.nojekyll"

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
done

echo "Generiere addons.xml ..."
python3 - "${REPO_ROOT}" "${DOCS_DIR}" <<'PYEOF'
import sys, os, hashlib, xml.etree.ElementTree as ET

repo_root = sys.argv[1]
docs_dir = sys.argv[2]

addons_el = ET.Element('addons')
addon_dirs = [
    'plugin.video.amazon-waipu',
    'repository.amazon-waipu',
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
