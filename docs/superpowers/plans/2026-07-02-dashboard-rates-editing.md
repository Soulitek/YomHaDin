# Dashboard Rates Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** View and edit the מקדמות rate (`mikdamotRate` only) from the web dashboard, persisted atomically to `config/rates.json`.

**Architecture:** Two new Public handler functions (`Get-DashboardRatesResponse`, `Set-DashboardRatesResponse`) following the existing handler-as-data pattern; two new Pode routes; a settings line in the frontend. Persistence is temp-file + full-schema validation via `Get-YeshConfig` + atomic `Move-Item`. Spec: `docs/superpowers/specs/2026-07-02-dashboard-rates-editing-design.md`. Work on branch `feature/tax-dashboard`.

**Tech Stack:** PowerShell 7+, Pester 5, Pode, vanilla JS.

## Global Constraints

- PowerShell 7.0+; Pester 5; no logging; tests never call the live API or start a server
- POST allowlist: ONLY `mikdamotRate` may be changed; any other body key → 400
- `mikdamotRate` is a fraction: numeric, `0 ≤ x < 1`; anything else → 400, file untouched
- Persistence must be atomic and validated: write temp next to target → validate temp via `Get-YeshConfig -RatesPath <temp>` → `Move-Item -Force`; original file untouched on any failure; no temp files left behind
- Error mapping (same as existing routes): validation → 400 `{error}`; read/write/schema failure → 502 `{error}`; route catch-all → 500 `{error:'Internal error'}`
- Handlers are Public (Pode runspace rule); `-RatesPath`/`-EnvPath` params exist for tests only — routes never pass user input into them
- Frontend: percent in the UI, fraction on the wire and in the file; `textContent` only, never innerHTML; on successful save re-fetch the current period
- Existing 80 tests stay green
- Commit after every task with the trailer: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: Rates handlers (Public) + manifest update

**Files:**
- Create: `src/YeshHeshbonit/Public/Get-DashboardRatesResponse.ps1`
- Create: `src/YeshHeshbonit/Public/Set-DashboardRatesResponse.ps1`
- Modify: `src/YeshHeshbonit/YeshHeshbonit.psd1` (FunctionsToExport)
- Modify: `tests/Module.Tests.ps1` (export-list assertion)
- Test: `tests/DashboardRates.Tests.ps1`

**Interfaces:**
- Consumes: `Get-YeshConfig [-EnvPath <string>] [-RatesPath <string>]` → `{Secret, UserKey, Rates}` (throws with precise message on any invalid file — this is the validator for candidate files too)
- Produces (Task 2 routes call exactly these):
  - `Get-DashboardRatesResponse [-RatesPath <string>] [-EnvPath <string>]` → `@{StatusCode=200; Body=@{mikdamotRate=<double>}}` or `@{StatusCode=502; Body=@{error}}`
  - `Set-DashboardRatesResponse -Body <object> [-RatesPath <string>] [-EnvPath <string>]` → `@{StatusCode=200; Body=@{mikdamotRate=<double>}}` | 400 | 502 (Body always `@{...}`)

- [ ] **Step 1: Write the failing tests**

`tests/DashboardRates.Tests.ps1`:

