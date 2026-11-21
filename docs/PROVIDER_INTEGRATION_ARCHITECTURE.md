# ASIX Provider Integration Architecture (Stage 1)

**Status:** design baseline only; no production behavior changed.  
**Repository baseline inspected:** frontend V153, active Supabase Edge Function `super-worker` V25, live schema snapshot V154.  
**Purpose:** define a safe path from the existing multiplayer card-game product to a B2B casino/provider integration without mixing operator-wallet responsibilities into the existing game engine.

## 1. Critical boundary: existing product vs provider platform

The current repository is an online multiplayer card game backed by Supabase. It is not yet a complete casino-provider platform. The current V25 worker routes authenticated game actions into PostgreSQL RPCs. The repository README records a current 5% ASIX commission / 95% prize-pool rule for its existing entry-fee model.

That existing game-economy rule must not be silently reused as a casino-provider commercial or wallet rule. In B2B mode:
- The casino/operator owns the player account and player wallet.
- ASIX receives authenticated game-launch/session context and requests bet debits / win credits from the operator wallet API.
- ASIX records provider-side transaction evidence, game rounds, provider revenue and partner settlement obligations.
- Casino deposits and withdrawals remain the operator's responsibility unless a separately licensed and contracted model says otherwise.

The existing game engine can be reused only behind a provider boundary after game math, RNG, game-state lifecycle and wallet semantics are independently reviewed.

## 2. Target topology

```text
Casino / Aggregator
       |
       | launch token + signed wallet API
       v
ASIX Provider Gateway
       |
       +--> Partner Registry / Auth / Limits
       |
       +--> Session & Launch Service
       |          |
       |          v
       |      Existing ASIX Game Runtime (isolated module)
       |
       +--> Wallet Orchestrator ----> Partner Wallet Adapter
       |          |                         |
       |          v                         v
       |      Transaction Journal       Casino Wallet API
       |
       +--> Provider Ledger / Reconciliation
       |
       +--> Risk & Policy Engine
       |
       +--> Observability / Audit / Control Center
```

Control-plane dashboards, AI analysis and reporting must not be synchronous dependencies of a live game round. A control-plane outage must not corrupt or invent a game outcome.

## 3. Modules and ownership

| Module | Responsibility | Must not do |
|---|---|---|
| Provider Gateway | Authenticate partner, validate signed requests, route API calls | Trust browser-supplied identity or amount |
| Partner Registry | Partner status, currencies, limits, adapter config references | Store plaintext partner secrets |
| Launch / Session | Validate launch token, bind partner/player/session/game | Accept arbitrary client-created partner identity |
| Game Runtime | Server-authoritative rules, RNG integration, round lifecycle | Call operator wallet directly from browser |
| Wallet Orchestrator | Durable bet/win/refund workflow and idempotency | Blindly retry UNKNOWN outcomes |
| Partner Adapter | Translate canonical ASIX calls to each operator protocol | Share credentials/config across partners |
| Provider Ledger | Append-only double-entry provider accounting | Represent the casino player's full wallet |
| Reconciliation | Compare ASIX transactions with operator reports | Silently force balances to match |
| Policy Engine | Enforce limits, state gates and approved automation | Give AI unrestricted financial permissions |
| Control Center | Exceptions, partner health, approvals, audit | Edit completed game outcomes or ledger history |

## 4. Canonical integration contract

Every partner adapter must implement the same internal interface, even if external protocols differ.

### Required inbound context
- `partner_code`
- `launch_token` (short-lived, single-use or replay-protected)
- `partner_player_ref` (pseudonymous operator identifier)
- `partner_session_ref`
- `game_code`
- `currency` (ISO 4217)
- `issued_at`, `expires_at`, `nonce`
- signed request metadata

Do not accept a player balance from the browser as authoritative.

### Canonical wallet request
- `transaction_id` — ASIX UUID
- `idempotency_key` — unique per partner and financial action
- `partner_player_ref`
- `partner_session_ref`
- `round_id`
- `action` — BET, WIN, REFUND or approved ROLLBACK
- `amount_minor` — positive integer in the currency's minor unit
- `currency`
- `created_at`
- `request_hash`

### Canonical response
- `status` — CONFIRMED, DECLINED, PENDING or UNKNOWN
- `partner_transaction_ref`
- `available_balance_minor` only if contract permits and it is clearly informational
- `currency`
- `response_code`
- `response_timestamp`

The adapter must normalize external error codes and preserve the raw, redacted response for audit.

## 5. Wallet transaction state machine

```text
CREATED -> SENT -> CONFIRMED -> RECONCILED
                 |-> DECLINED
                 |-> UNKNOWN -> STATUS_QUERY -> CONFIRMED / DECLINED / EXCEPTION
```

Rules:
1. Persist the transaction and idempotency key before sending the external request.
2. Reuse the same idempotency key when the partner contract supports safe retries.
3. If the network times out after send, set UNKNOWN. Query partner transaction status before another debit/credit attempt.
4. Never infer success from an HTTP timeout or infer failure from a missing response.
5. A bet is not playable until the debit is confirmed under the partner's protocol.
6. A win is not marked paid until credit confirmation is established.
7. Refunds and rollbacks are separate, traceable compensating actions.
8. Exactly-once network delivery is not promised; design for at-least-once delivery and exactly-once financial effect through idempotency and reconciliation.

## 6. Database evolution strategy

Do not apply a generic greenfield schema over the existing V154 database. The current schema and function set must first be inventoried and mapped.

