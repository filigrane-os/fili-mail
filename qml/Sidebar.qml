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
    // Heading of that section: "Labels" (Gmail, Proton) or "Folders" (plain IMAP)
    property string sectionTitle: Facteur.tr("Labels")
    signal accountChosen(string id)
    signal mailboxChosen(string key)
    // A box of an account that is not the current one
    signal boxOfAccountChosen(string id, string key)
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
    // Icon of an account's service: Gmail, Proton (by its domain) or a plain IMAP server
    function serviceIcon(a) {
        if (/@(proton\.me|protonmail\.com|pm\.me)$/i.test(a.email || "")) return "shield";
        return a.provider === "gmail" ? "mail" : "server";
    }
    // Right click: kind "account" (data: the account) or "label" (data: the label), at window position x, y
    signal contextRequested(string kind, var data, real x, real y)

    // Keyboard: the row under the cursor ("a:<account>", "b:<account>:<box>", "s:<account>", "l:<account>:<key>");
    // Up/Down (J/K) move, Enter opens, Left/Right fold, Menu or Shift+F10 the context menu, + a new label
    property string cursor: ""
    property point cursorPos: Qt.point(60, 60)
    activeFocusOnTab: true
    readonly property var rows: {
        const out = [];
        for (const a of accounts) {
            out.push({ key: "a:" + a.id, kind: "account", account: a });
            if (isFolded("account:" + a.id)) continue;
            for (const b of boxes) out.push({ key: "b:" + a.id + ":" + b.key, kind: "box", account: a, box: b.key });
            if (a.id !== account) continue;
            out.push({ key: "s:" + a.id, kind: "section", account: a });
            if (isFolded("labels:" + a.id)) continue;
            for (const l of labels) {
                const k = l.folder ? "folder:" + l.id : "label:" + l.rawName;
                out.push({ key: "l:" + a.id + ":" + k, kind: "label", account: a, label: l, box: k });
            }
        }
        return out;
    }
    function rowIndex() { return rows.findIndex(r => r.key === cursor); }
    function currentKey() {
        const r = rows.find(r => (r.kind === "box" || r.kind === "label") && r.account.id === account && r.box === mailbox);
        return r ? r.key : rows.length > 0 ? rows[0].key : "";
    }
    function activate(r) {
        if (r.kind === "account") {
            accountChosen(r.account.id);
            if (isFolded("account:" + r.account.id)) toggle("account:" + r.account.id);
        } else if (r.kind === "box") {
            if (r.account.id === account) mailboxChosen(r.box); else boxOfAccountChosen(r.account.id, r.box);
        } else if (r.kind === "section") {
            toggle("labels:" + r.account.id);
        } else {
            mailboxChosen(r.box);
        }
    }
    // Keep the row under the cursor in view and remember where it is (for the context menu)
    function reveal(item) {
        const p = item.mapToItem(sideFlick.contentItem, 0, 0);
        if (p.y < sideFlick.contentY) sideFlick.contentY = p.y;
        else if (p.y + item.height > sideFlick.contentY + sideFlick.height) sideFlick.contentY = p.y + item.height - sideFlick.height;
        cursorPos = item.mapToItem(null, 60, item.height);
    }
    onActiveFocusChanged: if (activeFocus && rowIndex() < 0) cursor = currentKey()
    Keys.onPressed: event => {
        Facteur.keyNav = true;
        const i = rowIndex();
        const r = i >= 0 ? rows[i] : null;
        if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
            cursor = rows[Math.min(rows.length - 1, i + 1)].key;
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
            cursor = rows[Math.max(0, i - 1)].key;
        } else if (event.key === Qt.Key_Home) {
            cursor = rows[0].key;
        } else if (event.key === Qt.Key_End) {
            cursor = rows[rows.length - 1].key;
        } else if (r && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
            activate(r);
        } else if (r && event.key === Qt.Key_Right && (r.kind === "account" || r.kind === "section")) {
            const k = (r.kind === "account" ? "account:" : "labels:") + r.account.id;
            if (isFolded(k)) toggle(k);
        } else if (r && event.key === Qt.Key_Left) {
            if (r.kind === "account" || r.kind === "section") {
                const k = (r.kind === "account" ? "account:" : "labels:") + r.account.id;
                if (!isFolded(k)) toggle(k);
            } else {
                // From a box or a label back to the heading above it
                for (let j = i - 1; j >= 0; j--)
                    if (rows[j].kind === "section" || (rows[j].kind === "account" && r.kind === "box")) { cursor = rows[j].key; break; }
            }
        } else if (r && (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier)))) {
            if (r.kind === "account") contextRequested("account", r.account, cursorPos.x, cursorPos.y);
            else if (r.kind === "label") contextRequested("label", r.label, cursorPos.x, cursorPos.y);
        } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Insert) {
            addLabelRequested();
        } else {
            return;
        }
        event.accepted = true;
    }
    FocusRing { target: side; gap: -2; shown: false }

    Flickable {
        id: sideFlick
        anchors { fill: parent; bottomMargin: FiliTheme.statusHeight + FiliTheme.space2; topMargin: FiliTheme.space3 }
        contentHeight: column.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        KineticScroll {}
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
                        id: headRow
                        readonly property string rk: "a:" + modelData.id
                        readonly property bool atCursor: side.activeFocus && Facteur.keyNav && side.cursor === rk
                        onAtCursorChanged: if (atCursor) side.reveal(headRow)
                        Rectangle { visible: headRow.atCursor; anchors { fill: parent; margins: 1 } color: "transparent"; border.width: FiliTheme.borderWidth; border.color: FiliTheme.accentColor; radius: FiliTheme.radiusControl }
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
                        Icon {
                            id: service
                            anchors { left: arrow.right; leftMargin: FiliTheme.space2; bottom: parent.bottom; bottomMargin: (FiliTheme.sideRowHeight - height) / 2 }
                            name: side.serviceIcon(modelData)
                            size: 14
                            color: FiliTheme.accentColor
                        }
                        Text {
                            anchors { left: service.right; leftMargin: FiliTheme.space2; right: parent.right; rightMargin: FiliTheme.space2; bottom: parent.bottom; bottomMargin: (FiliTheme.sideRowHeight - height) / 2 }
                            text: (modelData.label !== "" ? modelData.label : modelData.email)
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
                        model: acct.open ? side.boxes : []
                        delegate: Rectangle {
                            id: boxRow
                            readonly property string rk: "b:" + acct.info.id + ":" + modelData.key
                            readonly property bool atCursor: side.activeFocus && Facteur.keyNav && side.cursor === rk
                            onAtCursorChanged: if (atCursor) side.reveal(boxRow)
                            Rectangle { visible: boxRow.atCursor; anchors { fill: parent; margins: 1 } color: "transparent"; border.width: FiliTheme.borderWidth; border.color: FiliTheme.accentColor; radius: FiliTheme.radiusControl }
                            width: column.width
                            height: FiliTheme.sideRowHeight
                            readonly property bool selected: acct.current && side.mailbox === modelData.key
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
                            MouseArea { id: row; anchors.fill: parent; hoverEnabled: true; onClicked: acct.current ? side.mailboxChosen(modelData.key) : side.boxOfAccountChosen(acct.info.id, modelData.key) }
                        }
                    }
                    // Labels (Gmail): heading with fold arrow and a button to make one
                    Rectangle {
                        id: labelsHead
                        readonly property string rk: "s:" + modelData.id
                        readonly property bool atCursor: side.activeFocus && Facteur.keyNav && side.cursor === rk
                        onAtCursorChanged: if (atCursor) side.reveal(labelsHead)
                        Rectangle { visible: labelsHead.atCursor; anchors { fill: parent; margins: 1 } color: "transparent"; border.width: FiliTheme.borderWidth; border.color: FiliTheme.accentColor; radius: FiliTheme.radiusControl }
                        visible: current && acct.open
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
                            text: side.sectionTitle
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
                        model: current && acct.open && labelsHead.open ? side.labels : []
                        delegate: Rectangle {
                            id: labelRow
                            readonly property string rk: "l:" + acct.info.id + ":" + key
                            readonly property bool atCursor: side.activeFocus && Facteur.keyNav && side.cursor === rk
                            onAtCursorChanged: if (atCursor) side.reveal(labelRow)
                            Rectangle { visible: labelRow.atCursor; anchors { fill: parent; margins: 1 } color: "transparent"; border.width: FiliTheme.borderWidth; border.color: FiliTheme.accentColor; radius: FiliTheme.radiusControl }
                            width: column.width
                            height: FiliTheme.sideRowHeight
                            readonly property string key: modelData.folder ? "folder:" + modelData.id : "label:" + modelData.rawName
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
    FiliScrollBar {
        flick: sideFlick
        anchors { top: sideFlick.top; bottom: sideFlick.bottom; right: sideFlick.right }
    }
    TextButton {
        anchors { left: parent.left; bottom: parent.bottom; leftMargin: FiliTheme.space3; bottomMargin: FiliTheme.space2 }
        label: "+ " + Facteur.tr("Add account")
        onClicked: side.addAccount()
    }
}
