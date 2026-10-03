param(
    [string]$AddOnsPath = 'C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns'
)
# Developer-only: installs the TimeIsMoneyProbe measurement addon (#9). TOC
# entries under Sim/ come from the repository's Sim folder; the rest from Probe/.
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if (!(Test-Path -LiteralPath $AddOnsPath -PathType Container)) { throw "Missing AddOns folder: $AddOnsPath" }
$probeRoot = Join-Path $repoRoot 'Probe'
$toc = Join-Path $probeRoot 'TimeIsMoneyProbe.toc'
$entries = @(Get-Content -LiteralPath $toc | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne '' -and !($_.StartsWith('#')) })
$sources = @{}
foreach ($entry in $entries) {
    $base = if ($entry.StartsWith('Sim/')) { $repoRoot } else { $probeRoot }
    $source = [IO.Path]::GetFullPath((Join-Path $base $entry))
    if (!$source.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Probe TOC entry escapes repository: $entry"
    }
    if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing probe input: $entry" }
    $sources[$entry] = $source
}
$destination = Join-Path $AddOnsPath 'TimeIsMoneyProbe'
New-Item -ItemType Directory -Force -Path $destination | Out-Null
Copy-Item -LiteralPath $toc -Destination (Join-Path $destination 'TimeIsMoneyProbe.toc') -Force
foreach ($entry in $entries) {
    $target = Join-Path $destination $entry
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath $sources[$entry] -Destination $target -Force
}
Write-Host "Deployed probe to $destination. New folder: restart the client."
Write-Host 'In game: /console scriptErrors 1, then /timprobe.'
