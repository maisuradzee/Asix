-- ASIX V157 — preserve the 5% Entry Fee commission and remove prize-pool growth.
-- Apply ONLY to a disposable/staging restore of the complete V154 baseline.
-- This supersedes the Stage18 V155/V156 prize-growth approach.
--
-- Financial rule:
--   gross Entry Fee:                         100%
--   ASIX platform commission:                 5% of gross Entry Fee
--   prize pool:                                95% of gross Entry Fee
-- The commission is calculated once for the whole deal. The post-commission
-- pool is fully placed in the prize pot at deal start; card cuts never increase it.
-- No 85/80/70/60% milestones and no additional 3% reserve are used.
-- Existing wallet commission settlement remains authoritative and unchanged.
-- Historical ledger records are not deleted or rewritten.

begin;

-- Refuse to proceed unless the established 5% GEL commission is enabled and
-- there are no active deals whose state/trigger is being changed.
do $guard$
begin
  if not exists (
    select 1 from public.asix_platform_commission_settings
    where id=1 and enabled=true and currency='GEL'
      and commission_rate_bps=500 and recipient_user_id is not null
  ) then
    raise exception 'V157_EXPECTED_ENABLED_5_PERCENT_GEL_COMMISSION';
  end if;

  if exists (
    select 1 from public.qcard_game_state
    where state->>'phase'='playing'
  ) then
    raise exception 'V157_ACTIVE_DEALS_MUST_BE_SETTLED_FIRST';
  end if;
end
$guard$;

-- 1) Simplify the legacy helper. Its input is already the post-commission amount,
-- so 100% of that input is the prize pool. Keep the JSON keys needed by older
-- readers, but return zero growth and zero reserve.
create or replace function public.qcard_calculate_table_funds(
  p_sales_tetri bigint,
  p_player_count integer
)
returns jsonb
language plpgsql
immutable
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_pool bigint;
begin
  if p_sales_tetri is null or p_sales_tetri < 0 then
    raise exception 'INVALID_SALES_TETRI';
  end if;
  if p_player_count is null or p_player_count < 2 or p_player_count > 5 then
    raise exception 'UNSUPPORTED_PLAYER_COUNT';
  end if;

  v_pool := p_sales_tetri;
  return jsonb_build_object(
    'sales_tetri', p_sales_tetri,
    'player_count', p_player_count,
    'initial_prize_percent', 100.00,
    'growth_targets_percent', '[]'::jsonb,
    'growth_targets_tetri', '[]'::jsonb,
    'initial_prize_tetri', v_pool,
    'growth_budget_tetri', 0,
    'max_table_pool_tetri', v_pool,
    'reserve_tetri', 0,
    'total_allocated_tetri', v_pool,
    'within_sales', true
  );
end;
$function$;

-- 2) Remove the V154 card-cut milestone code and keep the post-commission pool
-- fully funded at the beginning of each deal. The 5% fee calculation itself is
-- intentionally not changed.
do $migration$
declare
  v_def text;
  v_new text;
  v_old text;
  v_replacement text;
  v_count integer;
begin
  v_def := pg_get_functiondef('public.qcard_process_action(bigint,uuid)'::regprocedure);

  -- Refuse to patch a different function version or a source that no longer
  -- follows the verified 5% fee / complete post-fee pool model.
  if position('commission_rate_bps' in v_def)=0
     or position('sales:=n_players*card_cost-round((n_players::numeric*card_cost::numeric*commission_fee::numeric)/10000)::bigint;' in v_def)=0
     or position('initial_prize:=sales;' in v_def)=0
     or position('max_table_pool:=sales;' in v_def)=0 then
    raise exception 'V157_EXPECTED_V154_ENTRY_FEE_5_PERCENT_SOURCE_NOT_FOUND';
  end if;

  v_new := v_def;

  -- Remove the per-action requirement for a four-step growth schedule.
  v_old := $old$  -- Preserve the schedule selected when this deal began.
  if v_phase='playing' then
    select array_agg(e.value::numeric order by e.ordinality)
      into weights
    from jsonb_array_elements_text(coalesce(st->'growth_weights','[]'::jsonb))
      with ordinality e(value,ordinality);
    if weights is null or array_length(weights,1)<>4 then
      raise exception 'INVALID_PRIZE_GROWTH_SCHEDULE';
    end if;
  end if;
