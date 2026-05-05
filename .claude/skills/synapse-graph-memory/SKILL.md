---
name: synapse-graph-memory
description: Use when a project contains MEMORY_MAP.md or meta/*.md memory node files, when handling cross-module tasks spanning multiple domains, or when project memory is organized into domain-specific files with frontmatter dependency declarations
---

# Synapse Graph Memory

## Overview

Partitioned context loading via graph topology with **progressive disclosure** (inspired by Claude-Mem). Each Markdown node declares its cross-module dependencies in frontmatter (`depends_on`) and a one-line `summary` for rapid triage. Agent performs three-layer retrieval:

- **Layer 1**: Read MEMORY_MAP summaries (~50-100 tok/node) — triage without commitment
- **Layer 2**: Read full target node(s) — load only after confirming relevance
- **Layer 3**: Bounded BFS deps (depth ≤ 2, width ≤ 5) — expand only when necessary

This sharply limits cross-domain noise while still surfacing the transitive dependencies a task actually needs. Keyword fallback (auto-extracted from API endpoints, function names, tables, config keys) supplements tag matching when synonyms or width limits block discovery.

Three CS primitives mapped to LLM context management: inverted index (MEMORY_MAP for O(1) lookup), normalization (domain-split nodes eliminate redundancy), foreign-key references (depends_on edges enable deterministic graph traversal instead of vector similarity search).

## Quick Reference

| Action | Command / Rule |
|---|---|
| Vague status / progress | Read `## Status Digest` or `## Progress Summary` in MEMORY_MAP.md |
| Find nodes for topic | Read `MEMORY_MAP.md`, match tags → aliases → keywords |
| Load memory for task | Layer 1: MAP summary scan → Layer 2: target node → Layer 3: bounded BFS deps (depth ≤ 2, width ≤ 5) |
| Compound time+domain query | Filtered BFS: decompose query → tag match + date filter + section locate |
| Create persistent module | `meta/mod_<name>.md` with type: module |
| Create feature (active) | `meta/feat_<name>.md` with type: feature, status: in-progress |
| Archive completed feature | Move to `meta/archive/`, set status: archived, rebuild index |
| Declare dependency | Add path to `depends_on` in both nodes' frontmatter |
| Suggest dependencies | `bash scripts/suggest_edges.sh` — auto-detect from Connection Points |
| Multi-root task | Select top-k nodes from MAP; ≤3 all, 4-5 by recency, >5 ask user |
| Traverse context | Layer 1 MAP summary → Layer 2 target node → Layer 3 bounded BFS deps |
| Check who depends on a module | Read `blocks` from MEMORY_MAP.md (auto-computed) |
| Assess impact before modify | Read Connection Points sections of blocking nodes only |
| Detect missing edges | Self-check node body for other-module references, verify in depends_on |
| Rebuild index + validate | Auto-run by session-end hook; manual: `scripts/generate_memory_map.sh` |
| Post-edit validation | Auto-run by post-tool-use hook; checks frontmatter + dead links |
| Initialize project | `bash scripts/init.sh` — auto-detect stack, generate skeleton nodes |

## Trigger Patterns (MANDATORY activation)

When the user's message matches ANY of these patterns, Agent MUST execute the Retrieval Protocol before responding:

| User says... | Extract keyword | Query MEMORY_MAP for |
|---|---|---|
| "XX 做得怎么样了" / "XX 的状态" / "XX 完成了吗" / "how is XX going" / "what's the status of XX" / "is XX done" | XX | tag matching XX |
| "继续做 XX" / "上次 XX 做到哪了" / "continue working on XX" / "where did we leave off on XX" | XX | tag matching XX |
| "XX 有什么问题" / "帮我看一下 XX" / "关于 XX..." / "what's wrong with XX" / "take a look at XX" / "regarding XX..." | XX | tag matching XX |
| "XX做到什么程度了" / "还有多少没做完" / "接下来做什么" / "what's the progress" / "what should I work on next" | (none — aggregate) | Progress Summary: ratios + issues + priorities |
| "今天XX改了什么" / "最近XX有什么变化" / "what changed in XX today/recently" | XX + time | Filtered BFS: tag + date filter |

**Keyword extraction rules:**
- Tech terms first: FastAPI → `api, backend`, React → `frontend, ui`
- Module names direct: 登录/login → `auth, login`, 支付/payment → `payment`
- Vague descriptions inferred: 前端 → `frontend`, 数据库 → `database`
- **Fallback**: If no keyword extracted AND no tag matches → go to Status Overview mode (read Status Digest only). Do NOT guess. Do NOT skip memory lookup.

## Query Routing

| Query type | Example | Mode | Reads |
|---|---|---|---|
| Vague status | "咱们做的咋样了" | **Status Digest + Progress Summary** | MEMORY_MAP.md only (Layer 1, ~500 tokens) |
| Progress / next steps | "咱们现在干到什么程度了" | **Progress Summary** | MEMORY_MAP.md Progress Summary section — aggregates ratios, issues, priorities |
| Pending work | "还有什么没做完" | **Status Digest** | Same, filter open issues > 0 |
| Specific module | "登录做得怎么样了" | **Progressive BFS** | Layer 1 MAP summary → Layer 2 target node → Layer 3 deps if needed |
| Cross-module | "支付超时怎么处理" | **Progressive BFS + Impact** | Layer 1 MAP summary → Layer 2 target node → Layer 3 deps + in-degree Connection Points |
| Trivial change | "登录按钮改个颜色" | **Progressive BFS (shallow)** | Layer 1 MAP summary → Layer 2 target node only (deps unnecessary) |
| Tag fails / too broad | "那个 token 刷新的事" | **Keyword Fallback** | Layer 1 Keyword Index → Layer 2 target node → Layer 3 deps if needed |
| Compound query | "今天的前端UI改了什么" | **Filtered BFS** | Decompose: domain→tag, time→date filter, action→section. Layer 1 filtered MAP → Layer 2 target → Layer 3 deps |
| Progress overview | "咱们现在干到什么程度了" | **Progress Summary** | Layer 1 MEMORY_MAP.md Progress Summary section only (~300 tok). Aggregate: stable/in-progress ratio, open issues, priorities |

### Filtered BFS — Compound Query Decomposition

When a query contains multiple dimensions (time, domain, sub-domain, action), decompose before matching:

| Dimension | Examples | Maps to |
|---|---|---|
| **Time** | "今天", "昨天", "上周", "最近", "2026-05" | Date filter on Change Log entries (YYYY-MM-DD enforced) |
| **Domain** | "前端", "认证", "支付", "数据库" | Tag match (Chinese/English normalized) |
| **Sub-domain** | "UI", "API", "样式", "路由" | Secondary tag match within domain results |
| **Action** | "改了什么", "新增", "修复", "删除了" | Section location: Change Log = changes, Current State = current, Open Issues = problems |

**Decomposition procedure:**
1. Extract time words → date filter window. Scan Change Log section for entries within the window.
2. Extract domain words → tag match in MEMORY_MAP Tag Index.
3. Extract sub-domain words → secondary tag filter within domain results.
4. Extract action words → determine which body section to target (Change Log / Current State / Open Issues).
5. Intersect: node must match domain tag AND have Change Log entries within time window.
6. If intersection is empty, broaden time window or drop sub-domain filter.

**Prerequisite:** All Change Log entries MUST use `YYYY-MM-DD` format. The script enforces this; non-conforming entries are flagged in Topology Health.

## Retrieval Protocol (MANDATORY) — Decision Tree

Follow this decision tree exactly. At each node, answer the question and follow the branch. Do NOT skip steps. Do NOT load files outside the paths specified here.

```
START: User query matches trigger pattern?
├─ NO  → Skip retrieval. Proceed with task as-is.
└─ YES → Continue below

STEP 1 — Query Classification
├─ "Vague status query" (e.g., "how are we doing?", "what's the status?")
│  └─ → Read MEMORY_MAP.md ## Status Digest + ## Progress Summary
│     └─ Answer from aggregates. Ask user which module to drill into.
│        Cost: ~500 tokens. STOP here for vague queries.
│
├─ "Progress / next-steps query" (e.g., "what's left?", "what should I do next?")
│  └─ → Read MEMORY_MAP.md ## Progress Summary ONLY
│     └─ Answer from ratio + issues + priorities. Suggest next action.
│        Cost: ~300 tokens. STOP here for progress queries.
│
├─ "Compound query" (has time + domain + action words)
│  └─ → Decompose per Filtered BFS protocol (above).
│     → Then continue to STEP 2 with decomposed dimensions.
│
└─ "Specific task query" (has domain keywords)
   └─ → Continue to STEP 2

STEP 2 — Layer 1: MAP Triage (DO NOT load node files yet)
Open MEMORY_MAP.md.

2a. Tag Index lookup
    └─ Search for tag matching query keyword.
       ├─ ≤ 3 matches  → Mark ALL as candidates. Go to STEP 3.
       ├─ 4–5 matches  → Read summaries only. Pick top 3 by recency.
       │                 Go to STEP 3 with top 3.
       ├─ > 5 matches  → STOP. Tell user: "Too many matches for 'X'.
       │                 Please narrow: specify module name or add context."
       └─ 0 matches    → Go to 2b.

2b. Tag Affinity expansion (only if 2a found 0 matches)
    └─ Scan ## Tag Affinity for synonyms of query tag.
       ├─ Found affinity ≥30%  → Retry 2a with synonym tag.
       │                          If still 0, go to 2c.
       └─ No affinity found    → Go to 2c.

2c. Alias match (only if 2a and 2b both failed)
    └─ Scan ## Tag Index for aliases matching query keyword (pure string contains).
       ├─ Found match  → Mark as candidate. Apply same width bounds as 2a.
       │                  Go to STEP 3.
       └─ No match     → Go to 2d.

2d. Keyword Index fallback (only if 2a, 2b, and 2c all failed)
    └─ Scan ## Keyword Index for API paths, function names, tables, configs.
       ├─ Found match  → Mark as candidate. Apply same width bounds as 2a.
       │                  Go to STEP 3.
       └─ No match     → STOP. Tell user: "No memory nodes found for 'X'.
                          Please check the topic or create a new node."

At end of STEP 2, you have 1–3 candidate nodes identified.
You have NOT loaded any node files. Cost: 200–500 tokens.

STEP 3 — Layer 2: Target Node Loading (commit to relevance)
For EACH candidate from STEP 2:
├─ Read the FULL node file.
├─ Check token estimate from MAP. Running total > ~1,000 tokens?
│  └─ YES → Prioritize most recent/closest match. Defer others.
└─ Confirm relevance from node content.

If task is trivial (e.g., "fix button color"):
   └─ STOP after reading target node. Deps unnecessary.

If task is cross-module or ambiguous:
   └─ Continue to STEP 4.

Cost per node: 400–1,200 tokens.

STEP 4 — Layer 3: Bounded BFS Expansion (depth ≤ 2, width ≤ 5)
For EACH target node loaded in STEP 3:

4a. Depth 1 (MANDATORY for cross-module tasks)
    └─ Read ALL files in target node's `depends_on`.
       ├─ > 5 depends_on? → Load first 5 by declaration order only.
       ├─ Check `~N tok` estimates. Running total > 15% of context window?
       │  └─ YES → STOP expansion. Report budget constraint to user.
       └─ Add to active context.

4b. Depth 2 (CONDITIONAL)
    └─ For each depth-1 node, read its `depends_on`.
       ├─ Load ONLY if node tags overlap with task domain.
       ├─ Skip unrelated transitive dependencies.
       └─ Add to active context if loaded.

4c. Stop checks (apply after each depth)
    ├─ depth > 2?           → STOP. (Beyond depth 2 is out of bounds —
    │                          if you need a deeper module, start a new
    │                          retrieval with that module as the root.)
    ├─ token budget > 15%?  → STOP.
    └─ Task scope satisfied? → STOP.

Theoretical worst case: 5 roots × (1 + 5 depth-1 deps + 5×5 depth-2 deps) = 155 files.
In practice the depth-2 tag-overlap filter and the 15% token budget cap collapse this
to typical loads of 2–4 files, with cross-module tasks loading 6–10.

STEP 5 — Modify Protocol (ONLY if task involves writing/editing)
For EACH node you will modify:
├─ Check node's `blocks` field in MEMORY_MAP.md.
├─ `blocks` is non-empty?
│  └─ YES → Read ONLY the ## Cross-Module Connection Points section
│           from EACH blocking node.
│           Assess: will your change break any downstream contract?
└─ Proceed with modification only after impact assessment.

STEP 6 — Post-Retrieval
├─ Assemble context: target nodes + BFS-loaded deps.
├─ Merge subgraphs if multiple roots.
├─ DO NOT load files outside assembled subgraph.
├─ Execute task.
├─ If cross-module relationships changed: update `depends_on` on ALL affected nodes.
└─ If node structure changed: run `scripts/generate_memory_map.sh`.

STEP 7 — Session Wrap (HOOK-ENFORCED, do NOT execute manually)
├─ PostToolUse hook validates frontmatter after each Write/Edit.
├─ Stop hook rebuilds MAP + validates topology + detects drift.
└─ Review hook output before next session.
```

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
summary: "One-line description for MAP triage. Read before loading full node."
depends_on:
  - meta/mod_auth-api.md
  - meta/mod_user-table.md
tags: [auth, login, jwt]
aliases: [authentication, 认证, 登录, signin, token验证]
# `aliases` are natural language synonyms the user might say (Chinese,
# English, abbreviations). Indexed alongside tags for fallback matching.
# Pure string contains — no embedding model, grep-compatible.
# `blocks` is the reverse of `depends_on`. It is auto-computed by
# generate_memory_map.sh and appears only in MEMORY_MAP.md.
# Do NOT add a `blocks` field to node files — it will be ignored.
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

## Change Log (YYYY-MM-DD format REQUIRED)

```markdown
- [YYYY-MM-DD] **Context**: [What was happening — the trigger or background]
  **Change**: [What was done — concrete, specific]
  **Impact**: [What this affects — downstream consumers, contracts, behavior]
  **Affected**: [list of modules/features impacted, if any]
```

> **Date format is mandatory.** All entries MUST begin with `[YYYY-MM-DD]`.
> Non-conforming entries break Filtered BFS time queries and are flagged in Topology Health.
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

**blocks (Script managed, MEMORY_MAP only — never lives in node files):**
- `blocks` is the reverse of `depends_on`. If A depends_on B, then B is blocked_by A.
- Computed automatically by `generate_memory_map.sh` and rendered ONLY into MEMORY_MAP.md.
- Agent reads `blocks` from MEMORY_MAP.md during the modify step. Do NOT add a `blocks` field to node frontmatter — the post-edit hook warns when it sees one.
- If `blocks` appears stale, run `scripts/generate_memory_map.sh` — it will recompute.

### 4. Soft dependency inference (drift detection)

Hard edges (`depends_on`) are the primary path. But they WILL drift — humans and Agents miss updates. The script auto-extracts keywords from each node (API endpoints, function names, tables, config keys) into `## Keyword Index` as a soft fallback when tag matching fails.

**Self-check after writing any node's `## Current State`:**
1. Scan the text for references to other modules: API paths (`/api/v1/auth/*`), table names, component imports, config keys
2. For each reference to another module's domain, verify `depends_on` contains that module
3. If a reference exists but no edge declares it, EITHER:
   - Add the edge to `depends_on`, OR
   - Flag in `## Open Issues`: `[PENDING VERIFY: depends_on mod_X? Reference to /api/v1/X but no edge declared]`

**This is NOT a replacement for hard edges.** It's a safety net. The script's keyword index provides semantic fallback; the topology health check catches dead links; this catches missing links.

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

Requires bash 4+. The fastest path is the cold-start wizard:

```bash
bash .claude/skills/synapse-graph-memory/scripts/init.sh
```

It detects your tech stack, generates skeleton nodes, copies the generation
and hook scripts into `scripts/` and `scripts/hooks/`, registers the hooks in
`.claude/settings.json`, and runs the first index build.

Manual setup if you prefer to wire it up yourself:

```bash
mkdir -p meta/archive scripts scripts/hooks
cp .claude/skills/synapse-graph-memory/scripts/generate_memory_map.sh scripts/
chmod +x scripts/generate_memory_map.sh
# Optional pre-commit hook
printf '#!/bin/sh\nbash scripts/generate_memory_map.sh\n' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

Run `scripts/generate_memory_map.sh` once after setup to create the initial `MEMORY_MAP.md`.

## Common Mistakes

| Mistake | Why wrong | Fix |
|---|---|---|
| Reading all meta/*.md "to be safe" | Loads irrelevant context, defeats the system | Trust the graph. MAP summary (Layer 1) → target node (Layer 2) → deps only if needed (Layer 3). |
| "the auth endpoints" instead of `/api/v1/auth/refresh` | Agent later works with a fuzzy signal, hallucinates details | Write paths/values verbatim |
| Updating `depends_on` on one side only | Graph becomes asymmetric, other direction is invisible | Check ALL affected nodes after cross-module work |
| Manual edit of MEMORY_MAP.md | Drift between MAP and actual files | Run `scripts/generate_memory_map.sh` |
| Deep directory nesting (meta/frontend/ui/components/...) | Defeats flat-file grep-ability | Max 2 levels |
| Creating a node per source file | Node count explodes, MAP becomes expensive to load | One node per functional module |
| Ignoring hook output warnings | Hooks enforce checks but Agent must act on warnings | Read hook output before next task; fix flagged issues |
| Missing `summary` in frontmatter | Agent cannot triage nodes in Layer 1; forced to load full files | Always include one-line summary: what this node is, why it exists |
| Flat Change Log entries | "2026-05-01 Fixed bug" loses causal context | Use Observation format: Context → Change → Impact → Affected |
| "Key data preserved" without specifics | Summary hallucination: Agent thinks it knows but lacks precision | Use fidelity category table, verbatim for exact-mode data |
| Manually editing `blocks` field | `blocks` does not live in node files; it is computed and rendered only in MEMORY_MAP.md | Run `generate_memory_map.sh` instead — it derives blocks from depends_on |
| Modifying a module without checking in-degree | Downstream consumers silently break | Always execute modify-protocol: check blocks in MAP, read Connection Points of dependents |
| Assuming flat 1-hop is always enough | Transitive chains (A→B→C→D) silently lose context at depth 3+ | Trust bounded BFS — constrains both depth (≤ 2) and width (≤ 5) |
| Free-text Connection Points | "Needs auth API" is useless for impact assessment | Use schema: Endpoint, Request, Response, Errors |
| Node too large (>150 lines) | Becomes its own memory collapse — all sub-topics jumbled | Split by sub-domain |
| Node too small (<30 lines) | Graph clutter, adds traversal cost without information gain | Merge with closest dependency |

## Supporting Files

- `scripts/generate_memory_map.sh` — Scans `meta/*.md`, extracts frontmatter, builds tag-indexed MEMORY_MAP.md
- `template.md` — Node templates: copy the relevant section when creating mod or feat nodes
