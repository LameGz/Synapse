#!/usr/bin/env bash
# parse-session.sh — Analyze a Claude Code session transcript for Synapse metrics.
# Usage: bash scripts/parse-session.sh <transcript.jsonl>
#        bash scripts/parse-session.sh --summary  (summarize all sessions in .claude/)
set -euo pipefail

mode="${1:---summary}"

# ─── Parse a single transcript ────────────────────────────────────────
parse_one() {
  local transcript="$1"
  if [ ! -f "$transcript" ]; then
    echo "File not found: $transcript"
    return 1
  fi

  local reads=0
  local read_bytes=0
  local writes=0
  local edits=0
  local map_read=0

  # Extract Read/Write/Edit tool calls targeting meta/ files
  while IFS= read -r line; do
    # Count Read calls to meta/*.md
    if echo "$line" | grep -q '"tool_name"[[:space:]]*:[[:space:]]*"Read"'; then
      file_path=$(echo "$line" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
      if echo "$file_path" | grep -q 'meta/.*\.md'; then
        reads=$((reads + 1))
        if echo "$file_path" | grep -q 'MEMORY_MAP.md'; then
          map_read=$((map_read + 1))
        fi
        # Try to get byte count from tool output if present
      fi
    fi

    # Count Write/Edit to meta/ files
    if echo "$line" | grep -q '"tool_name"[[:space:]]*:[[:space:]]*"\(Write\|Edit\)"'; then
      file_path=$(echo "$line" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
      if echo "$file_path" | grep -q 'meta/.*\.md'; then
        if echo "$line" | grep -q '"Write"'; then
          writes=$((writes + 1))
        else
          edits=$((edits + 1))
        fi
      fi
    fi
  done < "$transcript"

  node_reads=$((reads - map_read))

  echo "  MEMORY_MAP reads: $map_read"
  echo "  Node file reads:  $node_reads"
  echo "  Node writes:      $writes"
  echo "  Node edits:       $edits"
  echo "  Total meta/ ops:  $((reads + writes + edits))"

  # Compare against flat-file baseline
  if [ "$node_reads" -gt 0 ]; then
    flat_est=$((node_reads + 1))  # non-Synapse would read all files eventually
    echo ""
    if [ "$node_reads" -le 5 ]; then
      echo "  ✅ Synapse protocol appears active (≤5 node files loaded)"
    elif [ "$node_reads" -le 10 ]; then
      echo "  ⚠ Possible partial flat scan ($node_reads files)"
    else
      echo "  ❌ Likely flat scan — $node_reads files loaded (Synapse protocol not followed)"
    fi
  fi
}

# ─── Summary mode: scan all transcripts ────────────────────────────────
summary() {
  local transcripts_dir="${HOME}/.claude/transcripts"
  if [ ! -d "$transcripts_dir" ]; then
    # Try alternate locations
    transcripts_dir="${HOME}/.claude/projects/*/transcripts" 2>/dev/null || true
  fi

  echo "=== Synapse Session Metrics ==="
  echo "Scanning transcripts..."
  echo ""

  local total=0
  local synapse_active=0

  for dir in "${HOME}/.claude/transcripts" "${HOME}/.claude/projects/"*"/transcripts" 2>/dev/null; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.jsonl; do
      [ -f "$f" ] || continue
      # Check if this session touched meta/ files
      if grep -q 'meta/.*\.md' "$f" 2>/dev/null; then
        total=$((total + 1))
        local meta_ops=$(grep -c 'meta/.*\.md' "$f" 2>/dev/null || echo 0)
        local map_ops=$(grep -c 'MEMORY_MAP.md' "$f" 2>/dev/null || echo 0)
        local node_ops=$((meta_ops - map_ops))

        echo "  $(basename "$f" .jsonl | cut -c1-20): $node_ops node reads, $map_ops MAP reads"
        if [ "$node_ops" -le 5 ] && [ "$map_ops" -ge 1 ]; then
          synapse_active=$((synapse_active + 1))
        fi
      fi
    done
  done

  echo ""
  echo "Synapse sessions: $synapse_active / $total"
  if [ "$total" -gt 0 ]; then
    compliance=$((synapse_active * 100 / total))
    echo "Protocol compliance rate: ${compliance}%"
    if [ "$compliance" -ge 90 ]; then
      echo "✅ Hook enforcement is working"
    else
      echo "⚠ Compliance < 90% — check hook configuration"
    fi
  fi
}

case "$mode" in
  --summary) summary ;;
  *) parse_one "$mode" ;;
esac
