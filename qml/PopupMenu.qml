// Context menu: a small card at the pointer with one row per entry; a click anywhere else, or Esc, closes it.
// items: [{id, label, danger}]; `activated(id)` is sent before it closes.
import QtQuick
import Fili.Mail

Item {
    id: menu
    property var items: []
    signal activated(string id)
    visible: false
    anchors.fill: parent
    z: 200

    function openAt(x, y, entries) {
        items = entries;
        card.x = Math.max(4, Math.min(x, menu.width - card.width - 4));
        card.y = Math.max(4, Math.min(y, menu.height - card.height - 4));
        visible = true;
        forceActiveFocus();
    }
    function close() { visible = false; }

    Keys.onEscapePressed: menu.close()
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: menu.close()
    }
    Rectangle {
        id: card
        width: 190
        height: col.height + 2 * FiliTheme.space1
        radius: FiliTheme.radiusControl
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: FiliTheme.border
        Column {
            id: col
            x: FiliTheme.space1
            y: FiliTheme.space1
            width: parent.width - 2 * FiliTheme.space1
            Repeater {
                model: menu.items
                Rectangle {
                    required property var modelData
                    width: col.width
                    height: 26
                    radius: FiliTheme.radiusControl
                    color: area.containsMouse ? FiliTheme.surfaceHover : "transparent"
                    Text {
                        anchors { left: parent.left; leftMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                        text: modelData.label
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.size
                        color: modelData.danger ? FiliTheme.danger : FiliTheme.text
                    }
                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { const id = modelData.id; menu.close(); menu.activated(id); }
                    }
                }
            }
        }
    }
}
