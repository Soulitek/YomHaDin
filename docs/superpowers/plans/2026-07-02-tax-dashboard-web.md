# Tax Dashboard Web UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Local Hebrew RTL web dashboard (Pode) over the existing YeshHeshbonit module: period picker, three set-aside cards, invoice table, CSV download.

**Architecture:** Thin web adapter — no tax logic in the web layer. One behavior-preserving refactor extracts `Get-TaxSummary`'s orchestration into a shared private `Get-TaxPeriodSummary`. Two exported handler functions return `{StatusCode, Body/Bytes}` shapes so route script blocks stay trivial and all logic is unit-testable without a running server. Frontend is one static page, vanilla JS, no build step. Spec: `docs/superpowers/specs/2026-07-02-tax-dashboard-web-design.md`.

**Tech Stack:** PowerShell 7+, Pode (PSGallery), Pester 5, vanilla HTML/CSS/JS.

## Global Constraints

- PowerShell 7.0+; Pester 5; Pode is the ONLY new dependency
- Server binds **127.0.0.1 only**; no auth (deliberate: localhost, single user)
- Fail closed: invalid query params → 400 `{error}`; yeshinvoice API failure → 502 `{error}` (sanitized message from the module); anything else → 500 `{error: "Internal error"}` — no stack traces, no paths, never credentials
- No logging (project standard); disable/skip Pode request logging (Pode logs nothing unless enabled — do not enable)
- All money math stays in `ConvertTo-TaxCalculation`; rounding for JSON display uses `[math]::Round(x, 2, [System.MidpointRounding]::AwayFromZero)` (same as the rest of the project)
- Frontend: `dir="rtl" lang="he"`, system font stack, no CDN/external resources, all dynamic DOM insertion via `textContent`/`createElement` — NEVER `innerHTML`
- Existing 50 tests must stay green after the refactor; existing test assertions must not be weakened
- Pode runspace rule: route script blocks run in separate runspaces and can only call functions EXPORTED by modules imported via `Import-PodeModule` — this is why `Get-DashboardSummaryResponse`/`Get-DashboardCsvResponse` are Public while `Get-TaxPeriodSummary`/`Resolve-DashboardPeriodParam` stay Private (Public module functions run in module scope and can call Private ones)
- Tests never call the live API and never start a real Pode server
- Commit after every task with the trailer: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: Extract Get-TaxPeriodSummary (behavior-preserving refactor)

**Files:**
- Create: `src/YeshHeshbonit/Private/Get-TaxPeriodSummary.ps1`
- Modify: `src/YeshHeshbonit/Public/Get-TaxSummary.ps1` (full replacement below)
- Modify: `tests/Get-TaxSummary.Tests.ps1` (add ONE dot-source line to BeforeAll)
- Test: `tests/Get-TaxPeriodSummary.Tests.ps1`

**Interfaces:**
- Consumes: `Get-YeshConfig` → `{Secret, UserKey, Rates}`; `Get-YeshInvoice -From <datetime> -To <datetime> -Config <obj>`; `ConvertTo-TaxCalculation -Documents <object[]> -Rates <obj> -MonthsInPeriod <int>` → `{Invoices[], Totals{Gross,Net,Vat,Mikdamot,BituachLeumiEstimate,MonthsInPeriod}}`
- Produces: `Get-TaxPeriodSummary [-Month <yyyy-MM>] | [-From <datetime> -To <datetime>]` → `[pscustomobject] {From <datetime>, To <datetime>, Months <int>, Invoices <object[]>, Totals <pscustomobject>}`. Later tasks (3) call it with exactly these names.

- [ ] **Step 1: Write the failing tests**

`tests/Get-TaxPeriodSummary.Tests.ps1`:

```powershell
BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Get-YeshConfig.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\ConvertTo-TaxCalculation.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Invoke-YeshApi.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Public\Get-YeshInvoice.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Get-TaxPeriodSummary.ps1')

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

Describe 'Get-TaxPeriodSummary' {
    BeforeEach {
        Mock Get-YeshConfig { $fakeConfig }
    }

    It 'expands -Month to a full-month range' {
        Mock Get-YeshInvoice { @(New-ApiDoc) }
        $r = Get-TaxPeriodSummary -Month 2026-06
        $r.From | Should -Be ([datetime]'2026-06-01 00:00')
        $r.To | Should -Be ([datetime]'2026-06-30 23:59')
        $r.Months | Should -Be 1
    }

    It 'normalizes a date-only -To to end of day' {
        Mock Get-YeshInvoice { @() }
        $r = Get-TaxPeriodSummary -From '2026-05-01' -To '2026-06-30'
        $r.To | Should -Be ([datetime]'2026-06-30 23:59')
        $r.Months | Should -Be 2
    }

    It 'preserves an explicit -To time' {
        Mock Get-YeshInvoice { @() }
        $r = Get-TaxPeriodSummary -From '2026-05-01' -To '2026-06-30 12:30'
        $r.To | Should -Be ([datetime]'2026-06-30 12:30')
    }

    It 'rejects -From after -To' {
        { Get-TaxPeriodSummary -From '2026-06-30' -To '2026-06-01' } | Should -Throw '*earlier than*'
    }

    It 'rejects a malformed -Month' {
        { Get-TaxPeriodSummary -Month '2026-13' } | Should -Throw
    }

    It 'returns Invoices and Totals from the calculation' {
        Mock Get-YeshInvoice { @(New-ApiDoc -Price 29500) }
        $r = Get-TaxPeriodSummary -Month 2026-06
        $r.Totals.Net | Should -Be 25000
        $r.Totals.Vat | Should -Be 4500
        @($r.Invoices).Count | Should -Be 1
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester .\tests\Get-TaxPeriodSummary.Tests.ps1 -Output Detailed`
Expected: FAIL — dot-source error, `Get-TaxPeriodSummary.ps1` does not exist.

