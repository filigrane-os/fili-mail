// New message, reply or forward: a card at the bottom right of the window (the message list stays visible behind it),
// as mail clients do. Header with minimise, expand and close; From, To (with Cc / Bcc shown on demand), Subject,
// plain-text body, attached files, and a footer with discard, attach and Send.
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
    property bool minimized: false
    property bool expanded: false
    property bool showCc: false
    property bool showBcc: false
    function addFiles(urls) {
        const next = files.slice();
        for (const u of urls) {
            const path = decodeURIComponent(u.toString().replace(/^file:\/\//, ""));
            if (!next.some(f => f.path === path))
                next.push({ path: path, name: path.split("/").pop() });
        }
        files = next;
    }

    signal submitted(var fields)
    signal cancelled()

    // Fill the form and put the cursor where typing starts
    function open(draft) {
        to.text = draft.to || "";
        cc.text = draft.cc || "";
        bcc.text = draft.bcc || "";
        showCc = cc.text !== "";
        showBcc = bcc.text !== "";
        subject.text = draft.subject || "";
        body.text = draft.body || "";
        inReplyTo = draft.inReplyTo || "";
        references = draft.references || "";
        files = [];
        error = "";
        minimized = false;
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

    width: Math.min(expanded ? parent.width - 2 * FiliTheme.margin : 640, parent.width - 2 * FiliTheme.margin)
    height: minimized ? head.height : Math.min(expanded ? parent.height - 2 * FiliTheme.margin : 580, parent.height - 2 * FiliTheme.margin)
    radius: FiliTheme.radiusWindow
    color: FiliTheme.surface
    border.width: FiliTheme.borderWidth
    border.color: FiliTheme.border
    clip: true

    Keys.onEscapePressed: compose.cancelled()
    Shortcut { sequences: ["Ctrl+Return", "Ctrl+Enter"]; enabled: compose.visible; onActivated: compose.submit() }

    // A field of the card: no frame, a line under it
    component Line: TextField {
        id: f
        width: parent.width
        height: 40
        leftPadding: 0
        rightPadding: 0
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        color: FiliTheme.text
        placeholderTextColor: FiliTheme.muted
        selectionColor: FiliTheme.surfaceActive
        selectedTextColor: FiliTheme.text
        enabled: !compose.busy
        background: Rectangle {
            color: "transparent"
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: f.activeFocus ? 2 : FiliTheme.borderWidth; color: f.activeFocus ? FiliTheme.accentColor : FiliTheme.border }
        }
    }

    // Header: title (the subject once there is one), minimise, expand, close
    Rectangle {
        id: head
        width: parent.width
        height: 44
        color: FiliTheme.backgroundDeep
        Text {
            anchors { left: parent.left; leftMargin: FiliTheme.margin; right: controls.left; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
            text: subject.text.trim() !== "" ? subject.text : Facteur.tr("New message")
            elide: Text.ElideRight
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
            font.weight: FiliTheme.weightAccent
            color: FiliTheme.text
        }
        MouseArea { anchors.fill: parent; onDoubleClicked: compose.minimized = !compose.minimized }
        Row {
            id: controls
            anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
            spacing: 2
            IconButton { name: compose.minimized ? "maximize" : "minus"; tip: compose.minimized ? Facteur.tr("Restore") : Facteur.tr("Minimise"); onClicked: compose.minimized = !compose.minimized }
            IconButton { name: compose.expanded ? "minimize-2" : "maximize"; tip: compose.expanded ? Facteur.tr("Reduce") : Facteur.tr("Expand"); onClicked: { compose.expanded = !compose.expanded; compose.minimized = false } }
            IconButton { name: "x"; tip: Facteur.tr("Discard"); onClicked: if (!compose.busy) compose.cancelled() }
        }
    }

    Column {
        id: form
        visible: !compose.minimized
        anchors { left: parent.left; right: parent.right; top: head.bottom; leftMargin: FiliTheme.margin; rightMargin: FiliTheme.margin; topMargin: FiliTheme.space2 }
        spacing: 0
        Item {
            width: parent.width
            height: 40
            Text { id: fromLabel; anchors.verticalCenter: parent.verticalCenter; text: Facteur.tr("From"); font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.muted }
            Text { anchors { left: fromLabel.right; leftMargin: FiliTheme.space3; right: parent.right; verticalCenter: parent.verticalCenter } text: compose.from; elide: Text.ElideRight; font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.text }
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: FiliTheme.borderWidth; color: FiliTheme.border }
        }
        Item {
            width: parent.width
            height: 40
            Line { id: to; placeholderText: Facteur.tr("To"); anchors { left: parent.left; right: ccToggles.left; rightMargin: FiliTheme.space2 } width: undefined; KeyNavigation.tab: compose.showCc ? cc : compose.showBcc ? bcc : subject }
            Row {
                id: ccToggles
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: FiliTheme.space3
                Text { text: "CC"; visible: !compose.showCc; font.family: FiliTheme.font; font.pixelSize: FiliTheme.sizeList; font.weight: FiliTheme.weightAccent; color: FiliTheme.textSecondary; MouseArea { anchors { fill: parent; margins: -4 } onClicked: compose.showCc = true } }
                Text { text: "BCC"; visible: !compose.showBcc; font.family: FiliTheme.font; font.pixelSize: FiliTheme.sizeList; font.weight: FiliTheme.weightAccent; color: FiliTheme.textSecondary; MouseArea { anchors { fill: parent; margins: -4 } onClicked: compose.showBcc = true } }
            }
        }
        Line { id: cc; visible: compose.showCc; placeholderText: Facteur.tr("Cc"); KeyNavigation.tab: compose.showBcc ? bcc : subject }
        Line { id: bcc; visible: compose.showBcc; placeholderText: Facteur.tr("Bcc"); KeyNavigation.tab: subject }
        Line { id: subject; placeholderText: Facteur.tr("Subject"); KeyNavigation.tab: body }
    }

    // Body
    ScrollView {
        id: bodyScroll
        visible: !compose.minimized
        anchors { left: parent.left; right: parent.right; top: form.bottom; bottom: chips.visible ? chips.top : footer.top; leftMargin: FiliTheme.margin; rightMargin: FiliTheme.margin; topMargin: FiliTheme.space2; bottomMargin: FiliTheme.space2 }
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

    FileDialog {
        id: picker
        title: Facteur.tr("Attach files")
        fileMode: FileDialog.OpenFiles
        onAccepted: compose.addFiles(selectedFiles)
    }
    Shortcut { sequence: "Ctrl+Shift+U"; enabled: compose.visible && !compose.minimized; onActivated: picker.open() }

    // Attached files, one chip each (click removes it)
    Flow {
        id: chips
        visible: !compose.minimized && compose.files.length > 0
        anchors { left: parent.left; right: parent.right; bottom: footer.top; leftMargin: FiliTheme.margin; rightMargin: FiliTheme.margin; bottomMargin: FiliTheme.space2 }
        spacing: FiliTheme.space2
        Repeater {
            model: compose.files
            Rectangle {
                required property var modelData
                width: Math.min(chipLabel.implicitWidth + 2 * FiliTheme.space3 + 14 + FiliTheme.space2, chips.width)
                height: 26
                radius: FiliTheme.radiusControl
                color: chipArea.containsMouse ? FiliTheme.surfaceHover : FiliTheme.backgroundDeep
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

    // Footer: discard and attach on the left, the state and Send on the right
    Rectangle {
        id: footer
        visible: !compose.minimized
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 52
        color: FiliTheme.surface
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: FiliTheme.borderWidth; color: FiliTheme.border }
        Row {
            anchors { left: parent.left; leftMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
            spacing: 2
            IconButton { name: "trash"; tip: Facteur.tr("Discard"); onClicked: if (!compose.busy) compose.cancelled() }
            IconButton { name: "paperclip"; tip: Facteur.tr("Attach files"); onClicked: if (!compose.busy) picker.open() }
        }
        Text {
            anchors { right: sendButton.left; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
            width: Math.max(0, parent.width - 2 * 80 - sendButton.width - FiliTheme.space4)
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            text: compose.error !== "" ? compose.error : compose.files.length > 0 ? Facteur.tr("%1 attached").replace("%1", compose.files.length) : ""
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeList
            color: compose.error !== "" ? FiliTheme.danger : FiliTheme.textSecondary
        }
        Rectangle {
            id: sendButton
            anchors { right: parent.right; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
            width: sendText.implicitWidth + 2 * FiliTheme.space5
            height: 32
            radius: FiliTheme.radiusControl
            color: sendArea.pressed ? Qt.darker(FiliTheme.accentColor, 1.2) : sendArea.containsMouse ? FiliTheme.accentBright : FiliTheme.accentColor
            opacity: compose.busy ? 0.6 : 1
            Text { id: sendText; anchors.centerIn: parent; text: compose.busy ? Facteur.tr("Sending…") : Facteur.tr("Send"); font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; font.weight: FiliTheme.weightAccent; color: FiliTheme.accentColor.hslLightness > 0.55 ? "#1a1a1a" : "#ffffff" }
            MouseArea { id: sendArea; anchors.fill: parent; hoverEnabled: true; onClicked: compose.submit() }
        }
    }
}
