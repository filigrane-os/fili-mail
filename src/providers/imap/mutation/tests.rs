use super::*;
#[test]
fn encoded_from_name_never_becomes_the_smtp_sender() {
    for name in ["工 <victim@example.org>, Alias", "工, Lee"] {
        let payload = crate::message::compose::build(&json!({"from":"alias@example.org","fromName":name,"to":"to@example.org","cc":"cc@example.org","bcc":"bcc@example.org","body":"body"})).unwrap();
        let bytes = URL_SAFE_NO_PAD
            .decode(payload["raw"].as_str().unwrap())
            .unwrap();
        let (sender, recipients) = envelope(&bytes, "fallback@example.org").unwrap();
        assert_eq!(sender, "alias@example.org");
        assert_eq!(
            recipients,
            ["to@example.org", "cc@example.org", "bcc@example.org"]
        );
    }
}

#[test]
fn encoded_recipient_names_never_expand_smtp_recipients() {
    let raw = b"From: alias@example.org\r\nTo: =?UTF-8?B?5belIDx2aWN0aW1AZXhhbXBsZS5vcmc+LCBBbGlhcw==?= <to@example.org>\r\nCc: =?UTF-8?B?5belLCBMZWU=?= <cc@example.org>\r\nBcc: =?UTF-8?B?5belIDx2aWN0aW1AZXhhbXBsZS5vcmc+LCBBbGlhcw==?= <bcc@example.org>\r\n\r\nbody";
    assert_eq!(
        envelope(raw, "fallback@example.org").unwrap(),
        (
            "alias@example.org".into(),
            vec![
                "to@example.org".into(),
                "cc@example.org".into(),
                "bcc@example.org".into()
            ]
        )
    );
}
#[test]
fn native_envelope_preserves_groups_cc_and_bcc_recipients() {
    let (from,to)=envelope(b"From: Writer <from@example.org>\r\nTo: Group: a@example.org,b@example.org;\r\nCc: a@example.org\r\nBcc: secret@example.org\r\n\r\nHello","fallback@example.org").unwrap();
    assert_eq!(from, "from@example.org");
    assert_eq!(to, ["a@example.org", "b@example.org", "secret@example.org"]);
}
#[test]
fn folder_encoding_rejects_controls_and_uses_modified_utf7() {
    assert_eq!(encoded_mailbox("日本語").unwrap(), "&ZeVnLIqe-");
    assert_eq!(encoded_mailbox("R&D").unwrap(), "R&-D");
    for value in ["x\r", "x\n", "x\0", "x\t", ""] {
        assert!(encoded_mailbox(value).is_err());
    }
}
#[test]
fn bcc_is_in_envelope_but_absent_from_submitted_headers() {
    let raw=b"From: from@example.org\r\nTo: to@example.org\r\nbCc: secret@example.org,\r\n second@example.org\r\nSubject: visible\r\n\r\nBcc: body text stays\r\n";
    let (_, recipients) = envelope(raw, "fallback@example.org").unwrap();
    assert!(recipients.contains(&"secret@example.org".into()));
    assert!(recipients.contains(&"second@example.org".into()));
    let transmitted = String::from_utf8(without_bcc(raw)).unwrap();
    assert!(!transmitted.contains("secret@example.org"));
    assert!(!transmitted.contains("second@example.org"));
    assert!(transmitted.contains("Bcc: body text stays"));
}
async fn initialize(w: &mut Wire) {
    write(w, b"* OK ready\r\n").await.unwrap();
    assert!(line(w).await.unwrap().starts_with(b"O1 LOGIN"));
    write(w, b"O1 OK login\r\n").await.unwrap();
    for _ in 0..2 {
        assert_eq!(line(w).await.unwrap(), b"O1 CAPABILITY\r\n");
        write(w, b"* CAPABILITY IMAP4rev1\r\nO1 OK capabilities\r\n")
            .await
            .unwrap();
    }
    assert_eq!(line(w).await.unwrap(), b"O1 LIST \"\" \"*\"\r\n");
    write(w,b"* LIST () \"/\" INBOX\r\n* LIST (\\Archive) \"/\" Archive\r\n* LIST (\\Drafts) \"/\" Drafts\r\nO1 OK folders\r\n").await.unwrap();
}
fn params(port: u16) -> Value {
    json!({"settings":{"imapHost":"127.0.0.1","imapPort":port,"username":"synthetic","insecure":true,"testPlaintext":true},"credential":"synthetic:secret","oauth":false})
}
async fn planned_group_failure(failure: &str, use_move: bool, flags_only: bool, stall: bool) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let failure = failure.to_owned();
    let peer = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let mut w: Wire = BufReader::new(Box::new(socket));
        if flags_only {
            initialize(&mut w).await;
        } else {
            write(&mut w, b"* OK ready\r\n").await.unwrap();
            assert!(line(&mut w).await.unwrap().starts_with(b"O1 LOGIN"));
            write(&mut w, b"O1 OK login\r\n").await.unwrap();
            assert_eq!(line(&mut w).await.unwrap(), b"O1 CAPABILITY\r\n");
            write(&mut w, b"* CAPABILITY IMAP4rev1\r\nO1 OK capabilities\r\n")
                .await
                .unwrap();
        }
        'groups: for (folder, set) in [("INBOX", "7,9"), ("ZOther", "8")] {
            let mut commands = vec![
                format!("SELECT \"{folder}\""),
                format!("UID STORE {set} +FLAGS.SILENT (\\Seen)"),
                format!("UID STORE {set} -FLAGS.SILENT (\\Flagged)"),
            ];
            if !flags_only {
                if use_move {
                    commands.push(format!("UID MOVE {set} \"Archive\""));
                } else {
                    commands.extend([
                        format!("UID COPY {set} \"Archive\""),
                        format!("UID STORE {set} +FLAGS.SILENT (\\Deleted)"),
                        format!("UID EXPUNGE {set}"),
                    ]);
                }
            }
            for command in commands {
                assert_eq!(
                    line(&mut w).await.unwrap(),
                    format!("O1 {command}\r\n").as_bytes()
                );
                if folder == "ZOther" && command == failure {
                    if !stall {
                        write(
                            &mut w,
                            b"O1 NO synthetic failure with private diagnostic\r\n",
                        )
                        .await
                        .unwrap();
                    }
                    break 'groups;
                }
                write(&mut w, b"O1 OK acknowledged\r\n").await.unwrap();
            }
        }
        let mut byte = [0];
        assert_eq!(
            w.read(&mut byte).await.unwrap(),
            0,
            "no retry or later group after failure"
        );
        assert!(
            tokio::time::timeout(Duration::from_millis(20), listener.accept())
                .await
                .is_err()
        );
    });
    let mut p = params(port);
    // Preserve input order and spelling, not the BTreeMap's folder/UID order.
    p["ids"] = json!(["8:ZOther", "007:INBOX", "9:INBOX", "10:ZZLast"]);
    p["addLabelIds"] = json!([]);
    p["removeLabelIds"] = if flags_only {
        json!(["UNREAD", "STARRED"])
    } else {
        json!(["INBOX", "UNREAD", "STARRED"])
    };
    let context = if flags_only {
        Value::Null
    } else {
        json!({"folders":[],"special":{"\\archive":"Archive"},"capabilities":if use_move {vec!["MOVE"]} else {vec![]}})
    };
    let result = super::super::execute_planned_action("imap.modify", &p, &context)
        .await
        .unwrap();
    assert_eq!(result["succeededIds"], json!(["007:INBOX", "9:INBOX"]));
    assert_eq!(result["failedIds"], json!(["8:ZOther", "10:ZZLast"]));
    assert_eq!(
        result["error"],
        if stall {
            "request_timed_out"
        } else {
            "imap_command_failed"
        }
    );
    assert!(!result.to_string().contains("private diagnostic"));
    peer.await.unwrap();
}

