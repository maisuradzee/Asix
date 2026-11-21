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
- Launch session creation validates the active partner and exact enabled game/jurisdiction/currency/exponent configuration.
- partner_session_ref is idempotent within a partner; retry with the same immutable session identity reuses CREATED session, revokes older unconsumed token and issues one fresh token hash.
- Reuse of a partner session reference with a changed player/game/currency/policy identity is rejected.
- Concurrent launch retries for the same partner/session reference serialize and produce exactly one session and one currently valid token.
- Only token hashes are stored; token can be consumed once and only before expiry.
- Token consumption atomically advances session CREATED → ACTIVE; a replay, revoked token, expired token, inactive partner or disabled config returns no session context.
- Repeating Launch after the session is ACTIVE does not issue another token.
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

Verified GitHub Actions run 255 uses two isolated jobs:
- Deno reference suite: 76 passed, 0 failed.
- PostgreSQL 17 service container: schema proposal applied successfully, followed by smoke tests that emitted `PROVIDER_DATABASE_SMOKE_TESTS_PASSED`.
- Concurrent financial checks emitted `PROVIDER_CONCURRENT_FINANCIAL_LIMIT_TESTS_PASSED`.

The concurrency assertions used separate database clients:
1. Two 1,000-minor-unit BET requests raced against a 1,500-minor-unit partner/game/jurisdiction/currency open-exposure cap; one succeeded and one was rejected by the cap.
2. Two 300-minor-unit REFUND requests raced against a 500-minor-unit confirmed original Bet; one succeeded and one was rejected because the combined amount would exceed the original debit.

This validates the draft SQL and those specific concurrent paths on vanilla PostgreSQL 17. It does not prove compatibility with the restored ASIX V154 Supabase project, the Supabase Data API configuration, production throughput or every possible isolation/replica failure.

- Wallet response persistence: DISPATCHING → PENDING/UNKNOWN → read-only STATUS_QUERY → CONFIRMED/DECLINED, including idempotent replay of the same response attempt and a bounded status-query generation limit.

- Partner response persistence: DISPATCH/STATUS_QUERY responses must match a leased outbox event, the same worker ID that claimed the event, and an unexpired lease; duplicate attempt persistence is idempotent; changing the response under the same attempt number is rejected.
- A deliberately stale worker ID is rejected; the actual lease owner can still persist the response.
- Wallet financial identity fields are immutable; status/response metadata changes only through approved functions.
- Completed/voided rounds, wallet attempt evidence and signed commercial contract versions cannot be updated or deleted.


## L. Read-only status-query lease recovery

- If a wallet DISPATCH lease expires, its transaction becomes UNKNOWN and a read-only status query is queued. The original debit/credit dispatch is never resent automatically.
- If a WALLET_STATUS_QUERY lease expires, the query event returns to RETRY after bounded backoff; worker ID, lease token and lease expiry are cleared.
- A subsequent claim receives a fresh, one-time lease token.
- If the event has reached max_attempts, it moves to DEAD_LETTER, clears the stale lease data and is no longer claimable.
- Status-query lease recovery does not change the wallet transaction state or create a BET/WIN/REFUND transaction.
- Response persistence requires the exact worker ID, one-time lease token and unexpired lease. Stale workers/tokens are rejected.
- CI test marker: \`PROVIDER_STATUS_QUERY_LEASE_RECOVERY_PASSED\`.


## M. Launch session creation and activation (21 November 2026)

- \`create_launch_session\` validates partner status, exact game configuration, jurisdiction, currency/exponent, locale, policy version, token hash and a maximum five-minute token lifetime.
- \`partner_session_ref\` provides partner-scoped idempotency. Same immutable identity reuses the CREATED session; prior unused token hashes are revoked before a new one is issued. Changed identity is an integrity conflict.
- \`consume_launch_token\` locks the same partner/session advisory key, checks the active partner/config, consumes the one-use token and activates the session in one transaction.
- After activation, the same Launch request returns the existing ACTIVE session without minting another token.
- A two-client CI race test calls \`create_launch_session\` concurrently with the same partner/session reference and different token hashes. Expected result: 1 session, 1 unconsumed/unrevoked token and 1 revoked earlier token.
- Latest verified GitHub Actions run #307: 80 Deno tests passed, 0 failed; SQL schema, smoke, concurrent launch, concurrent Bet exposure, concurrent Refund cap, response lifecycle and status-query recovery checks passed on disposable PostgreSQL 17.

This validates the proposed SQL on vanilla PostgreSQL 17. It does not establish a verified V154 restore, Supabase staging compatibility, production throughput or partner UAT.
