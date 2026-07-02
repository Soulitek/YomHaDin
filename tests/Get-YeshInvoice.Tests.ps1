BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Invoke-YeshApi.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Public\Get-YeshInvoice.ps1')

    $script:config = [pscustomobject]@{
        Secret = 's'; UserKey = 'u'
        Rates  = [pscustomobject]@{
            revenueDocTypes = @(8, 9); creditDocTypes = @(10); cancelledStatusIds = @(2)
        }
    }

    function New-ApiDoc {
        param($Type, $Status = 1, $Number = '1001')
        [pscustomobject]@{
            DocumentType = $Type; StatusID = $Status; DocumentNumber = $Number
            TotalPrice = 100; vattype = ''; Date = '01-06-2026'; CustomerName = 'A'
        }
    }
}

Describe 'Get-YeshInvoice' {
    It 'keeps revenue and credit types, drops receipts and quotes' {
        Mock Invoke-YeshApi {
            @((New-ApiDoc 8), (New-ApiDoc 9), (New-ApiDoc 10), (New-ApiDoc 6), (New-ApiDoc 1))
        }
        $docs = Get-YeshInvoice -From '2026-06-01' -To '2026-06-30' -Config $config
        $docs.Count | Should -Be 3
        $docs.DocumentType | Should -Be @(8, 9, 10)
    }

    It 'excludes cancelled documents' {
        Mock Invoke-YeshApi { @((New-ApiDoc 8 -Status 1), (New-ApiDoc 8 -Status 2 -Number '1002')) }
        $docs = Get-YeshInvoice -From '2026-06-01' -To '2026-06-30' -Config $config
        $docs.Count | Should -Be 1
        $docs[0].DocumentNumber | Should -Be '1001'
    }

    It 'warns on an unrecognized StatusID but includes the document' {
        Mock Invoke-YeshApi { @(New-ApiDoc 8 -Status 7) }
        $warnings = @()
        $docs = Get-YeshInvoice -From '2026-06-01' -To '2026-06-30' -Config $config -WarningVariable warnings -WarningAction SilentlyContinue
        $docs.Count | Should -Be 1
        $warnings.Count | Should -Be 1
        "$($warnings[0])" | Should -Match 'StatusID 7'
    }

    It 'rejects a range where To is before From' {
        { Get-YeshInvoice -From '2026-06-30' -To '2026-06-01' -Config $config } |
            Should -Throw '*earlier than*'
    }

    It 'requests the API with the documented date format and pagination' {
        Mock Invoke-YeshApi { throw 'unmocked Invoke-YeshApi call - request shape regression' }
        Mock Invoke-YeshApi { @() } -ParameterFilter {
            $Endpoint -eq 'api/v1/getInvoices' -and
            $Body.from -eq '2026-06-01 00:00' -and
            $Body.to -eq '2026-06-30 23:59' -and
            $Body.PageSize -eq 100 -and
            $Paginate -eq $true
        }
        Get-YeshInvoice -From '2026-06-01 00:00' -To '2026-06-30 23:59' -Config $config | Out-Null
        Should -Invoke Invoke-YeshApi -Times 1 -Exactly
    }
}
