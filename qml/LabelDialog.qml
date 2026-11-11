// Modal "New label": a name and a colour from Gmail's palette (Gmail refuses other colours), with a live preview.
import QtQuick
import Fili.Mail

Rectangle {
    id: dialog
    property bool busy: false
    property string error: ""
    signal created(string name, string background, string text)
    signal cancelled()

    // [background, text] pairs of Gmail's label palette
    readonly property var swatches: [
        ["#fb4c2f", "#ffffff"], ["#ffad47", "#000000"], ["#fad165", "#000000"], ["#16a766", "#ffffff"],
        ["#43d692", "#000000"], ["#2da2bb", "#ffffff"], ["#4a86e8", "#ffffff"], ["#a479e2", "#ffffff"],
        ["#f691b2", "#000000"], ["#cc3a21", "#ffffff"], ["#8e63ce", "#ffffff"], ["#666666", "#ffffff"]
    ]
    property int pick: 6
    // Editing: id of the label (empty: a new one) and its current colour when it is not one of the swatches
    property string editId: ""
    property string editColor: ""
    // Colour only (labels of IMAP servers, which have none: the colour is kept on this computer)
    property bool colorOnly: false
    // IMAP account: the label is a folder of the server; with Proton Bridge it is a label ("Labels/") or a folder ("Folders/")
    property bool imap: false
    property bool bridge: false
    property string kind: "label"
    function bg() { return pick >= 0 ? swatches[pick][0] : editColor; }
    function fg() { return pick >= 0 ? swatches[pick][1] : "#ffffff"; }

    function pickColor(label) {
        colorOnly = true;
        editId = "local:" + label.id;
        editColor = label.color || "";
        name.text = label.rawName;
        error = "";
        pick = swatches.findIndex(s => s[0] === editColor);
        visible = true;
    }
    function open() {
        kind = "label";
        colorOnly = false;
        editId = "";
        editColor = "";
        name.text = "";
        error = "";
        pick = Math.floor(Math.random() * swatches.length);
        visible = true;
        name.forceActiveFocus();
    }
    function edit(label) {
        colorOnly = false;
        editId = label.id;
        editColor = label.color || "";
        name.text = label.rawName;
        error = "";
        pick = swatches.findIndex(s => s[0] === editColor);
        visible = true;
        name.forceActiveFocus();
        name.selectAll();
    }
    function submit() {
        if (busy || name.text.trim() === "") return;
        created(name.text.trim(), pick >= 0 ? swatches[pick][0] : "", fg());
    }

    visible: false
    anchors.fill: parent
    color: FiliTheme.alpha("#000000", 0.35)
    z: 100
    MouseArea { anchors.fill: parent; onClicked: if (!dialog.busy) dialog.cancelled() }
    Keys.onEscapePressed: dialog.cancelled()
    Shortcut { sequences: ["Ctrl+Return", "Ctrl+Enter"]; enabled: dialog.visible; onActivated: dialog.submit() }

    Rectangle {
        anchors.centerIn: parent
        width: 340
        height: card.height + 2 * FiliTheme.margin
        radius: FiliTheme.radiusWindow
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: FiliTheme.border
        MouseArea { anchors.fill: parent } // clicks inside do not close
        Column {
            id: card
            x: FiliTheme.margin
            y: FiliTheme.margin
            width: parent.width - 2 * FiliTheme.margin
            spacing: FiliTheme.space3
            Text {
                text: dialog.colorOnly ? Facteur.tr("Label colour") : dialog.editId !== "" ? Facteur.tr("Edit label") : dialog.imap && !dialog.bridge ? Facteur.tr("New folder") : Facteur.tr("New label")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeTitle
                font.weight: FiliTheme.weightAccent
                color: FiliTheme.text
            }
            Field {
                id: name
                width: parent.width
                placeholderText: Facteur.tr("Label name")
                enabled: !dialog.busy && !dialog.colorOnly
                onAccepted: dialog.submit()
            }
            Row {
                visible: dialog.imap && dialog.bridge && dialog.editId === ""
                spacing: FiliTheme.space2
                TextButton { label: (dialog.kind === "label" ? "● " : "○ ") + Facteur.tr("Label"); onClicked: dialog.kind = "label" }
                TextButton { label: (dialog.kind === "folder" ? "● " : "○ ") + Facteur.tr("Folder"); onClicked: dialog.kind = "folder" }
            }
            Text {
                text: Facteur.tr("Colour")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: FiliTheme.muted
            }
            Grid {
                columns: 6
                spacing: FiliTheme.space2
                Repeater {
                    model: dialog.swatches
                    Rectangle {
                        required property var modelData
                        required property int index
                        width: 30; height: 30; radius: 15
                        activeFocusOnTab: true
                        onActiveFocusChanged: if (activeFocus) dialog.pick = index
                        Keys.onLeftPressed: dialog.pick = Math.max(0, index - 1)
                        Keys.onRightPressed: dialog.pick = Math.min(dialog.swatches.length - 1, index + 1)
                        Keys.onReturnPressed: dialog.submit()
                        Keys.onEnterPressed: dialog.submit()
                        FocusRing { gap: 3 }
                        color: modelData[0]
                        border.width: dialog.pick === index ? 3 : 0
                        border.color: FiliTheme.text
                        Text { anchors.centerIn: parent; visible: dialog.pick === index; text: "✓"; font.pixelSize: 14; font.bold: true; color: modelData[1] }
                        MouseArea { anchors.fill: parent; onClicked: dialog.pick = index }
                    }
                }
            }
            // Preview: the label as it will appear in the sidebar
            Row {
                spacing: FiliTheme.space2
                Rectangle { width: 10; height: 10; radius: 5; anchors.verticalCenter: parent.verticalCenter; color: dialog.bg() }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: name.text.trim() !== "" ? name.text.trim() : Facteur.tr("Label name")
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.size
                    color: name.text.trim() !== "" ? FiliTheme.text : FiliTheme.muted
                }
            }
            Text {
                visible: dialog.error !== ""
                width: parent.width
                text: dialog.error
                wrapMode: Text.WordWrap
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeList
                color: FiliTheme.danger
            }
            Row {
                anchors.right: parent.right
                spacing: FiliTheme.space2
                TextButton { label: Facteur.tr("Cancel"); onClicked: if (!dialog.busy) dialog.cancelled() }
                TextButton { label: dialog.busy ? "…" : dialog.editId !== "" ? Facteur.tr("Save") : Facteur.tr("Create"); primary: true; onClicked: dialog.submit() }
            }
        }
    }
}
