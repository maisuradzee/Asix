-- Reconciliation idempotency must include the complete comparison state, not
-- only the provider export. A late callback/tombstone enrichment can change the
-- local snapshot while the provider export remains byte-identical.
begin;

alter table provider_internal.st8_reconciliation_runs
  add column if not exists comparison_snapshot_sha256 text;

update provider_internal.st8_reconciliation_runs
set comparison_snapshot_sha256=provider_export_sha256
where comparison_snapshot_sha256 is null;

alter table provider_internal.st8_reconciliation_runs
  alter column comparison_snapshot_sha256 set not null;

alter table provider_internal.st8_reconciliation_runs
  add constraint st8_reconciliation_runs_comparison_snapshot_sha256_check
  check (comparison_snapshot_sha256 ~ '^[0-9a-f]{64}$');

alter table provider_internal.st8_reconciliation_runs
  drop constraint if exists st8_reconciliation_runs_site_id_currency_window_start_windo_key;

alter table provider_internal.st8_reconciliation_runs
  add constraint st8_reconciliation_runs_snapshot_key
  unique (site_id,currency,window_start,window_end,comparison_snapshot_sha256);

drop function if exists public.st8_record_reconciliation_run(text,text,timestamptz,timestamptz,text,text,jsonb,jsonb);

