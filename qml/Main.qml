// Window of Facteur: sidebar (accounts, mailboxes), message list, reader. Without an account, the window is the account form.
import QtQuick
import QtQuick.Controls.Basic
import Fili.Mail

ApplicationWindow {
    id: win
    // Fonts embedded in the binary (fonts/, licenses/): same look on every distribution
    FontLoader { source: "qrc:/qt/qml/Fili/Mail/fonts/Jost-Variable.ttf" }
    FontLoader { source: "qrc:/qt/qml/Fili/Mail/fonts/JetBrainsMono-Variable.ttf" }
    FontLoader { source: "qrc:/qt/qml/Fili/Mail/fonts/FiliIcons.ttf" }
    width: 1000
    height: 640
    minimumWidth: 640
    minimumHeight: 360
    visible: true
    color: FiliTheme.background
    title: "Facteur"

    property var accounts: []
    property string account: ""
    property string mailbox: "inbox"
    // Reader beside the list ("right", default) or under it ("below"); the choice is kept
    property string preview: Facteur.uiGet("preview") === "below" ? "below" : "right"
    function togglePreview() {
        preview = preview === "below" ? "right" : "below";
        Facteur.uiSet("preview", preview);
    }
    // A label (Gmail) is a mailbox named "label:NAME": it lists everything carrying it except spam and trash
    property var labels: []
    function listBox() { return mailbox.startsWith("label:") ? "archive" : mailbox; }
    // Gmail sorts the inbox in categories (tabs above the list)
    property string category: "primary"
    readonly property var categories: [
        { key: "primary", label: Facteur.tr("Primary") },
        { key: "promotions", label: Facteur.tr("Promotions") },
        { key: "social", label: Facteur.tr("Social") },
        { key: "updates", label: Facteur.tr("Updates") },
        { key: "forums", label: Facteur.tr("Forums") }
    ]
    function isGmail() { const a = accounts.find(x => x.id === account); return !!a && a.provider === "gmail"; }
    function categoriesOn() { return mailbox === "inbox" && isGmail(); }
    function listQuery() {
        if (mailbox.startsWith("label:")) return ("label:\"" + mailbox.slice(6) + "\" " + query).trim();
        if (categoriesOn()) return ("category:" + category + " " + query).trim();
        return query;
    }
    // Right click in the sidebar: an account (edit, remove) or a label (edit, delete)
    property var contextData: null
    property string contextKind: ""
    property var deletingLabel: null
    function openContext(kind, data, x, y) {
        contextKind = kind;
        contextData = data;
        const entries = kind === "account"
            ? [{ id: "edit", label: Facteur.tr("Edit account…") }, { id: "remove", label: Facteur.tr("Remove account…"), danger: true }]
            : [{ id: "edit", label: Facteur.tr("Edit label…") }, { id: "delete", label: Facteur.tr("Delete label…"), danger: true }];
        popup.openAt(x, y, entries);
    }
    function runContext(id) {
        if (contextKind === "account") {
            if (id === "remove") { removing = contextData.id; return; }
            const d = JSON.parse(Facteur.accountDetails(contextData.id));
            if (d.error) { notice = errorText(d.error); return; }
            accountDialog.edit(d);
        } else if (id === "edit") {
            labelDialog.edit(contextData);
        } else {
            deletingLabel = contextData;
        }
    }
    function loadLabels() {
        labels = [];
        const a = accounts.find(x => x.id === account);
        if (a && a.provider === "gmail") Facteur.loadLabels(account);
    }
    // Search text applied to the list (typed text waits a moment in the toolbar field)
    property string query: ""
    // Places visited (account, mailbox, search) for the back and forward buttons
    property var history: []
    property int hindex: -1
    property bool navigating: false
    property bool adding: false
    property bool addBusy: false
    property string addError: ""
    property string selectedId: ""
    property string listError: ""
    property bool loading: false
    // Account the user is asked to confirm the removal of
    property string removing: ""
    // A short word under the list when an action failed
    property string notice: ""

    // Message being written (the pane next to the list shows the form instead of the reader)
    property bool composing: false
    property bool sending: false

    ListModel { id: messages }

    function quoted(text) {
        return text.split("\n").map(l => l === "" ? ">" : "> " + l).join("\n");
    }
    function sender() {
        const f = reader.summary.from;
        return f.display ? f.display + " <" + f.email + ">" : f.email;
    }
    // kind: "new", "reply" or "forward"
    function startCompose(kind) {
        if (account === "" || (kind !== "new" && reader.summary === null))
            return;
        let draft = {};
        if (kind === "reply") {
            const s = reader.summary;
            draft = {
                to: s.from.email,
                subject: /^re:/i.test(s.subject) ? s.subject : "Re: " + s.subject,
                body: "\n\n" + Facteur.tr("%1 wrote:").replace("%1", sender()) + "\n" + quoted(reader.body)
            };
        } else if (kind === "replyall") {
            const s = reader.summary;
            const self = account.replace(/^[a-z]+:/, "").toLowerCase();
            const mine = a => a.email.toLowerCase() === self;
            const others = (s.to || []).concat(s.cc || []).filter(a => !mine(a) && a.email !== s.from.email);
            draft = {
                to: [s.from.email].concat(others.filter(a => (s.to || []).includes(a)).map(a => a.email)).join(", "),
                cc: others.filter(a => !(s.to || []).includes(a)).map(a => a.email).join(", "),
                subject: /^re:/i.test(s.subject) ? s.subject : "Re: " + s.subject,
                body: "\n\n" + Facteur.tr("%1 wrote:").replace("%1", sender()) + "\n" + quoted(reader.body)
            };
        } else if (kind === "forward") {
            const s = reader.summary;
            draft = {
                subject: /^fwd?:/i.test(s.subject) ? s.subject : "Fwd: " + s.subject,
                body: "\n\n" + Facteur.tr("---------- Forwarded message ----------") + "\n" + Facteur.tr("From: %1").replace("%1", sender())
                    + "\n" + Facteur.tr("Date: %1").replace("%1", s.fullTime) + "\n" + Facteur.tr("Subject: %1").replace("%1", s.subject) + "\n\n" + reader.body
            };
        }
        composing = true;
        if (kind === "reply" || kind === "replyall") {
            const s = reader.summary;
            draft.inReplyTo = s.messageId || "";
            draft.references = ((s.inReplyTo || "") + " " + (s.messageId || "")).trim();
        }
        composer.open(draft);
    }

    function errorText(code) {
        const known = {
            "credential_missing": Facteur.tr("The password is not in the keyring."),
            "credential_store_unavailable": Facteur.tr("The keyring is not available."),
            "invalid_params": Facteur.tr("Check the address and the password."),
            "mail_network_failed": Facteur.tr("Cannot reach the mail server."),
            "mail_connection_closed": Facteur.tr("The server closed the connection."),
            "mail_auth_failed": Facteur.tr("The server refused the login."),
            "imap_auth_failed": Facteur.tr("The server refused the login."),
            "gmail_client_missing": Facteur.tr("No Google OAuth client: paste the client file first."),
            "gmail_client_unreadable": Facteur.tr("No Google OAuth client: paste the client file first."),
            "auth_port_unavailable": Facteur.tr("Port 9481 is in use: close the program that listens on it."),
            "auth_timeout": Facteur.tr("Google sign-in took too long. Try again."),
            "auth_offline_access_missing": Facteur.tr("Google did not grant lasting access. Remove Facteur from your Google account permissions and try again."),
            "auth_missing_scope": Facteur.tr("Mail access was not granted: tick every permission on Google's page.")
        };
        return known[code] || code;
    }

    function loadAccounts() {
        const r = JSON.parse(Facteur.accounts());
        accounts = (r.accounts || []).filter(a => a.id !== "");
        if (accounts.length === 0) {
            account = "";
            return;
        }
        if (!accounts.some(a => a.id === account))
            account = accounts.some(a => a.id === r.activeId) ? r.activeId : accounts[0].id;
    }

    function visit() {
        if (navigating || account === "")
            return;
        const here = { account: account, mailbox: mailbox, query: query };
        const kept = history.slice(0, hindex + 1);
        const last = kept.length > 0 ? kept[kept.length - 1] : null;
        if (last && last.account === here.account && last.mailbox === here.mailbox && last.query === here.query)
            return;
        kept.push(here);
        history = kept.slice(-50);
        hindex = history.length - 1;
    }
    function go(step) {
        const i = hindex + step;
        if (i < 0 || i >= history.length)
            return;
        navigating = true;
        hindex = i;
        const p = history[i];
        if (searchInput.text !== p.query) searchInput.text = p.query;
        query = p.query;
        account = p.account;
        mailbox = p.mailbox;
        navigating = false;
    }
    // Previous or next message of the list
    function step(delta) {
        const i = rowOf(selectedId) + delta;
        if (selectedId !== "" && i >= 0 && i < messages.count)
            choose(messages.get(i).id);
    }
    function boxLabel() {
        const names = { inbox: Facteur.tr("Inbox"), unread: Facteur.tr("Unread"), starred: Facteur.tr("Starred"), sent: Facteur.tr("Sent"), drafts: Facteur.tr("Drafts"), archive: Facteur.tr("Archive"), spam: Facteur.tr("Spam"), trash: Facteur.tr("Trash") };
        return names[mailbox] || (mailbox.startsWith("label:") ? mailbox.slice(6) : mailbox);
    }
    function unreadCount() {
        let n = 0;
        for (let i = 0; i < messages.count; i++)
            if (messages.get(i).unread) n++;
        return n;
    }
    // Messages ticked for a batch action (checkbox, Ctrl/Shift+click, X, Ctrl+A); empty: actions apply to the open message
    property int checkedCount: 0
    property bool checkedAnyUnread: false
    property bool checkedAllStarred: false
    property int checkAnchor: -1
    function recount() {
        let n = 0, unread = false, starred = n === 0;
        for (let i = 0; i < messages.count; i++) {
            const m = messages.get(i);
            if (!m.checked) continue;
            n++;
            if (m.unread) unread = true;
            if (!m.starred) starred = false;
        }
        checkedCount = n;
        checkedAnyUnread = unread;
        checkedAllStarred = n > 0 && starred;
    }
    function checkedIds() {
        const ids = [];
        for (let i = 0; i < messages.count; i++)
            if (messages.get(i).checked) ids.push(messages.get(i).id);
        return ids;
    }
    function clearChecks() {
        for (let i = 0; i < messages.count; i++)
            if (messages.get(i).checked) messages.setProperty(i, "checked", false);
        checkAnchor = -1;
        recount();
    }
    // mode 0: toggle one row; 1: range from the last toggled row (Shift+click)
    function check(index, mode) {
        if (index < 0 || index >= messages.count) return;
        if (mode === 1 && checkAnchor >= 0) {
            const a = Math.min(checkAnchor, index), b = Math.max(checkAnchor, index);
            for (let i = a; i <= b; i++) messages.setProperty(i, "checked", true);
        } else {
            messages.setProperty(index, "checked", !messages.get(index).checked);
            checkAnchor = index;
        }
        recount();
    }
    function checkAll() {
        for (let i = 0; i < messages.count; i++) messages.setProperty(i, "checked", true);
        recount();
    }
    // The ticked messages if there are any, else the open one
    function actOnSelection(operation) {
        if (checkedCount > 0) doActMany(operation, checkedIds());
        else if (selectedId !== "") doAct(operation, selectedId);
    }
    // Next page of the list (token of the last answer), fetched when the end of the list comes near
    property string nextToken: ""
    property bool loadingMore: false
    function loadMore() {
        if (nextToken === "" || loading || loadingMore || account === "" || listError !== "")
            return;
        loadingMore = true;
        Facteur.list(account, listBox(), listQuery(), nextToken);
    }
    function refresh() {
        nextToken = "";
        loadingMore = false;
        checkedCount = 0;
        checkAnchor = -1;
        if (account === "")
            return;
        loading = true;
        listError = "";
        Facteur.list(account, listBox(), listQuery(), "");
    }

    function rowOf(id) {
        for (let i = 0; i < messages.count; i++)
            if (messages.get(i).id === id)
                return i;
        return -1;
    }

    // Change a message: the list answers at once, the server follows; a refusal reloads the list
    function doAct(operation, id) {
        doActMany(operation, [id]);
    }
    function doActMany(operation, ids) {
        if (account === "" || ids.length === 0)
            return;
        if (operation === "archive" || operation === "trash" || operation === "spam") {
            // The message just after the first one that leaves takes its place
            let first = messages.count;
            for (const id of ids) {
                const i = rowOf(id);
                if (i >= 0 && i < first) first = i;
            }
            const leaving = selectedId !== "" && ids.includes(selectedId);
            for (const id of ids) {
                const i = rowOf(id);
                if (i >= 0) messages.remove(i);
            }
            if (leaving) {
                const at = Math.min(first, messages.count - 1);
                if (at >= 0) choose(messages.get(at).id, true); else { selectedId = ""; reader.summary = null; }
            }
        } else {
            for (const id of ids) {
                const i = rowOf(id);
                if (i < 0) continue;
                if (operation === "read" || operation === "unread") {
                    messages.setProperty(i, "unread", operation === "unread");
                    if (id === selectedId) reader.unread = operation === "unread";
                } else if (operation === "star" || operation === "unstar") {
                    messages.setProperty(i, "starred", operation === "star");
                    if (id === selectedId) reader.starred = operation === "star";
                }
            }
        }
        notice = "";
        recount();
        Facteur.act(account, operation, JSON.stringify(ids));
    }

    function choose(id, quiet) {
        selectedId = id;
        const row = rowOf(id);
        reader.unread = row >= 0 ? messages.get(row).unread : false;
        reader.starred = row >= 0 ? messages.get(row).starred : false;
        // Opening a message reads it
        if (row >= 0 && messages.get(row).unread)
            doAct("read", id);
        reader.summary = null;
        reader.attachments = [];
        reader.body = "";
        reader.rich = "";
        reader.unsubscribeUrl = "";
        reader.remoteImages = 0;
        reader.error = "";
        Facteur.openMessage(account, id);
    }

    Connections {
        target: Facteur
        function onListed(acc, box, qry, json) {
            if (acc !== win.account || box !== win.listBox() || qry !== win.listQuery())
                return;
            const r = JSON.parse(json);
            const more = r.append === true || (!!r.error && win.loadingMore);
            if (more && !win.loadingMore)
                return; // the answer of a list that was refreshed since
            win.loadingMore = false;
            if (more && r.error) {
                win.notice = win.errorText(r.error);
                return;
            }
            win.loading = false;
            if (!more)
                messages.clear();
            if (r.error) {
                win.listError = win.errorText(r.error);
                return;
            }
            win.nextToken = r.nextPageToken || "";
            const known = new Set();
            if (more)
                for (let i = 0; i < messages.count; i++) known.add(messages.get(i).id);
            for (const m of r.messages)
                if ((!listBar.unreadOnly || m.unread) && !known.has(m.id))
                    messages.append({ id: m.id, from: m.from.display || m.from.email || "", subject: m.subject, time: m.time, unread: m.unread, starred: m.starred, checked: false });
        }
        // Menu of the fili-bar (fili-mail ctl action NAME)
        function onCommand(name) {
            const boxes = { "inbox": "inbox", "unread-box": "unread", "starred": "starred", "sent": "sent", "drafts": "drafts", "archive-box": "archive", "spam-box": "spam", "trash-box": "trash" };
            const onMessage = !win.adding && !win.composing && win.selectedId !== "";
            if (name === "about") aboutCard.show();
            else if (name === "close") Qt.quit();
            else if (name === "add-account") { win.addError = ""; win.adding = true }
            else if (name === "new-message") win.startCompose("new");
            else if (name === "reply" || name === "forward") win.startCompose(name);
            else if (name === "reply-all") win.startCompose("replyall");
            else if (name === "next-message" || name === "previous-message") {
                if (win.selectedId === "" && messages.count > 0) win.choose(messages.get(0).id);
                else win.step(name === "next-message" ? 1 : -1);
            }
            else if (name === "refresh") win.refresh();
            else if (boxes[name]) { win.adding = false; win.mailbox = boxes[name] }
            else if (onMessage) win.doAct(name, win.selectedId);
        }
        function onSent(json) {
            win.sending = false;
            const r = JSON.parse(json);
            if (r.error) {
                composer.error = win.errorText(r.error);
                return;
            }
            win.composing = false;
            win.notice = "";
        }
        function onOpened(id, json) {
            if (id !== win.selectedId)
                return;
            const r = JSON.parse(json);
            if (r.error) {
                reader.error = win.errorText(r.error);
                return;
            }
            reader.summary = r.message.summary;
            reader.body = r.message.nativeContent.body.text;
            reader.rich = r.message.rich || "";
            reader.remoteImages = r.message.remoteImages || 0;
            reader.unsubscribeUrl = (r.message.unsubscribe && r.message.unsubscribe.urls && r.message.unsubscribe.urls[0]) || "";
            reader.attachments = r.message.nativeContent.attachments || [];
            reader.loadingImages = false;
        }
        function onAttachmentSaved(json) {
            const r = JSON.parse(json);
            win.notice = r.error ? win.errorText(r.error) : Facteur.tr("Saved to %1").replace("%1", r.path);
        }
        function onLabelsLoaded(acc, json) {
            if (acc === win.account) win.labels = JSON.parse(json);
        }
        function onLabelCreated(acc, json) {
            labelDialog.busy = false;
            const r = JSON.parse(json);
            if (r.error) {
                labelDialog.error = win.errorText(r.error);
                return;
            }
            labelDialog.visible = false;
            if (acc === win.account) win.loadLabels();
        }
        function onLabelChanged(acc, json) {
            const r = JSON.parse(json);
            labelDialog.busy = false;
            if (r.error) {
                if (labelDialog.visible) labelDialog.error = win.errorText(r.error); else win.notice = win.errorText(r.error);
                return;
            }
            labelDialog.visible = false;
            if (acc !== win.account) return;
            win.loadLabels();
        }
        function onAccountUpdated(json) {
            const r = JSON.parse(json);
            accountDialog.busy = false;
            if (r.error) { accountDialog.error = win.errorText(r.error); return; }
            accountDialog.visible = false;
            win.loadAccounts();
        }
        function onActed(acc, operation, ids, json) {
            if (acc !== win.account)
                return;
            const r = JSON.parse(json);
            if (r.error) {
                win.notice = win.errorText(r.error);
                win.refresh();
            }
        }
        function onAccountRemoved(json) {
            const r = JSON.parse(json);
            win.removing = "";
            if (r.error) {
                win.notice = win.errorText(r.error);
                return;
            }
            win.loadAccounts();
            messages.clear();
            win.selectedId = "";
            reader.summary = null;
            win.refresh();
        }
        function onGoogleStarted(url) {
            setupPage.googleUrl = url;
        }
        function onAccountAdded(json) {
            win.addBusy = false;
            const r = JSON.parse(json);
            if (r.error) {
                win.addError = win.errorText(r.error);
                return;
            }
            win.adding = false;
            win.account = r.added;
            win.loadAccounts();
            win.refresh();
        }
    }

    Component.onCompleted: {
        loadAccounts();
        visit();
        refresh();
    }
    onAccountChanged: { messages.clear(); selectedId = ""; reader.summary = null; if (mailbox.startsWith("label:")) mailbox = "inbox"; loadLabels(); visit(); refresh() }
    onMailboxChanged: { messages.clear(); selectedId = ""; reader.summary = null; visit(); refresh() }
    onCategoryChanged: { if (categoriesOn()) { messages.clear(); selectedId = ""; reader.summary = null; refresh() } }
    onQueryChanged: { messages.clear(); selectedId = ""; reader.summary = null; visit(); refresh() }

    Shortcut { sequences: ["Ctrl+Q", "Ctrl+W"]; onActivated: Qt.quit() }
    Shortcut { sequences: ["Ctrl+Shift+W"]; enabled: toolbar.visible; onActivated: windowPanel.visible ? windowPanel.close() : windowPanel.open() }
    Shortcut { sequences: ["F5", "Ctrl+R"]; enabled: !win.adding && win.account !== ""; onActivated: win.refresh() }
    Shortcut { sequences: ["Alt+Left"]; enabled: !win.adding && win.hindex > 0; onActivated: win.go(-1) }
    Shortcut { sequences: ["Alt+Right"]; enabled: !win.adding && win.hindex < win.history.length - 1; onActivated: win.go(1) }
    Shortcut { sequences: ["Ctrl+F"]; enabled: !win.adding && win.account !== "" && !win.composing; onActivated: searchInput.forceActiveFocus() }
    Shortcut { sequences: ["Ctrl+N"]; enabled: !win.adding && win.account !== ""; onActivated: win.startCompose("new") }
    Shortcut { sequences: ["Ctrl+Shift+R"]; enabled: !win.adding && !win.composing; onActivated: win.startCompose("reply") }
    Shortcut { sequences: ["Ctrl+Alt+R"]; enabled: !win.adding && !win.composing; onActivated: win.startCompose("replyall") }
    Shortcut { sequences: ["Ctrl+Shift+F"]; enabled: !win.adding && !win.composing; onActivated: win.startCompose("forward") }
    Shortcut { sequences: ["Ctrl+Shift+A"]; onActivated: { win.addError = ""; win.adding = true } }

    AccountSetup {
        anchors.fill: parent
        visible: win.adding || win.accounts.length === 0
        cancellable: win.accounts.length > 0
        busy: win.addBusy
        error: win.addError
        onCancelled: win.adding = false
        id: setupPage
        onSubmitted: spec => {
            win.addError = "";
            win.addBusy = true;
            if (spec.google)
                Facteur.googleSignIn(spec.hint);
            else
                Facteur.addImap(JSON.stringify(spec));
        }
    }

    // Toolbar: back and forward (places visited), title and counts, search, refresh, new message
    Rectangle {
        id: toolbar
        visible: !win.adding && win.accounts.length > 0
        width: parent.width
        height: FiliTheme.toolbarHeight
        color: FiliTheme.background
        Rectangle {
            x: FiliTheme.margin
            anchors.verticalCenter: nav.verticalCenter
            width: nav.width + 2 * FiliTheme.space1 + 2
            height: 30
            radius: 8
            color: FiliTheme.surface
            border.width: FiliTheme.borderWidth
            border.color: FiliTheme.border
        }
        Row {
            id: nav
            x: FiliTheme.margin + FiliTheme.space1 + 1
            anchors.verticalCenter: parent.verticalCenter
            spacing: FiliTheme.space1
            IconButton { name: "chevron-left"; tip: Facteur.tr("Go back"); enabledState: win.hindex > 0; onClicked: win.go(-1) }
            IconButton { name: "chevron-right"; tip: Facteur.tr("Go forward"); enabledState: win.hindex < win.history.length - 1; onClicked: win.go(1) }
        }
        Column {
            anchors { left: nav.right; leftMargin: FiliTheme.space5; right: tools.left; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
            Text {
                width: parent.width
                text: win.boxLabel() + (win.query !== "" ? "  ·  " + Facteur.tr("Search: %1").replace("%1", win.query) : "")
                elide: Text.ElideRight
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                font.weight: FiliTheme.weightAccent
                color: FiliTheme.text
            }
            Text {
                width: parent.width
                text: win.loading ? "…" : win.listError !== "" ? "" : Facteur.tr("%1 messages, %2 unread").replace("%1", messages.count).replace("%2", win.unreadCount())
                elide: Text.ElideRight
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeList
                color: FiliTheme.textSecondary
            }
        }
        Row {
            id: tools
            anchors { right: search.left; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
            spacing: FiliTheme.space1
            IconButton { name: win.preview === "below" ? "layout-below" : "layout-right"; tip: win.preview === "below" ? Facteur.tr("Preview on the right") : Facteur.tr("Preview below"); onClicked: win.togglePreview() }
            IconButton { name: "refresh"; tip: Facteur.tr("Refresh"); onClicked: win.refresh() }
            IconButton { name: "compose"; tip: Facteur.tr("New message"); onClicked: win.startCompose("new") }
        }
        // Window buttons at the far right: close, and the panel of window actions (niri)
        Rectangle {
            id: closeButton
            anchors { right: parent.right; rightMargin: (toolbar.height - height) / 2; verticalCenter: parent.verticalCenter }
            width: 28
            height: 24
            radius: FiliTheme.radiusControl
            color: closeArea.pressed ? FiliTheme.danger : closeArea.containsMouse ? FiliTheme.alpha(FiliTheme.danger, 0.75) : "transparent"
            WindowGlyph {
                anchors.centerIn: parent
                kind: "close"
                width: 16
                height: 16
                color: closeArea.containsMouse ? "#ffffff" : FiliTheme.text
            }
            MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; onClicked: Qt.quit() }
            Accessible.role: Accessible.Button
            Accessible.name: Facteur.tr("Close window")
        }
        Rectangle {
            id: windowButton
            anchors { right: closeButton.left; rightMargin: FiliTheme.space1; verticalCenter: parent.verticalCenter }
            width: 28
            height: 24
            radius: FiliTheme.radiusControl
            color: windowArea.pressed ? FiliTheme.surfaceActive : windowArea.containsMouse || windowPanel.visible ? FiliTheme.surfaceHover : "transparent"
            WindowGlyph { anchors.centerIn: parent; kind: "window"; width: 16; height: 16 }
            MouseArea { id: windowArea; anchors.fill: parent; hoverEnabled: true; onClicked: windowPanel.visible ? windowPanel.close() : windowPanel.open() }
            Accessible.role: Accessible.Button
            Accessible.name: Facteur.tr("Window")
        }
        Rectangle {
            id: search
            anchors { right: windowButton.left; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
            width: 200
            height: 26
            radius: FiliTheme.radiusControl
            color: FiliTheme.surface
            border.width: FiliTheme.borderWidth
            border.color: searchInput.activeFocus ? FiliTheme.accentColor : FiliTheme.border
            Text {
                anchors { left: parent.left; leftMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                visible: searchInput.text === ""
                text: Facteur.tr("Search")
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                color: FiliTheme.muted
            }
            TextInput {
                id: searchInput
                anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 }
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                color: FiliTheme.text
                selectionColor: FiliTheme.surfaceActive
                selectedTextColor: FiliTheme.text
                onTextChanged: searchWait.restart()
                Keys.onEscapePressed: { text = ""; win.query = ""; focus = false }
                Keys.onReturnPressed: { searchWait.stop(); win.query = text.trim(); focus = false }
                Keys.onDownPressed: focus = false
            }
            // The list follows the typing after a short pause
            Timer {
                id: searchWait
                interval: 450
                onTriggered: win.query = searchInput.text.trim()
            }
        }
    }
    Rectangle {
        id: toolbarLine
        visible: toolbar.visible
        anchors.top: toolbar.bottom
        width: parent.width
        height: FiliTheme.borderWidth
        color: FiliTheme.border
    }

    Row {
        anchors { top: toolbar.visible ? toolbarLine.bottom : parent.top; bottom: footer.visible ? footer.top : parent.bottom; left: parent.left; right: parent.right }
        visible: !win.adding && win.accounts.length > 0
        Sidebar {
            width: FiliTheme.sidebarWidth
            height: parent.height
            accounts: win.accounts
            account: win.account
            mailbox: win.mailbox
            onAccountChosen: id => win.account = id
            onMailboxChosen: key => win.mailbox = key
            labels: win.labels
            onAddLabelRequested: { labelDialog.error = ""; labelDialog.open() }
            onAddAccount: { win.addError = ""; win.adding = true }
            onContextRequested: (kind, data, x, y) => win.openContext(kind, data, x, y)
        }
        Rectangle { width: FiliTheme.borderWidth; height: parent.height; color: FiliTheme.border }
        // Bar over the list and the reader, then the two side by side
        Column {
            id: content
            width: parent.width - FiliTheme.sidebarWidth - FiliTheme.borderWidth
            height: parent.height
            ListBar {
                id: listBar
                width: parent.width
                onUnreadOnlyChanged: { messages.clear(); win.selectedId = ""; win.refresh() }
                selectedId: win.selectedId
                checkedCount: win.checkedCount
                onAct: operation => win.actOnSelection(operation)
                tabs: win.categoriesOn() ? win.categories : []
                tab: win.category
                onTabChosen: key => win.category = key
                onStep: delta => win.step(delta)
                selectedUnread: win.checkedCount > 0 ? win.checkedAnyUnread : reader.unread
                selectedStarred: win.checkedCount > 0 ? win.checkedAllStarred : reader.starred
                position: win.selectedId !== "" ? (win.rowOf(win.selectedId) + 1) + "/" + messages.count : messages.count > 0 ? "" + messages.count : ""
                canPrev: win.selectedId !== "" && win.rowOf(win.selectedId) > 0
                canNext: win.selectedId !== "" && win.rowOf(win.selectedId) < messages.count - 1
            }
            Rectangle { width: parent.width; height: FiliTheme.borderWidth; color: FiliTheme.border }
            Item {
                id: panes
                width: parent.width
                height: parent.height - listBar.height - FiliTheme.borderWidth
                readonly property bool below: win.preview === "below"
                MessageList {
                    id: messageList
                    width: panes.below ? panes.width : Math.max(250, Math.min(340, win.width * 0.34))
                    height: panes.below ? Math.max(140, Math.min(panes.height * 0.4, 340)) : panes.height
                    model: messages
                    selectedId: win.selectedId
                    onAct: operation => win.actOnSelection(operation)
                    onCheck: (index, mode) => win.check(index, mode)
                    onCheckAll: win.checkAll()
                    onClearChecks: win.clearChecks()
                    checkedCount: win.checkedCount
                    onStep: delta => win.step(delta)
                    emptyText: win.listError !== "" ? win.listError : win.loading ? "…" : Facteur.tr("No message")
                    onChosen: id => win.choose(id)
                    onNearEnd: win.loadMore()
                }
                Rectangle {
                    x: panes.below ? 0 : messageList.width
                    y: panes.below ? messageList.height : 0
                    width: panes.below ? panes.width : FiliTheme.borderWidth
                    height: panes.below ? FiliTheme.borderWidth : panes.height
                    color: FiliTheme.border
                }
                Reader {
                    id: reader
                    onAct: operation => win.doAct(operation, win.selectedId)
                    onReply: win.startCompose("reply")
                    onForward: win.startCompose("forward")
                    onReplyAll: win.startCompose("replyall")
                    onUnsubscribe: url => Qt.openUrlExternally(url)
                    onSaveAttachment: index => Facteur.saveAttachment(win.account, win.selectedId, reader.attachments[index].attachmentId, reader.attachments[index].filename)
                    onLoadImages: { reader.loadingImages = true; Facteur.loadImages(win.account, win.selectedId) }
                    x: panes.below ? 0 : messageList.width + FiliTheme.borderWidth
                    y: panes.below ? messageList.height + FiliTheme.borderWidth : 0
                    width: panes.below ? panes.width : panes.width - x
                    height: panes.below ? panes.height - y : panes.height
                    Compose {
                        id: composer
                        anchors.fill: parent
                        visible: win.composing
                        busy: win.sending
                        from: win.account.replace(/^[a-z]+:/, "")
                        onCancelled: win.composing = false
                        onSubmitted: fields => { win.sending = true; error = ""; Facteur.send(win.account, JSON.stringify(fields)) }
                    }
                }
            }
        }
    }

    // Removal asks first: the account and its password leave this computer, the mailbox itself is untouched
    Rectangle {
        visible: win.removing !== ""
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: FiliTheme.statusHeight + FiliTheme.space2
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: FiliTheme.border
        Text {
            anchors { left: parent.left; leftMargin: FiliTheme.margin; verticalCenter: parent.verticalCenter }
            text: Facteur.tr("Remove %1? Its password is forgotten; the mailbox itself is not touched.").replace("%1", win.removing.replace(/^[a-z]+:/, ""))
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
            color: FiliTheme.text
        }
        Row {
            anchors { right: parent.right; rightMargin: FiliTheme.margin; verticalCenter: parent.verticalCenter }
            spacing: FiliTheme.space2
            TextButton { label: Facteur.tr("Remove"); primary: true; onClicked: Facteur.removeAccount(win.removing) }
            TextButton { label: Facteur.tr("Cancel"); onClicked: win.removing = "" }
        }
    }
    // Footer: where we are, how much is loaded, what is selected, what went wrong
    Rectangle {
        id: footer
        visible: !win.adding && win.accounts.length > 0
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: FiliTheme.statusHeight
        color: FiliTheme.backgroundDeep
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: FiliTheme.borderWidth; color: FiliTheme.border }
        Text {
            id: where
            anchors { left: parent.left; leftMargin: FiliTheme.margin; verticalCenter: parent.verticalCenter }
            text: win.account.replace(/^[a-z]+:/, "") + "  ·  " + win.boxLabel() + (win.query !== "" ? "  ·  " + Facteur.tr("Search: %1").replace("%1", win.query) : "")
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeSmall
            color: FiliTheme.textSecondary
        }
        Text {
            anchors { right: parent.right; rightMargin: FiliTheme.margin; verticalCenter: parent.verticalCenter }
            width: Math.max(0, parent.width - where.width - 3 * FiliTheme.margin)
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            text: {
                if (win.notice !== "") return win.notice;
                const parts = [];
                if (win.loading) parts.push("…");
                else if (win.listError === "") {
                    parts.push(Facteur.tr("%1 messages, %2 unread").replace("%1", messages.count).replace("%2", win.unreadCount()));
                    if (win.nextToken !== "") parts.push(win.loadingMore ? Facteur.tr("Loading more…") : Facteur.tr("More below"));
                }
                if (win.checkedCount > 0) parts.push(Facteur.tr("%1 selected").replace("%1", win.checkedCount));
                return parts.join("  ·  ");
            }
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeSmall
            color: win.notice !== "" ? FiliTheme.danger : FiliTheme.textSecondary
        }
    }
    LabelDialog {
        id: labelDialog
        onCancelled: visible = false
        onCreated: (name, background, text) => {
            busy = true;
            error = "";
            if (editId !== "") {
                // A view of this label follows its new name
                const old = win.labels.find(l => l.id === editId);
                if (old && win.mailbox === "label:" + old.rawName) win.mailbox = "label:" + name;
                Facteur.updateLabel(win.account, editId, name, background, text);
            }
            else Facteur.createLabel(win.account, name, background, text);
        }
    }
    AccountDialog {
        id: accountDialog
        onCancelled: visible = false
        onSaved: (id, patch) => { busy = true; error = ""; Facteur.updateAccount(id, JSON.stringify(patch)) }
    }
    // Deleting a label asks first: the messages keep everything else, only the label goes
    Rectangle {
        visible: win.deletingLabel !== null
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: FiliTheme.statusHeight + FiliTheme.space2
        z: 90
        color: FiliTheme.surface
        border.width: FiliTheme.borderWidth
        border.color: FiliTheme.border
        Text {
            anchors { left: parent.left; leftMargin: FiliTheme.margin; verticalCenter: parent.verticalCenter }
            text: Facteur.tr("Delete the label %1? Its messages are kept.").replace("%1", win.deletingLabel ? win.deletingLabel.rawName : "")
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
            color: FiliTheme.text
        }
        Row {
            anchors { right: parent.right; rightMargin: FiliTheme.margin; verticalCenter: parent.verticalCenter }
            spacing: FiliTheme.space2
            TextButton { label: Facteur.tr("Delete"); primary: true; onClicked: { if (win.mailbox === "label:" + win.deletingLabel.rawName) win.mailbox = "inbox"; Facteur.deleteLabel(win.account, win.deletingLabel.id); win.deletingLabel = null } }
            TextButton { label: Facteur.tr("Cancel"); onClicked: win.deletingLabel = null }
        }
    }
    PopupMenu {
        id: popup
        onActivated: id => win.runContext(id)
    }
    WindowPanel {
        id: windowPanel
        anchorRight: width - (toolbar.height - closeButton.height) / 2
        anchorTop: toolbar.height + 1
    }
    AboutCard { id: aboutCard; anchors.fill: parent }
}
