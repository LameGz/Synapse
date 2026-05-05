# Synapse Example: E-Commerce Checkout

This directory contains a **minimal but realistic** Synapse memory graph demonstrating how the system works in practice.

## What's Inside

| File | Type | Purpose |
|---|---|---|
| `meta/mod_project.md` | Module | Project overview — entry point for new sessions |
| `meta/mod_auth-api.md` | Module | Auth module (JWT, RS256) — persistent architecture |
| `meta/mod_payment.md` | Module | Stripe payment integration — persistent architecture |
| `meta/feat_checkout.md` | Feature | Checkout flow — lifecycle-bound, in-progress |
| `MEMORY_MAP.md` | Index | Auto-generated tag/keyword index + status digest |

## Graph Topology

```
              mod_project
              (overview)
             /     |     \
            /      |      \
     mod_auth-api  |   mod_payment
     (JWT auth)    |   (Stripe)
            \      |      /
             \     |     /
              feat_checkout
              (in-progress)
```

## Key Concepts Demonstrated

1. **Module vs Feature nodes**: `mod_*` are persistent architecture; `feat_*` are lifecycle-bound
2. **`depends_on` edges**: `feat_checkout` depends on all three modules above it
3. **Tags + Aliases**: `mod_auth-api` has tags `[auth, api, security]` and aliases `[login, signin, session]`
4. **Connection Points**: Each node documents which APIs it exposes and which other nodes consume them
5. **Observation Format Change Log**: Structured entries with Context, Change, Impact, Affected
6. **Status Digest**: `MEMORY_MAP.md` summarizes all 4 nodes in a single glance (~200 tokens)

## How to Explore

1. Read `MEMORY_MAP.md` first — this is Layer 1 (triage)
2. Pick a node based on the summary — e.g., "checkout timeout" → `feat_checkout.md`
3. Follow `depends_on` edges to load context — e.g., `feat_checkout` → `mod_payment` for Stripe webhook details
4. Never load more than depth 2, width 5

## Cost Estimate

| Query | Mode | Files | Est. Tokens |
|---|---|---|---|
| "Project status" | Status Digest | MEMORY_MAP.md only | ~200 |
| "Auth module details" | Bounded BFS | mod_auth-api + mod_project | ~520 |
| "Checkout timeout fix" | Bounded BFS + Impact | feat_checkout + mod_payment + mod_auth-api | ~880 |
| Naive flat load (all files) | — | 4 files | ~1,120 |

Savings vs flat: ~20-80% depending on query specificity.
