//! Safe rich text for the window: the sanitized document tree of `nativeRender` (no attributes, no scripts,
//! no images) becomes the small HTML subset that Qt's rich text shows. Link targets come only from the
//! engine's vetted link list (http, https, mailto), matched by their text.
use serde_json::Value;

const MAX_OUT: usize = 512 * 1024;

fn escape(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

fn plain(node: &Value, out: &mut String) {
    match node["type"].as_str() {
        Some("text") => out.push_str(&super::html::decode_entities(node["text"].as_str().unwrap_or(""))),
        _ => node["children"].as_array().into_iter().flatten().for_each(|c| plain(c, out)),
    }
}

fn collapse(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut space = false;
    for c in s.chars() {
        if c.is_whitespace() {
            space = true;
        } else {
            if space {
                out.push(' ');
            }
            space = false;
            out.push(c);
        }
    }
    if space {
        out.push(' ');
    }
    out
}

/// Presentation of an element, read from its attributes and its inline style (each value validated).
#[derive(Default)]
struct Look {
    color: Option<String>,
    background: Option<String>,
    align: Option<&'static str>,
    bold: bool,
    italic: bool,
    underline: bool,
}

fn colour(value: &str) -> Option<String> {
    let v = value.trim().to_ascii_lowercase();
    let hex = v.strip_prefix('#').is_some_and(|h| matches!(h.len(), 3 | 6) && h.bytes().all(|b| b.is_ascii_hexdigit()));
    let named = !v.is_empty() && v.len() <= 20 && v.bytes().all(|b| b.is_ascii_lowercase()) && !matches!(v.as_str(), "transparent" | "inherit" | "initial" | "currentcolor");
    let rgb = v.starts_with("rgb(") && v.ends_with(')') && v.bytes().all(|b| b.is_ascii_digit() || b" (),rgb.%".contains(&b));
    (hex || named || rgb).then_some(v)
}

fn attr<'a>(node: &'a Value, name: &str) -> &'a str {
    node["attrs"]
        .as_array()
        .into_iter()
        .flatten()
        .find(|a| a["name"] == name)
        .and_then(|a| a["value"].as_str())
        .unwrap_or("")
}

fn look(node: &Value) -> Look {
    let mut l = Look { color: colour(attr(node, "color")), background: colour(attr(node, "bgcolor")), ..Look::default() };
    let aligned = |v: &str| match v.trim().to_ascii_lowercase().as_str() {
        "left" => Some("left"),
        "right" => Some("right"),
        "center" => Some("center"),
        "justify" => Some("justify"),
        _ => None,
    };
    l.align = aligned(attr(node, "align"));
    for declaration in attr(node, "style").split(';') {
        let Some((key, value)) = declaration.split_once(':') else { continue };
        let value = value.trim();
        match key.trim().to_ascii_lowercase().as_str() {
            "color" => l.color = colour(value).or(l.color),
            "background-color" | "background" => l.background = colour(value).or(l.background),
            "text-align" => l.align = aligned(value).or(l.align),
            "font-weight" => l.bold = value == "bold" || value.parse::<u32>().is_ok_and(|w| w >= 600),
            "font-style" => l.italic = value == "italic",
            "text-decoration" => l.underline = value.contains("underline"),
            _ => {}
        }
    }
    l
}

/// Widest picture, in pixels, drawn in the reader
const MAX_WIDTH: u32 = 560;

/// Picture store: data: URI to (file url, width, height).
pub type Store<'a> = &'a dyn Fn(&str) -> Option<(String, u32, u32)>;

struct Writer<'a> {
    store: Store<'a>,
    links: &'a [Value],
    used: Vec<bool>,
    out_len: usize,
}

