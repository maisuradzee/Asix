-- Current function definitions exported from connected ASIX database.
-- Snapshot only; not original migration history.

-- asix_internal.asix_wallet_cashout_room(p_room_id uuid)
CREATE OR REPLACE FUNCTION asix_internal.asix_wallet_cashout_room(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_room public.qcard_rooms%rowtype;
  v_seat public.qcard_seats%rowtype;
  v_result jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_room from public.qcard_rooms where id=p_room_id for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  select * into v_seat from public.qcard_seats
  where room_id=p_room_id and user_id=v_uid for update;
  if not found then raise exception 'NOT_A_ROOM_MEMBER'; end if;
  if v_seat.wallet_entry_key is null then raise exception 'WALLET_BUYIN_NOT_FOUND'; end if;

  if v_room.status='playing' then
    update public.qcard_seats set wallet_cashout_requested=true,
      is_connected=false,last_seen_at=now()
    where room_id=p_room_id and user_id=v_uid;
    return jsonb_build_object('ok',true,'pending',true,
      'message','CASHOUT_AFTER_CURRENT_DEAL');
  end if;

  v_result := public.asix_wallet_settle_cashout(p_room_id,v_uid);
  return v_result;
end;
$function$
;

-- asix_internal.asix_wallet_get_balance()
CREATE OR REPLACE FUNCTION asix_internal.asix_wallet_get_balance()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare v_uid uuid := auth.uid(); v_balance bigint := 0; v_anonymous boolean; v_inserted integer := 0; v_key text;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select coalesce(is_anonymous,true) into v_anonymous from auth.users where id=v_uid;
  if not found then raise exception 'USER_NOT_FOUND'; end if;
  v_key := 'demo-start-10000:' || v_uid::text;
  insert into public.asix_wallets(user_id,balance_tetri) values(v_uid,1000000)
  on conflict(user_id) do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted > 0 then
    insert into public.asix_wallet_transactions(user_id,transaction_type,amount_tetri,balance_after_tetri,idempotency_key,description,metadata)
    values(v_uid,'credit',1000000,1000000,v_key,'საწყისი დემო ბალანსი — 10,000.00 ₾',
      jsonb_build_object('kind','demo_initial_balance','currency','GEL','demo_only',true))
    on conflict(idempotency_key) do nothing;
  end if;
  select balance_tetri into v_balance from public.asix_wallets where user_id=v_uid;
  return jsonb_build_object('user_id',v_uid,'balance_tetri',coalesce(v_balance,0),
    'is_anonymous',v_anonymous,'account_linked',not v_anonymous,'wallet_enabled',not v_anonymous,'demo_balance',true);
end;
$function$
;

-- asix_internal.asix_wallet_get_transactions(p_limit integer)
CREATE OR REPLACE FUNCTION asix_internal.asix_wallet_get_transactions(p_limit integer DEFAULT 20)
 RETURNS TABLE(id bigint, transaction_type text, amount_tetri bigint, balance_after_tetri bigint, room_id uuid, description text, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
  select t.id,t.transaction_type,t.amount_tetri,t.balance_after_tetri,
         t.room_id,t.description,t.created_at
  from public.asix_wallet_transactions t
  join auth.users u on u.id=t.user_id
  where t.user_id=auth.uid()
    and coalesce(u.is_anonymous,true)=false
  order by t.id desc
  limit greatest(1,least(coalesce(p_limit,20),100));
$function$
;

-- asix_internal.qcard_asix_heartbeat_bundle(p_room_id uuid)
CREATE OR REPLACE FUNCTION asix_internal.qcard_asix_heartbeat_bundle(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_is_anonymous boolean;
  v_heartbeat jsonb;
  v_recovery jsonb;
  v_disconnect_timeout jsonb;
  v_turn_timeout jsonb;
  v_timeout_error text;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select u.is_anonymous into v_is_anonymous
  from auth.users u
  where u.id = v_uid;

  if not found or coalesce(v_is_anonymous, true) then
    raise exception 'ACCOUNT_LINK_REQUIRED';
  end if;

  -- IMPORTANT: heartbeat must acquire the room/game-state locks before
  -- updating qcard_seats. Game actions use room -> game_state -> seat order.
  -- Updating the seat first caused a real deadlock with qcard_process_action.
  v_heartbeat := public.qcard_server_heartbeat(p_room_id, v_uid);

  -- Preserve the prior presence behaviour, but only after the room and
  -- game-state locks have been acquired in the common order.
  update public.qcard_seats
  set is_connected = true,
      last_seen_at = now()
  where room_id = p_room_id
    and user_id = v_uid;

  if not found then
    raise exception 'NOT_A_ROOM_MEMBER';
  end if;

  if coalesce((v_heartbeat->>'cancelled')::boolean, false) then
    return jsonb_build_object(
      'ok', true,
      'heartbeat', v_heartbeat,
      'recovery', jsonb_build_object('ok', true, 'recovered', false, 'skipped', true),
      'timeout', jsonb_build_object('ok', true, 'processed', false, 'skipped', true),
      'turn_timeout', jsonb_build_object('ok', true, 'processed', false, 'skipped', true)
    );
  end if;

  v_recovery := public.qcard_recover_pending_action(p_room_id, v_uid);

  begin
    v_disconnect_timeout := public.qcard_process_disconnect_timeouts(p_room_id, v_uid);
  exception when others then
    get stacked diagnostics v_timeout_error = message_text;
    v_disconnect_timeout := jsonb_build_object('ok', false, 'error', v_timeout_error);
  end;

  begin
    v_turn_timeout := public.qcard_process_turn_timeout(p_room_id, v_uid);
  exception when others then
    get stacked diagnostics v_timeout_error = message_text;
    v_turn_timeout := jsonb_build_object('ok', false, 'error', v_timeout_error);
  end;

  return jsonb_build_object(
    'ok', true,
    'heartbeat', v_heartbeat,
    'recovery', v_recovery,
    'timeout', v_disconnect_timeout,
    'turn_timeout', v_turn_timeout
  );
end;
$function$
;

-- asix_internal.qcard_create_room_with_wallet(p_name text, p_card_price numeric, p_cards_per_player integer, p_max_players integer, p_max_bet numeric, p_display_name text, p_amount_tetri bigint)
CREATE OR REPLACE FUNCTION asix_internal.qcard_create_room_with_wallet(p_name text DEFAULT 'ASIX CLASSIC'::text, p_card_price numeric DEFAULT 0.10, p_cards_per_player integer DEFAULT 3, p_max_players integer DEFAULT 5, p_max_bet numeric DEFAULT 20.00, p_display_name text DEFAULT 'Player'::text, p_amount_tetri bigint DEFAULT 10000)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
AS $function$
declare
 v_uid uuid := auth.uid(); v_wallet public.asix_wallets%rowtype; v_room public.qcard_rooms%rowtype;
 v_code text; v_name text; v_card_price numeric(10,2); v_max_bet numeric(10,2);
 v_min_entry bigint; v_buyin_tetri bigint := p_amount_tetri; v_buyin_key text; v_is_anonymous boolean;
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select coalesce(is_anonymous,false) into v_is_anonymous from auth.users where id=v_uid;
 if coalesce(v_is_anonymous,true) then raise exception 'ACCOUNT_LINK_REQUIRED'; end if;
 if p_amount_tetri is null or p_amount_tetri < 30 then raise exception 'TABLE_BUYIN_MINIMUM_0_30'; end if;
if p_card_price is null or p_cards_per_player is null or p_max_players is null or p_max_bet is null then raise exception 'INVALID_ROOM_SETTINGS: NULL_SETTING'; end if;
 if p_card_price < 0.10 or p_card_price > 10.00 or p_card_price <> round(p_card_price,2) then raise exception 'CARD_PRICE_MINIMUM_0_10_MAXIMUM_10_00'; end if;
 v_card_price:=p_card_price::numeric(10,2); v_max_bet:=round(p_max_bet,2);
 if p_cards_per_player not between 1 and 5 then raise exception 'INVALID_ROOM_SETTINGS: CARDS_PER_PLAYER_1_TO_5'; end if;
 if p_max_players not between 2 and 5 then raise exception 'INVALID_ROOM_SETTINGS: MAX_PLAYERS_2_TO_5'; end if;
 if v_max_bet<=0 then raise exception 'INVALID_ROOM_SETTINGS: MAX_BET_MUST_BE_POSITIVE'; end if;
 v_min_entry:=30;
 insert into public.asix_wallets(user_id) values(v_uid) on conflict(user_id) do nothing;
 select * into v_wallet from public.asix_wallets where user_id=v_uid for update;
 if coalesce(v_wallet.balance_tetri,0)<v_buyin_tetri then raise exception 'WALLET_INSUFFICIENT_BALANCE:AVAILABLE=%:REQUIRED=%',coalesce(v_wallet.balance_tetri,0),v_buyin_tetri; end if;
 if v_buyin_tetri<v_min_entry then raise exception 'TABLE_BUYIN_BELOW_CARD_COST'; end if;
 v_name:=coalesce(nullif(trim(p_name),''),'ASIX CLASSIC');
 loop
   v_code:=upper(substr(encode(gen_random_bytes(5),'hex'),1,6));
   exit when not exists(select 1 from public.qcard_rooms where room_code=v_code);
 end loop;
 insert into public.qcard_rooms(room_code,name,host_user_id,card_price,cards_per_player,max_players,max_bet)
 values(v_code,v_name,v_uid,v_card_price,p_cards_per_player,p_max_players,v_max_bet) returning * into v_room;
 update public.asix_wallets set balance_tetri=balance_tetri-v_buyin_tetri,updated_at=now()
 where user_id=v_uid returning * into v_wallet;
 v_buyin_key:='room-buyin:'||v_room.id::text||':'||v_uid::text||':'||gen_random_uuid()::text;
 insert into public.qcard_seats(room_id,user_id,display_name,seat_no,stack_tetri,entry_stack_tetri,entry_set_at,is_connected,last_seen_at,wallet_entry_key)
 values(v_room.id,v_uid,left(coalesce(nullif(trim(p_display_name),''),'Player'),32),1,v_buyin_tetri,v_buyin_tetri,now(),true,now(),v_buyin_key);
 insert into public.asix_wallet_transactions(user_id,transaction_type,amount_tetri,balance_after_tetri,room_id,idempotency_key,description,metadata)
 values(v_uid,'table_buyin',v_buyin_tetri,v_wallet.balance_tetri,v_room.id,v_buyin_key,'ASIX მაგიდაზე საწყისი თანხის გადატანა',
   jsonb_build_object('card_price',v_room.card_price,'cards_per_player',v_room.cards_per_player,'created_room',true,'custom_table_buyin_tetri',v_buyin_tetri,'full_wallet_transfer',false));
 insert into public.qcard_game_state(room_id) values(v_room.id);
 return jsonb_build_object('room_id',v_room.id,'room_code',v_room.room_code,'seat_no',1,'status',v_room.status,
   'wallet_balance_tetri',v_wallet.balance_tetri,'stack_tetri',v_buyin_tetri,'buyin_tetri',v_buyin_tetri,'min_entry_tetri',v_min_entry,
   'name',v_room.name,'max_players',v_room.max_players,'card_price',v_room.card_price,'cards_per_player',v_room.cards_per_player,'max_bet',v_room.max_bet);
end;
$function$
;

-- asix_internal.qcard_get_my_deal_history(p_requester_user_id uuid, p_limit integer, p_before_id bigint)
CREATE OR REPLACE FUNCTION asix_internal.qcard_get_my_deal_history(p_requester_user_id uuid, p_limit integer DEFAULT 30, p_before_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
 v_result jsonb;
begin
 if auth.uid() is null or auth.uid() is distinct from p_requester_user_id then
   raise exception 'AUTH_USER_MISMATCH';
 end if;

 select coalesce(jsonb_agg(item order by history_id desc),'[]'::jsonb)
 into v_result
 from (
   select h.id as history_id,
     jsonb_build_object(
       'id',h.id,
       'room_id',h.room_id,
       'room_code',h.room_code,
       'room_name',h.room_name,
       'deal_number',h.deal_number,
       'started_at',h.started_at,
       'completed_at',h.completed_at,
       'final_phase',h.final_phase,
       'winner_user_id',h.winner_user_id,
       'winner_name',h.winner_name,
       'state_snapshot',h.state_snapshot,
       'room_settings',h.room_settings,
       'players',(
         select coalesce(jsonb_agg(jsonb_build_object(
           'user_id',p.user_id,
           'display_name',p.display_name,
           'seat_no',p.seat_no,
           'folded',p.folded,
           'all_in',p.all_in,
           'cards_count',p.cards_count,
           'stack_tetri_after_deal',p.stack_tetri_after_deal,
           'is_winner',p.is_winner
         ) order by p.seat_no),'[]'::jsonb)
         from public.qcard_deal_history_players p
         where p.deal_history_id=h.id
       )
     ) as item
   from public.qcard_deal_history h
   where (p_before_id is null or h.id<p_before_id)
     and exists(
       select 1 from public.qcard_deal_history_players mine
       where mine.deal_history_id=h.id and mine.user_id=p_requester_user_id
     )
   order by h.id desc
   limit greatest(1,least(coalesce(p_limit,30),100))
 ) page;

 return jsonb_build_object('ok',true,'items',v_result);
end;
$function$
;

-- asix_internal.qcard_is_room_member(p_room_id uuid)
CREATE OR REPLACE FUNCTION asix_internal.qcard_is_room_member(p_room_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
  select exists(select 1 from public.qcard_seats s where s.room_id=p_room_id and s.user_id=auth.uid());
$function$
;

-- asix_internal.qcard_join_public_room(p_room_id uuid, p_display_name text, p_amount_tetri bigint)
CREATE OR REPLACE FUNCTION asix_internal.qcard_join_public_room(p_room_id uuid, p_display_name text, p_amount_tetri bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
AS $function$
declare
 v_uid uuid := auth.uid(); v_room public.qcard_rooms%rowtype; v_seat public.qcard_seats%rowtype;
 v_wallet public.asix_wallets%rowtype; v_seat_no smallint; v_min_entry_tetri bigint;
 v_buyin_tetri bigint := p_amount_tetri; v_buyin_key text; v_is_anonymous boolean;
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
if p_amount_tetri is null or p_amount_tetri < 30 then raise exception 'TABLE_BUYIN_MINIMUM_0_30'; end if;
 select coalesce(is_anonymous,false) into v_is_anonymous from auth.users where id=v_uid;
 if coalesce(v_is_anonymous,true) then raise exception 'ACCOUNT_LINK_REQUIRED'; end if;
 select * into v_room from public.qcard_rooms where id=p_room_id for update;
 if not found then raise exception 'ROOM_NOT_FOUND'; end if;
 v_min_entry_tetri:=30;
 select * into v_seat from public.qcard_seats where room_id=p_room_id and user_id=v_uid for update;
 if found then
   if v_seat.entry_stack_tetri is null then
     if v_room.status not in ('waiting','playing') then raise exception 'ENTRY_CLOSED'; end if;
     insert into public.asix_wallets(user_id) values(v_uid) on conflict(user_id) do nothing;
     select * into v_wallet from public.asix_wallets where user_id=v_uid for update;
     if coalesce(v_wallet.balance_tetri,0)<v_buyin_tetri then raise exception 'WALLET_INSUFFICIENT_BALANCE:AVAILABLE=%:REQUIRED=%',coalesce(v_wallet.balance_tetri,0),v_buyin_tetri; end if;
     if v_buyin_tetri<v_min_entry_tetri then raise exception 'TABLE_BUYIN_BELOW_CARD_COST'; end if;
     update public.asix_wallets set balance_tetri=balance_tetri-v_buyin_tetri,updated_at=now() where user_id=v_uid returning * into v_wallet;
     v_buyin_key:='room-buyin:'||p_room_id::text||':'||v_uid::text||':'||gen_random_uuid()::text;
     insert into public.asix_wallet_transactions(user_id,transaction_type,amount_tetri,balance_after_tetri,room_id,idempotency_key,description,metadata)
     values(v_uid,'table_buyin',v_buyin_tetri,v_wallet.balance_tetri,p_room_id,v_buyin_key,'ASIX მაგიდაზე საწყისი თანხის გადატანა',
       jsonb_build_object('card_price',v_room.card_price,'cards_per_player',v_room.cards_per_player,'custom_table_buyin_tetri',v_buyin_tetri,'full_wallet_transfer',false));
     update public.qcard_seats set stack_tetri=v_buyin_tetri,entry_stack_tetri=v_buyin_tetri,entry_set_at=now(),is_connected=true,last_seen_at=now(),wallet_entry_key=v_buyin_key
     where room_id=p_room_id and user_id=v_uid;
   else
     if v_seat.wallet_entry_key is null then raise exception 'LEGACY_ROOM_NOT_WALLET_BACKED'; end if;
     update public.qcard_seats set is_connected=true,last_seen_at=now() where room_id=p_room_id and user_id=v_uid;
   end if;
   return jsonb_build_object('room_id',v_room.id,'room_code',v_room.room_code,'seat_no',v_seat.seat_no,'rejoined',true,
     'min_entry_tetri',v_min_entry_tetri,'name',v_room.name,'max_players',v_room.max_players,'card_price',v_room.card_price,
     'cards_per_player',v_room.cards_per_player,'max_bet',v_room.max_bet,'status',v_room.status);
 end if;
 if v_room.status not in ('waiting','playing') then
   if v_room.status in ('finished','cancelled') then raise exception 'ROOM_CLOSED'; end if;
   raise exception 'ENTRY_CLOSED';
 end if;
 select gs.seat_no into v_seat_no from generate_series(1,v_room.max_players) gs(seat_no)
 where not exists(select 1 from public.qcard_seats s where s.room_id=p_room_id and s.seat_no=gs.seat_no)
 order by gs.seat_no limit 1;
 if v_seat_no is null then raise exception 'ROOM_FULL'; end if;
 insert into public.asix_wallets(user_id) values(v_uid) on conflict(user_id) do nothing;
 select * into v_wallet from public.asix_wallets where user_id=v_uid for update;
 if coalesce(v_wallet.balance_tetri,0)<v_buyin_tetri then raise exception 'WALLET_INSUFFICIENT_BALANCE:AVAILABLE=%:REQUIRED=%',coalesce(v_wallet.balance_tetri,0),v_buyin_tetri; end if;
 if v_buyin_tetri<v_min_entry_tetri then raise exception 'TABLE_BUYIN_BELOW_CARD_COST'; end if;
 update public.asix_wallets set balance_tetri=balance_tetri-v_buyin_tetri,updated_at=now() where user_id=v_uid returning * into v_wallet;
 v_buyin_key:='room-buyin:'||p_room_id::text||':'||v_uid::text||':'||gen_random_uuid()::text;
 insert into public.qcard_seats(room_id,user_id,display_name,seat_no,stack_tetri,entry_stack_tetri,entry_set_at,is_connected,last_seen_at,wallet_entry_key)
 values(p_room_id,v_uid,left(coalesce(nullif(trim(p_display_name),''),'Player'),32),v_seat_no,v_buyin_tetri,v_buyin_tetri,now(),true,now(),v_buyin_key);
 insert into public.asix_wallet_transactions(user_id,transaction_type,amount_tetri,balance_after_tetri,room_id,idempotency_key,description,metadata)
 values(v_uid,'table_buyin',v_buyin_tetri,v_wallet.balance_tetri,p_room_id,v_buyin_key,'ASIX მაგიდაზე საწყისი თანხის გადატანა',
   jsonb_build_object('card_price',v_room.card_price,'cards_per_player',v_room.cards_per_player,'custom_table_buyin_tetri',v_buyin_tetri,
     'full_wallet_transfer',false,'late_join',v_room.status='playing'));
 return jsonb_build_object('room_id',v_room.id,'room_code',v_room.room_code,'seat_no',v_seat_no,'rejoined',false,
   'late_join',v_room.status='playing','message',case when v_room.status='playing' then 'JOINED_NEXT_DEAL' else 'JOINED_WAITING_ROOM' end,
   'min_entry_tetri',v_min_entry_tetri,'wallet_balance_tetri',v_wallet.balance_tetri,'stack_tetri',v_buyin_tetri,'buyin_tetri',v_buyin_tetri,
   'name',v_room.name,'max_players',v_room.max_players,'card_price',v_room.card_price,'cards_per_player',v_room.cards_per_player,
   'max_bet',v_room.max_bet,'status',v_room.status);
end;
$function$
;

-- asix_internal.qcard_join_room_with_wallet(p_room_code text, p_display_name text, p_amount_tetri bigint)
CREATE OR REPLACE FUNCTION asix_internal.qcard_join_room_with_wallet(p_room_code text, p_display_name text DEFAULT 'Player'::text, p_amount_tetri bigint DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_room_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select id into v_room_id from public.qcard_rooms
  where room_code=upper(trim(p_room_code));
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  return public.qcard_join_public_room(v_room_id,p_display_name,p_amount_tetri);
end;
$function$
;

-- asix_internal.qcard_list_public_rooms()
CREATE OR REPLACE FUNCTION asix_internal.qcard_list_public_rooms()
 RETURNS TABLE(room_id uuid, name text, status text, max_players smallint, online_players integer, occupied_players integer, card_price numeric, cards_per_player smallint, max_bet numeric, min_entry_tetri bigint, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  select r.id,r.name,r.status,r.max_players,
    count(s.user_id) filter(where s.is_connected=true and s.last_seen_at>=now()-interval '12 seconds')::integer,
    count(s.user_id)::integer,r.card_price,r.cards_per_player,r.max_bet,
    (round(r.card_price*100)::bigint*r.cards_per_player)::bigint,r.created_at
  from public.qcard_rooms r
  left join public.qcard_seats s on s.room_id=r.id
  where r.status in ('waiting','playing')
    and exists(select 1 from public.qcard_seats live where live.room_id=r.id
      and live.wallet_entry_key is not null and live.is_connected=true
      and live.last_seen_at>=now()-interval '12 seconds')
  group by r.id order by r.created_at desc limit 100;
$function$
;

-- asix_internal.qcard_process_turn_timeout(p_room_id uuid, p_requester_user_id uuid)
CREATE OR REPLACE FUNCTION asix_internal.qcard_process_turn_timeout(p_room_id uuid, p_requester_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  gs public.qcard_game_state%rowtype;
  target_uid uuid;
  target_all_in boolean := false;
  started_at timestamptz;
  action_id bigint;
  result_json jsonb;
  v_is_anonymous boolean;
begin
  if auth.uid() is null or p_requester_user_id is distinct from auth.uid() then
    raise exception 'REQUESTER_MISMATCH';
  end if;
  select u.is_anonymous into v_is_anonymous from auth.users u where u.id=auth.uid();
  if not found or coalesce(v_is_anonymous,true) then raise exception 'ACCOUNT_LINK_REQUIRED'; end if;
  if not exists(select 1 from public.qcard_seats where room_id=p_room_id and user_id=auth.uid()) then
    raise exception 'NOT_A_ROOM_MEMBER';
  end if;

  perform 1 from public.qcard_rooms where id=p_room_id for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  select * into gs from public.qcard_game_state where room_id=p_room_id for update;
  if not found then raise exception 'GAME_STATE_NOT_FOUND'; end if;
  if coalesce(gs.state->>'phase','') <> 'playing' then
    return jsonb_build_object('ok',true,'processed',false,'reason','NOT_PLAYING');
  end if;

  target_uid := nullif(gs.state->>'current_turn_user_id','')::uuid;
  select coalesce((p.value->>'all_in')::boolean,false)
    into target_all_in
  from jsonb_array_elements(coalesce(gs.state->'players','[]'::jsonb)) p(value)
  where p.value->>'user_id'=target_uid::text;
  target_all_in := coalesce(target_all_in,false);
  if target_uid is null then
    return jsonb_build_object('ok',true,'processed',false,'reason','NO_CURRENT_ACTOR');
  end if;
  begin
    started_at := nullif(gs.state->>'turn_started_at','')::timestamptz;
  exception when others then
    started_at := null;
  end;
  if started_at is null then
    update public.qcard_game_state
      set state=jsonb_set(state,'{turn_started_at}',to_jsonb(now()),true)
      where room_id=p_room_id;
    return jsonb_build_object('ok',true,'processed',false,'reason','TURN_CLOCK_INITIALIZED');
  end if;
  if started_at > now() - interval '9 seconds' then
    return jsonb_build_object('ok',true,'processed',false,'reason','TURN_TIME_REMAINING');
  end if;

  insert into public.qcard_actions(room_id,actor_user_id,action_type,payload,expected_version)
  values(p_room_id,target_uid,case when target_all_in then 'timeout_skip' else 'fold' end,
    jsonb_build_object('auto_turn_timeout',true,'timeout_seconds',9,'all_in_skip',target_all_in),gs.version)
  returning id into action_id;

  result_json := public.qcard_process_action(action_id,target_uid);
  return jsonb_build_object(
    'ok',true,'processed',true,'timed_out_user_id',target_uid,
    'action_id',action_id,'action',case when target_all_in then 'timeout_skip' else 'fold' end,'result',result_json
  );
end;
$function$
;

-- asix_internal.qcard_remove_permanent_player(p_target_user_id uuid)
CREATE OR REPLACE FUNCTION asix_internal.qcard_remove_permanent_player(p_target_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_room public.qcard_rooms%rowtype;
  v_phase text;
  v_deleted integer := 0;
  v_is_anonymous boolean;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select u.is_anonymous into v_is_anonymous from auth.users u where u.id=v_uid;
  if not found or coalesce(v_is_anonymous,true) then raise exception 'ACCOUNT_LINK_REQUIRED'; end if;
  if p_target_user_id is null then raise exception 'TARGET_REQUIRED'; end if;

  select * into v_room from public.qcard_rooms
  where room_code='ASIX01' for update;
  if not found then raise exception 'PERMANENT_ROOM_NOT_FOUND'; end if;
  if v_room.host_user_id <> v_uid then raise exception 'HOST_ONLY'; end if;
  if p_target_user_id=v_uid then raise exception 'CANNOT_REMOVE_HOST'; end if;

  select coalesce(state->>'phase','waiting') into v_phase
  from public.qcard_game_state where room_id=v_room.id for update;
  if v_phase='playing' then raise exception 'GAME_IN_PROGRESS'; end if;

  delete from public.qcard_private_hands where room_id=v_room.id and user_id=p_target_user_id;
  delete from public.qcard_seats where room_id=v_room.id and user_id=p_target_user_id;
  get diagnostics v_deleted=row_count;
  if v_deleted=0 then return jsonb_build_object('ok',false,'error','PLAYER_NOT_FOUND'); end if;
  return jsonb_build_object('ok',true,'removed_user_id',p_target_user_id);
end;
$function$
;

-- asix_internal.qcard_set_entry_stack(p_room_id uuid, p_amount_tetri bigint)
CREATE OR REPLACE FUNCTION asix_internal.qcard_set_entry_stack(p_room_id uuid, p_amount_tetri bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_room public.qcard_rooms%rowtype;
  v_seat public.qcard_seats%rowtype;
  v_wallet public.asix_wallets%rowtype;
  v_min_entry_tetri bigint;
  v_buyin_key text;
  v_is_anonymous boolean;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select coalesce(is_anonymous,false) into v_is_anonymous from auth.users where id=v_uid;
  if coalesce(v_is_anonymous,true) then raise exception 'ACCOUNT_LINK_REQUIRED'; end if;
  if p_amount_tetri is null or p_amount_tetri < 1 then raise exception 'INVALID_ENTRY_AMOUNT'; end if;
  select * into v_room from public.qcard_rooms where id=p_room_id for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  select * into v_seat from public.qcard_seats where room_id=p_room_id and user_id=v_uid for update;
  if not found then raise exception 'NOT_A_ROOM_MEMBER'; end if;
  if v_seat.entry_stack_tetri is not null then
    if v_seat.wallet_entry_key is null then raise exception 'LEGACY_ROOM_NOT_WALLET_BACKED'; end if;
    return jsonb_build_object('ok',true,'existing',true,'stack_tetri',v_seat.stack_tetri,
      'entry_stack_tetri',v_seat.entry_stack_tetri);
  end if;
  v_min_entry_tetri := round(v_room.card_price*100)::bigint*v_room.cards_per_player;
  if p_amount_tetri < v_min_entry_tetri then raise exception 'INSUFFICIENT_ENTRY_BALANCE:MINIMUM=%',v_min_entry_tetri; end if;
  if v_room.status <> 'waiting' then raise exception 'ENTRY_CLOSED'; end if;
  insert into public.asix_wallets(user_id) values(v_uid) on conflict(user_id) do nothing;
  select * into v_wallet from public.asix_wallets where user_id=v_uid for update;
  if v_wallet.balance_tetri < p_amount_tetri then
    raise exception 'WALLET_INSUFFICIENT_BALANCE:AVAILABLE=%:REQUIRED=%',v_wallet.balance_tetri,p_amount_tetri;
  end if;
  update public.asix_wallets set balance_tetri=balance_tetri-p_amount_tetri,updated_at=now()
  where user_id=v_uid returning * into v_wallet;
  v_buyin_key := 'room-buyin:'||p_room_id::text||':'||v_uid::text||':'||gen_random_uuid()::text;
  insert into public.asix_wallet_transactions(user_id,transaction_type,amount_tetri,balance_after_tetri,
    room_id,idempotency_key,description,metadata)
  values(v_uid,'table_buyin',p_amount_tetri,v_wallet.balance_tetri,p_room_id,v_buyin_key,
    'საწყისი თანხის გადატანა ASIX მაგიდაზე',
    jsonb_build_object('card_price',v_room.card_price,'cards_per_player',v_room.cards_per_player));
  update public.qcard_seats set stack_tetri=p_amount_tetri,entry_stack_tetri=p_amount_tetri,
    entry_set_at=now(),last_seen_at=now(),is_connected=true,wallet_entry_key=v_buyin_key
  where room_id=p_room_id and user_id=v_uid;
  return jsonb_build_object('ok',true,'existing',false,'stack_tetri',p_amount_tetri,
    'entry_stack_tetri',p_amount_tetri,'wallet_balance_tetri',v_wallet.balance_tetri,
    'min_entry_tetri',v_min_entry_tetri);
end;
$function$
;

-- asix_internal.qcard_set_presence(p_room_id uuid, p_connected boolean)
CREATE OR REPLACE FUNCTION asix_internal.qcard_set_presence(p_room_id uuid, p_connected boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_is_anonymous boolean;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select u.is_anonymous into v_is_anonymous from auth.users u where u.id=v_uid;
  if not found or coalesce(v_is_anonymous,true) then raise exception 'ACCOUNT_LINK_REQUIRED'; end if;
  update public.qcard_seats set is_connected=p_connected,last_seen_at=now()
   where room_id=p_room_id and user_id=v_uid;
  if not found then raise exception 'NOT_A_ROOM_MEMBER'; end if;
end;
$function$
;

-- asix_internal.qcard_submit_action(p_room_id uuid, p_action_type text, p_payload jsonb, p_expected_version bigint)
CREATE OR REPLACE FUNCTION asix_internal.qcard_submit_action(p_room_id uuid, p_action_type text, p_payload jsonb DEFAULT '{}'::jsonb, p_expected_version bigint DEFAULT 0)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_version bigint;
  v_current_turn uuid;
  v_action_id bigint;
  v_player jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_action_type not in ('ready','start','redeal','play_card','fold','raise','call','leave','reconnect') then
    raise exception 'INVALID_ACTION';
  end if;
  -- Serialize validation + action insertion with the same room lock
  -- used by qcard_process_action and heartbeat recovery.
  perform 1 from public.qcard_rooms where id=p_room_id for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;

  if not exists(select 1 from public.qcard_seats where room_id=p_room_id and user_id=v_uid) then
    raise exception 'NOT_A_ROOM_MEMBER';
  end if;
  select g.version,nullif(g.state->>'current_turn_user_id','')::uuid,
         (select x.value from jsonb_array_elements(coalesce(g.state->'players','[]'::jsonb)) x(value) where x.value->>'user_id'=v_uid::text limit 1)
    into v_version,v_current_turn,v_player
  from public.qcard_game_state g where g.room_id=p_room_id;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  if v_version<>p_expected_version then raise exception 'STALE_GAME_STATE'; end if;
  if p_action_type in ('play_card','fold','raise','call') and v_current_turn is distinct from v_uid then
    raise exception 'NOT_YOUR_TURN';
  end if;
  if p_action_type in ('raise','call') and coalesce((v_player->>'all_in')::boolean,false) then
    raise exception 'PLAYER_ALREADY_ALL_IN';
  end if;
  if p_action_type in ('start','redeal') and not exists(select 1 from public.qcard_rooms where id=p_room_id and host_user_id=v_uid) then
    raise exception 'HOST_ONLY';
  end if;
  insert into public.qcard_actions(room_id,actor_user_id,action_type,payload,expected_version)
  values(p_room_id,v_uid,p_action_type,coalesce(p_payload,'{}'::jsonb),p_expected_version)
  returning id into v_action_id;
  return v_action_id;
end;
$function$
;

-- asix_internal.qcard_submit_process_action(p_room_id uuid, p_action_type text, p_payload jsonb, p_expected_version bigint)
CREATE OR REPLACE FUNCTION asix_internal.qcard_submit_process_action(p_room_id uuid, p_action_type text, p_payload jsonb DEFAULT '{}'::jsonb, p_expected_version bigint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_action_id bigint;
  v_result jsonb;
  v_error text;
  v_state text;
  v_game_state jsonb;
  v_version bigint;
  v_snapshot jsonb;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  v_action_id := public.qcard_submit_action(
    p_room_id,
    p_action_type,
    coalesce(p_payload, '{}'::jsonb),
    p_expected_version
  );

  -- Keep queued actions recoverable if processing raises unexpectedly.
  -- The savepoint preserves the submitted action while rolling back only
  -- the failed processing work.
  begin
    v_result := public.qcard_process_action(v_action_id, v_uid);
  exception when others then
    get stacked diagnostics v_error = message_text, v_state = returned_sqlstate;
    return jsonb_build_object(
      'ok', false,
      'action_id', v_action_id,
      'recoverable_action', true,
      'error', v_error,
      'sqlstate', v_state
    );
  end;

  select gs.state, gs.version
    into v_game_state, v_version
  from public.qcard_game_state gs
  where gs.room_id = p_room_id;

  if not found then
    raise exception 'GAME_STATE_NOT_FOUND';
  end if;

  -- Bundle the public seats and this caller's private hand into the same
  -- RPC response. If the snapshot helper has a transient error, preserve
  -- the successfully processed action and let the client use its old
  -- one-request snapshot fallback.
  begin
    v_snapshot := public.qcard_get_asix_snapshot(p_room_id);
  exception when others then
    v_snapshot := null;
  end;

  return jsonb_build_object(
    'ok', true,
    'action_id', v_action_id,
    'result', v_result,
    'recoverable_action', false,
    'state', v_game_state,
    'version', v_version,
    'snapshot', v_snapshot
  );
end;
$function$
;

-- public.asix_record_platform_commission_from_card_purchase()
CREATE OR REPLACE FUNCTION public.asix_record_platform_commission_from_card_purchase()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_settings public.asix_platform_commission_settings%rowtype;
  v_card_cost bigint; v_player_count integer; v_player_rank integer; v_seat_no smallint;
  v_total_commission bigint; v_base_commission bigint; v_remainder bigint; v_player_commission bigint;
begin
  if new.entry_type<>'card_purchase' or new.user_id is null then return new; end if;
  if new.reference_action_id is null then raise exception 'CARD_PURCHASE_ACTION_REQUIRED'; end if;
  select * into v_settings from public.asix_platform_commission_settings where id=1 and enabled=true for share;
  if not found then raise exception 'PLATFORM_COMMISSION_NOT_CONFIGURED'; end if;
  if v_settings.recipient_user_id is null then raise exception 'PLATFORM_COMMISSION_RECIPIENT_NOT_CONFIGURED'; end if;
  if v_settings.commission_rate_bps<0 or v_settings.commission_rate_bps>10000 then raise exception 'INVALID_PLATFORM_COMMISSION_RATE'; end if;
  v_card_cost:=new.amount_tetri;
  select count(*)::integer into v_player_count from public.qcard_seats s
  where s.room_id=new.room_id and s.is_connected=true
    and (s.stack_tetri>=v_card_cost or exists(
      select 1 from public.qcard_money_ledger l where l.room_id=new.room_id
      and l.reference_action_id=new.reference_action_id and l.user_id=s.user_id and l.entry_type='card_purchase'));
  if v_player_count<2 then raise exception 'COMMISSION_PLAYER_COUNT_INVALID'; end if;
  select seat_no into v_seat_no from public.qcard_seats where room_id=new.room_id and user_id=new.user_id;
  if not found then raise exception 'COMMISSION_PLAYER_SEAT_NOT_FOUND'; end if;
  select count(*)::integer into v_player_rank from public.qcard_seats s
  where s.room_id=new.room_id and s.is_connected=true and s.seat_no<=v_seat_no
    and (s.stack_tetri>=v_card_cost or exists(
      select 1 from public.qcard_money_ledger l where l.room_id=new.room_id
      and l.reference_action_id=new.reference_action_id and l.user_id=s.user_id and l.entry_type='card_purchase'));
  if v_player_rank<1 or v_player_rank>v_player_count then raise exception 'COMMISSION_PLAYER_RANK_INVALID'; end if;
  v_total_commission:=round(v_player_count::numeric*v_card_cost::numeric*v_settings.commission_rate_bps::numeric/10000)::bigint;
  v_base_commission:=v_total_commission/v_player_count;
  v_remainder:=mod(v_total_commission,v_player_count);
  v_player_commission:=v_base_commission+case when v_player_rank<=v_remainder then 1 else 0 end;
  insert into public.asix_platform_commission_ledger(
    deal_id,room_id,recipient_user_id,player_user_id,amount_tetri,commission_rate_bps,gross_table_entry_fee_tetri,table_commission_tetri
  ) values (
    new.reference_action_id::text,new.room_id,v_settings.recipient_user_id,new.user_id,v_player_commission,
    v_settings.commission_rate_bps,v_player_count*v_card_cost,v_total_commission
  ) on conflict(deal_id,player_user_id) do nothing;
  return new;
end; $function$
;

-- public.asix_require_permanent_qcard_actor()
CREATE OR REPLACE FUNCTION public.asix_require_permanent_qcard_actor()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_is_anonymous boolean;
begin
  if new.actor_user_id is null then raise exception 'ACTION_ACTOR_REQUIRED'; end if;
  select u.is_anonymous into v_is_anonymous
  from auth.users u where u.id=new.actor_user_id;
  if not found or coalesce(v_is_anonymous,true) then
    raise exception 'ACCOUNT_LINK_REQUIRED';
  end if;
  return new;
end;
$function$
;

-- public.asix_settle_platform_commission_after_deal()
CREATE OR REPLACE FUNCTION public.asix_settle_platform_commission_after_deal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_deal_id text; v_commission record; v_wallet public.asix_wallets%rowtype; v_key text; v_processed integer:=0;
begin
  if coalesce(old.state->>'phase','')<>'playing' or coalesce(new.state->>'phase','') not in ('finished','cancelled') then return new; end if;
  v_deal_id:=nullif(new.state->>'entry_action_id','');
  if v_deal_id is null then return new; end if;
  if new.state->>'phase'='cancelled' then
    update public.asix_platform_commission_ledger set cancelled_at=coalesce(cancelled_at,now())
    where room_id=new.room_id and deal_id=v_deal_id and settled_at is null and cancelled_at is null;
    return new;
  end if;
  for v_commission in
    select * from public.asix_platform_commission_ledger
    where room_id=new.room_id and deal_id=v_deal_id and settled_at is null and cancelled_at is null
    order by id for update
  loop
    v_processed:=v_processed+1;
    if v_commission.amount_tetri>0 then
      insert into public.asix_wallets(user_id,balance_tetri) values(v_commission.recipient_user_id,0) on conflict(user_id) do nothing;
      update public.asix_wallets set balance_tetri=balance_tetri+v_commission.amount_tetri,updated_at=now()
      where user_id=v_commission.recipient_user_id returning * into v_wallet;
      v_key:='asix-platform-commission:'||v_deal_id||':'||v_commission.player_user_id::text;
      insert into public.asix_wallet_transactions(user_id,transaction_type,amount_tetri,balance_after_tetri,room_id,idempotency_key,description,metadata)
      values(v_commission.recipient_user_id,'platform_commission',v_commission.amount_tetri,v_wallet.balance_tetri,new.room_id,v_key,'ASIX თამაშის საკომისიო',
        jsonb_build_object('deal_action_id',v_deal_id,'player_user_id',v_commission.player_user_id,'source','successful_deal_entry_fee_5_percent',
          'commission_rate_bps',v_commission.commission_rate_bps,'gross_table_entry_fee_tetri',v_commission.gross_table_entry_fee_tetri,
          'whole_table_commission_tetri',v_commission.table_commission_tetri,'allocated_player_commission_tetri',v_commission.amount_tetri));
    end if;
    update public.asix_platform_commission_ledger set settled_at=now()
    where id=v_commission.id and settled_at is null and cancelled_at is null;
  end loop;
  if v_processed=0 then raise exception 'PLATFORM_COMMISSION_LEDGER_MISSING'; end if;
  return new;
end; $function$
;

-- public.asix_wallet_after_deal_settlement()
CREATE OR REPLACE FUNCTION public.asix_wallet_after_deal_settlement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
begin
  if coalesce(new.state->>'phase','') in ('finished','cancelled')
     and coalesce(old.state->>'phase','') not in ('finished','cancelled') then
    perform public.asix_wallet_settle_pending_cashouts(new.room_id);
  end if;
  return new;
end;
$function$
;

-- public.asix_wallet_cashout_room(p_room_id uuid)
CREATE OR REPLACE FUNCTION public.asix_wallet_cashout_room(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$ select asix_internal.asix_wallet_cashout_room($1); $function$
;

-- public.asix_wallet_create_for_new_user()
CREATE OR REPLACE FUNCTION public.asix_wallet_create_for_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_inserted integer := 0; v_key text;
begin
  v_key := 'demo-start-10000:' || new.id::text;
  insert into public.asix_wallets(user_id,balance_tetri) values(new.id,1000000)
  on conflict(user_id) do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted > 0 then
    insert into public.asix_wallet_transactions(user_id,transaction_type,amount_tetri,balance_after_tetri,idempotency_key,description,metadata)
    values(new.id,'credit',1000000,1000000,v_key,'საწყისი დემო ბალანსი — 10,000.00 ₾',
      jsonb_build_object('kind','demo_initial_balance','currency','GEL','demo_only',true))
    on conflict(idempotency_key) do nothing;
  end if;
  return new;
end;
$function$
;

-- public.asix_wallet_credit(p_user_id uuid, p_amount_tetri bigint, p_idempotency_key text, p_description text, p_metadata jsonb)
CREATE OR REPLACE FUNCTION public.asix_wallet_credit(p_user_id uuid, p_amount_tetri bigint, p_idempotency_key text, p_description text DEFAULT 'ASIX wallet credit'::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_wallet public.asix_wallets%rowtype;
  v_tx public.asix_wallet_transactions%rowtype;
  v_is_anonymous boolean;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  if p_user_id is null or p_amount_tetri is null or p_amount_tetri < 1
     or nullif(trim(p_idempotency_key),'') is null then raise exception 'INVALID_WALLET_CREDIT'; end if;

  select coalesce(is_anonymous,false) into v_is_anonymous
  from auth.users where id=p_user_id;
  if not found then raise exception 'USER_NOT_FOUND'; end if;
  if v_is_anonymous then raise exception 'ACCOUNT_LINK_REQUIRED'; end if;

  select * into v_tx from public.asix_wallet_transactions where idempotency_key=p_idempotency_key;
  if found then return jsonb_build_object('ok',true,'duplicate',true,
    'balance_tetri',v_tx.balance_after_tetri,'transaction_id',v_tx.id); end if;

  insert into public.asix_wallets(user_id) values(p_user_id) on conflict(user_id) do nothing;
  select * into v_wallet from public.asix_wallets where user_id=p_user_id for update;
  update public.asix_wallets set balance_tetri=balance_tetri+p_amount_tetri,updated_at=now()
  where user_id=p_user_id returning * into v_wallet;

  insert into public.asix_wallet_transactions(
    user_id,transaction_type,amount_tetri,balance_after_tetri,idempotency_key,description,metadata
  ) values (
    p_user_id,'credit',p_amount_tetri,v_wallet.balance_tetri,p_idempotency_key,
    coalesce(p_description,''),coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_tx;

  return jsonb_build_object('ok',true,'duplicate',false,
    'balance_tetri',v_wallet.balance_tetri,'transaction_id',v_tx.id);
end;
$function$
;

-- public.asix_wallet_finish_bot_session(p_session_id uuid, p_amount_tetri bigint)
CREATE OR REPLACE FUNCTION public.asix_wallet_finish_bot_session(p_session_id uuid, p_amount_tetri bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
AS $function$
declare v_uid uuid:=auth.uid(); v_session public.asix_bot_sessions%rowtype; v_wallet public.asix_wallets%rowtype; v_key text;
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_session_id is null or p_amount_tetri is null or p_amount_tetri<0 then raise exception 'INVALID_CASHOUT_AMOUNT'; end if;
 select * into v_session from public.asix_bot_sessions where id=p_session_id and user_id=v_uid for update;
 if not found then raise exception 'BOT_SESSION_NOT_FOUND'; end if;
 if v_session.status='cashed_out' then return jsonb_build_object('ok',true,'duplicate',true,'returned_tetri',0); end if;
 if p_amount_tetri>1000000000 then raise exception 'CASHOUT_AMOUNT_TOO_HIGH'; end if;
 insert into public.asix_wallets(user_id) values(v_uid) on conflict(user_id) do nothing;
 select * into v_wallet from public.asix_wallets where user_id=v_uid for update;
 v_key:='bot-cashout:'||p_session_id::text;
 if p_amount_tetri>0 then
  update public.asix_wallets set balance_tetri=balance_tetri+p_amount_tetri,updated_at=now() where user_id=v_uid returning * into v_wallet;
  insert into public.asix_wallet_transactions(user_id,transaction_type,amount_tetri,balance_after_tetri,idempotency_key,description,metadata)
  values(v_uid,'table_cashout',p_amount_tetri,v_wallet.balance_tetri,v_key,'ბოტების მაგიდიდან დარჩენილი თანხის დაბრუნება',jsonb_build_object('mode','bots','session_id',p_session_id,'buyin_tetri',v_session.buyin_tetri));
 end if;
 update public.asix_bot_sessions set status='cashed_out',cashed_out_at=now(),cashout_tetri=p_amount_tetri where id=p_session_id;
 return jsonb_build_object('ok',true,'duplicate',false,'returned_tetri',p_amount_tetri,'wallet_balance_tetri',v_wallet.balance_tetri);
end; $function$
;

-- public.asix_wallet_get_balance()
CREATE OR REPLACE FUNCTION public.asix_wallet_get_balance()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$ select asix_internal.asix_wallet_get_balance(); $function$
;

-- public.asix_wallet_get_transactions(p_limit integer)
CREATE OR REPLACE FUNCTION public.asix_wallet_get_transactions(p_limit integer DEFAULT 20)
 RETURNS TABLE(id bigint, transaction_type text, amount_tetri bigint, balance_after_tetri bigint, room_id uuid, description text, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$ select * from asix_internal.asix_wallet_get_transactions($1); $function$
;

-- public.asix_wallet_settle_cashout(p_room_id uuid, p_user_id uuid)
CREATE OR REPLACE FUNCTION public.asix_wallet_settle_cashout(p_room_id uuid, p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
AS $function$
declare
  v_room public.qcard_rooms%rowtype;
  v_seat public.qcard_seats%rowtype;
  v_wallet public.asix_wallets%rowtype;
  v_amount bigint;
  v_key text;
begin
  select * into v_room from public.qcard_rooms where id=p_room_id for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  if v_room.status='playing' then
    return jsonb_build_object('ok',false,'pending',true,'reason','DEAL_NOT_FINISHED');
  end if;

  select * into v_seat from public.qcard_seats
  where room_id=p_room_id and user_id=p_user_id for update;
  if not found then raise exception 'NOT_A_ROOM_MEMBER'; end if;
  if v_seat.wallet_entry_key is null then raise exception 'WALLET_BUYIN_NOT_FOUND'; end if;

  v_key := 'room-cashout:'||v_seat.wallet_entry_key;
  if exists(select 1 from public.asix_wallet_transactions where idempotency_key=v_key) then
    update public.qcard_seats set wallet_cashout_requested=false,stack_tetri=null,
      entry_stack_tetri=null,entry_set_at=null,wallet_entry_key=null,
      is_connected=false,last_seen_at=now()
    where room_id=p_room_id and user_id=p_user_id;
    return jsonb_build_object('ok',true,'duplicate',true,'returned_tetri',0);
  end if;

  v_amount := greatest(0,coalesce(v_seat.stack_tetri,0));
  insert into public.asix_wallets(user_id) values(p_user_id) on conflict(user_id) do nothing;
  select * into v_wallet from public.asix_wallets where user_id=p_user_id for update;

  if v_amount>0 then
    update public.asix_wallets set balance_tetri=balance_tetri+v_amount,updated_at=now()
    where user_id=p_user_id returning * into v_wallet;
    insert into public.asix_wallet_transactions(
      user_id,transaction_type,amount_tetri,balance_after_tetri,room_id,
      idempotency_key,description,metadata
    ) values(
      p_user_id,'table_cashout',v_amount,v_wallet.balance_tetri,p_room_id,
      v_key,'დარჩენილი თანხის დაბრუნება ASIX საფულეში',
      jsonb_build_object('source','remaining_table_stack','wallet_entry_key',v_seat.wallet_entry_key)
    );
  end if;

  update public.qcard_seats set wallet_cashout_requested=false,stack_tetri=null,
    entry_stack_tetri=null,entry_set_at=null,wallet_entry_key=null,
    is_connected=false,last_seen_at=now()
  where room_id=p_room_id and user_id=p_user_id;

  return jsonb_build_object('ok',true,'pending',false,'duplicate',false,
    'returned_tetri',v_amount,'wallet_balance_tetri',v_wallet.balance_tetri);
end;
$function$
;

-- public.asix_wallet_settle_pending_cashouts(p_room_id uuid)
CREATE OR REPLACE FUNCTION public.asix_wallet_settle_pending_cashouts(p_room_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_user uuid;
  v_count integer := 0;
  v_result jsonb;
begin
  for v_user in
    select user_id from public.qcard_seats
    where room_id=p_room_id and wallet_cashout_requested=true
    order by seat_no
  loop
    v_result := public.asix_wallet_settle_cashout(p_room_id,v_user);
    if coalesce((v_result->>'ok')::boolean,false)
       and not coalesce((v_result->>'pending')::boolean,false) then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$function$
;

-- public.asix_wallet_start_bot_session(p_amount_tetri bigint)
CREATE OR REPLACE FUNCTION public.asix_wallet_start_bot_session(p_amount_tetri bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
AS $function$
declare v_uid uuid:=auth.uid(); v_wallet public.asix_wallets%rowtype; v_session uuid; v_key text;
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_amount_tetri is null or p_amount_tetri<1 then raise exception 'INVALID_ENTRY_AMOUNT'; end if;
 if p_amount_tetri>100000000 then raise exception 'ENTRY_AMOUNT_TOO_HIGH'; end if;
 insert into public.asix_wallets(user_id) values(v_uid) on conflict(user_id) do nothing;
 select * into v_wallet from public.asix_wallets where user_id=v_uid for update;
 if v_wallet.balance_tetri<p_amount_tetri then raise exception 'WALLET_INSUFFICIENT_BALANCE'; end if;
 v_session:=gen_random_uuid(); v_key:='bot-buyin:'||v_session::text;
 update public.asix_wallets set balance_tetri=balance_tetri-p_amount_tetri,updated_at=now() where user_id=v_uid returning * into v_wallet;
 insert into public.asix_bot_sessions(id,user_id,buyin_tetri) values(v_session,v_uid,p_amount_tetri);
 insert into public.asix_wallet_transactions(user_id,transaction_type,amount_tetri,balance_after_tetri,idempotency_key,description,metadata)
 values(v_uid,'table_buyin',p_amount_tetri,v_wallet.balance_tetri,v_key,'ბოტების მაგიდაზე თანხის გადატანა',jsonb_build_object('mode','bots','session_id',v_session));
 return jsonb_build_object('ok',true,'session_id',v_session,'buyin_tetri',p_amount_tetri,'wallet_balance_tetri',v_wallet.balance_tetri);
end; $function$
;

-- public.qcard_action_preserve_actor_identity()
CREATE OR REPLACE FUNCTION public.qcard_action_preserve_actor_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  if old.actor_user_id is not null and new.actor_user_id is null then
    new.actor_user_id_snapshot := coalesce(new.actor_user_id_snapshot,old.actor_user_id);
  end if;
  return new;
end;
$function$
;

-- public.qcard_add_contribution(p_contributions jsonb, p_user_id uuid, p_amount_tetri bigint)
CREATE OR REPLACE FUNCTION public.qcard_add_contribution(p_contributions jsonb, p_user_id uuid, p_amount_tetri bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_old bigint;
  v_new bigint;
begin
  if p_user_id is null then
    raise exception 'INVALID_USER_ID';
  end if;

  if p_amount_tetri is null or p_amount_tetri < 0 then
    raise exception 'INVALID_CONTRIBUTION_AMOUNT';
  end if;

  if jsonb_typeof(coalesce(p_contributions, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_CONTRIBUTIONS_OBJECT';
  end if;

  begin
    v_old := coalesce(
      (p_contributions->>p_user_id::text)::bigint,
      0
    );
  exception when others then
    raise exception 'INVALID_EXISTING_CONTRIBUTION';
  end;

  if v_old < 0 or v_old > 9000000000000000 - p_amount_tetri then
    raise exception 'CONTRIBUTION_OVERFLOW';
  end if;

  v_new := v_old + p_amount_tetri;

  return jsonb_set(
    coalesce(p_contributions, '{}'::jsonb),
    array[p_user_id::text],
    to_jsonb(v_new),
    true
  );
end;
$function$
;

-- public.qcard_allocate_side_pots(p_side_pots jsonb, p_played_cards jsonb)
CREATE OR REPLACE FUNCTION public.qcard_allocate_side_pots(p_side_pots jsonb, p_played_cards jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v_pot jsonb; v_eligible jsonb; v_winner uuid; v_amount bigint;
 v_payouts jsonb:='{}'::jsonb; v_awarded jsonb:='[]'::jsonb;
 v_total bigint:=0; v_old bigint;
BEGIN
 IF jsonb_typeof(coalesce(p_side_pots,'[]'::jsonb))<>'array' THEN RAISE EXCEPTION 'INVALID_SIDE_POTS_ARRAY'; END IF;
 IF jsonb_typeof(coalesce(p_played_cards,'[]'::jsonb))<>'array' THEN RAISE EXCEPTION 'INVALID_PLAYED_CARDS_ARRAY'; END IF;
 FOR v_pot IN SELECT value FROM jsonb_array_elements(coalesce(p_side_pots,'[]'::jsonb))
 LOOP
  v_eligible:=coalesce(v_pot->'eligible_user_ids','[]'::jsonb);
  IF jsonb_typeof(v_eligible)<>'array' OR jsonb_array_length(v_eligible)=0 THEN RAISE EXCEPTION 'SIDE_POT_WITHOUT_ELIGIBLE_PLAYER'; END IF;
  SELECT (x.value->>'user_id')::uuid INTO v_winner
  FROM jsonb_array_elements(coalesce(p_played_cards,'[]'::jsonb)) WITH ORDINALITY x(value,ord)
  WHERE v_eligible ? (x.value->>'user_id')
  ORDER BY x.ord DESC LIMIT 1;
  IF v_winner IS NULL THEN
   SELECT value::uuid INTO v_winner
   FROM jsonb_array_elements_text(v_eligible) WITH ORDINALITY x(value,ord)
   ORDER BY ord LIMIT 1;
  END IF;
  v_amount:=coalesce((v_pot->>'amount_tetri')::bigint,0);
  IF v_amount<0 THEN RAISE EXCEPTION 'INVALID_SIDE_POT_AMOUNT'; END IF;
  v_old:=coalesce((v_payouts->>v_winner::text)::bigint,0);
  v_payouts:=jsonb_set(v_payouts,array[v_winner::text],to_jsonb(v_old+v_amount),true);
  v_total:=v_total+v_amount;
  v_awarded:=v_awarded||jsonb_build_array(v_pot||jsonb_build_object('winner_user_id',v_winner));
 END LOOP;
 RETURN jsonb_build_object('pots',v_awarded,'payouts',v_payouts,'total_tetri',v_total);
END;
$function$
;

-- public.qcard_archive_before_new_deal()
CREATE OR REPLACE FUNCTION public.qcard_archive_before_new_deal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
 r public.qcard_rooms%rowtype;
 v_history_id bigint;
 v_deal_no integer;
 v_winner uuid;
 v_winner_name text;
begin
 -- Archive immediately when a live deal reaches a terminal state.
 if coalesce(old.state->>'phase','') <> 'playing'
    or coalesce(new.state->>'phase','') not in ('finished','cancelled') then
   return new;
 end if;

 select * into r from public.qcard_rooms where id=old.room_id;
 if not found then raise exception 'ARCHIVE_ROOM_NOT_FOUND'; end if;

 v_winner:=nullif(new.state->>'winner_user_id','')::uuid;
 select value->>'display_name' into v_winner_name
 from jsonb_array_elements(coalesce(new.state->'players','[]'::jsonb)) x(value)
 where value->>'user_id'=v_winner::text limit 1;

 select coalesce(max(deal_number),0)+1 into v_deal_no
 from public.qcard_deal_history where room_id=old.room_id;

 insert into public.qcard_deal_history(
  room_id,room_code,room_name,deal_number,host_user_id,started_at,
  completed_at,final_phase,winner_user_id,winner_name,state_snapshot,room_settings
 ) values (
  old.room_id,r.room_code,r.name,v_deal_no,r.host_user_id,
  nullif(new.state->>'deal_started_at','')::timestamptz,now(),
  new.state->>'phase',v_winner,v_winner_name,new.state,
  jsonb_build_object(
   'max_players',r.max_players,
   'card_price',r.card_price,
   'cards_per_player',r.cards_per_player,
   'max_bet',r.max_bet,
   'prize_allocation_method','player_count_based',
   'player_count',nullif(new.state->>'player_count','')::integer,
   'initial_prize_percent',nullif(new.state->>'initial_prize_percent','')::numeric,
   'growth_targets_percent',coalesce(new.state->'growth_weights','[]'::jsonb),
   'final_prize_percent',100.00
  )
 ) returning id into v_history_id;

 insert into public.qcard_deal_history_players(
  deal_history_id,user_id,display_name,seat_no,folded,all_in,cards_count,
  stack_tetri_after_deal,is_winner
 )
 select v_history_id,
  nullif(value->>'user_id','')::uuid,
  coalesce(value->>'display_name','მოთამაშე'),
  (value->>'seat_no')::smallint,
  coalesce((value->>'folded')::boolean,false),
  coalesce((value->>'all_in')::boolean,false),
  coalesce((value->>'cards_count')::integer,0),
  coalesce(s.stack_tetri,nullif(value->>'stack_tetri','')::bigint),
  coalesce(nullif(value->>'user_id','')::uuid=v_winner,false)
 from jsonb_array_elements(coalesce(new.state->'players','[]'::jsonb)) x(value)
 left join public.qcard_seats s
   on s.room_id=old.room_id and s.user_id=nullif(value->>'user_id','')::uuid;

 return new;
end;
$function$
;

-- public.qcard_archive_completed_deal(p_room_id uuid, p_room_code text, p_room_name text, p_host_user_id uuid, p_state jsonb, p_settings jsonb)
CREATE OR REPLACE FUNCTION public.qcard_archive_completed_deal(p_room_id uuid, p_room_code text, p_room_name text, p_host_user_id uuid, p_state jsonb, p_settings jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
 v_deal_no integer;
 v_history_id bigint;
 v_winner uuid;
 v_winner_name text;
 v_phase text;
begin
 v_phase:=coalesce(p_state->>'phase','');
 if v_phase not in ('finished','cancelled') then
   raise exception 'DEAL_NOT_TERMINAL';
 end if;
 select (p_state->>'winner_user_id')::uuid into v_winner;
 select value->>'display_name' into v_winner_name
 from jsonb_array_elements(coalesce(p_state->'players','[]'::jsonb)) x(value)
 where value->>'user_id'=v_winner::text limit 1;

 select coalesce(max(deal_number),0)+1 into v_deal_no
 from public.qcard_deal_history where room_id=p_room_id;

 insert into public.qcard_deal_history(
  room_id,room_code,room_name,deal_number,host_user_id,started_at,
  completed_at,final_phase,winner_user_id,winner_name,state_snapshot,room_settings
 ) values (
  p_room_id,p_room_code,p_room_name,v_deal_no,p_host_user_id,
  nullif(p_state->>'deal_started_at','')::timestamptz,now(),v_phase,
  v_winner,v_winner_name,p_state,coalesce(p_settings,'{}'::jsonb)
 ) returning id into v_history_id;

 insert into public.qcard_deal_history_players(
  deal_history_id,user_id,display_name,seat_no,folded,all_in,cards_count,
  stack_tetri_after_deal,is_winner
 )
 select v_history_id,
  nullif(value->>'user_id','')::uuid,
  coalesce(value->>'display_name','მოთამაშე'),
  (value->>'seat_no')::smallint,
  coalesce((value->>'folded')::boolean,false),
  coalesce((value->>'all_in')::boolean,false),
  coalesce((value->>'cards_count')::integer,0),
  nullif(value->>'stack_tetri','')::bigint,
  nullif(value->>'user_id','')::uuid=v_winner
 from jsonb_array_elements(coalesce(p_state->'players','[]'::jsonb)) x(value);

 return v_history_id;
end;
$function$
;

-- public.qcard_asix_heartbeat_bundle(p_room_id uuid)
CREATE OR REPLACE FUNCTION public.qcard_asix_heartbeat_bundle(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$ select asix_internal.qcard_asix_heartbeat_bundle($1); $function$
;

-- public.qcard_asix_stamp_turn_started()
CREATE OR REPLACE FUNCTION public.qcard_asix_stamp_turn_started()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  if new.state->>'phase' = 'playing'
     and nullif(new.state->>'current_turn_user_id','') is not null
     and (
       old.state->>'current_turn_user_id' is distinct from new.state->>'current_turn_user_id'
       or old.state->>'phase' is distinct from 'playing'
     ) then
    new.state := jsonb_set(new.state, '{turn_started_at}', to_jsonb(now()), true);
  end if;
  return new;
end;
$function$
;

-- public.qcard_audit_growth_release()
CREATE OR REPLACE FUNCTION public.qcard_audit_growth_release()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_old_growth bigint;
  v_new_growth bigint;
  v_delta bigint;
  v_stage integer;
  v_action_id bigint;
  v_actor uuid;
  v_target_pct numeric;
  v_old_pot bigint;
  v_new_pot bigint;
begin
  v_old_growth:=coalesce((old.state->>'growth_added_tetri')::bigint,0);
  v_new_growth:=coalesce((new.state->>'growth_added_tetri')::bigint,0);
  v_delta:=v_new_growth-v_old_growth;

  if v_delta<=0 then
    return new;
  end if;

  v_stage:=coalesce((new.state->>'successful_cuts')::integer,0);
  v_actor:=nullif(new.state->>'last_cutter_user_id','')::uuid;
  v_old_pot:=coalesce((old.state->>'pot_tetri')::bigint,0);
  v_new_pot:=coalesce((new.state->>'pot_tetri')::bigint,0);

  if v_new_pot-v_old_pot<>v_delta then
    raise exception 'GROWTH_RELEASE_POT_DELTA_MISMATCH';
  end if;

  if v_stage < 1 or v_stage > 4 then
    raise exception 'INVALID_GROWTH_RELEASE_STAGE';
  end if;
  begin
    v_target_pct := (new.state->'growth_weights'->>(v_stage-1))::numeric;
  exception when others then
    v_target_pct := null;
  end;
  if v_target_pct is null or v_target_pct <= 0 or v_target_pct > 100 then
    raise exception 'INVALID_GROWTH_TARGET_PERCENT';
  end if;

  select a.id into v_action_id
  from public.qcard_actions a
  where a.room_id=new.room_id
    and a.actor_user_id=v_actor
    and a.action_type='play_card'
    and a.expected_version=old.version
    and a.status in ('pending','processing')
  order by a.id desc
  limit 1;

  if v_action_id is null then
    raise exception 'GROWTH_RELEASE_ACTION_NOT_FOUND';
  end if;

  insert into public.qcard_money_ledger(
    room_id,user_id,entry_type,amount_tetri,reference_action_id,details
  ) values (
    new.room_id,null,'growth_release',v_delta,v_action_id,
    jsonb_build_object(
      'stage',v_stage,
      'target_percent',v_target_pct,
      'player_count',nullif(new.state->>'player_count','')::integer,
      'initial_prize_percent',nullif(new.state->>'initial_prize_percent','')::numeric,
      'pot_before_tetri',v_old_pot,
      'pot_after_tetri',v_new_pot,
      'growth_release_tetri',v_delta
    )
  );

  return new;
end;
$function$
;

-- public.qcard_build_side_pots(p_contributions jsonb, p_players jsonb)
CREATE OR REPLACE FUNCTION public.qcard_build_side_pots(p_contributions jsonb, p_players jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  c record;
  pl record;
  v_uid uuid;
  v_amount bigint;
  v_level bigint;
  v_prev bigint := 0;
  v_contributor_count integer;
  v_eligible jsonb;
  v_pots jsonb := '[]'::jsonb;
  v_refunds jsonb := '{}'::jsonb;
  v_pot_amount bigint;
  v_pot_total bigint := 0;
  v_refund_total bigint := 0;
  v_contribution_total bigint := 0;
  v_index integer := 0;
  v_active_count integer := 0;
  v_fallback_winner uuid := null;
begin
  if jsonb_typeof(p_contributions) <> 'object' then
    raise exception 'INVALID_CONTRIBUTIONS_OBJECT';
  end if;
  if jsonb_typeof(p_players) <> 'array' then
    raise exception 'INVALID_PLAYERS_ARRAY';
  end if;

  for pl in select value from jsonb_array_elements(p_players)
  loop
    begin
      v_uid := (pl.value->>'user_id')::uuid;
    exception when others then
      raise exception 'INVALID_PLAYER_UUID';
    end;
    if (
      select count(*) from jsonb_array_elements(p_players) x
      where x.value->>'user_id' = v_uid::text
    ) <> 1 then
      raise exception 'DUPLICATE_PLAYER_UUID: %', v_uid;
    end if;
  end loop;

  for c in select key, value from jsonb_each(p_contributions)
  loop
    begin
      v_uid := c.key::uuid;
      v_amount := c.value::text::bigint;
    exception when others then
      raise exception 'INVALID_CONTRIBUTION: %', c.key;
    end;
    if v_amount < 0 then raise exception 'NEGATIVE_CONTRIBUTION: %', c.key; end if;
    if not exists (
      select 1 from jsonb_array_elements(p_players) x
      where x.value->>'user_id' = v_uid::text
    ) then
      raise exception 'CONTRIBUTOR_NOT_IN_PLAYERS: %', v_uid;
    end if;
    v_contribution_total := v_contribution_total + v_amount;
  end loop;

  select count(*) into v_active_count
  from jsonb_array_elements(p_players) x(value)
  where coalesce((x.value->>'folded')::boolean,false)=false;

  if v_active_count = 1 then
    select (x.value->>'user_id')::uuid into v_fallback_winner
    from jsonb_array_elements(p_players) x(value)
    where coalesce((x.value->>'folded')::boolean,false)=false
    limit 1;
  end if;

  for v_level in
    select distinct value::text::bigint
    from jsonb_each(p_contributions)
    where value::text::bigint > 0
    order by 1
  loop
    select count(*) into v_contributor_count
    from jsonb_each(p_contributions)
    where value::text::bigint >= v_level;

    v_pot_amount := (v_level - v_prev) * v_contributor_count;

    if v_contributor_count = 1 then
      select key::uuid into v_uid
      from jsonb_each(p_contributions)
      where value::text::bigint >= v_level
      limit 1;

      v_refunds := jsonb_set(
        v_refunds,
        array[v_uid::text],
        to_jsonb(coalesce((v_refunds->>v_uid::text)::bigint,0)+v_pot_amount),
        true
      );
      v_refund_total := v_refund_total + v_pot_amount;

    elsif v_pot_amount > 0 then
      select coalesce(
        jsonb_agg(x.value->>'user_id' order by (x.value->>'seat_no')::integer),
        '[]'::jsonb
      ) into v_eligible
      from jsonb_array_elements(p_players) x(value)
      where coalesce((x.value->>'folded')::boolean,false)=false
        and coalesce((p_contributions->>(x.value->>'user_id'))::bigint,0) >= v_level;

      -- If exactly one player remains, they win every contested pot layer,
      -- including a layer whose original contributors have all folded.
      if jsonb_array_length(v_eligible)=0 and v_fallback_winner is not null then
        v_eligible := jsonb_build_array(v_fallback_winner::text);
      end if;

      if jsonb_array_length(v_eligible)=0 then
        for c in
          select key from jsonb_each(p_contributions)
          where value::text::bigint >= v_level
        loop
          v_uid := c.key::uuid;
          v_refunds := jsonb_set(
            v_refunds,
            array[v_uid::text],
            to_jsonb(coalesce((v_refunds->>v_uid::text)::bigint,0)+(v_level-v_prev)),
            true
          );
          v_refund_total := v_refund_total + (v_level-v_prev);
        end loop;
      else
        v_index := v_index + 1;
        v_pots := v_pots || jsonb_build_array(jsonb_build_object(
          'pot_index',v_index,
          'from_tetri',v_prev,
          'to_tetri',v_level,
          'amount_tetri',v_pot_amount,
          'eligible_user_ids',v_eligible,
          'fallback_winner_user_id',v_fallback_winner
        ));
        v_pot_total := v_pot_total + v_pot_amount;
      end if;
    end if;
    v_prev := v_level;
  end loop;

  if v_pot_total+v_refund_total<>v_contribution_total then
    raise exception 'SIDE_POT_RECONCILIATION_FAILED';
  end if;

  return jsonb_build_object(
    'pots',v_pots,
    'refunds',v_refunds,
    'pot_total_tetri',v_pot_total,
    'refund_total_tetri',v_refund_total,
    'contribution_total_tetri',v_contribution_total,
    'pot_count',v_index
  );
end;
$function$
;

-- public.qcard_calculate_table_funds(p_sales_tetri bigint, p_player_count integer)
CREATE OR REPLACE FUNCTION public.qcard_calculate_table_funds(p_sales_tetri bigint, p_player_count integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_initial_pct numeric;
  v_targets_pct numeric[];
  v_targets_tetri bigint[];
  v_initial bigint;
  v_final bigint;
  v_growth bigint;
  v_reserve bigint;
begin
  if p_sales_tetri is null or p_sales_tetri < 0 then
    raise exception 'INVALID_SALES_TETRI';
  end if;

  v_initial_pct := case p_player_count
    when 2 then 85.00
    when 3 then 80.00
    when 4 then 70.00
    when 5 then 60.00
    else null
  end;
  if v_initial_pct is null then
    raise exception 'UNSUPPORTED_PLAYER_COUNT';
  end if;

  v_targets_pct := array[
    v_initial_pct+(100.00-v_initial_pct)*0.25,
    v_initial_pct+(100.00-v_initial_pct)*0.50,
    v_initial_pct+(100.00-v_initial_pct)*0.75,
    100.00
  ];
  v_initial := round(p_sales_tetri*v_initial_pct/100)::bigint;
  v_final := round(p_sales_tetri*1.00)::bigint;
  v_growth := greatest(0,v_final-v_initial);
  v_reserve := greatest(0,p_sales_tetri-v_final);
  select array_agg(round(p_sales_tetri*x/100)::bigint order by n)
    into v_targets_tetri
  from unnest(v_targets_pct) with ordinality as u(x,n);

  return jsonb_build_object(
    'sales_tetri',p_sales_tetri,
    'player_count',p_player_count,
    'initial_prize_percent',v_initial_pct,
    'growth_targets_percent',to_jsonb(v_targets_pct),
    'growth_targets_tetri',to_jsonb(v_targets_tetri),
    'initial_prize_tetri',v_initial,
    'growth_budget_tetri',v_growth,
    'max_table_pool_tetri',v_final,
    'reserve_tetri',v_reserve,
    'total_allocated_tetri',v_final+v_reserve,
    'within_sales',v_final+v_reserve<=p_sales_tetri
  );
end;
$function$
;

-- public.qcard_call_due(p_current_bet_tetri bigint, p_player_contribution_tetri bigint)
CREATE OR REPLACE FUNCTION public.qcard_call_due(p_current_bet_tetri bigint, p_player_contribution_tetri bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  if p_current_bet_tetri is null or p_player_contribution_tetri is null
     or p_current_bet_tetri < 0 or p_player_contribution_tetri < 0 then
    raise exception 'INVALID_BET_AMOUNT';
  end if;

  return greatest(
    0,
    p_current_bet_tetri - p_player_contribution_tetri
  );
end;
$function$
;

-- public.qcard_call_payment(p_current_bet_tetri bigint, p_player_contribution_tetri bigint, p_stack_tetri bigint)
CREATE OR REPLACE FUNCTION public.qcard_call_payment(p_current_bet_tetri bigint, p_player_contribution_tetri bigint, p_stack_tetri bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_due bigint;
  v_payment bigint;
begin
  if p_current_bet_tetri is null or p_current_bet_tetri < 0
     or p_player_contribution_tetri is null or p_player_contribution_tetri < 0
     or p_stack_tetri is null or p_stack_tetri < 0 then
    raise exception 'INVALID_CALL_INPUT';
  end if;

  v_due := greatest(0, p_current_bet_tetri - p_player_contribution_tetri);
  v_payment := least(v_due, p_stack_tetri);

  return jsonb_build_object(
    'call_due_tetri', v_due,
    'payment_tetri', v_payment,
    'remaining_stack_tetri', p_stack_tetri - v_payment,
    -- A zero-stack player who owes money is all-in even when the call payment is 0.
    'all_in', (v_due > 0 and p_stack_tetri - v_payment = 0),
    'short_call', (v_payment < v_due)
  );
end;
$function$
;

-- public.qcard_card_beats(p_candidate jsonb, p_target jsonb, p_trump text)
CREATE OR REPLACE FUNCTION public.qcard_card_beats(p_candidate jsonb, p_target jsonb, p_trump text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  c_j boolean;
  t_j boolean;
  c_s text;
  t_s text;
  c_v integer;
  t_v integer;
  c_joker_color text;
  t_joker_color text;
begin
  if p_candidate is null or p_target is null then
    return false;
  end if;

  c_j := (p_candidate->>'r' = 'JOKER')
      or coalesce((p_candidate->>'joker')::boolean, false);
  t_j := (p_target->>'r' = 'JOKER')
      or coalesce((p_target->>'joker')::boolean, false);

  -- Joker beats Joker only when their colors differ.
  if t_j then
    if not c_j then return false; end if;
    c_joker_color := lower(coalesce(p_candidate->>'jokerColor', p_candidate->>'joker_color', ''));
    t_joker_color := lower(coalesce(p_target->>'jokerColor', p_target->>'joker_color', ''));
    return c_joker_color in ('red','black')
       and t_joker_color in ('red','black')
       and c_joker_color <> t_joker_color;
  end if;

  -- Any Joker beats a non-Joker.
  if c_j then return true; end if;

  c_s := p_candidate->>'s';
  t_s := p_target->>'s';

  if c_s = p_trump and t_s <> p_trump then return true; end if;
  if c_s <> p_trump and t_s = p_trump then return false; end if;
  if c_s <> t_s then return false; end if;

  c_v := case p_candidate->>'r'
    when 'A' then 14 when 'K' then 13 when 'Q' then 12 when 'J' then 11
    when '10' then 10 when '9' then 9 when '8' then 8 when '7' then 7
    when '6' then 6 else 0 end;
  t_v := case p_target->>'r'
    when 'A' then 14 when 'K' then 13 when 'Q' then 12 when 'J' then 11
    when '10' then 10 when '9' then 9 when '8' then 8 when '7' then 7
    when '6' then 6 else 0 end;
  return c_v > t_v;
end;
$function$
;

-- public.qcard_clear_deal_history_on_logic_change()
CREATE OR REPLACE FUNCTION public.qcard_clear_deal_history_on_logic_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  if new.logic_version is distinct from old.logic_version then
    delete from public.qcard_deal_history;
    new.changed_at := now();
  end if;
  return new;
end;
$function$
;

-- public.qcard_create_room(p_name text, p_card_price numeric, p_cards_per_player integer, p_max_players integer, p_max_bet numeric, p_display_name text)
CREATE OR REPLACE FUNCTION public.qcard_create_room(p_name text DEFAULT 'Q-CARD FRIENDS'::text, p_card_price numeric DEFAULT 0.10, p_cards_per_player integer DEFAULT 3, p_max_players integer DEFAULT 5, p_max_bet numeric DEFAULT 20.00, p_display_name text DEFAULT 'Player'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_room public.qcard_rooms%rowtype;
  v_code text;
  v_name text;
  v_card_price numeric(10,2);
  v_max_bet numeric(10,2);
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_card_price is null or p_cards_per_player is null
     or p_max_players is null or p_max_bet is null then
    raise exception 'INVALID_ROOM_SETTINGS: NULL_SETTING';
  end if;

  v_card_price := round(p_card_price, 2);
  v_max_bet := round(p_max_bet, 2);

  if v_card_price <> 0.10 then raise exception 'INVALID_ROOM_SETTINGS: CARD_PRICE_FIXED_0_10'; end if;
  if p_cards_per_player not between 1 and 5 then raise exception 'INVALID_ROOM_SETTINGS: CARDS_PER_PLAYER_1_TO_5'; end if;
  if p_max_players not between 2 and 5 then raise exception 'INVALID_ROOM_SETTINGS: MAX_PLAYERS_2_TO_5'; end if;
  if v_max_bet <= 0 then raise exception 'INVALID_ROOM_SETTINGS: MAX_BET_MUST_BE_POSITIVE'; end if;

  v_name := coalesce(nullif(trim(p_name),''),'Q-CARD FRIENDS');
  loop
    v_code := upper(substr(encode(gen_random_bytes(5),'hex'),1,6));
    exit when not exists(select 1 from public.qcard_rooms where room_code=v_code);
  end loop;

  insert into public.qcard_rooms(room_code,name,host_user_id,card_price,cards_per_player,max_players,max_bet)
  values(v_code,v_name,v_uid,v_card_price,p_cards_per_player,p_max_players,v_max_bet)
  returning * into v_room;

  insert into public.qcard_seats(room_id,user_id,display_name,seat_no)
  values(v_room.id,v_uid,left(coalesce(nullif(trim(p_display_name),''),'Player'),32),1);

  insert into public.qcard_game_state(room_id) values(v_room.id);
  return jsonb_build_object('room_id',v_room.id,'room_code',v_room.room_code,'seat_no',1,'status',v_room.status);
end;
$function$
;

-- public.qcard_create_room_with_wallet(p_name text, p_card_price numeric, p_cards_per_player integer, p_max_players integer, p_max_bet numeric, p_display_name text, p_amount_tetri bigint)
CREATE OR REPLACE FUNCTION public.qcard_create_room_with_wallet(p_name text DEFAULT 'ASIX CLASSIC'::text, p_card_price numeric DEFAULT 0.10, p_cards_per_player integer DEFAULT 3, p_max_players integer DEFAULT 5, p_max_bet numeric DEFAULT 20.00, p_display_name text DEFAULT 'Player'::text, p_amount_tetri bigint DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
 select asix_internal.qcard_create_room_with_wallet($1,$2,$3,$4,$5,$6,$7)
   || jsonb_build_object('host_user_id',auth.uid());
$function$
;

-- public.qcard_get_asix_snapshot(p_room_id uuid)
CREATE OR REPLACE FUNCTION public.qcard_get_asix_snapshot(p_room_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_seats jsonb;
  v_hand jsonb;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.qcard_seats s
    where s.room_id = p_room_id
      and s.user_id = v_uid
  ) then
    raise exception 'NOT_A_ROOM_MEMBER';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'user_id', s.user_id,
        'seat_no', s.seat_no,
        'display_name', s.display_name,
        'is_connected', s.is_connected,
        'stack_tetri', s.stack_tetri
      ) order by s.seat_no
    ),
    '[]'::jsonb
  )
  into v_seats
  from public.qcard_seats s
  where s.room_id = p_room_id;

  select h.hand
  into v_hand
  from public.qcard_private_hands h
  where h.room_id = p_room_id
    and h.user_id = v_uid;

  return jsonb_build_object(
    'seats', coalesce(v_seats, '[]'::jsonb),
    'hand', coalesce(v_hand, '[]'::jsonb)
  );
end;
$function$
;

-- public.qcard_get_my_deal_history(p_requester_user_id uuid, p_limit integer, p_before_id bigint)
CREATE OR REPLACE FUNCTION public.qcard_get_my_deal_history(p_requester_user_id uuid, p_limit integer DEFAULT 30, p_before_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$ select asix_internal.qcard_get_my_deal_history($1, $2, $3); $function$
;

-- public.qcard_guard_manual_start_room()
CREATE OR REPLACE FUNCTION public.qcard_guard_manual_start_room()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_card_cost bigint;
  v_players integer;
  v_required_action text;
begin
  if new.status = 'playing' and old.status <> 'playing' then
    v_card_cost := round(new.card_price * 100)::bigint * new.cards_per_player;

    v_required_action := case
      when old.status = 'finished' then 'redeal'
      else 'start'
    end;

    if not exists (
      select 1 from public.qcard_actions a
      where a.room_id = new.id
        and a.actor_user_id = new.host_user_id
        and a.action_type = v_required_action
        and a.status in ('pending','processing')
    ) then
      raise exception 'MANUAL_START_REQUIRED';
    end if;

    select count(*) into v_players
      from public.qcard_seats s
      where s.room_id = new.id
        and s.is_connected = true
        and s.stack_tetri is not null
        and s.stack_tetri >= v_card_cost;

    if v_players < 2 then raise exception 'NOT_ENOUGH_PLAYERS'; end if;
  end if;
  return new;
end;
$function$
;

-- public.qcard_guard_manual_start_state()
CREATE OR REPLACE FUNCTION public.qcard_guard_manual_start_state()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_host uuid;
  v_card_cost bigint;
  v_players integer;
  v_required_action text;
begin
  if coalesce(new.state->>'phase','waiting') = 'playing'
     and coalesce(old.state->>'phase','waiting') <> 'playing' then
    select host_user_id, round(card_price * 100)::bigint * cards_per_player
      into v_host, v_card_cost
      from public.qcard_rooms where id = new.room_id;

    v_required_action := case
      when coalesce(old.state->>'phase','waiting') = 'finished' then 'redeal'
      else 'start'
    end;

    if not exists (
      select 1 from public.qcard_actions a
      where a.room_id = new.room_id
        and a.actor_user_id = v_host
        and a.action_type = v_required_action
        and a.status in ('pending','processing')
    ) then
      raise exception 'MANUAL_START_REQUIRED';
    end if;

    select count(*) into v_players
      from public.qcard_seats s
      where s.room_id = new.room_id
        and s.is_connected = true
        and s.stack_tetri is not null
        and s.stack_tetri >= v_card_cost;

    if v_players < 2 then raise exception 'NOT_ENOUGH_PLAYERS'; end if;
  end if;
  return new;
end;
$function$
;

-- public.qcard_is_room_member(p_room_id uuid)
CREATE OR REPLACE FUNCTION public.qcard_is_room_member(p_room_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$ select asix_internal.qcard_is_room_member($1); $function$
;

-- public.qcard_join_permanent_table(p_display_name text)
CREATE OR REPLACE FUNCTION public.qcard_join_permanent_table(p_display_name text DEFAULT 'Player'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_room public.qcard_rooms%rowtype;
  v_join jsonb;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select *
  into v_room
  from public.qcard_rooms
  where room_code = 'ASIX01'
  for update;

  if not found then
    insert into public.qcard_rooms(
      room_code,name,host_user_id,status,max_players,card_price,
      cards_per_player,max_bet,prize_share,platform_share,growth_steps
    )
    values (
      'ASIX01','ASIX მუდმივი მაგიდა',v_uid,'waiting',5,0.10,
      3,20.00,1.0000,0.0000,
      array[70.00,80.00,90.00,100.00]::numeric[]
    )
    on conflict (room_code) do nothing;

    select *
    into v_room
    from public.qcard_rooms
    where room_code = 'ASIX01'
    for update;

    insert into public.qcard_game_state(room_id)
    values (v_room.id)
    on conflict (room_id) do nothing;
  end if;

  -- Preserve the table's currently selected 1–5 card setting.
  -- The default of 3 cards is applied only when this legacy room is first created.
  update public.qcard_rooms
     set card_price=0.10,
         prize_share=1.0000,
         platform_share=0.0000,
         growth_steps=array[70.00,80.00,90.00,100.00]::numeric[],
         updated_at=now()
   where id=v_room.id;

  v_join := public.qcard_join_room('ASIX01', p_display_name);

  return v_join || jsonb_build_object(
    'name',v_room.name,
    'max_players',5,
    'permanent',true
  );
end;
$function$
;

-- public.qcard_join_public_room(p_room_id uuid, p_display_name text, p_amount_tetri bigint)
CREATE OR REPLACE FUNCTION public.qcard_join_public_room(p_room_id uuid, p_display_name text, p_amount_tetri bigint)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
 select asix_internal.qcard_join_public_room($1,$2,$3)
   || jsonb_build_object('host_user_id',(select host_user_id from public.qcard_rooms where id=$1));
$function$
;

-- public.qcard_join_room(p_room_code text, p_display_name text)
CREATE OR REPLACE FUNCTION public.qcard_join_room(p_room_code text, p_display_name text DEFAULT 'Player'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_room public.qcard_rooms%rowtype;
  v_seat smallint;
  v_phase text;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select * into v_room
  from public.qcard_rooms
  where room_code=upper(trim(p_room_code))
  for update;

  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  if v_room.status in ('finished','cancelled') then
    raise exception 'ROOM_CLOSED';
  end if;

  -- Existing members may reconnect during a hand.
  select seat_no into v_seat
  from public.qcard_seats
  where room_id=v_room.id and user_id=v_uid;

  if v_seat is not null then
    update public.qcard_seats
    set is_connected=true,last_seen_at=now()
    where room_id=v_room.id and user_id=v_uid;

    return jsonb_build_object(
      'room_id',v_room.id,
      'room_code',v_room.room_code,
      'seat_no',v_seat,
      'rejoined',true
    );
  end if;

  -- New players cannot enter after the hand has started, even if the room
  -- status and game-state phase temporarily disagree.
  select coalesce(state->>'phase','waiting')
    into v_phase
  from public.qcard_game_state
  where room_id=v_room.id
  for update;

  if v_room.status='playing' or coalesce(v_phase,'waiting')='playing' then
    raise exception 'GAME_IN_PROGRESS';
  end if;

  select gs.seat_no into v_seat
  from generate_series(1,v_room.max_players) as gs(seat_no)
  where not exists(
    select 1 from public.qcard_seats q
    where q.room_id=v_room.id and q.seat_no=gs.seat_no
  )
  order by gs.seat_no
  limit 1;

  if v_seat is null then raise exception 'ROOM_FULL'; end if;

  insert into public.qcard_seats(room_id,user_id,display_name,seat_no)
  values(
    v_room.id,
    v_uid,
    left(coalesce(nullif(trim(p_display_name),''),'Player'),32),
    v_seat
  );

  return jsonb_build_object(
    'room_id',v_room.id,
    'room_code',v_room.room_code,
    'seat_no',v_seat,
    'rejoined',false
  );
end;
$function$
;

-- public.qcard_join_room_with_wallet(p_room_code text, p_display_name text, p_amount_tetri bigint)
CREATE OR REPLACE FUNCTION public.qcard_join_room_with_wallet(p_room_code text, p_display_name text DEFAULT 'Player'::text, p_amount_tetri bigint DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
 select x.result || jsonb_build_object('host_user_id',(select host_user_id from public.qcard_rooms where id=(x.result->>'room_id')::uuid))
 from (select asix_internal.qcard_join_room_with_wallet($1,$2,$3) as result) x;
$function$
;

-- public.qcard_ledger_preserve_user_identity()
CREATE OR REPLACE FUNCTION public.qcard_ledger_preserve_user_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  if old.user_id is not null and new.user_id is null then
    new.user_id_snapshot := coalesce(new.user_id_snapshot,old.user_id);
  end if;
  return new;
end;
$function$
;

-- public.qcard_list_public_rooms()
CREATE OR REPLACE FUNCTION public.qcard_list_public_rooms()
 RETURNS TABLE(room_id uuid, name text, status text, max_players smallint, online_players integer, occupied_players integer, card_price numeric, cards_per_player smallint, max_bet numeric, min_entry_tetri bigint, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$ select * from asix_internal.qcard_list_public_rooms(); $function$
;

-- public.qcard_preserve_ledger_action_reference()
CREATE OR REPLACE FUNCTION public.qcard_preserve_ledger_action_reference()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  update public.qcard_money_ledger
     set reference_action_id_snapshot = coalesce(reference_action_id_snapshot,old.id)
   where reference_action_id=old.id;
  return old;
end;
$function$
;

-- public.qcard_preserve_ledger_before_room_delete()
CREATE OR REPLACE FUNCTION public.qcard_preserve_ledger_before_room_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_phase text;
begin
  select state->>'phase' into v_phase
  from public.qcard_game_state
  where room_id=old.id
  for update;

  if old.status='playing' or v_phase='playing' then
    raise exception 'CANNOT_DELETE_ACTIVE_QCARD_ROOM';
  end if;

  update public.qcard_money_ledger
     set details = coalesce(details, '{}'::jsonb) || jsonb_build_object(
       'deleted_room_id', old.id,
       'deleted_room_code', old.room_code,
       'deleted_room_name', old.name,
       'room_deleted_at', now()
     )
   where room_id = old.id;
  return old;
end;
$function$
;

-- public.qcard_prevent_account_delete_during_active_game()
CREATE OR REPLACE FUNCTION public.qcard_prevent_account_delete_during_active_game()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  if exists (
    select 1
    from public.qcard_seats s
    join public.qcard_rooms r on r.id=s.room_id
    left join public.qcard_game_state gs on gs.room_id=r.id
    where s.user_id=old.id
      and (r.status='playing' or gs.state->>'phase'='playing')
  ) then
    raise exception 'CANNOT_DELETE_ACCOUNT_DURING_ACTIVE_QCARD_GAME'
      using errcode='23503';
  end if;

  if exists (
    select 1
    from public.qcard_rooms r
    left join public.qcard_game_state gs on gs.room_id=r.id
    where r.host_user_id=old.id
      and (r.status='playing' or gs.state->>'phase'='playing')
  ) then
    raise exception 'CANNOT_DELETE_HOST_ACCOUNT_DURING_ACTIVE_QCARD_GAME'
      using errcode='23503';
  end if;

  return old;
end;
$function$
;

-- public.qcard_process_action(p_action_id bigint, p_actor_user_id uuid)
CREATE OR REPLACE FUNCTION public.qcard_process_action(p_action_id bigint, p_actor_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
AS $function$
declare
  a public.qcard_actions%rowtype;
  v_room_id uuid;
  r public.qcard_rooms%rowtype;
  g public.qcard_game_state%rowtype;
  st jsonb;
  res jsonb;
  deck jsonb := '[]'::jsonb;
  v_hand jsonb;
  card jsonb;
  trump_card jsonb;
  players jsonb;
  player jsonb;
  played jsonb;
  queue jsonb;
  weights numeric[];
  v_initial_pct numeric;
  suits text[] := array['♠','♥','♦','♣'];
  ranks text[] := array['A','K','Q','J','10','9','8','7','6'];
  uid uuid;
  winner uuid;
  next_uid uuid;
  last_cutter uuid;
  raise_owner uuid;
  turn_uid uuid;
  -- Removed local seat_no variable: it shadowed qcard_seats.seat_no (SQLSTATE 42702).
  next_seat integer;
  i integer;
  j integer;
  idx integer;
  n_players integer;
  active_count integer;
  card_count integer;
  card_cost bigint;
  commission_fee bigint;
  sales bigint;
  initial_prize bigint;
  growth_budget bigint;
  growth_added bigint;
  growth_target bigint;
  growth_stage integer;
  reserve bigint;
  pot bigint;
  side_amount bigint;
  pending_raise bigint;
  amount bigint;
  stack bigint;
  paid bigint;
  v_hand_count integer;
  v_seat smallint;
  v_name text;
  v_action text;
  v_phase text;
  v_trump text;
  v_top jsonb;
  v_error text;
  v_dealer smallint;
  v_current_seat integer;
  v_found boolean;
  v_player_count integer;
  v_total_payout bigint;
  v_contrib jsonb;
  v_contrib_value bigint;
  v_new_version bigint;
  v_side_result jsonb;
  v_side_built jsonb;
  v_side_awards jsonb;
  v_side_payout record;
  v_winner_payout bigint;
  v_refund record;
  v_refund_total bigint;
  v_refund_amount bigint;
  v_plan jsonb;
  v_due jsonb;
  v_funds jsonb;
  max_table_pool bigint;
  growth_factor numeric;
begin
  -- Lock the room before the action row so concurrent requests cannot
  -- overtake an earlier queued action in the same room.
  select room_id into v_room_id from public.qcard_actions where id=p_action_id;
  if not found then raise exception 'ACTION_NOT_FOUND'; end if;
  perform 1 from public.qcard_rooms where id=v_room_id for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  select * into a from public.qcard_actions where id=p_action_id for update;
  if not found then raise exception 'ACTION_NOT_FOUND'; end if;
  if a.actor_user_id is distinct from p_actor_user_id then raise exception 'ACTOR_MISMATCH'; end if;
  if a.status='applied' or a.status='rejected' then
    return coalesce(a.result,jsonb_build_object('ok',a.status='applied','duplicate',true));
  end if;
  if a.status not in ('pending','processing') then raise exception 'INVALID_ACTION_STATUS'; end if;

  -- A later request must wait until every earlier room action has been handled.
  -- This preserves click order when concurrent network requests reach Postgres
  -- in a different order from the order in which players submitted them.
  IF EXISTS (
    SELECT 1 FROM public.qcard_actions older
    WHERE older.room_id=a.room_id
      AND older.id<a.id
      AND older.status IN ('pending','processing')
  ) THEN
    RETURN jsonb_build_object(
      'ok',false,
      'queued',true,
      'error','ACTION_WAITING_FOR_PREVIOUS',
      'blocked_by_action_id',(
        SELECT min(older.id) FROM public.qcard_actions older
        WHERE older.room_id=a.room_id
          AND older.id<a.id
          AND older.status IN ('pending','processing')
      )
    );
  END IF;

  -- The room row is already locked above, before the action row.
  select * into r from public.qcard_rooms where id=a.room_id;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  select * into g from public.qcard_game_state where room_id=a.room_id for update;
  if not found then raise exception 'GAME_STATE_NOT_FOUND'; end if;

  if not exists(select 1 from public.qcard_seats s where s.room_id=a.room_id and s.user_id=p_actor_user_id) then
    raise exception 'NOT_A_ROOM_MEMBER';
  end if;
  if g.version <> a.expected_version then
    res:=jsonb_build_object('ok',false,'error','STALE_GAME_STATE','version',g.version);
    update public.qcard_actions set status='rejected',result=res,processed_at=now() where id=a.id;
    return res;
  end if;

  st:=g.state;
  v_phase:=coalesce(st->>'phase','waiting');
  -- Preserve the schedule selected when this deal began.
  if v_phase='playing' then
    select array_agg(e.value::numeric order by e.ordinality)
      into weights
    from jsonb_array_elements_text(coalesce(st->'growth_weights','[]'::jsonb))
      with ordinality e(value,ordinality);
    if weights is null or array_length(weights,1)<>4 then
      raise exception 'INVALID_PRIZE_GROWTH_SCHEDULE';
    end if;
  end if;
  v_action:=a.action_type;

  -- START / FIRST DEAL.
  if v_action in ('start','redeal') then
    if r.host_user_id is distinct from p_actor_user_id then v_error:='HOST_ONLY'; end if;
    if v_action='start' and (r.status<>'waiting' or v_phase<>'waiting') then v_error:='GAME_ALREADY_STARTED'; end if;
    if v_action='redeal' and not ((r.status='finished' and v_phase='finished') or (r.status='cancelled' and v_phase='cancelled')) then v_error:='GAME_NOT_FINISHED'; end if;
    card_cost:=round(r.card_price*100)::bigint*r.cards_per_player;
    commission_fee:=0;
    select commission_rate_bps::bigint into commission_fee
    from public.asix_platform_commission_settings
    where id=1 and enabled=true and recipient_user_id is not null
    for share;
    if not found then v_error:='PLATFORM_COMMISSION_NOT_CONFIGURED'; end if;
    commission_fee:=coalesce(commission_fee,0);
    if commission_fee<0 or commission_fee>10000 then v_error:='INVALID_PLATFORM_COMMISSION_RATE'; end if;
    -- Validate entry balances before changing anyone's connection state.
    -- If fewer than two players can afford the deal, reject without disconnecting them.
    if exists(select 1 from public.qcard_seats where room_id=a.room_id and is_connected and stack_tetri is null) then
      v_error:='ENTRY_BALANCE_REQUIRED';
    end if;
    select count(*) into n_players from public.qcard_seats
      where room_id=a.room_id and is_connected and stack_tetri is not null and stack_tetri>=card_cost;
    if n_players<2 and v_error is null then v_error:='NOT_ENOUGH_PLAYERS'; end if;
    if v_error is not null then
      res:=jsonb_build_object('ok',false,'error',v_error);
      update public.qcard_actions set status='rejected',result=res,processed_at=now() where id=a.id;
      return res;
    end if;
    update public.qcard_seats set is_connected=false,last_seen_at=now()
      where room_id=a.room_id and is_connected and stack_tetri is not null and stack_tetri<card_cost;
    if v_error is not null then
      res:=jsonb_build_object('ok',false,'error',v_error);
      update public.qcard_actions set status='rejected',result=res,processed_at=now() where id=a.id;
      return res;
    end if;

    -- Exact 36-card deck: remove 6♠ and 6♣; retain 6♥ and 6♦.
    for i in 1..4 loop
      for j in 1..9 loop
        if not (ranks[j]='6' and suits[i] in ('♠','♣')) then
          deck:=deck||jsonb_build_array(jsonb_build_object('s',suits[i],'r',ranks[j]));
        end if;
      end loop;
    end loop;
    deck:=deck||jsonb_build_array(
      jsonb_build_object('s','★','r','JOKER','jokerColor','red'),
      jsonb_build_object('s','★','r','JOKER','jokerColor','black')
    );
    if jsonb_array_length(deck)<>36 then raise exception 'INVALID_DECK_SIZE'; end if;
    select jsonb_agg(value order by random()) into deck from jsonb_array_elements(deck) x(value);

    delete from public.qcard_private_hands where room_id=a.room_id;
    players:='[]'::jsonb;
    idx:=0;
    sales:=n_players*card_cost-round((n_players::numeric*card_cost::numeric*commission_fee::numeric)/10000)::bigint;
    -- The fee has already been removed from gross card sales above.
    -- Four cumulative growth stages distribute the entire net entry-fee pool.
    v_initial_pct:=100.00;
    weights:=array[100.00,100.00,100.00,100.00];
    initial_prize:=sales;
    growth_budget:=0;
    max_table_pool:=sales;
    reserve:=0;
    growth_added:=0;

    -- Deal in rounds, clockwise by seat number. This matches the local game.
    for v_seat,v_name,uid,stack in
      select s.seat_no,s.display_name,s.user_id,s.stack_tetri
      from public.qcard_seats s
      where s.room_id=a.room_id and s.is_connected
      order by s.seat_no
    loop
      update public.qcard_seats set stack_tetri=stack_tetri-card_cost
       where room_id=a.room_id and user_id=uid;
      insert into public.qcard_money_ledger(room_id,user_id,entry_type,amount_tetri,reference_action_id,details)
      values(a.room_id,uid,'card_purchase',card_cost,a.id,jsonb_build_object('cards_per_player',r.cards_per_player,'card_price_tetri',round(r.card_price*100)::bigint));
      v_hand:='[]'::jsonb;
      for j in 1..r.cards_per_player loop
        v_hand:=v_hand||jsonb_build_array(deck->idx); idx:=idx+1;
      end loop;
      insert into public.qcard_private_hands(room_id,user_id,hand) values(a.room_id,uid,v_hand);
      players:=players||jsonb_build_array(jsonb_build_object(
        'user_id',uid,'seat_no',v_seat,'display_name',v_name,
        'cards_count',jsonb_array_length(v_hand),'folded',false,'all_in',(stack-card_cost)=0,
        'stack_tetri',stack-card_cost
      ));
    end loop;
    trump_card:=deck->idx;
    v_trump:=case when trump_card->>'s'='★' then null else trump_card->>'s' end;
    -- First deal starts at the lowest occupied seat. Every redeal moves
    -- the dealer one connected seat clockwise, skipping disconnected seats.
    if v_action='redeal' and nullif(st->>'dealer_seat','') is not null then
      select user_id,seat_no into turn_uid,v_dealer
      from public.qcard_seats
      where room_id=a.room_id and is_connected
      order by case when seat_no > (st->>'dealer_seat')::smallint then 0 else 1 end,
               seat_no
      limit 1;
    else
      select user_id,seat_no into turn_uid,v_dealer
      from public.qcard_seats
      where room_id=a.room_id and is_connected
      order by seat_no
      limit 1;
    end if;

    -- Record the initial prize allocation. No platform reserve is deducted:
    -- the complete net entry-fee amount is the deal's playable prize pool.
    insert into public.qcard_money_ledger(room_id,user_id,entry_type,amount_tetri,reference_action_id,details)
    values(a.room_id,null,'prize_allocation',initial_prize,a.id,jsonb_build_object('source','player_count_based_starting_prize','player_count',n_players,'initial_prize_percent',v_initial_pct,'gross_entry_fee_tetri',n_players*card_cost,'sales_tetri',sales,'commission_total_tetri',n_players*card_cost-sales,'net_entry_fee_pool_tetri',sales,'growth_budget_tetri',growth_budget,'max_table_pool_tetri',max_table_pool,'reserve_tetri',0,'growth_targets_percent',to_jsonb(weights)));

    st:=jsonb_build_object(
      'phase','playing','deal_started_at',now(),'turn_started_at',now(),'dealer_seat',v_dealer,'current_turn_user_id',turn_uid,
      'trump_suit',v_trump,'trump_card',trump_card,'top_card',null,'last_cutter_user_id',null,
      'pot_tetri',initial_prize,'side_tetri',0,'played_cards','[]'::jsonb,
      'players',players,'pending_raise_tetri',0,'raise_owner_user_id',null,
      'raise_queue','[]'::jsonb,'successful_cuts',0,
      'pot_start_tetri',initial_prize,'entry_action_id',a.id,'entry_fee_gross_tetri',n_players*card_cost,'platform_commission_tetri',n_players*card_cost-sales,'prize_pool_tetri',sales,'commission_rate_bps',commission_fee,
      'growth_budget_tetri',growth_budget,'growth_added_tetri',growth_added,
      'growth_weights',to_jsonb(weights),'initial_prize_percent',v_initial_pct,'player_count',n_players,
      'growth_reserve_tetri',reserve,'max_table_pool_tetri',max_table_pool,
      'deck_remaining',36-idx-1,'current_bet_tetri',0,'betting_contributions','{}'::jsonb,'round_contributions','{}'::jsonb
    );
    update public.qcard_rooms set status='playing',server_heartbeat_at=now(),updated_at=now() where id=a.room_id;
    update public.qcard_game_state set state=st,version=version+1,updated_at=now() where room_id=a.room_id;
    res:=jsonb_build_object('ok',true,'action',v_action,'players',n_players,'cards_per_player',r.cards_per_player,'trump_suit',v_trump,'deck_size',36);

  -- PLAYER ACTIONS.
  elsif v_action in ('play_card','fold','raise','call','timeout_skip') then
    if r.status<>'playing' or v_phase<>'playing' then v_error:='GAME_NOT_PLAYING'; end if;
    turn_uid:=nullif(st->>'current_turn_user_id','')::uuid;
    if turn_uid is distinct from p_actor_user_id then v_error:='NOT_YOUR_TURN'; end if;
    select value into player from jsonb_array_elements(coalesce(st->'players','[]'::jsonb)) e(value)
      where value->>'user_id'=p_actor_user_id::text limit 1;
    if player is null then v_error:='PLAYER_NOT_FOUND'; end if;
    if coalesce((player->>'folded')::boolean,false) then v_error:='PLAYER_FOLDED'; end if;
    if v_action in ('raise','call') and coalesce((player->>'all_in')::boolean,false) then v_error:='PLAYER_ALREADY_ALL_IN'; end if;
    if v_error is not null then
      res:=jsonb_build_object('ok',false,'error',v_error);
      update public.qcard_actions set status='rejected',result=res,processed_at=now() where id=a.id;
      return res;
    end if;

    players:=st->'players'; played:=coalesce(st->'played_cards','[]'::jsonb);
    queue:=coalesce(st->'raise_queue','[]'::jsonb);
    pot:=coalesce((st->>'pot_tetri')::bigint,0);
    max_table_pool:=coalesce((st->>'max_table_pool_tetri')::bigint,pot);
    side_amount:=coalesce((st->>'side_tetri')::bigint,0);
    pending_raise:=coalesce((st->>'pending_raise_tetri')::bigint,0);
    v_trump:=st->>'trump_suit';
    v_top:=nullif(st->'top_card','null'::jsonb);
    last_cutter:=nullif(st->>'last_cutter_user_id','')::uuid;
    select stack_tetri,seat_no into stack,v_seat from public.qcard_seats
      where room_id=a.room_id and user_id=p_actor_user_id for update;
    v_current_seat:=v_seat;

    if v_action='play_card' then
      if pending_raise>0 then v_error:='RAISE_RESPONSE_REQUIRED'; end if;
      begin idx:=(a.payload->>'card_index')::integer; exception when others then idx:=-1; end;
      select h.hand into v_hand from public.qcard_private_hands h
        where room_id=a.room_id and user_id=p_actor_user_id for update;
      if v_hand is null or idx<0 or idx>=jsonb_array_length(v_hand) then v_error:='INVALID_CARD_INDEX'; end if;
      if v_error is null then
        card:=v_hand->idx;
        if v_top is not null and not public.qcard_card_beats(card,v_top,v_trump) then v_error:='CARD_CANNOT_BEAT'; end if;
      end if;
      if v_error is not null then
        -- A rejected card attempt is still an active player interaction.
        -- Refresh presence so disconnect-timeout cannot auto-fold this player.
        if v_error = 'CARD_CANNOT_BEAT' then
          update public.qcard_seats set is_connected=true,last_seen_at=now()
          where room_id=a.room_id and user_id=p_actor_user_id;
        end if;
        res:=jsonb_build_object('ok',false,'error',v_error);
        update public.qcard_actions set status='rejected',result=res,processed_at=now() where id=a.id;
        return res;
      end if;
      select coalesce(jsonb_agg(value order by ord),'[]'::jsonb) into v_hand
      from jsonb_array_elements(v_hand) with ordinality x(value,ord) where ord<>idx+1;
      update public.qcard_private_hands set hand=v_hand,updated_at=now() where room_id=a.room_id and user_id=p_actor_user_id;
      played:=played||jsonb_build_array(jsonb_build_object('user_id',p_actor_user_id,'card',card));
      last_cutter:=p_actor_user_id;
      growth_stage:=coalesce((st->>'successful_cuts')::integer,0);
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
      end if;
      st:=jsonb_set(st,'{top_card}',card,true);
      st:=jsonb_set(st,'{last_cutter_user_id}',to_jsonb(last_cutter),true);
      st:=jsonb_set(st,'{played_cards}',played,true);
      st:=jsonb_set(st,'{pot_tetri}',to_jsonb(pot),true);
      st:=jsonb_set(st,'{successful_cuts}',to_jsonb(growth_stage+1),true);
      st:=jsonb_set(st,'{growth_added_tetri}',to_jsonb(growth_added),true);
      players:=(select jsonb_agg(case when value->>'user_id'=p_actor_user_id::text
        then jsonb_set(value,'{cards_count}',to_jsonb(jsonb_array_length(v_hand)),true)
        else value end order by ord)
        from jsonb_array_elements(players) with ordinality x(value,ord));
      st:=jsonb_set(st,'{players}',players,true);

    elsif v_action='fold' then
      if pending_raise>0 and (jsonb_array_length(queue)=0 or queue->>0<>p_actor_user_id::text) then v_error:='NOT_RAISE_RESPONSE_TURN'; end if;
      if v_error is not null then
        -- A rejected card attempt is still an active player interaction.
        -- Refresh presence so disconnect-timeout cannot auto-fold this player.
        if v_error = 'CARD_CANNOT_BEAT' then
          update public.qcard_seats set is_connected=true,last_seen_at=now()
          where room_id=a.room_id and user_id=p_actor_user_id;
        end if;
        res:=jsonb_build_object('ok',false,'error',v_error);
        update public.qcard_actions set status='rejected',result=res,processed_at=now() where id=a.id;
        return res;
      end if;
      -- A final active player cannot fold away the only possible winner.
      -- Keep the sole survivor active so the common settlement block awards the pot.
      if (select count(*) from jsonb_array_elements(players) x(value)
          where coalesce((value->>'folded')::boolean,false)=false) > 1 then
        players:=(select jsonb_agg(case when value->>'user_id'=p_actor_user_id::text
          then jsonb_set(value,'{folded}','true'::jsonb,true) else value end order by ord)
          from jsonb_array_elements(players) with ordinality x(value,ord));
        st:=jsonb_set(st,'{players}',players,true);
      end if;

    elsif v_action='raise' then
      begin amount:=(a.payload->>'amount_tetri')::bigint; exception when others then amount:=0; end;
      v_contrib:=coalesce(st->'betting_contributions','{}'::jsonb);
      v_contrib_value:=coalesce((v_contrib->>p_actor_user_id::text)::bigint,0);
      begin
        v_plan:=public.qcard_raise_plan(coalesce((st->>'current_bet_tetri')::bigint,0),v_contrib_value,amount,stack,round(r.max_bet*100)::bigint);
      exception when others then
        res:=jsonb_build_object('ok',false,'error',sqlerrm);
        update public.qcard_actions set status='rejected',result=res,processed_at=now() where id=a.id;
        return res;
      end;
      paid:=(v_plan->>'payment_tetri')::bigint;
      update public.qcard_seats set stack_tetri=stack_tetri-paid where room_id=a.room_id and user_id=p_actor_user_id;
      insert into public.qcard_money_ledger(room_id,user_id,entry_type,amount_tetri,reference_action_id,details)
      values(a.room_id,p_actor_user_id,'manual_raise',paid,a.id,jsonb_build_object('raise_increment_tetri',greatest(0,amount-coalesce((st->>'current_bet_tetri')::bigint,0)),'new_current_bet_tetri',v_plan->'new_current_bet_tetri'));
      side_amount:=side_amount+paid;
      v_contrib:=public.qcard_add_contribution(v_contrib,p_actor_user_id,paid);
      st:=jsonb_set(st,'{betting_contributions}',v_contrib,true);
      st:=jsonb_set(st,'{round_contributions}',public.qcard_add_contribution(coalesce(st->'round_contributions','{}'::jsonb),p_actor_user_id,paid),true);
      
      st:=jsonb_set(st,'{raise_increment_tetri}',to_jsonb(greatest(0,amount-coalesce((st->>'current_bet_tetri')::bigint,0))),true);
      st:=jsonb_set(st,'{current_bet_tetri}',v_plan->'new_current_bet_tetri',true);
      players:=(select jsonb_agg(case when value->>'user_id'=p_actor_user_id::text then
        jsonb_set(jsonb_set(value,'{all_in}',to_jsonb((v_plan->>'all_in')::boolean),true),'{stack_tetri}',to_jsonb(stack-paid),true)
        else value end order by ord) from jsonb_array_elements(players) with ordinality x(value,ord));
      st:=jsonb_set(st,'{players}',players,true);
      queue:='[]'::jsonb;
      for uid,next_seat in select (value->>'user_id')::uuid,(value->>'seat_no')::smallint
        from jsonb_array_elements(players) x(value)
        where value->>'user_id'<>p_actor_user_id::text
          and coalesce((value->>'folded')::boolean,false)=false
          and coalesce((value->>'all_in')::boolean,false)=false
          and coalesce((value->>'cards_count')::integer,0)>0
        order by case when (value->>'seat_no')::integer>v_current_seat then 0 else 1 end,(value->>'seat_no')::integer
      loop queue:=queue||jsonb_build_array(uid); end loop;
      pending_raise:=(v_plan->>'new_current_bet_tetri')::bigint;
      st:=jsonb_set(st,'{raise_owner_user_id}',to_jsonb(p_actor_user_id),true);
      

    elsif v_action='call' then
      if pending_raise<=0 then v_error:='NO_PENDING_RAISE'; end if;
      if jsonb_array_length(queue)=0 or queue->>0<>p_actor_user_id::text then v_error:='NOT_RAISE_RESPONSE_TURN'; end if;
      if v_error is not null then
        -- A rejected card attempt is still an active player interaction.
        -- Refresh presence so disconnect-timeout cannot auto-fold this player.
        if v_error = 'CARD_CANNOT_BEAT' then
          update public.qcard_seats set is_connected=true,last_seen_at=now()
          where room_id=a.room_id and user_id=p_actor_user_id;
        end if;
        res:=jsonb_build_object('ok',false,'error',v_error);
        update public.qcard_actions set status='rejected',result=res,processed_at=now() where id=a.id;
        return res;
      end if;
      v_contrib:=coalesce(st->'betting_contributions','{}'::jsonb);
      v_contrib_value:=coalesce((v_contrib->>p_actor_user_id::text)::bigint,0);
      v_due:=public.qcard_call_payment(coalesce((st->>'current_bet_tetri')::bigint,pending_raise),v_contrib_value,stack);
      paid:=(v_due->>'payment_tetri')::bigint;
      update public.qcard_seats set stack_tetri=stack_tetri-paid where room_id=a.room_id and user_id=p_actor_user_id;
      insert into public.qcard_money_ledger(room_id,user_id,entry_type,amount_tetri,reference_action_id,details)
      values(a.room_id,p_actor_user_id,'raise_call',paid,a.id,jsonb_build_object('call_due_tetri',v_due->'call_due_tetri','call_tetri',paid,'all_in',v_due->'all_in'));
      side_amount:=side_amount+paid;
      st:=jsonb_set(st,'{betting_contributions}',public.qcard_add_contribution(v_contrib,p_actor_user_id,paid),true);
      st:=jsonb_set(st,'{round_contributions}',public.qcard_add_contribution(coalesce(st->'round_contributions','{}'::jsonb),p_actor_user_id,paid),true);
      players:=(select jsonb_agg(case when value->>'user_id'=p_actor_user_id::text then
        jsonb_set(jsonb_set(value,'{all_in}',to_jsonb((v_due->>'all_in')::boolean or coalesce((value->>'all_in')::boolean,false)),true),'{stack_tetri}',to_jsonb(stack-paid),true)
        else value end order by ord) from jsonb_array_elements(players) with ordinality x(value,ord));
      st:=jsonb_set(st,'{players}',players,true);
    end if;

    if v_action in ('call','fold') and pending_raise>0 and jsonb_array_length(queue)>0 and queue->>0=p_actor_user_id::text then
      select coalesce(jsonb_agg(value order by ord),'[]'::jsonb) into queue
        from jsonb_array_elements(queue) with ordinality x(value,ord) where ord>1;
    end if;
    st:=jsonb_set(st,'{side_tetri}',to_jsonb(side_amount),true);
    st:=jsonb_set(st,'{pending_raise_tetri}',to_jsonb(case when jsonb_array_length(queue)=0 then 0 else pending_raise end),true);
    st:=jsonb_set(st,'{raise_queue}',queue,true);
    if jsonb_array_length(queue)=0 then
      st:=jsonb_set(st,'{raise_owner_user_id}','null'::jsonb,true);
      st:=jsonb_set(st,'{current_bet_tetri}','0'::jsonb,true);
      st:=jsonb_set(st,'{betting_contributions}','{}'::jsonb,true);
    end if;

    -- Determine next actor. If responding to a raise, next queue member;
    -- otherwise next clockwise seat with cards who is not folded or last cutter.
    if jsonb_array_length(queue)>0 then
      next_uid:=(queue->>0)::uuid;
    else
      pending_raise:=0;
      select seat_no into v_current_seat from public.qcard_seats where room_id=a.room_id and user_id=p_actor_user_id;
      select (value->>'user_id')::uuid into next_uid
      from jsonb_array_elements(coalesce(st->'players','[]'::jsonb)) x(value)
      where coalesce((value->>'folded')::boolean,false)=false
        and coalesce((value->>'cards_count')::integer,0)>0
        and (value->>'user_id')::uuid<>coalesce(last_cutter,p_actor_user_id)
      order by case when (value->>'seat_no')::integer>v_current_seat then 0 else 1 end,(value->>'seat_no')::integer
      limit 1;
      -- If the last cutter just played, search clockwise from their seat.
      if v_action in ('play_card','timeout_skip') then
        select seat_no into v_current_seat from public.qcard_seats where room_id=a.room_id and user_id=p_actor_user_id;
        select (value->>'user_id')::uuid into next_uid
        from jsonb_array_elements(st->'players') x(value)
        where coalesce((value->>'folded')::boolean,false)=false
          and coalesce((value->>'cards_count')::integer,0)>0
          and (value->>'user_id')::uuid<>p_actor_user_id
        order by case when (value->>'seat_no')::integer>v_current_seat then 0 else 1 end,(value->>'seat_no')::integer
        limit 1;
      end if;
    end if;

    select count(*) into active_count from jsonb_array_elements(st->'players') x(value)
      where coalesce((value->>'folded')::boolean,false)=false;
    select coalesce(sum((value->>'cards_count')::integer),0) into card_count
      from jsonb_array_elements(st->'players') x(value)
      where coalesce((value->>'folded')::boolean,false)=false;

    -- End exactly when one active player remains, all active hands are empty,
    -- or there is no next eligible actor. Award the whole single main pool.
    if active_count<=1 or card_count=0 or next_uid is null then
      -- Winner is the most recent successful cutter who has not folded.
      -- If no cutter remains eligible, only a sole remaining player may win.
      winner:=null;
      for idx in reverse jsonb_array_length(coalesce(st->'played_cards','[]'::jsonb))-1..0 loop
        if coalesce(st->'played_cards'->idx,'{}'::jsonb) ? 'user_id'
           and exists(
             select 1 from jsonb_array_elements(st->'players') x(value)
             where value->>'user_id'=st->'played_cards'->idx->>'user_id'
               and coalesce((value->>'folded')::boolean,false)=false
           ) then
          winner:=(st->'played_cards'->idx->>'user_id')::uuid;
          exit;
        end if;
      end loop;
      if winner is null and active_count=1 then
        select (value->>'user_id')::uuid into winner
        from jsonb_array_elements(st->'players') x(value)
        where coalesce((value->>'folded')::boolean,false)=false
        limit 1;
      end if;
      if winner is null then
        raise exception 'NO_ELIGIBLE_MAIN_POT_WINNER';
      end if;
      -- Award all money actually on the table (main pot + every contested side-pot layer)
      -- to the final round winner. Uncalled excess contributions are still refunded.
      v_side_built:=public.qcard_build_side_pots(
        coalesce(st->'round_contributions','{}'::jsonb),
        coalesce(st->'players','[]'::jsonb)
      );
      v_side_awards := public.qcard_allocate_side_pots(
        coalesce(v_side_built->'pots','[]'::jsonb),
        coalesce(st->'played_cards','[]'::jsonb)
      );
      -- Pay the complete net entry-fee pool at settlement, including
      -- growth stages not yet visually released during the deal.
      v_total_payout := coalesce(
        (st->>'max_table_pool_tetri')::bigint,
        (st->>'pot_tetri')::bigint,
        0
      );

      v_refund_total:=0;
      for v_refund in
        select key,value from jsonb_each(coalesce(v_side_built->'refunds','{}'::jsonb))
      loop
        v_refund_amount:=v_refund.value::text::bigint;
        if v_refund_amount>0 then
          update public.qcard_seats
             set stack_tetri=coalesce(stack_tetri,0)+v_refund_amount
           where room_id=a.room_id and user_id=v_refund.key::uuid;
          if not found then raise exception 'UNCALLED_REFUND_SEAT_NOT_FOUND'; end if;
          insert into public.qcard_money_ledger(room_id,user_id,entry_type,amount_tetri,reference_action_id,details)
          values(a.room_id,v_refund.key::uuid,'uncalled_bet_refund',v_refund_amount,a.id,jsonb_build_object('source','uncalled_excess'));
          v_refund_total:=v_refund_total+v_refund_amount;
        end if;
      end loop;
      v_side_result:=v_side_built||jsonb_build_object(
        'winner_user_id',winner,
        'pots',v_side_awards->'pots',
        'side_pot_payouts',v_side_awards->'payouts',
        'side_pot_total_tetri',coalesce((v_side_awards->>'total_tetri')::bigint,0),
        'paid_to_round_winner_tetri',
          v_total_payout + coalesce((v_side_awards->'payouts'->>winner::text)::bigint,0),
        'refunded_total_tetri',v_refund_total
      );

      growth_budget:=coalesce((st->>'growth_budget_tetri')::bigint,0);
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
      v_winner_payout:=v_total_payout;
      if winner is not null and v_total_payout>0 then
        update public.qcard_seats set stack_tetri=stack_tetri+v_total_payout where room_id=a.room_id and user_id=winner;
        if not found then raise exception 'MAIN_POT_WINNER_SEAT_NOT_FOUND'; end if;
        insert into public.qcard_money_ledger(room_id,user_id,entry_type,amount_tetri,reference_action_id,details)
        values(a.room_id,winner,'prize_payout',v_total_payout,a.id,jsonb_build_object('ruleset','B','main_entry_prize_pool',true));
      end if;

      for v_side_payout in
        select key,value from jsonb_each(coalesce(v_side_awards->'payouts','{}'::jsonb))
      loop
        v_refund_amount:=v_side_payout.value::text::bigint;
        update public.qcard_seats
          set stack_tetri=coalesce(stack_tetri,0)+v_refund_amount
        where room_id=a.room_id and user_id=v_side_payout.key::uuid;
        if not found then raise exception 'SIDE_POT_WINNER_SEAT_NOT_FOUND'; end if;
        insert into public.qcard_money_ledger(room_id,user_id,entry_type,amount_tetri,reference_action_id,details)
        values(a.room_id,v_side_payout.key::uuid,'side_pot_payout',v_refund_amount,a.id,
          jsonb_build_object('source','eligible_side_pot_layers','side_pot_payouts',v_side_awards->'pots'));
        if v_side_payout.key=winner::text then
          v_winner_payout:=v_winner_payout+v_refund_amount;
        end if;
      end loop;

      -- Reconcile every in-game player's saved stack with the authoritative
      -- seat balance after main-pot, side-pot and uncalled-refund settlements.
      players := (
        select jsonb_agg(
          jsonb_set(
            x.value,
            '{stack_tetri}',
            to_jsonb(coalesce(
              s.stack_tetri,
              nullif(x.value->>'stack_tetri','')::bigint,
              0
            )),
            true
          )
          order by x.ord
        )
        from jsonb_array_elements(coalesce(st->'players','[]'::jsonb))
          with ordinality as x(value,ord)
        left join public.qcard_seats s
          on s.room_id=a.room_id
         and s.user_id=(x.value->>'user_id')::uuid
      );
      st:=jsonb_set(st,'{players}',coalesce(players,'[]'::jsonb),true);

      st:=jsonb_set(st,'{winner_prize_tetri}',to_jsonb(v_winner_payout),true);
      st:=jsonb_set(st,'{phase}',to_jsonb('finished'::text),true);
      st:=jsonb_set(st,'{winner_user_id}',coalesce(to_jsonb(winner),'null'::jsonb),true);
      st:=jsonb_set(st,'{pot_tetri}','0'::jsonb,true);
      st:=jsonb_set(st,'{side_tetri}','0'::jsonb,true);
      st:=jsonb_set(st,'{side_pot_settlement}',coalesce(v_side_result,'{}'::jsonb),true);
      st:=jsonb_set(st,'{pending_raise_tetri}','0'::jsonb,true);
      st:=jsonb_set(st,'{current_turn_user_id}','null'::jsonb,true);
      st:=jsonb_set(st,'{turn_started_at}','null'::jsonb,true);
      update public.qcard_rooms set status='finished' where id=a.room_id;
    else
      st:=jsonb_set(st,'{current_turn_user_id}',to_jsonb(next_uid),true);
      st:=jsonb_set(st,'{turn_started_at}',to_jsonb(now()),true);
    end if;

    update public.qcard_game_state set state=st,version=version+1,updated_at=now() where room_id=a.room_id;
    res:=jsonb_build_object('ok',true,'action',v_action,'phase',st->>'phase',
      'current_turn_user_id',st->'current_turn_user_id','pot_tetri',st->'pot_tetri',
      'side_tetri',st->'side_tetri');

  elsif v_action='ready' then
    update public.qcard_seats set is_ready=true where room_id=a.room_id and user_id=p_actor_user_id;
    res:=jsonb_build_object('ok',true,'action','ready');

  elsif v_action='reconnect' then
    update public.qcard_seats set is_connected=true,last_seen_at=now() where room_id=a.room_id and user_id=p_actor_user_id;
    res:=jsonb_build_object('ok',true,'action','reconnect');

  elsif v_action='leave' then
    update public.qcard_seats set is_connected=false,last_seen_at=now() where room_id=a.room_id and user_id=p_actor_user_id;
    res:=jsonb_build_object('ok',true,'action','leave');

  else
    res:=jsonb_build_object('ok',false,'error','UNSUPPORTED_ACTION');
    update public.qcard_actions set status='rejected',result=res,processed_at=now() where id=a.id;
    return res;
  end if;

  update public.qcard_actions set status='applied',result=res,processed_at=now() where id=a.id;
  return res;
end;
$function$
;

-- public.qcard_process_disconnect_timeouts(p_room_id uuid, p_requester_user_id uuid)
CREATE OR REPLACE FUNCTION public.qcard_process_disconnect_timeouts(p_room_id uuid, p_requester_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
declare
  gs public.qcard_game_state%rowtype;
  target_uid uuid;
  target_seat public.qcard_seats%rowtype;
  target_player jsonb;
  action_id bigint;
  result_json jsonb;
  pending_raise bigint;
  raise_queue jsonb;
  timeout_action text;
begin
  if p_requester_user_id is null or not exists(select 1 from public.qcard_seats where room_id=p_room_id and user_id=p_requester_user_id) then
    raise exception 'NOT_A_ROOM_MEMBER';
  end if;
  perform 1 from public.qcard_rooms where id=p_room_id for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  select * into gs from public.qcard_game_state where room_id=p_room_id for update;
  if not found then raise exception 'GAME_STATE_NOT_FOUND'; end if;
  if coalesce(gs.state->>'phase','')<>'playing' then return jsonb_build_object('ok',true,'processed',false,'reason','NOT_PLAYING'); end if;

  pending_raise:=coalesce((gs.state->>'pending_raise_tetri')::bigint,0);
  raise_queue:=coalesce(gs.state->'raise_queue','[]'::jsonb);
  if pending_raise>0 and jsonb_array_length(raise_queue)>0 then target_uid:=nullif(raise_queue->>0,'')::uuid;
  else target_uid:=nullif(gs.state->>'current_turn_user_id','')::uuid; end if;
  if target_uid is null then return jsonb_build_object('ok',true,'processed',false,'reason','NO_CURRENT_ACTOR'); end if;

  select * into target_seat from public.qcard_seats where room_id=p_room_id and user_id=target_uid for update;
  if not found then return jsonb_build_object('ok',true,'processed',false,'reason','SEAT_NOT_FOUND'); end if;
  if target_seat.is_connected and target_seat.last_seen_at>now()-interval '9 seconds' then
    return jsonb_build_object('ok',true,'processed',false,'reason','PLAYER_STILL_CONNECTED');
  end if;
  if target_seat.last_seen_at>now()-interval '9 seconds' then
    return jsonb_build_object('ok',true,'processed',false,'reason','TIMEOUT_NOT_REACHED');
  end if;

  select x.value into target_player from jsonb_array_elements(coalesce(gs.state->'players','[]'::jsonb)) x(value)
   where x.value->>'user_id'=target_uid::text limit 1;
  if coalesce((target_player->>'all_in')::boolean,false) and pending_raise=0 then
    timeout_action:='timeout_skip';
  else
    timeout_action:='fold';
  end if;
  insert into public.qcard_actions(room_id,actor_user_id,action_type,payload,expected_version)
  values(p_room_id,target_uid,timeout_action,jsonb_build_object('auto_disconnect',true,'timeout_seconds',9),gs.version)
  returning id into action_id;
  result_json:=public.qcard_process_action(action_id,target_uid);
  update public.qcard_seats set is_connected=false where room_id=p_room_id and user_id=target_uid;
  return jsonb_build_object('ok',true,'processed',true,'timed_out_user_id',target_uid,'action_id',action_id,'action',timeout_action,'result',result_json);
end;
$function$
;

-- public.qcard_process_turn_timeout(p_room_id uuid, p_requester_user_id uuid)
CREATE OR REPLACE FUNCTION public.qcard_process_turn_timeout(p_room_id uuid, p_requester_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$ select asix_internal.qcard_process_turn_timeout($1, $2); $function$
;

-- public.qcard_raise_plan(p_current_bet_tetri bigint, p_player_contribution_tetri bigint, p_raise_increment_tetri bigint, p_stack_tetri bigint, p_max_bet_tetri bigint)
CREATE OR REPLACE FUNCTION public.qcard_raise_plan(p_current_bet_tetri bigint, p_player_contribution_tetri bigint, p_raise_increment_tetri bigint, p_stack_tetri bigint, p_max_bet_tetri bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_payment bigint;
begin
  if p_current_bet_tetri is null or p_current_bet_tetri < 0
     or p_player_contribution_tetri is null or p_player_contribution_tetri < 0
     or p_raise_increment_tetri is null or p_raise_increment_tetri <= 0
     or p_stack_tetri is null or p_stack_tetri < 0
     or p_max_bet_tetri is null or p_max_bet_tetri < 0 then
    raise exception 'INVALID_RAISE_INPUT';
  end if;
  if p_raise_increment_tetri > p_max_bet_tetri then
    raise exception 'RAISE_EXCEEDS_MAX_BET';
  end if;
  if p_raise_increment_tetri <= p_current_bet_tetri then
    raise exception 'RERAISE_MUST_EXCEED_CURRENT_RAISE';
  end if;
  v_payment := greatest(0, p_raise_increment_tetri - p_player_contribution_tetri);
  if v_payment > p_stack_tetri then
    raise exception 'INSUFFICIENT_BALANCE_FOR_RAISE';
  end if;
  return jsonb_build_object(
    'raise_increment_tetri', p_raise_increment_tetri,
    'new_current_bet_tetri', p_raise_increment_tetri,
    'payment_tetri', v_payment,
    'remaining_stack_tetri', p_stack_tetri - v_payment,
    'all_in', (v_payment > 0 and p_stack_tetri - v_payment = 0)
  );
end;
$function$
;

-- public.qcard_record_contribution(p_contributions jsonb, p_user_id uuid, p_add_tetri bigint)
CREATE OR REPLACE FUNCTION public.qcard_record_contribution(p_contributions jsonb, p_user_id uuid, p_add_tetri bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_old bigint;
  v_new bigint;
begin
  if p_user_id is null then
    raise exception 'INVALID_USER_ID';
  end if;

  if p_add_tetri is null or p_add_tetri < 0 then
    raise exception 'INVALID_CONTRIBUTION_AMOUNT';
  end if;

  if jsonb_typeof(coalesce(p_contributions, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_CONTRIBUTIONS_OBJECT';
  end if;

  v_old := coalesce(
    (p_contributions ->> p_user_id::text)::bigint,
    0
  );

  if v_old > 9000000000000000 - p_add_tetri then
    raise exception 'CONTRIBUTION_OVERFLOW';
  end if;

  v_new := v_old + p_add_tetri;

  return jsonb_set(
    coalesce(p_contributions, '{}'::jsonb),
    array[p_user_id::text],
    to_jsonb(v_new),
    true
  );
end;
$function$
;

-- public.qcard_recover_pending_action(p_room_id uuid, p_requester_user_id uuid)
CREATE OR REPLACE FUNCTION public.qcard_recover_pending_action(p_room_id uuid, p_requester_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
  v_action public.qcard_actions%rowtype;
  v_result jsonb;
BEGIN
  IF p_requester_user_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.qcard_seats
    WHERE room_id=p_room_id AND user_id=p_requester_user_id
  ) THEN
    RAISE EXCEPTION 'NOT_A_ROOM_MEMBER';
  END IF;

  -- Use the same room-first lock order as qcard_process_action.
  PERFORM 1 FROM public.qcard_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ROOM_NOT_FOUND'; END IF;

  SELECT a.* INTO v_action
  FROM public.qcard_actions a
  WHERE a.room_id=p_room_id
    AND a.status IN ('pending','processing')
    AND a.created_at < now()-interval '2 seconds'
  ORDER BY a.id
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',true,'recovered',false,'reason','NO_RECOVERABLE_ACTION');
  END IF;

  BEGIN
    v_result := public.qcard_process_action(v_action.id,v_action.actor_user_id);
    RETURN jsonb_build_object(
      'ok',true,'recovered',true,
      'action_id',v_action.id,
      'action_status_result',v_result
    );
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'ok',false,'recovered',false,
      'action_id',v_action.id,
      'error',SQLERRM,
      'sqlstate',SQLSTATE
    );
  END;
END;
$function$
;

-- public.qcard_remove_permanent_player(p_target_user_id uuid)
CREATE OR REPLACE FUNCTION public.qcard_remove_permanent_player(p_target_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$ select asix_internal.qcard_remove_permanent_player($1); $function$
;

-- public.qcard_room_preserve_host_identity()
CREATE OR REPLACE FUNCTION public.qcard_room_preserve_host_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  if old.host_user_id is not null and new.host_user_id is null then
    new.host_user_id_snapshot := coalesce(new.host_user_id_snapshot,old.host_user_id);
  end if;
  return new;
end;
$function$
;

-- public.qcard_server_heartbeat(p_room_id uuid, p_requester_user_id uuid)
CREATE OR REPLACE FUNCTION public.qcard_server_heartbeat(p_room_id uuid, p_requester_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  r public.qcard_rooms%rowtype;
  g public.qcard_game_state%rowtype;
  v_started timestamptz;
  v_original record;
  v_refund_count integer := 0;
  v_refund_total bigint := 0;
  v_gap_seconds numeric;
begin
  if p_requester_user_id is null or not exists (
    select 1 from public.qcard_seats
    where room_id=p_room_id and user_id=p_requester_user_id
  ) then
    raise exception 'NOT_A_ROOM_MEMBER';
  end if;

  select * into r from public.qcard_rooms where id=p_room_id for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;

  select * into g from public.qcard_game_state where room_id=p_room_id for update;
  if not found then raise exception 'GAME_STATE_NOT_FOUND'; end if;

  if coalesce(g.state->>'phase','') <> 'playing' or r.status <> 'playing' then
    update public.qcard_rooms set server_heartbeat_at=now()
    where id=p_room_id;
    return jsonb_build_object('ok',true,'cancelled',false,'reason','NOT_PLAYING');
  end if;

  v_gap_seconds := case
    when r.server_heartbeat_at is null then 0
    else extract(epoch from (now()-r.server_heartbeat_at))
  end;

  if r.server_heartbeat_at is not null and v_gap_seconds > 9 then
    begin
      v_started := nullif(g.state->>'deal_started_at','')::timestamptz;
    exception when others then
      v_started := null;
    end;
    if v_started is null then
      raise exception 'DEAL_START_TIMESTAMP_MISSING';
    end if;

    -- Refund every debit made during this deal. Each source ledger row can
    -- be reversed once only; balance update and refund ledger insert are atomic.
    for v_original in
      select l.*
      from public.qcard_money_ledger l
      where l.room_id=p_room_id
        and l.user_id is not null
        and l.entry_type in ('card_purchase','manual_raise','raise_call')
        and l.created_at >= v_started
        and l.reversal_of_ledger_id is null
      order by l.id
      for update
    loop
      insert into public.qcard_money_ledger(
        room_id,user_id,entry_type,amount_tetri,reference_action_id,
        reversal_of_ledger_id,details
      )
      values(
        p_room_id,v_original.user_id,'refund',v_original.amount_tetri,
        v_original.reference_action_id,v_original.id,
        jsonb_build_object('reason','server_heartbeat_gap','reverses_ledger_id',v_original.id)
      )
      on conflict (reversal_of_ledger_id) where reversal_of_ledger_id is not null
      do nothing;

      if found then
        update public.qcard_seats
        set stack_tetri=coalesce(stack_tetri,0)+v_original.amount_tetri
        where room_id=p_room_id and user_id=v_original.user_id;
        if not found then raise exception 'REFUND_PLAYER_SEAT_NOT_FOUND'; end if;
        v_refund_count:=v_refund_count+1;
        v_refund_total:=v_refund_total+v_original.amount_tetri;
      end if;
    end loop;

    delete from public.qcard_private_hands where room_id=p_room_id;
    update public.qcard_game_state
    set state=jsonb_set(
          jsonb_set(
            jsonb_set(g.state,'{phase}',to_jsonb('cancelled'::text),true),
            '{cancel_reason}',to_jsonb('server_heartbeat_gap'::text),true
          ),
          '{current_turn_user_id}','null'::jsonb,true
        ),
        version=version+1,updated_at=now()
    where room_id=p_room_id;

    update public.qcard_rooms
    set status='cancelled',server_heartbeat_at=now(),updated_at=now()
    where id=p_room_id;

    return jsonb_build_object(
      'ok',true,'cancelled',true,'reason','SERVER_HEARTBEAT_GAP',
      'gap_seconds',round(v_gap_seconds,2),
      'refund_entries',v_refund_count,'refund_total_tetri',v_refund_total
    );
  end if;

  update public.qcard_rooms set server_heartbeat_at=now()
  where id=p_room_id;

  return jsonb_build_object('ok',true,'cancelled',false,'gap_seconds',round(v_gap_seconds,2));
end;
$function$
;

-- public.qcard_set_entry_stack(p_room_id uuid, p_amount_tetri bigint)
CREATE OR REPLACE FUNCTION public.qcard_set_entry_stack(p_room_id uuid, p_amount_tetri bigint)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$ select asix_internal.qcard_set_entry_stack($1, $2); $function$
;

-- public.qcard_set_presence(p_room_id uuid, p_connected boolean)
CREATE OR REPLACE FUNCTION public.qcard_set_presence(p_room_id uuid, p_connected boolean)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$ select asix_internal.qcard_set_presence($1, $2); $function$
;

-- public.qcard_submit_action(p_room_id uuid, p_action_type text, p_payload jsonb, p_expected_version bigint)
CREATE OR REPLACE FUNCTION public.qcard_submit_action(p_room_id uuid, p_action_type text, p_payload jsonb DEFAULT '{}'::jsonb, p_expected_version bigint DEFAULT 0)
 RETURNS bigint
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$ select asix_internal.qcard_submit_action($1, $2, $3, $4); $function$
;

-- public.qcard_submit_process_action(p_room_id uuid, p_action_type text, p_payload jsonb, p_expected_version bigint)
CREATE OR REPLACE FUNCTION public.qcard_submit_process_action(p_room_id uuid, p_action_type text, p_payload jsonb DEFAULT '{}'::jsonb, p_expected_version bigint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$ select asix_internal.qcard_submit_process_action($1, $2, $3, $4); $function$
;

-- public.qcard_touch_updated_at()
CREATE OR REPLACE FUNCTION public.qcard_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin
  new.updated_at := now();
  return new;
end;
$function$
;
