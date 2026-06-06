use std::path::PathBuf;

fn runtime_dockerfile() -> String {
    let repo_root = std::env::var_os("CARGO_MANIFEST_DIR")
        .map(PathBuf::from)
        .or_else(|| std::env::current_dir().ok())
        .expect("repo root should be discoverable");
    let path = repo_root.join("Dockerfile");
    std::fs::read_to_string(path).expect("Dockerfile should be readable")
}

fn docker_compose_override() -> String {
    let repo_root = std::env::var_os("CARGO_MANIFEST_DIR")
        .map(PathBuf::from)
        .or_else(|| std::env::current_dir().ok())
        .expect("repo root should be discoverable");
    let path = repo_root.join("docker-compose.override.yml");
    std::fs::read_to_string(path).expect("docker-compose.override.yml should be readable")
}

#[test]
fn runtime_image_declares_and_prepares_ironclaw_home() {
    let dockerfile = runtime_dockerfile();

    assert!(
        dockerfile.contains("useradd -m -d /home/ironclaw -u 1000 ironclaw"),
        "runtime image must create the ironclaw user with the expected home directory",
    );
    assert!(
        dockerfile.contains("ENV HOME=/home/ironclaw"),
        "runtime image must set HOME to /home/ironclaw for ~/.ironclaw state",
    );
    assert!(
        dockerfile.contains("WORKDIR /home/ironclaw"),
        "runtime image must start in the ironclaw home directory",
    );
    assert!(
        dockerfile.contains("mkdir -p /home/ironclaw/.ironclaw"),
        "runtime image must pre-create ~/.ironclaw before dropping privileges",
    );
    assert!(
        dockerfile.contains("ENV GATEWAY_HOST=0.0.0.0"),
        "runtime image must bind the gateway to 0.0.0.0 inside containers so published host ports can reach it",
    );
}

#[test]
fn compose_override_forces_headless_runtime_bootstrap() {
    let compose_override = docker_compose_override();

    assert!(
        compose_override.contains("  ironclaw:\n"),
        "compose override must expose the runtime under the documented ironclaw service name",
    );
    assert!(
        compose_override.contains("command: run"),
        "compose override must start the runtime with `ironclaw run` instead of the bare CLI entrypoint",
    );
    assert!(
        compose_override.contains("ONBOARD_COMPLETED: \"true\""),
        "compose override must mark headless runtime onboarding as completed so the setup wizard does not block startup",
    );
    assert!(
        compose_override.contains("GATEWAY_HOST: 0.0.0.0"),
        "compose override must bind the gateway to 0.0.0.0 inside Docker so the published host port can reach it",
    );
    assert!(
        compose_override.contains("CLI_ENABLED: \"false\""),
        "compose override must disable CLI mode so the headless Docker runtime does not wait on stdin",
    );
    assert!(
        compose_override.contains("name: ironclaw-pgdata"),
        "compose override must reuse the canonical external postgres volume so recreates keep the existing local database",
    );
}
