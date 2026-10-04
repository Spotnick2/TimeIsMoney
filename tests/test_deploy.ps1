$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempRoot ('TimeIsMoney-deploy-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $fixture = Join-Path $testRoot 'source'
    $addOns = Join-Path $testRoot 'AddOns'
    New-Item -ItemType Directory -Path $fixture, $addOns, (Join-Path $fixture 'Tools'), (Join-Path $fixture 'Media/Nested') -Force | Out-Null
    foreach ($name in 'LICENSE', 'TimeIsMoney.toc', 'Compat.lua', 'Host.lua', 'TimeIsMoney.lua') {
        Copy-Item -LiteralPath (Join-Path $repoRoot $name) -Destination (Join-Path $fixture $name)
    }
    # The simulation (#18) loads from Sim/ through the TOC.
    Copy-Item -LiteralPath (Join-Path $repoRoot 'Sim') -Destination (Join-Path $fixture 'Sim') -Recurse
    $simFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Sim') -File | ForEach-Object { 'Sim/' + $_.Name })
    $deploy = Join-Path $fixture 'Tools/deploy.ps1'
    Copy-Item -LiteralPath (Join-Path $repoRoot 'Tools/deploy.ps1') -Destination $deploy
    [IO.File]::WriteAllBytes((Join-Path $fixture 'Media/Nested/probe.tga'), [byte[]](1, 2, 3, 4))
    Set-Content -LiteralPath (Join-Path $fixture 'README.md') -Value 'Developer-only file.'
    $sentinel = Join-Path $addOns 'another-addon.txt'
    Set-Content -LiteralPath $sentinel -Value 'Leave other addons alone.'
    $sentinelHash = (Get-FileHash -LiteralPath $sentinel).Hash

    & $deploy -AddOnsPath $addOns
    $destination = Join-Path $addOns 'TimeIsMoney'
    $actual = @(Get-ChildItem -LiteralPath $destination -Recurse -File |
        ForEach-Object { [IO.Path]::GetRelativePath($destination, $_.FullName).Replace('\', '/') } |
        Sort-Object)
    $expected = @(@('Compat.lua', 'Host.lua', 'LICENSE', 'Media/Nested/probe.tga', 'TimeIsMoney.lua', 'TimeIsMoney.toc') + $simFiles) | Sort-Object
    if (($actual -join "`n") -ne ($expected -join "`n")) { throw "Unexpected deployed files: $actual" }
    foreach ($relative in @('Compat.lua', 'Host.lua', 'TimeIsMoney.lua', 'LICENSE', 'Media/Nested/probe.tga') + $simFiles) {
        if ((Get-FileHash -LiteralPath (Join-Path $fixture $relative)).Hash -ne
            (Get-FileHash -LiteralPath (Join-Path $destination $relative)).Hash) {
            throw "Deployed bytes differ: $relative"
        }
    }
    $sourceToc = Join-Path $fixture 'TimeIsMoney.toc'
    $tocHash = (Get-FileHash -LiteralPath $sourceToc).Hash
    if (!(Get-Content -LiteralPath (Join-Path $destination 'TimeIsMoney.toc') -Raw).Contains('## Version: dev')) {
        throw 'Deployment did not substitute the development version.'
    }
    & $deploy -AddOnsPath $addOns
    if ((Get-FileHash -LiteralPath $sourceToc).Hash -ne $tocHash) { throw 'Deployment modified the source TOC.' }
    if ((Get-FileHash -LiteralPath $sentinel).Hash -ne $sentinelHash) { throw 'Deployment modified another addon.' }

    $installedTocHash = (Get-FileHash -LiteralPath (Join-Path $destination 'TimeIsMoney.toc')).Hash
    Add-Content -LiteralPath $sourceToc -Value 'Missing.lua'
    $rejected = $false
    try { & $deploy -AddOnsPath $addOns } catch { $rejected = $true }
    if (!$rejected) { throw 'A missing TOC input was accepted.' }
    if ((Get-FileHash -LiteralPath (Join-Path $destination 'TimeIsMoney.toc')).Hash -ne $installedTocHash) {
        throw 'Preflight failure changed the installed TOC.'
    }
    Set-Content -LiteralPath $sourceToc -Value "..\outside.lua"
    Set-Content -LiteralPath (Join-Path $testRoot 'outside.lua') -Value '-- Outside fixture'
    $rejected = $false
    try { & $deploy -AddOnsPath $addOns } catch { $rejected = $true }
    if (!$rejected) { throw 'A TOC input outside the source folder was accepted.' }

    # Developer probe (#9): exact folder from Probe/ and Sim/, nothing else touched.
    $probeAddOns = Join-Path $testRoot 'ProbeAddOns'
    New-Item -ItemType Directory -Path $probeAddOns | Out-Null
    & (Join-Path $repoRoot 'Tools/deploy_probe.ps1') -AddOnsPath $probeAddOns
    $probeDestination = Join-Path $probeAddOns 'TimeIsMoneyProbe'
    $tocEntries = @(Get-Content -LiteralPath (Join-Path $repoRoot 'Probe/TimeIsMoneyProbe.toc') |
        ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and !($_.StartsWith('#')) })
    $probeExpected = @(@('TimeIsMoneyProbe.toc') + $tocEntries | Sort-Object)
    $probeActual = @(Get-ChildItem -LiteralPath $probeDestination -Recurse -File |
        ForEach-Object { [IO.Path]::GetRelativePath($probeDestination, $_.FullName).Replace('\', '/') } | Sort-Object)
    if (($probeActual -join "`n") -ne ($probeExpected -join "`n")) { throw "Unexpected probe files: $probeActual" }
    foreach ($entry in $tocEntries) {
        $source = if ($entry.StartsWith('Sim/')) { Join-Path $repoRoot $entry } else { Join-Path $repoRoot ('Probe/' + $entry) }
        if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath (Join-Path $probeDestination $entry)).Hash) {
            throw "Probe bytes differ: $entry"
        }
    }
    if (@(Get-ChildItem -LiteralPath $probeAddOns).Count -ne 1) { throw 'Probe deployment created other folders.' }
    Write-Host 'deploy: exact files, nested media bytes, dev version, repeat install, source preservation and input rejection, and the probe folder passed.'
} finally {
    $resolved = (Resolve-Path -LiteralPath $testRoot).Path
    if (!$resolved.StartsWith($tempRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'TimeIsMoney-deploy-*') {
        throw "Refusing cleanup outside the test directory: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
