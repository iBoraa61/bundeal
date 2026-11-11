# BunDeal Project Audit

Status: Phase 0  
Audit date: 2026-11-11  
Scope: Existing local frontend prototype and its readiness for a Supabase-backed platform

## Executive summary

BunDeal is currently a static, bilingual frontend prototype. It contains no backend, database, authentication, affiliate integration, financial ledger, build system, dependency manager or automated test suite. The public pages correctly present cashback as a possible later BunDeal payment funded by confirmed affiliate commission, and they distinguish the merchant price from the bonus.

The existing visual identity, responsive CSS, bilingual content, legal pages, navigation, calculation example and lightweight JavaScript can be reused. The prototype should be extended incrementally rather than rewritten in a frontend framework.

Repository control is established. The live repository is `iBoraa61/bundeal`. Backend work stays on `feature/bundeal-backend`. `main` remains the published prototype. GitHub Pages serves the repository root, and `CNAME` maps it to `bundeal.de`.

A separate Desktop folder, `C:\Users\IBora\Desktop\BunDeal`, contains partner presentations and a nested `site/` copy. That folder is not the deployment source. New application files belong in this repository root, not in a new `site/` directory.

## A. Current project structure

Deployed repository `iBoraa61/bundeal`, branch `feature/bundeal-backend`:

```text
bundeal/
├─ index.html
├─ index-en.html
├─ beispiel-take3.html
├─ example-en.html
├─ impressum.html
├─ legal-notice-en.html
├─ datenschutz.html
├─ privacy-en.html
├─ css/styles.css
├─ js/site.js
├─ assets/
│  ├─ logo.svg
│  ├─ logo-icon.png
│  ├─ headphones.png
│  └─ fonts/
├─ CNAME
├─ README.md
├─ PROJECT_AUDIT.md
├─ ARCHITECTURE.md
└─ IMPLEMENTATION_ROADMAP.md
```

Partner PDFs, presentation HTML and Python generators exist only in the Desktop working folder. They are not part of the website repository and must not be uploaded to the GitHub Pages root.

There is no package manifest, CI workflow, test suite, Supabase directory, migration or environment template. `README.md` currently contains only the title.

## B. Existing frontend functionality

### Public content

- German and English landing pages.
- German and English calculation examples.
- German legal notice and privacy notice.
- Informational English translations of both legal pages.
- Transparent 35% / 15% / 50% concept example.
- Monthly-round explanation.
- Direct-referral explanation with no multi-level reward.
- Explicit distinction between merchant price and later BunDeal bonus.
- Explicit statement that only confirmed commission can fund a bonus.

### Interaction

- Responsive desktop and mobile navigation.
- German/English language switch.
- Copy-current-link action on the example page.
- Deal suggestion form that opens the visitor's email application.
- Accessible headings, labels, focus styles, skip links and status regions.

### Hosting behavior

- The site is already served as static files from the repository root.
- Relative paths match the current GitHub Pages deployment.
- `CNAME` contains `bundeal.de`.
- There is no client-side router and no server-side routing requirement.

## C. Reusable components

- `assets/logo.svg` is the canonical brand asset and must remain unchanged.
- `css/styles.css` provides typography, colors, cards, buttons, grids, responsive rules, forms, deal presentation and legal-page styling.
- Shared header, footer and navigation markup can be extracted only if a lightweight generation step becomes worthwhile; duplication is acceptable during the first backend phases.
- `js/site.js` can remain the entry point for shared progressive enhancement.
- The bilingual pages provide a reusable content and routing pattern.
- The calculation example is useful as the first simulation-mode deal detail.
- Existing notices about estimated and confirmed amounts should become shared status components.
- The current suggestion form can later submit to a protected database flow without changing its visual design.

## D. Missing functionality

### Platform foundation

- Git checkout of `feature/bundeal-backend` exists at `C:\Users\IBora\Desktop\bundeal-git`.
- Development and production environment separation.
- Supabase projects and configuration.
- Database schema and migrations.
- RLS policies.
- Environment-variable documentation.
- Automated tests and CI.

