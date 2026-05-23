#![cfg(feature = "libsql")]

use std::collections::HashMap;
use std::sync::Arc;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use ironclaw::history::SandboxJobRecord;
use ironclaw::orchestrator::api::OrchestratorState;
use ironclaw::orchestrator::{
    ContainerJobConfig, ContainerJobManager, OrchestratorApi, TokenStore,
};
use ironclaw::testing::StubLlm;
use tokio::sync::Mutex;
use tower::ServiceExt;
use uuid::Uuid;

#[tokio::test]
async fn report_complete_persists_sandbox_job_status() {
    let (db, _tmp) = ironclaw::testing::test_db().await;
    let token_store = TokenStore::new();
    let jm = ContainerJobManager::new(ContainerJobConfig::default(), token_store.clone());
    let job_id = Uuid::new_v4();
    let token = token_store.create_token(job_id).await;
    let now = chrono::Utc::now();

    db.save_sandbox_job(&SandboxJobRecord {
        id: job_id,
        task: "Sandbox health check".to_string(),
        status: "running".to_string(),
        user_id: "default".to_string(),
        project_dir: "/workspace/test".to_string(),
        success: None,
        failure_reason: None,
        created_at: now,
        started_at: Some(now),
        completed_at: None,
        credential_grants_json: "[]".to_string(),
        mcp_servers: None,
        max_iterations: None,
    })
    .await
    .unwrap();

    let state = OrchestratorState {
        llm: Arc::new(StubLlm::default()),
        job_manager: Arc::new(jm),
        token_store,
        job_event_tx: None,
        prompt_queue: Arc::new(Mutex::new(HashMap::new())),
        store: Some(db.clone()),
        secrets_store: None,
        job_owner_cache: Arc::new(std::sync::RwLock::new(HashMap::new())),
    };

    let router = OrchestratorApi::router(state);
    let payload = serde_json::json!({
        "success": true,
        "message": "Job completed successfully"
    });

    let req = Request::builder()
        .method("POST")
        .uri(format!("/worker/{}/complete", job_id))
        .header("Authorization", format!("Bearer {}", token))
        .header("Content-Type", "application/json")
        .body(Body::from(serde_json::to_vec(&payload).unwrap()))
        .unwrap();

    let resp = router.oneshot(req).await.unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let updated = db
        .get_sandbox_job(job_id)
        .await
        .unwrap()
        .expect("sandbox job should still exist");
    assert_eq!(updated.status, "completed");
    assert_eq!(updated.success, Some(true));
    assert!(updated.completed_at.is_some());
    assert_eq!(updated.failure_reason, None);
}
