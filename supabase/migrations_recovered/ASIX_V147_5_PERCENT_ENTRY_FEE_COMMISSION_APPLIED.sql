-- ASIX V147 — 5% commission from the FULL TABLE ENTRY FEE
-- APPLIED MIGRATION REFERENCE: asix_v147_5_percent_entry_fee_and_legacy_history_cleanup
-- Applied to the live ASIX Supabase project on 2026-11-17 (migration version 20261117183150).
-- Completed legacy game history is cleared; live lobbies and wallet accounting are preserved.
--
-- Base: live ASIX Supabase project schema inspected on 2026-11-17.
-- Rules:
--   * Entry Fee per player = card_price * cards_per_player (in tetri).
--   * Gross table Entry Fee = eligible funded players * per-player Entry Fee.
--   * Site commission = ROUND(gross table Entry Fee * 5%) ONCE for the whole table.
--   * The 5% is held as pending during play, credited only on success, and voided on cancellation.
--   * Commission is allocated across player ledger rows in seat order so the
--     sum of those rows equals the once-rounded table commission exactly.
--   * Net prize pool = gross table Entry Fee - table commission (95% before rounding).
--   * No 97% cap, no old 4-stage prize growth, no fixed 0.03 GEL/player fee.
--   * Additional raises / side pots remain separate and are not commission bases.
--   * Bot practice uses virtual balances and does not accrue real site commission.
--
-- Existing site commission recipient is preserved. Already-posted wallet transactions
-- remain as accounting records; game-specific ledger/history rows for finished rooms are removed.

-- 1) Add a configurable commission rate (basis points: 500 = 5%).
alter table public.asix_platform_commission_settings
  add column if not exists commission_rate_bps smallint not null default 500;

do $rate_constraint$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.asix_platform_commission_settings'::regclass
      and conname='asix_platform_commission_settings_rate_bps_check'
  ) then
    alter table public.asix_platform_commission_settings
      add constraint asix_platform_commission_settings_rate_bps_check
      check (commission_rate_bps between 0 and 10000);
  end if;
end;
$rate_constraint$;

-- Preserve the already configured site recipient; enforce the newly approved 5% rate.
do $commission_config$
begin
  update public.asix_platform_commission_settings
     set commission_rate_bps=500, enabled=true, updated_at=now()
   where id=1 and recipient_user_id is not null;
  if not found then
    raise exception 'ASIX_PLATFORM_COMMISSION_RECIPIENT_NOT_CONFIGURED';
  end if;
end;
$commission_config$;

-- Remove the legacy fixed-3-tetri constraint and neutralize the field so no
-- older client can mistake it for the active commission amount.
alter table public.asix_platform_commission_settings
  drop constraint if exists asix_platform_commission_settings_fee_per_player_tetri_check;
update public.asix_platform_commission_settings
   set fee_per_player_tetri=0, updated_at=now()
 where id=1;

comment on column public.asix_platform_commission_settings.commission_rate_bps is
  'ASIX V147 commission rate in basis points; 500 = 5% of the whole deal Entry Fee.';
comment on column public.asix_platform_commission_settings.fee_per_player_tetri is
  'Deprecated legacy field; always zero. V147 uses commission_rate_bps instead.';

-- The ledger now stores each player's allocated share of the table-level fee.
-- A zero share is valid when the rounded whole-table commission is smaller than
-- the number of players; no zero-value wallet transaction is written.
alter table public.asix_platform_commission_ledger
  drop constraint if exists asix_platform_commission_ledger_amount_tetri_check;
alter table public.asix_platform_commission_ledger
  add constraint asix_platform_commission_ledger_amount_tetri_check
  check (amount_tetri >= 0);

alter table public.asix_platform_commission_ledger
  add column if not exists commission_rate_bps smallint,
  add column if not exists gross_table_entry_fee_tetri bigint,
  add column if not exists table_commission_tetri bigint,
  add column if not exists settled_at timestamptz,
  add column if not exists cancelled_at timestamptz;

