# ASIX #2 / ST8 — შესრულების ანგარიში
**თარიღი:** 24 ნოემბერი 2026  
**სამიზნე:** მხოლოდ Asix #2 staging და კანდიდატი კოდი  
**Production საზღვარი:** უცვლელი; ამ აუდიტში Production-ზე არ შესრულებულა write, migration, secret update ან deployment.

## აღმასრულებელი შეჯამება

ამ ციკლში შესრულდა ხელმისაწვდომი კოდის, GitHub CI-ისა და Supabase გარემოს შემოწმებები. ლოკალური v0.8.0 ვერიფიკაცია წარმატებულია; v0.9.0 static CI წარმატებულია; Asix #2 staging-ის უსაფრთხოების საზღვრები read-only შემოწმებით დადასტურდა.

**სრული ST8 acceptance ჯერ არ დასრულებულა.** Deno-native ტესტები და C01–C12 მრავალსესიური PostgreSQL ტესტები არ გაშვებულა, ST8 Sandbox/Testing Tool მონაცემები არ არის ხელმისაწვდომი, Gateway არ არის deployed. ქვემოთ აღწერილი სტატიკური ტესტები არ უნდა ჩაითვალოს runtime/concurrency acceptance-ად.

## 1. დოკუმენტაცია და კანდიდატის ვერიფიკაცია

- v0.8.0 archive-ის `npm run verify`: **22 PASS / 0 FAIL**.
- Node.js Gateway/runtime suite: **74/74 PASS**.
- Static architecture/security contracts: **134/134 PASS**.
- TypeScript strict compile: **PASS**.
- 18 JavaScript module syntax checks: **PASS**.
- Inner SHA-256 manifest: **69/69 PASS**.
- Deno-native test suite: **SKIPPED** — Deno CLI ამ execution გარემოში არ იყო ხელმისაწვდომი. SKIPPED არ ნიშნავს PASS-ს.
- ორი FK-index migration ფაილი იდენტურია და ორივე უკვე ასახულია staging migration history-ში. რადგან SQL იყენებს `CREATE INDEX IF NOT EXISTS`, ეს ისტორიული დუბლირება არ საჭიროებს უკვე გამოყენებული migration history-ის გადაწერას ან წაშლას. მომავალი migration guard-ები უნდა ამოწმებდეს დუბლირებულ version/name/checksum-ებს.

## 2. Deno runtime tests

**სტატუსი: BLOCKED / NOT RUN.**  
Execution გარემოში Deno CLI არ არის და ქსელიდან ინსტალაციაც ვერ შესრულდა. Gateway-ის crypto/protocol/money/catalog native tests არ ჩაითვალოს გავლილად. აუცილებელია მათი გაშვება Deno-ს მხარდაჭერილ გარემოში.

## 3. C01–C12 wallet concurrency

**სტატუსი: PREPARED, NOT EXECUTED.**  
GitHub Actions run #50 წარმატებულია: JavaScript syntax, PowerShell launcher syntax, `service_role` execution boundary და `pg@8.16.3` dependency pin შემოწმებულია.

ეს workflow არ უშვებს C01–C12-ს. მრავალსესიური ტესტები უნდა გაეშვას მხოლოდ ცალკე disposable PostgreSQL 17.12 instance-ზე ან ცალკე Supabase development branch-ზე. Supabase branch provisioning-მა დააბრუნა: `Branching is supported only on the Pro plan or above`. მიმდინარე execution გარემოში Docker, PostgreSQL CLI და PowerShell არ არის. ძირითადი staging-ის ან Production-ის გამოყენება აკრძალულია.

## 4. Staging უსაფრთხოება და Production boundary

### Asix #2 staging

