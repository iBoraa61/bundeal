# BunDeal Live Readiness Checklist

Status: Phase 0 (2026-11-27)  
Purpose: Define when BunDeal is allowed to claim a real purchase and process live commission.  
Current overall result: **Not live-ready for money** (`PILOT.md` No-Go).

Legend: `[x]` done · `[ ]` open · `[~]` partial

---

## A. Product clarity

- [x] Three public modes exist: Cashback, Empfehlung, Creator  
- [x] Fourth mode: normal listing without cashback claim  
- [x] Cards show mode and shop price separately from cashback  
- [x] Public site states cashback only from confirmed commission  
- [~] Public site still says / behaves as purchase not fully live  
- [x] Per-merchant capability matrix visible in admin and enforced on publish  
- [x] Deal-creator reward left off by product decision (re-open only with advertiser yes)  

## B. Technical platform

- [x] Local Supabase migrations and RLS helpers  
- [x] Auth (register, login, reset) without self-serve admin role  
- [x] Deal submission + admin publish  
- [x] Server-side click + clickref  
- [x] Simulation commission → ledger → release path  
- [x] Creator campaigns gated by role + offer mode  
- [x] Admin operations snapshot (rounds, risks, payout_ready listing)  
- [ ] Production Supabase project separate from `bundeal-dev`  
- [ ] Automated backups + restore drill documented  
- [~] Monitoring for import runs, unmatched clicks, and open risks is visible in admin. No external alerting yet  
- [~] Awin sample dry-run exists. Live apply is refused. Production credentials are not configured  
- [ ] Published live cashback policy (e.g. 30 days) — not the 0-day pilot policy  

## C. Money safety

- [x] Integer cents  
- [x] Idempotent processing keys  
- [x] Append-only ledger + reversals  
- [x] Simulation / live split  
- [x] Unassigned referral share held as community reserve  
- [x] Browser cannot process live imports  
- [ ] No over-allocation possible under flexible future rates (sum = 10000 invariant tests)  
- [ ] Live commission processing runbook  
- [ ] Payout legal basis decided  
- [~] Payout marker exists for a simulation balance only. Live payout and bank transfer stay off  
- [ ] KYC / identity policy for payouts  

## D. Advertiser / network

- [~] Outreach in progress (Awin and others)  
- [~] Written cashback and referral answers are stored. The owner has not confirmed the matrix  
- [~] Written referral yes/no/pending is stored. No public Empfehlung was published for those programs  
- [ ] Written yes stored per merchant for creator campaign (if used)  
- [ ] No brand live with Empfehlung UI unless referral yes exists  
- [ ] Same brand not pitched on two networks  
- [ ] Amazon / AliExpress cashback left disabled (policy)  

## E. Legal / privacy / tax

- [x] Impressum and privacy pages exist  
- [ ] Counsel review of cashback / referral / creator wording  
- [ ] Cashback terms and referral terms published  
- [ ] Retention / deletion policy for accounts, clicks, ledger  
- [ ] Tax treatment decided for each reward type  
- [ ] Cookie / tracking consent if analytics added  
- [ ] Affiliate advertising disclosure where required  

## F. UX / community (can lag money, but needed for “full platform”)

- [x] Deal feed as home  
- [x] Mode legend and modern cards  
- [x] Search  
- [x] Filters / sort  
- [x] Category browse  
- [x] Old price / % off when data present  
- [x] Votes / temperature  
- [x] Comments + report  
- [x] Favorites  
- [ ] Email verification UX  

## G. Security

- [x] No service-role in frontend or git  
- [x] `js/config.js` gitignored  
- [x] RLS on sensitive tables  
- [x] Admin RPCs gated  
- [ ] Production secret rotation documented  
- [~] A signed-in user can post at most 10 comments an hour and 5 open comments on one deal. Click limits are still open  

## H. Go-live switches (owner-only)

Do not flip these until A–E critical items are green:

1. [ ] Remove “Kauf noch nicht möglich” as the global product state  
2. [ ] Allow `live` environment booking for approved merchants only  
3. [ ] Publish live cashback policy version  
4. [ ] Enable payout preparation → paid for real users  
5. [ ] Announce public launch  

---

## Minimum bar for first live offer (narrow launch)

A smaller first launch is allowed only if all of the following are true:

1. One merchant with written cashback yes (and referral yes only if mode is Empfehlung/Creator)  
2. Production backend + backups + import path for that network  
3. Live policy published  
4. Legal pages updated for accounts and cashback  
5. Purchase copy matches reality  
6. Payout may still be manual/admin-only, but users are not shown fake “payable” money  

If any item fails → keep simulation and public “not yet purchasable” wording.

---

## Sign-off

| Role | Name | Date | Result |
| --- | --- | --- | --- |
| Product owner | | | |
| Engineering | | | |
| Legal/tax (external) | | | |

Current engineering recommendation: **do not go live with money yet**. L5 can dry-run a sample. L6 and L7 switches stay off until this checklist is signed.
