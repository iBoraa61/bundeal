# BunDeal Target Architecture

Status: Proposed in Phase 0; no backend has been implemented  
Architecture: Static HTML/CSS/Vanilla JavaScript + Supabase

## 1. Architectural principles

1. Preserve the existing frontend and extend it progressively.
2. Treat every browser request as untrusted.
3. Keep authentication in Supabase Auth and application identity in `profiles`.
4. Enforce data access with PostgreSQL Row Level Security.
5. Execute privileged and financial operations in Edge Functions or database functions with explicit authorization.
6. Store money as integer minor units with an ISO currency.
7. Keep financial history append-only.
8. Make affiliate event processing idempotent.
9. Separate simulation and live data at the database boundary.
10. Version financial and attribution rules instead of silently changing them.
11. Keep affiliate-network adapters modular and do not assume unverified Awin capabilities.

## 2. System context

```text
Browser on GitHub Pages
  ├─ public HTML/CSS/assets
  ├─ Supabase Auth client
  ├─ RLS-constrained data reads/writes
  └─ calls public Edge Function endpoints

Supabase development project
  ├─ Auth
  ├─ PostgreSQL
  ├─ Row Level Security
  ├─ Edge Functions
  ├─ Storage (optional product images)
  ├─ Cron/scheduled jobs (only when needed)
  └─ logs and project secrets

Affiliate networks
  ├─ tracked outbound URLs
  ├─ reports, CSV files or approved APIs
  └─ webhooks only where actually supported

Administrator
  └─ static admin UI backed by server-authorized operations
```

## 3. Trust boundaries

### Public browser

May contain:

- Supabase project URL.
- Supabase publishable/anon key.
- Public deal content.
- Auth session managed by the Supabase client.

Must never contain:

- Service-role key.
- Affiliate API credentials.
- Webhook secrets.
- Admin credentials.
- Trusted financial values.
- Ability to select the `live` environment for transaction processing.

### Edge Functions

Responsible for:

- Affiliate redirect and click-reference creation.
- Validating and recording inbound affiliate events.
- CSV import validation.
- Commission processing.
- Cashback allocation.
- Reversals.
- Privileged admin mutations.
- Rate limiting for high-risk actions.

### PostgreSQL

Responsible for:

- Constraints and referential integrity.
- RLS.
- Atomic transactions.
- Uniqueness and idempotency guarantees.
- Append-only financial records.
- Role checks used by policies and privileged functions.

## 4. Recommended application structure

The deployed frontend stays at the repository root. New pages and scripts are added beside the existing files. A nested `site/` directory would break the current GitHub Pages deployment.

```text
bundeal/
├─ index.html
├─ index-en.html
├─ deals.html
├─ deal.html
├─ login.html
├─ register.html
├─ reset-password.html
├─ dashboard.html
├─ submit-deal.html
├─ admin.html
├─ beispiel-take3.html
├─ example-en.html
├─ impressum.html
├─ legal-notice-en.html
├─ datenschutz.html
├─ privacy-en.html
├─ css/
│  ├─ styles.css
│  ├─ dashboard.css
│  └─ admin.css
├─ js/
│  ├─ config.example.js
│  ├─ config.js
│  ├─ supabase-client.js
│  ├─ auth.js
│  ├─ deals.js
│  ├─ referrals.js
│  ├─ tracking.js
│  ├─ cashback.js
│  ├─ admin.js
│  ├─ utils.js
│  └─ site.js
├─ assets/
├─ CNAME
├─ supabase/
│  ├─ config.toml
│  ├─ migrations/
│  ├─ functions/
│  │  ├─ affiliate-redirect/
│  │  ├─ affiliate-webhook/
│  │  ├─ import-transactions/
│  │  ├─ process-commission/
│  │  ├─ reverse-commission/
│  │  └─ admin-operation/
│  ├─ seed.sql
│  └─ tests/
├─ .env.example
├─ .gitignore
├─ README.md
├─ PROJECT_AUDIT.md
├─ ARCHITECTURE.md
└─ IMPLEMENTATION_ROADMAP.md
```

