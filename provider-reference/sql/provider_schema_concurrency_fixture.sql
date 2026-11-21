-- Seed data for concurrency tests in disposable PostgreSQL 17 CI only.
-- Assumes provider_schema_proposal.sql and provider_schema_smoke_tests.sql ran.

INSERT INTO provider_internal.partners(id, partner_code, display_name, status)
VALUES (
  '00000000-0000-4000-8000-000000000301'::uuid,
  'ci-concurrency-operator',
  'CI Concurrency Operator',
  'ACTIVE'
);

INSERT INTO provider_internal.partner_keys(
  partner_id, key_id, auth_profile, protocol_version, secret_reference, status
)
VALUES (
  '00000000-0000-4000-8000-000000000301'::uuid,
  'ci-concurrency-key',
  'ASIX_HMAC_SHA256_V1',
  'provider-v1',
  'kms://ci/concurrency-operator/key',
  'ACTIVE'
);

INSERT INTO provider_internal.partner_game_configs(
  partner_id, game_code, jurisdiction, currency, currency_exponent,
  min_bet_minor, max_bet_minor, max_win_minor, max_open_exposure_minor, enabled
)
VALUES (
  '00000000-0000-4000-8000-000000000301'::uuid,
  'ASIX_CI_CONCURRENCY', 'GE', 'GEL', 2,
  100, 2000, 5000, 1500, true
), (
  '00000000-0000-4000-8000-000000000301'::uuid,
  'ASIX_CI_LAUNCH', 'GE', 'GEL', 2,
  100, 2000, 5000, 1500, true
);

INSERT INTO provider_internal.sessions(
  id, partner_id, partner_player_ref, partner_session_ref, game_code,
  jurisdiction, currency, currency_exponent, locale, status, policy_version
)
VALUES
(
  '00000000-0000-4000-8000-000000000302'::uuid,
  '00000000-0000-4000-8000-000000000301'::uuid,
  'ci-player-a', 'ci-conc-bet-session-a', 'ASIX_CI_CONCURRENCY',
  'GE', 'GEL', 2, 'en-GB', 'ACTIVE', 'policy-1'
),
(
  '00000000-0000-4000-8000-000000000304'::uuid,
  '00000000-0000-4000-8000-000000000301'::uuid,
  'ci-player-b', 'ci-conc-bet-session-b', 'ASIX_CI_CONCURRENCY',
  'GE', 'GEL', 2, 'en-GB', 'ACTIVE', 'policy-1'
),
(
  '00000000-0000-4000-8000-000000000306'::uuid,
  '00000000-0000-4000-8000-000000000301'::uuid,
  'ci-player-refund', 'ci-conc-refund-session', 'ASIX_CI_CONCURRENCY',
  'GE', 'GEL', 2, 'en-GB', 'ACTIVE', 'policy-1'
);

INSERT INTO provider_internal.rounds(
  id, partner_id, session_id, round_number, game_version, rules_hash, status, completed_at
)
VALUES
(
  '00000000-0000-4000-8000-000000000303'::uuid,
  '00000000-0000-4000-8000-000000000301'::uuid,
  '00000000-0000-4000-8000-000000000302'::uuid,
  1, 'ci-concurrency-v1', pg_catalog.decode(pg_catalog.repeat('c1', 32), 'hex'), 'OPEN', NULL
),
(
  '00000000-0000-4000-8000-000000000305'::uuid,
  '00000000-0000-4000-8000-000000000301'::uuid,
  '00000000-0000-4000-8000-000000000304'::uuid,
  1, 'ci-concurrency-v1', pg_catalog.decode(pg_catalog.repeat('c2', 32), 'hex'), 'OPEN', NULL
),
(
  '00000000-0000-4000-8000-000000000307'::uuid,
  '00000000-0000-4000-8000-000000000301'::uuid,
  '00000000-0000-4000-8000-000000000306'::uuid,
  1, 'ci-concurrency-v1', pg_catalog.decode(pg_catalog.repeat('c3', 32), 'hex'),
  'COMPLETED', pg_catalog.clock_timestamp()
);

-- Pre-existing confirmed debit of 500 minor units; two simultaneous refunds
-- of 300 must not both succeed (combined refunds would be 600).
INSERT INTO provider_internal.wallet_transactions(
  id, partner_id, session_id, round_id, idempotency_key, request_hash,
  operation, amount_minor, currency, currency_exponent, status, partner_transaction_ref
)
VALUES (
  '00000000-0000-4000-8000-000000000308'::uuid,
  '00000000-0000-4000-8000-000000000301'::uuid,
  '00000000-0000-4000-8000-000000000306'::uuid,
  '00000000-0000-4000-8000-000000000307'::uuid,
  'ci-conc-original-bet',
  pg_catalog.decode(pg_catalog.repeat('c4', 32), 'hex'),
  'BET', 500, 'GEL', 2, 'CONFIRMED', 'ci-conc-original-partner-ref'
);
