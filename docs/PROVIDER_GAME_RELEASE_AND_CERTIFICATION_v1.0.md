# ASIX Game Release and Certification Lifecycle v1.0

## 1. Release artifact identity

Every candidate game release must record:
- source commit;
- immutable build artifact digest;
- game version;
- ruleset version/hash;
- RNG implementation/config reference;
- math model/paytable version where applicable;
- supported platforms/locales/currencies;
- test suite version and results;
- certification evidence and jurisdiction scope;
- release approval and timestamp.

A label such as "V1.2" is not sufficient to prove which code executed a round; use content hashes.

## 2. Development stages

DRAFT → INTERNAL_TEST → MATHEMATICS_REVIEW → RNG_REVIEW → INDEPENDENT_TESTING → CERTIFIED_FOR_SCOPE → PARTNER_UAT → CANARY → ACTIVE → DEPRECATED / SUSPENDED.

The state is jurisdiction- and partner-scope aware. Certification for one market must not be assumed valid in another.

## 3. Game integrity controls

- Server-authoritative outcomes and state transitions.
- Versioned rules, deterministic replay where permitted and secure RNG evidence.
- Strict separation of test RNG and production RNG.
- No production test accounts that can affect real financial reports unless isolated by explicit account/jurisdiction tags and contract rules.
- Completed round records are immutable.
- Admin/support tools cannot alter results.
- A game build cannot be enabled for a partner unless its certification scope includes that partner's territory and distribution model.

## 4. Change classification

**Class A — cosmetic/client-only:** no change to math, RNG, payout, wallet or rules; standard QA and backward compatibility.

**Class B — service/API/config:** protocol, session, rendering or non-financial infrastructure; integration and security tests, partner compatibility approval as needed.

**Class C — game logic/math/RNG/payout/ledger:** enhanced tests, independent review and any required recertification. Production release requires explicit approval and verified rollback/recovery plan.

Any change with uncertain financial or game-integrity impact is Class C.

## 5. Mandatory verification

- game rule unit tests and edge-case coverage;
- probability/RTP/paytable validation if applicable;
- RNG implementation and statistical/independent evaluation as required;
- adversarial client-action validation;
- replay/snapshot recovery tests;
- concurrency and duplicate action tests;
- wallet debit/win/refund integration tests;
- load, soak and failure-mode tests;
- partner UAT;
- evidence archive and signed release checklist.

## 6. Canary and rollback

- Stage rollout by environment, partner, territory and traffic cohort.
- Observe game business metrics and financial correctness, not only server health.
- Auto rollback only to a previously approved compatible artifact.
- Never roll back by rewriting completed round results or deleting transactions.
- Database migrations require a separate compatibility and forward-repair plan.
