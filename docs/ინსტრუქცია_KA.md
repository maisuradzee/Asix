# ASIX-ის სრული წყაროების ექსპორტი — სტატუსი და ინსტრუქცია

## მიმდინარე GitHub მდგომარეობა — 2026-11-20

ASIX-ის ხელმისაწვდომი ძირითადი წყაროები უკვე ატვირთულია: V153 frontend, მოქმედი Supabase Edge Function V25, მიმდინარე აპლიკაციური schema snapshot, 73 ფუნქციის SQL, TypeScript ტიპები, 128 მიგრაციის ისტორიის სია, RLS/trigger/index/grant metadata და აღდგენილი V147–V149 SQL ფაილები.

**GitHub:** https://github.com/maisuradzee/Asix

## რა არის ატვირთული

- `frontend/AsixgameV153.html` — სრული HTML წყარო.
- `supabase/schema/schema.sql` — ცოცხალი PostgreSQL კატალოგიდან აღდგენილი მიმდინარე აპლიკაციური სქემა.
- `supabase/schema/functions_snapshot.sql` — 73 ფუნქციის ზუსტი მიმდინარე განსაზღვრებები.
- `supabase/types/database.types.ts` — ცოცხალი ბაზიდან გენერირებული TypeScript ტიპები.
- `supabase/MIGRATION_INVENTORY.md` — 128 მიგრაციის ვერსია და სახელი.
- `supabase/functions/super-worker/index.ts` — მოქმედი Edge Function V25.
- `supabase/migrations_recovered/` — ხელმისაწვდომი V147, V148 და V149 SQL წყაროები.
- `supabase/candidates/V157_ENTRY_FEE_5_PERCENT_NO_PRIZE_GROWTH.sql` — staging-ისთვის განკუთვნილი, ჯერ გამოუყენებელი კანდიდატი.
- `docs/` — აღდგენის, ფინანსური წესებისა და ვალიდაციის დოკუმენტები.

## რა არ არის ჯერ სრულად აღდგენილი

1. Supabase-ის migration history ინახავს 128 მიგრაციის სახელებსა და ვერსიებს, მაგრამ არა ყველა ისტორიული SQL ფაილის სრულ ტექსტს. ყველა 128 ორიგინალი მიგრაცია ამიტომ ვერ აიტვირთა.
2. `schema.sql` აღდგენილია live PostgreSQL catalog-იდან. ის ჯერ არ არის შემოწმებული ცალკე, სუფთა staging Supabase პროექტში restore-ით; ამიტომ ჯერ არ უნდა ჩაითვალოს სერტიფიცირებულ `pg_dump`-ად.
3. V26 Edge Function კანდიდატი წინა შემოწმების ჩანაწერებშია ნახსენები, მაგრამ მისი წყარო ამ სესიაში ვერ მოიძებნა. ატვირთულია მხოლოდ მოქმედი V25.
4. Supabase Auth მომხმარებლები, პაროლები, OAuth/SMTP საიდუმლოებები, service-role key, Edge Function secrets და Storage-ის ბინარული ობიექტები განზრახ არ არის ატვირთული.
5. ცოცხალი მოთამაშეების მონაცემები, საფულეები და ტრანზაქციების ისტორია არ გადატანილა.

## ფინანსური წესი

მთლიანი Entry Fee-ის 5% არის ASIX საკომისიო. დარჩენილი 95% სრულად შედის საპრიზო ფონდში დარიგების დაწყებისთანავე. ეტაპობრივი ზრდა და დამატებითი 3% რეზერვი არ გამოიყენება.

## უსაფრთხო გაშვება / აღდგენა

- ჯერ აღადგინე `supabase/schema/schema.sql` ცალკე, disposable staging ბაზაში.
- შემდეგ გადაამოწმე grants, RLS, Realtime publication და Auth პარამეტრები.
- V157 კანდიდატი არ გაუშვა production-ზე; ჯერ staging-ზე უნდა შემოწმდეს და PostgreSQL-მა უნდა დააკომპილიროს.
- production secrets არ ჩაწერო GitHub-ში, HTML-ში ან ჩატში.
- სრული clean restore და gameplay smoke test ჯერ დასრულებული არ არის.
