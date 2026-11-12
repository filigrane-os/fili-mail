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
        // Counts the changes of the settings files (fili-mail.toml, theme.toml): bindings that read it, and the header and
        // footer of the window (Main.qml, onThemeChanged), follow a change made while the window is open
        #[qproperty(i32, settings_rev, cxx_name = "settingsRev", READ, NOTIFY = theme_changed)]
        #[qproperty(bool, key_nav, cxx_name = "keyNav")]
        type Facteur = super::FacteurRust;

        #[qsignal]
        #[cxx_name = "themeChanged"]
        fn theme_changed(self: Pin<&mut Facteur>);

        // Merged theme (defaults of theme.toml + ~/.config/filigrane/fili-mail.toml), as JSON
        #[qinvokable]
        #[cxx_name = "themeJson"]
        fn theme_json(self: &Facteur) -> QString;
        // Labels of a Gmail account (the ones the user made); answered by `labelsLoaded` (JSON array)
        #[qinvokable]
        #[cxx_name = "loadLabels"]
        fn load_labels(self: Pin<&mut Facteur>, account: &QString);
        #[qsignal]
        #[cxx_name = "labelsLoaded"]
        fn labels_loaded(self: Pin<&mut Facteur>, account: &QString, result: &QString);
        // Create a Gmail label with a colour (hex background and text, from Gmail's palette); answered by `labelCreated`
        #[qinvokable]
        #[cxx_name = "createLabel"]
        fn create_label(self: Pin<&mut Facteur>, account: &QString, name: &QString, background: &QString, text: &QString);
        #[qsignal]
        #[cxx_name = "labelCreated"]
        fn label_created(self: Pin<&mut Facteur>, account: &QString, result: &QString);
        // Folders and labels of an IMAP account (Proton Bridge: `Labels/...`); answered by `labelsLoaded`
        #[qinvokable]
        #[cxx_name = "loadFolders"]
        fn load_folders(self: Pin<&mut Facteur>, account: &QString);
        // Folders of an IMAP account: create, rename, delete; answered by `labelChanged`
        #[qinvokable]
        #[cxx_name = "createFolder"]
        fn create_folder(self: Pin<&mut Facteur>, account: &QString, name: &QString);
        #[qinvokable]
        #[cxx_name = "renameFolder"]
        fn rename_folder(self: Pin<&mut Facteur>, account: &QString, id: &QString, name: &QString);
        #[qinvokable]
        #[cxx_name = "deleteFolder"]
        fn delete_folder(self: Pin<&mut Facteur>, account: &QString, id: &QString);
        // Window management under niri (the window panel of the toolbar)
        #[qinvokable]
        #[cxx_name = "windowControl"]
        fn window_control(self: &Facteur) -> bool;
        #[qinvokable]
        #[cxx_name = "windowState"]
        fn window_state(self: &Facteur) -> QString;
        #[qinvokable]
        #[cxx_name = "windowAction"]
        fn window_action(self: &Facteur, name: &QString) -> bool;
        // Header and footer of the window: false = hidden ([window] header|footer, --no-header, --no-footer)
        #[qinvokable]
        #[cxx_name = "header"]
        fn header(self: &Facteur) -> bool;
        #[qinvokable]
        #[cxx_name = "footer"]
        fn footer(self: &Facteur) -> bool;
        // Interface state kept between runs (~/.local/state/filigrane/mail/ui, lines key=value)
        #[qinvokable]
        #[cxx_name = "uiGet"]
        fn ui_get(self: &Facteur, key: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "uiSet"]
        fn ui_set(self: &Facteur, key: &QString, value: &QString);
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
        // Addresses seen in the mail already received (cache), the address books of the machine and contacts.json:
        // a JSON array of {name, email}, for the recipient suggestions of a new message
        #[qinvokable]
        fn contacts(self: &Facteur) -> QString;
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
        // Edit an account: its details (JSON, no password) and the update; answered by `accountUpdated`
        #[qinvokable]
        #[cxx_name = "accountDetails"]
        fn account_details(self: &Facteur, id: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "updateAccount"]
        fn update_account(self: Pin<&mut Facteur>, id: &QString, patch: &QString);
        #[qsignal]
        #[cxx_name = "accountUpdated"]
        fn account_updated(self: Pin<&mut Facteur>, result: &QString);
        // Rename / recolour / delete a Gmail label; answered by `labelChanged` (account, JSON result)
        #[qinvokable]
        #[cxx_name = "updateLabel"]
        fn update_label(self: Pin<&mut Facteur>, account: &QString, id: &QString, name: &QString, background: &QString, text: &QString);
        #[qinvokable]
        #[cxx_name = "deleteLabel"]
        fn delete_label(self: Pin<&mut Facteur>, account: &QString, id: &QString);
        #[qsignal]
        #[cxx_name = "labelChanged"]
        fn label_changed(self: Pin<&mut Facteur>, account: &QString, result: &QString);
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
        fn list(self: Pin<&mut Facteur>, account: &QString, mailbox: &QString, query: &QString, token: &QString);
        #[qsignal]
        fn listed(
            self: Pin<&mut Facteur>,
            account: &QString,
            mailbox: &QString,
            query: &QString,
            result: &QString,
        );
        // The last first page of a mailbox as `listed` gave it ("" when there is none), to fill the list at once
        // while the server answers
        #[qinvokable]
        #[cxx_name = "cachedList"]
        fn cached_list(self: &Facteur, account: &QString, mailbox: &QString) -> QString;
        // Unread messages of an account's inbox; answered by `unreadCounted` (-1 when the server did not answer)
        #[qinvokable]
        #[cxx_name = "countUnread"]
        fn count_unread(self: Pin<&mut Facteur>, account: &QString);
        #[qsignal]
        #[cxx_name = "unreadCounted"]
        fn unread_counted(self: Pin<&mut Facteur>, account: &QString, count: i32);
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
        // Save an attachment of a message to the Downloads folder; answered by `attachmentSaved` ({path} or {error})
        #[qinvokable]
        #[cxx_name = "saveAttachment"]
        fn save_attachment(self: Pin<&mut Facteur>, account: &QString, id: &QString, attachment: &QString, filename: &QString);
        // Open an attachment with the desktop's application (saved in the runtime directory first); answered by
        // `attachmentSaved` ({path, opened: true} or {error})
        #[qinvokable]
        #[cxx_name = "openAttachment"]
        fn open_attachment(self: Pin<&mut Facteur>, account: &QString, id: &QString, attachment: &QString, filename: &QString);
        // Save every attachment (JSON [{attachmentId, filename}]) to the Downloads folder; answered by
        // `attachmentSaved` ({count, path} or {error})
        #[qinvokable]
        #[cxx_name = "saveAllAttachments"]
        fn save_all_attachments(self: Pin<&mut Facteur>, account: &QString, id: &QString, list: &QString);
        #[qsignal]
        #[cxx_name = "attachmentSaved"]
        fn attachment_saved(self: Pin<&mut Facteur>, result: &QString);
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
    settings_rev: i32,
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

