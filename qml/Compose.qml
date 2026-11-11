// New message, reply or forward: address rows, subject, plain-text body. Covers the reader pane.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import Fili.Mail

Rectangle {
    id: compose
    property bool busy: false
    property string error: ""
    // Sender shown on the first line (the account)
    property string from: ""
    // Threading of a reply (Message-ID answered, References chain); empty otherwise
    property string inReplyTo: ""
    property string references: ""
    // Files to attach: {path, name}
    property var files: []
    function addFiles(urls) {
        const next = files.slice();
        for (const u of urls) {
            const path = decodeURIComponent(u.toString().replace(/^file:\/\//, ""));
            if (!next.some(f => f.path === path))
                next.push({ path: path, name: path.split("/").pop() });
        }
        files = next;
    }
    color: FiliTheme.backgroundDeep

    signal submitted(var fields)
    signal cancelled()

    // Fill the form and put the cursor where typing starts
    function open(draft) {
        to.text = draft.to || "";
        cc.text = draft.cc || "";
        bcc.text = draft.bcc || "";
        subject.text = draft.subject || "";
        body.text = draft.body || "";
        inReplyTo = draft.inReplyTo || "";
        references = draft.references || "";
        files = [];
        error = "";
        if (to.text === "") to.forceActiveFocus(); else { body.forceActiveFocus(); body.cursorPosition = 0 }
    }
    function submit() {
        if (busy) return;
        if (to.text.trim() === "" && cc.text.trim() === "" && bcc.text.trim() === "") {
            error = Facteur.tr("Add at least one recipient.");
            return;
        }
        submitted({ to: to.text, cc: cc.text, bcc: bcc.text, subject: subject.text, body: body.text, inReplyTo: inReplyTo, references: references, attachments: files.map(f => ({ path: f.path, name: f.name, size: 0 })) });
    }

    Keys.onEscapePressed: compose.cancelled()
    Shortcut { sequences: ["Ctrl+Return", "Ctrl+Enter"]; enabled: compose.visible; onActivated: compose.submit() }

    Column {
        id: form
        x: FiliTheme.margin
        y: FiliTheme.space3
        width: parent.width - 2 * FiliTheme.margin
        spacing: FiliTheme.space2
        Text {
            width: parent.width
            text: Facteur.tr("From %1").replace("%1", compose.from)
            elide: Text.ElideRight
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeList
            color: FiliTheme.textSecondary
        }
        Field { id: to; width: parent.width; placeholderText: Facteur.tr("To"); KeyNavigation.tab: cc; enabled: !compose.busy }
        Field { id: cc; width: parent.width; placeholderText: Facteur.tr("Cc"); KeyNavigation.tab: bcc; enabled: !compose.busy }
        Field { id: bcc; width: parent.width; placeholderText: Facteur.tr("Bcc"); KeyNavigation.tab: subject; enabled: !compose.busy }
        Field { id: subject; width: parent.width; placeholderText: Facteur.tr("Subject"); KeyNavigation.tab: body; enabled: !compose.busy }
    }
    FileDialog {
        id: picker
        title: Facteur.tr("Attach files")
        fileMode: FileDialog.OpenFiles
        onAccepted: compose.addFiles(selectedFiles)
    }
    Shortcut { sequence: "Ctrl+Shift+A"; enabled: compose.visible; onActivated: picker.open() }
    // Attached files, one chip each (click removes it)
    Flow {
        id: chips
        visible: compose.files.length > 0
        anchors { left: parent.left; right: parent.right; bottom: bar.top; leftMargin: FiliTheme.margin; rightMargin: FiliTheme.margin; bottomMargin: FiliTheme.space2 }
        spacing: FiliTheme.space2
        Repeater {
            model: compose.files
            Rectangle {
                required property var modelData
                width: Math.min(chipLabel.implicitWidth + 2 * FiliTheme.space3 + 14 + FiliTheme.space2, chips.width)
                height: 26
                radius: FiliTheme.radiusControl
                color: chipArea.containsMouse ? FiliTheme.surfaceHover : FiliTheme.surface
                border.width: FiliTheme.borderWidth
                border.color: FiliTheme.border
                Text {
                    id: chipLabel
                    x: FiliTheme.space3
                    width: parent.width - 2 * FiliTheme.space3 - 14 - FiliTheme.space2
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    elide: Text.ElideMiddle
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeList
                    color: FiliTheme.text
                }
                Text { anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter } text: "×"; font.pixelSize: FiliTheme.size; color: FiliTheme.textSecondary }
                ToolTip.visible: chipArea.containsMouse
                ToolTip.text: Facteur.tr("Remove attachment")
                MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; onClicked: compose.files = compose.files.filter(f => f.path !== modelData.path) }
            }
        }
    }
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: form.bottom; bottom: chips.visible ? chips.top : bar.top; margins: FiliTheme.margin }
        anchors.topMargin: FiliTheme.space3
        anchors.bottomMargin: FiliTheme.space2
        radius: FiliTheme.radiusControl
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: body.activeFocus ? FiliTheme.accentColor : FiliTheme.border
        ScrollView {
            anchors { fill: parent; margins: FiliTheme.space2 }
            clip: true
            TextArea {
                id: body
                enabled: !compose.busy
                wrapMode: TextEdit.Wrap
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                color: FiliTheme.text
                selectionColor: FiliTheme.surfaceActive
                selectedTextColor: FiliTheme.text
                background: null
                padding: 0
                KeyNavigation.priority: KeyNavigation.BeforeItem
                KeyNavigation.tab: to
            }
        }
    }
    Row {
        id: bar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: FiliTheme.margin }
        anchors.bottomMargin: FiliTheme.space2
        height: 28
        spacing: FiliTheme.space2
        TextButton { label: compose.busy ? Facteur.tr("Sending…") : Facteur.tr("Send"); primary: true; onClicked: compose.submit() }
        TextButton { label: Facteur.tr("Attach…"); onClicked: if (!compose.busy) picker.open() }
        TextButton { label: Facteur.tr("Discard"); onClicked: if (!compose.busy) compose.cancelled() }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: compose.error
            elide: Text.ElideRight
            width: bar.width - 200
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeList
            color: FiliTheme.danger
        }
    }
}
