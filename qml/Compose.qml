// New message, reply or forward: a card at the bottom right of the window (the message list stays visible behind it),
// as mail clients do. Header with minimise, expand and close; From, To (with Cc / Bcc shown on demand), Subject,
// body written as rich text (HTML, the default) or as plain text (switchable), attached files, and a footer with discard, attach and Send.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import Fili.Mail
import Fili.Html

Rectangle {
    id: compose
    property bool busy: false
    property string error: ""
    // Sender shown on the first line (the account)
    property string from: ""
    // Threading of a reply (Message-ID answered, References chain); empty otherwise
    property string inReplyTo: ""
    property string references: ""
    // Files to attach: {path, name}
    property var files: []
    // Several cards live side by side: the window decides which one is open (the others are reduced to their bar)
    property bool minimized: false
    // This card has the keyboard shortcuts
    property bool current: false
    property string draftKey: ""
    // Every draft being written ({key, title}): they are the tabs of the header; `draftKey` is the one this card holds
    property var tabs: null
    property int tabCount: 1
    readonly property string title: subject.text.trim()
    signal tabChosen(string key)
    signal tabClosed(string key)
    signal newRequested()
    onCurrentChanged: if (current && !minimized) Qt.callLater(() => { if (to.text === "") to.forceActiveFocus(); else body.forceActiveFocus() })
    property bool expanded: false
    // The draft kept on this computer as it is typed; the time of the last copy ("" while there is none)
    property string savedAt: ""
    property bool loaded: false
    property bool showCc: false
    property bool showBcc: false
    // The body is edited as rich text (what you see is what is sent: text + HTML alternatives); false: plain text only
    property bool html: true
    function escapeHtml(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
    function paragraphs(t) {
        return t.replace(/^\n+|\n+$/g, "").split(/\n{2,}/).filter(p => p.trim() !== "").map(p => "<p>" + escapeHtml(p).replace(/\n/g, "<br>\n") + "</p>").join("\n");
    }
    // Plain text to HTML: paragraphs, and the lines quoted with ">" (a reply) become a quotation block
    function textToHtml(t) {
        if (t.trim() === "") return "";
        const lines = t.replace(/\r\n/g, "\n").split("\n");
        const out = [];
        // A message starting with a blank line keeps an empty line to type on, above the quotation
        if (lines[0].trim() === "") out.push("<p><br></p>");
        let cur = [], quote = false;
        const flush = () => {
            if (cur.length === 0) return;
            const text = (quote ? cur.map(l => l.replace(/^\s*>[ ]?/, "")) : cur).join("\n");
            const html = paragraphs(text);
            if (html !== "") out.push(quote ? "<blockquote>" + html + "</blockquote>" : html);
            cur = [];
        };
        for (const l of lines) {
            const q = /^\s*>/.test(l);
            if (q !== quote) { flush(); quote = q }
            cur.push(l);
        }
        flush();
        return out.join("\n");
    }
    // Message being answered: kept apart from what is typed, hidden behind a "…" button, appended when sending.
    // quoteHeader: "On <date>, <sender> wrote:"; quoteText: the message as text; quoteHtml: its sanitized HTML (may be empty)
    property string quoteHeader: ""
    property string quoteText: ""
    property string quoteHtml: ""
    property bool quoteShown: false
    readonly property bool hasQuote: quoteText !== "" || quoteHtml !== ""
    // The quoted message as HTML (its own page when it has one, else its text in paragraphs)
    function quoteBodyHtml() {
        if (quoteHtml !== "") {
            const m = /<body[^>]*>([\s\S]*)<\/body>/i.exec(quoteHtml);
            return m ? m[1] : quoteHtml;
        }
        return paragraphs(quoteText);
    }
    function quotedText(t) { return t.split("\n").map(l => l === "" ? ">" : "> " + l).join("\n") }
    // What goes out: the typed message followed by the quotation
    function outgoing() {
        const f = fields();
        delete f.files;
        if (!hasQuote) return f;
        f.body = f.body.replace(/\s+$/, "") + "\n\n" + quoteHeader + "\n" + quotedText(quoteText);
        if (html) {
            const block = "<div>" + escapeHtml(quoteHeader) + "</div><blockquote style=\"margin:0 0 0 0.8ex;border-left:1px solid #ccc;padding-left:1ex\">" + quoteBodyHtml() + "</blockquote>";
            const end = f.html.lastIndexOf("</body>");
            f.html = end >= 0 ? f.html.slice(0, end) + block + f.html.slice(end) : f.html + block;
        }
        return f;
    }
    // The typed text, whatever the mode
    function plainBody() { return html ? body.getText(0, body.length).replace(/[\u2028\u2029]/g, "\n") : body.text }
    // The editor's HTML without its own font choices (family, size): the reader's defaults apply
    function cleanHtml(h) {
        return h.replace(/font-family:[^;"]*;\s*/g, "").replace(/font-size:[^;"]*;\s*/g, "").replace(/font-weight:400;\s*/g, "").replace(/font-style:normal;\s*/g, "");
    }
    // Switching keeps what was typed (the formatting is lost going to plain text)
    function setHtml(on) {
        if (on === html) return;
        const plain = plainBody();
        html = on;
        body.text = on ? textToHtml(plain) : plain;
        body.forceActiveFocus();
        changed();
    }
    // Bold, italic, underline on the selection (or on what is typed next)
    function toggleFormat(prop) {
        const f = body.cursorSelection.font;
        const next = {};
        next[prop] = !f[prop];
        body.cursorSelection.font = Qt.font(next);
        body.forceActiveFocus();
    }
    function align(a) { body.cursorSelection.alignment = a; body.forceActiveFocus() }
    function addFiles(urls) {
        const next = files.slice();
        for (const u of urls) {
            const path = decodeURIComponent(u.toString().replace(/^file:\/\//, ""));
            if (!next.some(f => f.path === path))
                next.push({ path: path, name: path.split("/").pop() });
        }
        files = next;
    }

    // Recipient suggestions: the address book is read once, when the card is first used
    property var book: null
    property Item suggestField: null
    property var matches: []
    property int pick: 0
    function suggest(field) {
        if (book === null) {
            try { book = JSON.parse(Facteur.contacts()) } catch (e) { book = [] }
        }
        const t = field.text;
        const cut = Math.max(t.lastIndexOf(","), t.lastIndexOf(";"));
        const part = t.slice(cut + 1).trim().toLowerCase();
        if (part.length < 2) { hideSuggest(); return }
        const starts = [], inside = [];
        for (const c of book) {
            const name = (c.name || "").toLowerCase(), mail = (c.email || "").toLowerCase();
            if (mail.startsWith(part) || name.startsWith(part)) starts.push(c);
            else if (mail.includes(part) || name.includes(part)) inside.push(c);
        }
        matches = starts.concat(inside).slice(0, 6);
        pick = 0;
        suggestField = matches.length > 0 ? field : null;
    }
    function hideSuggest() { suggestField = null; matches = [] }
    function accept(index) {
        const f = suggestField;
        if (!f || index < 0 || index >= matches.length) return;
        const cut = Math.max(f.text.lastIndexOf(","), f.text.lastIndexOf(";"));
        f.text = f.text.slice(0, cut + 1) + (cut >= 0 ? " " : "") + matches[index].email + ", ";
        f.cursorPosition = f.text.length;
        hideSuggest();
    }
    // Arrow keys move in the list, Enter and Tab take the highlighted address, Escape closes the list
    function suggestKey(field, event) {
        if (suggestField !== field || matches.length === 0) return false;
        if (event.key === Qt.Key_Down) pick = (pick + 1) % matches.length;
        else if (event.key === Qt.Key_Up) pick = (pick + matches.length - 1) % matches.length;
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) accept(pick);
        else if (event.key === Qt.Key_Escape) hideSuggest();
        else return false;
        return true;
    }

    signal submitted(var fields)
    // Closed with the draft kept (Escape, close button) or thrown away (trash)
    signal cancelled()
    signal discarded()
    // The bar was clicked: open or reduce this card
    signal minimizeToggled()
    signal activate()
    // The form changed and rests for a moment: the draft to keep
    signal edited(var fields)

    function fields() {
        return { to: to.text, cc: cc.text, bcc: bcc.text, subject: subject.text, body: plainBody(), html: html ? cleanHtml(body.text) : "", textMode: !html, quoteHeader: quoteHeader, quoteText: quoteText, quoteHtml: quoteHtml, inReplyTo: inReplyTo, references: references, files: files };
    }
    // Nothing typed: no draft to keep
    function isEmpty() {
        return to.text.trim() === "" && cc.text.trim() === "" && bcc.text.trim() === "" && subject.text.trim() === "" && plainBody().trim() === "" && files.length === 0;
    }
    function changed() { if (loaded) { savedAt = ""; keep.restart() } }
    Timer { id: keep; interval: 1500; onTriggered: if (!compose.busy) compose.edited(compose.fields()) }
    onFilesChanged: changed()

    // Fill the form and put the cursor where typing starts
    function open(draft, focus) {
        loaded = false;
        to.text = draft.to || "";
        cc.text = draft.cc || "";
        bcc.text = draft.bcc || "";
        showCc = cc.text !== "";
        showBcc = bcc.text !== "";
        subject.text = draft.subject || "";
        quoteHeader = draft.quoteHeader || "";
        quoteText = draft.quoteText || "";
        quoteHtml = draft.quoteHtml || "";
        quoteShown = false;
        html = !draft.textMode;
        body.text = !html ? (draft.body || "") : (draft.html || textToHtml(draft.body || ""));
        inReplyTo = draft.inReplyTo || "";
        references = draft.references || "";
        files = draft.files || [];
        error = "";
        loaded = true;
        if (focus === false) return;
        if (to.text === "") to.forceActiveFocus(); else { body.forceActiveFocus(); body.cursorPosition = 0 }
    }
    function submit() {
        if (busy) return;
        if (to.text.trim() === "" && cc.text.trim() === "" && bcc.text.trim() === "") {
            error = Facteur.tr("Add at least one recipient.");
            return;
        }
        const f = outgoing();
        f.attachments = files.map(a => ({ path: a.path, name: a.name, size: 0 }));
        submitted(f);
    }

    // The card sits in a dock: its room is `room` (the window) minus the margins
    property real roomWidth: 800
    property real roomHeight: 600
    width: minimized ? Math.min(roomWidth - 2 * FiliTheme.margin, Math.max(300, tabCount * 150 + 120)) : Math.min(expanded ? roomWidth - 2 * FiliTheme.margin : 640, roomWidth - 2 * FiliTheme.margin)
    height: minimized ? head.height : Math.min(expanded ? roomHeight - 2 * FiliTheme.margin : 580, roomHeight - 2 * FiliTheme.margin)
    radius: FiliTheme.radiusWindow
    color: FiliTheme.surface
    border.width: FiliTheme.borderWidth
    border.color: FiliTheme.border
    clip: true

    Keys.onEscapePressed: compose.cancelled()
    Shortcut { sequences: ["Ctrl+Return", "Ctrl+Enter"]; enabled: compose.current && !compose.minimized; onActivated: compose.submit() }
    Shortcut { sequences: ["Ctrl+Shift+C"]; enabled: compose.current && !compose.minimized; onActivated: { compose.showCc = true; cc.forceActiveFocus() } }
    Shortcut { sequences: ["Ctrl+Shift+B"]; enabled: compose.current && !compose.minimized; onActivated: { compose.showBcc = true; bcc.forceActiveFocus() } }
    Shortcut { sequences: ["Ctrl+Shift+H"]; enabled: compose.current && !compose.minimized; onActivated: compose.setHtml(!compose.html) }
    Shortcut { sequences: ["Ctrl+M"]; enabled: compose.current; onActivated: compose.minimizeToggled() }

    // A field of the card: no frame, a line under it
    component Line: TextField {
        id: f
        width: parent.width
        height: 40
        leftPadding: 0
        rightPadding: 0
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.size
        color: FiliTheme.text
        placeholderTextColor: FiliTheme.muted
        selectionColor: FiliTheme.surfaceActive
        selectedTextColor: FiliTheme.text
        enabled: !compose.busy
        // To, Cc and Bcc suggest addresses while typing
        property bool recipient: false
        onTextChanged: compose.changed()
        onTextEdited: if (recipient) compose.suggest(f)
        onActiveFocusChanged: if (!activeFocus && compose.suggestField === f) compose.hideSuggest()
        Keys.onPressed: event => { if (recipient && compose.suggestKey(f, event)) event.accepted = true }
        background: Rectangle {
            color: "transparent"
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: f.activeFocus ? 2 : FiliTheme.borderWidth; color: f.activeFocus ? FiliTheme.accentColor : FiliTheme.border }
        }
    }

    // Header: title (the subject once there is one), minimise, expand, close
    Rectangle {
        id: head
        width: parent.width
        height: 44
        color: FiliTheme.backgroundDeep
        // One draft: its title. Several: a tab each, the open one lit, a cross to close it (the draft is kept), and a plus
        Text {
            visible: compose.tabCount < 2
            anchors { left: parent.left; leftMargin: FiliTheme.margin; right: controls.left; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
            text: subject.text.trim() !== "" ? subject.text : Facteur.tr("New message")
            elide: Text.ElideRight
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
            font.weight: FiliTheme.weightAccent
            color: FiliTheme.text
        }
        MouseArea { anchors.fill: parent; onClicked: if (compose.minimized) compose.minimizeToggled(); onDoubleClicked: if (!compose.minimized) compose.minimizeToggled() }
        Row {
            id: tabRow
            visible: compose.tabCount > 1
            anchors { left: parent.left; leftMargin: FiliTheme.space3; right: controls.left; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
            spacing: FiliTheme.space1
            readonly property real tabWidth: Math.max(80, Math.min(170, (width - plus.width - FiliTheme.space1) / Math.max(1, compose.tabCount) - FiliTheme.space1))
            Repeater {
                model: compose.tabs
                Rectangle {
                    required property string key
                    required property string title
                    readonly property bool on: key === compose.draftKey
                    width: tabRow.tabWidth
                    height: 30
                    radius: FiliTheme.radiusControl
                    color: on && !compose.minimized ? FiliTheme.surfaceActive : tabArea.containsMouse ? FiliTheme.surfaceHover : "transparent"
                    MouseArea { id: tabArea; anchors.fill: parent; hoverEnabled: true; onClicked: compose.tabChosen(key) }
                    Text {
                        anchors { left: parent.left; leftMargin: FiliTheme.space3; right: closeTab.left; rightMargin: FiliTheme.space1; verticalCenter: parent.verticalCenter }
                        text: title !== "" ? title : Facteur.tr("New message")
                        elide: Text.ElideRight
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeList
                        font.weight: on ? FiliTheme.weightAccent : Font.Normal
                        color: on ? FiliTheme.text : FiliTheme.textSecondary
                    }
                    IconButton {
                        id: closeTab
                        name: "x"
                        width: 22; height: 22
                        anchors { right: parent.right; rightMargin: 2; verticalCenter: parent.verticalCenter }
                        tip: Facteur.tr("Close (the draft is kept)")
                        onClicked: compose.tabClosed(key)
                    }
                }
            }
            IconButton { id: plus; name: "plus"; tip: Facteur.tr("New message"); onClicked: compose.newRequested() }
        }
        Row {
            id: controls
            anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
            spacing: 2
            IconButton { name: compose.minimized ? "chevron-up" : "minus"; tip: compose.minimized ? Facteur.tr("Restore") : Facteur.tr("Minimise"); onClicked: compose.minimizeToggled() }
            IconButton { visible: !compose.minimized; name: compose.expanded ? "minimize-2" : "maximize"; tip: compose.expanded ? Facteur.tr("Reduce") : Facteur.tr("Expand"); onClicked: compose.expanded = !compose.expanded }
            IconButton { name: "x"; tip: Facteur.tr("Close (the draft is kept)"); onClicked: if (!compose.busy) compose.cancelled() }
        }
    }

    Column {
        id: form
        visible: !compose.minimized
        anchors { left: parent.left; right: parent.right; top: head.bottom; leftMargin: FiliTheme.margin; rightMargin: FiliTheme.margin; topMargin: FiliTheme.space2 }
        spacing: 0
        Item {
            width: parent.width
            height: 40
            Text { id: fromLabel; anchors.verticalCenter: parent.verticalCenter; text: Facteur.tr("From"); font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.muted }
            Text { anchors { left: fromLabel.right; leftMargin: FiliTheme.space3; right: parent.right; verticalCenter: parent.verticalCenter } text: compose.from; elide: Text.ElideRight; font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.text }
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: FiliTheme.borderWidth; color: FiliTheme.border }
        }
        Item {
            width: parent.width
            height: 40
            Line { id: to; recipient: true; placeholderText: Facteur.tr("To"); anchors { left: parent.left; right: ccToggles.left; rightMargin: FiliTheme.space2 } width: undefined; KeyNavigation.tab: compose.showCc ? cc : compose.showBcc ? bcc : subject }
            Row {
                id: ccToggles
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: FiliTheme.space3
                Text { text: "CC"; visible: !compose.showCc; font.family: FiliTheme.font; font.pixelSize: FiliTheme.sizeList; font.weight: FiliTheme.weightAccent; color: FiliTheme.textSecondary; MouseArea { anchors { fill: parent; margins: -4 } onClicked: compose.showCc = true } }
                Text { text: "BCC"; visible: !compose.showBcc; font.family: FiliTheme.font; font.pixelSize: FiliTheme.sizeList; font.weight: FiliTheme.weightAccent; color: FiliTheme.textSecondary; MouseArea { anchors { fill: parent; margins: -4 } onClicked: compose.showBcc = true } }
            }
        }
        Line { id: cc; recipient: true; visible: compose.showCc; placeholderText: Facteur.tr("Cc"); KeyNavigation.tab: compose.showBcc ? bcc : subject }
        Line { id: bcc; recipient: true; visible: compose.showBcc; placeholderText: Facteur.tr("Bcc"); KeyNavigation.tab: subject }
        Line { id: subject; placeholderText: Facteur.tr("Subject"); KeyNavigation.tab: body }
    }

    // Suggestions under the field being typed in
    Rectangle {
        id: suggestions
        visible: compose.suggestField !== null && compose.matches.length > 0
        z: 50
        property point at: compose.suggestField ? compose.suggestField.mapToItem(compose, 0, compose.suggestField.height) : Qt.point(0, 0)
        x: at.x
        y: at.y
        width: compose.suggestField ? compose.suggestField.width : 0
        height: compose.matches.length * 32 + 2
        radius: FiliTheme.radiusControl
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: FiliTheme.border
        Column {
            anchors { fill: parent; margins: 1 }
            Repeater {
                model: compose.matches
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 32
                    radius: FiliTheme.radiusControl
                    color: index === compose.pick ? FiliTheme.surfaceHover : "transparent"
                    Text {
                        anchors { left: parent.left; right: parent.right; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                        text: modelData.name ? modelData.name + "  " + modelData.email : modelData.email
                        elide: Text.ElideRight
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.sizeList
                        color: FiliTheme.text
                    }
                    MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: compose.pick = index; onClicked: compose.accept(index) }
                }
            }
        }
    }

    // Formatting bar (rich text mode)
    Row {
        id: fmtBar
        visible: compose.html && !compose.minimized
        anchors { left: parent.left; top: form.bottom; leftMargin: FiliTheme.margin; topMargin: FiliTheme.space1 }
        height: visible ? 24 : 0
        spacing: 2
        TextButton { label: "B"; primary: body.cursorSelection.font.bold; onClicked: compose.toggleFormat("bold") }
        TextButton { label: "I"; primary: body.cursorSelection.font.italic; onClicked: compose.toggleFormat("italic") }
        TextButton { label: "U"; primary: body.cursorSelection.font.underline; onClicked: compose.toggleFormat("underline") }
        Item { width: FiliTheme.space2; height: 1 }
        TextButton { label: "←"; onClicked: compose.align(Qt.AlignLeft) }
        TextButton { label: "↔"; onClicked: compose.align(Qt.AlignHCenter) }
        TextButton { label: "→"; onClicked: compose.align(Qt.AlignRight) }
    }
    Shortcut { sequence: "Ctrl+B"; enabled: compose.current && !compose.minimized && compose.html; onActivated: compose.toggleFormat("bold") }
    Shortcut { sequence: "Ctrl+I"; enabled: compose.current && !compose.minimized && compose.html; onActivated: compose.toggleFormat("italic") }
    Shortcut { sequence: "Ctrl+U"; enabled: compose.current && !compose.minimized && compose.html; onActivated: compose.toggleFormat("underline") }

    // Body
    Flickable {
        id: bodyScroll
        visible: !compose.minimized
        anchors { left: parent.left; right: parent.right; top: fmtBar.visible ? fmtBar.bottom : form.bottom; bottom: chips.visible ? chips.top : footer.top; leftMargin: FiliTheme.margin; rightMargin: FiliTheme.margin; topMargin: FiliTheme.space2; bottomMargin: FiliTheme.space2 }
        clip: true
        contentWidth: width
        contentHeight: Math.max(height, body.height + quoteBox.height + FiliTheme.space2)
        boundsBehavior: Flickable.StopAtBounds
        KineticScroll {}
        // The caret stays in view while typing
        function ensureVisible(r) {
            if (r.y < contentY) contentY = r.y;
            else if (r.y + r.height > contentY + height) contentY = r.y + r.height - height;
        }
        TextArea {
            id: body
            width: bodyScroll.width - 14
            // The minimum leaves room for the "…" button only: using quoteBox.height would loop (the quotation's page is placed from body.height)
            height: Math.max(implicitHeight, bodyScroll.height - (compose.hasQuote ? 20 + FiliTheme.space2 : 0) - FiliTheme.space2)
            enabled: !compose.busy
            wrapMode: TextEdit.Wrap
            font.family: FiliTheme.font
            textFormat: compose.html ? TextEdit.RichText : TextEdit.PlainText
            font.pixelSize: FiliTheme.size
            color: FiliTheme.text
            selectionColor: FiliTheme.surfaceActive
            selectedTextColor: FiliTheme.text
            background: null
            padding: 0
            onCursorRectangleChanged: bodyScroll.ensureVisible(cursorRectangle)
            onTextChanged: compose.changed()
            KeyNavigation.priority: KeyNavigation.BeforeItem
            KeyNavigation.tab: to
        }
        // The message answered: a "…" button, which opens it below what is typed
        Column {
            id: quoteBox
            visible: compose.hasQuote
            y: body.height + FiliTheme.space2
            width: bodyScroll.width - 14
            height: visible ? implicitHeight : 0
            spacing: FiliTheme.space2
            Rectangle {
                width: 32
                height: 20
                radius: FiliTheme.radiusControl
                color: dots.pressed ? FiliTheme.surfaceActive : dots.containsMouse ? FiliTheme.surfaceHover : "transparent"
                border.width: FiliTheme.borderWidth
                border.color: FiliTheme.border
                Icon { anchors.centerIn: parent; name: "more"; size: 14; color: FiliTheme.textSecondary }
                MouseArea { id: dots; anchors.fill: parent; hoverEnabled: true; onClicked: compose.quoteShown = !compose.quoteShown }
                ToolTip.visible: dots.containsMouse
                ToolTip.text: Facteur.tr("Show the quoted message")
            }
            Text {
                visible: compose.quoteShown
                width: parent.width
                text: compose.quoteHeader
                wrapMode: Text.Wrap
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                color: FiliTheme.textSecondary
            }
            // Quotation: bar on the left, the original page on paper (senders choose their colors for a white page)
            Item {
                id: quote
                visible: compose.quoteShown
                width: parent.width
                height: visible ? (compose.quoteHtml !== "" ? page.contentHeight + 2 * FiliTheme.space2 : plain.implicitHeight + 2 * FiliTheme.space2) : 0
                Rectangle { id: bar; width: 3; height: parent.height; radius: 1; color: FiliTheme.border }
                Rectangle {
                    id: paper
                    anchors { left: bar.right; leftMargin: FiliTheme.space2; right: parent.right }
                    height: parent.height
                    radius: FiliTheme.radiusControl
                    color: compose.quoteHtml !== "" ? "#ffffff" : "transparent"
                    clip: true
                    // Only the visible slice of the page is drawn: the view follows the scroll
                    readonly property real sliceTop: Math.max(0, Math.min(page.contentHeight, bodyScroll.contentY - quoteBox.y - quote.y - FiliTheme.space2))
                    HtmlView {
                        id: page
                        visible: compose.quoteHtml !== ""
                        x: FiliTheme.space2
                        y: FiliTheme.space2 + paper.sliceTop
                        width: parent.width - 2 * FiliTheme.space2
                        height: Math.max(1, Math.min(bodyScroll.height, page.contentHeight - paper.sliceTop))
                        viewportY: paper.sliceTop
                        html: compose.quoteShown ? compose.quoteHtml : ""
                        fontFamily: FiliTheme.font
                        fontSize: FiliTheme.size
                        onLinkActivated: url => Qt.openUrlExternally(url)
                    }
                    Text {
                        id: plain
                        visible: compose.quoteHtml === ""
                        x: FiliTheme.space2
                        y: FiliTheme.space2
                        width: parent.width - 2 * FiliTheme.space2
                        text: compose.quoteText
                        wrapMode: Text.Wrap
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.size
                        color: FiliTheme.textSecondary
                    }
                }
            }
        }
    }
    FiliScrollBar {
        flick: bodyScroll
        visible: needed && !compose.minimized
        anchors { top: bodyScroll.top; bottom: bodyScroll.bottom; right: bodyScroll.right }
    }

    FileDialog {
        id: picker
        title: Facteur.tr("Attach files")
        fileMode: FileDialog.OpenFiles
        onAccepted: compose.addFiles(selectedFiles)
    }
    Shortcut { sequence: "Ctrl+Shift+U"; enabled: compose.current && !compose.minimized; onActivated: picker.open() }

    // Attached files, one chip each (click removes it)
    Flow {
        id: chips
        visible: !compose.minimized && compose.files.length > 0
        anchors { left: parent.left; right: parent.right; bottom: footer.top; leftMargin: FiliTheme.margin; rightMargin: FiliTheme.margin; bottomMargin: FiliTheme.space2 }
        spacing: FiliTheme.space2
        Repeater {
            model: compose.files
            Rectangle {
                required property var modelData
                width: Math.min(chipLabel.implicitWidth + 2 * FiliTheme.space3 + 14 + FiliTheme.space2, chips.width)
                height: 26
                radius: FiliTheme.radiusControl
                color: chipArea.containsMouse ? FiliTheme.surfaceHover : FiliTheme.backgroundDeep
                border.width: FiliTheme.borderWidth
                border.color: FiliTheme.border
                Text {
                    id: chipLabel
                    x: FiliTheme.space3
                    width: parent.width - 2 * FiliTheme.space3 - 14 - FiliTheme.space2
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    elide: Text.ElideMiddle
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeList
                    color: FiliTheme.text
                }
                Text { anchors { right: parent.right; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter } text: "×"; font.pixelSize: FiliTheme.size; color: FiliTheme.textSecondary }
                ToolTip.visible: chipArea.containsMouse
                ToolTip.text: Facteur.tr("Remove attachment")
                MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; onClicked: compose.files = compose.files.filter(f => f.path !== modelData.path) }
            }
        }
    }

    // Footer: discard and attach on the left, the state and Send on the right
    Rectangle {
        id: footer
        visible: !compose.minimized
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 52
        color: FiliTheme.surface
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: FiliTheme.borderWidth; color: FiliTheme.border }
        Row {
            anchors { left: parent.left; leftMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
            spacing: 2
            IconButton { name: "trash"; tip: Facteur.tr("Discard"); onClicked: if (!compose.busy) compose.discarded() }
            IconButton { name: "paperclip"; tip: Facteur.tr("Attach files"); onClicked: if (!compose.busy) picker.open() }
            Item { width: FiliTheme.space2; height: 1 }
            // Body format: rich text (HTML) or plain text
            TextButton { anchors.verticalCenter: parent.verticalCenter; label: Facteur.tr("Text"); primary: !compose.html; onClicked: if (!compose.busy) compose.setHtml(false) }
            TextButton { anchors.verticalCenter: parent.verticalCenter; label: "HTML"; primary: compose.html; onClicked: if (!compose.busy) compose.setHtml(true) }
        }
        Text {
            anchors { right: sendButton.left; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
            width: Math.max(0, parent.width - 2 * 80 - sendButton.width - FiliTheme.space4)
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            text: compose.error !== "" ? compose.error : (compose.files.length > 0 ? Facteur.tr("%1 attached").replace("%1", compose.files.length) + "  ·  " : "") + (compose.savedAt !== "" ? Facteur.tr("Draft saved") : "")
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeList
            color: compose.error !== "" ? FiliTheme.danger : FiliTheme.textSecondary
        }
        Rectangle {
            id: sendButton
            anchors { right: parent.right; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
            width: sendText.implicitWidth + 2 * FiliTheme.space5
            height: 32
            radius: FiliTheme.radiusControl
            color: sendArea.pressed ? Qt.darker(FiliTheme.accentColor, 1.2) : sendArea.containsMouse ? FiliTheme.accentBright : FiliTheme.accentColor
            opacity: compose.busy ? 0.6 : 1
            Text { id: sendText; anchors.centerIn: parent; text: compose.busy ? Facteur.tr("Sending…") : Facteur.tr("Send"); font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; font.weight: FiliTheme.weightAccent; color: FiliTheme.accentColor.hslLightness > 0.55 ? "#1a1a1a" : "#ffffff" }
            MouseArea { id: sendArea; anchors.fill: parent; hoverEnabled: true; onClicked: compose.submit() }
        }
    }
}
