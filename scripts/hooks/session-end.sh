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

# ─── Step 2.5: Co-read dependency inference ──────────────────────────────
# Scan node files modified together in this session. If a pair of nodes
# has no depends_on edge but they reference each other's body content,
# suggest them as candidate dependencies for user confirmation.
if git rev-parse --git-dir >/dev/null 2>&1 && [ -d "$META_DIR" ]; then
  # Collect all node files touched this session
  all_touched=""
  if [ -n "$modified" ] && [ -n "$untracked" ]; then
    all_touched=$(printf '%s\n%s' "$modified" "$untracked")
  elif [ -n "$modified" ]; then
    all_touched="$modified"
  elif [ -n "$untracked" ]; then
    all_touched="$untracked"
  fi

  if [ -n "$all_touched" ]; then
    candidates=""
    # Convert to array, handling newlines
    while IFS= read -r f1; do
      [ -z "$f1" ] && continue
      [ ! -f "${PROJECT_ROOT}/${f1}" ] && continue
      id1=$(awk '/^---$/{c++;next} c==1 && /^id:/{print $2; exit}' "${PROJECT_ROOT}/${f1}" 2>/dev/null || true)
      deps1=$(awk '/^---$/{c++;next} c==1 && /^depends_on:/{in_dep=1; next} in_dep==1 && /^[[:space:]]*-/{d=$0; sub(/^[[:space:]]*-[[:space:]]*/,"",d); print d; next} in_dep==1 && /^[a-zA-Z#]/{exit}' "${PROJECT_ROOT}/${f1}" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
      [ -z "$id1" ] && continue

      while IFS= read -r f2; do
        [ -z "$f2" ] && continue
        [ "$f1" = "$f2" ] && continue
        [ ! -f "${PROJECT_ROOT}/${f2}" ] && continue
        id2=$(awk '/^---$/{c++;next} c==1 && /^id:/{print $2; exit}' "${PROJECT_ROOT}/${f2}" 2>/dev/null || true)
        deps2=$(awk '/^---$/{c++;next} c==1 && /^depends_on:/{in_dep=1; next} in_dep==1 && /^[[:space:]]*-/{d=$0; sub(/^[[:space:]]*-[[:space:]]*/,"",d); print d; next} in_dep==1 && /^[a-zA-Z#]/{exit}' "${PROJECT_ROOT}/${f2}" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        [ -z "$id2" ] && continue

        # Skip if edge already exists either way
        if echo "$deps1," | grep -qF "${f2}," || echo "$deps2," | grep -qF "${f1},"; then
          continue
        fi

        # Check mutual body references: does f1 mention id2, and f2 mention id1?
        body1=$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "${PROJECT_ROOT}/${f1}" 2>/dev/null || true)
        body2=$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "${PROJECT_ROOT}/${f2}" 2>/dev/null || true)

        ref1=$(echo "$body1" | grep -ciF "$id2" 2>/dev/null || echo 0)
        ref2=$(echo "$body2" | grep -ciF "$id1" 2>/dev/null || echo 0)

        if [ "$ref1" -gt 0 ] && [ "$ref2" -gt 0 ]; then
          pair_key=$(printf '%s|||%s' "$f1" "$f2")
          if [[ "$f1" < "$f2" ]]; then pair_key="$f1|||$f2"; fi
          # Avoid duplicates
          if ! echo "$candidates" | grep -qF "$pair_key"; then
            candidates="${candidates}${pair_key}
"
          fi
        fi
      done <<< "$all_touched"
    done <<< "$all_touched"

    if [ -n "$candidates" ]; then
      echo ""
      echo "🔗 Suggested Dependencies (co-read pairs without edges)"
      echo "──────────────────────────────────────────────────────"
      while IFS= read -r pair; do
        [ -z "$pair" ] && continue
        f_a="${pair%%|||*}"
        f_b="${pair##*|||}"
        id_a=$(awk '/^---$/{c++;next} c==1 && /^id:/{print $2; exit}' "${PROJECT_ROOT}/${f_a}" 2>/dev/null || true)
        id_b=$(awk '/^---$/{c++;next} c==1 && /^id:/{print $2; exit}' "${PROJECT_ROOT}/${f_b}" 2>/dev/null || true)
        echo "  $id_a ($f_a) ↔ $id_b ($f_b)"
        echo "    → Consider adding depends_on edge. Verify with: bash scripts/suggest_edges.sh"
      done <<< "$candidates"
      echo "──────────────────────────────────────────────────────"
    fi
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

