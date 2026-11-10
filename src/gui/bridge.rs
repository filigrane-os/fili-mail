// Object exposed to QML (module Fili.Mail): Facteur, the environment (live theme, translations) and the mail engine
// (accounts, message lists and messages, answered asynchronously by signals).
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        #[qproperty(bool, light, READ, NOTIFY = theme_changed)]
        #[qproperty(QString, accent, READ, NOTIFY = theme_changed)]
        #[qproperty(bool, key_nav, cxx_name = "keyNav")]
        type Facteur = super::FacteurRust;

        #[qsignal]
        #[cxx_name = "themeChanged"]
        fn theme_changed(self: Pin<&mut Facteur>);

        // Merged theme (defaults of theme.toml + ~/.config/filigrane/fili-mail.toml), as JSON
        #[qinvokable]
        #[cxx_name = "themeJson"]
        fn theme_json(self: &Facteur) -> QString;
        // Translation of a text written in English
        #[qinvokable]
        fn tr(self: &Facteur, text: &QString) -> QString;
        // Accounts of the registry, as JSON: {"accounts": [{id, email, provider, label}], "activeId"}
        #[qinvokable]
        fn accounts(self: &Facteur) -> QString;
        // Add an IMAP account (JSON: email, password, bridge, imapHost, imapPort, smtpHost, smtpPort, username): {"added"} or {"error"}
        #[qinvokable]
        #[cxx_name = "addImap"]
        fn add_imap(self: Pin<&mut Facteur>, spec: &QString);
        #[qsignal]
        #[cxx_name = "accountAdded"]
        fn account_added(self: Pin<&mut Facteur>, result: &QString);
        // Google sign-in (OAuth in the browser): whether a Google client is available, keep the client file Google's
        // console gives ("" or an error code), start the sign-in (the page is opened; `googleStarted` also gives its
        // address) and `accountAdded` follows once the browser is done
        #[qinvokable]
        #[cxx_name = "googleReady"]
        fn google_ready(self: &Facteur) -> bool;
        #[qinvokable]
        #[cxx_name = "saveGoogleClient"]
        fn save_google_client(self: &Facteur, text: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "googleSignIn"]
        fn google_sign_in(self: Pin<&mut Facteur>, hint: &QString);
        #[qsignal]
        #[cxx_name = "googleStarted"]
        fn google_started(self: Pin<&mut Facteur>, url: &QString);
        // Remove an account (registry entry and keyring secret); answered by `accountRemoved` ({"removed"} or {"error"})
        #[qinvokable]
        #[cxx_name = "removeAccount"]
        fn remove_account(self: Pin<&mut Facteur>, id: &QString);
        #[qsignal]
        #[cxx_name = "accountRemoved"]
        fn account_removed(self: Pin<&mut Facteur>, result: &QString);
        // Change messages: operation read, unread, star, unstar, archive, trash or spam; ids = JSON array.
        // Answered by `acted` (account, operation, ids, JSON result)
        #[qinvokable]
        fn act(self: Pin<&mut Facteur>, account: &QString, operation: &QString, ids: &QString);
        #[qsignal]
        fn acted(
            self: Pin<&mut Facteur>,
            account: &QString,
            operation: &QString,
            ids: &QString,
            result: &QString,
        );
        // Messages of a mailbox of an account, narrowed by a search text (may be empty); answered by `listed` (JSON: {messages, estimate} or {error})
        #[qinvokable]
        fn list(self: Pin<&mut Facteur>, account: &QString, mailbox: &QString, query: &QString);
        #[qsignal]
        fn listed(
            self: Pin<&mut Facteur>,
            account: &QString,
            mailbox: &QString,
            query: &QString,
            result: &QString,
        );
        // One message; answered by `opened` (JSON)
        #[qinvokable]
        #[cxx_name = "openMessage"]
        fn open_message(self: Pin<&mut Facteur>, account: &QString, id: &QString);
        #[qsignal]
        fn opened(self: Pin<&mut Facteur>, id: &QString, result: &QString);
        // The same message with its remote pictures loaded (the user asked for them); answered by `opened`
        #[qinvokable]
        #[cxx_name = "loadImages"]
        fn load_images(self: Pin<&mut Facteur>, account: &QString, id: &QString);
        // Send a message: fields = JSON {to, cc, bcc, subject, body} (address lists as strings);
        // answered by `sent` (JSON result or {error})
        #[qinvokable]
        fn send(self: Pin<&mut Facteur>, account: &QString, fields: &QString);
        #[qsignal]
        fn sent(self: Pin<&mut Facteur>, result: &QString);
        // A menu command from `fili-mail ctl action NAME` (the fili-bar menu)
        #[qsignal]
        fn command(self: Pin<&mut Facteur>, name: &QString);
        // Rows of the About card: JSON [[label, value], ...]
        #[qinvokable]
        #[cxx_name = "aboutRows"]
        fn about_rows(self: &Facteur) -> QString;
        // file:// url of the Filigrane logo for the current theme
        #[qinvokable]
        #[cxx_name = "aboutLogo"]
        fn about_logo(self: &Facteur) -> QString;
    }

    impl cxx_qt::Initialize for Facteur {}
    impl cxx_qt::Threading for Facteur {}
}

