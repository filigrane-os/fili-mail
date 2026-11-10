//! Facteur's window: Qt Quick interface (qml/) over the mail engine of this crate.
pub mod appearance;
pub mod bridge;
pub mod i18n;
pub mod theme;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};

/// Open the window; returns the process exit code.
pub fn run() -> i32 {
    // Static initializers of the Qt side (cxx-qt types, this crate, the QML module). Named here, they are linked in:
    // the package also has a library crate, which hides them from the linker otherwise.
    cxx_qt::init_crate!(cxx_qt_lib);
    cxx_qt::init_crate!(fili_mail);
    cxx_qt::init_qml_module!("Fili.Mail");
    let mut app = QGuiApplication::new();
    // Wayland app-id (niri rules, fili-mail.desktop)
    QGuiApplication::set_desktop_file_name(&QString::from("fili-mail"));
    let mut engine = QQmlApplicationEngine::new();
    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/Fili/Mail/qml/Main.qml"));
    }
    match app.as_mut() {
        Some(app) => app.exec(),
        None => 1,
    }
}
