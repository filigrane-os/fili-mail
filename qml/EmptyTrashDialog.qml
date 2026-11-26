// Dialog of "Empty Trash": asks first (the messages are deleted for good), shows the work in progress with an animated bar,
// then the result or the error. Centered over a dimmed window, so it can never hide behind the footer.
import QtQuick
import Fili.UI
import Fili.Mail

Rectangle {
    id: dialog
    // "ask" | "work" | "done" | "error" ("" = closed)
    property string state_: ""
    property string account: ""
    property string detail: ""
    // Where it stands while it works ("500 deleted, 700 left")
    property string progress: ""
    // Hidden while it works so the mail stays readable; the footer keeps the progress and the dialog comes back with the result
    property bool dismissed: false
    signal confirmed()

    z: 220
    visible: state_ !== "" && !dismissed
    color: FiliTheme.alpha(FiliTheme.backgroundDeep, 0.7)
    focus: visible

    function ask(acct) { account = acct; detail = ""; dismissed = false; state_ = "ask" }
    function working() { progress = ""; dismissed = false; state_ = "work" }
    function finish(text) { detail = text; dismissed = false; state_ = "done" }
    function fail(text) { detail = text; dismissed = false; state_ = "error" }
    function close() { if (state_ === "work") dismissed = true; else state_ = "" }

    onVisibleChanged: if (visible) forceActiveFocus()
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Escape) { close(); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            if (state_ === "ask") dialog.confirmed(); else close();
            e.accepted = true;
        }
    }
    // Clicking outside closes it (while it works, it only hides)
    MouseArea { anchors.fill: parent; onClicked: dialog.close() }

    Rectangle {
        anchors.centerIn: parent
        width: 400
        height: column.implicitHeight + 2 * FiliTheme.space5
        radius: FiliTheme.radiusWindow
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: FiliTheme.border
        MouseArea { anchors.fill: parent }
        Column {
            id: column
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: FiliTheme.space5 }
            spacing: FiliTheme.space3
            Text {
                width: parent.width
                text: dialog.state_ === "ask" ? Facteur.tr("Empty Trash")
                    : dialog.state_ === "work" ? Facteur.tr("Emptying the trash…")
                    : dialog.state_ === "done" ? Facteur.tr("Trash emptied")
                    : Facteur.tr("The trash could not be emptied")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeTitle
                font.weight: FiliTheme.weightAccent
                color: dialog.state_ === "error" ? FiliTheme.danger : FiliTheme.text
                wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width
                text: dialog.state_ === "ask"
                    ? Facteur.tr("Delete everything in the trash of %1 for good? This cannot be undone.").replace("%1", dialog.account.replace(/^[a-z]+:/, ""))
                    : dialog.state_ === "work" ? (dialog.progress !== "" ? dialog.progress + "\n" : "") + Facteur.tr("Deleting the messages on the server. You can hide this window and keep reading: it comes back when it is done.")
                    : dialog.detail
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                color: FiliTheme.textSecondary
                wrapMode: Text.WordWrap
            }
            // Progress: a bar sliding along its width while the server works
            Rectangle {
                visible: dialog.state_ === "work"
                width: parent.width
                height: 4
                radius: 2
                color: FiliTheme.surfaceActive
                clip: true
                Rectangle {
                    id: slider
                    width: parent.width * 0.3
                    height: parent.height
                    radius: 2
                    color: FiliTheme.accentColor
                    NumberAnimation on x { running: dialog.state_ === "work"; from: -slider.width; to: slider.parent.width; duration: 1100; loops: Animation.Infinite }
                }
            }
            Row {
                anchors.right: parent.right
                spacing: FiliTheme.space2
                FiliButton { visible: dialog.state_ === "ask"; label: Facteur.tr("Cancel"); onClicked: dialog.close() }
                FiliButton {
                    label: dialog.state_ === "ask" ? Facteur.tr("Empty Trash") : dialog.state_ === "work" ? Facteur.tr("Hide") : Facteur.tr("OK")
                    primary: true
                    onClicked: if (dialog.state_ === "ask") dialog.confirmed(); else dialog.close()
                }
            }
        }
    }
}
