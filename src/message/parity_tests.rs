use super::*;
use serde_json::{Value, json};
#[test]
fn outgoing_refuses_header_controls_and_preserves_binary() {
    for control in ['\0', '\t', '\u{7f}'] {
        let fields = json!({"to":format!("a@example.org{control}Bcc: victim@example.org")});
        assert!(compose::build(&fields).is_err());
    }
    let fields = json!({"to":"a@example.org\r\nBcc: victim@example.org","body":"legitimate\r\nbody","attachments":[{"filename":"x\r\nInjected: bad","data":"AP_-AQ"}],"boundary":"x"});
    let output = compose::build(&fields).unwrap();
    let raw = URL_SAFE_NO_PAD
        .decode(output["raw"].as_str().unwrap())
        .unwrap();
    let wire = String::from_utf8(raw.clone()).unwrap();
    assert!(!wire.contains("\r\nBcc:"));
    assert!(!wire.contains("\r\nInjected:"));
    let parsed = mailparse::parse_mail(&raw).unwrap();
    assert_eq!(parsed.subparts[1].get_body_raw().unwrap(), [0, 255, 254, 1]);
}
#[test]
fn outgoing_nested_boundary_cannot_alias_outer() {
    let fields = json!({"body":"مرحبا","boundary":"alt_".repeat(15),"attachments":[{"filename":"x","data":"AA"}]});
    let output = compose::build(&fields).unwrap();
    let bytes = URL_SAFE_NO_PAD
        .decode(output["raw"].as_str().unwrap())
        .unwrap();
    let parsed = mailparse::parse_mail(&bytes).unwrap();
    assert_eq!(parsed.subparts.len(), 2);
    assert_eq!(parsed.subparts[0].subparts.len(), 2);
}
#[test]
fn prepare_bounds_untrusted_mime_and_restores_compose_text() {
    let mut part = json!({"mimeType":"text/plain","body":{"data":"aGVsbG8"}});
    for _ in 0..20 {
        part = json!({"parts":[part]});
    }
    assert_eq!(
        content::prepare(&json!({"payload":part}), 0).unwrap()["body"]["text"],
        ""
    );
    assert!(content::request("message.prepare", &json!({"message":{},"now":"wrong"})).is_err());
    assert_eq!(content::request("message.composeText",&json!({"signature":" signed ","body":"one\ntwo","summary":{"subject":"hello","from":{"display":"Jane"},"fullTime":"today"}})).unwrap(),json!({"body":"\n\nsigned\n\nOn today, Jane wrote:\n> one\n> two","quote":"On today, Jane wrote:\n> one\n> two","replySubject":"Re: hello"}));
}

#[test]
fn composition_has_explicit_output_and_attachment_limits() {
    assert_eq!(
        compose::build(&json!({"body":"x".repeat(compose::MAX_RAW)})).unwrap_err(),
        "message_too_large"
    );
    assert_eq!(
        compose::build(&json!({"attachments":vec![json!({});257]})).unwrap_err(),
        "too_many_attachments"
    );
    assert_eq!(
        compose::build(&json!({"attachments":[{"data":"%%%"}]})).unwrap_err(),
        "invalid_attachment_encoding"
    );
}

#[test]
fn outgoing_preserves_twenty_mebibyte_attachment_support() {
    use base64::engine::general_purpose::STANDARD;
    let data = STANDARD.encode(vec![0xab; 20 * 1024 * 1024]);
    let output=compose::build(&json!({"to":"test@example.org","body":"hello","attachments":[{"filename":"large.bin","data":data}]})).unwrap();
    assert!(output["raw"].as_str().unwrap().len() < 48 * 1024 * 1024);
    let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(output["raw"].as_str().unwrap())
        .unwrap();
    let parsed = mailparse::parse_mail(&bytes).unwrap();
    assert_eq!(parsed.subparts.len(), 2);
    let attachment = &parsed.subparts[1];
    assert_eq!(
        attachment.get_content_disposition().params["filename"],
        "large.bin"
    );
    assert_eq!(
        attachment.get_body_raw().unwrap(),
        vec![0xab; 20 * 1024 * 1024]
    );
}
#[test]
fn outgoing_address_words_never_hide_address_structure() {
    use mailparse::MailHeaderMap;
    for name in ["工 <victim@example.org>, Alias", "工, Lee"] {
        let quoted = format!("\"{name}\"");
        let fields = json!({"from":"alias@example.org","fromName":name,
            "to":format!("{quoted} <to@example.org>"),
            "cc":format!("{quoted} <cc@example.org>"),
            "bcc":format!("{quoted} <bcc@example.org>"),"body":"body"});
        let payload = crate::message::compose::build(&fields).unwrap();
        let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
            .decode(payload["raw"].as_str().unwrap())
            .unwrap();
        let (headers, _) = mailparse::parse_headers(&bytes).unwrap();
        for (key, expected) in [
            ("From", "alias@example.org"),
            ("To", "to@example.org"),
            ("Cc", "cc@example.org"),
            ("Bcc", "bcc@example.org"),
        ] {
            let addresses =
                mailparse::addrparse_header(headers.get_first_header(key).unwrap()).unwrap();
            let one = addresses
                .extract_single_info()
                .expect("one structural address");
            assert_eq!(one.addr, expected);
            assert_eq!(one.display_name.as_deref(), Some(name));
        }
    }
}

