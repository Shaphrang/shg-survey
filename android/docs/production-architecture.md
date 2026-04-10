# Production Architecture (Offline-First Durable Outbox)

## Core principles
- Every household submission is persisted to Hive **before any network call**.
- A single outbox record contains the full household + members payload required by the RPC.
- Sync is state-machine driven and restart-safe.
- Server acknowledgement is required before marking a record as `synced`.

## Local durable outbox record
Each outbox record now stores:
- `local_submission_uuid`
- `device_household_ref`
- `household`
- `members` (with stable `device_member_ref`)
- `local_created_at`, `local_updated_at`
- `sync_status`
- `sync_attempt_count`, `last_sync_attempt_at`
- `synced_at`
- `last_error_code`, `last_error_message`
- `next_retry_at`
- `payload_hash`
- `schema_version`

## Submission lifecycle
1. UI validates the form.
2. UI builds household + member maps with stable device refs.
3. `OfflineSurveyService.saveHouseholdSurvey` writes one full record to `offline_surveys` box.
4. `SyncService.syncAll` picks eligible records and submits one record per RPC call.
5. On success (`response.success == true`), record transitions to `synced`.
6. On failure, record transitions to `failed_transient` or `failed_permanent`.

## Concurrency and burst handling
- Sync worker uses bounded concurrency (`max 3`) per run.
- In-flight set prevents duplicate simultaneous sync of same `local_submission_uuid`.
- Transient failures are delayed with exponential backoff + jitter (`next_retry_at`).
- Failed transient records are retryable manually and automatically.

## Restart safety
- App startup/entry calls sync bootstrap.
- Stale `syncing` records are reset back to `pending` if no recent attempt timestamp.
- Pending/transient records stay in Hive until successful server acknowledgement.

## UX behavior
- Save action always confirms offline durability.
- Pending count is visible.
- Manual sync and retry-failed actions are available from drawer/banner.