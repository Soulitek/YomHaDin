# YeshHeshbonitAPI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PowerShell module that pulls issued invoices from the yeshinvoice.co.il API and calculates per-period set-asides: מע"מ, מקדמות מס הכנסה, ביטוח לאומי (estimate).

**Architecture:** Stateless module (`src/YeshHeshbonit/`): config loader → API client (fail-closed, paginated) → pure calculation function → CLI command + CSV export. No database, no cache, no logging. Spec: `docs/superpowers/specs/2026-07-02-yeshheshbonit-tax-calc-design.md`.

**Tech Stack:** PowerShell 7+, Pester 5. No external dependencies.

## Global Constraints

- PowerShell 7.0+ only (`-SkipHeaderValidation`, `utf8BOM` encoding rely on it)
- ALL rates and ID mappings live in `config/rates.json` — never hardcoded in source
- Credentials only from `.env` (`YESH_SECRET`, `YESH_USERKEY`); never in output, errors, or logs
- **Fail closed:** any API failure, partial page fetch, unknown `vattype`, or invalid config → terminating error; never emit a partial total
- .NET header validation echoes the Authorization value in exceptions — every `Invoke-RestMethod` call must use `-SkipHeaderValidation` and wrap exceptions with sanitized messages
- No logging of any kind (project standard)
- Verified ID mappings (do not change without re-verification): revenue DocumentTypes 8 (חשבונית מס), 9 (חשבונית מס/קבלה); credit 10 (חשבונית זיכוי); **type 6 (קבלה) is excluded — including it double-counts revenue**. `vattype`: 1 = לפני מע"מ, 2/empty = כולל מע"מ, 3/4 = no VAT.
- API: base `https://api.yeshinvoice.co.il/`, all POST JSON; `Authorization` header value is compact JSON `{"secret":"…","userkey":"…"}`
- Tests never call the live API
- Commit after every task with the `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` trailer

---

### Task 1: Module skeleton + rates.json

**Files:**
- Create: `src/YeshHeshbonit/YeshHeshbonit.psd1`
- Create: `src/YeshHeshbonit/YeshHeshbonit.psm1`
- Create: `config/rates.json`
- Test: `tests/Module.Tests.ps1`

**Interfaces:**
- Consumes: nothing
- Produces: importable module exporting `Get-TaxSummary`, `Get-YeshInvoice`, `Export-TaxSummary` (stubs created by later tasks; manifest lists them now); `config/rates.json` with the schema every other task reads

- [ ] **Step 1: Write the failing test**

`tests/Module.Tests.ps1`:

```powershell
Describe 'YeshHeshbonit module' {
    BeforeAll {
        $script:manifestPath = Join-Path $PSScriptRoot '..\src\YeshHeshbonit\YeshHeshbonit.psd1'
    }

    It 'has a valid manifest' {
        { Test-ModuleManifest -Path $manifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'declares the three public functions' {
        $manifest = Test-ModuleManifest -Path $manifestPath
        $manifest.ExportedFunctions.Keys | Sort-Object |
            Should -Be @('Export-TaxSummary', 'Get-TaxSummary', 'Get-YeshInvoice')
    }

    It 'ships a rates.json with all required keys' {
        $rates = Get-Content (Join-Path $PSScriptRoot '..\config\rates.json') -Raw | ConvertFrom-Json
        $rates.vatRate | Should -Be 0.18
        $rates.mikdamotRate | Should -Not -BeNullOrEmpty
        $rates.bituachLeumi.averageWageMonthly | Should -BeGreaterThan 0
        $rates.bituachLeumi.reducedRateThreshold | Should -BeGreaterThan 0
        $rates.bituachLeumi.reducedRate | Should -BeGreaterThan 0
        $rates.bituachLeumi.fullRate | Should -BeGreaterThan 0
        @($rates.revenueDocTypes) | Should -Be @(8, 9)
        @($rates.creditDocTypes) | Should -Be @(10)
        $null -ne $rates.cancelledStatusIds | Should -BeTrue
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester .\tests\Module.Tests.ps1 -Output Detailed`
Expected: FAIL — manifest file not found.

- [ ] **Step 3: Write the implementation**

`config/rates.json` (mikdamotRate 0.05 is a placeholder default — Eitan overwrites with his assessment-letter rate):

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

`src/YeshHeshbonit/YeshHeshbonit.psm1`:

```powershell
$privateDir = Join-Path $PSScriptRoot 'Private'
$publicDir = Join-Path $PSScriptRoot 'Public'
$private = @(if (Test-Path $privateDir) { Get-ChildItem -Path $privateDir -Filter '*.ps1' })
$public = @(if (Test-Path $publicDir) { Get-ChildItem -Path $publicDir -Filter '*.ps1' })
foreach ($file in ($private + $public)) { . $file.FullName }
Export-ModuleMember -Function $public.BaseName
```

`src/YeshHeshbonit/YeshHeshbonit.psd1`:

```powershell
@{
    RootModule        = 'YeshHeshbonit.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'e1a9c2b4-7f3d-4a6e-9b0c-2d8f5e1a7c3b'
    Author            = 'Eitan / SouliTEK'
    Description       = 'Per-invoice tax set-aside calculator over the yeshinvoice.co.il API (VAT / mikdamot / Bituach Leumi).'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Get-TaxSummary', 'Get-YeshInvoice', 'Export-TaxSummary')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
```

Note: `Test-ModuleManifest` requires the exported functions to be resolvable only at `Import-Module` time, not manifest-validation time, so the manifest test passes before the Public files exist.

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester .\tests\Module.Tests.ps1 -Output Detailed`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```powershell
git add src config tests
git commit -m "feat: module skeleton, manifest, and rates.json"
```

---

### Task 2: Get-YeshConfig (Private)

**Files:**
- Create: `src/YeshHeshbonit/Private/Get-YeshConfig.ps1`
- Test: `tests/Get-YeshConfig.Tests.ps1`

**Interfaces:**
- Consumes: `.env` file (`KEY=value` lines, `#` comments), `config/rates.json`
- Produces: `Get-YeshConfig [-EnvPath <string>] [-RatesPath <string>]` → `[pscustomobject]` with properties `Secret` (string), `UserKey` (string), `Rates` (the parsed rates.json object). Throws a terminating error naming the exact missing/invalid key.

- [ ] **Step 1: Write the failing tests**

`tests/Get-YeshConfig.Tests.ps1`:

