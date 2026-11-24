# ASIX × ST8 — ავტომატური პროგრესის ციკლი

**Workflow:** `.github/workflows/asix-st8-autonomous-progression.yml`

## როგორ მოძრაობს პროცესი

1. **Static და უსაფრთხოების შემოწმება** — ყოველ ახალ ST8 static workflow run-ის დასრულებაზე, ყოველდღიურად 05:23 UTC-ზე და ხელით გაშვებისას. მოწმდება Node.js runner-ის სინტაქსი, PowerShell launcher, `pg@8.16.3` pin და `service_role` / API-role უსაფრთხოების კონტრაქტი.
2. **Wallet concurrency runtime** — ირთვება მხოლოდ მაშინ, როცა ზუსტად დამტკიცებული 9-მიგრაციიანი v0.8.0 პაკეტი არსებობს და მისი SHA-256 ემთხვევა დაფიქსირებულ მნიშვნელობას. GitHub Actions ქმნის დროებით PostgreSQL 17.12 სერვისს, ამზადებს ცარიელ Supabase Auth-ის სატესტო სტრუქტურას, იყენებს მხოლოდ სინთეზურ მონაცემებს და უშვებს C01–C12-ს 20 worker-ით.
3. **ST8 partner preflight** — runtime PASS-ის შემდეგ ამოწმებს, არსებობს თუ არა აუცილებელი დაცული GitHub Secrets. მათი მნიშვნელობები workflow log-ში არ იბეჭდება. ეს მხოლოდ მზადყოფნის შემოწმებაა; პარტნიორის Testing Tool-ს არ ასრულებს და მიღებას არ ამტკიცებს.
4. **Progression report** — თითოეული ციკლი ტოვებს `asix-st8-progression-report` JSON არტეფაქტს, სადაც ჩანს მიმდინარე ეტაპი, შედეგები და რა ბლოკავს შემდეგ ნაბიჯს. Runtime PASS-ის შემთხვევაში ცალკე ინახება მხოლოდ გაწმენდილი `asix-st8-runtime-evidence`; raw report არ იტვირთება.

## ამჟამინდელი ბლოკერი

Runtime ეტაპი შეგნებულად ჩაკეტილია, სანამ repository-ში არ დაემატება ზუსტად დამოწმებული 9 SQL migration-ის არქივი:

`staging-candidates/v0.9.0/runtime-migrations-bundle.zip`

მოსალოდნელი SHA-256:

`51dcbc061ba3dda3c5c9105a5d67b7f841360070be4094d995ff00fd7e03d425`

პაკეტის არქივის გარეშეც static და უსაფრთხოების შემოწმებები ავტომატურად გაეშვება, ხოლო progression report დააფიქსირებს `BLOCKED_MIGRATION_BUNDLE`-ს. Workflow არ გამოიყენებს Production-ს ან ძირითად Asix #2 staging პროექტს ამ ხარვეზის გვერდის ასავლელად.

## უცვლელი უსაფრთხოების ზღვარი

- Production Supabase `kxcuvagipqiqisowtgys` არ გამოიყენება.
- ძირითადი Asix #2 staging `liiowoclsddlywabvmcg` არ გამოიყენება.
- PR #3 რჩება Draft/Open; workflow მას არ აერთიანებს და Draft-დან არ გამოჰყავს.
- C01–C12-ის წარმატება არ ნიშნავს ST8 partner certification-ს ან Production readiness-ს.
- ST8 partner sandbox credentials-ის არსებობა არ უდრის Testing Tool acceptance-ს.
- Production release ყოველთვის LOCKED რჩება.

## ტრიგერები

- `workflow_run`: არსებული `ASIX ST8 v0.9 Static Validation` დასრულების შემდეგ.
- `schedule`: ყოველდღე 05:23 UTC.
- `workflow_dispatch`: ხელით გაშვება GitHub Actions-იდან.
- `pull_request`: თავად orchestration workflow-ისა და ამ დოკუმენტის ცვლილებების შემოწმება.