fn composed_headers(fields: &Value) -> (Vec<u8>, Value) {
    let raw = URL_SAFE_NO_PAD
        .decode(compose::build(fields).unwrap()["raw"].as_str().unwrap())
        .unwrap();
    let summary = content::prepare(&json!({"payload":parse(&raw).unwrap()}), 0).unwrap();
    (raw, summary["summary"].clone())
}

#[test]
fn display_names_with_specials_stay_one_name_in_every_address_header() {
    use mailparse::MailHeaderMap;
    let mut names: Vec<(String, String)> = "()<>[]:;@\\,.\""
        .chars()
        .map(|c| format!("Ada {c} Lovelace"))
        .chain(
            [
                "Doe, Jane",
                "Say \"hi\" \\ bye",
                "ends with \\",
                "\"",
                "()<>[]:;@\\,.\"",
                "Team: eve@example.net;",
                "eve@example.net",
                "Müller, Jörg",
                "工, Lee <eve@example.net>",
                // Readers decode `=?` even inside quotes, so it leaves encoded.
                "=?UTF-8?B?PGV2ZUBleGFtcGxlLm5ldD4=?=",
            ]
            .map(String::from),
        )
        .map(|name| (name.clone(), name))
        .collect();
    for (typed, read) in [
        ("Ada\rBcc: eve@example.net", "Ada Bcc: eve@example.net"),
        ("Ada\nLovelace", "Ada Lovelace"),
        ("Ada\r\nLovelace", "Ada Lovelace"),
    ] {
        names.push((typed.into(), read.into()));
    }
    for (name, read) in &names {
        // The To text as the composer's field holds it.
        let typed = |email: &str| format!("{} <{email}>", compose::quoted_phrase(name, false));
        let fields = json!({"from":"me@example.org","fromName":name,
            "to":format!("{}, ada@example.org", typed("to@example.org")),
            "cc":typed("cc@example.org"),"bcc":typed("bcc@example.org"),
            "replyTo":typed("reply@example.org"),"body":"body"});
        let (raw, summary) = composed_headers(&fields);
        let (headers, _) = mailparse::parse_headers(&raw).unwrap();
        assert!(
            headers.iter().all(|h| h.get_value_raw().is_ascii()),
            "{name:?}"
        );
        assert!(headers.get_all_headers("Bcc").len() == 1, "{name:?}");
        for (key, expected) in [
            ("From", vec!["me@example.org"]),
            ("To", vec!["to@example.org", "ada@example.org"]),
            ("Cc", vec!["cc@example.org"]),
            ("Bcc", vec!["bcc@example.org"]),
            ("Reply-To", vec!["reply@example.org"]),
        ] {
            let list = mailparse::addrparse_header(headers.get_first_header(key).unwrap()).unwrap();
            let singles: Vec<_> = list
                .iter()
                .map(|a| match a {
                    mailparse::MailAddr::Single(s) => s.clone(),
                    _ => panic!("{name:?} made a group in {key}"),
                })
                .collect();
            assert_eq!(
                singles.iter().map(|s| s.addr.as_str()).collect::<Vec<_>>(),
                expected,
                "{name:?} {key}"
            );
            assert_eq!(
                singles[0].display_name.as_deref(),
                Some(read.as_str()),
                "{name:?} {key}"
            );
        }
        // And the reader this app draws a message with agrees.
        assert_eq!(summary["from"]["name"], read.as_str(), "{name:?}");
        assert_eq!(summary["to"].as_array().unwrap().len(), 2, "{name:?}");
        assert_eq!(summary["to"][0]["name"], read.as_str(), "{name:?}");
        assert_eq!(summary["cc"][0]["name"], read.as_str(), "{name:?}");
    }
    assert_eq!(
        compose::build(&json!({"from":"me@example.org","fromName":"Ada\0Lovelace"})).unwrap_err(),
        "invalid_message_header"
    );
}

fn to_line(to: &str) -> Result<String, &'static str> {
    use mailparse::MailHeaderMap;
    let raw = URL_SAFE_NO_PAD
        .decode(
            compose::build(&json!({"to":to,"body":"b"}))?["raw"]
                .as_str()
                .unwrap(),
        )
        .unwrap();
    let (headers, _) = mailparse::parse_headers(&raw).unwrap();
    Ok(String::from_utf8(
        headers
            .get_first_header("To")
            .unwrap()
            .get_value_raw()
            .to_vec(),
    )
    .unwrap())
}

