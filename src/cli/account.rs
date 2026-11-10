//! `fili-mail accounts add-imap`: register an IMAP/SMTP account and keep its password in the
//! system keyring. Until the application can do this itself, it is how an account (Proton Mail
//! through Bridge, Fastmail, a server of your own) gets set up.
use clap::Args;
use serde_json::{Value, json};
use std::io::{self, BufRead, IsTerminal, Write};

/// Proton Mail Bridge listens on loopback with its own certificate.
const BRIDGE_HOST: &str = "127.0.0.1";
const BRIDGE_IMAP: u16 = 1143;
const BRIDGE_SMTP: u16 = 1025;

#[derive(Args)]
pub struct AddImap {
    /// Mailbox address, e.g. you@example.org
    #[arg(long)]
    email: String,
    /// Login when it differs from the address (Bridge shows its own user name)
    #[arg(long)]
    username: Option<String>,
    /// Defaults for Proton Mail Bridge (127.0.0.1, ports 1143 and 1025, its certificate trusted)
    #[arg(long)]
    bridge: bool,
    #[arg(long)]
    imap_host: Option<String>,
    #[arg(long)]
    imap_port: Option<u16>,
    #[arg(long)]
    smtp_host: Option<String>,
    #[arg(long)]
    smtp_port: Option<u16>,
    /// Display name of the account
    #[arg(long, default_value = "")]
    label: String,
    /// Read the password from the first line of stdin instead of asking for it
    #[arg(long)]
    password_stdin: bool,
}

fn read_password(from_stdin: bool) -> Result<String, &'static str> {
    let stdin = io::stdin();
    if from_stdin || !stdin.is_terminal() {
        let mut line = String::new();
        stdin
            .lock()
            .read_line(&mut line)
            .map_err(|_| "password_unreadable")?;
        return Ok(line.trim_end_matches(['\r', '\n']).to_owned());
    }
    eprint!("Password: ");
    let _ = io::stderr().flush();
    let echo = EchoOff::new();
    let mut line = String::new();
    let read = stdin.lock().read_line(&mut line);
    drop(echo);
    eprintln!();
    read.map_err(|_| "password_unreadable")?;
    Ok(line.trim_end_matches(['\r', '\n']).to_owned())
}

/// Terminal echo is off while this value lives.
struct EchoOff(Option<libc::termios>);

impl EchoOff {
    fn new() -> Self {
        // SAFETY: tcgetattr/tcsetattr on stdin with a zeroed, fully written termios.
        unsafe {
            let mut state: libc::termios = std::mem::zeroed();
            if libc::tcgetattr(0, &mut state) != 0 {
                return Self(None);
            }
            let saved = state;
            state.c_lflag &= !libc::ECHO;
            libc::tcsetattr(0, libc::TCSANOW, &state);
            Self(Some(saved))
        }
    }
}

impl Drop for EchoOff {
    fn drop(&mut self) {
        if let Some(saved) = self.0 {
            // SAFETY: restores the attributes read in `new`.
            unsafe { libc::tcsetattr(0, libc::TCSANOW, &saved) };
        }
    }
}

impl AddImap {
    pub fn run(
        &self,
        session: &crate::backend::Session,
        runtime: &tokio::runtime::Runtime,
    ) -> Result<Value, &'static str> {
        let email = self.email.trim().to_lowercase();
        if !crate::account::valid_email(&email) {
            return Err("invalid_params");
        }
        let password = read_password(self.password_stdin)?;
        if password.is_empty() {
            return Err("invalid_params");
        }
        let (default_host, default_imap, default_smtp) = if self.bridge {
            (BRIDGE_HOST.to_owned(), BRIDGE_IMAP, BRIDGE_SMTP)
        } else {
            let domain = email.split_once('@').map_or("", |(_, d)| d);
            (format!("imap.{domain}"), 993, 465)
        };
        let imap_host = self.imap_host.clone().unwrap_or(default_host.clone());
        let smtp_host = self.smtp_host.clone().unwrap_or_else(|| {
            if self.bridge {
                default_host.clone()
            } else {
                imap_host.replacen("imap.", "smtp.", 1)
            }
        });
        let mut imap = json!({
            "imapHost": imap_host,
            "imapPort": self.imap_port.unwrap_or(default_imap),
            "smtpHost": smtp_host,
            "smtpPort": self.smtp_port.unwrap_or(default_smtp),
            "username": self.username.clone().unwrap_or(email.clone()),
        });
        if self.bridge {
            imap["insecure"] = json!(true);
        }
        let id = format!("imap:{email}");
        let entry = json!({"provider":"imap","email":email,"label":self.label,"imap":imap});
        let read = runtime.block_on(session.dispatch("accounts.read", &json!({})))?;
        let mut registry = read["registry"].clone();
        let accounts = registry["accounts"]
            .as_array_mut()
            .ok_or("accounts_invalid")?;
        accounts.retain(|a| {
            !(a["provider"] == "imap"
                && a["email"].as_str().map(str::to_lowercase) == Some(email.clone()))
        });
        accounts.push(entry);
        if registry["activeId"].as_str().unwrap_or("").is_empty() {
            registry["activeId"] = json!(id);
        }
        // The password first: an account without one would only fail at the first check.
        runtime.block_on(session.dispatch(
            "credentials.put",
            &json!({"kind":"imap-password","accountId":id,"secret":password}),
        ))?;
        runtime.block_on(session.dispatch(
            "accounts.save",
            &json!({"registry":registry,"revision":read["revision"]}),
        ))?;
        Ok(json!({"added":id}))
    }
}
