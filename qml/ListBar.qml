// Bar over the list and the reader (full width): actions on the selected or ticked messages, filter, position and
// previous/next, then the category tabs (Gmail inbox).
import QtQuick
import Fili.Mail

Rectangle {
    id: list
    signal act(string operation)
    signal step(int delta)
    signal tabChosen(string key)
    property int checkedCount: 0
    property string selectedId: ""
    property var tabs: []
    property string tab: ""
    property bool selectedUnread: false
    property bool selectedStarred: false
    property string position: ""
    property bool canPrev: false
    property bool canNext: false
    // Only unread messages (the list is filtered when loaded)
    property bool unreadOnly: false

    color: FiliTheme.background
    height: bar.height + tabRow.height

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
            IconButton { name: "chevron-left"; tip: Facteur.tr("Previous message"); enabledState: list.canPrev && list.checkedCount === 0; onClicked: list.step(-1) }
            IconButton { name: "chevron-right"; tip: Facteur.tr("Next message"); enabledState: list.canNext && list.checkedCount === 0; onClicked: list.step(1) }
            Rectangle { width: 1; height: 18; anchors.verticalCenter: parent.verticalCenter; color: FiliTheme.border }
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
        }
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: FiliTheme.borderWidth; color: FiliTheme.border }
    }

    Rectangle {
        id: tabRow
        visible: list.tabs.length > 0
        anchors { left: parent.left; right: parent.right; top: bar.bottom }
        height: visible ? 40 : 0
        color: FiliTheme.background
        Row {
            anchors { left: parent.left; leftMargin: FiliTheme.margin; verticalCenter: parent.verticalCenter }
            spacing: FiliTheme.space3
            Repeater {
                model: list.tabs
                Rectangle {
                    required property var modelData
                    readonly property bool on: list.tab === modelData.key
                    width: tabText.implicitWidth + 2 * FiliTheme.space4
                    height: 28
                    radius: FiliTheme.radiusControl
                    color: on ? FiliTheme.surfaceActive : tabArea.containsMouse ? FiliTheme.surfaceHover : "transparent"
                    Text {
                        id: tabText
                        anchors.centerIn: parent
                        text: modelData.label
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeList
                        font.weight: on ? FiliTheme.weightAccent : Font.Normal
                        color: on ? FiliTheme.text : FiliTheme.textSecondary
                    }
                    MouseArea { id: tabArea; anchors.fill: parent; hoverEnabled: true; onClicked: list.tabChosen(modelData.key) }
                }
            }
        }
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: FiliTheme.borderWidth; color: FiliTheme.border; visible: parent.visible }
    }
}
