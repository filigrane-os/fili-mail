// Messages of the mailbox: one dense row each (sender and time, subject and preview), unread in bold with a dot.
import QtQuick
import Fili.Mail

Rectangle {
    id: list
    property alias model: view.model
    property string selectedId: ""
    property string emptyText: ""
    // Nothing to show yet and the list is being fetched (or a search runs): a thin moving bar; a refresh behind rows is silent
    property bool loading: false
    // The list is a search result: the words, and whether the slow pass is still running
    property string searchQuery: ""
    property bool searchBusy: false
    signal searchCleared()
    signal chosen(string id)
    // Right click on a row: its index and the pointer position in the window
    signal contextRequested(int index, real x, real y)
    // Keyboard action on the current message: archive, trash, star, unread
    signal act(string operation)
    // In the Trash the trash button empties it (when the account can); nothing is "moved to the trash" there
    property bool inTrash: false
    property bool canEmptyTrash: false
    signal emptyTrash()
    // Previous or next message of the list (-1, +1)
    signal step(int delta)
    // Ticking: toggle one row (mode 0) or a range (mode 1), all, none
    // Inbox views mix accounts: each row then shows the account it comes from ({account id: {name, color}})
    property bool showAccount: false
    property var accountInfo: ({})
    // {account id: {label id: {name, color}}}; rows of a single account have no account of their own: fallbackAccount
    property var labelInfo: ({})
    property string fallbackAccount: ""
    signal check(int index, int mode)
    // Action of the floating menu of a row (operation, message id)
    signal rowAct(string operation, string id)
    signal checkAll()
    signal reply()
    signal replyAll()
    signal forward()
    // "/" asks for the search field
    signal searchRequested()
    function focusList() {
        view.forceActiveFocus();
        if (view.currentIndex < 0 && view.count > 0) view.currentIndex = 0;
    }
    signal clearChecks()
    property int checkedCount: 0
    // The end of the list is near: the next page can be fetched
    signal nearEnd()

    color: FiliTheme.background

    // Says that this list is a search result, with the way out beside it: without it the only sign is the field in the toolbar
    Rectangle {
        id: banner
        visible: list.searchQuery !== ""
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: visible ? 30 : 0
        color: FiliTheme.alpha(FiliTheme.accentColor, 0.14)
        Text {
            anchors { left: parent.left; leftMargin: FiliTheme.space2; right: bannerClear.left; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeList
            color: FiliTheme.text
            text: Facteur.tr("Results for “%1”").replace("%1", list.searchQuery) + "  ·  " + (list.searchBusy ? Facteur.tr("Searching…") : Facteur.tr("%1 messages").replace("%1", view.count))
        }
        IconButton {
            id: bannerClear
            name: "x"
            tip: Facteur.tr("Clear search")
            anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
            height: 24
            width: 24
            onClicked: list.searchCleared()
        }
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: FiliTheme.borderWidth; color: FiliTheme.alpha(FiliTheme.accentColor, 0.5) }
    }

    // Master tick box: ticks every message of the list, or none
    Rectangle {
        id: head
        anchors { left: parent.left; right: parent.right; top: banner.bottom }
        height: 30
        color: FiliTheme.background
        readonly property bool all: view.count > 0 && list.checkedCount === view.count
        readonly property bool some: list.checkedCount > 0 && !all
        Rectangle {
            x: FiliTheme.space2
            anchors.verticalCenter: parent.verticalCenter
            width: 14; height: 14; radius: 3
            color: head.all || head.some ? FiliTheme.accentColor : FiliTheme.surface
            border.width: FiliTheme.borderWidth
            border.color: head.all || head.some ? FiliTheme.accentColor : FiliTheme.textSecondary
            Text { anchors.centerIn: parent; visible: head.all; text: "✓"; font.pixelSize: 11; font.bold: true; color: FiliTheme.background }
            Rectangle { visible: head.some; anchors.centerIn: parent; width: 8; height: 2; color: FiliTheme.background }
        }
        Text {
            x: FiliTheme.space2 + 28
            anchors.verticalCenter: parent.verticalCenter
            text: list.checkedCount > 0 ? Facteur.tr("%1 selected").replace("%1", list.checkedCount) : Facteur.tr("Select all")
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeList
            color: FiliTheme.textSecondary
        }
        MouseArea { anchors.fill: parent; enabled: view.count > 0; onClicked: head.all || head.some ? list.clearChecks() : list.checkAll() }
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: FiliTheme.borderWidth; color: FiliTheme.border }
    }

    ListView {
        id: view
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom }
        onContentYChanged: if (contentHeight - contentY - height < 400) list.nearEnd()
        onCountChanged: Qt.callLater(() => { if (contentHeight - contentY - height < 400) list.nearEnd() })
        clip: true
        focus: true
        activeFocusOnTab: true
        currentIndex: -1
        boundsBehavior: Flickable.StopAtBounds
        KineticScroll {}
        delegate: Rectangle {
            id: row
            width: view.width
            // Labels of the message (the ones the user made) and, in the Inbox views, a line for its account
            readonly property var chips: {
                let ids = [];
                try { ids = JSON.parse(model.labels || "[]"); } catch (e) { ids = []; }
                const known = list.labelInfo[model.acct || list.fallbackAccount] || ({});
                return ids.filter(i => known[i]).slice(0, 3).map(i => known[i]);
            }
            // The account of the row: its own, else the one its id carries ("<account>\u001f<id>")
            readonly property string acct: model.acct !== "" ? model.acct : model.id.indexOf("\u001f") > 0 ? model.id.slice(0, model.id.indexOf("\u001f")) : ""
            readonly property bool thirdLine: list.showAccount || chips.length > 0
            height: thirdLine ? 70 : 52
            readonly property bool selected: model.id === list.selectedId
            readonly property bool showBox: model.checked || list.checkedCount > 0 || rowHover.hovered
            HoverHandler { id: rowHover }
            color: model.checked ? FiliTheme.surfaceActive : selected ? FiliTheme.surfaceHover : rowHover.hovered ? FiliTheme.alpha(FiliTheme.surfaceHover, 0.5) : "transparent"
            Rectangle { // unread dot: the state is also in the bold sender, colour is never the only signal
                visible: model.unread && !row.showBox
                x: FiliTheme.space2 + 4; y: 23
                width: 6; height: 6; radius: 3
                color: FiliTheme.accentColor
            }
            Rectangle { // tick box: the state is also the check mark, not only the fill
                visible: row.showBox
                x: FiliTheme.space2; y: 19; z: 2
                width: 14; height: 14; radius: 3
                color: model.checked ? FiliTheme.accentColor : FiliTheme.surface
                border.width: FiliTheme.borderWidth
                border.color: model.checked ? FiliTheme.accentColor : FiliTheme.textSecondary
                Text { anchors.centerIn: parent; visible: model.checked; text: "✓"; font.pixelSize: 11; font.bold: true; color: FiliTheme.background }
                MouseArea { anchors { fill: parent; margins: -4 } onClicked: list.check(index, 0) }
            }
            Text {
                id: from
                x: FiliTheme.space2 + 28; y: 7
                width: row.width - x - when.width - FiliTheme.space4
                text: model.from
                elide: Text.ElideRight
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                font.weight: model.unread ? FiliTheme.weightAccent : Font.Normal
                color: FiliTheme.text
            }
            Text {
                visible: model.starred
                anchors { right: when.left; rightMargin: FiliTheme.space1 }
                y: 8
                text: "★"
                font.pixelSize: FiliTheme.sizeList
                color: FiliTheme.warning
            }
            Text {
                id: when
                anchors { right: parent.right; rightMargin: FiliTheme.space3 }
                y: 9
                text: model.time
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeSmall
                color: FiliTheme.muted
            }
            Text {
                x: from.x; y: 27
                width: row.width - x - FiliTheme.space3 - (model.attach ? 18 : 0)
                text: model.subject
                elide: Text.ElideRight
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeList
                color: model.unread ? FiliTheme.text : FiliTheme.textSecondary
            }
            Icon { // attachment
                visible: model.attach === true
                anchors { right: parent.right; rightMargin: FiliTheme.space3 }
                y: 28
                name: "paperclip"
                size: 13
                color: FiliTheme.textSecondary
            }
            Row { // account (plain text, not a label), then the labels
                visible: row.thirdLine
                x: from.x; y: 49
                width: row.width - x - FiliTheme.space3
                height: 16
                spacing: FiliTheme.space3
                Row {
                    visible: list.showAccount
                    spacing: FiliTheme.space1
                    anchors.verticalCenter: parent.verticalCenter
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: (list.accountInfo[row.acct] || ({ icon: "mail" })).icon; size: 11; color: FiliTheme.muted }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 130)
                        text: (list.accountInfo[row.acct] || ({ name: row.acct })).name
                        elide: Text.ElideRight
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeSmall
                        color: FiliTheme.muted
                    }
                }
                Repeater {
                    model: row.chips
                    Row { // same look as the sidebar: colour dot, then the name
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: FiliTheme.space1
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: modelData.color }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 110)
                            text: modelData.name
                            elide: Text.ElideRight
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.sizeSmall
                            color: FiliTheme.textSecondary
                        }
                    }
                }
            }
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: FiliTheme.borderWidth; color: FiliTheme.border; opacity: 0.5 }
            MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: mouse => {
                if (mouse.button === Qt.RightButton) { const p = row.mapToItem(null, mouse.x, mouse.y); list.contextRequested(index, p.x, p.y); return }
                if (mouse.modifiers & Qt.ShiftModifier) list.check(index, 1);
                else if (mouse.modifiers & Qt.ControlModifier) list.check(index, 0);
                else { view.currentIndex = index; list.chosen(model.id) }
            } }
            // Floating actions on the message under the pointer (over its date)
            Rectangle {
                visible: rowHover.hovered && !model.id.startsWith("draft:")
                anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                width: actions.width + 2 * FiliTheme.space1
                height: 30
                radius: 8
                color: FiliTheme.surface
                border.width: FiliTheme.borderWidth
                border.color: FiliTheme.border
                Row {
                    id: actions
                    x: FiliTheme.space1
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    IconButton { name: model.unread ? "mail-open" : "mail"; tip: model.unread ? Facteur.tr("Mark as read") : Facteur.tr("Mark as unread"); onClicked: list.rowAct(model.unread ? "read" : "unread", model.id) }
                    IconButton { name: "archive"; tip: Facteur.tr("Archive message"); onClicked: list.rowAct("archive", model.id) }
                    IconButton { visible: !list.inTrash; name: "trash"; tip: Facteur.tr("Move to trash"); onClicked: list.rowAct("trash", model.id) }
                    IconButton { visible: list.canEmptyTrash; name: "trash"; tip: Facteur.tr("Empty Trash"); onClicked: list.emptyTrash() }
                    IconButton { name: "star"; filled: model.starred; tip: model.starred ? Facteur.tr("Remove star") : Facteur.tr("Star message"); onClicked: list.rowAct(model.starred ? "unstar" : "star", model.id) }
                }
            }
        }
        Keys.onPressed: event => {
            Facteur.keyNav = true;
            if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                view.currentIndex = Math.min(view.count - 1, view.currentIndex + 1);
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                view.currentIndex = Math.max(0, view.currentIndex - 1);
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (view.currentItem) list.chosen(view.model.get(view.currentIndex).id);
                return;
            } else if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier)) && (event.key === Qt.Key_R || event.key === Qt.Key_A || event.key === Qt.Key_F)) {
                if (event.key === Qt.Key_R) list.reply(); else if (event.key === Qt.Key_A) list.replyAll(); else list.forward();
                event.accepted = true;
                return;
            } else if (event.key === Qt.Key_Slash) {
                list.searchRequested();
                event.accepted = true;
                return;
            } else if (event.key === Qt.Key_X) {
                list.check(view.currentIndex, 0);
                event.accepted = true;
                return;
            } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
                list.checkAll();
                event.accepted = true;
                return;
            } else if (event.key === Qt.Key_Escape && list.checkedCount > 0) {
                list.clearChecks();
                event.accepted = true;
                return;
            } else if (event.key === Qt.Key_E) {
                list.act("archive");
                event.accepted = true;
                return;
            } else if (event.key === Qt.Key_NumberSign || event.key === Qt.Key_Delete) {
                if (!list.inTrash) list.act("trash");
                event.accepted = true;
                return;
            } else if (event.key === Qt.Key_S) {
                list.act("star");
                event.accepted = true;
                return;
            } else if (event.key === Qt.Key_U) {
                list.act("unread");
                event.accepted = true;
                return;
            } else {
                return;
            }
            list.chosen(view.model.get(view.currentIndex).id);
            event.accepted = true;
        }
        FocusRing { target: view; gap: -2; shown: view.activeFocus }
    }
    FiliScrollBar {
        flick: view
        anchors { top: view.top; bottom: view.bottom; right: view.right }
    }
    LoadingBar {
        active: list.loading
        anchors { left: parent.left; right: parent.right; top: head.bottom }
    }
    Text {
        anchors.centerIn: parent
        visible: view.count === 0 && list.emptyText !== "" && !list.loading
        text: list.emptyText
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        color: FiliTheme.muted
    }
}
