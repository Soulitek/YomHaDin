# YeshHeshbonitAPI

Per-invoice tax set-aside calculator for an עוסק מורשה, pulling issued invoices from the
[yeshinvoice.co.il](https://www.yeshinvoice.co.il) API. For a given month or bi-monthly
VAT period, calculates how much to set aside for:

- **מע"מ** — VAT collected on issued invoices
- **מקדמות מס הכנסה** — personal advance rate × pre-VAT turnover
- **ביטוח לאומי** — self-employed contribution (estimate)

> **Unofficial tool.** Not affiliated with or endorsed by yeshinvoice. The figures are a
> planning aid, **not tax advice** — VAT and מקדמות are exact, but ביטוח לאומי is an
> estimate (your real advance is set by your Bituach Leumi assessment). Always confirm
> with your accountant. Provided "as is", no warranty (see [LICENSE](LICENSE)).

**New here? Follow the [Setup Guide](docs/SETUP.md).**

## Requirements

- Windows, PowerShell 7+
- yeshinvoice.co.il account with API credentials (secret + userkey)
- Pode module (dashboard only): `Install-Module Pode -Scope CurrentUser`
- Pester 5 (dev/testing only)

## Setup

See the [Setup Guide](docs/SETUP.md) for the full walkthrough. In short:

1. Copy `.env.example` to `.env` and fill in your API credentials.
2. Copy `config/rates.example.json` to `config/rates.json` and set your personal
   `mikdamotRate` from your מס הכנסה assessment letter (a fraction, e.g. `0.08`).
   Both files are gitignored — your keys and rate stay on your machine.
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

### Web dashboard

```powershell
Start-TaxDashboard              # http://127.0.0.1:8321, opens your browser
Start-TaxDashboard -Port 9000 -NoBrowser
```

Hebrew RTL dashboard: period picker, set-aside cards (מע"מ / מקדמות / ביטוח לאומי),
invoice table, accountant CSV download. Binds to 127.0.0.1 only — never reachable
from the network.

## Tests

```powershell
Invoke-Pester .\tests
```

## Documentation

- [Setup Guide](docs/SETUP.md) — full install and first-run walkthrough
- Design specs and plans live under [docs/superpowers/](docs/superpowers/)

## License

[MIT](LICENSE) © 2026 SouliTEK
