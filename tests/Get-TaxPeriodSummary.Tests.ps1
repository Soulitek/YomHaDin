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
