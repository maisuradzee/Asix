-- ASIX B2B PROVIDER DATABASE SCHEMA — DESIGN PROPOSAL ONLY
-- DO NOT EXECUTE AGAINST THE LIVE ASIX PROJECT.
--
-- This file is outside supabase/migrations/. It has not been executed or
-- validated by PostgreSQL. Review and test only after restoring a verified
-- V154 snapshot into isolated staging.
--
-- Domain boundary:
--   * provider_internal is not exposed through the Supabase Data API/GraphQL.
--   * Existing public and asix_internal objects are unchanged.
--   * provider_owner owns tables and SECURITY DEFINER routines.
--   * provider_runtime gets schema USAGE and EXECUTE on approved routines,
--     but no direct table privileges.
--   * A dedicated LOGIN role is provisioned out-of-band as a member of
--     provider_runtime. The application executes SET ROLE provider_runtime.
--   * Never use postgres or the Supabase service_role key for Provider runtime.

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'provider_owner') THEN
    CREATE ROLE provider_owner NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'provider_runtime') THEN
    CREATE ROLE provider_runtime NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
  END IF;
END
$roles$;

CREATE SCHEMA IF NOT EXISTS provider_internal AUTHORIZATION provider_owner;
REVOKE ALL ON SCHEMA provider_internal FROM PUBLIC;
REVOKE ALL ON SCHEMA provider_internal FROM anon, authenticated, service_role;
GRANT USAGE ON SCHEMA provider_internal TO provider_runtime;

SET ROLE provider_owner;

CREATE TABLE provider_internal.partners (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  partner_code text NOT NULL UNIQUE CHECK (partner_code ~ '^[a-z0-9][a-z0-9_-]{1,63}$'),
  display_name text NOT NULL CHECK (pg_catalog.length(display_name) BETWEEN 1 AND 160),
  status text NOT NULL DEFAULT 'ONBOARDING'
    CHECK (status IN ('ONBOARDING','ACTIVE','SUSPENDED','TERMINATED')),
  default_jurisdiction text,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp()
);

CREATE TABLE provider_internal.partner_keys (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  partner_id uuid NOT NULL REFERENCES provider_internal.partners(id),
  key_id text NOT NULL CHECK (pg_catalog.length(key_id) BETWEEN 1 AND 128),
  auth_profile text NOT NULL CHECK (auth_profile IN (
    'ASIX_HMAC_SHA256_V1','ECDSA_P256_SHA256_PAYLOAD_V1','MTLS','OAUTH2_JWT'
  )),
  protocol_version text NOT NULL CHECK (pg_catalog.length(protocol_version) BETWEEN 1 AND 64),
  secret_reference text,
  public_key_reference text,
  status text NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING','ACTIVE','RETIRING','REVOKED')),
  valid_from timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  valid_until timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (partner_id, key_id),
  CHECK (valid_until IS NULL OR valid_until > valid_from),
  CHECK (
    (auth_profile = 'ASIX_HMAC_SHA256_V1' AND secret_reference IS NOT NULL)
    OR (auth_profile = 'ECDSA_P256_SHA256_PAYLOAD_V1' AND public_key_reference IS NOT NULL)
    OR auth_profile IN ('MTLS','OAUTH2_JWT')
  )
);

