// The open message: title, a frame with sender, recipients and the actions, then the message on paper.
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
    // First unsubscribe address the sender declared (empty: none)
    property string unsubscribeUrl: ""
    // Pictures of the sender held back (number), and whether they are being fetched
    property int remoteImages: 0
    property bool loadingImages: false
    signal act(string operation)
    signal reply()
    signal replyAll()
    signal forward()
    signal loadImages()
    signal unsubscribe(string url)
    color: FiliTheme.backgroundDeep

    function names(list) {
        return (list || []).map(a => a.display || a.email).join(", ");
    }

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
    ScrollView {
        anchors.fill: parent
        visible: reader.summary !== null
        contentWidth: availableWidth
        clip: true
        Column {
            x: FiliTheme.margin
            width: parent.width - 2 * FiliTheme.margin
            topPadding: FiliTheme.margin
            bottomPadding: FiliTheme.margin
            spacing: FiliTheme.space3
            Text {
                width: parent.width
                text: reader.summary ? reader.summary.subject : ""
                wrapMode: Text.WordWrap
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeTitle
                font.weight: FiliTheme.weightAccent
                color: FiliTheme.text
            }
            // Frame: who wrote to whom and when, what the sender offers, what can be done
            Rectangle {
                width: parent.width
                height: frame.implicitHeight + 2 * FiliTheme.space3
                radius: FiliTheme.radiusControl
                color: FiliTheme.background
                border.width: FiliTheme.borderWidth
                border.color: FiliTheme.border
                Column {
                    id: frame
                    x: FiliTheme.space3
                    y: FiliTheme.space3
                    width: parent.width - 2 * FiliTheme.space3
                    spacing: FiliTheme.space2
                    readonly property bool narrow: width < 440
                    Row {
                        width: parent.width
                        spacing: FiliTheme.space3
                        Text { id: fromLabel; width: 44; text: Facteur.tr("From"); font.family: FiliTheme.font; font.pixelSize: FiliTheme.sizeList; color: FiliTheme.textSecondary }
                        Text {
                            width: Math.max(0, parent.width - 44 - parent.spacing - (when.visible ? when.width + parent.spacing : 0))
                            textFormat: Text.StyledText
                            text: reader.summary ? "<b>" + (reader.summary.from.display || reader.summary.from.email) + "</b>" + (reader.summary.from.display ? " &lt;" + reader.summary.from.email + "&gt;" : "") : ""
                            elide: Text.ElideRight
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.size
                            color: FiliTheme.text
                        }
                        Text {
                            id: when
                            visible: !frame.narrow
                            text: reader.summary ? reader.summary.fullTime : ""
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.sizeList
                            color: FiliTheme.textSecondary
                        }
                    }
                    Row {
                        width: parent.width
                        spacing: FiliTheme.space3
                        Text { width: 44; text: Facteur.tr("To"); font.family: FiliTheme.font; font.pixelSize: FiliTheme.sizeList; color: FiliTheme.textSecondary }
                        Text {
                            width: Math.max(0, parent.width - 44 - parent.spacing)
                            text: reader.summary ? reader.names(reader.summary.to) + (reader.summary.cc && reader.summary.cc.length > 0 ? "   " + Facteur.tr("Cc") + ": " + reader.names(reader.summary.cc) : "") : ""
                            elide: Text.ElideRight
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.size
                            color: FiliTheme.text
                        }
                    }
                    Text {
                        visible: frame.narrow
                        width: parent.width
                        text: reader.summary ? reader.summary.fullTime : ""
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeList
                        color: FiliTheme.textSecondary
                    }
                    // Mailing list: the sender gave a way out
                    Rectangle {
                        visible: reader.unsubscribeUrl !== ""
                        width: parent.width
                        height: 30
                        radius: FiliTheme.radiusControl
                        color: FiliTheme.surface
                        border.width: FiliTheme.borderWidth
                        border.color: FiliTheme.border
                        Icon { x: FiliTheme.space3; anchors.verticalCenter: parent.verticalCenter; name: "mail"; size: 14; color: FiliTheme.textSecondary }
                        Text {
                            x: FiliTheme.space3 + 14 + FiliTheme.space2
                            anchors.verticalCenter: parent.verticalCenter
                            text: Facteur.tr("This message comes from a mailing list.")
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.sizeList
                            color: FiliTheme.textSecondary
                        }
                        TextButton {
                            anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                            label: Facteur.tr("Unsubscribe")
                            onClicked: reader.unsubscribe(reader.unsubscribeUrl)
                        }
                    }
                    Flow {
                        id: actions
                        width: parent.width
                        spacing: FiliTheme.space2
                        Rectangle {
                            id: leftCap
                            width: leftActions.width + 2 * FiliTheme.space1
                            height: 30
                            radius: FiliTheme.radiusControl
                            color: FiliTheme.surface
                            border.width: FiliTheme.borderWidth
                            border.color: FiliTheme.border
                            Row {
                                id: leftActions
                                x: FiliTheme.space1
                                anchors.verticalCenter: parent.verticalCenter
                                IconButton { name: reader.unread ? "mail-open" : "mail"; tip: reader.unread ? Facteur.tr("Mark as read") : Facteur.tr("Mark as unread"); onClicked: reader.act(reader.unread ? "read" : "unread") }
                                IconButton { name: "trash"; tip: Facteur.tr("Move to trash"); onClicked: reader.act("trash") }
                                IconButton { name: "archive"; tip: Facteur.tr("Archive message"); onClicked: reader.act("archive") }
                                IconButton { name: "spam"; tip: Facteur.tr("Mark as spam"); onClicked: reader.act("spam") }
                                IconButton { name: "star"; filled: reader.starred; tip: reader.starred ? Facteur.tr("Remove star") : Facteur.tr("Star message"); onClicked: reader.act(reader.starred ? "unstar" : "star") }
                            }
                        }
                        // Pushes the reply group to the right when both fit on one line
                        Item { width: Math.max(0, actions.width - leftCap.width - rightCap.width - 2 * actions.spacing); height: 1 }
                        Rectangle {
                            id: rightCap
                            width: rightActions.width + 2 * FiliTheme.space1
                            height: 30
                            radius: FiliTheme.radiusControl
                            color: FiliTheme.surface
                            border.width: FiliTheme.borderWidth
                            border.color: FiliTheme.border
                            Row {
                                id: rightActions
                                x: FiliTheme.space1
                                anchors.verticalCenter: parent.verticalCenter
                                IconButton { name: "reply"; tip: Facteur.tr("Reply"); onClicked: reader.reply() }
                                IconButton { name: "reply-all"; tip: Facteur.tr("Reply all"); onClicked: reader.replyAll() }
                                IconButton { name: "forward"; tip: Facteur.tr("Forward"); onClicked: reader.forward() }
                            }
                        }
                    }
                }
            }
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