use core::pin::Pin;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use fili_mail::{
    account::setup::{
        ImapSpec, add_imap, google_begin, google_client_configured, google_poll, remove_account,
        save_google_client,
    },
    backend::{Session, runtime},
};
use qobject::*;
use serde_json::{Value, json};
use std::{env, path::PathBuf, sync::OnceLock};

#[derive(Default)]
pub struct FacteurRust {
    light: bool,
    accent: QString,
    key_nav: bool,
}

// One engine for the window: the same Session the daemon and the CLI use, on its own runtime
fn engine() -> &'static (tokio::runtime::Runtime, Session) {
    static ENGINE: OnceLock<(tokio::runtime::Runtime, Session)> = OnceLock::new();
    ENGINE.get_or_init(|| (runtime().expect("tokio runtime"), Session::default()))
}

fn home() -> String {
    env::var("HOME").unwrap_or_default()
}

// State of fili-theme ("light" or "dark"), like FiliTheme.qml of the fili-shell
fn theme_file() -> PathBuf {
    let state = env::var("XDG_STATE_HOME").unwrap_or_else(|_| format!("{}/.local/state", home()));
    PathBuf::from(state).join("filigrane/theme")
}

// Light mode: Filigrane's state file when there is one, else the desktop's color scheme (settings portal), else dark
fn read_light() -> bool {
    match std::fs::read_to_string(theme_file()) {
        Ok(t) => t.trim() == "light",
        Err(_) => super::appearance::prefers_light().unwrap_or(false),
    }
}

// Accent color (name), "default" by default
fn read_accent() -> String {
    std::fs::read_to_string(theme_file().with_file_name("accent"))
        .map(|t| t.trim().to_string())
        .unwrap_or_else(|_| "default".into())
}

fn error_json(error: &str) -> String {
    json!({"error": error}).to_string()
}

impl cxx_qt::Initialize for Facteur {
    fn initialize(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().light = read_light();
        self.as_mut().rust_mut().accent = QString::from(&read_accent());
        // Commands of the fili-bar menu
        let qt = self.qt_thread();
        crate::ctl::serve(move |name| {
            let _ = qt.queue(move |f| f.command(&QString::from(&name)));
        });
        // Without Filigrane's state file, follow the desktop's color scheme (settings portal signal, blocking thread)
        if !theme_file().exists() {
            let qt = self.qt_thread();
            std::thread::spawn(move || {
                super::appearance::watch(|light| {
                    let _ = qt.queue(move |mut f| {
                        if f.light != light {
                            f.as_mut().rust_mut().light = light;
                            f.as_mut().theme_changed();
                        }
                    });
                });
            });
        }
        // Follow the state directory (inotify, thread blocked on read: no wake-up while nothing changes)
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let file = theme_file();
            let Some(dir) = file.parent() else { return };
            let _ = std::fs::create_dir_all(dir);
            let Ok(c) = std::ffi::CString::new(dir.as_os_str().as_encoded_bytes()) else {
                return;
            };
            // SAFETY: plain inotify calls on a descriptor owned by this thread.
            let fd = unsafe { libc::inotify_init1(libc::IN_CLOEXEC) };
            if fd < 0
                || unsafe {
                    libc::inotify_add_watch(
                        fd,
                        c.as_ptr(),
                        libc::IN_CLOSE_WRITE | libc::IN_MOVED_TO | libc::IN_CREATE,
                    )
                } < 0
            {
                return;
            }
            let mut buf = [0u8; 4096];
            loop {
                // SAFETY: reads into a buffer of the stated length.
                if unsafe { libc::read(fd, buf.as_mut_ptr().cast(), buf.len()) } <= 0 {
                    return;
                }
                let (light, accent) = (read_light(), read_accent());
                let sent = qt.queue(move |mut f| {
                    if f.light != light || f.accent.to_string() != accent {
                        f.as_mut().rust_mut().light = light;
                        f.as_mut().rust_mut().accent = QString::from(&accent);
                        f.as_mut().theme_changed();
                    }
                });
                if sent.is_err() {
                    return;
                }
            }
        });
    }
}

