import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { validateAndSummarize, validatePublicSummary } from "./import-st8-runtime-evidence.mjs";

const ids = Array.from({ length: 12 }, (_, index) => "C" + String(index + 1).padStart(2, "0"));
const portalWorkflowPath = new URL("../.github/workflows/asix-development-portal-pages.yml", import.meta.url);
const legacySubmitterPath = new URL("./Submit-ST8-Runtime-Evidence.ps1", import.meta.url);
const portalWorkflow = readFileSync(portalWorkflowPath, "utf8");

function validReport() {
  return {
    schema: "asix-st8-v0.9.0-concurrency-report/v1",
    runId: "20261124083715999-a1b2c3d4",
    createdAt: "2026-11-24T08:37:15.999Z",
    target: { projectRef: "local-disposable-postgres17", database: "postgres", serverVersionNum: 170012 },
    workers: 20,
    total: 12,
    passed: 12,
    failed: 0,
    status: "PASS",
    results: ids.map(id => ({ id, title: "scenario " + id, status: "PASS", duration_ms: 12 }))
  };
}

test("accepts a complete local PostgreSQL 17 C01-C12 report and strips raw result payloads", () => {
  const raw = Buffer.from(JSON.stringify(validReport()));
  const summary = validateAndSummarize(validReport(), raw, "2026-11-24T09:00:00.000Z");
  assert.equal(summary.status, "PASS");
  assert.equal(summary.passed, 12);
  assert.equal(summary.scenarios.length, 12);
  assert.equal(summary.target, "local-disposable-postgres17");
  assert.equal("projectRef" in summary, false);
  assert.equal("database" in summary, false);
  assert.equal("results" in summary, false);
  assert.match(summary.sourceReportSha256, /^[a-f0-9]{64}$/);
});

test("rejects Production and primary staging targets", () => {
  for (const ref of ["kxcuvagipqiqisowtgys", "liiowoclsddlywabvmcg"]) {
    const report = validReport();
    report.target.projectRef = ref;
    assert.throws(() => validateAndSummarize(report, Buffer.from("{}")), /forbidden/);
  }
});

test("rejects remote or unknown database targets", () => {
  const report = validReport();
  report.target.projectRef = "some-other-project";
  assert.throws(() => validateAndSummarize(report, Buffer.from("{}")), /approved local/);
});

test("rejects incomplete, duplicate, or failed scenarios", () => {
  const missing = validReport();
  missing.results.pop();
  assert.throws(() => validateAndSummarize(missing, Buffer.from("{}")), /exactly 12/);

  const duplicate = validReport();
  duplicate.results[11].id = "C01";
  assert.throws(() => validateAndSummarize(duplicate, Buffer.from("{}")), /Duplicate/);

  const failed = validReport();
  failed.results[4].status = "FAIL";
  assert.throws(() => validateAndSummarize(failed, Buffer.from("{}")), /did not pass/);
});

test("rejects non-PostgreSQL-17 and worker counts outside 20..100", () => {
  const wrongVersion = validReport();
  wrongVersion.target.serverVersionNum = 160000;
  assert.throws(() => validateAndSummarize(wrongVersion, Buffer.from("{}")), /PostgreSQL 17/);

  const tooFewWorkers = validReport();
  tooFewWorkers.workers = 19;
  assert.throws(() => validateAndSummarize(tooFewWorkers, Buffer.from("{}")), /20..100 concurrent workers/);

  const tooManyWorkers = validReport();
  tooManyWorkers.workers = 101;
  assert.throws(() => validateAndSummarize(tooManyWorkers, Buffer.from("{}")), /20..100 concurrent workers/);
});

test("validates restored public summaries and strips unexpected fields", () => {
  const report = validReport();
  const generated = validateAndSummarize(report, Buffer.from(JSON.stringify(report)), "2026-11-24T09:00:00.000Z");
  generated.rawFixtureData = { userId: "must-not-survive" };
  const restored = validatePublicSummary(generated);
  assert.equal(restored.status, "PASS");
  assert.equal("rawFixtureData" in restored, false);
  assert.equal(restored.scenarios.length, 12);
});

test("rejects malformed persisted summaries", () => {
  const report = validReport();
  const generated = validateAndSummarize(report, Buffer.from(JSON.stringify(report)), "2026-11-24T09:00:00.000Z");
  generated.sourceReportSha256 = "invalid";
  assert.throws(() => validatePublicSummary(generated), /SHA-256/);
});

test("rejects persisted summaries below the C12 concurrency floor", () => {
  const report = validReport();
  const generated = validateAndSummarize(report, Buffer.from(JSON.stringify(report)), "2026-11-24T09:00:00.000Z");
  generated.workers = 19;
  assert.throws(() => validatePublicSummary(generated), /20..100 concurrent workers/);
});

test("portal accepts evidence only from a successful same-repository main-branch runtime workflow run", () => {
  assert.match(portalWorkflow, /workflows:\s*\["ASIX ST8 Autonomous Progression"\]/);
  assert.match(portalWorkflow, /workflow_run\.conclusion == 'success'/);
  assert.match(portalWorkflow, /workflow_run\.name == 'ASIX ST8 Autonomous Progression'/);
  assert.match(portalWorkflow, /workflow_run\.head_branch == 'main'/);
  assert.match(portalWorkflow, /workflow_run\.head_repository\.full_name == github\.repository/);
  assert.match(portalWorkflow, /run-id: \$\{\{ github\.event\.workflow_run\.id \}\}/);
  assert.match(portalWorkflow, /node tools\/import-st8-runtime-evidence\.mjs --validate-public-summary/);
});

test("portal exposes no caller-supplied runtime evidence import path", () => {
  assert.doesNotMatch(portalWorkflow, /summary_gzip_base64|SUMMARY_GZIP_BASE64/);
  assert.doesNotMatch(portalWorkflow, /Import and retain validated runtime evidence/);
  assert.doesNotMatch(portalWorkflow, /Submit-ST8-Runtime-Evidence\.ps1/);
  assert.doesNotMatch(portalWorkflow, /workflow_dispatch:\s*\n\s*inputs:/);
  assert.equal(existsSync(fileURLToPath(legacySubmitterPath)), false);
});
