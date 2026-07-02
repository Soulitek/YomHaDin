function Start-TaxDashboard {
    [CmdletBinding()]
    param(
        [ValidateRange(1024, 65535)][int]$Port = 8321,
        [switch]$NoBrowser,
        [string]$WebRoot
    )

    if (-not (Get-Module -ListAvailable -Name Pode)) {
        throw "The Pode module is required for the dashboard. Install it with: Install-Module Pode -Scope CurrentUser"
    }

    # Fail closed on bad config at startup, not at the first request
    $null = Get-YeshConfig

    if (-not $WebRoot) {
        # Public -> YeshHeshbonit -> src -> project root
        $WebRoot = Join-Path (Get-Item $PSScriptRoot).Parent.Parent.Parent.FullName 'web\public'
    }
    if (-not (Test-Path (Join-Path $WebRoot 'index.html'))) {
        throw "Dashboard assets not found at '$WebRoot'."
    }

    $modulePsd1 = Join-Path (Get-Item $PSScriptRoot).Parent.FullName 'YeshHeshbonit.psd1'
    $url = "http://127.0.0.1:$Port"

    Write-Host "Tax dashboard running at $url  (Ctrl+C to stop)"
    if (-not $NoBrowser) { Start-Process $url }

    # GetNewClosure captures $Port/$WebRoot/$modulePsd1 for the server setup block
    Start-PodeServer -ScriptBlock ({
        Add-PodeEndpoint -Address 127.0.0.1 -Port $Port -Protocol Http

        # Route script blocks run in Pode runspaces: they can only call functions
        # exported by modules imported here.
        Import-PodeModule -Path $modulePsd1

        Add-PodeStaticRoute -Path '/' -Source $WebRoot -Defaults @('index.html')

        Add-PodeRoute -Method Get -Path '/api/summary' -ScriptBlock {
            try {
                $r = Get-DashboardSummaryResponse -Query ([hashtable]$WebEvent.Query)
                Write-PodeJsonResponse -Value $r.Body -StatusCode $r.StatusCode -Depth 6
            }
            catch {
                Write-PodeJsonResponse -Value @{ error = 'Internal error' } -StatusCode 500
            }
        }

        Add-PodeRoute -Method Get -Path '/api/summary/csv' -ScriptBlock {
            try {
                $r = Get-DashboardCsvResponse -Query ([hashtable]$WebEvent.Query)
                if ($r.StatusCode -ne 200) {
                    Write-PodeJsonResponse -Value @{ error = $r.Error } -StatusCode $r.StatusCode
                    return
                }
                Add-PodeHeader -Name 'Content-Disposition' -Value ('attachment; filename="{0}"' -f $r.FileName)
                Write-PodeTextResponse -Bytes $r.Bytes -ContentType 'text/csv; charset=utf-8'
            }
            catch {
                Write-PodeJsonResponse -Value @{ error = 'Internal error' } -StatusCode 500
            }
        }
    }).GetNewClosure()
}