```powershell
BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Private\Get-YeshConfig.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Public\Get-DashboardRatesResponse.ps1')
    . (Join-Path $PSScriptRoot '..\src\YeshHeshbonit\Public\Set-DashboardRatesResponse.ps1')

    $script:goodRatesJson = @'
{
  "vatRate": 0.18,
  "mikdamotRate": 0.08,
  "bituachLeumi": { "averageWageMonthly": 13769, "reducedRateThreshold": 0.60, "reducedRate": 0.0597, "fullRate": 0.1783 },
  "revenueDocTypes": [8, 9],
  "creditDocTypes": [10],
  "cancelledStatusIds": []
}
'@
    $script:goodEnv = "YESH_SECRET=abc-123`nYESH_USERKEY=key-456`n"
}

Describe 'Get-DashboardRatesResponse' {
    BeforeEach {
        $script:envPath = Join-Path $TestDrive '.env'
        $script:ratesPath = Join-Path $TestDrive 'rates.json'
        Set-Content -Path $envPath -Value $goodEnv -NoNewline
        Set-Content -Path $ratesPath -Value $goodRatesJson -NoNewline
    }

    It 'returns the current rate' {
        $r = Get-DashboardRatesResponse -RatesPath $ratesPath -EnvPath $envPath
        $r.StatusCode | Should -Be 200
        $r.Body.mikdamotRate | Should -Be 0.08
    }

    It 'returns 502 for a broken rates file' {
        Set-Content -Path $ratesPath -Value '{ not json'
        $r = Get-DashboardRatesResponse -RatesPath $ratesPath -EnvPath $envPath
        $r.StatusCode | Should -Be 502
        $r.Body.error | Should -Not -BeNullOrEmpty
    }
}

Describe 'Set-DashboardRatesResponse' {
    BeforeEach {
        $script:envPath = Join-Path $TestDrive '.env'
        $script:ratesPath = Join-Path $TestDrive 'rates.json'
        Set-Content -Path $envPath -Value $goodEnv -NoNewline
        Set-Content -Path $ratesPath -Value $goodRatesJson -NoNewline
    }

    It 'updates the rate and preserves every other key' {
        $r = Set-DashboardRatesResponse -Body @{ mikdamotRate = 0.1 } -RatesPath $ratesPath -EnvPath $envPath
        $r.StatusCode | Should -Be 200
        $r.Body.mikdamotRate | Should -Be 0.1
        $after = Get-Content $ratesPath -Raw | ConvertFrom-Json
        $after.mikdamotRate | Should -Be 0.1
        $after.vatRate | Should -Be 0.18
        @($after.revenueDocTypes) | Should -Be @(8, 9)
        @($after.creditDocTypes) | Should -Be @(10)
        $after.bituachLeumi.averageWageMonthly | Should -Be 13769
    }

    It 'accepts a PSCustomObject body (Pode JSON parse shape)' {
        $r = Set-DashboardRatesResponse -Body ([pscustomobject]@{ mikdamotRate = 0.09 }) -RatesPath $ratesPath -EnvPath $envPath
        $r.StatusCode | Should -Be 200
        (Get-Content $ratesPath -Raw | ConvertFrom-Json).mikdamotRate | Should -Be 0.09
    }

    It 'rejects out-of-range values and leaves the file untouched' {
        $before = Get-Content $ratesPath -Raw
        foreach ($bad in -0.1, 1, 1.5) {
            $r = Set-DashboardRatesResponse -Body @{ mikdamotRate = $bad } -RatesPath $ratesPath -EnvPath $envPath
            $r.StatusCode | Should -Be 400
        }
        Get-Content $ratesPath -Raw | Should -Be $before
    }

    It 'rejects a non-numeric value' {
        $r = Set-DashboardRatesResponse -Body @{ mikdamotRate = 'abc' } -RatesPath $ratesPath -EnvPath $envPath
        $r.StatusCode | Should -Be 400
        $r.Body.error | Should -Match 'number'
    }

    It 'rejects a missing mikdamotRate key' {
        $r = Set-DashboardRatesResponse -Body @{} -RatesPath $ratesPath -EnvPath $envPath
        $r.StatusCode | Should -Be 400
        $r.Body.error | Should -Match 'Missing'
    }

    It 'rejects a null body' {
        $r = Set-DashboardRatesResponse -Body $null -RatesPath $ratesPath -EnvPath $envPath
        $r.StatusCode | Should -Be 400
    }

    It 'rejects extra keys and leaves the file untouched' {
        $before = Get-Content $ratesPath -Raw
        $r = Set-DashboardRatesResponse -Body @{ mikdamotRate = 0.1; vatRate = 0.5 } -RatesPath $ratesPath -EnvPath $envPath
        $r.StatusCode | Should -Be 400
        $r.Body.error | Should -Match 'Only'
        Get-Content $ratesPath -Raw | Should -Be $before
    }

    It 'returns 502 when the rates file is unreadable' {
        Remove-Item $ratesPath
        $r = Set-DashboardRatesResponse -Body @{ mikdamotRate = 0.1 } -RatesPath $ratesPath -EnvPath $envPath
        $r.StatusCode | Should -Be 502
    }

    It 'keeps the original intact when candidate validation fails' {
        # Validation of the candidate runs through Get-YeshConfig with this EnvPath;
        # a nonexistent env makes validation throw AFTER the temp is written.
        $before = Get-Content $ratesPath -Raw
        $r = Set-DashboardRatesResponse -Body @{ mikdamotRate = 0.1 } -RatesPath $ratesPath -EnvPath (Join-Path $TestDrive 'no.env')
        $r.StatusCode | Should -Be 502
        Get-Content $ratesPath -Raw | Should -Be $before
    }

    It 'leaves no temp files behind' {
        $null = Set-DashboardRatesResponse -Body @{ mikdamotRate = 0.1 } -RatesPath $ratesPath -EnvPath $envPath
        $null = Set-DashboardRatesResponse -Body @{ mikdamotRate = 5 } -RatesPath $ratesPath -EnvPath $envPath
        @(Get-ChildItem $TestDrive -Filter '*.tmp').Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester .\tests\DashboardRates.Tests.ps1 -Output Detailed`
