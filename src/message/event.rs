//! A mail about a meeting: an invitation (iCalendar text in the message), an `.ics` file attached, or a video conference link
//! (Meet, Teams, Zoom…). The reader shows "Add to Agenda" for it; Agenda (fili-cal) does the rest: its import preview for
//! an invitation (with Accept, Maybe, Decline), its editor, filled, for a link. Nothing is added without the user saving it.
use serde_json::{Value, json};

/// What the reader offers for a message (`Value::Null`: nothing). `message` is the `message` object of `mail.read`.
pub fn detect(message: &Value) -> Value {
    let subject = message["summary"]["subject"].as_str().unwrap_or("").trim();
    let sender = message["summary"]["from"]["display"].as_str().or(message["summary"]["from"]["email"].as_str()).unwrap_or("");
    if let Some(ics) = message["calendar"].as_str().filter(|t| t.contains("BEGIN:VEVENT")) {
        let fields = vevent(ics);
        let method = property(ics, "METHOD").unwrap_or_default().to_ascii_uppercase();
        // a cancellation is not something to add
        if method != "CANCEL" {
            let title = fields.summary.unwrap_or_else(|| subject.to_owned());
            return json!({"kind": "invite", "title": title, "start": fields.start.unwrap_or_default(), "invite": method == "REQUEST", "ics": ics});
        }
        return Value::Null;
    }
    let attached = message["nativeContent"]["attachments"].as_array().into_iter().flatten().find(|a| {
        let mime = a["mimeType"].as_str().unwrap_or("").to_ascii_lowercase();
        let name = a["filename"].as_str().unwrap_or("").to_ascii_lowercase();
        (mime.starts_with("text/calendar") || name.ends_with(".ics")) && !a["attachmentId"].as_str().unwrap_or("").is_empty()
    });
    if let Some(a) = attached {
        return json!({"kind": "file", "title": subject, "start": "", "attachmentId": a["attachmentId"], "filename": a["filename"]});
    }
    // The links of the HTML (vetted by the engine), then the words of the text
    let mut urls: Vec<String> = message["links"].as_array().into_iter().flatten().filter_map(|l| l["url"].as_str().map(str::to_owned)).collect();
    let body = message["nativeContent"]["body"]["text"].as_str().unwrap_or("");
    urls.extend(body.split(|c: char| c.is_whitespace() || "<>\"'()[],;".contains(c)).filter(|w| w.starts_with("https://")).map(|w| w.trim_end_matches(['.', ':', '!', '?']).to_owned()));
    if let Some((url, service)) = urls.iter().find_map(|u| service_of(u).map(|s| (u.clone(), s))) {
        let note = if sender.is_empty() { url.clone() } else { format!("{sender}\n{url}") };
        return json!({"kind": "meeting", "title": subject, "start": "", "service": service, "url": url, "note": note});
    }
    Value::Null
}

/// The JSON `fili-cal --new` takes for a meeting found by its link: {title, place, note, start}
pub fn proposal(event: &Value) -> String {
    json!({"title": event["title"], "place": event["url"], "note": event["note"], "start": event["start"]}).to_string()
}

struct Fields {
    summary: Option<String>,
    start: Option<String>,
}

/// Content lines unfolded (RFC 5545 §3.1: a line that starts with a space or a tab continues the one before)
fn unfold(ics: &str) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    for raw in ics.split('\n') {
        let line = raw.strip_suffix('\r').unwrap_or(raw);
        if let Some(rest) = line.strip_prefix([' ', '\t'])
            && let Some(last) = lines.last_mut()
        {
            last.push_str(rest);
        } else {
            lines.push(line.to_owned());
        }
    }
    lines
}

/// The value of a property outside or inside the first event: `NAME;PARAMS:value`
fn property(ics: &str, name: &str) -> Option<String> {
    unfold(ics).into_iter().find_map(|l| value_of(&l, name))
}

fn value_of(line: &str, name: &str) -> Option<String> {
    let (head, value) = line.split_once(':')?;
    let key = head.split(';').next()?;
    key.eq_ignore_ascii_case(name).then(|| value.trim().to_owned())
}

fn unescape(s: &str) -> String {
    s.replace("\\n", " ").replace("\\N", " ").replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\")
}

/// The title and the start of the first VEVENT; the start as Agenda reads it: "YYYY-MM-DD" (whole day) or
/// "YYYY-MM-DDTHH:MM" in local time (a UTC time is converted; a time with a TZID is shown as written)
fn vevent(ics: &str) -> Fields {
    let mut inside = false;
    let mut out = Fields { summary: None, start: None };
    for line in unfold(ics) {
        if line.eq_ignore_ascii_case("BEGIN:VEVENT") {
            inside = true;
        } else if line.eq_ignore_ascii_case("END:VEVENT") {
            break;
        } else if inside {
            if out.summary.is_none()
                && let Some(v) = value_of(&line, "SUMMARY")
            {
                out.summary = Some(unescape(&v)).filter(|s| !s.trim().is_empty());
            }
            if out.start.is_none()
                && let Some(v) = value_of(&line, "DTSTART")
            {
                out.start = start(&v);
            }
        }
    }
    out
}

