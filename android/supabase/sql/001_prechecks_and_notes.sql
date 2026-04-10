-- 001_prechecks_and_notes.sql
-- Purpose:
--   1) Capture current function/table/index state before manual changes.
--   2) Ensure required extension availability.
--   3) Provide a lightweight backup checklist query set.
--
-- Run this first in Supabase SQL Editor and save the output/screenshots.

-- Ensure UUID generation is available for fallback submission UUID generation.
create extension if not exists pgcrypto;

-- Confirm core tables and key columns exist.
select table_name, column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name in ('households', 'members')
order by table_name, ordinal_position;

-- Confirm existing unique constraints/indexes that support idempotent upsert behavior.
select schemaname, tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename in ('households', 'members')
order by tablename, indexname;

-- Capture existing RPC signature/body for rollback reference.
select p.oid::regprocedure as function_signature,
       pg_get_functiondef(p.oid) as function_ddl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'save_household_survey';

-- Optional: check approximate table sizes before change window.
select relname as table_name,
       n_live_tup as live_rows,
       n_dead_tup as dead_rows,
       last_vacuum,
       last_autovacuum
from pg_stat_user_tables
where relname in ('households', 'members', 'survey_submission_receipts')
order by relname;