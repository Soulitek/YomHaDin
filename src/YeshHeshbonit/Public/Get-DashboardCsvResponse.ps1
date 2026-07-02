function Get-DashboardCsvResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Query
    )

    try {
        $splat = Resolve-DashboardPeriodParam -Query $Query
    }
    catch {
        return @{ StatusCode = 400; Error = $_.Exception.Message }
    }

    try {
        $data = Get-TaxPeriodSummary @splat
        $summary = [pscustomobject]@{ Invoices = $data.Invoices; Totals = $data.Totals }
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("yesh-{0}.csv" -f [guid]::NewGuid())
        try {
            $null = Export-TaxSummary -Summary $summary -Path $tmp
            $bytes = [System.IO.File]::ReadAllBytes($tmp)
        }
        finally {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
        return @{
            StatusCode = 200
            Bytes      = $bytes
            FileName   = 'tax-summary-{0}_{1}.csv' -f $data.From.ToString('yyyy-MM-dd'), $data.To.ToString('yyyy-MM-dd')
        }
    }
    catch {
        return @{ StatusCode = 502; Error = $_.Exception.Message }
    }
}
