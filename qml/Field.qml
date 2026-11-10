// Single-line text field of the forms: surface, border, accent outline on focus; secret = dots.
import QtQuick
import QtQuick.Controls.Basic
import Fili.Mail

TextField {
    id: f
    property bool secret: false
    implicitHeight: 28
    leftPadding: FiliTheme.space2
    rightPadding: FiliTheme.space2
    font.family: FiliTheme.font
    font.pixelSize: FiliTheme.size
    color: FiliTheme.text
    placeholderTextColor: FiliTheme.muted
    selectionColor: FiliTheme.surfaceActive
    selectedTextColor: FiliTheme.text
    echoMode: secret ? TextInput.Password : TextInput.Normal
    activeFocusOnTab: true
    background: Rectangle {
        radius: FiliTheme.radiusControl
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: f.activeFocus ? FiliTheme.accentColor : FiliTheme.border
    }
}
