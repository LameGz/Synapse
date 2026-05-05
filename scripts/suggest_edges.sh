#!/usr/bin/env bash
# suggest_edges.sh — auto-detect potential dependency edges from node content
# Scans Connection Points and cross-references between nodes.
#
# Modes:
#   default (no args)     — Suggest NEW edges from content analysis
#   --check-drift         — Validate EXISTING edges for staleness
#
# Agent's job shifts from "inventing edges" to "confirming/rejecting suggestions".
set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
  echo "Error: requires bash 4+ (current: $BASH_VERSION)" >&2
  echo "macOS: brew install bash; ensure /opt/homebrew/bin or /usr/local/bin in PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/..")"
META_DIR="${PROJECT_ROOT}/meta"

MODE="suggest"
if [ "${1:-}" = "--check-drift" ]; then
  MODE="drift"
fi

if [ ! -d "$META_DIR" ]; then
  echo "No meta/ directory found."
  exit 0
fi

# ─── Extract connection point identifiers from a node ──────────────────
# Returns: one identifier per line, format: "type|value"
# Each grep is suffixed with `|| true` because no-match returns 1 and would
# trip `set -e` in the caller (the function's exit code is the last command's).
extract_connection_points() {
  local file="$1"
  local body
  body=$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "$file" 2>/dev/null || true)

  # API endpoints
  echo "$body" | grep -oE '(GET|POST|PUT|DELETE|PATCH)[[:space:]]+(/[a-zA-Z0-9_/{}:-]+)' 2>/dev/null | sed 's/^/api|/' || true

  # Table names
  echo "$body" | sed -n 's/.*\*\*[Tt]able\*\*:[[:space:]]*\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/p' | sed 's/^/table|/' || true

  # Shared state references
  echo "$body" | grep -oi 'shared state via [a-zA-Z_][a-zA-Z0-9_]*' 2>/dev/null | sed 's/.*via //I' | sed 's/^/state|/' || true

  return 0
}

