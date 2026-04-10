-- 004_indexes_and_timestamps.sql
-- Purpose:
--   Add/standardize updated_at tracking and practical indexes for sync/query paths.
--
-- NOTE:
--   CREATE INDEX (without CONCURRENTLY) may briefly lock writes. Run during low-traffic window.

-- 1) Ensure updated_at exists on core tables used by sync and support queries.
alter table public.households
  add column if not exists updated_at timestamptz not null default timezone('utc', now());

alter table public.members
  add column if not exists updated_at timestamptz not null default timezone('utc', now());

alter table public.survey_submission_receipts
  add column if not exists updated_at timestamptz not null default timezone('utc', now());

-- 2) Generic trigger to keep updated_at current on any update.
create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

-- 3) Attach trigger to tables if missing.
do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'trg_households_set_updated_at'
      and tgrelid = 'public.households'::regclass
  ) then
    create trigger trg_households_set_updated_at
    before update on public.households
    for each row
    execute function public.tg_set_updated_at();
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgname = 'trg_members_set_updated_at'
      and tgrelid = 'public.members'::regclass
  ) then
    create trigger trg_members_set_updated_at
    before update on public.members
    for each row
    execute function public.tg_set_updated_at();
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgname = 'trg_receipts_set_updated_at'
      and tgrelid = 'public.survey_submission_receipts'::regclass
  ) then
    create trigger trg_receipts_set_updated_at
    before update on public.survey_submission_receipts
    for each row
    execute function public.tg_set_updated_at();
  end if;
end $$;

-- 4) Focused indexes for field operations and support dashboards.
create index if not exists idx_households_village_id on public.households (village_id);
create index if not exists idx_households_updated_at on public.households (updated_at desc);

create index if not exists idx_members_household_id on public.members (household_id);
create index if not exists idx_members_updated_at on public.members (updated_at desc);

create index if not exists idx_receipts_status_last_received
  on public.survey_submission_receipts (processing_status, last_received_at desc);

-- 5) Verification snapshot after execution.
select schemaname, tablename, indexname
from pg_indexes
where schemaname = 'public'
  and tablename in ('households', 'members', 'survey_submission_receipts')
order by tablename, indexname;
