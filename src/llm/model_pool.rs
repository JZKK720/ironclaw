//! Model pool for multi-LLM configuration with runtime selection.
//!
//! This module provides environment-based multi-model support (Option A),
//! allowing users to configure multiple LLM backends and switch between them
//! at runtime via the Web UI or CLI.

use std::collections::HashMap;

use secrecy::SecretString;
use serde::{Deserialize, Serialize};

use crate::error::ConfigError;
use crate::llm::registry::{ProviderProtocol, ProviderRegistry};

/// A model configuration entry in the pool.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelPoolEntry {
    /// Unique identifier for this model config (e.g., "primary", "lmstudio")
    pub id: String,
    /// Human-readable display name
    pub name: String,
    /// Backend provider identifier (e.g., "ollama", "openai_compatible")
    pub backend: String,
    /// Base URL for the API endpoint
    pub base_url: Option<String>,
    /// Model identifier (e.g., "qwen3.5:9b", "gpt-4o")
    pub model: String,
    /// Optional API key
    #[serde(skip_serializing)]
    pub api_key: Option<SecretString>,
    /// Request timeout in seconds
    pub timeout_secs: u64,
    /// Extra HTTP headers
    pub extra_headers: Vec<(String, String)>,
    /// Provider protocol (resolved from backend)
    pub protocol: ProviderProtocol,
}

impl ModelPoolEntry {
    /// Create a provider configuration from this pool entry.
    pub fn to_registry_config(&self) -> crate::llm::config::RegistryProviderConfig {
        crate::llm::config::RegistryProviderConfig {
            protocol: self.protocol,
            provider_id: self.backend.clone(),
            api_key: self.api_key.clone(),
            base_url: self.base_url.clone().unwrap_or_default(),
            model: self.model.clone(),
            extra_headers: self.extra_headers.clone(),
            oauth_token: None,
            cache_retention: crate::llm::config::CacheRetention::default(),
            unsupported_params: Vec::new(),
        }
    }

    /// Convert to NearAiConfig for use with the LLM provider factory.
    pub fn to_nearai_config(&self) -> crate::llm::config::NearAiConfig {
        crate::llm::config::NearAiConfig {
            model: self.model.clone(),
            cheap_model: None,
            base_url: self.base_url.clone().unwrap_or_default(),
            api_key: self.api_key.clone(),
            fallback_model: None,
            max_retries: 3,
            circuit_breaker_threshold: None,
            circuit_breaker_recovery_secs: 30,
            response_cache_enabled: false,
            response_cache_ttl_secs: 3600,
            response_cache_max_entries: 1000,
            failover_cooldown_secs: 300,
            failover_cooldown_threshold: 3,
            smart_routing_cascade: true,
        }
    }
}

/// The model pool containing multiple model configurations.
#[derive(Debug, Clone, Default)]
pub struct ModelPool {
    /// All configured models
    entries: HashMap<String, ModelPoolEntry>,
    /// Currently active model ID
    active_id: Option<String>,
    /// Model IDs in order of priority (for fallback)
    order: Vec<String>,
}

impl ModelPool {
    /// Create an empty model pool.
    pub fn new() -> Self {
        Self {
            entries: HashMap::new(),
            active_id: None,
            order: Vec::new(),
        }
    }

    /// Load the model pool from environment variables.
    pub fn from_env(registry: &ProviderRegistry) -> Result<Self, ConfigError> {
        let pool_var = std::env::var("LLM_MODEL_POOL").unwrap_or_default();
        
        if pool_var.is_empty() {
            return Ok(Self::new());
        }

        let mut pool = Self::new();
        let model_ids: Vec<String> = pool_var
            .split(',')
            .map(|s| s.trim().to_lowercase())
            .filter(|s| !s.is_empty())
            .collect();

        for id in &model_ids {
            match Self::parse_model_entry(id, registry) {
                Ok(entry) => {
                    pool.entries.insert(id.clone(), entry);
                    pool.order.push(id.clone());
                }
                Err(e) => {
                    tracing::warn!("Failed to parse model '{}' from pool: {}", id, e);
                }
            }
        }

        // Set active model
        if let Ok(active) = std::env::var("LLM_MODEL_ACTIVE") {
            let active_lower = active.to_lowercase();
            if pool.entries.contains_key(&active_lower) {
                pool.active_id = Some(active_lower);
            } else {
                tracing::warn!(
                    "LLM_MODEL_ACTIVE='{}' not found in pool, using first available",
                    active
                );
                pool.active_id = pool.order.first().cloned();
            }
        } else {
            pool.active_id = pool.order.first().cloned();
        }

        if !pool.entries.is_empty() {
            tracing::info!(
                "Loaded model pool with {} models, active: {:?}",
                pool.entries.len(),
                pool.active_id
            );
        }

        Ok(pool)
    }

