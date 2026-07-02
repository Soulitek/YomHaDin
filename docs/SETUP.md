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

## 3. Import the module

```powershell
Import-Module .\src\YeshHeshbonit\YeshHeshbonit.psd1
```

---

## 4. Configure (interactive — recommended)

Run the one-time setup and answer the prompts:

```powershell
Initialize-YeshHeshbonit
```

It asks for:

- your yeshinvoice **API secret** and **userkey** (input is masked), and
- your **income-tax advance rate (מקדמות)** as a percent — you type `8`, it stores `0.08`.

It then **verifies the keys against the API** (so a typo is caught immediately), and writes
`.env` and `config/rates.json`. If the keys don't work, nothing is saved. Both files are
gitignored, so your keys and rate stay on your machine. Pass `-SkipTest` to save without the
online check, or `-Force` to overwrite an existing configuration.

### Or configure by hand

```powershell
Copy-Item .env.example .env                              # then edit: YESH_SECRET, YESH_USERKEY
Copy-Item config\rates.example.json config\rates.json    # then set mikdamotRate (fraction, e.g. 0.08)
```

The rate values you normally don't change:

| Key | Meaning | Default |
|-----|---------|---------|
| `vatRate` | VAT rate | `0.18` (18%) |
| `mikdamotRate` | **Your** income-tax advance rate | you set this |
| `bituachLeumi.*` | National-insurance brackets (2026) | preset |
| `revenueDocTypes` | yeshinvoice document types counted as income | `[8, 9]` (tax invoice, invoice-receipt) |
| `creditDocTypes` | document types counted as negative | `[10]` (credit note) |
| `cancelledStatusIds` | status IDs to exclude | `[]` |

> **Note on numbers:** VAT and מקדמות are exact. **ביטוח לאומי is an estimate** — your real
> advance is set by your Bituach Leumi assessment, which the tool cannot know. Verify the
> national-insurance rate figures against [btl.gov.il](https://www.btl.gov.il) for your year.

If a credential or the rates file is missing or invalid, the tool refuses to run and tells
you exactly what to fix.

---

## 5. Use it

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

## 6. Run the tests (optional)

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

---

Built and maintained by **[SouliTEK](https://soulitek.co.il)** — IT services and information
security, Ra'anana, Israel. Questions: eitan@soulitek.co.il