$old$;
  v_count := (length(v_new)-length(replace(v_new,v_old,''))) / length(v_old);
  if v_count <> 1 then raise exception 'V157_PHASE_GROWTH_GUARD_MISMATCH:%',v_count; end if;
  v_new := replace(v_new,v_old,'');

  -- Make the already-existing full post-commission allocation explicit and
  -- remove the obsolete player-count percentages and target array.
  v_old := $old$    -- The fee has already been removed from gross card sales above.
    -- Four cumulative growth stages distribute the entire net entry-fee pool.
    v_initial_pct:=100.00;
    weights:=array[100.00,100.00,100.00,100.00];
    initial_prize:=sales;
    growth_budget:=0;
    max_table_pool:=sales;
    reserve:=0;
    growth_added:=0;$old$;
  v_count := (length(v_new)-length(replace(v_new,v_old,''))) / length(v_old);
  if v_count <> 1 then raise exception 'V157_START_ALLOCATION_MISMATCH:%',v_count; end if;
  v_new := replace(v_new,v_old,$new$    -- The 5% ASIX commission has already been removed from gross Entry Fee.
    -- The complete remaining 95% is the prize pool from the start of the deal.
    v_initial_pct:=100.00;
    weights:=array[]::numeric[];
    initial_prize:=sales;
    growth_budget:=0;
    max_table_pool:=sales;
    reserve:=0;
    growth_added:=0;$new$);

  -- Keep the legacy allocation JSON shape compatible while removing its old
  -- target percentages; no growth schedule is stored for this or future deals.
  v_old := $old$'growth_budget_tetri',growth_budget,'max_table_pool_tetri',max_table_pool,'reserve_tetri',0,'growth_targets_percent',to_jsonb(weights)));$old$;
  v_count := (length(v_new)-length(replace(v_new,v_old,''))) / length(v_old);
  if v_count <> 1 then raise exception 'V157_GROWTH_METADATA_MISMATCH:%',v_count; end if;
  v_new := replace(v_new,v_old,$new$'growth_budget_tetri',0,'max_table_pool_tetri',max_table_pool,'reserve_tetri',0));$new$);

  -- Delete every per-card prize-pool increase. successful_cuts remains only as
  -- a gameplay counter and has no financial effect.
  v_old := $old$      growth_stage:=coalesce((st->>'successful_cuts')::integer,0);
      -- Each successful cut advances the pool to the next cumulative
      -- percentage of total entry-fee sales from this deal's stored schedule.
      if growth_stage between 0 and 3 then
        growth_budget:=coalesce((st->>'growth_budget_tetri')::bigint,0);
        growth_added:=coalesce((st->>'growth_added_tetri')::bigint,0);
        growth_target:=round((max_table_pool+coalesce((st->>'growth_reserve_tetri')::bigint,0))*weights[growth_stage+1]/100)::bigint
          -coalesce((st->>'pot_start_tetri')::bigint,0);
        amount:=least(greatest(0,growth_target-growth_added),greatest(0,max_table_pool-pot));
        pot:=pot+amount; growth_added:=growth_added+amount;
      else
        growth_budget:=coalesce((st->>'growth_budget_tetri')::bigint,0);
        growth_added:=coalesce((st->>'growth_added_tetri')::bigint,0);
      end if;$old$;
  v_count := (length(v_new)-length(replace(v_new,v_old,''))) / length(v_old);
  if v_count <> 1 then raise exception 'V157_PER_CARD_GROWTH_BLOCK_MISMATCH:%',v_count; end if;
  v_new := replace(v_new,v_old,$new$      -- The post-commission prize pool was fully funded at deal start.
      -- A successful card cut changes gameplay state only, never the prize amount.
      growth_stage:=coalesce((st->>'successful_cuts')::integer,0);
      growth_budget:=0;
      growth_added:=0;$new$);

  -- Remove the final-settlement release of any unearned growth.
  v_old := $old$      growth_budget:=coalesce((st->>'growth_budget_tetri')::bigint,0);
      growth_added:=coalesce((st->>'growth_added_tetri')::bigint,0);
      -- Release the remaining growth into the played pool at final settlement.
      -- No remainder is diverted to a platform reserve.
      if growth_budget>growth_added then
        insert into public.qcard_money_ledger(
          room_id,user_id,entry_type,amount_tetri,reference_action_id,details
        ) values (
          a.room_id,null,'growth_release',growth_budget-growth_added,a.id,
          jsonb_build_object(
            'source','final_settlement_release',
            'target_percent',100.00,
            'released_growth_tetri',growth_budget-growth_added,
            'net_entry_fee_pool_tetri',max_table_pool
          )
        );
      end if;
      v_winner_payout:=v_total_payout;$old$;
  v_count := (length(v_new)-length(replace(v_new,v_old,''))) / length(v_old);
  if v_count <> 1 then raise exception 'V157_SETTLEMENT_GROWTH_BLOCK_MISMATCH:%',v_count; end if;
  v_new := replace(v_new,v_old,$new$      -- No growth is released at settlement: the complete prize pool was
      -- already funded at deal start. Preserve compatibility counters as zero.
      growth_budget:=0;
      growth_added:=0;
      v_winner_payout:=v_total_payout;$new$);

  -- Preserve deal-level reconciliation references for all player-funded actions.
  v_old := 'a.room_id,p_actor_user_id,''manual_raise'',paid,a.id,';
  v_replacement := 'a.room_id,p_actor_user_id,''manual_raise'',paid,coalesce(nullif(st->>''entry_action_id'','''')::bigint,a.id),';
  v_count := (length(v_new)-length(replace(v_new,v_old,''))) / length(v_old);
  if v_count <> 1 then raise exception 'V157_MANUAL_RAISE_REFERENCE_MISMATCH:%',v_count; end if;
  v_new := replace(v_new,v_old,v_replacement);

  v_old := 'a.room_id,p_actor_user_id,''raise_call'',paid,a.id,';
  v_replacement := 'a.room_id,p_actor_user_id,''raise_call'',paid,coalesce(nullif(st->>''entry_action_id'','''')::bigint,a.id),';
  v_count := (length(v_new)-length(replace(v_new,v_old,''))) / length(v_old);
  if v_count <> 1 then raise exception 'V157_RAISE_CALL_REFERENCE_MISMATCH:%',v_count; end if;
  v_new := replace(v_new,v_old,v_replacement);

  v_old := 'a.room_id,v_refund.key::uuid,''uncalled_bet_refund'',v_refund_amount,a.id,';
  v_replacement := 'a.room_id,v_refund.key::uuid,''uncalled_bet_refund'',v_refund_amount,coalesce(nullif(st->>''entry_action_id'','''')::bigint,a.id),';
  v_count := (length(v_new)-length(replace(v_new,v_old,''))) / length(v_old);
  if v_count <> 1 then raise exception 'V157_UNCALLED_REFUND_REFERENCE_MISMATCH:%',v_count; end if;
  v_new := replace(v_new,v_old,v_replacement);

  v_old := 'a.room_id,winner,''prize_payout'',v_total_payout,a.id,';
  v_replacement := 'a.room_id,winner,''prize_payout'',v_total_payout,coalesce(nullif(st->>''entry_action_id'','''')::bigint,a.id),';
  v_count := (length(v_new)-length(replace(v_new,v_old,''))) / length(v_old);
  if v_count <> 1 then raise exception 'V157_PRIZE_PAYOUT_REFERENCE_MISMATCH:%',v_count; end if;
  v_new := replace(v_new,v_old,v_replacement);

  v_old := 'a.room_id,v_side_payout.key::uuid,''side_pot_payout'',v_refund_amount,a.id,';
  v_replacement := 'a.room_id,v_side_payout.key::uuid,''side_pot_payout'',v_refund_amount,coalesce(nullif(st->>''entry_action_id'','''')::bigint,a.id),';
  v_count := (length(v_new)-length(replace(v_new,v_old,''))) / length(v_old);
  if v_count <> 1 then raise exception 'V157_SIDE_POT_REFERENCE_MISMATCH:%',v_count; end if;
  v_new := replace(v_new,v_old,v_replacement);

  -- Audit the already-settled 5% ASIX commission in the game ledger. This is
  -- NOT a second wallet credit: the existing commission settlement trigger
  -- remains the only wallet-credit path.
  v_old := '      v_winner_payout:=v_total_payout;';
  v_replacement := $insert$
      if coalesce((st->>'platform_commission_tetri')::bigint,0)>0 then
        insert into public.qcard_money_ledger(
          room_id,user_id,entry_type,amount_tetri,reference_action_id,details
        ) values (
          a.room_id,null,'platform_allocation',
          (st->>'platform_commission_tetri')::bigint,
          coalesce(nullif(st->>'entry_action_id','')::bigint,a.id),
          jsonb_build_object(
            'source','settled_asix_platform_commission',
            'commission_rate_bps',coalesce((st->>'commission_rate_bps')::integer,0),
            'gross_entry_fee_tetri',coalesce((st->>'entry_fee_gross_tetri')::bigint,0),
            'deal_completion_action_id',a.id
          )
        );
      end if;
      v_winner_payout:=v_total_payout;$insert$;
  v_count := (length(v_new)-length(replace(v_new,v_old,''))) / length(v_old);
  if v_count <> 1 then raise exception 'V157_PLATFORM_ALLOCATION_ANCHOR_MISMATCH:%',v_count; end if;
  v_new := replace(v_new,v_old,v_replacement);

  execute v_new;
end
$migration$;

-- 3) Keep the independent 0.30 GEL minimum and zero-credit wallet hardening. with V149's 0.30 GEL table-buy-in minimum.
-- Create-room and join-public-room already enforce 30 tetri; this path did not.
do $migration$
declare
  v_def text;
  v_new text;
  v_old text;
  v_count integer;
begin
  v_def := pg_get_functiondef('asix_internal.qcard_set_entry_stack(uuid,bigint)'::regprocedure);
  v_old := 'if p_amount_tetri is null or p_amount_tetri < 1 then raise exception ''INVALID_ENTRY_AMOUNT''; end if;';
  v_count := (length(v_def)-length(replace(v_def,v_old,''))) / length(v_old);
  if v_count <> 1 then raise exception 'V155_STACK_MINIMUM_PATTERN_MISMATCH:%',v_count; end if;
  v_new := replace(v_def,v_old,'if p_amount_tetri is null or p_amount_tetri < 30 then raise exception ''TABLE_BUYIN_MINIMUM_0_30''; end if;');

  v_old := 'v_min_entry_tetri := round(v_room.card_price*100)::bigint*v_room.cards_per_player;';
  v_count := (length(v_new)-length(replace(v_new,v_old,''))) / length(v_old);
  if v_count <> 1 then raise exception 'V155_STACK_CALC_MINIMUM_PATTERN_MISMATCH:%',v_count; end if;
  v_new := replace(v_new,v_old,'v_min_entry_tetri := 30;');
  execute v_new;
end
$migration$;

-- 4) Stop issuing 10,000 GEL demo credit to new signups. Existing balances and
-- historical transactions are deliberately untouched by this migration.
create or replace function public.asix_wallet_create_for_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $function$
begin
  insert into public.asix_wallets(user_id,balance_tetri)
  values(new.id,0)
  on conflict(user_id) do nothing;
  return new;
end;
$function$;


-- 5) Remove the legacy demo-credit fallback from the wallet-read RPC as well.
-- Without this block, accounts missing a wallet row could still receive
-- 10,000 GEL merely by opening the wallet screen after the signup trigger was fixed.
do $migration$
declare
  v_def text;
  v_old text;
  v_count integer;
begin
  v_def := pg_get_functiondef('asix_internal.asix_wallet_get_balance()'::regprocedure);
  v_old := 'values(v_uid,1000000)';
  v_count := (length(v_def)-length(replace(v_def,v_old,''))) / length(v_old);
  if v_count <> 1
     or position('demo_initial_balance' in v_def)=0
     or position('demo_balance'',true' in v_def)=0 then
    raise exception 'V155_WALLET_READ_DEMO_GUARD_MISMATCH:%',v_count;
  end if;

  execute $function$
    CREATE OR REPLACE FUNCTION asix_internal.asix_wallet_get_balance()
    RETURNS jsonb
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'auth'
    AS $body$
    declare
      v_uid uuid := auth.uid();
      v_balance bigint := 0;
      v_anonymous boolean;
    begin
      if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
      select coalesce(is_anonymous,true) into v_anonymous
      from auth.users where id=v_uid;
      if not found then raise exception 'USER_NOT_FOUND'; end if;

      insert into public.asix_wallets(user_id,balance_tetri)
      values(v_uid,0)
      on conflict(user_id) do nothing;

      select coalesce(balance_tetri,0) into v_balance
      from public.asix_wallets where user_id=v_uid;

      return jsonb_build_object(
        'user_id',v_uid,
        'balance_tetri',coalesce(v_balance,0),
        'is_anonymous',v_anonymous,
        'account_linked',not v_anonymous,
        'wallet_enabled',not v_anonymous,
        'demo_balance',false
      );
    end;
    $body$;
  $function$;
end
$migration$;


-- 6) The old audit trigger exists only to record per-cut growth releases.
-- Remove it and its dedicated trigger function; do not delete historical ledger
-- rows that were recorded before this rule was retired.
drop trigger if exists qcard_audit_growth_release on public.qcard_game_state;
drop function if exists public.qcard_audit_growth_release();

commit;