### Product functionality

- Registration, login, logout, password reset and session handling.
- User profiles and immutable referral codes.
- Database-driven deals and categories.
- Deal submissions and moderation.
- Admin role and protected admin operations.
- Deal rounds.
- Direct referral attribution.
- Affiliate redirect and click-reference creation.
- Affiliate transaction ingestion.
- Simulation-mode event generation.
- Commission processing and immutable cashback ledger.
- User dashboard and admin dashboard.
- Payout preparation.

### Operational functionality

- Audit logs.
- Fraud indicators and rate limiting.
- Webhook signature validation.
- Idempotent event processing.
- Monitoring, error reporting and backup procedures.
- Data retention and deletion procedures.
- Legal and affiliate-network approval for the final model.

## E. Recommended target architecture

- Keep the existing static HTML/CSS/Vanilla JavaScript frontend.
- Continue static hosting initially.
- Use a separate Supabase development project for Auth, PostgreSQL, RLS and Edge Functions.
- Restrict browser access with RLS and perform privileged/financial operations server-side.
- Use network-specific affiliate adapters behind a network-neutral internal event model.
- Treat an append-only ledger as the source of financial truth.
- Keep simulation and live records separated and server-controlled.

The complete target architecture is defined in `ARCHITECTURE.md`.

## F. Proposed database schema

The schema includes identity, roles, merchants, categories, deals, submissions, affiliate accounts and links, user referrals, purchase referral attributions, clicks, rounds, raw affiliate events, transactions, versioned commission rules, commission allocations, community allocations, cashback accounts, immutable ledger entries, payout preparation, audit logs and risk events.

Important additions to the initial prompt are:

- `merchants`, because multiple required tables reference a merchant.
- `affiliate_accounts`, to scope external transaction uniqueness correctly.
- `affiliate_events`, for idempotency and inbound-event audit.
- `referral_attributions`, to separate a user relationship from purchase attribution.
- `commission_rules`, to version the 35/15/50 rule.
- `community_allocations`, to preserve an unassigned 15% referral allocation.
- `audit_logs` and `risk_events`, for operational accountability.

The normalized schema and constraints are specified in `ARCHITECTURE.md`.

## G. Required Supabase configuration

- One dedicated development project with no future production data.
- Supabase Auth with explicitly allowlisted callback URLs.
- RLS enabled before exposing every sensitive table.
- Edge Function secrets for service and affiliate credentials.
- Local CLI configuration and ignored local environment files.
- Public frontend configuration containing only project URL and publishable key.
- Separate simulation/live configuration enforced server-side.
- Backup, logging and sensitive-payload retention settings reviewed before a pilot.

## Current user flows

### Available

1. Visitor opens the German or English landing page.
2. Visitor reads the concept and opens the example calculation.
3. Visitor may copy the page URL.
4. Visitor may prepare a deal suggestion email.
5. Visitor may read legal and privacy information.

### Not yet available

1. Register or authenticate.
2. Open a real database-backed deal.
3. Generate a server-tracked affiliate click.
4. Attribute a direct referral.
5. Receive a reported affiliate transaction.
6. Confirm or reverse commission.
7. View cashback or request a payout.
8. Moderate submissions or transactions.

## Dependencies

The runtime has no third-party JavaScript dependencies. Fonts and images are self-hosted. Presentation generation uses Python, Pillow and headless Chrome, but those tools are not required to run the website.

## Deployment findings

- GitHub Pages deploys this repository root. Do not move the live pages into a `site/` folder.
- The project uses `noindex, nofollow` on all current pages. This is appropriate for a prototype but must be an explicit launch decision later.
- GitHub Pages cannot securely store secrets or execute server-side redirects.
- Supabase Auth redirect URLs must include every approved local, preview and production origin.
- Static pages cannot protect admin content by hiding links; every sensitive operation must be authorized by RLS and server-side logic.
- Configuration containing the Supabase URL and publishable key may be public. Service-role and affiliate secrets must never enter this repository's frontend or GitHub Pages artifacts.
- A custom domain on GitHub Pages requires correct HTTPS and DNS configuration. Authentication callbacks must use HTTPS in production.

