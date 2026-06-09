#!/bin/bash
set -uo pipefail

# ---------------------------------------------------------------------------
# KC Sync-Safety Check — check-sync-safety.sh
# ---------------------------------------------------------------------------
# Verifies that pulling the latest upstream (the GitHub "Sync fork" button)
# will merge WITHOUT conflicts, and that KC's footprint outside kc/ stays
# minimal and merge-safe.
#
# Why this exists: the Sync fork button performs `git merge upstream/develop`
# and CANNOT resolve conflicts — it just fails. A conflict happens only when
# the fork has modified the SAME lines of the SAME upstream-tracked file that
# upstream later changed. KC avoids this by keeping all custom code in NEW
# files under kc/ (which upstream never touches). The few unavoidable edits
# outside kc/ (Dockerfile, script/build/cleanup.sh) are kept purely ADDITIVE
# so they never share a line with upstream.
#
# This script:
#   1. Simulates the merge (git merge-tree) → definitive conflict answer.
#   2. Lists KC's complete out-of-kc/ footprint.
#   3. Fails if any upstream file outside the allowlist is modified, or if an
#      allowlisted file deletes/!changes an upstream line (i.e. is not purely
#      additive and therefore could conflict).
#
# Usage:
#   kc/script/check-sync-safety.sh            # uses upstream/develop
#   kc/script/check-sync-safety.sh --fetch    # git fetch upstream first
#   UPSTREAM_REMOTE=upstream UPSTREAM_BRANCH=develop kc/script/check-sync-safety.sh
#
# Exit codes: 0 = safe to sync, 1 = conflict/risk detected, 2 = setup error.
# ---------------------------------------------------------------------------

UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-develop}"
UPSTREAM_REF="${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH}"

# Upstream files KC is sanctioned to modify (see kc/CLAUDE.md). These are
# verified to be ADDITIVE-ONLY below — that is the actual safety guarantee,
# not the allowlist membership itself.
ALLOWLIST=("Dockerfile" "script/build/cleanup.sh")

FETCH=0
for arg in "$@"; do
  case "$arg" in
    --fetch) FETCH=1 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

cd "$(git rev-parse --show-toplevel)" || { echo "Not in a git repository." >&2; exit 2; }

if [ "$FETCH" -eq 1 ]; then
  echo "Fetching ${UPSTREAM_REMOTE}…"
  git fetch "${UPSTREAM_REMOTE}" --prune || { echo "git fetch failed." >&2; exit 2; }
fi

if ! git rev-parse --verify --quiet "${UPSTREAM_REF}" >/dev/null; then
  echo "ERROR: ${UPSTREAM_REF} not found." >&2
  echo "Add the upstream remote, e.g.:" >&2
  echo "  git remote add upstream https://github.com/zammad/zammad.git && git fetch upstream" >&2
  exit 2
fi

MB="$(git merge-base "${UPSTREAM_REF}" HEAD)" || { echo "No merge-base with ${UPSTREAM_REF}." >&2; exit 2; }

echo "=========================================="
echo "KC Sync-Safety Check"
echo "  HEAD:      $(git rev-parse --short HEAD)"
echo "  Upstream:  ${UPSTREAM_REF} ($(git rev-parse --short "${UPSTREAM_REF}"))"
echo "  Behind:    $(git rev-list --count HEAD.."${UPSTREAM_REF}") commit(s)"
echo "=========================================="

FAIL=0

# --- 1. Simulate the actual merge --------------------------------------------
# merge-tree operates on commits, so this reflects the last COMMIT (HEAD), not
# uncommitted working-tree changes. Commit, then re-run, for the final word.
echo
echo "[1/3] Simulating merge of ${UPSTREAM_REF} into committed HEAD…"
if MT_OUT="$(git merge-tree --write-tree HEAD "${UPSTREAM_REF}" 2>&1)"; then
  echo "  ✓ Clean merge — the Sync fork button will succeed."
else
  echo "  ✗ MERGE CONFLICT — the Sync fork button will FAIL."
  echo "${MT_OUT}" | grep -aiE 'conflict' | sed 's/^/      /'
  FAIL=1
fi

# --- 2. Out-of-kc/ footprint (working tree) ----------------------------------
# A file is only a CONFLICT RISK if KC's version diverges from upstream in a way
# upstream might also touch. We measure KC's changes against the merge-base
# (isolates KC's own edits from upstream being ahead) and treat a file that
# already matches upstream's tip as merge-safe regardless.
echo
echo "[2/3] KC's footprint outside kc/ (working tree — the only thing that can ever conflict)…"
in_allowlist() {
  local f="$1"
  for a in "${ALLOWLIST[@]}"; do [ "$f" = "$a" ] && return 0; done
  return 1
}

while IFS= read -r f; do
  [ -z "$f" ] && continue
  [[ "$f" == kc/* ]] && continue

  if ! git cat-file -e "${MB}:$f" 2>/dev/null && ! git cat-file -e "${UPSTREAM_REF}:$f" 2>/dev/null; then
    echo "  • ${f} — new file (no conflict unless upstream later adds the same path)"
    continue
  fi

  # File exists upstream. If KC's working-tree copy already matches upstream's
  # tip, the merge is a no-op for it — perfectly safe.
  if git diff --quiet "${UPSTREAM_REF}" -- "$f" 2>/dev/null; then
    echo "  ✓ ${f} — matches upstream tip (merge-safe)"
    continue
  fi

  # KC diverges from upstream on this file. Count upstream lines KC removed,
  # measured against the merge-base so upstream-ahead changes don't count.
  dels="$(git diff "${MB}" -- "$f" | grep -E '^-' | grep -vc '^---')"
  if in_allowlist "$f"; then
    if [ "$dels" -eq 0 ]; then
      echo "  ✓ ${f} — sanctioned, additive-only (0 upstream lines changed)"
    else
      echo "  ✗ ${f} — sanctioned BUT changes ${dels} upstream line(s); make it additive-only"
      FAIL=1
    fi
  else
    echo "  ✗ ${f} — UNSANCTIONED upstream-file modification (move it into kc/)"
    FAIL=1
  fi
done < <(git diff "${MB}" --name-only)

# --- 3. Verdict --------------------------------------------------------------
echo
echo "[3/3] Verdict"
echo "=========================================="
if [ "$FAIL" -eq 0 ]; then
  echo "✓ SAFE — sync fork will merge cleanly and KC's footprint is merge-safe."
else
  echo "✗ RISK — see the ✗ lines above. Sync may fail or drift toward failure."
fi
echo "=========================================="
exit "$FAIL"