impl Writer<'_> {
    /// Rich text of a node; empty when the node shows nothing.
    fn node(&mut self, node: &Value, pre: bool) -> String {
        if self.out_len > MAX_OUT {
            return String::new();
        }
        let kind = node["type"].as_str().unwrap_or("");
        if kind == "text" {
            let text = super::html::decode_entities(node["text"].as_str().unwrap_or(""));
            let text = if pre { text } else { collapse(&text) };
            self.out_len += text.len();
            return escape(&text).replace('\n', "<br>");
        }
        let name = node["name"].as_str().unwrap_or("").to_ascii_lowercase();
        if name == "img" {
            return self.picture(node);
        }
        if matches!(name.as_str(), "head" | "script" | "style" | "title" | "meta" | "link" | "svg" | "object" | "iframe") {
            return String::new();
        }
        if name == "br" {
            return "<br>".into();
        }
        if name == "hr" {
            return "<hr>".into();
        }
        let pre_children = pre || name == "pre";
        let anchor = (name == "a").then(|| {
            let mut text = String::new();
            plain(node, &mut text);
            self.link(collapse(&text).trim())
        });
        let mut inner = String::new();
        for child in node["children"].as_array().into_iter().flatten() {
            inner.push_str(&self.node(child, pre_children));
        }
        let shown = !inner.replace("<br>", "").replace("<hr>", "").trim().is_empty()
            || inner.contains("<img");
        let look = look(node);
        if shown && name != "a" {
            let mut style = String::new();
            if let Some(c) = &look.color {
                style += &format!("color:{c};");
            }
            if let Some(c) = &look.background {
                style += &format!("background-color:{c};");
            }
            if !style.is_empty() {
                inner = format!("<span style=\"{style}\">{inner}</span>");
            }
            if look.bold {
                inner = format!("<b>{inner}</b>");
            }
            if look.italic {
                inner = format!("<i>{inner}</i>");
            }
            if look.underline {
                inner = format!("<u>{inner}</u>");
            }
        }
        let block = matches!(
            name.as_str(),
            "p" | "div" | "section" | "article" | "header" | "footer" | "tr" | "table" | "center" | "td" | "th" | "h1" | "h2" | "h3" | "h4" | "h5" | "h6" | "li" | "blockquote"
        );
        if shown && block && let Some(align) = look.align {
            inner = format!("<div align=\"{align}\">{inner}</div>");
        }
        let wrap = |tag: &str, inner: &str| format!("<{tag}>{inner}</{tag}>");
        match name.as_str() {
            "a" => match anchor.flatten() {
                Some(url) if shown => format!("<a href=\"{}\">{inner}</a>", escape(&url).replace('"', "&quot;")),
                _ => inner,
            },
            "b" | "strong" if shown => wrap("b", &inner),
            "i" | "em" | "cite" if shown => wrap("i", &inner),
            "u" | "ins" if shown => wrap("u", &inner),
            "s" | "strike" | "del" if shown => wrap("s", &inner),
            "code" | "tt" | "kbd" | "samp" if shown => wrap("code", &inner),
            "sub" | "sup" if shown => wrap(&name, &inner),
            "h1" | "h2" | "h3" | "h4" | "h5" | "h6" if shown => wrap(&name, &inner),
            "p" | "ul" | "ol" | "li" | "blockquote" | "pre" if shown => wrap(&name, &inner),
            "div" | "section" | "article" | "header" | "footer" | "tr" | "table" | "center" | "address" | "figure" | "main" | "aside" | "nav"
                if shown =>
            {
                format!("{inner}<br>")
            }
            "td" | "th" if shown => format!("{inner} "),
            _ => inner,
        }
    }

    /// A picture: only a stored data: image is drawn (remote ones arrive as data once the reader allowed them).
    fn picture(&mut self, node: &Value) -> String {
        let Some((url, w, h)) = (self.store)(attr(node, "src")) else { return String::new() };
        let wanted = attr(node, "width").trim_end_matches("px").parse::<u32>().ok().filter(|w| *w > 0).unwrap_or(w);
        let width = wanted.min(MAX_WIDTH);
        let height = (u64::from(h) * u64::from(width) / u64::from(w.max(1))).max(1);
        format!("<img src=\"{}\" width=\"{width}\" height=\"{height}\">", escape(&url).replace('"', "&quot;"))
    }

    /// First unused vetted link whose text is `text`.
    fn link(&mut self, text: &str) -> Option<String> {
        let i = self
            .links
            .iter()
            .enumerate()
            .position(|(i, l)| !self.used[i] && l["text"].as_str().is_some_and(|t| collapse(t).trim() == text))?;
        self.used[i] = true;
        let url = self.links[i]["url"].as_str()?;
        let lower = url.trim_start().to_ascii_lowercase();
        (lower.starts_with("https://") || lower.starts_with("http://") || lower.starts_with("mailto:")).then(|| url.trim().to_owned())
    }
}

