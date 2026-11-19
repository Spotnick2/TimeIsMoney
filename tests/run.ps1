param([string]$Lua = 'C:\Program Files (x86)\Lua\5.1\lua.exe', [switch]$KitDev)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path (Split-Path -Parent $Lua) 'luac.exe'
if (!(Test-Path -LiteralPath $Lua) -or !(Test-Path -LiteralPath $compiler)) {
    throw 'Lua 5.1 and matching luac.exe are required; pass -Lua <path>.'
}
Push-Location $repoRoot
try {
    $version = & $Lua -e 'print(_VERSION)'
    if ($LASTEXITCODE -ne 0 -or $version.Trim() -ne 'Lua 5.1') { throw 'Expected Lua 5.1.' }
    # Every Lua file in the repository, not only the TOC's (Probe, Tools, tests).
    $paths = @(Get-ChildItem -LiteralPath . -Recurse -File -Filter '*.lua' |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|\.release|dist|\.tmp[^\\/]*)[\\/]' } |
        Select-Object -ExpandProperty FullName)
    if ($paths.Count -eq 0) { throw 'No Lua files found.' }
    foreach ($path in $paths) {
        & $compiler -p $path
        if ($LASTEXITCODE -ne 0) { throw "Syntax check failed: $path" }
    }
    Write-Host "Lua 5.1 syntax: $($paths.Count) file(s) passed."
} finally { Pop-Location }

# The tests run on WowTestKit at the commit tests\kit.pin names (-KitDev: the
# ..\WowTestKit working copy instead).
. (Join-Path $PSScriptRoot 'kit.ps1')
$kit = Get-WowTestKit -RepoRoot $repoRoot -KitDev:$KitDev
& (Join-Path $kit 'scripts\run.ps1') -RepoRoot $repoRoot -Toc 'TimeIsMoney.toc' -Lua $Lua
exit $LASTEXITCODE
