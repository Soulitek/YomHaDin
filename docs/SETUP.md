# Setup Guide

A step-by-step guide to get YeshHeshbonitAPI running on your machine. It pulls the
invoices you issued through [yeshinvoice.co.il](https://www.yeshinvoice.co.il) and tells
you how much to set aside for מע"מ, מקדמות מס הכנסה, and ביטוח לאומי.

> This is an unofficial, community tool — not affiliated with or endorsed by yeshinvoice.
> The figures are a planning aid, not tax advice. Always confirm with your accountant.

---

## 1. Prerequisites

| You need | How to get it |
|----------|---------------|
| **Windows** | The tool targets Windows and PowerShell 7. |
| **PowerShell 7+** | `winget install Microsoft.PowerShell`, then run `pwsh`. Check with `$PSVersionTable.PSVersion` (must be 7.0 or higher). |
| **yeshinvoice account + API keys** | Log in to yeshinvoice → account settings → API keys. You need a **secret** and a **userkey**. |
| **Pode** (only for the web dashboard) | `Install-Module Pode -Scope CurrentUser` |
| **Pester 5** (only to run the tests) | `Install-Module Pester -Scope CurrentUser -MinimumVersion 5.0` |

---

## 2. Get the code

```powershell
git clone <your-fork-or-repo-url> YeshHeshbonitAPI
cd YeshHeshbonitAPI
```

---

## 3. Add your API credentials

The tool reads credentials from a `.env` file that you create locally. It is gitignored —
it never gets committed.

```powershell
Copy-Item .env.example .env
```

Open `.env` and fill in your two keys:

```
YESH_SECRET=<your secret from yeshinvoice>
YESH_USERKEY=<your userkey from yeshinvoice>
```

---

## 4. Set your tax rates (required — you choose your rate)

The tool does **not** ship with a rate, so you set your own before first use.

```powershell
Copy-Item config\rates.example.json config\rates.json
```

Open `config\rates.json` and set **`mikdamotRate`** to your income-tax advance rate — the
percentage from your מס הכנסה assessment letter, written as a fraction (e.g. `0.08` for 8%).

The other values are current defaults you normally do not change:

| Key | Meaning | Default |
|-----|---------|---------|
| `vatRate` | VAT rate | `0.18` (18%) |
| `mikdamotRate` | **Your** income-tax advance rate | you set this |
| `bituachLeumi.*` | National-insurance brackets (2026) | preset |
| `revenueDocTypes` | yeshinvoice document types counted as income | `[8, 9]` (tax invoice, invoice-receipt) |
| `creditDocTypes` | document types counted as negative | `[10]` (credit note) |
| `cancelledStatusIds` | status IDs to exclude | `[]` |

`config\rates.json` is gitignored, so your personal rate stays on your machine.

> **Note on numbers:** VAT and מקדמות are exact. **ביטוח לאומי is an estimate** — your real
> advance is set by your Bituach Leumi assessment, which the tool cannot know. Verify the
> national-insurance rate figures against [btl.gov.il](https://www.btl.gov.il) for your year.

---

## 5. Import the module

```powershell
Import-Module .\src\YeshHeshbonit\YeshHeshbonit.psd1
```

If a credential or the rates file is missing or invalid, the tool refuses to run and tells
you exactly what to fix.

---

## 6. Use it

### Command line

```powershell
# One month
Get-TaxSummary -Month 2026-07

# A bi-monthly VAT period (any date range)
Get-TaxSummary -From 2026-05-01 -To 2026-06-30

# Export a CSV for your accountant
Get-TaxSummary -Month 2026-07 -ExportCsv .\2026-07-summary.csv
```

### Web dashboard

```powershell
Start-TaxDashboard          # opens http://127.0.0.1:8321 in your browser
Start-TaxDashboard -Port 9000 -NoBrowser
```

The dashboard (Hebrew, right-to-left) lets you pick a month, see the three set-aside cards
and a total-to-set-aside, browse the invoice table, and edit your מקדמות rate. It binds to
`127.0.0.1` only — it is never reachable from the network. Press `Ctrl+C` to stop it.

---

## 7. Run the tests (optional)

```powershell
Invoke-Pester .\tests
```

---

## Troubleshooting

| Message | Fix |
|---------|-----|
| `Missing .env file …` | Do step 3 — copy `.env.example` to `.env` and fill in your keys. |
| `Missing or placeholder value for 'YESH_SECRET' …` | Your `.env` still has the placeholder; paste your real key. |
| `Missing rates file …` | Do step 4 — copy `config\rates.example.json` to `config\rates.json`. |
| `The Pode module is required …` | `Install-Module Pode -Scope CurrentUser`. |
| Dashboard shows fewer invoices than expected | Only document types in `revenueDocTypes` (tax invoices / invoice-receipts) are counted. Standalone receipts (קבלה) are excluded to avoid double-counting income already invoiced. |

---

## Security notes

- Never commit `.env` or `config/rates.json` — both are gitignored by default; keep it that way.
- Credentials are sent only to `api.yeshinvoice.co.il` over HTTPS and are never written to logs or error messages.
- The dashboard is for local use on your own machine (localhost, no authentication). Do not expose it to a network.
