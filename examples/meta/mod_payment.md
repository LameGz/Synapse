---
id: mod_payment
type: module
status: stable
updated: 2026-05-03
summary: "Stripe payment integration. PCI compliance handled by Stripe."
depends_on:
  - meta/mod_project.md
tags: [payment, stripe, billing]
aliases: [billing, charge]
---

# Payment Module

## Current State
Stripe Checkout integration.
- Webhook endpoint: /api/v1/payments/stripe
- Supported methods: card, Apple Pay, Google Pay
- Currency: USD only (hardcoded)

## Key Decisions
- 2026-04-25 Stripe Checkout over Stripe Elements — less PCI burden

## Cross-Module Connection Points
- POST /api/v1/payments/intent — consumed by feat_checkout
- Webhook /api/v1/payments/stripe — updates order status, consumed by feat_checkout

## Open Issues
- [PENDING] Support EUR and GBP

## Change Log

- [2026-05-03] **Context**: Currency expansion prep
  **Change**: Refactored intent creation to accept currency param (still defaults to USD)
  **Impact**: feat_checkout can now pass currency; actual support requires Stripe config change
  **Affected**: feat_checkout
