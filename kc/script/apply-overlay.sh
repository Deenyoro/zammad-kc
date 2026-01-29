#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# KC Overlay — apply-overlay.sh
# ---------------------------------------------------------------------------
# Copies custom KC code into the Zammad app tree at Docker build time.
# Uses rsync --ignore-existing so upstream files are NEVER overwritten.
#
# Called from the Dockerfile after "COPY . ." and before asset compilation.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KC_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_ROOT="$(cd "${KC_ROOT}/.." && pwd)"

echo "=========================================="
echo "KC: Applying overlay"
echo "  Source: ${KC_ROOT}"
echo "  Target: ${APP_ROOT}"
echo "=========================================="

# --- Gemfile.local -----------------------------------------------------------
if [ -f "${KC_ROOT}/Gemfile.local" ]; then
  cp "${KC_ROOT}/Gemfile.local" "${APP_ROOT}/Gemfile.local"
  echo "KC: Copied Gemfile.local to app root"
else
  echo "KC: No Gemfile.local found, skipping"
fi

# --- Overlay directories -----------------------------------------------------
# rsync --ignore-existing ensures we only ADD new files; upstream files remain
# untouched even if a KC file has the same path (which should never happen by
# convention, but this is a safety net).
OVERLAY_DIRS="config app lib db"

for dir in ${OVERLAY_DIRS}; do
  if [ -d "${KC_ROOT}/${dir}" ]; then
    file_count=$(find "${KC_ROOT}/${dir}" -type f ! -name '.gitkeep' | wc -l)
    rsync -rv --ignore-existing --exclude='.gitkeep' "${KC_ROOT}/${dir}/" "${APP_ROOT}/${dir}/"
    echo "KC: Overlaid ${dir}/ (${file_count} files)"
  fi
done

echo "=========================================="
echo "KC: Overlay applied successfully"
echo "=========================================="
