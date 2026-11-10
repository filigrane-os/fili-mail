// The open message: subject, sender and date, then the text body.
import QtQuick
import QtQuick.Controls.Basic
import Fili.Mail

Rectangle {
    id: reader
    // summary and body of the open message (empty: nothing selected)
    property var summary: null
    property string body: ""
    // Sanitized rich text of an HTML message (empty: show body as plain text)
    property string rich: ""
    property string error: ""
    property bool starred: false
    property bool unread: false
    // Link under the pointer, shown at the bottom
    property string hovered: ""
    signal act(string operation)
    signal reply()
    signal loadImages()
    // Pictures of the sender held back (number), and whether they are being fetched
    property int remoteImages: 0
    property bool loadingImages: false
    signal forward()
    color: FiliTheme.backgroundDeep

    Text {
        anchors.centerIn: parent
        visible: reader.summary === null && reader.error === ""
        text: Facteur.tr("Select a message to read it")
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        color: FiliTheme.muted
    }
    Text {
        anchors { centerIn: parent; margins: FiliTheme.margin }
        width: parent.width - 2 * FiliTheme.margin
        horizontalAlignment: Text.AlignHCenter
        visible: reader.error !== ""
        text: reader.error
        wrapMode: Text.WordWrap
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        color: FiliTheme.danger
    }
    Row {
        id: tools
        visible: reader.summary !== null
        x: FiliTheme.space2
        y: FiliTheme.space2
        spacing: FiliTheme.space1
        TextButton { label: Facteur.tr("Reply"); onClicked: reader.reply() }
        TextButton { label: Facteur.tr("Forward"); onClicked: reader.forward() }
        TextButton { label: Facteur.tr("Archive"); onClicked: reader.act("archive") }
        TextButton { label: Facteur.tr("Trash"); onClicked: reader.act("trash") }
        TextButton { label: Facteur.tr("Spam"); onClicked: reader.act("spam") }
        TextButton { label: reader.starred ? Facteur.tr("Unstar") : Facteur.tr("Star"); onClicked: reader.act(reader.starred ? "unstar" : "star") }
        TextButton { label: reader.unread ? Facteur.tr("Mark as read") : Facteur.tr("Mark as unread"); onClicked: reader.act(reader.unread ? "read" : "unread") }
    }
    ScrollView {
        anchors { fill: parent; topMargin: tools.visible ? tools.height + 2 * FiliTheme.space2 : 0 }
        visible: reader.summary !== null
        contentWidth: availableWidth
        clip: true
        Column {
            x: FiliTheme.margin
            width: parent.width - 2 * FiliTheme.margin
            topPadding: FiliTheme.margin
            bottomPadding: FiliTheme.margin
            spacing: FiliTheme.space2
            Text {
                width: parent.width
                text: reader.summary ? reader.summary.subject : ""
                wrapMode: Text.WordWrap
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeTitle
                font.weight: FiliTheme.weightAccent
                color: FiliTheme.text
            }
            Text {
                width: parent.width
                text: reader.summary ? (reader.summary.from.display || reader.summary.from.email) + "  ·  " + reader.summary.fullTime : ""
                elide: Text.ElideRight
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeList
                color: FiliTheme.textSecondary
            }
            Rectangle { width: parent.width; height: FiliTheme.borderWidth; color: FiliTheme.border }
            // Pictures of the sender are held back: they tell the sender the message was opened
            Rectangle {
                visible: reader.remoteImages > 0
                width: parent.width
                height: 30
                radius: FiliTheme.radiusControl
                color: FiliTheme.surface
                border.width: FiliTheme.borderWidth
                border.color: FiliTheme.border
                Text {
                    anchors { left: parent.left; leftMargin: FiliTheme.space3; right: loadButton.left; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                    text: Facteur.tr("Pictures are hidden: the sender could see that you read this message.")
                    elide: Text.ElideRight
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeList
                    color: FiliTheme.textSecondary
                }
                TextButton {
                    id: loadButton
                    anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                    label: reader.loadingImages ? "…" : Facteur.tr("Load pictures (%1)").replace("%1", reader.remoteImages)
                    onClicked: if (!reader.loadingImages) reader.loadImages()
                }
            }
            // HTML mail is drawn on paper: senders choose their colors for a white page
            Rectangle {
                visible: reader.rich !== ""
                width: parent.width
                height: richText.implicitHeight + 2 * FiliTheme.space3
                radius: FiliTheme.radiusControl
                color: "#ffffff"
                Text {
                    id: richText
                    x: FiliTheme.space3
                    y: FiliTheme.space3
                    width: parent.width - 2 * FiliTheme.space3
                    text: reader.rich
                    wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    linkColor: "#1a56c4"
                    onLinkActivated: link => Qt.openUrlExternally(link)
                    onHoveredLinkChanged: reader.hovered = hoveredLink
                    HoverHandler { cursorShape: richText.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.size
                    lineHeight: 1.25
                    color: "#202124"
                }
            }
            Text {
                visible: reader.rich === ""
                width: parent.width
                text: reader.body
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                lineHeight: 1.25
                color: FiliTheme.text
            }
        }
    }
    Rectangle {
        visible: reader.hovered !== ""
        anchors { left: parent.left; bottom: parent.bottom }
        width: Math.min(parent.width, hoverText.implicitWidth + 2 * FiliTheme.space2)
        height: hoverText.implicitHeight + FiliTheme.space2
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: FiliTheme.border
        Text {
            id: hoverText
            anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
            verticalAlignment: Text.AlignVCenter
            text: reader.hovered
            elide: Text.ElideMiddle
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeList
            color: FiliTheme.textSecondary
        }
    }
}
