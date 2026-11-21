# ASIX B2B Provider Threat Model v1.0

**Scope:** provider gateway, partner launch, wallet orchestration, session/game boundary, provider ledger, reconciliation, Control Center and automation. This is an engineering threat model, not a formal penetration-test report.

## 1. Assets to protect

1. Game integrity: rules, RNG evidence, round state, results and replay records.
2. Financial integrity: wallet requests, partner acknowledgements, provider ledger and settlements.
3. Partner trust: credentials, signing keys, protocol configuration, limits and commercial terms.
4. Player privacy: pseudonymous operator identity, session history and regulated data where applicable.
5. Platform availability: game runtime, gateway, database, queues and recovery systems.
6. Auditability: traceability of staff actions, AI recommendations, approvals, releases and incidents.

## 2. Trust boundaries

- Casino/aggregator to ASIX public gateway.
- Player browser/client to ASIX game runtime.
- Provider gateway to internal services.
- ASIX to partner wallet/API.
- Runtime service identities to PostgreSQL and queues.
- Staff workstation to Control Center.
- AI analysis to deterministic Policy Engine.
- Production to staging/development environments.
- Primary infrastructure to backup/DR environment.

Every crossing must authenticate the caller, validate scope and payload, apply rate/size limits, assign correlation IDs and emit security-safe audit events.

## 3. Threat register

| Threat | Example attack/failure | Required controls |
|---|---|---|
| Spoofed partner | Caller sets a trusted partner_code in JSON | Derive tenant from verified key/signature, not body |
| Replay | Captured launch or wallet request submitted again | Timestamp, nonce uniqueness, one-time token, idempotency |
| Cross-tenant IDOR | Partner A requests Partner B session | Tenant scoping in service and DB, negative UAT tests |
| Key theft | Partner signing key exposed in logs or browser | KMS/secrets manager, redaction, rotation, short exposure |
| Amount tampering | Client changes amount/currency/round | Server derives authoritative bet amount and validates game state |
| Duplicate debit/credit | Retry after timeout | Durable idempotency, status lookup, partner ref uniqueness |
| False success | HTTP timeout treated as accepted debit | UNKNOWN state and no game progression before confirmation |
| Result manipulation | Admin or client changes result | Server authority, immutable round record, signed build/rules hashes |
| RNG compromise | Unauthorized RNG configuration/build change | Controlled entropy source, access segregation, test evidence, release gates |
| Ledger tampering | Update/delete old journal | Append-only privileges, hash/audit, compensating entries |
| Partner outage cascade | One adapter blocks all work | Per-partner queues, circuit breakers, concurrency/rate isolation |
| Privilege escalation | Staff account gains settlement/admin rights | MFA, RBAC, JIT access, dual control, audit |
| AI overreach | Model executes arbitrary SQL or changes limits | No direct privileged tools; Policy Engine allowlist |
| Supply-chain attack | Compromised dependency or build action | Lockfiles, dependency scanning, pinned/reviewed actions, signed artifacts |
| Data exfiltration | Logs expose tokens or player details | Data minimization, redaction, scoped access, retention |
| Backup compromise | Attacker encrypts/deletes production and backups | Separate accounts/keys, immutable backup, restore drills |
| Insider collusion | Same person changes and approves adjustment | Segregation of duties, dual approval, independent audit |

## 4. Security architecture requirements

### Authentication
- HMAC signatures must define canonical serialization, signed headers, timestamp and body digest.
- Use constant-time signature comparison.
- Support overlapping active keys during rotation.
- Revocation must take effect within a defined operational SLA.
- Avoid long-lived bearer secrets in launch URLs.
- Launch token contains no unnecessary PII and is stored hashed.

### Authorization
- Resolve partner identity from credential mapping.
- Check partner state, game enablement, jurisdiction, currency and limits on every relevant request.
- Staff permissions are action-specific, not just page-level.
- Sensitive functions live outside exposed schemas and have minimal EXECUTE grants.
- No authorization decisions based on user-editable metadata.

### Data and cryptography
- TLS in transit; managed encryption at rest.
- KMS-backed key encryption and rotation.
- Never log authorization headers, launch tokens or raw wallet secrets.
- Hash or redact partner request/response evidence.
- Retain only the minimum pseudonymous player reference required for reconciliation.

### Game and financial controls
- Server is authoritative for game state and amounts.
- Partner debit must be confirmed before stake is committed.
- Completed outcomes are immutable.
- Every journal balances per currency.
- No correction rewrites historical records.
- Uncertain wallet outcomes remain visible exceptions until resolved.

## 5. Abuse cases and expected response

**Partner credential compromise:** disable or revoke affected key, isolate only that partner, preserve logs and pending transaction evidence, rotate through approved procedure, validate partner ownership before reactivation.

**Suspected game-result manipulation:** pause new affected game sessions, preserve build/rules/RNG evidence, leave already confirmed outcomes immutable, initiate independent review and notify required parties under applicable rules.

**Provider ledger discrepancy:** freeze affected settlement release, preserve source transaction evidence, compare partner and ASIX references, record mismatch and require human resolution.

**Control Center compromise:** revoke staff sessions and privileged tokens, isolate admin access, preserve audit history, do not stop safe game runtime unless the incident affects data/game integrity.

## 6. Residual risks

Some risks cannot be solved solely by code:
- partner wallet protocol weaknesses;
- jurisdiction-specific licensing/certification;
- privileged insider collusion;
- third-party cloud/platform outage;
- contractual ambiguity in GGR, voids, bonuses and chargebacks.

These require partner contracts, independent audit, legal review, external security testing and operational controls.

## 7. Verification

Threat controls must be tested by:
- negative authentication/authorization tests;
- tenant-isolation tests;
- replay and idempotency tests;
- dependency and secret scanning;
- penetration testing;
- staff access review;
- game/RNG independent testing;
- backup and incident-response exercises.