Files should be added only in the phase that needs them. A separate Edge Function for every trivial action is unnecessary.

## 5. Proposed database schema

All primary keys should be UUIDs unless a strong reason exists otherwise. Timestamps should use `timestamptz`. Money uses `bigint` minor units plus a three-letter currency code. Public identifiers must not reveal sequential internal IDs.

### Identity and authorization

#### `profiles`

- `id uuid primary key references auth.users(id) on delete cascade`
- `username text unique`
- `display_name text`
- `referral_code text not null unique`
- `avatar_url text`
- `created_at timestamptz not null`
- `updated_at timestamptz not null`

Rules:

- Referral codes are generated server-side.
- Codes are immutable after issuance.
- Store and compare a canonical lowercase form.
- A new-auth-user trigger may create the profile, but it must not accept a role from user metadata.

#### `user_roles`

- `user_id uuid not null references auth.users(id) on delete cascade`
- `role text not null check (role in ('user', 'admin'))`
- `created_at timestamptz not null`
- Primary key: `(user_id, role)`

Only service-role or a tightly controlled administrative database function may modify this table.

### Merchants and categories

#### `merchants`

- `id uuid primary key`
- `name text not null`
- `slug text not null unique`
- `website_url text not null`
- `status text not null`
- `created_at timestamptz not null`
- `updated_at timestamptz not null`

This table is required because several proposed tables reference `merchant_id`.

#### `deal_categories`

- `id uuid primary key`
- `name text not null`
- `slug text not null unique`
- `created_at timestamptz not null`

### Deals and moderation

#### `deals`

- `id uuid primary key`
- `slug text not null unique`
- `title text not null`
- `description text not null`
- `product_image_url text`
- `merchant_id uuid not null references merchants(id)`
- `category_id uuid references deal_categories(id)`
- `original_price_cents bigint`
- `current_price_cents bigint not null`
- `currency char(3) not null`
- `cashback_estimate_cents bigint`
- `cashback_estimate_label text`
- `status text not null`
- `created_by uuid not null references auth.users(id)`
- `approved_by uuid references auth.users(id)`
- `published_at timestamptz`
- `created_at timestamptz not null`
- `updated_at timestamptz not null`

Do not make a raw affiliate URL publicly selectable from this table. Public deal pages should use a BunDeal redirect endpoint.

#### `deal_submissions`

- `id uuid primary key`
- `submitted_by uuid not null references auth.users(id)`
- `deal_id uuid references deals(id)`
- `proposed_title text not null`
- `proposed_description text not null`
- `proposed_url text not null`
- `proposed_price_cents bigint`
- `currency char(3)`
- `submission_status text not null`
- `admin_comment text`
- `created_at timestamptz not null`
- `updated_at timestamptz not null`
- `reviewed_at timestamptz`
- `reviewed_by uuid references auth.users(id)`

A submission must exist independently before an approved `deals` row is created. Users may update only their own pending submissions.

### Affiliate configuration

#### `affiliate_accounts`

- `id uuid primary key`
- `network text not null`
- `account_reference text not null`
- `environment text not null`
- `active boolean not null`
- Unique: `(network, account_reference, environment)`

No credentials are stored here. Secrets stay in Supabase project secrets.

#### `affiliate_links`

- `id uuid primary key`
- `deal_id uuid not null references deals(id)`
- `merchant_id uuid not null references merchants(id)`
- `affiliate_account_id uuid not null references affiliate_accounts(id)`
- `affiliate_url text not null`
- `tracking_configuration jsonb not null`
- `active boolean not null`
- `created_at timestamptz not null`
- `updated_at timestamptz not null`

`tracking_configuration` may describe approved parameter mappings, but never contain secrets.

### Referral relationships and attribution

#### `referrals`

- `id uuid primary key`
- `referrer_user_id uuid not null references auth.users(id)`
- `referred_user_id uuid not null references auth.users(id)`
- `referral_code text not null`
- `attribution_status text not null`
- `attributed_at timestamptz not null`
- `created_at timestamptz not null`

