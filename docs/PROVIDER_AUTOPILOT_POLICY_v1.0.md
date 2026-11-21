# ASIX Provider Autopilot Policy v1.0

## 1. Operating principle

Observe → Detect → Diagnose → Contain → Recover → Verify → Record.

Every action must have a policy ID, target partner/service, reason, precondition, bounded scope, timeout, expected postcondition and audit record. AI may recommend or explain. A deterministic Policy Engine decides whether the action is permitted.

## 2. Health state is scoped

Maintain independent health state for:
- each partner;
- each partner adapter;
- each game;
- each regional runtime;
- financial processing;
- reconciliation;
- control-plane services.

A partner-specific RED must not automatically disable healthy partners.

## 3. Allowed automatic actions

| Trigger | Permitted action | Verification |
|---|---|---|
| Stateless worker crash | Restart one worker | Readiness + synthetic non-financial request |
| Partner API sustained errors | Open that partner circuit breaker | Error rate falls; other partners unaffected |
| Queue lag | Scale workers within pre-approved ceiling | Queue age and throughput normalize |
| Bad deployment | Roll back to last approved artifact | Version, health and business probes pass |
| Stale read-only status query | Retry with bounded exponential backoff | Query completes; no financial side effect |
| Low-risk alert noise | Deduplicate/route notification | No suppression of critical financial/security alerts |

## 4. Human approval required

- Change partner bet, win or exposure limits.
- Approve manual refund/adjustment outside a pre-approved rule.
- Release material settlement.
- Resume partner after RED financial-integrity incident.
- Change key ownership or production trust configuration outside an approved rotation runbook.
- Change legal jurisdiction, product availability or commercial terms.

## 5. Prohibited autonomous actions

- Change a completed game outcome.
- Delete or update a posted financial journal.
- Invent a partner wallet response.
- Retry uncertain debit/credit with a new idempotency key.
- Increase financial limits.
- Disable audit or security controls.
- Deploy untested game math, RNG, wallet or ledger logic.
- Close an incident while transaction state remains UNKNOWN or reconciliation remains unresolved.

## 6. Incident severity and response

**GREEN:** all critical business and technical probes pass.  
**YELLOW:** degraded component; safe automation runs and human is notified if it persists beyond its policy SLA.  
**RED:** financial integrity, game integrity, security compromise or broad service failure. Stop unsafe new activity in the affected scope, isolate, preserve evidence and escalate.

## 7. Notification routing

- Financial UNKNOWN / mismatch → Financial Controller + on-call technical owner.
- Partner API outage → Partner Operations + managed SRE/NOC.
- Suspected credential compromise → Security on-call immediately.
- Game-state integrity incident → Technical Platform Owner; affected game/partner isolated.
- Legal/compliance trigger → Compliance Owner; no AI closure.

Notifications must include correlation IDs, partner, severity, first-seen time, business impact, safe next step and required decision. Do not include secrets or unnecessary player data.
