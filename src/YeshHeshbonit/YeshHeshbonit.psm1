$privateDir = Join-Path $PSScriptRoot 'Private'
$publicDir = Join-Path $PSScriptRoot 'Public'
$private = @(if (Test-Path $privateDir) { Get-ChildItem -Path $privateDir -Filter '*.ps1' })
$public = @(if (Test-Path $publicDir) { Get-ChildItem -Path $publicDir -Filter '*.ps1' })
foreach ($file in ($private + $public)) { . $file.FullName }
Export-ModuleMember -Function $public.BaseName