Expected: FAIL — handler files do not exist.

- [ ] **Step 3: Write the implementations**

`src/YeshHeshbonit/Public/Get-DashboardRatesResponse.ps1`:

```powershell
function Get-DashboardRatesResponse {
    [CmdletBinding()]
    param(
        [string]$RatesPath,
        [string]$EnvPath
    )

    try {
        $configArgs = @{}
        if ($RatesPath) { $configArgs.RatesPath = $RatesPath }
        if ($EnvPath) { $configArgs.EnvPath = $EnvPath }
        $config = Get-YeshConfig @configArgs
        return @{ StatusCode = 200; Body = @{ mikdamotRate = [double]$config.Rates.mikdamotRate } }
    }
    catch {
        return @{ StatusCode = 502; Body = @{ error = $_.Exception.Message } }
    }
}
```

`src/YeshHeshbonit/Public/Set-DashboardRatesResponse.ps1`:

```powershell
function Set-DashboardRatesResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Body,
        [string]$RatesPath,
        [string]$EnvPath
    )

    # Pode delivers JSON bodies as PSCustomObject; tests use hashtables; both accepted
    if ($Body -is [pscustomobject]) {
        $converted = @{}
        foreach ($p in $Body.PSObject.Properties) { $converted[$p.Name] = $p.Value }
        $Body = $converted
    }
    if ($Body -isnot [hashtable]) { $Body = @{} }

    $extraKeys = @($Body.Keys | Where-Object { $_ -ne 'mikdamotRate' })
    if ($extraKeys.Count -gt 0) {
        return @{ StatusCode = 400; Body = @{ error = "Only 'mikdamotRate' can be changed. Unexpected: $($extraKeys -join ', ')." } }
    }
    if (-not $Body.ContainsKey('mikdamotRate')) {
        return @{ StatusCode = 400; Body = @{ error = "Missing 'mikdamotRate'." } }
    }
    $value = $Body['mikdamotRate']
    if ($value -isnot [int] -and $value -isnot [long] -and $value -isnot [double] -and $value -isnot [decimal]) {
        return @{ StatusCode = 400; Body = @{ error = "'mikdamotRate' must be a number (fraction, e.g. 0.08)." } }
    }
    $rate = [double]$value
    if ($rate -lt 0 -or $rate -ge 1) {
        return @{ StatusCode = 400; Body = @{ error = "'mikdamotRate' must be between 0 and 1 (fraction, e.g. 0.08)." } }
    }

    if (-not $RatesPath) {
        # Public -> YeshHeshbonit -> src -> project root
        $RatesPath = Join-Path (Get-Item $PSScriptRoot).Parent.Parent.Parent.FullName 'config\rates.json'
    }

    $tmp = "$RatesPath.$([guid]::NewGuid()).tmp"
    try {
        $rates = Get-Content $RatesPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $rates.mikdamotRate = $rate
        $rates | ConvertTo-Json -Depth 5 | Set-Content -Path $tmp -Encoding utf8

        # Full schema validation of the candidate before it replaces the real file
        $validateArgs = @{ RatesPath = $tmp }
        if ($EnvPath) { $validateArgs.EnvPath = $EnvPath }
        $null = Get-YeshConfig @validateArgs

        Move-Item -Path $tmp -Destination $RatesPath -Force
        return @{ StatusCode = 200; Body = @{ mikdamotRate = $rate } }
    }
    catch {
        return @{ StatusCode = 502; Body = @{ error = $_.Exception.Message } }
    }
    finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}
```

Update `src/YeshHeshbonit/YeshHeshbonit.psd1` FunctionsToExport to:

```powershell
    FunctionsToExport = @('Get-TaxSummary', 'Get-YeshInvoice', 'Export-TaxSummary', 'Get-DashboardSummaryResponse', 'Get-DashboardCsvResponse', 'Get-DashboardRatesResponse', 'Set-DashboardRatesResponse', 'Start-TaxDashboard')
```

Update the export assertion in `tests/Module.Tests.ps1` to:

```powershell
    It 'declares the public functions' {
        $manifest = Test-ModuleManifest -Path $manifestPath
        $manifest.ExportedFunctions.Keys | Sort-Object |
            Should -Be @('Export-TaxSummary', 'Get-DashboardCsvResponse', 'Get-DashboardRatesResponse', 'Get-DashboardSummaryResponse', 'Get-TaxSummary', 'Get-YeshInvoice', 'Set-DashboardRatesResponse', 'Start-TaxDashboard')
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester .\tests\DashboardRates.Tests.ps1 -Output Detailed` → 12 PASS.
Then full suite: `Invoke-Pester .\tests` → 92 passing (80 + 12), 0 failed.

