//! Runtime skill catalog backed by ClawHub's public registry.
//!
//! Fetches skill listings from the ClawHub API (`/api/v1/search`) at runtime,
//! caching results in memory. No compile-time entries -- the catalog is always
//! up-to-date with the registry.
//!
//! Configuration:
//! - `CLAWHUB_REGISTRY` env var overrides the default base URL

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;

use crate::validation::normalize_skill_identifier;

/// Default ClawHub registry URL.
///
/// Points directly at the Convex backend, bypassing Vercel's edge which
/// rejects non-browser TLS fingerprints (JA3/JA4 filtering).
const DEFAULT_REGISTRY_URL: &str = "https://wry-manatee-359.convex.site";

/// How long cached search results remain valid (5 minutes).
const CACHE_TTL: Duration = Duration::from_secs(300);

/// Maximum number of results to return from a search.
const MAX_RESULTS: usize = 25;

/// HTTP request timeout for catalog queries.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(10);

fn normalize_registry_url(value: &str) -> String {
    value.trim().trim_end_matches('/').to_string()
}

fn push_registry_candidate(candidates: &mut Vec<String>, registry_url: &str) {
    let normalized = normalize_registry_url(registry_url);
    if normalized.is_empty()
        || candidates
            .iter()
            .any(|candidate| candidate.eq_ignore_ascii_case(&normalized))
    {
        return;
    }

    candidates.push(normalized);
}

/// Result of a catalog search, carrying both results and any error that occurred.
#[derive(Debug, Clone)]
pub struct CatalogSearchOutcome {
    /// Skill entries returned by the search (empty on error).
    pub results: Vec<CatalogEntry>,
    /// If the registry was unreachable or returned an error, a human-readable message.
    pub error: Option<String>,
}

/// A skill entry from the ClawHub catalog.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CatalogEntry {
    /// Skill slug (unique identifier, e.g. "owner/skill-name").
    pub slug: String,
    /// Display name.
    pub name: String,
    /// Short description.
    #[serde(default)]
    pub description: String,
    /// Skill version (semver).
    #[serde(default)]
    pub version: String,
    /// Relevance score from the search API.
    #[serde(default)]
    pub score: f64,
    /// Last updated timestamp (epoch milliseconds from registry).
    #[serde(default)]
    pub updated_at: Option<u64>,
    /// Star count (populated via detail enrichment).
    #[serde(default)]
    pub stars: Option<u64>,
    /// Total download count (populated via detail enrichment).
    #[serde(default)]
    pub downloads: Option<u64>,
    /// Current install count (populated via detail enrichment).
    #[serde(default)]
    pub installs_current: Option<u64>,
    /// Owner handle (populated via detail enrichment).
    #[serde(default)]
    pub owner: Option<String>,
}

/// Error when a human-readable catalog name cannot be resolved safely.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum CatalogResolveError {
    #[error("Skill name '{name}' matches multiple catalog entries; use a slug instead ({matches})")]
    AmbiguousName { name: String, matches: String },
}

fn normalize_catalog_identity(value: &str) -> String {
    value
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .map(|c| c.to_ascii_lowercase())
        .collect()
}

fn slug_suffix(slug: &str) -> &str {
    slug.rsplit('/').next().unwrap_or(slug)
}

/// Resolve a display name or suffix-like query to a unique catalog slug.
pub fn resolve_catalog_slug_for_name(
    name: &str,
    entries: &[CatalogEntry],
) -> Result<Option<String>, CatalogResolveError> {
    let normalized_name = normalize_catalog_identity(name);
    if normalized_name.is_empty() {
        return Ok(None);
    }

    let collect_matches = |predicate: &dyn Fn(&CatalogEntry) -> bool| -> Vec<String> {
        let mut matches: Vec<String> = entries
            .iter()
            .filter(|entry| predicate(entry))
            .map(|entry| entry.slug.clone())
            .collect();

        matches.sort();
        matches.dedup();
        matches
    };

    let exact_name = name.to_ascii_lowercase();
    let matches = collect_matches(&|entry| entry.name.to_ascii_lowercase() == exact_name);
    if matches.len() == 1 {
        return Ok(matches.into_iter().next());
    }
    if matches.len() > 1 {
        return Err(CatalogResolveError::AmbiguousName {
            name: name.to_string(),
            matches: matches.join(", "),
        });
    }

    let matches = collect_matches(&|entry| {
        normalize_catalog_identity(&entry.name) == normalized_name
            || normalize_catalog_identity(slug_suffix(&entry.slug)) == normalized_name
    });

    match matches.len() {
        0 => Ok(None),
        1 => Ok(matches.into_iter().next()),
        _ => Err(CatalogResolveError::AmbiguousName {
            name: name.to_string(),
            matches: matches.join(", "),
        }),
    }
}

