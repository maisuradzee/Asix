# ASIX Provider Data Model v1.1

**Status:** logical model only; not a migration and not approved for production execution.

## 1. Design decision

Create a separate, non-Data-API PostgreSQL schema named `provider_internal` for B2B operator integration. Do not add partner-domain objects into the existing Q-CARD game tables unless a later reviewed mapping proves it is necessary.

Existing consumer-domain objects remain separate:
- `asix_wallets`
- `asix_wallet_transactions`
- `asix_platform_commission_ledger`
- `qcard_money_ledger`
- `qcard_game_state`
- `qcard_actions`
- `qcard_deal_history`

Existing room commission/prize-pool rules are not the ASIX B2B revenue-share model.

## 2. Logical entities

| Entity | Key fields | Purpose |
|---|---|---|
| `provider_internal.partners` | id, code, status, jurisdiction | Tenant/partner identity |
| `provider_internal.partner_keys` | partner_id, key_id, auth_profile, protocol_version, secret_ref/public_key_ref, valid_from/to, revoked_at | Per-partner signature/auth profile; key material stays in KMS/secrets manager |
| `provider_internal.partner_game_configs` | partner_id, game_id, currency, limits, enabled, version | Per-partner game configuration |
| `provider_internal.partner_nonces` | partner_id, nonce_hash, expires_at, consumed_at | Replay protection |
| `provider_internal.launch_tokens` | partner_id, session_id, token_hash, expires_at, consumed_at, revoked_at | One-use launch authority; only the token hash is stored |
| `provider_internal.sessions` | partner/session/player/game/currency/exponent/policy/status/started_at/closed_at | B2B game session context; token consumption activates the session atomically |
| `provider_internal.rounds` | session_id, round_no, rules_hash, game_version, result_hash | Round identity and immutable result reference |
| `provider_internal.wallet_transactions` | partner_id, idempotency_key, request_hash, operation, amount, currency, state | Durable partner-wallet workflow |
| `provider_internal.wallet_attempts` | transaction_id, attempt_no, request/response hashes, timestamps, result | External dispatch evidence |
| `provider_internal.outbox_events` | event_id, transaction_id, lease, attempts, next_attempt_at | Durable delivery |
| `provider_internal.ledger_accounts` | code, account_type, currency | Contract-specific chart of accounts |
| `provider_internal.ledger_journals` | partner_id, source_ref, journal_type, currency, status | Double-entry journal |
| `provider_internal.ledger_entries` | journal_id, account_id, direction, amount_minor | Debit/credit lines |
| `provider_internal.reconciliation_runs` | partner_id, period, status, report_ref | Reconciliation batch |
| `provider_internal.reconciliation_items` | run_id, asix_tx_id, partner_ref, match_state, difference | Itemized mismatch evidence |
| `provider_internal.approval_requests` | type, target, reason, evidence, state | Human approval queue |
| `provider_internal.approval_decisions` | request_id, approver, decision, timestamp | Immutable decision history |
| `provider_internal.audit_events` | actor, action, target, correlation_id, payload_hash | Audit trail |
| `provider_internal.incidents` | partner_id, severity, state, opened/closed | Per-partner incident lifecycle |

## 3. Required uniqueness and integrity constraints

- `partners.code` unique.
- `partner_keys(partner_id, key_id)` unique.
- `launch_nonces(partner_id, nonce_hash)` unique.
- `launch_tokens.token_hash` unique.
- `launch_tokens` are one-use and may be consumed only while unexpired and not revoked.
- `sessions(partner_id, partner_session_ref)` is the partner-scoped Launch idempotency key.
- `sessions(partner_id, partner_session_ref)` unique.
- `rounds(session_id, round_no)` unique.
- `wallet_transactions(partner_id, idempotency_key)` unique.
- `wallet_attempts(transaction_id, attempt_no)` unique.
- Partner transaction reference unique per partner when supported by the external contract.
- A journal's lines must all use the journal currency.
- A posted journal must have at least two entries and balance to zero.
- No direct UPDATE/DELETE on posted ledger journals or entries.
- A correction references the original transaction/journal and creates a new compensating record.

## 4. Tenant isolation

- Derive partner identity from verified credentials/signature, never from an untrusted request body.
- All partner-owned records include partner_id, directly or through a foreign-key parent.
- Partner database access should occur through narrowly scoped server-side functions and a dedicated provider_runtime database role; never grant the runtime direct table access or reuse service_role.
- Do not give partner clients direct table access.
- RLS is enabled and FORCEd on every provider table as defense in depth; the partner API also enforces tenant scope before calling database functions.
- Cross-tenant queries are prohibited unless an audited internal reporting role has an explicit purpose.

## 5. Launch lifecycle invariants

- `create_launch_session` checks partner ACTIVE status and an enabled game/jurisdiction/currency/exponent configuration.
- A repeated `partner_session_ref` with identical immutable identity reuses the CREATED session, revokes its earlier unconsumed tokens, and issues a new token hash.
- Reusing a partner session reference with different player/game/currency/policy identity is rejected.
- A repeated Launch after the session becomes ACTIVE does not issue a new token.
- `consume_launch_token` and session activation from CREATED to ACTIVE are atomic.
- Create/reissue and consume use the same partner/session advisory lock so concurrent replicas cannot split a session or race token supersession.

## 6. Data classification and retention

- Secrets: never stored in database rows; store references to KMS/secret manager versions.
- Player identifiers: pseudonymous operator references; avoid name, email, phone and payment data.
- Financial records: immutable and retained according to applicable law, contract and audit requirements.
- Raw partner payloads: redact credentials and personal data; store hashes and selected sanitized fields where possible.
- Game events: retain enough evidence for replay, dispute investigation and certification, subject to retention rules.
- Logs: no access tokens, session secrets, full wallet credentials or unnecessary personal information.

## 7. Migration readiness gates

A physical migration may be drafted only after:
1. The V154 snapshot is restored into isolated staging.
2. Existing table and function dependencies are inventoried.
3. Current RLS policies, grants and SECURITY DEFINER search paths are reviewed.
4. Tenant and service-role model is selected.
5. Ledger journal balancing and immutability triggers are tested.
6. Upgrade and forward-repair plans are documented.
7. No impact on consumer game wallet, Q-CARD settlement or current 5% consumer commission is demonstrated.

Do not execute a generated greenfield schema against the source project.
