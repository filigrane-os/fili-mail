// Keyboard shortcuts of Facteur (F1): everything can be done without the mouse; this card lists how.
import QtQuick
import Fili.Mail

Rectangle {
    id: card
    z: 210
    visible: false
    color: FiliTheme.alpha(FiliTheme.backgroundDeep, 0.7)
    focus: visible

    readonly property var groups: [
        { title: Facteur.tr("Moving around"), rows: [
            ["F6 / Shift+F6", Facteur.tr("Next / previous pane")],
            ["Alt+1  Alt+2  Alt+3", Facteur.tr("Sidebar, list, reader")],
            ["Ctrl+F  /", Facteur.tr("Search (Enter starts it, Esc clears)")],
            ["Alt+←  Alt+→", Facteur.tr("Back / forward")],
            ["Ctrl+1 … Ctrl+5", Facteur.tr("Category tabs (Gmail)")],
            ["Ctrl+U", Facteur.tr("Unread messages only")],
            ["Ctrl+Shift+P", Facteur.tr("Preview beside or under the list")],
            ["F5  Ctrl+R", Facteur.tr("Refresh")],
            ["Ctrl+Shift+W", Facteur.tr("Window actions")]
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
            ["Ctrl+M  Esc", Facteur.tr("Minimise, discard")]
        ] },
        { title: Facteur.tr("Other"), rows: [
            ["Ctrl+Shift+A", Facteur.tr("Add an account")],
            ["Ctrl+Shift+L", Facteur.tr("New label or folder")],
            ["F1", Facteur.tr("This list")],
            ["Ctrl+Q", Facteur.tr("Quit")]
        ] }
    ]

    function show() { visible = true; }
    onVisibleChanged: if (visible) forceActiveFocus()
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Escape || e.key === Qt.Key_F1) {
            visible = false;
            e.accepted = true;
        }
    }
    MouseArea { anchors.fill: parent; onClicked: card.visible = false }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(620, card.width - 2 * FiliTheme.margin)
        height: Math.min(card.height - 2 * FiliTheme.margin, flick.contentHeight + 2 * FiliTheme.space5)
        radius: FiliTheme.radiusWindow
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: FiliTheme.border
        MouseArea { anchors.fill: parent }
        Flickable {
            id: flick
            anchors { fill: parent; margins: FiliTheme.space5 }
            contentHeight: column.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: column
                width: flick.width
                spacing: FiliTheme.space2
                Text {
                    text: Facteur.tr("Keyboard shortcuts")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeTitle
                    font.weight: FiliTheme.weightAccent
                    color: FiliTheme.text
                }
                Repeater {
                    model: card.groups
                    Column {
                        required property var modelData
                        width: column.width
                        spacing: 4
                        Item { width: 1; height: FiliTheme.space2 }
                        Text { text: modelData.title; font.family: FiliTheme.font; font.pixelSize: FiliTheme.sizeSmall; font.weight: FiliTheme.weightAccent; color: FiliTheme.muted }
                        Repeater {
                            model: modelData.rows
                            Row {
                                required property var modelData
                                width: column.width
                                spacing: FiliTheme.space3
                                Text { width: 250; text: modelData[0]; font.family: FiliTheme.mono; font.pixelSize: FiliTheme.sizeList; color: FiliTheme.accentColor; elide: Text.ElideRight }
                                Text { width: parent.width - 250 - FiliTheme.space3; text: modelData[1]; font.family: FiliTheme.font; font.pixelSize: FiliTheme.sizeList; color: FiliTheme.text; wrapMode: Text.WordWrap }
                            }
                        }
                    }
                }
            }
        }
    }
}
