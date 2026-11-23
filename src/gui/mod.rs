//! Facteur's window: Qt Quick interface (qml/) over the mail engine of this crate.
use fili_ui as _;

pub mod appearance;
pub mod bridge;
pub mod i18n;
pub mod theme;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};

/// Open the window; returns the process exit code.
unsafe extern "C" {
    // src/gui/html/htmlview.cpp: the HTML reader as `Fili.Html 1.0`
    fn fili_register_html_view();
}

pub fn run() -> i32 {
    // Static initializers of the Qt side (cxx-qt types, this crate, the QML module). Named here, they are linked in:
    // the package also has a library crate, which hides them from the linker otherwise.
    cxx_qt::init_crate!(cxx_qt_lib);
    cxx_qt::init_crate!(fili_mail);
    cxx_qt::init_qml_module!("Fili.Mail");
    // No undo in this window: a sent message leaves at once instead of waiting out the 10 s undo window
    fili_mail::outbox::set_send_delay(0);
    // Without a platform theme, Qt draws its own file dialog; through the portal, "Attach files" opens the desktop's
    // file chooser (Casier on Filigrane). Must be set before the application object exists.
    if std::env::var_os("QT_QPA_PLATFORMTHEME").is_none() {
        // SAFETY: nothing else runs yet (single thread, before Qt starts)
        unsafe { std::env::set_var("QT_QPA_PLATFORMTHEME", "xdgdesktopportal") };
    }
    // The log of the window process (the daemon has its own): before Qt starts, so that its messages are caught from the start
    fili_mail::logs::init("fili-mail", "filigrane-os/fili-mail", option_env!("FILI_MAIL_GIT").unwrap_or(env!("CARGO_PKG_VERSION")), fili_mail::window_parts::incidents_on());
    fili_mail::logs::capture_qt();
    let mut app = QGuiApplication::new();
    // Wayland app-id (niri rules, fili-mail.desktop)
    QGuiApplication::set_desktop_file_name(&QString::from("fili-mail"));
    // SAFETY: registers a QML type; the application object exists and no engine has loaded yet
    unsafe { fili_register_html_view() };
    let mut engine = QQmlApplicationEngine::new();
    if let Some(mut engine) = engine.as_mut() {
        // Development (`make run`): the QML is read from the source folders instead of the binary, so a change of a .qml file
        // needs no build. FILI_QML_DIR holds Main.qml.
        match std::env::var("FILI_QML_DIR") {
            Ok(dir) => engine.load(&QUrl::from(&format!("file://{dir}/Main.qml"))),
            Err(_) => engine.load(&QUrl::from("qrc:/qt/qml/Fili/Mail/qml/Main.qml")),
        }
    }
    match app.as_mut() {
        Some(app) => app.exec(),
        None => 1,
    }
}

#[cfg(test)]
mod tests {
    use std::fs;

    // A misspelled token does not fail at run time: the item just stays transparent
    #[test]
    fn every_theme_token_used_in_qml_is_defined() {
        let defined: Vec<String> = fs::read_to_string(env!("FILI_UI_THEME_QML"))
            .unwrap()
            .lines()
            .filter_map(|l| l.trim().strip_prefix("readonly property "))
            .filter_map(|l| Some(l.split(':').next()?.split_whitespace().last()?.to_string()))
            .chain(["alpha".to_string()])
            .collect();
        for entry in fs::read_dir(format!("{}/qml", env!("CARGO_MANIFEST_DIR"))).unwrap() {
            let path = entry.unwrap().path();
            let text = fs::read_to_string(&path).unwrap();
            for (i, _) in text.match_indices("FiliTheme.") {
                let name: String = text[i + 10..].chars().take_while(|c| c.is_alphanumeric() || *c == '_').collect();
                assert!(defined.contains(&name), "{}: FiliTheme.{name} is not defined", path.display());
            }
        }
    }

    // Every action the panel shows is on the list, and every listed action is in the panel
    #[test]
    fn the_panel_and_the_list_agree() {
        let qml = std::fs::read_to_string(std::path::Path::new(env!("FILI_UI_THEME_QML")).with_file_name("FiliWindowPanel.qml")).unwrap();
        let used: Vec<&str> = qml.split("action: \"").skip(1).filter_map(|t| t.split('"').next()).collect();
        for u in &used {
            assert!(fili_mail::window::ACTIONS.contains(u), "{u} is shown but not allowed");
        }
        for a in fili_mail::window::ACTIONS {
            assert!(used.contains(a), "{a} is allowed but not shown");
        }
    }
}
