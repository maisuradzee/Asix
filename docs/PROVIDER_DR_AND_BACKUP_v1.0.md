# ASIX Provider Disaster Recovery and Backup Model v1.0

**Status:** target design. RPO/RTO figures are planning objectives and must be validated by timed restore tests, not advertised guarantees.

## 1. Recovery design principles
- Game runtime, wallet transaction journal, provider ledger, audit data and Control Center have different recovery priorities.
- A dashboard or AI analytics outage must not corrupt live game state or confirmed financial records.
- A transaction with uncertain partner outcome remains UNKNOWN until reconciled after recovery.
- Restored data is not trusted for production traffic until integrity and partner reconciliation checks pass.
- Backups must be isolated from the production identity and administrative blast radius.

## 2. Data classes and provisional objectives

| Data class | Recovery point objective | Recovery time objective | Validation |
|---|---:|---:|---|
| Confirmed financial transaction/ledger journal | Zero confirmed loss target | ≤15 min target | WAL/replication and transaction-level reconciliation |
| Game state/event history | Last confirmed event/snapshot | ≤60 sec target where feasible | Deterministic replay and round-state verification |
| Partner configuration/key metadata | ≤5 min target | ≤30 min target | Version and key-reference validation |
| Control Center/audit metadata | ≤5 min target | ≤30 min target | Audit chain and operator access validation |
| Analytics/reporting | ≤15 min target | ≤2 hr target | Rebuild from operational/event source |

The exact targets depend on chosen hosting, replication mode, database plan, region and partner contracts.

## 3. Backup classes
- Continuous transaction-log/WAL protection where supported.
- Frequent encrypted database backups.
- Immutable object storage for audit exports, game evidence, settlement reports and approved artifacts.
- Separate configuration backup including version references but not plaintext secrets.
- Independent recovery environment with least-privilege access.

Do not store signing secrets or service-role keys inside ordinary database exports or Git repositories.

## 4. Restore sequence
1. Declare DR event and select authoritative recovery point.
2. Prevent accidental writes to the source/restore target.
3. Provision isolated recovery environment and restore database.
4. Apply only verified schema migrations in the recorded order.
5. Restore object/evidence archives and verify checksums.
6. Verify roles, grants, RLS, SECURITY DEFINER functions and secrets references.
7. Reconcile transaction states, unresolved UNKNOWN operations and ledger journals.
8. Replay only confirmed durable events; do not replay uncertain wallet commands as new transactions.
9. Run partner health/status checks and settlement reconciliation.
10. Obtain Technical Owner and Financial Controller sign-off before reopening financial activity.

## 5. Region and provider outage
- Maintain a documented dependency map for database, queue, object store, secrets manager, network and partner endpoints.
- Prepare a second-region recovery target only after data residency and legal requirements are checked.
- Use per-partner isolation and circuit breakers to avoid a single partner causing global outage.
- Define partner contact paths for status lookup and reconciliation during regional failure.

## 6. Required exercises
- Quarterly restore of a full database backup to isolated environment.
- WAL/PITR recovery exercise where supported.
- Lost queue worker and expired lease recovery.
- Region/provider outage tabletop exercise.
- Secrets-manager/key reference restore exercise.
- Reconciliation after simulated lost wallet response.
- Annual end-to-end disaster simulation with partner notification and business sign-off.

Every exercise records start/end time, recovery point, data loss observed, transaction mismatches, RTO/RPO achieved, defects, owner and remediation deadline.

## 7. Recovery stop conditions
Do not resume financial traffic when:
- ledger balance invariant fails;
- any material transaction remains unclassified;
- a game state cannot be reproduced from confirmed evidence;
- partner credentials/configuration cannot be verified;
- tenant isolation or access policies are not intact.
