# YeshHeshbonit Tax Dashboard — Local Web UI

**Date:** 2026-07-02
**Status:** Approved
**Builds on:** `2026-07-02-yeshheshbonit-tax-calc-design.md` (the shipped YeshHeshbonit module)

## Purpose

A local web dashboard over the existing YeshHeshbonit PowerShell module. Eitan picks a
month or date range in the browser and sees the three set-aside numbers (מע"מ, מקדמות
מס הכנסה, ביטוח לאומי) as cards, the per-invoice breakdown table, and a one-click
accountant CSV download. Hebrew, RTL.

v1 scope (approved): period picker + totals cards, per-invoice table, CSV download.
Explicitly out: charts/year overview, history store, auth, remote access.

## Architecture

Thin web adapter over the tested module — **no tax logic in the web layer**. Server is
[Pode](https://badgerati.github.io/Pode/) (PSGallery module), running in-process with
YeshHeshbonit imported. Frontend is one static page, vanilla JS, no build step, no npm.

```
YeshHeshbonitAPI/
├── src/YeshHeshbonit/
│   ├── Public/
│   │   ├── Start-TaxDashboard.ps1        # NEW: Pode server + browser launch
│   │   └── Get-TaxSummary.ps1            # MODIFIED: display only, delegates to private
│   └── Private/
│       ├── Get-TaxPeriodSummary.ps1      # NEW: extracted orchestration (shared core)
│       └── ... (existing, unchanged)
├── web/public/
│   ├── index.html                        # RTL Hebrew single page
│   ├── style.css
│   └── app.js                            # vanilla JS
└── tests/
    ├── Get-TaxPeriodSummary.Tests.ps1    # NEW
    ├── Start-TaxDashboard.Tests.ps1      # NEW (handler logic, Pode mocked)
    └── ... (existing 50 tests stay green)
```

## Targeted Refactor: Get-TaxPeriodSummary (Private)

`Get-TaxSummary` currently mixes orchestration with console display. Extract the
orchestration into a private function used by both the CLI command and the web route:

```
Get-TaxPeriodSummary [-Month <yyyy-MM>] | [-From <datetime> -To <datetime>]
  → [pscustomobject] @{
      From     = <datetime>   # resolved period start
      To       = <datetime>   # resolved period end (midnight -To normalized to 23:59)
      Months   = <int>        # calendar months in period
      Invoices = @(...)       # ConvertTo-TaxCalculation .Invoices
      Totals   = @{...}       # ConvertTo-TaxCalculation .Totals
    }
```

It owns: Month → date-range expansion, midnight `-To` end-of-day normalization,
From > To rejection, months-count formula, config load, fetch via `Get-YeshInvoice`,
calculation via `ConvertTo-TaxCalculation`. `Get-TaxSummary` keeps its parameter sets
and display formatting but delegates all logic to this function. Behavior-preserving:
the existing `Get-TaxSummary` tests must pass unchanged (except mocks may move to
`Get-TaxPeriodSummary`'s dependencies).

## Server: Start-TaxDashboard (Public)

```
Start-TaxDashboard [-Port <int, default 8321>] [-NoBrowser]
```

- Binds to **127.0.0.1 only** — never reachable from the network. No auth by decision
  (localhost, single user, personal machine).
- Fails closed at startup: if the Pode module is not installed, terminate with
  "Install-Module Pode -Scope CurrentUser" instruction. If `.env`/`rates.json` are
  invalid, `Get-YeshConfig`'s error surfaces at startup, not at first request.
- Opens the default browser to `http://127.0.0.1:<port>/` unless `-NoBrowser`.
- Ctrl+C stops the server (Pode default behavior).

### Routes

| Route | Behavior |
|---|---|
| `GET /` and static assets | Serves `web/public/` |
| `GET /api/summary?month=yyyy-MM` or `?from=yyyy-MM-dd&to=yyyy-MM-dd` | JSON: `{ period: {from, to, months}, invoices: [...], totals: {...} }` |
| `GET /api/summary/csv?month=...` (same params) | CSV download via `Export-TaxSummary` (temp file, `Content-Disposition: attachment; filename=tax-summary-<period>.csv`, temp file deleted after send) |

Route handlers are thin: parse/validate params → call `Get-TaxPeriodSummary` →
serialize. Handler logic lives in testable private helper functions, not inline Pode
script blocks:

- `Resolve-DashboardPeriodParam` (Private): query-param hashtable →
  `@{Month=...}` or `@{From=...; To=...}` splat, or throws on invalid/missing/
  contradictory params (month AND from/to → error; neither → error; bad formats → error)

### Error posture (fail closed, sanitized)

| Condition | Response |
|---|---|
| Invalid/missing period params | 400 + `{ error: "<validation message>" }` |
| yeshinvoice API failure (from `Invoke-YeshApi`'s sanitized throw) | 502 + `{ error: "<sanitized message>" }` |
| Anything else | 500 + `{ error: "Internal error" }` — no stack traces, no paths |

Credentials can never appear in responses: the only error text forwarded is from the
module's already-sanitized exceptions. No logging (project standard); Pode's default
request logging disabled.

## Frontend (web/public/)

Single page, `dir="rtl" lang="he"`. System font stack (no external font/CDN
dependencies — the page must work offline except for the API itself).

Layout top to bottom:
1. **Header:** title "מחשבון הפרשות מס — יש חשבונית".
2. **Period picker:** `<input type="month">` + quick buttons: החודש, חודש קודם,
   תקופה דו-חודשית (the current bi-monthly VAT period: Jan-Feb, Mar-Apr, …), and a
   custom from/to date-range option. Changing period triggers a fetch.
3. **Totals cards (3):** מע"מ להפרשה; מקדמות מס הכנסה; ביטוח לאומי — the BL card
   carries "אומדן" badge and the projected-annual-income disclaimer as small text.
   Amounts formatted with `Intl.NumberFormat('he-IL', {style:'currency', currency:'ILS'})`.
4. **Invoice table:** date, doc number, customer, gross, net, VAT. Empty period shows
   "לא נמצאו מסמכי הכנסה בתקופה".
5. **CSV button:** "הורדת CSV לרואה חשבון" → navigates to `/api/summary/csv?<current params>`.

Behavior rules:
- While loading: cards show a spinner state; **stale numbers are never left visible**
  for a new period.
- On any API error: red error banner with the server's error text; cards and table are
  cleared — **partial or stale numbers are never rendered next to an error**.
- All dynamic values inserted via `textContent` / DOM APIs — never `innerHTML` — so
  API-sourced strings (customer names) cannot inject markup (XSS defense per OWASP).

## Security Summary

- Server binds 127.0.0.1 only; no auth by decision (single-user local machine)
- Input validation on all query params server-side (fail closed, 400)
- Output: JSON via `ConvertTo-Json`; DOM insertion via `textContent` only
- CSV reuses `Export-TaxSummary` → formula-injection protection already applies
- Credential sanitization inherited from `Invoke-YeshApi`; no error path echoes secrets
- No logging

## Testing (Pester, tests/)

- **Get-TaxPeriodSummary:** Month expansion, midnight `-To` normalization, From > To
  rejection, months count, delegation (mocked `Get-YeshConfig`/`Get-YeshInvoice`),
  return shape. The existing `Get-TaxSummary` tests keep passing — proves the refactor
  is behavior-preserving.
- **Resolve-DashboardPeriodParam:** month param, from/to params, both → error,
  neither → error, malformed values → error.
- **Route handler helpers:** summary-to-JSON shape; CSV temp-file flow (Export mocked);
  error mapping (validation error → 400 payload, API error → 502 payload).
- **Start-TaxDashboard:** fails closed when Pode missing (mock `Get-Module`).
- No test starts a real Pode server or calls the live API. Live verification is a
  manual smoke task: start server, load page, check one period against CLI output.

## Out of Scope (v1)

- Charts / year overview (explicitly deferred by Eitan)
- Auth, HTTPS, non-localhost binding
- Expenses side, history store
- PWA/offline caching, mobile layout tuning (page should merely not break on mobile)
