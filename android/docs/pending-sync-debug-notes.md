# Pending Sync Debug Notes

## Root cause of `0 household(s) synced successfully`
Primary bug found in `SyncService`:
- `_running` flag was set to `true` at sync start but never reset to `false` after completion.
- Result: all later sync attempts returned early with `Sync already running`, causing zero upload behavior.

## Additional UX issue
- UI treated `uploaded=0, failed=0` as a normal success message and did not surface `errors[0]`.
- This masked root causes like throttling, no internet, or stale state.

## Fixes implemented
- Reset `_running=false` in `syncAll` finalization.
- Preserve and surface sync errors in UI (`Nothing synced: <reason>`).
- Keep accurate success/failure counts and clear summaries.

## Expected sync lifecycle now
1. Query Hive `offline_surveys` records in `pending` or eligible `failed_transient`.
2. Mark each as `syncing`.
3. Build RPC payload via shared payload builder.
4. Call RPC and parse acknowledgment.
5. Mark `synced` on ACK; mark `failed_transient`/`failed_permanent` on classified failures.
6. Return exact `{total, uploaded, failed, errors}` for user-visible reporting.
