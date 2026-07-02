# Dashboard Rates Editing — מקדמות % from the Web UI

**Date:** 2026-07-02
**Status:** Approved
**Builds on:** `2026-07-02-tax-dashboard-web-design.md` (the dashboard, on branch feature/tax-dashboard)

## Purpose

Let Eitan view and edit his personal מקדמות מס הכנסה rate from the dashboard instead of
editing `config/rates.json` by hand. Scope (approved): **only `mikdamotRate`** is
editable. VAT, ביטוח לאומי parameters, and document-type mappings stay file-only.

## API

Two endpoints, same handler-as-data pattern as the existing dashboard routes
(Public functions because Pode route runspaces can only call exported functions):

### GET /api/rates

Handler: `Get-DashboardRatesResponse [-RatesPath <string>]` →
- 200: `@{StatusCode=200; Body=@{ mikdamotRate = <double> }}`
- config invalid/unreadable → `@{StatusCode=502; Body=@{ error=<message> }}`

Reads through `Get-YeshConfig` (with its `-RatesPath` passthrough) so a broken rates
file fails closed identically to every other consumer.

### POST /api/rates

Body: JSON `{ "mikdamotRate": 0.08 }` (fraction, not percent — same unit as the file).

Handler: `Set-DashboardRatesResponse -Body <hashtable> [-RatesPath <string>] [-EnvPath <string>]` →
- Validation (fail closed → `@{StatusCode=400; Body=@{error}}`):
  - `mikdamotRate` key present, numeric (int or double), `0 ≤ x < 1`
  - any other key in the body → 400 ("only mikdamotRate can be changed")
- Persistence (any failure → `@{StatusCode=502; Body=@{error}}`, original file untouched):
  1. Read current `config/rates.json`, parse
  2. Set only `mikdamotRate`
  3. Write to a temp file (`rates-<guid>.json.tmp` next to the target)
  4. **Validate the temp file via `Get-YeshConfig -RatesPath <temp>`** — full schema
     validation, not just the changed key
  5. `Move-Item -Force` over the real file (atomic replace); delete temp in `finally`
- 200: `@{StatusCode=200; Body=@{ mikdamotRate = <the new value> }}`

Because the change is applied to the freshly-read current file and only one key is
touched, nothing else in `rates.json` can be modified through this endpoint.

### Route wiring (Start-TaxDashboard)

```
Add-PodeRoute -Method Get  -Path '/api/rates' → Get-DashboardRatesResponse; Write-PodeJsonResponse
Add-PodeRoute -Method Post -Path '/api/rates' → Set-DashboardRatesResponse -Body ([hashtable]$WebEvent.Data); Write-PodeJsonResponse
```

Both with the same catch-all → 500 `{error:'Internal error'}` as the existing routes.
POST body arrives via Pode's `$WebEvent.Data` (JSON auto-parse). If `$WebEvent.Data`
is null/non-hashtable → handler receives empty hashtable → 400 by validation.

## Frontend

A settings line in the controls area, above the cards:

- Display mode: `מקדמות מס הכנסה: 8% ` + `[עריכה]` button. Value loaded from
  `GET /api/rates` on page load (percent = fraction × 100, trimmed of trailing zeros).
- Edit mode: number input (**percent**: min 0, max 99.9, step 0.1) prefilled with the
  current %, + שמירה and ביטול buttons.
- Save: converts % → fraction (value / 100), `POST /api/rates`, on 200 → return to
  display mode with the new % **and re-run `load(currentParams)`** so the מקדמות card
  updates immediately. On error → the existing error banner shows the server message;
  display mode returns showing the last-known-good %.
- All values rendered via `textContent`; no innerHTML (project rule).

## Security

- Server-side validation is the gate: numeric, range, single-key allowlist
- File path is fixed server-side (optional `-RatesPath` exists for tests only; the
  route never passes user input into it) — no path traversal surface
- Atomic temp-write + full-schema validation before replace — a crash or bad value can
  never corrupt `rates.json`
- Cross-origin / DNS-rebinding: the server does not validate the Host header, so a page that rebinds DNS to 127.0.0.1 while the dashboard is running could reach this write endpoint. Accepted as low risk for this deployment: targeted attack against one user's ephemeral localhost port, the writable value is bounded to [0,1), and the rate is shown on every page load so a change would be noticed. A Host-header allowlist on the POST route is the mitigation if this is ever hardened. This matches the read-side DNS-rebinding risk already accepted in the dashboard spec.
- No credentials involved anywhere in this flow; no logging

## Testing (Pester)

- `Get-DashboardRatesResponse`: 200 with current value (TestDrive rates file);
  broken file → 502
- `Set-DashboardRatesResponse`: valid update → 200 and file actually contains the new
  value with all other keys intact; non-numeric / out-of-range (−0.1, 1, 1.5) / missing
  key / extra key → 400 and file untouched; unreadable rates file → 502; validation
  failure of the written temp leaves the original intact; no temp files left behind
- No live server, no live API. Existing 80 tests stay green.

## Out of Scope

- Editing VAT, ביטוח לאומי, doc types via the web (file-only, by decision)
- Rate history / audit trail
- Auth (unchanged posture: localhost single user)
