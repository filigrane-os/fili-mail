# Facteur (fili-mail)

Mail for [Filigrane](https://github.com/filigrane-os): a background daemon that watches every
account and notifies of new mail, a fili-bar module, and a Qt Quick application in the Casier style.

Status: work in progress. The mail engine (IMAP/SMTP, JMAP, Gmail, Microsoft 365, MIME, cache,
send queue) comes from [Omamail](https://github.com/huacnlee/omamail) (MIT); see `NOTICE`.

Program name: `fili-mail`. Display name (alias): **Facteur**.

## Plan

1. Daemon (`fili-mail daemon`): one watcher per account (IMAP IDLE where available), new-mail
   detection, desktop notifications over D-Bus, unread counter for the bar.
2. fili-bar module `mail`.
3. Qt Quick application (Casier theme, menu exposed to the bar, settings, About card).
4. Distribution integration (package, `mailto:`, launcher).

Providers kept: IMAP/SMTP (Proton Bridge included), JMAP, Gmail, Microsoft 365.
Removed over time: AI agent, HEY, Omarchy plugin glue.
