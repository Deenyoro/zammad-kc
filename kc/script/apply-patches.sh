#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# KC Patches — apply-patches.sh
# ---------------------------------------------------------------------------
# Applies KC patches to upstream files at Docker build time.
#
# Unlike the overlay (rsync --ignore-existing) which only adds NEW files,
# patches modify EXISTING upstream files to inject KC features like BCC,
# "Send with text color", and bulk merge into the upstream frontend.
#
# Each patch is a standard unified diff generated with:
#   git diff upstream/develop HEAD -- <file> > kc/patches/<name>.patch
#
# If upstream changes a patched file, the patch will fail to apply and
# the build will fail loudly — this is intentional. To fix:
#   1. Merge upstream into develop
#   2. Regenerate the patch: git diff upstream/develop HEAD -- <file>
#   3. Save to kc/patches/
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KC_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_ROOT="$(cd "${KC_ROOT}/.." && pwd)"
PATCHES_DIR="${KC_ROOT}/patches"

if [ ! -d "${PATCHES_DIR}" ]; then
  echo "KC: No patches directory found, skipping"
  exit 0
fi

PATCH_COUNT=0
FAIL_COUNT=0

echo "=========================================="
echo "KC: Applying frontend patches"
echo "  Patches: ${PATCHES_DIR}"
echo "  Target:  ${APP_ROOT}"
echo "=========================================="

for patch_file in "${PATCHES_DIR}"/*.patch; do
  [ -f "${patch_file}" ] || continue

  patch_name=$(basename "${patch_file}")

  # Dry-run first to check if patch applies cleanly
  if patch -p1 --dry-run --directory="${APP_ROOT}" < "${patch_file}" > /dev/null 2>&1; then
    patch -p1 --directory="${APP_ROOT}" < "${patch_file}"
    echo "KC: Applied patch: ${patch_name}"
    PATCH_COUNT=$((PATCH_COUNT + 1))
  else
    echo "KC: ERROR — Patch failed to apply: ${patch_name}"
    echo "KC:   This usually means upstream changed the patched file."
    echo "KC:   Regenerate with: git diff upstream/develop HEAD -- <file>"
    patch -p1 --dry-run --directory="${APP_ROOT}" < "${patch_file}" 2>&1 || true
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

if [ "${FAIL_COUNT}" -gt 0 ]; then
  echo "=========================================="
  echo "KC: FATAL — ${FAIL_COUNT} patch(es) failed to apply!"
  echo "KC: See errors above. Upstream likely changed these files."
  echo "KC: Merge upstream, resolve conflicts, and regenerate patches."
  echo "=========================================="
  exit 1
fi

echo "=========================================="
echo "KC: All ${PATCH_COUNT} patch(es) applied successfully"
echo "=========================================="
