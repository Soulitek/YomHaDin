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
        Mock Get-YeshInvoice { throw 'unmocked Get-YeshInvoice call - range regression' }
        Mock Get-YeshInvoice { @(New-ApiDoc) } -ParameterFilter {
            $From -eq [datetime]'2026-06-01 00:00' -and
            $To -eq [datetime]'2026-06-30 23:59'
        }
        Get-TaxSummary -Month 2026-06 | Out-Null
        Should -Invoke Get-YeshInvoice -Times 1 -Exactly
    }

    It 'treats a date-only -To as end of that day' {
        Mock Get-YeshInvoice { throw 'unexpected -To boundary' }
        Mock Get-YeshInvoice { @(New-ApiDoc) } -ParameterFilter {
            $To -eq [datetime]'2026-06-30 23:59'
        }
        Get-TaxSummary -From '2026-05-01' -To '2026-06-30' | Out-Null
        Should -Invoke Get-YeshInvoice -Times 1 -Exactly -ParameterFilter {
            $To -eq [datetime]'2026-06-30 23:59'
        }
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
