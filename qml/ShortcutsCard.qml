// Keyboard shortcuts of Facteur (F1): everything can be done without the mouse; the kit's card lists how.
import QtQuick
import Fili.UI
import Fili.Mail

FiliShortcutsCard {
    groups: [
        { title: Facteur.tr("Moving around"), rows: [
            ["F6 / Shift+F6", Facteur.tr("Next / previous pane")],
            ["Alt+1  Alt+2  Alt+3", Facteur.tr("Sidebar, list, reader")],
            ["Ctrl+F  /", Facteur.tr("Search (Enter starts it, Esc clears)")],
            ["Alt+←  Alt+→", Facteur.tr("Back / forward")],
            ["Ctrl+1 … Ctrl+5", Facteur.tr("Category tabs")],
            ["Ctrl+U", Facteur.tr("Unread messages only")],
            ["Ctrl+Shift+P", Facteur.tr("Preview beside or under the list")],
            ["F5  Ctrl+R", Facteur.tr("Refresh")],
            ["Ctrl+Shift+W", Facteur.tr("Window actions")],
            ["Ctrl+Alt+L", Facteur.tr("Debug logs")]
        ] },
        { title: Facteur.tr("List"), rows: [
            ["↑ ↓  J K", Facteur.tr("Move")],
            ["Enter", Facteur.tr("Open")],
            ["X  Ctrl+A  Esc", Facteur.tr("Tick, tick all, untick")],
            ["E  #  S  U", Facteur.tr("Archive, trash, star, read / unread")],
            ["R  A  F", Facteur.tr("Reply, reply all, forward")]
        ] },
        { title: Facteur.tr("Reader"), rows: [
            ["↑ ↓  Space  PageUp  PageDown", Facteur.tr("Scroll")],
            ["Tab  Enter", Facteur.tr("Attachments: save")],
            ["Ctrl+C  Ctrl+A", Facteur.tr("Copy, select all")],
            ["Esc", Facteur.tr("Back to the list")]
        ] },
        { title: Facteur.tr("Sidebar"), rows: [
            ["↑ ↓  Enter", Facteur.tr("Move, open")],
            ["← →", Facteur.tr("Fold, unfold")],
            ["Menu  Shift+F10", Facteur.tr("Edit or delete (menu)")],
            ["+", Facteur.tr("New label or folder")]
        ] },
        { title: Facteur.tr("Writing"), rows: [
            ["Ctrl+N", Facteur.tr("New message")],
            ["Ctrl+Enter", Facteur.tr("Send")],
            ["Ctrl+Shift+C  Ctrl+Shift+B", Facteur.tr("Add Cc, Bcc")],
            ["Ctrl+Shift+U", Facteur.tr("Attach files")],
            ["Ctrl+Shift+H", Facteur.tr("Write as plain text or HTML")],
            ["Ctrl+M  Esc", Facteur.tr("Minimise, discard")]
        ] },
        { title: Facteur.tr("Other"), rows: [
            ["Ctrl+Shift+A", Facteur.tr("Add an account")],
            ["Ctrl+Shift+L", Facteur.tr("New label or folder")],
            ["F1", Facteur.tr("This list")],
            ["Ctrl+Q", Facteur.tr("Quit")]
        ] }
    ]
}