impl qobject::Facteur {
    pub fn theme_json(&self) -> QString {
        QString::from(&super::theme::theme_json())
    }

    pub fn tr(&self, text: &QString) -> QString {
        QString::from(&super::i18n::tr(&text.to_string()))
    }

    pub fn accounts(&self) -> QString {
        let (runtime, session) = engine();
        let out = match runtime.block_on(session.dispatch("accounts.list", &json!({}))) {
            Ok(v) => v.to_string(),
            Err(e) => error_json(e),
        };
        QString::from(&out)
    }

    pub fn add_imap(self: Pin<&mut Self>, spec: &QString) {
        let spec: Value = serde_json::from_str(&spec.to_string()).unwrap_or_default();
        let text = |key: &str| {
            spec[key]
                .as_str()
                .map(str::to_owned)
                .filter(|v| !v.is_empty())
        };
        let port = |key: &str| spec[key].as_u64().and_then(|p| u16::try_from(p).ok());
        let spec = ImapSpec {
            email: text("email").unwrap_or_default(),
            password: text("password").unwrap_or_default(),
            label: text("label").unwrap_or_default(),
            username: text("username"),
            bridge: spec["bridge"] == true,
            imap_host: text("imapHost"),
            imap_port: port("imapPort"),
            smtp_host: text("smtpHost"),
            smtp_port: port("smtpPort"),
        };
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            let out = match add_imap(session, &spec).await {
                Ok(v) => v.to_string(),
                Err(e) => error_json(e),
            };
            let _ = qt.queue(move |f| f.account_added(&QString::from(&out)));
        });
    }

    pub fn google_ready(&self) -> bool {
        google_client_configured()
    }

    pub fn save_google_client(&self, text: &QString) -> QString {
        match save_google_client(&text.to_string()) {
            Ok(()) => QString::default(),
            Err(e) => QString::from(e),
        }
    }

    pub fn google_sign_in(self: Pin<&mut Self>, hint: &QString) {
        let hint = hint.to_string();
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            let out = async {
                let started = google_begin(session, &hint).await?;
                let id = started["id"]
                    .as_str()
                    .ok_or("auth_invalid_response")?
                    .to_owned();
                let url = started["url"]
                    .as_str()
                    .ok_or("auth_invalid_response")?
                    .to_owned();
                let _ = std::process::Command::new("xdg-open")
                    .arg(&url)
                    .stdin(std::process::Stdio::null())
                    .stdout(std::process::Stdio::null())
                    .stderr(std::process::Stdio::null())
                    .spawn();
                let shown = QString::from(&url);
                let _ = qt.queue(move |f| f.google_started(&shown));
                // The engine gives up after 180 s and answers with an error
                loop {
                    tokio::time::sleep(std::time::Duration::from_secs(1)).await;
                    if let Some(done) = google_poll(session, &id).await? {
                        return Ok::<Value, &'static str>(done);
                    }
                }
            }
            .await;
            let out = match out {
                Ok(v) => v.to_string(),
                Err(e) => error_json(e),
            };
            let _ = qt.queue(move |f| f.account_added(&QString::from(&out)));
        });
    }

    pub fn remove_account(self: Pin<&mut Self>, id: &QString) {
        let id = id.to_string();
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            let out = match remove_account(session, &id).await {
                Ok(v) => v.to_string(),
                Err(e) => error_json(e),
            };
            let _ = qt.queue(move |f| f.account_removed(&QString::from(&out)));
        });
    }

    pub fn act(self: Pin<&mut Self>, account: &QString, operation: &QString, ids: &QString) {
        let (account, operation, ids) =
            (account.to_string(), operation.to_string(), ids.to_string());
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            let list: Value = serde_json::from_str(&ids).unwrap_or_default();
            let params =
                json!({"account": account, "operation": operation, "ids": list, "execute": true});
            let out = match session.dispatch("mail.act", &params).await {
                Ok(v) => v.to_string(),
                Err(e) => error_json(e),
            };
            let _ = qt.queue(move |f| {
                f.acted(
                    &QString::from(&account),
                    &QString::from(&operation),
                    &QString::from(&ids),
                    &QString::from(&out),
                )
            });
        });
    }

    pub fn list(self: Pin<&mut Self>, account: &QString, mailbox: &QString, query: &QString) {
        let (account, mailbox, query) = (account.to_string(), mailbox.to_string(), query.to_string());
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            let params = json!({"account": account, "mailbox": mailbox, "query": query, "limit": 50});
            let out = match session.dispatch("mail.list", &params).await {
                Ok(v) => v.to_string(),
                Err(e) => error_json(e),
            };
            let _ = qt.queue(move |f| {
                f.listed(
                    &QString::from(&account),
                    &QString::from(&mailbox),
                    &QString::from(&query),
                    &QString::from(&out),
                )
            });
        });
    }

    pub fn open_message(self: Pin<&mut Self>, account: &QString, id: &QString) {
        let (account, id) = (account.to_string(), id.to_string());
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            let out = match read_message(session, &account, &id, false).await {
                Ok(v) => v.to_string(),
                Err(e) => error_json(e),
            };
            let _ = qt.queue(move |f| f.opened(&QString::from(&id), &QString::from(&out)));
        });
    }

    pub fn load_images(self: Pin<&mut Self>, account: &QString, id: &QString) {
        let (account, id) = (account.to_string(), id.to_string());
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            let out = match read_message(session, &account, &id, true).await {
                Ok(v) => v.to_string(),
                Err(e) => error_json(e),
            };
            let _ = qt.queue(move |f| f.opened(&QString::from(&id), &QString::from(&out)));
        });
    }

    pub fn about_rows(&self) -> QString {
        let t = |s: &str| super::i18n::tr(s);
        let home = env::var("HOME").unwrap_or_default();
        let settings = format!("{home}/.config/filigrane/fili-mail.toml").replace(&home, "~");
        let rows = json!([
            [t("Version"), env!("CARGO_PKG_VERSION")],
            [t("Also known as"), "fili-mail"],
            [t("Part of"), "Filigrane"],
            [t("Built with"), "Rust, Qt Quick"],
            [t("Settings"), settings],
        ]);
        QString::from(&rows.to_string())
    }

    pub fn about_logo(&self) -> QString {
        let home = env::var("HOME").unwrap_or_default();
        let shade = if self.light { "blanc" } else { "ardoise" };
        QString::from(&format!("file://{home}/.local/share/filigrane/filigrane-mono-{shade}.svg"))
    }

    pub fn send(self: Pin<&mut Self>, account: &QString, fields: &QString) {
        let (account, fields) = (account.to_string(), fields.to_string());
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            let out = match send_message(session, &account, &fields).await {
                Ok(v) => v.to_string(),
                Err(e) => error_json(e),
            };
            let _ = qt.queue(move |f| f.sent(&QString::from(&out)));
        });
    }
}