# ─── Step 4: Validate reference anchors in Connection Points ────────────
# Extract <!-- @ref: path:line --> annotations and verify they still match
if [ -d "$META_DIR" ]; then
  echo ""
  echo "🔍 Checking reference anchors..."

  anchor_issues=0

  while IFS= read -r -d '' node_file; do
    [ ! -f "$node_file" ] && continue
    rel="${node_file#$PROJECT_ROOT/}"
    [[ "$rel" == *"MEMORY_MAP.md"* ]] && continue
    [[ "$rel" == *"archive"* ]] && continue

    # Extract lines with @ref anchors
    anchors=$(grep -n '<!-- @ref:' "$node_file" 2>/dev/null || true)
    [ -z "$anchors" ] && continue

    while IFS= read -r anchor_line; do
      [ -z "$anchor_line" ] && continue

      # Parse: "123:- **Endpoint**: POST /api/v1/auth/refresh  <!-- @ref: src/auth/routes.ts:45 -->"
      line_num=$(echo "$anchor_line" | cut -d: -f1)
      ref_info=$(echo "$anchor_line" | sed -n 's/.*<!-- @ref:[[:space:]]*\([^[:space:]]*\)[[:space:]]*-->.*/\1/p')
      [ -z "$ref_info" ] && continue

      # ref_info format: path:line
      ref_path=$(echo "$ref_info" | cut -d: -f1)
      ref_line=$(echo "$ref_info" | cut -d: -f2)

      # Resolve path relative to project root
      if [ "${ref_path:0:1}" != "/" ] && [ "${ref_path:0:1}" != "." ]; then
        ref_path="${PROJECT_ROOT}/${ref_path}"
      fi

      # Check file exists
      if [ ! -f "$ref_path" ]; then
        echo "  ❌ $rel:$line_num → $ref_info (file not found)"
        anchor_issues=$((anchor_issues + 1))
        continue
      fi

      # Check line exists
      total_lines=$(wc -l < "$ref_path" 2>/dev/null || echo 0)
      if [ "$ref_line" -gt "$total_lines" ] 2>/dev/null || [ "$ref_line" -lt 1 ] 2>/dev/null; then
        echo "  ❌ $rel:$line_num → $ref_info (line $ref_line out of range, file has $total_lines lines)"
        anchor_issues=$((anchor_issues + 1))
        continue
      fi

      # Extract the expected value from the node file (the line content before the anchor)
      expected_value=$(sed -n "${line_num}p" "$node_file" | sed 's/[[:space:]]*<!-- @ref:.*-->[[:space:]]*$//' | sed 's/^[^:]*:[[:space:]]*//' | xargs)

      # Extract actual value from source file (the referenced line + context)
      actual_value=$(sed -n "${ref_line}p" "$ref_path" | xargs)

      # Fuzzy match: check if key terms from expected appear in actual
      # Extract key terms: API paths, function names, etc.
      key_terms=$(echo "$expected_value" | grep -oE '(/[a-zA-Z0-9_/{}:-]+|[a-zA-Z_][a-zA-Z0-9_]*\(\)|[A-Z][A-Z0-9_]{2,})' | sort -u | tr '\n' ' ')

      match_found=1
      if [ -n "$key_terms" ]; then
        for term in $key_terms; do
          if ! echo "$actual_value" | grep -qF "$term"; then
            match_found=0
            break
          fi
        done
      fi

      if [ "$match_found" -eq 0 ]; then
        echo "  ⚠️  $rel:$line_num → $ref_info"
        echo "     Expected (node): $expected_value"
        echo "     Actual (source): $actual_value"
        anchor_issues=$((anchor_issues + 1))
      fi

    done <<< "$anchors"
  done < <(find "$META_DIR" -maxdepth 2 -name '*.md' ! -name 'MEMORY_MAP.md' -print0 2>/dev/null || true)

  if [ "$anchor_issues" -eq 0 ]; then
    echo "  ✅ All reference anchors valid."
  else
    echo ""
    echo "  $anchor_issues anchor(s) drifted. Update Connection Points or source."
  fi
fi

echo "---"

# ─── Clear read-protocol marker for next session ───────────────────────
MARKER="${PROJECT_ROOT}/.claude/.synapse_cache/.map_read"
rm -f "$MARKER" 2>/dev/null || true

exit 0
