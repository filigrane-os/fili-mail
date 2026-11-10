// The open message: subject, sender and date, then the text body.
import QtQuick
import QtQuick.Controls.Basic
import Fili.Mail

Rectangle {
    id: reader
    // summary and body of the open message (empty: nothing selected)
    property var summary: null
    property string body: ""
    property string error: ""
    property bool starred: false
    property bool unread: false
    signal act(string operation)
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
            Text {
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
}
