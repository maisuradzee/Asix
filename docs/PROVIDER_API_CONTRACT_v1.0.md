# ASIX Provider API Contract v1.0

**Status:** implementation contract proposal; not deployed.  
**Scope:** partner-facing launch/session entry and the internal canonical wallet adapter boundary.  
**Compatibility rule:** this contract is separate from the existing ASIX consumer-game wallet and the active `super-worker` V25 API.

## 1. Integration topology

ASIX exposes a stable provider launch/session contract to casinos and aggregators. ASIX then calls each operator's wallet protocol through a partner-specific adapter.

```text
Operator / Aggregator
  ├─ signed launch request ───────────────> ASIX Provider Gateway
  └<─ launch URL + short-lived token ──────┘
                                           |
                                           v
                                   Session / Game Runtime
                                           |
                                canonical wallet command
                                           v
                                  Wallet Orchestrator
                                           |
                                  Partner-specific adapter
                                           |
                                           v
                                    Operator wallet API
```

The partner's wallet API is not assumed to be identical across operators. ASIX owns the canonical internal interface; each adapter translates that interface into the partner's signed requests, response codes and status-query semantics.

## 2. Authentication and launch

Preferred launch mechanism:
- Server-to-server signed launch request (HMAC-SHA-256 or mutually authenticated TLS as agreed with partner).
- Timestamp and one-time nonce; configurable clock-skew window.
- Partner key identifier to support key rotation.
- Nonce persisted in a replay-protection store with a unique constraint.
- Short-lived opaque launch token; store only a cryptographic hash.
- Token bound to partner, pseudonymous player reference, session reference, game, currency, jurisdiction and expiry.
- Token consumed once. A deliberate resume flow uses a separate, explicit session-resume operation.

Never accept identity, balance, currency or bet limits supplied by the browser as authoritative.

## 3. Suggested partner-facing endpoints

| Method | Path | Purpose |
|---|---|---|
| POST | `/provider/v1/launches` | Validate signed launch context and issue launch URL/token |
| GET | `/provider/v1/games` | Return partner-enabled games, locales and currencies |
| GET | `/provider/v1/sessions/{session_id}` | Return a minimal session status for authorized partner support |
| POST | `/provider/v1/sessions/{session_id}/close` | Request a controlled session close; does not alter completed rounds |

Partner-facing endpoints require partner authentication, authorization and per-partner rate limits. The game client does not call operator wallet endpoints directly.

## 4. Canonical launch request

```json
{
  "partner_code": "operator-a",
  "partner_player_ref": "opaque-player-91",
  "partner_session_ref": "operator-session-abc",
  "game_code": "ASIX_CARD",
  "currency": "GEL",
  "locale": "ka-GE",
  "jurisdiction": "GE",
  "issued_at": "2026-11-21T08:00:00Z",
  "expires_at": "2026-11-21T08:01:00Z",
  "nonce": "unique-random-value",
  "key_id": "operator-a-2026-01"
}
```

This example is illustrative. Partner identifiers must be pseudonymous, and the contract must define exactly which fields are signed and how canonical serialization is constructed.

## 5. Canonical wallet adapter interface

Each partner adapter must implement these logical operations:

| Operation | Purpose | Required behavior |
|---|---|---|
| `debitBet(command)` | Debit stake from operator-controlled player wallet | Return confirmed, declined, pending or unknown; idempotent |
| `creditWin(command)` | Credit win to operator-controlled player wallet | Return confirmed, pending or unknown; idempotent |
| `refund(command)` | Compensating credit for an eligible prior debit | Reference original transaction and approved reason |
| `getTransactionStatus(query)` | Resolve an uncertain prior request | Read-only; never create a new wallet effect |
| `healthCheck()` | Check partner endpoint availability | No financial side effects |

A partner may not support a native rollback. In that case, the adapter implements the agreed compensation process rather than simulating a rollback.

## 6. Canonical wallet command

