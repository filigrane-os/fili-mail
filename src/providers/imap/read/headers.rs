//! Local index of message headers (subject, sender, recipients) for the quick search of an IMAP folder.
//!
//! A server that scans every message to answer a SEARCH (Proton Bridge: about 0.75 ms a message, one connection at
//! a time) makes a quick search of a 17 000 message inbox last 15 seconds. The headers of a message never change, so
//! they are read once, kept in a SQLite file of the cache directory, and the quick search is answered from it in
//! milliseconds. The index is only ever an accelerator: whenever it cannot answer (folder not indexed yet, request
//! it does not understand, any error), the caller falls back to the server SEARCH.
//!
//! Filling is incremental: the UIDs of the folder the server lists and the index lacks are fetched in batches. A
//! large gap is filled in the background (the search of that moment goes to the server); a small one is filled
//! before answering. A change of UIDVALIDITY drops the folder's rows; UIDs that left the folder are pruned.
use super::*;
use std::collections::{HashMap, HashSet};
use std::sync::{LazyLock, Mutex};

/// A gap larger than this is filled in the background, the search of that moment going to the server.
const INLINE_MAX: usize = 400;
/// UIDs per FETCH: they are listed one by one, and a server refuses an argument over 4096 bytes.
const BATCH: usize = 300;
/// More than this many UIDs still missing after a fill: the index is not trusted for this answer.
const TOLERATED_GAPS: usize = 5;

#[derive(Clone, Debug, PartialEq)]
pub(super) struct Row {
    uid: u32,
    subject: String,
    sender: String,
    recipients: String,
}

