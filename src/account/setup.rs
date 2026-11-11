//! Registering an IMAP/SMTP account: the registry entry and the password in the keyring.
//! Shared by `fili-mail accounts add-imap` and the application's account sheet.
use crate::backend::Session;
use serde_json::{Value, json};

/// Proton Mail Bridge listens on loopback with its own certificate.
const BRIDGE_HOST: &str = "127.0.0.1";
const BRIDGE_IMAP: u16 = 1143;
const BRIDGE_SMTP: u16 = 1025;

#[derive(Default)]
pub struct ImapSpec {
    pub email: String,
    pub password: String,
    pub label: String,
    pub username: Option<String>,
    pub bridge: bool,
    pub imap_host: Option<String>,
    pub imap_port: Option<u16>,
    pub smtp_host: Option<String>,
    pub smtp_port: Option<u16>,
}

impl ImapSpec {
    /// The `imap` settings of the registry entry: Bridge defaults, else servers deduced from the address.
    pub fn settings(&self) -> Result<Value, &'static str> {
        let email = self.email.trim().to_lowercase();
        if !crate::account::valid_email(&email) {
            return Err("invalid_params");
        }
        let (host, imap_port, smtp_port) = if self.bridge {
            (BRIDGE_HOST.to_owned(), BRIDGE_IMAP, BRIDGE_SMTP)
        } else {
            let domain = email.split_once('@').map_or("", |(_, d)| d);
            (format!("imap.{domain}"), 993, 465)
        };
        let imap_host = self.imap_host.clone().unwrap_or(host.clone());
        let smtp_host = self.smtp_host.clone().unwrap_or_else(|| {
            if self.bridge {
                host.clone()
            } else {
                imap_host.replacen("imap.", "smtp.", 1)
            }
        });
        let mut imap = json!({
            "imapHost": imap_host,
            "imapPort": self.imap_port.unwrap_or(imap_port),
            "smtpHost": smtp_host,
            "smtpPort": self.smtp_port.unwrap_or(smtp_port),
            "username": self.username.clone().filter(|u| !u.is_empty()).unwrap_or(email),
        });
        if self.bridge {
            imap["insecure"] = json!(true);
        }
        Ok(imap)
    }
}

/// Add (or replace) an IMAP account. The password is stored first: an account without one
/// would only fail at its first check.
pub async fn add_imap(session: &Session, spec: &ImapSpec) -> Result<Value, &'static str> {
    let email = spec.email.trim().to_lowercase();
    if spec.password.is_empty() {
        return Err("invalid_params");
    }
    let imap = spec.settings()?;
    let id = format!("imap:{email}");
    let entry = json!({"provider":"imap","email":email,"label":spec.label,"imap":imap});
    let read = session.dispatch("accounts.read", &json!({})).await?;
    let mut registry = read["registry"].clone();
    let accounts = registry["accounts"]
        .as_array_mut()
        .ok_or("accounts_invalid")?;
    accounts.retain(|a| {
        !(a["provider"] == "imap"
            && a["email"].as_str().map(str::to_lowercase).as_deref() == Some(email.as_str()))
    });
    accounts.push(entry);
    if registry["activeId"].as_str().unwrap_or("").is_empty() {
        registry["activeId"] = json!(id);
    }
    session
        .dispatch(
            "credentials.put",
            &json!({"kind":"imap-password","accountId":id,"secret":spec.password}),
        )
        .await?;
    session
        .dispatch(
            "accounts.save",
            &json!({"registry":registry,"revision":read["revision"]}),
        )
        .await?;
    Ok(json!({"added":id}))
}

/// OAuth callback port of the desktop client (any loopback port is accepted by Google's desktop clients).
const GOOGLE_PORT: u16 = 9481;
/// Mail only; the refresh token is kept in the keyring by the engine itself.
const GOOGLE_SCOPES: [&str; 2] = [
    "https://www.googleapis.com/auth/gmail.modify",
    "https://www.googleapis.com/auth/gmail.send",
];

pub use crate::providers::gmail_credentials::{
    client_configured as google_client_configured, save_client as save_google_client,
};

/// Start the Google sign-in: `{"id","url"}`; the url is the page to open in the browser.
pub async fn google_begin(session: &Session, login_hint: &str) -> Result<Value, &'static str> {
    let client = crate::providers::gmail_credentials::read_for_account("")?;
    session
        .dispatch(
            "auth.begin",
            &json!({
                "clientId": client.client_id,
                "clientSecret": client.client_secret,
                "loginHint": login_hint,
                "port": GOOGLE_PORT,
                "scopes": GOOGLE_SCOPES,
            }),
        )
        .await
}

/// `Ok(None)` while the browser page is still open; `Ok(Some({"added"}))` once signed in, the account registered.
pub async fn google_poll(session: &Session, id: &str) -> Result<Option<Value>, &'static str> {
    let done = session.dispatch("auth.poll", &json!({"id": id})).await?;
    if done["pending"] == true {
        return Ok(None);
    }
    if done["status"] != 200 {
        return Err("auth_failed");
    }
    let email = done["profile"]["emailAddress"]
        .as_str()
        .ok_or("auth_invalid_profile")?
        .to_lowercase();
    let read = session.dispatch("accounts.read", &json!({})).await?;
    let mut registry = read["registry"].clone();
    let accounts = registry["accounts"]
        .as_array_mut()
        .ok_or("accounts_invalid")?;
    accounts.retain(|a| {
        !(a["provider"].as_str().unwrap_or("gmail") == "gmail"
            && a["email"].as_str().map(str::to_lowercase).as_deref() == Some(email.as_str()))
    });
    accounts.push(json!({"provider":"gmail","email":email,"label":""}));
    if registry["activeId"].as_str().unwrap_or("").is_empty() {
        registry["activeId"] = json!(email);
    }
    session
        .dispatch(
            "accounts.save",
            &json!({"registry":registry,"revision":read["revision"]}),
        )
        .await?;
    Ok(Some(json!({"added": email})))
}

