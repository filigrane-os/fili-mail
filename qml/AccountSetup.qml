// Add a mail account (IMAP/SMTP): Gmail and Proton Mail through Bridge need nothing but an address and a password.
// Gmail wants an app password, Bridge its own generated password.
import QtQuick
import Fili.Mail

Rectangle {
    id: setup
    // A first account has nothing to go back to
    property bool cancellable: false
    property bool busy: false
    property string error: ""
    // "google" (browser sign-in), "gmail" (app password), "bridge" or "other"
    property string kind: "google"
    // Google sign-in: a client file is needed once; the browser page is open while this is set
    property bool googleReady: Facteur.googleReady()
    property string googleUrl: ""
    property string clientError: ""
    signal cancelled()
    signal submitted(var spec)

    color: FiliTheme.background

    function signInGoogle() {
        if (busy)
            return;
        setup.googleUrl = "";
        setup.submitted({ google: true, hint: email.text.trim() });
    }

    function saveClient() {
        const err = Facteur.saveGoogleClient(clientText.text);
        setup.clientError = err === "" ? "" : Facteur.tr("This is not a Google desktop client file (the JSON downloaded from the console).");
        if (err === "") {
            clientText.text = "";
            setup.googleReady = Facteur.googleReady();
        }
    }

    function submit() {
        if (kind === "google") {
            signInGoogle();
            return;
        }
        if (busy || email.text.trim() === "" || password.text === "")
            return;
        // Google shows an app password in groups of four letters; the spaces are not part of it
        const secret = kind === "gmail" ? password.text.replace(/\s+/g, "") : password.text;
        const spec = { email: email.text.trim(), password: secret, bridge: kind === "bridge" };
        if (kind === "other") {
            if (imapHost.text.trim() !== "") spec.imapHost = imapHost.text.trim();
            if (parseInt(imapPort.text) > 0) spec.imapPort = parseInt(imapPort.text);
            if (smtpHost.text.trim() !== "") spec.smtpHost = smtpHost.text.trim();
            if (parseInt(smtpPort.text) > 0) spec.smtpPort = parseInt(smtpPort.text);
            if (username.text.trim() !== "") spec.username = username.text.trim();
        }
        setup.submitted(spec);
    }

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * FiliTheme.margin, 380)
        spacing: FiliTheme.space3

        Text {
            text: Facteur.tr("Add an account")
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeTitle
            font.weight: FiliTheme.weightAccent
            color: FiliTheme.text
        }
        Row {
            spacing: FiliTheme.space1
            Repeater {
                model: [
                    { key: "google", label: Facteur.tr("Gmail (Google sign-in)") },
                    { key: "gmail", label: Facteur.tr("Gmail (app password)") },
                    { key: "bridge", label: "Proton Mail (Bridge)" },
                    { key: "other", label: Facteur.tr("Other IMAP") }
                ]
                delegate: TextButton {
                    label: modelData.label
                    primary: setup.kind === modelData.key
                    onClicked: setup.kind = modelData.key
                }
            }
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeList
            color: FiliTheme.textSecondary
            text: setup.kind === "google" ? (setup.googleReady ? Facteur.tr("Your browser opens Google's own sign-in page: Facteur never sees your Google password.") : Facteur.tr("Google sign-in needs an OAuth client, created once in the Google Cloud console (APIs & Services › Credentials › OAuth client ID › Desktop app). Paste the JSON file it lets you download."))
                : setup.kind === "gmail" ? Facteur.tr("Gmail needs an app password: Google account › Security › 2-step verification › App passwords.")
                : setup.kind === "bridge" ? Facteur.tr("Proton Mail Bridge must be running. Use the password it shows for this account, not your Proton password.")
                : Facteur.tr("Servers are guessed from the address (imap.domain, smtp.domain); fill them in if they differ.")
        }
        Field { id: email; width: parent.width; placeholderText: Facteur.tr("Email address"); inputMethodHints: Qt.ImhEmailCharactersOnly; KeyNavigation.tab: password; onAccepted: password.forceActiveFocus() }
        Field { id: password; visible: setup.kind !== "google"; width: parent.width; placeholderText: Facteur.tr("Password"); secret: true; KeyNavigation.tab: setup.kind === "other" ? imapHost : email; onAccepted: setup.submit() }
        Column {
            width: parent.width
            spacing: FiliTheme.space2
            visible: setup.kind === "google" && !setup.googleReady
            Rectangle {
                width: parent.width
                height: 110
                radius: FiliTheme.radiusControl
                color: FiliTheme.surface
                border.width: FiliTheme.borderWidth
                border.color: clientText.activeFocus ? FiliTheme.accentColor : FiliTheme.border
                TextEdit {
                    id: clientText
                    anchors { fill: parent; margins: FiliTheme.space2 }
                    wrapMode: TextEdit.WrapAnywhere
                    font.family: FiliTheme.mono
                    font.pixelSize: FiliTheme.sizeSmall
                    color: FiliTheme.text
                    selectionColor: FiliTheme.surfaceActive
                    clip: true
                }
            }
            Text {
                visible: setup.clientError !== ""
                width: parent.width
                text: setup.clientError
                wrapMode: Text.WordWrap
                font.family: FiliTheme.font
                font.pixelSize: FiliTheme.sizeList
                color: FiliTheme.danger
            }
            TextButton { label: Facteur.tr("Save the client"); primary: true; onClicked: setup.saveClient() }
        }
        Column {
            width: parent.width
            spacing: FiliTheme.space2
            visible: setup.kind === "other"
            Row {
                spacing: FiliTheme.space2
                Field { id: imapHost; width: parent.parent.width - 80 - FiliTheme.space2; placeholderText: Facteur.tr("IMAP server"); KeyNavigation.tab: imapPort }
                Field { id: imapPort; width: 80; placeholderText: "993"; inputMethodHints: Qt.ImhDigitsOnly; KeyNavigation.tab: smtpHost }
            }
            Row {
                spacing: FiliTheme.space2
                Field { id: smtpHost; width: parent.parent.width - 80 - FiliTheme.space2; placeholderText: Facteur.tr("SMTP server"); KeyNavigation.tab: smtpPort }
                Field { id: smtpPort; width: 80; placeholderText: "465"; inputMethodHints: Qt.ImhDigitsOnly; KeyNavigation.tab: username }
            }
            Field { id: username; width: parent.width; placeholderText: Facteur.tr("User name (if not the address)"); KeyNavigation.tab: email; onAccepted: setup.submit() }
        }
        Text {
            width: parent.width
            visible: setup.busy && setup.kind === "google" && setup.googleUrl !== ""
            text: Facteur.tr("If the page did not open, copy this address into your browser:") + "\n" + setup.googleUrl
            wrapMode: Text.WrapAnywhere
            font.family: FiliTheme.mono
            font.pixelSize: FiliTheme.sizeSmall
            color: FiliTheme.textSecondary
        }
        Text {
            width: parent.width
            visible: setup.kind === "gmail" && password.text.replace(/\s+/g, "").length > 0 && password.text.replace(/\s+/g, "").length !== 16
            text: Facteur.tr("An app password has 16 letters; this is not your Google password.")
            wrapMode: Text.WordWrap
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeList
            color: FiliTheme.warning
        }
        Text {
            width: parent.width
            visible: setup.error !== ""
            text: setup.error
            wrapMode: Text.WordWrap
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeList
            color: FiliTheme.danger
        }
        Row {
            spacing: FiliTheme.space2
            TextButton {
                visible: setup.kind !== "google" || setup.googleReady
                label: setup.busy ? (setup.kind === "google" ? Facteur.tr("Waiting for the browser…") : Facteur.tr("Adding…")) : setup.kind === "google" ? Facteur.tr("Sign in with Google") : Facteur.tr("Add account")
                primary: true
                onClicked: setup.submit()
            }
            TextButton { visible: setup.cancellable; label: Facteur.tr("Cancel"); onClicked: setup.cancelled() }
        }
    }
    Component.onCompleted: email.forceActiveFocus()
    Keys.onEscapePressed: if (cancellable) cancelled()
}