do $ledger_constraints$
begin
  if not exists (select 1 from pg_constraint where conrelid='public.asix_platform_commission_ledger'::regclass and conname='asix_platform_commission_ledger_rate_bps_check') then
    alter table public.asix_platform_commission_ledger add constraint asix_platform_commission_ledger_rate_bps_check
      check (commission_rate_bps is null or commission_rate_bps between 0 and 10000);
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.asix_platform_commission_ledger'::regclass and conname='asix_platform_commission_ledger_gross_amount_check') then
    alter table public.asix_platform_commission_ledger add constraint asix_platform_commission_ledger_gross_amount_check
      check (gross_table_entry_fee_tetri is null or gross_table_entry_fee_tetri >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.asix_platform_commission_ledger'::regclass and conname='asix_platform_commission_ledger_table_commission_check') then
    alter table public.asix_platform_commission_ledger add constraint asix_platform_commission_ledger_table_commission_check
      check (table_commission_tetri is null or table_commission_tetri >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.asix_platform_commission_ledger'::regclass and conname='asix_platform_commission_ledger_settlement_state_check') then
    alter table public.asix_platform_commission_ledger add constraint asix_platform_commission_ledger_settlement_state_check
      check (settled_at is null or cancelled_at is null);
  end if;
end;
$ledger_constraints$;

-- All commission rows that existed before V147 were already credited by the
-- former immediate 0.03 GEL/player trigger. Mark them settled to prevent a
-- second credit when an older live deal finishes after this migration.
update public.asix_platform_commission_ledger
   set settled_at=created_at
 where settled_at is null and cancelled_at is null and commission_rate_bps is null;

comment on column public.asix_platform_commission_ledger.settled_at is
  'When the pending V147 commission was credited after successful deal completion.';
comment on column public.asix_platform_commission_ledger.cancelled_at is
  'When pending V147 commission was voided because the deal was cancelled/refunded.';

-- Keep legacy room metadata defaults aligned with the new 95/5 model.
-- Existing room rows and completed deal history are not rewritten.
alter table public.qcard_rooms alter column prize_share set default 0.95;
alter table public.qcard_rooms alter column platform_share set default 0.05;
alter table public.qcard_rooms alter column growth_steps
  set default array[100.00,100.00,100.00,100.00]::numeric[];
alter table public.qcard_rooms alter column growth_reserve_tetri set default 0;

-- 2) Replace the card-purchase commission trigger with an exact whole-table
--    5% allocation. The trigger runs inside the same transaction as deal start.
create or replace function public.asix_record_platform_commission_from_card_purchase()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_settings public.asix_platform_commission_settings%rowtype;
  v_card_cost bigint;
  v_player_count integer;
  v_player_rank integer;
  v_seat_no smallint;
  v_total_commission bigint;
  v_base_commission bigint;
  v_remainder bigint;
  v_player_commission bigint;
begin
  if new.entry_type <> 'card_purchase' or new.user_id is null then
    return new;
  end if;

  if new.reference_action_id is null then
    raise exception 'CARD_PURCHASE_ACTION_REQUIRED';
  end if;

  select * into v_settings
  from public.asix_platform_commission_settings
  where id=1 and enabled=true
  for share;

  if not found then
    raise exception 'PLATFORM_COMMISSION_NOT_CONFIGURED';
  end if;
  if v_settings.recipient_user_id is null then
    raise exception 'PLATFORM_COMMISSION_RECIPIENT_NOT_CONFIGURED';
  end if;
  if v_settings.commission_rate_bps < 0 or v_settings.commission_rate_bps > 10000 then
    raise exception 'INVALID_PLATFORM_COMMISSION_RATE';
  end if;

  v_card_cost := new.amount_tetri;

  -- During deal start, already charged seats have a card_purchase ledger row;
  -- seats not yet charged still have stack_tetri >= the Entry Fee.
  select count(*)::integer into v_player_count
  from public.qcard_seats s
  where s.room_id=new.room_id
    and s.is_connected=true
    and (
      s.stack_tetri >= v_card_cost
      or exists (
        select 1 from public.qcard_money_ledger l
        where l.room_id=new.room_id
          and l.reference_action_id=new.reference_action_id
          and l.user_id=s.user_id
          and l.entry_type='card_purchase'
      )
    );

  if v_player_count < 2 then
    raise exception 'COMMISSION_PLAYER_COUNT_INVALID';
  end if;

  select seat_no into v_seat_no
  from public.qcard_seats
  where room_id=new.room_id and user_id=new.user_id;
  if not found then
    raise exception 'COMMISSION_PLAYER_SEAT_NOT_FOUND';
  end if;

  select count(*)::integer into v_player_rank
  from public.qcard_seats s
  where s.room_id=new.room_id
    and s.is_connected=true
    and s.seat_no <= v_seat_no
    and (
      s.stack_tetri >= v_card_cost
      or exists (
        select 1 from public.qcard_money_ledger l
        where l.room_id=new.room_id
          and l.reference_action_id=new.reference_action_id
          and l.user_id=s.user_id
          and l.entry_type='card_purchase'
      )
    );

  if v_player_rank < 1 or v_player_rank > v_player_count then
    raise exception 'COMMISSION_PLAYER_RANK_INVALID';
  end if;

  -- Round once on the total table Entry Fee, not separately per player.
  v_total_commission := round(
    v_player_count::numeric * v_card_cost::numeric * v_settings.commission_rate_bps::numeric / 10000
  )::bigint;
  v_base_commission := v_total_commission / v_player_count;
  v_remainder := mod(v_total_commission, v_player_count);
  v_player_commission := v_base_commission
    + case when v_player_rank <= v_remainder then 1 else 0 end;

  -- This is a pending commission allocation. It is NOT credited to the site
  -- wallet until the deal reaches phase=finished. Cancelled deals void it.
  insert into public.asix_platform_commission_ledger(
    deal_id,room_id,recipient_user_id,player_user_id,amount_tetri,
    commission_rate_bps,gross_table_entry_fee_tetri,table_commission_tetri
  ) values (
    new.reference_action_id::text,new.room_id,v_settings.recipient_user_id,
    new.user_id,v_player_commission,v_settings.commission_rate_bps,
    v_player_count*v_card_cost,v_total_commission
  )
  on conflict (deal_id,player_user_id) do nothing;

  return new;
end;
$function$;

revoke all on function public.asix_record_platform_commission_from_card_purchase() from public, anon, authenticated;

-- Pending commission is credited only after a successful deal. If the server
-- cancels a deal and refunds Entry Fees, the pending commission is voided.
create or replace function public.asix_settle_platform_commission_after_deal()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_deal_id text;
  v_commission record;
  v_wallet public.asix_wallets%rowtype;
  v_key text;
  v_processed integer := 0;
begin
  if coalesce(old.state->>'phase','') <> 'playing'
     or coalesce(new.state->>'phase','') not in ('finished','cancelled') then
    return new;
  end if;

  -- Legacy deals started before V147 have no entry_action_id; their old
  -- fixed commission was already paid and marked settled by the migration.
  v_deal_id := nullif(new.state->>'entry_action_id','');
  if v_deal_id is null then
    return new;
  end if;

  if new.state->>'phase'='cancelled' then
    update public.asix_platform_commission_ledger
       set cancelled_at=coalesce(cancelled_at,now())
     where room_id=new.room_id and deal_id=v_deal_id
       and settled_at is null and cancelled_at is null;
    return new;
  end if;

  for v_commission in
    select *
    from public.asix_platform_commission_ledger
    where room_id=new.room_id and deal_id=v_deal_id
      and settled_at is null and cancelled_at is null
    order by id
    for update
  loop
    v_processed := v_processed + 1;
    if v_commission.amount_tetri > 0 then
      insert into public.asix_wallets(user_id,balance_tetri)
      values(v_commission.recipient_user_id,0)
      on conflict(user_id) do nothing;

      update public.asix_wallets
         set balance_tetri=balance_tetri+v_commission.amount_tetri,
             updated_at=now()
       where user_id=v_commission.recipient_user_id
      returning * into v_wallet;

      v_key := 'asix-platform-commission:'||v_deal_id||':'||v_commission.player_user_id::text;
      insert into public.asix_wallet_transactions(
        user_id,transaction_type,amount_tetri,balance_after_tetri,room_id,
        idempotency_key,description,metadata
      ) values (
        v_commission.recipient_user_id,'platform_commission',
        v_commission.amount_tetri,v_wallet.balance_tetri,new.room_id,
        v_key,'ASIX თამაშის საკომისიო',
        jsonb_build_object(
          'deal_action_id',v_deal_id,
          'player_user_id',v_commission.player_user_id,
          'source','successful_deal_entry_fee_5_percent',
          'commission_rate_bps',v_commission.commission_rate_bps,
          'gross_table_entry_fee_tetri',v_commission.gross_table_entry_fee_tetri,
          'whole_table_commission_tetri',v_commission.table_commission_tetri,
          'allocated_player_commission_tetri',v_commission.amount_tetri
        )
      );
    end if;

    update public.asix_platform_commission_ledger
       set settled_at=now()
     where id=v_commission.id and settled_at is null and cancelled_at is null;
  end loop;

  if v_processed=0 then
    raise exception 'PLATFORM_COMMISSION_LEDGER_MISSING';
  end if;

  return new;
end;
$function$;

revoke all on function public.asix_settle_platform_commission_after_deal() from public, anon, authenticated;
drop trigger if exists asix_platform_commission_settlement_after_deal on public.qcard_game_state;
create trigger asix_platform_commission_settlement_after_deal
after update of state on public.qcard_game_state
for each row execute function public.asix_settle_platform_commission_after_deal();

-- 3) Patch the existing server-side game processor without replacing its
--    card, turn, timeout, side-pot, refund, archive or idempotency logic.
--    The patch is deliberately guarded: it aborts if the expected live source
--    no longer matches this reviewed V146 baseline.
do $patch_qcard_process_action$
declare
  v_def text;
  v_old text;
  v_new text;
  v_old_growth text;
  v_new_growth text;
