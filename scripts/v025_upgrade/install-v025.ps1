[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [string]$Remote = "origin",
    [string]$Branch = "main",
    [string]$OllamaHostUrl = "http://127.0.0.1:11434",
    [string]$GatewayHealthUrl = "http://127.0.0.1:3231/api/health",
    [string]$OllamaModel,
    [switch]$SkipGitSync,
    [switch]$SkipDockerBuild,
    [switch]$SkipGatewayHealthCheck,
    [switch]$SkipOllamaCheck,
    [switch]$AllowDirtyRepo
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Require-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

function Invoke-Git {
    param([string[]]$Arguments)

    & git -C $RepoDir @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Invoke-Compose {
    param([string[]]$Arguments)

    Push-Location $RepoDir
    try {
        & docker compose @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "docker compose $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function Wait-HttpOk {
    param(
        [string]$Url,
        [int]$Attempts = 20,
        [int]$DelaySeconds = 3
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 15
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
                return $response
            }
        }
        catch {
            if ($attempt -eq $Attempts) {
                throw "Timed out waiting for $Url to return HTTP 2xx. Last error: $($_.Exception.Message)"
            }
        }

        Start-Sleep -Seconds $DelaySeconds
    }
}

function Invoke-OllamaGenerateProbe {
    param(
        [string]$BaseUrl,
        [string]$Model
    )

    $payload = @{
        model  = $Model
        prompt = "Reply with exactly OK"
        stream = $false
    } | ConvertTo-Json -Compress

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/api/generate" -Method POST -ContentType "application/json" -Body $payload -TimeoutSec 180
        return ($response.Content | ConvertFrom-Json)
    }
    catch {
        $details = $_.ErrorDetails.Message
        if ([string]::IsNullOrWhiteSpace($details)) {
            $details = $_.Exception.Message
        }

        throw "Ollama generate probe failed: $details"
    }
}

function Restart-Ollama {
    param([string]$BaseUrl)

    $ollamaExe = Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"
    if (-not (Test-Path $ollamaExe)) {
        throw "Could not find Ollama at $ollamaExe"
    }

    $procs = Get-Process ollama -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Stop-Process -Force
        Start-Sleep -Seconds 2
    }

    Start-Process $ollamaExe -ArgumentList "serve" | Out-Null
    Wait-HttpOk -Url "$BaseUrl/api/tags" -Attempts 30 -DelaySeconds 2 | Out-Null
}

Write-Step "Validating prerequisites"
Require-Command git
Require-Command docker

if (-not $SkipOllamaCheck) {
    Require-Command ollama
}

$RepoDir = (Resolve-Path $RepoDir).Path

if (-not (Test-Path (Join-Path $RepoDir ".git"))) {
    throw "RepoDir does not point to a git repository: $RepoDir"
}

if (-not (Test-Path (Join-Path $RepoDir ".env"))) {
    throw "Missing $RepoDir\.env. Copy the machine-specific env file into place before running this installer."
}

if (-not $AllowDirtyRepo) {
    $dirty = git -C $RepoDir status --porcelain
    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect git status for $RepoDir"
    }
    if (-not [string]::IsNullOrWhiteSpace(($dirty | Out-String))) {
        throw "Working tree is dirty. Commit or stash local changes first, or rerun with -AllowDirtyRepo."
    }
}

Write-Step "Checking Docker"
Push-Location $RepoDir
try {
    & docker info | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "docker info failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

if (-not $SkipGitSync) {
    Write-Step "Syncing $Branch from $Remote"
    Invoke-Git @("fetch", $Remote)
    Invoke-Git @("checkout", $Branch)
    if ($PSCmdlet.ShouldProcess("$Remote/$Branch", "git pull --ff-only")) {
        Invoke-Git @("pull", "--ff-only", $Remote, $Branch)
    }
}

if (-not $SkipDockerBuild) {
    Write-Step "Building ironclaw-worker sandbox image"
    if ($PSCmdlet.ShouldProcess("docker build", "Dockerfile.worker -> ironclaw-worker:latest")) {
        Push-Location $RepoDir
        try {
            & docker build -f Dockerfile.worker -t ironclaw-worker:latest .
            if ($LASTEXITCODE -ne 0) {
                throw "docker build ironclaw-worker failed with exit code $LASTEXITCODE."
            }
        }
        finally {
            Pop-Location
        }
    }

    Write-Step "Building and starting the v0.25 Docker stack"
    if ($PSCmdlet.ShouldProcess("docker compose", "up -d --build postgres ironclaw")) {
        Invoke-Compose @("up", "-d", "--build", "postgres", "ironclaw")
    }
}

Write-Step "Printing compose status"
Invoke-Compose @("ps")

if (-not $SkipGatewayHealthCheck) {
    Write-Step "Waiting for IronClaw gateway health endpoint"
    Wait-HttpOk -Url $GatewayHealthUrl -Attempts 30 -DelaySeconds 2 | Out-Null
    Write-Host "Gateway is healthy at $GatewayHealthUrl" -ForegroundColor Green
}

if (-not $SkipOllamaCheck) {
    Write-Step "Checking Ollama reachability"
    Wait-HttpOk -Url "$OllamaHostUrl/api/tags" -Attempts 20 -DelaySeconds 2 | Out-Null
    Write-Host "Ollama is reachable at $OllamaHostUrl" -ForegroundColor Green

    if ($OllamaModel) {
        Write-Step "Running Ollama model probe for $OllamaModel"
        try {
            $probe = Invoke-OllamaGenerateProbe -BaseUrl $OllamaHostUrl -Model $OllamaModel
        }
        catch {
            $message = $_.Exception.Message
            if ($message -match "model failed to load" -or $message -match "resource limitations") {
                Write-Warning "Ollama reported a stuck model load. Restarting Ollama once and retrying."
                if ($PSCmdlet.ShouldProcess("Ollama", "restart local server")) {
                    Restart-Ollama -BaseUrl $OllamaHostUrl
                }
                $probe = Invoke-OllamaGenerateProbe -BaseUrl $OllamaHostUrl -Model $OllamaModel
            }
            else {
                throw
            }
        }

        if ($probe.response -ne "OK") {
            throw "Ollama model probe returned '$($probe.response)' instead of 'OK'."
        }

        Write-Host "Ollama model probe succeeded for $OllamaModel" -ForegroundColor Green
    }
    else {
        Write-Host "Skipping Ollama generate probe because -OllamaModel was not provided." -ForegroundColor Yellow
    }
}

Write-Step "Upgrade complete"
Write-Host "Fork sync target: $Remote/$Branch" -ForegroundColor Green
Write-Host "Repo root: $RepoDir" -ForegroundColor Green
Write-Host "Next checks:" -ForegroundColor Green
Write-Host "  1. Open the gateway UI and confirm the configured model answers." -ForegroundColor Green
Write-Host "  2. Send a Telegram DM and approve pairing if this machine uses a new Telegram user." -ForegroundColor Green
Write-Host "  3. If you restored older Postgres data, verify the expected sessions, settings, and MCP config are present." -ForegroundColor Green