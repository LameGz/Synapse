# Synapse

<p align="center">
  <img src="docs/images/synapse-logo.png" alt="Synapse" width="200"><br>
  <em>Graph-Based Partitioned Memory for AI Agents</em>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License"></a>
</p>

---

## What is Synapse?

Synapse loads only the subgraph of memory nodes relevant to the current task, using explicit `depends_on` edges for deterministic traversal instead of vector similarity or flat-file scanning.

> **Core principle**: Partitioned loading via graph topology — keep information completeness while eliminating cross-domain noise.

> **Measured**: 73% average token reduction vs flat-file memory across 7 task types (2–5 files loaded vs ~2,600 tokens of flat context). No cross-module context loss. [Full report →](USAGE.md#testing--benchmarking)

If RecallLoom answers "what happened?", Synapse answers "what do I need to know *right now*?"

---

## The Problem

Flat memory files (RecallLoom-style) work perfectly for small projects. But as a project grows — frontend, backend, database, auth, payments — the single `rolling_summary.md` becomes a landfill. When the Agent only needs to fix a button color, it's forced to load database schema into context.

**This is the flat-memory information density collapse.**

Synapse solves this by organizing memory as a graph. The Agent loads only the target node and the relevant subgraph via bounded BFS traversal (depth ≤ 2, width ≤ 5) — nothing else.

---

## Architecture

```
                    ┌─────────────────────┐
                    │    MEMORY_MAP.md     │  ← Auto-generated tag index (O(1) lookup)
                    │  (DO NOT EDIT        │
                    │   MANUALLY)          │
                    └────────┬────────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
     ┌────────────┐  ┌────────────┐  ┌────────────┐
     │ mod_auth   │  │ feat_login │  │ mod_db     │
     │ -api.md    │◄─┤ .md         ├─►│ -schema.md │
     └──────┬─────┘  └────────────┘  └────────────┘
            │
            │  depends_on / blocks (auto-computed reverse edges)
            │
     ┌──────▼─────┐
     │ feat_oauth │
     │ .md        │
     └────────────┘
```

> [Flowchart placeholder — draw your own or insert `docs/images/synapse-architecture.png`]

---

## How It Works

### Three CS Primitives in LLM Context Management

| Concept | CS Primitive | Why |
|---|---|---|
| `MEMORY_MAP` + tag index | **Inverted Index** | O(1) lookup, never scans all files |
| Domain-split nodes, on-demand load | **Normalization** | Eliminates redundancy, isolates irrelevant data |
| `depends_on` edges + bounded BFS traversal | **Foreign Key References** | Deterministic routing — not "semantically similar" guessing |

### Node Types

| Prefix | Type | Lifecycle |
|---|---|---|
| `mod_` | Persistent architecture module | Active forever (routing, state management, DB schema) |
| `feat_` | Lifecycle-bound feature | active → stable → archived |

### Query Routing

| User says... | Mode | Reads |
|---|---|---|
| "咱们做的咋样了" | **Status Digest** | `MEMORY_MAP.md` only (~200 tokens) |
| "还有什么没做完" | **Status Digest** | Same, filter `in-progress` |
| "登录做得怎么样了" | **Bounded BFS** | `feat_login.md` + deps |
| "FastAPI 接口写完没" | **Bounded BFS** | `mod_auth-api.md` + deps |
| "支付超时怎么改" | **Bounded BFS + Impact** | Target + deps + downstream contracts |

**Status Digest** is a lightweight section auto-generated in `MEMORY_MAP.md` — one line per node with status, last update, open issues count. Vague queries like "how's the project going" answer from this single section without loading any node files.

**Trigger Patterns**: Agent detects phrases like "XX做得怎么样了"/"XX的状态"/"继续做XX" and automatically activates memory lookup before responding.

---

## Quick Start

```bash
# 1. Initialize Synapse in your project
mkdir -p meta/archive scripts

# 2. Copy the generation script
cp .claude/skills/synapse-graph-memory/scripts/generate_memory_map.sh scripts/
chmod +x scripts/generate_memory_map.sh

# 3. Create your first module node
cat > meta/mod_project.md << 'EOF'
---
id: mod_project
type: module
status: in-progress
updated: $(date +%Y-%m-%d)
depends_on: []
blocks: []
tags: [project, overview]
---

# Project Overview

## Current State
[Describe your project architecture here. Preserve exact paths, versions, configs.]

## Key Decisions
- Decision — rationale

## Cross-Module Connection Points
None yet.

## Open Issues
None.

## Change Log
- Initial creation
EOF

# 4. Generate the index
./scripts/generate_memory_map.sh

# 5. Install pre-commit hook
echo '#!/bin/sh' > .git/hooks/pre-commit
echo 'scripts/generate_memory_map.sh' >> .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

---

## Synapse vs RecallLoom

| | RecallLoom (Flat) | Synapse (Graph) |
|---|---|---|
| **Best for** | Small projects, single domain | Multi-domain projects, 10+ modules |
| **Context purity** | Low — everything in one file | High — only relevant subgraph loaded |
| **Setup cost** | Near zero | ~5 minutes |
| **Cross-module work** | All context always loaded | Traverse edges to find related nodes |
| **Risk** | Token waste, hallucination from noise | Graph drift if hooks misconfigured (auto-enforced by default) |
| **Learning curve** | None | 7-step retrieval protocol |

> **They are complementary.** Use RecallLoom for rapid prototyping. Graduate to Synapse when cross-domain noise becomes visible.

---

## File Structure

```
project/
├── MEMORY_MAP.md              ← Auto-generated index (DO NOT EDIT)
├── meta/
│   ├── mod_*.md               ← Persistent module nodes
│   ├── feat_*.md              ← Feature nodes (active/stable)
│   └── archive/               ← Archived features
├── scripts/
│   ├── generate_memory_map.sh ← Index generator + topology validator
│   └── hooks/
│       ├── post-tool-use.sh   ← Validates frontmatter after edits
│       └── session-end.sh     ← Auto-rebuilds MAP at session end
├── .claude/
│   ├── settings.json          ← Hook registration
│   └── skills/synapse-graph-memory/
└── .git/hooks/pre-commit      ← Auto-rebuild on commit
```

---

## Hooks: Infrastructure-Level Enforcement

Synapse uses Claude Code hooks to **enforce memory integrity automatically** — no Agent self-discipline required.

| Hook | Event | What it does |
|---|---|---|
| `post-tool-use.sh` | After every `Write`/`Edit` to `meta/*.md` | Validates frontmatter completeness, checks `depends_on` targets exist, verifies `updated` field |
| `session-end.sh` | Session end | Rebuilds `MEMORY_MAP.md`, runs topology validation, outputs change summary, flags source→memory drift |

Configured in `.claude/settings.json`. The Agent doesn't need to remember session wrap — the hook guarantees it.

## The Skill

This project is powered by the `synapse-graph-memory` skill at `.claude/skills/synapse-graph-memory/SKILL.md`. Load it into your Agent to enforce the retrieval protocol, fidelity rules, and cleanup workflow.

---

## License

Apache 2.0 © 2026

---

## Related Projects

- [RecallLoom](https://github.com/Frappucc1no/RecallLoom) — Flat-file memory for small projects (the precursor to Synapse)
  - [Microsoft GraphRAG](https://github.com/microsoft/graphrag) — Enterprise-scale graph retrieval (the academic foundation)
