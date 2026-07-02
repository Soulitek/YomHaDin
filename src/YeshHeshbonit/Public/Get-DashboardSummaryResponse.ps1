function Get-DashboardSummaryResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Query
    )

    try {
        $splat = Resolve-DashboardPeriodParam -Query $Query
    }
    catch {
        return @{ StatusCode = 400; Body = @{ error = $_.Exception.Message } }
    }

    try {
        $data = Get-TaxPeriodSummary @splat
    }
    catch {
        return @{ StatusCode = 502; Body = @{ error = $_.Exception.Message } }
    }

    $round = { param($v) [math]::Round($v, 2, [System.MidpointRounding]::AwayFromZero) }
    @{
        StatusCode = 200
        Body       = @{
            period   = @{
                from   = $data.From.ToString('yyyy-MM-dd')
                to     = $data.To.ToString('yyyy-MM-dd')
                months = $data.Months
            }
            invoices = @($data.Invoices | ForEach-Object {
                @{
                    date           = $_.Date
                    documentNumber = $_.DocumentNumber
                    customer       = $_.Customer
                    gross          = & $round $_.Gross
                    net            = & $round $_.Net
                    vat            = & $round $_.Vat
                }
            })
            totals   = @{
                gross                = $data.Totals.Gross
                net                  = $data.Totals.Net
                vat                  = $data.Totals.Vat
                mikdamot             = $data.Totals.Mikdamot
                bituachLeumiEstimate = $data.Totals.BituachLeumiEstimate
                months               = $data.Totals.MonthsInPeriod
            }
        }
    }
}