- [ ] **Step 5: Commit**

```powershell
git add src/YeshHeshbonit/Public/Get-DashboardRatesResponse.ps1 src/YeshHeshbonit/Public/Set-DashboardRatesResponse.ps1 src/YeshHeshbonit/YeshHeshbonit.psd1 tests/DashboardRates.Tests.ps1 tests/Module.Tests.ps1
git commit -m "feat: rates read/update handlers with atomic validated persistence"
```

---

### Task 2: Routes + frontend settings line

**Files:**
- Modify: `src/YeshHeshbonit/Public/Start-TaxDashboard.ps1` (add two routes inside the Start-PodeServer block, after the existing `/api/summary/csv` route)
- Modify: `web/public/index.html` (settings section)
- Modify: `web/public/app.js` (rate load/edit/save logic)
- Modify: `web/public/style.css` (settings styles)

**Interfaces:**
- Consumes: `Get-DashboardRatesResponse` (no args in route context), `Set-DashboardRatesResponse -Body $WebEvent.Data` (Task 1); existing frontend helpers `$()`, `show()`, `showError()`, `load()`, `currentParams`
- Produces: `GET /api/rates`, `POST /api/rates` live endpoints; visible settings line

- [ ] **Step 1: Add the routes**

In `src/YeshHeshbonit/Public/Start-TaxDashboard.ps1`, inside the `Start-PodeServer` script block, immediately after the `/api/summary/csv` route's closing brace, add:

```powershell
        Add-PodeRoute -Method Get -Path '/api/rates' -ScriptBlock {
            try {
                $r = Get-DashboardRatesResponse
                Write-PodeJsonResponse -Value $r.Body -StatusCode $r.StatusCode
            }
            catch {
                Write-PodeJsonResponse -Value @{ error = 'Internal error' } -StatusCode 500
            }
        }

        Add-PodeRoute -Method Post -Path '/api/rates' -ScriptBlock {
            try {
                $r = Set-DashboardRatesResponse -Body $WebEvent.Data
                Write-PodeJsonResponse -Value $r.Body -StatusCode $r.StatusCode
            }
            catch {
                Write-PodeJsonResponse -Value @{ error = 'Internal error' } -StatusCode 500
            }
        }
```

- [ ] **Step 2: Add the settings line to `web/public/index.html`**

Immediately after the closing `</section>` of the `controls` section and before `<div id="error-banner" ...>`, add:

```html
<section class="rates">
  <span>מקדמות מס הכנסה: <b id="rate-value"></b></span>
  <button id="btn-rate-edit" type="button">עריכה</button>
  <span id="rate-editor" class="hidden">
    <input type="number" id="rate-input" min="0" max="99.9" step="0.1"> %
    <button id="btn-rate-save" type="button">שמירה</button>
    <button id="btn-rate-cancel" type="button">ביטול</button>
  </span>
</section>
```

- [ ] **Step 3: Add the rate logic to `web/public/app.js`**

Immediately before the final `$('btn-this-month').click();` line, add:

```javascript
  let currentRatePercent = null;

  function showRate(percent) {
    currentRatePercent = percent;
    $('rate-value').textContent = percent + '%';
    show($('rate-editor'), false);
    show($('btn-rate-edit'), true);
  }

  async function loadRate() {
    try {
      const res = await fetch('/api/rates');
      const body = await res.json();
      if (res.ok) {
        showRate(Math.round(body.mikdamotRate * 1000) / 10);
      } else {
        showError(body.error || 'שגיאה בטעינת אחוז המקדמות');
      }
    } catch {
      /* server-unavailable already surfaced by the summary load */
    }
  }

  $('btn-rate-edit').addEventListener('click', () => {
    $('rate-input').value = currentRatePercent ?? '';
    show($('btn-rate-edit'), false);
    show($('rate-editor'), true);
  });

  $('btn-rate-cancel').addEventListener('click', () => showRate(currentRatePercent));

  $('btn-rate-save').addEventListener('click', async () => {
    const percent = parseFloat($('rate-input').value);
    if (Number.isNaN(percent) || percent < 0 || percent >= 100) {
      showError('אחוז מקדמות לא תקין.');
      return;
    }
    try {
      const res = await fetch('/api/rates', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ mikdamotRate: percent / 100 })
      });
      const body = await res.json();
      if (!res.ok) {
        showError(body.error || 'שמירת אחוז המקדמות נכשלה');
        showRate(currentRatePercent);
        return;
      }
      showRate(Math.round(body.mikdamotRate * 1000) / 10);
      if (currentParams) load(currentParams);
    } catch {
      showError('השרת אינו זמין.');
    }
  });

  loadRate();
```

