//! `unread.json`: the counter the fili-bar module reads, replaced atomically on every change.
use serde_json::{Value, json};
use std::{collections::HashMap, fs, path::PathBuf};

fn path() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/state")))?;
    Some(base.join("filigrane/mail/unread.json"))
}

pub fn render(
    watched: &HashMap<String, String>,
    counts: &HashMap<String, Value>,
    now: u64,
) -> Value {
    let mut accounts: Vec<Value> = watched
        .iter()
        .map(|(id, email)| {
            let count = counts
                .get(id)
                .cloned()
                .unwrap_or_else(|| json!({"unread":0,"error":""}));
            json!({"id":id,"email":email,"unread":count["unread"],"error":count["error"]})
        })
        .collect();
    accounts.sort_by(|a, b| a["id"].as_str().cmp(&b["id"].as_str()));
    let total: u64 = accounts.iter().filter_map(|a| a["unread"].as_u64()).sum();
    json!({"total":total,"updatedAt":now,"accounts":accounts})
}

pub fn write(watched: &HashMap<String, String>, counts: &HashMap<String, Value>) {
    let Some(path) = path() else { return };
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let body = render(watched, counts, now).to_string();
    let Some(dir) = path.parent() else { return };
    let temporary = path.with_extension("json.tmp");
    if fs::create_dir_all(dir).is_ok() && fs::write(&temporary, body).is_ok() {
        let _ = fs::rename(&temporary, &path);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn totals_every_account_and_keeps_errors() {
        let watched = HashMap::from([
            ("imap:a@x.org".into(), "a@x.org".into()),
            ("b@y.org".into(), "b@y.org".into()),
        ]);
        let counts = HashMap::from([
            ("imap:a@x.org".into(), json!({"unread":2,"error":""})),
            (
                "b@y.org".into(),
                json!({"unread":3,"error":"gmail_http_failed"}),
            ),
        ]);
        let out = render(&watched, &counts, 9);
        assert_eq!(out["total"], 5);
        assert_eq!(out["accounts"][0]["error"], "gmail_http_failed");
    }
}
