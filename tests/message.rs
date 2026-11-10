use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use serde_json::json;

#[test]
fn dispatch_uses_shared_parser_and_validates_parameters() {
    let raw = b"Subject: hello\r\n\r\nbody";
    let parsed = fili_mail::message::parse(raw).unwrap();
    let via_rpc =
        fili_mail::backend::dispatch("message.parse", &json!({"raw":URL_SAFE_NO_PAD.encode(raw)}))
            .unwrap();
    assert_eq!(parsed, via_rpc);
    assert_eq!(
        fili_mail::backend::dispatch("message.parse", &json!({"raw":"%%%"})),
        Err("invalid_message_encoding")
    );
    assert_eq!(
        fili_mail::backend::dispatch("message.parse", &json!({"raw":"","extra":true})),
        Err("invalid_params")
    );
}
