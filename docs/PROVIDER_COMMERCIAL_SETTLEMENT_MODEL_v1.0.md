# ASIX B2B Commercial and Settlement Model v1.0

**Purpose:** define the contract and data requirements for provider revenue reporting. This document does not set ASIX's final price or any partner-specific revenue share.

## 1. Separate consumer and B2B economics

Current ASIX consumer-game rule: 5% commission from gross table Entry Fee and 95% prize pool. It remains scoped to the current product.

B2B Provider economics are contractual and may use:
- revenue share;
- fixed monthly/platform fee;
- hybrid fee;
- per-round/per-session fee where contractually agreed.

Do not apply the consumer 5% fee to casino GGR or operator wallet transactions.

## 2. Contractual GGR definition

A common starting concept is:
- eligible stakes/bets;
- less eligible player winnings;
- adjusted for explicitly defined voided rounds, refunds, bonuses, jackpots, progressive contributions, chargebacks and taxes.

There is no universal definition that can safely be assumed. The signed agreement must define each component, timing, reporting source and precedence for disputes.

The settlement calculation engine must be versioned by contract and effective period.

## 3. Contract fields

Every partner agreement model must store:
- contract_id and version;
- partner_id;
- fee_model;
- revenue_share_rate_bps or fixed fee amount;
- fee currency;
- GGR definition version;
- permitted deductions;
- taxes and withholding treatment;
- FX source and conversion timestamp policy;
- rounding rule;
- reporting period;
- settlement date and payment terms;
- minimum guarantees or caps where applicable;
- dispute window and evidence requirements;
- effective_from/effective_until.

Do not hard-code a universal rate.

## 4. Settlement pipeline

1. Close reporting period.
2. Freeze an immutable input snapshot of eligible partner transactions.
3. Resolve transaction statuses; UNKNOWN items are exceptions.
4. Match partner statements to ASIX provider transaction records.
5. Apply the signed contract version valid for the period.
6. Calculate GGR and fee components using exact arithmetic.
7. Produce line-item explanation and reconciliation report.
8. Financial Controller reviews material discrepancies and contractual exceptions.
9. Authorized approver releases the settlement.
10. Create invoice/receivable/payable records and archive evidence.

Never calculate final settlement solely from a dashboard total without traceable source items.

## 5. Settlement controls

- One settlement run per partner + contract version + period unless a documented rerun is created.
- Reruns have new IDs and link to superseded drafts; posted/approved runs are not overwritten.
- No settlement release while high-severity UNKNOWN or unexplained discrepancy remains.
- Dual approval above contract-defined materiality threshold.
- Settlement bank/payment execution remains within the company's authorized banking/payment process.
- Statements and invoices are retained under legal/accounting requirements.

## 6. Financial reporting

Partner statement should include:
- opening/closing period;
- currency;
- eligible stakes and wins;
- deductions and adjustments by category;
- net GGR under the contracted definition;
- provider fee/rate;
- tax/withholding where applicable;
- prior-period adjustments;
- amount payable/receivable;
- transaction count and exception list;
- contract version and calculation run ID.

## 7. Dispute workflow

- Register dispute with partner, period, amount and reason.
- Freeze only disputed amount/line if contract permits; do not block undisputed settlement without cause.
- Attach transaction-level evidence and partner references.
- Assign financial owner and response deadline.
- Corrections become linked adjustment entries in a new run.
- Close only after evidence and approval are recorded.
