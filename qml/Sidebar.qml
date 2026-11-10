// Accounts and mailboxes: the account heading selects the account, the rows below are its mailboxes.
import QtQuick
import Fili.Mail

Rectangle {
    id: side
    property var accounts: []
    property string account: ""
    property string mailbox: "inbox"
    signal accountChosen(string id)
    signal mailboxChosen(string key)
    signal addAccount()
    signal compose()
    signal removeRequested(string id)

    color: FiliTheme.backgroundDeep

    readonly property var boxes: [
        { key: "inbox", label: Facteur.tr("Inbox") },
        { key: "unread", label: Facteur.tr("Unread") },
        { key: "starred", label: Facteur.tr("Starred") },
        { key: "sent", label: Facteur.tr("Sent") },
        { key: "drafts", label: Facteur.tr("Drafts") },
        { key: "archive", label: Facteur.tr("Archive") },
        { key: "spam", label: Facteur.tr("Spam") },
        { key: "trash", label: Facteur.tr("Trash") }
    ]

    Flickable {
        anchors { fill: parent; bottomMargin: FiliTheme.statusHeight + FiliTheme.space2; topMargin: FiliTheme.statusHeight + FiliTheme.space3 }
        contentHeight: column.height
        clip: true
        Column {
            id: column
            width: parent.width
            Repeater {
                model: side.accounts
                delegate: Column {
                    width: column.width
                    readonly property bool current: modelData.id === side.account
                    Rectangle {
                        width: parent.width
                        height: FiliTheme.sideRowHeight
                        color: head.containsMouse ? FiliTheme.surfaceHover : "transparent"
                        Text {
                            anchors { left: parent.left; right: parent.right; leftMargin: FiliTheme.margin / 2; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                            text: (modelData.label !== "" ? modelData.label : modelData.email) + (modelData.provider === "imap" ? "  ·  IMAP" : modelData.provider === "gmail" ? "  ·  Gmail" : "")
                            elide: Text.ElideRight
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.sizeSmall
                            font.weight: FiliTheme.weightAccent
                            color: current ? FiliTheme.text : FiliTheme.muted
                        }
                        MouseArea {
                            id: head
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => mouse.button === Qt.RightButton ? side.removeRequested(modelData.id) : side.accountChosen(modelData.id)
                        }
                    }
                    Repeater {
                        model: current ? side.boxes : []
                        delegate: Rectangle {
                            width: column.width
                            height: FiliTheme.sideRowHeight
                            readonly property bool selected: side.mailbox === modelData.key
                            color: selected ? FiliTheme.surfaceHover : row.containsMouse ? FiliTheme.alpha(FiliTheme.surfaceHover, 0.5) : "transparent"
                            Text {
                                anchors { left: parent.left; right: parent.right; leftMargin: FiliTheme.margin / 2 + FiliTheme.space2; verticalCenter: parent.verticalCenter }
                                text: modelData.label
                                elide: Text.ElideRight
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.size
                                font.weight: selected ? FiliTheme.weightAccent : Font.Normal
                                color: FiliTheme.text
                            }
                            MouseArea { id: row; anchors.fill: parent; hoverEnabled: true; onClicked: side.mailboxChosen(modelData.key) }
                        }
                    }
                }
            }
        }
    }
    TextButton {
        anchors { left: parent.left; bottom: parent.bottom; leftMargin: FiliTheme.space3; bottomMargin: FiliTheme.space2 }
        label: "+ " + Facteur.tr("Add account")
        onClicked: side.addAccount()
    }
    TextButton {
        anchors { left: parent.left; top: parent.top; leftMargin: FiliTheme.space3; topMargin: FiliTheme.space2 }
        label: Facteur.tr("New message")
        primary: true
        onClicked: side.compose()
    }
}
