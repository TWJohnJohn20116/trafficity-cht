param([string]$GameDir = "")

$ErrorActionPreference = "Stop"
$Marker = "[Trafficity CHT]"

function Say($m) { Write-Host ($Marker + " " + $m) }
function Fail($m) {
    Write-Host ($Marker + " 失敗: " + $m) -ForegroundColor Red
    Write-Host ""
    Write-Host "按任意鍵結束..."
    try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch {}
    exit 1
}

$script:entries = New-Object System.Collections.Generic.List[object]

function Walk-Files($node, $prefix) {
    foreach ($p in $node.files.PSObject.Properties) {
        $child = $p.Value
        $pth = $prefix + "/" + $p.Name
        if ($child.PSObject.Properties.Name -contains "files") {
            Walk-Files $child $pth
        } else {
            $script:entries.Add([pscustomobject]@{ Path = $pth; Node = $child })
        }
    }
}

function Get-ObjectEndIndex($s, $startIdx) {
    $open = $s[$startIdx]
    $close = [char]125
    if ($open -eq [char]91) { $close = [char]93 }
    $depth = 0
    $inStr = $false
    $quote = [char]0
    for ($i = $startIdx; $i -lt $s.Length; $i++) {
        $ch = $s[$i]
        if ($inStr) {
            if ($ch -eq [char]92) { $i = $i + 1; continue }
            if ($ch -eq $quote) { $inStr = $false }
            continue
        }
        if ($ch -eq [char]34 -or $ch -eq [char]39 -or $ch -eq [char]96) { $inStr = $true; $quote = $ch; continue }
        if ($ch -eq $open) { $depth = $depth + 1 }
        elseif ($ch -eq $close) {
            $depth = $depth - 1
            if ($depth -eq 0) { return $i }
        }
    }
    return -1
}

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
                    if ($m.Success) {
                        $p2 = $m.Groups[1].Value -replace "\\\\", "\"
                        $cands.Add((Join-Path $p2 "steamapps\common\Trafficity"))
                    }
                }
            }
        }
    } catch {}
    foreach ($c in $cands) {
        if ($c -and (Test-Path (Join-Path $c "resources\app.asar"))) { return $c }
    }
    return $null
}

$dir = Find-GameDir
if (-not $dir) { Fail "找不到遊戲資料夾（找不到 resources\app.asar）。請把本資料夾放到遊戲根目錄再執行，或右鍵以系統管理員身分執行並指定路徑。" }
$dir = (Resolve-Path $dir).Path
Say ("遊戲目錄: " + $dir)

$asar = Join-Path $dir "resources\app.asar"
if (Get-Process Trafficity -ErrorAction SilentlyContinue) { Fail "遊戲正在執行，請先完全關閉遊戲（含 Steam 工作列圖示）再安裝。" }
if (-not (Test-Path $asar)) { Fail "找不到 resources\app.asar。" }

$zhtPath = Join-Path (Split-Path -Parent $PSCommandPath) "zht.json"
if (-not (Test-Path $zhtPath)) { Fail "找不到 zht.json，請確認解壓時檔案完整。" }
$zhtObj = Get-Content $zhtPath -Raw -Encoding UTF8 | ConvertFrom-Json
$zhtJson = $zhtObj | ConvertTo-Json -Depth 10 -Compress
Say ("譯文筆數: " + @($zhtObj.PSObject.Properties).Count)

$orig = Join-Path $dir "resources\app.asar.orig"
if (-not (Test-Path $orig)) {
    Copy-Item $asar $orig -Force
    Say "已備份原版為 app.asar.orig"
} else {
    Say "已存在備份 app.asar.orig（保留）"
}

