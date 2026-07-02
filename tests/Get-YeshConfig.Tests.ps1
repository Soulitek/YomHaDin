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
