# BunDeal Implementation Roadmap

Status: Proposed after Phase 0  
Rule: Every phase ends with a review checkpoint and requires owner approval before the next major phase.

## Working method for every phase

At each checkpoint, provide:

1. Objective and completed scope.
2. Changed and newly created files.
3. Applied migrations in execution order.
4. Environment and secret changes without exposing values.
5. Automated tests and their actual results.
6. Manual verification steps and observed results.
7. Security considerations.
8. Known limitations and unresolved decisions.
9. Rollback or recovery notes.
10. Approval request for the next phase.

Do not report a command or migration as successful unless it was executed and verified.

## Phase 0 — Audit and architecture

### Objective

Understand the current project and define a safe target before backend work.

### Deliverables

- `PROJECT_AUDIT.md`
- `ARCHITECTURE.md`
- `IMPLEMENTATION_ROADMAP.md`
- GitHub branch `feature/bundeal-backend`

### Current result

- Frontend and presentation sources audited.
- Target architecture and schema proposed.
- Security and deployment risks documented.
- Live repository identified as `iBoraa61/bundeal`.
- Branch `feature/bundeal-backend` created from `main`.
- Phase 0 documents committed to the feature branch.
- Repository layout confirmed: GitHub Pages serves the repository root through `CNAME` `bundeal.de`.
- Partner files remain outside this repository.

### Approval gate

- Confirm architecture and root-level file layout.
- Resolve open attribution rules.
- Create a separate Supabase development project.

## Phase 1 — Technical foundation

### Objective

Create a reproducible, non-production Supabase foundation without changing the public product behavior.

### Files expected

- `.gitignore`
- `.env.example`
- `README.md`
- `supabase/config.toml`
- `supabase/migrations/<timestamp>_foundation.sql`
- `supabase/migrations/<timestamp>_rls_helpers.sql`
- `supabase/seed.sql`
- `supabase/tests/foundation.sql`
- `js/config.example.js`
- `js/config.js` or generated equivalent
- `js/supabase-client.js`

### Scope

- Connect the correct Git repository.
- Create and use `feature/bundeal-backend`.
- Configure Supabase CLI and local workflow.
- Connect only the dedicated development Supabase project.
- Create foundational enums/domains or check constraints.
- Create identity, role, merchant, category and audit foundations.
- Enable RLS immediately.
- Add safe public configuration.
- Document development and deployment commands.

### Tests

- Fresh local database reset from migrations.
- Seed execution.
- Anonymous access denied to protected tables.
- User cannot assign a role.
- Public deal-safe views expose no secrets.
- No service key exists in frontend files or Git history.

### Manual verification

- Existing German and English static pages still work.
- Development Supabase project is clearly labelled and separate.
- Public frontend can initialize the Supabase client without privileged access.

### Approval gate

Review every migration, RLS helper, environment variable name and test result before authentication work.

## Phase 2 — Authentication and profiles

### Objective

Implement secure user registration and account sessions.

### Files expected

- `login.html`
- `register.html`
- `reset-password.html`
- `dashboard.html`
- `js/auth.js`
- `js/utils.js`
- `supabase/migrations/<timestamp>_profiles_and_roles.sql`
- `supabase/migrations/<timestamp>_profile_rls.sql`
- authentication tests

### Scope

- Registration.
- Email verification according to development settings.
- Login and logout.
- Password reset.
- Session persistence.
- Profile creation trigger.
- Immutable server-generated referral code.
- Protected dashboard shell.
- User/admin role separation.

### Tests

- Registration and profile creation.
- Duplicate username and referral-code protection.
- User can read/update only permitted own profile fields.
- User cannot read another private profile.
- User cannot create or modify `admin` role.
- Password reset callback returns to an allowlisted URL.

### Approval gate

Inspect auth flows, RLS policies, role protection and browser storage behavior.

## Phase 3 — Deal management

### Objective

Replace hardcoded deal content with reviewed database-backed deals while preserving the current design.

### Files expected

- `deals.html`
- `deal.html`
- `submit-deal.html`
- `admin.html` moderation section
- `js/deals.js`
- `js/admin.js`
- deal/merchant/category/submission migrations
- deal RLS tests

### Scope

- Merchants and categories.
- Public published deal list.
- Public deal detail.
- User submission.
- Editing own pending submission.
- Admin review, rejection and publication.
- Safe product image handling.

### Tests

- Anonymous users see only published deals.
- Users cannot publish directly.
- Users can edit only their own pending submissions.
- Published deal records cannot expose raw secrets.
- Admin actions are authorized and audited.
- User-provided content is rendered safely.

### Approval gate

Review public fields, moderation flow, image policy and current UI parity.

## Phase 4 — Referral attribution

### Objective

Implement direct-only referral links with documented attribution behavior and no financial reward yet.

### Required owner decisions before implementation

- Attribution duration.
- First-click or last-click precedence.
- Whether referrer eligibility requires a confirmed purchase.
- Whether referral attribution can be replaced before purchase.
- Cross-device behavior.

### Files expected

- `js/referrals.js`
- `supabase/functions/resolve-referral/` or consolidated redirect function
- referral and attribution migrations
- referral security tests
- attribution decision record in documentation

### Scope

- Personal referral links.
- Opaque referral-code resolution.
- Direct referral attribution.
- Self-referral prevention.
- Referral statistics.
- Risk-event recording.
- No multi-level commission.

### Tests

- Self-referral rejected.
- Second-level relationship creates no upstream entitlement.
- Invalid and expired codes handled safely.
- Attribution precedence follows the approved rule.
- Referral clicks alone create no financial entries.

