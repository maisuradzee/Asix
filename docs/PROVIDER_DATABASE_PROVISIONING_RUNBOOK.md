# ASIX Provider Database Provisioning Runbook v1.0

Status: proposed procedure for isolated staging only. No production database changes have been applied.

## 1. Current live boundary verified

The connected Supabase project is ASIX, running PostgreSQL 17.11.0.019. Its migration history includes V154 migration 20261118093932_asix_v154_sync_settled_player_stacks_into_game_snapshot.

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
2. consume_launch_token — atomic one-time token consumption by hash.
3. create_wallet_transaction — partner/session/config validation, scoped idempotency and outbox insert in one transaction.
4. claim_outbox_events — bounded worker lease claims.
5. mark_expired_wallet_dispatches_unknown — uncertain dispatch becomes UNKNOWN and queues a read-only status query, never a new debit.
6. post_ledger_journal — validates a same-currency balanced journal before posting.

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

## 7. Staging migration workflow

1. Restore verified V154 snapshot into isolated staging.
2. Verify existing consumer wallet, Q-CARD round lifecycle, commission and reconciliation smoke tests.
3. Confirm historical migration source and schema diff.
4. Install/verify Supabase CLI and inspect supabase --help.
5. Generate the real filename using supabase migration new provider_internal_foundation. Do not invent timestamps or write this proposal manually under supabase/migrations.
6. Review SQL and apply to staging only.
7. Run security advisors, pgTAP, role/grant/RLS tests, concurrency and failure-injection tests.
8. Verify schema is unexposed, table grants absent, and only approved function EXECUTE grants exist.
9. Re-run existing consumer product smoke tests against baseline.
10. Record migration ID, schema diff, test output, advisor results and rollback/forward-repair plan.
11. Only after a separate release gate should production deployment be considered.

## 8. Rollback and recovery

Do not drop provider tables or erase transactions after Provider has accepted live traffic. Production rollback disables new partner launches, isolates affected routes, preserves transaction and ledger evidence, resolves UNKNOWN operations and deploys a forward-fix. Schema rollback is allowed only when empty/test-only and backed by a verified restore.

## 9. Current blockers

- Historical V154 SQL source is not fully present in the GitHub repository; migration history is visible but clean-restore proof is not recorded.
- Supabase CLI is not installed in the current authoring environment; no Supabase-generated migration has been created.
- No dedicated Provider database LOGIN credential or secret has been provisioned.
- No Provider schema, role, function, trigger or table has been created in the live project.
