# BunDeal Project Audit

Status: Phase 0 refresh  
Audit date: 2026-11-27  
Scope: Current repository after phases 1–9 simulation work, offer modes, and the public storefront rebuild

## Executive summary

BunDeal is no longer an empty landing-page prototype. The repository already contains a working local Supabase stack, versioned migrations, SQL tests through admin operations, a static storefront, auth, deal publish flow, click attribution, cashback ledger, creator campaigns, and an admin UI.

What is still missing for a real go-live with money:

- written advertiser approvals wired into per-merchant capabilities
- a flexible, per-merchant/per-deal payout matrix beyond the locked concept rates
- a “normal deal” mode without cashback claims
- community features (search, filters, votes, comments, favorites)
- real Awin (or other network) production import
- payout execution
- legal/tax decisions and a published 30-day cashback policy
- production monitoring and backups

Live money remains **No-Go** (`PILOT.md`). The public site at `https://bundeal.de/` may look like a marketplace, but a purchase and a payout are not enabled.

## A. Repository and deployment

- Live repo: `iBoraa61/bundeal`
- Public host: GitHub Pages from `main`, path `/`, `CNAME` `bundeal.de`
- Active development branch: `feature/bundeal-backend`
- Stack: static HTML/CSS/vanilla JS + Supabase (Auth, Postgres, RLS, RPCs)
- Local project id: `bundeal-dev`
- Browser may hold only URL + anon key in gitignored `js/config.js`
- Desktop folder `C:\Users\IBora\Desktop\BunDeal` is not the git repo

## B. What already exists

### Database and money path

| Area | Status |
| --- | --- |
| Profiles, roles (`user`, `admin`, `creator`) | Done |
| Merchants, categories, deals, submissions | Done |
| `offer_mode` (`cashback`, `referral`, `creator`) | Done |
| Direct referral attribution `direct-v1` | Done |
| Creator campaigns `creator-v1` | Done |
| Clickref / clicks / affiliate events / transactions | Done |
| Commission rules in basis points | Done (global versions, not per merchant) |
| Cashback ledger, accounts, community hold | Done |
| Simulation vs live split | Done |
| Admin operations snapshot / risk close | Done |
| SQL tests for foundation → admin | Done locally (see `PILOT.md`) |
| Real payouts | Not built |
| Live import from browser | Blocked by design |

Coded split today:

- Without campaign: **35 / 15 / 50** (buyer / direct referrer / BunDeal)
- With campaign: **35 / 15 / 10 / 40**
- Unassigned 15% stays community reserve (`held`), not BunDeal revenue
- Amounts are integer cents; processing is idempotent

### Frontend

| Page | Role |
| --- | --- |
| `index.html` / `index-en.html` | Deal feed with mode legend and deal cards |
| `deal.html` | Detail, mode badge, merchant CTA |
| `was-ist-bundeal.html` / `about-en.html` | Product explanation |
| Auth pages | Login, register, reset |
| `dashboard.html` | Own cashback, purchases, referrals, creator |
| `admin.html` | Merchants, deals, offer mode, tracking, cashback, ops, creators |
| Legal pages | Impressum / privacy DE+EN |

Deal cards already show merchant, title, excerpt, shop price, mode pill, and savings path. Product image URL is supported; demo deal has no image yet.

### Reusable components

- Brand assets and CSS design system
- One-row header + account menu
- Supabase client bootstrap without service role
- RPC-driven admin and booking path
- Attribution and cashback rules documents

## C. Gap analysis vs the full live product brief

The 2026-11-27 product brief asks for a Mydealz/Dealoo-style community platform with five deal types and per-merchant flexible rates. Against that brief:

### Already covered in substance

- Cashback deals
- Referral model (one level, after own purchase)
- Creator campaigns
- Admin moderation of submissions
- Server-side affiliate click + ledger
- Simulation environment

### Missing or only partial

1. **Normal deals** without cashback claims (new mode, e.g. `listing`)
2. **Deal-creator reward** from confirmed commission (explicitly deferred earlier; not coded)
3. **Per-merchant / per-program capability flags** (`cashback_allowed`, `referral_reward_allowed`, …)
4. **Per-merchant / per-deal configurable rates** (today: global versioned rules)
5. **Search, filters, sort, categories browse**
6. **Votes / temperature, comments, favorites, report**
7. **Profile images / Supabase Storage**
8. **Email verification UX**
9. **Awin production adapter** (CSV/API) with secrets outside the repo
10. **Payout rail** (admin prepare exists as listing only)
11. **Rich deal card fields** (old price, % off, temperature, comment count)
12. **Header IA** from the brief (search, categories, cashback, community, creator)

### Product conflicts that need an owner decision before coding

| Topic | Current locked behaviour | New brief |
| --- | --- | --- |
| Default money split | 35/15/50 concept, do not silently change | Fully flexible per merchant |
| Offer types | Cashback / Empfehlung / Creator | + Normal deal + creator-of-deal reward |
| Deal-creator share | Deferred; suggestions unpaid | Optional paid share when advertiser allows |
| Public claim | Purchase not possible; no payout | Go live with real users and money |

Phase 0 does **not** rewrite these locks. Later phases need explicit approval for each change.

## D. Risks

1. **Advertiser mismatch** — personal link often refused; showing Empfehlung without a written yes is a compliance risk.
2. **Money before law** — tax, payout legal basis, KYC, retention still open.
3. **Flexible rates without invariants** — can over-allocate >100% or reassign community reserve into BunDeal revenue.
4. **Community spam** — votes/comments without moderation costs.
5. **Secrets** — service role or network keys must never reach GitHub Pages.
6. **False live look** — storefront must not imply a working purchase or payable balance until enabled.
7. **Scope explosion** — rebuilding Mydealz fully before first approved live offer delays revenue.

## E. External dependencies

| Dependency | Need |
| --- | --- |
| Awin (and later others) | Approved publisher programs; cashback and referral answers stored per merchant |
| Advertiser written yes | Separate flags, not implied by program join |
| Legal/tax counsel | Cashback, referral, creator, payout |
| Production Supabase | Separate from `bundeal-dev`; backups; monitoring |
| Payment provider | Only after payout legal path exists |

## F. Recommendation for the path to live

Do **not** treat “live look” as “live money”.

Recommended sequence after Phase 0 approval:

1. Harden merchant capabilities and a **listing** (normal) deal mode.
2. Keep unpaid suggestions; leave deal-creator reward off until a written advertiser yes exists.
3. Wire approved partners (e.g. Guiders cashback GO, Wondershare both) into admin flags only — still no public purchase until legal checklist passes.
4. Add search/filter and stronger deal cards next.
5. Community votes/comments after the money path is safe.
6. Production Awin import + 30-day policy + monitoring before any live commission booking.
7. Payout last.

## G. Phase 0 deliverables

- This file
- `ARCHITECTURE.md`
- `IMPLEMENTATION_ROADMAP.md`
- `LIVE_READINESS_CHECKLIST.md`

Stop here for owner review. No implementation phase starts without approval.