- [ ] **Step 3: Write the implementation**

`src/YeshHeshbonit/Private/Get-TaxPeriodSummary.ps1`:

```powershell
function Get-TaxPeriodSummary {
    [CmdletBinding(DefaultParameterSetName = 'Month')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Month')]
        [ValidatePattern('^\d{4}-(0[1-9]|1[0-2])$')]
        [string]$Month,

        [Parameter(Mandatory, ParameterSetName = 'Range')][datetime]$From,
        [Parameter(Mandatory, ParameterSetName = 'Range')][datetime]$To
    )

    if ($PSCmdlet.ParameterSetName -eq 'Month') {
        $From = [datetime]::ParseExact("$Month-01", 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
        $To = $From.AddMonths(1).AddMinutes(-1)
    }
    if ($PSCmdlet.ParameterSetName -eq 'Range' -and $To.TimeOfDay -eq [timespan]::Zero) {
        # A date-only -To means "through the end of that day"
        $To = $To.Date.AddDays(1).AddMinutes(-1)
    }
    if ($To -lt $From) {
        throw "Invalid range: -To ($($To.ToString('yyyy-MM-dd'))) is earlier than -From ($($From.ToString('yyyy-MM-dd')))."
    }
    $months = (($To.Year - $From.Year) * 12) + $To.Month - $From.Month + 1

    $config = Get-YeshConfig
    $docs = @(Get-YeshInvoice -From $From -To $To -Config $config)
    $calc = ConvertTo-TaxCalculation -Documents $docs -Rates $config.Rates -MonthsInPeriod $months

    [pscustomobject]@{
        From     = $From
        To       = $To
        Months   = $months
        Invoices = $calc.Invoices
        Totals   = $calc.Totals
    }
}
```

Replace `src/YeshHeshbonit/Public/Get-TaxSummary.ps1` in full with:

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

    $data = if ($PSCmdlet.ParameterSetName -eq 'Month') {
        Get-TaxPeriodSummary -Month $Month
    }
    else {
        Get-TaxPeriodSummary -From $From -To $To
    }
    $summary = [pscustomobject]@{ Invoices = $data.Invoices; Totals = $data.Totals }

    if (@($summary.Invoices).Count -gt 0) {
        $table = $summary.Invoices | Select-Object Date, DocumentNumber, Customer,
            @{ n = 'Gross'; e = { [math]::Round($_.Gross, 2, [System.MidpointRounding]::AwayFromZero) } },
            @{ n = 'Net'; e = { [math]::Round($_.Net, 2, [System.MidpointRounding]::AwayFromZero) } },
            @{ n = 'Vat'; e = { [math]::Round($_.Vat, 2, [System.MidpointRounding]::AwayFromZero) } } |
            Format-Table -AutoSize | Out-String
        Write-Host $table
    }
    else {
        Write-Host 'No revenue documents found in the period.'
    }

    $t = $summary.Totals
    Write-Host ("Period: {0:yyyy-MM-dd} to {1:yyyy-MM-dd} ({2} month(s))" -f $data.From, $data.To, $data.Months)
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

(Behavior note: the per-invoice display previously used plain `[math]::Round(x,2)`; using AwayFromZero here aligns display with the Totals policy — the existing display tests assert values that are identical under both modes, so this does not break them.)

In `tests/Get-TaxSummary.Tests.ps1`, add this line to the `BeforeAll` dot-source block (after the ConvertTo-TaxCalculation line):

```powershell
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Get-TaxPeriodSummary.ps1')
```

Do not change anything else in that file — its mocks of `Get-YeshConfig`/`Get-YeshInvoice` intercept the calls now made inside `Get-TaxPeriodSummary` because everything is dot-sourced into one scope.

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester .\tests\Get-TaxPeriodSummary.Tests.ps1 -Output Detailed` → 6 PASS.
Run: `Invoke-Pester .\tests -Output Detailed` → all 56 PASS (50 existing + 6 new). The existing Get-TaxSummary tests passing unchanged is the proof the refactor preserved behavior.

- [ ] **Step 5: Commit**

```powershell
git add src/YeshHeshbonit/Private/Get-TaxPeriodSummary.ps1 src/YeshHeshbonit/Public/Get-TaxSummary.ps1 tests/Get-TaxPeriodSummary.Tests.ps1 tests/Get-TaxSummary.Tests.ps1
git commit -m "refactor: extract Get-TaxPeriodSummary shared orchestration"
```

---

### Task 2: Resolve-DashboardPeriodParam (Private)

**Files:**
- Create: `src/YeshHeshbonit/Private/Resolve-DashboardPeriodParam.ps1`
- Test: `tests/Resolve-DashboardPeriodParam.Tests.ps1`

**Interfaces:**
- Consumes: nothing (pure function)
- Produces: `Resolve-DashboardPeriodParam -Query <hashtable>` → hashtable splat for `Get-TaxPeriodSummary`: either `@{Month='yyyy-MM'}` or `@{From=<datetime>; To=<datetime>}`. Throws on invalid/missing/contradictory params. Task 3 splats the result directly.

- [ ] **Step 1: Write the failing tests**

`tests/Resolve-DashboardPeriodParam.Tests.ps1`:

```powershell
BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Resolve-DashboardPeriodParam.ps1')
}

