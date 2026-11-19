use serde_json::{Value, json};
use std::collections::BTreeSet;
use tabled::{
    builder::Builder,
    settings::{Style, Width, peaker::PriorityMax},
};

pub(super) fn print_result(result: Result<Value, &'static str>, json: bool, envelope: bool) {
    match result {
        Ok(value) => {
            let failure = result_failure(&value);
            if json {
                let value = if let Some(code) = failure {
                    json!({"ok":false,"error":{"code":code},"result":value})
                } else if envelope {
                    json!({"ok":true,"result":value})
                } else {
                    value
                };
                println!("{}", serde_json::to_string_pretty(&value).unwrap());
            } else {
                print!("{}", pretty(&value));
            }
            if let Some(code) = failure {
                if !json {
                    eprintln!("fili-mail: {code}");
                }
                std::process::exit(1);
            }
        }
        Err(code) => {
            if json {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&json!({"ok":false,"error":{"code":code}}))
                        .unwrap()
                );
            } else {
                eprintln!("fili-mail: {code}");
            }
            std::process::exit(1);
        }
    }
}

fn result_failure(value: &Value) -> Option<&'static str> {
    if value["failedIds"]
        .as_array()
        .is_some_and(|ids| !ids.is_empty())
    {
        return Some("mail_action_failed");
    }
    if value["executed"] == true && value["sendId"].is_string() {
        let entry = value["outbox"]["entries"]
            .as_array()?
            .iter()
            .find(|entry| entry["id"] == value["sendId"])?;
        return match entry["state"].as_str() {
            Some("sent") => None,
            Some("failed") if entry["error"] == "outbox_storage_unavailable" => {
                Some("outbox_storage_unavailable")
            }
            Some("failed") => Some("outbox_send_refused"),
            Some("cancelled") => Some("outbox_stopped_unsent"),
            _ => Some("outbox_delivery_unknown"),
        };
    }
    None
}

// Sender-controlled text must not execute terminal escapes or inject table rows.
fn safe(text: &str) -> String {
    let mut result = String::new();
    for c in text.chars() {
        match c {
            '\n' => result.push_str("\\n"),
            '\r' => result.push_str("\\r"),
            '\t' => result.push_str("\\t"),
            '\\' => result.push_str("\\\\"),
            '|' => result.push_str("\\|"),
            c if c.is_control()
                || matches!(c, '\u{061c}' | '\u{200e}'..='\u{200f}' | '\u{2028}'..='\u{202e}' | '\u{2066}'..='\u{2069}') =>
            {
                result.extend(c.escape_unicode());
            }
            c => result.push(c),
        }
    }
    result
}

// Like `safe`, but keeps line breaks (message bodies)
fn safe_body(text: &str) -> String {
    text.lines().map(|l| safe(l.trim_end()).replace("\\|", "|")).collect::<Vec<_>>().join("\n")
}

fn who(value: &Value) -> String {
    let name = value["display"].as_str().or(value["name"].as_str()).unwrap_or("");
    let email = value["email"].as_str().unwrap_or("");
    match (name.is_empty(), email.is_empty()) {
        (false, false) if name != email => format!("{name} <{email}>"),
        (false, _) => name.to_string(),
        _ => email.to_string(),
    }
}

fn people(value: &Value) -> String {
    value.as_array().map(|a| a.iter().map(who).collect::<Vec<_>>().join(", ")).unwrap_or_default()
}

