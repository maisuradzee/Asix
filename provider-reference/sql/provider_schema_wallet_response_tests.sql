\set ON_ERROR_STOP on

-- Earlier isolated smoke scenarios intentionally leave unrelated wallet
-- dispatch events behind. Mark only those old fixture events out of scope so
-- this test claims precisely the concurrent Bet dispatch under test.
UPDATE provider_internal.outbox_events
SET state = 'SUPERSEDED', lease_owner = NULL, lease_until = NULL
WHERE partner_id = '00000000-0000-4000-8000-000000000101'::uuid
  AND state IN ('READY','RETRY','LEASED');

SET ROLE provider_runtime;

DO $dispatch_response$
DECLARE
  v_transaction_id uuid;
  v_request_hash bytea;
  v_transaction_status text;
  v_generation integer;
  v_was_recorded boolean;
  v_claim_count integer;
BEGIN
  -- Exactly one of the two simultaneous Bet requests was accepted.
  SELECT q.transaction_id INTO v_transaction_id
  FROM provider_internal.get_wallet_transaction_status(
    '00000000-0000-4000-8000-000000000301'::uuid,
    'ci-concurrent-bet-a'::text
  ) AS q;

  IF v_transaction_id IS NOT NULL THEN
    v_request_hash := pg_catalog.decode(pg_catalog.repeat('c5', 32), 'hex');
  ELSE
    SELECT q.transaction_id INTO v_transaction_id
    FROM provider_internal.get_wallet_transaction_status(
      '00000000-0000-4000-8000-000000000301'::uuid,
      'ci-concurrent-bet-b'::text
    ) AS q;
    v_request_hash := pg_catalog.decode(pg_catalog.repeat('c6', 32), 'hex');
  END IF;

  IF v_transaction_id IS NULL THEN
    RAISE EXCEPTION 'NO_ACCEPTED_CONCURRENT_BET_FOUND';
  END IF;

  SELECT pg_catalog.count(*) INTO v_claim_count
  FROM provider_internal.claim_outbox_events(
    '00000000-0000-4000-8000-000000000196'::uuid, 10, 30
  );
  IF v_claim_count <> 1 THEN
    RAISE EXCEPTION 'DISPATCH_OUTBOX_NOT_CLAIMED_FOR_RESPONSE_TEST';
  END IF;

  -- A stale/different worker cannot persist a response for this lease.
  BEGIN
    PERFORM * FROM provider_internal.record_wallet_partner_response(
      '00000000-0000-4000-8000-000000000301'::uuid,
      '00000000-0000-4000-8000-000000000195'::uuid,
      v_transaction_id,
      'DISPATCH'::text,
      0,
      1,
      v_request_hash,
      pg_catalog.decode(pg_catalog.repeat('e1', 32), 'hex'),
      'CONFIRMED'::text,
      'OK'::text,
      'ci-concurrent-bet-partner-ref'::text,
      NULL::timestamptz
    );
    RAISE EXCEPTION 'STALE_WORKER_RESPONSE_WAS_ACCEPTED';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;

  SELECT r.transaction_status, r.status_query_generation, r.was_recorded
    INTO v_transaction_status, v_generation, v_was_recorded
  FROM provider_internal.record_wallet_partner_response(
    '00000000-0000-4000-8000-000000000301'::uuid,
    '00000000-0000-4000-8000-000000000196'::uuid,
    v_transaction_id,
    'DISPATCH'::text,
    0,
    1,
    v_request_hash,
    pg_catalog.decode(pg_catalog.repeat('e1', 32), 'hex'),
    'CONFIRMED'::text,
    'OK'::text,
    'ci-concurrent-bet-partner-ref'::text,
    NULL::timestamptz
  ) AS r;

  IF v_transaction_status <> 'CONFIRMED' OR v_generation <> 0 OR NOT v_was_recorded THEN
    RAISE EXCEPTION 'DISPATCH_CONFIRMED_RESPONSE_NOT_RECORDED';
  END IF;

  -- Duplicate persistence with the same attempt number and exact evidence
  -- must return the stored result without creating another financial effect.
  SELECT r.transaction_status, r.status_query_generation, r.was_recorded
    INTO v_transaction_status, v_generation, v_was_recorded
  FROM provider_internal.record_wallet_partner_response(
    '00000000-0000-4000-8000-000000000301'::uuid,
    '00000000-0000-4000-8000-000000000196'::uuid,
    v_transaction_id,
    'DISPATCH'::text,
    0,
    1,
    v_request_hash,
    pg_catalog.decode(pg_catalog.repeat('e1', 32), 'hex'),
    'CONFIRMED'::text,
    'OK'::text,
    'ci-concurrent-bet-partner-ref'::text,
    NULL::timestamptz
  ) AS r;

  IF v_transaction_status <> 'CONFIRMED' OR v_was_recorded THEN
    RAISE EXCEPTION 'DISPATCH_RESPONSE_REPLAY_NOT_IDEMPOTENT';
  END IF;
END
$dispatch_response$;

RESET ROLE;
SELECT 'PROVIDER_WALLET_RESPONSE_PERSISTENCE_PASSED' AS result;
