// Thin bar sliding along its width while something loads (a list, a message). Place it at the top of the area.
import QtQuick
import Fili.Mail

Item {
    id: bar
    property bool active: false
    visible: active
    height: 2
    clip: true
    z: 40
    Rectangle {
        id: slider
        width: bar.width * 0.3
        height: bar.height
        color: FiliTheme.accentColor
        NumberAnimation on x { running: bar.active; from: -slider.width; to: bar.width; duration: 1100; loops: Animation.Infinite }
    }
}