#[tokio::test]
async fn planned_groups_preserve_acknowledgements_at_every_later_failure_boundary() {
    for failure in [
        "SELECT \"ZOther\"",
        "UID STORE 8 +FLAGS.SILENT (\\Seen)",
        "UID STORE 8 -FLAGS.SILENT (\\Flagged)",
        "UID COPY 8 \"Archive\"",
        "UID STORE 8 +FLAGS.SILENT (\\Deleted)",
        "UID EXPUNGE 8",
    ] {
        planned_group_failure(failure, false, false, false).await;
    }
    planned_group_failure("UID MOVE 8 \"Archive\"", true, false, false).await;
    planned_group_failure("UID STORE 8 -FLAGS.SILENT (\\Flagged)", false, true, false).await;
}

#[tokio::test]
async fn planned_groups_preserve_acknowledgements_when_later_group_exceeds_deadline() {
    planned_group_failure("SELECT \"ZOther\"", true, false, true).await;
}

#[tokio::test]
async fn archive_without_move_sets_flags_then_copy_then_uid_expunge() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let peer = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let mut w: Wire = BufReader::new(Box::new(socket));
        initialize(&mut w).await;
        for wanted in [
            "O1 SELECT \"INBOX\"\r\n",
            "O1 UID STORE 7 +FLAGS.SILENT (\\Seen)\r\n",
            "O1 UID COPY 7 \"Archive\"\r\n",
            "O1 UID STORE 7 +FLAGS.SILENT (\\Deleted)\r\n",
            "O1 UID EXPUNGE 7\r\n",
        ] {
            assert_eq!(line(&mut w).await.unwrap(), wanted.as_bytes());
            write(&mut w, b"O1 OK done\r\n").await.unwrap();
        }
    });
    let mut p = params(port);
    p["ids"] = json!(["7:INBOX"]);
    p["addLabelIds"] = json!([]);
    p["removeLabelIds"] = json!(["INBOX", "UNREAD"]);
    super::super::call("imap.modify", &p).await.unwrap();
    peer.await.unwrap();
}
#[tokio::test]
async fn malformed_later_mutation_id_opens_no_socket() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let mut p = params(port);
    p["ids"] = json!(["7:INBOX", "8:INBOX\r\nEXPUNGE"]);
    p["addLabelIds"] = json!([]);
    p["removeLabelIds"] = json!(["INBOX"]);
    assert_eq!(
        super::super::call("imap.modify", &p).await,
        Err("invalid_params")
    );
    assert!(
        tokio::time::timeout(Duration::from_millis(20), listener.accept())
            .await
            .is_err()
    );
}
#[tokio::test]
async fn saved_draft_cleanup_failure_still_returns_saved() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let raw = b"Subject: draft\r\n\r\nbody";
    let peer = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let mut w: Wire = BufReader::new(Box::new(socket));
        initialize(&mut w).await;
        assert_eq!(
            line(&mut w).await.unwrap(),
            format!("O1 APPEND \"Drafts\" (\\Draft) {{{}}}\r\n", raw.len()).as_bytes()
        );
        write(&mut w, b"+ send data\r\n").await.unwrap();
        let mut bytes = vec![0; raw.len() + 2];
        w.read_exact(&mut bytes).await.unwrap();
        assert_eq!(&bytes[..raw.len()], raw);
        write(&mut w, b"O1 OK appended\r\n").await.unwrap();
        assert_eq!(line(&mut w).await.unwrap(), b"O1 SELECT \"Drafts\"\r\n");
        write(&mut w, b"O1 NO cannot select\r\n").await.unwrap();
    });
    let mut p = params(port);
    p["raw"] = json!(URL_SAFE_NO_PAD.encode(raw));
    p["draftId"] = json!("7:Drafts");
    let result = super::super::call("imap.saveDraft", &p).await.unwrap();
    assert_eq!(result["saved"], true);
    assert!(result["warning"].as_str().unwrap().contains("old copy"));
    peer.await.unwrap();
}
#[tokio::test]
async fn invalid_draft_replacement_id_is_refused_before_append() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    for id in [
        "bad",
        "0:Drafts",
        "7:Drafts\r",
        "7:Drafts\n",
        "7:Drafts\r\n",
        "7:Drafts\0",
    ] {
        let mut p = params(port);
        p["raw"] = json!(URL_SAFE_NO_PAD.encode(b"Subject: draft\r\n\r\nbody"));
        p["draftId"] = json!(id);
        assert_eq!(
            super::super::call("imap.saveDraft", &p).await,
            Err("invalid_params")
        );
    }
    for wrong_type in [
        json!(123),
        json!({"id":"7:Drafts"}),
        json!(["7:Drafts"]),
        Value::Null,
        json!(false),
    ] {
        let mut p = params(port);
        p["raw"] = json!(URL_SAFE_NO_PAD.encode(b"Subject: draft\r\n\r\nbody"));
        p["draftId"] = wrong_type;
        assert_eq!(
            super::super::call("imap.saveDraft", &p).await,
            Err("invalid_params")
        );
    }
    assert!(
        tokio::time::timeout(Duration::from_millis(20), listener.accept())
            .await
            .is_err()
    );
}