Describe 'Resolve-DashboardPeriodParam' {
    It 'returns a Month splat for a valid month param' {
        $r = Resolve-DashboardPeriodParam -Query @{ month = '2026-06' }
        $r.Month | Should -Be '2026-06'
        $r.Keys.Count | Should -Be 1
    }

    It 'returns a From/To splat for valid from+to params' {
        $r = Resolve-DashboardPeriodParam -Query @{ from = '2026-05-01'; to = '2026-06-30' }
        $r.From | Should -Be ([datetime]'2026-05-01')
        $r.To | Should -Be ([datetime]'2026-06-30')
    }

    It 'rejects month combined with from/to' {
        { Resolve-DashboardPeriodParam -Query @{ month = '2026-06'; from = '2026-05-01' } } |
            Should -Throw '*not both*'
    }

    It 'rejects an empty query' {
        { Resolve-DashboardPeriodParam -Query @{} } | Should -Throw '*Missing period*'
    }

    It 'rejects from without to' {
        { Resolve-DashboardPeriodParam -Query @{ from = '2026-05-01' } } | Should -Throw '*Missing period*'
    }

    It 'rejects a malformed month' {
        { Resolve-DashboardPeriodParam -Query @{ month = '2026-13' } } | Should -Throw "*Invalid 'month'*"
        { Resolve-DashboardPeriodParam -Query @{ month = 'June' } } | Should -Throw "*Invalid 'month'*"
    }

    It 'rejects malformed dates' {
        { Resolve-DashboardPeriodParam -Query @{ from = '01/05/2026'; to = '2026-06-30' } } |
            Should -Throw "*Invalid 'from'*"
        { Resolve-DashboardPeriodParam -Query @{ from = '2026-05-01'; to = 'soon' } } |
            Should -Throw "*Invalid 'to'*"
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester .\tests\Resolve-DashboardPeriodParam.Tests.ps1 -Output Detailed`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Write the implementation**

`src/YeshHeshbonit/Private/Resolve-DashboardPeriodParam.ps1`:

```powershell
function Resolve-DashboardPeriodParam {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Query
    )

    $month = "$($Query['month'])"
    $from = "$($Query['from'])"
    $to = "$($Query['to'])"

    if ($month -and ($from -or $to)) {
        throw "Specify either 'month' or 'from'+'to', not both."
    }
    if ($month) {
        if ($month -notmatch '^\d{4}-(0[1-9]|1[0-2])$') {
            throw "Invalid 'month' format '$month'. Expected yyyy-MM."
        }
        return @{ Month = $month }
    }
    if ($from -and $to) {
        $f = [datetime]::MinValue
        $t = [datetime]::MinValue
        $styles = [System.Globalization.DateTimeStyles]::None
        $culture = [cultureinfo]::InvariantCulture
        if (-not [datetime]::TryParseExact($from, 'yyyy-MM-dd', $culture, $styles, [ref]$f)) {
            throw "Invalid 'from' date '$from'. Expected yyyy-MM-dd."
        }
        if (-not [datetime]::TryParseExact($to, 'yyyy-MM-dd', $culture, $styles, [ref]$t)) {
            throw "Invalid 'to' date '$to'. Expected yyyy-MM-dd."
        }
        return @{ From = $f; To = $t }
    }
    throw "Missing period: provide 'month' or 'from'+'to'."
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester .\tests\Resolve-DashboardPeriodParam.Tests.ps1 -Output Detailed` → 7 PASS (some Its have two assertions).
Then full suite: `Invoke-Pester .\tests` → all PASS.

- [ ] **Step 5: Commit**

```powershell
git add src/YeshHeshbonit/Private/Resolve-DashboardPeriodParam.ps1 tests/Resolve-DashboardPeriodParam.Tests.ps1
git commit -m "feat: dashboard query-param validation (fail closed)"
```

---

### Task 3: Dashboard response handlers (Public) + manifest update

**Files:**
- Create: `src/YeshHeshbonit/Public/Get-DashboardSummaryResponse.ps1`
- Create: `src/YeshHeshbonit/Public/Get-DashboardCsvResponse.ps1`
- Modify: `src/YeshHeshbonit/YeshHeshbonit.psd1` (FunctionsToExport)
- Modify: `tests/Module.Tests.ps1` (export-list assertion)
- Test: `tests/DashboardHandlers.Tests.ps1`

**Interfaces:**
- Consumes: `Resolve-DashboardPeriodParam -Query <hashtable>` (Task 2), `Get-TaxPeriodSummary` (Task 1), `Export-TaxSummary -Summary <obj> -Path <string>` (existing)
- Produces (Task 5 routes call exactly these):
  - `Get-DashboardSummaryResponse -Query <hashtable>` → `@{StatusCode=<int>; Body=<hashtable>}` — 200 Body is `{period{from,to,months}, invoices[], totals{gross,net,vat,mikdamot,bituachLeumiEstimate,months}}`; 400/502 Body is `{error=<string>}`
  - `Get-DashboardCsvResponse -Query <hashtable>` → 200: `@{StatusCode=200; Bytes=<byte[]>; FileName=<string 'tax-summary-yyyy-MM-dd_yyyy-MM-dd.csv'>}`; error: `@{StatusCode=400|502; Error=<string>}`

These are Public ONLY because Pode route runspaces can call exported functions exclusively (see Global Constraints). They are not part of the user-facing CLI story.

- [ ] **Step 1: Write the failing tests**

`tests/DashboardHandlers.Tests.ps1`:

```powershell
BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Resolve-DashboardPeriodParam.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Get-TaxPeriodSummary.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Public\Export-TaxSummary.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Public\Get-DashboardSummaryResponse.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Public\Get-DashboardCsvResponse.ps1')

    $script:fakeData = [pscustomobject]@{
        From   = [datetime]'2026-06-01'
        To     = [datetime]'2026-06-30 23:59'
        Months = 1
        Invoices = @(
            [pscustomobject]@{ Date = '05-06-2026'; DocumentNumber = '1001'; DocumentType = 8
                               Customer = 'לקוח א'; Gross = 1180.0; Net = 1000.0; Vat = 180.0 }
        )
        Totals = [pscustomobject]@{
            Gross = 1180.0; Net = 1000.0; Vat = 180.0
            Mikdamot = 50.0; BituachLeumiEstimate = 59.7; MonthsInPeriod = 1
        }
    }
}

Describe 'Get-DashboardSummaryResponse' {
    It 'returns 400 with an error body for an empty query' {
        $r = Get-DashboardSummaryResponse -Query @{}
        $r.StatusCode | Should -Be 400
        $r.Body.error | Should -Match 'Missing period'
    }

    It 'returns 400 for a malformed month' {
        $r = Get-DashboardSummaryResponse -Query @{ month = 'June' }
        $r.StatusCode | Should -Be 400
        $r.Body.error | Should -Match "Invalid 'month'"
    }

    It 'returns 502 with the sanitized message when the API layer fails' {
        Mock Get-TaxPeriodSummary { throw 'yeshinvoice API request failed (HTTP 500). Details withheld to protect credentials.' }
        $r = Get-DashboardSummaryResponse -Query @{ month = '2026-06' }
        $r.StatusCode | Should -Be 502
        $r.Body.error | Should -Match 'withheld'
    }

    It 'returns 200 with the shaped body on success' {
        Mock Get-TaxPeriodSummary { $fakeData }
        $r = Get-DashboardSummaryResponse -Query @{ month = '2026-06' }
        $r.StatusCode | Should -Be 200
        $r.Body.period.from | Should -Be '2026-06-01'
        $r.Body.period.to | Should -Be '2026-06-30'
        $r.Body.period.months | Should -Be 1
        @($r.Body.invoices).Count | Should -Be 1
        $r.Body.invoices[0].customer | Should -Be 'לקוח א'
        $r.Body.invoices[0].net | Should -Be 1000
        $r.Body.totals.vat | Should -Be 180
        $r.Body.totals.mikdamot | Should -Be 50
        $r.Body.totals.bituachLeumiEstimate | Should -Be 59.7
    }

    It 'passes range params through to the period summary' {
        Mock Get-TaxPeriodSummary { $fakeData } -ParameterFilter {
            $From -eq [datetime]'2026-05-01' -and $To -eq [datetime]'2026-06-30'
        }
        Mock Get-TaxPeriodSummary { throw 'wrong splat' }
        $r = Get-DashboardSummaryResponse -Query @{ from = '2026-05-01'; to = '2026-06-30' }
        $r.StatusCode | Should -Be 200
    }
}

Describe 'Get-DashboardCsvResponse' {
    It 'returns 400 for invalid params' {
        $r = Get-DashboardCsvResponse -Query @{}
        $r.StatusCode | Should -Be 400
        $r.Error | Should -Match 'Missing period'
    }

    It 'returns 502 when the API layer fails' {
        Mock Get-TaxPeriodSummary { throw 'yeshinvoice API reported failure: bad token' }
        $r = Get-DashboardCsvResponse -Query @{ month = '2026-06' }
        $r.StatusCode | Should -Be 502
    }

    It 'returns CSV bytes with BOM and a period-stamped filename' {
        Mock Get-TaxPeriodSummary { $fakeData }
        $r = Get-DashboardCsvResponse -Query @{ month = '2026-06' }
        $r.StatusCode | Should -Be 200
        $r.FileName | Should -Be 'tax-summary-2026-06-01_2026-06-30.csv'
        $r.Bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
    }

    It 'leaves no temp file behind' {
        Mock Get-TaxPeriodSummary { $fakeData }
        $before = @(Get-ChildItem ([System.IO.Path]::GetTempPath()) -Filter 'yesh-*.csv').Count
        $null = Get-DashboardCsvResponse -Query @{ month = '2026-06' }
        $after = @(Get-ChildItem ([System.IO.Path]::GetTempPath()) -Filter 'yesh-*.csv').Count
        $after | Should -Be $before
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester .\tests\DashboardHandlers.Tests.ps1 -Output Detailed`
Expected: FAIL — handler files do not exist.

- [ ] **Step 3: Write the implementations**

`src/YeshHeshbonit/Public/Get-DashboardSummaryResponse.ps1`:

```powershell
function Get-DashboardSummaryResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Query
    )

    try {
        $splat = Resolve-DashboardPeriodParam -Query $Query
    }
    catch {
        return @{ StatusCode = 400; Body = @{ error = $_.Exception.Message } }
    }

    try {
        $data = Get-TaxPeriodSummary @splat
    }
    catch {
        return @{ StatusCode = 502; Body = @{ error = $_.Exception.Message } }
    }

    $round = { param($v) [math]::Round($v, 2, [System.MidpointRounding]::AwayFromZero) }
    @{
        StatusCode = 200
        Body       = @{
            period   = @{
                from   = $data.From.ToString('yyyy-MM-dd')
                to     = $data.To.ToString('yyyy-MM-dd')
                months = $data.Months
            }
            invoices = @($data.Invoices | ForEach-Object {
                @{
                    date           = $_.Date
                    documentNumber = $_.DocumentNumber
                    customer       = $_.Customer
                    gross          = & $round $_.Gross
                    net            = & $round $_.Net
                    vat            = & $round $_.Vat
                }
            })
            totals   = @{
                gross                = $data.Totals.Gross
                net                  = $data.Totals.Net
                vat                  = $data.Totals.Vat
                mikdamot             = $data.Totals.Mikdamot
                bituachLeumiEstimate = $data.Totals.BituachLeumiEstimate
                months               = $data.Totals.MonthsInPeriod
            }
        }
    }
}
```

`src/YeshHeshbonit/Public/Get-DashboardCsvResponse.ps1`:

```powershell
function Get-DashboardCsvResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Query
    )

    try {
        $splat = Resolve-DashboardPeriodParam -Query $Query
    }
    catch {
        return @{ StatusCode = 400; Error = $_.Exception.Message }
    }

    try {
        $data = Get-TaxPeriodSummary @splat
        $summary = [pscustomobject]@{ Invoices = $data.Invoices; Totals = $data.Totals }
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("yesh-{0}.csv" -f [guid]::NewGuid())
        try {
            $null = Export-TaxSummary -Summary $summary -Path $tmp
            $bytes = [System.IO.File]::ReadAllBytes($tmp)
        }
        finally {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
        return @{
            StatusCode = 200
            Bytes      = $bytes
            FileName   = 'tax-summary-{0}_{1}.csv' -f $data.From.ToString('yyyy-MM-dd'), $data.To.ToString('yyyy-MM-dd')
        }
    }
    catch {
        return @{ StatusCode = 502; Error = $_.Exception.Message }
    }
}
```

Update `src/YeshHeshbonit/YeshHeshbonit.psd1`, replacing the FunctionsToExport line with:

```powershell
    FunctionsToExport = @('Get-TaxSummary', 'Get-YeshInvoice', 'Export-TaxSummary', 'Get-DashboardSummaryResponse', 'Get-DashboardCsvResponse')