/// Whether a catalog entry should be marked as installed for a set of local names.
pub fn catalog_entry_is_installed(slug: &str, name: &str, installed_names: &[String]) -> bool {
    let normalized_slug_name = normalize_skill_identifier(slug);
    let slug_suffix = slug_suffix(slug);
    installed_names.iter().any(|installed| {
        slug.eq_ignore_ascii_case(installed)
            || slug_suffix.eq_ignore_ascii_case(installed)
            || name.eq_ignore_ascii_case(installed)
            || normalized_slug_name
                .as_deref()
                .is_some_and(|n| n.eq_ignore_ascii_case(installed))
    })
}

/// Top-level wrapper from the ClawHub `/api/v1/skills/{slug}` response.
///
/// The API returns `{"skill": {...}, "owner": {...}, "latestVersion": {...}}`.
#[derive(Debug, Clone, Deserialize)]
struct SkillDetailResponse {
    skill: SkillDetailInner,
    #[serde(default)]
    owner: Option<SkillOwner>,
}

/// Inner `skill` object within `SkillDetailResponse`.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SkillDetailInner {
    pub slug: String,
    #[serde(default)]
    pub display_name: Option<String>,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub stats: Option<SkillStats>,
    #[serde(default)]
    pub updated_at: Option<u64>,
}

/// Detailed skill information from the ClawHub `/api/v1/skills/{slug}` endpoint.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SkillDetail {
    pub slug: String,
    #[serde(default)]
    pub display_name: Option<String>,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub version: Option<String>,
    #[serde(default)]
    pub stats: Option<SkillStats>,
    #[serde(default)]
    pub owner: Option<SkillOwner>,
    #[serde(default)]
    pub updated_at: Option<u64>,
}

/// Statistics for a skill from the ClawHub detail endpoint.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SkillStats {
    #[serde(default)]
    pub stars: Option<u64>,
    #[serde(default)]
    pub downloads: Option<u64>,
    #[serde(default)]
    pub installs_current: Option<u64>,
    #[serde(default)]
    pub installs_all_time: Option<u64>,
    #[serde(default)]
    pub versions: Option<u64>,
}

/// Owner information for a skill.
#[derive(Debug, Clone, Deserialize)]
pub struct SkillOwner {
    #[serde(default)]
    pub handle: Option<String>,
    #[serde(default, rename = "displayName")]
    pub display_name: Option<String>,
}

/// Cached search result with TTL.
struct CachedSearch {
    query: String,
    outcome: CatalogSearchOutcome,
    fetched_at: Instant,
}

/// Runtime skill catalog that queries ClawHub's API.
pub struct SkillCatalog {
    /// Base URL for the registry.
    registry_url: String,
    /// Additional registry URLs to try if the primary URL fails.
    fallback_registry_urls: Vec<String>,
    /// HTTP client (reused across requests).
    client: reqwest::Client,
    /// In-memory search cache keyed by query string.
    cache: RwLock<Vec<CachedSearch>>,
    /// Last registry URL that successfully served a request.
    last_successful_registry_url: Mutex<String>,
}

