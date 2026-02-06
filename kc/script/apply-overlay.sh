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

COLLISIONS=0

echo "=========================================="
echo "KC: Applying overlay"
echo "  Source: ${KC_ROOT}"
echo "  Target: ${APP_ROOT}"
echo "=========================================="

# --- Gemfile.local -----------------------------------------------------------
if [ -f "${KC_ROOT}/Gemfile.local" ]; then
  if [ -f "${APP_ROOT}/Gemfile.local" ]; then
    echo "KC: WARNING — Gemfile.local already exists at app root, appending KC gems"
    echo "" >> "${APP_ROOT}/Gemfile.local"
    cat "${KC_ROOT}/Gemfile.local" >> "${APP_ROOT}/Gemfile.local"
  else
    cp "${KC_ROOT}/Gemfile.local" "${APP_ROOT}/Gemfile.local"
  fi
  echo "KC: Installed Gemfile.local"
else
  echo "KC: No Gemfile.local found, skipping"
fi

# --- Collision detection -----------------------------------------------------
# Check for KC files that would collide with existing upstream files BEFORE
# rsyncing. This catches developer mistakes early instead of silently dropping
# files.
check_collisions() {
  local src_dir="$1"
  local target_dir="$2"
  local dir_name="$3"

  while IFS= read -r -d '' file; do
    local rel_path="${file#"${src_dir}/"}"
    local target_file="${target_dir}/${rel_path}"
    if [ -f "${target_file}" ]; then
      echo "KC: ERROR — Collision detected: ${dir_name}/${rel_path} already exists upstream"
      COLLISIONS=$((COLLISIONS + 1))
    fi
  done < <(find "${src_dir}" -type f ! -name '.gitkeep' -print0)
}

# --- Overlay directories -----------------------------------------------------
OVERLAY_DIRS="config app lib db"

for dir in ${OVERLAY_DIRS}; do
  if [ -d "${KC_ROOT}/${dir}" ]; then
    file_count=$(find "${KC_ROOT}/${dir}" -type f ! -name '.gitkeep' | wc -l)

    # Check for collisions before copying
    check_collisions "${KC_ROOT}/${dir}" "${APP_ROOT}/${dir}" "${dir}"

    rsync -rv --ignore-existing --exclude='.gitkeep' "${KC_ROOT}/${dir}/" "${APP_ROOT}/${dir}/"
    echo "KC: Overlaid ${dir}/ (${file_count} files)"
  fi
done

# --- Duplicate migration version detection ------------------------------------
# After overlay, all migrations (upstream + KC) live in db/migrate/. Check that
# no two files share the same version number prefix — Rails will refuse to boot.
DUPES=$(ls -1 "${APP_ROOT}/db/migrate/" | sed 's/_.*//' | sort | uniq -d)
if [ -n "${DUPES}" ]; then
  echo "=========================================="
  echo "KC: FATAL — Duplicate migration version(s) detected!"
  for ver in ${DUPES}; do
    echo "  Version ${ver}:"
    ls -1 "${APP_ROOT}/db/migrate/${ver}_"* 2>/dev/null | sed 's|.*/|    |'
  done
  echo "KC: Each migration must have a unique version number."
  echo "KC: Fix the duplicates above and rebuild."
  echo "=========================================="
  exit 1
fi
echo "KC: Migration version check passed (no duplicates)"

# --- Final report ------------------------------------------------------------
if [ "${COLLISIONS}" -gt 0 ]; then
  echo "=========================================="
  echo "KC: FATAL — ${COLLISIONS} file collision(s) detected!"
  echo "KC: KC files must NOT share paths with upstream Zammad files."
  echo "KC: The colliding KC files were SKIPPED (upstream versions kept)."
  echo "KC: Fix the paths above and rebuild."
  echo "=========================================="
  exit 1
fi

echo "=========================================="
echo "KC: Overlay applied successfully"
echo "=========================================="
