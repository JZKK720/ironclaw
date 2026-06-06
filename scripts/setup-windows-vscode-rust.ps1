[CmdletBinding()]
param(
    [switch]$BootstrapOnly,
    [switch]$PrintEnv,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$devRoot = Join-Path $repoRoot '.ironclaw-dev\windows-rust'
$cargoHome = Join-Path $devRoot 'cargo-home'
$rustupHome = Join-Path $devRoot 'rustup-home'
$cargoBin = Join-Path $cargoHome 'bin'
$cargoExe = Join-Path $cargoBin 'cargo.exe'
$rustupExe = Join-Path $cargoBin 'rustup.exe'
$rustfmtExe = Join-Path $cargoBin 'rustfmt.exe'
$wasmToolsExe = Join-Path $cargoBin 'wasm-tools.exe'
$toolchainFile = Join-Path $repoRoot 'rust-toolchain.toml'
$wasmToolsVersion = '1.246.1'

function Get-RequiredToolchain {
    if (Test-Path $toolchainFile) {
        $match = Select-String -Path $toolchainFile -Pattern '^\s*channel\s*=\s*"([^"]+)"\s*$' | Select-Object -First 1
        if ($match) {
            return $match.Matches[0].Groups[1].Value
        }
    }

    return '1.92.0'
}

$requiredToolchain = Get-RequiredToolchain

function Invoke-WorkspaceCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$Arguments = @()
    )

    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
    return $process.ExitCode
}

function Use-WorkspaceRustEnvironment {
    New-Item -ItemType Directory -Force -Path $cargoHome, $rustupHome, $cargoBin | Out-Null
    $env:CARGO_HOME = $cargoHome
    $env:RUSTUP_HOME = $rustupHome
    $env:PATH = "$cargoBin;$env:PATH"
}

function Test-WorkspaceToolchain {
    if (-not (Test-Path $rustupExe)) {
        return $false
    }

    $toolchainList = & $rustupExe toolchain list 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    return [bool]($toolchainList | Select-String -SimpleMatch $requiredToolchain)
}

function Install-Rustup {
    if (Test-Path $rustupExe) {
        return
    }

    $installerPath = Join-Path ([System.IO.Path]::GetTempPath()) 'rustup-init.exe'
    try {
        Invoke-WebRequest -Uri 'https://win.rustup.rs/x86_64' -OutFile $installerPath
        $exitCode = Invoke-WorkspaceCommand -FilePath $installerPath -Arguments @('-y', '--default-toolchain', 'none', '--no-modify-path')
        if ($exitCode -ne 0) {
            throw "rustup-init failed with exit code $exitCode"
        }
    }
    finally {
        if (Test-Path $installerPath) {
            Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Install-WorkspaceToolchain {
    Install-Rustup

    if (-not (Test-WorkspaceToolchain)) {
        $exitCode = Invoke-WorkspaceCommand -FilePath $rustupExe -Arguments @('toolchain', 'install', $requiredToolchain, '--profile', 'minimal', '--component', 'clippy', '--component', 'rustfmt')
        if ($exitCode -ne 0) {
            throw "Rust toolchain install failed with exit code $exitCode"
        }
    }

    $exitCode = Invoke-WorkspaceCommand -FilePath $rustupExe -Arguments @('target', 'add', 'wasm32-wasip2', '--toolchain', $requiredToolchain)
    if ($exitCode -ne 0) {
        throw "wasm32-wasip2 target install failed with exit code $exitCode"
    }

    if (-not (Test-Path $wasmToolsExe)) {
        Install-WasmToolsBinary
    }
}

function Get-WasmToolsAssetName {
    $architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture

    switch ($architecture) {
        'X64' { return "wasm-tools-$wasmToolsVersion-x86_64-windows.zip" }
        'Arm64' { return "wasm-tools-$wasmToolsVersion-aarch64-windows.zip" }
        default { throw "Unsupported Windows architecture for wasm-tools bootstrap: $architecture" }
    }
}

function Install-WasmToolsBinary {
    $assetName = Get-WasmToolsAssetName
    $downloadUrl = "https://github.com/bytecodealliance/wasm-tools/releases/download/v$wasmToolsVersion/$assetName"
    $archivePath = Join-Path ([System.IO.Path]::GetTempPath()) $assetName
    $extractRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wasm-tools-" + [System.Guid]::NewGuid().ToString('N'))

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath
        Expand-Archive -Path $archivePath -DestinationPath $extractRoot -Force

        $downloadedExe = Get-ChildItem -Path $extractRoot -Filter 'wasm-tools.exe' -File -Recurse | Select-Object -First 1
        if (-not $downloadedExe) {
            throw "wasm-tools.exe was not found in $assetName"
        }

        Copy-Item $downloadedExe.FullName $wasmToolsExe -Force
    }
    finally {
        if (Test-Path $archivePath) {
            Remove-Item $archivePath -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path $extractRoot) {
            Remove-Item $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Resolve-CommandPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    switch ($CommandName) {
        'cargo' { return $cargoExe }
        'rustup' { return $rustupExe }
        'rustfmt' { return $rustfmtExe }
        'wasm-tools' { return $wasmToolsExe }
        default { return $CommandName }
    }
}

function Assert-WorkspaceToolchain {
    if (-not (Test-Path $cargoExe) -or -not (Test-WorkspaceToolchain)) {
        Write-Error "IronClaw local Windows Rust tooling is not bootstrapped yet. Run the VS Code task 'Rust: Bootstrap local Windows toolchain' once."
        exit 1
    }
}

Use-WorkspaceRustEnvironment
Set-Location $repoRoot

if ($PrintEnv) {
    Write-Output "CARGO_HOME=$cargoHome"
    Write-Output "RUSTUP_HOME=$rustupHome"
    Write-Output "CARGO_BIN=$cargoBin"
    Write-Output "RUST_TOOLCHAIN=$requiredToolchain"
    exit 0
}

if ($BootstrapOnly) {
    Install-WorkspaceToolchain
    exit 0
}

if ($CommandArgs.Count -eq 0) {
    Assert-WorkspaceToolchain
    & $cargoExe --version
    exit $LASTEXITCODE
}

Assert-WorkspaceToolchain

$commandPath = Resolve-CommandPath -CommandName $CommandArgs[0]
$forwardedArgs = if ($CommandArgs.Count -gt 1) {
    $CommandArgs[1..($CommandArgs.Count - 1)]
}
else {
    @()
}

$exitCode = Invoke-WorkspaceCommand -FilePath $commandPath -Arguments $forwardedArgs
exit $exitCode