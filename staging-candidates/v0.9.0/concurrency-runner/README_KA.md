# ASIX × ST8 v0.9.0 — მრავალსესიური concurrency runner

ეს დამოუკიდებელი Node.js runner თითოეული DB მოქმედებისთვის PostgreSQL pool-ის ცალკე connection-ს იყენებს. პარალელური callback-ები სრულდება სხვადასხვა DB session-ზე.

## უსაფრთხოების ზღვარი

- გაუშვით მხოლოდ disposable Supabase development branch-ზე ან ადგილობრივ disposable PostgreSQL 17-ზე.
- **აკრძალულია** Production `kxcuvagipqiqisowtgys` და ძირითადი Asix #2 staging `liiowoclsddlywabvmcg`.
- Runner უარს ამბობს ამ ორი project ref-ის გამოყენებაზე.
- საჭიროა explicit acknowledgement `ST8_TEST_ALLOW_DISPOSABLE_DB`-ში და პირდაპირი DB hostname `db.<ref>.supabase.co`.
- ყველა fixture სინთეზურია. Test users, wallet ledger და audit rows რჩება disposable branch-ში.
- არასოდეს გამოიყენოთ რეალური მომხმარებელი, ST8 live credentials ან რეალური თანხა.

## ინსტალაცია

```bash
npm install --ignore-scripts
```

`pg` dependency pin-ულია `8.16.3`-ზე. Node.js მინიმუმ `22.16.0`.

## გაშვება — PowerShell

```powershell
$env:ST8_TEST_PROJECT_REF = "<DISPOSABLE_BRANCH_PROJECT_REF>"
$env:ST8_TEST_DATABASE_URL = "postgresql://postgres:<BRANCH_DB_PASSWORD>@db.<DISPOSABLE_BRANCH_PROJECT_REF>.supabase.co:5432/postgres"
$env:ST8_TEST_ALLOW_DISPOSABLE_DB = "YES_I_UNDERSTAND_THIS_IS_A_DISPOSABLE_ST8_TEST_DATABASE"
$env:ST8_TEST_WORKERS = "20"
npm run test:concurrency
```

Connection string შეინახეთ მხოლოდ environment variable/secret manager-ში. TLS certificate verification ჩართულია ნაგულისხმევად. დისტანციურ ბაზასთან `ST8_TEST_SSL=disable` არ გამოიყენოთ.

## რას ამოწმებს runner

- PostgreSQL 17.x და ST8 callback/funding RPC signatures.
- 14/14 ST8 ცხრილის RLS + FORCE RLS, ცარიელი მონაცემები და private schema grants.
- Synthetic auth user, test site/game, player mapping და wallet session.
- C01–C12 დამოუკიდებელი pooled connections-ით.
- Balance/debt/ledger/idempotency invariants და თითოეული ტესტის JSON evidence.

Ledger და audit append-only-ია, ამიტომ fixture rows ავტომატურად არ იშლება. Report-ის ექსპორტის შემდეგ წაშალეთ მთლიანად disposable branch.

## შეზღუდვები

ეს runner ამოწმებს მხოლოდ DB-level RPC concurrency-ს. ის არ ამოწმებს ST8-ის რეალურ signature verification-ს, HTTP Gateway-ს, provider callbacks-ს ან პარტნიორის Testing Tool-ს. PASS არ ნიშნავს ST8 certification-ს ან Production readiness-ს.
