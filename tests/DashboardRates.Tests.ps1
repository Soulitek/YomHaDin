BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Get-YeshConfig.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Public\Get-DashboardRatesResponse.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Public\Set-DashboardRatesResponse.ps1')

    $script:goodRatesJson = @'
{
  "vatRate": 0.18,
  "mikdamotRate": 0.08,
  "bituachLeumi": { "averageWageMonthly": 13769, "reducedRateThreshold": 0.60, "reducedRate": 0.0597, "fullRate": 0.1783 },
  "revenueDocTypes": [8, 9],
  "creditDocTypes": [10],
  "cancelledStatusIds": []
}
'@
    $script:goodEnv = "YESH_SECRET=abc-123`nYESH_USERKEY=key-456`n"
}

Describe 'Get-DashboardRatesResponse' {
    BeforeEach {
        $script:envPath = Join-Path $TestDrive '.env'
        $script:ratesPath = Join-Path $TestDrive 'rates.json'
        Set-Content -Path $envPath -Value $goodEnv -NoNewline
        Set-Content -Path $ratesPath -Value $goodRatesJson -NoNewline
    }

    It 'returns the current rate' {
        $r = Get-DashboardRatesResponse -RatesPath $ratesPath -EnvPath $envPath
        $r.StatusCode | Should -Be 200
        $r.Body.mikdamotRate | Should -Be 0.08
    }

    It 'returns 502 for a broken rates file' {
        Set-Content -Path $ratesPath -Value '{ not json'
        $r = Get-DashboardRatesResponse -RatesPath $ratesPath -EnvPath $envPath
        $r.StatusCode | Should -Be 502
        $r.Body.error | Should -Not -BeNullOrEmpty
    }
}

Describe 'Set-DashboardRatesResponse' {
    BeforeEach {
        $script:envPath = Join-Path $TestDrive '.env'
        $script:ratesPath = Join-Path $TestDrive 'rates.json'
        Set-Content -Path $envPath -Value $goodEnv -NoNewline
        Set-Content -Path $ratesPath -Value $goodRatesJson -NoNewline
    }

    It 'updates the rate and preserves every other key' {
        $r = Set-DashboardRatesResponse -Body @{ mikdamotRate = 0.1 } -RatesPath $ratesPath -EnvPath $envPath
        $r.StatusCode | Should -Be 200
        $r.Body.mikdamotRate | Should -Be 0.1
        $after = Get-Content $ratesPath -Raw | ConvertFrom-Json
        $after.mikdamotRate | Should -Be 0.1
        $after.vatRate | Should -Be 0.18
        @($after.revenueDocTypes) | Should -Be @(8, 9)
        @($after.creditDocTypes) | Should -Be @(10)
        $after.bituachLeumi.averageWageMonthly | Should -Be 13769
    }

    It 'accepts a PSCustomObject body (Pode JSON parse shape)' {
        $r = Set-DashboardRatesResponse -Body ([pscustomobject]@{ mikdamotRate = 0.09 }) -RatesPath $ratesPath -EnvPath $envPath
        $r.StatusCode | Should -Be 200
        (Get-Content $ratesPath -Raw | ConvertFrom-Json).mikdamotRate | Should -Be 0.09
    }

    It 'rejects out-of-range values and leaves the file untouched' {
        $before = Get-Content $ratesPath -Raw
        foreach ($bad in -0.1, 1, 1.5) {
            $r = Set-DashboardRatesResponse -Body @{ mikdamotRate = $bad } -RatesPath $ratesPath -EnvPath $envPath
            $r.StatusCode | Should -Be 400
        }
        Get-Content $ratesPath -Raw | Should -Be $before
    }

    It 'rejects a non-numeric value' {
        $r = Set-DashboardRatesResponse -Body @{ mikdamotRate = 'abc' } -RatesPath $ratesPath -EnvPath $envPath
        $r.StatusCode | Should -Be 400
        $r.Body.error | Should -Match 'number'
    }

    It 'rejects a missing mikdamotRate key' {
        $r = Set-DashboardRatesResponse -Body @{} -RatesPath $ratesPath -EnvPath $envPath
        $r.StatusCode | Should -Be 400
        $r.Body.error | Should -Match 'Missing'
    }

    It 'rejects a null body' {
        $r = Set-DashboardRatesResponse -Body $null -RatesPath $ratesPath -EnvPath $envPath
        $r.StatusCode | Should -Be 400
    }

    It 'rejects extra keys and leaves the file untouched' {
        $before = Get-Content $ratesPath -Raw
        $r = Set-DashboardRatesResponse -Body @{ mikdamotRate = 0.1; vatRate = 0.5 } -RatesPath $ratesPath -EnvPath $envPath
        $r.StatusCode | Should -Be 400
        $r.Body.error | Should -Match 'Only'
        Get-Content $ratesPath -Raw | Should -Be $before
    }

    It 'returns 502 when the rates file is unreadable' {
        Remove-Item $ratesPath
        $r = Set-DashboardRatesResponse -Body @{ mikdamotRate = 0.1 } -RatesPath $ratesPath -EnvPath $envPath
        $r.StatusCode | Should -Be 502
    }

    It 'keeps the original intact when candidate validation fails' {
        # Validation of the candidate runs through Get-YeshConfig with this EnvPath;
        # a nonexistent env makes validation throw AFTER the temp is written.
        $before = Get-Content $ratesPath -Raw
        $r = Set-DashboardRatesResponse -Body @{ mikdamotRate = 0.1 } -RatesPath $ratesPath -EnvPath (Join-Path $TestDrive 'no.env')
        $r.StatusCode | Should -Be 502
        Get-Content $ratesPath -Raw | Should -Be $before
    }

    It 'leaves no temp files behind' {
        $null = Set-DashboardRatesResponse -Body @{ mikdamotRate = 0.1 } -RatesPath $ratesPath -EnvPath $envPath
        $null = Set-DashboardRatesResponse -Body @{ mikdamotRate = 5 } -RatesPath $ratesPath -EnvPath $envPath
        @(Get-ChildItem $TestDrive -Filter '*.tmp').Count | Should -Be 0
    }
}
