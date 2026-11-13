//! Desktop notifications through `notify-send` (libnotify), one per message up to a small cap.
use super::detect::Message;
use tokio::process::Command;

const INDIVIDUAL: usize = 3;

pub async fn announce(account: &str, fresh: &[Message]) {
    if fresh.is_empty() {
        return;
    }
    if fresh.len() > INDIVIDUAL {
        send(&format!("{} new messages", fresh.len()), account).await;
        return;
    }
    for message in fresh {
        let title = if message.from.is_empty() {
            account
        } else {
            &message.from
        };
        let subject = if message.subject.is_empty() {
            "(no subject)"
        } else {
            &message.subject
        };
        send(title, subject).await;
    }
}

async fn send(title: &str, body: &str) {
    let _ = Command::new("notify-send")
        .args([
            "--app-name=Facteur",
            "--icon=fili-mail",
            "--category=email.arrived",
            "--expire-time=8000",
            "--",
        ])
        .arg(title)
        .arg(body)
        .kill_on_drop(true)
        .status()
        .await;
}
