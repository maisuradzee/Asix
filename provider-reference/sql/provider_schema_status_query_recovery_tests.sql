\set ON_ERROR_STOP on

-- This is an isolated PostgreSQL 17 CI test, never run against live ASIX.
-- Use the confirmed wallet transaction produced by the preceding response test.
INSERT INTO provider_internal.outbox_events(
  partner_id, wallet_transaction_id, event_type, generation, dedupe_key, payload,
  state, attempts, max_attempts, available_at, lease_owner, lease_token, lease_until
)
SELECT
  w.partner_id,
  w.id,
  'WALLET_STATUS_QUERY',
  fixture.generation,
  fixture.dedupe_key,
  pg_catalog.jsonb_build_object('transaction_id', w.id),
  'LEASED',
  fixture.attempts,
  fixture.max_attempts,
  pg_catalog.clock_timestamp() - interval '1 minute',
  '00000000-0000-4000-8000-000000000195'::uuid,
  fixture.stale_token,
  pg_catalog.clock_timestamp() - interval '1 second'
FROM provider_internal.wallet_transactions AS w
CROSS JOIN (
  VALUES
    (77, 'ci-status-recovery-retry', 1, 3,
     '00000000-0000-4000-8000-000000000177'::uuid),
    (78, 'ci-status-recovery-dead-letter', 3, 3,
     '00000000-0000-4000-8000-000000000178'::uuid)
) AS fixture(generation, dedupe_key, attempts, max_attempts, stale_token)
WHERE w.partner_id = '00000000-0000-4000-8000-000000000301'::uuid
  AND w.partner_transaction_ref = 'ci-concurrent-bet-partner-ref';

DO $assert_seed$
DECLARE v_count integer;
BEGIN
  SELECT pg_catalog.count(*) INTO v_count
  FROM provider_internal.outbox_events
  WHERE dedupe_key IN ('ci-status-recovery-retry','ci-status-recovery-dead-letter');
  IF v_count <> 2 THEN RAISE EXCEPTION 'STATUS_QUERY_RECOVERY_FIXTURE_NOT_SEEDED'; END IF;
END
$assert_seed$;

SET ROLE provider_runtime;

DO $status_query_recovery$
DECLARE
  v_recovered integer;
  v_claimed provider_internal.outbox_events%ROWTYPE;
BEGIN
  v_recovered := provider_internal.recover_expired_wallet_status_query_leases(1);
  IF v_recovered <> 2 THEN
    RAISE EXCEPTION 'EXPIRED_STATUS_QUERY_LEASE_RECOVERY_COUNT_MISMATCH';
  END IF;

  -- The retry event is delayed by the bounded backoff. Dead-lettered events
  -- are terminal and are not returned by claim_outbox_events.
  PERFORM pg_catalog.pg_sleep(1.2);

  SELECT e.* INTO v_claimed
  FROM provider_internal.claim_outbox_events(
    '00000000-0000-4000-8000-000000000196'::uuid, 10, 30
  ) AS e
  WHERE e.dedupe_key = 'ci-status-recovery-retry';

  IF NOT FOUND
     OR v_claimed.event_type <> 'WALLET_STATUS_QUERY'
     OR v_claimed.state <> 'LEASED'
     OR v_claimed.lease_owner <> '00000000-0000-4000-8000-000000000196'::uuid
     OR v_claimed.lease_token IS NULL
     OR v_claimed.lease_token = '00000000-0000-4000-8000-000000000177'::uuid THEN
    RAISE EXCEPTION 'EXPIRED_STATUS_QUERY_DID_NOT_RECLAIM_WITH_NEW_LEASE_TOKEN';
  END IF;
END
$status_query_recovery$;

RESET ROLE;

DO $status_query_terminal_check$
DECLARE
  v_retry_state text;
  v_dead_state text;
  v_dead_token uuid;
BEGIN
  SELECT state INTO v_retry_state
  FROM provider_internal.outbox_events
  WHERE dedupe_key = 'ci-status-recovery-retry';

  SELECT state, lease_token INTO v_dead_state, v_dead_token
  FROM provider_internal.outbox_events
  WHERE dedupe_key = 'ci-status-recovery-dead-letter';

  IF v_retry_state <> 'LEASED' THEN
    RAISE EXCEPTION 'STATUS_QUERY_RETRY_EVENT_NOT_RECLAIMED';
  END IF;
  IF v_dead_state <> 'DEAD_LETTER' OR v_dead_token IS NOT NULL THEN
    RAISE EXCEPTION 'STATUS_QUERY_ATTEMPT_LIMIT_DID_NOT_DEAD_LETTER';
  END IF;
END
$status_query_terminal_check$;

SELECT 'PROVIDER_STATUS_QUERY_LEASE_RECOVERY_PASSED' AS result;
