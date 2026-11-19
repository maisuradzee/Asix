-- ASIX destination-only bootstrap for a NEW casino-owned Supabase project.
-- Run only after restoring schema.sql and creating the casino's Auth recipient.
-- Replace the marker below with the UUID of the destination Auth user who will
-- receive ASIX commission. Never use the source project's user UUID.
-- This seed contains only non-personal application configuration, not source
-- user records, wallet balances, transaction rows or game history.

begin;

do $bootstrap$
declare
  v_recipient_text text := 'REPLACE_WITH_CASINO_AUTH_USER_UUID';
  v_recipient_id uuid;
begin
  if v_recipient_text = 'REPLACE_WITH_CASINO_AUTH_USER_UUID' then
    raise exception 'SET_DESTINATION_COMMISSION_RECIPIENT_UUID_BEFORE_RUNNING';
  end if;

  begin
    v_recipient_id := v_recipient_text::uuid;
  exception when others then
    raise exception 'INVALID_DESTINATION_COMMISSION_RECIPIENT_UUID';
  end;

  if not exists(select 1 from auth.users where id=v_recipient_id) then
    raise exception 'DESTINATION_COMMISSION_RECIPIENT_NOT_FOUND_IN_AUTH_USERS';
  end if;

  insert into public.asix_platform_commission_settings(
    id,recipient_user_id,fee_per_player_tetri,currency,enabled,updated_at,commission_rate_bps
  ) values (
    1,v_recipient_id,0,'GEL',true,now(),500
  )
  on conflict(id) do update set
    recipient_user_id=excluded.recipient_user_id,
    fee_per_player_tetri=0,
    currency='GEL',
    enabled=true,
    commission_rate_bps=500,
    updated_at=now();

  insert into public.qcard_game_logic_version(
    singleton_id,logic_version,change_note,changed_at
  ) values (
    1,2,'Casino destination bootstrap: 5% Entry Fee commission and 95% immediate prize pool',now()
  )
  on conflict(singleton_id) do update set
    logic_version=2,
    change_note='Casino destination bootstrap: 5% Entry Fee commission and 95% immediate prize pool',
    changed_at=now();
end
$bootstrap$;

commit;

-- Verify after the transaction:
select id,enabled,currency,commission_rate_bps,fee_per_player_tetri,
       (recipient_user_id is not null) as recipient_configured
from public.asix_platform_commission_settings where id=1;

select singleton_id,logic_version,change_note
from public.qcard_game_logic_version where singleton_id=1;
