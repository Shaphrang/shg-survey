# RPC Contract: `save_household_survey`

## Final signature
```sql
public.save_household_survey(
  p_household jsonb,
  p_members jsonb,
  p_submission_uuid uuid default null,
  p_payload_hash text default null
) returns jsonb
```

## Request contract
### `p_household` (required JSON object)
Required fields:
- `device_household_ref` (text, non-empty)

Expected operational fields:
- `district_id`, `block_id`, `village_id`
- `hof_name`, `hof_type`, `guardian_specify`

### `p_members` (required JSON array)
Each item should include:
- `device_member_ref`
- `sort_order`
- plus existing member attributes used by schema

### `p_submission_uuid` (optional UUID)
- If provided: server uses this as the idempotency key for one logical submission unit.
- If omitted: server generates UUID, but deterministic replay behavior from client is weaker.

### `p_payload_hash` (optional text)
- Optional client hash used to detect unsafe reuse of same `submission_uuid` with different payload.
- If omitted, server computes a fallback hash from JSON payload text.

## Response contract (JSON)
On first successful processing:
```json
{
  "success": true,
  "status": "processed",
  "submission_uuid": "<uuid>",
  "household_id": "<db-id>",
  "server_timestamp": "2026-04-10T12:00:00Z",
  "member_count": 4
}
```

On safe replay of already-processed same submission UUID:
```json
{
  "success": true,
  "status": "already_processed",
  "submission_uuid": "<uuid>",
  "household_id": "<db-id>",
  "server_timestamp": "2026-04-10T12:01:00Z",
  "member_count": 4
}
```

## Submission UUID semantics
- Same `submission_uuid` + same payload => deterministic safe replay (`already_processed`).
- Same `submission_uuid` + different payload => RPC raises exception (unsafe UUID reuse).
- New `submission_uuid` + same `device_household_ref` => valid household resubmission/update (`processed`).

## Flutter client expectations
- Always send stable `local_submission_uuid` as `p_submission_uuid`.
- Treat `status in ('processed', 'already_processed')` as sync acknowledgment success.
- Mark local outbox record synced only when `success = true` and status is one of those values.
- If UUID reuse mismatch error occurs, mark as permanent failure and surface diagnostics.