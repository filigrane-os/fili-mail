// Modal "Add a folder tab": pick a folder of the account and an icon. Editing a tab (`edit`) only changes its icon.
import QtQuick
import Fili.Mail

Rectangle {
    id: dialog
    // [{key, label, icon}]: folders that are not tabs yet; icon is the default one
    property var folders: []
    property int pick: 0
    property string icon: "inbox"
    property string editKey: ""
    property string editLabel: ""
    readonly property var icons: ["inbox", "mail", "mail-open", "star", "tag", "users", "bell", "chat", "archive", "trash", "spam", "paperclip", "shield", "server", "compose", "forward", "search", "download"]
    signal accepted(string key, string icon)
    signal cancelled()

    function open(list) {
        editKey = "";
        folders = list;
        pick = 0;
        icon = list.length > 0 ? list[0].icon : "inbox";
        visible = true;
        forceActiveFocus();
    }
    function edit(key, label, current) {
        editKey = key;
        editLabel = label;
        icon = current;
        visible = true;
        forceActiveFocus();
    }
    function choose(i) {
        pick = Math.max(0, Math.min(folders.length - 1, i));
        if (folders.length > 0) icon = folders[pick].icon;
    }
    function submit() {
        if (editKey !== "") accepted(editKey, icon);
        else if (folders.length > 0) accepted(folders[pick].key, icon);
    }

    visible: false
    anchors.fill: parent
    color: FiliTheme.alpha("#000000", 0.35)
    z: 100
    focus: visible
    MouseArea { anchors.fill: parent; onClicked: dialog.cancelled() }
    Keys.onEscapePressed: dialog.cancelled()
    Keys.onReturnPressed: dialog.submit()
    Keys.onEnterPressed: dialog.submit()
    Keys.onPressed: event => {
        if (dialog.editKey !== "") return;
        if (event.key === Qt.Key_Down || event.key === Qt.Key_J) dialog.choose(dialog.pick + 1);
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) dialog.choose(dialog.pick - 1);
        else return;
        event.accepted = true;
    }

    Rectangle {
        anchors.centerIn: parent
        width: 340
        height: card.height + 2 * FiliTheme.margin
        radius: FiliTheme.radiusWindow
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: FiliTheme.border
        MouseArea { anchors.fill: parent }
        Column {
            id: card
            x: FiliTheme.margin
            y: FiliTheme.margin
            width: parent.width - 2 * FiliTheme.margin
            spacing: FiliTheme.space3
            Text {
                text: dialog.editKey !== "" ? Facteur.tr("Tab icon: %1").replace("%1", dialog.editLabel) : Facteur.tr("Add a folder tab")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeTitle
                font.weight: FiliTheme.weightAccent
                color: FiliTheme.text
                elide: Text.ElideRight
                width: parent.width
            }
            Text {
                visible: dialog.editKey === ""
                text: Facteur.tr("Folder")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: FiliTheme.muted
            }
            Rectangle {
                visible: dialog.editKey === ""
                width: parent.width
                height: Math.min(200, Math.max(1, list.count) * 28 + 2 * FiliTheme.space1)
                radius: FiliTheme.radiusControl
                color: FiliTheme.background
                border.width: FiliTheme.borderWidth
                border.color: FiliTheme.border
                ListView {
                    id: list
                    anchors { fill: parent; margins: FiliTheme.space1 }
                    clip: true
                    KineticScroll {}
                    model: dialog.folders
                    currentIndex: dialog.pick
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: list.width
                        height: 28
                        radius: FiliTheme.radiusControl
                        color: dialog.pick === index ? FiliTheme.surfaceActive : rowArea.containsMouse ? FiliTheme.surfaceHover : "transparent"
                        Icon { x: FiliTheme.space3; anchors.verticalCenter: parent.verticalCenter; name: modelData.icon; size: 14; color: dialog.pick === index ? FiliTheme.accentColor : FiliTheme.textSecondary }
                        Text {
                            x: FiliTheme.space3 + 14 + FiliTheme.space3
                            width: parent.width - x - FiliTheme.space3
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            elide: Text.ElideRight
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.sizeList
                            color: FiliTheme.text
                        }
                        MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; onClicked: dialog.choose(index); onDoubleClicked: dialog.submit() }
                    }
                }
                FiliScrollBar {
                    flick: list
                    anchors { top: list.top; bottom: list.bottom; right: list.right }
                }
                Text {
                    visible: dialog.folders.length === 0
                    anchors.centerIn: parent
                    text: Facteur.tr("Every folder is already a tab")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeList
                    color: FiliTheme.muted
                }
            }
            Text {
                text: Facteur.tr("Icon")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: FiliTheme.muted
            }
            Grid {
                columns: 6
                spacing: FiliTheme.space2
                Repeater {
                    model: dialog.icons
                    Rectangle {
                        required property string modelData
                        width: 40; height: 32
                        radius: FiliTheme.radiusControl
                        color: dialog.icon === modelData ? FiliTheme.surfaceActive : iconArea.containsMouse ? FiliTheme.surfaceHover : "transparent"
                        Icon { anchors.centerIn: parent; name: modelData; size: 16; color: dialog.icon === modelData ? FiliTheme.accentColor : FiliTheme.text }
                        MouseArea { id: iconArea; anchors.fill: parent; hoverEnabled: true; onClicked: dialog.icon = modelData }
                    }
                }
            }
            Row {
                anchors.right: parent.right
                spacing: FiliTheme.space2
                TextButton { label: Facteur.tr("Cancel"); onClicked: dialog.cancelled() }
                TextButton { label: dialog.editKey !== "" ? Facteur.tr("Save") : Facteur.tr("Add"); primary: true; onClicked: dialog.submit() }
            }
        }
    }
}
