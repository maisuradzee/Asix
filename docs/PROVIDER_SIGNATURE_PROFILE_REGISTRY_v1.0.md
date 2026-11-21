# ASIX Partner Signature and Authentication Profile Registry v1.0

## 1. Policy

Authentication is selected per partner, endpoint direction and exact protocol version. ASIX does not assume every casino, aggregator or certification environment uses the same signature scheme.

A partner configuration must record:
- partner code and trusted identity;
- integration direction (inbound to ASIX / outbound from ASIX);
- auth profile ID and version;
- signature header or mTLS identity;
- canonical payload definition;
- public/private key reference and key ID;
- timestamp and nonce rules, if defined by the partner protocol;
- allowed network sources, where contractually supported;
- key validity, overlap and revocation status.

No endpoint may silently fall back to unsigned requests.

## 2. Current reference profiles

| Profile | Purpose | Signature / payload | Freshness and replay | Implementation status |
|---|---|---|---|---|
| ASIX-HMAC-SHA256-v1 | ASIX's proposed Provider API profile | HMAC-SHA256 over method, host, path/query, timestamp, nonce and raw-body hash | Signed timestamp + nonce store + application idempotency | Reference code and tests |
| ECDSA-P256-SHA256-PAYLOAD-v1 | Partner protocols documenting payload signing, including the public ST8 Operator API pattern | ECDSA P-256 / SHA-256, Base64 DER signature over exact POST body or encoded GET query | The reviewed ST8 profile does not define the same timestamp/nonce headers; use partner transaction IDs, one-time launch/session tokens and exact partner replay rules | Reference verifier and tests |
| mTLS | Partner protocols requiring client-certificate identity | TLS certificate chain and peer identity | Certificate validity, revocation and session controls | Architecture option; not implemented |
| OAuth2 / JWT | Partner protocols that explicitly require token-based auth | Issuer/audience/scope/expiry validated against trusted issuer metadata | Token expiry, audience, issuer and jti/replay rules as specified | Architecture option; not implemented |

## 3. HMAC profile

The proposed ASIX HMAC payload is:

```text
METHOD
HOST
PATH_AND_QUERY
TIMESTAMP_SECONDS
NONCE
SHA256_HEX_OF_RAW_BODY
```

Rules:
- sign the exact raw request body bytes;
- use lowercase normalized host and the exact path/query sent;
- compare signatures using Web Crypto verification;
- apply a bounded timestamp window;
- atomically consume a nonce only after the signature is valid;
- use partner-scoped durable nonce storage shared by all gateway instances;
- store key material only in a secrets manager/KMS.

## 4. ECDSA payload profile

The reference verifier supports ECDSA P-256 / SHA-256 with a Base64 ASN.1 DER signature and a partner-provided trusted public key.

Payload selection:
- POST: the exact raw HTTP body bytes;
- GET: the exact encoded query string without the leading question mark.

The verifier validates the complete payload before JSON parsing. It does not add timestamp or nonce fields that the external protocol does not define. That does not mean replay can be ignored: the partner adapter must apply the exact protocol's transaction idempotency, token lifecycle and duplicate-request semantics.

The ECDSA reference is based on the publicly documented ST8 Operator API signature profile, not proof that ST8 uses the same profile for its private Provider/Developer onboarding contract.

## 5. Key and trust lifecycle

- Sandbox and production keys are separate.
- Key IDs are immutable; never overwrite key bytes under an existing ID.
- Rotation supports controlled overlap and explicit revocation.
- Public keys are pinned or resolved from a trusted configuration source.
- Private signing keys stay in KMS/HSM or a managed secrets service.
- Key creation, activation, rotation and emergency revocation are audited and independently approved.
- A revoked or unknown key is always rejected.

## 6. Replay and idempotency are separate controls

A valid signature proves payload authenticity and integrity; it does not by itself prove that the action has never been processed before.

For every financial operation:
- enforce a durable partner-scoped idempotency key;
- compare a server-generated canonical request fingerprint;
- same key + same payload returns the stored result;
- same key + different payload is rejected;
- UNKNOWN wallet outcomes are resolved by status query;
- do not retry debit/credit as a new financial transaction.

Where the protocol has no timestamp/nonce, do not invent incompatible signed fields. Rely on the protocol's exact transaction IDs, session/token rules, network protections and auditable duplicate handling.

## 7. Production status

All authentication profiles in this package are reference code, not deployed gateways. A profile becomes production-ready only after partner specification review, key exchange, positive/negative tests, replay tests, security review and partner UAT.