// Interface choices that outlive the window (layout of the panes)
fn ui_file() -> PathBuf {
    let state = env::var("XDG_STATE_HOME").unwrap_or_else(|_| format!("{}/.local/state", home()));
    PathBuf::from(state).join("filigrane/mail/ui")
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
        // Follow the settings directory (~/.config/filigrane: fili-mail.toml, theme.toml written by `fili-theme font|header|footer`
        // or by hand): same thread model as below
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let dir = fili_mail::window_parts::config_dir();
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
                let sent = qt.queue(move |mut f| {
                    let rev = f.settings_rev.wrapping_add(1);
                    f.as_mut().rust_mut().settings_rev = rev;
                    f.as_mut().theme_changed();
                });
                if sent.is_err() {
                    return;
                }
            }
        });
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

    pub fn load_labels(self: Pin<&mut Self>, account: &QString) {
        let account = account.to_string();
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            let out = match session.dispatch("gmail.labels", &json!({"accountId": account})).await {
                Ok(v) => v,
                Err(_) => json!([]),
            };
            let mut labels: Vec<Value> = out.as_array().cloned().unwrap_or_default().into_iter().filter(|l| l["system"] == false).collect();
            labels.sort_by_key(|l| l["rawName"].as_str().unwrap_or("").to_lowercase());
            let out = Value::Array(labels).to_string();
            let _ = qt.queue(move |f| f.labels_loaded(&QString::from(&account), &QString::from(&out)));
        });
    }

    pub fn create_label(self: Pin<&mut Self>, account: &QString, name: &QString, background: &QString, text: &QString) {
        let (account, name, background, text) = (account.to_string(), name.to_string(), background.to_string(), text.to_string());
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            let params = json!({"accountId": account, "name": name, "color": {"backgroundColor": background, "textColor": text}});
            let out = match session.dispatch("gmail.createLabel", &params).await {
                Ok(v) => v.to_string(),
                Err(e) => error_json(e),
            };
            let _ = qt.queue(move |f| f.label_created(&QString::from(&account), &QString::from(&out)));
        });
    }

    pub fn header(&self) -> bool {
        fili_mail::window_parts::shown_now("header")
    }

    pub fn footer(&self) -> bool {
        fili_mail::window_parts::shown_now("footer")
    }

    pub fn ui_get(&self, key: &QString) -> QString {
        let key = key.to_string();
        let text = std::fs::read_to_string(ui_file()).unwrap_or_default();
        let value = text.lines().find_map(|l| l.strip_prefix(&format!("{key}="))).unwrap_or("");
        QString::from(value)
    }

    pub fn ui_set(&self, key: &QString, value: &QString) {
        let (key, value) = (key.to_string(), value.to_string());
        let path = ui_file();
        let old = std::fs::read_to_string(&path).unwrap_or_default();
        let mut lines: Vec<String> = old.lines().filter(|l| !l.starts_with(&format!("{key}="))).map(str::to_owned).collect();
        lines.push(format!("{key}={value}"));
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let _ = std::fs::write(&path, lines.join("\n") + "\n");
    }

    pub fn load_folders(self: Pin<&mut Self>, account: &QString) {
        let account = account.to_string();
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            let answer = session.dispatch("imap.folders", &json!({"accountId": account})).await.unwrap_or_default();
            let mut folders: Vec<Value> = answer["labels"]
                .as_array()
                .cloned()
                .unwrap_or_default()
                .into_iter()
                // Folders and labels the user made: not the system boxes the sidebar already has, nor "Labels"/"Folders" themselves
                .filter(|l| l["system"] == false)
                .filter(|l| !matches!(l["rawName"].as_str(), Some("Labels" | "Folders" | "All Mail" | "INBOX" | "Starred")))
                .map(|l| {
                    let raw = l["rawName"].as_str().unwrap_or("");
                    let shown = l["name"].as_str().unwrap_or(raw);
                    let prefix = if shown.starts_with("Labels/") { "Labels/" } else if shown.starts_with("Folders/") { "Folders/" } else { "" };
                    let name = &shown[prefix.len()..];
                    json!({"id": raw, "rawName": name, "prefix": prefix, "color": "", "unread": 0, "folder": true, "group": if prefix == "Folders/" { "Folders" } else { "Labels" }})
                })
                .collect();
            folders.sort_by_key(|l| (l["group"].as_str().unwrap_or("").to_owned(), l["rawName"].as_str().unwrap_or("").to_lowercase()));
            let out = Value::Array(folders).to_string();
            let _ = qt.queue(move |f| f.labels_loaded(&QString::from(&account), &QString::from(&out)));
        });
    }

    pub fn create_folder(self: Pin<&mut Self>, account: &QString, name: &QString) {
        self.folder_call("imap.createFolder", json!({"name": name.to_string()}), account);
    }

    pub fn rename_folder(self: Pin<&mut Self>, account: &QString, id: &QString, name: &QString) {
        self.folder_call("imap.renameFolder", json!({"id": id.to_string(), "name": name.to_string()}), account);
    }

    pub fn delete_folder(self: Pin<&mut Self>, account: &QString, id: &QString) {
        self.folder_call("imap.deleteFolder", json!({"id": id.to_string()}), account);
    }

    fn folder_call(self: Pin<&mut Self>, method: &'static str, mut params: Value, account: &QString) {
        let account = account.to_string();
        params["accountId"] = json!(account);
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            let out = match session.dispatch(method, &params).await {
                Ok(v) => v.to_string(),
                Err(e) => error_json(e),
            };
            let _ = qt.queue(move |f| f.label_changed(&QString::from(&account), &QString::from(&out)));
        });
    }

    pub fn window_control(&self) -> bool {
        fili_mail::window::available()
    }

    pub fn window_state(&self) -> QString {
        QString::from(&fili_mail::window::state())
    }

    pub fn window_action(&self, name: &QString) -> bool {
        fili_mail::window::run(&name.to_string())
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

    pub fn contacts(&self) -> QString {
        let list = fili_mail::contacts::suggest().unwrap_or_else(|_| json!([]));
        QString::from(list.to_string())
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

    pub fn account_details(&self, id: &QString) -> QString {
        let (runtime, session) = engine();
        let out = match runtime.block_on(fili_mail::account::setup::account_details(session, &id.to_string())) {
            Ok(v) => v.to_string(),
            Err(e) => error_json(e),
        };
        QString::from(&out)
    }

    pub fn update_account(self: Pin<&mut Self>, id: &QString, patch: &QString) {
        let id = id.to_string();
        let patch: Value = serde_json::from_str(&patch.to_string()).unwrap_or_default();
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            let out = match fili_mail::account::setup::update_account(session, &id, &patch).await {
                Ok(v) => v.to_string(),
                Err(e) => error_json(e),
            };
            let _ = qt.queue(move |f| f.account_updated(&QString::from(&out)));
        });
    }

    pub fn update_label(self: Pin<&mut Self>, account: &QString, id: &QString, name: &QString, background: &QString, text: &QString) {
        let (account, id, name, background, text) = (account.to_string(), id.to_string(), name.to_string(), background.to_string(), text.to_string());
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            let mut params = json!({"accountId": account, "id": id, "name": name});
            if !background.is_empty() {
                params["color"] = json!({"backgroundColor": background, "textColor": text});
            }
            let out = match session.dispatch("gmail.renameLabel", &params).await {
                Ok(v) => v.to_string(),
                Err(e) => error_json(e),
            };
            let _ = qt.queue(move |f| f.label_changed(&QString::from(&account), &QString::from(&out)));
        });
    }

    pub fn delete_label(self: Pin<&mut Self>, account: &QString, id: &QString) {
        let (account, id) = (account.to_string(), id.to_string());
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            let out = match session.dispatch("gmail.deleteLabel", &json!({"accountId": account, "id": id})).await {
                Ok(v) => v.to_string(),
                Err(e) => error_json(e),
            };
            let _ = qt.queue(move |f| f.label_changed(&QString::from(&account), &QString::from(&out)));
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

    pub fn cached_list(&self, account: &QString, mailbox: &QString) -> QString {
        let text = list_cache_file(&account.to_string(), &mailbox.to_string()).and_then(|p| std::fs::read_to_string(p).ok());
        QString::from(text.unwrap_or_default())
    }

    pub fn count_unread(self: Pin<&mut Self>, account: &QString) {
        let account = account.to_string();
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            // One message is enough: the answer carries the number of unread ones
            let params = json!({"account": account, "mailbox": "unread", "query": "", "limit": 1});
            let count = match session.dispatch("mail.list", &params).await {
                Ok(v) => v["estimate"].as_u64().map_or(-1, |n| n.min(i32::MAX as u64) as i32),
                Err(_) => -1,
            };
            let _ = qt.queue(move |f| f.unread_counted(&QString::from(&account), count));
        });
    }

    pub fn list(self: Pin<&mut Self>, account: &QString, mailbox: &QString, query: &QString, token: &QString) {
        let (account, mailbox, query, token) = (account.to_string(), mailbox.to_string(), query.to_string(), token.to_string());
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            // "folder:NAME" names an IMAP folder to list instead of one of the fixed mailboxes
            let mut params = match mailbox.strip_prefix("folder:") {
                Some(folder) => json!({"account": account, "mailbox": "inbox", "folder": folder, "query": query, "limit": 50}),
                None => json!({"account": account, "mailbox": mailbox, "query": query, "limit": 50}),
            };
            if !token.is_empty() {
                params["pageToken"] = json!(token);
            }
            let out = match session.dispatch("mail.list", &params).await {
                Ok(mut v) => {
                    // The page continues the list when it was asked with a token
                    v["append"] = json!(!token.is_empty());
                    fili_mail::contacts::remember(&v["messages"]);
                    if token.is_empty() && query.is_empty() {
                        store_list_cache(&account, &mailbox, &v);
                    }
                    v.to_string()
                }
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

    pub fn save_attachment(self: Pin<&mut Self>, account: &QString, id: &QString, attachment: &QString, filename: &QString) {
        let (account, id, attachment, filename) = (account.to_string(), id.to_string(), attachment.to_string(), filename.to_string());
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            let out = match store_attachment(session, &account, &id, &attachment, &filename, false).await {
                Ok(v) => v.to_string(),
                Err(e) => error_json(e),
            };
            let _ = qt.queue(move |f| f.attachment_saved(&QString::from(&out)));
        });
    }

    pub fn open_attachment(self: Pin<&mut Self>, account: &QString, id: &QString, attachment: &QString, filename: &QString) {
        let (account, id, attachment, filename) = (account.to_string(), id.to_string(), attachment.to_string(), filename.to_string());
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            let out = match store_attachment(session, &account, &id, &attachment, &filename, true).await {
                Ok(v) => {
                    let path = v["path"].as_str().unwrap_or("").to_owned();
                    match std::process::Command::new("xdg-open")
                        .arg(&path)
                        .stdin(std::process::Stdio::null())
                        .stdout(std::process::Stdio::null())
                        .stderr(std::process::Stdio::null())
                        .spawn()
                    {
                        Ok(_) => json!({"path": path, "opened": true}).to_string(),
                        Err(_) => error_json("attachment_open_failed"),
                    }
                }
                Err(e) => error_json(e),
            };
            let _ = qt.queue(move |f| f.attachment_saved(&QString::from(&out)));
        });
    }

    pub fn save_all_attachments(self: Pin<&mut Self>, account: &QString, id: &QString, list: &QString) {
        let (account, id, list) = (account.to_string(), id.to_string(), list.to_string());
        let qt = self.qt_thread();
        let (runtime, session) = engine();
        runtime.spawn(async move {
            let items: Vec<Value> = serde_json::from_str(&list).unwrap_or_default();
            let mut saved = 0;
            let mut folder = String::new();
            let mut failure = None;
            for item in &items {
                let (attachment, filename) = (item["attachmentId"].as_str().unwrap_or(""), item["filename"].as_str().unwrap_or("attachment"));
                match store_attachment(session, &account, &id, attachment, filename, false).await {
                    Ok(v) => {
                        saved += 1;
                        if let Some(dir) = v["path"].as_str().and_then(|p| std::path::Path::new(p).parent()) {
                            folder = dir.display().to_string();
                        }
                    }
                    Err(e) => failure = Some(e),
                }
            }
            let out = match (saved, failure) {
                (0, Some(e)) => error_json(e),
                _ => json!({"count": saved, "path": folder}).to_string(),
            };
            let _ = qt.queue(move |f| f.attachment_saved(&QString::from(&out)));
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

/// Fetch one attachment (Gmail: by its attachment id) and write it in Downloads under a name that never overwrites.
async fn store_attachment(session: &Session, account: &str, id: &str, attachment: &str, filename: &str, open: bool) -> Result<Value, &'static str> {
    if attachment.is_empty() {
        return Err("attachment_unavailable");
    }
    // The provider is told by the account id (Gmail ids are plain addresses)
    let method = match account.split_once(':') {
        Some(("imap", _)) => "imap.attachment",
        Some(("jmap", _)) => "jmap.attachment",
        Some(("m365", _)) => "m365.attachment",
        _ => "gmail.attachment",
    };
    let answer = session
        .dispatch(method, &json!({"accountId": account, "messageId": id, "attachmentId": attachment}))
        .await?;
    let data = answer["data"].as_str().ok_or("attachment_data_invalid")?;
    session
        .dispatch("attachment.store", &json!({"filename": filename, "data": data, "open": open}))
        .await
}

/// Where the first page of a mailbox is kept between runs (private: subjects and senders).
fn list_cache_file(account: &str, mailbox: &str) -> Option<PathBuf> {
    let base = env::var_os("XDG_CACHE_HOME").map(PathBuf::from).filter(|p| p.is_absolute()).or_else(|| env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))?;
    let safe = |s: &str| s.chars().map(|c| if c.is_ascii_alphanumeric() || c == '.' || c == '-' { c } else { '_' }).collect::<String>();
    Some(base.join("fili-mail/lists").join(format!("{}__{}.json", safe(account), safe(mailbox))))
}

fn store_list_cache(account: &str, mailbox: &str, answer: &Value) {
    use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
    use std::io::Write;
    let Some(file) = list_cache_file(account, mailbox) else { return };
    if let Some(dir) = file.parent() {
        let _ = std::fs::DirBuilder::new().recursive(true).mode(0o700).create(dir);
    }
    let page = json!({"messages": answer["messages"], "estimate": answer["estimate"]});
    if let Ok(mut out) = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&file) {
        let _ = out.write_all(page.to_string().as_bytes());
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

/// The interface only knows the path and the name of an attachment; the engine wants the size it will then check
/// again while reading the file (a file changed in between is refused).
fn attachments_with_size(list: &Value) -> Vec<Value> {
    let mut out = list.as_array().cloned().unwrap_or_default();
    for item in &mut out {
        let size = item["path"].as_str().and_then(|p| std::fs::metadata(p).ok()).map_or(0, |m| m.len());
        item["size"] = json!(size);
    }
    out
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
        "attachments": attachments_with_size(&fields["attachments"]),
        "inReplyTo": text("inReplyTo"),
        "references": text("references"),
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

/// HTML for HtmlView, written back from the document tree the engine checked node by node (`mail_read`): text
/// keeps its entities; a style sheet (kept by the sanitizer's layout mode, `safe_css`) is written raw.
fn layout_html(node: &Value) -> String {
    fn write(node: &Value, raw: bool, out: &mut String) {
        match node["type"].as_str() {
            Some("text") => {
                let text = node["text"].as_str().unwrap_or("");
                if raw && !text.contains("</") {
                    out.push_str(text)
                } else {
                    out.push_str(&text.replace('<', "&lt;").replace('>', "&gt;"))
                }
            }
            Some("root") => node["children"].as_array().into_iter().flatten().for_each(|c| write(c, false, out)),
            Some("element") => {
                let name = node["name"].as_str().unwrap_or("span");
                if !name.bytes().all(|b| b.is_ascii_alphanumeric()) {
                    return;
                }
                out.push('<');
                out.push_str(name);
                for attr in node["attrs"].as_array().into_iter().flatten() {
                    let (Some(key), Some(value)) = (attr["name"].as_str(), attr["value"].as_str()) else { continue };
                    if key.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-') {
                        // Attributes keep their entities, except the link target, which the engine decoded once
                        let value = if key == "href" { value.replace('&', "&amp;") } else { value.to_owned() };
                        out.push_str(&format!(" {key}=\"{}\"", value.replace('"', "&quot;")));
                    }
                }
                out.push('>');
                if matches!(name, "img" | "br" | "hr" | "col" | "wbr" | "area" | "input") {
                    return;
                }
                let sheet = name == "style";
                node["children"].as_array().into_iter().flatten().for_each(|c| write(c, sheet, out));
                out.push_str(&format!("</{name}>"));
            }
            _ => {}
        }
    }
    let mut out = String::new();
    write(node, false, &mut out);
    out
}

/// One message for the window: the engine's read, its HTML as rich text (pictures stored in the cache) and, when
/// the sender's remote pictures were held back, how many there are. `load`: fetch them and read again with them.
async fn read_message(session: &Session, account: &str, id: &str, load: bool) -> Result<Value, &'static str> {
    // Layout mode: the sanitized HTML stays whole (tables, style sheets) for HtmlView (litehtml)
    let mut params = json!({"account": account, "id": id, "layout": true});
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
        message["html"] = json!(layout_html(&message["nativeRender"]["document"]));
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