- Project ref: `liiowoclsddlywabvmcg`
- Status: `ACTIVE_HEALTHY`
- PostgreSQL: `17.12`
- Applied migration history: **9 entries**
- `provider_internal.st8_*` tables: **14/14**, ყველა RLS + FORCE RLS ჩართული.
- ზუსტად დათვლილი ჩანაწერები: **14/14 ცხრილი ცარიელია**.
- `anon`, `authenticated`, `service_role`-ს `provider_internal` schema USAGE არ აქვს; ST8 ცხრილებზე ამ როლების პირდაპირი table privileges არ გამოვლენილა.
- Edge Functions deployed: **0** — ST8 Gateway არ არის deployed.
- Supabase Advisors: Security **14 INFO** (`rls_enabled_no_policy`, private schema-ზე განზრახ); Performance **11 INFO** (unused indexes ცარიელ staging-ზე); Health **0 findings**.

### Existing Production

Read-only live metadata check:
- Project ref: `kxcuvagipqiqisowtgys`
- Status: `ACTIVE_HEALTHY`, PostgreSQL `17.11.0.019`.
- `super-worker`: **version 26**, ACTIVE, `verify_jwt=true`.
- Deployed function source digest: `4804411c7daeae389caab0754e011dc0af080335a8aa33bdae2166a1b3e7218e`.

ეს განსხვავდება ძველ დოკუმენტაციაში ნახსენები V25 baseline-ისგან; მიმდინარე live metadata არის V26. ამ ციკლში Production ფუნქცია არ შეგვიცვლია. Production `super-worker` არის არსებული ASIX gameplay/QCard worker და არ წარმოადგენს ST8 Game Provider Gateway-ს.

## 5. ST8 პარტნიორული მონაცემები და არქიტექტურის შესაბამისობა

ეს არის მთავარი არქიტექტურული შეუსაბამობა, რომელიც უნდა გასწორდეს სანამ ST8-ზე გაგრძელდება deployment.

საჯარო ST8 დოკუმენტაცია არის **Operator API**: ის აღწერს, როგორ უკავშირდება ST8 კაზინოს/ოპერატორს და როგორ აწვდის ოპერატორი Seamless Wallet callback-ებს. ეს API და არსებული ST8 wallet callback Gateway ASIX-ს თავისთავად არ ანიჭებს თამაშების მიმწოდებლის სტატუსს.

ASIX-ის განსაზღვრული მიზანია **B2B Game Service Provider** — თამაშების მიწოდება ლიცენზირებული ოპერატორებისთვის. ამისთვის საჭიროა ST8-ის ცალკე Provider/Developer onboarding-ის, ტექნიკური კონტრაქტის და შესაბამისი Game Provider API/ინტეგრაციის დადასტურება. ამ მონაცემების მიღებამდე operator-wallet candidate არ ჩაითვალოს game-provider ინტეგრაციად.

GitHub PR #1 `ASIX B2B Provider Integration Foundation` უფრო ახლოს დგას ამ ბიზნეს-მიზანთან და უკვე აღწერს ცალკე Partner Gateway/Wallet Orchestrator/Settlement მოდელს. ისიც Draft/unmerged კანდიდატია; მისი დიზაინი და ტესტირების მტკიცებულებები უნდა გადაიხედოს, ვიდრე რეალურ პარტნიორთან დაინერგება.

## 6. Sandbox და ოფიციალური acceptance

**სტატუსი: BLOCKED.**  
არ არის ST8 Provider/Developer onboarding-ის დამადასტურებელი კონტრაქტი ან API სპეციფიკაცია, პარტნიორის sandbox endpoint/credentials, site/operator identifiers, საჯარო გასაღებები და Testing Tool-ის ანგარიშები. ამიტომ არც ცოცხალი ST8 მოთხოვნა, არც ხელმოწერის callback, არც launch/wallet test არ გაშვებულა. ოფიციალური Testing Tool credentials უნდა მიიღოს ASIX-მა ST8 onboarding-ის მეშვეობით; არ შეიძლება მათი გამოგონება ან Operator API-ის მონაცემებით ჩანაცვლება.

## 7. სამართლებრივი და ოპერაციული მზადყოფნა

**სტატუსი: PRELIMINARY REVIEW ONLY — NOT CLEARED.**

