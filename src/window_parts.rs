//! Parts of the window that can be left out: the header (`header`, headless windows) and the footer (`footer`, the
//! status bar). `[window] header = false` / `footer = false` (written by `fili-theme header|footer off`) in
//! ~/.config/filigrane/fili-mail.toml, which takes precedence, or in the shared ~/.config/filigrane/theme.toml; the
//! command-line flags --no-header / --header and --no-footer / --footer win over both. Absent or invalid: the part is shown.
//! No Qt here, so that the rule is tested with the rest of the crate.

use std::path::PathBuf;

/// `[window] KEY = true|false` of a TOML text; anything else is "not set".
fn setting(text: &str, key: &str) -> Option<bool> {
    let mut in_window = false;
    for line in text.lines() {
        // A `#` inside quotes would be a colour, never a boolean: cutting at the first one is enough here
        let line = line.split('#').next().unwrap_or("").trim();
        if let Some(name) = line.strip_prefix('[').and_then(|r| r.strip_suffix(']')) {
            in_window = name.trim() == "window";
        } else if in_window {
            if let Some((k, v)) = line.split_once('=') {
                if k.trim() == key {
                    return match v.trim().trim_matches('"').trim() {
                        "true" => Some(true),
                        "false" => Some(false),
                        _ => None,
                    };
                }
            }
        }
    }
    None
}

/// Whether the part is shown: flag, then the application's file, then the shared file, then yes.
pub fn shown(key: &str, global: &str, user: &str, args: &[String]) -> bool {
    let (on, off) = (format!("--{key}"), format!("--no-{key}"));
    let flag = args.iter().rev().find_map(|a| {
        if *a == off {
            Some(false)
        } else if *a == on {
            Some(true)
        } else {
            None
        }
    });
    flag.or_else(|| setting(user, key)).or_else(|| setting(global, key)).unwrap_or(true)
}

/// The window flags of the command line (`fili-mail --no-header`): they open the window like no argument does.
pub fn is_flag(arg: &str) -> bool {
    matches!(arg, "--header" | "--no-header" | "--footer" | "--no-footer")
}

/// The folder of the settings files (fili-mail.toml, theme.toml).
pub fn config_dir() -> PathBuf {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config"));
    base.join("filigrane")
}

/// Whether the part is shown, from the files and the arguments of this process.
pub fn shown_now(key: &str) -> bool {
    let read = |name: &str| std::fs::read_to_string(config_dir().join(name)).unwrap_or_default();
    let args: Vec<String> = std::env::args().collect();
    shown(key, &read("theme.toml"), &read("fili-mail.toml"), &args)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn flag_then_app_then_global() {
        let none: Vec<String> = vec![];
        let flag = |f: &str| vec!["fili-mail".to_string(), f.to_string()];
        assert!(shown("header", "", "", &none));
        assert!(!shown("header", "[window]\nheader = false\n", "", &none));
        assert!(shown("header", "[window]\nheader = false\n", "[window]\nheader = true # on\n", &none));
        assert!(shown("header", "[window]\nheader = false\n", "", &flag("--header")));
        assert!(!shown("header", "", "[window]\nheader = true\n", &flag("--no-header")));
        assert!(shown("header", "[window]\nheader = maybe\n", "", &none));
        assert!(!shown("header", "[window]\nheader = \"false\"\n", "", &none));
    }

    #[test]
    fn footer_is_independent_of_the_header() {
        let none: Vec<String> = vec![];
        assert!(!shown("footer", "[window]\nfooter = false\n", "", &none));
        assert!(shown("header", "[window]\nfooter = false\n", "", &none));
        assert!(!shown("footer", "", "", &["--no-footer".to_string()]));
        assert!(shown("footer", "[window]\nfooter = false\n", "", &["--footer".to_string()]));
    }

    #[test]
    fn only_the_window_section_counts() {
        assert!(shown("header", "[theme]\nheader = false\n", "", &[]));
        assert!(!shown("header", "[theme]\nx = 1\n[window]\nheader = false\n[other]\n", "", &[]));
    }

    #[test]
    fn window_flags_are_recognised() {
        assert!(is_flag("--no-footer") && is_flag("--header"));
        assert!(!is_flag("--version") && !is_flag("ctl"));
    }
}