#[test]
fn typed_ascii_lists_go_out_as_typed_and_rewrites_refuse_what_they_could_change() {
    // A group in the middle, a nameless address with specials, a comment, an
    // unquoted comma, a half-typed draft: all as typed.
    for typed in [
        "ada@example.org, Team: eve@example.net; <dave@example.org>",
        "<a@example.org,eve@example.net>, <team:eve@example.net;>",
        "Smith (Sales) <s@example.org>, ann@example.org (Ann)",
        "Doe, Jane <x@example.org>",
        "bo",
    ] {
        assert_eq!(to_line(typed).unwrap(), typed);
    }
    // A list ASCII cannot carry, or with a name holding `=?`, is written again:
    // a nameless address keeps its brackets unless it is a plain addr-spec.
    assert_eq!(
        to_line("Jörg <j@example.org>, <a@example.org,eve@example.net>, <c@example.org>").unwrap(),
        "=?UTF-8?B?SsO2cmc=?= <j@example.org>, <a@example.org,eve@example.net>, c@example.org"
    );
    assert_eq!(
        to_line("=?utf-8?q?Team=3A_eve=40example=2Enet=3B?= <dave@example.org>").unwrap(),
        format!(
            "=?UTF-8?B?{}?= <dave@example.org>",
            base64::engine::general_purpose::STANDARD
                .encode("=?utf-8?q?Team=3A_eve=40example=2Enet=3B?=")
        )
    );
    // And refuses a group, an address that is not ASCII or printable, and what
    // it cannot read.
    for typed in [
        "Jörg <j@example.org>, Team: eve@example.net; <dave@example.org>",
        "Équipe: a@example.org, b@example.org;",
        "Jörg <j@example.org>, undisclosed-recipients:;",
        "=?x?=: a@example.org;",
        "x <jörg@example.org>",
        "jörg@example.org",
        "x <a\u{85}@example.org>",
        "x <a\0@example.org>",
        "Müller, Jörg <j@example.org>",
        // Rewritten, these would lose their first recipient: mailparse reads the
        // address's `=?utf-8?q?` as an encoded word that runs into the next
        // name, and the address turns into display text.
        "=?utf-8?q?a?=b@example.org, Jörg <c@example.org>",
        " =?utf-8?q?a?=b@example.org=?x?= ,=?utf-8?q?a?=Jörg <c@example.org,d@example.org>",
    ] {
        assert_eq!(
            to_line(typed).unwrap_err(),
            "invalid_message_header",
            "{typed:?}"
        );
    }
}

#[test]
fn composed_lists_name_the_recipients_that_were_typed() {
    // Random lists of specials, names that need rewriting and addresses:
    // whenever a message is built, its To names exactly the addresses mailparse
    // reads in the typed text, rewritten or not.
    let pieces = [
        "\"",
        "<",
        ">",
        "(",
        ")",
        "[",
        "]",
        ":",
        ";",
        "@",
        "\\",
        ",",
        ".",
        " ",
        "a",
        "é",
        "Jörg ",
        "=?x?= ",
        "\"Müller, Jörg\" ",
        "<a@example.org>",
        "b@example.org",
        "<c@example.org,d@example.org>",
        "Team: ",
        "(Sales) ",
    ];
    let mut seed: u64 = 0x9e3779b97f4a7c15;
    for _ in 0..200000 {
        seed ^= seed << 13;
        seed ^= seed >> 7;
        seed ^= seed << 17;
        let mut x = seed;
        let typed: String = (0..(seed % 10) as usize + 1)
            .map(|_| {
                x = x
                    .wrapping_mul(6364136223846793005)
                    .wrapping_add(1442695040888963407);
                pieces[((x >> 33) as usize) % pieces.len()]
            })
            .collect();
        let Ok(payload) = compose::build(&json!({"to":typed,"body":"b"})) else {
            continue;
        };
        let raw = URL_SAFE_NO_PAD
            .decode(payload["raw"].as_str().unwrap())
            .unwrap();
        let (headers, _) = mailparse::parse_headers(&raw).unwrap();
        let before = format!("To: {typed}\r\n\r\n");
        let (typed_headers, _) = mailparse::parse_headers(before.as_bytes()).unwrap();
        if let Ok(expected) = envelope::addresses(&typed_headers, "To") {
            assert_eq!(
                envelope::addresses(&headers, "To"),
                Ok(expected),
                "{typed:?}"
            );
        }
    }
}

#[test]
fn address_lists_honour_escapes_inside_quoted_names() {
    let read = content::addresses("\"O\\\"Neil, Pat\" <pat@example.org>, ada@example.org");
    assert_eq!(read.len(), 2);
    assert_eq!(read[0]["name"], "O\"Neil, Pat");
    assert_eq!(read[1]["email"], "ada@example.org");
}