Say "讀取封裝..."
$fs = [System.IO.File]::Open($asar, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
try {
    $head = New-Object byte[] 16
    [void]$fs.Read($head, 0, 16)
    $headerSize = [BitConverter]::ToUInt32($head, 4)
    $jsonLen = [BitConverter]::ToUInt32($head, 12)
    $dataBase = [long](8 + $headerSize)
    $jbuf = New-Object byte[] $jsonLen
    $fs.Position = 16
    [void]$fs.Read($jbuf, 0, $jsonLen)
    $jtext = [System.Text.Encoding]::UTF8.GetString($jbuf)
} finally {
    $fs.Close()
}
$header = $jtext | ConvertFrom-Json
Walk-Files $header ""
Say ("封裝檔案數: " + $script:entries.Count)

$bundle = $script:entries | Where-Object { $_.Path -match "^/dist/transit-city-game\.[0-9a-f]+\.js$" }
if (-not $bundle) { Fail "找不到遊戲主程式 dist/transit-city-game.*.js，遊戲版本可能不相容。" }

$bSize = [int]$bundle.Node.size
$bOff = [long]$bundle.Node.offset
$fs = [System.IO.File]::Open($asar, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
try {
    $bbuf = New-Object byte[] $bSize
    $fs.Position = $dataBase + $bOff
    [void]$fs.Read($bbuf, 0, $bSize)
} finally {
    $fs.Close()
}
$src = [System.Text.Encoding]::UTF8.GetString($bbuf)
Say ("主程式大小: " + $src.Length + " 字元")

if ($src.Contains(",zht:")) { Fail "這個版本已經是繁體中文版，不需要重複安裝。" }

# --- 檢查所有錨點 ---
$anchors = @("zhs:", "schinese:", "zhs:""zh-CN""")
foreach ($a in $anchors) { if (-not $src.Contains($a)) { Fail ("找不到必要標記 [" + $a + "]，遊戲版本不相容。") } }

$zhsIdx = $src.IndexOf("zhs:{")
if ($zhsIdx -lt 0) { Fail "找不到 zhs 語言表，遊戲版本不相容。" }
$zhsOpen = $src.IndexOf("{", $zhsIdx)
$zhsEnd = Get-ObjectEndIndex $src $zhsOpen
if ($zhsEnd -lt 0) { Fail "語言表解析失敗。" }

Say "寫入繁中語言表..."
$src = $src.Substring(0, $zhsEnd + 1) + ",zht:" + $zhtJson + $src.Substring($zhsEnd + 1)

$nameOld = "zhs:""简体中文"""
if (-not $src.Contains($nameOld)) { Fail "找不到語言名稱標記。" }
$src = $src.Replace($nameOld, $nameOld + ",zht:""繁體中文""")

$steamOld = "schinese:""zhs"""
if (-not $src.Contains($steamOld)) { Fail "找不到 Steam 語言對照標記。" }
$src = $src.Replace($steamOld, $steamOld + ",tchinese:""zht"",traditionalchinese:""zht""")

$codeOld = "zhs:""zh-CN"""
if (-not $src.Contains($codeOld)) { Fail "找不到語系代碼標記。" }
$src = $src.Replace($codeOld, $codeOld + ",zht:""zh-TW""")

$detOld = "if(""zh""===t)return c(n)&&g(""zhs"")?""zhs"":null;"
if (-not $src.Contains($detOld)) { Fail "找不到語言判斷邏輯。" }
$detNew = "if(""zh""===t){if(/^zh-(tw|hk|mo|hant)/.test(n))return g(""zht"")?""zht"":null;return c(n)&&g(""zhs"")?""zhs"":null}"
$src = $src.Replace($detOld, $detNew)

$newBytes = [System.Text.Encoding]::UTF8.GetBytes($src)
$bundle.Node.size = $newBytes.Length
Say ("新主程式大小: " + $newBytes.Length + " 位元組")

# --- 重算偏移 ---
$off = [long]0
foreach ($e in $script:entries) {
    $isUnpacked = $false
    if ($e.Node.PSObject.Properties.Name -contains "unpacked") { $isUnpacked = [bool]$e.Node.unpacked }
    if ($e.Node.PSObject.Properties.Name -contains "link") { if ($e.Node.link) { continue } }
    if ($isUnpacked) { continue }
    $e | Add-Member -NotePropertyName OrigOffset -NotePropertyValue ([long]$e.Node.offset) -Force
    $e | Add-Member -NotePropertyName OrigSize -NotePropertyValue ([int]$e.Node.size) -Force
    $e.Node.offset = [string]$off
    $off = $off + [long]$e.Node.size
}

$headerJson = $header | ConvertTo-Json -Depth 100 -Compress
$jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($headerJson)
$pad = (4 - ((4 + $jsonBytes.Length) % 4)) % 4
if ($pad -gt 0) {
    $headerJson = $headerJson + (" " * $pad)
    $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($headerJson)
}
$payloadLen = 4 + $jsonBytes.Length
$headerSize2 = 4 + $payloadLen

$tmp = $asar + ".new"
Say "重建封裝（約 700 MB，請稍候）..."
$srcFs = [System.IO.File]::Open($asar, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$outFs = $null
try {
    $outFs = [System.IO.File]::Open($tmp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
} catch {
    $srcFs.Close()
    Fail "無法在遊戲資料夾建立暫存檔。常見原因：Steam 正在下載或更新這款遊戲、遊戲仍在執行，或資料夾被防毒鎖住。請確認後再執行一次。"
}
try {
    $headBytes = New-Object byte[] 16
    [BitConverter]::GetBytes([uint32]4).CopyTo($headBytes, 0)
    [BitConverter]::GetBytes([uint32]$headerSize2).CopyTo($headBytes, 4)
    [BitConverter]::GetBytes([uint32]$payloadLen).CopyTo($headBytes, 8)
    [BitConverter]::GetBytes([uint32]$jsonBytes.Length).CopyTo($headBytes, 12)
    $outFs.Write($headBytes, 0, 16)
    $outFs.Write($jsonBytes, 0, $jsonBytes.Length)

    $buf = New-Object byte[] (4 * 1024 * 1024)
    foreach ($e in $script:entries) {
        if ($e.Node.PSObject.Properties.Name -contains "unpacked") { if ($e.Node.unpacked) { continue } }
        if ($e.Node.PSObject.Properties.Name -contains "link") { if ($e.Node.link) { continue } }
        if ($e.Path -eq $bundle.Path) {
            $outFs.Write($newBytes, 0, $newBytes.Length)
            continue
        }
        $srcFs.Position = $dataBase + $e.OrigOffset
        $remain = [long]$e.OrigSize
        while ($remain -gt 0) {
            $take = [int][Math]::Min([long]$buf.Length, $remain)
            $read = $srcFs.Read($buf, 0, $take)
            if ($read -le 0) { break }
            $outFs.Write($buf, 0, $read)
            $remain = $remain - $read
        }
    }
} finally {
    if ($outFs) { $outFs.Close() }
    $srcFs.Close()
}

$newLen = (Get-Item $tmp).Length
Say ("新封裝大小: " + $newLen)

Say "套用..."
Remove-Item $asar -Force
Move-Item $tmp $asar -Force
Say "完成！"

# --- 順便把遊戲語言設為繁中 ---
try {
    $settings = Join-Path $env:APPDATA "Trafficity\saves\settings.json"
    if (Test-Path $settings) {
        if (-not (Test-Path ($settings + ".bak"))) { Copy-Item $settings ($settings + ".bak") -Force }
        $s = Get-Content $settings -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($s.PSObject.Properties.Name -contains "language") { $s.language = "zht" }
        $txt = $s | ConvertTo-Json -Depth 20 -Compress
        [System.IO.File]::WriteAllText($settings, $txt, (New-Object System.Text.UTF8Encoding($false)))
        Say "已將遊戲語言設為繁體中文"
    }
} catch { Say "（略過語言設定，請進遊戲手動選擇 繁體中文）" }

Write-Host ""
Write-Host "安裝完成！請啟動遊戲，若語言不是繁體中文，到 設定 -> 語言 選「繁體中文」。" -ForegroundColor Green
Write-Host "還原方式：執行 還原原版.bat" -ForegroundColor DarkGray
Write-Host ""
Write-Host "按任意鍵結束..."
try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch {}
