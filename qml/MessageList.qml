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

    color: FiliTheme.background

    ListView {
        id: view
        anchors.fill: parent
        clip: true
        focus: true
        activeFocusOnTab: true
        currentIndex: -1
        boundsBehavior: Flickable.StopAtBounds
        delegate: Rectangle {
            id: row
            width: view.width
            height: 52
            readonly property bool selected: model.id === list.selectedId
            color: selected ? FiliTheme.surfaceHover : hover.containsMouse ? FiliTheme.alpha(FiliTheme.surfaceHover, 0.5) : "transparent"
            Rectangle { // unread dot: the state is also in the bold sender, colour is never the only signal
                visible: model.unread
                x: FiliTheme.space2; y: 12
                width: 6; height: 6; radius: 3
                color: FiliTheme.accentColor
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
            MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; onClicked: { view.currentIndex = index; list.chosen(model.id) } }
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
    Text {
        anchors.centerIn: parent
        visible: view.count === 0 && list.emptyText !== ""
        text: list.emptyText
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        color: FiliTheme.muted
    }
}
