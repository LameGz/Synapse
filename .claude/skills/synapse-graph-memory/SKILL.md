---
name: synapse-graph-memory
description: Use when a project contains MEMORY_MAP.md or meta/*.md memory node files, when handling cross-module tasks spanning multiple domains, or when project memory is organized into domain-specific files with frontmatter dependency declarations
---

# Synapse Graph Memory

## Overview

Partitioned context loading via graph topology. Each Markdown node declares its cross-module dependencies in frontmatter (`depends_on`). Agent performs bounded BFS traversal — depth 1 (all deps), depth 2 (tag-filtered), depth 3 (explicit) — loading only the subgraph relevant to the current task. This eliminates cross-domain noise while handling real transitive dependency chains.

Three CS primitives mapped to LLM context management: inverted index (MEMORY_MAP for O(1) lookup), normalization (domain-split nodes eliminate redundancy), foreign-key references (depends_on edges enable deterministic graph traversal instead of vector similarity search).

## Quick Reference

| Action | Command / Rule |
|---|---|
| Vague status query | Read `## Status Digest` in MEMORY_MAP.md (~200 tok, 1 file) |
| Find nodes for topic | Read `MEMORY_MAP.md`, match tags/keywords |
| Load memory for task | Target node + bounded BFS deps (depth ≤ 2, width ≤ 5) |
| Create persistent module | `meta/mod_<name>.md` with type: module |
| Create feature (active) | `meta/feat_<name>.md` with type: feature, status: in-progress |
| Archive completed feature | Move to `meta/archive/`, set status: archived, rebuild index |
| Declare dependency | Add path to `depends_on` in both nodes' frontmatter |
| Multi-root task | Select top-k nodes from MAP; ≤3 all, 4-5 by recency, >5 ask user |
| Traverse context | Bounded BFS (depth ≤ 2, width ≤ 5): depth 1 all → depth 2 tag-filtered → depth 3 explicit |
| Check who depends on a module | Read `blocks` from MEMORY_MAP.md (auto-computed) |
| Assess impact before modify | Read Connection Points sections of blocking nodes only |
| Detect missing edges | Self-check node body for other-module references, verify in depends_on |
| Rebuild index + validate | Auto-run by session-end hook; manual: `scripts/generate_memory_map.sh` |
| Post-edit validation | Auto-run by post-tool-use hook; checks frontmatter + dead links |

## Trigger Patterns (MANDATORY activation)

When the user's message matches ANY of these patterns, Agent MUST execute the Retrieval Protocol before responding:

| User says... | Extract keyword | Query MEMORY_MAP for |
|---|---|---|
| "XX做得怎么样了" / "XX的状态" / "XX完成了吗" | XX | tag matching XX |
| "继续做XX" / "上次XX做到哪了" | XX | tag matching XX |
| "XX有什么问题" / "帮我看一下XX" / "关于XX..." | XX | tag matching XX |

**Keyword extraction rules:**
- Tech terms first: FastAPI → `api, backend`, React → `frontend, ui`
- Module names direct: 登录/login → `auth, login`, 支付/payment → `payment`
- Vague descriptions inferred: 前端 → `frontend`, 数据库 → `database`
- **Fallback**: If no keyword extracted AND no tag matches → go to Status Overview mode (read Status Digest only). Do NOT guess. Do NOT skip memory lookup.

## Query Routing

| Query type | Example | Mode | Reads |
|---|---|---|---|
| Vague status | "咱们做的咋样了" | **Status Digest** | MEMORY_MAP.md only (1 file, ~200 tokens) |
| Pending work | "还有什么没做完" | **Status Digest** | Same, filter open issues > 0 |
| Specific module | "登录做得怎么样了" | **Bounded BFS** | Target node + deps |
| Cross-module | "支付超时怎么处理" | **Bounded BFS + Impact** | Target node + deps + in-degree Connection Points |
| Trivial change | "登录按钮改个颜色" | **Bounded BFS (shallow)** | Target node only (deps may be unnecessary) |

## Retrieval Protocol (MANDATORY)

Execute in this exact order. Skip no step.

1. **Read MAP**: Open `MEMORY_MAP.md`.

   **Vague query** (no clear domain keyword): read `## Status Digest` section only. Answer from the digest. Token cost: ~200 tokens. Then ask user which module to drill into.

   **Specific query** (has domain keywords): scan the tag index with width bound:
   - **≤ 3 matches**: load all.
   - **4–5 matches**: load the 3 most recent by `updated` date.
   - **> 5 matches**: STOP. Tell user to narrow scope.
   - Multi-domain task: one candidate per domain (max 3 total).

2. **Read primary node(s)**: Open the candidate node(s) from Step 1.
   - Single-domain task: read 1 primary node.
   - Multi-domain or ambiguous task: read all top-k nodes (max 3).
3. **Bounded BFS (depth ≤ 2, width ≤ 5)**:
   - **Depth 1 (mandatory)**: Read files listed in the target node's `depends_on`.
     Apply width bound: if a node has > 5 `depends_on`, load only the first 5 by declaration order (most critical first).
   - **Depth 2 (conditional)**: For each depth-1 node, check its `depends_on`. Load a depth-2 node ONLY if its tags overlap with the task domain. Skip unrelated transitive dependencies.
   - **Depth 3 (explicit only)**: Load only if a depth-2 node's Connection Points explicitly names a further module as required for the current task.
   - **Stop conditions**: depth > 3 OR estimated token budget exceeds ~15% of context window.
   
   Rationale: Real DAGs have transitive chains (feat_checkout → mod_payment → mod_auth → mod_user). Rigid 1-hop misses context; unlimited traversal collapses to flat-file. Bounded BFS constrains both how deep (≤ 2) and how wide (≤ 5 per node). Combined with tag-level width bound (≤ 5 per query), worst-case memory load per task is: 5 roots × (1 + 5 deps) = 30 files. Typical load: 2–4 files.

   **If the task will MODIFY any node**, add in-degree awareness BEFORE making changes:
   - Check each to-be-modified node's `blocks` field in MEMORY_MAP.md (auto-computed as reverse of depends_on)
   - Read ONLY the `## Cross-Module Connection Points` section from each blocking node
   - Assess whether your change breaks any downstream contract before proceeding
4. **Assemble context**: Active context = all primary node(s) + BFS-loaded dependencies. Merge subgraphs if multiple roots were selected. Do NOT load files outside this merged subgraph.
5. **Execute task** using the assembled context.
6. **Update edges**: If work creates or changes cross-module relationships, add/update `depends_on` entries on ALL affected nodes.
7. **Rebuild**: Run `scripts/generate_memory_map.sh` when node structure changes (new files, deleted files, tag changes).

### 8. Session wrap (HOOK-ENFORCED)

**This step is enforced by infrastructure, not Agent memory.**

`scripts/hooks/session-end.sh` runs automatically at session end via `.claude/settings.json` Stop hook. It executes:
1. **Rebuild index**: Runs `scripts/generate_memory_map.sh`
2. **Topology validation**: Checks dead links, cycles, orphans, oversized nodes
3. **Change summary**: Outputs 📝 Memory Changes diff (git diff of meta/ files)
4. **Drift flag**: If source files were modified but no meta/ nodes were updated, emits ⚠ warning

Agent: you do NOT need to manually execute the session wrap steps. The hook does it.
If the hook output shows warnings, address them before the next session.

## Node File Specification

### Naming

- `mod_<name>.md` — persistent architecture modules (routing, state management, database schema). Never archived.
- `feat_<name>.md` — lifecycle-bound features (user login, payment integration). Move to `meta/archive/` when completed.
- Filesystem flat or max 2 levels: `meta/` and `meta/archive/`.

### Size constraint

A node must satisfy both criteria:
- **Independently understandable**: After reading it, you know the full state of that module without needing to open another file.
- **30–150 lines**: If larger, split by sub-domain (e.g., `mod_auth.md` → `mod_auth-api.md` + `mod_auth-session.md`). If smaller than 30 lines, merge with its closest dependency — a 10-line node is a leaf that should be folded into its parent.
- Script auto-warns on nodes exceeding 200 lines (grace buffer).

### Frontmatter

```yaml
---
id: feat_user-login
type: feature          # "feature" or "module"
status: in-progress    # "in-progress", "stable", or "archived"
updated: 2026-04-30
depends_on:
  - meta/mod_auth-api.md
  - meta/mod_user-table.md
blocks: []             # AUTO-COMPUTED by generate_memory_map.sh. Agent: do NOT edit.
tags: [auth, login, jwt]
---
```

### Body sections

```markdown
# [Node Title]

## Current State
[Specific, concrete details. Apply fidelity categories — exact mode for
paths/names/values, fuzzy mode for motivation/rationale.]

## Key Decisions
- [Date] Decision made — why this over alternatives

## Cross-Module Connection Points

### To mod_<name>
- **Endpoint**: METHOD /path
- **Request**: `{ field: type, ... }`
- **Response**: `{ field: type, ... }`
- **Errors**:
  - `CODE` Description
- **Constraints**: rate limits, idempotency, ordering requirements

Each connection point MUST be an interface contract, not a free-text description.
If the dependency is not API-based (shared state, file format, naming convention),
adapt the fields accordingly but preserve structure.

## Open Issues
- [Blocked on...]

## Change Log
- [YYYY-MM-DD] What changed, why, who (if multi-agent)
```

## Critical Rules

### 1. Concrete values: no summarization

The `Current State` section must preserve specific values exactly:
- `/api/v1/auth/refresh` — not "the refresh endpoint"
- `access_token_ttl: 900` — not "short-lived tokens"
- `User.email VARCHAR(255) UNIQUE NOT NULL` — not "email field exists"

This prevents summary hallucination — information loss across the compression chain: code → developer understanding → node summary → agent reading → agent's mental model.

### Fidelity categories

**Exact mode — copy verbatim, never paraphrase:**

| Category | Example |
|---|---|
| API endpoint paths | `POST /api/v1/auth/refresh` |
| Field names + types | `expires_at: TIMESTAMP NOT NULL` |
| Version numbers | `"jsonwebtoken": "^9.0.2"` |
| Config values | `TOKEN_EXPIRY=900` |
| Error codes | `{ code: 40101, message: "Token expired" }` |
| Naming conventions | `use{Feature}.tsx` |
| Boundary constraints | "password min 8 chars, must include upper/lower/digit" |

**Fuzzy mode — compressible:**
Motivation, progress status, team consensus, rationale for rejected alternatives.

**Self-check before writing:** If I remove this data point, can the Agent re-derive the correct value from description alone?
- Yes → fuzzy mode
- No → exact mode, preserve verbatim

### 2. MEMORY_MAP is read-only for Agent

`MEMORY_MAP.md` header contains `<!-- AUTO-GENERATED. DO NOT EDIT MANUALLY. -->`. Agent MUST NOT edit this file. Run `scripts/generate_memory_map.sh` to rebuild.

Rationale: Agent instruction compliance degrades in long sessions. Deterministic script output is more reliable than trusting the Agent to remember index updates. This is reliability engineering, not preference.

### 3. Edge maintenance

**depends_on (Agent managed):**
- `feat_X depends_on mod_Y` means X needs Y's information to function.
- After any work that touches cross-module boundaries, update `depends_on` on ALL affected nodes.
- Check bidirectionality: if A depends_on B and B also needs to be aware of A, add the reverse edge too.

**blocks (Script managed — Agent NEVER edits):**
- `blocks` is the reverse of `depends_on`. If A depends_on B, then B is blocked_by A.
- Computed automatically by `generate_memory_map.sh`. Agent reads blocks from MEMORY_MAP.md during the modify step, never edits the field directly.
- If blocks appears stale, run `scripts/generate_memory_map.sh` — it will recompute.

### 4. Soft dependency inference (drift detection)

Hard edges (`depends_on`) are the primary path. But they WILL drift — humans and Agents miss updates. Add a soft validation layer:

**Self-check after writing any node's `## Current State`:**
1. Scan the text for references to other modules: API paths (`/api/v1/auth/*`), table names, component imports, config keys
2. For each reference to another module's domain, verify `depends_on` contains that module
3. If a reference exists but no edge declares it, EITHER:
   - Add the edge to `depends_on`, OR
   - Flag in `## Open Issues`: `[PENDING VERIFY: depends_on mod_X? Reference to /api/v1/X but no edge declared]`

**This is NOT a replacement for hard edges.** It's a safety net. The script's topology health check catches dead links; this catches missing links.

### 5. Node lifecycle (Neat-Freak protocol)

```
active (in-progress) → stable (completed, rarely changes) → archived (moved to meta/archive/)
```

- `mod_` nodes: status cycles between `in-progress` and `stable`. Never archived.
- `feat_` nodes: archived when feature is complete and no longer referenced by any active node.
- After archiving: rebuild index. The MAP will drop archived nodes from the index but preserve file paths for historical reference.

### Cleanup checklist (run on demand or when user says "clean memory")

| Check | Condition | Action |
|---|---|---|
| Orphan nodes | `depends_on` and `blocks` both empty | Ask user: archive or reconnect? |
| Dead links | `depends_on` target file doesn't exist | Script auto-detects (see Topology Health in MAP output) |
| Bidirectional consistency | A.depends_on contains B but B.blocks doesn't contain A | Run script — auto-fixes by reversing depends_on |
| Oversized nodes | File exceeds 200 lines | Suggest splitting into sub-nodes |
| Stale nodes | `active` status but `updated` > 30 days ago | Suggest downgrade to `stable` |

## Setup

```bash
mkdir -p meta/archive scripts
curl -o scripts/generate_memory_map.sh <source>
chmod +x scripts/generate_memory_map.sh
# Pre-commit hook
echo '#!/bin/sh\nscripts/generate_memory_map.sh' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

Run `scripts/generate_memory_map.sh` once after setup to create the initial `MEMORY_MAP.md`.

## Common Mistakes

| Mistake | Why wrong | Fix |
|---|---|---|
| Reading all meta/*.md "to be safe" | Loads irrelevant context, defeats the system | Trust the graph. MAP + 1-hop only. |
| "the auth endpoints" instead of `/api/v1/auth/refresh` | Agent later works with a fuzzy signal, hallucinates details | Write paths/values verbatim |
| Updating `depends_on` on one side only | Graph becomes asymmetric, other direction is invisible | Check ALL affected nodes after cross-module work |
| Manual edit of MEMORY_MAP.md | Drift between MAP and actual files | Run `scripts/generate_memory_map.sh` |
| Deep directory nesting (meta/frontend/ui/components/...) | Defeats flat-file grep-ability | Max 2 levels |
| Creating a node per source file | Node count explodes, MAP becomes expensive to load | One node per functional module |
| Ignoring hook output warnings | Hooks enforce checks but Agent must act on warnings | Read hook output before next task; fix flagged issues |
| "Key data preserved" without specifics | Summary hallucination: Agent thinks it knows but lacks precision | Use fidelity category table, verbatim for exact-mode data |
| Manually editing `blocks` field | Will be overwritten by next script run; also breaks the single-source-of-truth | Run script instead — it auto-computes blocks from depends_on |
| Modifying a module without checking in-degree | Downstream consumers silently break | Always execute modify-protocol: check blocks in MAP, read Connection Points of dependents |
| Assuming flat 1-hop is always enough | Transitive chains (A→B→C→D) silently lose context at depth 3+ | Trust bounded BFS — constrains both depth (≤ 2) and width (≤ 5) |
| Free-text Connection Points | "Needs auth API" is useless for impact assessment | Use schema: Endpoint, Request, Response, Errors |
| Node too large (>150 lines) | Becomes its own memory collapse — all sub-topics jumbled | Split by sub-domain |
| Node too small (<30 lines) | Graph clutter, adds traversal cost without information gain | Merge with closest dependency |

## Supporting Files

- `scripts/generate_memory_map.sh` — Scans `meta/*.md`, extracts frontmatter, builds tag-indexed MEMORY_MAP.md
- `template.md` — Node templates: copy the relevant section when creating mod or feat nodes
