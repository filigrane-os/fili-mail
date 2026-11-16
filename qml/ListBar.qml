// Tab row over the list and the reader (full width): the tabs (Gmail categories and folders the user pinned; draggable, "+" adds one).
import QtQuick
import Fili.Mail

Rectangle {
    id: list
    signal tabChosen(string key)
    signal tabsReordered(var keys)
    signal tabAddRequested()
    signal tabCloseRequested(string key)
    signal tabContext(string key, real x, real y)
    property var tabs: []
    property bool tabsAddable: true
    // The tab system is in use; off, the band is not there at all
    property bool shown: true
    property string tab: ""
    // {tab key: unread messages}, shown after the tab name
    property var tabCounts: ({})
    // Only unread messages (the list is filtered when loaded); toggled from the header
    property bool unreadOnly: false

    color: FiliTheme.background
    visible: shown
    height: shown ? tabRow.height : 0

    Rectangle {
        id: tabRow
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: FiliTheme.tabBarHeight
        color: FiliTheme.background
        TabStrip {
            anchors { left: parent.left; leftMargin: FiliTheme.margin; right: parent.right; rightMargin: FiliTheme.margin; verticalCenter: parent.verticalCenter }
            items: list.tabs
            addable: list.tabsAddable
            current: list.tab
            counts: list.tabCounts
            onChosen: key => list.tabChosen(key)
            onReordered: keys => list.tabsReordered(keys)
            onAddRequested: list.tabAddRequested()
            onCloseRequested: key => list.tabCloseRequested(key)
            onContextRequested: (key, x, y) => list.tabContext(key, x, y)
        }
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: FiliTheme.borderWidth; color: FiliTheme.border }
    }
}