```powershell
BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Get-YeshConfig.ps1')

    $script:goodRatesJson = @'
{
  "vatRate": 0.18,
  "mikdamotRate": 0.05,
  "bituachLeumi": { "averageWageMonthly": 13769, "reducedRateThreshold": 0.60, "reducedRate": 0.0597, "fullRate": 0.1783 },
  "revenueDocTypes": [8, 9],
  "creditDocTypes": [10],
  "cancelledStatusIds": []
}
'@
    $script:goodEnv = "# comment`nYESH_SECRET=abc-123`nYESH_USERKEY=key-456`n"
}

Describe 'Get-YeshConfig' {
    BeforeEach {
        $script:envPath = Join-Path $TestDrive '.env'
        $script:ratesPath = Join-Path $TestDrive 'rates.json'
        Set-Content -Path $envPath -Value $goodEnv -NoNewline
        Set-Content -Path $ratesPath -Value $goodRatesJson -NoNewline
    }

    It 'returns secret, userkey and rates from valid files' {
        $config = Get-YeshConfig -EnvPath $envPath -RatesPath $ratesPath
        $config.Secret | Should -Be 'abc-123'
        $config.UserKey | Should -Be 'key-456'
        $config.Rates.vatRate | Should -Be 0.18
        @($config.Rates.revenueDocTypes) | Should -Be @(8, 9)
    }

    It 'fails closed when .env is missing' {
        { Get-YeshConfig -EnvPath (Join-Path $TestDrive 'nope.env') -RatesPath $ratesPath } |
            Should -Throw '*Missing .env*'
    }

    It 'fails closed on placeholder credentials' {
        Set-Content -Path $envPath -Value "YESH_SECRET=your-secret-guid-here`nYESH_USERKEY=x`n"
        { Get-YeshConfig -EnvPath $envPath -RatesPath $ratesPath } | Should -Throw '*YESH_SECRET*'
    }

    It 'fails closed when a required env key is empty' {
        Set-Content -Path $envPath -Value "YESH_SECRET=abc`nYESH_USERKEY=`n"
        { Get-YeshConfig -EnvPath $envPath -RatesPath $ratesPath } | Should -Throw '*YESH_USERKEY*'
    }

    It 'fails closed on malformed rates.json' {
        Set-Content -Path $ratesPath -Value '{ not json'
        { Get-YeshConfig -EnvPath $envPath -RatesPath $ratesPath } | Should -Throw '*not valid JSON*'
    }

    It 'fails closed on out-of-range vatRate' {
        Set-Content -Path $ratesPath -Value ($goodRatesJson -replace '0\.18', '18')
        { Get-YeshConfig -EnvPath $envPath -RatesPath $ratesPath } | Should -Throw '*vatRate*'
    }

    It 'fails closed when revenueDocTypes is empty' {
        Set-Content -Path $ratesPath -Value ($goodRatesJson -replace '\[8, 9\]', '[]')
        { Get-YeshConfig -EnvPath $envPath -RatesPath $ratesPath } | Should -Throw '*revenueDocTypes*'
    }

    It 'never includes the secret value in error text' {
        Set-Content -Path $ratesPath -Value '{ not json'
        $err = $null
        try { Get-YeshConfig -EnvPath $envPath -RatesPath $ratesPath } catch { $err = $_ }
        $err.Exception.Message | Should -Not -Match 'abc-123'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester .\tests\Get-YeshConfig.Tests.ps1 -Output Detailed`
Expected: FAIL — dot-source error, file `Get-YeshConfig.ps1` does not exist.

- [ ] **Step 3: Write the implementation**

`src/YeshHeshbonit/Private/Get-YeshConfig.ps1`:

```powershell
function Get-YeshConfig {
    [CmdletBinding()]
    param(
        [string]$EnvPath,
        [string]$RatesPath
    )

    # Project root = three levels up from Private/ (Private -> YeshHeshbonit -> src -> root)
    $root = (Get-Item $PSScriptRoot).Parent.Parent.Parent.FullName
    if (-not $EnvPath) { $EnvPath = Join-Path $root '.env' }
    if (-not $RatesPath) { $RatesPath = Join-Path $root 'config\rates.json' }

    if (-not (Test-Path $EnvPath)) {
        throw "Missing .env file at '$EnvPath'. Copy .env.example and fill in your yeshinvoice credentials."
    }
    $envVars = @{}
    foreach ($line in Get-Content $EnvPath) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $key, $value = $line -split '=', 2
        $envVars[$key.Trim()] = $value.Trim()
    }
    foreach ($required in 'YESH_SECRET', 'YESH_USERKEY') {
        if ([string]::IsNullOrWhiteSpace($envVars[$required]) -or $envVars[$required] -like 'your-*') {
            throw "Missing or placeholder value for '$required' in .env."
        }
    }

    if (-not (Test-Path $RatesPath)) {
        throw "Missing rates file at '$RatesPath'."
    }
    try {
        $rates = Get-Content $RatesPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Rates file at '$RatesPath' is not valid JSON."
    }

    if ($null -eq $rates.vatRate -or $rates.vatRate -le 0 -or $rates.vatRate -ge 1) {
        throw "rates.json: 'vatRate' must be a number between 0 and 1 (e.g. 0.18)."
    }
    if ($null -eq $rates.mikdamotRate -or $rates.mikdamotRate -lt 0 -or $rates.mikdamotRate -ge 1) {
        throw "rates.json: 'mikdamotRate' must be a number between 0 and 1 (from your mas hachnasa assessment letter)."
    }
    foreach ($key in 'averageWageMonthly', 'reducedRateThreshold', 'reducedRate', 'fullRate') {
        if ($null -eq $rates.bituachLeumi.$key -or $rates.bituachLeumi.$key -le 0) {
            throw "rates.json: 'bituachLeumi.$key' must be a positive number."
        }
    }
    if (-not $rates.revenueDocTypes -or @($rates.revenueDocTypes).Count -eq 0) {
        throw "rates.json: 'revenueDocTypes' must be a non-empty array of DocumentType IDs."
    }
    if ($null -eq $rates.creditDocTypes) {
        throw "rates.json: 'creditDocTypes' must be an array (may be empty)."
    }
    if ($null -eq $rates.cancelledStatusIds) {
        throw "rates.json: 'cancelledStatusIds' must be an array (may be empty)."
    }

    [pscustomobject]@{
        Secret  = $envVars['YESH_SECRET']
        UserKey = $envVars['YESH_USERKEY']
        Rates   = $rates
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester .\tests\Get-YeshConfig.Tests.ps1 -Output Detailed`
Expected: 8 tests PASS.

- [ ] **Step 5: Commit**

```powershell
git add src/YeshHeshbonit/Private/Get-YeshConfig.ps1 tests/Get-YeshConfig.Tests.ps1
git commit -m "feat: config loader with fail-closed validation"
```

---

### Task 3: ConvertTo-TaxCalculation (Private, pure math)

**Files:**
- Create: `src/YeshHeshbonit/Private/ConvertTo-TaxCalculation.ps1`
- Test: `tests/ConvertTo-TaxCalculation.Tests.ps1`

**Interfaces:**
- Consumes: document objects with `DocumentType`, `TotalPrice`, `vattype`, `Date`, `DocumentNumber`, `CustomerName` (shape returned by `getInvoices`); `Rates` object from `Get-YeshConfig().Rates`
- Produces: `ConvertTo-TaxCalculation -Documents <object[]> -Rates <pscustomobject> [-MonthsInPeriod <int>]` → `[pscustomobject]` with:
  - `.Invoices` — array of `[pscustomobject]` `{ Date, DocumentNumber, DocumentType, Customer, Gross, Net, Vat }` (unrounded doubles)
  - `.Totals` — `[pscustomobject]` `{ Gross, Net, Vat, Mikdamot, BituachLeumiEstimate, MonthsInPeriod }` (rounded to 2 decimals, computed from unrounded sums)

- [ ] **Step 1: Write the failing tests**

`tests/ConvertTo-TaxCalculation.Tests.ps1`:

```powershell
BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\ConvertTo-TaxCalculation.ps1')

    $script:rates = [pscustomobject]@{
        vatRate      = 0.18
        mikdamotRate = 0.05
        bituachLeumi = [pscustomobject]@{
            averageWageMonthly   = 13769
            reducedRateThreshold = 0.60   # threshold = 8261.40
            reducedRate          = 0.0597
            fullRate             = 0.1783
        }
        revenueDocTypes    = @(8, 9)
        creditDocTypes     = @(10)
        cancelledStatusIds = @()
    }

    function New-Doc {
        param($Type = 8, $Price = 1180, $VatType = '', $Number = '1001', $Customer = 'Client A', $Date = '01-06-2026')
        [pscustomobject]@{
            DocumentType = $Type; TotalPrice = $Price; vattype = $VatType
            DocumentNumber = $Number; CustomerName = $Customer; Date = $Date
        }
    }
}

Describe 'ConvertTo-TaxCalculation' {
    It 'splits a VAT-inclusive invoice into net and VAT' {
        $result = ConvertTo-TaxCalculation -Documents @(New-Doc -Price 1180) -Rates $rates
        [math]::Round($result.Invoices[0].Net, 2) | Should -Be 1000
        [math]::Round($result.Invoices[0].Vat, 2) | Should -Be 180
        [math]::Round($result.Invoices[0].Gross, 2) | Should -Be 1180
    }

    It 'treats empty vattype as VAT-inclusive' {
        $result = ConvertTo-TaxCalculation -Documents @(New-Doc -VatType '') -Rates $rates
        $result.Invoices[0].Vat | Should -BeGreaterThan 0
    }

    It 'treats vattype 1 (before VAT) as net-basis' {
        $result = ConvertTo-TaxCalculation -Documents @(New-Doc -Price 1000 -VatType 1) -Rates $rates
        [math]::Round($result.Invoices[0].Net, 2) | Should -Be 1000
        [math]::Round($result.Invoices[0].Vat, 2) | Should -Be 180
        [math]::Round($result.Invoices[0].Gross, 2) | Should -Be 1180
    }

    It 'assigns no VAT to vattype 3 and 4' {
        foreach ($vt in 3, 4) {
            $result = ConvertTo-TaxCalculation -Documents @(New-Doc -Price 500 -VatType $vt) -Rates $rates
            $result.Invoices[0].Vat | Should -Be 0
            [math]::Round($result.Invoices[0].Net, 2) | Should -Be 500
        }
    }

    It 'fails closed on an unknown vattype' {
        { ConvertTo-TaxCalculation -Documents @(New-Doc -VatType 99) -Rates $rates } |
            Should -Throw '*vattype*'
    }

    It 'counts credit notes (type 10) as negative' {
        $docs = @((New-Doc -Price 1180), (New-Doc -Type 10 -Price 118 -Number '1002'))
        $result = ConvertTo-TaxCalculation -Documents $docs -Rates $rates
        [math]::Round($result.Totals.Net, 2) | Should -Be 900
        [math]::Round($result.Totals.Vat, 2) | Should -Be 162
    }

    It 'computes mikdamot as rate times net' {
        $result = ConvertTo-TaxCalculation -Documents @(New-Doc -Price 29500) -Rates $rates
        $result.Totals.Net | Should -Be 25000
        $result.Totals.Mikdamot | Should -Be 1250
    }

    It 'computes Bituach Leumi below the reduced-rate threshold' {
        # net 8000 <= threshold 8261.40 -> 8000 * 0.0597 = 477.60
        $result = ConvertTo-TaxCalculation -Documents @(New-Doc -Price 9440) -Rates $rates
        $result.Totals.BituachLeumiEstimate | Should -Be 477.6
    }

    It 'computes Bituach Leumi across the threshold' {
        # net 25000: 8261.40*0.0597 + 16738.60*0.1783 = 493.20558 + 2984.49238 = 3477.70
        $result = ConvertTo-TaxCalculation -Documents @(New-Doc -Price 29500) -Rates $rates
        $result.Totals.BituachLeumiEstimate | Should -Be 3477.7
    }

    It 'normalizes Bituach Leumi per month over multi-month periods' {
        # two months, 29500 gross total -> monthly net 12500
        # monthly BL: 8261.40*0.0597 + 4238.60*0.1783 = 493.20558 + 755.74238 = 1248.94796
        # period BL = 2 * 1248.94796 = 2497.90
        $result = ConvertTo-TaxCalculation -Documents @(New-Doc -Price 29500) -Rates $rates -MonthsInPeriod 2
        $result.Totals.BituachLeumiEstimate | Should -Be 2497.9
    }

    It 'returns zero totals for an empty period' {
        $result = ConvertTo-TaxCalculation -Documents @() -Rates $rates
        $result.Invoices.Count | Should -Be 0
        $result.Totals.Net | Should -Be 0
        $result.Totals.Vat | Should -Be 0
        $result.Totals.Mikdamot | Should -Be 0
        $result.Totals.BituachLeumiEstimate | Should -Be 0
    }

    It 'sums unrounded values before rounding totals' {
        # 3 x 100 gross: each net = 84.745762..., sum = 254.237288... -> 254.24
        # per-invoice rounding first would give 84.75*3 = 254.25 (wrong)
        $docs = 1..3 | ForEach-Object { New-Doc -Price 100 -Number "10$_" }
        $result = ConvertTo-TaxCalculation -Documents $docs -Rates $rates
        $result.Totals.Net | Should -Be 254.24
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester .\tests\ConvertTo-TaxCalculation.Tests.ps1 -Output Detailed`
Expected: FAIL — dot-source error, file does not exist.

- [ ] **Step 3: Write the implementation**

`src/YeshHeshbonit/Private/ConvertTo-TaxCalculation.ps1`:

```powershell
function ConvertTo-TaxCalculation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Documents,
        [Parameter(Mandatory)][pscustomobject]$Rates,
        [ValidateRange(1, 120)][int]$MonthsInPeriod = 1
    )

    $noVatTypes = @(3, 4)

    $invoices = @(foreach ($doc in $Documents) {
        $sign = if (@($Rates.creditDocTypes) -contains [int]$doc.DocumentType) { -1 } else { 1 }
        $amount = [double]$doc.TotalPrice * $sign
        $vatType = if ([string]::IsNullOrWhiteSpace("$($doc.vattype)")) { 2 } else { [int]$doc.vattype }

        if ($vatType -eq 1) {
            # lifnei maam: TotalPrice excludes VAT
            $net = $amount
            $vat = $amount * $Rates.vatRate
        }
        elseif ($vatType -eq 2) {
            # kolel maam: TotalPrice includes VAT
            $net = $amount / (1 + $Rates.vatRate)
            $vat = $amount - $net
        }
        elseif ($noVatTypes -contains $vatType) {
            $net = $amount
            $vat = 0.0
        }
        else {
            throw "Unknown vattype '$vatType' on document $($doc.DocumentNumber) - refusing to guess a VAT treatment."
        }

        [pscustomobject]@{
            Date           = $doc.Date
            DocumentNumber = $doc.DocumentNumber
            DocumentType   = [int]$doc.DocumentType
            Customer       = $doc.CustomerName
            Gross          = $net + $vat
            Net            = $net
            Vat            = $vat
        }
    })

    $totalNet = [double](($invoices | Measure-Object -Property Net -Sum).Sum ?? 0)
    $totalVat = [double](($invoices | Measure-Object -Property Vat -Sum).Sum ?? 0)

    $bl = $Rates.bituachLeumi
    $threshold = [double]$bl.averageWageMonthly * [double]$bl.reducedRateThreshold
    $monthlyNet = $totalNet / $MonthsInPeriod
    $blMonthly =
        if ($monthlyNet -le 0) { 0.0 }
        elseif ($monthlyNet -le $threshold) { $monthlyNet * $bl.reducedRate }
        else { $threshold * $bl.reducedRate + ($monthlyNet - $threshold) * $bl.fullRate }

    [pscustomobject]@{
        Invoices = $invoices
        Totals   = [pscustomobject]@{
            Gross                = [math]::Round($totalNet + $totalVat, 2)
            Net                  = [math]::Round($totalNet, 2)
            Vat                  = [math]::Round($totalVat, 2)
            Mikdamot             = [math]::Round($totalNet * $Rates.mikdamotRate, 2)
            BituachLeumiEstimate = [math]::Round($blMonthly * $MonthsInPeriod, 2)
            MonthsInPeriod       = $MonthsInPeriod
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester .\tests\ConvertTo-TaxCalculation.Tests.ps1 -Output Detailed`
Expected: 12 tests PASS.

- [ ] **Step 5: Commit**

```powershell
git add src/YeshHeshbonit/Private/ConvertTo-TaxCalculation.ps1 tests/ConvertTo-TaxCalculation.Tests.ps1
git commit -m "feat: pure tax calculation (VAT split, mikdamot, Bituach Leumi tiers)"
```

---

### Task 4: Invoke-YeshApi (Private HTTP layer)

**Files:**
- Create: `src/YeshHeshbonit/Private/Invoke-YeshApi.ps1`
- Test: `tests/Invoke-YeshApi.Tests.ps1`

**Interfaces:**
- Consumes: `Config` object from `Get-YeshConfig` (uses `.Secret`, `.UserKey`)
- Produces:
  - `Invoke-YeshApi -Endpoint <string> -Body <hashtable> -Config <pscustomobject>` → raw response object (`Success`, `ErrorMessage`, `total`, `ReturnValue`, …)
  - `Invoke-YeshApi … -Paginate` → combined `object[]` of all pages' `ReturnValue`
  - Both throw sanitized terminating errors; raw `Invoke-RestMethod` exceptions never propagate

- [ ] **Step 1: Write the failing tests**

`tests/Invoke-YeshApi.Tests.ps1`:

```powershell
BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Invoke-YeshApi.ps1')
    $script:config = [pscustomobject]@{ Secret = 'test-secret-value'; UserKey = 'test-user-key'; Rates = $null }
}

Describe 'Invoke-YeshApi' {
    It 'sends the JSON credential object in the Authorization header' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{ Success = $true; ErrorMessage = ''; ReturnValue = @() }
        } -ParameterFilter {
            $Headers.Authorization -eq '{"secret":"test-secret-value","userkey":"test-user-key"}'
        }
        Invoke-YeshApi -Endpoint 'api/v1/getvatTypes' -Body @{} -Config $config | Out-Null
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly
    }

    It 'fails closed when the API reports Success=false' {
        Mock Invoke-RestMethod { [pscustomobject]@{ Success = $false; ErrorMessage = 'invalid credentials' } }
        { Invoke-YeshApi -Endpoint 'api/v1/getInvoices' -Body @{} -Config $config } |
            Should -Throw '*invalid credentials*'
    }

    It 'sanitizes transport exceptions so credentials never leak' {
        Mock Invoke-RestMethod { throw "The format of value '{""secret"":""test-secret-value""}' is invalid." }
        $err = $null
        try { Invoke-YeshApi -Endpoint 'api/v1/getInvoices' -Body @{} -Config $config } catch { $err = $_ }
        $err | Should -Not -BeNullOrEmpty
        $err.Exception.Message | Should -Not -Match 'test-secret-value'
        $err.Exception.Message | Should -Match 'withheld'
    }

    It 'combines all pages when -Paginate is set' {
        $script:page = 0
        Mock Invoke-RestMethod {
            $script:page++
            if ($script:page -eq 1) {
                [pscustomobject]@{ Success = $true; ErrorMessage = ''; total = 3; ReturnValue = @(
                    [pscustomobject]@{ ID = 1 }, [pscustomobject]@{ ID = 2 }) }
            }
            else {
                [pscustomobject]@{ Success = $true; ErrorMessage = ''; total = 3; ReturnValue = @(
                    [pscustomobject]@{ ID = 3 }) }
            }
        }
        $result = Invoke-YeshApi -Endpoint 'api/v1/getInvoices' -Body @{ PageSize = 2 } -Config $config -Paginate
        $result.Count | Should -Be 3
        $result.ID | Should -Be @(1, 2, 3)
        Should -Invoke Invoke-RestMethod -Times 2 -Exactly
    }

    It 'fails closed if a page comes back empty before total is reached' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{ Success = $true; ErrorMessage = ''; total = 5; ReturnValue = @() }
        }
        { Invoke-YeshApi -Endpoint 'api/v1/getInvoices' -Body @{} -Config $config -Paginate } |
            Should -Throw '*partial*'
    }

    It 'returns an empty array for a zero-result paginated query' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{ Success = $true; ErrorMessage = ''; total = 0; ReturnValue = @() }
        }
        $result = Invoke-YeshApi -Endpoint 'api/v1/getInvoices' -Body @{} -Config $config -Paginate
        @($result).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester .\tests\Invoke-YeshApi.Tests.ps1 -Output Detailed`
Expected: FAIL — dot-source error, file does not exist.

- [ ] **Step 3: Write the implementation**

`src/YeshHeshbonit/Private/Invoke-YeshApi.ps1`:

```powershell
function Invoke-YeshApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)][hashtable]$Body,
        [Parameter(Mandatory)][pscustomobject]$Config,
        [switch]$Paginate
    )

    # Ordered so the header is byte-stable and testable
    $auth = [ordered]@{ secret = $Config.Secret; userkey = $Config.UserKey } | ConvertTo-Json -Compress
    $headers = @{ Authorization = $auth }
    $uri = "https://api.yeshinvoice.co.il/$Endpoint"

    if (-not $Paginate) {
        return Invoke-YeshApiPage -Uri $uri -Headers $headers -Body $Body
    }

    $all = [System.Collections.Generic.List[object]]::new()
    $page = 1
    while ($true) {
        $pageBody = @{} + $Body
        $pageBody['PageNumber'] = $page
        $response = Invoke-YeshApiPage -Uri $uri -Headers $headers -Body $pageBody
        foreach ($item in @($response.ReturnValue)) { $all.Add($item) }
        if ($all.Count -ge [int]$response.total) { break }
        if (@($response.ReturnValue).Count -eq 0) {
            throw "yeshinvoice returned $($all.Count) of $($response.total) documents and stopped. Aborting - refusing to calculate on partial data."
        }
        $page++
    }
    return $all.ToArray()
}

