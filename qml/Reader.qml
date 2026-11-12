// The open message: title, a frame with sender, recipients and the actions, then the message on paper.
import QtQuick
import QtQuick.Controls.Basic
import Fili.Mail
import Fili.Html

Rectangle {
    id: reader
    // summary and body of the open message (empty: nothing selected)
    property var summary: null
    property string body: ""
    // Sanitized rich text of an HTML message (empty: show body as plain text)
    property string rich: ""
    // Sanitized HTML of the message, laid out by HtmlView (litehtml); `rich` is the fallback
    property string html: ""
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
    // Files attached to the message ({filename, mimeType, size, attachmentId}); clicking one opens it, its arrow saves it
    property var attachments: []
    signal saveAttachment(int index)
    signal openAttachment(int index)
    signal saveAllAttachments()
    // Right click on the HTML page, at (x, y) in the window: the link and whether a picture is under it
    signal pageMenu(real x, real y, string link, bool image)
    readonly property bool hasSelection: reader.html !== "" && page.hasSelection
    // Selection of the HTML page (Edit menu, Ctrl+C, Ctrl+A)
    function copySelection() { return reader.html !== "" && page.copy(); }
    function selectAllText() { if (reader.html !== "") page.selectAll(); }
    function pageAction(id, link) {
        if (id === "open-link") Qt.openUrlExternally(link);
        else if (id === "copy-link") page.copyText(link.startsWith("mailto:") ? decodeURIComponent(link.slice(7).split("?")[0]) : link);
        else if (id === "copy-image") page.copyImage();
        else if (id === "copy") page.copy();
        else if (id === "select-all") page.selectAll();
    }
    // Escape: back to the list
    signal leave()
    function focusReader() { scroller.forceActiveFocus(); }
    color: FiliTheme.backgroundDeep

    function sizeText(bytes) {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1048576) return Math.round(bytes / 1024) + " KB";
        return (bytes / 1048576).toFixed(1) + " MB";
    }
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
    Flickable {
        id: scroller
        anchors.fill: parent
        visible: reader.summary !== null
        contentWidth: width
        contentHeight: content.height
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        KineticScroll {}
        activeFocusOnTab: true
        // Keyboard: scrolling, and the keys of the list for the message that is open
        Keys.onPressed: event => {
            Facteur.keyNav = true;
            const top = scroller.originY, max = Math.max(top, top + scroller.contentHeight - scroller.height);
            const go = y => scroller.contentY = Math.max(top, Math.min(max, y));
            const plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier));
            if (event.key === Qt.Key_Down || (plain && event.key === Qt.Key_J)) go(scroller.contentY + 48);
            else if (event.key === Qt.Key_Up || (plain && event.key === Qt.Key_K)) go(scroller.contentY - 48);
            else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_Space) go(scroller.contentY + scroller.height * 0.9);
            else if (event.key === Qt.Key_PageUp) go(scroller.contentY - scroller.height * 0.9);
            else if (event.key === Qt.Key_Home) go(top);
            else if (event.key === Qt.Key_End) go(max);
            else if (event.matches(StandardKey.Copy)) reader.copySelection();
            else if (event.matches(StandardKey.SelectAll)) reader.selectAllText();
            else if (event.key === Qt.Key_Escape && page.hasSelection) page.clearSelection();
            else if (event.key === Qt.Key_Escape) reader.leave();
            else if (plain && event.key === Qt.Key_R) reader.reply();
            else if (plain && event.key === Qt.Key_A) reader.replyAll();
            else if (plain && event.key === Qt.Key_F) reader.forward();
            else if (plain && event.key === Qt.Key_E) reader.act("archive");
            else if (plain && (event.key === Qt.Key_NumberSign || event.key === Qt.Key_Delete)) reader.act("trash");
            else if (plain && event.key === Qt.Key_S) reader.act(reader.starred ? "unstar" : "star");
            else if (plain && event.key === Qt.Key_U) reader.act(reader.unread ? "read" : "unread");
            else return;
            event.accepted = true;
        }

        Column {
            id: content
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
                            // Stops short of the Unsubscribe button, elided when the window is narrow
                            width: Math.max(0, parent.width - x - unsubscribeButton.width - 2 * FiliTheme.space2)
                            elide: Text.ElideRight
                            text: Facteur.tr("This message comes from a mailing list.")
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.sizeList
                            color: FiliTheme.textSecondary
                        }
                        TextButton {
                            id: unsubscribeButton
                            anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                            label: Facteur.tr("Unsubscribe")
                            onClicked: reader.unsubscribe(reader.unsubscribeUrl)
                        }
                    }
                    Flow {
                        visible: reader.attachments.length > 0
                        width: parent.width
                        spacing: FiliTheme.space2
                        Repeater {
                            model: reader.attachments
                            Rectangle {
                                required property var modelData
                                required property int index
                                activeFocusOnTab: !!modelData.attachmentId
                                Keys.onReturnPressed: reader.openAttachment(index)
                                Keys.onEnterPressed: reader.openAttachment(index)
                                Keys.onSpacePressed: reader.openAttachment(index)
                                FocusRing {}
                                width: Math.min(chipText.implicitWidth + 2 * FiliTheme.space3 + 14 + FiliTheme.space2 + 28, content.width)
                                height: 28
                                radius: FiliTheme.radiusControl
                                color: chipArea.containsMouse ? FiliTheme.surfaceHover : FiliTheme.surface
                                border.width: FiliTheme.borderWidth
                                border.color: FiliTheme.border
                                Icon { x: FiliTheme.space3; anchors.verticalCenter: parent.verticalCenter; name: "archive"; size: 14; color: FiliTheme.textSecondary }
                                Text {
                                    id: chipText
                                    x: FiliTheme.space3 + 14 + FiliTheme.space2
                                    width: parent.width - x - FiliTheme.space3 - 28
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.filename + "  ·  " + reader.sizeText(modelData.size)
                                    elide: Text.ElideMiddle
                                    font.family: FiliTheme.font
                                    font.pixelSize: FiliTheme.sizeList
                                    color: modelData.attachmentId ? FiliTheme.text : FiliTheme.muted
                                }
                                MouseArea {
                                    id: chipArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !!modelData.attachmentId
                                    onClicked: reader.openAttachment(index)
                                }
                                // Save to the Downloads folder without opening
                                IconButton {
                                    anchors { right: parent.right; rightMargin: 2; verticalCenter: parent.verticalCenter }
                                    name: "download"
                                    tip: Facteur.tr("Download")
                                    enabledState: !!modelData.attachmentId
                                    onClicked: if (modelData.attachmentId) reader.saveAttachment(index)
                                }
                            }
                        }
                        TextButton {
                            visible: reader.attachments.filter(a => !!a.attachmentId).length > 1
                            label: Facteur.tr("Download all")
                            onClicked: reader.saveAllAttachments()
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
                id: paper
                visible: reader.html !== ""
                width: parent.width
                height: page.contentHeight + 2 * FiliTheme.space3
                radius: FiliTheme.radiusControl
                color: "#ffffff"
                clip: true
                // Only the visible slice of the page is drawn: the view follows the scroll
                readonly property real sliceTop: Math.max(0, Math.min(page.contentHeight, scroller.contentY - content.y - paper.y - FiliTheme.space3))
                HtmlView {
                    id: page
                    x: FiliTheme.space3
                    y: FiliTheme.space3 + paper.sliceTop
                    width: parent.width - 2 * FiliTheme.space3
                    height: Math.max(1, Math.min(scroller.height, page.contentHeight - paper.sliceTop))
                    viewportY: paper.sliceTop
                    html: reader.html
                    fontFamily: FiliTheme.font
                    fontSize: FiliTheme.size
                    onLinkActivated: url => Qt.openUrlExternally(url)
                    onHoveredLinkChanged: reader.hovered = hoveredLink
                    onContextMenuRequested: (x, y, link, image) => {
                        const p = page.mapToItem(null, x, y);
                        reader.pageMenu(p.x, p.y, link, image);
                    }
                }
            }
            Rectangle {
                visible: reader.html === "" && reader.rich !== ""
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
                visible: reader.rich === "" && reader.html === ""
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
    FocusRing { target: scroller; gap: -2; shown: scroller.activeFocus }
    FiliScrollBar {
        flick: scroller
        visible: needed && reader.summary !== null
        anchors { top: scroller.top; bottom: scroller.bottom; right: scroller.right }
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