/// Split an address field ("a@x.org, b@y.org") into the list the engine wants.
fn address_list(text: &str) -> Vec<String> {
    text.split([',', ';'])
        .map(str::trim)
        .filter(|part| !part.is_empty())
        .map(str::to_owned)
        .collect()
}

async fn send_message(session: &Session, account: &str, fields: &str) -> Result<Value, &'static str> {
    let fields: Value = serde_json::from_str(fields).map_err(|_| "invalid_params")?;
    let text = |name: &str| fields[name].as_str().unwrap_or("").to_owned();
    let params = json!({
        "account": account,
        "to": address_list(&text("to")),
        "cc": address_list(&text("cc")),
        "bcc": address_list(&text("bcc")),
        "subject": text("subject"),
        "body": text("body"),
        "execute": true,
    });
    let mut result = session.dispatch("mail.send", &params).await?;
    session.finish_cli_send(&mut result).await?;
    Ok(result)
}

fn host_is_local(url: &reqwest::Url) -> bool {
    use std::net::IpAddr;
    let Some(host) = url.host_str() else { return true };
    let host = host.trim_start_matches('[').trim_end_matches(']').to_ascii_lowercase();
    match host.parse::<IpAddr>() {
        Ok(IpAddr::V4(ip)) => ip.is_private() || ip.is_loopback() || ip.is_link_local() || ip.is_unspecified(),
        Ok(IpAddr::V6(ip)) => {
            let first = ip.segments()[0];
            ip.is_loopback() || ip.is_unspecified() || first & 0xfe00 == 0xfc00 || first & 0xffc0 == 0xfe80
        }
        Err(_) => host == "localhost" || host.ends_with(".localhost") || host.ends_with(".local") || host.ends_with(".internal"),
    }
}