Required fields:
- `transaction_id`: ASIX UUID.
- `idempotency_key`: unique for partner + operation + business transaction.
- `partner_code`.
- `partner_player_ref`.
- `partner_session_ref`.
- `round_id`.
- `operation`: BET, WIN or REFUND.
- `amount_minor`: positive integer.
- `currency`: ISO 4217 code.
- `currency_exponent`: resolved from a maintained currency registry, not trusted from client input.
- `created_at`.
- `request_hash` — canonical fingerprint generated internally by ASIX, not trusted from the partner/client.

GEL uses tetri as its minor unit (100 tetri = 1 GEL). Do not assume every partner currency has two decimal places. All calculations use integer minor units or exact decimal arithmetic.

## 7. Canonical adapter response

```json
{
  "state": "CONFIRMED",
  "partner_transaction_ref": "operator-tx-777",
  "currency": "GEL",
  "amount_minor": 1250,
  "response_code": "OK",
  "response_at": "2026-11-21T08:00:02Z"
}
```

Allowed states:
- `CONFIRMED`: partner has confirmed the wallet effect.
- `DECLINED`: partner definitively rejected the request.
- `PENDING`: partner confirms processing is still in progress.
- `UNKNOWN`: ASIX cannot determine whether the effect occurred.

A timeout, connection reset, malformed response or 5xx after sending a request must not be treated as DECLINED. It is UNKNOWN until a status query resolves it.

## 8. Standard error envelope

```json
{
  "ok": false,
  "error": {
    "code": "PARTNER_TRANSACTION_UNKNOWN",
    "message": "The operator outcome has not yet been confirmed.",
    "retryable": false,
    "resolution": "QUERY_STATUS",
    "correlation_id": "uuid"
  }
}
```

Stable internal error codes:
- `AUTH_REQUIRED`
- `SIGNATURE_INVALID`
- `REQUEST_EXPIRED`
- `REPLAY_DETECTED`
- `PARTNER_SUSPENDED`
- `GAME_DISABLED`
- `CURRENCY_NOT_ALLOWED`
- `BET_LIMIT_EXCEEDED`
- `IDEMPOTENCY_CONFLICT`
- `PARTNER_DECLINED`
- `PARTNER_TRANSACTION_UNKNOWN`
- `PARTNER_UNAVAILABLE`
- `RECONCILIATION_MISMATCH`

Never return stack traces, internal database errors, secret references or raw partner payloads to the browser.

## 9. Idempotency contract

- Scope: `partner_id + idempotency_key`.
- Store a canonical request hash before external dispatch.
- Same key + same hash returns the original transaction state/result.
- Same key + different hash returns `IDEMPOTENCY_CONFLICT`.
- An idempotency key is never recycled.
- Partner transaction references are unique within the partner where the partner protocol supports it.
- Status queries are read-only and may be retried with bounded backoff.

## 10. Security and reliability requirements

- TLS for every network hop; partner-specific signature or mTLS contract.
- Timestamp tolerance and nonce replay protection.
- Key identifiers and overlapping key rotation windows.
- Partner-specific credentials, rate limits, circuit breakers and concurrency budgets.
- Request/response redaction before logging.
- Correlation ID carried from launch through session, round, wallet request, ledger journal and settlement.
- No service-role key, signing key or partner secret in frontend code.
- Partner isolation: one partner's outage or malformed response must not impact another partner.

## 11. Versioning and change policy

- Public API uses explicit major version path.
- Additive optional fields may be backward-compatible.
- Removing/renaming fields or changing financial semantics requires a new major version and partner migration plan.
- Every adapter stores the protocol version and configuration version used for each transaction.
- Contract tests run before every adapter release.

## 12. Go-live gates

No real-money launch until:
1. Partner technical specification and wallet semantics are signed off.
2. Game math/RNG and game lifecycle have passed applicable independent testing.
3. Launch authentication, replay protection and tenant isolation are tested.
4. Idempotency and UNKNOWN recovery tests pass.
5. Partner UAT and reconciliation tests pass.
6. Legal/regulatory approvals and contractual settlement definitions are confirmed.
7. Monitoring, escalation, restore and rollback runbooks are active.
