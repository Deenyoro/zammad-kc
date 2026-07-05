#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# KC Self-Healing Patches — heal-patches.sh
# ---------------------------------------------------------------------------
# Runs in CI (with a real git checkout) BEFORE the Docker build. Guarantees
# the unified diffs in kc/patches/ apply EXACTLY against the current tree —
# without manual intervention — even after upstream refactors shift the
# surrounding code:
#
#   1. `git apply --check`  → patch is exact, nothing to do.
#   2. `git apply --3way`   → re-anchor the change with git's 3-way merge
#      (survives context shifts, offsets, and nearby upstream edits that
#      make plain `patch` reject). The patch file is then REGENERATED from
#      the merged result, so drift never accumulates, and the refreshed
#      patch is committed & pushed back to the repo (set HEAL_PUSH_BRANCH).
#   3. If even the 3-way merge conflicts, upstream rewrote the very lines
#      the patch changes. No automatic answer can be correct — fail loudly.
#
# The working tree is left CLEAN apart from regenerated kc/patches/*.patch
# files: the Docker build still applies the patches itself, exactly as
# before. This script only guarantees they will apply.
#
# Requirements: git history for the pre-image blobs (actions/checkout with
# fetch-depth: 0). Blobless partial clones (filter=blob:none) are fine —
# git lazily fetches the blobs that `--3way` needs.
#
# Env:
#   HEAL_PUSH_BRANCH  branch to push refreshed patches to (e.g. develop).
#                     Empty/unset = heal for this build only, do not push.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KC_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_ROOT="$(cd "${KC_ROOT}/.." && pwd)"
PATCHES_DIR="${KC_ROOT}/patches"

cd "${APP_ROOT}"

if [ ! -d "${PATCHES_DIR}" ]; then
  echo "KC: No patches directory found, skipping"
  exit 0
fi

if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "KC: FATAL — heal-patches.sh needs a git checkout (run it in CI, not in Docker)"
  exit 2
fi

HEALED=()

echo "=========================================="
echo "KC: Self-healing patch check"
echo "  Patches: ${PATCHES_DIR}"
echo "=========================================="

shopt -s nullglob
for patch_file in "${PATCHES_DIR}"/*.patch; do
  patch_name=$(basename "${patch_file}")

  if git apply --check "${patch_file}" > /dev/null 2>&1; then
    echo "KC: exact:  ${patch_name}"
    continue
  fi

  echo "KC: drifted — re-anchoring with 3-way merge: ${patch_name}"
  # All files this patch touches (tab-separated numstat, path is field 3).
  mapfile -t files < <(git apply --numstat "${patch_file}" | cut -f3)

  applied=""
  if git apply --3way "${patch_file}" > /dev/null 2>&1; then
    applied="3-way merge"
  else
    # Clear any conflict leftovers from the failed 3-way attempt.
    git checkout HEAD -- "${files[@]}" 2>/dev/null || true
    # Last resort: classic patch(1) with fuzz — the same leniency the Docker
    # build used to rely on. If it lands, we regenerate an exact patch from
    # the result, so the fuzz never accumulates.
    if command -v patch > /dev/null 2>&1 \
        && patch -p1 --dry-run --force < "${patch_file}" > /dev/null 2>&1; then
      patch -p1 --force --no-backup-if-mismatch < "${patch_file}" > /dev/null
      applied="fuzzy patch(1)"
    fi
  fi

  if [ -n "${applied}" ]; then
    git diff HEAD -- "${files[@]}" > "${patch_file}"
    git checkout HEAD -- "${files[@]}"
    if ! git apply --check "${patch_file}" > /dev/null 2>&1; then
      echo "KC: FATAL — regenerated ${patch_name} is still not exact (bug?)"
      exit 1
    fi
    echo "KC: healed (${applied}): ${patch_name}"
    HEALED+=("${patch_name}")
  else
    echo "=========================================="
    echo "KC: FATAL — CONFLICT in ${patch_name}"
    echo "KC: Upstream rewrote the exact lines this patch changes; neither a"
    echo "KC: 3-way merge nor a fuzzy apply can land it. A human must"
    echo "KC: re-implement the change. See kc/CLAUDE.md."
    echo "KC: Files: ${files[*]}"
    echo "=========================================="
    exit 1
  fi
done

if [ "${#HEALED[@]}" -eq 0 ]; then
  echo "KC: All patches are exact — nothing to heal."
  exit 0
fi

echo "KC: Healed ${#HEALED[@]} patch(es): ${HEALED[*]}"

if [ -n "${HEAL_PUSH_BRANCH:-}" ]; then
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git add "${PATCHES_DIR}"
  git commit -m "chore(kc): auto-refresh drifted patches after upstream sync"
  # Best effort: a failed push (race, protection) must not fail the build —
  # the patches are already healed in this workspace and the next run will
  # simply heal again.
  git push origin "HEAD:refs/heads/${HEAL_PUSH_BRANCH}" \
    || echo "KC: WARN — could not push refreshed patches (healed for this build only)"
else
  echo "KC: HEAL_PUSH_BRANCH not set — healed for this build only."
fi