    /// Parse a single model entry from environment variables.
    fn parse_model_entry(
        id: &str,
        registry: &ProviderRegistry,
    ) -> Result<ModelPoolEntry, ConfigError> {
        let prefix = format!("LLM_MODEL_{}_", id.to_uppercase());

        let backend = std::env::var(format!("{}BACKEND", prefix))
            .map_err(|_| ConfigError::MissingRequired {
                key: format!("{}BACKEND", prefix),
                hint: format!("Model '{}' requires BACKEND", id),
            })?;

        let model = std::env::var(format!("{}MODEL", prefix))
            .map_err(|_| ConfigError::MissingRequired {
                key: format!("{}MODEL", prefix),
                hint: format!("Model '{}' requires MODEL", id),
            })?;

        let base_url = std::env::var(format!("{}BASE_URL", prefix)).ok();
        let api_key = std::env::var(format!("{}API_KEY", prefix))
            .ok()
            .map(SecretString::from);
        let timeout_secs = std::env::var(format!("{}TIMEOUT_SECS", prefix))
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(120);
        let extra_headers = std::env::var(format!("{}EXTRA_HEADERS", prefix))
            .ok()
            .map(|val| parse_extra_headers(&val))
            .transpose()
            .map_err(|e| ConfigError::InvalidValue {
                key: format!("{}EXTRA_HEADERS", prefix),
                message: e.to_string(),
            })?
            .unwrap_or_default();

        let backend_lower = backend.to_lowercase();
        let protocol = if let Some(def) = registry.find(&backend_lower) {
            def.protocol
        } else if backend_lower == "nearai" || backend_lower == "near" {
            ProviderProtocol::OpenAiCompletions
        } else {
            tracing::warn!(
                "Unknown backend '{}', defaulting to open_ai_completions",
                backend
            );
            ProviderProtocol::OpenAiCompletions
        };

        Ok(ModelPoolEntry {
            id: id.to_string(),
            name: id.to_string(),
            backend: backend_lower,
            base_url,
            model,
            api_key,
            timeout_secs,
            extra_headers,
            protocol,
        })
    }

    pub fn entries(&self) -> &HashMap<String, ModelPoolEntry> {
        &self.entries
    }

    pub fn order(&self) -> &[String] {
        &self.order
    }

    pub fn active_id(&self) -> Option<&str> {
        self.active_id.as_deref()
    }

    pub fn active(&self) -> Option<&ModelPoolEntry> {
        self.active_id.as_ref().and_then(|id| self.entries.get(id))
    }

    pub fn get(&self, id: &str) -> Option<&ModelPoolEntry> {
        self.entries.get(&id.to_lowercase())
    }

    pub fn set_active(&mut self, id: &str) -> Result<(), String> {
        let id_lower = id.to_lowercase();
        if self.entries.contains_key(&id_lower) {
            self.active_id = Some(id_lower);
            Ok(())
        } else {
            Err(format!("Model '{}' not found in pool", id))
        }
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn ordered_entries(&self) -> Vec<&ModelPoolEntry> {
        self.order
            .iter()
            .filter_map(|id| self.entries.get(id))
            .collect()
    }

    /// Get the next model in the pool for failover.
    /// Returns None if at the end of the pool.
    pub fn next_model(&self, current_id: &str) -> Option<&ModelPoolEntry> {
        let current_lower = current_id.to_lowercase();
        let mut found_current = false;
        
        for id in &self.order {
            if found_current {
                return self.entries.get(id);
            }
            if id == &current_lower {
                found_current = true;
            }
        }
        None
    }
}

fn parse_extra_headers(val: &str) -> Result<Vec<(String, String)>, String> {
    if val.trim().is_empty() {
        return Ok(Vec::new());
    }

    let mut headers = Vec::new();
    for pair in val.split(',') {
        let pair = pair.trim();
        if pair.is_empty() {
            continue;
        }
        let Some((key, value)) = pair.split_once(':') else {
            return Err(format!(
                "malformed header entry '{}', expected Key:Value",
                pair
            ));
        };
        let key = key.trim();
        if key.is_empty() {
            return Err(format!("empty header name in entry '{}'", pair));
        }
        headers.push((key.to_string(), value.trim().to_string()));
    }
    Ok(headers)
}

/// Thread-safe model pool handle for runtime model switching.
#[derive(Clone)]
pub struct ModelPoolHandle {
    inner: std::sync::Arc<std::sync::RwLock<ModelPool>>,
}

impl ModelPoolHandle {
    pub fn new(pool: ModelPool) -> Self {
        Self {
            inner: std::sync::Arc::new(std::sync::RwLock::new(pool)),
        }
    }

    pub fn active_id(&self) -> Option<String> {
        self.inner.read().ok()?.active_id.clone()
    }

    pub fn active(&self) -> Option<ModelPoolEntry> {
        self.inner.read().ok()?.active().cloned()
    }

    pub fn list(&self) -> Vec<ModelPoolEntry> {
        self.inner
            .read()
            .ok()
            .map(|p| p.entries().values().cloned().collect())
            .unwrap_or_default()
    }

    pub fn switch_to(&self, id: &str) -> Result<(), String> {
        let mut pool = self
            .inner
            .write()
            .map_err(|_| "Failed to acquire write lock".to_string())?;
        pool.set_active(id)
    }

    pub fn get(&self, id: &str) -> Option<ModelPoolEntry> {
        self.inner.read().ok()?.get(id).cloned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_extra_headers() {
        let result = parse_extra_headers("X-Custom:value,Authorization:Bearer token").unwrap();
        assert_eq!(result.len(), 2);
        assert_eq!(result[0], ("X-Custom".to_string(), "value".to_string()));
        assert_eq!(
            result[1],
            ("Authorization".to_string(), "Bearer token".to_string())
        );
    }

    #[test]
    fn test_parse_extra_headers_empty() {
        let result = parse_extra_headers("").unwrap();
        assert!(result.is_empty());
    }

    #[test]
    fn test_parse_extra_headers_malformed() {
        let result = parse_extra_headers("NoColonHere");
        assert!(result.is_err());
    }
}
