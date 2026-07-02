BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Resolve-DashboardPeriodParam.ps1')
}

Describe 'Resolve-DashboardPeriodParam' {
    It 'returns a Month splat for a valid month param' {
        $r = Resolve-DashboardPeriodParam -Query @{ month = '2026-06' }
        $r.Month | Should -Be '2026-06'
        $r.Keys.Count | Should -Be 1
    }

    It 'returns a From/To splat for valid from+to params' {
        $r = Resolve-DashboardPeriodParam -Query @{ from = '2026-05-01'; to = '2026-06-30' }
        $r.From | Should -Be ([datetime]'2026-05-01')
        $r.To | Should -Be ([datetime]'2026-06-30')
    }

    It 'rejects month combined with from/to' {
        { Resolve-DashboardPeriodParam -Query @{ month = '2026-06'; from = '2026-05-01' } } |
            Should -Throw '*not both*'
    }

    It 'rejects an empty query' {
        { Resolve-DashboardPeriodParam -Query @{} } | Should -Throw '*Missing period*'
    }

    It 'rejects from without to' {
        { Resolve-DashboardPeriodParam -Query @{ from = '2026-05-01' } } | Should -Throw '*Missing period*'
    }

    It 'rejects to without from' {
        { Resolve-DashboardPeriodParam -Query @{ to = '2026-06-30' } } | Should -Throw '*Missing period*'
    }

    It 'rejects array-valued query params' {
        { Resolve-DashboardPeriodParam -Query @{ month = @('2026-06', '2026-07') } } |
            Should -Throw '*multiple values not allowed*'
    }

    It 'rejects a malformed month' {
        { Resolve-DashboardPeriodParam -Query @{ month = '2026-13' } } | Should -Throw "*Invalid 'month'*"
        { Resolve-DashboardPeriodParam -Query @{ month = 'June' } } | Should -Throw "*Invalid 'month'*"
    }

    It 'rejects malformed dates' {
        { Resolve-DashboardPeriodParam -Query @{ from = '01/05/2026'; to = '2026-06-30' } } |
            Should -Throw "*Invalid 'from'*"
        { Resolve-DashboardPeriodParam -Query @{ from = '2026-05-01'; to = 'soon' } } |
            Should -Throw "*Invalid 'to'*"
    }

    It 'rejects an inverted range as a validation error' {
        { Resolve-DashboardPeriodParam -Query @{ from = '2026-06-30'; to = '2026-06-01' } } |
            Should -Throw '*earlier than*'
    }
}
