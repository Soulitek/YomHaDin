function Get-DashboardRatesResponse {
    [CmdletBinding()]
    param(
        [string]$RatesPath,
        [string]$EnvPath
    )

    try {
        $configArgs = @{}
        if ($RatesPath) { $configArgs.RatesPath = $RatesPath }
        if ($EnvPath) { $configArgs.EnvPath = $EnvPath }
        $config = Get-YeshConfig @configArgs
        return @{ StatusCode = 200; Body = @{ mikdamotRate = [double]$config.Rates.mikdamotRate } }
    }
    catch {
        return @{ StatusCode = 502; Body = @{ error = $_.Exception.Message } }
    }
}
