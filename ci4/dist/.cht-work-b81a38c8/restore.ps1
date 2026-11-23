param([string]$GameDir = "")
$ErrorActionPreference = "Stop"
$Marker = "[Trafficity CHT]"
function Say($m) { Write-Host ($Marker + " " + $m) }
function Fail($m) { Write-Host ($Marker + " " + $m) -ForegroundColor Red; Write-Host ""; Write-Host "按任意鍵結束..."; try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch {}; exit 1 }

function Find-GameDir {
    $here = Split-Path -Parent $PSCommandPath
    $cands = New-Object System.Collections.Generic.List[string]
    if ($GameDir -ne "") { $cands.Add($GameDir) }
    $cands.Add($here)
    $cands.Add((Split-Path -Parent $here))
    try {
        $sp = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
        if ($sp) {
            $sp = $sp -replace "/", "\"
            $cands.Add((Join-Path $sp "steamapps\common\Trafficity"))
            $vdf = Join-Path $sp "steamapps\libraryfolders.vdf"
            if (Test-Path $vdf) {
                foreach ($line in Get-Content $vdf) {
                    $m = [regex]::Match($line, '"path"\s+"([^"]+)"')
                    if ($m.Success) { $cands.Add((Join-Path ($m.Groups[1].Value -replace "\\\\", "\") "steamapps\common\Trafficity")) }
                }
            }
        }
    } catch {}
    foreach ($c in $cands) { if ($c -and (Test-Path (Join-Path $c "resources\app.asar"))) { return $c } }
    return $null
}

$dir = Find-GameDir
if (-not $dir) { Fail "找不到遊戲資料夾。" }
$dir = (Resolve-Path $dir).Path
if (Get-Process Trafficity -ErrorAction SilentlyContinue) { Fail "請先關閉遊戲。" }

$asar = Join-Path $dir "resources\app.asar"
$orig = Join-Path $dir "resources\app.asar.orig"
if (-not (Test-Path $orig)) { Fail "找不到備份 app.asar.orig，無法還原。請用 Steam 的「驗證遊戲檔案完整性」。" }

Copy-Item $orig $asar -Force
Say "已還原原版 app.asar"

try {
    $settings = Join-Path $env:APPDATA "Trafficity\saves\settings.json"
    if (Test-Path ($settings + ".bak")) {
        Copy-Item ($settings + ".bak") $settings -Force
        Say "已還原語言設定"
    }
} catch {}

Write-Host ""
Write-Host "還原完成。" -ForegroundColor Green
Write-Host ""
Write-Host "按任意鍵結束..."
try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch {}
