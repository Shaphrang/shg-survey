-- 003_harden_save_household_survey.sql
-- Purpose:
--   Upgrade save_household_survey RPC with deterministic idempotency semantics while
--   preserving atomic household + members processing.
--
-- New optional params are backward-compatible for existing callers:
--   p_submission_uuid uuid default null
--   p_payload_hash text default null
--
-- Deterministic outcomes:
--   - processed: first-time successful processing
--   - already_processed: exact replay of same submission_uuid + payload_hash
--
-- NOTE:
--   This function assumes households/members tables already contain the target columns used below.

create or replace function public.save_household_survey(
  p_household jsonb,
  p_members jsonb,
  p_submission_uuid uuid default null,
  p_payload_hash text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := timezone('utc', now());
  v_submission_uuid uuid := coalesce(p_submission_uuid, gen_random_uuid());
  v_payload_hash text := coalesce(
    nullif(p_payload_hash, ''),
    md5(coalesce(p_household::text, '') || '|' || coalesce(p_members::text, ''))
  );
  v_device_household_ref text;
  v_household_id public.households.id%type;
  v_member_count integer := 0;
  v_existing_receipt public.survey_submission_receipts%rowtype;
  v_response jsonb;
begin
  -- 1) Basic shape checks.
  if p_household is null or jsonb_typeof(p_household) <> 'object' then
    raise exception using message = 'p_household must be a JSON object';
  end if;

  if p_members is null or jsonb_typeof(p_members) <> 'array' then
    raise exception using message = 'p_members must be a JSON array';
  end if;

  v_device_household_ref := nullif(trim(p_household->>'device_household_ref'), '');

  if v_device_household_ref is null then
    raise exception using message = 'device_household_ref is required in p_household';
  end if;

  -- 2) Lock/select receipt row to enforce deterministic replay behavior.
  select *
  into v_existing_receipt
  from public.survey_submission_receipts
  where submission_uuid = v_submission_uuid
  for update;

  if found then
    -- Same submission UUID retried with a different payload is unsafe and must fail loudly.
    if coalesce(v_existing_receipt.payload_hash, '') <> coalesce(v_payload_hash, '') then
      raise exception using message =
        format('submission_uuid %s was reused with a different payload_hash', v_submission_uuid);
    end if;

    update public.survey_submission_receipts
      set last_received_at = v_now,
          updated_at = v_now,
          notes = coalesce(notes, '') || case when notes is null then '' else E'\n' end ||
                  format('Replay received at %s', v_now)
    where submission_uuid = v_submission_uuid;

    if v_existing_receipt.processing_status in ('processed', 'already_processed') then
      return jsonb_build_object(
        'success', true,
        'status', 'already_processed',
        'submission_uuid', v_submission_uuid,
        'household_id', v_existing_receipt.household_id,
        'server_timestamp', v_now,
        'member_count', coalesce(jsonb_array_length(p_members), 0)
      );
    end if;
  else
    insert into public.survey_submission_receipts (
      submission_uuid,
      device_household_ref,
      processing_status,
      payload_hash,
      first_received_at,
      last_received_at,
      created_at,
      updated_at
    )
    values (
      v_submission_uuid,
      v_device_household_ref,
      'processing',
      v_payload_hash,
      v_now,
      v_now,
      v_now,
      v_now
    );
  end if;

  -- 3) Upsert household via existing device_household_ref unique behavior.
  insert into public.households (
    device_household_ref,
    district_id,
    block_id,
    village_id,
    hof_name,
    hof_type,
    guardian_specify,
    created_at,
    updated_at
  )
  values (
    v_device_household_ref,
    case when nullif(trim(p_household->>'district_id'), '') is null then null else (p_household->>'district_id')::bigint end,
    case when nullif(trim(p_household->>'block_id'), '') is null then null else (p_household->>'block_id')::bigint end,
    case when nullif(trim(p_household->>'village_id'), '') is null then null else (p_household->>'village_id')::bigint end,
    nullif(trim(p_household->>'hof_name'), ''),
    nullif(trim(p_household->>'hof_type'), ''),
    nullif(trim(p_household->>'guardian_specify'), ''),
    v_now,
    v_now
  )
  on conflict (device_household_ref)
  do update set
    district_id = excluded.district_id,
    block_id = excluded.block_id,
    village_id = excluded.village_id,
    hof_name = excluded.hof_name,
    hof_type = excluded.hof_type,
    guardian_specify = excluded.guardian_specify,
    updated_at = v_now
  returning id into v_household_id;

  -- 4) Deterministic member replacement (existing behavior retained).
  delete from public.members where household_id = v_household_id;

  insert into public.members (
    household_id,
    device_member_ref,
    sort_order,
    relationship_to_hof,
    member_name,
    gender,
    age,
    marital_status,
    is_shg_member,
    shg_name_or_code,
    special_group,
    is_job_card_holder,
    is_pwd,
    has_aadhaar,
    aadhaar_no,
    has_epic,
    epic_no,
    created_at,
    updated_at
  )
  select
    v_household_id,
    nullif(trim(e->>'device_member_ref'), ''),
    (e->>'sort_order')::integer,
    nullif(trim(e->>'relationship_to_hof'), ''),
    nullif(trim(e->>'member_name'), ''),
    nullif(trim(e->>'gender'), ''),
    case when nullif(trim(e->>'age'), '') is null then null else (e->>'age')::integer end,
    nullif(trim(e->>'marital_status'), ''),
    coalesce((e->>'is_shg_member')::boolean, false),
    nullif(trim(e->>'shg_name_or_code'), ''),
    nullif(trim(e->>'special_group'), ''),
    coalesce((e->>'is_job_card_holder')::boolean, false),
    coalesce((e->>'is_pwd')::boolean, false),
    coalesce((e->>'has_aadhaar')::boolean, false),
    nullif(trim(e->>'aadhaar_no'), ''),
    coalesce((e->>'has_epic')::boolean, false),
    nullif(trim(e->>'epic_no'), ''),
    v_now,
    v_now
  from jsonb_array_elements(p_members) as e;

  get diagnostics v_member_count = row_count;

  v_response := jsonb_build_object(
    'success', true,
    'status', 'processed',
    'submission_uuid', v_submission_uuid,
    'household_id', v_household_id,
    'server_timestamp', v_now,
    'member_count', v_member_count
  );

  update public.survey_submission_receipts
    set household_id = v_household_id::text,
        processing_status = 'processed',
        processed_at = v_now,
        last_received_at = v_now,
        response_snapshot = v_response,
        updated_at = v_now
  where submission_uuid = v_submission_uuid;

  return v_response;

exception when others then
  -- Keep failure trace for operational support, while preserving transaction atomicity.
  update public.survey_submission_receipts
    set processing_status = 'failed_validation',
        last_received_at = timezone('utc', now()),
        notes = coalesce(notes, '') || case when notes is null then '' else E'\n' end ||
                format('Failure: %s', sqlerrm),
        updated_at = timezone('utc', now())
  where submission_uuid = v_submission_uuid;

  raise;
end;
$$;

comment on function public.save_household_survey(jsonb, jsonb, uuid, text) is
  'Atomic household+members submission with deterministic replay acknowledgment via submission_uuid.';