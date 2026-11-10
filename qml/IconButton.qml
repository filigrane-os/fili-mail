// Toolbar icon button (Fili Icons glyph): hover surfaceHover, pressed surfaceActive, disabled muted
import QtQuick
import QtQuick.Controls.Basic
import Fili.Mail

Rectangle {
    id: b
    property string glyph
    // Line icon (Icon.qml) instead of a font glyph
    property string name
    property bool filled: false
    property string tip
    property bool enabledState: true
    signal clicked()

    width: 28
    height: 24
    radius: FiliTheme.radiusControl
    color: !enabledState ? "transparent" : area.pressed ? FiliTheme.surfaceActive : area.containsMouse ? FiliTheme.surfaceHover : "transparent"
    activeFocusOnTab: false

    Icon {
        visible: b.name !== ""
        anchors.centerIn: parent
        name: b.name
        filled: b.filled
        size: 16
        color: b.enabledState ? FiliTheme.text : FiliTheme.muted
    }
    Text {
        visible: b.name === ""
        anchors.centerIn: parent
        text: b.glyph
        font.family: FiliTheme.icons
        font.pixelSize: 14
        color: b.enabledState ? FiliTheme.text : FiliTheme.muted
    }
    ToolTip {
        visible: area.containsMouse && b.tip !== ""
        delay: 600
        text: b.tip
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.sizeList
        contentItem: Text { text: b.tip; font: parent.font; color: FiliTheme.text }
        background: Rectangle { color: FiliTheme.surface; border.width: FiliTheme.borderWidth; border.color: FiliTheme.border; radius: FiliTheme.radiusControl }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: b.enabledState
        onClicked: b.clicked()
    }
}
