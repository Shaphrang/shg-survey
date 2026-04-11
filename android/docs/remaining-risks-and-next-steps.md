# Remaining Risks and Next Steps

## Remaining risks
1. **Backend saturation risk under sync storms**
   - Client now throttles and jitters retries, but server/database throughput still must be validated.
2. **Auth/session expiration at scale**
   - Client classifies auth failures as transient; explicit re-login UX may still need strengthening.
3. **No end-to-end telemetry pipeline in app**
   - Debug logs exist, but centralized observability (error events, retry metrics, queue depth trends) is not implemented here.
4. **Payload/business validation ownership split**
   - App validates structural fields; domain validation is still ultimately backend-dependent.
5. **Local storage hardening**
   - Hive durability is used, but encryption-at-rest/key management policy is not implemented in this repo.

## Required pre-rollout actions
- Run staged load tests (1k → 5k → 20k simulated clients) against production-like Supabase.
- Verify RPC p95/p99 latencies and error rates during burst windows.
- Confirm database index health and write amplification impacts.
- Implement operational alerting:
  - sync failure rate threshold
  - backlog growth rate
  - duplicate UUID mismatch incidence
- Execute phased rollout (pilot districts first), with rollback criteria.

## Recommended additional app work
- Add explicit auth-expired banner and re-auth CTA.
- Add on-device sync diagnostics screen for supervisors/support.
- Expand test coverage for widget-level UX states (pending/syncing/failed badges).