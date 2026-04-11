# Manual QA Checklist: Save + Pending Sync

## 1) Online save success
1. Keep internet ON.
2. Fill valid household + members.
3. Tap **Save Household**.
4. Expected:
   - Success message: saved to server.
   - No extra pending record created for that submission.
   - Pending badge/count should not increase for this save.

## 2) Offline fallback save
1. Turn internet OFF.
2. Fill valid household + members.
3. Tap **Save Household**.
4. Expected:
   - Message indicates offline-safe pending save.
   - Hive record exists in `offline_surveys` with `sync_status=pending`.
   - Pending count increases.

## 3) Sync pending success
1. Create 1+ pending records while offline.
2. Restore internet.
3. Tap **Sync offline households**.
4. Expected:
   - RPC calls fire for pending records.
   - Success count matches synced records.
   - Synced records transition to `sync_status=synced`.
   - Pending count drops accordingly.

## 4) Failure handling (auth/server/network)
1. Create pending record.
2. Force transient failure (network drop / server down).
3. Sync.
4. Expected:
   - Failure summary includes reason.
   - Record remains retryable (`failed_transient` or `pending` via retry-now).
   - Data remains in Hive and is not lost.

## 5) Repeat sync reliability
1. Run sync once to completion.
2. Create another pending record.
3. Run sync again.
4. Expected:
   - Second run starts normally (not stuck with “already running”).
   - New record uploads successfully.