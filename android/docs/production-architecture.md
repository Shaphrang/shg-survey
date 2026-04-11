# Production Architecture (Client)

## Pipeline
1. User submits household form.
2. App validates and persists one logical submission unit (household + members) into Hive outbox.
3. Sync worker uploads pending records with bounded concurrency.
4. Server RPC processes atomically and returns deterministic status.
5. Client marks synced only on confirmed acknowledgment.

## Reliability controls
- Local-first write-before-network.
- Durable outbox in Hive survives app restarts.
- Idempotent key: `local_submission_uuid` -> `p_submission_uuid`.
- Deterministic payload hash: SHA-256 (`p_payload_hash`).
- Retry policy: exponential backoff + jitter + transient/permanent classification.
- Stale `syncing` recovery on startup/sync invocation.
- Trigger throttling to reduce sync storms.

## Scale considerations
- Per-device concurrency capped at 3.
- Retry jitter reduces synchronized retries across many devices.
- Final scale safety depends on Supabase capacity planning, DB indexing, and staged load tests.