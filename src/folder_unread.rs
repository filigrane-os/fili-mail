//! Unread counts of the folders of an IMAP account, for the folder tabs and the sidebar.
//!
//! `imap.folders` lists the folders without any count; `imap.count` asks the server (`STATUS … UNSEEN`) for one folder.
use crate::backend::Session;
use futures_util::{StreamExt, stream};
use serde_json::{Value, json};
use std::collections::HashMap;

/// Folders asked at the same time. The pool keeps one idle connection per account: a second request in flight would
/// log in on a new connection (a TLS handshake and a session some servers cap), so the folders go one after the other.
const PARALLEL: usize = 1;

/// The unread count of one `imap.count` answer; `None` when the answer carries no number.
pub fn unread_of(answer: &Value) -> Option<u64> {
    answer["unread"].as_u64()
}

/// Puts each folder's count in its `unread` field. A folder with no answer keeps the count it had (the one from the
/// last time, or 0), so one failed request does not blank a badge.
pub fn apply(folders: &mut [Value], counts: &HashMap<String, u64>) {
    for folder in folders {
        let id = folder["id"].as_str().unwrap_or("");
        if let Some(n) = counts.get(id) {
            folder["unread"] = json!(n);
        }
    }
}

/// What to remember for the next load: the counts of the folders that still exist, the fresh answer over the old one.
/// A folder deleted or renamed since drops out, so its number cannot come back.
pub fn remembered(folders: &[Value], old: &HashMap<String, u64>, fresh: &HashMap<String, u64>) -> HashMap<String, u64> {
    folders
        .iter()
        .filter_map(|f| f["id"].as_str())
        .filter_map(|id| fresh.get(id).or_else(|| old.get(id)).map(|n| (id.to_owned(), *n)))
        .collect()
}

/// Asks the server for the unread count of every folder of the account.
pub async fn fetch(session: &Session, account: &str, folders: &[Value]) -> HashMap<String, u64> {
    let ids: Vec<String> = folders.iter().filter_map(|f| f["id"].as_str().map(str::to_owned)).collect();
    stream::iter(ids)
        .map(|id| async move {
            let params = json!({"accountId": account, "labelId": id});
            let n = match session.dispatch("imap.count", &params).await {
                Ok(answer) => unread_of(&answer),
                Err(_) => None,
            };
            (id, n)
        })
        .buffer_unordered(PARALLEL)
        .filter_map(|(id, n)| async move { n.map(|n| (id, n)) })
        .collect()
        .await
}

#[cfg(test)]
mod tests {
    use super::*;

    fn folder(id: &str, unread: u64) -> Value {
        json!({"id": id, "rawName": id, "unread": unread, "folder": true})
    }

    #[test]
    fn count_is_read_from_the_server_answer() {
        assert_eq!(unread_of(&json!({"id":"Folders/Newsletters","unread":7,"total":120})), Some(7));
        assert_eq!(unread_of(&json!({"id":"x","unread":0,"total":3})), Some(0));
    }

    #[test]
    fn an_answer_without_a_number_is_not_a_count() {
        assert_eq!(unread_of(&json!({"id":"x","total":3})), None);
        assert_eq!(unread_of(&json!({"unread":"7"})), None);
        assert_eq!(unread_of(&json!({"unread":-1})), None);
    }

    #[test]
    fn counts_land_on_the_matching_folders() {
        let mut folders = vec![folder("Folders/Newsletters", 0), folder("Folders/Transactions", 0), folder("Labels/Code", 0)];
        let counts = HashMap::from([("Folders/Newsletters".to_owned(), 12), ("Labels/Code".to_owned(), 2)]);
        apply(&mut folders, &counts);
        let got: Vec<u64> = folders.iter().map(|f| f["unread"].as_u64().unwrap()).collect();
        assert_eq!(got, [12, 0, 2]);
    }

    #[test]
    fn a_folder_without_answer_keeps_its_previous_count() {
        let mut folders = vec![folder("Folders/Newsletters", 5)];
        apply(&mut folders, &HashMap::new());
        assert_eq!(folders[0]["unread"], 5);
    }

    #[test]
    fn remembered_counts_follow_the_folders_that_still_exist() {
        let folders = vec![folder("A", 0), folder("B", 0)];
        let old = HashMap::from([("A".to_owned(), 3), ("B".to_owned(), 4), ("Gone".to_owned(), 9)]);
        let fresh = HashMap::from([("A".to_owned(), 1)]);
        let kept = remembered(&folders, &old, &fresh);
        // A: the fresh answer; B: no answer, the old count stays; Gone: the folder no longer exists
        assert_eq!(kept, HashMap::from([("A".to_owned(), 1), ("B".to_owned(), 4)]));
    }

    #[test]
    fn a_count_for_an_unknown_folder_adds_nothing() {
        let mut folders = vec![folder("Folders/Newsletters", 0)];
        apply(&mut folders, &HashMap::from([("Folders/Gone".to_owned(), 9)]));
        assert_eq!(folders.len(), 1);
        assert_eq!(folders[0]["unread"], 0);
    }
}
