# Sync State Machine

## States
- `draft`: local record created but not ready (reserved)
- `pending`: ready to sync
- `syncing`: currently being uploaded
- `synced`: server acknowledged success
- `failed_transient`: retryable failure
- `failed_permanent`: non-retryable until user/edit intervention

## Transitions
- `draft -> pending`: queue-ready record
- `pending -> syncing`: worker starts upload attempt
- `syncing -> synced`: RPC success=true
- `syncing -> failed_transient`: network/auth/server/unknown failure
- `syncing -> failed_permanent`: local validation/business-rule failure
- `failed_transient -> pending`: retry due (auto) or manual retry action
- `syncing -> pending`: crash recovery (stale syncing reset)

## Retry behavior
- Backoff: exponential with capped delay
- Jitter: randomized additive delay to reduce synchronized retry storms
- Permanent failures do not schedule retries

## Safety constraints
- A submission is never deleted before sync acknowledgement.
- A submission cannot be synced concurrently by two workers.
- Retry attempts use identical stable device refs, preserving idempotent upsert behavior.