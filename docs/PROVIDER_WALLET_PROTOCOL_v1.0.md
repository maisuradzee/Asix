# ASIX Provider Wallet Protocol v1.0

**Status:** normative engineering proposal. No production wallet behavior is changed by this document.

## 1. Ownership boundary

For B2B provider integrations, the casino/operator remains the owner of the player's account and wallet. ASIX requests wallet debits and credits through the operator's wallet API. ASIX maintains an independent provider-side record of transactions and contractual settlement obligations.

Do not merge these domains:
- Existing ASIX consumer-game wallet: `asix_wallets`, `asix_wallet_transactions`, Q-CARD game balances and related game ledgers.
- B2B provider accounting: partner-scoped wallet requests, provider ledger journals, reconciliation and commercial settlement.

The existing GEL `tetri` unit can be mapped to provider GEL minor units only under an explicit currency conversion rule. Never reuse consumer-game balances as casino player balances.

## 2. Transaction lifecycle

```text
CREATED
   |
   v
DISPATCHING
   |--------------------|
   v                    v
CONFIRMED             DECLINED
   |
   v
RECONCILED

DISPATCHING -- timeout / lost response --> UNKNOWN
UNKNOWN --> STATUS_QUERY --> CONFIRMED / DECLINED / PENDING / EXCEPTION
```

Rules:
1. Insert the transaction row and reserve the idempotency key before network dispatch.
2. Record request hash, partner, operation, player/session/round references, amount, currency and protocol version.
3. Dispatch only after local validation and partner limit checks.
4. If a definitive response is received, persist it with partner reference and response hash.
5. If the result is uncertain, persist UNKNOWN and schedule a status query.
6. Never send a second debit/credit merely because the first HTTP response was lost.
7. Reconciliation can resolve late partner reports but cannot silently overwrite a transaction.
8. Terminal states are immutable; any correction is a new, linked compensating transaction.

## 3. Bet acceptance rule

A bet is accepted into the game only after the operator confirms the debit according to the partner's protocol.

If debit response is UNKNOWN:
- Freeze that action's progression.
- Do not deal/continue a game action that assumes the bet has been collected.
- Query the original partner transaction reference or idempotency key.
- If partner confirms debit, continue exactly once.
- If partner declines, reject the action and restore the pre-action state.
- If it remains unresolved beyond the configured SLA, move to EXCEPTION and route to human investigation.

The system must not invent a successful debit or treat a timeout as a failed debit.

## 4. Win credit rule

The game result and the wallet credit are separate facts:
- A completed game result is immutable once committed under the game rules.
- A failed or uncertain win credit does not permit changing the winner or result.
- Keep the win transaction pending/unknown, retry only under the same idempotency contract, and escalate unresolved payouts.
- Record a separate payout obligation and resolution history.

## 5. Refund and rollback

A refund must include:
- a reference to the original debit;
- a unique new transaction ID and idempotency key;
- amount and currency;
- reason code;
- originating round/session;
- whether it is an automatic pre-approved refund or a human-approved exception.

Never delete the original transaction. A rollback is not a database undo; it is a traceable compensating financial action.

## 6. Amount and currency precision

- Store money as signed integer minor units, with positive transaction amounts and an explicit debit/credit direction.
- Persist currency code and resolved exponent with every financial event.
- Reject fractional minor units.
- Never use JavaScript floating-point arithmetic for money.
- Currency exponent must come from a versioned ISO 4217 registry or an agreed partner contract.
- For GEL, 100 tetri = 1 GEL. This does not imply every currency has exponent 2.

## 7. Provider ledger

The provider ledger is not the player's wallet. It records provider accounting events using a contract-specific chart of accounts.

Required invariants:
- Every posted journal balances (total debits = total credits) per currency.
- Journals are immutable after posting.
- Ledger entries cannot be updated or deleted by application roles.
- Corrections are reversals/adjustments linked to the original journal.
- All lines retain partner, game, session, round, transaction, currency, timestamp and configuration/version context.
- No journal may combine currencies.
- Settlement is derived from reconciled partner transactions and the signed commercial agreement.

The chart of accounts and debit/credit mappings must be approved by the company's accountant based on the actual revenue-share / fixed-fee / hybrid contract. Do not treat the player's gross bet as ASIX cash revenue by default.

## 8. Reconciliation

Run real-time exception reconciliation and scheduled partner statement reconciliation.

Compare at minimum:
- ASIX transaction ID / idempotency key;
- partner transaction reference;
- player/session/round reference;
- operation;
- amount and currency;
- outcome/status;
- event and settlement timestamps.

Exception classes:
- MATCHED;
- PARTNER_RECORD_DELAYED;
- ASIX_RECORD_DELAYED;
- DUPLICATE_PARTNER_EFFECT;
- DUPLICATE_ASIX_REQUEST;
- AMOUNT_MISMATCH;
- CURRENCY_MISMATCH;
- STATUS_MISMATCH;
- MISSING_PARTNER_REFERENCE;
- UNKNOWN_UNRESOLVED;
- CONTRACT_SETTLEMENT_MISMATCH.

Unmatched items remain visible, assigned and time-bounded. Never force totals to match by rewriting historical data.

## 9. Outbox and delivery reliability

Use a transactional outbox:
- Create wallet transaction and outbox event in the same database transaction.
- Worker claims event with a lease and bounded attempt counter.
- External request uses stable idempotency key.
- Persist partner response and outbox completion atomically where possible.
- Lease expiry permits safe worker recovery, not a new financial identity.
- Dead-letter only after automatic status-resolution attempts; unresolved financial events remain visible to the exception queue.

## 10. Human approval thresholds

Amounts and thresholds must be configured per partner and contract, not hard-coded globally.

Require dual approval for:
- manual financial adjustment above the contract threshold;
- settlement release above materiality threshold;
- reopening a partner after a RED financial-integrity incident;
- changing max bet, max payout or exposure limits.

AI may classify and explain anomalies but cannot approve, settle, rewrite or suppress financial records.

## 11. Required fault-injection scenarios

- Partner accepts debit but response is dropped.
- Partner declines debit but response is malformed.
- Partner returns PENDING for longer than SLA.
- Same request is delivered concurrently by two workers.
- Worker crashes after send but before local response persistence.
- Database connection is lost while a partner response arrives.
- Partner statement is delayed and arrives after reconciliation close.
- Partner sends duplicate statement line.
- Settlement total disagrees with transaction-level records.

Expected behavior: no duplicate financial effect, no lost traceability, no fabricated result, and clear exception state.
