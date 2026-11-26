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
- Writing in a card at the bottom right: rich text by default (bold, italic, underline, alignment) with a switch to
  plain text, sent as text + HTML; reply (the message answered behind a "…" button), reply all, forward, Cc/Bcc,
  attachments, threading headers. `mailto:` links open a new message.
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

## Resources

CPU and memory of each release, measured on a running desktop (Gmail and IMAP accounts, idle, a few minutes after
launch). Kept from release to release to spot a version that gets heavier.

| Version | Window RAM (RSS) | Window CPU | Daemon RAM (RSS) | Daemon CPU |
|---------|------------------|------------|------------------|------------|
| 1.8.1   | not measured (keys only, as 1.8.0) | | | |
| 1.4.1   | 202 MB           | 0.3 %      | 40 MB            | 0.2 %      |
| 1.4.0   | 176 MB           | 0.3 %      | 47 MB            | 0.2 %      |
| 1.3.0   | 157 MB           | 1.2 %      | 41 MB            | 0.2 %      |
| 1.2.0   | 214 MB           | 0.7 %      | 30 MB            | 0.1 %      |

Earlier versions were not measured. 1.4.1: window CPU measured over 30 s idle, 4 minutes after launch (the average
since launch is higher, the list loads). 1.4.0: window CPU is the average since launch (1 h 19 min, idle at the time
of measuring); the daemon figures come from a daemon started before the update (same engine, 4 days of uptime).

## Google sign-in

Google needs an OAuth client. Create a desktop client in the Google Cloud console and paste its JSON
into the account sheet once, or build with `FILI_MAIL_GOOGLE_CLIENT_ID` and `FILI_MAIL_GOOGLE_CLIENT_SECRET`.
