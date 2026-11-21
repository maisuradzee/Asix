# Local mock operator wallet simulator

This is a local-only test double for ASIX partner adapter development. It is not a real casino wallet, not a production endpoint and not connected to the live ASIX project.

## Requirements
- Deno 1.40+ (or a compatible current Deno runtime).

## Run locally
```bash
deno run --allow-net=127.0.0.1:8787 provider-reference/simulator/server.ts
```

Optional environment values:
- `PORT` — defaults to `8787`.
- `SIM_INITIAL_BALANCE_MINOR` — defaults to `100000` for each new player/currency pair.

The listener binds to `127.0.0.1` only. It stores balances and transaction records in memory; restarting clears them.

## Routes
- `GET /health`
- `POST /wallet/bet`
- `POST /wallet/win`
- `POST /wallet/refund`
- `GET /wallet/transactions/{transactionRef}`

Every POST requires an `idempotency-key` header and a JSON body with transactionRef, playerRef, amountMinor, currency, sessionRef and roundRef. Refund additionally requires originalTransactionRef.

## Fault injection
Set `x-simulate-fault` to one of:
- `normal` — process normally.
- `decline` — definitive decline.
- `accept_then_timeout` — apply and persist the wallet effect, then return HTTP 504 to simulate a lost response.
- `pending_then_confirm` — return pending; the first status query resolves and applies the effect once.

The simulator demonstrates why a timeout must lead to status inquiry and reuse of the same idempotency key, not a new debit.

## Tests
```bash
deno test provider-reference/simulator/server_test.ts
```

Tests cover duplicate delivery, idempotency conflicts, acceptance with lost response, pending resolution and refund limits.

## Limitations
- In-memory only; no durability, authentication, TLS, production rate limiting, persistence or signing.
- Test fault headers are intentionally available; they must never exist in a production adapter.
- It does not implement ASIX's Wallet Orchestrator; it only simulates the operator side of the integration.
