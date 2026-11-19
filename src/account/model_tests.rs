use super::*;

fn row(id: &str, date: i64) -> Value {
    json!({"id":id,"date":format!("2026-09-12T10:{date:02}:00.000Z"),"subject":"subject","labelIds":["INBOX","UNREAD"],"unread":true,"inInbox":true})
}

#[test]
fn refused_capability_is_side_effect_free_and_quiet_read_stays_open() {
    let r = row("a", 1);
    let refused=apply(&json!({"operation":"action","action":"archive","capabilities":{"archive":false},"messages":[r],"messageId":"a"})).unwrap();
    assert_eq!(refused, json!({"refused":true,"capability":"archive"}));
    let result=apply(&json!({"operation":"action","action":"markRead","messages":[r],"messageId":"a","selectedId":"a","quiet":true,"mailboxKey":"unread"})).unwrap();
    assert_eq!(result["removed"], false);
    assert_eq!(result["messages"][0]["unread"], false);
}

#[test]
fn detail_fallback_recomputes_subject_direction_from_preserved_subject() {
    let merged = apply(&json!({"operation":"detailSummary","args":[
        {"subject":"Re: مرحبا","subjectDirection":"rtl"},
        {"subject":"(no subject)","subjectDirection":"ltr"}
    ]}))
    .unwrap();
    assert_eq!(merged["subject"], "Re: مرحبا");
    assert_eq!(merged["subjectDirection"], "rtl");
}

#[test]
fn unified_rejects_identifier_amplification_before_composition() {
    let source = json!({"id":"a".repeat(8192),"messages":[{"id":"one","thread":{"memberIds":vec!["x";3000]}}]});
    assert_eq!(
        super::super::unified::apply(&json!({"sources":[source]})),
        Err("model_output_too_large")
    );
}

#[test]
fn malformed_account_identifier_cannot_collide_with_another_source() {
    for account in [json!("a\u{1f}b"), json!("a\n"), json!("a\0"), json!(123)] {
        let sources = json!([{ "id":account,"messages":[{"id":"c"}] },
          {"id":"a","messages":[{"id":"b\u{1f}c"}]}]);
        assert_eq!(
            super::super::unified::apply(&json!({"sources":sources})),
            Err("model_account_invalid")
        );
    }
}

#[test]
fn declarative_rebase_rejects_snapshot_amplification_before_replay() {
    let mut entries = vec![json!({"token":0,"before":{"id":"x","snippet":"a".repeat(1024*1024)}})];
    entries.extend((1..64).map(|n| json!({"token":n,"apply":{"action":"star"}})));
    assert_eq!(
        apply(&json!({"operation":"rebaseIntents","args":[entries,0]})),
        Err("model_output_too_large")
    );
}

#[test]
fn repeated_authoritative_ids_cannot_amplify_one_cached_summary() {
    let args = json!([[],[{"id":"x","snippet":"a".repeat(512*1024)}],[],vec!["x";1000],false]);
    for operation in ["settledSearchResults", "searchFinish"] {
        assert_eq!(
            apply(&json!({"operation":operation,"args":args})),
            Err("model_output_too_large")
        );
    }
}
