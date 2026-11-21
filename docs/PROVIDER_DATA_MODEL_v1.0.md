# ASIX Provider Data Model v1.0

**Status:** logical model only; not a migration and not approved for production execution.

## 1. Design decision

Create a separate PostgreSQL schema named `provider` for B2B operator integration. Do not add partner-domain objects into the existing Q-CARD game tables unless a later reviewed mapping proves it is necessary.

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
| `provider.partners` | id, code, status, jurisdiction | Tenant/partner identity |
| `provider.partner_keys` | partner_id, key_id, auth_profile, protocol_version, secret_ref/public_key_ref, valid_from/to, revoked_at | Per-partner signature/auth profile; key material stays in KMS/secrets manager |
| `provider.partner_game_config` | partner_id, game_id, currency, limits, enabled, version | Per-partner game configuration |
| `provider.launch_nonces` | partner_id, nonce_hash, expires_at, consumed_at | Replay protection |
| `provider.launch_tokens` | token_hash, partner_id, player_ref, session_ref, game_id, currency, expiry | One-use launch authority |
| `provider.sessions` | partner/session/player/game/status | B2B game session context |
| `provider.rounds` | session_id, round_no, rules_hash, game_version, result_hash | Round identity and immutable result reference |
| `provider.wallet_transactions` | partner_id, idempotency_key, request_hash, operation, amount, currency, state | Durable partner-wallet workflow |
| `provider.wallet_attempts` | transaction_id, attempt_no, request/response hashes, timestamps, result | External dispatch evidence |
| `provider.outbox` | event_id, transaction_id, lease, attempts, next_attempt_at | Durable delivery |
| `provider.ledger_accounts` | code, account_type, currency | Contract-specific chart of accounts |
| `provider.ledger_journals` | partner_id, source_ref, journal_type, currency, status | Double-entry journal |
| `provider.ledger_entries` | journal_id, account_id, direction, amount_minor | Debit/credit lines |
| `provider.reconciliation_runs` | partner_id, period, status, report_ref | Reconciliation batch |
| `provider.reconciliation_items` | run_id, asix_tx_id, partner_ref, match_state, difference | Itemized mismatch evidence |
| `provider.approval_requests` | type, target, reason, evidence, state | Human approval queue |
| `provider.approval_decisions` | request_id, approver, decision, timestamp | Immutable decision history |
| `provider.audit_events` | actor, action, target, correlation_id, payload_hash | Audit trail |
| `provider.incidents` | partner_id, severity, state, opened/closed | Per-partner incident lifecycle |

## 3. Required uniqueness and integrity constraints

- `partners.code` unique.
- `partner_keys(partner_id, key_id)` unique.
- `launch_nonces(partner_id, nonce_hash)` unique.
- `launch_tokens.token_hash` unique.
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
- Partner database access should occur through narrowly scoped server-side functions/service roles.
- Do not give partner clients direct table access.
- RLS is defense in depth, not the only tenant boundary.
- Cross-tenant queries are prohibited unless an audited internal reporting role has an explicit purpose.

## 5. Data classification and retention

- Secrets: never stored in database rows; store references to KMS/secret manager versions.
- Player identifiers: pseudonymous operator references; avoid name, email, phone and payment data.
- Financial records: immutable and retained according to applicable law, contract and audit requirements.
- Raw partner payloads: redact credentials and personal data; store hashes and selected sanitized fields where possible.
- Game events: retain enough evidence for replay, dispute investigation and certification, subject to retention rules.
- Logs: no access tokens, session secrets, full wallet credentials or unnecessary personal information.

## 6. Migration readiness gates

A physical migration may be drafted only after:
1. The V154 snapshot is restored into isolated staging.
2. Existing table and function dependencies are inventoried.
3. Current RLS policies, grants and SECURITY DEFINER search paths are reviewed.
4. Tenant and service-role model is selected.
5. Ledger journal balancing and immutability triggers are tested.
6. Upgrade and forward-repair plans are documented.
7. No impact on consumer game wallet, Q-CARD settlement or current 5% consumer commission is demonstrated.

Do not execute a generated greenfield schema against the source project.
