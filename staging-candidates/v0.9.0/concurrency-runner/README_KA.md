# ASIX × ST8 v0.9.0 — მრავალსესიური concurrency runner

ეს დამოუკიდებელი Node.js runner თითოეული DB მოქმედებისთვის PostgreSQL pool-ის ცალკე connection-ს იყენებს. პარალელური callback-ები სრულდება სხვადასხვა DB session-ზე.

## უსაფრთხოების ზღვარი
- გაუშვით მხოლოდ ცალკე disposable Supabase development branch-ზე ან ადგილობრივ disposable PostgreSQL 17.12-ზე.
- **აკრძალულია** Production `kxcuvagipqiqisowtgys` და ძირითადი Asix #2 staging `liiowoclsddlywabvmcg`.
- Runner უარს ამბობს ამ ორი project ref-ის გამოყენებაზე.
- საჭიროა explicit acknowledgement `ST8_TEST_ALLOW_DISPOSABLE_DB`-ში და პირდაპირი DB hostname `db.<ref>.supabase.co` ან localhost.
- ყველა fixture სინთეზურია. არ გამოიყენოთ რეალური მოთამაშე, ST8 live credentials ან რეალური თანხა.

## წინაპირობები
- Windows PowerShell 7 (რეკომენდებულია), Docker Desktop გაშვებული;
- Node.js 22.16+ და npm;
- v0.8.0-ის ზუსტად გადამოწმებული archive: `ASIX_ST8_Integration_Candidate_v0.8.0_Asix2_Staging.zip`.

## ერთსაფეხურიანი ლოკალური გაშვება — PowerShell
გადმოწერეთ v0.8.0 archive და შეინახეთ მისამართი. შემდეგ გაუშვით repository root-იდან:

```powershell
pwsh -File .\staging-candidates\v0.9.0\concurrency-runner\Start-Local-Postgres17-Test.ps1 -MigrationZipPath "C:\path\to\ASIX_ST8_Integration_Candidate_v0.8.0_Asix2_Staging.zip" -Workers 20
```

Launcher:
1. ქმნის localhost-ზე მიბმულ disposable PostgreSQL 17.12 Docker container-ს (პორტი 55432);
2. ამზადებს მინიმალურ Supabase Auth-compatible local test schema-ს;
3. archive-იდან იღებს და თანმიმდევრობით იყენებს ზუსტად 9 ST8 migration-ს;
4. აყენებს pin-ულ `pg@8.16.3` dependency-ს;
5. უშვებს C01–C12-ს 20 დამოუკიდებელი connection-ით;
6. წარმატებისას შლის disposable container-ს; შეცდომისას ტოვებს დიაგნოსტიკისთვის.

`-KeepContainer` დაამატეთ, თუ წარმატებული ტესტის შემდეგაც გსურთ DB container-ის შენარჩუნება. JSON evidence ინახება `concurrency-runner/concurrency-results/`-ში. ეს ლოკალური ტესტი არ ქმნის Supabase branch-ს და არ იწვევს Supabase საათობრივ ხარჯს.

## ხელით გაშვება Supabase disposable branch-ზე
```powershell
$env:ST8_TEST_PROJECT_REF = "<DISPOSABLE_BRANCH_PROJECT_REF>"
$env:ST8_TEST_DATABASE_URL = "postgresql://postgres:<BRANCH_DB_PASSWORD>@db.<DISPOSABLE_BRANCH_PROJECT_REF>.supabase.co:5432/postgres"
$env:ST8_TEST_ALLOW_DISPOSABLE_DB = "YES_I_UNDERSTAND_THIS_IS_A_DISPOSABLE_ST8_TEST_DATABASE"
$env:ST8_TEST_WORKERS = "20"
npm install --ignore-scripts
npm run test:concurrency
```
Connection string შეინახეთ მხოლოდ environment variable/secret manager-ში. TLS certificate verification ჩართულია ნაგულისხმევად. დისტანციურ ბაზასთან `ST8_TEST_SSL=disable` არ გამოიყენოთ.

## რას ამოწმებს runner
- PostgreSQL 17.x და ST8 callback/funding RPC signatures;
- 14/14 ST8 ცხრილის RLS + FORCE RLS, ცარიელი მონაცემები და private schema grants;
- synthetic auth user, test site/game, player mapping და wallet session;
- C01–C12 დამოუკიდებელი pooled connections-ით;
- balance/debt/ledger/idempotency invariants და თითოეული ტესტის JSON evidence.

Ledger და audit append-only-ია, ამიტომ fixture rows ავტომატურად არ იშლება. Report-ის ექსპორტის შემდეგ წაშალეთ მთლიანად disposable database/container ან Supabase branch.

## შეზღუდვები
ეს runner ამოწმებს მხოლოდ DB-level RPC concurrency-ს. ის არ ამოწმებს ST8-ის რეალურ signature verification-ს, HTTP Gateway-ს, provider callbacks-ს ან პარტნიორის Testing Tool-ს. PASS არ ნიშნავს ST8 certification-ს ან Production readiness-ს.

## Supabase branch-ის მიმდინარე შეზღუდვა
Supabase branch creation API-მ დააბრუნა `Branching is supported only on the Pro plan or above`. ამიტომ development branch არ შექმნილა და საათობრივი გადასახადი არ დარიცხულა. ლოკალური Docker გზა ამ გეგმურ შეზღუდვას გვერდს უვლის და მონაცემებს მხოლოდ მომხმარებლის კომპიუტერზე ინახავს.
