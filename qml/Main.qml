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

    ListModel { id: messages }

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

    function choose(id) {
        selectedId = id;
        reader.summary = null;
        reader.body = "";
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
                messages.append({ id: m.id, from: m.from.display || m.from.email || "", subject: m.subject, time: m.time, unread: m.unread });
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
            onAddAccount: { win.addError = ""; win.adding = true }
        }
        Rectangle { width: FiliTheme.borderWidth; height: parent.height; color: FiliTheme.border }
        MessageList {
            width: 340
            height: parent.height
            model: messages
            selectedId: win.selectedId
            emptyText: win.listError !== "" ? win.listError : win.loading ? "…" : Facteur.tr("No message")
            onChosen: id => win.choose(id)
        }
        Rectangle { width: FiliTheme.borderWidth; height: parent.height; color: FiliTheme.border }
        Reader {
            id: reader
            width: parent.width - FiliTheme.sidebarWidth - 340 - 2 * FiliTheme.borderWidth
            height: parent.height
        }
    }
}