impl SkillCatalog {
    fn with_urls_and_timeout(url: &str, fallback_registry_urls: Vec<String>, timeout: Duration) -> Self {
        let registry_url = {
            let normalized = normalize_registry_url(url);
            if normalized.is_empty() {
                DEFAULT_REGISTRY_URL.to_string()
            } else {
                normalized
            }
        };

        let fallback_registry_urls = fallback_registry_urls
            .into_iter()
            .map(|candidate| normalize_registry_url(&candidate))
            .filter(|candidate| {
                !candidate.is_empty() && !candidate.eq_ignore_ascii_case(&registry_url)
            })
            .collect();

        let client = reqwest::Client::builder()
            .timeout(timeout)
            .user_agent(concat!("ironclaw/", env!("CARGO_PKG_VERSION")))
            .build()
            .unwrap_or_else(|e| {
                tracing::warn!("Failed to build HTTP client: {e}");
                reqwest::Client::default()
            });

        Self {
            registry_url: registry_url.clone(),
            fallback_registry_urls,
            client,
            cache: RwLock::new(Vec::new()),
            last_successful_registry_url: Mutex::new(registry_url),
        }
    }

    /// Create a new catalog.
    ///
    /// Reads `CLAWHUB_REGISTRY` (or legacy `CLAWDHUB_REGISTRY`) from the
    /// environment, falling back to the Convex backend.
    pub fn new() -> Self {
        let registry_url = std::env::var("CLAWHUB_REGISTRY")
            .or_else(|_| std::env::var("CLAWDHUB_REGISTRY"))
            .map(|value| normalize_registry_url(&value))
            .unwrap_or_else(|_| DEFAULT_REGISTRY_URL.to_string());

        let fallback_registry_urls = if registry_url.eq_ignore_ascii_case(DEFAULT_REGISTRY_URL) {
            Vec::new()
        } else {
            vec![DEFAULT_REGISTRY_URL.to_string()]
        };

        Self::with_urls_and_timeout(&registry_url, fallback_registry_urls, REQUEST_TIMEOUT)
    }

    /// Create a catalog with a custom registry URL (for testing).
    pub fn with_url(url: &str) -> Self {
        Self::with_urls_and_timeout(url, Vec::new(), REQUEST_TIMEOUT)
    }

    /// Create a catalog with a custom registry URL and timeout (for testing).
    pub fn with_url_and_timeout(url: &str, timeout: Duration) -> Self {
        Self::with_urls_and_timeout(url, Vec::new(), timeout)
    }

    fn candidate_registry_urls(&self) -> Vec<String> {
        let mut candidates = Vec::with_capacity(self.fallback_registry_urls.len() + 2);
        let active_registry_url = self.resolved_registry_url();

        push_registry_candidate(&mut candidates, &active_registry_url);
        push_registry_candidate(&mut candidates, &self.registry_url);
        for registry_url in &self.fallback_registry_urls {
            push_registry_candidate(&mut candidates, registry_url);
        }

        candidates
    }

    fn note_successful_registry_url(&self, registry_url: &str) {
        let normalized = normalize_registry_url(registry_url);
        if normalized.is_empty() {
            return;
        }

        match self.last_successful_registry_url.lock() {
            Ok(mut current) => *current = normalized,
            Err(e) => tracing::warn!(
                "Skill catalog registry URL lock poisoned while updating active registry: {}",
                e
            ),
        }
    }

    /// Get the last registry URL that successfully served a request.
    pub fn resolved_registry_url(&self) -> String {
        match self.last_successful_registry_url.lock() {
            Ok(current) => current.clone(),
            Err(e) => {
                tracing::warn!(
                    "Skill catalog registry URL lock poisoned while reading active registry: {}",
                    e
                );
                self.registry_url.clone()
            }
        }
    }

    /// Record a registry URL that successfully served a request.
    pub fn mark_registry_success(&self, registry_url: &str) {
        self.note_successful_registry_url(registry_url);
    }

    /// Search for skills in the catalog.
    ///
    /// First checks the in-memory cache. If not cached or expired, fetches
    /// from the ClawHub API. Returns a [`CatalogSearchOutcome`] that carries
    /// both results and any error that occurred (catalog search is best-effort,
    /// never blocks the agent).
    pub async fn search(&self, query: &str) -> CatalogSearchOutcome {
        let query_lower = query.to_lowercase();

        // Check cache
        {
            let cache = self.cache.read().await;
            if let Some(cached) = cache.iter().find(|c| c.query == query_lower)
                && cached.fetched_at.elapsed() < CACHE_TTL
            {
                return cached.outcome.clone();
            }
        }

        // Fetch from API
        let outcome = self.fetch_search(&query_lower).await;

        // Update cache
        {
            let mut cache = self.cache.write().await;
            // Remove stale entry for this query
            cache.retain(|c| c.query != query_lower);
            if outcome.error.is_none() {
                // Limit cache size to prevent unbounded growth
                if cache.len() >= 50 {
                    cache.remove(0);
                }
                cache.push(CachedSearch {
                    query: query_lower,
                    outcome: outcome.clone(),
                    fetched_at: Instant::now(),
                });
            }
        }

        outcome
    }

