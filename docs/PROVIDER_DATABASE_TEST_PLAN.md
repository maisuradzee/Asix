# ASIX Provider Database Test Plan v1.0

Target: disposable PostgreSQL 17 CI container for current automated smoke checks; full acceptance still requires isolated restored V154 Supabase staging. The SQL proposal has not been applied to the live ASIX database.

## A. Environment and compatibility
- Restore the exact V154 baseline into an isolated database.
- Record PostgreSQL version, migration head, schema dump, function signatures, role grants and RLS inventory.
- Confirm super-worker V25 remains unchanged and verify_jwt=true.
- Confirm baseline Q-CARD tests pass before Provider schema installation.
- Confirm no existing wallet, commission, Q-CARD state/action/history table is altered by the migration.

## B. Schema exposure and role security
| Test | Expected result |
|---|---|
| provider_internal absent from Data API exposed schemas | Pass |
| anon/authenticated schema USAGE | Denied |
| service_role direct provider table access | Denied |
| provider_runtime direct SELECT/INSERT/UPDATE/DELETE | Denied |
| provider_runtime EXECUTE on approved provider functions | Allowed |
| Every provider table has RLS enabled and FORCE RLS | Pass |
| SECURITY DEFINER functions use empty search_path and qualified names | Pass |
| Provider runtime is not a member of authenticated, service_role, postgres or supabase_admin | Pass |

## C. Partner and credential lifecycle
- Duplicate partner code rejected.
- Duplicate key ID within a partner rejected; same key ID may exist for another partner.
- Suspended/terminated partner and revoked/expired/not-yet-valid key cannot consume a nonce.
- Nonce hash must be exactly 32 bytes; same partner + key ID + nonce hash can be consumed once only.
- Same nonce hash used by another partner is isolated to that partner/key scope.
- Raw private keys, HMAC secrets, access tokens and launch tokens are never stored in provider tables.

## D. Launch and session
- Session uniqueness is partner_id + partner_session_ref.
- Partner A cannot consume Partner B launch token.
- Only token hashes are stored; token can be consumed once and only before expiry.
- Expired or already consumed token returns no session context.
- Disabled game, currency or jurisdiction cannot create a launch.
- Session currency and exponent cannot be changed by a wallet request.

## E. Wallet transaction and idempotency
- Same partner + same idempotency key + same request hash returns existing transaction and no second outbox event.
- Same key + different request hash is rejected.
- Same idempotency key may be used by different partners without collision.
- Bet below minimum/above max and win above max are rejected.
- Unknown game/currency/jurisdiction config is rejected.
- Round must belong to session/partner and be OPEN.
- Currency exponent mismatch is rejected.
- Refund without original transaction is rejected.
- Refund for another partner/session/currency is rejected.
- Refund of declined/unknown/pending bet is rejected.
- Refund amount cannot exceed remaining confirmed original bet.
- Concurrent refund workers cannot over-refund one original bet.
- Wallet transaction and WALLET_DISPATCH outbox row are committed atomically.
- Money uses integer minor units only.

## F. Outbox and worker crash recovery
- Two workers using FOR UPDATE SKIP LOCKED never claim the same READY event simultaneously.
- Claim limits and leases are bounded.
- Expired WALLET_DISPATCH lease is not re-dispatched.
- Expired dispatch becomes UNKNOWN and queues WALLET_STATUS_QUERY.
- Status queries are read-only and use bounded backoff.
- Duplicate status-query generation is prevented.
- Worker crash after dispatch but before response persistence leaves UNKNOWN, never fabricated success/failure.

## G. Ledger and settlement
- Journal has at least two lines; all lines use journal currency and same-partner accounts.
- Debit total equals credit total exactly; unbalanced journal cannot post.
- Mixed-currency or cross-partner lines are rejected.
- Posted journal and its entries cannot be updated or deleted.
- Reversal creates a new linked journal and never edits original.
- Settlement run references one signed contract version and immutable input hash.
- Settlement uses contract GGR definition, rounding and negative-GGR policy.
- Material UNKNOWN transactions/unexplained differences block settlement release.

## H. Append-only audit and approvals
- Audit events cannot be updated or deleted.
- Approval decisions cannot be updated or deleted.
- Material adjustment requires two distinct approver identities.
- Material operations include partner, actor, correlation ID, source transaction, timestamp and evidence hash.
- No staff or AI action can rewrite completed game results or posted ledger events.

## I. Failure injection
1. Worker dies after claiming but before network send.
2. Partner accepts debit and response is dropped.
3. Partner declines debit but API times out.
4. Partner returns PENDING beyond status-query SLA.
5. Database connection drops after partner response arrives.
6. Two workers process same idempotency key concurrently.
7. Two refunds compete for the same remaining refundable amount.
8. Outbox backlog reaches configured capacity.
9. Partner key is revoked while requests are in flight.
10. Partner A outage while Partner B continues.

Expected result: no duplicate financial effect, no cross-partner access, no fabricated wallet result, and every unresolved transaction remains a visible, auditable exception.

## J. Exit criteria
- SQL and pgTAP tests pass on a clean isolated V154 restore.
- Security/performance advisors reviewed with no critical Provider-specific findings.
- Existing Q-CARD and consumer wallet smoke tests are unchanged.
- Load/concurrency tests demonstrate stable row locking, indexes and outbox throughput.
- Restore/forward-repair plan tested.
- Independent security review approves schema and routines.


## K. Current CI execution evidence (21 November 2026)

The current CI workflow uses two separate jobs:
- Provider reference Deno job: 73 tests passed, 0 failed.
- Provider database SQL job: design proposal applied successfully to disposable PostgreSQL 17; smoke suite ended with `PROVIDER_DATABASE_SMOKE_TESTS_PASSED`.

This validates draft SQL against vanilla PostgreSQL 17 and the specific smoke assertions. It does not prove V154 upgrade compatibility, Supabase Data API exposure settings, production load, or a successful restore of the historical ASIX database.
