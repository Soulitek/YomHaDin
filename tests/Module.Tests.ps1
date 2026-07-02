Describe 'YeshHeshbonit module' {
    BeforeAll {
        $script:manifestPath = Join-Path $PSScriptRoot '..\src\YeshHeshbonit\YeshHeshbonit.psd1'
    }

    It 'has a valid manifest' {
        { Test-ModuleManifest -Path $manifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'declares the public functions' {
        $manifest = Test-ModuleManifest -Path $manifestPath
        $manifest.ExportedFunctions.Keys | Sort-Object |
            Should -Be @('Export-TaxSummary', 'Get-DashboardCsvResponse', 'Get-DashboardRatesResponse', 'Get-DashboardSummaryResponse', 'Get-TaxSummary', 'Get-YeshInvoice', 'Set-DashboardRatesResponse', 'Start-TaxDashboard')
    }

    It 'ships a rates.example.json with all required keys' {
        $rates = Get-Content (Join-Path $PSScriptRoot '..\config\rates.example.json') -Raw | ConvertFrom-Json
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