begin
  v_def := pg_get_functiondef('public.qcard_process_action(bigint,uuid)'::regprocedure);

  v_old := $old_commission$
    -- Use the same enabled per-player fee as the commission ledger trigger.
    -- Holding the settings row prevents a fee change mid-deal.
    commission_fee:=0;
    select fee_per_player_tetri into commission_fee
    from public.asix_platform_commission_settings
    where id=1 and enabled=true
    for share;
    commission_fee:=coalesce(commission_fee,0);
    if card_cost <= commission_fee then
      v_error:='ENTRY_FEE_BELOW_PLATFORM_FEE';
    end if;
$old_commission$;

  v_new := $new_commission$
    -- commission_fee now carries the rate in basis points (500 = 5%).
    -- Lock the enabled recipient/rate row for the duration of deal start.
    commission_fee:=0;
    select commission_rate_bps::bigint into commission_fee
    from public.asix_platform_commission_settings
    where id=1 and enabled=true and recipient_user_id is not null
    for share;
    if not found then
      v_error:='PLATFORM_COMMISSION_NOT_CONFIGURED';
    end if;
    commission_fee:=coalesce(commission_fee,0);
    if commission_fee < 0 or commission_fee > 10000 then
      v_error:='INVALID_PLATFORM_COMMISSION_RATE';
    end if;
