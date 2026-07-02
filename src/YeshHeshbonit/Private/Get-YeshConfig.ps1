function Get-YeshConfig {
    [CmdletBinding()]
    param(
        [string]$EnvPath,
        [string]$RatesPath
    )

    # Project root = three levels up from Private/ (Private -> YeshHeshbonit -> src -> root)
    $root = (Get-Item $PSScriptRoot).Parent.Parent.Parent.FullName
    if (-not $EnvPath) { $EnvPath = Join-Path $root '.env' }
    if (-not $RatesPath) { $RatesPath = Join-Path $root 'config\rates.json' }

    if (-not (Test-Path $EnvPath)) {
        throw "Missing .env file at '$EnvPath'. Run Initialize-YeshHeshbonit to set up (or copy .env.example to .env and fill in your yeshinvoice credentials)."
    }
    $envVars = @{}
    foreach ($line in Get-Content $EnvPath) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $key, $value = $line -split '=', 2
        $envVars[$key.Trim()] = $value.Trim()
    }
    foreach ($required in 'YESH_SECRET', 'YESH_USERKEY') {
        if ([string]::IsNullOrWhiteSpace($envVars[$required]) -or $envVars[$required] -like 'your-*') {
            throw "Missing or placeholder value for '$required' in .env."
        }
    }

    if (-not (Test-Path $RatesPath)) {
        throw "Missing rates file at '$RatesPath'. Run Initialize-YeshHeshbonit to set up (or copy config/rates.example.json to config/rates.json and set your mikdamotRate)."
    }
    try {
        $rates = Get-Content $RatesPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Rates file at '$RatesPath' is not valid JSON."
    }

    if ($null -eq $rates.vatRate -or $rates.vatRate -le 0 -or $rates.vatRate -ge 1) {
        throw "rates.json: 'vatRate' must be a number between 0 and 1 (e.g. 0.18)."
    }
    if ($null -eq $rates.mikdamotRate -or $rates.mikdamotRate -lt 0 -or $rates.mikdamotRate -ge 1) {
        throw "rates.json: 'mikdamotRate' must be a number between 0 and 1 (from your mas hachnasa assessment letter)."
    }
    foreach ($key in 'averageWageMonthly', 'reducedRateThreshold', 'reducedRate', 'fullRate') {
        if ($null -eq $rates.bituachLeumi.$key -or $rates.bituachLeumi.$key -le 0) {
            throw "rates.json: 'bituachLeumi.$key' must be a positive number."
        }
    }
    if (-not $rates.revenueDocTypes -or @($rates.revenueDocTypes).Count -eq 0) {
        throw "rates.json: 'revenueDocTypes' must be a non-empty array of DocumentType IDs."
    }
    if ($null -eq $rates.creditDocTypes) {
        throw "rates.json: 'creditDocTypes' must be an array (may be empty)."
    }
    if ($null -eq $rates.cancelledStatusIds) {
        throw "rates.json: 'cancelledStatusIds' must be an array (may be empty)."
    }

    [pscustomobject]@{
        Secret  = $envVars['YESH_SECRET']
        UserKey = $envVars['YESH_USERKEY']
        Rates   = $rates
    }
}