/// Fake server for `imap.emptyTrash`: the answer to SELECT says how many messages the Trash holds.
async fn empty_trash_server(exists: u32, batch: u32) -> (u16, tokio::task::JoinHandle<()>) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let peer = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let mut w: Wire = BufReader::new(Box::new(socket));
        write(&mut w, b"* OK ready\r\n").await.unwrap();
        assert!(line(&mut w).await.unwrap().starts_with(b"O1 LOGIN"));
        write(&mut w, b"O1 OK login\r\n").await.unwrap();
        for _ in 0..2 {
            assert_eq!(line(&mut w).await.unwrap(), b"O1 CAPABILITY\r\n");
            write(&mut w, b"* CAPABILITY IMAP4rev1\r\nO1 OK capabilities\r\n").await.unwrap();
        }
        assert_eq!(line(&mut w).await.unwrap(), b"O1 LIST \"\" \"*\"\r\n");
        write(&mut w, b"* LIST () \"/\" INBOX\r\n* LIST (\\Trash) \"/\" Bin\r\nO1 OK folders\r\n").await.unwrap();
        // Only the folder with the Trash role is touched, never INBOX
        assert_eq!(line(&mut w).await.unwrap(), b"O1 SELECT \"Bin\"\r\n");
        write(&mut w, format!("* {exists} EXISTS\r\nO1 OK selected\r\n").as_bytes()).await.unwrap();
        if exists > 0 {
            assert_eq!(line(&mut w).await.unwrap(), format!("O1 STORE 1:{batch} +FLAGS.SILENT (\\Deleted)\r\n").as_bytes());
            write(&mut w, b"O1 OK flagged\r\n").await.unwrap();
            assert_eq!(line(&mut w).await.unwrap(), b"O1 EXPUNGE\r\n");
            write(&mut w, b"O1 OK expunged\r\n").await.unwrap();
        }
        // Nothing else is sent (no STORE on an empty Trash)
        // (the connection goes back to the pool, so it stays open: no data is the answer)
        let mut byte = [0];
        match tokio::time::timeout(Duration::from_millis(100), w.read(&mut byte)).await {
            Err(_) | Ok(Ok(0)) => {}
            other => panic!("unexpected command after the expunge: {other:?}"),
        }
    });
    (port, peer)
}

