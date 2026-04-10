# Backend Scale Notes

## Why this design is safer at high concurrency
- RPC remains atomic for household + members in one transaction.
- Receipt table adds deterministic replay handling using `submission_uuid`.
- Upsert by `device_household_ref` continues to support long-lived household updates.
- Status-rich response enables reliable client outbox acknowledgements.

## Index and observability improvements
- Receipt indexes improve replay lookup and operational debugging.
- Added/standardized `updated_at` supports auditing and support workflows.
- Receipt timestamps (`first_received_at`, `last_received_at`, `processed_at`) provide retry visibility.

## Client-side responsibilities still required
- Must save locally before network submit.
- Must retry transient failures with bounded backoff+jitter.
- Must avoid concurrent sync of same submission UUID.
- Must treat `processed` and `already_processed` as acknowledged success.

## Practical limitations
- Member delete/reinsert approach is deterministic but not historical; use CDC/audit tables if member-level history is required.
- Payload hash uses client/server text hash fallback; canonical hashing is recommended long term if cross-language determinism becomes critical.
- Dashboard-only manual SQL workflow requires strict execution discipline and change logging.

## Operational note
- Apply index-heavy scripts during lower traffic windows to minimize lock impact.