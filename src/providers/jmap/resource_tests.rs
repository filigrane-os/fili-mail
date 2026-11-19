use super::*;


fn email() -> Value {
    json!({"id":" e1 ","threadId":"thread","receivedAt":"2026-09-11T09:10:11.123Z","size":501,
      "subject":" Hello ","preview":"<3 & >", "from":[{"email":"ada@example.org","name":"Ada, A."},{"email":"雪@example.org","name":"雪"}],
      "to":[{"email":"to@example.org"}],"cc":[],"messageId":["id@example.org","<wrapped>"],"references":["old"],
      "header:Date":" Fri, 11 Sep 2026 09:10:11 +0000", "header:List-Unsubscribe:asRaw":" <https://example.org/remove>",
      "headers":[{"name":"Subject","value":"wrong subject"},{"name":"Reply-To","value":" reply@example.org"},{"name":"","value":"ignored"}],
      "keywords":{"$flagged":true,"$draft":false},"mailboxIds":{"in":true,"sent":true,"trash":false},
      "bodyStructure":{"partId":"root","type":"multipart/mixed","subParts":[
        {"partId":"text","type":"text/plain","charset":"iso-8859-1","blobId":"textBlob","size":999},
        {"partId":"file","type":"text/plain","charset":"windows-1252","name":"notes.txt","blobId":"fileBlob","size":19,"cid":"cid","headers":[{"name":"Content-ID","value":" <cid>"}]}]},
      "bodyValues":{"text":{"value":"Hi 雪\nsecond","isTruncated":true,"isEncodingProblem":true}}})
}
#[test]
fn refuses_duplicate_body_value_amplification_before_building_mime() {
    let leaves = vec![json!({"partId":"same","type":"text/plain"}); 512];
    let email = json!({"bodyStructure":{"type":"multipart/mixed","subParts":leaves},"bodyValues":{"same":{"value":"x".repeat(65536)}}});
    assert!(serde_json::to_vec(&email).unwrap().len() < 100_000);
    // Were construction allowed, the same small source would emit over44MiB
    // of base64 strings. Reject from sizes alone before encoding any of them.
    assert_eq!(
        validate_budget(&email, true),
        Err("jmap_response_too_large")
    );
    assert_eq!(validate_budget(&email, false), Ok(()));
    let numeric = json!({"bodyStructure":{"type":"text/plain","partId":1},"bodyValues":{"1":{"value":"x".repeat(25*1024*1024)}}});
    assert_eq!(
        validate_budget(&numeric, true),
        Err("jmap_response_too_large")
    );
}

#[test]
fn bounds_nodes_and_structural_expansion_but_allows_realistic_bodies() {
    let many = json!({"bodyStructure":{"type":"multipart/mixed","subParts":vec![json!({});4096]}});
    assert_eq!(validate_budget(&many, true), Err("jmap_response_too_large"));
    let large = json!({"bodyStructure":{"partId":"text","type":"text/plain"},"bodyValues":{"text":{"value":"x".repeat(12*1024*1024)}}});
    assert_eq!(validate_budget(&large, true), Ok(()));
    let preview = json!({"preview":"&".repeat(6*1024*1024)});
    assert_eq!(
        validate_budget(&preview, false),
        Err("jmap_response_too_large")
    );
    assert_eq!(validate_budget(&email(), true), Ok(()));
}
