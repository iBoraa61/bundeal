# BunDeal Target Architecture

Status: Phase 0 refresh (2026-11-27)  
Stack: Static HTML/CSS/vanilla JS + Supabase (Auth, Postgres, RLS, RPCs)  
Rule: Prefer extending the existing system. Do not introduce React/Vue unless the owner explicitly changes the stack.

## 1. Architectural principles

1. Preserve the static storefront and extend it.
2. Treat every browser request as untrusted.
3. Auth in Supabase Auth; application identity in `profiles` / `user_roles`.
4. Enforce access with RLS; privileged work in security-definer RPCs.
5. Money as integer cents; EUR only until multi-currency is approved.
6. Financial history append-only; corrections via reversals.
7. Idempotent commission and release processing.
8. Hard split `simulation` vs `live`.
9. Version commission and attribution rules; never silently rewrite history.
10. One publisher commission to BunDeal; internal splits are BunDeal allocation after confirmation.
11. Show only capabilities the merchant/program actually allows.
12. No service-role key, affiliate secret, or payout credential in the frontend or git.

## 2. System context

```text
Browser (GitHub Pages / local static server)
  ├─ public HTML/CSS/assets
  ├─ Supabase Auth + anon client
  ├─ RLS-constrained reads
  └─ authenticated RPC calls

Supabase
  ├─ Auth
  ├─ PostgreSQL + RLS
  ├─ security-definer RPCs (booking, click, admin)
  ├─ Storage (optional images; not required for MVP live)
  └─ Edge Functions (optional; current booking path is DB RPCs)

Affiliate networks (Awin first)
  ├─ outbound tracked URLs (server-held destinations)
  ├─ reports / CSV / approved APIs
  └─ clickref / subid mapped to BunDeal click ids

Admin
  └─ static admin UI + server-authorized RPCs
```

## 3. Trust boundaries

### Browser may hold

- Supabase URL
- anon/publishable key
- public deal content
- user session

### Browser must never hold

- service-role key
- network API credentials
- ability to confirm commissions
- ability to mark balances paid
- ability to process `live` imports

### PostgreSQL owns

- click creation and clickref
- attribution eligibility
- commission split
- ledger posts and reversals
- admin capability checks

## 4. Current domain model (implemented)

Core tables already in migrations:

- `profiles`, `user_roles`
- `merchants`, `deal_categories`, `deals`, `deal_submissions`
- `attribution_rules`, `referrals`, `referral_attributions`, `risk_events`
- `affiliate_accounts`, `affiliate_links`, `deal_rounds`, `clicks`, `affiliate_events`, `transactions`
- `commission_rules`, `cashback_policies`, `commissions`
- `cashback_accounts`, `cashback_ledger`, `community_allocations`
- `creator_campaigns`, `creator_applications`
- `audit_logs`

Public read path: view `public_deals` (no affiliate destination).

Offer modes on `deals.offer_mode`:

| Mode | Buyer cashback | Personal referral after own purchase | Creator campaign |
| --- | --- | --- | --- |
| `cashback` | yes | no | no |
| `referral` | yes | yes | no |
| `creator` | yes | yes | yes |

Enforcement: BEFORE INSERT triggers on clicks, attributions, campaigns.

## 5. Target extensions (approved only after Phase 0 gate)

### 5.1 Merchant / program capabilities

Add a capabilities record per merchant or affiliate program (admin-only), for example:

- `listing_allowed`
- `affiliate_tracking_allowed`
- `cashback_allowed`
- `referral_reward_allowed`
- `creator_campaign_allowed`
- `deal_creator_reward_allowed` (default false; unpaid suggestions remain the default product rule)
- channel notes, approval notes, approval date

Joining a network program must **not** auto-enable cashback, referral, or creator rewards.

### 5.2 Offer mode `listing` (normal deal)

A fourth public mode for Mydealz-style offers:

- shop price and deal info only
- BunDeal may still use its affiliate link if tracking is allowed
- UI must not promise cashback, referral bonus, or creator share

### 5.3 Configurable rates

Keep versioned rules. Extend so a deal or merchant can select a rule version rather than hard-coding 35/15/50 in application logic.

Invariants that must remain coded:

- basis points sum to 10000 including any creator share
- never pay from open/pending commission
- unassigned referral share stays community reserve unless a future explicit rule says otherwise
- no multi-level referral
- no double pay for the same bucket on the same commission

The concept example 35/15/50 stays the default seed until the owner publishes a new version.

### 5.4 Deal-creator reward

Only if explicitly approved later:

- separate ledger bucket
- only when `deal_creator_reward_allowed` is true for that merchant/program
- never auto-enabled by submission alone
- unpaid suggestion remains the default

### 5.5 Community layer

New tables only when that phase starts:

- `deal_votes` / temperature aggregate
- `comments` (+ report)
- `favorites`

Moderation hooks go through admin RPCs and audit logs.

### 5.6 Network adapters

Keep `affiliate_events` + `import_affiliate_events` as the ingestion boundary.

Awin adapter (future):

- maps Awin transaction fields → BunDeal event rows
- uses clickref already issued by `begin_affiliate_click`
- runs with service role / scheduled job, never from the public browser for `live`

## 6. Money flow (unchanged shape)

```text
User login → begin_affiliate_click → network
Network reports transaction → import → match click
Confirm commission → process_commission → ledger pending
Policy delay → release_due_cashback → available
Admin prepares payout list → (future) paid marker
Return/cancel → reverse_commission
```

Statuses conceptually: pending → approved/available → payable → paid, plus rejected/reversed.

## 7. Frontend information architecture (target)

Keep one-row header. Evolve labels carefully:

- Deals (home feed)
- Search (phase)
- Categories (phase)
- Was ist BunDeal
- Suggest
- Account
- Admin (role)

Avoid a marketing hero that pushes deals below the fold. The home page stays a deal feed.

Deal cards:

- image or placeholder
- merchant · category
- title, short excerpt
- shop price (and later: old price / % off when data exists)
- mode pill
- savings path text only when cashback/referral/creator applies
- no confusion between shop discount and BunDeal cashback

## 8. Security architecture

- RLS on all sensitive tables
- column grants for public-safe deal fields
- `is_admin()` security definer
- creator role cannot self-assign; application + admin review
- append-only ledger trigger
- simulation release/import allowed for admin; live processing service-role only
- secrets via env / ignored local config only

## 9. Environments

| Env | Purpose |
| --- | --- |
| Local `bundeal-dev` | Simulation, SQL tests, UI work |
| Public GitHub Pages | Static UI; may point at no backend or a future non-money preview |
| Production Supabase | Only after live checklist; separate secrets and backups |

## 10. Non-goals for the next implementation slice

- Payment-provider auto payout
- Multi-level MLM
- Amazon/AliExpress cashback (policy forbidden)
- Rewriting the stack to React
- Claiming live purchase while legal/advertiser gates fail
