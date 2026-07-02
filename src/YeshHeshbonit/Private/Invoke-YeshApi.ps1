function Invoke-YeshApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)][hashtable]$Body,
        [Parameter(Mandatory)][pscustomobject]$Config,
        [switch]$Paginate
    )

    # Ordered so the header is byte-stable and testable
    $auth = [ordered]@{ secret = $Config.Secret; userkey = $Config.UserKey } | ConvertTo-Json -Compress
    $headers = @{ Authorization = $auth }
    $uri = "https://api.yeshinvoice.co.il/$Endpoint"

    if (-not $Paginate) {
        return Invoke-YeshApiPage -Uri $uri -Headers $headers -Body $Body
    }

    $all = [System.Collections.Generic.List[object]]::new()
    $page = 1
    while ($true) {
        $pageBody = @{} + $Body
        $pageBody['PageNumber'] = $page
        $response = Invoke-YeshApiPage -Uri $uri -Headers $headers -Body $pageBody
        $items = if ($null -ne $response.ReturnValue) { @($response.ReturnValue) } else { @() }
        foreach ($item in $items) { $all.Add($item) }
        $totalProp = $response.PSObject.Properties['total']
        if ($null -eq $totalProp -or $null -eq $totalProp.Value -or -not ($totalProp.Value -as [int] -is [int])) {
            throw "yeshinvoice response is missing a numeric 'total' field. Aborting - refusing to calculate on possibly partial data."
        }
        $total = [int]$totalProp.Value
        if ($all.Count -ge $total) { break }
        if ($items.Count -eq 0) {
            throw "yeshinvoice returned $($all.Count) of $($total) documents and stopped. Aborting - refusing to calculate on partial data."
        }
        $page++
    }
    return $all.ToArray()
}

function Invoke-YeshApiPage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)][hashtable]$Body
    )
    try {
        # -SkipHeaderValidation is required: .NET rejects the JSON-shaped Authorization
        # value AND echoes it verbatim in the exception, which would leak credentials.
        $response = Invoke-RestMethod -Method Post -Uri $Uri -Headers $Headers `
            -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Compress) `
            -SkipHeaderValidation
    }
    catch {
        $status = 0
        try { $status = [int]$_.Exception.Response.StatusCode } catch { }
        throw "yeshinvoice API request to '$Uri' failed (HTTP $status). Details withheld to protect credentials."
    }
    if ($response.Success -ne $true) {
        throw "yeshinvoice API reported failure for '$Uri': $($response.ErrorMessage)"
    }
    return $response
}
