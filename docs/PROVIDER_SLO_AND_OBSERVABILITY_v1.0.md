# ASIX Provider SLO and Observability Model v1.0

**Status:** proposed service objectives for capacity planning and operational measurement. These are targets, not achieved production metrics.

## 1. SLI categories

### Availability
- Provider Gateway successful eligible request rate.
- Partner wallet adapter availability per partner.
- Game runtime healthy session-minute ratio.
- Control Center availability (non-critical to live game execution).

### Financial correctness
- Duplicate financial effects: target 0.
- Posted unbalanced journals: target 0.
- Unresolved UNKNOWN transactions over SLA: tracked and escalated.
- Reconciliation coverage: 100% of eligible transactions are matched or have an assigned exception.
- Refund and win credits confirmed exactly once under partner protocol.

### Game correctness
- Rounds completed without integrity exception.
- State recovery from last confirmed event.
- Duplicate game actions rejected by idempotency/version checks.
- Invalid game transitions rejected.
- RNG evidence/build/rules hash attached to completed round metadata.

### Performance
- p50/p95/p99 launch latency.
- p50/p95/p99 wallet debit latency per partner.
- Game action processing latency.
- Queue age and oldest pending outbox event.
- Database query latency and connection saturation.

## 2. Proposed objectives

Set separate objectives per partner and service class. Initial planning targets:

| SLI | Initial target | Measurement window |
|---|---:|---|
| Gateway availability | 99.95% | monthly |
| Game runtime availability | 99.95% | monthly |
| Confirmed financial effect duplication | 0 | continuous |
| Unbalanced posted journals | 0 | continuous |
| Transaction trace coverage | 100% | daily |
| Partner reconciliation coverage | 100% matched or exceptioned | daily / contract period |
| Critical alert acknowledgement | 5 minutes | 24/7 on-call target |
| Recovery test execution | at least quarterly | quarterly |

Wallet latency and recovery SLAs must be partner-specific and contractually agreed. Do not publish a universal latency promise before measuring actual partner endpoints.

## 3. Business transaction probes

Do not rely on CPU or HTTP 200 alone. Track synthetic/business-flow probes:
1. Launch token accepted/rejected as expected.
2. Test partner adapter health endpoint.
3. Safe read-only transaction-status query.
4. Controlled sandbox debit/credit with test accounts.
5. Ledger posting invariant.
6. Reconciliation sample.

Production probes must never create real-money bets or credits unless explicitly designed, contractually permitted and separately approved.

## 4. Correlation model

Carry:
- correlation_id;
- partner_id;
- adapter/config version;
- game_code and game_version;
- session_id;
- round_id;
- action_id;
- wallet_transaction_id;
- partner_transaction_ref;
- ledger_journal_id;
- build/release ID.

Use UTC timestamps and synchronized clocks. Avoid putting player names or secrets into labels/cardinality-heavy metrics.

## 5. Alert policy

**Page immediately**
- potential duplicate debit/credit;
- confirmed result with unresolved payout outside SLA;
- game integrity/RNG evidence mismatch;
- suspected credential compromise;
- posted journal imbalance;
- cross-partner data access indication;
- production database corruption or backup loss.

**Urgent ticket / on-call**
- partner-specific elevated timeout/decline rate;
- rising UNKNOWN transaction age;
- growing outbox lag;
- reconciliation mismatch above threshold;
- high database saturation.

**Routine**
- capacity trend;
- expiring partner key/certificate;
- upcoming settlement or contract expiry;
- non-critical report delay.

## 6. Error budget

An availability error budget may guide release risk, but it cannot relax financial integrity or security invariants. If availability consumes its budget, slow or freeze non-critical releases and capacity experiments. Never relax idempotency, authorization, ledger immutability or audit checks to recover availability.

## 7. Dashboard layout

- Global: service health, active partners, incidents, game/session counts, financial exceptions.
- Partner detail: adapter health, limits, error rate, wallet transaction age, reconciliation status.
- Financial control: confirmed debit/credit totals, unknowns, refunds, mismatch aging and settlements.
- Game integrity: build/rules version, round exceptions, reconnect/recovery statistics.
- Operations: deployment, worker, queue, database, backup and alert status.

Financial Controller sees business and money facts; infrastructure details remain role-restricted.
