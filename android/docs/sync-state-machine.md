# Sync State Machine

## States
- `draft`: local record created but not queue-ready (reserved).
- `pending`: queue-ready and eligible for sync.
- `syncing`: active upload attempt.
- `synced`: server acknowledged with `success=true` and status `processed` or `already_processed`.
- `failed_transient`: retryable error (network/auth/server/unknown).
- `failed_permanent`: non-retryable error (validation, unsafe UUID replay mismatch).

## Transitions
- `draft -> pending`: submission is finalized locally.
- `pending -> syncing`: worker starts upload.
- `syncing -> synced`: RPC returns valid ack status.
- `syncing -> failed_transient`: transient failure; retry time scheduled.
- `syncing -> failed_permanent`: payload invalid or UUID mismatch.
- `failed_transient -> pending`: auto retry due or manual retry action.
- `syncing -> pending`: stale syncing reset during crash recovery.

## Retry behavior
- Exponential backoff with cap.
- Random jitter added per attempt.
- Minimum sync gap throttles repeated trigger storms.
- Permanent failures never auto-retry.

## Safety constraints
- Never delete queued data before ack.
- Stable `local_submission_uuid` is sent as `p_submission_uuid`.
- Client includes deterministic SHA-256 `p_payload_hash`.
- Replay-safe ack (`already_processed`) is treated as successful sync.