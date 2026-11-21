# ASIX Provider Privacy and Data Governance v1.0

## 1. Data minimization
ASIX should receive only the data required to launch a game, operate the session, process game-wallet actions, prevent abuse and settle contractual obligations.

Prefer:
- pseudonymous operator player reference;
- operator session reference;
- partner code;
- game, round and transaction references;
- currency and jurisdiction;
- limited risk/technical signals required by contract.

Do not request or store full player name, email, phone, address, payment card details or KYC documents unless a separately reviewed legal/business requirement makes ASIX responsible for that data.

## 2. Data classification

| Class | Examples | Handling |
|---|---|---|
| Public | Game catalogue, public API docs | Publish approved versions only |
| Internal | Architecture, runbooks, service metrics | Staff access by role |
| Confidential | Partner contracts, limits, reports | Partner-scoped and need-to-know |
| Restricted | Signing secrets, access tokens, security evidence | Secrets manager/KMS; never in logs or frontend |
| Financial/audit | Wallet references, ledger journals, settlement evidence | Immutable, access-logged, legally retained |
| Pseudonymous player data | Player/session references, round history | Minimize, scope and retain per legal/contract needs |

## 3. Access model
- Partner can access only its own sessions and reports, if partner portal access is provided.
- Financial Controller accesses settlements and reconciliation, not secrets or unrelated player data.
- Technical operators access infrastructure metadata and only the minimum transaction context required for incidents.
- Support staff see masked player/session references by default.
- Break-glass access is time-limited, justified and audited.

## 4. Retention and deletion
Retention periods must be set by jurisdiction, license, contract, accounting law and dispute limitation periods. Do not apply a single global retention period without legal review.

Separate:
- legally retained financial/audit evidence;
- operational logs with shorter retention;
- temporary launch tokens/nonces;
- security incident evidence;
- analytics aggregates.

Expired launch tokens and replay nonces should be removed or archived according to a bounded retention job. Financial and game evidence must not be deleted where law or contract requires preservation.

## 5. Data subject and partner requests
- Route requests through a verified partner/legal contact.
- Identify ASIX's role (controller, processor or independent controller) by data category and contract.
- Verify identity/authority before disclosure or correction.
- Correct operational metadata through auditable correction events; never rewrite financial history or completed game results.
- Record legal basis, request, scope, action and response.

## 6. Cross-border transfer
Before activating a jurisdiction or region:
- confirm applicable data protection and localization requirements;
- document transfer mechanism and subprocessors;
- agree breach notification and audit rights;
- map hosting, backup and support access locations.

## 7. Logging rules
Never log:
- partner signing secrets or private keys;
- launch tokens or Authorization headers;
- service-role credentials;
- full request bodies where they contain sensitive values;
- unnecessary personal data.

Use correlation IDs, request hashes, pseudonymous references and redacted partner response metadata.
