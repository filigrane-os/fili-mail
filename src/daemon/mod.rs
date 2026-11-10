//! `fili-mail daemon`: watch every account, announce new mail, keep the unread counter.
//!
//! One process for all accounts: the backend's per-account check loops (IMAP IDLE where the
//! server offers it, polling otherwise) feed `mail.updated` events; each change is turned into
//! desktop notifications and into `unread.json`, which the fili-bar module reads.
mod detect;
mod notify;
mod state;

use crate::backend::Session;
use detect::{Detector, Message};
use serde_json::{Value, json};
use std::{collections::HashMap, time::Duration};

const WATCH_INTERVAL_SEC: u64 = 120;
const REGISTRY_POLL: Duration = Duration::from_secs(30);
const LIST_LIMIT: u64 = 25;

pub fn run() -> i32 {
    let Ok(runtime) = crate::backend::runtime() else {
        eprintln!("fili-mail: cannot start the runtime");
        return 1;
    };
    runtime.block_on(serve());
    0
}

fn provider_of(account: &str) -> &str {
    account
        .split_once(':')
        .map_or("gmail", |(provider, _)| provider)
}

async fn accounts() -> Option<Vec<(String, String)>> {
    let listed = tokio::task::spawn_blocking(crate::account::list)
        .await
        .ok()?
        .ok()?;
    Some(
        listed["accounts"]
            .as_array()?
            .iter()
            .filter(|a| a["pending"] != true && a["provider"] != "hey")
            .filter_map(|a| {
                let id = a["id"].as_str().filter(|id| !id.is_empty())?;
                Some((id.to_owned(), a["email"].as_str().unwrap_or(id).to_owned()))
            })
            .collect(),
    )
}

async fn sync_watches(
    session: &Session,
    watched: &mut HashMap<String, String>,
    detector: &mut Detector,
) {
    let Some(wanted) = accounts().await else {
        return;
    };
    for (id, email) in &wanted {
        if watched.contains_key(id) {
            continue;
        }
        let Some(query) = crate::providers::domain::mailbox_query(provider_of(id), "unread") else {
            continue;
        };
        let params = json!({"accountId":id,"query":query,"intervalSec":WATCH_INTERVAL_SEC,"pageSize":LIST_LIMIT});
        match session.dispatch("mail.watch", &params).await {
            Ok(_) => {
                watched.insert(id.clone(), email.clone());
            }
            Err(error) => eprintln!("fili-mail: cannot watch {id}: {error}"),
        }
    }
    let gone: Vec<String> = watched
        .keys()
        .filter(|id| !wanted.iter().any(|(w, _)| w == *id))
        .cloned()
        .collect();
    for id in gone {
        let _ = session
            .dispatch("mail.unwatch", &json!({"accountId":id}))
            .await;
        watched.remove(&id);
        detector.forget(&id);
    }
}

async fn unread_messages(session: &Session, account: &str) -> Result<Vec<Message>, &'static str> {
    let params = json!({"account":account,"mailbox":"inbox","limit":LIST_LIMIT});
    let page = session.dispatch("mail.list", &params).await?;
    Ok(page["messages"]
        .as_array()
        .map(|messages| messages.iter().filter_map(Message::unread).collect())
        .unwrap_or_default())
}

async fn serve() {
    let session = Session::default();
    // Subscribe before the first watch: its immediate check can finish before it returns.
    let mut events = session.mail_events();
    let mut watched: HashMap<String, String> = HashMap::new();
    let mut counts: HashMap<String, Value> = HashMap::new();
    let mut detector = Detector::default();
    let mut tick = tokio::time::interval(REGISTRY_POLL);
    let mut stop = match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
        Ok(signal) => signal,
        Err(_) => return,
    };
    loop {
        tokio::select! {
            _ = tick.tick() => {
                sync_watches(&session, &mut watched, &mut detector).await;
                counts.retain(|id, _| watched.contains_key(id));
                state::write(&watched, &counts);
            }
            _ = stop.recv() => break,
            _ = tokio::signal::ctrl_c() => break,
            event = events.recv() => {
                let Ok(event) = event else { continue };
                if !session.mail_is_current(&event) {
                    continue;
                }
                let snapshot = &event.value["params"];
                let Some(account) = snapshot["accountId"].as_str().map(str::to_owned) else { continue };
                counts.insert(account.clone(), json!({
                    "unread": snapshot["estimate"].as_u64().unwrap_or(0),
                    "error": snapshot["error"].as_str().unwrap_or(""),
                }));
                state::write(&watched, &counts);
                if !detector.changed(&account, snapshot) {
                    continue;
                }
                match unread_messages(&session, &account).await {
                    Ok(unread) => {
                        let email = watched.get(&account).cloned().unwrap_or_default();
                        let fresh = detector.observe(&account, unread);
                        notify::announce(&email, &fresh).await;
                    }
                    Err(_) => detector.retry(&account),
                }
            }
        }
    }
    session.shutdown_mail().await;
}
