---
id: feat_login
type: feature
status: in-progress
updated: 2026-05-11
summary: Solo SaaS login page wired from natural-language memory ingestion.
depends_on: []
auto_linked:
  - meta/mod_auth-api.md
  - meta/mod_design-system.md
tags:
  - login
  - auth
  - frontend
aliases:
  - signin
---

# Login Feature

## Current State
- 登录页面调用 `POST /api/v1/auth/login`。
- 成功后保存 `access_token` 和 `refresh_token`。
- 后端返回 `expires_in: 900`。
- 页面使用 `TextField`, `PasswordField`, and `PrimaryButton`。

## Key Decisions
- [2026-05-11] Machine-suggested edges are stored in `auto_linked` so the user does not hand-write `depends_on` during natural-language ingestion.

## Cross-Module Connection Points

### To mod_auth-api
- **Endpoint**: `POST /api/v1/auth/login`
- **Request**: `{ email: string, password: string }`
- **Response**: `{ access_token: string, refresh_token: string, expires_in: 900 }`
- **Errors**:
  - `401` Invalid credentials
- **Constraints**: Store `refresh_token` only after a successful login response.

### To mod_design-system
- **Shared component**: `TextField`
- **Shared component**: `PasswordField`
- **Shared component**: `PrimaryButton`
- **Constraints**: Authentication errors use `#DC2626`.

- **Auto-linked** `meta/mod_auth-api.md`: exact endpoint match: POST /api/v1/auth/login; tag/alias overlap: api, auth, login
## Open Issues
None.

## Change Log
- [2026-05-11] **Context**: Natural-language memory ingestion
  - **Change**: 登录页面调用 `POST /api/v1/auth/login` and stores `access_token` / `refresh_token`.
  - **Impact**: Creates explainable Auto-Link candidates to auth API and design system modules.
  - **Affected**: meta/feat_login.md