- [ ] **Step 4: Add styles to `web/public/style.css`**

Append at the end of the file:

```css
.rates {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  align-items: center;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 10px 16px;
  margin-bottom: 18px;
}
.rates b { color: var(--accent); }
.rates input[type="number"] {
  width: 90px;
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 6px 8px;
  font: inherit;
}
#rate-editor { display: inline-flex; gap: 8px; align-items: center; }
#rate-editor.hidden { display: none; }
```

(The `#rate-editor` display rule is needed because the global `.hidden` uses `display:none !important` but the visible state must be `inline-flex`, not the span default.)

- [ ] **Step 5: Sanity check + run the suite**

Run: `node --check web/public/app.js` (skip if node missing). Run `Invoke-Pester .\tests` → 92 passing (routes are inside Start-PodeServer, exercised by the Task 3 smoke, not unit tests).

- [ ] **Step 6: Commit**

```powershell
git add src/YeshHeshbonit/Public/Start-TaxDashboard.ps1 web/public/index.html web/public/app.js web/public/style.css
git commit -m "feat: rates editing UI and /api/rates routes"
```

---

### Task 3: Live smoke test

**Files:**
- No file changes expected (README's dashboard section already describes the dashboard generally; the rate editor needs no setup)

- [ ] **Step 1: Start the server and probe the rates API**

```powershell
$job = Start-Job -ScriptBlock {
    Import-Module 'C:\Users\Eitan\ClaudeCodeAI\YeshHeshbonitAPI\src\YeshHeshbonit\YeshHeshbonit.psd1' -Force
    Start-TaxDashboard -NoBrowser -Port 8321
}
Start-Sleep -Seconds 8

# 1. Read current rate
Invoke-RestMethod 'http://127.0.0.1:8321/api/rates'                     # expect mikdamotRate 0.08
# 2. Update to 9%
Invoke-RestMethod 'http://127.0.0.1:8321/api/rates' -Method Post -ContentType 'application/json' -Body '{"mikdamotRate":0.09}'   # expect mikdamotRate 0.09
# 3. Verify persisted + used by the summary
Invoke-RestMethod 'http://127.0.0.1:8321/api/rates'                     # expect 0.09
(Invoke-RestMethod 'http://127.0.0.1:8321/api/summary?from=2026-01-01&to=2026-07-02').totals.mikdamot  # expect net * 0.09
# 4. Invalid value → 400, extra key → 400
try { Invoke-WebRequest 'http://127.0.0.1:8321/api/rates' -Method Post -ContentType 'application/json' -Body '{"mikdamotRate":1.5}' -UseBasicParsing } catch { [int]$_.Exception.Response.StatusCode }  # 400
try { Invoke-WebRequest 'http://127.0.0.1:8321/api/rates' -Method Post -ContentType 'application/json' -Body '{"mikdamotRate":0.08,"vatRate":0.5}' -UseBasicParsing } catch { [int]$_.Exception.Response.StatusCode }  # 400
# 5. Restore 8%
Invoke-RestMethod 'http://127.0.0.1:8321/api/rates' -Method Post -ContentType 'application/json' -Body '{"mikdamotRate":0.08}'   # expect 0.08

Stop-Job $job; Remove-Job $job -Force
Get-Content .\config\rates.json   # confirm mikdamotRate 0.08 and all other keys intact
```

- [ ] **Step 2: Manual browser check**

Run `Start-TaxDashboard`, confirm: settings line shows "מקדמות מס הכנסה: 8%", עריכה opens the input, saving 9 updates the card immediately, ביטול restores, invalid % shows the error banner. Restore to 8 and Ctrl+C.

- [ ] **Step 3: Commit (only if any file changed during smoke)**

If `git status` is clean, no commit. Otherwise commit what changed with an explanatory message.

---

## Self-Review Notes

- **Spec coverage:** GET/POST handlers incl. allowlist, fraction validation, atomic temp+validate+move persistence, no-temp-left guarantee (T1); routes with 500 catch-all, percent↔fraction conversion, re-fetch after save, textContent-only (T2); live verification incl. persistence round-trip and 400 paths (T3). Out-of-scope items have no tasks.
- **Type consistency:** handler names and `-Body`/`-RatesPath`/`-EnvPath` signatures match between T1 definitions and T2 route calls; JSON field `mikdamotRate` consistent across handlers, routes, app.js, and tests.
- **Placeholder scan:** all steps carry complete code and exact commands.
