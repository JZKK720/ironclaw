#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
toolchain_file="${repo_root}/rust-toolchain.toml"
required_toolchain="$({ sed -nE 's/^channel = "([^"]+)"$/\1/p' "${toolchain_file}" || true; } | head -n 1)"

if [ -z "${required_toolchain}" ]; then
    required_toolchain='1.92.0'
fi

echo "Configuring IronClaw Rust tooling..."

if rustup toolchain list | grep -q "^${required_toolchain}"; then
    echo "  Rust ${required_toolchain} already installed"
else
    if rustup toolchain install "${required_toolchain}" --profile minimal --component clippy --component rustfmt; then
        echo "  installed Rust ${required_toolchain}"
    else
        echo "  warning: failed to install Rust ${required_toolchain}; rerun 'rustup toolchain install ${required_toolchain} --profile minimal --component clippy --component rustfmt' inside the container"
    fi
fi

if rustup override set "${required_toolchain}"; then
    echo "  pinned workspace to Rust ${required_toolchain}"
else
    echo "  warning: failed to pin Rust ${required_toolchain}; rerun 'rustup override set ${required_toolchain}' inside the container"
fi

if rustup target list --installed | grep -qx 'wasm32-wasip2'; then
    echo "  wasm32-wasip2 target already installed"
else
    if rustup target add wasm32-wasip2 --toolchain "${required_toolchain}"; then
        echo "  installed wasm32-wasip2 target"
    else
        echo "  warning: failed to install wasm32-wasip2 target; rerun 'rustup target add wasm32-wasip2 --toolchain ${required_toolchain}' inside the container"
    fi
fi

if command -v wasm-tools >/dev/null 2>&1; then
    echo "  wasm-tools already available: $(wasm-tools --version)"
else
    if cargo +"${required_toolchain}" install --locked wasm-tools --version 1.246.1; then
        echo "  installed wasm-tools 1.246.1"
    else
        echo "  warning: failed to install wasm-tools; rerun 'cargo +${required_toolchain} install --locked wasm-tools --version 1.246.1' inside the container"
    fi
fi