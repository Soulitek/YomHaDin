function Get-TaxPeriodSummary {
    [CmdletBinding(DefaultParameterSetName = 'Month')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Month')]
        [ValidatePattern('^\d{4}-(0[1-9]|1[0-2])$')]
        [string]$Month,

        [Parameter(Mandatory, ParameterSetName = 'Range')][datetime]$From,
        [Parameter(Mandatory, ParameterSetName = 'Range')][datetime]$To
    )

    if ($PSCmdlet.ParameterSetName -eq 'Month') {
        $From = [datetime]::ParseExact("$Month-01", 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
        $To = $From.AddMonths(1).AddMinutes(-1)
    }
    if ($PSCmdlet.ParameterSetName -eq 'Range' -and $To.TimeOfDay -eq [timespan]::Zero) {
        # A date-only -To means "through the end of that day"
        $To = $To.Date.AddDays(1).AddMinutes(-1)
    }
    if ($To -lt $From) {
        throw "Invalid range: -To ($($To.ToString('yyyy-MM-dd'))) is earlier than -From ($($From.ToString('yyyy-MM-dd')))."
    }
    $months = (($To.Year - $From.Year) * 12) + $To.Month - $From.Month + 1

    $config = Get-YeshConfig
    $docs = @(Get-YeshInvoice -From $From -To $To -Config $config)
    $calc = ConvertTo-TaxCalculation -Documents $docs -Rates $config.Rates -MonthsInPeriod $months

    [pscustomobject]@{
        From     = $From
        To       = $To
        Months   = $months
        Invoices = $calc.Invoices
        Totals   = $calc.Totals
    }
}
