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
        } else if (kind === "forward") {
            const s = reader.summary;
            draft = {
                subject: /^fwd?:/i.test(s.subject) ? s.subject : "Fwd: " + s.subject,
                body: "\n\n" + Facteur.tr("---------- Forwarded message ----------") + "\n" + Facteur.tr("From: %1").replace("%1", sender())
                    + "\n" + Facteur.tr("Date: %1").replace("%1", s.fullTime) + "\n" + Facteur.tr("Subject: %1").replace("%1", s.subject) + "\n\n" + reader.body
            };
        }
        composing = true;
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

    function refresh() {
        if (account === "")
            return;
        loading = true;
        listError = "";
        Facteur.list(account, mailbox);
    }

    function rowOf(id) {
        for (let i = 0; i < messages.count; i++)
            if (messages.get(i).id === id)
                return i;
        return -1;
    }

    // Change a message: the list answers at once, the server follows; a refusal reloads the list
    function doAct(operation, id) {
        const i = rowOf(id);
        if (i < 0 || account === "")
            return;
        if (operation === "archive" || operation === "trash" || operation === "spam") {
            // The next message takes the place of the one that leaves
            const next = i + 1 < messages.count ? messages.get(i + 1).id : i > 0 ? messages.get(i - 1).id : "";
            messages.remove(i);
            if (id === selectedId) {
                if (next !== "") choose(next, true); else { selectedId = ""; reader.summary = null; }
            }
        } else if (operation === "read" || operation === "unread") {
            messages.setProperty(i, "unread", operation === "unread");
            if (id === selectedId) reader.unread = operation === "unread";
        } else if (operation === "star" || operation === "unstar") {
            messages.setProperty(i, "starred", operation === "star");
            if (id === selectedId) reader.starred = operation === "star";
        }
        notice = "";
        Facteur.act(account, operation, JSON.stringify([id]));
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
        reader.body = "";
        reader.rich = "";
        reader.error = "";
        Facteur.openMessage(account, id);
    }

    Connections {
        target: Facteur
        function onListed(acc, box, json) {
            if (acc !== win.account || box !== win.mailbox)
                return;
            win.loading = false;
            const r = JSON.parse(json);
            messages.clear();
            if (r.error) {
                win.listError = win.errorText(r.error);
                return;
            }
            for (const m of r.messages)
                messages.append({ id: m.id, from: m.from.display || m.from.email || "", subject: m.subject, time: m.time, unread: m.unread, starred: m.starred });
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
        refresh();
    }
    onAccountChanged: { messages.clear(); selectedId = ""; reader.summary = null; refresh() }
    onMailboxChanged: { messages.clear(); selectedId = ""; reader.summary = null; refresh() }

    Shortcut { sequences: ["Ctrl+Q", "Ctrl+W"]; onActivated: Qt.quit() }
    Shortcut { sequences: ["F5", "Ctrl+R"]; enabled: !win.adding && win.account !== ""; onActivated: win.refresh() }
    Shortcut { sequences: ["Ctrl+N"]; enabled: !win.adding && win.account !== ""; onActivated: win.startCompose("new") }
    Shortcut { sequences: ["Ctrl+Shift+R"]; enabled: !win.adding && !win.composing; onActivated: win.startCompose("reply") }
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

    Row {
        anchors.fill: parent
        visible: !win.adding && win.accounts.length > 0
        Sidebar {
            width: FiliTheme.sidebarWidth
            height: parent.height
            accounts: win.accounts
            account: win.account
            mailbox: win.mailbox
            onAccountChosen: id => win.account = id
            onMailboxChosen: key => win.mailbox = key
            onCompose: win.startCompose("new")
            onAddAccount: { win.addError = ""; win.adding = true }
            onRemoveRequested: id => win.removing = id
        }
        Rectangle { width: FiliTheme.borderWidth; height: parent.height; color: FiliTheme.border }
        MessageList {
            width: 340
            height: parent.height
            model: messages
            selectedId: win.selectedId
            onAct: operation => { if (win.selectedId !== "") win.doAct(operation, win.selectedId) }
            emptyText: win.listError !== "" ? win.listError : win.loading ? "…" : Facteur.tr("No message")
            onChosen: id => win.choose(id)
        }
        Rectangle { width: FiliTheme.borderWidth; height: parent.height; color: FiliTheme.border }
        Reader {
            id: reader
            onAct: operation => win.doAct(operation, win.selectedId)
            onReply: win.startCompose("reply")
            onForward: win.startCompose("forward")
            width: parent.width - FiliTheme.sidebarWidth - 340 - 2 * FiliTheme.borderWidth
            height: parent.height
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
    Text {
        visible: win.notice !== "" && win.removing === ""
        anchors { right: parent.right; bottom: parent.bottom; margins: FiliTheme.space3 }
        text: win.notice
        font.family: FiliTheme.font
        font.pixelSize: FiliTheme.sizeList
        color: FiliTheme.danger
    }
    AboutCard { id: aboutCard; anchors.fill: parent }
}
