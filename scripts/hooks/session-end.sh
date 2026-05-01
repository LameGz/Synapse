#!/usr/bin/env bash
# SessionEnd hook: rebuilds MEMORY_MAP, validates topology, outputs change summary.
# Runs automatically at session end — Agent does NOT need to remember.
set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-$PWD}"
META_DIR="${PROJECT_ROOT}/meta"

# ─── Step 1: Rebuild index + validate topology ────────────────────────
echo "---"
echo "🔍 Synapse Session End — Running memory integrity checks..."

if [ -f "${PROJECT_ROOT}/scripts/generate_memory_map.sh" ]; then
  bash "${PROJECT_ROOT}/scripts/generate_memory_map.sh" 2>&1
else
  echo "⚠ generate_memory_map.sh not found at scripts/generate_memory_map.sh"
fi

# ─── Step 2: Scan for nodes modified in this session ──────────────────
# Compare git diff to find changed meta/ files
if git rev-parse --git-dir >/dev/null 2>&1; then
  modified=$(git diff --name-only HEAD -- meta/ 2>/dev/null || true)
  untracked=$(git ls-files --others --exclude-standard -- meta/ 2>/dev/null || true)

  if [ -n "$modified" ] || [ -n "$untracked" ]; then
    echo ""
    echo "📝 Memory Changes"
    echo "─────────────────"
    if [ -n "$modified" ]; then
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        echo "Modified: $f"
      done <<< "$modified"
    fi
    if [ -n "$untracked" ]; then
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        echo "New: $f"
      done <<< "$untracked"
    fi
    echo "─────────────────"
    echo "Changes committed to memory system. Next session will load automatically."
  fi
fi

# ─── Step 3: Soft-check for source→memory drift ───────────────────────
# Flag: if source files were modified but corresponding meta/ nodes weren't updated
# (Only runs if git is available and there are source changes)
if git rev-parse --git-dir >/dev/null 2>&1 && [ -d "$META_DIR" ]; then
  src_changed=$(git diff --name-only HEAD -- '*.ts' '*.tsx' '*.js' '*.py' '*.go' '*.rs' 2>/dev/null | head -20 || true)
  meta_changed=$(git diff --name-only HEAD -- meta/ 2>/dev/null || true)

  if [ -n "$src_changed" ] && [ -z "$meta_changed" ]; then
    echo ""
    echo "⚠ Source files modified but no meta/ nodes updated."
    echo "  If these changes affect cross-module contracts, update the relevant node files."
    echo "  Changed source files:"
    echo "$src_changed" | while IFS= read -r f; do
      [ -z "$f" ] && continue
      echo "    - $f"
    done
  fi
fi

echo "---"

exit 0
