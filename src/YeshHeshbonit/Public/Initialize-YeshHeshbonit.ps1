function Initialize-YeshHeshbonit {
    <#
    .SYNOPSIS
        Interactive first-time setup: writes .env and config/rates.json.
    .DESCRIPTION
        Prompts for your yeshinvoice API secret and userkey (masked) and your
        income-tax advance rate (mikdamot, as a percent). Verifies the credentials
        against the API, then writes .env and config/rates.json. Non-personal rate
        defaults (VAT, Bituach Leumi, document types) are taken from
        config/rates.example.json.

        Any of -Secret / -UserKey / -MikdamotRate supplied on the command line
        skips the matching prompt, making the command scriptable and testable.
    .EXAMPLE
        Initialize-YeshHeshbonit
    .EXAMPLE
        Initialize-YeshHeshbonit -Secret $s -UserKey $u -MikdamotRate 8
    #>
    [CmdletBinding()]
    param(
        [string]$Secret,
        [string]$UserKey,
        [double]$MikdamotRate,
        [string]$ProjectRoot,
        [switch]$SkipTest,
        [switch]$Force
    )

    if (-not $ProjectRoot) {
        # Public -> YeshHeshbonit -> src -> project root
        $ProjectRoot = (Get-Item $PSScriptRoot).Parent.Parent.Parent.FullName
    }
    $envPath = Join-Path $ProjectRoot '.env'
    $ratesPath = Join-Path $ProjectRoot 'config/rates.json'
    $ratesExamplePath = Join-Path $ProjectRoot 'config/rates.example.json'

    # Fail closed: never clobber an existing configuration without -Force.
    if (-not $Force) {
        $existing = @()
        if (Test-Path $envPath) { $existing += '.env' }
        if (Test-Path $ratesPath) { $existing += 'config/rates.json' }
        if ($existing.Count -gt 0) {
            throw "Already configured ($($existing -join ', ') exist). Re-run with -Force to overwrite."
        }
    }

    if (-not (Test-Path $ratesExamplePath)) {
        throw "Missing config/rates.example.json at '$ratesExamplePath' - cannot build rates.json."
    }

    # Collect any values not supplied on the command line.
    if ([string]::IsNullOrWhiteSpace($Secret)) { $Secret = Read-YeshSecret -Prompt 'Enter your yeshinvoice API secret' }
    if ([string]::IsNullOrWhiteSpace($UserKey)) { $UserKey = Read-YeshSecret -Prompt 'Enter your yeshinvoice API userkey' }
    if (-not $PSBoundParameters.ContainsKey('MikdamotRate')) {
        $raw = Read-Host 'Enter your income-tax advance rate (mikdamot) as a percent, e.g. 8'
        $parsed = 0.0
        # Parse with the invariant culture so '8.5' works regardless of the machine's
        # locale (on a he-IL machine the current culture's decimal separator is ',').
        $ok = [double]::TryParse($raw, [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)
        if (-not $ok) {
            throw "'$raw' is not a valid number for the mikdamot rate."
        }
        $MikdamotRate = $parsed
    }

    # Validate (fail closed) before touching the API or disk.
    foreach ($pair in @(@{ n = 'secret'; v = $Secret }, @{ n = 'userkey'; v = $UserKey })) {
        if ([string]::IsNullOrWhiteSpace($pair.v) -or $pair.v -like 'your-*') {
            throw "The $($pair.n) is empty or still a placeholder."
        }
    }
    if ($MikdamotRate -lt 0 -or $MikdamotRate -ge 100) {
        throw "The mikdamot rate must be a percent between 0 and 100 (e.g. 8 for 8%)."
    }
    $rateFraction = [math]::Round($MikdamotRate / 100, 6)

    # Verify the credentials against the API unless explicitly skipped. On failure,
    # nothing is written - bad keys are never persisted.
    if (-not $SkipTest) {
        Write-Host 'Verifying your API credentials with yeshinvoice...'
        $cfg = [pscustomobject]@{ Secret = $Secret; UserKey = $UserKey }
        $body = @{
            from     = '2000-01-01 00:00'
            to       = (Get-Date).ToString('yyyy-MM-dd HH:mm')
            PageSize = 1
            PageNumber = 1
            Search   = ''
        }
        try {
            $null = Invoke-YeshApi -Endpoint 'api/v1/getInvoices' -Body $body -Config $cfg
        }
        catch {
            throw "Could not verify your API credentials: $($_.Exception.Message) Nothing was saved - check your secret/userkey and try again (or pass -SkipTest to save without verifying)."
        }
    }

    # Build rates.json from the example, overriding only the personal rate.
    $rates = Get-Content $ratesExamplePath -Raw | ConvertFrom-Json
    $rates.mikdamotRate = $rateFraction

    $configDir = Join-Path $ProjectRoot 'config'
    if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir | Out-Null }

    # The trailing newline is already in the string; -NoNewline stops Set-Content adding another.
    "YESH_SECRET=$Secret`nYESH_USERKEY=$UserKey`n" | Set-Content -Path $envPath -Encoding utf8 -NoNewline
    $rates | ConvertTo-Json -Depth 5 | Set-Content -Path $ratesPath -Encoding utf8

    # Confirm the written configuration loads cleanly.
    $null = Get-YeshConfig -EnvPath $envPath -RatesPath $ratesPath

    Write-Host ''
    Write-Host 'Setup complete. Wrote:'
    Write-Host "  $envPath"
    Write-Host "  $ratesPath"
    Write-Host ("Your mikdamot rate is set to {0}%." -f $MikdamotRate)
    Write-Host ''
    Write-Host ('Try:  Get-TaxSummary -Month {0}' -f (Get-Date -Format 'yyyy-MM'))
    Write-Host 'Or:   Start-TaxDashboard'
}
