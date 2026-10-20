use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Clone)]
pub struct UsageResponse {
    pub five_hour: WindowUsage,
    pub seven_day: WindowUsage,
    #[serde(default)]
    pub limits: Vec<LimitEntry>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct WindowUsage {
    pub utilization: f64,
    pub resets_at: Option<String>,
}

/// One entry of the API's `limits` array. Model-scoped weekly limits (e.g. the
/// Fable-only weekly cap) are only reported here, not as a top-level window.
#[derive(Debug, Deserialize, Clone)]
pub struct LimitEntry {
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub percent: Option<f64>,
    #[serde(default)]
    pub resets_at: Option<String>,
    #[serde(default)]
    pub scope: Option<LimitScope>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct LimitScope {
    #[serde(default)]
    pub model: Option<ScopeModel>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct ScopeModel {
    #[serde(default)]
    pub display_name: Option<String>,
}

/// A weekly window scoped to a single model, labeled by that model's name.
#[derive(Debug, Clone)]
pub struct ScopedWindow {
    pub label: String,
    pub util: f64,
    pub resets_at: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct AggregatedUsage {
    pub five_hour_util: f64,
    pub five_hour_resets_at: Option<String>,
    pub seven_day_util: f64,
    pub seven_day_resets_at: Option<String>,
    pub scoped_weekly: Vec<ScopedWindow>,
    pub claude_available: bool,
    pub codex: CodexStatus,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CodexStatus {
    pub weekly: Option<WindowUsage>,
    /// The rolling 5-hour window; only some plans have one.
    #[serde(default)]
    pub five_hour: Option<WindowUsage>,
    pub error: Option<String>,
    pub updated_at: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct CodexResponse {
    pub rate_limit: Option<CodexLimits>,
}

#[derive(Debug, Deserialize)]
pub struct CodexLimits {
    pub primary_window: Option<CodexWindow>,
    pub secondary_window: Option<CodexWindow>,
}

#[derive(Debug, Deserialize)]
pub struct CodexWindow {
    pub used_percent: f64,
    pub limit_window_seconds: u64,
    pub reset_at: Option<i64>,
}

/// The Codex windows a plan has. Either may be missing: some plans have no 5-hour window.
#[derive(Debug, Clone, Default)]
pub struct CodexUsage {
    pub weekly: Option<WindowUsage>,
    pub five_hour: Option<WindowUsage>,
}

const WEEK_SECONDS: u64 = 604_800;
const FIVE_HOURS_SECONDS: u64 = 18_000;

impl CodexResponse {
    /// Picks each window by its length, since the plan decides which one is primary.
    pub fn usage(self) -> anyhow::Result<CodexUsage> {
        let limits = self
            .rate_limit
            .ok_or_else(|| anyhow::anyhow!("Codex limits unavailable"))?;
        let windows: Vec<CodexWindow> = [limits.primary_window, limits.secondary_window]
            .into_iter()
            .flatten()
            .collect();
        let pick = |seconds: u64| -> anyhow::Result<Option<WindowUsage>> {
            let Some(window) = windows.iter().find(|w| w.limit_window_seconds == seconds) else {
                return Ok(None);
            };
            if !window.used_percent.is_finite() || window.used_percent < 0.0 {
                anyhow::bail!("invalid Codex usage");
            }
            Ok(Some(WindowUsage {
                utilization: window.used_percent,
                resets_at: window
                    .reset_at
                    .and_then(|t| chrono::DateTime::from_timestamp(t, 0))
                    .map(|t| t.to_rfc3339()),
            }))
        };
        let usage = CodexUsage {
            weekly: pick(WEEK_SECONDS)?,
            five_hour: pick(FIVE_HOURS_SECONDS)?,
        };
        if usage.weekly.is_none() && usage.five_hour.is_none() {
            anyhow::bail!("Codex limits unavailable");
        }
        Ok(usage)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn selects_weekly_by_duration_in_either_position() {
        let week =
            json!({"used_percent": 13, "limit_window_seconds": 604800, "reset_at": 2000000000});
        let short =
            json!({"used_percent": 99, "limit_window_seconds": 18000, "reset_at": 1900000000});
        for (primary, secondary) in [
            (week.clone(), short.clone()),
            (short, week.clone()),
            (week, json!(null)),
        ] {
            let has_short = !primary.is_null() && primary["limit_window_seconds"] == 18000
                || !secondary.is_null() && secondary["limit_window_seconds"] == 18000;
            let response: CodexResponse = serde_json::from_value(json!({"rate_limit": {
                "primary_window": primary, "secondary_window": secondary
            }}))
            .unwrap();
            let usage = response.usage().unwrap();
            let weekly = usage.weekly.unwrap();
            assert_eq!(weekly.utilization, 13.0);
            assert_eq!(
                weekly.resets_at.as_deref(),
                Some("2033-05-18T03:33:20+00:00")
            );
            match usage.five_hour {
                Some(five) => {
                    assert!(has_short);
                    assert_eq!(five.utilization, 99.0);
                    assert_eq!(five.resets_at.as_deref(), Some("2030-03-17T17:46:40+00:00"));
                }
                None => assert!(!has_short),
            }
        }
    }

    #[test]
    fn five_hour_alone_is_reported_without_weekly() {
        let response: CodexResponse = serde_json::from_value(json!({"rate_limit": {
            "primary_window": {"used_percent": 40, "limit_window_seconds": 18000}, "secondary_window": null
        }}))
        .unwrap();
        let usage = response.usage().unwrap();
        assert!(usage.weekly.is_none());
        assert_eq!(usage.five_hour.unwrap().utilization, 40.0);
    }

    #[test]
    fn missing_windows_are_unavailable_not_zero() {
        for payload in [
            json!({}),
            json!({"rate_limit": null}),
            json!({"rate_limit": {"primary_window": null, "secondary_window": null}}),
            json!({"rate_limit": {
                "primary_window": {"used_percent": 0, "limit_window_seconds": 3600}, "secondary_window": null
            }}),
        ] {
            let response: CodexResponse = serde_json::from_value(payload).unwrap();
            assert!(response.usage().is_err());
        }
    }

    #[test]
    fn ignores_extra_credits_even_when_their_schema_changes() {
        let response: UsageResponse = serde_json::from_value(json!({
            "five_hour": {"utilization": 12}, "seven_day": {"utilization": 34},
            "extra_usage": {"monthly_limit": null, "currency": null}
        }))
        .unwrap();
        assert_eq!(response.five_hour.utilization, 12.0);
    }
}
