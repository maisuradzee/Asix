-- ASIX V148
-- Corrects wallet transaction metadata to record the exact user-selected
-- table starting balance. The per-deal Entry Fee remains card_price × cards_per_player.
-- The already deployed V147 5% whole-table commission formula is preserved.
-- Safe: this migration does not update wallet balances, wallet transactions,
-- active rooms, player stacks, or game history.

do $v148_patch_buyin_metadata$
declare
  v_def text;
  v_old text := '''custom_table_buyin_tetri'',10000';
  v_new text := '''custom_table_buyin_tetri'',v_buyin_tetri';
  v_count integer;
begin
  v_def := pg_get_functiondef(
    'asix_internal.qcard_create_room_with_wallet(text,numeric,integer,integer,numeric,text,bigint)'::regprocedure
  );
  v_count := (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
  if v_count <> 1 then
    raise exception 'V148_CREATE_ROOM_METADATA_EXPECTED_ONE_MATCH_FOUND_%',v_count;
  end if;
  v_def := replace(v_def,v_old,v_new);
  execute v_def;

  v_def := pg_get_functiondef(
    'asix_internal.qcard_join_public_room(uuid,text,bigint)'::regprocedure
  );
  v_count := (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
  if v_count <> 2 then
    raise exception 'V148_JOIN_ROOM_METADATA_EXPECTED_TWO_MATCHES_FOUND_%',v_count;
  end if;
  v_def := replace(v_def,v_old,v_new);
  execute v_def;

  if position(v_old in pg_get_functiondef(
    'asix_internal.qcard_create_room_with_wallet(text,numeric,integer,integer,numeric,text,bigint)'::regprocedure
  )) > 0 then
    raise exception 'V148_CREATE_ROOM_METADATA_VERIFY_FAILED';
  end if;
  if position(v_old in pg_get_functiondef(
    'asix_internal.qcard_join_public_room(uuid,text,bigint)'::regprocedure
  )) > 0 then
    raise exception 'V148_JOIN_ROOM_METADATA_VERIFY_FAILED';
  end if;

  if not exists (
    select 1 from public.asix_platform_commission_settings
    where id=1 and enabled=true and recipient_user_id is not null
      and commission_rate_bps=500
  ) then
    raise exception 'V148_COMMISSION_CONFIGURATION_NOT_5_PERCENT';
  end if;
end;
$v148_patch_buyin_metadata$;

comment on function asix_internal.qcard_create_room_with_wallet(text,numeric,integer,integer,numeric,text,bigint)
  is 'ASIX V148: creates a wallet-backed room and records the exact requested starting stack in transaction metadata. Per-deal Entry Fee remains card_price × cards_per_player.';
comment on function asix_internal.qcard_join_public_room(uuid,text,bigint)
  is 'ASIX V148: joins a wallet-backed room and records the exact requested starting stack in transaction metadata.';