create or replace function public.st8_record_reconciliation_run(
  p_site_id text,
  p_currency text,
  p_window_start timestamptz,
  p_window_end timestamptz,
  p_provider_export_sha256 text,
  p_comparison_snapshot_sha256 text,
  p_comparison_status text,
  p_counts jsonb,
  p_issues jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, auth, provider_internal
as $$
declare
  v_run_id uuid;
  v_issue jsonb;
  v_issue_id uuid;
  v_old_status text;
  v_issue_type text;
  v_fingerprint text;
  v_severity text;
  v_transaction_id text;
  v_reference_transaction_id text;
  v_details jsonb;
  v_occurrences integer;
  v_created boolean;
  v_reopened boolean;
  v_new_count integer := 0;
  v_reopened_count integer := 0;
  v_issue_count integer;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  if nullif(btrim(p_site_id),'') is null or length(p_site_id)>100
     or p_currency is distinct from 'GEL'
     or p_window_start is null or p_window_end is null
     or p_window_start >= p_window_end or p_window_end > clock_timestamp()
     or p_window_end - p_window_start > interval '31 days'
     or p_provider_export_sha256 is null
     or p_provider_export_sha256 !~ '^[0-9a-f]{64}$'
     or p_comparison_snapshot_sha256 is null
     or p_comparison_snapshot_sha256 !~ '^[0-9a-f]{64}$'
     or p_comparison_status is null
     or p_comparison_status not in ('matched','mismatch')
     or jsonb_typeof(p_counts) is distinct from 'object'
     or octet_length(p_counts::text)>8192
     or jsonb_typeof(p_issues) is distinct from 'array'
     or octet_length(p_issues::text)>2097152 then
    raise exception 'INVALID_RECONCILIATION_RUN' using errcode='22023';
  end if;
  if jsonb_array_length(p_issues)>10000 then
    raise exception 'INVALID_RECONCILIATION_RUN' using errcode='22023';
  end if;
  if not exists (select 1 from provider_internal.st8_sites s where s.site_id=p_site_id) then
    raise exception 'ST8_SITE_NOT_CONFIGURED' using errcode='22023';
  end if;

  v_issue_count := jsonb_array_length(p_issues);
  if p_comparison_status='matched' and v_issue_count<>0 then
    raise exception 'MATCHED_RUN_CANNOT_CONTAIN_ISSUES' using errcode='22023';
  end if;
  if p_comparison_status='mismatch' and v_issue_count=0 then
    raise exception 'MISMATCH_RUN_REQUIRES_ISSUES' using errcode='22023';
  end if;

  insert into provider_internal.st8_reconciliation_runs(
    site_id,currency,window_start,window_end,provider_export_sha256,comparison_snapshot_sha256,
    comparison_status,counts,issue_count
  ) values (
    p_site_id,p_currency,p_window_start,p_window_end,p_provider_export_sha256,p_comparison_snapshot_sha256,
    p_comparison_status,p_counts,v_issue_count
  ) on conflict (site_id,currency,window_start,window_end,comparison_snapshot_sha256)
    do nothing
  returning id into v_run_id;

  if v_run_id is null then
    select id into v_run_id from provider_internal.st8_reconciliation_runs
    where site_id=p_site_id and currency=p_currency
      and window_start=p_window_start and window_end=p_window_end
      and comparison_snapshot_sha256=p_comparison_snapshot_sha256;
    return jsonb_build_object(
      'status','ok','duplicate',true,'run_id',v_run_id,
      'issues_received',v_issue_count,'new_issues',0,'reopened_issues',0
    );
  end if;

  for v_issue in select value from jsonb_array_elements(p_issues) as item(value)
  loop
    v_issue_type := v_issue->>'issue_type';
    v_fingerprint := v_issue->>'issue_fingerprint';
    v_transaction_id := nullif(v_issue->>'transaction_id','');
    v_reference_transaction_id := nullif(v_issue->>'reference_transaction_id','');
    v_details := coalesce(v_issue->'details','{}'::jsonb);

    if jsonb_typeof(v_issue) is distinct from 'object'
       or coalesce(v_issue_type,'') not in (
         'PROVIDER_ONLY','LOCAL_ONLY','AMOUNT_MISMATCH','CURRENCY_MISMATCH',
         'SITE_MISMATCH','ACTION_KIND_MISMATCH','PROVIDER_KIND_MISMATCH',
         'REFERENCE_TRANSACTION_MISMATCH','FIELD_MISMATCH','PENDING_REFERENCE_CANCEL',
         'LEDGER_BALANCE_MISMATCH','LEDGER_SEQUENCE_MISMATCH','DEBT_BALANCE_MISMATCH'
       )
       or coalesce(v_fingerprint,'') !~ '^[0-9a-f]{64}$'
       or jsonb_typeof(v_details) is distinct from 'object'
       or octet_length(v_details::text)>4096
       or (v_transaction_id is not null and length(v_transaction_id)>255)
       or (v_reference_transaction_id is not null and length(v_reference_transaction_id)>255) then
      raise exception 'INVALID_RECONCILIATION_ISSUE' using errcode='22023';
    end if;

    v_severity := case
      when v_issue_type in ('LEDGER_BALANCE_MISMATCH','LEDGER_SEQUENCE_MISMATCH','DEBT_BALANCE_MISMATCH') then 'CRITICAL'
      when v_issue_type='PENDING_REFERENCE_CANCEL' then 'WARNING'
      else 'WARNING'
    end;

    select i.id,i.status into v_issue_id,v_old_status
    from provider_internal.st8_reconciliation_issues i
    where i.issue_fingerprint=v_fingerprint
    for update;

    v_created := false;
    v_reopened := false;
    if found then
      v_reopened := v_old_status in ('RESOLVED','IGNORED');
      update provider_internal.st8_reconciliation_issues
      set latest_run_id=v_run_id,
          severity=v_severity,
          status=case when v_reopened then 'OPEN' else status end,
          transaction_id=coalesce(v_transaction_id,transaction_id),
          reference_transaction_id=coalesce(v_reference_transaction_id,reference_transaction_id),
          details=v_details,
          occurrence_count=occurrence_count+1,
          last_seen_at=clock_timestamp(),
          resolution_note=case when v_reopened then null else resolution_note end,
          resolved_at=case when v_reopened then null else resolved_at end,
          updated_at=clock_timestamp()
      where id=v_issue_id
      returning occurrence_count into v_occurrences;
    else
      insert into provider_internal.st8_reconciliation_issues(
        issue_fingerprint,site_id,currency,issue_type,severity,
        transaction_id,reference_transaction_id,details,first_run_id,latest_run_id
      ) values (
        v_fingerprint,p_site_id,p_currency,v_issue_type,v_severity,
        v_transaction_id,v_reference_transaction_id,v_details,v_run_id,v_run_id
      ) returning id,occurrence_count into v_issue_id,v_occurrences;
      v_created := true;
      v_new_count := v_new_count+1;
    end if;

    if v_reopened then v_reopened_count := v_reopened_count+1; end if;
    if v_created or v_reopened then
      insert into provider_internal.st8_alert_outbox(issue_id,event_key,event_type,payload)
      values (
        v_issue_id,
        'st8-recon:'||v_issue_id::text||':'||v_run_id::text,
        case when v_reopened then 'ISSUE_REOPENED' else 'ISSUE_OPENED' end,
        jsonb_build_object(
          'event',case when v_reopened then 'st8.reconciliation.issue_reopened' else 'st8.reconciliation.issue_opened' end,
          'issue_id',v_issue_id,
          'run_id',v_run_id,
          'site_id',p_site_id,
          'currency',p_currency,
          'issue_type',v_issue_type,
          'severity',v_severity,
          'transaction_id',v_transaction_id,
          'reference_transaction_id',v_reference_transaction_id,
          'details',v_details,
          'occurrence_count',v_occurrences,
          'created_at',clock_timestamp()
        )
      ) on conflict (event_key) do nothing;
    end if;
  end loop;

  return jsonb_build_object(
    'status','ok','duplicate',false,'run_id',v_run_id,
    'issues_received',v_issue_count,'new_issues',v_new_count,
    'reopened_issues',v_reopened_count
  );
end;
$$;

revoke all on function public.st8_record_reconciliation_run(text,text,timestamptz,timestamptz,text,text,text,jsonb,jsonb)
  from public, anon, authenticated;
grant execute on function public.st8_record_reconciliation_run(text,text,timestamptz,timestamptz,text,text,text,jsonb,jsonb)
  to service_role;

commit;