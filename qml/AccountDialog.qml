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
    // Category tabs of an account without categories: {category: folder id}; the folder is picked in a menu (Main)
    property var catMap: ({})
    property bool mapped: false
    property var folderNames: ({})
    signal pickRequested(string category, real x, real y)
    signal saved(string id, var patch)
    signal cancelled()

    function edit(details) {
        accountId = details.id;
        imap = details.provider === "imap";
        mapped = details.provider === "imap" || details.provider === "outlook";
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
    Shortcut { sequences: ["Ctrl+Return", "Ctrl+Enter"]; enabled: dialog.visible; onActivated: dialog.submit() }

    // One form row: a label on the left, the control on the right
    component FormRow: Item {
        id: fr
        property string title
        default property alias content: slot.data
        width: parent ? parent.width : 0
        height: 28
        Text {
            width: 120
            anchors.verticalCenter: parent.verticalCenter
            text: fr.title
            elide: Text.ElideRight
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeList
            color: FiliTheme.textSecondary
        }
        Item { id: slot; x: 128; width: parent.width - 128; height: parent.height }
    }
    component SectionTitle: Text {
        width: parent ? parent.width : 0
        topPadding: FiliTheme.space2
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.sizeSmall
        font.weight: FiliTheme.weightAccent
        color: FiliTheme.muted
    }

    Rectangle {
        anchors.centerIn: parent
        width: 460
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
            SectionTitle { text: Facteur.tr("Account") }
            FormRow { title: Facteur.tr("Address"); Field { id: email; anchors.fill: parent; readOnly: true; enabled: false } }
            FormRow { title: Facteur.tr("Name"); Field { id: label; anchors.fill: parent; placeholderText: Facteur.tr("Name shown in the sidebar"); enabled: !dialog.busy; onAccepted: dialog.submit() } }
            Column {
                visible: dialog.imap
                width: parent.width
                spacing: FiliTheme.space2
                SectionTitle { text: Facteur.tr("Server") }
                FormRow {
                    title: Facteur.tr("Incoming (IMAP)")
                    Field { id: imapHost; anchors { left: parent.left; right: imapPort.left; rightMargin: FiliTheme.space2 } placeholderText: Facteur.tr("IMAP server"); enabled: !dialog.busy }
                    Field { id: imapPort; anchors.right: parent.right; width: 72; placeholderText: Facteur.tr("Port"); enabled: !dialog.busy }
                }
                FormRow {
                    title: Facteur.tr("Outgoing (SMTP)")
                    Field { id: smtpHost; anchors { left: parent.left; right: smtpPort.left; rightMargin: FiliTheme.space2 } placeholderText: Facteur.tr("SMTP server"); enabled: !dialog.busy }
                    Field { id: smtpPort; anchors.right: parent.right; width: 72; placeholderText: Facteur.tr("Port"); enabled: !dialog.busy }
                }
                FormRow { title: Facteur.tr("User name"); Field { id: username; anchors.fill: parent; enabled: !dialog.busy } }
                FormRow { title: Facteur.tr("Password"); Field { id: password; anchors.fill: parent; secret: true; placeholderText: Facteur.tr("Empty: keep the current one"); enabled: !dialog.busy; onAccepted: dialog.submit() } }
            }
            Column {
                visible: dialog.mapped
                width: parent.width
                spacing: FiliTheme.space2
                SectionTitle { text: Facteur.tr("Category tabs") }
                Text {
                    width: parent.width
                    text: Facteur.tr("Every account has the same tabs. Choose the folder of this account each tab shows; Primary is the inbox.")
                    wrapMode: Text.WordWrap
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeList
                    color: FiliTheme.muted
                }
                Repeater {
                    model: [["promotions", Facteur.tr("Promotions"), "tag"], ["social", Facteur.tr("Social"), "users"], ["updates", Facteur.tr("Updates"), "bell"], ["forums", Facteur.tr("Forums"), "chat"]]
                    FormRow {
                        id: catRow
                        required property var modelData
                        title: modelData[1]
                        Rectangle {
                            id: pick
                            anchors.fill: parent
                            radius: FiliTheme.radiusControl
                            color: pickArea.containsMouse ? FiliTheme.surfaceHover : FiliTheme.surface
                            border.width: FiliTheme.borderWidth
                            border.color: FiliTheme.border
                            readonly property string folder: dialog.catMap[catRow.modelData[0]] || ""
                            Text {
                                anchors { left: parent.left; leftMargin: FiliTheme.space2; right: chev.left; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                                text: pick.folder !== "" ? (dialog.folderNames[pick.folder] || pick.folder) : Facteur.tr("None")
                                elide: Text.ElideRight
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.size
                                color: pick.folder !== "" ? FiliTheme.text : FiliTheme.muted
                            }
                            Icon { id: chev; anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter } name: "chevron-down"; size: 14; color: FiliTheme.textSecondary }
                            MouseArea {
                                id: pickArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: { const p = pick.mapToItem(null, 0, pick.height); dialog.pickRequested(catRow.modelData[0], p.x, p.y); }
                            }
                        }
                    }
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
                TextButton { label: dialog.busy ? "…" : Facteur.tr("Save"); primary: true; onClicked: dialog.submit() }
            }
        }
    }
}
