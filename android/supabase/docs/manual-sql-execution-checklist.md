# Manual SQL Execution Checklist (Supabase Dashboard)

## Before changes
1. Announce maintenance/change window.
2. Open SQL Editor and run `supabase/sql/001_prechecks_and_notes.sql`.
3. Save outputs (existing function DDL, indexes, table stats) in your change ticket.
4. Confirm rollback owner and process.

## Execution order (mandatory)
1. `supabase/sql/001_prechecks_and_notes.sql`
   - Validates baseline + captures current state.
2. `supabase/sql/002_add_submission_receipts.sql`
   - Creates idempotency receipt table + indexes.
3. `supabase/sql/003_harden_save_household_survey.sql`
   - Replaces RPC with replay-safe deterministic response contract.
4. `supabase/sql/004_indexes_and_timestamps.sql`
   - Adds updated_at tracking and supporting indexes/triggers.
5. `supabase/sql/005_validation_scenarios.sql`
   - Run manual validation snippets.

## Verify after each file
- 002: Table exists, constraints/indexes created.
- 003: Function signature includes optional `p_submission_uuid` and `p_payload_hash`.
- 003: Existing app calls with 2 params still work due defaults.
- 004: Triggers exist and `updated_at` changes on updates.
- 005: Scenarios return expected `processed` and `already_processed` statuses.

## Dashboard checks required (manual)
- Confirm function execute grants for intended roles (anon/authenticated/service_role) are correct.
- Confirm RLS policies on `households`, `members`, and `survey_submission_receipts` allow RPC path but do not overexpose direct table writes.
- Confirm function owner and `SECURITY DEFINER` usage are acceptable for your security model.
- Confirm RPC is exposed and callable only as intended via PostgREST.

## Post-deploy monitoring
- Monitor `survey_submission_receipts` growth and status distribution.
- Watch for repeated `failed_validation` and UUID payload mismatch errors.
- Verify sync success rate from mobile telemetry after rollout.