// One line per message: id, date, flags, sender, subject (what a person or an agent needs to pick a mail)
fn compact_list(object: &serde_json::Map<String, Value>) -> String {
    let messages = object["messages"].as_array().map(Vec::as_slice).unwrap_or(&[]);
    let mut out = format!(
        "{} - {} message(s) shown, about {} in all\n",
        safe(&cell(&object["mailbox"])),
        messages.len(),
        cell(&object["estimate"])
    );
    for m in messages {
        let flag = |on: &Value, c: &str| if on == &Value::Bool(true) { c.to_string() } else { "-".to_string() };
        let flags = format!("{}{}{}", flag(&m["unread"], "U"), flag(&m["starred"], "*"), flag(&m["hasAttachment"], "@"));
        let sender = who(&m["from"]);
        out.push_str(&format!(
            "{}  {}  {}  {}  {}\n",
            safe(&cell(&m["id"])),
            safe(&cell(&m["fullTime"])),
            flags,
            safe(&sender),
            safe(&cell(&m["subject"]))
        ));
    }
    if let Some(token) = object["nextPageToken"].as_str().filter(|t| !t.is_empty()) {
        out.push_str(&format!("more: --page-token {}\n", safe(token)));
    }
    out.push_str("flags: U unread, * starred, @ attachment\n");
    out
}

// Headers and the readable text of one message (links, remote images and the render tree stay in --json)
fn compact_message(object: &serde_json::Map<String, Value>) -> Option<String> {
    let message = object.get("message")?;
    let summary = message.get("summary")?;
    let body = message["nativeContent"]["body"]["text"].as_str().unwrap_or("");
    let collapsed = body.split('\n').map(str::trim_end).collect::<Vec<_>>().join("\n");
    let mut text = String::new();
    let mut blank = 0;
    for line in collapsed.lines() {
        if line.trim().is_empty() {
            blank += 1;
            if blank > 1 {
                continue;
            }
        } else {
            blank = 0;
        }
        text.push_str(line);
        text.push('\n');
    }
    const LIMIT: usize = 6000;
    let total = text.chars().count();
    let shown: String = text.chars().take(LIMIT).collect();
    let mut out = format!(
        "From: {}\nTo: {}\n",
        safe(&who(&summary["from"])),
        safe(&people(&summary["to"]))
    );
    let cc = people(&summary["cc"]);
    if !cc.is_empty() {
        out.push_str(&format!("Cc: {}\n", safe(&cc)));
    }
    out.push_str(&format!("Date: {}\nSubject: {}\n", safe(&cell(&summary["fullTime"])), safe(&cell(&summary["subject"]))));
    let attachments = message["attachments"].as_array().map(Vec::len).unwrap_or(0);
    if attachments > 0 {
        out.push_str(&format!("Attachments: {attachments}\n"));
    }
    out.push('\n');
    out.push_str(&safe_body(&shown));
    out.push('\n');
    if total > LIMIT {
        out.push_str(&format!("[truncated: {LIMIT} of {total} characters; --json has everything]\n"));
    }
    Some(out)
}

fn cell(value: &Value) -> String {
    match value {
        Value::Null => "-".into(),
        Value::String(text) => text.clone(),
        Value::Bool(value) => if *value { "yes" } else { "no" }.into(),
        Value::Array(values) => values.iter().map(cell).collect::<Vec<_>>().join(", "),
        Value::Object(values) => values
            .iter()
            .map(|(key, value)| format!("{key}: {}", cell(value)))
            .collect::<Vec<_>>()
            .join(", "),
        _ => value.to_string(),
    }
}

fn table(headers: Vec<String>, rows: Vec<Vec<String>>) -> String {
    let mut builder = Builder::default();
    builder.push_record(headers.iter().map(|text| safe(text)));
    for row in rows {
        builder.push_record(row.iter().map(|text| safe(text)));
    }
    format!(
        "{}\n",
        builder.build().with(Style::markdown()).with(
            Width::wrap(100)
                .priority(PriorityMax::new(false))
                .keep_words(true)
        )
    )
}