function Invoke-YeshApiPage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)][hashtable]$Body
    )
    try {
        # -SkipHeaderValidation is required: .NET rejects the JSON-shaped Authorization
        # value AND echoes it verbatim in the exception, which would leak credentials.
        $response = Invoke-RestMethod -Method Post -Uri $Uri -Headers $Headers `
            -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Compress) `
            -SkipHeaderValidation
    }
    catch {
        $status = 0
        try { $status = [int]$_.Exception.Response.StatusCode } catch { }
        throw "yeshinvoice API request to '$Uri' failed (HTTP $status). Details withheld to protect credentials."
    }
    if ($response.Success -ne $true) {
        throw "yeshinvoice API reported failure for '$Uri': $($response.ErrorMessage)"
    }
    return $response
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester .\tests\Invoke-YeshApi.Tests.ps1 -Output Detailed`
Expected: 6 tests PASS.

- [ ] **Step 5: Commit**

```powershell
git add src/YeshHeshbonit/Private/Invoke-YeshApi.ps1 tests/Invoke-YeshApi.Tests.ps1
git commit -m "feat: fail-closed API client with pagination and sanitized errors"
```

---

### Task 5: Get-YeshInvoice (Public)

**Files:**
- Create: `src/YeshHeshbonit/Public/Get-YeshInvoice.ps1`
- Test: `tests/Get-YeshInvoice.Tests.ps1`

**Interfaces:**
- Consumes: `Invoke-YeshApi -Endpoint 'api/v1/getInvoices' -Body <hashtable> -Config <pscustomobject> -Paginate` (Task 4), `Get-YeshConfig` (Task 2)
- Produces: `Get-YeshInvoice -From <datetime> -To <datetime> [-Config <pscustomobject>]` → `object[]` of raw API documents filtered to revenue + credit types, cancelled excluded, warning on unknown `StatusID`

- [ ] **Step 1: Write the failing tests**

`tests/Get-YeshInvoice.Tests.ps1`:

```powershell
BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Invoke-YeshApi.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Public\Get-YeshInvoice.ps1')

    $script:config = [pscustomobject]@{
        Secret = 's'; UserKey = 'u'
        Rates  = [pscustomobject]@{
            revenueDocTypes = @(8, 9); creditDocTypes = @(10); cancelledStatusIds = @(2)
        }
    }

    function New-ApiDoc {
        param($Type, $Status = 1, $Number = '1001')
        [pscustomobject]@{
            DocumentType = $Type; StatusID = $Status; DocumentNumber = $Number
            TotalPrice = 100; vattype = ''; Date = '01-06-2026'; CustomerName = 'A'
        }
    }
}

