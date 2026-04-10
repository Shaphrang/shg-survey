# Manual QA Checklist

## Local durability
- [ ] Fill household + members and tap save once.
- [ ] Confirm success toast says saved offline.
- [ ] Force-close app immediately.
- [ ] Reopen app and verify pending count still includes saved record.

## Duplicate prevention
- [ ] Rapidly tap save button multiple times.
- [ ] Confirm only one record is created per completed save flow.
- [ ] Trigger sync twice quickly; verify no duplicate in-flight sync for same local UUID.

## Retry behavior
- [ ] Disable internet and trigger sync.
- [ ] Verify record goes to transient failure/pending state, not lost.
- [ ] Re-enable internet and sync again.
- [ ] Verify successful transition to synced.

## Restart-safe resume
- [ ] Put a record in syncing state (start sync, then kill app).
- [ ] Relaunch app.
- [ ] Verify stale syncing reset and record resumes eligible sync.

## Validation
- [ ] Attempt save with invalid HOF fields.
- [ ] Confirm validation blocks queueing.
- [ ] Attempt member entries with inconsistent data.
- [ ] Confirm payload is not queued when invalid.

## Field UX
- [ ] Pending banner appears only when pending > 0.
- [ ] Drawer shows pending + failed counts.
- [ ] Retry failed action re-queues transient failures.