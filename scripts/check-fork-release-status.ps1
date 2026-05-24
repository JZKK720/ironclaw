param(
    [string]$Owner = "JZKK720",
    [string]$Repo = "ironclaw",
    [string]$PushDockerRunId,
    [string]$ReleaseRunId,
    [string]$VersionTag
)

Set-StrictMode -Version Latest

function Get-RepoVersion {
    $cargoToml = Join-Path $PSScriptRoot "..\Cargo.toml"
    $match = Select-String -Path $cargoToml -Pattern '^version\s*=\s*"([^"]+)"' | Select-Object -First 1

    if (-not $match) {
        throw "Could not determine package version from $cargoToml"
    }

    return $match.Matches[0].Groups[1].Value
}

function Get-DockerPath {
    $candidate = Get-Command docker.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    if ($candidate) {
        return $candidate
    }

    $fallback = "C:\Program Files\Docker\Docker\resources\bin\docker.exe"
    if (Test-Path $fallback) {
        return $fallback
    }

    return $null
}

function Get-GitPath {
    $candidate = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    if ($candidate) {
        return $candidate
    }

    $fallback = "C:\Program Files\Git\cmd\git.exe"
    if (Test-Path $fallback) {
        return $fallback
    }

    return $null
}

function Get-HeadSha {
    param([string]$GitPath)

    if (-not $GitPath) {
        return $null
    }

    try {
        $headSha = (& $GitPath rev-parse HEAD).Trim()
        if ($headSha) {
            return $headSha
        }
    }
    catch {
    }

    return $null
}

function Resolve-WorkflowRunUrl {
    param(
        [string]$WorkflowFile,
        [string]$HeadSha,
        [string]$Event,
        [string]$VersionTag,
        [string]$FallbackRunId
    )

    $apiUrl = "https://api.github.com/repos/$Owner/$Repo/actions/workflows/$WorkflowFile/runs?per_page=20"
    if ($Event) {
        $apiUrl = "$apiUrl&event=$Event"
    }

    try {
        $apiResponse = Invoke-WebRequest -UseBasicParsing -Uri $apiUrl -Headers @{
            "User-Agent" = "IronClawReleaseStatusCheck/1.0"
            "Accept" = "application/vnd.github+json"
            "X-GitHub-Api-Version" = "2022-11-28"
        }
        $payload = $apiResponse.Content | ConvertFrom-Json
        $runs = @($payload.workflow_runs)
        if ($HeadSha) {
            $runs = @($runs | Where-Object { $_.head_sha -eq $HeadSha })
        }
        if ($VersionTag) {
            $runs = @($runs | Sort-Object @{ Expression = { $_.display_title -like "*$VersionTag*" }; Descending = $true }, created_at -Descending)
        }

        $run = $runs | Select-Object -First 1
        if ($run -and $run.html_url) {
            return $run.html_url
        }
    }
    catch {
    }

    if ($FallbackRunId) {
        return "https://github.com/$Owner/$Repo/actions/runs/$FallbackRunId"
    }

    return $null
}

function Get-RunStatus {
    param([string]$RunUrl)

    $runIdMatch = [regex]::Match($RunUrl, '/runs/(\d+)')
    if ($runIdMatch.Success) {
        $runId = $runIdMatch.Groups[1].Value
        $apiUrl = "https://api.github.com/repos/$Owner/$Repo/actions/runs/$runId"

        try {
            $apiResponse = Invoke-WebRequest -UseBasicParsing -Uri $apiUrl -Headers @{
                "User-Agent" = "IronClawReleaseStatusCheck/1.0"
                "Accept" = "application/vnd.github+json"
                "X-GitHub-Api-Version" = "2022-11-28"
            }
            $payload = $apiResponse.Content | ConvertFrom-Json

            if ($payload.status) {
                if ($payload.status -eq 'completed') {
                    switch ($payload.conclusion) {
                        'success' { $apiStatus = 'Completed successfully' }
                        'failure' { $apiStatus = 'Failed' }
                        'cancelled' { $apiStatus = 'Cancelled' }
                        default { $apiStatus = 'Completed' }
                    }
                }
                elseif ($payload.status -eq 'in_progress') {
                    $apiStatus = 'In progress'
                }
                elseif ($payload.status -eq 'queued') {
                    $apiStatus = 'Queued'
                }
                else {
                    $apiStatus = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase(($payload.status -replace '_', ' '))
                }

                return [pscustomobject]@{
                    Url = $RunUrl
                    Status = $apiStatus
                }
            }
        }
        catch {
        }
    }

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $RunUrl -Headers @{ "User-Agent" = "IronClawReleaseStatusCheck/1.0" }
        $html = $response.Content
        $text = [System.Net.WebUtility]::HtmlDecode([regex]::Replace($html, '<[^>]+>', ' '))
        $text = $text -replace '\s+', ' '

        $statusMatch = [regex]::Match($text, 'Status\s*(In progress|Completed successfully|Completed|Failed|Cancelled|Queued|Waiting)\s*Total duration', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($statusMatch.Success) {
            $status = $statusMatch.Groups[1].Value
        }
        elseif ($text -match 'currently running:') {
            $status = 'In progress'
        }
        elseif ($text -match 'completed successfully:') {
            $status = 'Completed successfully'
        }
        elseif ($text -match 'failed:') {
            $status = 'Failed'
        }
        elseif ($text -match 'cancelled:') {
            $status = 'Cancelled'
        }
        else {
            $status = 'Unknown'
        }

        return [pscustomobject]@{
            Url = $RunUrl
            Status = $status
        }
    }
    catch {
        return [pscustomobject]@{
            Url = $RunUrl
            Status = "Fetch failed: $($_.Exception.Message)"
        }
    }
}

