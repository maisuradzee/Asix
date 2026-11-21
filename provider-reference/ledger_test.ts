import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildLedgerJournal, buildReversalJournal } from "./ledger.ts";

const balanced = {
  journalId: "journal-001",
  partnerCode: "operator-a",
  sourceReference: "wallet-tx-001",
  currency: "GEL",
  lines: [
    { accountCode: "OPERATOR_CLEARING", direction: "DEBIT" as const, amountMinor: 1_250n, currency: "GEL" },
    { accountCode: "PROVIDER_PAYABLE", direction: "CREDIT" as const, amountMinor: 1_000n, currency: "GEL" },
    { accountCode: "PROVIDER_REVENUE", direction: "CREDIT" as const, amountMinor: 250n, currency: "GEL" },
  ],
};

Deno.test("balanced multi-line journal is accepted with exact BigInt totals", async () => {
  const journal = await buildLedgerJournal(balanced);
  assertEquals(journal.debitTotalMinor, 1_250n);
  assertEquals(journal.creditTotalMinor, 1_250n);
  assertEquals(journal.balanced, true);
  assertEquals(journal.journalHash.startsWith("sha256:"), true);
});

Deno.test("unbalanced journal is rejected", async () => {
  await assertRejects(
    () => buildLedgerJournal({
      ...balanced,
      lines: balanced.lines.slice(0, 2),
    }),
    Error,
    "LEDGER_JOURNAL_UNBALANCED",
  );
});

Deno.test("mixed-currency journal is rejected", async () => {
  await assertRejects(
    () => buildLedgerJournal({
      ...balanced,
      lines: [
        balanced.lines[0],
        { ...balanced.lines[1], currency: "USD" },
      ],
    }),
    Error,
    "INVALID_JOURNAL_LINE",
  );
});

Deno.test("reversal creates a new journal with all directions inverted", async () => {
  const original = await buildLedgerJournal(balanced);
  const reversal = await buildReversalJournal(original, "journal-002", "reversal-of-wallet-tx-001");
  assertEquals(reversal.reversalOfJournalId, original.journalId);
  assertEquals(reversal.debitTotalMinor, original.creditTotalMinor);
  assertEquals(reversal.creditTotalMinor, original.debitTotalMinor);
  assertEquals(reversal.lines.some((line) => line.direction === "DEBIT"), true);
  assertEquals(reversal.journalHash === original.journalHash, false);
});
