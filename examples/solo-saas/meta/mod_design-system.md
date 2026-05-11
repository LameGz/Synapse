---
id: mod_design-system
type: module
status: stable
updated: 2026-05-11
summary: "Shared UI tokens and reusable login form components."
depends_on: []
auto_linked: []
tags: [ui, design-system, frontend]
aliases: [components, styling]
---

# Design System

## Current State
- Primary color is `#2563EB`.
- Button radius is `8px`.
- Login form uses `TextField`, `PasswordField`, and `PrimaryButton`.
- Error text color is `#DC2626`.

## Key Decisions
- [2026-05-11] Keep form primitives in the design system so product features only compose validated UI pieces.

## Cross-Module Connection Points

### To feat_login
- **Shared component**: `PrimaryButton`
- **Shared component**: `TextField`
- **Shared component**: `PasswordField`
- **Constraints**: Login page should use `#DC2626` for authentication error feedback.

## Open Issues
None.

## Change Log
- [2026-05-11] Initial solo SaaS design-system example.
