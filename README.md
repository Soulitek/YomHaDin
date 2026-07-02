# YeshHeshbonitAPI

Per-invoice tax set-aside calculator for an עוסק מורשה, pulling issued invoices from the
[yeshinvoice.co.il](https://www.yeshinvoice.co.il) API. For a given month or bi-monthly
VAT period, calculates how much to set aside for:

- **מע"מ** — VAT collected on issued invoices
- **מקדמות מס הכנסה** — personal advance rate × pre-VAT turnover
- **ביטוח לאומי** — self-employed contribution (estimate)

## Requirements

- Windows, PowerShell 7+
- yeshinvoice.co.il account with API credentials (secret + userkey)
- Pester 5 (dev/testing only)

## Setup

1. Copy `.env.example` to `.env` and fill in your API credentials.
2. Edit `config/rates.json` — set your personal `mikdamotRate` from your מס הכנסה
   assessment letter. VAT and ביטוח לאומי figures are current for 2026.
3. Import the module:

```powershell
Import-Module .\src\YeshHeshbonit\YeshHeshbonit.psd1
```

## Usage

```powershell
# Monthly summary
Get-TaxSummary -Month 2026-06

# Bi-monthly VAT period
Get-TaxSummary -From 2026-05-01 -To 2026-06-30

# Export for the accountant
Get-TaxSummary -Month 2026-06 -ExportCsv .\2026-06-summary.csv
```

## Tests

```powershell
Invoke-Pester .\tests
```

## Documentation

- Design spec: [docs/superpowers/specs/2026-07-02-yeshheshbonit-tax-calc-design.md](docs/superpowers/specs/2026-07-02-yeshheshbonit-tax-calc-design.md)

## Status

Working. Run `Invoke-Pester .\tests` to verify (46 tests).

Remember to set `mikdamotRate` in `config/rates.json` to your actual rate from the
מס הכנסה assessment letter — the committed value is a placeholder default.
