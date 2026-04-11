# Manual QA Checklist

## Local durability
- [ ] Fill household + members and tap save once.
- [ ] Confirm toast says saved locally/offline.
- [ ] Force-close app immediately.
- [ ] Reopen app and verify pending count still includes saved record.

## Online submission path
- [ ] Keep internet on, submit survey.
- [ ] Confirm local-save message appears first.
- [ ] Confirm pending count drops after successful sync.

## Offline submission path
- [ ] Disable internet.
- [ ] Submit survey.
- [ ] Confirm record remains pending and is not lost.
- [ ] Re-enable internet and trigger sync; verify status becomes synced.

## Unstable internet / retry behavior
- [ ] Trigger sync with flaky internet.
- [ ] Verify transient failure and `next_retry_at` scheduling.
- [ ] Retry and verify eventual sync success.

## Replay + idempotency
- [ ] Replay same local submission UUID through retry flow.
- [ ] Confirm backend `already_processed` response is treated as synced.
- [ ] Validate no duplicate household/member rows server-side.


## Duplicate prevention
- [ ] Rapidly tap save with same form payload.
- [ ] Confirm duplicate-save guard blocks immediate repeated submission.
- [ ] Trigger sync twice quickly; verify sync throttling/in-flight guard.

## Validation + permanent failures
- [ ] Submit invalid member payload (test fixture/debug).
- [ ] Confirm transition to `failed_permanent` with error reason.

## App lifecycle recovery
- [ ] Put record in syncing state (start sync, kill app).
- [ ] Relaunch app.
- [ ] Verify stale syncing resets and record is retried.

## Auth/session failure
- [ ] Expire/invalid session token and trigger sync.
- [ ] Confirm failure is captured and record remains recoverable.