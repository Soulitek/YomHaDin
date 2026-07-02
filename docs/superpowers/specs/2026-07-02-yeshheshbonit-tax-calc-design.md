# YeshHeshbonitAPI — Per-Invoice Tax Set-Aside Calculator

**Date:** 2026-07-02
**Status:** Approved

## Purpose

Eitan (עוסק מורשה, SouliTEK) issues invoices through yeshinvoice.co.il. For any period
(month or bi-monthly VAT period), the system pulls the issued invoices from the
yeshinvoice API and answers one question per period:

> "הכנסתי X ש״ח — כמה להפריש למע״מ, למקדמות מס הכנסה ולביטוח לאומי?"

Output is a per-invoice breakdown plus period totals for:

1. **מע"מ** — the VAT component collected on issued invoices (to set aside for the VAT return)
2. **מקדמות מס הכנסה** — personal advance rate × pre-VAT turnover
3. **ביטוח לאומי** — self-employed contribution estimate (explicitly labeled estimate;
   actual advances are based on the BL projected-income assessment, not monthly revenue)

Scope is **income side only** (invoices issued). Expenses / input-VAT offset are out of
scope for v1.

## Architecture

Stateless PowerShell module. Every run: read config → call yeshinvoice API → calculate
→ print/export. No database, no cache, no logging. yeshinvoice remains the single
source of truth; re-running always reflects current data.

```
YeshHeshbonitAPI/
├── docs/
│   └── superpowers/specs/          # this spec
├── src/YeshHeshbonit/
│   ├── YeshHeshbonit.psd1          # module manifest
│   ├── YeshHeshbonit.psm1          # dot-sources Public/ + Private/, exports Public
│   ├── Public/
│   │   ├── Get-TaxSummary.ps1      # main command
│   │   ├── Get-YeshInvoice.ps1     # raw invoice fetch (standalone use)
│   │   └── Export-TaxSummary.ps1   # CSV export for the accountant
│   └── Private/
│       ├── Invoke-YeshApi.ps1      # HTTP + auth header + pagination + fail-closed
│       ├── Get-YeshConfig.ps1      # loads/validates .env + config/rates.json
│       └── ConvertTo-TaxCalculation.ps1  # pure math, no I/O
├── config/rates.json               # ALL rates and doc-type mappings — nothing hardcoded
├── tests/                          # Pester 5
├── .env                            # secrets (gitignored)
├── .env.example
├── .gitignore
└── README.md
```

## yeshinvoice API (discovered from official docs at user.yeshinvoice.co.il/api/doc)

- **Base URLs:** `https://api.yeshinvoice.co.il/api/v1/` and `/api/v1.1/` (all POST, JSON)
- **Auth:** `Authorization` header whose value is a JSON object:
  `{"secret":"<YESH_SECRET>","userkey":"<YESH_USERKEY>"}` — loaded from `.env`
- **Primary endpoint:** `POST /api/v1/getInvoices`
  - Request body: `from`, `to` (date strings), `PageSize`, `PageNumber`, `Search`, `docTypes`
  - Response: `Success` (bool), `ErrorMessage`, `total`, `totalpage`, `ReturnValue[]`
  - Per document: `DocumentNumber`, `DocumentType`, `Date`, `CustomerID`, `CustomerName`,
    `TotalPrice`, `vattype`, `StatusID`, `MaxDateToPay`, `pdfUrl`, `items[]`
- Related (not used in v1, noted for future): `POST /api/v1.1/expenses/getall`,
  `POST /api/v1.1/report/vat` (PDF report).

## Components

### Invoke-YeshApi (Private)

Single choke point for HTTP. Builds the auth header from config, POSTs JSON, loops
`PageNumber` until all pages fetched (guided by `total`/`totalpage`), returns the
combined `ReturnValue` array.

Fail-closed rules (any violation → terminating error, no partial data returned):
- HTTP failure or non-2xx
- `Success` is not `$true`, or `ErrorMessage` non-empty
- A page fetch fails mid-pagination
- Response missing expected fields

### Get-YeshConfig (Private)

Loads `.env` (simple `KEY=value` parser) and `config/rates.json`. Validates presence and
types of every required key; refuses to run with a precise "missing X" message.
Credentials are never included in any error text or output.

### ConvertTo-TaxCalculation (Private)

Pure function: takes an invoice list + rates, returns calculation objects. No I/O, which
makes it directly unit-testable.

Per invoice:
- `net = gross / (1 + vatRate)`, `vat = gross − net` — for standard-VAT documents
- Documents whose `vattype` indicates zero/exempt VAT: `net = gross`, `vat = 0`
- Credit documents (חשבונית זיכוי): amounts contribute negatively
- Per-invoice values kept unrounded internally; display rounds to 2 decimals (אגורות);
  totals computed from unrounded sums, then rounded — avoids agorot drift

Per period:
- **מע"מ להפרשה** = Σ vat
- **מקדמות מס הכנסה** = `mikdamotRate` × Σ net
- **ביטוח לאומי (estimate)** = tiered: `reducedRate` on income up to
  `reducedRateThreshold × averageWageMonthly`, `fullRate` above (rates include health
  insurance). Computed on the period's net revenue normalized per month. Labeled
  "estimate" in output.