function Test-ManifestTag {
    param(
        [string]$DockerPath,
        [string]$Image
    )

    & $DockerPath manifest inspect $Image *> $null
    if ($LASTEXITCODE -eq 0) {
        return "present"
    }

    return "missing"
}

function Get-LatestImageSha {
    param(
        [string]$DockerPath,
        [string]$Image
    )

    try {
        & $DockerPath pull $Image *> $null
        $labelsJson = & $DockerPath image inspect $Image --format '{{json .Config.Labels}}'
        if (-not $labelsJson) {
            return "unknown"
        }

        $labels = $labelsJson | ConvertFrom-Json
        if ($labels.PSObject.Properties.Name -contains "ironclaw.git.sha") {
            return $labels."ironclaw.git.sha"
        }

        return "unknown"
    }
    catch {
        return "inspect failed: $($_.Exception.Message)"
    }
}

if (-not $VersionTag) {
    $VersionTag = Get-RepoVersion
}

$dockerPath = Get-DockerPath
$gitPath = Get-GitPath
$headSha = Get-HeadSha -GitPath $gitPath
$pushRunUrl = Resolve-WorkflowRunUrl -WorkflowFile "docker.yml" -HeadSha $headSha -Event "push" -VersionTag $VersionTag -FallbackRunId $PushDockerRunId
$releaseRunUrl = Resolve-WorkflowRunUrl -WorkflowFile "release.yml" -HeadSha $headSha -Event "workflow_dispatch" -VersionTag $VersionTag -FallbackRunId $ReleaseRunId
$appVersionImage = "ghcr.io/$($Owner.ToLowerInvariant())/${Repo}:$VersionTag"
$workerVersionImage = "ghcr.io/$($Owner.ToLowerInvariant())/${Repo}-worker:$VersionTag"
$appLatestImage = "ghcr.io/$($Owner.ToLowerInvariant())/${Repo}:latest"
$workerLatestImage = "ghcr.io/$($Owner.ToLowerInvariant())/${Repo}-worker:latest"

$pushRun = if ($pushRunUrl) { Get-RunStatus -RunUrl $pushRunUrl } else { [pscustomobject]@{ Url = $null; Status = "Unavailable" } }
$releaseRun = if ($releaseRunUrl) { Get-RunStatus -RunUrl $releaseRunUrl } else { [pscustomobject]@{ Url = $null; Status = "Unavailable" } }

$appVersionStatus = "docker unavailable"
$workerVersionStatus = "docker unavailable"
$appLatestSha = "docker unavailable"
$workerLatestSha = "docker unavailable"

if ($dockerPath) {
    $appVersionStatus = Test-ManifestTag -DockerPath $dockerPath -Image $appVersionImage
    $workerVersionStatus = Test-ManifestTag -DockerPath $dockerPath -Image $workerVersionImage
    $appLatestSha = Get-LatestImageSha -DockerPath $dockerPath -Image $appLatestImage
    $workerLatestSha = Get-LatestImageSha -DockerPath $dockerPath -Image $workerLatestImage
}

Write-Output "Release status check: $(Get-Date -Format s)"
Write-Output "Version tag: $VersionTag"
Write-Output "Push docker run: $($pushRun.Status)"
Write-Output "Release run: $($releaseRun.Status)"
Write-Output "App version tag ($appVersionImage): $appVersionStatus"
Write-Output "Worker version tag ($workerVersionImage): $workerVersionStatus"
Write-Output "App latest sha ($appLatestImage): $appLatestSha"
Write-Output "Worker latest sha ($workerLatestImage): $workerLatestSha"
Write-Output "Push docker URL: $($pushRun.Url)"
Write-Output "Release URL: $($releaseRun.Url)"

if ($appLatestSha -is [string] -and $workerLatestSha -is [string] -and $appLatestSha -notlike 'inspect failed:*' -and $workerLatestSha -notlike 'inspect failed:*' -and $appLatestSha -ne 'unknown' -and $workerLatestSha -ne 'unknown' -and $appLatestSha -ne $workerLatestSha) {
    Write-Warning "App latest and worker latest are not aligned yet."
}