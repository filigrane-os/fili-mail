# Changelog

## 0.1.0

First release of Facteur, the mail client of Filigrane, forked from Omamail 0.11.3 (a7b2441).

- Qt Quick window in the Casier style: accounts, mailboxes, labels and folders, list with infinite scroll,
  tick boxes and batch actions, category tabs (Gmail), reader with HTML mail and attachments.
- Writing, replying, forwarding (with attachments and threading headers) in a card at the bottom right.
- Gmail sign-in in the browser, IMAP/SMTP (Proton Mail through Bridge), account edit dialog.
- Preview beside or under the list, window buttons, scroll bars, footer with counts.
- Daemon with desktop notifications, fili-bar module and menu (`fili-mail ctl`), About card, icon.
- Attachments open on click and save one by one or all at once (through Casier's file chooser); recipient
  suggestions from the mail already received; unread counts in the sidebar; the last list is shown at start.
- HTML mail is laid out by litehtml (vendored in `third_party/litehtml`, no browser engine): tables, style sheets,
  rounded buttons, pictures once loaded; text selection and copy, right-click menu on links and pictures.
- Agent feature off by default; Omarchy marketplace, release and CI glue removed.