### Get-TaxSummary (Public)

```powershell
Get-TaxSummary -Month 2026-06
Get-TaxSummary -From 2026-05-01 -To 2026-06-30   # bi-monthly VAT period
Get-TaxSummary -Month 2026-06 -ExportCsv summary.csv
```

Parameter sets: `-Month` (string `yyyy-MM`) XOR `-From`/`-To` (dates). Validates input
dates (fail closed on nonsense ranges, e.g. From > To).

Flow: config → fetch via `Get-YeshInvoice` → filter to relevant documents → calculate →
emit. Output: a per-invoice table (date, doc number, customer, type, gross, net, VAT)
followed by a totals block (gross, net, מע"מ, מקדמות, ביטוח לאומי estimate + disclaimer).
Returns structured objects (formatted for display but pipeline-friendly).

### Get-YeshInvoice (Public)

Thin wrapper over `Invoke-YeshApi` for `getInvoices`: date range in, filtered raw
document objects out. Filtering rules:
- Include only document types listed in `revenueDocTypes` (config)
- Documents whose type is in `creditDocTypes` are included with negative sign
- Skip documents whose `StatusID` marks them cancelled

### Export-TaxSummary (Public)

Takes `Get-TaxSummary` output, writes UTF-8-with-BOM CSV (Hebrew must open correctly in
Excel): per-invoice rows + totals rows.

## Configuration — config/rates.json

```json
{
  "vatRate": 0.18,
  "mikdamotRate": 0.05,
  "bituachLeumi": {
    "averageWageMonthly": 13769,
    "reducedRateThreshold": 0.60,
    "reducedRate": 0.0597,
    "fullRate": 0.1783
  },
  "revenueDocTypes": [8, 9],
  "creditDocTypes": [10],
  "cancelledStatusIds": []
}
```

- `mikdamotRate` is personal — Eitan fills it from his מס הכנסה assessment letter.
- BL figures are 2026 values; year changes = edit this file only. Nothing is hardcoded
  in source.

### Verified ID mappings (live API + official docs, 2026-07-02)

`DocumentType` (from the create-invoice docs):

| ID | Document | Treatment |
|----|----------|-----------|
| 1 | הצעת מחיר | excluded |
| 2 | הזמנה | excluded |
| 3 | תעודת משלוח | excluded |
| 6 | קבלה | **excluded — payment record for an invoice already counted; including it double-counts revenue** (Eitan's account issues both 8 and 6) |
| 8 | חשבונית מס | revenue |
| 9 | חשבונית מס/קבלה | revenue |
| 10 | חשבונית זיכוי | credit (negative) |
| 11 | קבלה לתרומה | excluded |

`vattype` (from `POST /api/v1/getvatTypes`): 1 = לפני מע"מ, 2 = כולל מע"מ,
3 = פיקדון נאמנות (no VAT), 4 = ללא מע"מ. In `getInvoices` list responses `vattype`
can be empty — treat empty as כולל מע"מ (TotalPrice is gross); types 3 and 4
contribute no VAT. Verify the empty-value assumption against one known invoice during
implementation.

`StatusID`: live account shows 1 = active. The cancelled-status ID must still be
confirmed during implementation (create/cancel a test doc in sandbox, or check the
cancel-endpoint docs); until confirmed, `cancelledStatusIds` stays empty and every
non-1 status triggers a visible warning rather than silent inclusion.

## Security

- Credentials only in `.env` (gitignored); `.env.example` committed with placeholders
- Auth header built in one place (`Invoke-YeshApi`); never echoed, never in errors.
  Confirmed hazard: .NET header validation rejects the JSON-shaped Authorization value
  and **echoes it verbatim in the exception message** — `Invoke-YeshApi` must use
  `-SkipHeaderValidation` and wrap all exceptions so raw messages never surface
- Input validation on all parameters (dates, paths); config schema validated on load
- Fail closed everywhere: any unexpected state aborts rather than producing a
  plausible-but-wrong tax number
- No logging (per project standards)

## Testing (Pester 5, tests/)

- **ConvertTo-TaxCalculation** (pure): standard VAT split at 18%; zero/exempt vattype;
  credit-note negatives; mixed periods; rounding behavior (unrounded sums vs displayed);
  BL tier boundary (income exactly at threshold, below, above); zero-invoice period
- **Invoke-YeshApi** (mock `Invoke-RestMethod`): auth header shape; pagination across
  multiple pages; abort on `Success:false`; abort on HTTP error mid-pagination;
  no-partial-results guarantee
- **Get-YeshConfig**: missing .env key → precise failure; malformed rates.json → failure;
  valid config → typed object
- **Get-TaxSummary**: parameter-set validation (Month xor From/To); From > To rejected;
  doc-type filtering incl. credit and cancelled docs
- No live API calls in tests

## Out of Scope (v1)

- Expenses / input VAT (מע"מ תשומות) and net VAT position
- Local history store / retroactive-change detection
- Deadline reminders and scheduling
- PDF report generation via `report/vat`
