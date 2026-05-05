---
id: mod_auth-api
type: module
status: stable
updated: 2026-05-01
summary: "Authentication endpoints and session management. Stateless JWT."
depends_on:
  - meta/mod_project.md
tags: [auth, api, security]
aliases: [login, signin, session]
---

# Auth API Module

## Current State
JWT-based auth with refresh tokens.
- Access token expiry: 15 min
- Refresh token expiry: 7 days
- Algorithm: RS256 (asymmetric)

## Key Decisions
- 2026-04-20 RS256 over HS256 — allows key rotation without invalidating all sessions

## Cross-Module Connection Points
- POST /api/v1/auth/session — consumed by feat_checkout (checkout requires login)
- POST /api/v1/auth/refresh — consumed by frontend middleware

## Open Issues
- None

## Change Log

- [2026-05-01] **Context**: Security review
  **Change**: Switched from HS256 to RS256
  **Impact**: All existing sessions invalidated; clients must re-login
  **Affected**: mod_project
