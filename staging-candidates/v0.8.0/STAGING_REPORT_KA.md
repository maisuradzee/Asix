# ASIX × ST8 — Asix #2 v0.8.0 staging ანგარიში

**თარიღი:** 23 ნოემბერი 2026  
**პაკეტი:** v0.8.0  
**Staging:** `liiowoclsddlywabvmcg` / `ACTIVE_HEALTHY` / PostgreSQL 17.12  
**Database schema:** v0.7.2; 9 migration-history ჩანაწერი  
**Gateway:** არ არის deployed.

## v0.8.0 ცვლილებები

აუდიტისას აღმოვაჩინე, რომ წინა ვერსიის deployment preflight staging project ref-ს ამოწმებდა, მაგრამ Gateway runtime ყველა მარშრუტზე იმავე შეზღუდვას არ აღასრულებდა. v0.8.0-ში დაემატა უნივერსალური `assertStagingProject()`, რომელიც სრულდება ყველა მოთხოვნაზე.

Gateway მუშაობს მხოლოდ მაშინ, როცა:
- `ST8_ENVIRONMENT=staging`;
- `ST8_STAGING_PROJECT_REF=liiowoclsddlywabvmcg`;
- `SUPABASE_URL=https://liiowoclsddlywabvmcg.supabase.co` ზუსტად ემთხვევა HTTPS origin-ს.

სხვა ref/host, nonstandard port, URL credentials/path/query/fragment იბლოკება `STAGING_ONLY` პასუხით, სანამ Auth, PostgREST ან ST8 network call შესრულდება.

Supabase Auth და service-role RPC fetch-ებს დაემატა `redirect: "error"` და `cache: "no-store"`. Callback-ის byte-identical retry იგივე request hash-ს ატარებს, შეცვლილი payload კი განსხვავებულ hash-ს.

## ვერიფიკაცია

- Runtime/Gateway: **74/74 PASS**.
- Static contracts: **134/134 PASS**.
- TypeScript strict compile: **PASS**.
- Operational/test script syntax: **18/18 PASS**.
- სრული `npm run verify`: **22 PASS / 0 FAIL**.
- SHA-256 package manifest: **69/69 ფაილი გადამოწმებული**.
- Deno tests: **SKIPPED** — Deno CLI ხელმისაწვდომი არ არის.

## Staging-ის ხელახალი read-only შემოწმება

- 14/14 private ST8 tables: RLS + FORCE RLS.
- ყველა 14 ST8 ცხრილი ცარიელია.
- `anon`, `authenticated`, `service_role`-ს `provider_internal` schema-ზე USAGE არ აქვს.
- Migration history კვლავ 9 ჩანაწერია; v0.8.0 migration არ გამოუყენებია.
- Edge Functions deployed: 0.

v0.8.0 არის source/test ცვლილება. არ შეცვლილა Supabase schema, secrets, Edge Function deployment ან რეალური ST8 callback state.

## დარჩენილი გარე ბლოკერები

ST8 Operator Code, Site ID, sandbox API/launcher URL, ST8 public key, ASIX key registration, ოფიციალური game/developer/jurisdiction codes, Testing Tool credentials, Deno runtime test, live callbacks, multi-session concurrency/load/reversal tests, legal/PSP/KYC/AML და responsible-gaming approvals.

**Production უცვლელია:** `kxcuvagipqiqisowtgys`, `super-worker V25`, QCard და არსებული ASIX wallet მონაცემები არ შეცვლილა. ეს არ არის ST8 certification ან Production readiness.
