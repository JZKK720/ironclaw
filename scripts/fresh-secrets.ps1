[CmdletBinding()]
param(
    [ValidateRange(16, 128)]
    [int]$Bytes = 32,

    [switch]$IncludeMasterKey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-HexSecret {
    param(
        [Parameter(Mandatory = $true)]
        [int]$SecretBytes
    )

    $buffer = New-Object byte[] $SecretBytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($buffer)
    }
    finally {
        $rng.Dispose()
    }
    return ([System.BitConverter]::ToString($buffer)).Replace('-', '').ToLowerInvariant()
}

$gatewayAuthToken = New-HexSecret -SecretBytes $Bytes
$httpWebhookSecret = New-HexSecret -SecretBytes $Bytes

Write-Output '# Paste these into .env'
Write-Output "GATEWAY_AUTH_TOKEN=$gatewayAuthToken"
Write-Output "HTTP_WEBHOOK_SECRET=$httpWebhookSecret"

if ($IncludeMasterKey) {
    $secretsMasterKey = New-HexSecret -SecretBytes $Bytes
    Write-Output "SECRETS_MASTER_KEY=$secretsMasterKey"
}