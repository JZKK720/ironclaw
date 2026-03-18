[CmdletBinding()]
param(
    [string]$GatewayUrl = 'http://localhost:3231',

    [string]$WebhookUrl = 'http://localhost:8281',

    [string]$GatewayAuthToken,

    [string]$HttpWebhookSecret,

    [switch]$SkipDocker,

    [switch]$SkipGatewayStatus,

    [switch]$SkipWebhookPost,

    [switch]$RunDoctor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = New-Object System.Collections.Generic.List[string]

function Test-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    Write-Host "[CHECK] $Name" -ForegroundColor Cyan
    try {
        & $Action
        Write-Host "[PASS]  $Name" -ForegroundColor Green
    }
    catch {
        $script:failures.Add("$Name :: $($_.Exception.Message)")
        Write-Host "[FAIL]  $Name" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkRed
    }
    Write-Host ''
}

function Assert-HealthyResponse {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedChannel
    )

    $response = Invoke-RestMethod -Uri $Url -Method Get
    if ($response.status -ne 'healthy') {
        throw "Unexpected status '$($response.status)' from $Url"
    }
    if ($response.channel -ne $ExpectedChannel) {
        throw "Unexpected channel '$($response.channel)' from $Url"
    }
}

function New-HmacSignature {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Secret,

        [Parameter(Mandatory = $true)]
        [string]$Body
    )

    $hmac = [System.Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($Secret))
    try {
        $sigBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($Body))
    }
    finally {
        $hmac.Dispose()
    }

    $sigHex = ([BitConverter]::ToString($sigBytes)).Replace('-', '').ToLowerInvariant()
    return "sha256=$sigHex"
}

if (-not $SkipDocker) {
    Test-Step -Name 'docker compose ps' -Action {
        & docker compose ps
        if ($LASTEXITCODE -ne 0) {
            throw 'docker compose ps failed.'
        }
    }
}

if ($RunDoctor) {
    Test-Step -Name 'ironclaw doctor' -Action {
        & docker compose exec app ironclaw doctor
        if ($LASTEXITCODE -ne 0) {
            throw 'docker compose exec app ironclaw doctor failed.'
        }
    }
}

Test-Step -Name 'gateway health' -Action {
    Assert-HealthyResponse -Url "$GatewayUrl/api/health" -ExpectedChannel 'gateway'
}

Test-Step -Name 'http webhook health' -Action {
    Assert-HealthyResponse -Url "$WebhookUrl/health" -ExpectedChannel 'http'
}

if (-not $SkipGatewayStatus) {
    if ([string]::IsNullOrWhiteSpace($GatewayAuthToken)) {
        Write-Host '[SKIP]  gateway status requires -GatewayAuthToken' -ForegroundColor Yellow
        Write-Host ''
    }
    else {
        Test-Step -Name 'gateway authenticated status' -Action {
            $headers = @{ Authorization = "Bearer $GatewayAuthToken" }
            $response = Invoke-RestMethod -Uri "$GatewayUrl/api/gateway/status" -Headers $headers -Method Get
            if (-not $response.version) {
                throw 'Gateway status response did not include a version field.'
            }
        }
    }
}

if (-not $SkipWebhookPost) {
    if ([string]::IsNullOrWhiteSpace($HttpWebhookSecret)) {
        Write-Host '[SKIP]  signed webhook POST requires -HttpWebhookSecret' -ForegroundColor Yellow
        Write-Host ''
    }
    else {
        Test-Step -Name 'signed webhook POST' -Action {
            $body = '{"content":"fresh-check webhook test","wait_for_response":false}'
            $signature = New-HmacSignature -Secret $HttpWebhookSecret -Body $body
            $headers = @{
                'X-Hub-Signature-256' = $signature
                'Content-Type' = 'application/json'
            }
            $response = Invoke-RestMethod -Uri "$WebhookUrl/webhook" -Method Post -Headers $headers -Body $body
            if (-not $response.message_id) {
                throw 'Webhook response did not include message_id.'
            }
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host 'Checks failed:' -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host "- $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host 'All requested checks passed.' -ForegroundColor Green