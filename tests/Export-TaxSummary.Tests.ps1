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

    It 'neutralizes Excel formula injection in string fields' {
        $evil = [pscustomobject]@{
            Invoices = @(
                [pscustomobject]@{ Date = '01-06-2026'; DocumentNumber = '1001'; DocumentType = 8
                                   Customer = '=HYPERLINK("http://evil","x")'; Gross = 118.0; Net = 100.0; Vat = 18.0 }
            )
            Totals = [pscustomobject]@{ Gross = 118.0; Net = 100.0; Vat = 18.0
                                        Mikdamot = 5.0; BituachLeumiEstimate = 5.97; MonthsInPeriod = 1 }
        }
        $path = Join-Path $TestDrive 'evil.csv'
        Export-TaxSummary -Summary $evil -Path $path | Out-Null
        $rows = Import-Csv $path
        $rows[0].Customer | Should -Be "'=HYPERLINK(""http://evil"",""x"")"
    }
}
