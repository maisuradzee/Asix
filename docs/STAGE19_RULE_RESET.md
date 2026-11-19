# Stage 19 — confirmed Entry Fee and prize-pool rule

Date: 2026-11-19

## Authoritative rule

The only distribution rule used by the current ASIX design is:

1. Sum every player's gross Entry Fee for the deal.
2. Calculate ASIX commission once on that gross total at **5%**.
3. Deduct the 5% commission.
4. Put **100% of the remaining post-commission amount** (equivalent to 95% of gross Entry Fee) into the player prize pool immediately at deal start.

No player-count-based starting allocation applies. No four-successful-cut progression applies. No four-deal progression applies. No 3% prize reserve applies.

## Example

| Item | Amount |
|---|---:|
| Gross Entry Fee | 6.00 ₾ |
| ASIX commission (5%) | 0.30 ₾ |
| Full player prize pool | 5.70 ₾ |
| Additional 3% reserve | 0.00 ₾ |

## Implementation consequences

- Live V154 `qcard_process_action` already computes `sales = gross Entry Fee - 5% commission` and sets both `initial_prize` and `max_table_pool` to that complete post-commission `sales` amount.
- The live commission setting was read-only verified as enabled, GEL, and 500 basis points (5%). The existing `card_purchase` trigger calculates and records the deal commission in `asix_platform_commission_ledger`; V157 leaves that commission settlement path and its wallet credit behavior unchanged. The additional `platform_allocation` row in `qcard_money_ledger` is a separate audit record only; its trigger is restricted to `entry_type = 'card_purchase'`, so the audit row cannot create a second wallet credit.
- The experimental Stage18 prize-growth patch is superseded and removed from the active Stage19 package.
- The Stage18 V156 growth-reserve accounting is superseded. V157 retains only the independent deal-level ledger-reference corrections and an audit-only platform-commission allocation row.
- Legacy server-state compatibility fields, if retained, are zeroed and have no financial effect. The dedicated `qcard_audit_growth_release` trigger/function is removed by V157.
- Historical `growth_release` or reserve ledger records, if present, remain immutable audit history. V157 does not delete or rewrite them.
- The local BOT practice mode uses virtual values and mirrors the 5% deduction / full 95% prize allocation. It does not credit any real ASIX wallet.

## Verification boundary

V157 is a prepared, guarded staging candidate only. It requires the enabled GEL 500-bps commission setting and no active deals; it has not been applied to the connected source project, compiled by PostgreSQL, or smoke-tested on an isolated restored database. The read-only source inspection confirmed the current V154 start-allocation path, commission configuration, growth-audit trigger identity, and function anchors. Production remains unchanged.