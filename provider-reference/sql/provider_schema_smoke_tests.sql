\set ON_ERROR_STOP on

-- This test suite runs only inside a disposable PostgreSQL 17 CI container.
-- It is not a production migration test and does not connect to Supabase.

DO $security$
DECLARE
  v_total integer;
  v_rls integer;
BEGIN
  IF pg_catalog.has_schema_privilege('anon', 'provider_internal', 'USAGE')
     OR pg_catalog.has_schema_privilege('authenticated', 'provider_internal', 'USAGE')
     OR pg_catalog.has_schema_privilege('service_role', 'provider_internal', 'USAGE') THEN
    RAISE EXCEPTION 'UNTRUSTED_ROLE_HAS_PROVIDER_SCHEMA_USAGE';
  END IF;

  IF NOT pg_catalog.has_schema_privilege('provider_runtime', 'provider_internal', 'USAGE') THEN
    RAISE EXCEPTION 'PROVIDER_RUNTIME_SCHEMA_USAGE_MISSING';
  END IF;

  IF pg_catalog.has_table_privilege('provider_runtime', 'provider_internal.partners', 'SELECT')
     OR pg_catalog.has_table_privilege('provider_runtime', 'provider_internal.wallet_transactions', 'INSERT')
     OR pg_catalog.has_table_privilege('provider_runtime', 'provider_internal.ledger_entries', 'UPDATE') THEN
    RAISE EXCEPTION 'PROVIDER_RUNTIME_HAS_DIRECT_TABLE_PRIVILEGE';
  END IF;

  IF NOT pg_catalog.has_function_privilege(
    'provider_runtime',
    'provider_internal.consume_partner_nonce(uuid,text,bytea,timestamp with time zone)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'PROVIDER_RUNTIME_APPROVED_FUNCTION_GRANT_MISSING';
  END IF;

  IF pg_catalog.has_function_privilege(
    'provider_runtime',
    'provider_internal.guard_append_only_history()',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'PROVIDER_RUNTIME_CAN_EXECUTE_INTERNAL_TRIGGER_FUNCTION';
  END IF;

  IF pg_catalog.pg_has_role('provider_runtime', 'service_role', 'MEMBER')
     OR pg_catalog.pg_has_role('provider_runtime', 'authenticated', 'MEMBER') THEN
    RAISE EXCEPTION 'PROVIDER_RUNTIME_INHERITS_UNTRUSTED_ROLE';
  END IF;

  SELECT pg_catalog.count(*) INTO v_total
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'provider_internal' AND c.relkind = 'r';

  SELECT pg_catalog.count(*) INTO v_rls
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'provider_internal' AND c.relkind = 'r'
    AND c.relrowsecurity AND c.relforcerowsecurity;

  IF v_total = 0 OR v_rls <> v_total THEN
    RAISE EXCEPTION 'PROVIDER_TABLE_RLS_NOT_FULLY_FORCED total %, protected %', v_total, v_rls;
  END IF;
END
$security$;

INSERT INTO provider_internal.partners(id, partner_code, display_name, status)
VALUES ('00000000-0000-4000-8000-000000000101', 'ci-operator', 'CI Operator', 'ACTIVE');

INSERT INTO provider_internal.partner_keys(
  id, partner_id, key_id, auth_profile, protocol_version, secret_reference, status
)
VALUES (
  '00000000-0000-4000-8000-000000000102',
  '00000000-0000-4000-8000-000000000101',
  'ci-key-1', 'ASIX_HMAC_SHA256_V1', 'provider-v1', 'kms://ci/partner-key', 'ACTIVE'
);

INSERT INTO provider_internal.partner_game_configs(
  partner_id, game_code, jurisdiction, currency, currency_exponent,
  min_bet_minor, max_bet_minor, max_win_minor, max_open_exposure_minor, enabled
)
VALUES (
  '00000000-0000-4000-8000-000000000101',
  'ASIX_CI_GAME', 'GE', 'GEL', 2, 100, 2000, 5000, 3000, true
);

INSERT INTO provider_internal.sessions(
  id, partner_id, partner_player_ref, partner_session_ref, game_code,
  jurisdiction, currency, currency_exponent, locale, status, policy_version
)
VALUES
(
  '00000000-0000-4000-8000-000000000103',
  '00000000-0000-4000-8000-000000000101',
  'ci-player-opaque', 'ci-session-launch', 'ASIX_CI_GAME',
  'GE', 'GEL', 2, 'en-GB', 'CREATED', 1
),
(
  '00000000-0000-4000-8000-000000000104',
  '00000000-0000-4000-8000-000000000101',
  'ci-player-opaque', 'ci-session-wallet', 'ASIX_CI_GAME',
  'GE', 'GEL', 2, 'en-GB', 'ACTIVE', 1
);

INSERT INTO provider_internal.rounds(
  id, partner_id, session_id, round_number, game_version, rules_hash, status
)
VALUES (
  '00000000-0000-4000-8000-000000000105',
  '00000000-0000-4000-8000-000000000101',
  '00000000-0000-4000-8000-000000000104',
  1, 'ci-game-v1', pg_catalog.decode(pg_catalog.repeat('11', 32), 'hex'), 'OPEN'
);

INSERT INTO provider_internal.launch_tokens(
  partner_id, session_id, token_hash, expires_at
)
VALUES (
  '00000000-0000-4000-8000-000000000101',
  '00000000-0000-4000-8000-000000000103',
  pg_catalog.decode(pg_catalog.repeat('22', 32), 'hex'),
  pg_catalog.clock_timestamp() + interval '2 minutes'
);

SET ROLE provider_runtime;

DO $nonce_and_launch$
DECLARE
  v_first boolean;
  v_second boolean;
  v_launch_count integer;
BEGIN
  v_first := provider_internal.consume_partner_nonce(
    '00000000-0000-4000-8000-000000000101',
    'ci-key-1',
    pg_catalog.decode(pg_catalog.repeat('33', 32), 'hex'),
    pg_catalog.clock_timestamp() + interval '5 minutes'
  );
  v_second := provider_internal.consume_partner_nonce(
    '00000000-0000-4000-8000-000000000101',
    'ci-key-1',
    pg_catalog.decode(pg_catalog.repeat('33', 32), 'hex'),
    pg_catalog.clock_timestamp() + interval '5 minutes'
  );
  IF NOT v_first OR v_second THEN
    RAISE EXCEPTION 'NONCE_CONSUMPTION_NOT_ONE_TIME';
  END IF;

  SELECT pg_catalog.count(*) INTO v_launch_count
  FROM provider_internal.consume_launch_token(
    pg_catalog.decode(pg_catalog.repeat('22', 32), 'hex')
  );
  IF v_launch_count <> 1 THEN RAISE EXCEPTION 'LAUNCH_TOKEN_FIRST_USE_FAILED'; END IF;

  SELECT pg_catalog.count(*) INTO v_launch_count
  FROM provider_internal.consume_launch_token(
    pg_catalog.decode(pg_catalog.repeat('22', 32), 'hex')
  );
  IF v_launch_count <> 0 THEN RAISE EXCEPTION 'LAUNCH_TOKEN_REPLAY_ACCEPTED'; END IF;
END
$nonce_and_launch$;

DO $wallet$
DECLARE
  v_tx uuid;
  v_status text;
  v_created boolean;
  v_existing_count integer;
BEGIN
  -- Direct table reads are denied even though the SECURITY DEFINER functions work.
  BEGIN
    PERFORM 1 FROM provider_internal.partners;
    RAISE EXCEPTION 'PROVIDER_RUNTIME_DIRECT_TABLE_READ_SUCCEEDED';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  SELECT t.transaction_id, t.transaction_status, t.was_created
    INTO v_tx, v_status, v_created
  FROM provider_internal.create_wallet_transaction(
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000104',
    '00000000-0000-4000-8000-000000000105',
    'ci-bet-idempotency-1',
    pg_catalog.decode(pg_catalog.repeat('44', 32), 'hex'),
    'BET', 1000, 'GEL', 2, NULL
  ) AS t;

  IF v_tx IS NULL OR v_status <> 'CREATED' OR NOT v_created THEN
    RAISE EXCEPTION 'WALLET_BET_CREATE_FAILED';
  END IF;

  SELECT t.transaction_id, t.transaction_status, t.was_created
    INTO v_existing_count, v_status, v_created
  FROM provider_internal.create_wallet_transaction(
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000104',
    '00000000-0000-4000-8000-000000000105',
    'ci-bet-idempotency-1',
    pg_catalog.decode(pg_catalog.repeat('44', 32), 'hex'),
    'BET', 1000, 'GEL', 2, NULL
  ) AS t;

  IF v_existing_count::uuid <> v_tx OR v_created THEN
    RAISE EXCEPTION 'WALLET_IDEMPOTENCY_REPLAY_FAILED';
  END IF;

  BEGIN
    PERFORM * FROM provider_internal.create_wallet_transaction(
      '00000000-0000-4000-8000-000000000101',
      '00000000-0000-4000-8000-000000000104',
      '00000000-0000-4000-8000-000000000105',
      'ci-bet-idempotency-1',
      pg_catalog.decode(pg_catalog.repeat('55', 32), 'hex'),
      'BET', 1000, 'GEL', 2, NULL
    );
    RAISE EXCEPTION 'IDEMPOTENCY_DIFFERENT_HASH_WAS_ACCEPTED';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  BEGIN
    PERFORM * FROM provider_internal.create_wallet_transaction(
      '00000000-0000-4000-8000-000000000101',
      '00000000-0000-4000-8000-000000000104',
      '00000000-0000-4000-8000-000000000105',
      'ci-bet-idempotency-over-limit',
      pg_catalog.decode(pg_catalog.repeat('66', 32), 'hex'),
      'BET', 2500, 'GEL', 2, NULL
    );
    RAISE EXCEPTION 'OPEN_EXPOSURE_LIMIT_WAS_BYPASSED';
  EXCEPTION WHEN SQLSTATE '22003' THEN
    NULL;
  END;

  -- Claim dispatch once; an expired wallet dispatch is converted to UNKNOWN,
  -- never resent, and produces a read-only status-query outbox item.
  SELECT pg_catalog.count(*) INTO v_existing_count
  FROM provider_internal.claim_outbox_events(
    '00000000-0000-4000-8000-000000000199', 10, 5
  );
  IF v_existing_count <> 1 THEN RAISE EXCEPTION 'OUTBOX_DISPATCH_CLAIM_FAILED'; END IF;
END
$wallet$;

RESET ROLE;

-- Simulate the worker crash after dispatch and before response persistence.
UPDATE provider_internal.wallet_transactions
SET dispatch_lease_until = pg_catalog.clock_timestamp() - interval '1 minute'
WHERE id = '00000000-0000-4000-8000-000000000106';

-- The actual transaction id is obtained through the idempotency key above.
UPDATE provider_internal.wallet_transactions
SET dispatch_lease_until = pg_catalog.clock_timestamp() - interval '1 minute'
WHERE partner_id = '00000000-0000-4000-8000-000000000101'
  AND idempotency_key = 'ci-bet-idempotency-1';

SET ROLE provider_runtime;
DO $recovery$
DECLARE
  v_count integer;
  v_status text;
  v_query_events integer;
BEGIN
  v_count := provider_internal.mark_expired_wallet_dispatches_unknown();
  IF v_count <> 1 THEN RAISE EXCEPTION 'EXPIRED_DISPATCH_RECOVERY_FAILED'; END IF;

  SELECT w.status INTO v_status
  FROM provider_internal.wallet_transactions AS w
  WHERE w.partner_id = '00000000-0000-4000-8000-000000000101'
    AND w.idempotency_key = 'ci-bet-idempotency-1';
  IF v_status <> 'UNKNOWN' THEN RAISE EXCEPTION 'EXPIRED_DISPATCH_NOT_UNKNOWN'; END IF;

  SELECT pg_catalog.count(*) INTO v_query_events
  FROM provider_internal.outbox_events AS o
  WHERE o.event_type = 'WALLET_STATUS_QUERY'
    AND o.partner_id = '00000000-0000-4000-8000-000000000101';
  IF v_query_events <> 1 THEN RAISE EXCEPTION 'STATUS_QUERY_EVENT_NOT_CREATED'; END IF;

  SELECT pg_catalog.count(*) INTO v_query_events
  FROM provider_internal.claim_outbox_events(
    '00000000-0000-4000-8000-000000000198', 10, 5
  );
  IF v_query_events <> 1 THEN RAISE EXCEPTION 'STATUS_QUERY_OUTBOX_NOT_CLAIMABLE'; END IF;
END
$recovery$;

RESET ROLE;

-- Simulate the confirmed partner wallet response before testing refund lineage.
UPDATE provider_internal.wallet_transactions
SET status = 'CONFIRMED'
WHERE partner_id = '00000000-0000-4000-8000-000000000101'
  AND idempotency_key = 'ci-bet-idempotency-1';

UPDATE provider_internal.rounds
SET status = 'COMPLETED', completed_at = pg_catalog.clock_timestamp()
WHERE id = '00000000-0000-4000-8000-000000000105';

SET ROLE provider_runtime;
DO $refund_and_win$
DECLARE
  v_original uuid;
  v_refund uuid;
  v_created boolean;
BEGIN
  SELECT w.id INTO v_original
  FROM provider_internal.wallet_transactions AS w
  WHERE w.partner_id = '00000000-0000-4000-8000-000000000101'
    AND w.idempotency_key = 'ci-bet-idempotency-1';

  SELECT t.transaction_id, t.was_created INTO v_refund, v_created
  FROM provider_internal.create_wallet_transaction(
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000104',
    '00000000-0000-4000-8000-000000000105',
    'ci-refund-idempotency-1',
    pg_catalog.decode(pg_catalog.repeat('77', 32), 'hex'),
    'REFUND', 600, 'GEL', 2, v_original
  ) AS t;
  IF v_refund IS NULL OR NOT v_created THEN RAISE EXCEPTION 'VALID_REFUND_CREATE_FAILED'; END IF;

  BEGIN
    PERFORM * FROM provider_internal.create_wallet_transaction(
      '00000000-0000-4000-8000-000000000101',
      '00000000-0000-4000-8000-000000000104',
      '00000000-0000-4000-8000-000000000105',
      'ci-refund-over-idempotency',
      pg_catalog.decode(pg_catalog.repeat('88', 32), 'hex'),
      'REFUND', 500, 'GEL', 2, v_original
    );
    RAISE EXCEPTION 'OVER_REFUND_WAS_ACCEPTED';
  EXCEPTION WHEN SQLSTATE '22003' THEN
    NULL;
  END;

  -- Wins are allowed only for completed rounds; cumulative win cap is enforced.
  PERFORM * FROM provider_internal.create_wallet_transaction(
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000104',
    '00000000-0000-4000-8000-000000000105',
    'ci-win-idempotency-1',
    pg_catalog.decode(pg_catalog.repeat('99', 32), 'hex'),
    'WIN', 3000, 'GEL', 2, NULL
  );

  BEGIN
    PERFORM * FROM provider_internal.create_wallet_transaction(
      '00000000-0000-4000-8000-000000000101',
      '00000000-0000-4000-8000-000000000104',
      '00000000-0000-4000-8000-000000000105',
      'ci-win-over-idempotency',
      pg_catalog.decode(pg_catalog.repeat('aa', 32), 'hex'),
      'WIN', 2500, 'GEL', 2, NULL
    );
    RAISE EXCEPTION 'CUMULATIVE_ROUND_WIN_LIMIT_WAS_BYPASSED';
  EXCEPTION WHEN SQLSTATE '22003' THEN
    NULL;
  END;
END
$refund_and_win$;

RESET ROLE;

-- Ledger posting, balance validation and immutability.
INSERT INTO provider_internal.ledger_accounts(id, partner_id, account_code, account_type, currency)
VALUES
('00000000-0000-4000-8000-000000000201','00000000-0000-4000-8000-000000000101','CLEARING','CLEARING','GEL'),
('00000000-0000-4000-8000-000000000202','00000000-0000-4000-8000-000000000101','PROVIDER_PAYABLE','LIABILITY','GEL');

INSERT INTO provider_internal.ledger_journals(
  id, partner_id, source_type, source_ref, journal_type, currency, status
)
VALUES (
  '00000000-0000-4000-8000-000000000203',
  '00000000-0000-4000-8000-000000000101',
  'WALLET_TRANSACTION', 'ci-ledger-source-1', 'TEST_POST', 'GEL', 'DRAFT'
);

INSERT INTO provider_internal.ledger_entries(
  journal_id, partner_id, account_id, currency, direction, amount_minor
)
VALUES
('00000000-0000-4000-8000-000000000203','00000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000201','GEL','DEBIT',1000),
('00000000-0000-4000-8000-000000000203','00000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000202','GEL','CREDIT',1000);

SET ROLE provider_runtime;
DO $ledger$
DECLARE v_posted boolean;
BEGIN
  v_posted := provider_internal.post_ledger_journal(
    '00000000-0000-4000-8000-000000000203',
    pg_catalog.decode(pg_catalog.repeat('bb', 32), 'hex')
  );
  IF NOT v_posted THEN RAISE EXCEPTION 'BALANCED_JOURNAL_NOT_POSTED'; END IF;
END
$ledger$;
RESET ROLE;

DO $ledger_immutability$
BEGIN
  BEGIN
    UPDATE provider_internal.ledger_journals
    SET source_ref = 'mutated'
    WHERE id = '00000000-0000-4000-8000-000000000203';
    RAISE EXCEPTION 'POSTED_JOURNAL_HEADER_MUTATED';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;

  BEGIN
    UPDATE provider_internal.ledger_entries
    SET amount_minor = 999
    WHERE journal_id = '00000000-0000-4000-8000-000000000203';
    RAISE EXCEPTION 'POSTED_JOURNAL_ENTRY_MUTATED';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
END
$ledger_immutability$;

-- Successful completion prints one final marker for CI logs.
SELECT 'PROVIDER_DATABASE_SMOKE_TESTS_PASSED' AS result;
