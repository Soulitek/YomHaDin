function Resolve-DashboardPeriodParam {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Query
    )

    foreach ($key in 'month', 'from', 'to') {
        if ($Query[$key] -is [array]) {
            throw "Invalid '$key': multiple values not allowed."
        }
    }

    $month = "$($Query['month'])"
    $from = "$($Query['from'])"
    $to = "$($Query['to'])"

    if ($month -and ($from -or $to)) {
        throw "Specify either 'month' or 'from'+'to', not both."
    }
    if ($month) {
        if ($month -notmatch '^\d{4}-(0[1-9]|1[0-2])$') {
            throw "Invalid 'month' format '$month'. Expected yyyy-MM."
        }
        return @{ Month = $month }
    }
    if ($from -and $to) {
        $f = [datetime]::MinValue
        $t = [datetime]::MinValue
        $styles = [System.Globalization.DateTimeStyles]::None
        $culture = [cultureinfo]::InvariantCulture
        if (-not [datetime]::TryParseExact($from, 'yyyy-MM-dd', $culture, $styles, [ref]$f)) {
            throw "Invalid 'from' date '$from'. Expected yyyy-MM-dd."
        }
        if (-not [datetime]::TryParseExact($to, 'yyyy-MM-dd', $culture, $styles, [ref]$t)) {
            throw "Invalid 'to' date '$to'. Expected yyyy-MM-dd."
        }
        if ($f -gt $t) {
            throw "Invalid range: 'to' ($to) is earlier than 'from' ($from)."
        }
        return @{ From = $f; To = $t }
    }
    throw "Missing period: provide 'month' or 'from'+'to'."
}
