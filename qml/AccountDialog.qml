// Modal "Edit account": the name shown in the sidebar and, for an IMAP account, its servers, user name and password
// (left empty, the password stays as it is).
import QtQuick
import Fili.Mail

Rectangle {
    id: dialog
    property bool busy: false
    property string error: ""
    property string accountId: ""
    property bool imap: false
    signal saved(string id, var patch)
    signal cancelled()

    function edit(details) {
        accountId = details.id;
        imap = details.provider === "imap";
        email.text = details.email || "";
        label.text = details.label || "";
        const s = details.imap || {};
        imapHost.text = s.imapHost || "";
        imapPort.text = s.imapPort ? "" + s.imapPort : "";
        smtpHost.text = s.smtpHost || "";
        smtpPort.text = s.smtpPort ? "" + s.smtpPort : "";
        username.text = s.username || "";
        password.text = "";
        error = "";
        visible = true;
        label.forceActiveFocus();
    }
    function submit() {
        if (busy) return;
        const patch = { label: label.text.trim() };
        if (imap) {
            patch.imapHost = imapHost.text;
            patch.imapPort = parseInt(imapPort.text) || 0;
            patch.smtpHost = smtpHost.text;
            patch.smtpPort = parseInt(smtpPort.text) || 0;
            patch.username = username.text;
            patch.password = password.text;
        }
        saved(accountId, patch);
    }

    visible: false
    anchors.fill: parent
    color: FiliTheme.alpha("#000000", 0.35)
    z: 100
    MouseArea { anchors.fill: parent; onClicked: if (!dialog.busy) dialog.cancelled() }
    Keys.onEscapePressed: dialog.cancelled()

    Rectangle {
        anchors.centerIn: parent
        width: 380
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
            spacing: FiliTheme.space2
            Text {
                text: Facteur.tr("Edit account")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeTitle
                font.weight: FiliTheme.weightAccent
                color: FiliTheme.text
            }
            Field { id: email; width: parent.width; readOnly: true; enabled: false; placeholderText: Facteur.tr("Address") }
            Field { id: label; width: parent.width; placeholderText: Facteur.tr("Name shown in the sidebar"); enabled: !dialog.busy; onAccepted: dialog.submit() }
            Column {
                visible: dialog.imap
                width: parent.width
                spacing: FiliTheme.space2
                Row {
                    width: parent.width
                    spacing: FiliTheme.space2
                    Field { id: imapHost; width: parent.width - 80 - FiliTheme.space2; placeholderText: Facteur.tr("IMAP server"); enabled: !dialog.busy }
                    Field { id: imapPort; width: 80; placeholderText: Facteur.tr("Port"); enabled: !dialog.busy }
                }
                Row {
                    width: parent.width
                    spacing: FiliTheme.space2
                    Field { id: smtpHost; width: parent.width - 80 - FiliTheme.space2; placeholderText: Facteur.tr("SMTP server"); enabled: !dialog.busy }
                    Field { id: smtpPort; width: 80; placeholderText: Facteur.tr("Port"); enabled: !dialog.busy }
                }
                Field { id: username; width: parent.width; placeholderText: Facteur.tr("User name"); enabled: !dialog.busy }
                Field { id: password; width: parent.width; secret: true; placeholderText: Facteur.tr("New password (empty: keep the current one)"); enabled: !dialog.busy; onAccepted: dialog.submit() }
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
                TextButton { label: dialog.busy ? "…" : Facteur.tr("Save"); primary: true; onClicked: dialog.submit() }
            }
        }
    }
}
