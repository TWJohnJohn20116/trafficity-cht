# Build dist\Trafficity-CHT-Setup.exe (single file, embeds patch.ps1 / restore.ps1 / zht.json).
# Uses .NET Framework 4.x csc.exe, which ships with Windows. No external tooling required.
param(
    [string]$OutDir = ""
)
$ErrorActionPreference = "Stop"

# this script lives at <repo>\src\installer\build.ps1
$scriptDir = Split-Path -Parent $PSCommandPath
$root = Split-Path -Parent (Split-Path -Parent $scriptDir)
if ([string]::IsNullOrEmpty($OutDir)) { $OutDir = Join-Path $root "dist" }

Write-Host ("repo root: " + $root)

$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe" }
if (-not (Test-Path $csc)) { throw "csc.exe not found (.NET Framework 4.x required)" }
Write-Host ("csc: " + $csc)

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$OutDir = (Resolve-Path $OutDir).Path
$out = Join-Path $OutDir "Trafficity-CHT-Setup.exe"

$inputs = @(
    (Join-Path $root "src\installer\Installer.cs"),
    (Join-Path $root "src\patch.ps1"),
    (Join-Path $root "src\restore.ps1"),
    (Join-Path $root "src\zht.json")
)
foreach ($f in $inputs) { if (-not (Test-Path $f)) { throw ("missing input: " + $f) } }

# Stage into a space-free temp directory: csc's /resource parsing breaks on paths with spaces.
$stage = Join-Path $env:TEMP ("cht-build-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
try {
    Copy-Item $inputs[0] (Join-Path $stage "Installer.cs") -Force
    Copy-Item $inputs[1] (Join-Path $stage "patch.ps1")   -Force
    Copy-Item $inputs[2] (Join-Path $stage "restore.ps1") -Force
    Copy-Item $inputs[3] (Join-Path $stage "zht.json")    -Force

    Push-Location $stage
    try {
        $cscArgs = @(
            "/nologo",
            "/target:exe",
            "/platform:anycpu",
            "/optimize+",
            ("/out:" + $out),
            "/resource:patch.ps1,patch.ps1",
            "/resource:restore.ps1,restore.ps1",
            "/resource:zht.json,zht.json",
            "Installer.cs"
        )
        & $csc $cscArgs
        if ($LASTEXITCODE -ne 0) { throw ("compile failed (exit " + $LASTEXITCODE + ")") }
    } finally {
        Pop-Location
    }
} finally {
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
}

Get-Item $out | Format-List Name, Length, FullName