# ─── Extract a YAML list (inline or multi-line) into space-separated items ─
extract_list_items() {
  local key="$1" fm="$2"
  # Inline: key: [a, b]
  local inline
  inline=$(echo "$fm" | sed -n "/^${key}:[[:space:]]*\[/s/^${key}:[[:space:]]*//p" | tr -d '[]"')
  if [ -n "$(echo "$inline" | xargs)" ]; then
    echo "$inline" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d'
    return
  fi
  # Multi-line: key:\n  - a\n  - b
  echo "$fm" | awk -v k="$key" '
    $0 ~ ("^" k ":[[:space:]]*$") { in_list=1; next }
    in_list && /^[[:space:]]*-[[:space:]]+/ {
      item = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", item)
      gsub(/["'\''\],]/, "", item)
      sub(/[[:space:]]+$/, "", item)
      if (item != "") print item
      next
    }
    in_list && /^[[:space:]]*$/ { next }
    in_list && /^[a-zA-Z]/ { in_list=0 }
  '
}

# ─── Collect identifiers and tags for every node ───────────────────────
# Populates global arrays NODE_IDS and NODE_TAGS, used by both suggest and drift modes.
collect_node_metadata() {
  declare -gA NODE_IDS      # rel_path -> newline-separated "type|value"
  declare -gA NODE_TAGS     # rel_path -> tags

  local file rel ids fm tags
  while IFS= read -r -d '' file; do
    rel="${file#$PROJECT_ROOT/}"
    ids=$(extract_connection_points "$file")
    if [ -n "$ids" ]; then
      NODE_IDS["$rel"]="$ids"
    fi

    fm=$(awk '/^---$/ {c++; next} c==1' "$file" 2>/dev/null || true)
    tags=$(extract_list_items "tags" "$fm" | tr '\n' ' ' | xargs)
    NODE_TAGS["$rel"]="$tags"
  done < <(find "$META_DIR" -maxdepth 2 -name '*.md' ! -name 'MEMORY_MAP.md' -print0 2>/dev/null || true)
}

# ─── Suggest mode: propose new edges from content cross-references ─────
suggest_edges() {
  echo "💡 Synapse Edge Suggestions"
  echo "   (Agent: review each suggestion, add confirmed ones to depends_on)"
  echo ""

  local suggestions=0
  local rel_a rel_b ids_a type_a value_a fm_b deps_b id_a id_b tags_b

  for rel_a in "${!NODE_IDS[@]}"; do
    ids_a="${NODE_IDS[$rel_a]}"

    while IFS='|' read -r type_a value_a; do
      [ -z "$type_a" ] && continue
      [ -z "$value_a" ] && continue

      for rel_b in "${!NODE_IDS[@]}"; do
        [ "$rel_a" = "$rel_b" ] && continue

        if echo "${NODE_IDS[$rel_b]}" | grep -qF "$value_a"; then
          fm_b=$(awk '/^---$/ {c++; next} c==1' "${PROJECT_ROOT}/${rel_b}" 2>/dev/null || true)
          deps_b=$(echo "$fm_b" | sed -n 's/^depends_on:[[:space:]]*//p' | tr -d '[]"' | tr ',' '\n' | xargs)

          if ! echo "$deps_b" | grep -qF "$rel_a"; then
            id_a=$(basename "$rel_a" .md)
            id_b=$(basename "$rel_b" .md)
            tags_b="${NODE_TAGS[$rel_b]:-}"

            echo "💡 Suggested edge: $id_b depends_on $id_a"
            echo "   Reason: $id_b's Connection Points reference $value_a ($type_a)"
            [ -n "$tags_b" ] && echo "   Tags: $tags_b"
            echo ""
            suggestions=$((suggestions + 1))
          fi
        fi
      done
    done <<< "$ids_a"
  done

  echo ""
  echo "── Tag-based cross-references (weaker signal, review carefully) ──"
  echo ""

  local tags_a tag
  for rel_a in "${!NODE_TAGS[@]}"; do
    tags_a="${NODE_TAGS[$rel_a]}"
    [ -z "$tags_a" ] && continue

    IFS=' ' read -ra TAGS_A <<< "$tags_a"
    for tag in "${TAGS_A[@]}"; do
      tag=$(echo "$tag" | xargs)
      [ -z "$tag" ] && continue
      [ ${#tag} -lt 4 ] && continue  # skip short tags (too generic)

      for rel_b in "${!NODE_TAGS[@]}"; do
        [ "$rel_a" = "$rel_b" ] && continue

        if echo "${NODE_TAGS[$rel_b]}" | grep -qiw "$tag"; then
          fm_b=$(awk '/^---$/ {c++; next} c==1' "${PROJECT_ROOT}/${rel_b}" 2>/dev/null || true)
          deps_b=$(echo "$fm_b" | sed -n 's/^depends_on:[[:space:]]*//p' | tr -d '[]"' | tr ',' '\n' | xargs)

          if ! echo "$deps_b" | grep -qF "$rel_a"; then
            id_a=$(basename "$rel_a" .md)
            id_b=$(basename "$rel_b" .md)

            echo "💡 Suggested edge: $id_b depends_on $id_a"
            echo "   Reason: shared tag '$tag' (weak signal — confirm manually)"
            echo ""
            suggestions=$((suggestions + 1))
          fi
        fi
      done
    done
  done

  echo "────────────────────────────────────────────────────────────"
  echo "Total suggestions: $suggestions"
}

# ─── Drift mode: validate existing edges for staleness ─────────────────
check_drift() {
  echo "🔄 Synapse Edge Drift Check"
  echo "   Validating existing depends_on edges against current node content."
  echo "   (An edge is 'stale' if the source node no longer references"
  echo "    any Connection Point identifier from the target node.)"
  echo ""

  local drift_count=0
  local checked=0
  local node_file rel fm deps src_body src_id dep target_path target_ids
  local still_referenced type value

  while IFS= read -r -d '' node_file; do
    [ ! -f "$node_file" ] && continue
    rel="${node_file#$PROJECT_ROOT/}"

    [[ "$rel" == *"MEMORY_MAP.md"* ]] && continue
    [[ "$rel" == *"archive"* ]] && continue

    fm=$(awk '/^---$/ {c++; next} c==1' "$node_file" 2>/dev/null || true)
    deps=$(echo "$fm" | sed -n 's/^depends_on:[[:space:]]*//p' | tr -d '[]"' | tr ',' '\n' | xargs)

    [ -z "$deps" ] && continue

    src_body=$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "$node_file" 2>/dev/null || true)
    src_id=$(echo "$fm" | sed -n 's/^id:[[:space:]]*//p' | tr -d '"' | xargs)

    IFS=' ' read -ra DEP_ARR <<< "$deps"
    for dep in "${DEP_ARR[@]}"; do
      [ -z "$dep" ] && continue
      checked=$((checked + 1))

      target_path="${PROJECT_ROOT}/${dep}"
      if [ ! -f "$target_path" ]; then
        echo "⚠️  DEAD LINK: $src_id → $dep (file not found)"
        drift_count=$((drift_count + 1))
        continue
      fi

      target_ids=$(extract_connection_points "$target_path")

      if [ -z "$target_ids" ]; then
        continue
      fi

      still_referenced=0
      while IFS='|' read -r type value; do
        [ -z "$value" ] && continue
        if echo "$src_body" | grep -qF "$value"; then
          still_referenced=1
          break
        fi
      done <<< "$target_ids"

      if [ "$still_referenced" -eq 0 ]; then
        echo "🚨 STALE EDGE: $src_id depends_on $dep"
        echo "   Reason: Source node body no longer references any identifier"
        echo "   from target's Connection Points."
        echo "   Target identifiers:"
        while IFS='|' read -r type value; do
          [ -z "$value" ] && continue
          echo "     - $value ($type)"
        done <<< "$target_ids"
        echo "   Recommendation:"
        echo "     1. Verify if the dependency still exists (check imports, API calls)"
        echo "     2. If still valid: update Connection Points in source node"
        echo "     3. If no longer valid: remove from depends_on and rebuild MAP"
        echo ""
        drift_count=$((drift_count + 1))
      fi
    done
  done < <(find "$META_DIR" -maxdepth 2 -name '*.md' ! -name 'MEMORY_MAP.md' -print0 2>/dev/null || true)

  echo "────────────────────────────────────────────────────────────"
  echo "Checked $checked edges, found $drift_count stale/dead edge(s)."
  if [ "$drift_count" -eq 0 ]; then
    echo "✅ All declared edges still reference their targets."
  else
    echo "⚠️  Review each stale edge. Stale edges break BFS traversal —"
    echo "   downstream context silently disappears when edges are wrong."
  fi
}

# ─── Main dispatch ────────────────────────────────────────────────────
collect_node_metadata

if [ "$MODE" = "drift" ]; then
  check_drift
else
  suggest_edges
fi
