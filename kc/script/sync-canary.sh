#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# KC Sync Canary — sync-canary.sh
# ---------------------------------------------------------------------------
# Answers ONE question ahead of time: "if I hit the GitHub Sync fork button
# right now, will everything stay green?"
#
# It simulates the next sync in a throwaway worktree:
#   1. Merge the CURRENT upstream branch (conflict = the Sync button itself
#      would fail).
#   2. On the merged tree, verify every kc/patches/*.patch still lands —
#      exact, via git apply --3way, or via fuzzy patch(1) (the same ladder
#      the CI self-heal uses). Only a true conflict is reported.
#   3. Verify no upstream file appeared at a path the kc/ overlay owns
#      (rsync --ignore-existing would silently skip ours).
#
# Exit 0 = next sync is safe (drift, if any, will self-heal).
# Exit 1 = next sync needs a human; findings on stdout.
#
# Env: UPSTREAM_URL (default zammad), UPSTREAM_BRANCH (default develop).
# Needs full history for --3way (blobless partial clone is fine).
# ---------------------------------------------------------------------------

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/zammad/zammad.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-develop}"
PREFIX="KC"
OVERLAY_DIR="kc"

ROOT="$(git rev-parse --show-toplevel)"
cd "${ROOT}"

echo "${PREFIX}: Fetching ${UPSTREAM_URL} ${UPSTREAM_BRANCH}…"
git fetch --no-tags "${UPSTREAM_URL}" "${UPSTREAM_BRANCH}"
UPSTREAM_SHA="$(git rev-parse FETCH_HEAD)"

if git merge-base --is-ancestor "${UPSTREAM_SHA}" HEAD; then
  echo "${PREFIX}: Fork already contains upstream ${UPSTREAM_SHA:0:10} — nothing new to sync."
  exit 0
fi

WT="$(mktemp -d)"
cleanup() { cd "${ROOT}"; git worktree remove --force "${WT}" > /dev/null 2>&1 || true; }
trap cleanup EXIT

git worktree add --detach "${WT}" HEAD > /dev/null 2>&1
cd "${WT}"

PROBLEMS=()

echo "${PREFIX}: Simulating merge of upstream ${UPSTREAM_SHA:0:10}…"
if git -c user.name=canary -c user.email=canary@localhost \
     merge --no-ff --no-verify -m canary "${UPSTREAM_SHA}" > /dev/null 2>&1; then
  echo "${PREFIX}: ✓ Merge is clean — the Sync fork button will work."
else
  mapfile -t conflicted < <(git diff --name-only --diff-filter=U)
  PROBLEMS+=("MERGE CONFLICT — the Sync fork button itself will FAIL. Conflicted files: ${conflicted[*]}")
  git merge --abort > /dev/null 2>&1 || true
fi

if [ "${#PROBLEMS[@]}" -eq 0 ]; then
  echo "${PREFIX}: Testing patches against the merged tree…"
  shopt -s nullglob
  for patch_file in "${OVERLAY_DIR}"/patches/*.patch; do
    patch_name=$(basename "${patch_file}")
    mapfile -t files < <(git apply --numstat "${patch_file}" | cut -f3)

    if git apply --check "${patch_file}" > /dev/null 2>&1; then
      echo "${PREFIX}: ✓ exact:          ${patch_name}"
    elif git apply --3way "${patch_file}" > /dev/null 2>&1; then
      git checkout HEAD -- "${files[@]}"
      echo "${PREFIX}: ✓ will self-heal: ${patch_name} (3-way)"
    else
      git checkout HEAD -- "${files[@]}" 2>/dev/null || true
      if command -v patch > /dev/null 2>&1 \
          && patch -p1 --dry-run --force < "${patch_file}" > /dev/null 2>&1; then
        echo "${PREFIX}: ✓ will self-heal: ${patch_name} (fuzzy)"
      else
        PROBLEMS+=("PATCH CONFLICT: ${patch_name} — upstream rewrote the patched lines in: ${files[*]}. Re-implement the change on the merged tree and regenerate the patch.")
      fi
    fi
  done

  echo "${PREFIX}: Checking overlay paths for new upstream collisions…"
  while IFS= read -r -d '' overlay_file; do
    rel="${overlay_file#"${OVERLAY_DIR}"/}"
    for prefix_dir in app lib config db; do
      case "${rel}" in
        "${prefix_dir}"/*)
          if [ -e "./${rel}" ]; then
            PROBLEMS+=("OVERLAY COLLISION: upstream now ships ${rel} — the overlay copy would be silently skipped. Rename the KC file or convert to a patch.")
          fi
          ;;
      esac
    done
  done < <(find "${OVERLAY_DIR}/app" "${OVERLAY_DIR}/lib" "${OVERLAY_DIR}/config" "${OVERLAY_DIR}/db" -type f -print0 2>/dev/null)
fi

echo "=========================================="
if [ "${#PROBLEMS[@]}" -eq 0 ]; then
  echo "${PREFIX}: ✓ CANARY PASS — the next Sync fork will merge and build green."
  exit 0
fi

echo "${PREFIX}: ✗ CANARY FAIL — the next Sync fork needs manual attention:"
for problem in "${PROBLEMS[@]}"; do
  echo "  • ${problem}"
done
echo "=========================================="
exit 1