fn start(v: &str) -> Option<String> {
    let d = v.get(..8).filter(|d| d.chars().all(|c| c.is_ascii_digit()))?;
    let date = format!("{}-{}-{}", &d[..4], &d[4..6], &d[6..8]);
    let Some(t) = v.get(9..13).filter(|t| v.as_bytes().get(8) == Some(&b'T') && t.chars().all(|c| c.is_ascii_digit())) else {
        return Some(date);
    };
    if v.ends_with('Z') {
        let utc = chrono::NaiveDateTime::parse_from_str(&format!("{date} {t}"), "%Y-%m-%d %H%M").ok()?.and_utc();
        return Some(utc.with_timezone(&chrono::Local).format("%Y-%m-%dT%H:%M").to_string());
    }
    Some(format!("{date}T{}:{}", &t[..2], &t[2..]))
}

/// The service of a video conference link (the same hosts as Agenda's join.rs), None for any other link
fn service_of(url: &str) -> Option<&'static str> {
    let rest = url.split_once("://")?.1;
    let host = rest.split(['/', '?', '#']).next()?.split(':').next()?.to_lowercase();
    let path = rest[rest.find('/').unwrap_or(rest.len())..].to_lowercase();
    let has = |parts: &[&str]| parts.iter().any(|p| path.contains(p));
    let is = |d: &str| host == d || host.ends_with(&format!(".{d}"));
    Some(if is("teams.microsoft.com") || is("teams.live.com") || is("teams.microsoft.us") {
        if !has(&["/l/meetup-join/", "/meet/"]) {
            return None;
        }
        "Teams"
    } else if is("meet.google.com") {
        if path.len() < 4 {
            return None;
        }
        "Meet"
    } else if is("zoom.us") || is("zoomgov.com") || is("zoom.com") {
        if !has(&["/j/", "/my/", "/wc/join/", "/s/"]) {
            return None;
        }
        "Zoom"
    } else if is("webex.com") {
        if !has(&["/meet/", "/join", "/j.php", "mtid="]) {
            return None;
        }
        "Webex"
    } else if is("whereby.com") {
        "Whereby"
    } else if is("meet.jit.si") {
        "Jitsi"
    } else if is("gotomeet.me") || is("gotomeeting.com") {
        "GoTo"
    } else if is("meet.proton.me") {
        "Proton Meet"
    } else {
        return None;
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const INVITE: &str = "BEGIN:VCALENDAR\r\nMETHOD:REQUEST\r\nBEGIN:VEVENT\r\nSUMMARY:Point\r\n  projet\r\nDTSTART;TZID=Europe/Paris:20261203T143000\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";

    #[test]
    fn invitation_gives_title_start_and_text() {
        let m = json!({"summary": {"subject": "Invitation: Point projet"}, "calendar": INVITE});
        let e = detect(&m);
        assert_eq!(e["kind"], "invite");
        assert_eq!(e["title"], "Point projet");
        assert_eq!(e["start"], "2026-12-03T14:30");
        assert_eq!(e["invite"], true);
        assert_eq!(e["ics"], INVITE);
    }

    #[test]
    fn cancellation_offers_nothing() {
        let m = json!({"summary": {"subject": "Cancelled"}, "calendar": INVITE.replace("REQUEST", "CANCEL")});
        assert!(detect(&m).is_null());
    }

    #[test]
    fn whole_day_start() {
        assert_eq!(start("20261224").as_deref(), Some("2026-12-24"));
        assert_eq!(start("garbage"), None);
    }

    #[test]
    fn attached_ics_file() {
        let m = json!({"summary": {"subject": "Dîner"}, "nativeContent": {"attachments": [{"filename": "invite.ics", "mimeType": "application/octet-stream", "attachmentId": "a1"}]}});
        let e = detect(&m);
        assert_eq!(e["kind"], "file");
        assert_eq!(e["attachmentId"], "a1");
    }

    #[test]
    fn meeting_link_in_text_or_links() {
        let m = json!({"summary": {"subject": "Visio jeudi", "from": {"display": "Alice"}}, "nativeContent": {"body": {"text": "On se voit ici: https://meet.google.com/abc-defg-hij."}}});
        let e = detect(&m);
        assert_eq!(e["kind"], "meeting");
        assert_eq!(e["service"], "Meet");
        assert_eq!(e["url"], "https://meet.google.com/abc-defg-hij");
        let p: Value = serde_json::from_str(&proposal(&e)).unwrap();
        assert_eq!(p["title"], "Visio jeudi");
        assert_eq!(p["place"], "https://meet.google.com/abc-defg-hij");
        assert_eq!(p["note"], "Alice\nhttps://meet.google.com/abc-defg-hij");
        let m = json!({"summary": {"subject": "Call"}, "links": [{"url": "https://teams.microsoft.com/l/meetup-join/19%3a"}]});
        assert_eq!(detect(&m)["service"], "Teams");
    }

    #[test]
    fn ordinary_links_offer_nothing() {
        let m = json!({"summary": {"subject": "News"}, "links": [{"url": "https://zoom.us/pricing"}, {"url": "https://meet.google.com/"}], "nativeContent": {"body": {"text": "https://example.com"}}});
        assert!(detect(&m).is_null());
    }
}