Constraints:

- `referrer_user_id <> referred_user_id`.
- One active acquisition referrer per referred user.
- Referral relationship creation is server-controlled.

This table represents the user acquisition relationship. It is not proof of a purchase.

#### `referral_attributions`

- `id uuid primary key`
- `deal_id uuid not null references deals(id)`
- `referrer_user_id uuid not null references auth.users(id)`
- `buyer_user_id uuid not null references auth.users(id)`
- `source_click_id uuid`
- `status text not null`
- `rule_version text not null`
- `expires_at timestamptz`
- `created_at timestamptz not null`

This table captures deal/purchase referral attribution separately from the account-acquisition relationship.

### Click tracking

#### `clicks`

- `id uuid primary key`
- `click_ref text not null unique`
- `user_id uuid not null references auth.users(id)`
- `deal_id uuid not null references deals(id)`
- `affiliate_link_id uuid not null references affiliate_links(id)`
- `referrer_user_id uuid references auth.users(id)`
- `affiliate_network text not null`
- `environment text not null check (environment in ('simulation', 'live'))`
- `clicked_at timestamptz not null`
- `ip_risk_hash text`
- `user_agent_risk_hash text`

Only minimum fraud signals should be retained, preferably short-lived and hashed with a rotating server-side secret. No email, username or other personal data goes into network tracking parameters.

### Deal rounds

#### `deal_rounds`

- `id uuid primary key`
- `deal_id uuid not null references deals(id)`
- `period_start timestamptz not null`
- `period_end timestamptz not null`
- `round_status text not null`
- `environment text not null`
- `created_at timestamptz not null`
- `closed_at timestamptz`
- Unique: `(deal_id, period_start, environment)`
- Check: `period_end > period_start`

Only an open round may receive a newly reported transaction. Closing a round is an explicit privileged operation.

### Raw affiliate events and transactions

#### `affiliate_events`

- `id uuid primary key`
- `affiliate_account_id uuid not null references affiliate_accounts(id)`
- `network text not null`
- `environment text not null`
- `external_event_id text`
- `event_type text not null`
- `payload jsonb not null`
- `payload_hash text not null`
- `received_at timestamptz not null`
- `processed_at timestamptz`
- `processing_status text not null`
- `error_code text`
- Unique idempotency key appropriate to network/account/environment

Raw events provide an audit trail. Sensitive fields should be redacted before storage and retained only as long as operationally necessary.

#### `transactions`

- `id uuid primary key`
- `affiliate_account_id uuid not null references affiliate_accounts(id)`
- `external_transaction_id text not null`
- `user_id uuid references auth.users(id)`
- `deal_id uuid not null references deals(id)`
- `deal_round_id uuid not null references deal_rounds(id)`
- `click_id uuid references clicks(id)`
- `referral_attribution_id uuid references referral_attributions(id)`
- `affiliate_network text not null`
- `order_amount_cents bigint`
- `commission_amount_cents bigint not null`
- `currency char(3) not null`
- `transaction_status text not null`
- `environment text not null`
- `transaction_date timestamptz not null`
- `confirmed_at timestamptz`
- `created_at timestamptz not null`
- `updated_at timestamptz not null`
- Unique: `(affiliate_account_id, external_transaction_id, environment)`

Live rows may be created or status-changed only by authorized server-side import paths.

### Financial rules and allocations

#### `commission_rules`

- `id uuid primary key`
- `version text not null unique`
- `basic_cashback_basis_points integer not null`
- `referral_bonus_basis_points integer not null`
- `platform_basis_points integer not null`
- `effective_from timestamptz not null`
- `effective_to timestamptz`
- `active boolean not null`
- `created_at timestamptz not null`

Initial values are 3500, 1500 and 5000 basis points. Published rules are immutable.

#### `commissions`