#[derive(Debug, PartialEq)]
enum Term {
    /// One of the fields, by name: FROM, TO or SUBJECT
    Field(&'static str, String),
    /// A plain word: in the subject, the sender or a recipient
    Word(String),
}

/// Reads back the criteria `domain::imap_header_search` writes; None for anything else (then the server answers).
fn parse_criteria(criteria: &str) -> Option<Vec<Term>> {
    let mut tokens = Vec::new();
    let mut chars = criteria.trim().chars().peekable();
    while let Some(&c) = chars.peek() {
        if c.is_whitespace() {
            chars.next();
        } else if c == '"' {
            let mut raw = String::from('"');
            chars.next();
            let mut closed = false;
            while let Some(c) = chars.next() {
                raw.push(c);
                if c == '\\' {
                    raw.push(chars.next()?);
                } else if c == '"' {
                    closed = true;
                    break;
                }
            }
            if !closed {
                return None;
            }
            tokens.push(Token::Text(serde_json::from_str::<String>(&raw).ok()?));
        } else {
            let mut word = String::new();
            while let Some(&c) = chars.peek() {
                if c.is_whitespace() || c == '"' {
                    break;
                }
                word.push(c.to_ascii_uppercase());
                chars.next();
            }
            tokens.push(Token::Word(word));
        }
    }
    let mut at = 0;
    let mut terms = Vec::new();
    let next = |at: &mut usize| -> Option<&Token> {
        *at += 1;
        tokens.get(*at - 1)
    };
    let keyword = |token: Option<&Token>, name: &str| matches!(token, Some(Token::Word(w)) if w == name);
    while at < tokens.len() {
        match next(&mut at)? {
            Token::Word(w) if w == "OR" => {
                // OR SUBJECT w OR FROM w TO w
                if !keyword(next(&mut at), "SUBJECT") {
                    return None;
                }
                let Some(Token::Text(word)) = next(&mut at) else { return None };
                let word = word.clone();
                if !keyword(next(&mut at), "OR") || !keyword(next(&mut at), "FROM") {
                    return None;
                }
                if !matches!(next(&mut at), Some(Token::Text(t)) if *t == word)
                    || !keyword(next(&mut at), "TO")
                    || !matches!(next(&mut at), Some(Token::Text(t)) if *t == word)
                {
                    return None;
                }
                terms.push(Term::Word(word));
            }
            Token::Word(w) if matches!(w.as_str(), "FROM" | "TO" | "SUBJECT") => {
                let name = match w.as_str() {
                    "FROM" => "FROM",
                    "TO" => "TO",
                    _ => "SUBJECT",
                };
                let Some(Token::Text(value)) = next(&mut at) else { return None };
                terms.push(Term::Field(name, value.clone()));
            }
            _ => return None,
        }
    }
    (!terms.is_empty()).then_some(terms)
}

enum Token {
    Word(String),
    Text(String),
}

fn matches_row(row: &Row, terms: &[Term]) -> bool {
    terms.iter().all(|term| match term {
        Term::Field("FROM", v) => row.sender.contains(&v.to_lowercase()),
        Term::Field("TO", v) => row.recipients.contains(&v.to_lowercase()),
        Term::Field(_, v) => row.subject.contains(&v.to_lowercase()),
        Term::Word(v) => {
            let v = v.to_lowercase();
            row.subject.contains(&v) || row.sender.contains(&v) || row.recipients.contains(&v)
        }
    })
}

/// The index row of a header block (decoded, lower case, so that a search is a substring test).
fn row_of(uid: u32, raw: &[u8]) -> Row {
    let (headers, _) = mailparse::parse_headers(raw).unwrap_or_default();
    let value = |name: &str| {
        headers
            .iter()
            .filter(|h| h.get_key_ref().eq_ignore_ascii_case(name))
            .map(|h| h.get_value())
            .collect::<Vec<_>>()
            .join(" ")
            .to_lowercase()
    };
    Row {
        uid,
        subject: value("subject"),
        sender: value("from"),
        recipients: format!("{} {}", value("to"), value("cc")).trim().to_owned(),
    }
}

fn open() -> Result<rusqlite::Connection> {
    let dir = crate::platform::dirs::AppDirs::discover()?.cache;
    std::fs::create_dir_all(&dir).map_err(|_| "cache_unavailable")?;
    let path = dir.join("headers.sqlite");
    let db = rusqlite::Connection::open(&path).map_err(|_| "cache_unavailable")?;
    #[cfg(unix)]
    {
        // The subjects and senders of a mailbox are private
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600));
    }
    db.busy_timeout(Duration::from_secs(10)).map_err(|_| "cache_unavailable")?;
    let _ = db.pragma_update(None, "journal_mode", "WAL");
    db.execute_batch(
        "CREATE TABLE IF NOT EXISTS hdr(account TEXT NOT NULL, folder TEXT NOT NULL, validity INTEGER NOT NULL,
            uid INTEGER NOT NULL, subject TEXT NOT NULL, sender TEXT NOT NULL, recipients TEXT NOT NULL,
            PRIMARY KEY(account, folder, uid)) WITHOUT ROWID;",
    )
    .map_err(|_| "cache_unavailable")?;
    Ok(db)
}

/// The rows of a folder; those of another UIDVALIDITY are dropped (the UIDs mean other messages now).
fn load(account: &str, folder: &str, validity: u64) -> Result<Vec<Row>> {
    let db = open()?;
    let failed = |_| "cache_unavailable";
    db.execute(
        "DELETE FROM hdr WHERE account = ?1 AND folder = ?2 AND validity <> ?3",
        rusqlite::params![account, folder, validity as i64],
    )
    .map_err(failed)?;
    let mut statement = db
        .prepare("SELECT uid, subject, sender, recipients FROM hdr WHERE account = ?1 AND folder = ?2")
        .map_err(failed)?;
    let rows = statement
        .query_map(rusqlite::params![account, folder], |r| {
            Ok(Row { uid: r.get(0)?, subject: r.get(1)?, sender: r.get(2)?, recipients: r.get(3)? })
        })
        .map_err(failed)?
        .collect::<std::result::Result<Vec<_>, _>>()
        .map_err(failed)?;
    Ok(rows)
}