/// What the edit sheet shows of an account: its name and, for IMAP, the server settings (never the password).
pub async fn account_details(session: &Session, id: &str) -> Result<Value, &'static str> {
    let read = session.dispatch("accounts.read", &json!({})).await?;
    let (_, entry) = find_entry(&read["registry"], session, id).await?;
    Ok(json!({"id":id,"provider":entry["provider"],"email":entry["email"],"label":entry["label"],"imap":entry["imap"]}))
}

async fn find_entry(registry: &Value, session: &Session, id: &str) -> Result<(usize, Value), &'static str> {
    let summary = session.dispatch("accounts.list", &json!({})).await?;
    let provider = summary["accounts"]
        .as_array()
        .and_then(|list| list.iter().find(|a| a["id"] == id))
        .and_then(|a| a["provider"].as_str())
        .ok_or("mail_account_unknown")?
        .to_owned();
    let email = id.strip_prefix(&format!("{provider}:")).unwrap_or(id).to_owned();
    registry["accounts"]
        .as_array()
        .ok_or("accounts_invalid")?
        .iter()
        .enumerate()
        .find(|(_, a)| {
            a["provider"].as_str().unwrap_or("gmail") == provider
                && a["email"].as_str().map(str::to_lowercase).as_deref() == Some(email.as_str())
        })
        .map(|(i, a)| (i, a.clone()))
        .ok_or("mail_account_unknown")
}

/// Change an account: its name (any provider) and, for IMAP, servers, ports, user name and (when given) password.
pub async fn update_account(session: &Session, id: &str, patch: &Value) -> Result<Value, &'static str> {
    let read = session.dispatch("accounts.read", &json!({})).await?;
    let mut registry = read["registry"].clone();
    let (at, mut entry) = find_entry(&registry, session, id).await?;
    if let Some(label) = patch["label"].as_str() {
        entry["label"] = json!(label.trim());
    }
    if entry["provider"] == "imap" {
        for key in ["imapHost", "smtpHost", "username"] {
            if let Some(v) = patch[key].as_str().map(str::trim).filter(|v| !v.is_empty()) {
                entry["imap"][key] = json!(v);
            }
        }
        for key in ["imapPort", "smtpPort"] {
            if let Some(p) = patch[key].as_u64().and_then(|p| u16::try_from(p).ok()).filter(|p| *p > 0) {
                entry["imap"][key] = json!(p);
            }
        }
    }
    registry["accounts"][at] = entry;
    if let Some(secret) = patch["password"].as_str().filter(|s| !s.is_empty()) {
        session
            .dispatch("credentials.put", &json!({"kind":"imap-password","accountId":id,"secret":secret}))
            .await?;
    }
    session
        .dispatch("accounts.save", &json!({"registry":registry,"revision":read["revision"]}))
        .await?;
    Ok(json!({"updated":id}))
}

/// Remove an account: its registry entry, then its secret in the keyring (a missing secret is not an error).
pub async fn remove_account(session: &Session, id: &str) -> Result<Value, &'static str> {
    let read = session.dispatch("accounts.read", &json!({})).await?;
    let mut registry = read["registry"].clone();
    let summary = session.dispatch("accounts.list", &json!({})).await?;
    let provider = summary["accounts"]
        .as_array()
        .and_then(|list| list.iter().find(|a| a["id"] == id))
        .and_then(|a| a["provider"].as_str())
        .ok_or("mail_account_unknown")?
        .to_owned();
    let email = id
        .strip_prefix(&format!("{provider}:"))
        .unwrap_or(id)
        .to_owned();
    let accounts = registry["accounts"]
        .as_array_mut()
        .ok_or("accounts_invalid")?;
    accounts.retain(|a| {
        let same = a["provider"].as_str().unwrap_or("gmail") == provider
            && a["email"].as_str().map(str::to_lowercase).as_deref() == Some(email.as_str());
        !same
    });
    if registry["activeId"] == id {
        registry["activeId"] = json!("");
    }
    session
        .dispatch(
            "accounts.save",
            &json!({"registry":registry,"revision":read["revision"],"releasedIds":[id]}),
        )
        .await?;
    let secret = match provider.as_str() {
        "imap" => Some(json!({"kind":"imap-password","accountId":id})),
        "gmail" => crate::providers::gmail_credentials::read_for_account(id)
            .ok()
            .map(|client| json!({"kind":"google-refresh-token","accountId":id,"clientId":client.client_id})),
        _ => None,
    };
    if let Some(secret) = secret {
        // The account is gone either way; a keyring that fails here only leaves an orphan secret.
        let _ = session.dispatch("credentials.delete", &secret).await;
    }
    Ok(json!({"removed": id}))
}
