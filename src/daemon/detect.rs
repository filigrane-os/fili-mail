//! New-mail detection: which unread messages have not been announced yet.
use serde_json::Value;
use std::collections::{HashMap, HashSet};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Message {
    pub id: String,
    pub from: String,
    pub subject: String,
}

impl Message {
    /// Read a message summary as `mail.list` returns it; `None` unless it is unread.
    pub fn unread(summary: &Value) -> Option<Self> {
        if summary["unread"] != true {
            return None;
        }
        let id = summary["id"].as_str().filter(|id| !id.is_empty())?;
        let from = &summary["from"];
        let from = ["name", "email"]
            .iter()
            .filter_map(|key| from[*key].as_str())
            .find(|text| !text.trim().is_empty())
            .or_else(|| from.as_str())
            .unwrap_or("")
            .trim()
            .to_owned();
        Some(Self {
            id: id.to_owned(),
            from,
            subject: summary["subject"].as_str().unwrap_or("").trim().to_owned(),
        })
    }
}

#[derive(Default)]
pub struct Detector {
    /// Unread ids already seen per account; an account is primed by its first listing.
    seen: HashMap<String, HashSet<String>>,
    fingerprints: HashMap<String, String>,
}

impl Detector {
    /// Whether a `mail.updated` snapshot warrants listing the mailbox. An unchanged
    /// fingerprint means nothing moved since the last listing; an error never does.
    pub fn changed(&mut self, account: &str, snapshot: &Value) -> bool {
        if !snapshot["error"].as_str().unwrap_or("").is_empty() {
            return false;
        }
        let fingerprint = snapshot["fingerprint"].as_str().unwrap_or("");
        if self.fingerprints.get(account).map(String::as_str) == Some(fingerprint)
            && self.seen.contains_key(account)
        {
            return false;
        }
        self.fingerprints
            .insert(account.to_owned(), fingerprint.to_owned());
        true
    }

    /// Record the current unread messages and return those never seen before. The first
    /// listing of an account only primes it, so starting the daemon announces nothing.
    pub fn observe(&mut self, account: &str, unread: Vec<Message>) -> Vec<Message> {
        let current: HashSet<String> = unread.iter().map(|m| m.id.clone()).collect();
        let fresh = match self.seen.get(account) {
            None => Vec::new(),
            Some(seen) => unread
                .into_iter()
                .filter(|m| !seen.contains(&m.id))
                .collect(),
        };
        self.seen.insert(account.to_owned(), current);
        fresh
    }

    /// A listing failed: look again at the next update instead of trusting the fingerprint.
    pub fn retry(&mut self, account: &str) {
        self.fingerprints.remove(account);
    }

    pub fn forget(&mut self, account: &str) {
        self.seen.remove(account);
        self.fingerprints.remove(account);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn msg(id: &str) -> Message {
        Message {
            id: id.into(),
            from: "A".into(),
            subject: "S".into(),
        }
    }

    #[test]
    fn first_listing_primes_without_announcing() {
        let mut d = Detector::default();
        assert!(d.observe("a", vec![msg("1"), msg("2")]).is_empty());
        assert_eq!(
            d.observe("a", vec![msg("1"), msg("2"), msg("3")]),
            vec![msg("3")]
        );
    }

    #[test]
    fn read_then_new_announces_only_the_new_one() {
        let mut d = Detector::default();
        d.observe("a", vec![msg("1")]);
        assert_eq!(d.observe("a", vec![msg("2")]), vec![msg("2")]);
        assert!(d.observe("a", vec![msg("2")]).is_empty());
    }

    #[test]
    fn accounts_are_independent() {
        let mut d = Detector::default();
        d.observe("a", vec![]);
        assert!(d.observe("b", vec![msg("1")]).is_empty());
        assert_eq!(d.observe("a", vec![msg("1")]), vec![msg("1")]);
    }

    #[test]
    fn unchanged_fingerprint_and_errors_skip_the_listing() {
        let mut d = Detector::default();
        let snap = json!({"fingerprint":"f1","error":""});
        assert!(d.changed("a", &snap));
        d.observe("a", vec![]);
        assert!(!d.changed("a", &snap));
        assert!(d.changed("a", &json!({"fingerprint":"f2","error":""})));
        assert!(!d.changed("a", &json!({"fingerprint":"f3","error":"imap_failed"})));
    }

    #[test]
    fn summary_reads_name_then_address_and_skips_read_mail() {
        let m = Message::unread(
            &json!({"id":"1","unread":true,"from":{"name":"","email":"x@y.z"},"subject":" Hi "}),
        );
        assert_eq!(m.unwrap().from, "x@y.z");
        assert!(Message::unread(&json!({"id":"1","unread":false})).is_none());
    }
}
