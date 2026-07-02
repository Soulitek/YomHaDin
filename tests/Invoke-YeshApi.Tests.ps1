BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Invoke-YeshApi.ps1')
    $script:config = [pscustomobject]@{ Secret = 'test-secret-value'; UserKey = 'test-user-key'; Rates = $null }
}

Describe 'Invoke-YeshApi' {
    It 'sends the JSON credential object in the Authorization header' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{ Success = $true; ErrorMessage = ''; ReturnValue = @() }
        } -ParameterFilter {
            $Headers.Authorization -eq '{"secret":"test-secret-value","userkey":"test-user-key"}'
        }
        Invoke-YeshApi -Endpoint 'api/v1/getvatTypes' -Body @{} -Config $config | Out-Null
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly
    }

    It 'fails closed when the API reports Success=false' {
        Mock Invoke-RestMethod { [pscustomobject]@{ Success = $false; ErrorMessage = 'invalid credentials' } }
        { Invoke-YeshApi -Endpoint 'api/v1/getInvoices' -Body @{} -Config $config } |
            Should -Throw '*invalid credentials*'
    }

    It 'sanitizes transport exceptions so credentials never leak' {
        Mock Invoke-RestMethod { throw "The format of value '{""secret"":""test-secret-value""}' is invalid." }
        $err = $null
        try { Invoke-YeshApi -Endpoint 'api/v1/getInvoices' -Body @{} -Config $config } catch { $err = $_ }
        $err | Should -Not -BeNullOrEmpty
        $err.Exception.Message | Should -Not -Match 'test-secret-value'
        $err.Exception.Message | Should -Match 'withheld'
    }

    It 'combines all pages when -Paginate is set' {
        $script:page = 0
        Mock Invoke-RestMethod {
            $script:page++
            if ($script:page -eq 1) {
                [pscustomobject]@{ Success = $true; ErrorMessage = ''; total = 3; ReturnValue = @(
                    [pscustomobject]@{ ID = 1 }, [pscustomobject]@{ ID = 2 }) }
            }
            else {
                [pscustomobject]@{ Success = $true; ErrorMessage = ''; total = 3; ReturnValue = @(
                    [pscustomobject]@{ ID = 3 }) }
            }
        }
        $result = Invoke-YeshApi -Endpoint 'api/v1/getInvoices' -Body @{ PageSize = 2 } -Config $config -Paginate
        $result.Count | Should -Be 3
        $result.ID | Should -Be @(1, 2, 3)
        Should -Invoke Invoke-RestMethod -Times 2 -Exactly
    }

    It 'fails closed if a page comes back empty before total is reached' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{ Success = $true; ErrorMessage = ''; total = 5; ReturnValue = @() }
        }
        { Invoke-YeshApi -Endpoint 'api/v1/getInvoices' -Body @{} -Config $config -Paginate } |
            Should -Throw '*partial*'
    }

    It 'returns an empty array for a zero-result paginated query' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{ Success = $true; ErrorMessage = ''; total = 0; ReturnValue = @() }
        }
        $result = Invoke-YeshApi -Endpoint 'api/v1/getInvoices' -Body @{} -Config $config -Paginate
        @($result).Count | Should -Be 0
    }
}
