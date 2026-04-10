-- 005_validation_scenarios.sql
-- Purpose:
--   Manual validation snippets for SQL Editor (no local test harness required).
--
-- HOW TO USE:
--   1) Replace sample IDs/refs with safe test values.
--   2) Execute each section and inspect JSON responses + receipt rows.

-- ----------------------------------------------------------------------------
-- Scenario A: First submission (expected status=processed)
-- ----------------------------------------------------------------------------
with vars as (
  select
    gen_random_uuid() as submission_uuid,
    'hh_test_001'::text as device_household_ref
)
select public.save_household_survey(
  jsonb_build_object(
    'device_household_ref', (select device_household_ref from vars),
    'district_id', 1,
    'block_id', 1,
    'village_id', 1,
    'hof_name', 'Test HOF',
    'hof_type', 'father'
  ),
  jsonb_build_array(
    jsonb_build_object(
      'device_member_ref', 'mem_test_001',
      'sort_order', 1,
      'relationship_to_hof', 'head_of_family',
      'member_name', 'Test HOF',
      'gender', 'M',
      'age', 40,
      'marital_status', 'Married',
      'is_shg_member', false,
      'is_job_card_holder', false,
      'is_pwd', false,
      'has_aadhaar', false,
      'has_epic', false
    )
  ),
  (select submission_uuid from vars),
  null
) as response;

-- ----------------------------------------------------------------------------
-- Scenario B: Same submission replay (expected status=already_processed)
-- ----------------------------------------------------------------------------
-- Re-run Scenario A exactly with same submission_uuid + same payload.

-- ----------------------------------------------------------------------------
-- Scenario C: Same household update with NEW submission_uuid (expected processed)
-- ----------------------------------------------------------------------------
select public.save_household_survey(
  jsonb_build_object(
    'device_household_ref', 'hh_test_001',
    'district_id', 1,
    'block_id', 1,
    'village_id', 1,
    'hof_name', 'Test HOF Updated',
    'hof_type', 'father'
  ),
  jsonb_build_array(
    jsonb_build_object(
      'device_member_ref', 'mem_test_001',
      'sort_order', 1,
      'relationship_to_hof', 'head_of_family',
      'member_name', 'Test HOF Updated',
      'gender', 'M',
      'age', 41,
      'marital_status', 'Married',
      'is_shg_member', false,
      'is_job_card_holder', false,
      'is_pwd', false,
      'has_aadhaar', false,
      'has_epic', false
    )
  ),
  gen_random_uuid(),
  null
) as response;

-- ----------------------------------------------------------------------------
-- Scenario D: Validation failure (expected SQL exception)
-- ----------------------------------------------------------------------------
-- p_members must be an array.
-- select public.save_household_survey(
--   '{"device_household_ref":"hh_invalid"}'::jsonb,
--   '{"bad":"shape"}'::jsonb,
--   gen_random_uuid(),
--   null
-- );

-- ----------------------------------------------------------------------------
-- Scenario E: Receipt verification
-- ----------------------------------------------------------------------------
select submission_uuid,
       device_household_ref,
       household_id -- stored as text in receipt table for cross-schema compatibility,
       processing_status,
       first_received_at,
       last_received_at,
       processed_at
from public.survey_submission_receipts
order by last_received_at desc
limit 20;