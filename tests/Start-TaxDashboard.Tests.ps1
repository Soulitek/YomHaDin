BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Get-YeshConfig.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Public\Start-TaxDashboard.ps1')
}

Describe 'Start-TaxDashboard' {
    It 'fails closed with install instructions when Pode is missing' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -eq $true -and $Name -eq 'Pode' }
        { Start-TaxDashboard -NoBrowser } | Should -Throw '*Install-Module Pode*'
    }

    It 'fails closed at startup when config is invalid' {
        Mock Get-Module { [pscustomobject]@{ Name = 'Pode' } } -ParameterFilter { $ListAvailable -eq $true -and $Name -eq 'Pode' }
        Mock Get-YeshConfig { throw "Missing or placeholder value for 'YESH_SECRET' in .env." }
        { Start-TaxDashboard -NoBrowser } | Should -Throw '*YESH_SECRET*'
    }

    It 'fails closed when the web assets are missing' {
        Mock Get-Module { [pscustomobject]@{ Name = 'Pode' } } -ParameterFilter { $ListAvailable -eq $true -and $Name -eq 'Pode' }
        Mock Get-YeshConfig { [pscustomobject]@{ Secret = 's'; UserKey = 'u'; Rates = $null } }
        { Start-TaxDashboard -NoBrowser -WebRoot (Join-Path $TestDrive 'nope') } |
            Should -Throw '*Dashboard assets not found*'
    }

    It 'rejects out-of-range ports' {
        { Start-TaxDashboard -NoBrowser -Port 80 } | Should -Throw
    }
}
