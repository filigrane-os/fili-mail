//! Facteur's window: Qt Quick interface (qml/) over the mail engine of this crate.
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
    let mut app = QGuiApplication::new();
    // Wayland app-id (niri rules, fili-mail.desktop)
    QGuiApplication::set_desktop_file_name(&QString::from("fili-mail"));
    // SAFETY: registers a QML type; the application object exists and no engine has loaded yet
    unsafe { fili_register_html_view() };
    let mut engine = QQmlApplicationEngine::new();
    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/Fili/Mail/qml/Main.qml"));
    }
    match app.as_mut() {
        Some(app) => app.exec(),
        None => 1,
    }
}
