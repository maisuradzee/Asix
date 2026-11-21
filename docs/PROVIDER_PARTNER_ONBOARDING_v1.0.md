# ASIX Partner Onboarding and Certification v1.0

## Stage A — Commercial and legal intake

Collect and verify:
- legal entity and authorized signatories;
- operator/aggregator role and operating jurisdictions;
- applicable licenses/authorizations and product scope;
- game distribution territories and excluded territories;
- player-wallet ownership and responsibility;
- fee/revenue-share model and definition of GGR;
- treatment of bonuses, taxes, refunds, voids, chargebacks and jackpots if relevant;
- currency, conversion source, rounding and settlement schedule;
- audit, dispute, record-retention and incident-notification terms;
- support contacts and escalation SLA.

No technical sandbox success substitutes for contract or legal approval.

## Stage B — Technical discovery

Obtain current official technical specifications:
- launch and authentication protocol;
- wallet debit/credit/refund operations;
- transaction status-query support;
- idempotency semantics and partner reference guarantees;
- error codes and retry rules;
- currencies and minor-unit exponents;
- limits, rate limits and maintenance windows;
- sandbox credentials and test accounts;
- settlement and transaction report formats;
- key rotation and incident contacts.

Record the exact document version, date and owner.

## Stage C — Partner configuration

Create an isolated partner record with:
- immutable partner code;
- lifecycle status;
- jurisdiction allowlist;
- allowed games/currencies/locales;
- bet/payout/exposure limits;
- adapter/protocol/config version;
- secret-manager references and key IDs;
- rate limits and concurrency budgets;
- reconciliation schedule;
- commercial contract version and effective dates.

No plaintext secret is stored in configuration tables or Git.

## Stage D — Sandbox integration

1. Validate signed launch request.
2. Verify timestamp, nonce and one-use token.
3. Launch a test session.
4. Test debit accepted/declined/pending/unknown.
5. Test win credit and status query.
6. Test refund/compensation.
7. Test disconnect/reconnect and round recovery.
8. Run partner-specific UAT matrix.
9. Generate reconciled test statement and settlement report.

## Stage E — Operational readiness

- partner-specific alerts and circuit breaker tested;
- on-call escalation and partner contact tree confirmed;
- dashboard access role-tested;
- settlement calendar and invoice process configured;
- backup/restore and key revocation procedures tested;
- data retention and privacy obligations mapped;
- support and incident channels agreed.

## Stage F — Controlled production enablement

Production activation requires separate sign-offs:
- Business Owner: contract and commercial schedule.
- Compliance Owner: jurisdiction/licensing/certification.
- Technical Owner: security, capacity, reliability, DR and rollback.
- Financial Controller: wallet semantics, ledger mapping, reconciliation and settlement.
- Partner: UAT sign-off and production keys.

Start with restricted games, currencies, limits and exposure. Increase traffic only after agreed observation periods and no unresolved critical incidents.

## Stage G — Ongoing partner lifecycle

Monitor:
- contract/license/certificate/key expiry;
- API version changes;
- transaction decline/unknown/latency rates;
- reconciliation mismatch aging;
- game availability and commercial performance;
- incident history and SLA compliance.

Suspension reasons must be explicit and audited. Termination must revoke credentials and preserve records according to legal/contract retention.
