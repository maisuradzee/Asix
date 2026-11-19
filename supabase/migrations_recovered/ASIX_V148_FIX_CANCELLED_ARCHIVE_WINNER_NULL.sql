-- ASIX V148 follow-up fix
-- Fixes deal archival for cancelled deals that have no winner_user_id.
-- Applied to the live Supabase project as migration:
-- asix_v148_fix_cancelled_archive_winner_null

DO $v148_archive_winner_null_fix$
DECLARE
  v_def text;
  v_old text := 'nullif(value->>''user_id'','''')::uuid=v_winner';
  v_new text := 'coalesce(nullif(value->>''user_id'','''')::uuid=v_winner,false)';
  v_count integer;
BEGIN
  v_def := pg_get_functiondef('public.qcard_archive_before_new_deal()'::regprocedure);
  v_count := (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'V148_ARCHIVE_WINNER_PATCH_EXPECTED_ONE_MATCH_FOUND_%',v_count;
  END IF;

  v_def := replace(v_def,v_old,v_new);
  EXECUTE v_def;

  IF position(v_new IN pg_get_functiondef('public.qcard_archive_before_new_deal()'::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'V148_ARCHIVE_WINNER_PATCH_VERIFICATION_FAILED';
  END IF;
END;
$v148_archive_winner_null_fix$;

COMMENT ON FUNCTION public.qcard_archive_before_new_deal()
IS 'ASIX V148: archives completed and cancelled deals; cancelled deals without a winner record is_winner=false instead of NULL.';