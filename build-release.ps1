param([string]$Tag = "dev")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSCommandPath
$out = Join-Path $root ("Trafficity-CHT-" + $Tag + ".zip")
if (Test-Path $out) { Remove-Item $out -Force }
Compress-Archive -Path (Join-Path $root "src\*") -DestinationPath $out -Force
Get-Item $out | Format-List Name, Length
