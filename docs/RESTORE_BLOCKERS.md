# Restore blockers and what is included

## Included and verified in Stage 18

- ASIX V153 frontend baseline, using destination-project config placeholders.
- Exact active `super-worker` V25 raw source capture with matching SHA-256.
- Separate V26 Edge Function candidate; TypeScript check passes, but it is not deployed.
- Recovered V147/V148/V149 SQL references.
- Read-only database, security, financial, gameplay, wallet, and deal-ledger audits.
- Guarded V155 patch for the player-count prize schedule, the 0.30 GEL table-buy-in floor, and disabling both signup-time and wallet-read demo-credit minting.
- Guarded V156 patch for deal-level money-ledger references, platform commission allocation records, and the 3% retained reserve audit row.
- Read-only Stage 17 and Stage 18 database validation SQL.
- Local BOT practice schedule aligned to 85/80/70/60% initial prize pool and 97% final pool.
- Static validator covering frontend JavaScript, prize profile calculations, destination config syntax, frontend secret scan, Edge Function TypeScript, V155/V156 guards, dollar-quote structure, and source hashes.

## Not yet materialized as verified local files

- Full ordered V154 base schema SQL.
- All 73 exact live function definitions as deployable SQL.
- Exact live generated 30,172-character `database.types.ts` file. The ZIP copy is clearly marked as a placeholder; exact generated output remains in the Supabase source-snapshot notebook.
- Complete SQL bodies for the 128 historical migration records.
- A clean-target restore and gameplay smoke test.

These are actual restore blockers. Do not advertise or use this ZIP as a one-click fresh-project restore until they are resolved.

## Staging cost and user approval

There are currently no development branches on the source project. Supabase returned a development-branch cost quote of **$0.01344/hour** (approximately **$9.81 per 730 hours**). The branch has not been created because explicit user acceptance of that cost is required. No production changes were made.

## Important design terminology

The prepared growth patch currently advances after **four successful card plays/cuts**. Historic wording “after 4 deals” may mean four card cuts in one deal or four completed deals. This interpretation should be settled before production rollout; see `docs/STAGE18_UNRESOLVED_DESIGN_ASSUMPTIONS.md`.

## Required deployment sequence

1. Materialize and restore the V154 baseline on an isolated staging project.
2. Apply V155 only after its exact guarded function anchors match.
3. Apply V156 only after V155.
4. Run `supabase/exports/read_only_stage17_validation.sql` and `supabase/exports/read_only_stage18_validation.sql`.
5. Complete 2–5 player game, early-finish, cancellation/refund, side-pot, uncalled-refund, cashout, bot-session, and idempotency smoke tests.
6. Enable Auth leaked-password protection and review Auth URLs, Edge secrets, RLS, and grants before public launch.

No source production modifications were performed while preparing this bundle.