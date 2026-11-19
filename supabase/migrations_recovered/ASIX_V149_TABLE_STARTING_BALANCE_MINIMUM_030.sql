-- ASIX V149: table starting balance is independent from per-deal Entry Fee.
-- Minimum table starting balance: 0.30 GEL (30 tetri).
-- Per-deal Entry Fee remains calculated separately from card price * cards per player.

do $migration$
declare
  v_def text;
  v_new text;
begin
  v_def := pg_get_functiondef('asix_internal.qcard_create_room_with_wallet(text,numeric,integer,integer,numeric,text,bigint)'::regprocedure);
  v_new := replace(v_def,
    'if p_amount_tetri is null or p_amount_tetri < 1 then raise exception ''INVALID_ENTRY_AMOUNT''; end if;',
    'if p_amount_tetri is null or p_amount_tetri < 30 then raise exception ''TABLE_BUYIN_MINIMUM_0_30''; end if;');
  if v_new = v_def then raise exception 'CREATE_ROOM_AMOUNT_VALIDATION_PATTERN_NOT_FOUND'; end if;
  v_def := v_new;
  v_new := replace(v_def,
    'v_min_entry:=round(v_card_price*100)::bigint*p_cards_per_player; if v_min_entry<10 then raise exception ''ENTRY_FEE_BELOW_MINIMUM_CARD_COST:MINIMUM=0.10''; end if;',
    'v_min_entry:=30;');
  if v_new = v_def then raise exception 'CREATE_ROOM_MINIMUM_PATTERN_NOT_FOUND'; end if;
  execute v_new;

  v_def := pg_get_functiondef('asix_internal.qcard_join_public_room(uuid,text,bigint)'::regprocedure);
  v_new := replace(v_def,
    'if p_amount_tetri is null or p_amount_tetri < 1 then raise exception ''INVALID_ENTRY_AMOUNT''; end if;',
    'if p_amount_tetri is null or p_amount_tetri < 30 then raise exception ''TABLE_BUYIN_MINIMUM_0_30''; end if;');
  if v_new = v_def then raise exception 'JOIN_ROOM_AMOUNT_VALIDATION_PATTERN_NOT_FOUND'; end if;
  v_def := v_new;
  v_new := replace(v_def,
    'v_min_entry_tetri:=round(v_room.card_price*100)::bigint*v_room.cards_per_player;',
    'v_min_entry_tetri:=30;');
  if v_new = v_def then raise exception 'JOIN_ROOM_MINIMUM_PATTERN_NOT_FOUND'; end if;
  execute v_new;
end
$migration$;