    /// Fetch search results from the ClawHub API.
    async fn fetch_search(&self, query: &str) -> CatalogSearchOutcome {
        let mut last_error = None;

        for registry_url in self.candidate_registry_urls() {
            match self.fetch_search_from_registry(&registry_url, query).await {
                Ok(results) => {
                    self.note_successful_registry_url(&registry_url);
                    return CatalogSearchOutcome {
                        results,
                        error: None,
                    };
                }
                Err(error) => {
                    tracing::debug!(
                        "Catalog search via '{}' failed: {}",
                        registry_url,
                        error
                    );
                    last_error = Some(error);
                }
            }
        }

        let error = last_error.unwrap_or_else(|| "Registry unreachable".to_string());
        tracing::warn!(
            "Catalog search failed for '{}' across all registry URLs: {}",
            query,
            error
        );
        CatalogSearchOutcome {
            results: Vec::new(),
            error: Some(error),
        }
    }

    async fn fetch_search_from_registry(
        &self,
        registry_url: &str,
        query: &str,
    ) -> Result<Vec<CatalogEntry>, String> {
        let url = format!("{}/api/v1/search", registry_url);

        let response = self
            .client
            .get(&url)
            .query(&[("q", query)])
            .send()
            .await
            .map_err(|e| {
                tracing::debug!(
                    "Catalog search failed (network) via '{}': {}",
                    registry_url,
                    e
                );
                "Registry unreachable".to_string()
            })?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response
                .text()
                .await
                .unwrap_or_else(|_| "(no body)".to_string());
            tracing::debug!(
                "Catalog search via '{}' returned status {}: {}",
                registry_url,
                status,
                body
            );
            return Err(format!("Registry returned status {status}"));
        }

        // Parse the response body as text first so we can try multiple formats.
        let body = response.text().await.map_err(|e| {
            tracing::debug!(
                "Catalog search via '{}' failed to read response body: {}",
                registry_url,
                e
            );
            "Failed to read registry response".to_string()
        })?;

        // Try wrapped format first: {"results": [...]}
        // Then fall back to bare array: [...]
        let raw_results = if let Ok(envelope) = serde_json::from_str::<CatalogSearchEnvelope>(&body)
        {
            envelope.results
        } else if let Ok(arr) = serde_json::from_str::<Vec<CatalogSearchResult>>(&body) {
            arr
        } else {
            let preview = body.get(..200).unwrap_or(&body);
            tracing::debug!(
                "Catalog search via '{}' failed to parse response: {}",
                registry_url,
                preview
            );
            return Err("Invalid response from registry".to_string());
        };