საქართველოს კანონი „ლატარიების, აზარტული და მომგებიანი თამაშობების მოწყობის შესახებ“ თამაშების მიწოდებას ცალკე განსაზღვრავს და მუხლი 5(1)-ით საქართველოში შესაბამისი საქმიანობა ნებართვის რეჟიმს უკავშირებს. არსებითი პროდუქტის/მომსახურების განსაზღვრება მოიცავს ისეთ თამაშებსა და პლატფორმა/სერვერულ/სისტემურ კომპონენტებსაც, რომლებსაც თამაშის შედეგზე გავლენა შეუძლიათ.

სანამ B2B Game Service Provider მოდელი ამოქმედდება, საქართველოს სათამაშო ბიზნესის იურისტთან და შემოსავლების სამსახურთან წერილობით უნდა დადასტურდეს:
- ASIX-ის კონკრეტული საქმიანობის კლასიფიკაცია და საჭირო ნებართვა/ავტორიზაცია;
- თამაშის, RNG-ის, სერვერის/პლატფორმისა და სხვა კრიტიკული პროდუქტის სერტიფიცირების/შერჩევული პირის მოთხოვნები;
- პარტნიორი ოპერატორის ნებართვები და დაშვებული იურისდიქციები;
- მოთამაშის თანხების, PSP settlement-ისა და პასუხისმგებლობის გამიჯვნა;
- AML/KYC, ასაკი, გეოლოკაცია, თვითგამორიცხვა და responsible-gambling კონტროლები;
- მონაცემთა დაცვის, აუდიტის, ინციდენტისა და ანგარიშგების ვალდებულებები.

ეს დოკუმენტი არ წარმოადგენს იურიდიულ დასკვნას ან ნებართვის დამადასტურებელ საბუთს. საჯარო ავტორიზაციის/სერტიფიცირების პროცედურები უნდა გადამოწმდეს უშუალოდ შესაბამის ოფიციალურ ორგანოებთან და იურისტთან.

## 8. Production readiness

**სტატუსი: NOT READY / DEPLOYMENT BLOCKED.**  
არ შესრულებულა Production migration, ST8 Gateway deployment, secret configuration, wallet movement, live ST8 request ან Production setting change. Production `super-worker v26` დარჩა უცვლელი. Production rollout დაიშვება მხოლოდ Provider/Developer onboarding-ის, იურიდიული ნებართვების, შესაბამისი სერტიფიცირების, Deno/runtime + C01–C12 ტესტების, Sandbox/Testing Tool acceptance-ის, დამოუკიდებელი უსაფრთხოების აუდიტის და DR/backup/monitoring readiness-ის შემდეგ.

## შემდეგი ზუსტი მოქმედებები

1. ST8-ს წერილობით მოვთხოვოთ Provider/Developer onboarding package, API specification, certification criteria და Testing Tool access.
2. PR #1-ის B2B Provider კანდიდატის review გავაკეთოთ როგორც ASIX-ის მთავარ მიმართულებაზე; PR #3-ის ST8 Operator API კოდი დარჩეს ცალკე ინტეგრაციის კანდიდატად.
3. Deno-native test suite გაეშვას Deno გარემოში.
4. C01–C12 გაეშვას local Docker/PostgreSQL 17.12 გარემოში ან ხელმისაწვდომ Pro Supabase development branch-ზე, არასოდეს ძირითად staging/Production-ზე.
5. საქართველოს სათამაშო ბიზნესის იურისტის/შემოსავლების სამსახურის წერილობითი შეფასება და საჭირო permit/certification მივიღოთ.
6. ST8 Sandbox acceptance დასრულდეს მხოლოდ Provider onboarding-ის შემდეგ.
7. ამის შემდეგ მოხდეს ცალკე Production architecture review და rollout-ის გადაწყვეტილება.

**საბოლოო დასკვნა:** კოდის სტატიკური და staging-ის უსაფრთხოების შემოწმებები დადებითია. ST8-ის ოფიციალური provider integration, runtime concurrency acceptance, Sandbox certification და სამართლებრივი clearance ჯერ არ არსებობს. Production deployment არ არის დაშვებული.