Describe 'Get-YeshInvoice' {
    It 'keeps revenue and credit types, drops receipts and quotes' {
        Mock Invoke-YeshApi {
            @((New-ApiDoc 8), (New-ApiDoc 9), (New-ApiDoc 10), (New-ApiDoc 6), (New-ApiDoc 1))
        }
        $docs = Get-YeshInvoice -From '2026-06-01' -To '2026-06-30' -Config $config
        $docs.Count | Should -Be 3
        $docs.DocumentType | Should -Be @(8, 9, 10)
    }

    It 'excludes cancelled documents' {
        Mock Invoke-YeshApi { @((New-ApiDoc 8 -Status 1), (New-ApiDoc 8 -Status 2 -Number '1002')) }
        $docs = Get-YeshInvoice -From '2026-06-01' -To '2026-06-30' -Config $config
        $docs.Count | Should -Be 1
        $docs[0].DocumentNumber | Should -Be '1001'
    }

    It 'warns on an unrecognized StatusID but includes the document' {
        Mock Invoke-YeshApi { @(New-ApiDoc 8 -Status 7) }
        $warnings = @()
        $docs = Get-YeshInvoice -From '2026-06-01' -To '2026-06-30' -Config $config -WarningVariable warnings -WarningAction SilentlyContinue
        $docs.Count | Should -Be 1
        $warnings.Count | Should -Be 1
        "$($warnings[0])" | Should -Match 'StatusID 7'
    }

    It 'rejects a range where To is before From' {
        { Get-YeshInvoice -From '2026-06-30' -To '2026-06-01' -Config $config } |
            Should -Throw '*earlier than*'
    }

    It 'requests the API with the documented date format and pagination' {
        Mock Invoke-YeshApi { @() } -ParameterFilter {
            $Endpoint -eq 'api/v1/getInvoices' -and
            $Body.from -eq '2026-06-01 00:00' -and
            $Body.to -eq '2026-06-30 23:59' -and
            $Body.PageSize -eq 100 -and
            $Paginate -eq $true
        }
        Get-YeshInvoice -From '2026-06-01 00:00' -To '2026-06-30 23:59' -Config $config | Out-Null
        Should -Invoke Invoke-YeshApi -Times 1 -Exactly
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester .\tests\Get-YeshInvoice.Tests.ps1 -Output Detailed`
Expected: FAIL — dot-source error, `Get-YeshInvoice.ps1` does not exist.

- [ ] **Step 3: Write the implementation**

`src/YeshHeshbonit/Public/Get-YeshInvoice.ps1`:

```powershell
function Get-YeshInvoice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][datetime]$From,
        [Parameter(Mandatory)][datetime]$To,
        [pscustomobject]$Config
    )

    if ($To -lt $From) {
        throw "Invalid range: -To ($($To.ToString('yyyy-MM-dd'))) is earlier than -From ($($From.ToString('yyyy-MM-dd')))."
    }
    if (-not $Config) { $Config = Get-YeshConfig }

    $body = @{
        from     = $From.ToString('yyyy-MM-dd HH:mm')
        to       = $To.ToString('yyyy-MM-dd HH:mm')
        PageSize = 100
        Search   = ''
    }
    $docs = Invoke-YeshApi -Endpoint 'api/v1/getInvoices' -Body $body -Config $Config -Paginate

    $wantedTypes = @($Config.Rates.revenueDocTypes) + @($Config.Rates.creditDocTypes)
    $cancelled = @($Config.Rates.cancelledStatusIds)

    @(foreach ($doc in $docs) {
        if ($wantedTypes -notcontains [int]$doc.DocumentType) { continue }
        if ($cancelled -contains [int]$doc.StatusID) { continue }
        if ([int]$doc.StatusID -ne 1) {
            Write-Warning "Document $($doc.DocumentNumber) has unrecognized StatusID $($doc.StatusID) - included in totals. Verify it is not cancelled, then add the ID to cancelledStatusIds in rates.json if it is."
        }
        $doc
    })
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester .\tests\Get-YeshInvoice.Tests.ps1 -Output Detailed`
Expected: 5 tests PASS.

- [ ] **Step 5: Commit**

```powershell
git add src/YeshHeshbonit/Public/Get-YeshInvoice.ps1 tests/Get-YeshInvoice.Tests.ps1
git commit -m "feat: invoice fetch with document-type and status filtering"
```

---

### Task 6: Export-TaxSummary (Public)

**Files:**
- Create: `src/YeshHeshbonit/Public/Export-TaxSummary.ps1`
- Test: `tests/Export-TaxSummary.Tests.ps1`

**Interfaces:**
- Consumes: summary object from `ConvertTo-TaxCalculation` (`.Invoices`, `.Totals` — Task 3 shapes)
- Produces: `Export-TaxSummary -Summary <pscustomobject> -Path <string>` → writes UTF-8-with-BOM CSV, returns `[System.IO.FileInfo]` of the written file. Columns: `Type, Date, DocumentNumber, Customer, Gross, Net, Vat, Amount`. One `Invoice` row per invoice, then `Total`, `SetAside-VAT`, `SetAside-Mikdamot`, `SetAside-BituachLeumi-Estimate` rows with the figure in `Amount`.

- [ ] **Step 1: Write the failing tests**

`tests/Export-TaxSummary.Tests.ps1`:

```powershell
BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Public\Export-TaxSummary.ps1')

    $script:summary = [pscustomobject]@{
        Invoices = @(
            [pscustomobject]@{ Date = '01-06-2026'; DocumentNumber = '1001'; DocumentType = 8
                               Customer = 'לקוח א'; Gross = 1180.0; Net = 1000.0; Vat = 180.0 }
        )
        Totals = [pscustomobject]@{
            Gross = 1180.0; Net = 1000.0; Vat = 180.0
            Mikdamot = 50.0; BituachLeumiEstimate = 59.7; MonthsInPeriod = 1
        }
    }
}

