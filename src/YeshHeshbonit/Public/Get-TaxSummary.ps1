function Get-TaxSummary {
    [CmdletBinding(DefaultParameterSetName = 'Month')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Month')]
        [ValidatePattern('^\d{4}-(0[1-9]|1[0-2])$')]
        [string]$Month,

        [Parameter(Mandatory, ParameterSetName = 'Range')][datetime]$From,
        [Parameter(Mandatory, ParameterSetName = 'Range')][datetime]$To,

        [string]$ExportCsv,
        [switch]$PassThru
    )

    $data = if ($PSCmdlet.ParameterSetName -eq 'Month') {
        Get-TaxPeriodSummary -Month $Month
    }
    else {
        Get-TaxPeriodSummary -From $From -To $To
    }
    $summary = [pscustomobject]@{ Invoices = $data.Invoices; Totals = $data.Totals }

    if (@($summary.Invoices).Count -gt 0) {
        $table = $summary.Invoices | Select-Object Date, DocumentNumber, Customer,
            @{ n = 'Gross'; e = { [math]::Round($_.Gross, 2, [System.MidpointRounding]::AwayFromZero) } },
            @{ n = 'Net'; e = { [math]::Round($_.Net, 2, [System.MidpointRounding]::AwayFromZero) } },
            @{ n = 'Vat'; e = { [math]::Round($_.Vat, 2, [System.MidpointRounding]::AwayFromZero) } } |
            Format-Table -AutoSize | Out-String
        Write-Host $table
    }
    else {
        Write-Host 'No revenue documents found in the period.'
    }

    $t = $summary.Totals
    Write-Host ("Period: {0:yyyy-MM-dd} to {1:yyyy-MM-dd} ({2} month(s))" -f $data.From, $data.To, $data.Months)
    Write-Host ("  Gross revenue:                 {0,12:N2}" -f $t.Gross)
    Write-Host ("  Net (pre-VAT):                 {0,12:N2}" -f $t.Net)
    Write-Host ("  Set aside - VAT:               {0,12:N2}" -f $t.Vat)
    Write-Host ("  Set aside - Mikdamot:          {0,12:N2}" -f $t.Mikdamot)
    Write-Host ("  Set aside - Bituach Leumi:     {0,12:N2}  (ESTIMATE)" -f $t.BituachLeumiEstimate)
    Write-Host '  NOTE: Bituach Leumi advances are officially based on your projected annual'
    Write-Host '  income assessment; this figure is a set-aside estimate, not your actual mikdama.'

    if ($ExportCsv) {
        Export-TaxSummary -Summary $summary -Path $ExportCsv | Out-Null
        Write-Host "Exported to $ExportCsv"
    }
    if ($PassThru) { return $summary }
}
