---
id: feat_checkout
type: feature
status: in-progress
updated: 2026-05-05
summary: "Checkout flow with Stripe payment and auth gating."
depends_on:
  - meta/mod_project.md
  - meta/mod_auth-api.md
  - meta/mod_payment.md
tags: [checkout, payment, frontend]
aliases: [cart, order]
---

# Checkout Feature

## Current State
Two-step checkout:
1. POST /api/v1/checkout/start — creates order, returns client_secret
2. Frontend redirects to Stripe Checkout
3. Webhook updates order status

Timeout: 30 min for abandoned checkouts (Stripe session expiry).

## Key Decisions
- 2026-05-05 Stripe Checkout hosted page — less frontend complexity

## Cross-Module Connection Points
- Calls POST /api/v1/auth/session (mod_auth-api) — requires login before checkout
- Calls POST /api/v1/payments/intent (mod_payment) — creates payment intent
- Receives webhook from /api/v1/payments/stripe (mod_payment) — updates order status

## Open Issues
- [PENDING] Timeout handling for abandoned carts — currently relies on Stripe 30-min expiry, need cleanup job
- [PENDING] Guest checkout — currently requires auth, losing ~15% of conversions

## Change Log

- [2026-05-05] **Context**: Initial implementation
  **Change**: Created checkout flow with Stripe integration
  **Impact**: New feature node linking auth and payment modules
  **Affected**: mod_auth-api, mod_payment
