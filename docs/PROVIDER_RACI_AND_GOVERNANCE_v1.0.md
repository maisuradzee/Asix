# ASIX Provider Accountability and RACI v1.0

## 1. Internal operating model
A small internal team can own governance, finance and technical direction, but cannot personally provide continuous 24/7 operations. Managed SRE/NOC and specialist vendors provide on-call coverage under contract.

Core internal functions:
- Business & Compliance Owner.
- Technical Platform Owner.
- Financial Controller.

External support may include managed SRE/NOC, software engineering, security testing, independent game testing/certification, legal counsel and accounting/audit.

## 2. Responsibility matrix

R = Responsible for execution; A = Accountable for final decision; C = Consulted; I = Informed.

| Activity | Business/Compliance | Technical Owner | Financial Controller | Managed SRE/NOC | Independent Lab / Legal |
|---|---|---|---|---|---|
| Partner contract/commercial terms | A/R | C | C | I | C |
| Jurisdiction/license determination | A/R | C | I | I | C |
| Provider architecture | C | A/R | C | C | I |
| Production security architecture | C | A | I | R | C |
| Game math/RNG certification | A | R | I | I | R |
| Partner API adapter | I | A | C | R/C | I |
| Wallet transaction workflow | I | A/R | C | C | I |
| Ledger chart and settlement mapping | C | C | A/R | I | C |
| Reconciliation exceptions | I | C | A/R | C | I |
| Manual financial adjustment | I | C | A/R with dual approval | I | C |
| Critical incident containment | I | A | C | R | C |
| Partner suspension/resumption after RED | A | R | C | C | C |
| Backup/DR exercise | I | A | C | R | I |
| Audit evidence and regulatory reporting | A | C | R | I | C |

## 3. Segregation of duties
- No person may initiate and solely approve their own material financial adjustment.
- Production code author cannot unilaterally approve and deploy a critical Game Engine/RNG/Ledger release.
- Partner key rotation and partner reactivation after security incident require independent review.
- Financial Controller does not receive unrestricted infrastructure or secret-manager access by default.
- AI is never an approver or accountable role.

## 4. Approval categories
- Routine pre-approved technical remediation: Policy Engine may authorize within strict limits.
- Partner limit change: Business + Technical + Financial review; contract update where applicable.
- Material adjustment/settlement: Financial Controller plus a second authorized approver.
- Core game/RNG/ledger release: Technical Owner plus independent test evidence and required compliance approval.
- RED incident recovery: Technical Owner plus Financial Controller for finance-impacting incidents; Compliance Owner when legal notification/jurisdiction is implicated.

## 5. Operational coverage
Define primary and secondary on-call, escalation vendor, response SLA, partner contact tree and holiday/weekend coverage. Three internal functions do not equal 24/7 staffing. External coverage must be tested through scheduled incident exercises.