Add provider-domain tables as a separate migration family only after:
- exact V154 baseline is restorable in isolated staging;
- existing wallet, deal, round, commission and action RPCs are mapped;
- foreign-key and RLS boundaries are reviewed;
- migration rollback/forward-repair strategy is documented.

Suggested new domain entities:
- `provider_partners`
- `provider_partner_configs` (secret references only)
- `provider_games`
- `provider_launch_tokens` (hash only, expiry, nonce, consumed_at)
- `provider_sessions`
- `provider_wallet_transactions`
- `provider_ledger_accounts`
- `provider_ledger_journals`
- `provider_ledger_entries`
- `provider_reconciliation_runs`
- `provider_reconciliation_items`
- `provider_approval_requests`
- `provider_audit_events`

Tenant isolation must be enforced server-side and in database policies. Never rely only on a client-supplied `partner_id`.

## 7. Existing Supabase worker integration

Current `super-worker` V25 is a game-action worker that invokes authenticated Postgres RPCs. Do not overload it with all partner protocol logic.

Recommended separation:
- Keep the existing worker responsible for existing ASIX game actions until a tested replacement is approved.
- Add a distinct provider gateway / wallet orchestrator Edge Function family.
- Use shared internal libraries for request validation, trace IDs, structured errors and partner scoping.
- Keep `verify_jwt=true` for user-facing authenticated routes. Partner-to-provider routes should use partner-specific authentication/signature verification, timestamp tolerance, nonce/replay protection and key rotation; do not simply disable JWT verification globally.
- Never expose service-role keys or partner secrets to the frontend.
- Restrict CORS to known browser origins for browser-facing endpoints; server-to-server partner endpoints should not depend on permissive browser CORS.

## 8. Partner isolation and circuit breakers

Each partner has independent:
- credentials and key versions;
- currencies, limits and enabled games;
- adapter deployment/config version;
- rate limits and concurrency budgets;
- health state and incident timeline;
- reconciliation schedule and settlement report.

A partner adapter timeout must not block other partners. Circuit-break only the affected partner integration. During partner wallet unavailability, stop new financial actions for that partner and safely resolve in-flight UNKNOWN transactions.

## 9. Autopilot permission model

**May run automatically after policy approval**
- restart a stateless adapter worker;
- open a partner-specific circuit breaker;
- retry safe read-only status queries;
- scale bounded workers;
- roll back a deployment that fails health checks;
- generate reconciliation and incident reports.

**Requires human approval**
- change partner bet/payout limits;
- release a material settlement;
- approve a manual financial adjustment;
- rotate production partner credentials outside a pre-approved emergency procedure;
- resume a partner after a financial-integrity RED incident.

**Never autonomous**
- alter a completed round result;
- delete or rewrite ledger entries;
- create a financial entry without a balanced journal;
- bypass partner wallet confirmation;
- deploy untested game math, RNG or ledger changes.

## 10. Minimum partner certification test suite

1. Valid launch token, expired token, replayed nonce and invalid signature.
2. Unknown partner, suspended partner and disabled game.
3. Currency mismatch and bet below/above configured limits.
4. Bet accepted, declined, duplicated and timed out after partner acceptance.
5. Win accepted, duplicated and timed out after partner acceptance.
6. Partner status query returns pending, confirmed, declined and not found.
7. Player disconnect before bet confirmation and after confirmation.
8. Game server restart during an open round.
9. Partner A outage while Partner B continues.
10. Reconciliation with exact match, delayed record, duplicate and amount mismatch.
11. Rate-limit exhaustion and circuit-breaker recovery.
12. Audit evidence export and settlement report verification.

No partner goes live until all required cases pass in its sandbox/UAT environment.

## 11. Rollout sequence

- **P0 — Baseline verification:** restore V154 to isolated staging; compile SQL; map RPCs and financial tables.
- **P1 — Contract and simulator:** publish canonical API, mock partner wallet and contract tests; no real-money calls.
- **P2 — Transaction core:** implement idempotent wallet orchestrator, UNKNOWN resolution and provider ledger.
- **P3 — First adapter:** integrate one sandbox partner end-to-end; keep existing ASIX game flow unchanged.
- **P4 — Game certification:** verify game math, RNG, reconnect, round recovery and required independent testing.
- **P5 — Control Center:** partner health, financial exceptions, approvals, reconciliation and audit.
- **P6 — Controlled launch:** legal/compliance approval, partner UAT, load/security tests, on-call runbooks and staged traffic ramp.

## 12. Current blockers inherited from repository handover

The repository itself records that:
- the complete 128 historical migration SQL bodies are not available;
- the checked-in schema is catalog-reconstructed, not a verified clean restore;
- V157 is a staging-only candidate and has not been PostgreSQL-compiled or smoke-tested;
- a clean restore and end-to-end gameplay/financial smoke test remain outstanding;
- the active V25 worker and non-deployed V26 candidate must remain clearly separated.

These blockers must be closed before a provider integration is allowed to touch production financial flows.

## 13. Definition of done for Stage 1

Stage 1 is complete when:
- this provider boundary is accepted as the architecture baseline;
- the V154 database can be restored and validated in isolated staging;
- current financial RPCs and wallet semantics are documented;
- a partner simulator can complete launch, bet, win, status-query and reconciliation flows;
- duplicate and timeout tests prove no duplicate financial effect;
- no production endpoint, game rule or live database behavior has been changed by this design stage.
