function Get-YeshInvoice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][datetime]$From,
        [Parameter(Mandatory)][datetime]$To,
        [pscustomobject]$Config
    )

    if ($To -lt $From) {
        throw "Invalid range: -To ($($To.ToString('yyyy-MM-dd'))) is earlier than -From ($($From.ToString('yyyy-MM-dd')))."
    }
    if (-not $Config) { $Config = Get-YeshConfig }

    $body = @{
        from     = $From.ToString('yyyy-MM-dd HH:mm')
        to       = $To.ToString('yyyy-MM-dd HH:mm')
        PageSize = 100
        Search   = ''
    }
    $docs = Invoke-YeshApi -Endpoint 'api/v1/getInvoices' -Body $body -Config $Config -Paginate

    $wantedTypes = @($Config.Rates.revenueDocTypes) + @($Config.Rates.creditDocTypes)
    $cancelled = @($Config.Rates.cancelledStatusIds)

    @(foreach ($doc in $docs) {
        if ($wantedTypes -notcontains [int]$doc.DocumentType) { continue }
        if ($cancelled -contains [int]$doc.StatusID) { continue }
        if ([int]$doc.StatusID -ne 1) {
            Write-Warning "Document $($doc.DocumentNumber) has unrecognized StatusID $($doc.StatusID) - included in totals. Verify it is not cancelled, then add the ID to cancelledStatusIds in rates.json if it is."
        }
        $doc
    })
}
