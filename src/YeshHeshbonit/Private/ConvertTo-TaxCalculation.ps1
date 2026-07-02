function ConvertTo-TaxCalculation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Documents,
        [Parameter(Mandatory)][pscustomobject]$Rates,
        [ValidateRange(1, 120)][int]$MonthsInPeriod = 1
    )

    $noVatTypes = @(3, 4)

    $invoices = @(foreach ($doc in $Documents) {
        $sign = if (@($Rates.creditDocTypes) -contains [int]$doc.DocumentType) { -1 } else { 1 }
        $amount = [double]$doc.TotalPrice * $sign
        $vatType = if ([string]::IsNullOrWhiteSpace("$($doc.vattype)")) { 2 } else { [int]$doc.vattype }

        if ($vatType -eq 1) {
            # lifnei maam: TotalPrice excludes VAT
            $net = $amount
            $vat = $amount * $Rates.vatRate
        }
        elseif ($vatType -eq 2) {
            # kolel maam: TotalPrice includes VAT
            $net = $amount / (1 + $Rates.vatRate)
            $vat = $amount - $net
        }
        elseif ($noVatTypes -contains $vatType) {
            $net = $amount
            $vat = 0.0
        }
        else {
            throw "Unknown vattype '$vatType' on document $($doc.DocumentNumber) - refusing to guess a VAT treatment."
        }

        [pscustomobject]@{
            Date           = $doc.Date
            DocumentNumber = $doc.DocumentNumber
            DocumentType   = [int]$doc.DocumentType
            Customer       = $doc.CustomerName
            Gross          = $net + $vat
            Net            = $net
            Vat            = $vat
        }
    })

    $totalNet = [double](($invoices | Measure-Object -Property Net -Sum).Sum ?? 0)
    $totalVat = [double](($invoices | Measure-Object -Property Vat -Sum).Sum ?? 0)

    $bl = $Rates.bituachLeumi
    $threshold = [double]$bl.averageWageMonthly * [double]$bl.reducedRateThreshold
    $monthlyNet = $totalNet / $MonthsInPeriod
    $blMonthly =
        if ($monthlyNet -le 0) { 0.0 }
        elseif ($monthlyNet -le $threshold) { $monthlyNet * $bl.reducedRate }
        else { $threshold * $bl.reducedRate + ($monthlyNet - $threshold) * $bl.fullRate }

    [pscustomobject]@{
        Invoices = $invoices
        Totals   = [pscustomobject]@{
            Gross                = [math]::Round($totalNet + $totalVat, 2, [System.MidpointRounding]::AwayFromZero)
            Net                  = [math]::Round($totalNet, 2, [System.MidpointRounding]::AwayFromZero)
            Vat                  = [math]::Round($totalVat, 2, [System.MidpointRounding]::AwayFromZero)
            Mikdamot             = [math]::Round($totalNet * $Rates.mikdamotRate, 2, [System.MidpointRounding]::AwayFromZero)
            BituachLeumiEstimate = [math]::Round($blMonthly * $MonthsInPeriod, 2, [System.MidpointRounding]::AwayFromZero)
            MonthsInPeriod       = $MonthsInPeriod
        }
    }
}
