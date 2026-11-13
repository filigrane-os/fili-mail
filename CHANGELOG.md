# Changelog

## 1.0.1

- The bar's unread total is exact for Gmail: the daemon reads the INBOX label counter instead of the list estimate.
- Clear button in the search field (clears the search in progress, like Escape).
- New-mail notifications use the Facteur icon.

## 1.0.0

First stable release.

- The preview follows the window: beside the list when the window fills the screen (full screen, maximized column), under it when the window takes part of the screen. The layout button and Ctrl+Shift+P flip it until the window changes size class; the stored "preview" setting is gone.
- Unread count after the name of each Gmail category tab, read from the category label counters (one light request per tab).

## 0.2.0

- Headless window: the header and the footer can be hidden with `[window] header = false` / `footer = false` in `~/.config/filigrane/theme.toml` or `fili-mail.toml`, with `--no-header` / `--no-footer` (and `--header` / `--footer`) at launch, or from Settings > Appearance of the shell. Open windows follow the file live. Ctrl+F shows the search; the footer comes back for an operation, an error or a notice. New menu entries Show Header and Show Status Bar (`fili-mail ctl action toggle-header|toggle-footer`) change one window only.

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
