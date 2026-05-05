---
id: mod_project
type: module
status: stable
updated: 2026-05-05
summary: "E-commerce demo project. Entry point for new sessions."
depends_on: []
tags: [project, overview]
aliases: [demo, shop]
---

# Demo E-Commerce Project

## Current State
Tech stack: Next.js 14 + TypeScript, Express.js API, PostgreSQL 15.
Root: http://localhost:3000
API base: /api/v1

## Key Decisions
- 2026-04-20 JWT over session auth — stateless, works with mobile clients
- 2026-04-25 Stripe for payment processing — PCI compliance handled by Stripe

## Cross-Module Connection Points
- Auth API: POST /api/v1/auth/session, POST /api/v1/auth/refresh
- Payment API: POST /api/v1/payments/intent, webhook /api/v1/payments/stripe
- Checkout API: POST /api/v1/checkout/start, GET /api/v1/checkout/status/:id

## Open Issues
- [PENDING] Checkout timeout handling — see feat_checkout

## Change Log

- [2026-05-05] **Context**: Project initialization
  **Change**: Added checkout feature with Stripe integration
  **Impact**: New feat_checkout node linked to mod_auth-api and mod_payment
  **Affected**: feat_checkout, mod_payment, mod_auth-api