### Approval gate

Review attribution examples and fraud cases before affiliate transaction work.

## Phase 5 — Affiliate click and transaction tracking

### Objective

Create network-neutral outbound tracking and safe simulation/import flows.

### Files expected

- `js/tracking.js`
- `supabase/functions/affiliate-redirect/`
- `supabase/functions/affiliate-webhook/` only if supported
- `supabase/functions/import-transactions/`
- affiliate account/link/event/click/transaction migrations
- sample redacted CSV fixtures
- idempotency tests

### Scope

- Server-generated unique click reference.
- Validated redirect to an active approved affiliate link.
- Click logging.
- Strict simulation/live environment.
- Simulation event endpoint restricted to development/admin use.
- CSV fallback importer.
- Awin adapter shell based only on verified fields.
- Transaction status updates and returns.

### Tests

- Open redirect attempts rejected.
- Duplicate external event does not duplicate a transaction.
- Duplicate transaction ID in the same network account is rejected.
- Same external ID in a different account is handled according to scoped uniqueness.
- Frontend cannot create or convert a live transaction.
- Forged or unsigned webhook rejected where signatures exist.
- Simulation data cannot affect live records.

### Approval gate

Review approved Awin capabilities, mapping fixtures, stored raw data and redaction.

## Phase 6 — Cashback engine and deal rounds

### Objective

Implement deterministic 35/15/50 allocation, immutable ledger entries, reversals and monthly rounds.

### Required owner decisions before implementation

- Cashback release delay after confirmation.
- Final treatment of unassigned community allocation.
- Round closure timing and late-arriving transaction handling.
- Currency scope for pilot.

### Files expected

- `supabase/functions/process-commission/`
- `supabase/functions/reverse-commission/`
- commission-rule, commission, round, account, ledger and community-allocation migrations
- SQL reconciliation views
- financial unit and integration tests

### Scope

- Versioned 35/15/50 rule.
- Integer-cent calculation.
- Explicit rounding adjustment.
- Pending and available ledger states.
- Unassigned 15% community allocation.
- Atomic balance projection.
- Rejection handling.
- Compensating reversal entries.
- Round opening and closure.

### Tests

- €10.00 produces €3.50 / €1.50 / €5.00.
- Odd-cent amounts reconcile exactly.
- No eligible referrer creates a community allocation, not extra BunDeal revenue.
- Reprocessing the same transaction creates no duplicate credit.
- Full and partial reversals reconcile.
- Closed rounds reject silent new assignment.
- Concurrent processing cannot double-credit.
- Simulation entries never affect live projections.

### Approval gate

Review calculation fixtures, ledger rows, reconciliation report and reversal behavior line by line.

## Phase 7 — User dashboard

### Objective

Expose clear, user-owned account information without weakening financial security.

### Files expected

- `dashboard.html`
- `css/dashboard.css`
- `js/cashback.js`
- dashboard views or RPC migrations
- dashboard access tests

### Scope

- Profile.
- Estimated, pending, confirmed/available and reversed status explanations.
- Transaction history.
- Referral statistics.
- Submitted deals.
- Account settings.

### Tests

- Users see only their own records.
- Amount labels match source status.
- Estimated cashback is never displayed as guaranteed.
- Reversals remain visible in history.
- Empty states and network errors are accessible.

### Approval gate

Review dashboard wording, privacy and reconciliation against database values.

## Phase 8 — Admin dashboard

### Objective

Provide controlled operational tools without exposing service credentials to the browser.

### Files expected

- `admin.html`
- `css/admin.css`
- `js/admin.js`
- admin Edge Function operations
- admin read models and audit migrations
- authorization tests

### Scope

- Deal and submission moderation.
- User review without arbitrary role escalation.
- Affiliate event and transaction inspection.
- Commission and ledger reconciliation.
- Round control.
- Risk-event review.
- Payout-request preparation only.
- Audit-log access.

### Tests

- Regular users cannot access admin data or operations.
- Hiding the admin page is not the authorization mechanism.
- Every privileged mutation is validated and audited.
- Financial records cannot be manually overwritten.

### Approval gate

Review each admin capability, required role and audit event.

## Phase 9 — Pilot readiness

### Objective

Prove the complete simulation flow and prepare a controlled live pilot without enabling real payouts prematurely.

### Test scenarios

- Registration and password reset.
- Profile and referral-code creation.
- Deal submission, rejection and approval.
- Referral link and direct attribution.
- Self-referral rejection.
- Affiliate redirect and unique click reference.
- Simulated pending transaction.
- Confirmation and 35/15/50 allocation.
- Rejection.
- Full and partial return.
- Duplicate and replayed events.
- Closed monthly round.
- Unassigned community allocation.
- User and admin RLS.
- Simulation/live separation.
- Ledger/account reconciliation.

### Operational deliverables

- Known-limitations document.
- Incident and rollback procedure.
- Backup/restore verification.
- Secrets inventory.
- Data retention plan.
- Monitoring and alert plan.
- Affiliate approval evidence.
- Legal/tax review checklist.
- Go/no-go checklist.

### Pilot restriction

Do not enable real-money payouts until affiliate terms, legal structure, tax treatment, identity requirements, accounting and operational controls are approved.

## Prioritized next actions

1. Obtain the exact GitHub repository URL.
2. Connect or clone it without overwriting the current prototype.
3. Create `feature/bundeal-backend` from the deployed default branch.
4. Review and approve Phase 0 documents.
5. Decide the open referral-attribution rules.
6. Create a separate Supabase development project.
7. Begin Phase 1 only after explicit approval.
