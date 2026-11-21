# Existing ASIX Compatibility Map for B2B Provider Work

**Status:** repository-source review; design guidance only.  
**Source references:** current repository README, catalog-reconstructed V154 schema snapshot, generated database types and deployed `super-worker` V25 capture. This is not a live database audit performed by this document.

## 1. Executive decision

Keep the current ASIX multiplayer card-game product intact while adding a distinct B2B provider domain. The current tables and RPCs describe ASIX's own game product and its internal player/table economy. They are not a ready-made casino provider wallet or partner settlement ledger.

No B2B development should directly repurpose a table listed below without a separate compatibility review and migration tests.

## 2. Current objects and their intended boundary

| Existing object | Observed role | Provider integration decision |
|---|---|---|
| `asix_wallets` | ASIX internal user balance stored as `balance_tetri` | Do not use as operator player wallet |
| `asix_wallet_transactions` | Internal credit, table buy-in/cashout, adjustment and platform commission history; has unique idempotency key | Keep for the current product; provider transaction keys must be partner-scoped in a separate table |
| `asix_platform_commission_ledger` | Consumer-game platform commission allocation by deal/player | Do not use as casino-provider revenue-share settlement |
| `asix_platform_commission_settings` | Current ASIX consumer product's commission configuration | Do not assume this defines B2B pricing or partner commission |
| `qcard_money_ledger` | Card-table financial events such as buy-in, prize allocation, payout, refund and side-pot payout | Keep as game-economy event evidence; not the B2B double-entry ledger |
| `qcard_game_state` | Current table state snapshot keyed by room | Do not use as the B2B session registry |
| `qcard_actions` | Client/player actions, version checks and processing status | Do not mix partner API requests into game action queue |
| `qcard_deal_history` / players | Completed deal archive and end-state evidence | May inform a later round-result adapter, but not a substitute for provider session/round records |
| `qcard_rooms` / `qcard_seats` | Current multiplayer table configuration and seat membership | Keep consumer lobbies and provider session access separate |

## 3. Existing financial rule — explicit scope

The repository README records the current consumer game room rule:
- Gross Entry Fee = 100%.
- ASIX game commission = 5% of gross Entry Fee.
- Prize pool = 95%, fully funded at deal start.
- Example: 6.00 GEL gross → 0.30 GEL game commission → 5.70 GEL prize pool.

This rule is for the existing ASIX game product. It is not a default casino-provider revenue share, not an operator wallet deduction, and not a B2B settlement formula.

B2B commercial pricing must be defined separately by contract, for example:
- revenue share based on contractually defined provider GGR;
- fixed monthly/platform fee;
- hybrid fee;
- other approved structure.

The contract must define GGR, taxes, bonuses, chargebacks, voided rounds, rounding, currency conversion, reporting period, payment terms and dispute window.

## 4. Current worker boundary

The checked-in `supabase/functions/super-worker/index.ts` is the captured active V25 game-action worker. It validates authenticated game actions and calls current Q-CARD RPCs, including action submission/processing and heartbeat/recovery operations.

Decision:
- Do not extend this worker into the partner wallet gateway.
- Do not turn off its `verify_jwt=true` setting as a shortcut for server-to-server casino access.
- Add a distinct provider gateway and partner adapter family.
- Reuse common utilities only after extracting and testing them without changing V25 behavior.
- Keep provider routes isolated from browser user-session routes.

The captured worker currently includes wildcard CORS response headers. This document does not change that existing behavior. Before exposing any additional browser-facing provider console endpoints, configure explicit trusted origins and test authentication independently of CORS. Server-to-server partner APIs must rely on server authentication/signatures, not browser CORS.

## 5. Current schema caveats relevant to provider work

- The repository README identifies the V154 schema file as a reconstruction from database catalogs, not a verified clean restore.
- The migration inventory contains 128 applied migration names, but not the complete original SQL bodies.
- The V157 candidate is staging-only and not recorded as a production deployment.
- No clean restore and end-to-end game/financial smoke test are recorded as complete in the handover README.
- The current wallet transaction idempotency key is globally unique in that table. A partner system needs the composite scope `partner_id + idempotency_key`.
- The current game wallet stores GEL tetri. A multi-currency provider layer must carry currency code and a versioned currency exponent.

Therefore a provider schema migration must wait for a verified isolated restore and a mapping of current RLS, grants, triggers and SECURITY DEFINER RPC dependencies.

## 6. Safe coexistence target

```text
Existing ASIX product                         New B2B provider domain
---------------------                         ----------------------
Existing frontend                             Provider Gateway
super-worker V25                              Partner Registry/Auth
asix_wallets                                  Launch & Session Registry
asix_wallet_transactions                      Wallet Orchestrator
qcard_money_ledger                             Partner Wallet Adapters
qcard_game_state / qcard_actions               Provider Wallet Transactions
qcard_deal_history                             Provider Ledger & Reconciliation
Existing 5% / 95% room rule                    Contract-specific commercial model
```

The two domains may exchange a validated game result event through a narrow internal interface. They must not share player balances, idempotency namespaces or settlement semantics.

## 7. Required compatibility tests before any shared integration

1. Existing consumer game can still create room, join, buy in, play and cash out.
2. Existing commission and prize-pool invariants remain unchanged.
3. Existing game ledger reconciliation remains unchanged.
4. New partner transaction IDs cannot collide with consumer wallet idempotency keys.
5. Partner A cannot read or mutate Partner B's session or finance records.
6. Operator wallet outage does not corrupt a completed game result.
7. Control Center / AI outage does not block confirmed game state or financial recovery.
8. New database migrations apply only on clean isolated staging and pass rollback/forward-repair testing.

## 8. Approval gate

This map is an engineering boundary, not permission to change existing production functions or tables. Any later shared table, RPC, trigger, RLS policy or Edge Function change requires:
- before/after schema and function diff;
- test evidence against the restored V154 staging baseline;
- financial invariant checks;
- explicit rollback/forward-repair instructions;
- separate production deployment plan.
