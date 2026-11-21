# ASIX Provider Database Provisioning Runbook v1.1

Status: proposed procedure for isolated staging only. No production database changes have been applied.

## 1. Current live boundary verified

The connected Supabase project is ASIX, running PostgreSQL 17.11.0.019. Its migration history contains 128 records and ends at V154 migration 20261118093932_asix_v154_sync_settled_player_stacks_into_game_snapshot. GitHub contains only four recovered historical SQL files (V147/V148/V149); the full original 128-file migration chain is not present.

The live product contains the existing consumer-domain objects:
- public.asix_wallets
- public.asix_wallet_transactions
- public.asix_platform_commission_settings
- public.asix_platform_commission_ledger
- public.qcard_rooms, qcard_seats, qcard_game_state, qcard_actions, qcard_money_ledger
- asix_internal schema with current SECURITY DEFINER wallet and Q-CARD functions

The current deployed super-worker is V25 and verify_jwt=true.

These are protected compatibility boundaries. Provider must not reuse these balances, ledgers, action queues or functions.

## 2. Schema boundary

Use a dedicated, non-Data-API schema named provider_internal, not public and not asix_internal. Do not add provider_internal to exposed Data API or GraphQL schemas.

Provider domain owns partner identities, key metadata, game configuration, nonces, launch-token hashes, sessions, rounds, wallet transactions, attempts, outbox, provider ledger, reconciliation, settlement, approvals, audit and incidents.

## 3. Database role separation

- provider_owner: NOLOGIN owner of schema, tables and approved SECURITY DEFINER routines; NOBYPASSRLS.
- provider_runtime: NOLOGIN capability role with schema USAGE and EXECUTE on explicitly approved functions; no direct table DML or SELECT.
- A separate LOGIN role is provisioned out-of-band and granted membership in provider_runtime. The function connects using a dedicated ASIX_PROVIDER_DATABASE_URL secret and executes SET ROLE provider_runtime.

Never connect Provider using the broad postgres credential or Supabase service_role key. Never store database credentials in this repository.

## 4. Data-access contract

Initial routines:
1. consume_partner_nonce — atomic partner/key/nonce-hash uniqueness.
2. create_launch_session — partner/game/currency eligibility, partner-scoped launch idempotency, revocation of superseded token hashes and fresh one-use launch token issuance.
3. consume_launch_token — atomic one-time token consumption by hash and CREATED → ACTIVE session transition.
4. create_wallet_transaction — partner/session/config validation, scoped idempotency and outbox insert in one transaction.
5. claim_outbox_events — bounded worker lease claims.
6. mark_expired_wallet_dispatches_unknown — uncertain dispatch becomes UNKNOWN and queues a read-only status query, never a new debit.
7. record_wallet_partner_response — requires the relevant outbox lease, the worker ID that owns that lease, its one-time lease token, an unexpired lease and the exact response generation; persists a partner DISPATCH/STATUS_QUERY response idempotently, stores attempt evidence, closes the lease and schedules a bounded next status query when still pending/unknown.
8. get_wallet_transaction_status — returns only scoped transaction status fields for an authenticated partner context.
9. post_ledger_journal — validates a same-currency balanced journal before posting.
10. recover_expired_wallet_status_query_leases — returns expired read-only status checks to RETRY with bounded backoff, or moves events at max_attempts to DEAD_LETTER.

Append-only/integrity controls freeze completed/voided rounds, wallet financial identity fields, wallet attempt evidence, commercial contract versions, audit/approval history and posted ledger journals/entries. Financial status updates must use approved state-transition routines.

Launch creation/reissue and token consumption share a partner/session advisory transaction lock. This serializes concurrent retries against the same operator session reference and prevents token consumption racing with reissue.

Runtime must not be granted direct access to provider tables. Add routines only after unit, SQL, concurrency and security review.

## 5. Credential handling

- HMAC private keys remain in KMS/Secrets Manager; store references only.
- ECDSA private signing material remains in KMS/HSM; store public-key references only.
- Never persist raw launch tokens; persist SHA-256 hashes.
- Persist nonce hashes, not raw nonces.
- Avoid storing raw partner request/response bodies. Persist hashes and only necessary redacted evidence.
- No credentials in GitHub, SQL source, logs, notebooks or incident messages.

## 6. Supabase Data API and RLS

