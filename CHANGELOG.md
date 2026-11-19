# Changelog

## 1.5.0

- The window asks for attention: the header and footer take the accent colour when new mail arrives while another window is in front (`[window] attention`, `--no-attention`).
- A search in progress shows a banner above the list (words, count, clear button), and the search field stays tinted in the accent while it filters.
- Actions on every message of a sender: move to trash, archive, mark as spam, mark as read, or show all of them, from the context menu of a message; the mailboxes of the sidebar have a context menu too. Popup menus are as wide as their longest label.
- Header: an Ask Rob button (left of the window button) shows Rob's small floating field for Facteur (`fili-chat here`).
- Command line: `fili-mail list` prints one line per message (id, date, U unread / * starred / @ attachment, sender, subject) and `fili-mail read` prints the headers and the text (6000 characters at most); `--json` is unchanged.
- The shortcuts card and the folder tab dialog scroll with the shell's kinetic scrolling and scroll bar.

## 1.4.1

- Opening an account (or "All") shows its cached list at once and updates it in place when the server answers: no placeholder rows, no "Loading..." or moving bar while rows are on screen, the selection and the scroll stay. The bar and the empty text only show when there is nothing to display yet or a search runs.
- The unified Inbox views also start from the cache of each account.

## 1.4.0

- The message is written as rich text by default (bold, italic, underline, alignment; Ctrl+B, Ctrl+I, Ctrl+U) and goes out as text + HTML alternatives. A Text / HTML switch in the footer (Ctrl+Shift+H) goes back to plain text; the mode is kept with the draft.
- A reply opens empty. The message answered is kept apart: a "…" button shows it as its original page below what you typed, and it is added to the message when sending (HTML and text).
- `mailto:` links open Facteur: `fili-mail mailto:...` writes a new message with the recipients, subject and text of the link, in the open window when there is one. The desktop entry claims the scheme, so the desktop can make Facteur its default mail client.
- IMAP accounts: the unread counts of the folder tabs and of the sidebar folders and labels were always missing (the folder list carried a fixed 0); they now come from the server (STATUS UNSEEN, one folder after the other) and refresh every minute for the account on screen.
- A failed folder list no longer erases the tabs and the labels; the last list is shown at once again on IMAP accounts (the cache key did not match); the tab row scrolls with the wheel when the tabs do not fit; linking a folder to a tab refreshes the list at once.
- The Inbox views (All, Unread) fill in without flicker, list a message that reaches two accounts once, and show an account's error only when nothing else could be listed.

## 1.3.0

- Your own folders as tabs: a "+" after the tabs opens a dialog (folder and icon). Tabs can always be dragged to reorder; middle click or the right-click menu removes a folder tab.
- The same five tabs (Primary, Promotions, Social, Updates, Forums) on every account. Gmail uses its own categories; on other accounts each tab is linked to a folder in Edit account (Category tabs). One button in the header uses the tab system or not. Unread counts show on the tabs (Gmail: exact label counters, other accounts: the folder counters).
- Inbox group at the top of the sidebar: "All" and "Unread" list the inboxes of every account together, newest first, with the account of each message.
- The list shows the labels of a message (coloured dot and name, Gmail) and a paperclip when it has an attachment. The row actions float over the message under the pointer, the list action row is gone.
- Header: previous/next message, new message, unread only (new icon), refresh on the left; the actions on ticked messages only show while something is ticked; a switch Auto / side / bottom places the preview (auto: beside the list from 1061 px of window width).
- Edit account has a new layout.
- The Gmail unread count of the sidebar is exact (it showed an estimate, 201 for 1 unread message).

## 1.2.0

- Right click on a message in the list: reply, reply all, forward, mark read/unread, star, archive, spam, trash. On a ticked message it acts on every ticked message.
- Category tabs can be turned off: a button in the list bar and "Show Category Tabs" in the Mailbox menu (remembered, Gmail accounts). The first page of each tab is kept on disk and shown at once.
- IMAP lists are faster: the arrival dates of a folder are kept in memory and reused while its UIDVALIDITY, UIDNEXT and message count are unchanged, so a list no longer reads every date again (1.3 s down to 0.3 s on a 17 000 message Proton Bridge inbox).

## 1.1.0

- Several messages can be written at once: one frame with a tab per draft in its header, never wider than the window; reducing it leaves the tab bar flush with the footer.
- Drafts are saved as they are typed (on this computer, `~/.local/state/fili-mail/drafts`), come back after a restart and are listed first in the Drafts mailbox. The close button keeps the draft, the trash button throws it away.
- Loading is visible: a cached list shows at once when the account or mailbox changes, otherwise placeholder rows and a moving bar; the open message stays on screen (dimmed, with a bar) until the next one has arrived.
- "Unread only" has its own icon (a funnel) and keeps fetching pages while few rows pass the filter.
- The unread counts of the sidebar and of the header follow reading, archiving and trashing at once; the confusing "n/N" position in the list bar is gone.
- The Labels / Folders heading stays folded when the account changes, and folded sections are kept between runs.
- The body of a message being written scrolls like the other views (kinetic scrolling, Facteur scroll bar).
- The Add account page wraps its tabs and scrolls on a small window.

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
