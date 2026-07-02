===============================================================================
 YeshHeshbonitAPI - tax set-aside calculator for an Israeli osek murshe
===============================================================================

Pulls the invoices you issued through yeshinvoice.co.il and tells you how much
to set aside, per month or per VAT period, for:

  - Ma'am (VAT)              - VAT collected on issued invoices
  - Mikdamot mas hachnasa    - your income-tax advance rate x pre-VAT turnover
  - Bituach Leumi            - self-employed national insurance (ESTIMATE)

Unofficial community tool. Not affiliated with yeshinvoice. Not tax advice -
always confirm the numbers with your accountant. Provided "as is", no warranty
(MIT License, see the LICENSE file).


-------------------------------------------------------------------------------
 REQUIREMENTS
-------------------------------------------------------------------------------

  - Windows with PowerShell 7 or newer   (run: pwsh)
  - A yeshinvoice.co.il account with API keys (a secret and a userkey)
  - Pode module        (web dashboard only):  Install-Module Pode -Scope CurrentUser
  - Pester 5           (to run the tests):    Install-Module Pester -Scope CurrentUser


-------------------------------------------------------------------------------
 QUICK SETUP
-------------------------------------------------------------------------------

  1. Get the code:
        git clone <repo-url> YeshHeshbonitAPI
        cd YeshHeshbonitAPI

  2. Load the module:
        Import-Module .\src\YeshHeshbonit\YeshHeshbonit.psd1

  3. Run the interactive setup:
        Initialize-YeshHeshbonit
     It prompts for your API secret + userkey (masked) and your mikdamot rate
     as a percent, verifies the keys against the API, then writes .env and
     config\rates.json (both gitignored - they stay on your machine).

     Prefer to do it by hand? Copy .env.example to .env and
     config\rates.example.json to config\rates.json, then edit them.


-------------------------------------------------------------------------------
 USAGE
-------------------------------------------------------------------------------

  Command line:
        Get-TaxSummary -Month 2026-07
        Get-TaxSummary -From 2026-05-01 -To 2026-06-30
        Get-TaxSummary -Month 2026-07 -ExportCsv .\2026-07-summary.csv

  Web dashboard (Hebrew, right-to-left; binds to 127.0.0.1 only):
        Start-TaxDashboard
        Start-TaxDashboard -Port 9000 -NoBrowser

  Tests:
        Invoke-Pester .\tests


-------------------------------------------------------------------------------
 MORE
-------------------------------------------------------------------------------

  Full step-by-step guide:  docs/SETUP.md
  License:                  LICENSE  (MIT)

  Built and maintained by SouliTEK - https://soulitek.co.il
  IT services and information security, Ra'anana, Israel.
  Contact: eitan@soulitek.co.il