$new_commission$;

  if position(v_new in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'V147_PATCH_FAILED: COMMISSION_BLOCK_NOT_FOUND';
    end if;
    v_def := replace(v_def,v_old,v_new);
  end if;

  v_old := 'sales:=n_players*(card_cost-commission_fee);';
  v_new := 'sales:=n_players*card_cost-round((n_players::numeric*card_cost::numeric*commission_fee::numeric)/10000)::bigint;';
  if position(v_new in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'V147_PATCH_FAILED: SALES_FORMULA_NOT_FOUND';
    end if;
    v_def := replace(v_def,v_old,v_new);
  end if;

  v_old_growth := $old_growth$
    v_initial_pct:=case n_players
      when 2 then 85.00
      when 3 then 80.00
      when 4 then 70.00
      when 5 then 60.00
      else null
    end;
    if v_initial_pct is null then raise exception 'UNSUPPORTED_PLAYER_COUNT'; end if;
    weights:=array[
      v_initial_pct+(100.00-v_initial_pct)*0.25,
      v_initial_pct+(100.00-v_initial_pct)*0.50,
      v_initial_pct+(100.00-v_initial_pct)*0.75,
      100.00
    ];
    initial_prize:=round(sales*v_initial_pct/100)::bigint;
    growth_budget:=greatest(0,sales-initial_prize);
    max_table_pool:=sales;
    reserve:=0;
    growth_added:=0;
$old_growth$;

  v_new_growth := $new_growth$
    -- The net Entry Fee pool (95% of gross) is available from deal start.
    -- Keep four 100% compatibility weights; growth_budget=0 disables old growth.
    v_initial_pct:=100.00;
    weights:=array[100.00,100.00,100.00,100.00];
    initial_prize:=sales;
    growth_budget:=0;
    max_table_pool:=sales;
    reserve:=0;
    growth_added:=0;
$new_growth$;

  if position(v_new_growth in v_def)=0 then
    if position(v_old_growth in v_def)=0 then
      raise exception 'V147_PATCH_FAILED: LEGACY_GROWTH_BLOCK_NOT_FOUND';
    end if;
    v_def := replace(v_def,v_old_growth,v_new_growth);
  end if;

  v_old := '''sales_tetri'',sales';
  v_new := '''gross_entry_fee_tetri'',n_players*card_cost,''sales_tetri'',sales';
  if position(v_new in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'V147_PATCH_FAILED: GROSS_ENTRY_METADATA_NOT_FOUND';
    end if;
    v_def := replace(v_def,v_old,v_new);
  end if;

  v_old := '''commission_total_tetri'',n_players*commission_fee';
  v_new := '''commission_total_tetri'',n_players*card_cost-sales';
  if position(v_new in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'V147_PATCH_FAILED: COMMISSION_METADATA_NOT_FOUND';
    end if;
    v_def := replace(v_def,v_old,v_new);
  end if;

  v_old := '''pot_start_tetri'',initial_prize,';
  v_new := '''pot_start_tetri'',initial_prize,''entry_action_id'',a.id,''entry_fee_gross_tetri'',n_players*card_cost,''platform_commission_tetri'',n_players*card_cost-sales,''prize_pool_tetri'',sales,''commission_rate_bps'',commission_fee,';
  if position(v_new in v_def)=0 then
    if position(v_old in v_def)=0 then
      raise exception 'V147_PATCH_FAILED: FINANCE_STATE_FIELDS_NOT_FOUND';
    end if;
    v_def := replace(v_def,v_old,v_new);
  end if;

  execute v_def;
end;
$patch_qcard_process_action$;

-- 4) Remove the obsolete 0.03 GEL minimum-fee check from the room-creation
--    RPC. The minimum Entry Fee is now simply the selected card cost
--    (card price >= 0.10 GEL and cards per player >= 1).
do $patch_room_creation$
declare
  v_def text;
begin
  v_def := pg_get_functiondef('asix_internal.qcard_create_room_with_wallet(text,numeric,integer,integer,numeric,text,bigint)'::regprocedure);
  if position('v_min_entry<10' in v_def)=0 then
    if position('v_min_entry<3' in v_def)=0 then raise exception 'V147_PATCH_FAILED: LEGACY_ROOM_MINIMUM_CHECK_NOT_FOUND'; end if;
    v_def := replace(v_def,'v_min_entry<3','v_min_entry<10');
    v_def := replace(v_def,'ENTRY_FEE_BELOW_PLATFORM_FEE:MINIMUM=0.03','ENTRY_FEE_BELOW_MINIMUM_CARD_COST:MINIMUM=0.10');
    execute v_def;
  end if;
end;
$patch_room_creation$;

-- 5) Verify that the live server function now has the V147 formula and no
--    fixed 0.03 GEL / player-count growth schedule in its deal-start block.
do $verify_patch$
declare
  v_def text := pg_get_functiondef('public.qcard_process_action(bigint,uuid)'::regprocedure);
begin
  if position('commission_rate_bps::bigint into commission_fee' in v_def)=0 then
    raise exception 'V147_VERIFY_FAILED: RATE_NOT_READ';
  end if;
  if position('sales:=n_players*card_cost-round(' in v_def)=0 then
    raise exception 'V147_VERIFY_FAILED: NET_SALES_FORMULA_MISSING';
  end if;
  if position('v_initial_pct:=100.00;' in v_def)=0 then
    raise exception 'V147_VERIFY_FAILED: OLD_PRIZE_GROWTH_REMAINS';
  end if;
end;
$verify_patch$;

-- 6) Remove completed legacy game history only.
--    Preserve: the currently playing room, waiting lobbies (some have buy-ins),
--    all ASIX wallet balances, deposits/credits, withdrawals/cashouts, and the
--    already-posted platform_commission wallet transactions as accounting history.
--    The associated old commission allocation rows and game money/action history
--    for finished rooms are removed.
do $cleanup_legacy_history$
declare
  v_finished_room_ids uuid[];
  v_wallet_fingerprint_before text;
  v_wallet_fingerprint_after text;
begin
  select md5(coalesce(string_agg(user_id::text||':'||balance_tetri::text,',' order by user_id::text),''))
    into v_wallet_fingerprint_before
  from public.asix_wallets;

  select array_agg(r.id) into v_finished_room_ids
  from public.qcard_rooms r
  join public.qcard_game_state gs on gs.room_id=r.id
  where r.status='finished' and gs.state->>'phase'='finished';

  if coalesce(cardinality(v_finished_room_ids),0)>0 then
    delete from public.asix_platform_commission_ledger
    where room_id=any(v_finished_room_ids);

    update public.qcard_money_ledger m
       set reversal_of_ledger_id=null
     where m.reversal_of_ledger_id in (
       select id from public.qcard_money_ledger where room_id=any(v_finished_room_ids)
     );

    delete from public.qcard_money_ledger
    where room_id=any(v_finished_room_ids);

    -- FK cascades remove qcard_game_state, qcard_actions, qcard_private_hands and qcard_seats.
    -- Wallet transaction room_id is ON DELETE SET NULL, so financial audit rows survive.
    delete from public.qcard_rooms
    where id=any(v_finished_room_ids);
  end if;

  select md5(coalesce(string_agg(user_id::text||':'||balance_tetri::text,',' order by user_id::text),''))
    into v_wallet_fingerprint_after
  from public.asix_wallets;

  if v_wallet_fingerprint_before is distinct from v_wallet_fingerprint_after then
    raise exception 'V147_CLEANUP_CHANGED_WALLET_BALANCES';
  end if;

  if exists (
    select 1 from public.qcard_rooms r
    join public.qcard_game_state gs on gs.room_id=r.id
    where r.status='finished' and gs.state->>'phase'='finished'
  ) then
    raise exception 'V147_CLEANUP_FINISHED_ROOMS_REMAIN';
  end if;
end;
$cleanup_legacy_history$;