## წყაროები და შესაბამისობის შენიშვნები

- ST8-ის საჯარო ტექნიკური დოკუმენტაცია საკუთარ თავს ასათაურებს **Operator API documentation (v1)**-ად; შესავალი ჩამოთვლის Operator-ის Game Launch, Query, Bonus და Transfer Wallet API-ებს და ამბობს, რომ Seamless Wallet-ის შემთხვევაში API-ს ოპერატორი აწვდის. ეს დოკუმენტაცია თავისთავად არ ადასტურებს ASIX-ის Game Provider onboarding-ს: https://docs.st8api.com/
- საქართველოს კანონის კონსოლიდირებულ ტექსტში მუხლი 11(1)(ლ) ცალკე ასახელებს „აზარტული ან/და მომგებიანი თამაშების მიწოდებას“ ნებართვას დაქვემდებარებულ საქმიანობად; მუხლი 3(ც), (ძ), (წ) განსაზღვრავს მიწოდებას, მიმწოდებელს და არსებით პროდუქტს/მომსახურებას: https://matsne.gov.ge/ka/document/view/30988
- შერჩეული პირის RS Georgia/RSIG-ის გამოქვეყნებული GSP B2B პროცედურა ამჟამად მიუთითებს საქართველოში დაფუძნებული კომპანიის მოთხოვნაზე, 100,000 GEL წლიურ სანებართვო მოსაკრებელზე, თამაშებისა და კრიტიკული პროდუქტის აღწერაზე და შერჩეული პირის ავტორიზაციის სერტიფიკატზე. RSIG თავად აფრთხილებს, რომ ჩამონათვალი შეიძლება არ იყოს ამომწურავი და მიმართავს განმცხადებელს ადგილობრივ იურისტთან კონსულტაციისკენ; თანხა/პირობები განაცხადამდე უშუალოდ შემოსავლების სამსახურთან უნდა დადასტურდეს: https://rsig.ge/ge/permits-and-processes

აღნიშნული წყაროები არის სამართლებრივი/ტექნიკური მიმართულების წინასწარი საფუძველი და არა ASIX-ის ნებართვა, სერტიფიკატი ან პარტნიორის მიღების დადასტურება.


## Follow-up verification — 24 Nov 2026

After this report was first committed, the separate B2B Provider foundation branch was independently checked:
- PR #1 head `7a754a98199dbbeabadf6457c9cf078bc0eca27e`.
- GitHub Actions run **#374**: SUCCESS. The `provider-reference` job completed Deno type-check and all Provider reference tests; the separate `provider-database-sql` job completed its disposable PostgreSQL 17 schema smoke, response lifecycle, status-query lease recovery, concurrent launch idempotency and concurrent financial exposure/refund tests.
- This validates the separate Provider reference candidate, not the ST8 Operator-wallet C01–C12 runner. Do not transfer its PASS status to the ST8 wallet candidate.
- The ST8 branch's latest static workflow run **#52** also completed SUCCESS on report commit `7e1fb5350544340bdf09aa107921a80c05b51baf`; it validates runner syntax, PowerShell syntax, role-boundary assertions and dependency pin only. It does not execute C01–C12.
- The ST8 Deno test files referenced in the local v0.8.0 archive are not present at the corresponding `supabase/functions/st8-gateway/*_test.ts` paths in the current GitHub integration branch. Therefore an Actions run against that branch cannot execute those native tests until the exact candidate source/test tree is registered in GitHub.
- The ST8 C01–C12 runner remains prepared but not executed. The local runner requires the nine exact v0.8.0 migrations and a disposable PostgreSQL 17.12 instance. No test has been run against the base staging or Production.

Links:
- PR #1: https://github.com/maisuradzee/Asix/pull/1
- Provider CI run #374: https://github.com/maisuradzee/Asix/actions/runs/44916078807
- ST8 static CI run #52: https://github.com/maisuradzee/Asix/actions/runs/45441760330