- `id uuid primary key`
- `transaction_id uuid not null unique references transactions(id)`
- `rule_id uuid not null references commission_rules(id)`
- `gross_commission_cents bigint not null`
- `basic_cashback_cents bigint not null`
- `referral_bonus_cents bigint not null`
- `unassigned_community_cents bigint not null`
- `bundeal_revenue_cents bigint not null`
- `rounding_adjustment_cents bigint not null`
- `commission_status text not null`
- `processed_at timestamptz`
- `created_at timestamptz not null`
- `updated_at timestamptz not null`

Checks must guarantee non-negative values and exact reconciliation to gross commission.

### Cashback accounts and ledger

#### `cashback_accounts`

- `user_id uuid primary key references auth.users(id)`
- `currency char(3) not null`
- `pending_balance_cents bigint not null`
- `available_balance_cents bigint not null`
- `reserved_balance_cents bigint not null`
- `updated_at timestamptz not null`

This is a transactional projection for efficient reads, not the source of truth.

#### `cashback_ledger`

- `id uuid primary key`
- `user_id uuid not null references auth.users(id)`
- `transaction_id uuid references transactions(id)`
- `commission_id uuid references commissions(id)`
- `deal_round_id uuid references deal_rounds(id)`
- `reverses_entry_id uuid references cashback_ledger(id)`
- `entry_type text not null`
- `amount_cents bigint not null`
- `currency char(3) not null`
- `status text not null`
- `environment text not null`
- `idempotency_key text not null unique`
- `description text not null`
- `created_at timestamptz not null`

Ledger rows are never updated or deleted after posting. Reversals use compensating rows linked through `reverses_entry_id`.

#### `community_allocations`

- `id uuid primary key`
- `commission_id uuid not null references commissions(id)`
- `amount_cents bigint not null`
- `currency char(3) not null`
- `status text not null`
- `rule_version text not null`
- `environment text not null`
- `created_at timestamptz not null`
- `resolved_at timestamptz`

This explicitly preserves an unassigned 15% referral allocation when no eligible direct referrer exists. No redistribution is implemented until a policy is approved.

### Payout preparation

#### `payouts`

- `id uuid primary key`
- `user_id uuid not null references auth.users(id)`
- `amount_cents bigint not null`
- `currency char(3) not null`
- `payout_status text not null`
- `environment text not null`
- `requested_at timestamptz not null`
- `processed_at timestamptz`
- `reference text`

#### `payout_items`

- `id uuid primary key`
- `payout_id uuid not null references payouts(id)`
- `ledger_entry_id uuid not null unique references cashback_ledger(id)`
- `amount_cents bigint not null`

No real payout provider is implemented in the initial phases.

### Audit and abuse controls

#### `audit_logs`

- `id uuid primary key`
- `actor_user_id uuid references auth.users(id)`
- `actor_type text not null`
- `action text not null`
- `target_table text`
- `target_id uuid`
- `environment text`
- `metadata jsonb`
- `created_at timestamptz not null`

#### `risk_events`

- `id uuid primary key`
- `user_id uuid references auth.users(id)`
- `click_id uuid references clicks(id)`
- `transaction_id uuid references transactions(id)`
- `risk_type text not null`
- `severity text not null`
- `status text not null`
- `metadata jsonb`
- `created_at timestamptz not null`

## 6. Attribution rules requiring approval

Recommended initial rules:

1. A buyer must be authenticated before the outbound affiliate click.
2. The server creates the click and immutable unique `click_ref`.
3. The server resolves the direct referrer from the personal deal URL.
4. Self-referrals are rejected.
5. A click is not a purchase and creates no financial entitlement.
6. A referral reward requires a matched, confirmed affiliate transaction.
7. Only one direct referrer can be attached to a transaction.
8. The rule used is stored by version on the attribution and commission.
9. Referral precedence and duration must be decided before implementation.
10. Referral codes and network parameters contain opaque identifiers only.

Open product decisions:

