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