CREATE TABLE provider_internal.partner_game_configs (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  partner_id uuid NOT NULL REFERENCES provider_internal.partners(id),
  game_code text NOT NULL,
  jurisdiction text NOT NULL CHECK (jurisdiction ~ '^[A-Z0-9_-]{2,8}$'),
  currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  currency_exponent smallint NOT NULL CHECK (currency_exponent BETWEEN 0 AND 6),
  min_bet_minor bigint NOT NULL DEFAULT 1 CHECK (min_bet_minor > 0),
  max_bet_minor bigint NOT NULL CHECK (max_bet_minor >= min_bet_minor),
  max_win_minor bigint NOT NULL CHECK (max_win_minor > 0),
  max_open_exposure_minor bigint NOT NULL CHECK (max_open_exposure_minor > 0),
  enabled boolean NOT NULL DEFAULT false,
  config_version integer NOT NULL DEFAULT 1 CHECK (config_version > 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (partner_id, game_code, jurisdiction, currency)
);

CREATE TABLE provider_internal.partner_nonces (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  partner_id uuid NOT NULL,
  key_id text NOT NULL,
  nonce_hash bytea NOT NULL CHECK (pg_catalog.octet_length(nonce_hash) = 32),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (partner_id, key_id, nonce_hash),
  FOREIGN KEY (partner_id, key_id)
    REFERENCES provider_internal.partner_keys(partner_id, key_id)
);
CREATE INDEX provider_partner_nonces_expiry_idx
  ON provider_internal.partner_nonces(expires_at);

CREATE TABLE provider_internal.sessions (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  partner_id uuid NOT NULL REFERENCES provider_internal.partners(id),
  partner_player_ref text NOT NULL CHECK (pg_catalog.length(partner_player_ref) BETWEEN 1 AND 200),
  partner_session_ref text NOT NULL CHECK (pg_catalog.length(partner_session_ref) BETWEEN 1 AND 200),
  game_code text NOT NULL,
  jurisdiction text NOT NULL,
  currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  currency_exponent smallint NOT NULL CHECK (currency_exponent BETWEEN 0 AND 6),
  locale text NOT NULL,
  status text NOT NULL DEFAULT 'CREATED'
    CHECK (status IN ('CREATED','ACTIVE','PAUSED','COMPLETED','CANCELLED','EXCEPTION')),
  policy_version integer NOT NULL CHECK (policy_version > 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  started_at timestamptz,
  closed_at timestamptz,
  UNIQUE (partner_id, partner_session_ref),
  UNIQUE (id, partner_id)
);
CREATE INDEX provider_sessions_partner_player_idx
  ON provider_internal.sessions(partner_id, partner_player_ref, created_at DESC);

CREATE TABLE provider_internal.launch_tokens (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  partner_id uuid NOT NULL,
  session_id uuid NOT NULL,
  token_hash bytea NOT NULL UNIQUE CHECK (pg_catalog.octet_length(token_hash) = 32),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  FOREIGN KEY (session_id, partner_id)
    REFERENCES provider_internal.sessions(id, partner_id)
);
CREATE INDEX provider_launch_tokens_expiry_idx
  ON provider_internal.launch_tokens(expires_at) WHERE consumed_at IS NULL;

CREATE TABLE provider_internal.rounds (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  partner_id uuid NOT NULL,
  session_id uuid NOT NULL,
  partner_round_ref text,
  round_number bigint NOT NULL CHECK (round_number > 0),
  game_version text NOT NULL,
  rules_hash bytea NOT NULL CHECK (pg_catalog.octet_length(rules_hash) = 32),
  result_hash bytea CHECK (result_hash IS NULL OR pg_catalog.octet_length(result_hash) = 32),
  status text NOT NULL DEFAULT 'OPEN'
    CHECK (status IN ('OPEN','COMPLETED','VOID_PENDING','VOIDED','EXCEPTION')),
  started_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  completed_at timestamptz,
  UNIQUE (session_id, round_number),
  UNIQUE (id, partner_id),
  FOREIGN KEY (session_id, partner_id)
    REFERENCES provider_internal.sessions(id, partner_id)
);

CREATE TABLE provider_internal.wallet_transactions (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  partner_id uuid NOT NULL REFERENCES provider_internal.partners(id),
  session_id uuid NOT NULL,
  round_id uuid,
  idempotency_key text NOT NULL CHECK (pg_catalog.length(idempotency_key) BETWEEN 1 AND 200),
  request_hash bytea NOT NULL CHECK (pg_catalog.octet_length(request_hash) = 32),
  operation text NOT NULL CHECK (operation IN ('BET','WIN','REFUND')),
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  currency_exponent smallint NOT NULL CHECK (currency_exponent BETWEEN 0 AND 6),
  status text NOT NULL DEFAULT 'CREATED'
    CHECK (status IN ('CREATED','DISPATCHING','CONFIRMED','DECLINED','PENDING','UNKNOWN','RECONCILED','EXCEPTION')),
  partner_transaction_ref text,
  original_transaction_id uuid,
  dispatch_started_at timestamptz,
  dispatch_lease_until timestamptz,
  status_query_generation integer NOT NULL DEFAULT 0 CHECK (status_query_generation >= 0),
  response_code text,
  response_hash bytea CHECK (response_hash IS NULL OR pg_catalog.octet_length(response_hash) = 32),
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (partner_id, idempotency_key),
  UNIQUE (id, partner_id),
  FOREIGN KEY (session_id, partner_id)
    REFERENCES provider_internal.sessions(id, partner_id),
  FOREIGN KEY (round_id, partner_id)
    REFERENCES provider_internal.rounds(id, partner_id),
  FOREIGN KEY (original_transaction_id, partner_id)
    REFERENCES provider_internal.wallet_transactions(id, partner_id),
  CHECK (
    (operation = 'REFUND' AND original_transaction_id IS NOT NULL)
    OR (operation IN ('BET','WIN') AND original_transaction_id IS NULL)
  )
);
CREATE UNIQUE INDEX provider_wallet_partner_reference_uq
  ON provider_internal.wallet_transactions(partner_id, partner_transaction_ref)
  WHERE partner_transaction_ref IS NOT NULL;
CREATE INDEX provider_wallet_status_age_idx
  ON provider_internal.wallet_transactions(partner_id, status, created_at);

CREATE TABLE provider_internal.wallet_attempts (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  transaction_id uuid NOT NULL REFERENCES provider_internal.wallet_transactions(id),
  attempt_number integer NOT NULL CHECK (attempt_number > 0),
  attempt_kind text NOT NULL CHECK (attempt_kind IN ('DISPATCH','STATUS_QUERY')),
  request_hash bytea NOT NULL CHECK (pg_catalog.octet_length(request_hash) = 32),
  response_hash bytea CHECK (response_hash IS NULL OR pg_catalog.octet_length(response_hash) = 32),
  transport_state text NOT NULL
    CHECK (transport_state IN ('SENT','RESPONSE','TIMEOUT','TRANSPORT_ERROR','MALFORMED_RESPONSE')),
  partner_response_code text,
  started_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  completed_at timestamptz,
  UNIQUE (transaction_id, attempt_number)
);

CREATE TABLE provider_internal.outbox_events (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  partner_id uuid NOT NULL REFERENCES provider_internal.partners(id),
  wallet_transaction_id uuid NOT NULL,
  event_type text NOT NULL CHECK (event_type IN ('WALLET_DISPATCH','WALLET_STATUS_QUERY')),
  generation integer NOT NULL DEFAULT 0 CHECK (generation >= 0),
  dedupe_key text NOT NULL UNIQUE,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  state text NOT NULL DEFAULT 'READY'
    CHECK (state IN ('READY','LEASED','RETRY','DELIVERED','SUPERSEDED','DEAD_LETTER')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  max_attempts integer NOT NULL DEFAULT 10 CHECK (max_attempts > 0),
  available_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  lease_owner uuid,
  lease_until timestamptz,
  last_error_code text,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  delivered_at timestamptz,
  FOREIGN KEY (wallet_transaction_id, partner_id)
    REFERENCES provider_internal.wallet_transactions(id, partner_id),
  UNIQUE (wallet_transaction_id, event_type, generation)
);
CREATE INDEX provider_outbox_ready_idx
  ON provider_internal.outbox_events(state, available_at, created_at)
  WHERE state IN ('READY','RETRY','LEASED');

CREATE TABLE provider_internal.ledger_accounts (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  partner_id uuid NOT NULL REFERENCES provider_internal.partners(id),
  account_code text NOT NULL CHECK (pg_catalog.length(account_code) BETWEEN 1 AND 100),
  account_type text NOT NULL
    CHECK (account_type IN ('ASSET','LIABILITY','EQUITY','REVENUE','EXPENSE','CLEARING')),
  currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (partner_id, account_code, currency),
  UNIQUE (id, partner_id, currency)
);

CREATE TABLE provider_internal.ledger_journals (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  partner_id uuid NOT NULL REFERENCES provider_internal.partners(id),
  source_type text NOT NULL CHECK (source_type IN ('WALLET_TRANSACTION','SETTLEMENT','ADJUSTMENT','REVERSAL')),
  source_ref text NOT NULL,
  journal_type text NOT NULL CHECK (pg_catalog.length(journal_type) BETWEEN 1 AND 64),
  currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','POSTED')),
  journal_hash bytea CHECK (journal_hash IS NULL OR pg_catalog.octet_length(journal_hash) = 32),
  reversal_of_journal_id uuid,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  posted_at timestamptz,
  UNIQUE (partner_id, source_type, source_ref, journal_type),
  UNIQUE (id, partner_id, currency),
  FOREIGN KEY (reversal_of_journal_id, partner_id, currency)
    REFERENCES provider_internal.ledger_journals(id, partner_id, currency)
);

CREATE TABLE provider_internal.ledger_entries (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  journal_id uuid NOT NULL,
  partner_id uuid NOT NULL,
  account_id uuid NOT NULL,
  currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  direction text NOT NULL CHECK (direction IN ('DEBIT','CREDIT')),
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  FOREIGN KEY (journal_id, partner_id, currency)
    REFERENCES provider_internal.ledger_journals(id, partner_id, currency),
  FOREIGN KEY (account_id, partner_id, currency)
    REFERENCES provider_internal.ledger_accounts(id, partner_id, currency)
);
CREATE INDEX provider_ledger_entries_journal_idx
  ON provider_internal.ledger_entries(journal_id);

CREATE TABLE provider_internal.reconciliation_runs (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  partner_id uuid NOT NULL REFERENCES provider_internal.partners(id),
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  statement_reference text,
  status text NOT NULL DEFAULT 'OPEN'
    CHECK (status IN ('OPEN','MATCHED','HAS_EXCEPTIONS','CLOSED')),
  input_hash bytea CHECK (input_hash IS NULL OR pg_catalog.octet_length(input_hash) = 32),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  closed_at timestamptz,
  CHECK (period_end > period_start),
  UNIQUE (partner_id, period_start, period_end, statement_reference)
);

CREATE TABLE provider_internal.reconciliation_items (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  run_id uuid NOT NULL REFERENCES provider_internal.reconciliation_runs(id),
  wallet_transaction_id uuid REFERENCES provider_internal.wallet_transactions(id),
  partner_transaction_ref text,
  match_state text NOT NULL CHECK (match_state IN (
    'MATCHED','ASIX_DELAYED','PARTNER_DELAYED','DUPLICATE','AMOUNT_MISMATCH',
    'CURRENCY_MISMATCH','STATUS_MISMATCH','UNKNOWN_UNRESOLVED','UNCLASSIFIED'
  )),
  asix_amount_minor bigint,
  partner_amount_minor bigint,
  currency text CHECK (currency IS NULL OR currency ~ '^[A-Z]{3}$'),
  details_hash bytea CHECK (details_hash IS NULL OR pg_catalog.octet_length(details_hash) = 32),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp()
);

CREATE TABLE provider_internal.commercial_contract_versions (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  partner_id uuid NOT NULL REFERENCES provider_internal.partners(id),
  contract_reference text NOT NULL,
  version text NOT NULL,
  fee_model text NOT NULL CHECK (fee_model IN ('REVENUE_SHARE','FIXED_FEE','HYBRID')),
  currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  revenue_share_bps integer NOT NULL DEFAULT 0 CHECK (revenue_share_bps BETWEEN 0 AND 10000),
  fixed_fee_minor bigint NOT NULL DEFAULT 0 CHECK (fixed_fee_minor >= 0),
  ggr_definition jsonb NOT NULL,
  rounding_mode text NOT NULL CHECK (rounding_mode IN ('FLOOR','HALF_UP')),
  negative_ggr_policy text NOT NULL CHECK (negative_ggr_policy IN ('FLOOR_AT_ZERO','CARRY_FORWARD')),
  effective_from timestamptz NOT NULL,
  effective_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (partner_id, contract_reference, version),
  CHECK (effective_until IS NULL OR effective_until > effective_from),
  CHECK (
    (fee_model = 'REVENUE_SHARE' AND revenue_share_bps > 0 AND fixed_fee_minor = 0)
    OR (fee_model = 'FIXED_FEE' AND revenue_share_bps = 0 AND fixed_fee_minor > 0)
    OR (fee_model = 'HYBRID' AND revenue_share_bps > 0 AND fixed_fee_minor > 0)
  )
);

CREATE TABLE provider_internal.settlement_runs (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  partner_id uuid NOT NULL REFERENCES provider_internal.partners(id),
  contract_version_id uuid NOT NULL REFERENCES provider_internal.commercial_contract_versions(id),
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  calculation_hash bytea CHECK (calculation_hash IS NULL OR pg_catalog.octet_length(calculation_hash) = 32),
  total_provider_fee_minor bigint,
  status text NOT NULL DEFAULT 'DRAFT'
    CHECK (status IN ('DRAFT','REVIEW','APPROVED','RELEASED','DISPUTED','CANCELLED')),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  approved_at timestamptz,
  released_at timestamptz,
  CHECK (period_end > period_start),
  CHECK (total_provider_fee_minor IS NULL OR total_provider_fee_minor >= 0)
);

CREATE TABLE provider_internal.approval_requests (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  partner_id uuid REFERENCES provider_internal.partners(id),
  request_type text NOT NULL
    CHECK (request_type IN ('MANUAL_ADJUSTMENT','SETTLEMENT_RELEASE','LIMIT_CHANGE','PARTNER_REACTIVATION','KEY_ACTIVATION')),
  target_reference text NOT NULL,
  reason text NOT NULL CHECK (pg_catalog.length(reason) BETWEEN 5 AND 2000),
  evidence_hash bytea NOT NULL CHECK (pg_catalog.octet_length(evidence_hash) = 32),
  status text NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING','APPROVED','REJECTED','CANCELLED')),
  requested_by text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  resolved_at timestamptz
);

CREATE TABLE provider_internal.approval_decisions (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  approval_request_id uuid NOT NULL REFERENCES provider_internal.approval_requests(id),
  approver_ref text NOT NULL,
  decision text NOT NULL CHECK (decision IN ('APPROVE','REJECT','REQUEST_MORE_EVIDENCE')),
  reason text,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (approval_request_id, approver_ref)
);

CREATE TABLE provider_internal.audit_events (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  partner_id uuid REFERENCES provider_internal.partners(id),
  actor_type text NOT NULL CHECK (actor_type IN ('PARTNER','SYSTEM','STAFF','POLICY_ENGINE')),
  actor_ref text,
  action_code text NOT NULL,
  target_type text NOT NULL,
  target_ref text NOT NULL,
  correlation_id uuid,
  payload_hash bytea NOT NULL CHECK (pg_catalog.octet_length(payload_hash) = 32),
  occurred_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp()
);

CREATE TABLE provider_internal.incidents (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  partner_id uuid REFERENCES provider_internal.partners(id),
  severity text NOT NULL CHECK (severity IN ('YELLOW','RED')),
  incident_type text NOT NULL,
  state text NOT NULL DEFAULT 'OPEN' CHECK (state IN ('OPEN','MITIGATING','MONITORING','CLOSED')),
  summary text NOT NULL,
  evidence_hash bytea CHECK (evidence_hash IS NULL OR pg_catalog.octet_length(evidence_hash) = 32),
  opened_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  closed_at timestamptz
);

CREATE OR REPLACE FUNCTION provider_internal.guard_posted_journal_immutability()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_journal_id uuid; v_status text;
BEGIN
  IF TG_OP = 'INSERT' THEN v_journal_id := NEW.journal_id;
  ELSE v_journal_id := OLD.journal_id; END IF;
  SELECT j.status INTO v_status FROM provider_internal.ledger_journals AS j WHERE j.id = v_journal_id;
  IF v_status = 'POSTED' THEN
    RAISE EXCEPTION 'POSTED_LEDGER_IS_IMMUTABLE' USING ERRCODE = '55000';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER provider_guard_posted_ledger_entry
BEFORE INSERT OR UPDATE OR DELETE ON provider_internal.ledger_entries
FOR EACH ROW EXECUTE FUNCTION provider_internal.guard_posted_journal_immutability();

CREATE OR REPLACE FUNCTION provider_internal.guard_append_only_history()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION 'APPEND_ONLY_HISTORY' USING ERRCODE = '55000';
END
$function$;

CREATE TRIGGER provider_audit_events_append_only
BEFORE UPDATE OR DELETE ON provider_internal.audit_events
FOR EACH ROW EXECUTE FUNCTION provider_internal.guard_append_only_history();

CREATE TRIGGER provider_approval_decisions_append_only
BEFORE UPDATE OR DELETE ON provider_internal.approval_decisions
FOR EACH ROW EXECUTE FUNCTION provider_internal.guard_append_only_history();

CREATE OR REPLACE FUNCTION provider_internal.guard_posted_journal_header()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF OLD.status = 'POSTED' THEN
    RAISE EXCEPTION 'POSTED_JOURNAL_HEADER_IS_IMMUTABLE' USING ERRCODE = '55000';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER provider_guard_posted_journal_header
BEFORE UPDATE OR DELETE ON provider_internal.ledger_journals
FOR EACH ROW EXECUTE FUNCTION provider_internal.guard_posted_journal_header();

CREATE OR REPLACE FUNCTION provider_internal.consume_partner_nonce(
  p_partner_id uuid, p_key_id text, p_nonce_hash bytea, p_expires_at timestamptz
)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_inserted integer;
BEGIN
  IF p_nonce_hash IS NULL OR pg_catalog.octet_length(p_nonce_hash) <> 32
     OR p_expires_at <= pg_catalog.clock_timestamp()
     OR p_expires_at > pg_catalog.clock_timestamp() + interval '20 minutes' THEN
    RAISE EXCEPTION 'INVALID_NONCE_INPUT' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM provider_internal.partners AS p
    JOIN provider_internal.partner_keys AS k ON k.partner_id = p.id
    WHERE p.id = p_partner_id AND p.status = 'ACTIVE'
      AND k.key_id = p_key_id AND k.status = 'ACTIVE' AND k.revoked_at IS NULL
      AND k.valid_from <= pg_catalog.clock_timestamp()
      AND (k.valid_until IS NULL OR k.valid_until > pg_catalog.clock_timestamp())
  ) THEN
    RAISE EXCEPTION 'PARTNER_OR_KEY_NOT_ACTIVE' USING ERRCODE = '42501';
  END IF;
  INSERT INTO provider_internal.partner_nonces(partner_id, key_id, nonce_hash, expires_at)
  VALUES (p_partner_id, p_key_id, p_nonce_hash, p_expires_at)
  ON CONFLICT (partner_id, key_id, nonce_hash) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted = 1;
END
$function$;

CREATE OR REPLACE FUNCTION provider_internal.consume_launch_token(p_token_hash bytea)
RETURNS TABLE (
  partner_id uuid, session_id uuid, partner_player_ref text,
  partner_session_ref text, game_code text, currency text,
  jurisdiction text, locale text
)
LANGUAGE sql SECURITY DEFINER SET search_path = ''
AS $function$
  WITH consumed AS (
    UPDATE provider_internal.launch_tokens AS t
       SET consumed_at = pg_catalog.clock_timestamp()
     WHERE t.token_hash = p_token_hash
       AND pg_catalog.octet_length(p_token_hash) = 32
       AND t.consumed_at IS NULL
       AND t.expires_at > pg_catalog.clock_timestamp()
     RETURNING t.partner_id, t.session_id
  )
  SELECT c.partner_id, s.id, s.partner_player_ref, s.partner_session_ref,
         s.game_code, s.currency, s.jurisdiction, s.locale
  FROM consumed AS c
  JOIN provider_internal.sessions AS s ON s.id = c.session_id AND s.partner_id = c.partner_id
  JOIN provider_internal.partners AS p ON p.id = c.partner_id
  WHERE p.status = 'ACTIVE' AND s.status = 'CREATED'
$function$;

CREATE OR REPLACE FUNCTION provider_internal.create_wallet_transaction(
  p_partner_id uuid, p_session_id uuid, p_round_id uuid,
  p_idempotency_key text, p_request_hash bytea, p_operation text,
  p_amount_minor bigint, p_currency text, p_currency_exponent smallint,
  p_original_transaction_id uuid DEFAULT NULL
)
RETURNS TABLE(transaction_id uuid, transaction_status text, was_created boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  v_existing provider_internal.wallet_transactions%ROWTYPE;
  v_session provider_internal.sessions%ROWTYPE;
  v_config provider_internal.partner_game_configs%ROWTYPE;
  v_original provider_internal.wallet_transactions%ROWTYPE;
  v_refunded numeric;
  v_open_exposure numeric;
  v_round_payout numeric;
  v_new_id uuid;
BEGIN
  IF p_idempotency_key IS NULL OR pg_catalog.length(p_idempotency_key) NOT BETWEEN 1 AND 200
     OR p_request_hash IS NULL OR pg_catalog.octet_length(p_request_hash) <> 32
     OR p_operation NOT IN ('BET','WIN','REFUND')
     OR p_amount_minor IS NULL OR p_amount_minor <= 0
     OR p_currency !~ '^[A-Z]{3}$'
     OR p_currency_exponent NOT BETWEEN 0 AND 6 THEN
    RAISE EXCEPTION 'INVALID_WALLET_TRANSACTION_INPUT' USING ERRCODE = '22023';
  END IF;

  SELECT w.* INTO v_existing
  FROM provider_internal.wallet_transactions AS w
  WHERE w.partner_id = p_partner_id AND w.idempotency_key = p_idempotency_key
  FOR UPDATE;
  IF FOUND THEN
    IF v_existing.request_hash <> p_request_hash THEN
      RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT' USING ERRCODE = '23505';
    END IF;
    transaction_id := v_existing.id;
    transaction_status := v_existing.status;
    was_created := false;
    RETURN NEXT;
    RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM provider_internal.partners AS p WHERE p.id = p_partner_id AND p.status = 'ACTIVE') THEN
    RAISE EXCEPTION 'PARTNER_NOT_ACTIVE' USING ERRCODE = '42501';
  END IF;

  SELECT s.* INTO v_session
  FROM provider_internal.sessions AS s
  WHERE s.id = p_session_id AND s.partner_id = p_partner_id
  FOR UPDATE;
  IF NOT FOUND OR v_session.status <> 'ACTIVE'
     OR v_session.currency <> p_currency OR v_session.currency_exponent <> p_currency_exponent THEN
    RAISE EXCEPTION 'SESSION_OR_CURRENCY_INVALID' USING ERRCODE = '23514';
  END IF;

  IF p_operation IN ('BET','WIN') AND p_round_id IS NULL THEN
    RAISE EXCEPTION 'BET_AND_WIN_REQUIRE_ROUND' USING ERRCODE = '22023';
  END IF;

  IF p_operation = 'BET' AND NOT EXISTS (
    SELECT 1 FROM provider_internal.rounds AS r
    WHERE r.id = p_round_id AND r.partner_id = p_partner_id
      AND r.session_id = p_session_id AND r.status = 'OPEN'
  ) THEN
    RAISE EXCEPTION 'BET_REQUIRES_OPEN_ROUND' USING ERRCODE = '23514';
  END IF;

  IF p_operation = 'WIN' AND NOT EXISTS (
    SELECT 1 FROM provider_internal.rounds AS r
    WHERE r.id = p_round_id AND r.partner_id = p_partner_id
      AND r.session_id = p_session_id AND r.status = 'COMPLETED'
  ) THEN
    RAISE EXCEPTION 'WIN_REQUIRES_COMPLETED_ROUND' USING ERRCODE = '23514';
  END IF;

  SELECT c.* INTO v_config
  FROM provider_internal.partner_game_configs AS c
  WHERE c.partner_id = p_partner_id AND c.game_code = v_session.game_code
    AND c.jurisdiction = v_session.jurisdiction AND c.currency = p_currency
    AND c.currency_exponent = p_currency_exponent AND c.enabled = true
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PARTNER_GAME_CONFIGURATION_NOT_ENABLED' USING ERRCODE = '42501';
  END IF;

  IF p_operation = 'BET' AND
     (p_amount_minor < v_config.min_bet_minor OR p_amount_minor > v_config.max_bet_minor) THEN
    RAISE EXCEPTION 'BET_OUTSIDE_PARTNER_LIMITS' USING ERRCODE = '22003';
  END IF;

  IF p_operation = 'BET' THEN
    SELECT COALESCE(pg_catalog.sum(w.amount_minor), 0)
      INTO v_open_exposure
    FROM provider_internal.wallet_transactions AS w
    JOIN provider_internal.sessions AS s
      ON s.id = w.session_id AND s.partner_id = w.partner_id
    JOIN provider_internal.rounds AS r
      ON r.id = w.round_id AND r.partner_id = w.partner_id
    WHERE w.partner_id = p_partner_id
      AND s.game_code = v_session.game_code
      AND s.jurisdiction = v_session.jurisdiction
      AND s.currency = p_currency
      AND w.operation = 'BET'
      AND w.status IN ('CREATED','DISPATCHING','PENDING','UNKNOWN','CONFIRMED')
      AND r.status = 'OPEN';

    IF v_open_exposure + p_amount_minor > v_config.max_open_exposure_minor THEN
      RAISE EXCEPTION 'PARTNER_OPEN_EXPOSURE_LIMIT_EXCEEDED' USING ERRCODE = '22003';
    END IF;
  END IF;
  IF p_operation = 'WIN' THEN
    SELECT COALESCE(pg_catalog.sum(w.amount_minor), 0)
      INTO v_round_payout
    FROM provider_internal.wallet_transactions AS w
    WHERE w.partner_id = p_partner_id
      AND w.round_id = p_round_id
      AND w.operation = 'WIN'
      AND w.status IN ('CREATED','DISPATCHING','PENDING','UNKNOWN','CONFIRMED','RECONCILED');

    IF v_round_payout + p_amount_minor > v_config.max_win_minor THEN
      RAISE EXCEPTION 'ROUND_WIN_LIMIT_EXCEEDED' USING ERRCODE = '22003';
    END IF;
  END IF;

  IF p_operation = 'REFUND' THEN
    IF p_original_transaction_id IS NULL THEN
      RAISE EXCEPTION 'REFUND_REQUIRES_ORIGINAL_TRANSACTION' USING ERRCODE = '22023';
    END IF;
    SELECT w.* INTO v_original
    FROM provider_internal.wallet_transactions AS w
    WHERE w.id = p_original_transaction_id AND w.partner_id = p_partner_id
      AND w.session_id = p_session_id
      AND w.round_id IS NOT DISTINCT FROM p_round_id
      AND w.operation = 'BET' AND w.currency = p_currency
      AND w.status IN ('CONFIRMED','RECONCILED')
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'ORIGINAL_CONFIRMED_BET_NOT_FOUND' USING ERRCODE = '23503';
    END IF;
    SELECT COALESCE(pg_catalog.sum(r.amount_minor), 0) INTO v_refunded
    FROM provider_internal.wallet_transactions AS r
    WHERE r.partner_id = p_partner_id AND r.original_transaction_id = p_original_transaction_id
      AND r.operation = 'REFUND'
      AND r.status IN ('CREATED','DISPATCHING','PENDING','UNKNOWN','CONFIRMED','RECONCILED');
    IF v_refunded + p_amount_minor > v_original.amount_minor THEN
      RAISE EXCEPTION 'REFUND_EXCEEDS_UNREFUNDED_ORIGINAL_BET' USING ERRCODE = '22003';
    END IF;
  END IF;

  INSERT INTO provider_internal.wallet_transactions(
    partner_id, session_id, round_id, idempotency_key, request_hash,
    operation, amount_minor, currency, currency_exponent, original_transaction_id
  )
  VALUES (
    p_partner_id, p_session_id, p_round_id, p_idempotency_key, p_request_hash,
    p_operation, p_amount_minor, p_currency, p_currency_exponent, p_original_transaction_id
  )
  ON CONFLICT (partner_id, idempotency_key) DO NOTHING
  RETURNING id INTO v_new_id;

  IF v_new_id IS NULL THEN
    SELECT w.* INTO v_existing FROM provider_internal.wallet_transactions AS w
    WHERE w.partner_id = p_partner_id AND w.idempotency_key = p_idempotency_key FOR UPDATE;
    IF v_existing.request_hash <> p_request_hash THEN
      RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT' USING ERRCODE = '23505';
    END IF;
    transaction_id := v_existing.id;
    transaction_status := v_existing.status;
    was_created := false;
    RETURN NEXT;
    RETURN;
  END IF;

  INSERT INTO provider_internal.outbox_events(partner_id, wallet_transaction_id, event_type, dedupe_key, payload)
  VALUES (p_partner_id, v_new_id, 'WALLET_DISPATCH',
          'wallet-dispatch:' || v_new_id::text,
          pg_catalog.jsonb_build_object('transaction_id', v_new_id));

  transaction_id := v_new_id;
  transaction_status := 'CREATED';
  was_created := true;
  RETURN NEXT;
END
$function$;

CREATE OR REPLACE FUNCTION provider_internal.claim_outbox_events(
  p_worker_id uuid, p_limit integer DEFAULT 25, p_lease_seconds integer DEFAULT 30
)
RETURNS SETOF provider_internal.outbox_events
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  v_event provider_internal.outbox_events%ROWTYPE;
  v_updated integer;
BEGIN
  IF p_worker_id IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR p_lease_seconds NOT BETWEEN 5 AND 300 THEN
    RAISE EXCEPTION 'INVALID_OUTBOX_CLAIM_ARGUMENTS' USING ERRCODE = '22023';
  END IF;
  FOR v_event IN
    SELECT o.* FROM provider_internal.outbox_events AS o
    WHERE o.state IN ('READY','RETRY') AND o.available_at <= pg_catalog.clock_timestamp()
      AND o.attempts < o.max_attempts
      AND (
        o.event_type <> 'WALLET_DISPATCH'
        OR EXISTS (
          SELECT 1 FROM provider_internal.wallet_transactions AS w
          WHERE w.id = o.wallet_transaction_id AND w.partner_id = o.partner_id AND w.status = 'CREATED'
        )
      )
    ORDER BY o.available_at, o.created_at
    LIMIT p_limit
    FOR UPDATE SKIP LOCKED
  LOOP
    IF v_event.event_type = 'WALLET_DISPATCH' THEN
      UPDATE provider_internal.wallet_transactions AS w
      SET status = 'DISPATCHING',
          dispatch_started_at = pg_catalog.clock_timestamp(),
          dispatch_lease_until = pg_catalog.clock_timestamp() + pg_catalog.make_interval(secs => p_lease_seconds),
          updated_at = pg_catalog.clock_timestamp()
      WHERE w.id = v_event.wallet_transaction_id AND w.partner_id = v_event.partner_id AND w.status = 'CREATED';
      GET DIAGNOSTICS v_updated = ROW_COUNT;
      IF v_updated <> 1 THEN
        UPDATE provider_internal.outbox_events SET state = 'SUPERSEDED' WHERE id = v_event.id;
        CONTINUE;
      END IF;
    END IF;
    UPDATE provider_internal.outbox_events AS o
    SET state = 'LEASED', lease_owner = p_worker_id,
        lease_until = pg_catalog.clock_timestamp() + pg_catalog.make_interval(secs => p_lease_seconds),
        attempts = o.attempts + 1
    WHERE o.id = v_event.id;
    SELECT o.* INTO v_event FROM provider_internal.outbox_events AS o WHERE o.id = v_event.id;
    RETURN NEXT v_event;
  END LOOP;
END
$function$;

CREATE OR REPLACE FUNCTION provider_internal.mark_expired_wallet_dispatches_unknown()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_tx record; v_count integer := 0;
BEGIN
  FOR v_tx IN
    SELECT w.id, w.partner_id, w.status_query_generation
    FROM provider_internal.wallet_transactions AS w
    WHERE w.status = 'DISPATCHING' AND w.dispatch_lease_until <= pg_catalog.clock_timestamp()
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE provider_internal.wallet_transactions
    SET status = 'UNKNOWN', status_query_generation = v_tx.status_query_generation + 1,
        updated_at = pg_catalog.clock_timestamp()
    WHERE id = v_tx.id AND partner_id = v_tx.partner_id AND status = 'DISPATCHING';

    UPDATE provider_internal.outbox_events
    SET state = 'SUPERSEDED', lease_owner = NULL, lease_until = NULL
    WHERE wallet_transaction_id = v_tx.id AND event_type = 'WALLET_DISPATCH' AND state = 'LEASED';

    INSERT INTO provider_internal.outbox_events(
      partner_id, wallet_transaction_id, event_type, generation, dedupe_key, payload
    )
    VALUES (
      v_tx.partner_id, v_tx.id, 'WALLET_STATUS_QUERY',
      v_tx.status_query_generation + 1,
      'wallet-status:' || v_tx.id::text || ':' || (v_tx.status_query_generation + 1)::text,
      pg_catalog.jsonb_build_object('transaction_id', v_tx.id)
    )
    ON CONFLICT (wallet_transaction_id, event_type, generation) DO NOTHING;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END
$function$;

CREATE OR REPLACE FUNCTION provider_internal.post_ledger_journal(p_journal_id uuid, p_journal_hash bytea)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  v_journal provider_internal.ledger_journals%ROWTYPE;
  v_line_count bigint;
  v_debits numeric;
  v_credits numeric;
BEGIN
  IF p_journal_hash IS NULL OR pg_catalog.octet_length(p_journal_hash) <> 32 THEN
    RAISE EXCEPTION 'INVALID_JOURNAL_HASH' USING ERRCODE = '22023';
  END IF;
  SELECT j.* INTO v_journal FROM provider_internal.ledger_journals AS j
  WHERE j.id = p_journal_id FOR UPDATE;
  IF NOT FOUND OR v_journal.status <> 'DRAFT' THEN
    RAISE EXCEPTION 'JOURNAL_NOT_DRAFT' USING ERRCODE = '55000';
  END IF;
  SELECT pg_catalog.count(*),
         COALESCE(pg_catalog.sum(e.amount_minor) FILTER (WHERE e.direction = 'DEBIT'), 0),
         COALESCE(pg_catalog.sum(e.amount_minor) FILTER (WHERE e.direction = 'CREDIT'), 0)
  INTO v_line_count, v_debits, v_credits
  FROM provider_internal.ledger_entries AS e
  WHERE e.journal_id = p_journal_id AND e.partner_id = v_journal.partner_id AND e.currency = v_journal.currency;
  IF v_line_count < 2 OR v_debits <= 0 OR v_debits <> v_credits THEN
    RAISE EXCEPTION 'LEDGER_JOURNAL_UNBALANCED' USING ERRCODE = '23514';
  END IF;
  UPDATE provider_internal.ledger_journals
  SET status = 'POSTED', journal_hash = p_journal_hash, posted_at = pg_catalog.clock_timestamp()
  WHERE id = p_journal_id;
  RETURN true;
END
$function$;

RESET ROLE;

REVOKE ALL ON ALL TABLES IN SCHEMA provider_internal
  FROM PUBLIC, anon, authenticated, service_role, provider_runtime;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA provider_internal
  FROM PUBLIC, anon, authenticated, service_role, provider_runtime;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA provider_internal
  FROM PUBLIC, anon, authenticated, service_role, provider_runtime;

DO $rls$
DECLARE v_table record;
BEGIN
  FOR v_table IN
    SELECT c.relname FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'provider_internal' AND c.relkind = 'r'
  LOOP
    EXECUTE pg_catalog.format('ALTER TABLE provider_internal.%I ENABLE ROW LEVEL SECURITY', v_table.relname);
    EXECUTE pg_catalog.format('ALTER TABLE provider_internal.%I FORCE ROW LEVEL SECURITY', v_table.relname);
    EXECUTE pg_catalog.format(
      'CREATE POLICY provider_owner_only ON provider_internal.%I TO provider_owner USING (true) WITH CHECK (true)',
      v_table.relname
    );
  END LOOP;
END
$rls$;

GRANT EXECUTE ON FUNCTION provider_internal.consume_partner_nonce(uuid, text, bytea, timestamptz) TO provider_runtime;
GRANT EXECUTE ON FUNCTION provider_internal.consume_launch_token(bytea) TO provider_runtime;
GRANT EXECUTE ON FUNCTION provider_internal.create_wallet_transaction(uuid, uuid, uuid, text, bytea, text, bigint, text, smallint, uuid) TO provider_runtime;
GRANT EXECUTE ON FUNCTION provider_internal.claim_outbox_events(uuid, integer, integer) TO provider_runtime;
GRANT EXECUTE ON FUNCTION provider_internal.mark_expired_wallet_dispatches_unknown() TO provider_runtime;
GRANT EXECUTE ON FUNCTION provider_internal.post_ledger_journal(uuid, bytea) TO provider_runtime;

ALTER ROLE provider_runtime SET search_path = 'pg_catalog, provider_internal';
ALTER DEFAULT PRIVILEGES FOR ROLE provider_owner IN SCHEMA provider_internal
  REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated, service_role, provider_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE provider_owner IN SCHEMA provider_internal
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role, provider_runtime;

-- OUT-OF-BAND DBA PROVISIONING (not part of this proposal):
-- 1. Create a dedicated LOGIN role with securely generated password.
-- 2. Grant that LOGIN role membership in provider_runtime.
-- 3. Store its URL as ASIX_PROVIDER_DATABASE_URL in Provider function secrets.
-- 4. Execute SET ROLE provider_runtime after connecting.
-- 5. Restrict network access and rotate credentials independently.
-- Never commit LOGIN passwords or database URLs.