fn store(account: &str, folder: &str, validity: u64, rows: &[Row]) -> Result<()> {
    let mut db = open()?;
    let failed = |_| "cache_unavailable";
    let tx = db.transaction().map_err(failed)?;
    {
        let mut statement = tx
            .prepare_cached("INSERT OR REPLACE INTO hdr VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)")
            .map_err(failed)?;
        for r in rows {
            statement
                .execute(rusqlite::params![account, folder, validity as i64, r.uid, r.subject, r.sender, r.recipients])
                .map_err(failed)?;
        }
    }
    tx.commit().map_err(failed)
}

fn prune(account: &str, folder: &str, gone: &[u32]) -> Result<()> {
    let mut db = open()?;
    let failed = |_| "cache_unavailable";
    let tx = db.transaction().map_err(failed)?;
    for uid in gone {
        tx.execute(
            "DELETE FROM hdr WHERE account = ?1 AND folder = ?2 AND uid = ?3",
            rusqlite::params![account, folder, uid],
        )
        .map_err(failed)?;
    }
    tx.commit().map_err(failed)
}

fn parse_fetched(data: &[u8]) -> Result<Vec<Row>> {
    let mut rows = Vec::new();
    for row in nodes(data)? {
        if row.len() < 4 || !row[0].is("*") || !row[2].is("FETCH") {
            continue;
        }
        let (mut uid, mut raw) = (None, None);
        for pair in row[3].list().as_chunks::<2>().0 {
            if pair[0].is("UID") {
                uid = pair[1].number();
            } else if pair[0].text().to_ascii_uppercase().starts_with(b"BODY[") {
                raw = Some(pair[1].text());
            }
        }
        if let (Some(uid), Some(raw)) = (uid, raw) {
            rows.push(row_of(uid, raw));
        }
    }
    Ok(rows)
}

/// Reads the headers of `missing` on a connection of its own and stores them, batch by batch.
async fn fill(p: &Value, folder: &str, validity: u64, missing: &[u32]) -> Result<()> {
    let account = p["accountId"].as_str().ok_or("invalid_params")?.to_owned();
    let (mut wire, key) = acquire(p).await?;
    let selected = command(&mut wire, &format!("SELECT {}", quote(folder)?)).await?;
    if select_state(&selected).map(|s| s.0) != Some(validity) {
        return Err("imap_search_expired");
    }
    for batch in missing.chunks(BATCH) {
        let set = batch.iter().map(u32::to_string).collect::<Vec<_>>().join(",");
        let data = command(
            &mut wire,
            &format!("UID FETCH {set} (UID BODY.PEEK[HEADER.FIELDS (FROM TO CC SUBJECT)])"),
        )
        .await?;
        let rows = tokio::task::spawn_blocking(move || parse_fetched(&data))
            .await
            .map_err(|_| "worker_failed")??;
        let (account, folder) = (account.clone(), folder.to_owned());
        tokio::task::spawn_blocking(move || store(&account, &folder, validity, &rows))
            .await
            .map_err(|_| "worker_failed")??;
    }
    release(wire, key).await;
    Ok(())
}

static FILLING: LazyLock<Mutex<HashSet<String>>> = LazyLock::new(Default::default);

