// Tab row shared by the Filigrane applications: tabs the user can drag to reorder, a "+" button after them.
// items: [{key, label, icon}] in display order. Reordering is a constant of every tab row (see app-window.md): drag a
// tab onto another one; `reordered(keys)` gives the new order when the button is released.
import QtQuick
import Fili.Mail

Item {
    id: strip
    property var items: []
    property string current: ""
    // {tab key: unread messages}, shown after the tab name
    property var counts: ({})
    property bool addable: true
    signal chosen(string key)
    signal reordered(var keys)
    signal addRequested()
    // Middle click on a tab, right click (window position)
    signal closeRequested(string key)
    signal contextRequested(string key, real x, real y)

    height: FiliTheme.tabHeight

    ListModel { id: model }
    function sync() {
        let same = model.count === items.length;
        for (let i = 0; same && i < items.length; i++)
            if (model.get(i).key !== items[i].key) same = false;
        if (!same) {
            model.clear();
            for (const t of items) model.append({ key: t.key, label: t.label, icon: t.icon || "" });
        } else {
            for (let i = 0; i < items.length; i++) {
                model.setProperty(i, "label", items[i].label);
                model.setProperty(i, "icon", items[i].icon || "");
            }
        }
    }
    onCurrentChanged: view.showCurrent()
    onItemsChanged: sync()
    Component.onCompleted: sync()
    function order() {
        const keys = [];
        for (let i = 0; i < model.count; i++) keys.push(model.get(i).key);
        return keys;
    }

    ListView {
        id: view
        orientation: ListView.Horizontal
        interactive: false
        clip: true
        spacing: FiliTheme.space3
        height: strip.height
        width: Math.min(contentWidth, strip.width - (strip.addable ? plus.width + FiliTheme.space3 : 0))
        model: model
        // The row does not flick (a drag moves a tab): when the tabs are wider than the space, the wheel scrolls it and
        // the current tab is brought into view
        readonly property bool overflows: contentWidth > width
        function clampX(x) { return Math.max(0, Math.min(x, contentWidth - width)); }
        function showCurrent() {
            if (!overflows) { contentX = 0; return; }
            for (let i = 0; i < model.count; i++) {
                if (model.get(i).key !== strip.current) continue;
                const item = itemAtIndex(i);
                if (!item) { positionViewAtIndex(i, ListView.Contain); return; }
                if (item.x < contentX) contentX = clampX(item.x);
                else if (item.x + item.width > contentX + width) contentX = clampX(item.x + item.width - width);
                return;
            }
        }
        onContentWidthChanged: showCurrent()
        onWidthChanged: showCurrent()
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const d = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y;
                view.contentX = view.clampX(view.contentX - d);
            }
        }
        delegate: Item {
            id: slot
            required property int index
            required property string key
            required property string label
            required property string icon
            readonly property bool on: strip.current === key
            width: tab.width
            height: FiliTheme.tabHeight
            z: area.drag.active ? 10 : 0

            DropArea {
                anchors.fill: parent
                onEntered: drag => {
                    const from = drag.source.slotIndex;
                    if (from !== slot.index) model.move(from, slot.index, 1);
                }
            }

            Rectangle {
                id: tab
                property int slotIndex: slot.index
                anchors.horizontalCenter: slot.horizontalCenter
                anchors.verticalCenter: slot.verticalCenter
                width: tabIcon.width + FiliTheme.space2 + tabText.implicitWidth + (tabBadge.visible ? FiliTheme.space2 + tabBadge.implicitWidth : 0) + 2 * FiliTheme.space4
                height: FiliTheme.tabHeight
                radius: FiliTheme.radiusControl
                color: slot.on ? FiliTheme.surfaceActive : area.containsMouse || area.drag.active ? FiliTheme.surfaceHover : "transparent"
                Drag.active: area.drag.active
                Drag.source: tab
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2
                states: State {
                    when: tab.Drag.active
                    ParentChange { target: tab; parent: strip }
                    AnchorChanges { target: tab; anchors.horizontalCenter: undefined; anchors.verticalCenter: undefined }
                }
                Icon {
                    id: tabIcon
                    x: FiliTheme.space4
                    anchors.verticalCenter: parent.verticalCenter
                    name: slot.icon
                    size: 14
                    color: slot.on ? FiliTheme.accentColor : FiliTheme.textSecondary
                }
                Text {
                    id: tabText
                    x: FiliTheme.space4 + tabIcon.width + FiliTheme.space2
                    anchors.verticalCenter: parent.verticalCenter
                    text: slot.label
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeList
                    font.weight: slot.on ? FiliTheme.weightAccent : Font.Normal
                    color: slot.on ? FiliTheme.text : FiliTheme.textSecondary
                }
                Text {
                    id: tabBadge
                    readonly property int n: strip.counts[slot.key] || 0
                    visible: n > 0
                    x: tabText.x + tabText.implicitWidth + FiliTheme.space2
                    anchors.verticalCenter: parent.verticalCenter
                    text: "" + n
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeSmall
                    color: slot.on ? FiliTheme.accentColor : FiliTheme.muted
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    drag.target: tab
                    drag.axis: Drag.XAxis
                    drag.threshold: 6
                    onClicked: mouse => {
                        if (mouse.button === Qt.MiddleButton) strip.closeRequested(slot.key);
                        else if (mouse.button === Qt.RightButton) {
                            const p = tab.mapToItem(null, mouse.x, mouse.y);
                            strip.contextRequested(slot.key, p.x, p.y);
                        } else strip.chosen(slot.key);
                    }
                    onReleased: {
                        if (!tab.Drag.active) return;
                        tab.Drag.drop();
                        strip.reordered(strip.order());
                    }
                }
            }
        }
    }

    IconButton {
        id: plus
        visible: strip.addable
        x: view.width + (view.count > 0 ? FiliTheme.space3 : 0)
        anchors.verticalCenter: parent.verticalCenter
        name: "plus"
        tip: Facteur.tr("Add a folder tab")
        onClicked: strip.addRequested()
    }
}