- Last eligible direct-referral click versus first eligible referral.
- Attribution duration.
- Whether a buyer may replace an earlier referrer before purchase.
- Whether the referrer must also have a confirmed purchase for that deal.
- Treatment of cross-device purchases.
- Treatment of unattributed network transactions.

## 7. Financial calculation rules

Use integer cents and basis points.

For an eligible direct referrer:

```text
basic = floor(gross * 3500 / 10000)
referral = floor(gross * 1500 / 10000)
platform = gross - basic - referral
```

The platform receives the deterministic cent remainder only to make the allocation reconcile. The remainder must be exposed as `rounding_adjustment_cents`, not hidden.

Without an eligible direct referrer:

```text
basic = floor(gross * 3500 / 10000)
unassigned community = floor(gross * 1500 / 10000)
platform = gross - basic - unassigned community
```

The unassigned amount is recorded in `community_allocations`. It does not silently become platform revenue.

Processing requirements:

- One commission allocation per transaction.
- Serializable or equivalent atomic processing.
- Stable idempotency key.
- Exact reconciliation check.
- Rejection before confirmation creates no payable ledger credit.
- Reversal after posting creates compensating debit entries.
- Simulation ledger entries can affect simulation projections only.

## 8. RLS policy model

### Public

- Read published live deals, active categories and public merchant fields.
- No direct read of affiliate destination URLs if redirects require server-generated tracking.

### Authenticated user

- Read and update permitted fields in own profile.
- Read own referrals and referral statistics through restricted views.
- Read own clicks where useful.
- Read own transactions, commissions, accounts, ledger and payouts.
- Create and edit own pending deal submissions.
- Never insert or update roles, transactions, commissions, ledger, balances or live events.

### Admin

Admin status is checked using a server-controlled role table. RLS may permit appropriate reads, but high-risk mutations should use audited server-side functions.

### Service processes

Edge Functions using service credentials perform narrowly scoped ingestion and processing. Function code still validates environment, role, event origin and input; service-role access is not treated as input validation.

## 9. Required Supabase development configuration

Create a dedicated development project, separate from future production.

Required settings:

- Region chosen with expected users and legal requirements in mind.
- Email/password authentication initially.
- Production email confirmation behavior decided before launch.
- Site URL set to the approved development origin.
- Redirect URLs for local development and approved GitHub Pages preview/production origins.
- RLS enabled on every public-schema table before frontend access.
- Storage bucket only if deal images are moved to Supabase Storage.
- Edge Function secrets for affiliate credentials and webhook verification.
- Separate values for simulation and live integrations.
- PITR/backups reviewed before financial pilot.
- Log retention and sensitive-payload redaction policy.

Local configuration:

- Supabase CLI.
- Docker-compatible local Supabase stack if available.
- `.env.local` ignored by Git.
- `.env.example` containing names only.
- Public frontend config generated from development project values.

Never copy development data or keys into a production project.

## 10. Affiliate adapter boundary

Define a network-neutral internal event:

```text
network
account
environment
external_event_id
external_transaction_id
event_type
occurred_at
order_amount_cents
commission_amount_cents
currency
click_ref
payload_hash
```

Each network adapter maps approved CSV, API or webhook fields into this format. Awin-specific assumptions are deferred until the approved account documentation is available.

## 11. Deployment environments

### Local

- Static server for the repository root.
- Local Supabase or dedicated cloud development project.
- Simulation data only by default.

### Development

- GitHub branch or preview deployment.
- Dedicated development Supabase project.
- Test email accounts.
- Simulation transactions.

### Production

- Production GitHub Pages/custom-domain deployment.
- Separate production Supabase project.
- Live integrations explicitly enabled server-side.
- No test fixtures or simulation events in live balances.

## 12. Architecture decisions deferred

- Exact GitHub repository layout and Pages source.
- Approved Awin import mechanism.
- Referral precedence and duration.
- Unassigned-community redistribution.
- Cashback release delay.
- Minimum payout and payout provider.
- Business entity, tax treatment and accounting integration.
- Whether public product images remain in Git or move to Storage.
