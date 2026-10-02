param([string]$Lua = 'C:\Program Files (x86)\Lua\5.1\lua.exe')
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
    $paths = @(Get-ChildItem -LiteralPath . -Recurse -File -Filter '*.lua' |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|\.release|dist|\.tmp[^\\/]*)[\\/]' } |
        Select-Object -ExpandProperty FullName)
    if ($paths.Count -eq 0) { throw 'No Lua files found.' }
    foreach ($path in $paths) {
        & $compiler -p $path
        if ($LASTEXITCODE -ne 0) { throw "Syntax check failed: $path" }
    }
    $tests = @(Get-ChildItem -LiteralPath 'tests' -Filter 'test_*.lua' -File | Sort-Object Name)
    if ($tests.Count -eq 0) { throw 'No tests found.' }
    foreach ($test in $tests) {
        & $Lua $test.FullName
        if ($LASTEXITCODE -ne 0) { throw "Test failed: $($test.Name)" }
    }
    Write-Host "Lua 5.1 syntax and $($tests.Count) test file(s) passed."
} finally { Pop-Location }