/// Answers a quick search from the index: the UIDs of `snapshot` (the folder as the server lists it now) matching
/// `criteria`, or None when the index cannot answer and the server must.
pub(super) async fn search(
    p: &Value,
    folder: &str,
    validity: u64,
    snapshot: &[u32],
    criteria: &str,
) -> Option<Vec<u32>> {
    let terms = parse_criteria(criteria)?;
    let account = p["accountId"].as_str()?.to_owned();
    let known = {
        let (account, folder) = (account.clone(), folder.to_owned());
        tokio::task::spawn_blocking(move || load(&account, &folder, validity)).await.ok()?.ok()?
    };
    let have: HashSet<u32> = known.iter().map(|r| r.uid).collect();
    let live: HashSet<u32> = snapshot.iter().copied().collect();
    let missing: Vec<u32> = snapshot.iter().copied().filter(|uid| !have.contains(uid)).collect();
    let gone: Vec<u32> = have.iter().copied().filter(|uid| !live.contains(uid)).collect();
    if !gone.is_empty() {
        let (account, folder) = (account.clone(), folder.to_owned());
        let _ = tokio::task::spawn_blocking(move || prune(&account, &folder, &gone)).await;
    }
    let mut rows: HashMap<u32, Row> = known.into_iter().map(|r| (r.uid, r)).collect();
    if !missing.is_empty() {
        let blocking = missing.len() <= INLINE_MAX || std::env::var("FILI_MAIL_INDEX").is_ok_and(|v| v == "wait");
        if !blocking {
            let marker = format!("{account}\u{0}{folder}");
            if FILLING.lock().ok()?.insert(marker.clone()) {
                let (p, folder) = (p.clone(), folder.to_owned());
                tokio::spawn(async move {
                    let _ = fill(&p, &folder, validity, &missing).await;
                    if let Ok(mut filling) = FILLING.lock() {
                        filling.remove(&marker);
                    }
                });
            }
            return None;
        }
        fill(p, folder, validity, &missing).await.ok()?;
        let (account, folder) = (account.clone(), folder.to_owned());
        let again = tokio::task::spawn_blocking(move || load(&account, &folder, validity)).await.ok()?.ok()?;
        rows = again.into_iter().map(|r| (r.uid, r)).collect();
        if snapshot.iter().filter(|uid| !rows.contains_key(uid)).count() > TOLERATED_GAPS {
            return None;
        }
    }
    let mut found: Vec<u32> = snapshot
        .iter()
        .filter_map(|uid| rows.get(uid))
        .filter(|row| matches_row(row, &terms))
        .map(|row| row.uid)
        .collect();
    found.sort_unstable_by(|a, b| b.cmp(a));
    Some(found)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn criteria_written_by_the_quick_search_are_read_back() {
        let terms = parse_criteria(r#"OR SUBJECT "facture" OR FROM "facture" TO "facture" FROM "amazon""#).unwrap();
        assert_eq!(terms, vec![Term::Word("facture".into()), Term::Field("FROM", "amazon".into())]);
        let quoted = parse_criteria(r#"SUBJECT "a \"b\" é""#).unwrap();
        assert_eq!(quoted, vec![Term::Field("SUBJECT", "a \"b\" é".into())]);
    }

    #[test]
    fn criteria_the_index_does_not_know_go_to_the_server() {
        for criteria in [
            r#"TEXT "facture""#,
            r#"UNSEEN"#,
            r#"OR SUBJECT "a" OR FROM "b" TO "a""#,
            r#"FROM "unterminated"#,
            "",
        ] {
            assert_eq!(parse_criteria(criteria), None, "{criteria}");
        }
    }

    #[test]
    fn a_header_block_becomes_decoded_lower_case_text() {
        let raw = "From: =?UTF-8?Q?Th=C3=A9o_Martin?= <Theo@Example.org>\r\nTo: a@b.fr\r\nCc: C@d.fr\r\nSubject: =?UTF-8?B?RmFjdHVyZSBkZSBkw6ljZW1icmU=?=\r\n\r\n";
        let row = row_of(7, raw.as_bytes());
        assert_eq!(row.sender, "théo martin <theo@example.org>");
        assert_eq!(row.subject, "facture de décembre");
        assert_eq!(row.recipients, "a@b.fr c@d.fr");
        let word = |w: &str| vec![Term::Word(w.into())];
        assert!(matches_row(&row, &word("FACTURE")));
        assert!(matches_row(&row, &word("théo")));
        assert!(matches_row(&row, &word("c@d.fr")));
        assert!(!matches_row(&row, &word("amazon")));
        assert!(!matches_row(&row, &[Term::Field("TO", "theo".into())]));
        assert!(matches_row(&row, &[Term::Field("FROM", "theo".into()), Term::Field("SUBJECT", "décembre".into())]));
    }
}
