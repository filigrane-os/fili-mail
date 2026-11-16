// Window of Facteur: sidebar (accounts, mailboxes), message list, reader. Without an account, the window is the account form.
import QtQuick
import QtQuick.Controls.Basic
import Fili.Mail

ApplicationWindow {
    id: win
    // Close and window-actions buttons at the right of the header (bar menu: Window > Show Window Buttons), kept in
    // the state file like Casier's
    property bool windowButtons: Facteur.uiGet("window_buttons") !== "0"
    function toggleWindowButtons() {
        windowButtons = !windowButtons;
        Facteur.uiSet("window_buttons", windowButtons ? "1" : "0");
    }
    // Header (toolbar) and footer (status bar): hidden when the settings say so (Settings > Appearance, [window] header|footer,
    // --no-header, --no-footer), and followed live. The search (Ctrl+F) shows the header while it is used, a notice or an error
    // shows the footer for its duration. The bar menu entries "Show Header" / "Show Status Bar" change them for this window only
    property bool showHeader: Facteur.header()
    property bool showFooter: Facteur.footer()
    property bool searchOpen: false
    readonly property bool mainView: !adding && accounts.length > 0
    readonly property bool headerShown: mainView && (showHeader || searchOpen || searchInput.text !== "")
    readonly property bool footerShown: mainView && (showFooter || notice !== "")
    function openSearch() {
        searchOpen = true;
        searchInput.forceActiveFocus();
    }
    Connections {
        target: Facteur
        function onThemeChanged() {
            win.showHeader = Facteur.header();
            win.showFooter = Facteur.footer();
        }
    }
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
    // Where the reader sits: "side" (beside the list), "bottom" (under it) or "auto": beside as soon as the window is wide
    // enough for a message to read well next to the list (list 340 + reader 520, the sidebar included), under it below that.
    readonly property int sideMinWidth: FiliTheme.sidebarWidth + FiliTheme.borderWidth + 340 + FiliTheme.borderWidth + 520
    property string previewMode: ["auto", "side", "bottom"].indexOf(Facteur.uiGet("preview_mode")) >= 0 ? Facteur.uiGet("preview_mode") : "auto"
    function setPreviewMode(mode) { previewMode = mode; Facteur.uiSet("preview_mode", mode); }
    function togglePreview() { setPreviewMode(previewMode === "auto" ? "side" : previewMode === "side" ? "bottom" : "auto"); }
    readonly property string preview: previewMode === "side" ? "right" : previewMode === "bottom" ? "below" : (win.width >= sideMinWidth ? "right" : "below")
    // A label (Gmail) is a mailbox named "label:NAME": it lists everything carrying it except spam and trash
    property var labels: []
    // "All" / "Unread" of the Inbox group: the inboxes of every account in one list (mailbox "all" / "allunread").
    // A row id is then "<account>\u001f<id>" (ids of two IMAP accounts can be the same).
    readonly property bool unified: mailbox === "all" || mailbox === "allunread"
    readonly property string sep: "\u001f"
    function splitId(id) {
        const i = id.indexOf(sep);
        return i < 0 ? { acct: account, id: id } : { acct: id.slice(0, i), id: id.slice(i + 1) };
    }
    readonly property var selectedRef: splitId(selectedId)
    property int unifiedPending: 0
    // What an account lists for the current mailbox and tab: {box, query}, or null when the account has nothing for that tab
    // (a category its folders are not mapped to). "folder:NAME" (IMAP) goes through as is.
    function listSpec(acct) {
        let box = mailbox === "all" ? "inbox" : mailbox === "allunread" ? "unread" : mailbox.startsWith("label:") ? "archive" : mailbox;
        let q = query;
        if (mailbox.startsWith("label:")) {
            q = ("label:\"" + mailbox.slice(6) + "\" " + query).trim();
        } else if (categoriesOn()) {
            if (providerOf(acct) === "gmail") {
                box = "inbox";
                q = ("category:" + category + (mailbox === "allunread" ? " is:unread" : "") + " " + query).trim();
            } else if (category !== "primary") {
                const folder = (catMaps[acct] || {})[category];
                if (!folder) return null;
                box = "folder:" + folder;
            }
        }
        return { box: box, query: q };
    }
    function listBox() { const sp = listSpec(account); return sp ? sp.box : "inbox"; }
    function listQuery() { const sp = listSpec(account); return sp ? sp.query : query; }
    // Gmail sorts the inbox in categories (tabs above the list)
    property string category: "primary"
    readonly property var categories: [
        { key: "primary", label: Facteur.tr("Primary"), icon: "inbox" },
        { key: "promotions", label: Facteur.tr("Promotions"), icon: "tag" },
        { key: "social", label: Facteur.tr("Social"), icon: "users" },
        { key: "updates", label: Facteur.tr("Updates"), icon: "bell" },
        { key: "forums", label: Facteur.tr("Forums"), icon: "chat" }
    ]
    function providerOf(acct) { const a = accounts.find(x => x.id === acct); return a ? a.provider : ""; }
    // Category tabs are the same for every account: Gmail has them natively, any other account maps a tab to one of its
    // folders (Account settings > Category tabs, `catmap:<account>` in the UI state); Primary is always the inbox.
    property var catMaps: ({})
    property var accountFolders: ({})
    function readCatMaps() {
        const m = {};
        for (const a of accounts) {
            try { m[a.id] = JSON.parse(Facteur.uiGet("catmap:" + a.id) || "{}"); } catch (e) { m[a.id] = {}; }
        }
        catMaps = m;
    }
    function saveCatMap(acct, cat, folder) {
        const next = Object.assign({}, catMaps[acct] || {});
        if (folder === "") delete next[cat]; else next[cat] = folder;
        Facteur.uiSet("catmap:" + acct, JSON.stringify(next));
        const all = Object.assign({}, catMaps);
        all[acct] = next;
        catMaps = all;
    }
    // The same five tabs for every account
    function availableCats() { return categories.map(c => c.key); }
    onAccountsChanged: {
        readCatMaps();
        for (const a of accounts) {
            if (a.provider === "imap" || a.provider === "outlook") Facteur.loadFolders(a.id);
            else if (a.provider === "gmail") Facteur.loadLabels(a.id);
        }
    }
    function isGmail() { const a = accounts.find(x => x.id === account); return !!a && a.provider === "gmail"; }
    // The tab system is used or not ("Show Tabs" in the bar menu and the header): used, the band shows the default tabs and the folders pinned with "+"; not, the list alone.
    property bool categoryTabs: Facteur.uiGet("category_tabs2") !== "0"
    function toggleCategoryTabs() {
        categoryTabs = !categoryTabs;
        Facteur.uiSet("category_tabs2", categoryTabs ? "1" : "0");
    }
    function categoriesOn() { return (mailbox === "inbox" || unified) && categoryTabs; }

    // Tabs above the list: the Gmail categories and the folders the user pinned ("+"), in the order they dragged them to.
    // A tab key is "cat:<category>" or "box:<mailbox>"; the list is kept per account (stored: [{key, icon}], null = default).
    property var storedTabs: null
    function tabsKey() { return unified ? "tabs:all" : "tabs:" + account; }
    function readTabs() {
        let v = null;
        try { v = JSON.parse(Facteur.uiGet(tabsKey()) || "null"); } catch (e) { v = null; }
        storedTabs = Array.isArray(v) ? v : null;
    }
    function saveTabs(entries) {
        storedTabs = entries;
        Facteur.uiSet(tabsKey(), JSON.stringify(entries));
    }
    readonly property var boxNames: ({ inbox: Facteur.tr("Inbox"), unread: Facteur.tr("Unread"), starred: Facteur.tr("Starred"), sent: Facteur.tr("Sent"), drafts: Facteur.tr("Drafts"), archive: Facteur.tr("Archive"), spam: Facteur.tr("Spam"), trash: Facteur.tr("Trash") })
    readonly property var boxIcons: ({ inbox: "inbox", unread: "mail", starred: "star", sent: "forward", drafts: "compose", archive: "archive", spam: "spam", trash: "trash" })
    function boxIcon(box) { return boxIcons[box] || "tag"; }
    readonly property var tabItems: {
        const cats = categoryTabs ? categories.map(c => ({ key: "cat:" + c.key, label: c.label, icon: c.icon })) : [];
        const out = [];
        const seen = {};
        for (const e of (storedTabs || cats)) {
            if (e.key.startsWith("cat:")) {
                const c = cats.find(c => c.key === e.key);
                if (c && !seen[c.key]) { out.push(c); seen[c.key] = true; }
            } else {
                const box = e.key.slice(4);
                // A folder the category tabs already show is not shown twice
                if (categoryTabs && (box === "inbox" || (account !== "" && Object.values(catMaps[account] || {}).includes(box.slice(7))))) continue;
                out.push({ key: e.key, label: boxLabel(box), icon: e.icon || boxIcon(box) });
            }
        }
        return cats.filter(c => !seen[c.key]).concat(out);
    }
    readonly property string currentTab: categoriesOn() ? "cat:" + category : "box:" + mailbox
    // Unread messages of a tab for one account, from what is already known (no request of its own):
    // Gmail category counts, the inbox count, the unread count of the folders list
    function folderUnread(acct, id) {
        const l = (accountFolders[acct] || []).find(l => l.id === id);
        return l ? l.unread || 0 : 0;
    }
    function acctTabCount(acct, key) {
        if (key.startsWith("cat:")) {
            const c = key.slice(4);
            if (providerOf(acct) === "gmail") return (categoryCounts[acct] || {})[c] || 0;
            if (c === "primary") return unreadCounts[acct] || 0;
            const f = (catMaps[acct] || {})[c];
            return f ? folderUnread(acct, f) : 0;
        }
        const box = key.slice(4);
        if (box === "inbox") return unreadCounts[acct] || 0;
        if (box.startsWith("folder:")) return folderUnread(acct, box.slice(7));
        if (box.startsWith("label:")) {
            const l = (accountFolders[acct] || []).find(l => !l.folder && l.rawName === box.slice(6));
            return l ? l.unread || 0 : 0;
        }
        return 0;
    }
    // Counts shown after the tab names; in the Inbox views, summed over the accounts
    readonly property var tabCounts: {
        const out = {};
        const accts = unified ? accounts.map(a => a.id) : [account];
        for (const t of tabItems) {
            let n = 0;
            for (const a of accts) n += acctTabCount(a, t.key);
            if (n > 0) out[t.key] = n;
        }
        return out;
    }
    function chooseTab(key) {
        if (key.startsWith("cat:")) { if (!unified) mailbox = "inbox"; category = key.slice(4); }
        else mailbox = key.slice(4);
    }
    function reorderTabs(keys) {
        const entries = keys.map(k => { const t = tabItems.find(t => t.key === k); return k.startsWith("box:") ? { key: k, icon: t ? t.icon : boxIcon(k.slice(4)) } : { key: k }; });
        saveTabs(entries);
    }
    function removeTab(key) {
        if (key.startsWith("cat:")) return;
        saveTabs(tabItems.filter(t => t.key !== key).map(t => t.key.startsWith("box:") ? { key: t.key, icon: t.icon } : { key: t.key }));
    }
    // Folders that are not tabs yet
    function pinnableFolders() {
        const pinned = {};
        for (const t of tabItems) pinned[t.key] = true;
        const out = [];
        for (const k in boxNames) {
            if (k === "inbox" && categoryTabs) continue;
            if (!pinned["box:" + k]) out.push({ key: "box:" + k, label: boxNames[k], icon: boxIcon(k) });
        }
        for (const l of labels) {
            const k = "box:" + (l.folder ? "folder:" + l.id : "label:" + l.rawName);
            if (!pinned[k]) out.push({ key: k, label: l.rawName, icon: "tag" });
        }
        return out;
    }
    function addTab(key, icon) {
        const entries = tabItems.map(t => t.key.startsWith("box:") ? { key: t.key, icon: t.icon } : { key: t.key });
        const i = entries.findIndex(e => e.key === key);
        if (i >= 0) entries[i].icon = icon; else entries.push({ key: key, icon: icon });
        saveTabs(entries);
    }
    // Right click in the sidebar: an account (edit, remove) or a label (edit, delete)
    property var contextData: null
    property string contextKind: ""
    property var deletingLabel: null
    function folderName(acct, id) {
        const l = (accountFolders[acct] || []).find(l => l.id === id);
        return l ? l.rawName : id;
    }
    function openContext(kind, data, x, y) {
        if (kind === "tab" && data.startsWith("cat:")) return; // the category tabs cannot be removed
        contextKind = kind;
        contextData = data;
        if (kind === "catpick") {
            popup.openAt(x, y, [{ id: "none", label: Facteur.tr("None") }].concat((accountFolders[accountDialog.accountId] || []).map(l => ({ id: l.id, label: l.rawName }))));
            return;
        }
        const entries = kind === "tab"
            ? (data.startsWith("cat:") ? [{ id: "hide", label: Facteur.tr("Hide Category Tabs") }]
               : [{ id: "icon", label: Facteur.tr("Change Icon…") }, { id: "remove", label: Facteur.tr("Remove Tab"), danger: true }])
            : kind === "label" && data.folder
            ? [{ id: "edit", label: Facteur.tr("Rename…") }, { id: "color", label: Facteur.tr("Change colour…") }, { id: "delete", label: Facteur.tr("Delete…"), danger: true }]
            : kind === "account"
            ? [{ id: "edit", label: Facteur.tr("Edit account…") }, { id: "remove", label: Facteur.tr("Remove account…"), danger: true }]
            : [{ id: "edit", label: Facteur.tr("Edit label…") }, { id: "delete", label: Facteur.tr("Delete label…"), danger: true }];
        popup.openAt(x, y, entries);
    }
    // Right click on the page of a message: link, picture and selection actions
    function openPageMenu(x, y, link, image) {
        contextKind = "page";
        contextData = link;
        const entries = [];
        if (link !== "") {
            entries.push({ id: "open-link", label: Facteur.tr("Open Link") });
            entries.push({ id: "copy-link", label: link.startsWith("mailto:") ? Facteur.tr("Copy Email Address") : Facteur.tr("Copy Link Address") });
        }
        if (image) entries.push({ id: "copy-image", label: Facteur.tr("Copy Image") });
        if (reader.hasSelection) entries.push({ id: "copy", label: Facteur.tr("Copy") });
        entries.push({ id: "select-all", label: Facteur.tr("Select All") });
        popup.openAt(x, y, entries);
    }
    // Right click on a message of the list: the ticked messages when it is one of them, else this one alone
    property string pendingCompose: ""
    function openMessageMenu(index, x, y) {
        const row = messages.get(index);
        if (!row || row.id.startsWith("draft:")) return;
        const multi = checkedCount > 0 && row.checked;
        const unread = multi ? checkedAnyUnread : row.unread;
        const starred = multi ? checkedAllStarred : row.starred;
        contextKind = "message";
        contextData = { ids: multi ? checkedIds() : [row.id], id: row.id };
        const entries = [];
        if (!multi) {
            entries.push({ id: "reply", label: Facteur.tr("Reply") });
            entries.push({ id: "replyall", label: Facteur.tr("Reply all") });
            entries.push({ id: "forward", label: Facteur.tr("Forward") });
        }
        entries.push({ id: unread ? "read" : "unread", label: unread ? Facteur.tr("Mark as read") : Facteur.tr("Mark as unread") });
        entries.push({ id: starred ? "unstar" : "star", label: starred ? Facteur.tr("Remove star") : Facteur.tr("Star message") });
        entries.push({ id: "archive", label: Facteur.tr("Archive message") });
        entries.push({ id: "spam", label: Facteur.tr("Mark as spam") });
        entries.push({ id: "trash", label: Facteur.tr("Move to trash"), danger: true });
        popup.openAt(x, y, entries);
    }
    function runContext(id) {
        if (contextKind === "message") {
            if (id === "reply" || id === "replyall" || id === "forward") {
                // Writing needs the message open: open it first, the answer starts the draft (onOpened)
                if (selectedId === contextData.id && reader.summary !== null) startCompose(id);
                else { pendingCompose = id; choose(contextData.id); }
            } else doActMany(id, contextData.ids);
        } else if (contextKind === "page") {
            reader.pageAction(id, contextData);
        } else if (contextKind === "catpick") {
            saveCatMap(accountDialog.accountId, contextData, id === "none" ? "" : id);
            accountDialog.catMap = catMaps[accountDialog.accountId] || {};
        } else if (contextKind === "tab") {
            const t = tabItems.find(t => t.key === contextData);
            if (id === "icon" && t) folderTabDialog.edit(t.key, t.label, t.icon);
            else removeTab(contextData);
        } else if (contextKind === "account") {
            if (id === "remove") { removing = contextData.id; return; }
            const d = JSON.parse(Facteur.accountDetails(contextData.id));
            if (d.error) { notice = errorText(d.error); return; }
            accountDialog.catMap = catMaps[d.id] || {};
            accountDialog.edit(d);
            if (d.provider === "imap" || d.provider === "outlook") Facteur.loadFolders(d.id);
        } else if (id === "color") {
            labelDialog.pickColor(contextData);
        } else if (id === "edit") {
            labelDialog.edit(contextData);
        } else {
            deletingLabel = contextData;
        }
    }
    // A stable colour for a name (Proton's label palette)
    readonly property var nameColors: ["#8080ff", "#db60d6", "#ec3e7c", "#f78400", "#936d58", "#5252cc", "#a839a4", "#ba1e55", "#c44800", "#415df0", "#179fd9", "#1da583", "#3cbb3a", "#b4a40e"]
    function nameColor(name) {
        let h = 0;
        for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0;
        return nameColors[h % nameColors.length];
    }
    // IMAP account whose server is Proton Bridge (labels and folders live under "Labels/" and "Folders/")
    property bool bridge: false
    function isImap() { const a = accounts.find(x => x.id === account); return !!a && (a.provider === "imap" || a.provider === "outlook"); }
    // Which pane has the keyboard: 0 sidebar, 1 list, 2 reader
    property int pane: 1
    function focusPane(n) {
        pane = ((n % 3) + 3) % 3;
        Facteur.keyNav = true;
        if (pane === 0) sidebar.forceActiveFocus();
        else if (pane === 1) messageList.focusList();
        else reader.focusReader();
    }
    function confirmDeleteLabel() {
        const gone = deletingLabel;
        if (!gone) return;
        if (mailbox === "label:" + gone.rawName || mailbox === "folder:" + gone.id) mailbox = "inbox";
        if (gone.folder) Facteur.deleteFolder(account, gone.id); else Facteur.deleteLabel(account, gone.id);
        deletingLabel = null;
    }
    function loadLabels() {
        labels = [];
        bridge = false;
        if (isImap()) {
            const d = JSON.parse(Facteur.accountDetails(account));
            bridge = !d.error && !!d.imap && d.imap.imapHost === "127.0.0.1";
        }
        const a = accounts.find(x => x.id === account);
        if (a && a.provider === "gmail") Facteur.loadLabels(account);
        else if (a && (a.provider === "imap" || a.provider === "outlook")) Facteur.loadFolders(account);
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
    // A notice that is not an error links to a folder (where a file was saved); errors have none
    property string noticeFolder: ""
    onNoticeChanged: if (notice === "") noticeFolder = ""

    // Message being written (the pane next to the list shows the form instead of the reader)
    // Several messages can be written at once: one card each in the dock, one of them open, the others reduced to a bar
    property string activeDraft: ""
    // The cards are one frame with a tab each; the frame is reduced to its header bar when minimised
    property bool dockMinimized: false
    readonly property bool composing: activeDraft !== "" && !dockMinimized
    property bool sending: false
    property string sendingKey: ""
    ListModel { id: draftModel }

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
        if (account === "" || (kind !== "new" && (reader.summary === null || reader.loadingNext)))
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
            const self = selectedRef.acct.replace(/^[a-z]+:/, "").toLowerCase();
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
        if (kind === "reply" || kind === "replyall") {
            const s = reader.summary;
            draft.inReplyTo = s.messageId || "";
            draft.references = ((s.inReplyTo || "") + " " + (s.messageId || "")).trim();
        }
        openDraft(kind === "new" ? account : selectedRef.acct, draft, "");
    }

    function newKey() { return Date.now().toString(36) + Math.random().toString(36).slice(2, 6) }
    function openDraft(acc, draft, key) {
        dockMinimized = false;
        if (key !== "" && draftIndex(key) >= 0) {
            activeDraft = key;
            return;
        }
        key = key || newKey();
        draftModel.append({ key: key, account: acc, init: JSON.stringify(draft), title: draft.subject || "" });
        activeDraft = key;
    }
    function draftIndex(key) {
        for (let i = 0; i < draftModel.count; i++)
            if (draftModel.get(i).key === key) return i;
        return -1;
    }
    // The card leaves the dock; its copy on this computer stays unless the draft is thrown away or sent
    function closeDraft(key, forget) {
        const i = draftIndex(key);
        if (i >= 0) draftModel.remove(i);
        if (activeDraft === key) activeDraft = draftModel.count > 0 ? draftModel.get(draftModel.count - 1).key : "";
        if (forget) Facteur.deleteDraft(key);
        showLocalDrafts();
    }
    function keepDraft(key, acc, fields) {
        const empty = !(fields.to.trim() || fields.cc.trim() || fields.bcc.trim() || fields.subject.trim() || fields.body.trim() || fields.files.length);
        if (empty) Facteur.deleteDraft(key);
        else Facteur.saveDraft(key, JSON.stringify(Object.assign({ key: key, account: acc, savedAt: Date.now() }, fields)));
        showLocalDrafts();
    }
    function localDrafts() {
        try { return JSON.parse(Facteur.drafts()) } catch (e) { return [] }
    }
    // Drafts found from an earlier run come back as bars in the dock
    function restoreDrafts() {
        for (const d of localDrafts())
            if (d.key && accounts.some(a => a.id === d.account) && draftIndex(d.key) < 0)
                draftModel.append({ key: d.key, account: d.account, init: JSON.stringify(d), title: d.subject || "" });
        if (draftModel.count > 0) {
            activeDraft = draftModel.get(0).key;
            dockMinimized = true;
        }
    }
    // The Drafts mailbox lists the ones kept here first (the server does not have them)
    function showLocalDrafts() {
        for (let i = messages.count - 1; i >= 0; i--)
            if (messages.get(i).id.startsWith("draft:")) messages.remove(i);
        if (mailbox !== "drafts" || query !== "" || account === "") return;
        const mine = localDrafts().filter(d => d.account === account).sort((a, b) => b.savedAt - a.savedAt);
        mine.forEach((d, i) => messages.insert(i, { id: "draft:" + d.key, from: Facteur.tr("Draft"), subject: d.subject || Facteur.tr("(no subject)"), time: d.to || "", unread: false, starred: false, checked: false }));
    }
    function openLocalDraft(id) {
        const key = id.slice(6);
        const d = localDrafts().find(x => x.key === key);
        if (d) openDraft(d.account, d, key);
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
            "attachment_open_refused": Facteur.tr("This kind of file is not opened from a message: download it instead."),
            "attachment_open_failed": Facteur.tr("No application could open this file."),
            "attachment_unavailable": Facteur.tr("This attachment is not available."),
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
        // Nothing selected yet: "next" opens the first message
        const i = selectedId === "" ? (delta > 0 ? 0 : -1) : rowOf(selectedId) + delta;
        if (i >= 0 && i < messages.count)
            choose(messages.get(i).id);
    }
    function boxLabel(box) {
        if (box === undefined) box = mailbox;
        if (box === "all") return Facteur.tr("All inboxes");
        if (box === "allunread") return Facteur.tr("All unread");
        return boxNames[box] || (box.startsWith("label:") ? box.slice(6) : box.startsWith("folder:") ? ((labels.find(l => l.id === box.slice(7)) || {}).rawName || box.slice(7)) : box);
    }
    // Unread rows of the list, kept up to date as the rows change (a binding cannot see a role change by itself)
    property int unreadTotal: 0
    function updateUnreadTotal() { unreadTotal = unreadCount() }
    Connections {
        target: messages
        function onDataChanged() { win.updateUnreadTotal() }
        function onRowsInserted() { win.updateUnreadTotal() }
        function onRowsRemoved() { win.updateUnreadTotal() }
        function onModelReset() { win.updateUnreadTotal() }
    }
    // The inbox count of the sidebar follows an action at once (the server's figure comes after)
    function bumpUnread(delta, acct) {
        if (acct === undefined) acct = account;
        if (delta === 0 || acct === "") return;
        const next = Object.assign({}, unreadCounts);
        next[acct] = Math.max(0, (next[acct] || 0) + delta);
        unreadCounts = next;
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
    property int autoPages: 0
    // Search on IMAP: "quick" (headers of the mailbox shown), "full" (content of the whole account, merged after), or ""
    property string searchPhase: ""
    function loadMore() {
        if (nextToken === "" || loading || loadingMore || account === "" || listError !== "")
            return;
        loadingMore = true;
        Facteur.list(account, listBox(), listQuery(), nextToken);
    }
    // Unread messages of each account's inbox ({accountId: count}), shown in the sidebar
    property var unreadCounts: ({})
    // Unread messages of each Gmail category tab ({key: count}) of the current account
    property var categoryCounts: ({})
    function countUnread() {
        for (const a of accounts)
            Facteur.countUnread(a.id);
        // The tabs of the accounts on screen only (all of them in the Inbox views); Gmail counts each category, the others
        // reload their folders list (one request, it also feeds the sidebar), and only when a tab is linked to a folder
        if (categoryTabs)
            for (const a of accounts) {
                if (!unified && a.id !== account) continue;
                if (a.provider === "gmail") for (const c of categories) Facteur.countCategory(a.id, c.key);
                else if (Object.keys(catMaps[a.id] || {}).length > 0) Facteur.loadFolders(a.id);
            }
    }
    Timer { interval: 60000; running: win.accounts.length > 0; repeat: true; triggeredOnStart: true; onTriggered: win.countUnread() }
    function appendMessages(list, known, acct) {
        for (const m of list) {
            const id = acct ? acct + sep + m.id : m.id;
            if ((!listBar.unreadOnly || m.unread) && !known.has(id))
                messages.append({ id: id, acct: acct || "", date: m.date || "", attach: m.hasAttachment === true, labels: JSON.stringify(m.labelIds || []), from: m.from.display || m.from.email || "", subject: m.subject, time: m.time, unread: m.unread, starred: m.starred, checked: false });
        }
    }
    // One answer of an account for the unified list: merged, newest first
    property bool unifiedFresh: false
    function mergeUnified(acc, json) {
        const r = JSON.parse(json);
        if (unifiedFresh) { messages.clear(); unifiedFresh = false; }
        unifiedPending = Math.max(0, unifiedPending - 1);
        if (r.error) {
            listError = errorText(r.error);
        } else {
            const rows = [];
            for (let i = 0; i < messages.count; i++) { const m = messages.get(i); rows.push({ id: m.id, acct: m.acct, date: m.date, attach: m.attach, labels: m.labels, from: m.from, subject: m.subject, time: m.time, unread: m.unread, starred: m.starred, checked: m.checked }); }
            const known = new Set(rows.map(m => m.id));
            for (const m of r.messages)
                if ((!(listBar.unreadOnly || mailbox === "allunread") || m.unread) && !known.has(acc + sep + m.id))
                    rows.push({ id: acc + sep + m.id, acct: acc, date: m.date || "", attach: m.hasAttachment === true, labels: JSON.stringify(m.labelIds || []), from: m.from.display || m.from.email || "", subject: m.subject, time: m.time, unread: m.unread, starred: m.starred, checked: false });
            rows.sort((a, b) => a.date < b.date ? 1 : a.date > b.date ? -1 : 0);
            messages.clear();
            for (const m of rows) messages.append(m);
        }
        if (unifiedPending === 0) loading = false;
    }
    function refresh() {
        // What the mailbox showed last time, at once; the server's answer replaces it
        if (unified) {
            nextToken = "";
            loadingMore = false;
            searchPhase = "";
            checkedCount = 0;
            checkAnchor = -1;
            countUnread();
            loading = true;
            listError = "";
            unifiedFresh = true;
            unifiedPending = 0;
            for (const a of accounts) {
                const sp = listSpec(a.id);
                if (!sp) continue;
                unifiedPending++;
                Facteur.list(a.id, sp.box, sp.query, "");
            }
            if (unifiedPending === 0) { messages.clear(); loading = false; }
            return;
        }
        if (!unified && account !== "" && categoriesOn() && listSpec(account) === null) {
            messages.clear();
            loading = false;
            listError = "";
            checkedCount = 0;
            return;
        }
        if (messages.count === 0 && account !== "" && query === "") {
            const kept = Facteur.cachedList(account, listBox() + (categoriesOn() ? "#" + category : ""));
            if (kept !== "") {
                try { appendMessages(JSON.parse(kept).messages || [], new Set()) } catch (e) {}
            }
            showLocalDrafts();
        }
        nextToken = "";
        autoPages = 0;
        loadingMore = false;
        searchPhase = "";
        checkedCount = 0;
        checkAnchor = -1;
        if (account === "")
            return;
        countUnread();
        loading = true;
        listError = "";
        // IMAP: a quick pass in the mailbox shown (subject, sender, recipients), then the whole account and the content
        if (query !== "" && isImap()) {
            searchPhase = "quick";
            Facteur.list(account, listBox(), "scope:headers " + listQuery(), "");
        } else {
            searchPhase = "";
            Facteur.list(account, listBox(), listQuery(), "");
        }
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
        // Drafts kept on this computer: only removing makes sense
        const local = ids.filter(id => id.startsWith("draft:"));
        if (local.length > 0) {
            if (operation === "trash" || operation === "archive" || operation === "spam")
                for (const id of local) closeDraft(id.slice(6), true);
            ids = ids.filter(id => !id.startsWith("draft:"));
        }
        if (account === "" || ids.length === 0)
            return;
        const deltas = {};
        for (const id of ids) {
            const i = rowOf(id);
            if (i < 0) continue;
            const a = splitId(id).acct;
            const wasUnread = messages.get(i).unread;
            if (operation === "read" && wasUnread) deltas[a] = (deltas[a] || 0) - 1;
            else if (operation === "unread" && !wasUnread) deltas[a] = (deltas[a] || 0) + 1;
            else if ((operation === "archive" || operation === "trash" || operation === "spam") && wasUnread) deltas[a] = (deltas[a] || 0) - 1;
        }
        for (const a in deltas) bumpUnread(deltas[a], a);
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
        const groups = {};
        for (const id of ids) { const r = splitId(id); (groups[r.acct] = groups[r.acct] || []).push(r.id); }
        for (const a in groups) Facteur.act(a, operation, JSON.stringify(groups[a]));
    }

    function choose(id, quiet) {
        if (id.startsWith("draft:"))
            return;
        selectedId = id;
        const row = rowOf(id);
        reader.unread = row >= 0 ? messages.get(row).unread : false;
        reader.starred = row >= 0 ? messages.get(row).starred : false;
        // Opening a message reads it
        if (row >= 0 && messages.get(row).unread)
            doAct("read", id);
        // The message shown stays until this one arrives (`onOpened`): no blank page in between
        reader.error = "";
        reader.loadingNext = true;
        Facteur.openMessage(splitId(id).acct, splitId(id).id);
    }

    Connections {
        target: Facteur
        function onUnreadCounted(acc, count) {
            const next = Object.assign({}, win.unreadCounts);
            if (count >= 0) next[acc] = count;
            win.unreadCounts = next;
        }
        function onCategoryCounted(acc, cat, count) {
            if (count < 0) return;
            const next = Object.assign({}, win.categoryCounts);
            next[acc] = Object.assign({}, next[acc] || {});
            next[acc][cat] = count;
            win.categoryCounts = next;
        }
        function onListed(acc, box, rawQry, json) {
            const quick = rawQry.startsWith("scope:headers ");
            const qry = quick ? rawQry.slice(14) : rawQry;
            if (win.unified) {
                const sp = win.listSpec(acc);
                if (sp && box === sp.box && qry === sp.query) win.mergeUnified(acc, json);
                return;
            }
            if (acc !== win.account || box !== win.listBox() || qry !== win.listQuery())
                return;
            const r = JSON.parse(json);
            // The slow pass of a search is merged after the quick one
            const merge = !quick && win.searchPhase === "full";
            if (merge) {
                win.searchPhase = "";
                if (r.error) return;
            }
            const more = !merge && (r.append === true || (!!r.error && win.loadingMore));
            if (more && !win.loadingMore)
                return; // the answer of a list that was refreshed since
            win.loadingMore = false;
            if (more && r.error) {
                win.notice = win.errorText(r.error);
                return;
            }
            win.loading = false;
            if (!more && !merge)
                messages.clear();
            if (r.error) {
                win.listError = win.errorText(r.error);
                return;
            }
            if (!quick)
                win.nextToken = r.nextPageToken || "";
            const known = new Set();
            if (more || merge)
                for (let i = 0; i < messages.count; i++) known.add(messages.get(i).id);
            win.appendMessages(r.messages, known);
            win.showLocalDrafts();
            // "Unread only" filters the pages as they come: while few rows pass and more pages exist, fetch some more
            // (a few pages at most, so a mailbox without unread mail does not read everything)
            if (!quick && listBar.unreadOnly && win.nextToken !== "" && messages.count < 25 && win.autoPages < 4) {
                win.autoPages++;
                Qt.callLater(win.loadMore);
            }
            if (quick) {
                // Now the full search: content, whole account; its results come after these
                win.searchPhase = "full";
                Facteur.list(acc, box, qry, "");
            }
        }
        // Menu of the fili-bar (fili-mail ctl action NAME)
        function onCommand(name) {
            const boxes = { "inbox": "inbox", "unread-box": "unread", "starred": "starred", "sent": "sent", "drafts": "drafts", "archive-box": "archive", "spam-box": "spam", "trash-box": "trash" };
            const onMessage = !win.adding && !win.composing && win.selectedId !== "";
            if (name === "about") aboutCard.show();
            else if (name === "shortcuts") shortcutsCard.show();
            else if (name === "close") Qt.quit();
            else if (name === "window-actions") { if (win.mainView) windowPanel.visible ? windowPanel.close() : windowPanel.open() }
            else if (name === "toggle-header") win.showHeader = !win.showHeader;
            else if (name === "toggle-footer") win.showFooter = !win.showFooter;
            else if (name === "toggle-window-buttons") win.toggleWindowButtons();
            else if (name === "toggle-category-tabs") win.toggleCategoryTabs();
            else if (name === "add-account") { win.addError = ""; win.adding = true }
            else if (name === "new-message") win.startCompose("new");
            else if (name === "reply" || name === "forward") win.startCompose(name);
            else if (name === "reply-all") win.startCompose("replyall");
            else if (name === "next-message" || name === "previous-message") {
                if (win.selectedId === "" && messages.count > 0) win.choose(messages.get(0).id);
                else win.step(name === "next-message" ? 1 : -1);
            }
            else if (name === "refresh") win.refresh();
            else if (name === "load-pictures") { if (reader.remoteImages > 0 && !reader.loadingImages) { reader.loadingImages = true; Facteur.loadImages(win.selectedRef.acct, win.selectedRef.id) } }
            else if (name === "copy") { if (!win.composing && !win.adding) reader.copySelection() }
            else if (name === "select-all") { if (!win.composing && !win.adding) reader.selectAllText() }
            else if (boxes[name]) { win.adding = false; win.mailbox = boxes[name] }
            else if (onMessage) win.doAct(name, win.selectedId);
        }
        function onSent(json) {
            const key = win.sendingKey;
            win.sending = false;
            win.sendingKey = "";
            const r = JSON.parse(json);
            if (r.error) {
                const card = dock.cardOf(key);
                if (card) card.error = win.errorText(r.error);
                return;
            }
            win.closeDraft(key, true);
            win.notice = "";
        }
        function onOpened(id, json) {
            if (id !== win.selectedRef.id)
                return;
            const r = JSON.parse(json);
            reader.loadingNext = false;
            if (r.error) {
                win.pendingCompose = "";
                reader.summary = null;
                reader.error = win.errorText(r.error);
                return;
            }
            reader.summary = r.message.summary;
            reader.body = r.message.nativeContent.body.text;
            if (win.pendingCompose !== "") { const kind = win.pendingCompose; win.pendingCompose = ""; Qt.callLater(() => win.startCompose(kind)); }
            reader.rich = r.message.rich || "";
            reader.html = r.message.html || "";
            reader.remoteImages = r.message.remoteImages || 0;
            reader.unsubscribeUrl = (r.message.unsubscribe && r.message.unsubscribe.urls && r.message.unsubscribe.urls[0]) || "";
            reader.attachments = r.message.nativeContent.attachments || [];
            reader.loadingImages = false;
        }
        function onAttachmentSaved(json) {
            const r = JSON.parse(json);
            win.noticeFolder = "";
            if (r.error) win.notice = win.errorText(r.error);
            else if (r.opened) win.notice = "";
            else {
                // A file gives its path, several give their folder
                const folder = r.count !== undefined ? r.path : r.path.replace(/\/[^\/]*$/, "");
                const shown = folder.replace(/^\/home\/[^\/]+/, "~");
                win.notice = r.count !== undefined ? Facteur.tr("%1 attachments saved to %2").replace("%1", r.count).replace("%2", shown) : Facteur.tr("Saved to %1").replace("%1", shown);
                win.noticeFolder = folder;
            }
        }
        function onLabelsLoaded(acc, json) {
            const kept = Object.assign({}, win.accountFolders);
            kept[acc] = JSON.parse(json);
            win.accountFolders = kept;
            if (acc !== win.account) return;
            // IMAP labels come without colour: the one chosen here, else one taken from the name (stable)
            win.labels = JSON.parse(json).map(l => l.folder ? Object.assign({}, l, { color: Facteur.uiGet("color:" + acc + ":" + l.id) || win.nameColor(l.rawName) }) : l);
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
            if (acc !== win.account && !win.unified)
                return;
            const r = JSON.parse(json);
            if (r.error) {
                win.notice = win.errorText(r.error);
                win.refresh();
            } else {
                Facteur.countUnread(acc);
                if (win.categoriesOn() && win.providerOf(acc) === "gmail") Facteur.countCategory(acc, win.category);
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
        restoreDrafts();
        visit();
        refresh();
    }
    onSelectedIdChanged: if (selectedId === "") reader.loadingNext = false
    onAccountChanged: { readTabs(); category = "primary"; messages.clear(); selectedId = ""; reader.summary = null; if (mailbox.startsWith("label:") || mailbox.startsWith("folder:") || unified) mailbox = "inbox"; loadLabels(); visit(); refresh() }
    onMailboxChanged: { readTabs(); messages.clear(); selectedId = ""; reader.summary = null; visit(); refresh() }
    onCategoryTabsChanged: { messages.clear(); selectedId = ""; reader.summary = null; refresh() }
    onCategoryChanged: { if (categoriesOn()) { messages.clear(); selectedId = ""; reader.summary = null; refresh() } }
    onQueryChanged: { messages.clear(); selectedId = ""; reader.summary = null; visit(); refresh() }

    Shortcut { sequences: ["Ctrl+Q", "Ctrl+W"]; onActivated: Qt.quit() }
    // Keyboard: the three panes (F6 / Shift+F6 go round them, Alt+1 2 3 go straight), the tabs, the filter, the layout
    Shortcut { sequences: ["F6"]; enabled: !win.adding && win.account !== ""; onActivated: win.focusPane(win.pane + 1) }
    Shortcut { sequences: ["Shift+F6"]; enabled: !win.adding && win.account !== ""; onActivated: win.focusPane(win.pane - 1) }
    Shortcut { sequences: ["Alt+1"]; enabled: !win.adding && win.account !== ""; onActivated: win.focusPane(0) }
    Shortcut { sequences: ["Alt+2"]; enabled: !win.adding && win.account !== ""; onActivated: win.focusPane(1) }
    Shortcut { sequences: ["Alt+3"]; enabled: !win.adding && win.account !== ""; onActivated: win.focusPane(2) }
    Shortcut { sequences: ["Ctrl+1"]; enabled: win.categoriesOn(); onActivated: win.category = win.categories[0].key }
    Shortcut { sequences: ["Ctrl+2"]; enabled: win.categoriesOn(); onActivated: win.category = win.categories[1].key }
    Shortcut { sequences: ["Ctrl+3"]; enabled: win.categoriesOn(); onActivated: win.category = win.categories[2].key }
    Shortcut { sequences: ["Ctrl+4"]; enabled: win.categoriesOn(); onActivated: win.category = win.categories[3].key }
    Shortcut { sequences: ["Ctrl+5"]; enabled: win.categoriesOn(); onActivated: win.category = win.categories[4].key }
    Shortcut { sequences: ["Ctrl+U"]; enabled: !win.adding && win.account !== ""; onActivated: listBar.unreadOnly = !listBar.unreadOnly }
    Shortcut { sequences: ["Ctrl+Shift+P"]; enabled: !win.adding; onActivated: win.togglePreview() }
    Shortcut { sequences: ["Ctrl+Shift+L"]; enabled: !win.adding && win.account !== ""; onActivated: { labelDialog.error = ""; labelDialog.imap = win.isImap(); labelDialog.bridge = win.bridge; labelDialog.open() } }
    Shortcut { sequences: ["F1", "Ctrl+/"]; onActivated: shortcutsCard.show() }
    // The confirmation bars answer to Enter and Esc
    Shortcut { sequences: ["Return", "Enter"]; enabled: win.deletingLabel !== null; onActivated: win.confirmDeleteLabel() }
    Shortcut { sequences: ["Escape"]; enabled: win.deletingLabel !== null; onActivated: win.deletingLabel = null }
    Shortcut { sequences: ["Return", "Enter"]; enabled: win.removing !== ""; onActivated: Facteur.removeAccount(win.removing) }
    Shortcut { sequences: ["Escape"]; enabled: win.removing !== ""; onActivated: win.removing = "" }
    Shortcut { sequences: ["Ctrl+Shift+W"]; enabled: win.mainView; onActivated: windowPanel.visible ? windowPanel.close() : windowPanel.open() }
    Shortcut { sequences: ["F5", "Ctrl+R"]; enabled: !win.adding && win.account !== ""; onActivated: win.refresh() }
    Shortcut { sequences: ["Alt+Left"]; enabled: !win.adding && win.hindex > 0; onActivated: win.go(-1) }
    Shortcut { sequences: ["Alt+Right"]; enabled: !win.adding && win.hindex < win.history.length - 1; onActivated: win.go(1) }
    Shortcut { sequences: ["Ctrl+F"]; enabled: !win.adding && win.account !== "" && !win.composing; onActivated: win.openSearch() }
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
        visible: win.headerShown
        width: parent.width
        height: win.headerShown ? FiliTheme.toolbarHeight : 0
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
            readonly property int at: win.selectedId === "" ? -1 : win.rowOf(win.selectedId)
            IconButton { name: "chevron-left"; tip: Facteur.tr("Previous message"); enabledState: parent.at > 0; onClicked: win.step(-1) }
            IconButton { name: "chevron-right"; tip: Facteur.tr("Next message"); enabledState: parent.at < messages.count - 1 && messages.count > 0; onClicked: win.step(1) }
            Rectangle { width: 1; height: 18; anchors.verticalCenter: parent.verticalCenter; color: FiliTheme.border }
            IconButton { name: "compose"; tip: Facteur.tr("New message"); onClicked: win.startCompose("new") }
            IconButton { name: "mail-unread"; toggled: listBar.unreadOnly; tip: Facteur.tr("Unread only"); onClicked: listBar.unreadOnly = !listBar.unreadOnly }
            IconButton { name: "refresh"; tip: Facteur.tr("Refresh"); onClicked: win.refresh() }
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
                text: win.checkedCount > 0 ? Facteur.tr("%1 selected").replace("%1", win.checkedCount) : win.loading ? (win.query !== "" ? Facteur.tr("Searching…") : Facteur.tr("Loading…")) : win.listError !== "" ? "" : Facteur.tr("%1 messages, %2 unread").replace("%1", messages.count).replace("%2", win.unreadTotal)
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
            readonly property bool on: win.selectedId !== "" || win.checkedCount > 0
            readonly property bool unreadNow: win.checkedCount > 0 ? win.checkedAnyUnread : reader.unread
            readonly property bool starredNow: win.checkedCount > 0 ? win.checkedAllStarred : reader.starred
            IconButton { visible: win.checkedCount > 0; name: parent.unreadNow ? "mail-open" : "mail"; tip: parent.unreadNow ? Facteur.tr("Mark as read") : Facteur.tr("Mark as unread"); enabledState: parent.on; onClicked: win.actOnSelection(parent.unreadNow ? "read" : "unread") }
            IconButton { visible: win.checkedCount > 0; name: "archive"; tip: Facteur.tr("Archive message"); enabledState: parent.on; onClicked: win.actOnSelection("archive") }
            IconButton { visible: win.checkedCount > 0; name: "trash"; tip: Facteur.tr("Move to trash"); enabledState: parent.on; onClicked: win.actOnSelection("trash") }
            IconButton { visible: win.checkedCount > 0; name: "spam"; tip: Facteur.tr("Mark as spam"); enabledState: parent.on; onClicked: win.actOnSelection("spam") }
            IconButton { visible: win.checkedCount > 0; name: "star"; filled: parent.starredNow; tip: parent.starredNow ? Facteur.tr("Remove star") : Facteur.tr("Star message"); enabledState: parent.on; onClicked: win.actOnSelection(parent.starredNow ? "unstar" : "star") }
            Rectangle { visible: win.checkedCount > 0; width: 1; height: 18; anchors.verticalCenter: parent.verticalCenter; color: FiliTheme.border }
            IconButton { name: "tabs"; toggled: win.categoryTabs; tip: win.categoryTabs ? Facteur.tr("Hide tabs") : Facteur.tr("Show tabs"); onClicked: win.toggleCategoryTabs() }
            Rectangle { // where the reader goes: auto, side, bottom
                id: previewSwitch
                anchors.verticalCenter: parent.verticalCenter
                width: modes.width + 2 * FiliTheme.space1
                height: 24
                radius: FiliTheme.radiusControl
                color: FiliTheme.background
                border.width: FiliTheme.borderWidth
                border.color: FiliTheme.border
                Row {
                    id: modes
                    x: FiliTheme.space1
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: [
                            { key: "auto", icon: "layout-auto", tip: Facteur.tr("Preview: automatic, by window width") },
                            { key: "side", icon: "layout-right", tip: Facteur.tr("Preview on the right") },
                            { key: "bottom", icon: "layout-below", tip: Facteur.tr("Preview below") }
                        ]
                        Rectangle {
                            id: cell
                            required property var modelData
                            readonly property bool on: win.previewMode === modelData.key
                            width: modelData.icon ? 26 : autoText.implicitWidth + 2 * FiliTheme.space3
                            height: 20
                            radius: FiliTheme.radiusControl
                            color: on ? FiliTheme.surfaceActive : cellArea.containsMouse ? FiliTheme.surfaceHover : "transparent"
                            Icon { visible: !!cell.modelData.icon; anchors.centerIn: parent; name: cell.modelData.icon || "layout-right"; size: 14; color: cell.on ? FiliTheme.accentColor : FiliTheme.text }
                            Text {
                                id: autoText
                                visible: !cell.modelData.icon
                                anchors.centerIn: parent
                                text: cell.modelData.label || ""
                                font.family: FiliTheme.font
                                font.pixelSize: FiliTheme.sizeSmall
                                font.weight: cell.on ? FiliTheme.weightAccent : Font.Normal
                                color: cell.on ? FiliTheme.accentColor : FiliTheme.text
                            }
                            MouseArea { id: cellArea; anchors.fill: parent; hoverEnabled: true; onClicked: win.setPreviewMode(cell.modelData.key) }
                            ToolTip { visible: cellArea.containsMouse; delay: 600; text: cell.modelData.tip }
                        }
                    }
                }
            }
        }
        // Window buttons at the far right: close, and the panel of window actions (niri)
        Rectangle {
            id: closeButton
            visible: win.windowButtons
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
            visible: win.windowButtons
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
            anchors { right: win.windowButtons ? windowButton.left : parent.right; rightMargin: win.windowButtons ? FiliTheme.space3 : FiliTheme.margin; verticalCenter: parent.verticalCenter }
            width: 180
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
                anchors { fill: parent; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2 + 22 + (searchInput.text !== "" ? 24 : 0) }
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.size
                color: FiliTheme.text
                selectionColor: FiliTheme.surfaceActive
                selectedTextColor: FiliTheme.text
                // The search starts on Enter or on the button, not while typing (a search can take long)
                onTextChanged: if (text.trim() === "" && win.query !== "") win.query = ""
                onActiveFocusChanged: if (!activeFocus && text === "") win.searchOpen = false
                Keys.onEscapePressed: { text = ""; win.query = ""; focus = false }
                Keys.onReturnPressed: { win.query = text.trim(); focus = false }
                Keys.onEnterPressed: { win.query = text.trim(); focus = false }
                Keys.onDownPressed: focus = false
            }
            // Clears the search in progress (same as Escape in the field)
            IconButton {
                visible: searchInput.text !== "" || win.query !== ""
                name: "x"
                tip: Facteur.tr("Clear search")
                anchors { right: parent.right; rightMargin: 25; verticalCenter: parent.verticalCenter }
                height: parent.height - 2
                width: 24
                onClicked: { searchInput.text = ""; win.query = ""; win.searchOpen = false }
            }
            IconButton {
                name: "search"
                tip: Facteur.tr("Search")
                anchors { right: parent.right; rightMargin: 1; verticalCenter: parent.verticalCenter }
                height: parent.height - 2
                width: 24
                onClicked: win.query = searchInput.text.trim()
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
            id: sidebar
            width: FiliTheme.sidebarWidth
            height: parent.height
            accounts: win.accounts
            unreadCounts: win.unreadCounts
            account: win.account
            mailbox: win.mailbox
            onAccountChosen: id => win.account = id
            onMailboxChosen: key => win.mailbox = key
            onUnifiedChosen: key => win.mailbox = key
            onBoxOfAccountChosen: (id, key) => { win.account = id; win.mailbox = key }
            labels: win.labels
            onAddLabelRequested: { labelDialog.error = ""; labelDialog.imap = win.isImap(); labelDialog.bridge = win.bridge; labelDialog.open() }
            sectionTitle: win.isImap() && !win.bridge ? Facteur.tr("Folders") : Facteur.tr("Labels")
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
                tabs: win.tabItems
                shown: win.categoryTabs
                tabsAddable: !win.unified
                tabCounts: win.tabCounts
                tab: win.currentTab
                onTabChosen: key => win.chooseTab(key)
                onTabsReordered: keys => win.reorderTabs(keys)
                onTabAddRequested: folderTabDialog.open(win.pinnableFolders())
                onTabCloseRequested: key => win.removeTab(key)
                onTabContext: (key, x, y) => win.openContext("tab", key, x, y)
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
                    showAccount: win.unified
                    accountInfo: { const m = {}; for (const a of win.accounts) m[a.id] = { name: a.label !== "" ? a.label : a.email, icon: /@(proton\.me|protonmail\.com|pm\.me)$/i.test(a.email || "") ? "shield" : a.provider === "gmail" ? "mail" : "server" }; return m; }
                    labelInfo: { const m = {}; for (const a in win.accountFolders) { m[a] = {}; for (const l of win.accountFolders[a]) m[a][l.id] = { name: l.rawName, color: l.color || win.nameColor(l.rawName) }; } return m; }
                    fallbackAccount: win.account
                    selectedId: win.selectedId
                    onAct: operation => win.actOnSelection(operation)
                    onRowAct: (operation, id) => win.doAct(operation, id)
                    onCheck: (index, mode) => win.check(index, mode)
                    onCheckAll: win.checkAll()
                    onClearChecks: win.clearChecks()
                    checkedCount: win.checkedCount
                    onStep: delta => win.step(delta)
                    loading: win.loading && win.listError === ""
                    emptyText: win.listError !== "" ? win.listError : win.categoriesOn() && win.listSpec(win.account) === null && !win.unified ? Facteur.tr("No folder is linked to this tab. Right-click the account, Edit account, Category tabs.") : Facteur.tr("No message")
                    onContextRequested: (index, x, y) => win.openMessageMenu(index, x, y)
                    onChosen: id => id.startsWith("draft:") ? win.openLocalDraft(id) : win.choose(id)
                    onNearEnd: win.loadMore()
                    onReply: win.startCompose("reply")
                    onReplyAll: win.startCompose("replyall")
                    onForward: win.startCompose("forward")
                    onSearchRequested: win.openSearch()
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
                    onLeave: win.focusPane(1)
                    onOpenAttachment: index => Facteur.openAttachment(win.selectedRef.acct, win.selectedRef.id, reader.attachments[index].attachmentId, reader.attachments[index].filename)
                    onSaveAllAttachments: Facteur.saveAllAttachments(win.selectedRef.acct, win.selectedRef.id, JSON.stringify(reader.attachments.filter(a => !!a.attachmentId).map(a => ({ attachmentId: a.attachmentId, filename: a.filename }))))
                    onSaveAttachment: index => Facteur.saveAttachment(win.selectedRef.acct, win.selectedRef.id, reader.attachments[index].attachmentId, reader.attachments[index].filename)
                    onPageMenu: (x, y, link, image) => win.openPageMenu(x, y, link, image)
                    onLoadImages: { reader.loadingImages = true; Facteur.loadImages(win.selectedRef.acct, win.selectedRef.id) }
                    x: panes.below ? 0 : messageList.width + FiliTheme.borderWidth
                    y: panes.below ? messageList.height + FiliTheme.borderWidth : 0
                    width: panes.below ? panes.width : panes.width - x
                    height: panes.below ? panes.height - y : panes.height
                }
            }
        }
    }

    // Removal asks first: the account and its password leave this computer, the mailbox itself is untouched
    Rectangle {
        visible: win.removing !== ""
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: FiliTheme.statusHeight
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
        visible: win.footerShown
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
                if (win.loading) parts.push(win.query !== "" ? Facteur.tr("Searching…") : Facteur.tr("Loading…"));
                else if (win.listError === "") {
                    if (win.searchPhase === "full") parts.push(Facteur.tr("Searching the content…"));
                    parts.push(Facteur.tr("%1 messages, %2 unread").replace("%1", messages.count).replace("%2", win.unreadTotal));
                    if (win.nextToken !== "") parts.push(win.loadingMore ? Facteur.tr("Loading more…") : Facteur.tr("More below"));
                }
                if (win.checkedCount > 0) parts.push(Facteur.tr("%1 selected").replace("%1", win.checkedCount));
                return parts.join("  ·  ");
            }
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeSmall
            color: win.notice === "" ? FiliTheme.textSecondary : win.noticeFolder !== "" ? FiliTheme.accentColor : FiliTheme.danger
            font.underline: win.noticeFolder !== ""
            MouseArea {
                anchors.fill: parent
                enabled: win.noticeFolder !== ""
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: Qt.openUrlExternally("file://" + win.noticeFolder)
            }
        }
    }
    // The messages being written: one frame at the bottom right, flush with the footer and never wider than the window.
    // Its header holds a tab per draft; only the open one is drawn (all stay alive, so nothing typed is lost).
    Item {
        id: dock
        z: 60
        anchors { right: parent.right; rightMargin: FiliTheme.margin; bottom: footer.visible ? footer.top : parent.bottom }
        width: parent.width - 2 * FiliTheme.margin
        height: parent.height - (footer.visible ? footer.height : 0)
        function cardOf(key) {
            const i = win.draftIndex(key);
            return i >= 0 ? cards.itemAt(i) : null;
        }
        Repeater {
            id: cards
            model: draftModel
            delegate: Item {
                id: slot
                required property int index
                required property string key
                required property string account
                required property string init
                anchors { right: parent.right; bottom: parent.bottom }
                width: card.width
                height: card.height
                visible: win.activeDraft === slot.key
                property alias card: card
                property alias error: card.error
                Compose {
                    id: card
                    draftKey: slot.key
                    tabs: draftModel
                    tabCount: draftModel.count
                    roomWidth: dock.width + 2 * FiliTheme.margin
                    roomHeight: dock.height
                    minimized: win.dockMinimized
                    current: win.activeDraft === slot.key && !win.dockMinimized
                    busy: win.sending && win.sendingKey === slot.key
                    from: slot.account.replace(/^[a-z]+:/, "")
                    Component.onCompleted: open(JSON.parse(slot.init), win.composing && win.activeDraft === slot.key)
                    onTitleChanged: draftModel.setProperty(slot.index, "title", title)
                    onMinimizeToggled: win.dockMinimized = !win.dockMinimized
                    onTabChosen: key => { win.activeDraft = key; win.dockMinimized = false }
                    onTabClosed: key => {
                        const other = dock.cardOf(key), i = win.draftIndex(key);
                        if (other && i >= 0) win.keepDraft(key, draftModel.get(i).account, other.card.fields());
                        win.closeDraft(key, false);
                    }
                    onNewRequested: win.startCompose("new")
                    onEdited: fields => { win.keepDraft(slot.key, slot.account, fields); savedAt = "now" }
                    onCancelled: { win.keepDraft(slot.key, slot.account, fields()); win.closeDraft(slot.key, false) }
                    onDiscarded: win.closeDraft(slot.key, true)
                    onSubmitted: fields => {
                        if (win.sending) { error = Facteur.tr("Another message is being sent."); return }
                        win.sending = true;
                        win.sendingKey = slot.key;
                        error = "";
                        Facteur.send(slot.account, JSON.stringify(fields));
                    }
                }
            }
        }
    }
    FolderTabDialog {
        id: folderTabDialog
        onCancelled: visible = false
        onAccepted: (key, icon) => { win.addTab(key, icon); visible = false }
    }
    LabelDialog {
        id: labelDialog
        onCancelled: visible = false
        onCreated: (name, background, text) => {
            busy = true;
            error = "";
            if (colorOnly) {
                // Servers without label colours: the choice stays on this computer
                const id = editId.slice(6);
                Facteur.uiSet("color:" + win.account + ":" + id, background);
                busy = false;
                visible = false;
                win.labels = win.labels.map(l => l.id === id ? Object.assign({}, l, { color: background }) : l);
                return;
            }
            if (editId !== "" && win.isImap()) {
                // Rename a folder of the server: its colour follows
                const old = win.labels.find(l => l.id === editId);
                const raw = (old ? old.prefix : "") + name;
                if (raw !== editId) {
                    const color = background !== "" ? background : Facteur.uiGet("color:" + win.account + ":" + editId);
                    if (color !== "") Facteur.uiSet("color:" + win.account + ":" + raw, color);
                    if (win.mailbox === "folder:" + editId) win.mailbox = "folder:" + raw;
                    Facteur.renameFolder(win.account, editId, raw);
                } else if (background !== "") {
                    Facteur.uiSet("color:" + win.account + ":" + editId, background);
                    win.labels = win.labels.map(l => l.id === editId ? Object.assign({}, l, { color: background }) : l);
                    busy = false;
                    visible = false;
                }
                return;
            }
            if (editId !== "") {
                // A view of this label follows its new name
                const old = win.labels.find(l => l.id === editId);
                if (old && win.mailbox === "label:" + old.rawName) win.mailbox = "label:" + name;
                Facteur.updateLabel(win.account, editId, name, background, text);
            }
            else if (win.isImap()) {
                // A folder of the server; its colour is only kept here
                const raw = (win.bridge ? (kind === "folder" ? "Folders/" : "Labels/") : "") + name;
                if (background !== "") Facteur.uiSet("color:" + win.account + ":" + raw, background);
                Facteur.createFolder(win.account, raw);
            } else Facteur.createLabel(win.account, name, background, text);
        }
    }
    AccountDialog {
        id: accountDialog
        folderNames: { const m = {}; for (const l of (win.accountFolders[accountId] || [])) m[l.id] = l.rawName; return m; }
        onPickRequested: (cat, x, y) => win.openContext("catpick", cat, x, y)
        onCancelled: visible = false
        onSaved: (id, patch) => { busy = true; error = ""; Facteur.updateAccount(id, JSON.stringify(patch)) }
    }
    // Deleting a label asks first: the messages keep everything else, only the label goes
    Rectangle {
        visible: win.deletingLabel !== null
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: FiliTheme.statusHeight
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
            TextButton { label: Facteur.tr("Delete"); primary: true; onClicked: win.confirmDeleteLabel() }
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
    ShortcutsCard { id: shortcutsCard; anchors.fill: parent }
}