## H. Security risks

### Critical if implemented incorrectly

- Client-controlled role assignment could create administrators.
- Client-supplied commission or cashback amounts could corrupt balances.
- Missing RLS could expose all users' financial records.
- Duplicate affiliate events could issue cashback more than once.
- Replaying a confirmation or reversal could corrupt the ledger.
- Mixing simulation and live events could affect real balances.
- Exposed service-role or affiliate credentials would compromise the platform.

### High

- Referral self-attribution or referral-code replacement after purchase.
- Open redirects through unvalidated affiliate URLs.
- Forged webhooks or CSV imports.
- Reusing external transaction IDs across network accounts.
- Mutable or deletable ledger history.
- Race conditions during transaction confirmation and payout reservation.
- Storing personal data in affiliate tracking parameters.

### Medium

- Deal-submission spam.
- Referral-click manipulation.
- Enumeration of usernames or referral relationships.
- Unsafe rendering of user-provided deal descriptions.
- Inconsistent language versions displaying different financial claims.
- GitHub Pages caching old frontend configuration after backend changes.

## I. GitHub Pages and Supabase issues

- Supabase Auth works with a static frontend, but callback and password-reset URLs must be allowlisted.
- Session tokens are handled in the browser; XSS prevention is therefore essential.
- All browser database access is untrusted and must be constrained by RLS.
- Edge Functions should handle affiliate redirects, imports, commission processing and privileged admin mutations.
- GitHub Pages has no secure runtime environment variables. Public configuration must be generated or committed separately from secrets.
- Browser-to-Supabase requests require correct CORS behavior and stable production origins.
- Previewing arbitrary branches through GitHub Pages is not automatic. A separate preview workflow or local Supabase setup may be needed.
- The development Supabase project must be separate from production from the start. Data, keys, webhook URLs and scheduled jobs must never be shared.

## J. Prioritized implementation plan

1. Identify and connect the actual GitHub repository.
2. Create `feature/bundeal-backend` from the deployed default branch.
3. Approve Phase 0 architecture and attribution decisions.
4. Create the separate Supabase development project.
5. Establish migrations, RLS, environment handling and tests.
6. Add authentication and profiles.
7. Add moderated database-backed deals.
8. Add direct referral attribution without financial rewards.
9. Add affiliate tracking and simulation/import processing.
10. Add the cashback ledger and round accounting.
11. Add user and admin dashboards.
12. Complete pilot-readiness testing and operational review.

Detailed phase gates are defined in `IMPLEMENTATION_ROADMAP.md`.

## K. Files to create or modify

Phase 0 creates only:

- `PROJECT_AUDIT.md`
- `ARCHITECTURE.md`
- `IMPLEMENTATION_ROADMAP.md`

Expected later files are documented phase by phase in `IMPLEMENTATION_ROADMAP.md`. Existing frontend pages and brand assets are preserved. No migration, Supabase function or backend file is created before Phase 1 approval.

## Technical risks requiring early decisions

1. The real GitHub repository and deployment branch are not identified locally.
2. The exact affiliate network interface is not approved or verified.
3. Referral attribution duration and precedence are not yet defined.
4. The treatment of unassigned 15% community allocation is intentionally unresolved.
5. Cashback availability timing after confirmation is not yet defined.
6. Legal, tax and payout requirements have not been validated.
7. The privacy notice will require substantial expansion before accounts, tracking or payouts are enabled.

## Audit conclusion

The selected HTML/CSS/Vanilla JavaScript plus Supabase architecture is appropriate for a controlled pilot. It avoids an unnecessary frontend rewrite while providing PostgreSQL, authentication, RLS and server-side functions. The financial core must be built around immutable events, idempotent processing and an append-only ledger rather than mutable balance fields.

Phase 1 should not begin until the GitHub repository is identified, a dedicated development Supabase project exists, and the Phase 0 architecture and attribution rules are approved.
