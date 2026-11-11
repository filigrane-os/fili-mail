// Qt Quick interface of Facteur, compiled into the binary (module Fili.Mail, qrc:/qt/qml/Fili/Mail/qml/);
// the Rust object it talks to is in src/gui/bridge.rs.
#[cfg(feature = "gui")]
use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

#[cfg(not(feature = "gui"))]
fn main() {}

#[cfg(feature = "gui")]
fn main() {
    // Version of the About card: tag or commit of the repository (absent outside a repository)
    if let Ok(o) = std::process::Command::new("git").args(["describe", "--tags", "--always", "--dirty"]).output() {
        if o.status.success() {
            println!("cargo:rustc-env=FILI_MAIL_GIT={}", String::from_utf8_lossy(&o.stdout).trim());
        }
    }
    CxxQtBuilder::new_qml_module(
        QmlModule::new("Fili.Mail")
            .qml_files([
                "qml/Main.qml",
                "qml/AccountSetup.qml",
                "qml/Sidebar.qml",
                "qml/LabelDialog.qml",
                "qml/PopupMenu.qml",
                "qml/AccountDialog.qml",
                "qml/MessageList.qml",
                "qml/ListBar.qml",
                "qml/Reader.qml",
                "qml/FiliScrollBar.qml",
                "qml/WindowGlyph.qml",
                "qml/WindowPanel.qml",
                "qml/KineticScroll.qml",
                "qml/Compose.qml",
                "qml/AboutCard.qml",
                "qml/Icon.qml",
                "qml/Field.qml",
                "qml/IconButton.qml",
                "qml/TextButton.qml",
                "qml/FocusRing.qml",
            ])
            .qml_file(QmlFile::from("qml/FiliTheme.qml").singleton(true))
            .depend("QtQuick")
            .depend("QtQuick.Controls"),
    )
    // Fonts of the interface travel with the binary: the application looks the same on any distribution
    .qrc_resources(["fonts/Jost-Variable.ttf", "fonts/JetBrainsMono-Variable.ttf", "fonts/FiliIcons.ttf"])
    .qt_module("Quick")
    .files(["src/gui/bridge.rs"])
    .build();
}
