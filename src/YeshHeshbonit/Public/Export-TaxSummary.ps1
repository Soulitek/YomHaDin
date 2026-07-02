function Export-TaxSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Summary,
        [Parameter(Mandatory)][string]$Path
    )

    function New-Row {
        param($Type, $Date = '', $DocumentNumber = '', $Customer = '', $Gross = '', $Net = '', $Vat = '', $Amount = '')
        [pscustomobject]@{
            Type = $Type; Date = $Date; DocumentNumber = $DocumentNumber; Customer = $Customer
            Gross = $Gross; Net = $Net; Vat = $Vat; Amount = $Amount
        }
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($inv in @($Summary.Invoices)) {
        $rows.Add((New-Row -Type 'Invoice' -Date $inv.Date -DocumentNumber $inv.DocumentNumber `
            -Customer $inv.Customer -Gross ([math]::Round($inv.Gross, 2)) `
            -Net ([math]::Round($inv.Net, 2)) -Vat ([math]::Round($inv.Vat, 2))))
    }
    $t = $Summary.Totals
    $rows.Add((New-Row -Type 'Total' -Gross $t.Gross -Net $t.Net -Vat $t.Vat))
    $rows.Add((New-Row -Type 'SetAside-VAT' -Amount $t.Vat))
    $rows.Add((New-Row -Type 'SetAside-Mikdamot' -Amount $t.Mikdamot))
    $rows.Add((New-Row -Type 'SetAside-BituachLeumi-Estimate' -Amount $t.BituachLeumiEstimate))

    $rows | Export-Csv -Path $Path -Encoding utf8BOM -NoTypeInformation
    Get-Item $Path
}
