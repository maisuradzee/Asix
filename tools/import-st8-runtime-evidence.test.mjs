import test from "node:test";
import assert from "node:assert/strict";
import { validateAndSummarize, validatePublicSummary } from "./import-st8-runtime-evidence.mjs";

const ids = Array.from({ length: 12 }, (_, index) => "C" + String(index + 1).padStart(2, "0"));
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

test("rejects non-PostgreSQL-17 and worker counts outside 2..100", () => {
  const wrongVersion = validReport();
  wrongVersion.target.serverVersionNum = 160000;
  assert.throws(() => validateAndSummarize(wrongVersion, Buffer.from("{}")), /PostgreSQL 17/);

  const wrongWorkers = validReport();
  wrongWorkers.workers = 101;
  assert.throws(() => validateAndSummarize(wrongWorkers, Buffer.from("{}")), /worker count/);
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
