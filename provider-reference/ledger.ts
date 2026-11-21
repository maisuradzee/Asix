/**
 * Pure provider-ledger journal builder.
 *
 * This module validates and hashes balanced journal drafts. It does not post
 * to PostgreSQL and does not replace the required durable append-only ledger.
 */

export type LedgerDirection = "DEBIT" | "CREDIT";

export interface LedgerLineInput {
  accountCode: string;
  direction: LedgerDirection;
  amountMinor: bigint;
  currency: string;
}

export interface LedgerJournalInput {
  journalId: string;
  partnerCode: string;
  sourceReference: string;
  currency: string;
  lines: LedgerLineInput[];
  reversalOfJournalId?: string;
}

export interface LedgerJournalDraft extends LedgerJournalInput {
  debitTotalMinor: bigint;
  creditTotalMinor: bigint;
  journalHash: string;
  balanced: true;
}

function validateInput(input: LedgerJournalInput): void {
  if (!input.journalId || !input.partnerCode || !input.sourceReference ||
      !/^[A-Z]{3}$/.test(input.currency)) {
    throw new Error("INVALID_JOURNAL_METADATA");
  }
  if (!Array.isArray(input.lines) || input.lines.length < 2 || input.lines.length > 500) {
    throw new Error("INVALID_JOURNAL_LINE_COUNT");
  }
  for (const line of input.lines) {
    if (!line.accountCode || line.accountCode.length > 100 ||
        !/^[A-Z]{3}$/.test(line.currency) ||
        line.currency !== input.currency ||
        line.amountMinor <= 0n ||
        (line.direction !== "DEBIT" && line.direction !== "CREDIT")) {
      throw new Error("INVALID_JOURNAL_LINE");
    }
  }
}

function stableLines(lines: LedgerLineInput[]): LedgerLineInput[] {
  return [...lines].sort((a, b) =>
    a.accountCode.localeCompare(b.accountCode) ||
    a.direction.localeCompare(b.direction) ||
    a.amountMinor.toString().localeCompare(b.amountMinor.toString())
  );
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", toArrayBuffer(new TextEncoder().encode(value)));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function buildLedgerJournal(input: LedgerJournalInput): Promise<LedgerJournalDraft> {
  validateInput(input);

  const debitTotalMinor = input.lines
    .filter((line) => line.direction === "DEBIT")
    .reduce((sum, line) => sum + line.amountMinor, 0n);
  const creditTotalMinor = input.lines
    .filter((line) => line.direction === "CREDIT")
    .reduce((sum, line) => sum + line.amountMinor, 0n);

  if (debitTotalMinor !== creditTotalMinor) {
    throw new Error("LEDGER_JOURNAL_UNBALANCED");
  }
  if (debitTotalMinor <= 0n) throw new Error("LEDGER_JOURNAL_EMPTY");

  const lines = stableLines(input.lines);
  const canonical = JSON.stringify({
    journalId: input.journalId,
    partnerCode: input.partnerCode,
    sourceReference: input.sourceReference,
    currency: input.currency,
    reversalOfJournalId: input.reversalOfJournalId ?? null,
    lines: lines.map((line) => ({
      accountCode: line.accountCode,
      direction: line.direction,
      amountMinor: line.amountMinor.toString(),
      currency: line.currency,
    })),
  });

  return {
    ...input,
    lines,
    debitTotalMinor,
    creditTotalMinor,
    journalHash: `sha256:${await sha256Hex(canonical)}`,
    balanced: true,
  };
}

/**
 * A reversal is a new journal with directions inverted. The original journal
 * remains unchanged and must remain in the audit history.
 */
export async function buildReversalJournal(
  original: LedgerJournalDraft,
  reversalJournalId: string,
  sourceReference: string,
): Promise<LedgerJournalDraft> {
  return await buildLedgerJournal({
    journalId: reversalJournalId,
    partnerCode: original.partnerCode,
    sourceReference,
    currency: original.currency,
    reversalOfJournalId: original.journalId,
    lines: original.lines.map((line) => ({
      ...line,
      direction: line.direction === "DEBIT" ? "CREDIT" : "DEBIT",
    })),
  });
}
