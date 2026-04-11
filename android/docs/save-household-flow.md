# Save Household Flow (Production-Hardened)

## Deterministic behavior
- Form is validated first in UI.
- App builds one normalized submission payload (`household` + `members`) with stable device refs.
- Save path is **online-first with offline fallback**:
  1. If internet is unavailable, save to Hive (`offline_surveys`) as `pending`.
  2. If internet is available, call Supabase RPC `save_household_survey`.
  3. If RPC ACK is valid (`success=true` and `status in [processed, already_processed]`), treat save as server-success.
  4. Any online failure (timeout/network/auth/server/parse/unexpected) falls back to Hive pending immediately.

## Data safety guarantee
- Household data is never discarded after user taps save and validation passes.
- If server path fails at any point, the same payload is saved locally for later retry.

## RPC contract
- RPC: `save_household_survey`
- Params:
  - `p_household`
  - `p_members`
  - `p_submission_uuid`
  - `p_payload_hash`
- Success acknowledgment:
  - `success=true`
  - `status=processed|already_processed`

## User-visible outcomes
- Server success: `Saved to server successfully.`
- Offline save/no internet: `No internet. Saved offline safely and marked pending for sync.`
- Online fail fallback: `Server save failed (<category>). Saved offline safely for later sync.`