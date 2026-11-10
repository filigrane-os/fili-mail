//! `fili-mail accounts add-imap`: register an IMAP/SMTP account and keep its password in the
//! system keyring. Until the application can do this itself, it is how an account (Proton Mail
//! through Bridge, Fastmail, a server of your own) gets set up.
use crate::account::setup::ImapSpec;
use clap::Args;
use serde_json::Value;
use std::io::{self, BufRead, IsTerminal, Write};

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
        let spec = ImapSpec {
            email: self.email.clone(),
            password: String::new(),
            label: self.label.clone(),
            username: self.username.clone(),
            bridge: self.bridge,
            imap_host: self.imap_host.clone(),
            imap_port: self.imap_port,
            smtp_host: self.smtp_host.clone(),
            smtp_port: self.smtp_port,
        };
        // Validate the address and the servers before asking for a password.
        spec.settings()?;
        let password = read_password(self.password_stdin)?;
        let spec = ImapSpec { password, ..spec };
        runtime.block_on(crate::account::setup::add_imap(session, &spec))
    }
}
