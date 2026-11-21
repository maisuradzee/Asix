# ASIX Partner Key Management and Rotation v1.0

## 1. Key custody
- Generate partner HMAC keys using a cryptographically secure random generator or approved KMS/HSM process.
- Keep key material in a secrets manager or KMS-backed secret store.
- Database stores only partner code, key ID, key version, secret reference, allowed scopes, created/active/revoked timestamps.
- Never write plaintext keys to Git, tickets, logs, chat, frontend configuration or ordinary database columns.
- Production and sandbox keys are separate and must not be interchangeable.

## 2. Key metadata
Each key record should include:
- immutable key_id;
- partner_id;
- protocol/signature version;
- secret_manager_reference;
- status: PENDING, ACTIVE, RETIRING, REVOKED;
- not_before and expires_at;
- created_by and approval reference;
- last_used_at;
- rotation reason and audit event reference.

## 3. Standard rotation
1. Verify the request with the partner's authorized technical contact.
2. Generate a new key in the approved secret manager.
3. Add the new key ID as PENDING.
4. Exchange the new key through an authenticated secure channel.
5. Activate the new key for a documented overlap period.
6. Accept both old and new key IDs during the overlap, with independent audit.
7. Confirm partner traffic is using the new key.
8. Mark old key RETIRING, then REVOKED.
9. Verify requests signed by the old key are rejected.
10. Record the rotation evidence and completion time.

Never overwrite key bytes under an existing key_id. A new key always gets a new identifier.

## 4. Emergency compromise
1. Open a security incident.
2. Verify partner identity using a pre-agreed out-of-band contact.
3. Revoke the compromised key immediately; isolate the partner if key scope cannot be isolated.
4. Preserve recent request, nonce, signature-validation and transaction evidence.
5. Rotate to a new key and validate sandbox/production handshake.
6. Review all transactions during the suspected compromise window.
7. Resume only after security review and appropriate business/technical approvals.

## 5. Replay protection
- Signed request includes timestamp, nonce and raw-body digest.
- Recommended initial timestamp tolerance: ±300 seconds, configurable per partner only with justification.
- Nonce storage must be durable, shared across all gateway instances and atomic on (partner_id, nonce).
- Nonce TTL must exceed the accepted timestamp window and any retry window specified in partner contract.
- A repeated nonce is rejected even when the signature is otherwise valid.
- Do not consume nonce for invalid signatures; do consume it after successful signature validation before business action.

## 6. Monitoring
Alert on:
- unknown/revoked key use;
- repeated invalid signatures;
- replay detection spikes;
- timestamp skew drift;
- use of retiring keys near overlap end;
- sudden key use from unexpected source ranges where partner contract includes IP allowlisting.

## 7. Dual control
Key creation, production activation and emergency partner reactivation require independent authorization. No one operator should be able to create, activate and approve a production key for the same partner alone.