fn pretty(value: &Value) -> String {
    match value {
        Value::Object(object)
            if object.contains_key("name")
                && object.contains_key("version")
                && object.contains_key("protocol")
                && object.get("methods").is_some_and(Value::is_array) =>
        {
            let metadata = table(
                vec!["Field".into(), "Value".into()],
                object
                    .iter()
                    .filter(|(key, _)| key.as_str() != "methods")
                    .map(|(key, value)| vec![key.clone(), cell(value)])
                    .collect(),
            );
            let methods = table(
                vec!["Method".into()],
                object["methods"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|method| vec![cell(method)])
                    .collect(),
            );
            format!("{metadata}\n{methods}")
        }
        Value::Object(object)
            if object.contains_key("accounts") && object.contains_key("activeId") =>
        {
            format!(
                "Active account: {}\n\n{}",
                safe(&cell(&object["activeId"])),
                pretty(&object["accounts"])
            )
        }
        Value::Object(object) if object.get("messages").is_some_and(Value::is_array) && object.contains_key("mailbox") => {
            compact_list(object)
        }
        Value::Object(object) if compact_message(object).is_some() => compact_message(object).unwrap(),
        Value::Object(object) => table(
            vec!["Field".into(), "Value".into()],
            object
                .iter()
                .map(|(key, value)| vec![key.clone(), cell(value)])
                .collect(),
        ),
        Value::Array(values) if values.is_empty() => "No entries.\n".into(),
        Value::Array(values) if values.iter().all(Value::is_object) => {
            let keys: BTreeSet<&String> = values
                .iter()
                .flat_map(|value| value.as_object().unwrap().keys())
                .collect();
            if keys.is_empty() {
                return format!("{} empty entries.\n", values.len());
            }
            table(
                keys.iter().map(|key| (*key).clone()).collect(),
                values
                    .iter()
                    .map(|value| keys.iter().map(|key| cell(&value[*key])).collect())
                    .collect(),
            )
        }
        Value::Array(values) => table(
            vec!["Value".into()],
            values.iter().map(|value| vec![cell(value)]).collect(),
        ),
        value => format!("{}\n", safe(&cell(value))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn list_is_one_line_per_message_and_escapes_sender_text() {
        let v = json!({"mailbox":"inbox","estimate":2,"nextPageToken":"1","messages":[
            {"id":"1:INBOX","fullTime":"Nov 19","unread":true,"starred":false,"hasAttachment":true,
             "from":{"display":"Eve\u{1b}[31m","email":"e@x.org"},"subject":"a\nb | c"}]});
        let out = pretty(&v);
        assert!(out.contains("1:INBOX  Nov 19  U-@  "));
        assert!(!out.contains('\u{1b}'));
        assert_eq!(out.lines().filter(|l| l.starts_with("1:INBOX")).count(), 1);
        assert!(out.contains("more: --page-token 1"));
    }

    #[test]
    fn message_shows_headers_and_body_without_the_render_tree() {
        let v = json!({"accountId":"a","message":{"attachments":[],"links":[{"url":"https://x"}],
            "nativeContent":{"body":{"text":"Hello\n\n\n\nworld"}},
            "summary":{"from":{"name":"Ann","email":"a@x.org"},"to":[{"email":"me@x.org"}],"cc":[],"fullTime":"Nov 19","subject":"Hi"}}});
        let out = pretty(&v);
        assert!(out.starts_with("From: Ann <a@x.org>\nTo: me@x.org\n"));
        assert!(out.contains("Hello\n\nworld"));
        assert!(!out.contains("https://x"));
    }

    #[test]
    fn send_storage_failure_is_not_reported_as_a_provider_refusal() {
        let result = json!({"executed":true,"sendId":"one","outbox":{"entries":[{"id":"one","state":"failed","error":"outbox_storage_unavailable"}]}});
        assert_eq!(result_failure(&result), Some("outbox_storage_unavailable"));
    }

    #[test]
    fn sender_fields_cannot_control_the_terminal_or_inject_table_rows() {
        let result = pretty(&json!({"messages":[{
            "from":"Eve\u{1b}[31m\r\n|forged\trow\u{202e}\u{2067}工"
        }]}));
        for control in ['\u{1b}', '\r', '\t', '\u{202e}', '\u{2067}'] {
            assert!(!result.contains(control));
        }
        assert!(result.contains("\\u{1b}") && result.contains("\\u{202e}"));
        assert!(!result.lines().any(|line| line.starts_with("|forged")));
        assert!(result.contains("工"));
    }
}
