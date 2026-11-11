// Accounts and mailboxes: the account heading selects the account, the rows below are its mailboxes.
import QtQuick
import Fili.Mail

Rectangle {
    id: side
    property var accounts: []
    property string account: ""
    property string mailbox: "inbox"
    // Labels the user made ({name, rawName, unread}); each one is a mailbox "label:<rawName>"
    property var labels: []
    signal accountChosen(string id)
    signal mailboxChosen(string key)
    signal addAccount()
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

    // Sections folded by the user: "account:<id>" (the whole account) and "labels:<id>"
    property var folded: ({})
    function isFolded(key) { return folded[key] === true; }
    function toggle(key) {
        const next = Object.assign({}, folded);
        next[key] = !isFolded(key);
        folded = next;
    }
    signal addLabelRequested()
    // Right click: kind "account" (data: the account) or "label" (data: the label), at window position x, y
    signal contextRequested(string kind, var data, real x, real y)

    Flickable {
        anchors { fill: parent; bottomMargin: FiliTheme.statusHeight + FiliTheme.space2; topMargin: FiliTheme.space3 }
        contentHeight: column.height
        clip: true
        Column {
            id: column
            width: parent.width
            Repeater {
                model: side.accounts
                delegate: Column {
                    id: acct
                    width: column.width
                    readonly property var info: modelData
                    readonly property bool current: modelData.id === side.account
                    readonly property bool open: !side.isFolded("account:" + modelData.id)
                    // Account heading: room above it, a fold arrow, then the name
                    Rectangle {
                        width: parent.width
                        height: FiliTheme.sideRowHeight + FiliTheme.space4
                        color: head.containsMouse ? FiliTheme.surfaceHover : "transparent"
                        Text {
                            id: arrow
                            x: FiliTheme.margin / 2
                            anchors { bottom: parent.bottom; bottomMargin: (FiliTheme.sideRowHeight - height) / 2 }
                            text: acct.open ? "▾" : "▸"
                            font.pixelSize: FiliTheme.sizeSmall
                            color: FiliTheme.muted
                        }
                        Text {
                            anchors { left: arrow.right; leftMargin: FiliTheme.space2; right: parent.right; rightMargin: FiliTheme.space2; bottom: parent.bottom; bottomMargin: (FiliTheme.sideRowHeight - height) / 2 }
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
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) { const p = head.mapToItem(null, mouse.x, mouse.y); side.contextRequested("account", modelData, p.x, p.y); }
                                else if (mouse.x < arrow.x + arrow.width + FiliTheme.space3) side.toggle("account:" + modelData.id);
                                else { side.accountChosen(modelData.id); if (!acct.open) side.toggle("account:" + modelData.id); }
                            }
                        }
                    }
                    Repeater {
                        model: current && acct.open ? side.boxes : []
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
                    // Labels (Gmail): heading with fold arrow and a button to make one
                    Rectangle {
                        id: labelsHead
                        visible: current && acct.open && modelData.provider === "gmail"
                        readonly property bool open: !side.isFolded("labels:" + modelData.id)
                        width: parent.width
                        height: visible ? FiliTheme.sideRowHeight + FiliTheme.space4 : 0
                        color: lhArea.containsMouse ? FiliTheme.alpha(FiliTheme.surfaceHover, 0.5) : "transparent"
                        Text {
                            id: lArrow
                            x: FiliTheme.margin / 2 + FiliTheme.space2
                            anchors { bottom: parent.bottom; bottomMargin: (FiliTheme.sideRowHeight - height) / 2 }
                            text: labelsHead.open ? "▾" : "▸"
                            font.pixelSize: FiliTheme.sizeSmall
                            color: FiliTheme.muted
                        }
                        Text {
                            anchors { left: lArrow.right; leftMargin: FiliTheme.space2; bottom: parent.bottom; bottomMargin: (FiliTheme.sideRowHeight - height) / 2 }
                            text: Facteur.tr("Labels")
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.sizeSmall
                            font.weight: FiliTheme.weightAccent
                            color: FiliTheme.muted
                        }
                        MouseArea { id: lhArea; anchors.fill: parent; hoverEnabled: true; onClicked: side.toggle("labels:" + modelData.id) }
                        IconButton {
                            anchors { right: parent.right; rightMargin: FiliTheme.space2; bottom: parent.bottom; bottomMargin: (FiliTheme.sideRowHeight - height) / 2 }
                            glyph: "+"
                            tip: Facteur.tr("New label")
                            onClicked: side.addLabelRequested()
                        }
                    }
                    Repeater {
                        model: current && acct.open && labelsHead.open && acct.info.provider === "gmail" ? side.labels : []
                        delegate: Rectangle {
                            width: column.width
                            height: FiliTheme.sideRowHeight
                            readonly property string key: "label:" + modelData.rawName
                            readonly property bool selected: side.mailbox === key
                            color: selected ? FiliTheme.surfaceHover : lrow.containsMouse ? FiliTheme.alpha(FiliTheme.surfaceHover, 0.5) : "transparent"
                            Rectangle { // colour of the label: a dot (grey ring when the label has none)
                                x: FiliTheme.margin / 2 + FiliTheme.space2
                                anchors.verticalCenter: parent.verticalCenter
                                width: 10; height: 10; radius: 5
                                color: modelData.color || "transparent"
                                border.width: modelData.color ? 0 : 1
                                border.color: FiliTheme.muted
                            }
                            Text {
                                anchors { left: parent.left; right: parent.right; leftMargin: FiliTheme.margin / 2 + FiliTheme.space2 + 16; rightMargin: FiliTheme.space6; verticalCenter: parent.verticalCenter }
                                text: modelData.rawName
                                elide: Text.ElideRight
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.size
                                font.weight: selected ? FiliTheme.weightAccent : Font.Normal
                                color: FiliTheme.text
                            }
                            Text {
                                visible: modelData.unread > 0
                                anchors { right: parent.right; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
                                text: "" + modelData.unread
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.sizeSmall
                                color: FiliTheme.muted
                            }
                            MouseArea {
                                id: lrow
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) { const p = lrow.mapToItem(null, mouse.x, mouse.y); side.contextRequested("label", modelData, p.x, p.y); }
                                    else side.mailboxChosen(key);
                                }
                            }
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
}