        Ok(raw_results
            .into_iter()
            .take(MAX_RESULTS)
            .map(|r| CatalogEntry {
                slug: r.slug,
                name: r.display_name.unwrap_or_default(),
                description: r.summary.unwrap_or_default(),
                version: r.version.unwrap_or_default(),
                score: r.score.unwrap_or(0.0),
                updated_at: r.updated_at,
                stars: None,
                downloads: None,
                installs_current: None,
                owner: None,
            })
            .collect())
    }

    /// Fetch detailed information for a single skill by slug.
    ///
    /// Calls `GET /api/v1/skills/{slug}` and returns the detail if available.
    /// Returns `None` on any network or parse error (best-effort).
    pub async fn fetch_skill_detail(&self, slug: &str) -> Option<SkillDetail> {
        let mut last_error = None;

        for registry_url in self.candidate_registry_urls() {
            match self.fetch_skill_detail_from_registry(&registry_url, slug).await {
                Ok(detail) => {
                    self.note_successful_registry_url(&registry_url);
                    return Some(detail);
                }
                Err(error) => {
                    tracing::debug!(
                        "Skill detail for '{}' via '{}' failed: {}",
                        slug,
                        registry_url,
                        error
                    );
                    last_error = Some(error);
                }
            }
        }

        if let Some(error) = last_error {
            tracing::debug!(
                "Skill detail for '{}' failed across all registry URLs: {}",
                slug,
                error
            );
        }
        None
    }

    async fn fetch_skill_detail_from_registry(
        &self,
        registry_url: &str,
        slug: &str,
    ) -> Result<SkillDetail, String> {
        let url = format!(
            "{}/api/v1/skills/{}",
            registry_url,
            urlencoding::encode(slug)
        );

        let response = self.client.get(&url).send().await.map_err(|e| {
            tracing::debug!(
                "Skill detail for '{}' failed (network) via '{}': {}",
                slug,
                registry_url,
                e
            );
            "Registry unreachable".to_string()
        })?;
        if !response.status().is_success() {
            tracing::debug!(
                "Skill detail for '{}' via '{}' returned status {}",
                slug,
                registry_url,
                response.status()
            );
            return Err(format!("Registry returned status {}", response.status()));
        }

        let wrapper = response
            .json::<SkillDetailResponse>()
            .await
            .map_err(|e| {
                tracing::debug!(
                    "Skill detail for '{}' via '{}' failed to parse: {}",
                    slug,
                    registry_url,
                    e
                );
                "Invalid response from registry".to_string()
            })?;
        let inner = wrapper.skill;
        Ok(SkillDetail {
            slug: inner.slug,
            display_name: inner.display_name,
            summary: inner.summary,
            version: None, // not returned in detail response
            stats: inner.stats,
            owner: wrapper.owner,
            updated_at: inner.updated_at,
        })
    }

    /// Enrich catalog entries with detail data (stars, downloads, owner).
    ///
    /// Fetches detail for up to `max` entries in parallel. Best-effort: entries
    /// that fail to enrich keep their `None` values.
    pub async fn enrich_search_results(&self, entries: &mut [CatalogEntry], max: usize) {
        let count = entries.len().min(max);
        if count == 0 {
            return;
        }

        let futures: Vec<_> = entries
            .iter()
            .take(count)
            .map(|e| self.fetch_skill_detail(&e.slug))
            .collect();

        let details = futures::future::join_all(futures).await;

        for (entry, detail) in entries.iter_mut().take(count).zip(details) {
            if let Some(detail) = detail {
                if let Some(ref stats) = detail.stats {
                    entry.stars = stats.stars;
                    entry.downloads = stats.downloads;
                    entry.installs_current = stats.installs_current;
                }
                if let Some(ref owner) = detail.owner {
                    entry.owner = owner.handle.clone().or_else(|| owner.display_name.clone());
                }
            }
        }
    }

    /// Get the registry base URL.
    pub fn registry_url(&self) -> &str {
        &self.registry_url
    }

    /// List registry base URLs in fallback order.
    pub fn registry_urls(&self) -> Vec<String> {
        self.candidate_registry_urls()
    }

    /// Construct candidate download URLs in fallback order for a skill slug.
    pub fn download_urls_for_slug(&self, slug: &str) -> Vec<String> {
        self.candidate_registry_urls()
            .into_iter()
            .map(|registry_url| skill_download_url(&registry_url, slug))
            .collect()
    }

    /// Clear the search cache.
    pub async fn clear_cache(&self) {
        self.cache.write().await.clear();
    }
}

impl Default for SkillCatalog {
    fn default() -> Self {
        Self::new()
    }
}

/// Wrapper for ClawHub's `{"results": [...]}` envelope.
#[derive(Debug, Deserialize)]
struct CatalogSearchEnvelope {
    results: Vec<CatalogSearchResult>,
}

/// Internal type matching ClawHub's `/api/v1/search` response items.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CatalogSearchResult {
    slug: String,
    #[serde(default)]
    display_name: Option<String>,
    #[serde(default)]
    version: Option<String>,
    #[serde(default)]
    summary: Option<String>,
    #[serde(default)]
    score: Option<f64>,
    #[serde(default)]
    updated_at: Option<u64>,
}