#[tokio::test]
async fn empty_trash_deletes_everything_in_the_trash_folder_only() {
    let (port, peer) = empty_trash_server(3, 3).await;
    let p = params(port);
    let result = call("imap.emptyTrash", &p, &std::sync::atomic::AtomicBool::new(false)).await.unwrap();
    assert_eq!(result["deleted"], 3);
    assert_eq!(result["remaining"], 0);
    peer.await.unwrap();
}

#[tokio::test]
async fn empty_trash_works_by_batches_of_500() {
    let (port, peer) = empty_trash_server(1200, 500).await;
    let p = params(port);
    let result = call("imap.emptyTrash", &p, &std::sync::atomic::AtomicBool::new(false)).await.unwrap();
    assert_eq!(result["deleted"], 500);
    assert_eq!(result["remaining"], 700);
    peer.await.unwrap();
}

#[tokio::test]
async fn empty_trash_on_an_empty_trash_sends_no_store() {
    let (port, peer) = empty_trash_server(0, 0).await;
    let p = params(port);
    let result = call("imap.emptyTrash", &p, &std::sync::atomic::AtomicBool::new(false)).await.unwrap();
    assert_eq!(result["deleted"], 0);
    peer.await.unwrap();
}

/// Fake server for a trash from "All Mail": `accepts_move` says whether the server takes the MOVE.
async fn all_mail_trash(accepts_move: bool) -> Value {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let peer = tokio::spawn(async move {
        let (socket, _) = listener.accept().await.unwrap();
        let mut w: Wire = BufReader::new(Box::new(socket));
        write(&mut w, b"* OK ready\r\n").await.unwrap();
        assert!(line(&mut w).await.unwrap().starts_with(b"O1 LOGIN"));
        write(&mut w, b"O1 OK login\r\n").await.unwrap();
        assert_eq!(line(&mut w).await.unwrap(), b"O1 CAPABILITY\r\n");
        write(&mut w, b"* CAPABILITY IMAP4rev1 MOVE\r\nO1 OK capabilities\r\n").await.unwrap();
        assert_eq!(line(&mut w).await.unwrap(), b"O1 SELECT \"All Mail\"\r\n");
        write(&mut w, b"O1 OK done\r\n").await.unwrap();
        // The MOVE is always tried first
        assert_eq!(line(&mut w).await.unwrap(), b"O1 UID MOVE 7,9 \"Trash\"\r\n");
        if accepts_move {
            write(&mut w, b"O1 OK moved\r\n").await.unwrap();
        } else {
            write(&mut w, b"O1 NO operation not allowed\r\n").await.unwrap();
            assert_eq!(line(&mut w).await.unwrap(), b"O1 UID COPY 7,9 \"Trash\"\r\n");
            write(&mut w, b"O1 OK copied\r\n").await.unwrap();
        }
        // (the connection goes back to the pool and stays open: no data is the answer)
        let mut byte = [0];
        match tokio::time::timeout(Duration::from_millis(100), w.read(&mut byte)).await {
            Err(_) | Ok(Ok(0)) => {}
            other => panic!("unexpected command: {other:?}"),
        }
    });
    let mut p = params(port);
    p["ids"] = json!(["7:All Mail", "9:All Mail"]);
    let context = json!({"folders":[],"special":{"\\trash":"Trash","\\all":"All Mail"},"capabilities":["MOVE"]});
    let result = super::super::execute_planned_action("imap.trash", &p, &context).await.unwrap();
    peer.await.unwrap();
    result
}

#[tokio::test]
async fn trashing_from_all_mail_moves_when_the_server_allows_it() {
    let result = all_mail_trash(true).await;
    assert_eq!(result["succeededIds"], json!(["7:All Mail", "9:All Mail"]));
}

/// Proton Bridge refuses to MOVE out of "All Mail" ("operation not allowed"): only then, a COPY.
#[tokio::test]
async fn trashing_from_all_mail_copies_when_the_server_refuses_the_move() {
    let result = all_mail_trash(false).await;
    assert_eq!(result["succeededIds"], json!(["7:All Mail", "9:All Mail"]));
    assert_eq!(result["failedIds"], json!([]));
}
