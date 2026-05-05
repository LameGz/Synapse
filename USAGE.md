# Synapse — Usage Guide

> Step-by-step walkthrough from initialization to daily workflow.

---

## Table of Contents

- [Initial Setup](#initial-setup)
- [Creating Your First Nodes](#creating-your-first-nodes)
- [Daily Workflow](#daily-workflow)
- [Cross-Module Work](#cross-module-work)
- [Archiving Completed Features](#archiving-completed-features)
- [What's New in 0.3.0](#whats-new-in-030)
- [Cleanup & Maintenance](#cleanup--maintenance)
- [Troubleshooting](#troubleshooting)
- [Advanced: Custom Topology Validation](#advanced-custom-topology-validation)

---

## Initial Setup

### Prerequisites

- Git repository initialized
- `bash` 4+ (macOS ships with bash 3.2 — install via `brew install bash`; Git Bash on Windows is fine; native bash on Linux is fine)
- POSIX `awk`, `grep`, `sed` available
- Optional: `jq` (only needed for `parse-session.sh --audit`, which does deep JSON traversal of session transcripts to verify exact BFS depth/width compliance)
- The `synapse-graph-memory` skill installed in `.claude/skills/`

### Option A — One-command wizard (recommended for new projects)

```bash
bash .claude/skills/synapse-graph-memory/scripts/init.sh
```

`init.sh` will:

1. **Auto-detect your tech stack** — reads `package.json`, `go.mod`, `pyproject.toml`, `Cargo.toml`, etc. to identify framework (Next.js, FastAPI, Express, etc.) and database.
2. **Infer module boundaries** — detects common directories like `src/api`, `src/auth`, `src/db`, and generates `mod_*.md` skeletons for each.
3. **Install all 4 hooks** — copies `pre-read-check.sh`, `pre-modify-check.sh`, `post-tool-use.sh`, and `session-end.sh` into `scripts/hooks/`.
4. **Register hooks** — merges the Synapse hook configuration into `.claude/settings.json` (safe merge, no overwrite of existing hooks).
5. **Build the first `MEMORY_MAP.md`** — generates index + JSON mirror immediately.

Re-runnable: existing nodes are skipped, never overwritten. If your project already has nodes from a previous run, only missing ones are created.

### Option B — Manual setup

#### Step 1: Directory structure

```bash
cd your-project
mkdir -p meta/archive scripts docs/images
```

#### Step 2: Install the generation script

```bash
cp .claude/skills/synapse-graph-memory/scripts/generate_memory_map.sh scripts/
chmod +x scripts/generate_memory_map.sh
```

#### Step 3: Git hook (auto-rebuild index on commit)

```bash
cat > .git/hooks/pre-commit << 'HOOK'
#!/bin/sh
scripts/generate_memory_map.sh
HOOK
chmod +x .git/hooks/pre-commit
```

#### Step 4: Create the root module node

Create `meta/mod_project.md`:

```yaml
---
id: mod_project
type: module
status: in-progress
updated: 2026-04-30
depends_on: []
tags: [project, overview]
---

# Project Overview

## Current State
Tech stack: React 18 + TypeScript, Express.js, PostgreSQL 15.
Root endpoint: http://localhost:3000
API base: /api/v1

## Key Decisions
- 2026-04-30 JWT over session auth — stateless, works with mobile clients

## Cross-Module Connection Points
None yet — add as modules are created.

## Open Issues
None.

## Change Log
- 2026-04-30 Project initialized with Synapse
```

### Step 5: Generate the first index

```bash
./scripts/generate_memory_map.sh
```

You should see:
```
MEMORY_MAP.md regenerated: 1 nodes, 2 tags, 0 topology warnings.
```

---

## Creating Your First Nodes

### Adding a module node

When you build a new architectural component (auth system, database schema, state management):

```bash
# Copy the template, then use the "Module Node" section as your starting point
cp .claude/skills/synapse-graph-memory/template.md meta/mod_auth-api.md
# Edit: keep the mod_ section, delete the feat_ and archive sections
```

Fill in:
- `id`, `tags` — for MAP discovery
- `## Current State` — use **exact mode** for endpoints, config keys, field names
- `## Cross-Module Connection Points` — use the schema format (Endpoint, Request, Response, Errors)

### Adding a feature node

When you start implementing a new feature:

```bash
# Copy the template, then use the "Feature Node" section as your starting point
cp .claude/skills/synapse-graph-memory/template.md meta/feat_user-login.md
# Edit: keep the feat_ section, delete the mod_ and archive sections
```

Edit `depends_on` to list the modules this feature depends on:

```yaml
depends_on:
  - meta/mod_auth-api.md
  - meta/mod_user-table.md
```

> **Run `scripts/generate_memory_map.sh` after creating or editing nodes.** This updates the index and auto-computes `blocks` fields.

---

## Daily Workflow

### Starting a task

1. **Read `MEMORY_MAP.md`** — identify top-2 candidate nodes matching your task's domain. For multi-domain tasks (e.g., "login fails with 401"), pick one candidate per domain (max 3).
2. **Read primary node(s)** — understand current state and decisions
3. **Bounded BFS traverse** — depth 1 (all `depends_on`), depth 2 (only if tags overlap with task domain), depth 3 (only if explicitly needed). Stop at token budget ~15%.
4. **Start working**

### Modifying a module (critical difference from read-only tasks)

When you're about to **change** a module that other features depend on:

1. Read the module's node
2. **Check `blocks` in MEMORY_MAP.md** — who depends on this module?
3. **Read only the `## Cross-Module Connection Points`** section of each dependent node
4. Assess: does my change break any downstream contract?
5. Proceed with the change

**Example**: You're adding a required parameter to an API endpoint.

```
Read MEMORY_MAP.md → find mod_auth-api
Check blocks → feat_user-login, feat_admin-panel
Read feat_user-login.md → only "Cross-Module Connection Points" section
  → "### To mod_auth-api | Endpoint: POST /api/v1/auth/login | Request: { email, password } | Response: { token, user } | Errors: 40101, 40102"
Read feat_admin-panel.md → only "Cross-Module Connection Points" section
  → "### To mod_auth-api | Endpoint: POST /api/v1/auth/login | Request: { email, password } | Response: { token, user, role } | Errors: 40101, 40102"

Assessment: Adding a required field will break BOTH consumers.
Decision: Make the new parameter optional, or coordinate the change with both features.
```

### Ending a session

**Session end is handled automatically by hooks.** No manual steps needed.

`scripts/hooks/session-end.sh` runs via `.claude/settings.json` Stop hook and:

1. Rebuilds `MEMORY_MAP.md` + validates topology
2. Outputs change summary from git diff of `meta/` files
3. Flags if source files were modified but no memory nodes were updated

Expected hook output:
```
🔍 Synapse Session End — Running memory integrity checks...
MEMORY_MAP.md regenerated: 5 nodes, 8 tags, 0 topology warnings.

📝 Memory Changes
─────────────────
Modified: meta/mod_auth-api.md
─────────────────
Changes committed to memory system.
```

### Post-edit validation

`scripts/hooks/post-tool-use.sh` fires after every `Write`/`Edit` to `meta/*.md` and checks frontmatter completeness in real time. If issues are found, a warning is injected directly into the conversation.

---

## Cross-Module Work

### When a feature spans multiple domains

Example: "Add social login" touches auth, database, and frontend.

1. Create `meta/feat_social-login.md`:

```yaml
depends_on:
  - meta/mod_auth-api.md      # needs OAuth endpoints
  - meta/mod_user-table.md    # needs social_id column
  - meta/mod_frontend-routing.md  # needs callback page
tags: [auth, login, oauth, social]
```

2. Update each depended-on module's `depends_on` if they need to be aware of this feature (e.g., `mod_frontend-routing.md` now needs to serve a callback route — add `feat_social-login` to its `depends_on`).

3. Run `scripts/generate_memory_map.sh`. The script auto-computes:
   - `mod_auth-api` `blocks`: feat_social-login (auto)
   - `mod_user-table` `blocks`: feat_social-login (auto)

---

## Archiving Completed Features

When a feature is done and stable:

```bash
# 1. Update the node
# Change status: in-progress → archived
# Add "Why archived" and "Restore notes" to body

# 2. Move to archive
mv meta/feat_social-login.md meta/archive/

# 3. Rebuild
./scripts/generate_memory_map.sh
```

Archived nodes are excluded from the index but preserved for historical reference.

---

## What's New in 0.3.0

### Filtered BFS for compound queries

When a query spans multiple dimensions — *"What changed in auth last week"* — the agent decomposes it into time + domain + sub-domain + action filters. Instead of loading the entire auth subgraph, BFS only follows edges matching all dimensions simultaneously.

**How it works in practice:**
- **Time filter**: `Change Log` entries with dates within the range
- **Domain filter**: tags matching the primary domain (`auth`)
- **Sub-domain filter**: `depends_on` edges leading to specific sub-modules
- **Action filter**: keywords matching the action (`change`, `update`, `fix`)

Only nodes passing all four filters are loaded. For the query above, instead of 5-8 auth nodes, the agent may load only 2-3 specific ones from last week's changes.

### Tag aliases

The `aliases:` frontmatter field lets a node respond to multiple names:

```yaml
---
id: mod_auth-api
type: module
status: stable
updated: 2026-04-30
depends_on: [meta/mod_project.md]
tags: [auth, api, security]
aliases: [login, signin, session]  # ← query "login" now hits this node
summary: "Authentication endpoints and session management"
---
```

When a user's query uses an alias, the tag index maps it back to the canonical node. The `aliases:` field is auto-indexed by `generate_memory_map.sh` and appears in the `MEMORY_MAP.md` tag section.

### Session-end Progress Summary

`session-end.sh` now produces a structured digest instead of free-form output:

```
Synapse session summary:

Nodes touched:
  feat_checkout.md  →  1 change  →  stable
  mod_auth-api.md   →  0 changes →  stable

Topology status: ✅ Valid (no dead links, no orphans)

Drift detection:
  ✅ Source → memory consistent (no un-synced edits)

Action items:
  - feat_checkout: frontmatter updated, check blocks consistency
```

This is intentionally machine-readable — parse-session.sh can consume it for trend analysis across sessions.

### Pre-read and pre-modify hooks

The hook suite expanded from 2 to 4:

| Hook | When | What |
|---|---|---|
| `pre-read-check.sh` | Before every `Read meta/*.md` | Tracks consecutive reads. If width > 5 or depth > 2, injects a BFS protocol reminder before the read completes. |
| `pre-modify-check.sh` | Before every `Write`/`Edit` to source files | Scans memory nodes referencing the file, surfaces `blocks` (downstream consumers) so the agent knows what contracts might break. |
| `post-tool-use.sh` | After `Write`/`Edit` to `meta/*.md` | Validates frontmatter and `depends_on` targets. |
| `session-end.sh` | Session end | Rebuilds MAP, validates topology, outputs summary. |

The two new hooks are installed automatically by `init.sh` and registered in `.claude/settings.json`. For manual setups, copy them from `.claude/skills/synapse-graph-memory/scripts/hooks/`.

---

## Cleanup & Maintenance

### Weekly check

```bash
./scripts/generate_memory_map.sh
```

Check the `## Topology Health` section of `MEMORY_MAP.md`:

```
## Topology Health

⚠ DEAD LINK: meta/feat_payment.md depends_on meta/mod_stripe.md — file not found
⚪ ORPHAN: meta/feat_ab-test.md (feat_ab-test) — no edges in either direction
```

### Manual cleanup checklist

| Check | What to look for | Action |
|---|---|---|
| Orphan nodes | No `depends_on` and no `blocks` | Archive or reconnect |
| Dead links | `depends_on` targets missing files | Update or remove edge |
| Oversized nodes | Files > 200 lines | Split into sub-nodes |
| Stale nodes | `status: in-progress` but `updated` > 30 days ago | Downgrade to `stable` |
| Bidirectional gaps | A→B exists but B's blocks lacks A | Run script (auto-fix) |

---

## Troubleshooting

### "No meta/ directory found"

You haven't created any nodes yet. Create at least one `.md` file in `meta/`.

### "MEMORY_MAP.md not found"

Run `scripts/generate_memory_map.sh` once to create it.

### Agent is loading too many nodes

Check: is the Agent following bounded BFS, or reading all files "to be safe"? Verify the `synapse-graph-memory` skill is loaded. Run `bash scripts/parse-session.sh --summary` to audit recent sessions.

### blocks field is stale

Run `scripts/generate_memory_map.sh`. It recomputes blocks from depends_on.

### Script fails on a node file

Verify the frontmatter between `---` delimiters is valid. Common issues:
- Missing closing `---`
- Tabs instead of spaces in YAML
- Unquoted colons in values

---

## Advanced: Custom Topology Validation

The script's `## Topology Health` section covers dead links and orphans. For deeper validation, pipe the output:

```bash
# Find all nodes with more than 5 dependencies
grep -c "depends_on:" meta/*.md | grep -v ":0$" | sort -t: -k2 -rn

# Find nodes missing the updated field
grep -L "^updated:" meta/*.md

# Find nodes using fuzzy language (potential summary hallucination)
grep -n "the endpoint\|short-lived\|etc\." meta/*.md
```

---

## Testing & Benchmarking

### Simulated benchmark (no Agent required)

```bash
# Create a 10-module test project + flat-file equivalent
bash scripts/benchmark.sh setup

# Simulate 8 tasks and report expected token savings
bash scripts/benchmark.sh run
```

Output shows per-task file count, estimated tokens, and % reduction vs both baselines (dumb full-load and smart search-only):

```
Fix button color on checkout page          |  4 f |  1156 tok |  55% ↓ flat |  29% ↓ smart
Update JWT expiry time                     |  2 f |   400 tok |  84% ↓ flat |  50% ↓ smart
AVERAGE: 3 files | 753 tokens
  vs flat (dumb):   71% reduction  — flat loads everything
  vs flat (smart):  46% reduction — flat searches + reads relevant only
```

### Real session analysis

After running sessions with Synapse active, measure actual protocol compliance:

```bash
# Analyze one session transcript
bash scripts/parse-session.sh ~/.claude/transcripts/<session-id>.jsonl

# Summarize all sessions
bash scripts/parse-session.sh --summary

# Deep audit — requires jq (checks exact BFS depth/width per Read call)
bash scripts/parse-session.sh --audit ~/.claude/transcripts/<session-id>.jsonl
```

> **When do you need `jq`?** Only for `--audit`. The `--summary` mode works with POSIX tools (`grep`, `awk`, `sed`) and gives you file counts and protocol-compliance yes/no. `--audit` drills into every `Read` call in the transcript to measure exact traversal depth and width — this requires `jq` to parse the JSONL transcript structure. If you don't have `jq`, the first two commands above still work fine.

Expected output for a compliant session:
```
MEMORY_MAP reads: 1
Node file reads:  3
Node writes:      0
Total meta/ ops:  4

✅ Synapse protocol appears active (≤5 node files loaded)
```

### Manual verification checklist

For the most rigorous test — run identical tasks against flat and Synapse setups:

1. Create a test project with 10+ interconnected modules
2. **Flat baseline**: put all module info in a single `rolling_summary.md`
3. Run 3 tasks (single-domain, cross-domain, ambiguous) — count `Read` calls to `meta/`
4. **Synapse**: replace flat file with Synapse node files + load the skill
5. Run the same 3 tasks — count `Read` calls
6. Compare: files read, estimated tokens, task success rate

**What good looks like:**

| Metric | Flat | Synapse | Target |
|---|---|---|---|
| Files loaded per task | 1 (but all info inside) | 2-5 | ≤5 |
| Estimated tokens | ~2500+ (entire flat file) | ~400-1300 | ≤1500 |
| Task success rate | High (all context) | Same as flat | No regression |
| Cross-module misses | 0 (everything loaded) | 0 | No silent failures |

### Benchmark Report (10-module e-commerce project)

**Setup**: 10 interconnected modules (auth, payment, checkout, cart, search, profile, DB schema, API gateway, frontend routing, UI components) with cross-references via `depends_on`. Flat equivalent: all 10 modules concatenated into a single `rolling_summary.md` (~10KB, ~2,600 tokens).

**Baseline**: naive full-load — every task gets the entire `rolling_summary.md` injected into context. This represents the simplest "memory file" approach: dump everything, let the model sort it out.

**Methodology**: For each task, simulate the bounded BFS protocol — depth 1 (all deps, full load), depth 2 (tag-filtered, Connection Points only), MAP overhead (~200 bytes). Compare loaded bytes against the naive flat-load baseline above. Numbers are simulated counts of bytes/tokens that would be sent to the model, not measurements of a live Agent session.

| # | Task | Type | Files | Tokens | vs Flat (dumb) | vs Flat (smart) |
|---|---|---|---|---|---|---|
| 1 | Fix button color on checkout page | Single-domain | 4 | 1,156 | 55% ↓ | 29% ↓ |
| 2 | Add new field to user profile | Single-domain | 4 | 592 | 77% ↓ | 61% ↓ |
| 3 | Optimize product search query | Single-domain | 3 | 479 | 81% ↓ | 56% ↓ |
| 4 | Update JWT expiry time | Single-domain (modify) | 2 | 400 | 84% ↓ | 50% ↓ |
| 5 | Add new payment method | Cross-domain (modify) | 4 | 579 | 77% ↓ | 63% ↓ |
| 6 | Add cart persistence across devices | Single-domain (modify) | 3 | 373 | 85% ↓ | 65% ↓ |
| 7 | Debug 401 on login page | Multi-domain | 5 | 1,288 | 50% ↓ | 28% ↓ |
| 8 | Cold-start: login → checkout flow broken | Cross-domain | 4 | 1,156 | 55% ↓ | 29% ↓ |
| | | **Average** | **3** | **753** | **71% ↓** | **46% ↓** |

The "smart flat" baseline assumes the Agent searches the flat file first and only reads relevant sections (not the full file every time). It is the harder, more honest comparison — Synapse still wins, just by a smaller margin.

**Key findings:**

- **Best case** (Task 6): single-domain modification loads only 3 files, 85% reduction vs full flat-file
- **Worst case** (Task 7): multi-domain debugging loads 5 files, still 50% reduction — bounded BFS prevents the flat-file collapse even here
- **Zero regression in simulation**: all cross-module dependencies reachable within depth-2 + tag filtering
- **MAP overhead**: ~2% of flat baseline, amortized across the session
- These are simulated byte counts, not measurements of a real Agent in a real session — see the verification checklist above

**Reproduce**: `bash scripts/benchmark.sh setup && bash scripts/benchmark.sh run`
