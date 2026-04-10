# Backend Contract Needs

## Current contract used by client
Client submits one RPC call to `save_household_survey` with:
- `p_household` jsonb
- `p_members` jsonb

Assumed behavior:
- Household upsert by `device_household_ref`
- Existing members deleted for the household
- Members re-inserted from submitted array
- Single DB transaction for household + members
- Response includes `{ success: true, household_id: ... }`

## Client assumptions to keep stable
- `households.device_household_ref` remains unique.
- `members.device_member_ref` remains unique.
- `(household_id, sort_order)` remains unique.
- RPC remains atomic.

## Recommended backend improvements
1. Add support for `local_submission_uuid` in payload and persist as audit/idempotency key.
2. Return normalized error categories/codes (validation/auth/server) for deterministic client classification.
3. Return an explicit `idempotent_replay` marker when duplicate-safe reprocessing occurs.
4. Add server-side request logging keyed by submission UUID + device refs.
5. Provide optional `updated_at` / version info in response to support conflict diagnostics.
6. Consider soft member merge option to avoid full delete-insert churn for very large households.