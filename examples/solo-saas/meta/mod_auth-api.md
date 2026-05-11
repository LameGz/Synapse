---
id: mod_auth-api
type: module
status: stable
updated: 2026-05-11
summary: "Authentication API contracts for login and token refresh."
depends_on: []
auto_linked: []
tags: [auth, api, login]
aliases: [authentication, signin]
---

# Auth API

## Current State
- `POST /api/v1/auth/login` accepts `{ email: string, password: string }` and returns `{ access_token: string, refresh_token: string, expires_in: 900 }`.
- `POST /api/v1/auth/refresh` accepts `{ refresh_token: string }` and returns `{ access_token: string, expires_in: 900 }`.
- `access_token` TTL is `900` seconds.

## Key Decisions
- [2026-05-11] Keep refresh token handling in the API module so frontend login can depend on one stable contract.

## Cross-Module Connection Points

### To feat_login
- **Endpoint**: `POST /api/v1/auth/login`
- **Request**: `{ email: string, password: string }`
- **Response**: `{ access_token: string, refresh_token: string, expires_in: 900 }`
- **Errors**:
  - `401` Invalid credentials
- **Constraints**: `access_token` expires after `900` seconds.

## Open Issues
None.

## Change Log
- [2026-05-11] Initial solo SaaS auth API example.
