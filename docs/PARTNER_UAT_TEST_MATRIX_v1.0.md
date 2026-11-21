# ASIX Partner Certification / UAT Test Matrix v1.0

A partner must pass the mandatory tests in its sandbox before production onboarding. Record evidence, build version, adapter version, test timestamp, partner witness and final result for each case.

| ID | Area | Test | Expected result |
|---|---|---|---|
| AUTH-01 | Authentication | Valid signed launch | Session context accepted |
| AUTH-02 | Authentication | Invalid signature | Rejected; no session/token created |
| AUTH-03 | Authentication | Expired request timestamp | Rejected |
| AUTH-04 | Replay | Reuse nonce | Rejected; replay audit event recorded |
| AUTH-05 | Token | Expired launch token | Rejected |
| AUTH-06 | Token | Consume one-use token twice | Second use rejected unless explicit resume contract |
| TEN-01 | Tenant | Partner A sends Partner B reference | Rejected; no cross-tenant data disclosure |
| TEN-02 | Tenant | Suspended partner starts session | Rejected |
| GAME-01 | Configuration | Disabled game requested | Rejected |
| GAME-02 | Configuration | Unsupported currency | Rejected |
| GAME-03 | Limits | Bet below minimum / above maximum | Rejected before wallet dispatch |
| WAL-01 | Bet | Partner confirms debit | Bet may proceed exactly once |
| WAL-02 | Bet | Partner declines debit | Bet rejected; no game progression |
| WAL-03 | Bet | Timeout after partner accepted | UNKNOWN; status query; no second debit |
| WAL-04 | Bet | Two concurrent identical requests | One financial effect; same result returned |
| WAL-05 | Idempotency | Same key with altered amount | IDEMPOTENCY_CONFLICT |
| WAL-06 | Win | Partner confirms credit | Win payment recorded once |
| WAL-07 | Win | Credit response lost | UNKNOWN; status query; game result remains immutable |
| WAL-08 | Refund | Valid refund references original debit | Compensating credit traced to original |
| WAL-09 | Refund | Refund exceeds original allowed amount | Rejected or approval exception |
| SES-01 | Session | Player disconnects before debit confirmation | No unconfirmed bet progression |
| SES-02 | Session | Player reconnects to a valid active session | State restored from confirmed server state |
| SES-03 | Recovery | Worker crashes after send | Lease recovery + same idempotency identity |
| REC-01 | Reconciliation | Exact partner statement match | MATCHED |
| REC-02 | Reconciliation | Delayed partner transaction line | Pending exception then matched |
| REC-03 | Reconciliation | Duplicate partner line | Duplicate classified; no double posting |
| REC-04 | Reconciliation | Amount or currency mismatch | Exception; no silent correction |
| ISO-01 | Isolation | Partner A endpoint unavailable | A isolated; Partner B continues |
| ISO-02 | Isolation | Partner A rate limit exhausted | A throttled; other partners unaffected |
| SEC-01 | Security | Attempt to read service secret in client | No secret exposed |
| SEC-02 | Security | Brute-force or replay burst | Rate limit / security alert |
| FIN-01 | Ledger | Journal has unequal debit and credit totals | Posting prevented |
| FIN-02 | Ledger | Attempt to update posted entry | Denied; immutable audit evidence |
| FIN-03 | Approval | High-value adjustment with one approver | Remains pending if dual approval required |
| OPS-01 | Autopilot | Adapter worker crash | Approved restart; health independently verified |
| OPS-02 | Autopilot | RED financial-integrity incident | Affected partner paused; evidence preserved; human escalation |
| OPS-03 | Deployment | New adapter fails health gate | Rollback; old healthy version retained |

## Evidence required per test

- Test ID and requirement reference.
- Partner sandbox environment and adapter/config version.
- Request/response correlation IDs.
- Redacted request and response evidence or hashes.
- Transaction and round references when applicable.
- Ledger journal/reconciliation item reference.
- Expected vs actual result.
- Pass/fail, defect severity and retest status.
- Partner and ASIX sign-off.

## Production exit criteria

- 100% of mandatory P0/P1 cases pass.
- No unresolved critical/high defects in authentication, tenant isolation, game integrity, wallet idempotency or ledger correctness.
- All UNKNOWN tests demonstrate status resolution and no duplicate effect.
- Reconciliation demonstrates both exact match and controlled mismatch handling.
- Partner-specific monitoring, alert routing, escalation and settlement reporting are operational.
- Legal, compliance, certification and contract approvals are recorded separately from technical UAT.