/// Rich text of a message: `render` is `nativeRender`, `links` the vetted link list of the message.
/// Empty when the document shows nothing.
pub fn rich_text(render: &Value, links: &Value, store: Store<'_>) -> String {
    let links = links.as_array().map_or(&[][..], Vec::as_slice);
    let mut writer = Writer { store, links, used: vec![false; links.len()], out_len: 0 };
    let mut html = writer.node(&render["document"], false);
    // Runs of line breaks (empty layout cells) shrink to one blank line
    while html.contains("<br><br><br>") {
        html = html.replace("<br><br><br>", "<br><br>");
    }
    let html = html.trim_start_matches(|c: char| c == ' ').trim_start_matches("<br>").to_owned();
    if html.replace("<br>", "").trim().is_empty() { String::new() } else { html }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn el(name: &str, children: Vec<Value>) -> Value {
        json!({"type":"element","name":name,"attrs":[],"selfClosing":false,"children":children})
    }
    fn tx(t: &str) -> Value {
        json!({"type":"text","text":t})
    }

    #[test]
    fn keeps_basic_formatting_and_decodes_entities() {
        let doc = json!({"document": {"type":"root","children":[el("p",vec![tx("It&#39;s "),el("strong",vec![tx("bold")])])]}});
        assert_eq!(rich_text(&doc, &json!([]), &|_| None), "<p>It's <b>bold</b></p>");
    }

    #[test]
    fn drops_scripts_styles_and_head() {
        let doc = json!({"document": {"type":"root","children":[el("head",vec![el("style",vec![tx("p{}")])]),el("script",vec![tx("alert(1)")]),el("p",vec![tx("ok")])]}});
        assert_eq!(rich_text(&doc, &json!([]), &|_| None), "<p>ok</p>");
    }

    #[test]
    fn markup_in_text_is_escaped() {
        let doc = json!({"document": {"type":"root","children":[el("p",vec![tx("&lt;img src=x onerror=1&gt; &amp; <b>")])]}});
        let out = rich_text(&doc, &json!([]), &|_| None);
        assert!(!out.contains("<img") && !out.contains("<b>"), "{out}");
        assert!(out.contains("&lt;img") && out.contains("&amp;"), "{out}");
    }

    #[test]
    fn links_use_only_the_vetted_list() {
        let doc = json!({"document": {"type":"root","children":[
            el("p",vec![el("a",vec![tx("Open")]),tx(" "),el("a",vec![tx("Evil")])])]}});
        let links = json!([{"text":"Open","url":"https://example.org/a?x=1&y=2"},{"text":"Evil","url":"javascript:alert(1)"}]);
        let out = rich_text(&doc, &links, &|_| None);
        assert!(out.contains("<a href=\"https://example.org/a?x=1&amp;y=2\">Open</a>"), "{out}");
        assert!(!out.contains("javascript"), "{out}");
        assert!(out.contains("Evil"), "{out}");
    }

    #[test]
    fn colors_and_alignment_are_validated() {
        let mut p = el("p", vec![tx("hi")]);
        p["attrs"] = json!([{"name":"style","value":"color:#ff0000; text-align:center; background-color:expression(alert(1))"}]);
        let out = rich_text(&json!({"document": {"type":"root","children":[p]}}), &json!([]), &|_| None);
        assert!(out.contains("color:#ff0000;") && out.contains("align=\"center\""), "{out}");
        assert!(!out.contains("expression"), "{out}");
    }

    #[test]
    fn pictures_come_from_the_store_and_are_scaled() {
        let mut img = el("img", vec![]);
        img["attrs"] = json!([{"name":"src","value":"data:image/png;base64,AAAA"},{"name":"width","value":"1200"}]);
        let doc = json!({"document": {"type":"root","children":[el("p",vec![img])]}});
        let out = rich_text(&doc, &json!([]), &|_| Some(("file:///c/a.png".into(), 1200, 600)));
        assert!(out.contains("<img src=\"file:///c/a.png\" width=\"560\" height=\"280\">"), "{out}");
        // Not a stored picture: nothing is drawn
        assert_eq!(rich_text(&doc, &json!([]), &|_| None), "");
    }

    #[test]
    fn empty_document_gives_nothing() {
        let doc = json!({"document": {"type":"root","children":[el("div",vec![tx("  ")])]}});
        assert_eq!(rich_text(&doc, &json!([]), &|_| None), "");
    }
}