Supabase grants determine which roles can reach objects; RLS controls row access. Keep provider_internal unexposed, revoke direct table grants and enable plus FORCE RLS on every provider table. The owner-only policy is intended for the SECURITY DEFINER owner role, not partner or browser roles.

Do not copy auth.uid() policies onto Provider tables: casino partner identities are not Supabase Auth users. Partner identity is derived from verified key mapping in the trusted server.

## 7. V154 baseline export and staging workflow

The current source snapshot is useful for inspection but is not a proven restore. Read docs/V154_RESTORE_READINESS_ASSESSMENT.md before starting.

1. Install and authenticate the current Supabase CLI v3 on the authorized Windows workstation.
2. From the repository root, run:
   powershell -ExecutionPolicy Bypass -File .\scripts\export_asix_v154_baseline.ps1
3. The script validates that supabase/config.toml points to kxcuvagipqiqisowtgys and that the CLI supports --remote and --role-only. It uses explicit --remote=kxcuvagipqiqisowtgys for both schema and role dumps.
4. The script writes roles.sql, schema.sql and manifest.txt under supabase/private_exports/v154_<UTC timestamp>/. This folder is ignored by Git. Keep it private and retain the checksum manifest outside GitHub.
5. No --data-only export is run. The export contains no source Auth users, player rows, wallet balances, financial transactions or Q-CARD game history.
6. Create or select an isolated Supabase staging destination. The source project currently has no Supabase development branch. A new branch/project may incur charges; obtain the platform cost quote and explicit cost approval before creating one.
7. Restore schema.sql and roles.sql into staging only. Ensure the destination is a compatible Supabase-managed environment with the required managed Auth/Storage services and compatible extension versions. The CLI dump excludes managed and extension-owned schemas.
8. Review owner/grant/default-privilege behavior before applying roles. Never copy a source database password, login secret, Vault secret or source Auth UUID into staging.
9. Compare schemas, tables, functions, views, indexes, policies, triggers and ACLs with the read-only source inventory. Review extension versions, RLS and SECURITY DEFINER search_path.
10. Create synthetic destination Auth users and synthetic game/wallet fixtures. Use the destination-only commission bootstrap only after replacing its recipient marker with a new staging Auth user UUID.
11. Run existing Q-CARD, game lifecycle, wallet, buy-in, payout, cashout, commission and reconciliation smoke tests. Record baseline results before installing Provider schema.
12. Only after Stage 2A passes, create a Provider migration using the supported CLI command supabase migration new provider_internal_foundation, review it, and apply to isolated staging. Do not apply this SQL proposal to the source project.
13. Run Supabase security/performance advisors, pgTAP, tenant-isolation, concurrency and failure-recovery tests. Re-run all existing consumer tests against the staging baseline.
14. Record migration ID, schema diff, test evidence, extension versions, restore results and a forward-repair plan. Production deployment needs a separate release gate.

Supabase CLI v3 runs database commands against the local stack by default unless --remote is supplied. The export script pins the exact project reference so it cannot silently dump whichever project happens to be linked. The CLI dump is read-only; it exports schema and roles separately and does not export data.

Latest verified Provider GitHub Actions run #307: 80 Deno tests passed, 0 failed. The consolidated schema and SQL smoke suite passed on disposable PostgreSQL 17, including concurrent Launch session idempotency/token supersession, concurrent Bet exposure limits, concurrent Refund caps, wallet response persistence and expired read-only status-query lease recovery. This is not a V154 restore or a Supabase staging test.

## 8. Rollback and recovery

Do not drop provider tables or erase transactions after Provider has accepted live traffic. Production rollback disables new partner launches, isolates affected routes, preserves transaction and ledger evidence, resolves UNKNOWN operations and deploys a forward-fix. Schema rollback is allowed only when empty/test-only and backed by a verified restore.

## 9. Current blockers

- The original 128-file SQL migration history is not fully present in GitHub. Only four V147/V148/V149 references were recovered; current-state catalog snapshots are not equivalent to the original replay chain.
- The private schema/roles export script has been added but has not yet been executed on the authorized Windows workstation; a fresh manifest/checksum set is still pending.
- No Supabase staging branch currently exists. No new branch/project was created because its cost has not been quoted and approved.
- A clean schema/roles restore into isolated Supabase staging, extension reconciliation and consumer smoke tests have not yet been performed.
- Supabase CLI-generated Provider migration is not yet created.
- No dedicated Provider database LOGIN credential or secret has been provisioned.
- No Provider schema, role, function, trigger or table has been created in the live project.