```

Update the export assertion in `tests/Module.Tests.ps1` to:

```powershell
    It 'declares the public functions' {
        $manifest = Test-ModuleManifest -Path $manifestPath
        $manifest.ExportedFunctions.Keys | Sort-Object |
            Should -Be @('Export-TaxSummary', 'Get-DashboardCsvResponse', 'Get-DashboardSummaryResponse', 'Get-TaxSummary', 'Get-YeshInvoice')
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester .\tests\DashboardHandlers.Tests.ps1 -Output Detailed` → 9 PASS.
Then full suite: `Invoke-Pester .\tests` → all PASS.

- [ ] **Step 5: Commit**

```powershell
git add src/YeshHeshbonit/Public/Get-DashboardSummaryResponse.ps1 src/YeshHeshbonit/Public/Get-DashboardCsvResponse.ps1 src/YeshHeshbonit/YeshHeshbonit.psd1 tests/DashboardHandlers.Tests.ps1 tests/Module.Tests.ps1
git commit -m "feat: dashboard API response handlers with fail-closed error mapping"
```

---

### Task 4: Frontend static assets

**Files:**
- Create: `web/public/index.html`
- Create: `web/public/style.css`
- Create: `web/public/app.js`

**Interfaces:**
- Consumes: `GET /api/summary?month=yyyy-MM | ?from=yyyy-MM-dd&to=yyyy-MM-dd` → 200 `{period{from,to,months}, invoices[{date,documentNumber,customer,gross,net,vat}], totals{gross,net,vat,mikdamot,bituachLeumiEstimate,months}}` or 4xx/5xx `{error}`; `GET /api/summary/csv?<same>` → CSV attachment (Task 5 serves both)
- Produces: the static page Task 5 serves from `web/public/`

No unit tests for static assets (project has no JS test infrastructure — deliberate). Verification is the Task 6 live smoke. Keep app.js logic minimal.

- [ ] **Step 1: Write `web/public/index.html`**

```html
<!DOCTYPE html>
<html dir="rtl" lang="he">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>מחשבון הפרשות מס — יש חשבונית</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
<header>
  <h1>מחשבון הפרשות מס</h1>
  <p class="sub">הכנסות מיש חשבונית — מע"מ, מקדמות מס הכנסה וביטוח לאומי</p>
</header>

<section class="controls">
  <div class="quick">
    <button id="btn-this-month" type="button">החודש</button>
    <button id="btn-prev-month" type="button">חודש קודם</button>
    <button id="btn-vat-period" type="button">תקופת מע"מ נוכחית</button>
  </div>
  <div class="pickers">
    <label>חודש <input type="month" id="month-input"></label>
    <span class="or">או טווח:</span>
    <label>מ־ <input type="date" id="from-input"></label>
    <label>עד <input type="date" id="to-input"></label>
    <button id="btn-apply-range" type="button">הצג טווח</button>
  </div>
</section>

<div id="error-banner" class="error hidden"></div>
<div id="loading" class="loading hidden">טוען…</div>

<section id="results" class="hidden">
  <p id="period-label" class="period"></p>
  <section class="cards">
    <div class="card"><h2>מע"מ להפרשה</h2><p class="amount" id="card-vat"></p></div>
    <div class="card"><h2>מקדמות מס הכנסה</h2><p class="amount" id="card-mikdamot"></p></div>
    <div class="card">
      <h2>ביטוח לאומי <span class="badge">אומדן</span></h2>
      <p class="amount" id="card-bl"></p>
      <p class="note">מבוסס על הכנסת התקופה; המקדמה בפועל נקבעת לפי השומה בביטוח לאומי.</p>
    </div>
  </section>
  <p class="summary-line">
    <span>ברוטו: <b id="sum-gross"></b></span>
    <span>נטו לפני מע"מ: <b id="sum-net"></b></span>
  </p>
  <table id="invoice-table">
    <thead><tr><th>תאריך</th><th>מס' מסמך</th><th>לקוח</th><th>ברוטו</th><th>נטו</th><th>מע"מ</th></tr></thead>
    <tbody></tbody>
  </table>
  <p id="empty-msg" class="hidden">לא נמצאו מסמכי הכנסה בתקופה.</p>
  <button id="btn-csv" type="button" class="csv">הורדת CSV לרואה חשבון</button>
</section>

<script src="app.js"></script>
</body>
</html>
```

- [ ] **Step 2: Write `web/public/style.css`**

```css
:root {
  --bg: #f5f6f8;
  --card: #ffffff;
  --ink: #1c2430;
  --muted: #66707d;
  --accent: #0b6e4f;
  --error: #b00020;
  --border: #dde2e8;
}
* { box-sizing: border-box; }
body {
  margin: 0 auto;
  max-width: 960px;
  padding: 24px 16px 48px;
  background: var(--bg);
  color: var(--ink);
  font-family: "Segoe UI", system-ui, -apple-system, Arial, sans-serif;
}
header h1 { margin: 0 0 4px; font-size: 1.6rem; }
header .sub { margin: 0 0 20px; color: var(--muted); }
.hidden { display: none !important; }

.controls {
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 14px 16px;
  display: flex;
  flex-direction: column;
  gap: 10px;
  margin-bottom: 18px;
}
.quick, .pickers { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
.or { color: var(--muted); }
button {
  border: 1px solid var(--border);
  background: var(--card);
  border-radius: 8px;
  padding: 7px 14px;
  font: inherit;
  cursor: pointer;
}
button:hover { border-color: var(--accent); color: var(--accent); }
button.csv { margin-top: 16px; background: var(--accent); border-color: var(--accent); color: #fff; }
button.csv:hover { opacity: .9; color: #fff; }
input[type="month"], input[type="date"] {
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 6px 8px;
  font: inherit;
}

.error {
  background: #fdecee;
  border: 1px solid var(--error);
  color: var(--error);
  border-radius: 8px;
  padding: 12px 14px;
  margin-bottom: 18px;
}
.loading { color: var(--muted); padding: 12px 0; }
.period { color: var(--muted); margin: 0 0 12px; }

.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; }
.card {
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 14px 16px;
}
.card h2 { margin: 0 0 8px; font-size: 1rem; color: var(--muted); font-weight: 600; }
.card .amount { margin: 0; font-size: 1.7rem; font-weight: 700; color: var(--accent); }
.card .note { margin: 8px 0 0; font-size: .78rem; color: var(--muted); }
.badge {
  background: #fff3cd;
  color: #7a5d00;
  border-radius: 6px;
  font-size: .7rem;
  padding: 2px 6px;
  vertical-align: middle;
}

.summary-line { display: flex; gap: 24px; color: var(--muted); }
table { width: 100%; border-collapse: collapse; background: var(--card); border: 1px solid var(--border); border-radius: 10px; overflow: hidden; }
th, td { padding: 9px 12px; text-align: right; border-bottom: 1px solid var(--border); }
th { background: #eef1f4; font-weight: 600; }
tbody tr:last-child td { border-bottom: none; }
```

- [ ] **Step 3: Write `web/public/app.js`**

```javascript
(() => {
  'use strict';
  const ils = new Intl.NumberFormat('he-IL', { style: 'currency', currency: 'ILS' });
  const $ = (id) => document.getElementById(id);
  let currentParams = null;

  function show(el, visible) { el.classList.toggle('hidden', !visible); }

  function setLoading() {
    show($('error-banner'), false);
    show($('results'), false);
    show($('loading'), true);
  }

  function showError(message) {
    show($('loading'), false);
    show($('results'), false);
    const banner = $('error-banner');
    banner.textContent = message;
    show(banner, true);
  }

  function render(data) {
    $('period-label').textContent =
      'תקופה: ' + data.period.from + ' עד ' + data.period.to + ' (' + data.period.months + ' חודשים)';
    $('card-vat').textContent = ils.format(data.totals.vat);
    $('card-mikdamot').textContent = ils.format(data.totals.mikdamot);
    $('card-bl').textContent = ils.format(data.totals.bituachLeumiEstimate);
    $('sum-gross').textContent = ils.format(data.totals.gross);
    $('sum-net').textContent = ils.format(data.totals.net);

    const tbody = $('invoice-table').querySelector('tbody');
    tbody.replaceChildren();
    for (const inv of data.invoices) {
      const tr = document.createElement('tr');
      const cells = [inv.date, inv.documentNumber, inv.customer,
                     ils.format(inv.gross), ils.format(inv.net), ils.format(inv.vat)];
      for (const value of cells) {
        const td = document.createElement('td');
        td.textContent = value ?? '';
        tr.appendChild(td);
      }
      tbody.appendChild(tr);
    }
    const empty = data.invoices.length === 0;
    show($('empty-msg'), empty);
    $('invoice-table').classList.toggle('hidden', empty);
    show($('loading'), false);
    show($('results'), true);
  }

  async function load(params) {
    currentParams = params;
    setLoading();
    try {
      const res = await fetch('/api/summary?' + new URLSearchParams(params));
      const body = await res.json();
      if (!res.ok) { showError(body.error || 'שגיאה לא ידועה'); return; }
      render(body);
    } catch {
      showError('השרת אינו זמין.');
    }
  }

  function pad(n) { return String(n).padStart(2, '0'); }
  function monthStr(d) { return d.getFullYear() + '-' + pad(d.getMonth() + 1); }
  function dateStr(d) { return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()); }

  $('btn-this-month').addEventListener('click', () => {
    const m = monthStr(new Date());
    $('month-input').value = m;
    load({ month: m });
  });

  $('btn-prev-month').addEventListener('click', () => {
    const d = new Date();
    d.setDate(1);
    d.setMonth(d.getMonth() - 1);
    const m = monthStr(d);
    $('month-input').value = m;
    load({ month: m });
  });

  $('btn-vat-period').addEventListener('click', () => {
    // Bi-monthly VAT periods: Jan-Feb, Mar-Apr, May-Jun, Jul-Aug, Sep-Oct, Nov-Dec
    const now = new Date();
    const startMonth = now.getMonth() - (now.getMonth() % 2);
    const from = new Date(now.getFullYear(), startMonth, 1);
    const to = new Date(now.getFullYear(), startMonth + 2, 0);
    load({ from: dateStr(from), to: dateStr(to) });
  });

  $('month-input').addEventListener('change', (e) => {
    if (e.target.value) load({ month: e.target.value });
  });

  $('btn-apply-range').addEventListener('click', () => {
    const from = $('from-input').value;
    const to = $('to-input').value;
    if (!from || !to) { showError('יש לבחור תאריך התחלה ותאריך סיום.'); return; }
    load({ from, to });
  });

  $('btn-csv').addEventListener('click', () => {
    if (currentParams) {
      window.location.href = '/api/summary/csv?' + new URLSearchParams(currentParams);
    }
  });

  $('btn-this-month').click();
})();
```

- [ ] **Step 4: Sanity check**

Run: `node --check web/public/app.js` if Node is available; otherwise open `web/public/index.html` directly in a browser — the page must render (it will show "השרת אינו זמין." since there is no API yet; that IS the expected error path working). Confirm all three files exist and `Invoke-Pester .\tests` still passes (nothing should have changed).

- [ ] **Step 5: Commit**

```powershell
git add web/public/index.html web/public/style.css web/public/app.js
git commit -m "feat: dashboard frontend (RTL Hebrew, vanilla JS, no build)"
```

---

### Task 5: Start-TaxDashboard (Public) + manifest update

**Files:**
- Create: `src/YeshHeshbonit/Public/Start-TaxDashboard.ps1`
- Modify: `src/YeshHeshbonit/YeshHeshbonit.psd1` (FunctionsToExport)
- Modify: `tests/Module.Tests.ps1` (export-list assertion)
- Test: `tests/Start-TaxDashboard.Tests.ps1`

**Interfaces:**
- Consumes: `Get-DashboardSummaryResponse -Query`, `Get-DashboardCsvResponse -Query` (Task 3), `Get-YeshConfig` (existing), Pode module (`Start-PodeServer`, `Add-PodeEndpoint`, `Import-PodeModule`, `Add-PodeStaticRoute`, `Add-PodeRoute`, `Write-PodeJsonResponse`, `Write-PodeTextResponse`, `Add-PodeHeader`), `web/public/` assets (Task 4)
- Produces: `Start-TaxDashboard [-Port <int=8321>] [-NoBrowser] [-WebRoot <string>]` — blocks while serving; Ctrl+C stops

- [ ] **Step 1: Write the failing tests**

`tests/Start-TaxDashboard.Tests.ps1` — tests cover the fail-closed startup paths only; no real server is started (Global Constraints):

```powershell
BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Get-YeshConfig.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Public\Start-TaxDashboard.ps1')
}

Describe 'Start-TaxDashboard' {
    It 'fails closed with install instructions when Pode is missing' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -eq $true -and $Name -eq 'Pode' }
        { Start-TaxDashboard -NoBrowser } | Should -Throw '*Install-Module Pode*'
    }

    It 'fails closed at startup when config is invalid' {
        Mock Get-Module { [pscustomobject]@{ Name = 'Pode' } } -ParameterFilter { $ListAvailable -eq $true -and $Name -eq 'Pode' }
        Mock Get-YeshConfig { throw "Missing or placeholder value for 'YESH_SECRET' in .env." }
        { Start-TaxDashboard -NoBrowser } | Should -Throw '*YESH_SECRET*'
    }

    It 'fails closed when the web assets are missing' {
        Mock Get-Module { [pscustomobject]@{ Name = 'Pode' } } -ParameterFilter { $ListAvailable -eq $true -and $Name -eq 'Pode' }
        Mock Get-YeshConfig { [pscustomobject]@{ Secret = 's'; UserKey = 'u'; Rates = $null } }
        { Start-TaxDashboard -NoBrowser -WebRoot (Join-Path $TestDrive 'nope') } |
            Should -Throw '*Dashboard assets not found*'
    }

    It 'rejects out-of-range ports' {
        { Start-TaxDashboard -NoBrowser -Port 80 } | Should -Throw
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester .\tests\Start-TaxDashboard.Tests.ps1 -Output Detailed`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Write the implementation**

`src/YeshHeshbonit/Public/Start-TaxDashboard.ps1`:

```powershell
function Start-TaxDashboard {
    [CmdletBinding()]
    param(
        [ValidateRange(1024, 65535)][int]$Port = 8321,
        [switch]$NoBrowser,
        [string]$WebRoot
    )

    if (-not (Get-Module -ListAvailable -Name Pode)) {
        throw "The Pode module is required for the dashboard. Install it with: Install-Module Pode -Scope CurrentUser"
    }

    # Fail closed on bad config at startup, not at the first request
    $null = Get-YeshConfig

    if (-not $WebRoot) {
        # Public -> YeshHeshbonit -> src -> project root
        $WebRoot = Join-Path (Get-Item $PSScriptRoot).Parent.Parent.Parent.FullName 'web\public'
    }
    if (-not (Test-Path (Join-Path $WebRoot 'index.html'))) {
        throw "Dashboard assets not found at '$WebRoot'."
    }

    $modulePsd1 = Join-Path (Get-Item $PSScriptRoot).Parent.FullName 'YeshHeshbonit.psd1'
    $url = "http://127.0.0.1:$Port"

    Write-Host "Tax dashboard running at $url  (Ctrl+C to stop)"
    if (-not $NoBrowser) { Start-Process $url }

    # GetNewClosure captures $Port/$WebRoot/$modulePsd1 for the server setup block
    Start-PodeServer -ScriptBlock ({
        Add-PodeEndpoint -Address 127.0.0.1 -Port $Port -Protocol Http

        # Route script blocks run in Pode runspaces: they can only call functions
        # exported by modules imported here.
        Import-PodeModule -Path $modulePsd1

        Add-PodeStaticRoute -Path '/' -Source $WebRoot -Defaults @('index.html')

        Add-PodeRoute -Method Get -Path '/api/summary' -ScriptBlock {
            try {
                $r = Get-DashboardSummaryResponse -Query ([hashtable]$WebEvent.Query)
                Write-PodeJsonResponse -Value $r.Body -StatusCode $r.StatusCode -Depth 6
            }
            catch {
                Write-PodeJsonResponse -Value @{ error = 'Internal error' } -StatusCode 500
            }
        }

        Add-PodeRoute -Method Get -Path '/api/summary/csv' -ScriptBlock {
            try {
                $r = Get-DashboardCsvResponse -Query ([hashtable]$WebEvent.Query)
                if ($r.StatusCode -ne 200) {
                    Write-PodeJsonResponse -Value @{ error = $r.Error } -StatusCode $r.StatusCode
                    return
                }
                Add-PodeHeader -Name 'Content-Disposition' -Value ('attachment; filename="{0}"' -f $r.FileName)
                Write-PodeTextResponse -Bytes $r.Bytes -ContentType 'text/csv; charset=utf-8'
            }
            catch {
                Write-PodeJsonResponse -Value @{ error = 'Internal error' } -StatusCode 500
            }
        }
    }).GetNewClosure()
}
```

Update `src/YeshHeshbonit/YeshHeshbonit.psd1` FunctionsToExport to the final list:

```powershell
    FunctionsToExport = @('Get-TaxSummary', 'Get-YeshInvoice', 'Export-TaxSummary', 'Get-DashboardSummaryResponse', 'Get-DashboardCsvResponse', 'Start-TaxDashboard')
```

Update the export assertion in `tests/Module.Tests.ps1` to:

```powershell
    It 'declares the public functions' {
        $manifest = Test-ModuleManifest -Path $manifestPath
        $manifest.ExportedFunctions.Keys | Sort-Object |
            Should -Be @('Export-TaxSummary', 'Get-DashboardCsvResponse', 'Get-DashboardSummaryResponse', 'Get-TaxSummary', 'Get-YeshInvoice', 'Start-TaxDashboard')
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester .\tests\Start-TaxDashboard.Tests.ps1 -Output Detailed` → 4 PASS.
Then full suite: `Invoke-Pester .\tests` → all PASS.

- [ ] **Step 5: Commit**

```powershell
git add src/YeshHeshbonit/Public/Start-TaxDashboard.ps1 src/YeshHeshbonit/YeshHeshbonit.psd1 tests/Start-TaxDashboard.Tests.ps1 tests/Module.Tests.ps1
git commit -m "feat: Start-TaxDashboard Pode server (127.0.0.1 only)"
```

---

### Task 6: Live smoke test + README

**Files:**
- Modify: `README.md` (Requirements, Usage, Status sections)

**Interfaces:**
- Consumes: the complete module + real `.env`; installs Pode from PSGallery if absent

- [ ] **Step 1: Ensure Pode is installed**

```powershell
if (-not (Get-Module -ListAvailable -Name Pode)) { Install-Module Pode -Scope CurrentUser -Force }
```

- [ ] **Step 2: Start the server in a background job and probe the API**

```powershell
$job = Start-Job -ScriptBlock {
    Import-Module 'C:\Users\Eitan\ClaudeCodeAI\YeshHeshbonitAPI\src\YeshHeshbonit\YeshHeshbonit.psd1' -Force
    Start-TaxDashboard -NoBrowser -Port 8321
}
Start-Sleep -Seconds 6   # Pode startup

# 1. Static page
(Invoke-WebRequest 'http://127.0.0.1:8321/' -UseBasicParsing).StatusCode          # expect 200, HTML contains 'מחשבון הפרשות מס'
# 2. Summary JSON (real data)
Invoke-RestMethod 'http://127.0.0.1:8321/api/summary?from=2026-01-01&to=2026-07-02'  # expect totals matching CLI output
# 3. Validation error
try { Invoke-WebRequest 'http://127.0.0.1:8321/api/summary?month=June' -UseBasicParsing } catch { $_.Exception.Response.StatusCode }  # expect 400
# 4. CSV download
$csv = Invoke-WebRequest 'http://127.0.0.1:8321/api/summary/csv?from=2026-01-01&to=2026-07-02' -UseBasicParsing
$csv.Headers['Content-Disposition']   # expect attachment; filename="tax-summary-2026-01-01_2026-07-02.csv"

Stop-Job $job; Remove-Job $job -Force
```

Cross-check the JSON totals against `Get-TaxSummary -From 2026-01-01 -To 2026-07-02` CLI output — they must be identical.

- [ ] **Step 3: Manual browser check**

Run `Start-TaxDashboard` (with browser), verify: RTL layout, three cards, invoice table with Hebrew customer names, quick buttons switch periods, CSV button downloads a file that opens in Excel with Hebrew intact. Stop with Ctrl+C.

- [ ] **Step 4: Update README.md**

In Requirements add: `- Pode module (dashboard only): Install-Module Pode -Scope CurrentUser`.
In Usage add:

```markdown
### Web dashboard

​```powershell
Start-TaxDashboard              # http://127.0.0.1:8321, opens your browser
Start-TaxDashboard -Port 9000 -NoBrowser
​```

Hebrew RTL dashboard: period picker, set-aside cards (מע"מ / מקדמות / ביטוח לאומי),
invoice table, accountant CSV download. Binds to 127.0.0.1 only.
```

Update Status test count to the final number from the full suite run.

- [ ] **Step 5: Final commit**

```powershell
git add README.md
git commit -m "docs: dashboard usage after live smoke test"
```

---

## Self-Review Notes

- **Spec coverage:** refactor (T1), param validation (T2), handlers + error mapping 400/502/500 (T3, 500 catch-all in T5 routes), frontend incl. RTL/textContent/quick buttons/empty state/error banner/stale-number clearing (T4), server incl. 127.0.0.1 binding, Pode-missing failure, startup config check, static route, CSV attachment (T5), live verification + docs (T6). Out-of-scope items have no tasks — correct.
- **Type consistency:** `Get-TaxPeriodSummary` → `{From,To,Months,Invoices,Totals}` consumed by T3 handlers and T1's CLI display under those names; handler return shapes `{StatusCode,Body}` / `{StatusCode,Bytes,FileName,Error}` consumed by T5 routes exactly; JSON field names (`period.from`, `invoices[].documentNumber`, `totals.bituachLeumiEstimate`) match between T3 handler and T4 app.js.
- **Known risk, called out for the implementer:** Pode runspace scoping (`Import-PodeModule`, `.GetNewClosure()`) is validated by the T6 live smoke, not unit tests — if route functions are unavailable at runtime, the fix is in T5's server block, not the handlers.
- **Placeholder scan:** all steps carry complete code and exact commands.
