# ASIX Provider Operations Runbooks v1.0

## General incident protocol

1. Create incident ID and assign severity.
2. Identify affected partner, game, region and service.
3. Preserve relevant logs, correlation IDs, transaction/round references and deployment versions.
4. Contain only the affected scope where possible.
5. Do not guess transaction outcome or game result.
6. Recover using approved procedure.
7. Independently verify business and technical health.
8. Record cause, financial impact, customer/partner impact and preventive actions.

## RB-01 — Partner wallet timeout / UNKNOWN

**Trigger:** wallet debit/credit request times out, disconnects or returns an ambiguous response after dispatch.

Actions:
1. Persist transaction as UNKNOWN with original idempotency key and request hash.
2. For a bet, do not progress the game as though debit were confirmed.
3. Query the partner's status endpoint using the original reference/key.
4. If CONFIRMED, persist partner confirmation and continue the one original action.
5. If DECLINED, reject the action or close its pending workflow safely.
6. If PENDING, schedule bounded status polling with backoff.
7. If unresolved past the partner SLA, mark EXCEPTION, isolate further risky actions and page Financial Controller + technical on-call.

Never create a new idempotency key to retry an uncertain financial operation.

## RB-02 — Duplicate or mismatched transaction

1. Stop settlement release for the affected partner/period.
2. Identify the ASIX transaction, partner reference and idempotency key.
3. Compare amount, currency, operation, session and round.
4. Determine whether duplicate was network delivery, partner posting or local posting.
5. Do not delete either record.
6. Create a linked compensating transaction only after evidence and authority are established.
7. Re-run reconciliation and retain the original and correction references.

## RB-03 — Partner API outage

1. Verify the outage using safe health/status probes.
2. Open circuit breaker for that partner only.
3. Stop new wallet-dependent gameplay for that partner.
4. Resolve in-flight UNKNOWN operations by status query when possible.
5. Keep other partners and unaffected games running.
6. Notify partner contact under the SLA.
7. Close circuit only after consecutive successful health checks and wallet test probes.
8. Require human approval to resume after RED financial-integrity incident.

## RB-04 — Game state integrity exception

1. Freeze new actions for the affected session/round.
2. Preserve last confirmed event number, snapshot, game version, rules hash and RNG reference.
3. Attempt deterministic replay in isolated recovery environment.
4. If replay matches, restore only from verified confirmed state.
5. If replay diverges, keep round isolated and escalate to Technical Owner / independent game reviewer.
6. Never manufacture a result, modify a completed result or silently void a financial effect.
7. Record any approved void/refund as separate auditable actions.

## RB-05 — Suspected key compromise

1. Declare security incident and record key ID, partner and time window.
2. Disable/revoke the affected key or partner route using approved emergency authority.
3. Do not print secret material into incident ticket/chat.
4. Preserve authentication, replay and transaction logs.
5. Coordinate key rotation with verified partner contact.
6. Review requests since last known-good timestamp and investigate affected sessions/transactions.
7. Re-enable only after security validation and documented approval.

## RB-06 — Ledger or reconciliation imbalance

1. Block affected journal posting or settlement release.
2. Confirm the journal uses one currency and all lines are present.
3. Recalculate debit/credit totals from immutable entries.
4. Compare source transaction, adapter response and partner statement.
5. Classify missing/duplicate/delayed/mismatched record.
6. Never edit posted historical lines.
7. Use linked reversal/adjustment only with approval.
8. Require zero unclassified difference before closing the incident.

## RB-07 — Failed deployment

1. Stop further rollout automatically.
2. Route traffic back to last approved artifact if health gate says rollback is safe.
3. Verify game runtime, wallet flow, database compatibility and business probes.
4. Do not automatically reverse an already-applied destructive database migration.
5. Reconcile any in-flight financial operations from transaction journal and partner status.
6. Require review and a corrected release candidate before retry.

## RB-08 — Backup restore / disaster recovery

1. Declare DR event and choose authoritative recovery point.
2. Isolate restore target from live partner traffic.
3. Restore encrypted backup and replay confirmed durable events according to recovery plan.
4. Validate schema/version, checksums, journal balance, transaction IDs and round snapshots.
5. Reconcile with each affected partner before resuming financial traffic.
6. Switch traffic only after Technical and Financial Owners sign off.
7. Preserve restored evidence and document RPO/RTO achieved.

## Incident closure checklist

- Root cause identified or explicitly bounded.
- Affected partners/sessions/transactions enumerated.
- Financial impact reconciled or all remaining items tracked as exceptions.
- Game results and audit evidence preserved.
- Partner/regulator/customer notifications assessed.
- Recovery independently verified.
- Preventive action has owner and deadline.
