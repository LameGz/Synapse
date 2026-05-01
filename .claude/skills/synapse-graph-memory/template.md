# Synapse Node Templates

Copy the relevant template below when creating a new node.

---

## Module Node (`mod_<name>.md`)

```yaml
---
id: mod_NAME
type: module
status: in-progress
updated: YYYY-MM-DD
depends_on: []
blocks: []             # AUTO-COMPUTED by generate_memory_map.sh. Do NOT edit.
tags: []
---

# [Module Name]

## Current State
[Architecture overview. Exact mode for paths, config keys, version numbers.]

## Key Decisions
- [YYYY-MM-DD] Decision — rationale

## Cross-Module Connection Points

### To mod_<name>
- **Endpoint**: METHOD /path
- **Request**: `{ field: type }`
- **Response**: `{ field: type }`
- **Errors**: `CODE` Description
- **Constraints**: rate limits, idempotency

## Open Issues
- 

## Change Log
- [YYYY-MM-DD] Initial creation
```

---

## Feature Node (`feat_<name>.md`)

```yaml
---
id: feat_NAME
type: feature
status: in-progress
updated: YYYY-MM-DD
depends_on: []
blocks: []             # AUTO-COMPUTED by generate_memory_map.sh. Do NOT edit.
tags: []
---

# [Feature Name]

## Current State
[What's built, what's pending. Exact mode for endpoints, field names, config values.]

## Key Decisions
- [YYYY-MM-DD] Decision — why this over alternatives

## Cross-Module Connection Points

### To mod_<name>
- **Endpoint**: METHOD /path
- **Request**: `{ field: type }`
- **Response**: `{ field: type }`
- **Errors**: `CODE` Description
- **Constraints**: rate limits, idempotency

## Open Issues
- 

## Change Log
- [YYYY-MM-DD] Feature started
```

---

## Archive Entry (`meta/archive/<name>.md`)

```yaml
---
id: archived_NAME
type: feature
status: archived
updated: YYYY-MM-DD
depends_on: []
blocks: []             # AUTO-COMPUTED. Do NOT edit.
tags: []
---

# [Archived Feature Name]

## Why archived
[Reason: completed / superseded / abandoned]

## Key deliverables
[What was built / decided]

## Restore notes
[What would need to change to reactivate this node]

## Change Log
- [YYYY-MM-DD] Archived
```
