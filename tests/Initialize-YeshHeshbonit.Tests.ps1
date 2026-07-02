BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Get-YeshConfig.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Invoke-YeshApi.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Read-YeshSecret.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Public\Initialize-YeshHeshbonit.ps1')

    $script:exampleJson = @'
{
  "vatRate": 0.18,
  "mikdamotRate": 0.05,
  "bituachLeumi": { "averageWageMonthly": 13769, "reducedRateThreshold": 0.60, "reducedRate": 0.0597, "fullRate": 0.1783 },
  "revenueDocTypes": [8, 9],
  "creditDocTypes": [10],
  "cancelledStatusIds": []
}
'@
}

Describe 'Initialize-YeshHeshbonit' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $root 'config') -Force | Out-Null
        Set-Content -Path (Join-Path $root 'config/rates.example.json') -Value $exampleJson -NoNewline
    }

    It 'writes .env and rates.json from supplied values' {
        Initialize-YeshHeshbonit -Secret 'abc-123' -UserKey 'key-456' -MikdamotRate 8 -SkipTest -Force -ProjectRoot $root
        $envText = Get-Content (Join-Path $root '.env') -Raw
        $envText | Should -Match 'YESH_SECRET=abc-123'
        $envText | Should -Match 'YESH_USERKEY=key-456'
        $rates = Get-Content (Join-Path $root 'config/rates.json') -Raw | ConvertFrom-Json
        $rates.mikdamotRate | Should -Be 0.08
        $rates.vatRate | Should -Be 0.18
        @($rates.revenueDocTypes) | Should -Be @(8, 9)
        $rates.bituachLeumi.averageWageMonthly | Should -Be 13769
    }

    It 'converts percent to fraction (8.5 -> 0.085)' {
        Initialize-YeshHeshbonit -Secret s -UserKey u -MikdamotRate 8.5 -SkipTest -Force -ProjectRoot $root
        (Get-Content (Join-Path $root 'config/rates.json') -Raw | ConvertFrom-Json).mikdamotRate | Should -Be 0.085
    }

    It 'accepts a zero rate' {
        Initialize-YeshHeshbonit -Secret s -UserKey u -MikdamotRate 0 -SkipTest -Force -ProjectRoot $root
        (Get-Content (Join-Path $root 'config/rates.json') -Raw | ConvertFrom-Json).mikdamotRate | Should -Be 0
    }

    It 'rejects an out-of-range rate and writes nothing' {
        { Initialize-YeshHeshbonit -Secret s -UserKey u -MikdamotRate 150 -SkipTest -Force -ProjectRoot $root } |
            Should -Throw '*between 0 and 100*'
        Test-Path (Join-Path $root '.env') | Should -BeFalse
    }

    It 'rejects a negative rate' {
        { Initialize-YeshHeshbonit -Secret s -UserKey u -MikdamotRate -1 -SkipTest -Force -ProjectRoot $root } |
            Should -Throw '*between 0 and 100*'
    }

    It 'rejects a placeholder secret' {
        { Initialize-YeshHeshbonit -Secret 'your-secret-guid-here' -UserKey u -MikdamotRate 8 -SkipTest -Force -ProjectRoot $root } |
            Should -Throw '*placeholder*'
    }

    It 'refuses to overwrite existing config without -Force' {
        Set-Content -Path (Join-Path $root '.env') -Value 'YESH_SECRET=x' -NoNewline
        { Initialize-YeshHeshbonit -Secret s -UserKey u -MikdamotRate 8 -SkipTest -ProjectRoot $root } |
            Should -Throw '*Force*'
    }

    It 'overwrites with -Force' {
        Set-Content -Path (Join-Path $root '.env') -Value 'YESH_SECRET=old' -NoNewline
        Initialize-YeshHeshbonit -Secret 'new-secret' -UserKey u -MikdamotRate 8 -SkipTest -Force -ProjectRoot $root
        (Get-Content (Join-Path $root '.env') -Raw) | Should -Match 'new-secret'
    }

    It 'verifies credentials when not skipped and aborts on failure without writing' {
        Mock Invoke-YeshApi { throw 'yeshinvoice API reported failure: bad token' }
        { Initialize-YeshHeshbonit -Secret s -UserKey u -MikdamotRate 8 -Force -ProjectRoot $root } |
            Should -Throw '*Could not verify*'
        Test-Path (Join-Path $root '.env') | Should -BeFalse
        Test-Path (Join-Path $root 'config/rates.json') | Should -BeFalse
    }

    It 'saves after a successful credential verification' {
        Mock Invoke-YeshApi { [pscustomobject]@{ Success = $true; ErrorMessage = ''; total = 0; ReturnValue = @() } }
        Initialize-YeshHeshbonit -Secret s -UserKey u -MikdamotRate 8 -Force -ProjectRoot $root
        Test-Path (Join-Path $root '.env') | Should -BeTrue
        Should -Invoke Invoke-YeshApi -Times 1 -Exactly
    }

    It 'fails clearly when rates.example.json is missing' {
        Remove-Item (Join-Path $root 'config/rates.example.json')
        { Initialize-YeshHeshbonit -Secret s -UserKey u -MikdamotRate 8 -SkipTest -Force -ProjectRoot $root } |
            Should -Throw '*rates.example.json*'
    }

    It 'writes a config that Get-YeshConfig accepts' {
        Initialize-YeshHeshbonit -Secret 'real-secret' -UserKey 'real-key' -MikdamotRate 8 -SkipTest -Force -ProjectRoot $root
        $cfg = Get-YeshConfig -EnvPath (Join-Path $root '.env') -RatesPath (Join-Path $root 'config/rates.json')
        $cfg.Secret | Should -Be 'real-secret'
        $cfg.Rates.mikdamotRate | Should -Be 0.08
    }
}
