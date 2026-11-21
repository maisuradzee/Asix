# ASIX B2B Provider — Stage 2 Build Plan

**Objective:** move from written integration contract to a tested partner sandbox flow without touching the current ASIX production game path.

## Stage 2A — Establish the safe engineering baseline

Tasks:
1. Review docs/V154_RESTORE_READINESS_ASSESSMENT.md; confirm V154, PostgreSQL 17.11.0.019 and the current 128-entry migration inventory.
2. Run scripts/export_asix_v154_baseline.ps1 on the authorized workstation. It exports only schema.sql and roles.sql from the explicit source project reference, with a SHA-256 manifest; no live data is exported.
3. Preserve the private export under supabase/private_exports/ (Git-ignored). Never commit source role metadata, schema dump or any future private backup files.
4. Obtain the cost quote and explicit cost approval before creating a dedicated Supabase staging branch/project. The current source project has no staging branch.
5. Restore schema/roles to staging only. Reconcile Supabase-managed Auth/Storage dependencies and the five installed source extensions/versions before applying objects.
6. Compare schemas, tables, functions, views, indexes, triggers, RLS policies and grants against the read-only source inventory.
7. Create synthetic destination Auth identities and synthetic wallet/game fixtures. Do not import source Auth users, player rows, wallet balances, ledger transactions or Q-CARD game history.
8. Run existing 2–5 player game, wallet, buy-in, payout, cashout, commission and reconciliation smoke tests.
9. Record a signed-off staging baseline and every restore exception. Do not treat the four recovered V147/V148/V149 SQL files as the full historical migration chain.
10. Decide how V157 relates to the selected current consumer-game 5%/95% rule; do not apply it merely because it exists as a candidate.

Exit criteria:
- Private schema/roles export completed and SHA-256 manifest verified.
- Restore completed in an isolated Supabase staging environment with managed schemas/extensions reconciled.
- Object counts, critical function definitions, RLS and grants match the recorded live baseline or have reviewed exceptions.
- Existing wallet and Q-CARD financial invariants pass with synthetic fixtures.
- Staging is isolated from source production and live player data.
- No B2B migration has been applied yet.

## Stage 2B — Partner simulator and contract tests

Tasks:
1. Run the local mock operator wallet simulator.
2. Connect a thin test client to bet, win, refund and status-query routes.
3. Validate same-key/same-payload replay and same-key/different-payload conflict.
4. Validate accepted debit with lost response and pending status resolution.
5. Add contract fixtures for each future operator protocol.

Exit criteria:
- Deno CI compiles and all simulator tests pass.
- No scenario can create a second financial effect from a repeated request.
- Test evidence includes request/response correlation IDs and wallet balances.

## Stage 2C — Provider service skeleton

Suggested separate function/service boundaries:
- `provider-launch`: signed partner launch, nonce protection, one-time launch tokens.
- `provider-wallet`: transaction orchestration only; no game outcome logic.
- `provider-status`: read-only status queries and reconciliation support.
- `provider-admin`: partner configuration and approval workflow; staff MFA/RBAC required.

Do not overload `super-worker` V25. Keep partner secrets in a secrets manager. Keep server-to-server authentication distinct from Supabase user JWT authentication.

## Stage 2D — Isolated provider persistence

Only after Stage 2A:
- create a separate `provider` schema;
- apply provider-domain tables as a new migration;
- scope all business records by partner;
- keep unique constraint on `(partner_id, idempotency_key)`;
- add transactional outbox, attempts, reconciliation and approval tables;
- enforce immutable posted journals and balanced per-currency entries;
- deny partner clients direct database access.

Exit criteria:
- RLS, grants and service-role paths are reviewed.
- Tenant-isolation tests pass.
- Database uniqueness/concurrency tests prove idempotency under parallel dispatch.
- Migration is repeatable in staging and has a tested forward-repair path.

## Stage 2E — First operator sandbox adapter

Choose one partner only after its technical documentation and commercial owner are confirmed. Build an adapter translating its wallet protocol to the canonical interface.

Test:
- launch;
- balance inquiry only if contract requires and permits it;
- debit;
- credit;
- status query;
- refund/compensation;
- timeout and duplicate;
- partner report reconciliation;
- circuit breaker and recovery.

No real funds and no production traffic during this stage.

## Stage 2F — Certification and launch readiness

Before production:
- independent game math/RNG testing and required certification;
- security assessment and penetration test;
- contract and regulatory review by jurisdiction;
- partner UAT sign-off;
- financial reconciliation dry-run;
- backup restore and disaster-recovery exercise;
- incident on-call and escalation coverage;
- staged traffic/risk limit plan.

## Work ownership

| Workstream | Responsible | Approval |
|---|---|---|
| Existing V154 restore | Supabase/DB engineer | Technical Owner |
| Wallet protocol and adapter | Backend engineer | Technical + Financial Controller |
| Ledger and settlement mapping | Backend + accountant | Financial Controller |
| Game/RNG certification | Independent test lab | Compliance Owner |
| Partner contract/UAT | Partner Integration Owner | Business Owner |
| Production go-live | Operations | Technical + Financial + Compliance |

## Non-goals for Stage 2

- No rework of current ASIX consumer wallet.
- No change to current 5%/95% consumer-game economy.
- No deployment of provider APIs to public internet.
- No player deposits/withdrawals handled by ASIX.
- No autonomous AI settlement or financial adjustment.