/// Remote pictures of a message as data URIs, fetched by this program (never by the interface): the public
/// http(s) sources the engine vetted, redirects limited and kept away from the local network, small
/// pictures only. Anything that is not a real picture is left out.
async fn fetch_pictures(sources: &[String]) -> Value {
    use base64::{Engine, engine::general_purpose::STANDARD};
    use fili_mail::message::picture::{MAX_PICTURE, describe};
    let policy = reqwest::redirect::Policy::custom(|attempt| {
        if attempt.previous().len() >= 3 || host_is_local(attempt.url()) {
            attempt.stop()
        } else {
            attempt.follow()
        }
    });
    let Ok(client) = reqwest::Client::builder()
        .redirect(policy)
        .timeout(std::time::Duration::from_secs(10))
        .user_agent("Mozilla/5.0")
        .build()
    else {
        return json!({});
    };
    let mut jobs = tokio::task::JoinSet::new();
    for source in sources.iter().take(24) {
        let (client, source) = (client.clone(), source.clone());
        jobs.spawn(async move {
            let url = reqwest::Url::parse(&source).ok().filter(|u| matches!(u.scheme(), "http" | "https") && !host_is_local(u))?;
            let mut response = client.get(url).send().await.ok()?.error_for_status().ok()?;
            let mut bytes = Vec::new();
            while let Some(chunk) = response.chunk().await.ok()? {
                bytes.extend_from_slice(&chunk);
                if bytes.len() > MAX_PICTURE {
                    return None;
                }
            }
            let (ext, _, _) = describe(&bytes)?;
            let mime = if ext == "jpg" { "jpeg" } else { ext };
            Some((source, format!("data:image/{mime};base64,{}", STANDARD.encode(&bytes))))
        });
    }
    let mut out = serde_json::Map::new();
    let mut total = 0;
    while let Some(Ok(Some((source, uri)))) = jobs.join_next().await {
        total += uri.len();
        if total <= 24 * 1024 * 1024 {
            out.insert(source, json!(uri));
        }
    }
    Value::Object(out)
}

/// One message for the window: the engine's read, its HTML as rich text (pictures stored in the cache) and, when
/// the sender's remote pictures were held back, how many there are. `load`: fetch them and read again with them.
async fn read_message(session: &Session, account: &str, id: &str, load: bool) -> Result<Value, &'static str> {
    let mut params = json!({"account": account, "id": id});
    let mut value = session.dispatch("mail.read", &params).await?;
    let sources: Vec<String> = value["message"]["nativeRender"]["remoteImageSources"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|s| s.as_str().map(str::to_owned))
        .collect();
    let mut pending = sources.len();
    if load && !sources.is_empty() {
        params["allowRemoteImages"] = json!(true);
        params["remoteImageData"] = fetch_pictures(&sources).await;
        value = session.dispatch("mail.read", &params).await?;
        pending = 0;
    }
    let message = &mut value["message"];
    if message["nativeContent"]["body"]["source"] == "html" {
        let rich = fili_mail::message::rich::rich_text(&message["nativeRender"], &message["links"], &|uri| {
            fili_mail::message::picture::store_data_uri(uri)
        });
        message["rich"] = json!(rich);
    }
    message["remoteImages"] = json!(pending);
    // The document tree (with picture data) stays on this side
    message["nativeRender"] = Value::Null;
    Ok(value)
}
