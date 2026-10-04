param(
    [string]$AddOnsPath = 'C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns',
    # The LibGlass-1.0 dev checkout (the packager embeds the pinned tag instead).
    [string]$LibGlass = $(if ($env:LIBGLASS) { $env:LIBGLASS } else { Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'LibGlass' })
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if (!(Test-Path -LiteralPath $AddOnsPath -PathType Container)) { throw "Missing AddOns folder: $AddOnsPath" }
$destination = Join-Path $AddOnsPath 'TimeIsMoney'
$toc = Join-Path $repoRoot 'TimeIsMoney.toc'
$tocLines = @(Get-Content -LiteralPath $toc |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and !($_.StartsWith('#')) })
# Embedded libraries come from their own checkout, through their own deploy.
$libLines = @($tocLines | Where-Object { $_.Replace([char]92, [char]47).StartsWith('Libs/') })
foreach ($line in $libLines) {
    if ($line.Replace([char]92, [char]47) -ne 'Libs/LibGlass-1.0/LibGlass-1.0.xml') { throw "Unexpected library TOC input: $line" }
}
$libDeploy = Join-Path $LibGlass 'Tools/deploy.ps1'
if ($libLines.Count -gt 0 -and !(Test-Path -LiteralPath $libDeploy -PathType Leaf)) {
    throw "LibGlass checkout not found at $LibGlass (pass -LibGlass or set LIBGLASS)"
}
$inputs = @('LICENSE') + @($tocLines | Where-Object { $libLines -notcontains $_ })
$mediaRoot = Join-Path $repoRoot 'Media'
if (Test-Path -LiteralPath $mediaRoot) {
    $inputs += @(Get-ChildItem -LiteralPath $mediaRoot -Recurse -File |
        Where-Object { $_.Extension -in '.tga', '.blp', '.ogg' } |
        ForEach-Object { [IO.Path]::GetRelativePath($repoRoot, $_.FullName) })
}
foreach ($relative in $inputs) {
    $source = [IO.Path]::GetFullPath((Join-Path $repoRoot $relative))
    if (!$source.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "TOC input escapes repository: $relative"
    }
    if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing input: $relative" }
}
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$uniqueInputs = @($inputs | Select-Object -Unique)
foreach ($relative in $uniqueInputs) {
    $target = Join-Path $destination $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot $relative) -Destination $target -Force
}
if ($libLines.Count -gt 0) {
    & $libDeploy -Addon 'TimeIsMoney' -AddOnsPath $AddOnsPath
    if ($LASTEXITCODE) { throw "LibGlass deploy failed ($LASTEXITCODE)" }
}
(Get-Content -LiteralPath $toc -Raw).Replace('## Version: @project-version@', '## Version: dev') |
    Set-Content -LiteralPath (Join-Path $destination 'TimeIsMoney.toc') -Encoding utf8 -NoNewline
Write-Host "Deployed to $destination. New folder: restart client. Updated files: /reload."
Write-Host 'In game: /console scriptErrors 1, then /tim status.'
