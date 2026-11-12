# Facteur (fili-mail)

The mail client of [Filigrane](https://github.com/filigrane-os): a Qt Quick application, a background
daemon that watches every account and notifies of new mail, and a fili-bar module.

Program name: `fili-mail`. Display name (alias): **Facteur** (`facteur` also works in a terminal).

## What it does

- Accounts: Gmail (Google sign-in in the browser), IMAP/SMTP including Proton Mail through Bridge, JMAP,
  Microsoft 365.
- List with infinite scroll, tick boxes and batch actions (read, star, archive, spam, trash), category tabs
  (Gmail), labels and folders in the sidebar (create, rename, recolour, delete), search.
- Reader with HTML mail (remote pictures on request), attachments saved to Downloads.
- Writing in a card at the bottom right: reply, reply all, forward, Cc/Bcc, attachments, threading headers.
- Preview beside the list or under it (following the window size), window buttons and the niri window panel like Casier.
- Daemon (`fili-mail daemon`): IMAP IDLE where available, notifications over D-Bus, unread counter for the bar.
- Menu exposed to the fili-bar (`fili-mail ctl action NAME`), settings in `~/.config/filigrane/fili-mail.toml`.

The mail engine (IMAP/SMTP, JMAP, Gmail, Microsoft 365, MIME, cache, send queue) comes from
[Omamail](https://github.com/huacnlee/omamail) (MIT); see `NOTICE`.

## Build and install

```sh
make                     # needs Rust and Qt 6 (qt6-declarative, qt6-svg); QMAKE=... if qmake6 is not found
sudo make install PREFIX=/usr
```

`make test` runs the engine tests (no Qt needed to link them). 24 of them compare with the JavaScript
implementation of Omamail and need `node`; they fail without it.

## Google sign-in

Google needs an OAuth client. Create a desktop client in the Google Cloud console and paste its JSON
into the account sheet once, or build with `FILI_MAIL_GOOGLE_CLIENT_ID` and `FILI_MAIL_GOOGLE_CLIENT_SECRET`.
