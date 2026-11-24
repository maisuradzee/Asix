#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const EXPECTED_IDS = Array.from({ length: 12 }, (_, index) => "C" + String(index + 1).padStart(2, "0"));
const EXPECTED_SCHEMA = "asix-st8-v0.9.0-concurrency-report/v1";
const ALLOWED_LOCAL_REF = "local-disposable-postgres17";
const PROD_REF = "kxcuvagipqiqisowtgys";
const PRIMARY_STAGING_REF = "liiowoclsddlywabvmcg";

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

export function validateAndSummarize(report, rawBytes, importedAt = new Date().toISOString()) {
  requireCondition(report && typeof report === "object" && !Array.isArray(report), "Evidence must be a JSON object.");
  requireCondition(report.schema === EXPECTED_SCHEMA, "Unsupported runner report schema.");
  requireCondition(typeof report.runId === "string" && /^\d{17}-[a-f0-9]{8}$/.test(report.runId), "Invalid runner runId.");
  requireCondition(typeof report.createdAt === "string" && Number.isFinite(Date.parse(report.createdAt)), "Invalid report createdAt timestamp.");
  requireCondition(report.target && typeof report.target === "object", "Missing database target metadata.");

  const projectRef = report.target.projectRef;
  requireCondition(projectRef !== PROD_REF && projectRef !== PRIMARY_STAGING_REF, "Production and primary staging evidence are forbidden.");
  requireCondition(projectRef === ALLOWED_LOCAL_REF, "Only the approved local PostgreSQL 17.12 runner target can be published.");
  requireCondition(report.target.database === "postgres", "Unexpected local test database name.");

  const serverVersionNum = Number(report.target.serverVersionNum);
  requireCondition(Number.isInteger(serverVersionNum) && serverVersionNum >= 170000 && serverVersionNum < 180000,
    "Runtime evidence must come from PostgreSQL 17.x.");

  const workers = Number(report.workers);
  requireCondition(Number.isInteger(workers) && workers >= 2 && workers <= 100, "Invalid worker count.");
  requireCondition(report.total === 12 && report.passed === 12 && report.failed === 0 && report.status === "PASS",
    "Only a complete 12/12 PASS report can be imported as a passed runtime run.");
  requireCondition(Array.isArray(report.results) && report.results.length === 12, "Expected exactly 12 scenario results.");

  const resultById = new Map();
  for (const result of report.results) {
    requireCondition(result && typeof result === "object", "Malformed scenario result.");
    requireCondition(typeof result.id === "string" && EXPECTED_IDS.includes(result.id), "Unknown scenario ID.");
    requireCondition(!resultById.has(result.id), "Duplicate scenario ID: " + result.id);
    requireCondition(result.status === "PASS", "Scenario did not pass: " + result.id);
    requireCondition(typeof result.title === "string" && result.title.length > 0 && result.title.length <= 160,
      "Invalid scenario title: " + result.id);
    requireCondition(Number.isFinite(Number(result.duration_ms)) && Number(result.duration_ms) >= 0,
      "Invalid scenario duration: " + result.id);
    resultById.set(result.id, result);
  }
  requireCondition(EXPECTED_IDS.every(id => resultById.has(id)), "One or more C01–C12 scenarios are missing.");

  const raw = Buffer.isBuffer(rawBytes) ? rawBytes : Buffer.from(rawBytes);
  requireCondition(raw.length > 0 && raw.length <= 1024 * 1024, "Raw report must be between 1 byte and 1 MiB.");
  requireCondition(Number.isFinite(Date.parse(importedAt)), "Invalid import timestamp.");

  return {
    schema: "asix-st8-v0.9.0-public-runtime-summary/v1",
    evidenceType: "locally-generated-runner-report",
    validationLevel: "schema-and-invariants-only",
    runId: report.runId,
    testedAt: report.createdAt,
    importedAt,
    target: "local-disposable-postgres17",
    postgresMajor: 17,
    workers,
    total: 12,
    passed: 12,
    failed: 0,
    status: "PASS",
    scenarios: EXPECTED_IDS.map(id => ({
      id,
      title: resultById.get(id).title,
      status: "PASS",
      durationMs: Number(resultById.get(id).duration_ms)
    })),
    sourceReportSha256: crypto.createHash("sha256").update(raw).digest("hex")
  };
}

async function main() {
  const inputPath = process.argv[2];
  const outputPath = process.argv[3] || ".github/asix-st8-runtime-evidence.json";
  if (!inputPath || inputPath === "--help" || inputPath === "-h") {
    process.stdout.write("Usage: node tools/import-st8-runtime-evidence.mjs <runner-report.json> [output.json]\n");
    process.exit(inputPath ? 0 : 2);
  }

  const raw = await fs.readFile(inputPath);
  let report;
  try {
    report = JSON.parse(raw.toString("utf8"));
  } catch {
    throw new Error("Input is not valid UTF-8 JSON.");
  }
  const summary = validateAndSummarize(report, raw);
  await fs.mkdir(path.dirname(path.resolve(outputPath)), { recursive: true });
  await fs.writeFile(outputPath, JSON.stringify(summary, null, 2) + "\n", { mode: 0o644 });
  process.stdout.write("ST8 runtime evidence accepted: C01–C12 12/12 PASS (structural validation only).\n");
  process.stdout.write("Sanitized summary: " + path.resolve(outputPath) + "\n");
  process.stdout.write("Raw report SHA-256: " + summary.sourceReportSha256 + "\n");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => {
    process.stderr.write("Evidence import rejected: " + error.message + "\n");
    process.exitCode = 1;
  });
}