Describe 'Export-TaxSummary' {
    It 'writes invoice rows plus total and set-aside rows' {
        $path = Join-Path $TestDrive 'out.csv'
        Export-TaxSummary -Summary $summary -Path $path | Out-Null
        $rows = Import-Csv $path
        $rows.Count | Should -Be 5
        $rows[0].Type | Should -Be 'Invoice'
        $rows[0].Net | Should -Be '1000'
        ($rows | Where-Object Type -eq 'SetAside-Mikdamot').Amount | Should -Be '50'
        ($rows | Where-Object Type -eq 'SetAside-BituachLeumi-Estimate').Amount | Should -Be '59.7'
    }

    It 'writes UTF-8 with BOM so Hebrew opens correctly in Excel' {
        $path = Join-Path $TestDrive 'bom.csv'
        Export-TaxSummary -Summary $summary -Path $path | Out-Null
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
    }

    It 'returns the written file' {
        $path = Join-Path $TestDrive 'ret.csv'
        $file = Export-TaxSummary -Summary $summary -Path $path
        $file | Should -BeOfType System.IO.FileInfo
        $file.FullName | Should -Be (Get-Item $path).FullName
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester .\tests\Export-TaxSummary.Tests.ps1 -Output Detailed`
Expected: FAIL — dot-source error, file does not exist.

- [ ] **Step 3: Write the implementation**

`src/YeshHeshbonit/Public/Export-TaxSummary.ps1`:

```powershell
function Export-TaxSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Summary,
        [Parameter(Mandatory)][string]$Path
    )

    function New-Row {
        param($Type, $Date = '', $DocumentNumber = '', $Customer = '', $Gross = '', $Net = '', $Vat = '', $Amount = '')
        [pscustomobject]@{
            Type = $Type; Date = $Date; DocumentNumber = $DocumentNumber; Customer = $Customer
            Gross = $Gross; Net = $Net; Vat = $Vat; Amount = $Amount
        }
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($inv in @($Summary.Invoices)) {
        $rows.Add((New-Row -Type 'Invoice' -Date $inv.Date -DocumentNumber $inv.DocumentNumber `
            -Customer $inv.Customer -Gross ([math]::Round($inv.Gross, 2)) `
            -Net ([math]::Round($inv.Net, 2)) -Vat ([math]::Round($inv.Vat, 2))))
    }
    $t = $Summary.Totals
    $rows.Add((New-Row -Type 'Total' -Gross $t.Gross -Net $t.Net -Vat $t.Vat))
    $rows.Add((New-Row -Type 'SetAside-VAT' -Amount $t.Vat))
    $rows.Add((New-Row -Type 'SetAside-Mikdamot' -Amount $t.Mikdamot))
    $rows.Add((New-Row -Type 'SetAside-BituachLeumi-Estimate' -Amount $t.BituachLeumiEstimate))

    $rows | Export-Csv -Path $Path -Encoding utf8BOM -NoTypeInformation
    Get-Item $Path
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester .\tests\Export-TaxSummary.Tests.ps1 -Output Detailed`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```powershell
git add src/YeshHeshbonit/Public/Export-TaxSummary.ps1 tests/Export-TaxSummary.Tests.ps1
git commit -m "feat: CSV export with UTF-8 BOM for Hebrew Excel compatibility"
```

---

### Task 7: Get-TaxSummary (Public, main command)

**Files:**
- Create: `src/YeshHeshbonit/Public/Get-TaxSummary.ps1`
- Test: `tests/Get-TaxSummary.Tests.ps1`

**Interfaces:**
- Consumes: `Get-YeshConfig` (Task 2), `Get-YeshInvoice -From -To -Config` (Task 5), `ConvertTo-TaxCalculation -Documents -Rates -MonthsInPeriod` (Task 3), `Export-TaxSummary -Summary -Path` (Task 6)
- Produces: `Get-TaxSummary [-Month <yyyy-MM>] | [-From <datetime> -To <datetime>] [-ExportCsv <path>] [-PassThru]` — prints per-invoice table + totals to host; with `-PassThru` returns the `ConvertTo-TaxCalculation` result object

- [ ] **Step 1: Write the failing tests**

`tests/Get-TaxSummary.Tests.ps1`:

```powershell
BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Get-YeshConfig.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\ConvertTo-TaxCalculation.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Invoke-YeshApi.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Public\Get-YeshInvoice.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Public\Export-TaxSummary.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Public\Get-TaxSummary.ps1')

    $script:fakeConfig = [pscustomobject]@{
        Secret = 's'; UserKey = 'u'
        Rates  = [pscustomobject]@{
            vatRate      = 0.18
            mikdamotRate = 0.05
            bituachLeumi = [pscustomobject]@{
                averageWageMonthly = 13769; reducedRateThreshold = 0.60
                reducedRate = 0.0597; fullRate = 0.1783
            }
            revenueDocTypes = @(8, 9); creditDocTypes = @(10); cancelledStatusIds = @()
        }
    }

    function New-ApiDoc {
        param($Price = 1180, $Number = '1001')
        [pscustomobject]@{
            DocumentType = 8; StatusID = 1; DocumentNumber = $Number
            TotalPrice = $Price; vattype = ''; Date = '05-06-2026'; CustomerName = 'A'
        }
    }
}

Describe 'Get-TaxSummary' {
    BeforeEach {
        Mock Get-YeshConfig { $fakeConfig }
        Mock Write-Host { }
    }

    It 'converts -Month into a full-month range' {
        Mock Get-YeshInvoice { @(New-ApiDoc) } -ParameterFilter {
            $From -eq [datetime]'2026-06-01 00:00' -and
            $To -eq [datetime]'2026-06-30 23:59'
        }
        Get-TaxSummary -Month 2026-06 | Out-Null
        Should -Invoke Get-YeshInvoice -Times 1 -Exactly
    }

    It 'rejects a malformed -Month' {
        { Get-TaxSummary -Month '2026-13' } | Should -Throw
        { Get-TaxSummary -Month 'June' } | Should -Throw
    }

    It 'rejects -From after -To' {
        { Get-TaxSummary -From '2026-06-30' -To '2026-06-01' } | Should -Throw '*earlier than*'
    }

    It 'returns totals with -PassThru' {
        Mock Get-YeshInvoice { @(New-ApiDoc -Price 29500) }
        $result = Get-TaxSummary -Month 2026-06 -PassThru
        $result.Totals.Net | Should -Be 25000
        $result.Totals.Vat | Should -Be 4500
        $result.Totals.Mikdamot | Should -Be 1250
    }

    It 'passes the month count of a bi-monthly range to the calculator' {
        Mock Get-YeshInvoice { @(New-ApiDoc -Price 29500) }
        $result = Get-TaxSummary -From '2026-05-01' -To '2026-06-30' -PassThru
        $result.Totals.MonthsInPeriod | Should -Be 2
    }

    It 'handles an empty period without error' {
        Mock Get-YeshInvoice { @() }
        $result = Get-TaxSummary -Month 2026-06 -PassThru
        $result.Totals.Net | Should -Be 0
    }

    It 'exports when -ExportCsv is given' {
        Mock Get-YeshInvoice { @(New-ApiDoc) }
        $path = Join-Path $TestDrive 'summary.csv'
        Get-TaxSummary -Month 2026-06 -ExportCsv $path | Out-Null
        Test-Path $path | Should -BeTrue
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester .\tests\Get-TaxSummary.Tests.ps1 -Output Detailed`
Expected: FAIL — dot-source error, `Get-TaxSummary.ps1` does not exist.

- [ ] **Step 3: Write the implementation**

`src/YeshHeshbonit/Public/Get-TaxSummary.ps1`:

```powershell
function Get-TaxSummary {
    [CmdletBinding(DefaultParameterSetName = 'Month')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Month')]
        [ValidatePattern('^\d{4}-(0[1-9]|1[0-2])$')]
        [string]$Month,

        [Parameter(Mandatory, ParameterSetName = 'Range')][datetime]$From,
        [Parameter(Mandatory, ParameterSetName = 'Range')][datetime]$To,

        [string]$ExportCsv,
        [switch]$PassThru
    )

    if ($PSCmdlet.ParameterSetName -eq 'Month') {
        $From = [datetime]::ParseExact("$Month-01", 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
        $To = $From.AddMonths(1).AddMinutes(-1)
    }
    if ($To -lt $From) {
        throw "Invalid range: -To ($($To.ToString('yyyy-MM-dd'))) is earlier than -From ($($From.ToString('yyyy-MM-dd')))."
    }
    $months = (($To.Year - $From.Year) * 12) + $To.Month - $From.Month + 1

    $config = Get-YeshConfig
    $docs = Get-YeshInvoice -From $From -To $To -Config $config
    $summary = ConvertTo-TaxCalculation -Documents $docs -Rates $config.Rates -MonthsInPeriod $months

    if (@($summary.Invoices).Count -gt 0) {
        $table = $summary.Invoices | Select-Object Date, DocumentNumber, Customer,
            @{ n = 'Gross'; e = { [math]::Round($_.Gross, 2) } },
            @{ n = 'Net'; e = { [math]::Round($_.Net, 2) } },
            @{ n = 'Vat'; e = { [math]::Round($_.Vat, 2) } } |
            Format-Table -AutoSize | Out-String
        Write-Host $table
    }
    else {
        Write-Host 'No revenue documents found in the period.'
    }

    $t = $summary.Totals
    Write-Host ("Period: {0:yyyy-MM-dd} to {1:yyyy-MM-dd} ({2} month(s))" -f $From, $To, $months)
    Write-Host ("  Gross revenue:                 {0,12:N2}" -f $t.Gross)
    Write-Host ("  Net (pre-VAT):                 {0,12:N2}" -f $t.Net)
    Write-Host ("  Set aside - VAT:               {0,12:N2}" -f $t.Vat)
    Write-Host ("  Set aside - Mikdamot:          {0,12:N2}" -f $t.Mikdamot)
    Write-Host ("  Set aside - Bituach Leumi:     {0,12:N2}  (ESTIMATE)" -f $t.BituachLeumiEstimate)
    Write-Host '  NOTE: Bituach Leumi advances are officially based on your projected annual'
    Write-Host '  income assessment; this figure is a set-aside estimate, not your actual mikdama.'

    if ($ExportCsv) {
        Export-TaxSummary -Summary $summary -Path $ExportCsv | Out-Null
        Write-Host "Exported to $ExportCsv"
    }
    if ($PassThru) { return $summary }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester .\tests\Get-TaxSummary.Tests.ps1 -Output Detailed`
Expected: 7 tests PASS.

- [ ] **Step 5: Run the full suite**

Run: `Invoke-Pester .\tests -Output Detailed`
Expected: ALL tests PASS (Module 3, Config 8, Calculation 12, Api 6, Invoice 5, Export 3, Summary 7 = 44).

- [ ] **Step 6: Commit**

```powershell
git add src/YeshHeshbonit/Public/Get-TaxSummary.ps1 tests/Get-TaxSummary.Tests.ps1
git commit -m "feat: Get-TaxSummary main command with month/range parameter sets"
```

---

### Task 8: Live smoke test + README finalization

**Files:**
- Modify: `README.md` (Status section)
- No new source files

**Interfaces:**
- Consumes: the complete module, Eitan's real `.env`
- Produces: verified end-to-end run against the live API; README reflecting reality

- [ ] **Step 1: Import and run against the live API**

```powershell
Import-Module .\src\YeshHeshbonit\YeshHeshbonit.psd1 -Force
Get-TaxSummary -Month 2026-06
```

Expected: table of June 2026 invoices (types 8/9 only — receipts excluded) and a totals block with VAT / mikdamot / Bituach Leumi figures. No errors, no credential text anywhere in output.

- [ ] **Step 2: Sanity-check one invoice by hand**

Pick one displayed invoice; verify `Net = Gross / 1.18` and `Vat = Gross − Net` against the actual PDF in yeshinvoice. If `vattype` was empty and the numbers are wrong, the empty-value assumption (empty = כולל מע"מ) is falsified — stop and re-check `getbyid` for that document before proceeding.

- [ ] **Step 3: Test the CSV export end-to-end**

```powershell
Get-TaxSummary -Month 2026-06 -ExportCsv .\june-2026.csv
Invoke-Item .\june-2026.csv
```

Expected: opens in Excel with Hebrew customer names rendered correctly. Delete the file afterward (`Remove-Item .\june-2026.csv` — it is gitignored anyway via `*.csv`).

- [ ] **Step 4: Update README status**

Replace the Status section of `README.md` with:

```markdown
## Status

Working. Run `Invoke-Pester .\tests` to verify (44 tests).

Remember to set `mikdamotRate` in `config/rates.json` to your actual rate from the
מס הכנסה assessment letter — the committed value is a placeholder default.
```

- [ ] **Step 5: Final commit**

```powershell
git add README.md
git commit -m "docs: mark module working after live smoke test"
```

---

## Self-Review Notes

- **Spec coverage:** module structure (T1), config + validation (T2), calculation incl. vattype semantics, credit negatives, rounding, BL tiers (T3), fail-closed HTTP + pagination + credential sanitization (T4), doc-type/status filtering incl. receipt exclusion (T5), UTF-8-BOM CSV (T6), parameter sets + display + disclaimer (T7), live verification of the empty-vattype assumption (T8). Out-of-scope items (expenses, history, reminders) have no tasks — correct per spec.
- **Type consistency:** `Get-YeshConfig` → `{Secret, UserKey, Rates}` consumed by T4/T5/T7 under those names; `ConvertTo-TaxCalculation` output `{Invoices[], Totals{Gross,Net,Vat,Mikdamot,BituachLeumiEstimate,MonthsInPeriod}}` consumed by T6/T7 under those names; `Invoke-YeshApi -Paginate` returns a flat array consumed by T5.
- **Placeholder scan:** every code step contains complete code; every run step has an exact command and expected outcome.
