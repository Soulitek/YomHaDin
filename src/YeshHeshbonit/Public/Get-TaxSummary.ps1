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

    if ($PSCmdlet.ParameterSetName -eq 'Month') {
        $From = [datetime]::ParseExact("$Month-01", 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
        $To = $From.AddMonths(1).AddMinutes(-1)
    }
    if ($To -lt $From) {
        throw "Invalid range: -To ($($To.ToString('yyyy-MM-dd'))) is earlier than -From ($($From.ToString('yyyy-MM-dd')))."
    }
    $months = (($To.Year - $From.Year) * 12) + $To.Month - $From.Month + 1

    $config = Get-YeshConfig
    $docs = @(Get-YeshInvoice -From $From -To $To -Config $config)
    $summary = ConvertTo-TaxCalculation -Documents $docs -Rates $config.Rates -MonthsInPeriod $months

    if (@($summary.Invoices).Count -gt 0) {
        $table = $summary.Invoices | Select-Object Date, DocumentNumber, Customer,
            @{ n = 'Gross'; e = { [math]::Round($_.Gross, 2) } },
            @{ n = 'Net'; e = { [math]::Round($_.Net, 2) } },
            @{ n = 'Vat'; e = { [math]::Round($_.Vat, 2) } } |
            Format-Table -AutoSize | Out-String
        Write-Host $table
    }
    else {
        Write-Host 'No revenue documents found in the period.'
    }

    $t = $summary.Totals
    Write-Host ("Period: {0:yyyy-MM-dd} to {1:yyyy-MM-dd} ({2} month(s))" -f $From, $To, $months)
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
