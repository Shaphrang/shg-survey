-- 002_add_submission_receipts.sql
-- Purpose:
--   Add a submission receipt table for deterministic acknowledgement and replay-safe processing.
--
-- This table is intentionally minimal and focused on idempotency + observability.

create table if not exists public.survey_submission_receipts (
  submission_uuid uuid primary key,
  device_household_ref text not null,
  household_id text null,
  processing_status text not null default 'processing',
  payload_hash text null,
  first_received_at timestamptz not null default timezone('utc', now()),
  last_received_at timestamptz not null default timezone('utc', now()),
  processed_at timestamptz null,
  response_snapshot jsonb null,
  notes text null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint survey_submission_receipts_processing_status_chk
    check (processing_status in ('processing', 'processed', 'already_processed', 'failed_validation'))
);

comment on table public.survey_submission_receipts is
  'Receipt/idempotency log for save_household_survey RPC submissions.';

comment on column public.survey_submission_receipts.submission_uuid is
  'Client-stable UUID for one logical submission attempt. Replays should send same UUID.';

comment on column public.survey_submission_receipts.payload_hash is
  'Client-supplied or server-derived hash to detect UUID reuse with different payloads.';

create index if not exists idx_receipts_device_household_ref
  on public.survey_submission_receipts (device_household_ref);

create index if not exists idx_receipts_last_received_at
  on public.survey_submission_receipts (last_received_at desc);

create index if not exists idx_receipts_processed_at
  on public.survey_submission_receipts (processed_at desc);