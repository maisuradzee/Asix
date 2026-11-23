# ASIX × ST8 — Asix #2 v0.7.2 reconciliation idempotency report

**თარიღი:** 23 ნოემბერი 2026  
**გარემო:** `Asix #2` (`liiowoclsddlywabvmcg`) / `dragon.nika` / PostgreSQL 17.12  
**ვერსია:** v0.7.2 (database) + v0.7.1 (alert tooling)  
**Production:** ძველი ASIX (`kxcuvagipqiqisowtgys`) უცვლელია.

## მიზეზი და გამოსწორება

ადრე reconciliation run-ის უნიკალურობა ეფუძნებოდა მხოლოდ ST8 provider export-ის SHA-256-ს. იგივე export-ის ხელახლა დამუშავებისას, თუ ადგილობრივი მდგომარეობა შეიცვლებოდა — მაგალითად დაგვიანებული callback ან cancel tombstone enrichment — ახალი შედარება შეიძლება ძველ run-ად ჩათვლილიყო და დაიკარგებოდა ახალი შედეგი.

v0.7.2 ამატებს `comparison_snapshot_sha256` ველს. იგი ითვლის canonical SHA-256-ს provider transaction facts-ის, local transaction/cancel/ledger snapshot-ისა და accounting integrity snapshot-ის მიხედვით. არასტაბილური `exported_at`, pagination `pages` და `generated_at` timestamp-ები hash-ში არ შედის. შესაბამისად:
- იგივე provider export + იგივე local/accounting facts → duplicate run;
- იგივე provider export + შეცვლილი local/accounting facts → ახალი reconciliation run.

## staging ცვლილებები და ტესტები

- Applied migration: `20261123073723` — `st8_reconciliation_snapshot_idempotency`.
- ახალი სვეტი `comparison_snapshot_sha256`: `NOT NULL` და 64-ნიშნა lowercase SHA-256 check constraint.
- ძველი RPC signature წაიშალა; განახლებული RPC იღებს provider hash-სა და comparison snapshot hash-ს ცალ-ცალკე.
- Schema verifier: `ST8_RECONCILIATION_SNAPSHOT_IDEMPOTENCY_SCHEMA_PASSED`.
- Rollback-only SQL test: იგივე snapshot-ის duplicate suppression, იგივე provider export-ის შეცვლილი local snapshot-ით ახალი run, issue resolve/reopen და alert retry/delivery. Test transaction დასრულდა `ROLLBACK`-ით.
- შემდგომი read-only შემოწმება: sites=0, runs=0, issues=0, alerts=0, wallets=0, ledger=0, transactions=0.
- 14/14 private ST8 table კვლავ RLS + FORCE RLS-ითაა დაცული; private schema direct USAGE არ აქვს `anon`, `authenticated`, `service_role` როლებს. Edge Functions: 0. Health Advisor: 0 findings.

## ლოკალური ვალიდაცია
- Node.js 22.16 runtime: 64/64 PASS.
- Static security/architecture contracts: 128/128 PASS.
- TypeScript 5.8.3 strict compile: PASS.
- `npm run verify`: 22 PASS / 0 FAIL; 18 operational/test `.mjs` syntax checks PASS; 64/64 SHA-256 manifest files verified.
- Performance Advisor: no unindexed-FK findings; 11 unused-index INFO notices remain on empty staging and are to be re-evaluated after workload.
- Deno-native tests: SKIPPED — Deno CLI არ არის დაყენებული.

## დარჩენილი გარე ბლოკერები

ST8 Operator Code, Site ID, sandbox API/launcher origin, ST8 public key, ASIX public-key registration confirmation, ოფიციალური game/developer codes, approved jurisdiction values და Testing Tool credentials ჯერ არ არის მიღებული. ამიტომ `st8-gateway` არ არის deployed; live callback/Transactions Query API/official ST8 acceptance არ ჩატარებულა. Alert webhook და scheduler არ არის კონფიგურირებული; alert dispatcher ხელით იძახება.

**Production საზღვარი:** არცერთი Production migration, Edge Function deployment, secret ცვლილება, user mapping, wallet movement ან QCard ცვლილება არ შესრულებულა. `super-worker V25` უცვლელია.
