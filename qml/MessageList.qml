// Messages of the mailbox: one dense row each (sender and time, subject and preview), unread in bold with a dot.
import QtQuick
import Fili.Mail

Rectangle {
    id: list
    property alias model: view.model
    property string selectedId: ""
    property string emptyText: ""
    signal chosen(string id)
    // Keyboard action on the current message: archive, trash, star, unread
    signal act(string operation)
    // Previous or next message of the list (-1, +1)
    signal step(int delta)
    // Ticking: toggle one row (mode 0) or a range (mode 1), all, none
    signal check(int index, int mode)
    signal checkAll()
    signal clearChecks()
    property int checkedCount: 0
    // State of the selected message, for the action bar
    property bool selectedUnread: false
    property bool selectedStarred: false
    property string position: ""
    property bool canPrev: false
    property bool canNext: false
    // Only unread messages (the list is filtered when loaded)
    property bool unreadOnly: false

    color: FiliTheme.background

    // Actions on the selected message, then its place in the list
    Rectangle {
        id: bar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 40
        color: FiliTheme.background
        Row {
            x: FiliTheme.space2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            readonly property bool on: list.selectedId !== "" || list.checkedCount > 0
            IconButton { name: list.selectedUnread ? "mail-open" : "mail"; tip: list.selectedUnread ? Facteur.tr("Mark as read") : Facteur.tr("Mark as unread"); enabledState: parent.on; onClicked: list.act(list.selectedUnread ? "read" : "unread") }
            Rectangle { width: 1; height: 18; anchors.verticalCenter: parent.verticalCenter; color: FiliTheme.border }
            IconButton { name: "trash"; tip: Facteur.tr("Move to trash"); enabledState: parent.on; onClicked: list.act("trash") }
            IconButton { name: "archive"; tip: Facteur.tr("Archive message"); enabledState: parent.on; onClicked: list.act("archive") }
            IconButton { name: "spam"; tip: Facteur.tr("Mark as spam"); enabledState: parent.on; onClicked: list.act("spam") }
            Rectangle { width: 1; height: 18; anchors.verticalCenter: parent.verticalCenter; color: FiliTheme.border }
            IconButton { name: "star"; filled: list.selectedStarred; tip: list.selectedStarred ? Facteur.tr("Remove star") : Facteur.tr("Star message"); enabledState: parent.on; onClicked: list.act(list.selectedStarred ? "unstar" : "star") }
        }
        Row {
            anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
            spacing: 2
            Text {
                anchors.verticalCenter: parent.verticalCenter
                rightPadding: FiliTheme.space1
                text: list.checkedCount > 0 ? Facteur.tr("%1 selected").replace("%1", list.checkedCount) : list.position
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeList
                color: FiliTheme.textSecondary
            }
            IconButton { name: "mail"; toggled: list.unreadOnly; tip: Facteur.tr("Unread only"); onClicked: list.unreadOnly = !list.unreadOnly }
            IconButton { name: "chevron-left"; tip: Facteur.tr("Previous message"); enabledState: list.canPrev && list.checkedCount === 0; onClicked: list.step(-1) }
            IconButton { name: "chevron-right"; tip: Facteur.tr("Next message"); enabledState: list.canNext && list.checkedCount === 0; onClicked: list.step(1) }
        }
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: FiliTheme.borderWidth; color: FiliTheme.border }
    }

    ListView {
        id: view
        anchors { left: parent.left; right: parent.right; top: bar.bottom; bottom: parent.bottom }
        clip: true
        focus: true
        activeFocusOnTab: true
        currentIndex: -1
        boundsBehavior: Flickable.StopAtBounds
        KineticScroll {}
        delegate: Rectangle {
            id: row
            width: view.width
            height: 52
            readonly property bool selected: model.id === list.selectedId
            readonly property bool showBox: model.checked || list.checkedCount > 0 || hover.containsMouse
            color: model.checked ? FiliTheme.surfaceActive : selected ? FiliTheme.surfaceHover : hover.containsMouse ? FiliTheme.alpha(FiliTheme.surfaceHover, 0.5) : "transparent"
            Rectangle { // unread dot: the state is also in the bold sender, colour is never the only signal
                visible: model.unread && !row.showBox
                x: FiliTheme.space2; y: 12
                width: 6; height: 6; radius: 3
                color: FiliTheme.accentColor
            }
            Rectangle { // tick box: the state is also the check mark, not only the fill
                visible: row.showBox
                x: FiliTheme.space2 - 1; y: 9; z: 2
                width: 14; height: 14; radius: 3
                color: model.checked ? FiliTheme.accentColor : FiliTheme.surface
                border.width: FiliTheme.borderWidth
                border.color: model.checked ? FiliTheme.accentColor : FiliTheme.textSecondary
                Text { anchors.centerIn: parent; visible: model.checked; text: "✓"; font.pixelSize: 11; font.bold: true; color: FiliTheme.background }
                MouseArea { anchors { fill: parent; margins: -4 } onClicked: list.check(index, 0) }
            }
            Text {
                id: from
                x: FiliTheme.space2 + 14; y: 7
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
                width: row.width - x - FiliTheme.space3
                text: model.subject
                elide: Text.ElideRight
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeList
                color: model.unread ? FiliTheme.text : FiliTheme.textSecondary
            }
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: FiliTheme.borderWidth; color: FiliTheme.border; opacity: 0.5 }
            MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; onClicked: mouse => {
                if (mouse.modifiers & Qt.ShiftModifier) list.check(index, 1);
                else if (mouse.modifiers & Qt.ControlModifier) list.check(index, 0);
                else { view.currentIndex = index; list.chosen(model.id) }
            } }
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
                list.act("trash");
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
    Text {
        anchors.centerIn: parent
        visible: view.count === 0 && list.emptyText !== ""
        text: list.emptyText
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        color: FiliTheme.muted
    }
}