/// Construct the download URL for a skill's SKILL.md from the registry.
///
/// The slug is URL-encoded to prevent query string injection via special
/// characters like `&` or `#`.
pub fn skill_download_url(registry_url: &str, slug: &str) -> String {
    format!(
        "{}/api/v1/download?slug={}",
        registry_url,
        urlencoding::encode(slug)
    )
}

/// Convenience wrapper for creating a shared catalog.
pub fn shared_catalog() -> Arc<SkillCatalog> {
    Arc::new(SkillCatalog::new())
}

#[cfg(test)]
mod tests {
    use std::sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    };

    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    async fn spawn_search_server(
        body: &str,
    ) -> (String, Arc<AtomicUsize>, tokio::task::JoinHandle<()>) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind test search server");
        let address = listener.local_addr().expect("get test search server address");
        let hits = Arc::new(AtomicUsize::new(0));
        let hits_for_task = Arc::clone(&hits);
        let response_body = body.to_string();

        let handle = tokio::spawn(async move {
            loop {
                let accept_result = listener.accept().await;
                let (mut stream, _) = match accept_result {
                    Ok(pair) => pair,
                    Err(_) => break,
                };

                let hits = Arc::clone(&hits_for_task);
                let response_body = response_body.clone();
                tokio::spawn(async move {
                    hits.fetch_add(1, Ordering::SeqCst);
                    let mut request_buffer = [0_u8; 1024];
                    let _ = stream.read(&mut request_buffer).await;

                    let response = format!(
                        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                        response_body.as_bytes().len(),
                        response_body
                    );
                    let _ = stream.write_all(response.as_bytes()).await;
                });
            }
        });

        (format!("http://{}", address), hits, handle)
    }

    #[test]
    fn test_default_registry_url() {
        // When CLAWHUB_REGISTRY is not set, should use default
        let catalog = SkillCatalog::with_url(DEFAULT_REGISTRY_URL);
        assert_eq!(catalog.registry_url(), DEFAULT_REGISTRY_URL);
        assert_eq!(catalog.resolved_registry_url(), DEFAULT_REGISTRY_URL);
    }

    #[test]
    fn test_custom_registry_url() {
        let catalog = SkillCatalog::with_url("https://custom.registry.example");
        assert_eq!(catalog.registry_url(), "https://custom.registry.example");
        assert_eq!(
            catalog.resolved_registry_url(),
            "https://custom.registry.example"
        );
    }

    #[tokio::test]
    async fn test_search_returns_error_on_network_failure() {
        // Use RFC 5737 TEST-NET-1 (192.0.2.0/24) for reliable failure even behind proxies.
        // Short timeout so the test doesn't block for the full 10s REQUEST_TIMEOUT.
        let catalog =
            SkillCatalog::with_url_and_timeout("http://192.0.2.1:9999", Duration::from_secs(1));
        let outcome = catalog.search("test").await;
        assert!(outcome.results.is_empty());
        assert!(outcome.error.is_some());
        let error = outcome.error.unwrap();
        assert!(
            error.contains("Registry unreachable")
                || error.contains("connect")
                || error.contains("502")
                || error.contains("503")
                || error.contains("504"),
            "Expected connection or gateway error, got: {error}",
        );
    }

    #[tokio::test]
    async fn test_failed_search_is_not_cached() {
        let catalog = SkillCatalog::with_url("http://127.0.0.1:1");

        catalog.search("cached-query").await;

        let cache = catalog.cache.read().await;
        assert!(!cache.iter().any(|c| c.query == "cached-query"));
    }

    #[tokio::test]
    async fn test_cache_is_populated_after_successful_search() {
        let response =
            r#"{"results":[{"slug":"finance/mortgage-calculator","displayName":"Mortgage Calculator","summary":"A skill","version":"1.0.0","score":3.5}]}"#;
        let (registry_url, hits, server_handle) = spawn_search_server(response).await;
        let catalog = SkillCatalog::with_url(&registry_url);

        let first = catalog.search("cached-query").await;
        let second = catalog.search("cached-query").await;

        assert!(first.error.is_none());
        assert!(second.error.is_none());
        let cache = catalog.cache.read().await;
        assert!(cache.iter().any(|c| c.query == "cached-query"));
        assert_eq!(hits.load(Ordering::SeqCst), 1);

        server_handle.abort();
    }

    #[tokio::test]
    async fn test_clear_cache() {
        let catalog = SkillCatalog::with_url("http://127.0.0.1:1");
        catalog.search("something").await;

        catalog.clear_cache().await;
        let cache = catalog.cache.read().await;
        assert!(cache.is_empty());
    }

    #[test]
    fn test_skill_download_url() {
        let url = skill_download_url("https://clawhub.ai", "owner/my-skill");
        assert_eq!(
            url,
            "https://clawhub.ai/api/v1/download?slug=owner%2Fmy-skill"
        );
    }

    #[test]
    fn test_skill_download_url_encodes_special_chars() {
        let url = skill_download_url("https://clawhub.ai", "foo&bar=baz#frag");
        assert!(url.contains("slug=foo%26bar%3Dbaz%23frag"));
    }

    #[test]
    fn test_resolve_catalog_slug_for_name_unique_match() {
        let entries = vec![CatalogEntry {
            slug: "finance/mortgage-calculator".to_string(),
            name: "Mortgage Calculator".to_string(),
            description: String::new(),
            version: String::new(),
            score: 1.0,
            updated_at: None,
            stars: None,
            downloads: None,
            installs_current: None,
            owner: None,
        }];

        assert_eq!(
            resolve_catalog_slug_for_name("Mortgage Calculator", &entries).unwrap(),
            Some("finance/mortgage-calculator".to_string())
        );
        assert_eq!(
            resolve_catalog_slug_for_name("mortgage-calculator", &entries).unwrap(),
            Some("finance/mortgage-calculator".to_string())
        );
    }

    #[test]
    fn test_resolve_catalog_slug_for_name_ambiguous() {
        let entries = vec![
            CatalogEntry {
                slug: "alice/mortgage-calculator".to_string(),
                name: "Mortgage Calculator".to_string(),
                description: String::new(),
                version: String::new(),
                score: 1.0,
                updated_at: None,
                stars: None,
                downloads: None,
                installs_current: None,
                owner: None,
            },
            CatalogEntry {
                slug: "bob/mortgage-calculator".to_string(),
                name: "Mortgage Calculator".to_string(),
                description: String::new(),
                version: String::new(),
                score: 0.9,
                updated_at: None,
                stars: None,
                downloads: None,
                installs_current: None,
                owner: None,
            },
        ];

        let err = resolve_catalog_slug_for_name("Mortgage Calculator", &entries).unwrap_err();
        assert!(matches!(err, CatalogResolveError::AmbiguousName { .. }));
        assert!(err.to_string().contains("use a slug instead"));
    }

    #[test]
    fn test_resolve_catalog_slug_for_name_prefers_exact_display_name() {
        let entries = vec![
            CatalogEntry {
                slug: "alice/ab".to_string(),
                name: "AB".to_string(),
                description: String::new(),
                version: String::new(),
                score: 1.0,
                updated_at: None,
                stars: None,
                downloads: None,
                installs_current: None,
                owner: None,
            },
            CatalogEntry {
                slug: "bob/a-b".to_string(),
                name: "A-B".to_string(),
                description: String::new(),
                version: String::new(),
                score: 0.9,
                updated_at: None,
                stars: None,
                downloads: None,
                installs_current: None,
                owner: None,
            },
        ];

        assert_eq!(
            resolve_catalog_slug_for_name("AB", &entries).unwrap(),
            Some("alice/ab".to_string())
        );
    }

    #[test]
    fn test_catalog_entry_is_installed_matches_normalized_slug_name() {
        let installed = vec!["finance-mortgage-calculator".to_string()];

        assert!(catalog_entry_is_installed(
            "finance/mortgage-calculator",
            "Mortgage Calculator",
            &installed,
        ));
    }

    #[test]
    fn test_catalog_entry_is_installed_does_not_match_partial_suffix() {
        let installed = vec!["calculator".to_string()];

        assert!(!catalog_entry_is_installed(
            "alice/mortgage-calculator",
            "Mortgage Calculator",
            &installed,
        ));
    }

    #[test]
    fn test_parse_wrapped_response() {
        // ClawHub returns {"results": [...]} format
        let json = r#"{"results":[{"slug":"markdown","displayName":"Markdown","summary":"A skill","version":"1.0.0","score":3.5}]}"#;
        let envelope: CatalogSearchEnvelope = serde_json::from_str(json).unwrap();
        assert_eq!(envelope.results.len(), 1);
        assert_eq!(envelope.results[0].slug, "markdown");
        assert_eq!(
            envelope.results[0].display_name.as_deref(),
            Some("Markdown")
        );
    }

    #[test]
    fn test_parse_bare_array_response() {
        // Fallback: bare array format
        let json = r#"[{"slug":"markdown","displayName":"Markdown","summary":"A skill","version":"1.0.0","score":3.5}]"#;
        let results: Vec<CatalogSearchResult> = serde_json::from_str(json).unwrap();
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].slug, "markdown");
    }

    #[test]
    fn test_parse_skill_detail() {
        // Response format matches the actual ClawHub API: {"skill": {...}, "owner": {...}}
        let json = r#"{
            "skill": {
                "slug": "steipete/markdown-writer",
                "displayName": "Markdown Writer",
                "summary": "Write markdown docs",
                "stats": {
                    "stars": 142,
                    "downloads": 8400,
                    "installsCurrent": 55,
                    "installsAllTime": 200,
                    "versions": 5
                },
                "updatedAt": 1700000000000
            },
            "owner": {
                "handle": "steipete",
                "displayName": "Peter S."
            },
            "latestVersion": {
                "version": "1.2.3",
                "createdAt": 1700000000000,
                "changelog": ""
            }
        }"#;

        let wrapper: SkillDetailResponse = serde_json::from_str(json).unwrap();
        let inner = &wrapper.skill;
        assert_eq!(inner.slug, "steipete/markdown-writer");
        assert_eq!(inner.display_name.as_deref(), Some("Markdown Writer"));

        let stats = inner.stats.as_ref().unwrap();
        assert_eq!(stats.stars, Some(142));
        assert_eq!(stats.downloads, Some(8400));
        assert_eq!(stats.installs_current, Some(55));

        let owner = wrapper.owner.as_ref().unwrap();
        assert_eq!(owner.handle.as_deref(), Some("steipete"));
    }

    #[tokio::test]
    async fn test_fetch_skill_detail_returns_none_on_error() {
        let catalog = SkillCatalog::with_url("http://127.0.0.1:1");
        let result = catalog.fetch_skill_detail("nonexistent/skill").await;
        assert!(result.is_none());
    }

    #[tokio::test]
    async fn test_search_uses_fallback_registry_and_updates_resolved_url() {
        let response =
            r#"{"results":[{"slug":"finance/mortgage-calculator","displayName":"Mortgage Calculator","summary":"A skill","version":"1.0.0","score":3.5}]}"#;
        let (fallback_registry_url, hits, server_handle) = spawn_search_server(response).await;
        let catalog = SkillCatalog::with_urls_and_timeout(
            "http://127.0.0.1:1",
            vec![fallback_registry_url.clone()],
            Duration::from_secs(1),
        );

        let outcome = catalog.search("mortgage").await;

        assert!(outcome.error.is_none());
        assert_eq!(outcome.results.len(), 1);
        assert_eq!(outcome.results[0].slug, "finance/mortgage-calculator");
        assert_eq!(catalog.resolved_registry_url(), fallback_registry_url);
        assert_eq!(hits.load(Ordering::SeqCst), 1);

        let download_urls = catalog.download_urls_for_slug("finance/mortgage-calculator");
        assert_eq!(
            download_urls[0],
            skill_download_url(&fallback_registry_url, "finance/mortgage-calculator")
        );

        server_handle.abort();
    }

    #[test]
    fn test_catalog_entry_serde() {
        let entry = CatalogEntry {
            slug: "test/skill".to_string(),
            name: "Test Skill".to_string(),
            description: "A test".to_string(),
            version: "1.0.0".to_string(),
            score: 0.95,
            updated_at: Some(1700000000000),
            stars: Some(42),
            downloads: Some(1000),
            installs_current: None,
            owner: Some("tester".to_string()),
        };
        let json = serde_json::to_string(&entry).unwrap();
        let parsed: CatalogEntry = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.slug, "test/skill");
        assert_eq!(parsed.name, "Test Skill");
    }
}
