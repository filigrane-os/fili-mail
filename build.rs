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
    let builder = CxxQtBuilder::new_qml_module(
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
                "qml/ShortcutsCard.qml",
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
    .qrc_resources([
        "fonts/Jost-Variable.ttf",
        "fonts/JetBrainsMono-Variable.ttf",
        "fonts/FiliIcons.ttf",
        // The icon of the application, shown by the About card
        "data/icons/hicolor/scalable/apps/fili-mail.svg",
    ])
    .qt_module("Quick")
    .files(["src/gui/bridge.rs"])
    // HtmlView (Fili.Html): HTML mail laid out by litehtml, painted by QPainter
    .cpp_files(["src/gui/html/htmlview.h", "src/gui/html/htmlview.cpp", "src/gui/html/container.cpp"]);
    // SAFETY: only include directories are added to cxx-qt's own C++ build
    let builder = unsafe {
        builder.cc_builder(|cc| {
            cc.include("third_party/litehtml/include").include("third_party/litehtml/include/litehtml").flag_if_supported("-std=c++17");
        })
    };
    builder.build();
    // After the Qt side, so the linker meets litehtml after the code that uses it
    build_litehtml();
}

#[cfg(feature = "gui")]
fn build_litehtml() {
    use std::path::Path;
    let root = Path::new("third_party/litehtml");
    let sources = |dir: &Path, ext: &str| -> Vec<std::path::PathBuf> {
        let mut files: Vec<_> = std::fs::read_dir(dir)
            .expect("third_party/litehtml")
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().is_some_and(|x| x == ext))
            .collect();
        files.sort();
        files
    };
    println!("cargo::rerun-if-changed=third_party/litehtml");
    // gumbo, the HTML5 parser litehtml reads with (C)
    cc::Build::new()
        .files(sources(&root.join("src/gumbo"), "c"))
        .include(root.join("src/gumbo/include"))
        .include(root.join("src/gumbo/include/gumbo"))
        .warnings(false)
        .opt_level(2)
        .compile("gumbo");
    cc::Build::new()
        .cpp(true)
        .std("c++17")
        .files(sources(&root.join("src"), "cpp"))
        .include(root.join("include"))
        .include(root.join("include/litehtml"))
        .include(root.join("src/gumbo/include"))
        .include(root.join("src/gumbo/include/gumbo"))
        .warnings(false)
        .opt_level(2)
        .compile("litehtml");
}
