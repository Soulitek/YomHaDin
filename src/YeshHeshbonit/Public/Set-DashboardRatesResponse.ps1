function Set-DashboardRatesResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Body,
        [string]$RatesPath,
        [string]$EnvPath
    )

    # Pode delivers JSON bodies as PSCustomObject; tests use hashtables; both accepted
    if ($Body -is [pscustomobject]) {
        $converted = @{}
        foreach ($p in $Body.PSObject.Properties) { $converted[$p.Name] = $p.Value }
        $Body = $converted
    }
    if ($Body -isnot [hashtable]) { $Body = @{} }

    $extraKeys = @($Body.Keys | Where-Object { $_ -ne 'mikdamotRate' })
    if ($extraKeys.Count -gt 0) {
        return @{ StatusCode = 400; Body = @{ error = "Only 'mikdamotRate' can be changed. Unexpected: $($extraKeys -join ', ')." } }
    }
    if (-not $Body.ContainsKey('mikdamotRate')) {
        return @{ StatusCode = 400; Body = @{ error = "Missing 'mikdamotRate'." } }
    }
    $value = $Body['mikdamotRate']
    if ($value -is [bool]) {
        return @{ StatusCode = 400; Body = @{ error = "'mikdamotRate' must be a number (fraction, e.g. 0.08)." } }
    }
    if ($value -isnot [int] -and $value -isnot [long] -and $value -isnot [double] -and $value -isnot [decimal]) {
        return @{ StatusCode = 400; Body = @{ error = "'mikdamotRate' must be a number (fraction, e.g. 0.08)." } }
    }
    $rate = [double]$value
    if ($rate -lt 0 -or $rate -ge 1) {
        return @{ StatusCode = 400; Body = @{ error = "'mikdamotRate' must be between 0 and 1 (fraction, e.g. 0.08)." } }
    }

    if (-not $RatesPath) {
        # Public -> YeshHeshbonit -> src -> project root
        $RatesPath = Join-Path (Get-Item $PSScriptRoot).Parent.Parent.Parent.FullName 'config\rates.json'
    }

    $tmp = "$RatesPath.$([guid]::NewGuid()).tmp"
    try {
        $rates = Get-Content $RatesPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $rates.mikdamotRate = $rate
        $rates | ConvertTo-Json -Depth 5 | Set-Content -Path $tmp -Encoding utf8

        # Full schema validation of the candidate before it replaces the real file
        $validateArgs = @{ RatesPath = $tmp }
        if ($EnvPath) { $validateArgs.EnvPath = $EnvPath }
        $null = Get-YeshConfig @validateArgs

        Move-Item -Path $tmp -Destination $RatesPath -Force
        return @{ StatusCode = 200; Body = @{ mikdamotRate = $rate } }
    }
    catch {
        return @{ StatusCode = 502; Body = @{ error = $_.Exception.Message } }
    }
    finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}
