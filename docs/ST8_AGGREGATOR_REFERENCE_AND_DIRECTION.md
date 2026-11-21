# ST8 Aggregator Integration Reference and API Direction Map

**Reference source:** official ST8 Operator API documentation, v1, publicly available at https://docs.st8api.com/  
**Status:** architecture reference only. This document does not establish an ASIX–ST8 partnership, approval, certification or provider onboarding.

## 1. Critical API direction distinction

The public ST8 document identifies ST8 as a Game Aggregator and explicitly labels its public API as an **Operator API**. The documentation reviewed was published as Operator API v1; its changelog includes updates through 2026-06-29. It describes APIs for casino Operators: Game Launch, Query, Bonus and Transfer Wallet. If the Operator selects Seamless Wallet, the Operator must implement the Seamless Wallet API callbacks.

This is not, by itself, the technical specification for a Game Developer/Provider to submit games to ST8. ASIX must request the current provider/developer integration pack directly from ST8 before implementing a provider-side adapter.

**Do not copy the Operator API endpoints and assume that they are the API ASIX must expose as a game provider.**

## 2. ST8 wallet modes and relevance to ASIX

### Seamless Wallet
The official documentation says the Operator holds the player's balance and performs balance checks, debits and credits through callbacks. This is the closer conceptual fit for ASIX's B2B design:
- the Operator owns the player account and wallet;
- ASIX operates the game;
- wallet requests are sent through the agreed partner protocol;
- ASIX records game and provider-side financial evidence;
- ASIX does not become the player's deposit/withdrawal wallet.

### Transfer Wallet
The Operator transfers an amount to the Aggregator, which then holds and changes the player's game balance. The Operator later transfers funds in/out and may query transaction records or consume a transaction stream.

This is a different custody/operating model. ASIX must not silently adopt it. Any transfer-wallet arrangement requires explicit legal, contractual, accounting, safeguarding and reconciliation review.

## 3. Security and signing profile observations

The public ST8 Operator API documentation describes ECDSA request signatures using its `x-st8-sign` header:
- the requester signs the payload with a private key;
- the receiver verifies it with the corresponding public key;
- the public example uses an EC P-256 key and SHA-256;
- the documented signature header is `x-st8-sign`;
- the documentation states that the entire payload must be verified, including fields that may be added later.

This is an important reason not to impose one universal authentication method on all ASIX partners.

ASIX's own proposed Provider API v1 currently uses a host-bound HMAC-SHA256 profile with timestamp, nonce and body hash. That is ASIX's proposed partner-facing contract, not a claim of ST8 wire compatibility.

For any ST8 connection:
1. Obtain the provider/developer-specific auth specification.
2. Confirm whether requests are signed using ECDSA, which exact bytes are signed and how signatures are encoded.
3. Confirm key exchange, rotation, revocation and environment separation.
4. Verify the entire raw payload before parsing or acting on it.
5. Implement a separate protocol/auth adapter; do not weaken the existing ASIX HMAC gateway.

## 4. Launch and session token lessons

The ST8 Operator API describes two launch patterns: Operator-built launch URL with a `/check` callback, or a server-to-server `/launch` request.

The public guide also documents that:
- launch tokens should be unique for a player/game/currency launch;
- the token should be checked against the requested game code;
- a separate wallet/session token should be returned by `/check`, rather than reusing the launch token exposed in the game URL;
- wallet tokens may be referenced by delayed credit/cancel operations, so historical token references must remain resolvable for the required period.

ASIX design mapping:
- `launch_token` is short-lived and intended only to start a game session;
- a separate durable `partner_session_ref` and ASIX `session_id` identify the B2B session;
- wallet calls use the durable session reference and immutable ASIX transaction ID;
- token expiry and historical reference retention are separate policies;
- do not store the raw launch token after issuance; store only its cryptographic hash;
- any longer-lived session/wallet token must be protected separately and retained according to contract and law.

The ST8 documentation mentions a 15-minute launch-token expiry recommendation and retention of wallet tokens for at least a couple of months due to delayed callbacks. These are ST8-specific documented recommendations, not automatic universal ASIX retention periods. ASIX must set each partner's values from its actual contract and legal retention schedule.

## 5. Transaction and round integrity lessons

The public ST8 Operator API describes:
- `transaction_id` as a unique identifier and idempotency key;
- repeated requests with the same transaction ID must not be processed more than once;
- `round` as the identifier linking related debit and credit transactions;
- `round_closed` as an indication that a transaction closes the round;
- `cancel` as a reversal of a referenced transaction effect;
- a cancel ID that has not been seen before must still be stored so that the same transaction cannot be processed later.

ASIX mapping:
- use ASIX `transaction_id` as the durable local operation ID;
- maintain a partner-scoped idempotency key and partner transaction reference;
- maintain `round_id` separately from transaction ID;
- store each debit, credit and reversal independently;
- a cancellation/reversal creates a compensating record and never deletes the original;
- an unknown or not-yet-seen cancellation reference must create a durable tombstone/exception rule so a delayed original event cannot be applied after the cancellation;
- `round_closed` maps to an explicit round lifecycle transition and cannot be inferred from a client timeout.

## 6. Amount representation

The ST8 Operator API describes amounts as stringified decimal values in its callback payloads. ASIX should preserve partner wire-format exactly in the adapter, but use integer minor units or exact decimal types internally.

Never parse financial amounts with JavaScript `parseFloat`. Adapter conversion must:
- use the currency's defined exponent;
- reject excess decimal precision;
- reject scientific notation unless the contract explicitly permits it;
- use deterministic rounding agreed by contract;
- preserve the original decimal string for redacted audit evidence when required.

## 7. How ASIX should integrate through ST8

Before implementation, request these ST8 materials:
1. Provider/Game Developer onboarding documentation, not only the public Operator API.
2. Provider-side game server/RGS API and authentication profile.
3. Game catalogue metadata, launch requirements, session lifecycle and supported currencies.
4. Wallet responsibility and callback direction for the proposed integration mode.
5. Sandbox credentials, sample payloads, test accounts and certification/UAT checklist.
6. Settlement reports, GGR calculation definition and commercial terms.
7. Incident, rate-limit, retry, idempotency and reconciliation requirements.
8. Applicable certification and jurisdiction approval requirements.

Then build a separate ST8 adapter that maps its actual provider-side protocol to ASIX's canonical interfaces. The current public Operator API is useful as a model of operator wallet responsibilities and transaction safety, but it must not be mistaken for ST8's provider-facing contract.

## 8. Integration decision

ASIX canonical layer remains protocol-neutral:

```text
ASIX Game Runtime
       |
       v
Canonical Wallet Orchestrator
       |
       +--> Direct Casino Adapter (partner-specific)
       |
       +--> Aggregator Adapter (ST8 or another aggregator)
       |
       v
Operator / Aggregator protocol and wallet model
```

All external differences belong in the partner adapter:
- request/response mapping;
- signature verification/signing;
- token lifecycle;
- idempotency field mapping;
- transaction state normalization;
- currency and decimal conversion;
- timeout/status-query behavior;
- reconciliation report ingestion.

Do not create ST8-specific conditions inside the core game engine or financial ledger.
