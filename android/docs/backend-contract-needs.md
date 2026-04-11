# Backend Contract Needs

## Required RPC behavior
`save_household_survey(p_household, p_members, p_submission_uuid, p_payload_hash)` must:
- process household + members atomically,
- return `{success:true,status:'processed'}` for first success,
- return `{success:true,status:'already_processed'}` for exact replay,
- throw explicit error for same UUID + different payload hash.

## Client assumptions now implemented
- Client always sends stable `p_submission_uuid` from local outbox record.
- Client always sends deterministic SHA-256 payload hash.
- Client marks local record `synced` only for `processed` / `already_processed`.
- UUID mismatch is treated as permanent failure requiring intervention.

## Ops expectations
- Preserve receipt table/index performance under high write concurrency.
- Provide monitoring for replay mismatch, validation failures, and latency spikes.