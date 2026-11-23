# ASIX × ST8 — v0.9.0 Wallet lifecycle და concurrency ტესტირების გეგმა

**სტატუსი:** დაგეგმილია; PostgreSQL მრავალსესიური ტესტი ჯერ არ გაშვებულა.
**სამიზნე:** მხოლოდ disposable Asix #2 staging clone ან იზოლირებული PostgreSQL 17 test instance.
**Production:** აკრძალულია.

## წინასწარი კონტროლი
- გამოიყენე სინთეზური auth user, pseudonymous ST8 player ID, test site/game და ცალკე wallet.
- თითოეული ტესტი დაიწყე wallet/debt/ledger/transaction snapshot-ით.
- გაუშვი ორ ან მეტ დამოუკიდებელ DB session-ში, არა ერთ SQL transaction-ში.
- თითოეული შემთხვევა დაასრულე rollback-ით ან disposable DB reset-ით.
- არ გამოიყენო რეალური მოთამაშე, თანხა, PSP ან ST8 live credential.

## აუცილებელი მრავალსესიური შემთხვევები

| ID | პარალელური ოპერაციები | მოსალოდნელი შედეგი |
|---|---|---|
| C01 | ერთი debit-ის იდენტური callback ორჯერ | ერთი transaction და ერთი ledger movement; მეორე duplicate |
| C02 | ერთი transaction ID, განსხვავებული request hash | ერთი გამარჯვებული; მეორე IDEMPOTENCY_CONFLICT; მეორე მოძრაობა არ იქმნება |
| C03 | საწყისი 1000 tetri, ორი 700-tetri debit სხვადასხვა ID-ით | მაქსიმუმ ერთი წარმატებული debit; balance არასდროს უარყოფითი |
| C04 | daily limit-ის ზღვარზე ორი პარალელური debit | ჯამური დაშვებული wager ლიმიტს არ აჭარბებს |
| C05 | ერთი debit და მის reference-ზე cancel ერთდროულად | სერიალიზებული საბოლოო მდგომარეობა; ერთი refund მაქსიმუმ |
| C06 | ერთი cancel ID-ის ორი იდენტური callback | ერთი cancellation ledger movement; მეორე duplicate |
| C07 | ერთი cancel ID სხვადასხვა payload/hash-ით | IDEMPOTENCY_CONFLICT; დამატებითი movement არ იქმნება |
| C08 | payout reversal და სხვა payout/debit ერთ საფულეზე | balance >= 0; shortfall მხოლოდ ST8 debt-ში |
| C09 | trusted funding იგივე idempotency key-ით ორჯერ | ერთი funding ledger row; მეორე duplicate |
| C10 | trusted funding ერთი key-ით განსხვავებული თანხით | IDEMPOTENCY_CONFLICT; balance უცვლელი |
| C11 | cancel მოვიდა original debit-მდე; original შემოვიდა პარალელურად | ერთი tombstone; original cash movement 0; tombstone enriched |
| C12 | 20–100 ერთდროული სხვადასხვა transaction ID ერთ user-ზე | ledger balance chain უწყვეტი; არ არის duplicate key ან lost update |

## ინვარიანტები
1. wallet balance >= 0.
2. wallet balance ემთხვევა ბოლო ledger row-ის balance_after_tetri-ს.
3. idempotency_key უნიკალურია; ერთი provider transaction/cancel ID მაქსიმუმ ერთ ჩანაწერს ქმნის.
4. debt >= 0; reversal debt მხოლოდ ST8 debt table-შია.
5. callback retry ვერ ქმნის მეორე ფინანსურ მოძრაობას.
6. ASIX demo/QCard ცხრილები და მონაცემები უცვლელია.
7. deadlock/serialization retry არ იმეორებს უკვე დადასტურებულ movement-ს.

## მიმდინარე კოდის წინასწარი სტატიკური დაკვირვება
Wallet callback SQL იყენებს transaction/cancel advisory locks-ს, შემდეგ wallet row lock-ს და player-debt advisory/row lock-ს. Daily wager aggregation სრულდება debt lock-ის შემდეგ, რაც ერთ user/currency-ზე wager limit-ის სერიალიზაციას უწყობს ხელს. Trusted funding-ს აქვს ცალკე funding-key lock და wallet/debt lock.

ეს არის კოდის დონის დაკვირვება და არა concurrency ტესტის მტკიცებულება.

## Lock-order review — v0.9.0 სტატიკური გაფართოება
ქვემოთ ჩამოთვლილი მიმდევრობა გადამოწმებულია v0.8.0-ის `20261121000100_st8_seamless_wallet.sql` მიგრაციაში. ეს აღწერს SQL-ში მოთხოვნილ lock-ებს და არა რეალურ runtime timing-ს.

| ოპერაცია | lock-ების მიმდევრობა |
|---|---|
| ჩვეულებრივი callback | advisory `st8:transaction:<transaction_id>` → transaction row `FOR UPDATE` → wallet account row `FOR UPDATE` → player-debt advisory lock → debt row `FOR UPDATE` |
| cancel callback | advisory `st8:cancel:<cancel_id>` → advisory `st8:transaction:<reference_transaction_id>` → cancel/reference rows → wallet account row `FOR UPDATE` → player-debt advisory lock → debt row `FOR UPDATE` |
| trusted funding | advisory `st8:funding-key:<idempotency_key>` → idempotency ledger lookup → wallet account row `FOR UPDATE` → player-debt advisory lock → debt row `FOR UPDATE` |

დამატებითი დაკვირვებები:
- Original callback და cancel callback reference transaction-ის ერთსა და იმავე `st8:transaction:<ID>` advisory lock-ს იყენებს. ეს განზრახული საერთო serialization point-ია late-original/tombstone race-ისთვის.
- Cancel-ის საკუთარი ID ცალკე იკეტება, ამიტომ იდენტური cancellation replay-ები ერთმანეთს ვერ ასწრებს.
- ერთი user/currency-ის wager aggregation სრულდება player-debt advisory lock-ის მიღების შემდეგ; ეს უნდა დადასტურდეს C04-ის პარალელური ტესტით.
- Callback, cancel და trusted funding wallet account row-ს debt row-მდე კეტავს. განსხვავებული funding keys ერთი wallet row-ზე საბოლოოდ სერიალიზდება.
- Advisory hash collision შეიძლება ზედმეტ სერიალიზაციას იწვევდეს, მაგრამ თვითონ არ უნდა იწვევდეს ფინანსური მონაცემების დაკარგვას.

## Release gate
- PostgreSQL 17.12 ან შესაბამისი Supabase staging clone;
- მინიმუმ 2 დამოუკიდებელი connection, სასურველია 20+ worker;
- Deno CLI და Supabase Edge Function test harness;
- raw request hash, SQLSTATE, response, before/after account/debt/ledger snapshots;
- deadlock/serialization logs და repeat run evidence.

**v0.9.0 concurrency acceptance გავლილად არ ჩაითვალოს**, სანამ C01–C12 რეალურად არ შესრულდება disposable DB-ზე და evidence არ შეინახება.
