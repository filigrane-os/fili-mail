//! Control of an open window: `fili-mail ctl [--pid PID] action NAME` runs a menu command in it.
//! The fili-bar menu (appmenu/fili-mail.json) calls this instead of simulating key presses.
//! One socket per window process: $XDG_RUNTIME_DIR/fili-mail/<pid>.sock, one command per connection
//! ("action<TAB>NAME"), answered by a JSON line {"ok":true} or {"ok":false,"error":"..."}.
use std::{
    fs,
    io::{Read, Write},
    os::unix::net::{UnixListener, UnixStream},
    path::{Path, PathBuf},
    time::Duration,
};

/// The commands of the window (menu entries); the interface runs them by name.
pub const ACTIONS: &[&str] = &[
    "new-message", "next-message", "previous-message", "reply", "reply-all", "forward", "refresh", "archive", "trash", "spam", "star", "unstar",
    "read", "unread", "add-account", "about", "close", "inbox", "unread-box", "starred", "sent",
    "drafts", "archive-box", "spam-box", "trash-box",
];

fn dir() -> Option<PathBuf> {
    let dir = PathBuf::from(std::env::var_os("XDG_RUNTIME_DIR")?).join("fili-mail");
    fs::create_dir_all(&dir).ok()?;
    Some(dir)
}

fn answer(request: &str) -> (String, Option<String>) {
    let (verb, name) = request.trim().split_once('\t').unwrap_or((request.trim(), ""));
    if verb == "action" && ACTIONS.contains(&name) {
        ("{\"ok\":true}".into(), Some(name.to_owned()))
    } else if verb == "action" {
        (format!("{{\"ok\":false,\"error\":\"unknown action: {}\"}}", name.replace(['"', '\\'], "")), None)
    } else {
        ("{\"ok\":false,\"error\":\"unknown command\"}".into(), None)
    }
}

/// Listen for commands in a thread (asleep on accept); `on_action` gets each valid action name.
pub fn serve(on_action: impl Fn(String) + Send + 'static) {
    let Some(dir) = dir() else { return };
    let sock = dir.join(format!("{}.sock", std::process::id()));
    let _ = fs::remove_file(&sock);
    let Ok(listener) = UnixListener::bind(&sock) else { return };
    let _ = fs::set_permissions(&sock, std::os::unix::fs::PermissionsExt::from_mode(0o600));
    std::thread::spawn(move || {
        for mut c in listener.incoming().flatten() {
            let _ = c.set_read_timeout(Some(Duration::from_secs(2)));
            let mut text = String::new();
            let _ = (&mut c).take(4096).read_to_string(&mut text);
            let (reply, action) = answer(&text);
            if let Some(name) = action {
                on_action(name);
            }
            let _ = c.write_all(format!("{reply}\n").as_bytes());
        }
    });
}

fn alive(pid: &str) -> bool {
    Path::new(&format!("/proc/{pid}")).is_dir()
}

/// The socket of the requested pid, otherwise of the most recently started window.
fn target(pid: Option<&str>) -> Option<PathBuf> {
    let dir = dir()?;
    if let Some(pid) = pid.filter(|p| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit())) {
        let s = dir.join(format!("{pid}.sock"));
        return (alive(pid) && s.exists()).then_some(s);
    }
    let mut socks: Vec<_> = fs::read_dir(&dir)
        .ok()?
        .flatten()
        .filter(|e| e.path().extension().is_some_and(|x| x == "sock"))
        .filter(|e| alive(&e.path().file_stem().unwrap_or_default().to_string_lossy()))
        .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path())))
        .collect();
    socks.sort();
    socks.pop().map(|(_, p)| p)
}

const USAGE: &str = "usage: fili-mail ctl [--pid PID] action NAME | actions";

/// `fili-mail ctl ...` (arguments after `ctl`): prints the JSON answer; Err carries the reason.
pub fn run(args: &[String]) -> Result<String, String> {
    let (pid, rest) = match args {
        [flag, pid, rest @ ..] if flag == "--pid" => (Some(pid.as_str()), rest),
        _ => (None, args),
    };
    match rest {
        [verb] if verb == "actions" => Ok(format!("[{}]", ACTIONS.iter().map(|a| format!("\"{a}\"")).collect::<Vec<_>>().join(","))),
        [verb, name] if verb == "action" => {
            let sock = target(pid).ok_or("no fili-mail window")?;
            let mut c = UnixStream::connect(sock).map_err(|e| e.to_string())?;
            c.set_read_timeout(Some(Duration::from_secs(5))).ok();
            c.write_all(format!("action\t{name}\n").as_bytes()).map_err(|e| e.to_string())?;
            c.shutdown(std::net::Shutdown::Write).ok();
            let mut reply = String::new();
            let _ = c.read_to_string(&mut reply);
            let reply = reply.trim().to_owned();
            if reply.starts_with("{\"ok\":true") { Ok(reply) } else { Err(reply) }
        }
        _ => Err(USAGE.into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_action_is_forwarded() {
        let (reply, action) = answer("action\treply\n");
        assert_eq!(reply, "{\"ok\":true}");
        assert_eq!(action.as_deref(), Some("reply"));
    }

    #[test]
    fn unknown_action_is_refused() {
        let (reply, action) = answer("action\trm -rf\n");
        assert!(reply.contains("\"ok\":false"));
        assert!(action.is_none());
        assert!(answer("nope").0.contains("unknown command"));
    }

    #[test]
    fn usage_without_a_command() {
        assert!(run(&[]).is_err());
        assert!(run(&["actions".into()]).unwrap().contains("new-message"));
    }
}
