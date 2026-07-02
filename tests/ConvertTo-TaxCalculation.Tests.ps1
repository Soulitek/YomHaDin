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

    It 'rounds half up (away from zero), not banker''s rounding' {
        # net 100.10, mikdamotRate 0.05 -> 100.10*0.05 = 5.005 (exact midpoint in binary float)
        # AwayFromZero gives 5.01, banker's rounding gives 5.00 (rounds to even)
        # empirically verified: [math]::Round(100.10*0.05,2) = 5.00 vs AwayFromZero = 5.01
        $doc = [pscustomobject]@{ DocumentType = 8; TotalPrice = 100.10; vattype = 1
                                  DocumentNumber = '9001'; CustomerName = 'M'; Date = '01-06-2026' }
        $result = ConvertTo-TaxCalculation -Documents @($doc) -Rates $rates
        $result.Totals.Mikdamot | Should -Be 5.01
    }
}
