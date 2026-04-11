# Submit and Sync Behavior

## Core rule
1. Tap **Save Household**.
2. App validates form and **writes to Hive first** (`offline_surveys`).
3. Only after durable local save does app attempt network sync.
4. App marks record `synced` only for RPC ack with:
   - `success = true`
   - `status in ('processed', 'already_processed')`

## State transitions
- `pending` → new local save, retry-now action.
- `pending/failed_transient` → `syncing` when sync worker starts.
- `syncing` → `synced` on valid server ack.
- `syncing` → `failed_transient` on network/auth/server/unknown errors.
- `syncing` → `failed_permanent` on payload validation or UUID replay mismatch.
- stale `syncing` older than 5 minutes → reset to `pending` on next sync run.

## Online submit (internet + session healthy)
- Save locally first.
- User sees success: "Saved offline securely. Will sync automatically when possible."
- Sync worker starts immediately in background.
- On ack, status becomes `synced` and pending count drops.

## Offline submit
- Save locally first.
- UI still confirms saved safely.
- Sync is deferred; record remains `pending`.
- When connectivity returns, background trigger attempts upload.

## Unstable internet/server failures
- Local record is retained.
- Failure is classified and saved (`last_error_code`, `last_error_message`).
- Retry schedule uses exponential backoff with jitter.
- Transient failures remain recoverable without user re-entry.

## Replay / duplicate handling
- Each submission has stable `local_submission_uuid`.
- Client sends this as `p_submission_uuid` plus SHA-256 `p_payload_hash`.
- If server replies `already_processed`, client marks local record synced.
- If server detects same UUID with different payload, client marks permanent failure.

## UX expectations for field teams
- Save action is never blocked by temporary internet loss.
- Pending banner shows queued items and explicit Sync action.
- Drawer exposes counts for pending and failed submissions.
- Retry action re-queues transient failures.
- Immediate duplicate save attempts with same form data are blocked for 10 seconds.