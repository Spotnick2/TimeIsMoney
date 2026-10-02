# One-time reconciliation of the tracked issue catalog with GitHub milestone objects.
# Requires gh authentication/network. Does not replace issue bodies or create duplicates.
param([string]$Repository = 'Spotnick2/TimeIsMoney')
$ErrorActionPreference = 'Stop'
$catalog = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\docs\backlog.json') -Raw | ConvertFrom-Json
if ($Repository -ne $catalog.repository) { throw 'Repository must match the tracked issue catalog.' }

function Invoke-GhJson {
    param([string[]]$Arguments)
    $output = & gh @Arguments
    if ($LASTEXITCODE -ne 0) { throw "gh failed: $($Arguments[0])" }
    $output -join "`n" | ConvertFrom-Json
}

$existing = @(Invoke-GhJson -Arguments @('api', "repos/$Repository/milestones?state=all&per_page=100"))
$byKey = @{}
foreach ($milestone in $catalog.milestones) {
    $match = @($existing | Where-Object { $_.title -eq $milestone.title })
    if ($match.Count -gt 1) { throw "Ambiguous milestone: $($milestone.title)" }
    if ($match.Count -eq 0) {
        $new = Invoke-GhJson -Arguments @('api', '--method', 'POST', "repos/$Repository/milestones",
            '-f', "title=$($milestone.title)", '-f', "description=$($milestone.description)")
        $byKey[$milestone.key] = $new.number
    } else { $byKey[$milestone.key] = $match[0].number }
}
foreach ($issue in $catalog.issues) {
    $current = Invoke-GhJson -Arguments @('api', "repos/$Repository/issues/$($issue.number)")
    if ($current.pull_request -or $current.title -ne "[$($issue.milestone)] $($issue.title)") {
        throw "Issue identity changed; inspect #$($issue.number) before attaching a milestone."
    }
    $number = $byKey[$issue.milestone]
    if (!$current.milestone -or $current.milestone.number -ne $number) {
        $null = Invoke-GhJson -Arguments @('api', '--method', 'PATCH',
            "repos/$Repository/issues/$($issue.number)", '-F', "milestone=$number")
    }
    Write-Host "#$($issue.number): $($issue.milestone)"
}
