[CmdletBinding()]
param(
    [ValidateRange(1, 5000)]
    [int]$Tail = 200,

    [string[]]$Services = @('app', 'postgres'),

    [switch]$Follow,

    [switch]$SkipPs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $SkipPs) {
    Write-Host '== docker compose ps ==' -ForegroundColor Cyan
    & docker compose ps
    if ($LASTEXITCODE -ne 0) {
        throw 'docker compose ps failed.'
    }
    Write-Host ''
}

$logArgs = @('compose', 'logs', "--tail=$Tail")
if ($Follow) {
    $logArgs += '-f'
}
if ($Services.Count -gt 0) {
    $logArgs += $Services
}

Write-Host "== docker $($logArgs -join ' ') ==" -ForegroundColor Cyan
& docker @logArgs
if ($LASTEXITCODE -ne 0) {
    throw 'docker compose logs failed.'
}