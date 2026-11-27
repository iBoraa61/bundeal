# BunDeal Implementation Roadmap

Status: Phase 0 refresh (2026-11-27)  
Rule: Every phase ends with an owner checkpoint. Do not start the next major phase without approval.  
Rule: Do not enable live money, payouts, or `db reset` unless the owner explicitly asks.

## Working method

At each checkpoint provide:

1. Objective and completed scope  
2. Changed files  
3. Migrations applied (in order)  
4. Tests run and results  
5. Manual browser checks  
6. Security notes  
7. Open decisions  
8. Approval request for the next phase  

Do not mark a command successful unless it was executed.

## Progress map (honest)

| Roadmap id | Name | State |
| --- | --- | --- |
| 0 | Audit / architecture | **This refresh — awaiting approval** |
| 1 | Technical foundation | Done (local Supabase, RLS, config pattern) |
| 2 | Auth / profiles / roles | Done |
| 3 | Deals / submissions / publish | Done |
| 4 | Direct referral | Done |
| 5 | Clickref / import / rounds | Done |
| 6 | Cashback ledger | Done (simulation) |
| 7 | Creator campaigns + role | Done |
| 8 | Dashboards | Done (user + admin ops listing) |
| 9 | Pilot review | Done — **Live money No-Go** (`PILOT.md`) |
| A | Storefront + offer modes | Done locally and published to Pages |
| L1+ | Live product completion | **Not started — see below** |

The original phases 1–9 are complete for a **simulation platform**. The work below is the remaining path toward a **real live product**, not a redo of phases 1–9.

---

## Phase 0 — Audit refresh (current)

### Deliverables

- `PROJECT_AUDIT.md`
- `ARCHITECTURE.md`
- `IMPLEMENTATION_ROADMAP.md`
- `LIVE_READINESS_CHECKLIST.md`

### Approval gate

Confirm:

1. Keep static HTML + Supabase (no framework rewrite).  
2. Keep unpaid suggestions by default; deal-creator reward stays off until a later yes.  
3. Add `listing` (normal deal) as the next mode after Cashback / Empfehlung / Creator.  
4. Per-merchant capability flags before flexible public rates.  
5. Live purchase stays off until the live checklist is green.  

**Stop here until the owner approves.**

---

## Phase L1 — Merchant capabilities and listing deals

### Objective

Make the mixed system real at the data model: every merchant/program has explicit flags; deals can be normal listings without cashback claims.

### Scope

- Admin-managed capability flags (cashback, referral, creator, listing, tracking)
- Approval notes / date fields
- New `offer_mode = listing` (or equivalent) with UI that promises no cashback
- Publish/review flows refuse modes the merchant does not allow
- Keep existing 35/15/50 default rule versions unchanged unless a new version is published

### Out of scope

- Deal-creator reward ledger  
- Flexible arbitrary rate UI for every deal  
- Community votes/comments  

### Tests

- Cashback-only merchant cannot publish `referral` / `creator`  
- Listing deal never creates referral attribution or cashback estimate promise  
- Existing kopfhoerer referral behaviour still works  

### Approval gate

Owner reviews admin UX and public listing card copy.

---

## Phase L2 — Storefront depth (Mydealz-style cards without fake money)

### Objective

Richer deal feed and detail without implying payouts.

### Scope

- Search and basic filters (category, mode, merchant)
- Optional old price + computed % off when `original_price_cents` is set
- Stronger empty and loading states
- Category chips
- Image upload path or strict HTTPS image URL validation (Storage optional)

### Out of scope

- Votes/comments  
- Live Awin API  

### Approval gate

Mobile + desktop review of feed and detail.

---

## Phase L3 — Wire approved partners (still no live money)

### Objective

Store real advertiser decisions and prepare offers without enabling purchase.

### Scope

- Record written answers per merchant/program (cashback yes/no, referral yes/no)
- Map known answers (examples from outreach: Finanzguru cashback-only; 123.live cashback-only; Guiders cashback GO pending referral; Wondershare both)
- Admin checklist before flipping a deal from draft/simulation to public listing
- Public copy remains “Kauf noch nicht möglich” until L6

### Approval gate

Owner confirms partner matrix accuracy.

---

## Phase L4 — Community layer (optional before money)

### Objective

Add engagement only if owner wants traffic mechanics before first paid offer.

### Scope

- Votes / temperature  
- Comments + report  
- Favorites  
- Moderation in admin  

### Risk

Spam and moderation load before revenue. Prefer after first approved live offer if resources are tight.

### Approval gate

Explicit owner choice: do L4 now or after L6.

---

## Phase L5 — Production affiliate ingestion

### Objective

Replace simulation-only imports for production with a real Awin path.

### Scope

- Document exact Awin fields used (clickref / transaction id / commission / status)
- Service-role importer or scheduled job
- Idempotent upsert into `affiliate_events`
- Monitoring: failed import, unmatched clicks, open risks
- Never process live from the public browser

### Approval gate

Dry-run against sample Awin export in simulation, then production credentials in env only.

---

## Phase L6 — Live money readiness

### Objective

Enable confirmed-commission booking in `live` only after checklist green.

### Scope

- Publish 30-day (or counsel-approved) cashback policy version  
- Production Supabase project, backups, restore drill  
- Monitoring / alerting for import + reconciliation  
- Legal pages and cashback/referral terms reviewed  
- Explicit owner flip: “purchase possible” copy  
- Payout remains admin-prepared, not auto-sent, until payment provider + KYC decided  

### Approval gate

`LIVE_READINESS_CHECKLIST.md` all critical items green.

---

## Phase L7 — Payout execution (later)

### Objective

Mark and execute payouts.

### Scope

- Payment provider or manual SEPA process  
- KYC / identity checks as required by counsel  
- `paid` markers with audit  
- User-visible payout history  

### Approval gate

Legal + tax sign-off.

---

## Phase L8 — Deal-creator reward (only if still desired)

### Objective

Optional share for the user who submitted a deal, when a merchant explicitly allows it.

### Preconditions

- Written advertiser yes for this reward  
- Owner overrides the earlier “unpaid suggestions” product default  

### Scope

- Capability flag + ledger bucket  
- No payment for merely submitting; only confirmed commission  
- Clear UI separation from referral and creator-campaign shares  

---

## Explicit non-goals until approved

- Framework rewrite  
- Amazon / AliExpress cashback deals  
- Multi-level referrals  
- Auto-enabling referral because cashback was allowed  
- Showing test commissions as real payable money  
- Pushing secrets to GitHub Pages  

## Immediate next step after Phase 0 approval

Start **Phase L1** (merchant capabilities + listing deals). Do not jump to community or payouts first.
